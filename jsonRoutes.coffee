import Fiber from 'fibers'
import connect from 'connect'
import connectRoute from 'connect-route'
import pluralize from 'pluralize'
import _ from 'lodash'
import { Meteor } from 'meteor/meteor'
import bodyParser from 'body-parser'
import qs from 'qs'
import parseUrl from "parse-url"
import { T9n } from 'meteor-accounts-t9n'

setHeaders = (res, headers) ->
  _.each headers, (value, key) ->
    res.setHeader key, value
    return
  return

writeJsonToBody = (res, json) ->
  if json != undefined
    shouldPrettyPrint = process.env.NODE_ENV == 'development'
    spacer = if shouldPrettyPrint then 2 else null
    res.setHeader 'Content-type', 'application/json'
    res.write JSON.stringify(json, null, spacer)
  return

JsonRoutes = {}

JsonRoutes.errors =
  invalidTokenError: (req, res, next) ->
    error = new Meteor.Error("authenticationFailure", T9n.get('errors.authenticationFailure'))
    error.statusCode = Meteor.ERROR_CODES.authenticationFailure
    throw error

  badRequestError: (req, res, next) ->
    error = new Meteor.Error("badRequest", T9n.get('errors.badRequest'))
    error.statusCode = Meteor.ERROR_CODES.badRequest
    throw error

  recordNotFoundError: (req, res, next) ->
    error = new Meteor.Error("recordNotFound", T9n.get('errors.recordNotFound'))
    error.statusCode = Meteor.ERROR_CODES.recordNotFound
    throw error

urlEncodedMiddleware = bodyParser.urlencoded({ extended: true })
jsonMiddleware = bodyParser.json()
queryMiddleware = (req, res, next) ->
  if (!req.query)
    if ~req.url.indexOf('?')
      req.query = qs.parse(parseurl(req).query, { allowDots: false, allowPrototypes: true })
    else
      req.query = {}
  next()

composeWithMiddlewares = (callback) ->
  (req, res, next) ->
    # only execute custom middlewares at API routes
    # required to avoid conflict with `ostrio:files`
    urlEncodedMiddleware req, res, ->
      jsonMiddleware req, res, ->
        queryMiddleware req, res, ->
          callback req, res, next
          return
        return
      return
    return

WebApp.connectHandlers.use queryMiddleware
# Handler for adding middleware before an endpoint (JsonRoutes.middleWare
# is just for legacy reasons). Also serves as a namespace for middleware
# packages to declare their middleware functions.
JsonRoutes.Middleware = JsonRoutes.middleWare = connect()
WebApp.connectHandlers.use(JsonRoutes.Middleware)
# List of all defined JSON API endpoints
JsonRoutes.routes = []
# Save reference to router for later
connectRouter = undefined

# Register as a middleware
WebApp.connectHandlers.use Meteor.bindEnvironment(connectRoute((router) ->
  connectRouter = router
  return
))

# Error middleware must be added last, to catch errors from prior middleware.
# That's why we cache them and then add after startup.
errorMiddlewares = []

JsonRoutes.ErrorMiddleware = use: ->
  errorMiddlewares.push arguments
  return

Meteor.startup ->
  for errorMiddleware in errorMiddlewares
    errorMiddleware = _.map(errorMiddleware, (maybeFn) ->
      if _.isFunction(maybeFn)
        # A connect error middleware needs exactly 4 arguments because they use fn.length === 4 to
        # decide if something is an error middleware.
        return (a, b, c, d) ->
          Meteor.bindEnvironment(maybeFn) a, b, c, d
          return

      maybeFn
    )
    WebApp.connectHandlers.use.apply WebApp.connectHandlers, errorMiddleware
    return
  errorMiddlewares = []
  return

JsonRoutes.add = (method, path, handler) ->
  # Make sure path starts with a slash
  if path[0] != '/'
    path = '/' + path
  path = Meteor.WEB_API_NAMESPACE + path
  # Add to list of known endpoints
  JsonRoutes.routes.push
    method: method
    path: path
  connectRouter[method.toLowerCase()] path, composeWithMiddlewares((req, res, next) ->
    # Set headers on response
    setHeaders res, responseHeaders
    Fiber(->
      try
        handler req, res, next
      catch error
        next error
      return
    ).run()
    return
  )
  return

###
# Code to add crud routes start here
###

JsonRoutes.getRestActionsToBeAdded = (options = {}) ->
  allRestActions = ['index', 'create', 'show', 'update', 'destroy']
  if options.pickRoutes?.length > 0
    _.intersection(allRestActions, options.pickRoutes)
  else if options.omitRoutes?.length > 0
    _.difference(allRestActions, options.omitRoutes)
  else
    allRestActions

#for collection RestfulRoute it will return restfulRoutes
restFulRouteNameForCollection = (collection) ->
  pluralize(_.camelCase(collection._name))

JsonRoutes.indexRouteObject = (collection) ->
  method: 'get'
  path: '/' + restFulRouteNameForCollection(collection)
  callback: (req, res, next) =>
    #TODO move this in a mixin as a collection pagination helper
    limit = parseInt(req.query.pageSize) || 0
    skip = (limit) * ((parseInt(req.query.pageNumber) || 1) - 1)
    entities = collection.find({enterpriseId: req.headers['enterprise-id']}, {limit: limit, skip: skip}).fetch()
    if entities
      @sendResult res, data: entities
    else
      @errors.badRequestError req, res, next

JsonRoutes.createRouteObject = (collection) ->
  method: 'post'
  path: '/' + restFulRouteNameForCollection(collection)
  callback: (req, res, next) =>
    bodyParams = req.body
    bodyParams.enterpriseId = req.headers['enterprise-id']
    entityId = collection.insert(bodyParams)
    entity = collection.findOne(entityId)
    if entity
      @sendResult res, data: entity
    else
      @errors.badRequestError req, res, next

JsonRoutes.showRouteObject = (collection) ->
  method: 'get'
  path: '/' + restFulRouteNameForCollection(collection) + '/:id'
  callback: (req, res, next) =>
    entity = collection.findOne(req.params.id)
    if entity
      @sendResult res, data: entity
    else
      @errors.recordNotFoundError req, res, next

JsonRoutes.updateRouteObject = (collection) ->
  method: 'put'
  path: '/' + restFulRouteNameForCollection(collection) + '/:id'
  callback: (req, res, next) =>
    bodyParams = req.body
    #TODO add check for acceptable fields
    #added this to prevent user from changing enterprise id of the record.
    bodyParams.enterpriseId = req.headers['enterprise-id']
    entityIsUpdated = collection.update(req.params.id, {$set: req.body})
    if entityIsUpdated
      entity = collection.findOne(req.params.id)
      @sendResult res, data: entity
    else
      @errors.recordNotFoundError req, res, next

JsonRoutes.destroyRouteObject = (collection) ->
  method: 'delete'
  path: '/' + restFulRouteNameForCollection(collection) + '/:id'
  callback: (req, res, next) =>
    if collection.remove(req.params.id)
      @sendResult res, data: 'Record deleted successfully'
    else
      @errors.recordNotFoundError req, res, next

JsonRoutes.addCrudRoute = (crudRouteObject) ->
  @add crudRouteObject.method, crudRouteObject.path, crudRouteObject.callback

JsonRoutes.crudRoutes =
  index:
    add: (collection) -> JsonRoutes.addCrudRoute(JsonRoutes.indexRouteObject(collection))
  create:
    add: (collection) -> JsonRoutes.addCrudRoute(JsonRoutes.createRouteObject(collection))
  show:
    add: (collection) -> JsonRoutes.addCrudRoute(JsonRoutes.showRouteObject(collection))
  update:
    add: (collection) -> JsonRoutes.updateRouteObject(JsonRoutes.showRouteObject(collection))
  destroy:
    add: (collection) -> JsonRoutes.destroyRouteObject(JsonRoutes.showRouteObject(collection))

###*
# Adds crud routes for the passed collection
#
# @param {Object} collection Meteor Collection Object
# @param {Object} [options]
# @param {Array} [options.pickRoutes] any route from this array ['index', 'create', 'show', 'update', 'destroy'] can be picked.
# @param {Object} [options.omitRoutes] opposite of pickActions. pickActions will have precedence over omit routes
# @param {Boolean} [options.pagination] default true. When set true pagination will be added to the index route.
###

JsonRoutes.addCrudRoutesForCollection = (collection, options = {}) ->
  @crudRoutes[actionToBeAdded].add(collection) for actionToBeAdded in @getRestActionsToBeAdded(options)

###
# Code to add crud routes ends here
###


responseHeaders =
  'Cache-Control': 'no-store'
  Pragma: 'no-cache'

JsonRoutes.setResponseHeaders = (headers) ->
  responseHeaders = headers
  return

###*
# Sets the response headers, status code, and body, and ends it.
# The JSON response will be pretty printed if NODE_ENV is `development`.
#
# @param {Object} res Response object
# @param {Object} [options]
# @param {Number} [options.code] HTTP status code. Default is 200.
# @param {Object} [options.headers] Dictionary of headers.
# @param {Object|Array|null|undefined} [options.data] The object to
#   stringify as the response. If `null`, the response will be "null".
#   If `undefined`, there will be no response body.
###

JsonRoutes.sendResult = (res, options) ->
  options = options or {}
  # We've already set global headers on response, but if they
  # pass in more here, we set those.
  if options.headers
    setHeaders res, options.headers
  # Set status code on response
  res.statusCode = options.code or 200
  # Set response body
  writeJsonToBody res, options.data
  # Send the response
  res.end()
  return

module.exports.JsonRoutes = JsonRoutes
