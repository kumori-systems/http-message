slaputils = require 'slaputils'

# Slap implementation of http.Agent.
# Just used as 'tag' for sticky-instance control in http-message-client
#
class Agent


  constructor: () ->
    @name = slaputils.generateId()
    method = 'Agent.constructor'
    @logger.debug "#{method} name=#{@name}"


  destroy: () ->
    # Do nothing ...
    @logger.debug "#Agent.destroy name=#{@name}"


module.exports = Agent