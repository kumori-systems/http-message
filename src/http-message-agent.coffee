slaputils = require 'slaputils'

# Slap implementation of http.Agent.
# Just used as 'tag' for sticky-instance control in http-message-client
#
class Agent


  constructor: () ->
    if not @logger? # If logger hasn't been injected from outside
      slaputils.setLogger [Agent]
    @name = slaputils.generateId()
    method = 'Agent.constructor'
    @logger.debug "#{method} name=#{@name}"


  destroy: () ->
    # Do nothing ...
    method = 'Agent.destroy'
    @logger.debug "#{method} name=#{@name}"


module.exports = Agent