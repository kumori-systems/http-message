kutil = require './util'

# Slap implementation of http.Agent.
# Just used as 'tag' for sticky-instance control in http-message-client
#
class Agent


  constructor: () ->
    @logger ?= kutil.getLogger()
    @name = kutil.generateId()
    method = 'Agent.constructor'
    @logger.debug "#{method} name=#{@name}"


  destroy: () ->
    # Do nothing ...
    method = 'Agent.destroy'
    @logger.debug "#{method} name=#{@name}"


module.exports.Agent = Agent