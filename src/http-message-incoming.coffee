Readable = require('stream').Readable

# Slap implementation of http.IncomingMessage.
#
# TODO:
# - timeout
# - flow control (readStart, readStop) - ticket#637
#
class IncomingMessage extends Readable


  constructor: (options) ->
    method = 'IncomingMessage.constructor'
    @logger.debug "#{method}"
    super options

    @_source = options.source
    @_source.on 'data', @_onSourceData
    @_source.on 'end', @_onSourceEnd
    @_source.on 'error', @_onSourceError

    @_originalMessage = options.originalMessage
    if @_originalMessage? and @_originalMessage.data
      @httpVersionMajor = @_originalMessage.data.httpVersionMajor
      @httpVersionMinor = @_originalMessage.data.httpVersionMinor
      @httpVersion = @_originalMessage.data.httpVersion
      @headers = @_originalMessage.data.headers
      @rawHeaders = @_originalMessage.data.rawHeaders
      @trailers = @_originalMessage.data.trailers
      @rawTrailers = @_originalMessage.data.rawTrailers
      @url = @_originalMessage.data.url
      @method = @_originalMessage.data.method
      @statusCode = @_originalMessage.data.statusCode
      @statusMessage = @_originalMessage.data.statusMessage
    else
      @logger.warn "#{method} originalMessage is not defined"
      @httpVersionMajor = null
      @httpVersionMinor = null
      @httpVersion = null
      @headers = {}
      @rawHeaders = []
      @trailers = {}
      @rawTrailers = []
      @url = ''
      @method = null
      @statusCode = null
      @statusMessage = null


  setTimeout: (msecs, callback) ->
    str = 'IncomingMessage.setTimeout is not implemented'
    @logger.warn str
    throw new Error str


  destroy: () ->
    str = 'IncomingMessage.destroy is not implemented'
    @logger.warn str


  _onSourceData: (chunk) =>
    method = 'IncomingMessage._onSourceData'
    @logger.debug "#{method} #{chunk.toString()}"
    if @push(chunk) is false
      # Nothing to do... because we have not flow control over the source.
      # In the future, _source (a slap-request channel) will have flow
      # control, and will have a readStop method
      @logger.warn "#{method} Push has returned false (higthWaterMark)"
      if @_source.readStop? then @_source.readStop()


  _onSourceEnd: () =>
    @push null
    @emit 'close'


  _onSourceError: (e) =>
    method = 'IncomingMessage._onSourceError'
    @logger.warn "#{method} Source has emitted an error: #{e.message}"
    @emit 'error'


  _read: (size) ->
    # Nothing to do... because we have not flow control over the source.
    # In the future, _source (a slap-request channel) will have flow control,
    # and will have a readStart method
    if @_source.readStart? then @_source.readStart()


module.exports = IncomingMessage
