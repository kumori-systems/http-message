http = require 'http'
url = require 'url'
extend = require('util')._extend
ip = require 'ip'


INTERNALPORT = 8081
DEFAULT_CHANNEL_TIMEOUT = 3600000 # 1 hour


class ServerMessage extends http.Server


  constructor: (requestListener) ->
    method = 'ServerMessage.constructor'
    @logger.info "#{methodName}"

    # Dictionary of dynamic reply channels, indexed by httpSep-iid.
    @dynReplyChannels = {}

    # Destination of http-request (parsed as object)
    @target = url.parse("http://localhost:#{INTERNALPORT}")

    @currentTimeout = DEFAULT_CHANNEL_TIMEOUT

    super requestListener


  listen: (@channel, cb) ->
    console.log "ServerMessage.listen channel=#{@channel.name}, \
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
    @_setChannelTimeout(channel, msecs) for iid, channel of @dynReplyChannels
    super msecs, cb


  # Receive a new request via static reply channel: returns, using a promise
  # a dynamic reply channel for proccess http requests.
  #
  _handleStaticRequest: (message) =>
    methodName = 'ServerMessage:_handleStaticRequest'
    @logger.info "#{methodName} message received #{message.toString()}"
    return q.promise (resolve, reject) =>
      try
        request = JSON.parse message
        iid = request.from
        if request.type is 'getDynChannel'
          if not @dynReplyChannels[iid]?
            channel = @runtime.createChannel()
            channel.handleRequest = @_handleHttpRequest
            @_setChannelTimeout(channel, @currentTimeout)
            @dynReplyChannels[iid] = channel
          @logger.info "#{methodName} resolve dynReplyChannel=\
                        #{@dynReplyChannels[iid].name}"
          resolve [[JSON.stringify(request)],[@dynReplyChannels[iid]]]
        else
          throw new Error 'Invalid request type'
      catch e
        @logger.error "#{methodName} catch error = #{e.message}"
        @emit 'error', e
        reject(e)


  # Receive a new http request vía dynamic reply channel: create an equivalent
  # http request, send to target, and wait (promise) response
  #
  _handleHttpRequest: (message) =>
    methodName = 'ServerMessage:_handleHttpRequest'
    @logger.debug "#{methodName} message received"
    return q.promise (resolve, reject) =>
      try
        message = Array.apply null, message
        slapRequest = JSON.parse message[0]
        slapRequestData = message[1] ? null # payload of request

        options = @_getOptionsRequest slapRequest
        proxyReq = http.request options

        proxyReq.on 'error', (err) =>
          @logger.error "#{methodName} onError error = #{err.message}"
          @emit 'error', err
          reject(err)

        proxyReq.on 'response', (proxyRes) =>
          @_onHttpResponse options.headers.instancespath, proxyRes, resolve

        if slapRequestData?
          slapRequestData = new Buffer slapRequestData
          proxyReq.write slapRequestData
        proxyReq.end()
      catch e
        @logger.error "#{methodName} catch error = #{e.message}"
        @emit 'error', e
        reject(e)


  # Process a http response
  # Extract relevant info from response, "package" it, and return via promise
  #
  _onHttpResponse: (instancespath, response, resolve) ->
    methodName = 'ServerMessage:_onHttpResponse'
    @logger.debug "#{methodName} message received"

    # For development debug: special header "instancespath"
    if instancespath? then response.headers.instancespath = instancespath

    slapResponse =
      headers: response.headers
      statusCode: response.statusCode
    slapResponseData = null

    response.on 'data', (chunk) ->
      if slapResponseData is null then slapResponseData = []
      slapResponseData.push chunk

    response.on 'end', () ->
      if slapResponseData isnt null
        slapResponseData = Buffer.concat(slapResponseData)
      aux = [JSON.stringify(slapResponse)]
      if slapResponseData? then aux.push slapResponseData
      resolve [aux]

    response.on 'error', () =>
      @logger.info textError
      @emit 'error', new Error(textError)


  # Create "option" param that http.request constructor needs
  #
  _getOptionsRequest: (slapRequest) ->
    options = {}
    options.port = @target.port
    if (@target.host != undefined) then options.host = @target.host
    if (@target.hostname != undefined) then options.hostname = @target.hostname
    options.method = slapRequest.method
    options.headers = extend({}, slapRequest.headers)
    if (options.method is 'DELETE' or \ # Copied from http-proxy
       options.method is 'OPTIONS') and \
       (not options.headers['content-length'])
      options.headers['content-length'] = '0'
    if options.headers.instancespath? # For development debug
      options.headers.instancespath = "#{options.headers.instancespath},\
                                       iid=#{@iid}"
    options.path = url.parse(slapRequest.url).path
    return options


  _setChannelTimeout: (channel, msecs) ->
    # TODO: código necesario por el ticket#75. Se supone que podría fijar el
    # timeout en cada petición, pero creo que no funciona OK
    cfg = if channel.config? then channel.config else {}
    if cfg.timeout isnt msecs
      cfg.timeout = msecs
      channel.setConfig cfg


module.exports = ServerMessage
