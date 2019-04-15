import Fiber from 'fibers'
import connect from 'connect'
import connectRoute from 'connect-route'
import _ from 'lodash'
import { Meteor } from 'meteor/meteor'
import bodyParser from 'body-parser'
import qs from 'qs'
import parseUrl from "parse-url"

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
