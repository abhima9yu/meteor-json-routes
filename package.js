Package.describe({
  name: 'abhima9yu:json-routes',
  version: '3.0.0',

  // Brief, one-line summary of the package.
  summary: 'The simplest way to define server-side routes that return JSON',

  // URL to the Git repository containing the source code for this package.
  git: 'https://github.com/JSSolutions/meteor-json-routes',

  // By default, Meteor will default to using README.md for documentation.
  // To avoid submitting documentation, set this field to null.
  documentation: 'README.md',
});

//npm dependencies shown below should be installed in the main app
Npm.depends({
  connect: '2.30.2'
  //'connect-route': '0.1.5',
  //'body-parser': '1.18.3',
  //'qs': '6.7.0',
  //'pluralize': '7.0.0',
  //'lodash': '4.17.11'
});

Package.onUse(function (api) {
  api.versionsFrom('1.0');

  api.use([
    'webapp',
    'meteor',
    'coffeescript@2.0.0',
    'ecmascript@0.10.0'
  ], 'server');

  api.addFiles([
    'json-routes.coffee',
    'middleware.coffee',
  ], 'server');

  api.export([
    'JsonRoutes',
    'RestMiddleware',
  ], 'server');
});

Package.onTest(function (api) {
  api.use('tinytest');
  api.use('test-helpers');
  api.use('simple:json-routes');
  api.use('http');
  api.addFiles('json-routes-tests.js');
});
