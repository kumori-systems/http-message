http = require '../src/index'
q = require 'q'
EventEmitter = require('events').EventEmitter
slaputils = require 'slaputils'
should = require 'should'
supertest = require 'supertest'


#-------------------------------------------------------------------------------
class Reply extends EventEmitter

  @dynCount = 0

  constructor: (@name, iid) ->
    @config = {}
    @runtimeAgent = {
      config: {
        iid: iid
      },
      createChannel: () =>
        return new Reply("#{@name}_#{Reply.dynCount++}", iid)
    }

  setConfig: () ->

  handleRequest: () -> throw new Error 'NOT IMPLEMENTED'

#-------------------------------------------------------------------------------

logger = null
httpMessageServer = null
replyChannel = null
dynReplyChannel = null
IID = 'A1'
EXPECTED_REPLY = 'Hello'
EXPECTED_PAYLOAD = 'More data'

createSlapRequest = (method, use_instancespath) ->
  req =
    connectionKey: "123456",
    domain: ''
    protocol: 'http'
    origin: '127.0.0.1'
    httpversion: '1.1'
    url: '/'
    method: method
    headers:
      host:"localhost:8080",
      connection:"keep-alive"
  if use_instancespath? then req.headers.instancespath = ''
  return req


describe 'http-message test', ->

  before (done) ->
    slaputils.setLoggerOwner 'http-message'
    logger = slaputils.getLogger 'http-message'
    logger.configure {
      'console-log' : false
      'console-level' : 'debug'
      'colorize': true
      'file-log' : false
      'file-level': 'debug'
      'file-filename' : 'slap.log'
      'http-log' : false
      'vm' : ''
      'auto-method': false
    }
    httpMessageServer = http.createServer()
    httpMessageServer.on 'error', (err) ->
      @logger.warn "httpMessageServer.on error = #{err.message}"
    replyChannel = new Reply('main_channel', IID)
    done()


  after (done) ->
    httpMessageServer.close()
    done()


  it 'Listen', (done) ->
    httpMessageServer.listen replyChannel
    httpMessageServer.on 'listening', () -> done()


  it 'Send an invalid request', (done) ->
    request = JSON.stringify {
      type: 'XXX'
      from: IID
    }
    replyChannel.handleRequest(request)
    .then (message) ->
      done new Error 'Expected <invalid request type> error'
    .fail (err) ->
      done()


  it 'Establish dynamic channel', (done) ->
    request = JSON.stringify {
      type: 'getDynChannel'
      from: IID
    }
    replyChannel.handleRequest(request)
    .then (message) ->
      reply = message[0][0] # when test, we dont receive a "status" segment
      reply.should.be.eql request
      dynReplyChannel = message[1][0]
      dynReplyChannel.constructor.name.should.be.eql 'Reply'
      done()
    .fail (err) ->
      done err


  it 'Process a request', (done) ->
    httpMessageServer.once 'request', (req, res) ->
      res.statusCode = 200
      res.setHeader('content-type', 'text/plain')
      res.write EXPECTED_REPLY
      res.end()
    dynReplyChannel.handleRequest([
      JSON.stringify(createSlapRequest('GET')),
      null
    ])
    .then (reply) ->
      data = reply[0][1].toString()
      data.should.be.eql EXPECTED_REPLY
      done()


  it 'Process a request with payload', (done) ->
    httpMessageServer.once 'request', (req, res) ->
      data = ''
      req.on 'data', (chunk) ->
        data += chunk
      req.on 'end', () ->
        data.should.be.eql EXPECTED_PAYLOAD
        res.statusCode = 200
        res.setHeader('content-type', 'text/plain')
        res.write EXPECTED_REPLY
        res.end()

    dynReplyChannel.handleRequest([
      JSON.stringify(createSlapRequest('POST')),
      EXPECTED_PAYLOAD
    ])
    .then (reply) ->
      data = reply[0][1].toString()
      data.should.be.eql EXPECTED_REPLY
      done()


  it 'Process a with instancespath header', (done) ->
    httpMessageServer.once 'request', (req, res) ->
      res.statusCode = 200
      res.setHeader('content-type', 'text/plain')
      res.write EXPECTED_REPLY
      res.end()
    dynReplyChannel.handleRequest([
      JSON.stringify(createSlapRequest('GET', true)),
      null
    ])
    .then (reply) ->
      headers = JSON.parse(reply[0][0]).headers
      if not headers.instancespath?
        done new Error 'header instancespath expected'
      else
        headers.instancespath.should.be.eql ',iid=A1'
        data = reply[0][1].toString()
        data.should.be.eql EXPECTED_REPLY
        done()


  it 'Fail a request because timeout', (done) ->
    httpMessageServer.once 'request', (req, res) ->
      q.delay(1000)
      .then () ->
        res.statusCode = 200
        res.setHeader('content-type', 'text/plain')
        res.write EXPECTED_REPLY
        res.end()
    httpMessageServer.setTimeout 500, () ->
      done()
    dynReplyChannel.handleRequest([
      JSON.stringify(createSlapRequest('GET')),
      null
    ])
    .then (reply) ->
      done new Error 'Timeout expected'
