fs = require 'fs'
http = require 'http'
url = require 'url'
extend = require('util')._extend
q = require 'q'
mkdirp = require 'mkdirp'
debug = require 'debug'
kutil = require './util'

# Just to inject logger
ClientRequest = require('./http-message-client').ClientRequest


UDS_PATH = './sockets'
MAX_UDS = 100
DEFAULT_CHANNEL_TIMEOUT = 60 * 60 * 1000 # 1 hour
REQUEST_GARBAGE_EXPIRE_TIME = 2 * 60 * 60 * 1000   # 2 hour


class ServerMessage extends http.Server

  used_uds: [] # class variable, shared between objects

  constructor: (requestListener) ->
    @logger ?= kutil.getLogger()
    method = 'ServerMessage.constructor'
    @logger.info "#{method}"
    @dynChannels = {} # Dictionary of dynamic channels, by Sep-iid
    @requests = {} # http requests in process, by reqId
    @websockets = {} # websocket connections in process, by original reqId
    @currentTimeout = DEFAULT_CHANNEL_TIMEOUT
    @_startGarbageRequests(REQUEST_GARBAGE_EXPIRE_TIME)
    super requestListener


  listen: (@channel, cb) ->
    method = 'ServerMessage.listen'
    @logger.info "#{method} channel=#{@channel.name}"
    @runtime = @channel.runtimeAgent
    @iid = @runtime.config.iid
    @channel.handleRequest = @_handleStaticRequest
    # When local-stamp, uses a tcp-port instead uds
    @tcpPort = @channel.config?.port
    if @tcpPort
      @logger.info "#{method} using tcp-port #{@tcpPort} (local-stamp)"
      super @tcpPort, cb
    else
      @_getUdsPort()
      .then (socketPath) =>
        @socketPath = socketPath
        @logger.info "#{method} socketPath=#{@socketPath}"
        super @socketPath, cb
      .fail (err) =>
        if cb? then cb err
        @emit 'error', err


  close: (cb) ->
    method = 'ServerMessage.close'
    @logger.info "#{method}"
    @_stopGarbageRequests()
    @channel.handleRequest = null
    super cb


  setTimeout: (msecs, cb) ->
    @currentTimeout = msecs
    @_setChannelTimeout(dyn.request, msecs) for iid, dyn of @dynChannels
    super msecs, cb


  _handleStaticRequest: ([request], [dynRequestChannel]) =>
    method = 'ServerMessage:_handleStaticRequest'
    @logger.debug "#{method}"
    return q.promise (resolve, reject) =>
      try
        @logger.debug "#{method} request = #{request.toString()}"
        request = JSON.parse request.toString()
        if request.type is 'getDynChannel'
          # Check if dynamic channels are already established with the other
          # instance.
          # It is mandatory to check if DynRequestChannel is the same as the one
          # stored in @dynChannels, to take into account the case that the other
          # instance is the same... but a new reincarnation.
          if @dynChannels[request.fromInstance]?.request is dynRequestChannel
            dynReplyChannel = @dynChannels[request.fromInstance].reply
            created = false
          else
            dynReplyChannel = @runtime.createChannel()
            dynReplyChannel.handleRequest = ([message, data]) =>
              message = JSON.parse message
              if message.protocol is 'ws' then @_handleWS [message, data]
              else @_handleHttpRequest [message, data]
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
    reqId = message.reqId
    type = message.type
    method = "ServerMessage:_handleHttpRequest reqId=#{reqId} type=#{type}"
    @logger.debug "#{method}"
    return q.promise (resolve, reject) =>
      try
        switch type

          when 'request'
            options = @_getOptionsRequest message.data
            request = http.request options
            @_addRequest(reqId, request)
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
                @logger.warn "#{method} onResponse request not found"
            resolve [['ACK']]

          when 'data'
            request = @requests[reqId]
            if request?
              request.write data, () -> resolve [['ACK']]
            else
              # Doesnt generate error if request isnt found in @request
              # Maybe, the response already has been generated (ticket656)
              #throw new Error "Request not found"
              resolve [['ACK']]

          when 'aborted'
            request = @requests[reqId]
            if request?
              request.abort()
              resolve [['ACK']]
            else
              # Doesnt generate error if request isnt found in @request
              # Maybe, the response already has been generated (ticket656)
              #throw new Error "Request not found"
              resolve [['ACK']]

          when 'end'
            request = @requests[reqId]
            if request?
              request.end()
              resolve [['ACK']]
            else
              # Doesnt generate error if request isnt found in @request
              # Maybe, the response already has been generated (ticket656)
              #throw new Error "Request not found"
              resolve [['ACK']]

          else
            throw new Error "Invalid message type: #{type}"
      catch e
        @logger.warn "#{method} catch error = #{e.message}"
        reject(e)


  _processHttpResponse: (response, requestMessage) ->
    reqId = requestMessage.reqId
    method = "ServerMessage:_processHttpResponse reqId=#{reqId}"
    @logger.debug "#{method}"

    dynRequestChannel = @dynChannels[requestMessage.fromInstance].request
    if dynRequestChannel?

      responseMessage = @_createHttpMessage('response', response, \
                                            requestMessage)
      @_sendMessage(dynRequestChannel, responseMessage)

      response.on 'data', (chunk) =>
        responseMessage = @_createHttpMessage('data', response, requestMessage)
        @_sendMessage(dynRequestChannel, responseMessage, chunk)

      response.on 'end', () =>
        responseMessage = @_createHttpMessage('end', response, requestMessage)
        @_sendMessage(dynRequestChannel, responseMessage)
        if @requests[reqId]? then @_deleteRequest(reqId)

      response.on 'error', (err) =>
        @logger.warn "#{method} onError #{err.stack}"
        if @requests[reqId]? then @_deleteRequest(reqId)

    else
      @logger.warn "#{method} dynRequestChannel not found for iid = \
                    #{requestMessage.fromInstance}"


  _processHttpResponseError: (requestMessage, err) ->
    method = 'ServerMessage:_processHttpResponseError'
    @logger.debug "#{method} #{JSON.stringify requestMessage}"
    reqId = requestMessage.reqId
    dynRequestChannel = @dynChannels[requestMessage.fromInstance].request
    if dynRequestChannel?
      responseMessage = @_createHttpMessage('error', null, requestMessage)
      @_sendMessage(dynRequestChannel, responseMessage, err.message)
      if @requests[reqId]? then @_deleteRequest(reqId)
    else
      @logger.warn "#{method} dynRequestChannel not found for iid = \
                    #{requestMessage.fromInstance}"


  _handleWS: ([message, data]) =>
    reqId = message.reqId
    method = "ServerMessage:_handleWS reqId=#{reqId} type=#{message?.type}"
    @logger.debug "#{method}"
    return q.promise (resolve, reject) =>
      try
        switch message.type

          when 'upgrade'
            @_processUpgrade message, resolve, reject

          when 'data'
            socket = @websockets[reqId]
            if socket?
              socket.write data, () -> resolve [['ACK']]
            else
              # Doesnt generate error if request isnt found in @request
              # Maybe, the wsconnection already has been closed
              #throw new Error "WS request not foun"
              resolve [['ACK']]

          when 'end'
            socket = @websockets[reqId]
            if socket?
              socket.end()
              resolve [['ACK']]
            else
              # Doesnt generate error if request isnt found in @request
              # Maybe, the wsconnection already has been closed
              #throw new Error "WS request not foun"
              resolve [['ACK']]

          else
            throw new Error "Invalid message type: #{message.type}"
      catch e
        @logger.warn "#{method} catch error = #{e.message}"
        reject(e)


  _processUpgrade: (message, resolve, reject) ->
    reqId = message.reqId
    connKey = message.connKey
    method = "ServerMessage:_processUpgrade reqId=#{reqId}"
    @logger.debug "#{method}"
    dynRequestChannel = @dynChannels[message.fromInstance].request
    if dynRequestChannel?

      options = @_getOptionsRequest message.data
      request = http.request options

      request.on 'error', (err) =>
        @logger.error "#{method} onError #{err.message}"
        responseMessage = @_createWsMessage('upgrade', connKey, reqId, \
                                            err.message)
        @_sendMessage(dynRequestChannel, responseMessage)

      request.on 'response', (response) =>
        err = 'resonse event unexpected'
        @logger.error "#{method} onError #{err}"
        responseMessage = @_createWsMessage('upgrade', connKey, reqId, err)
        @_sendMessage(dynRequestChannel, responseMessage)

      request.on 'upgrade', (response, socket, head) =>
        @logger.debug "#{method} upgrade received"
        responseMessage = @_createWsMessage('upgrade', connKey, reqId)
        ack = @_createWsUpgradeAck(response)
        @_sendMessage(dynRequestChannel, responseMessage, ack)
        @websockets[reqId] = socket
        if @requests[reqId]? then @_deleteRequest(reqId)
        socket.on 'data', (chunk) =>
          message = @_createWsMessage('data', connKey, reqId)
          @_sendMessage(dynRequestChannel, message, chunk)
        socket.on 'close', () =>
          delete @websockets[reqId]
          message = @_createWsMessage('end', connKey, reqId)
          @_sendMessage(dynRequestChannel, message)

      request.end()
      resolve [['ACK']]

    else
      text = "dynRequestChannel not found for iid = \
              #{requestMessage.fromInstance}"
      @logger.warn "#{method} #{text}"
      reject new Error text


  _createHttpMessage: (type, response, requestMessage) ->
    message = {
      protocol: 'http'
      type: type
      domain: requestMessage.domain
      connKey: requestMessage.connKey
      reqId: requestMessage.reqId
    }
    if type is 'response'
      message.data = {}
      message.data.httpVersionMajor = response.httpVersionMajor
      message.data.httpVersionMinor = response.httpVersionMinor
      message.data.httpVersion = response.httpVersion
      message.data.headers = response.headers
      message.data.rawHeaders = response.rawHeaders
      message.data.trailers = response.trailers
      message.data.rawTrailers = response.rawTrailers
      message.data.url = response.url
      message.data.method = response.method
      message.data.statusCode = response.statusCode
      message.data.statusMessage = response.statusMessage
    return message


  _createWsMessage: (type, connKey, reqId, error) ->
    message = {
      protocol: 'ws'
      type: type
      connKey: connKey,
      reqId: reqId
      error: error
    }
    return message


  _createWsUpgradeAck: (response) ->
    ack = ''
    ack = ['HTTP/1.1 101 Switching Protocols']
    ack.push "#{key}: #{value}" for key, value of response.headers
    ack = ack.join '\r\n'
    ack = ack + '\r\n\r\n'
    return ack


  _sendMessage: (channel, message, data) ->
    method = "ServerMessage:_sendMessage reqId=#{message?.reqId} \
              type=#{message?.type}"
    @logger.debug "#{method}"
    aux = [JSON.stringify message]
    if data? then aux.push data
    channel.sendRequest aux
    .fail (err) =>
      @logger.error "#{method} err = #{err.stack}"


  _getOptionsRequest: (request) ->
    options = {}
    # When local-stamp, uses a tcp-port instead uds
    if @tcpPort? then options.port = @tcpPort
    else options.socketPath = @socketPath
    options.host = 'localhost'
    options.method = request.method
    options.headers = extend({}, request.headers)
    if (options.method is 'DELETE' or \ # Copied r http-proxy
       options.method is 'OPTIONS') and \
       (not options.headers['content-length'])
      options.headers['content-length'] = '0'
    if options.headers.instancespath? # For development debug
      options.headers.instancespath = "#{options.headers.instancespath},\
                                       iid=#{@iid}"
    # request.path is available when request is received from
    # http-message-client.coffee
    options.path = request.path || url.parse(request.url).path
    if options.headers['upgrade']?.toLowerCase() is 'websocket' and \
       options.headers['connection']?.toLowerCase() is 'upgrade'
      options.agent = false
    else
      options.agent = @agent
    return options


  _setChannelTimeout: (channel, msecs) ->
    # TODO: código necesario por el ticket#75. Se supone que podría fijar el
    # timeout en cada petición, pero creo que no funciona OK
    cfg = if channel.config? then channel.config else {}
    if cfg.timeout isnt msecs
      cfg.timeout = msecs
      channel.setConfig cfg


  _getUdsPort: () ->
    self_used_uds = @used_uds
    return q.promise (resolve, reject) ->
      mkdirp UDS_PATH, (err) ->
        if err then return reject err
        next = self_used_uds.length+1
        if next > MAX_UDS then return reject Error "Too many sockets #{MAX_UDS}"
        socketPath = UDS_PATH + '/' + next + '.sock'
        self_used_uds.push socketPath
        _deleteFile socketPath
        .then () -> resolve socketPath
        .fail (err) -> reject err


  _addRequest: (reqId, request) ->
    request.timestamp = new Date()
    @requests[reqId] = request


  _deleteRequest: (reqId) ->
    if @requests[reqId]? then delete @requests[reqId]
    else @logger.warn "_deleteRequest request #{reqId} not found"


  # Periodically, checks if exists "zombie" requests
  #
  _garbageRequests: () ->
    now = new Date()
    numZombies = 0
    for reqId, request of @requests
      elapsed = now - request.timestamp
      if elapsed > @requestGarbageExpireTime
        numZombies++
        delete @requests[reqId]
    if numZombies > 0
      @logger.warn "ServerMessage._garbageRequests numZombies=#{numZombies}"
      @emit 'garbageRequests', numZombies # Used only in unitary tests


  _startGarbageRequests: (msec) ->
    @_stopGarbageRequests()
    @requestGarbageExpireTime = msec
    @garbageInterval = setInterval () =>
      @_garbageRequests()
    , @requestGarbageExpireTime


  _stopGarbageRequests: (msec) ->
    if @garbageInterval? then clearInterval(@garbageInterval)


  # This is a method class used to inject a logger to all dependent classes.
  # This method is used by klogger/index.coffee/setLogger
  #
  # @_loggerDependencies: () ->
  #   return [ClientRequest]


  # Delete a file. Returns a promise
  #
  _deleteFile = (filename) ->
    q.promise (resolve, reject) ->
      fs.unlink filename, (error) ->
        if error and not error.code is 'ENOENT'
          reject new Error('Deleting file: ' + error.message)
        resolve()


module.exports.ServerMessage = ServerMessage
