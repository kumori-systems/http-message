slaputils = require 'slaputils'

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
  return new ClientRequest(options, cb)

