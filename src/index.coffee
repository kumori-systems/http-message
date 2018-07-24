httpNode = require 'http'

ServerMessage   = require('./http-message').ServerMessage
ClientRequest   = require('./http-message-client').ClientRequest
Agent           = require('./http-message-agent').Agent
IncomingMessage = require('./http-message-incoming').IncomingMessage
getDynChannManager = require('./dynchannel-manager').getDynChannManager

module.exports = ServerMessage
module.exports.ClientRequest = ClientRequest
module.exports.Agent = Agent
module.exports.IncomingMessage = IncomingMessage

# Just for unit tests
module.exports._getDynChannManager = getDynChannManager

module.exports.createServer = (requestListener) ->
  return new ServerMessage(requestListener)

module.exports.request = (options, cb) ->
  # Allows use httpMessage.request() with options.channel or options.host
  # If options.channels is not defined, then returns a node-clientRequest
  # object
  if options.channel?
    return new ClientRequest(options, cb)
  else
    return httpNode.request(options, cb)

