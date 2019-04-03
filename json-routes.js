/* global JsonRoutes:true */

var Fiber = Npm.require('fibers');
var connect = Npm.require('connect');
var connectRoute = Npm.require('connect-route');

JsonRoutes = {};

var urlEncodedMiddleware = connect.urlencoded();
var jsonMiddleware = connect.json();
var queryMiddleware = connect.query();

var composeWithMiddlewares = function (callback) {
  return function (req, res, next) {
    // only execute custom middlewares at API routes
    // required to avoid conflict with `ostrio:files`
    urlEncodedMiddleware(req, res, function () {
      jsonMiddleware(req, res, function () {
        queryMiddleware(req, res, function () {
          callback(req, res, next);
        });
      });
    });
  }
};

WebApp.connectHandlers.use(connect.query());

// Handler for adding middleware before an endpoint (JsonRoutes.middleWare
// is just for legacy reasons). Also serves as a namespace for middleware
// packages to declare their middleware functions.
JsonRoutes.Middleware = JsonRoutes.middleWare = connect();
WebApp.connectHandlers.use(JsonRoutes.Middleware);

// List of all defined JSON API endpoints
JsonRoutes.routes = [];

// Save reference to router for later
var connectRouter;

// Register as a middleware
WebApp.connectHandlers.use(Meteor.bindEnvironment(connectRoute(function (router) {
  connectRouter = router;
})));

// Error middleware must be added last, to catch errors from prior middleware.
// That's why we cache them and then add after startup.
var errorMiddlewares = [];
JsonRoutes.ErrorMiddleware = {
  use: function () {
    errorMiddlewares.push(arguments);
  },
};

Meteor.startup(function () {
  _.each(errorMiddlewares, function (errorMiddleware) {
    errorMiddleware = _.map(errorMiddleware, function (maybeFn) {
      if (_.isFunction(maybeFn)) {
        // A connect error middleware needs exactly 4 arguments because they use fn.length === 4 to
        // decide if something is an error middleware.
        return function (a, b, c, d) {
          Meteor.bindEnvironment(maybeFn)(a, b, c, d);
        }
      }

      return maybeFn;
    });

    WebApp.connectHandlers.use.apply(WebApp.connectHandlers, errorMiddleware);
  });

  errorMiddlewares = [];
});

JsonRoutes.add = function (method, path, handler) {
  // Make sure path starts with a slash
  if (path[0] !== '/') {
    path = '/' + path;
  }
  console.log('********')
  console.log(Meteor.WEB_API_NAMESPACE)

  path = Meteor.WEB_API_NAMESPACE + path

  // Add to list of known endpoints
  JsonRoutes.routes.push({
    method: method,
    path: path,
  });

  connectRouter[method.toLowerCase()](path, composeWithMiddlewares(function (req, res, next) {
    // Set headers on response
    setHeaders(res, responseHeaders);
    Fiber(function () {
      try {
        handler(req, res, next);
      } catch (error) {
        next(error);
      }
    }).run();
  }));
};

var responseHeaders = {
  'Cache-Control': 'no-store',
  Pragma: 'no-cache',
};

JsonRoutes.setResponseHeaders = function (headers) {
  responseHeaders = headers;
};

/**
 * Sets the response headers, status code, and body, and ends it.
 * The JSON response will be pretty printed if NODE_ENV is `development`.
 *
 * @param {Object} res Response object
 * @param {Object} [options]
 * @param {Number} [options.code] HTTP status code. Default is 200.
 * @param {Object} [options.headers] Dictionary of headers.
 * @param {Object|Array|null|undefined} [options.data] The object to
 *   stringify as the response. If `null`, the response will be "null".
 *   If `undefined`, there will be no response body.
 */
JsonRoutes.sendResult = function (res, options) {
  options = options || {};

  // We've already set global headers on response, but if they
  // pass in more here, we set those.
  if (options.headers) setHeaders(res, options.headers);

  // Set status code on response
  res.statusCode = options.code || 200;

  // Set response body
  writeJsonToBody(res, options.data);

  // Send the response
  res.end();
};

function setHeaders(res, headers) {
  _.each(headers, function (value, key) {
    res.setHeader(key, value);
  });
}

function writeJsonToBody(res, json) {
  if (json !== undefined) {
    var shouldPrettyPrint = (process.env.NODE_ENV === 'development');
    var spacer = shouldPrettyPrint ? 2 : null;
    res.setHeader('Content-type', 'application/json');
    res.write(JSON.stringify(json, null, spacer));
  }
}
