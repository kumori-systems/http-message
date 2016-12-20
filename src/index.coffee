slaputils = require 'slaputils'
httpNode = require 'http'

ServerMessage   = require './http-message'
ClientRequest   = require './http-message-client'
Agent           = require './http-message-agent'
IncomingMessage = require './http-message-incoming'
DynChannManager = require('./dynchannel-manager').DynChannManager
getDynChannManager = require('./dynchannel-manager').getDynChannManager

slaputils.setLogger [ServerMessage, ClientRequest, Agent, IncomingMessage, \
                     DynChannManager]

module.exports = ServerMessage
module.exports.ClientRequest = ClientRequest
module.exports.Agent = Agent
module.exports.IncomingMessage = IncomingMessage
module.exports.getDynChannManager = getDynChannManager

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

