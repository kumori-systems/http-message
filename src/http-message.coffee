http = require 'http'
url = require 'url'
extend = require('util')._extend
ip = require 'ip'
q = require 'q'
tcpPortUsed = require 'tcp-port-used'

# Provisional. Ticket461
MIN_INTERNAL_PORT = 8000
MAX_INTERNAL_PORT = 9000

DEFAULT_CHANNEL_TIMEOUT = 3600000 # 1 hour


class ServerMessage extends http.Server

  used_internal_ports: [] # class variable, shared between objects

  constructor: (requestListener) ->
    method = 'ServerMessage.constructor'
    @logger.info "#{method}"
    @dynChannels = {} # Dictionary of dynamic channels, by Sep-iid
    @requests = {} # http requests in process
    @target = null
    @currentTimeout = DEFAULT_CHANNEL_TIMEOUT
    super requestListener


  listen: (@channel, cb) ->
    method = 'ServerMessage.listen'
    @logger.info "#{method} channel=#{@channel.name}"
    @runtime = @channel.runtimeAgent
    @iid = @runtime.config.iid
    @channel.handleRequest = @_handleStaticRequest
    @_getInternalPort(MIN_INTERNAL_PORT, MAX_INTERNAL_PORT)
    .then (internalport) =>
      @logger.info "#{method} internalport=#{internalport}"
      @target = url.parse("http://localhost:#{internalport}")
      super internalport, cb
    .fail (err) ->
      cb err


  close: (cb) ->
    method = 'ServerMessage.close'
    @logger.info "#{method}"
    @channel.handleRequest = null
    super cb


  setTimeout: (msecs, cb) ->
    @currentTimeout = msecs
    @_setChannelTimeout(dyn.request, msecs) for iid, dyn of @dynChannels
    super msecs, cb


  _handleStaticRequest: ([request], [dynRequestChannel]) =>
    method = 'ServerMessage:_handleStaticRequest'
    @logger.debug "#{method} message received"
    return q.promise (resolve, reject) =>
      try
        @logger.debug "#{method} request = #{request.toString()}"
        request = JSON.parse request.toString()
        if request.type is 'getDynChannel'
          if @dynChannels[request.fromInstance]?
            dynReplyChannel = @dynChannels[request.fromInstance].reply
            created = false
          else
            dynReplyChannel = @runtime.createChannel()
            dynReplyChannel.handleRequest = @_handleHttpRequest
            @_setChannelTimeout(dynReplyChannel, @currentTimeout)
            @dynChannels[request.fromInstance] = {
              reply: dynReplyChannel
              request: dynRequestChannel
            }
            created = true
          @logger.debug "#{method} created=#{created} \
                        dynReplyChannel=#{dynReplyChannel.name},\
                        dynRequestChannel=#{dynRequestChannel.name}"
          resolve [[@iid],[dynReplyChannel]]
        else
          throw new Error 'Invalid request type'
      catch e
        @logger.error "#{method} catch error = #{e.message}"
        reject(e)


  _handleHttpRequest: ([message, data]) =>
    method = 'ServerMessage:_handleHttpRequest'
    @logger.debug "#{method} message received"
    return q.promise (resolve, reject) =>
      try
        message = JSON.parse message
        reqId = message.reqId
        switch message.type
          when 'request'
            options = @_getOptionsRequest message.data
            request = http.request options
            @requests[reqId] = request

            request.on 'error', (err) =>
              @logger.warn "#{method} onError #{err.stack}"
              @_processHttpResponseError message, err

            request.on 'response', (response) =>
              if @requests[reqId]?
                # For development debug: special header "instancespath"
                instancespath = options.headers.instancespath
                if instancespath?
                  response.headers.instancespath = instancespath
                @_processHttpResponse response, message
              else
                @logger.warn "#{method} onResponse request #{reqId} \
                              not found"
            resolve [['ACK']]

          when 'data'
            request = @requests[reqId]
            if request? then request.write data, () -> resolve [['ACK']]
            else throw new Error "Request #{reqId} not found"

          when 'end'
            request = @requests[reqId]
            if request? then request.end()
            else throw new Error "Request #{reqId} not found"
            resolve [['ACK']]

          else
            throw new Error "Invalid message type: #{message.type}"

      catch e
        @logger.warn "#{method} catch error = #{e.message}"
        reject(e)


  _processHttpResponseError: (requestMessage, err) ->
    method = 'ServerMessage:_processHttpResponseError'
    @logger.debug "#{method} #{JSON.stringify requestMessage}"

    reqId = requestMessage.reqId
    dynRequestChannel = @dynChannels[requestMessage.fromInstance].request
    if dynRequestChannel?

      responseMessage = _createMessage('error', null, requestMessage)
      @_sendMessage(dynRequestChannel, [JSON.stringify(responseMessage), \
                                        err.message])
      if @requests[reqId]? then delete @requests[reqId]

    else
      @logger.warn "#{method} dynRequestChannel not found for iid = \
                    #{requestMessage.fromInstance}"


  _processHttpResponse: (response, requestMessage) ->
    method = 'ServerMessage:_processHttpResponse'
    @logger.debug "#{method} #{JSON.stringify requestMessage}"

    reqId = requestMessage.reqId
    dynRequestChannel = @dynChannels[requestMessage.fromInstance].request
    if dynRequestChannel?

      responseMessage = _createMessage('response', response, requestMessage)
      @_sendMessage(dynRequestChannel, [JSON.stringify(responseMessage)])

      response.on 'data', (chunk) =>
        responseMessage = _createMessage('data', response, requestMessage)
        @_sendMessage(dynRequestChannel, [JSON.stringify(responseMessage), \
                                          chunk])

      response.on 'end', () =>
        responseMessage = _createMessage('end', response, requestMessage)
        @_sendMessage(dynRequestChannel, [JSON.stringify(responseMessage)])
        if @requests[reqId]? then delete @requests[reqId]

      response.on 'error', (err) =>
        @logger.warn "#{method} onError #{err.stack}"
        if @requests[reqId]? then delete @requests[reqId]

    else
      @logger.warn "#{method} dynRequestChannel not found for iid = \
                    #{requestMessage.fromInstance}"


  _createMessage = (type, response, requestMessage) ->
    message = {
      type: type
      domain: requestMessage.domain
      connKey: requestMessage.connKey
      reqId: requestMessage.reqId
    }
    if type is 'response'
      message.headers = response.headers
      message.statusCode = response.statusCode
    return message


  _sendMessage: (channel, message) ->
    method = 'ServerMessage:_sendMessage'
    channel.sendRequest message
    .fail (err) =>
      @logger.error "#{method} message.type = #{message.type} \
                     err = #{err.stack}"


  _getOptionsRequest: (request) ->
    options = {}
    options.port = @target.port
    if (@target.host != undefined) then options.host = @target.host
    if (@target.hostname != undefined) then options.hostname = @target.hostname
    options.method = request.method
    options.headers = extend({}, request.headers)
    if (options.method is 'DELETE' or \ # Copied r http-proxy
       options.method is 'OPTIONS') and \
       (not options.headers['content-length'])
      options.headers['content-length'] = '0'
    if options.headers.instancespath? # For development debug
      options.headers.instancespath = "#{options.headers.instancespath},\
                                       iid=#{@iid}"
    options.headers['connection'] = 'keep-alive'
    options.path = url.parse(request.url).path
    return options


  _setChannelTimeout: (channel, msecs) ->
    # TODO: código necesario por el ticket#75. Se supone que podría fijar el
    # timeout en cada petición, pero creo que no funciona OK
    cfg = if channel.config? then channel.config else {}
    if cfg.timeout isnt msecs
      cfg.timeout = msecs
      channel.setConfig cfg


  _getInternalPort: (minPort, maxPort) ->
    q()
    .then () =>
      if @used_internal_ports.indexOf(minPort) < 0 then q.resolve()
      else q.reject()
    .then () ->
      tcpPortUsed.check minPort, "127.0.0.1"
    .then (inUse) ->
      if inUse then q.reject new Error()
    .then () =>
      @used_internal_ports.push minPort
      return minPort
    .fail (err) =>
      minPort++
      if minPort <= maxPort
        @_getInternalPort minPort, maxPort
      else
        q.reject new Error 'Internal port not available'


module.exports = ServerMessage
