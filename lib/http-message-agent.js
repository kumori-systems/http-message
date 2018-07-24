(function() {
  var Agent, klogger;

  klogger = require('k-logger');

  Agent = (function() {
    function Agent() {
      var method;
      if (this.logger == null) {
        klogger.setLogger([Agent]);
      }
      this.name = klogger.generateId();
      method = 'Agent.constructor';
      this.logger.debug(method + " name=" + this.name);
    }

    Agent.prototype.destroy = function() {
      var method;
      method = 'Agent.destroy';
      return this.logger.debug(method + " name=" + this.name);
    };

    return Agent;

  })();

  module.exports.Agent = Agent;

}).call(this);
//# sourceMappingURL=http-message-agent.js.map