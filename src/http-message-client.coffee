EventEmitter = require('events').EventEmitter
extend = require('util')._extend
DynChannManager = require('./dynchannel-manager').DynChannManager
getDynChannManager = require('./dynchannel-manager').getDynChannManager
IncomingMessage = require('./http-message-incoming').IncomingMessage
Agent = require('./http-message-agent').Agent
q = require 'q'
kutil = require './util'


# Slap implementation of http.ClientRequest
#
# TODO:
# - flow control - Ticket#637
# - Timeout
# - Abort a request
# - Encoding (utf,...) a request
# - Garbage for DynChannManager.agentsMap
# - How use with Restler, etc.?
# - Test when a destination instance dies and agents are reconfigured
#
class ClientRequest extends EventEmitter


  # Constructor.
  # Throws an exception if options values are not valid.
  # Initiates asynchronous operations.
  #
  constructor: (options, @cb) ->
    @logger ?= kutil.getLogger()
    super()
    @_reqId = kutil.generateId()
    method = "ClientRequest.constructor reqId=#{@_reqId}"
    @logger.debug "#{method}"

    # Control over which dyn-channels we must use / are using for this
    # http request (more details: see dynchannel-manager.coffee)
    @_dynChannManager = getDynChannManager()

    # Gets static request channel and agent (optional) from options.
    @_staRequest = @_getStaRequest(options)
    @_agent = @_getAgent(options)

    # Gets dynamic reply channel for this request (shared between all requests)
    @_dynReply = @_dynChannManager.getDynReply(@_staRequest)

    # This flag will be 'true' when request finishes (@end() has been invoked)
    @_endIsSent = false

    # This promise works as a semaphore: doesn't permit send messages before
    # obtain dynamic request channel
    @waitingDynRequest = q.promise (resolve, reject) =>
      # Selects a dynamic request channel for this request
      @_instance = null
      @_dynRequest = null
      @_response = null
      @_responseSource = null
      @_selectDynRequest()
      .then () =>
        @logger.debug "#{method} dynReply=#{@_dynReply.name}, \
                      dynRequest=#{@_dynRequest.name}"
        @_send('request', options)
        resolve()
      .fail (err) =>
        @logger.error "#{method} #{err.stack}"
        @emit 'error', err
        reject err


  # Sends a chunk of the body of request
  #
  write: (chunk, encoding, callback) ->
    @logger.debug "ClientRequest.write reqId=#{@_reqId}"
    @waitingDynRequest
    .then () =>
      if not @_dynRequest? then throw new Error 'DynRequest is null'
      if @_endIsSent then throw new Error 'Write after end'
      @_send('data', chunk, encoding, callback)
    .fail (err) =>
      @emit 'error', err
    return true


  # Finishes sending the request.
  # If 'data' is specified, then is equivalent to write(data) + send()
  # If 'callback' is specified, it will be called when request stream is
  # finished
  #
  end: (chunk, encoding, callback) ->
    @logger.debug "ClientRequest.end reqId=#{@_reqId}"
    @waitingDynRequest
    .then () =>
      if not @_dynRequest? then throw new Error 'DynRequest is null'
      if @_endIsSent then throw new Error 'End after end'
      @_send('end', chunk, encoding, callback)
    .fail (err) =>
      @emit 'error', err
    return true


  # Not implemented functions that will cause an error
  #
  abort: () ->
    str = 'ClientRequest.abort is not implemented'
    @logger.warn str
    throw new Error str
  setTimeout: (msecs, callback) ->
    str = 'ClientRequest.setTimeout is not implemented'
    @logger.warn str
    throw new Error str


  # Not implemented functions that will not cause an error
  #
  flushHeaders: () ->
    @logger.debug 'ClientRequest.flushHeaders is not implemented'
  setNoDelay: () ->
    @logger.debug 'ClientRequest.setNoDelay is not implemented'
  setSocketKeepAlive: () ->
    @logger.debug 'ClientRequest.setSocketKeepAlive is not implemented'


  # A message has been received through dynamic reply.
  # This method is invoked by @_dynChannManager, that manages dynamic reply
  # channel (shared by all ClientRequest instances).
  #
  onDynReply: ([message, data]) ->
    method = "ClientRequest.onDynReply reqId=#{message.reqId} \
              type=#{message.type}"
    @logger.debug "#{method}"
    return q.promise (resolve, reject) =>
      try
        if message.type is 'response'
          @_responseSource = new EventEmitter()
          @_response = new IncomingMessage {
            source: @_responseSource
            originalMessage: message
          }
          if @cb? then @cb(@_response)
          else @emit 'response', @_response
        else
          if not @_response? then throw new Error 'Response not yet received'
          switch message.type
            when 'data'
              @_responseSource.emit 'data', data
            when 'end'
              @_dynChannManager.removeRequest(message.reqId)
              @_responseSource.emit 'end'
            when 'error'
              @_dynChannManager.removeRequest(message.reqId)
              @_responseSource.emit 'error', data
            else
              @logger.warn "#{method} invalid message type"
        resolve([['ACK']])
      catch e
        @logger.warn "#{method} catch error = #{e.message}"
        @_dynChannManager.removeRequest(message.reqId)
        reject(e)


  # Sends the message through dynamic request channel.
  # Parameters data, encoding and callback are the same parameters that
  # nodejs.http.clientRequest.write/end
  #
  # TODO: use 'encoding'! Now is ignored
  #
  _send: (type, data, encoding, callback) ->
    message = {}
    message.type = type
    message.reqId = @_reqId
    message.connKey = null # not used in http-message-client, used in sep.
    message.fromInstance = @_staRequest.runtimeAgent.instance.iid
    message.protocol = 'http'
    message.domain = null # not used in http-message-client, used in sep.
    if type is 'request'
      options = data
      data = null
      message.data = {
        protocol: 'http'
        path: options.path
        method: options.method
        headers: extend({}, options.headers)
      }
    else if type is 'data' or type is 'end'
      message.data = null
      if typeof data is 'function'
        callback = data
        data = null
        encoding = null
      else if typeof encoding is 'function'
        callback = encoding
        encoding = null
    else
      throw new Error "Invalid message type=#{type}"
    (if data?
      @_dynRequest.sendRequest [JSON.stringify(message), data]
    else
      @_dynRequest.sendRequest [JSON.stringify(message)])
    .then () =>
      if callback? then callback()
      if type is 'request' then @_endIsSent = true
    .fail (err) =>
      @logger.error "ClientRequest._send reqId=#{@_reqId} err=#{err.message}"
      @_dynChannManager.removeRequest(@_reqId)
      emit 'error', err


  # Gets static request channel associated with http-request options
  # Throws an exception if it isnt included in options, or it isnt a
  # request channel
  #
  _getStaRequest: (options) ->
    method = "ClientRequest._getStaRequest reqId=#{@_reqId}"
    try
      if not options.channel?
        throw new Error 'options.channel is mandatory'
      if options.channel.constructor.name isnt 'Request'
        throw new Error 'options.channel must be a request channel'
      if not options.channel.runtimeAgent?
        throw new Error 'options.channel has not a runtimeAgent property'
      return options.channel
    catch e
      @logger.error "#{method} #{e.stack}"
      throw e


  # Gets agent associated with http-request options
  # Throws an exception if 'agent' is included in options, but it isnt really
  # an agent object (with a 'name' property)
  #
  _getAgent: (options) ->
    method = "ClientRequest._getAgent reqId=#{@_reqId}"
    try
      if not options.agent? then return null
      if (options.agent.constructor?.name isnt 'Agent') or
         (not options.agent.name?)
        throw new Error 'options.agent must be an Agent'
      return options.agent
    catch e
      @logger.error "#{method} #{e.stack}"
      throw e


  # Finds a dynamic request channel.
  #
  # Cases:
  # [1]: staRequest and agent are provided, and this pair already exists in
  #      @dynChannelManager --> solve using the current dynRequest stored
  # [2]: staRequest and agent are provided, and this pair is 'in process' in
  #      @dynChannelManager --> solve using the current dynRequest stored when
  #      its promise will be solved.
  # [3]: staRequest and agent are provided, but this pair doesnt exists in
  #      @dynChannelManager --> sends dynReply vía LB and retrieve a
  #      a dynRequest to use
  # [4]: only staRequest are provided --> sends dynReply vía LB and
  #      retrieve a dynRequest to use
  #
  _selectDynRequest: () ->
    method = "ClientRequest._selectDynRequest reqId=#{@_reqId} \
              channel=#{@_staRequest.name}, agent=#{@_agent?.name}"
    return q.promise (resolve, reject) =>
      try
        instancePromise = null

        # Case [1]/[2]/[3]
        if @_agent?.name?
          instancePromise = @_dynChannManager.getInstancePromise(@_staRequest, \
                                                                @_agent)
          # Case [1]/[2]
          if instancePromise?
            @logger.debug "#{method} case[1]/[2]"

          # Case [3]
          else
            @logger.debug "#{method} case[3]"
            instancePromise = @_sendGetDynChannel()
            @_dynChannManager.addInstancePromise(@_staRequest, @_agent, \
                                               instancePromise)
        # Case [4]
        else
          @logger.debug "#{method} case[4]"
          instancePromise = @_sendGetDynChannel()

        # Wait instance promise is solved
        instancePromise.then ([instance, dynRequest]) =>
          @_instance = instance
          @_dynRequest = dynRequest
          #@_dynChannManager.addDynChannels(@_staRequest, instance, \
          #                                 @_dynRequest, @_dynReply)
          @_dynChannManager.addRequest @
          @logger.debug "#{method} instance=#{instance}, \
                         dynRequest=#{dynRequest.name}"
          resolve dynRequest
        .fail (err) =>
          @logger.error "#{method} #{err.stack}"
          reject err

      catch e
        @logger.error "#{method} #{e.stack}"
        reject e


  # Sends a 'getDynChannel' message through static request channel (tipically
  # to as instance that has a http-message object).
  # Returns a promise, solved when reply is received.
  #
  _sendGetDynChannel: () ->
    method = "ClientRequest._sendGetDynChannel reqId=#{@_reqId}"
    @logger.debug "#{method}"
    return q.promise (resolve, reject) =>
      request = JSON.stringify {
        type: 'getDynChannel'
        fromInstance: @_staRequest.runtimeAgent.instance.iid
      }
      @_staRequest.sendRequest [request], [@_dynReply]
      .then (value) =>
        @logger.debug "#{method} solved"
        status = value[0][0]
        if status.status is 'OK'
          if value.length > 1 and value[1]?.length > 0
            instance = value[0][1]
            dynRequest = value[1][0]
            resolve([instance, dynRequest])
          else
            throw new Error 'Response doesnt have dynChannel'
        else
          throw new Error "Status=#{JSON.stringify status}"
      .fail (err) =>
        @logger.warn "#{method} #{err.stack}"
        @_dynChannManager.resetInstancePromise(@_staRequest, @_agent)
        reject err


  # This is a method class used to inject a logger to all dependent classes.
  # This method is used by klogger/index.coffee/setLogger
  #
  @_loggerDependencies: () ->
    return [DynChannManager, IncomingMessage, Agent]

module.exports.ClientRequest = ClientRequest
