(function() {
  var debug;

  debug = require('debug');

  exports.getLogger = function() {
    return {
      error: debug('kumori:error'),
      warn: debug('kumori:warn'),
      info: debug('kumori:info'),
      debug: debug('kumori:debug'),
      silly: debug('kumori:silly')
    };
  };

}).call(this);
//# sourceMappingURL=util.js.map