slaputils = require 'slaputils'

ServerMessage = require('./http-message')

slaputils.setLogger [ServerMessage]
slaputils.setParser [ServerMessage]

module.exports = ServerMessage

module.exports.createServer = (requestListener) ->
  return new ServerMessage(requestListener)