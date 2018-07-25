(function() {
  var BASE, debug, uuid;

  debug = require('debug');

  uuid = require('node-uuid');

  BASE = 'http-message';

  exports.getLogger = function() {
    return {
      error: debug(BASE + ":error"),
      warn: debug(BASE + ":warn"),
      info: debug(BASE + ":info"),
      debug: debug(BASE + ":debug"),
      silly: debug(BASE + ":silly")
    };
  };

  exports.generateId = function() {
    return uuid.v4();
  };

}).call(this);
//# sourceMappingURL=util.js.map