(function() {
  var Agent, ClientRequest, IncomingMessage, ServerMessage, getDynChannManager, httpNode;

  httpNode = require('http');

  ServerMessage = require('./http-message');

  ClientRequest = require('./http-message-client');

  Agent = require('./http-message-agent');

  IncomingMessage = require('./http-message-incoming');

  getDynChannManager = require('./dynchannel-manager').getDynChannManager;

  module.exports = ServerMessage;

  module.exports.ClientRequest = ClientRequest;

  module.exports.Agent = Agent;

  module.exports.IncomingMessage = IncomingMessage;

  module.exports._getDynChannManager = getDynChannManager;

  module.exports.createServer = function(requestListener) {
    return new ServerMessage(requestListener);
  };

  module.exports.request = function(options, cb) {
    if (options.channel != null) {
      return new ClientRequest(options, cb);
    } else {
      return httpNode.request(options, cb);
    }
  };

}).call(this);
//# sourceMappingURL=index.js.map