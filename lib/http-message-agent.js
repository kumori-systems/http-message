(function() {
  var Agent, kutil;

  kutil = require('./util');

  Agent = (function() {
    function Agent() {
      var method;
      if (this.logger == null) {
        this.logger = kutil.getLogger();
      }
      this.name = kutil.generateId();
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