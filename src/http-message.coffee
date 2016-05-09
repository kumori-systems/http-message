http = require 'http'
url = require 'url'
extend = require('util')._extend
ip = require 'ip'
q = require 'q'


INTERNALPORT = 8081
DEFAULT_CHANNEL_TIMEOUT = 3600000 # 1 hour


class ServerMessage extends http.Server


  constructor: (requestListener) ->
    method = 'ServerMessage.constructor'
    @logger.info "#{method}"
    @dynChannels = {} # Dictionary of dynamic channels, by Sep-iid
    @requests = {}
    @target = url.parse("http://localhost:#{INTERNALPORT}")
    @currentTimeout = DEFAULT_CHANNEL_TIMEOUT
    super requestListener


  listen: (@channel, cb) ->
    @logger.info "ServerMessage.listen channel=#{@channel.name}, \
                 internalport=#{INTERNALPORT}"
    @runtime = @channel.runtimeAgent
    @iid = @runtime.config.iid
    @channel.handleRequest = @_handleStaticRequest
    super INTERNALPORT, cb


  close: (cb) ->
    @channel.handleRequest = null
    super cb


  setTimeout: (msecs, cb) ->
    @currentTimeout = msecs
    @_setChannelTimeout(dyn.request, msecs) for iid, dyn of @dynChannels
    super msecs, cb


  _handleStaticRequest: (message) =>
    method = 'ServerMessage:_handleStaticRequest'
    @logger.info "#{method} message received #{message.toString()}"
    return q.promise (resolve, reject) =>
      try
        request = JSON.parse message[0]
        dynRequestChannel = message[1]
        iid = request.from
        if request.type is 'getDynChannel'
          if @dynChannels[request.fromInstance]? # Shoudn't happen!
            @logger.warn "#{method} getDynChannel will be replaced"
          dynReplyChannel = @runtime.createChannel()
          dynReplyChannel.handleRequest = @_handleHttpRequest
          @_setChannelTimeout(dynReplyChannel, @currentTimeout)
          @dynChannels[request.fromInstance] = {
            reply: dynReplyChannel
            request: dynRequestChannel
          }
          @logger.info "#{method} dynReplyChannel=#{dynReplyChannel.name},\
                        dynRequestChannel=#{dynRequestChannel.name}"
          resolve [['ACK'],[dynReplyChannel]]
        else
          throw new Error 'Invalid request type'
      catch e
        @logger.error "#{method} catch error = #{e.message}"
        @emit 'error', e
        reject(e)


  _handleHttpRequest: (message) =>
    method = 'ServerMessage:_handleHttpRequest'
    @logger.debug "#{method} message received"
    return q.promise (resolve, reject) =>
      try
        message = JSON.parse(message[0])
        switch message.type

          when 'request'
            options = @_getOptionsRequest message.data
            request = http.request options
            @requests[message.reqId] = request
            request.on 'error', (err) =>
              @logger.warn "#{method} onError #{err.stack}"
              @emit 'error', err
              if @requests[message.reqId]? delete @requests[message.reqId]
            request.on 'response', (response) =>
              if @requests[message.reqId]?
                instancespath = options.headers.instancespath # debug purposes
                @_onHttpResponse response, message, instancespath
              else
                @logger.warn "#{method}:response request #{message.reqId} not found"

          when 'data'
            request = @requests[message.reqId]
            if request? then request.write message.data
            else throw new Error "Request #{message.reqId} not found"

          when 'end'
            request = @requests[message.reqId]
            if request? then request.end()
            else throw new Error "Request #{message.reqId} not found"

          else
            throw new Error "Invalid message type: #{message.type}"

        resolve [['ACK']]
      catch e
        @logger.warn "#{method} catch error = #{e.message}"
        @emit 'error', e
        reject(e)


  _onHttpResponse: (response, requestMessage, instancespath) ->
    method = 'ServerMessage:_onHttpResponse'
    @logger.debug "#{method}"

    # For development debug: special header "instancespath"
    if instancespath?
      response.headers.instancespath = instancespath

    dynRequestChanel = @dynChannels[requestMessage.fromInstance]
    if dynRequestChannel?
      responseMessage = _createMessage(requestMessage)
      dynRequest.sendRequest JSON.stringify responseMessage
      .then () =>
        slapStatus = value[0][0]
        if slapStatus.status isnt 'OK'
          @logger.error "#{method} status = #{JSON.stringify slapStatus}"
      .fail (err) =>
        @logger.error "#{method} #{err.stack}"
    else
      @logger.warn "#{method} dynRequestChannel not found for iid = \
                    #{requestMessage.fromInstance}"

    ----------------

    response.on 'data', (chunk) ->
      if slapResponseData is null then slapResponseData = []
      slapResponseData.push chunk

    response.on 'end', () ->
      if slapResponseData isnt null
        slapResponseData = Buffer.concat(slapResponseData)
      aux = [JSON.stringify(slapResponse)]
      if slapResponseData? then aux.push slapResponseData
      resolve [aux]
      if @requests[message.reqId]? delete @requests[message.reqId]

    response.on 'error', () =>
      @logger.info textError
      @emit 'error', new Error(textError)


  _createMessage = (requestMessage, data) ->
    type = requestMessage.type
    if type is 'request'
      type = 'response'
      data =
        headers: response.headers
        statusCode: response.statusCode
    return {
      type: type
      domain: domain
      connKey: connKey
      reqId: reqId
      data: data
    }


  _getOptionsRequest: (request) ->
    options = {}
    options.port = @target.port
    if (@target.host != undefined) then options.host = @target.host
    if (@target.hostname != undefined) then options.hostname = @target.hostname
    options.method = request.method
    options.headers = extend({}, request.headers)
    if (options.method is 'DELETE' or \ # Copied from http-proxy
       options.method is 'OPTIONS') and \
       (not options.headers['content-length'])
      options.headers['content-length'] = '0'
    if options.headers.instancespath? # For development debug
      options.headers.instancespath = "#{options.headers.instancespath},\
                                       iid=#{@iid}"
    options.path = url.parse(request.url).path
    return options


  _setChannelTimeout: (channel, msecs) ->
    # TODO: código necesario por el ticket#75. Se supone que podría fijar el
    # timeout en cada petición, pero creo que no funciona OK
    cfg = if channel.config? then channel.config else {}
    if cfg.timeout isnt msecs
      cfg.timeout = msecs
      channel.setConfig cfg


module.exports = ServerMessage
