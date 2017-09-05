http = require '../src/index'
#httpnode = require 'http'
q = require 'q'
net = require 'net'
EventEmitter = require('events').EventEmitter
slaputils = require 'slaputils'
should = require 'should'
supertest = require 'supertest'
WebSocketServer = require('websocket').server


#-------------------------------------------------------------------------------
class Reply extends EventEmitter

  @dynCount = 0

  constructor: (@name, iid) ->
    @config = {}
    @runtimeAgent = {
      config: {
        iid: iid
      },
      createChannel: () ->
        return new Reply("dyn_rep_#{Reply.dynCount++}", iid)
    }

  setConfig: () ->

  handleRequest: () -> throw new Error 'NOT IMPLEMENTED'

#-------------------------------------------------------------------------------
class Request extends EventEmitter

  constructor: (@name, iid) ->
    @sentMessages = []
    @config = {}
    @runtimeAgent = {
      config: {
        iid: iid
      }
    }

  sendRequest: (message) ->
    @sentMessages.push message
    return q.promise (resolve, reject) ->
      resolve [{status: 'OK'}]
      reject 'NOT IMPLEMENTED'

  setConfig: () ->

  resetSentMesages: () -> @sentMessages = []

  getLastSentMessage: () -> return @sentMessages.pop()

#-------------------------------------------------------------------------------

logger = null
httpMessageServer = null
wsServer = null
replyChannel = null
dynReplyChannel = null
dynRequestChannel = null
SEP_IID = 'SEP1'
IID = 'A1'
CONNKEY = '123456'
EXPECTED_REPLY = 'Hello'
EXPECTED_PAYLOAD = 'More data'
reqIdCount = 1


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
    replyChannel = new Reply('main_rep_channel', IID)
    dynRequestChannel = new Request('dyn_req', IID)
    done()


  after (done) ->
    if httpMessageServer? then httpMessageServer.close()
    if wsServer? then wsServer.shutDown()
    done()


  it 'Listen', (done) ->
    httpMessageServer.listen replyChannel
    httpMessageServer.on 'listening', () -> done()


  it 'Send an invalid request', (done) ->
    request = JSON.stringify {
      type: 'XXX'
      fromInstance: IID
    }
    replyChannel.handleRequest([request], [dynRequestChannel])
    .then (message) ->
      done new Error 'Expected <invalid request type> error'
    .fail (err) ->
      done()


  it 'Establish dynamic channel', (done) ->
    request = JSON.stringify {
      type: 'getDynChannel'
      fromInstance: SEP_IID
    }
    replyChannel.handleRequest([request], [dynRequestChannel])
    .then (message) ->
      reply = message[0][0] # when test, we dont receive a "status" segment
      reply.should.be.eql IID
      dynReplyChannel = message[1][0]
      dynReplyChannel.constructor.name.should.be.eql 'Reply'
      dynReplyChannel.name.should.be.eql 'dyn_rep_0'
      done()
    .fail (err) ->
      done err


  it 'Process a request', (done) ->
    httpMessageServer.once 'request', (req, res) ->
      res.statusCode = 200
      res.setHeader('content-type', 'text/plain')
      res.write EXPECTED_REPLY
      res.end()
    dynRequestChannel.resetSentMesages()
    reqId = "#{reqIdCount++}"
    m1 = _createMessage 'http', 'request', reqId, 'get', true
    dynReplyChannel.handleRequest [m1]
    .then () ->
      m2 = _createMessage 'http', 'end', reqId
      dynReplyChannel.handleRequest [m2]
    .then () ->
      q.delay(100)
    .then () ->
      r3 = dynRequestChannel.getLastSentMessage()
      r3 = JSON.parse r3
      [r2, r2data] = dynRequestChannel.getLastSentMessage()
      r2 = JSON.parse r2
      r2data = r2data.toString()
      r1 = dynRequestChannel.getLastSentMessage()
      r1 = JSON.parse r1
      r1.type.should.be.eql 'response'
      r1.reqId.should.be.eql reqId
      r1.data.headers.instancespath.should.be.eql ",iid=#{IID}"
      r2.type.should.be.eql 'data'
      r2.reqId.should.be.eql reqId
      r2data.should.be.eql EXPECTED_REPLY
      r3.type.should.be.eql 'end'
      r3.reqId.should.be.eql reqId
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
    reqId = "#{reqIdCount++}"
    m1 = _createMessage 'http', 'request', reqId, 'post'
    dynReplyChannel.handleRequest [m1]
    .then () ->
      m2 = _createMessage 'http', 'data', reqId
      dynReplyChannel.handleRequest [m2, EXPECTED_PAYLOAD]
    .then () ->
      m3 = _createMessage 'http', 'end', reqId
      dynReplyChannel.handleRequest [m3]
    .then () ->
      q.delay(100)
    .then () ->
      r3 = dynRequestChannel.getLastSentMessage()
      r3 = JSON.parse r3
      [r2, r2data] = dynRequestChannel.getLastSentMessage()
      r2 = JSON.parse r2
      r2data = r2data.toString()
      r1 = dynRequestChannel.getLastSentMessage()
      r1 = JSON.parse r1
      r1.type.should.be.eql 'response'
      r1.reqId.should.be.eql reqId
      r2.type.should.be.eql 'data'
      r2.reqId.should.be.eql reqId
      r2data.should.be.eql EXPECTED_REPLY
      r3.type.should.be.eql 'end'
      r3.reqId.should.be.eql reqId
      done()


  it 'Fail a request because timeout', (done) ->
    httpMessageServer.once 'request', (req, res) ->
      q.delay(1000)
      .then () ->
        res.statusCode = 200
        res.setHeader('content-type', 'text/plain')
        res.write EXPECTED_REPLY
        res.end()
    dynRequestChannel.resetSentMesages()
    httpMessageServer.setTimeout 500
    reqId = "#{reqIdCount++}"
    m1 = _createMessage 'http', 'request', reqId, 'get', true
    dynReplyChannel.handleRequest [m1]
    .then () ->
      m2 = _createMessage 'http', 'end', reqId
      dynReplyChannel.handleRequest [m2]
    .then () ->
      q.delay(1000)
    .then () ->
      last = dynRequestChannel.getLastSentMessage()[0]
      JSON.parse(last).type.should.be.eql 'error'
      done()


  it 'Interleave a correct request and a timeout request', (done) ->
    processRequest = (req, res) ->
      data = ''
      req.on 'data', (chunk) ->
        data += chunk
      req.on 'end', () ->
        if data is 'normal request' then sleep = 200
        else if data is 'timeout request' then sleep = 600
        else done Error "Invalid test request type: #{data}"
        q.delay(sleep)
        .then () ->
          res.statusCode = 200
          res.setHeader('content-type', 'text/plain')
          res.write EXPECTED_REPLY
          res.end()
    httpMessageServer.on 'request', processRequest
    httpMessageServer.setTimeout 500

    dynRequestChannel.resetSentMesages()

    reqId = "#{reqIdCount++}"
    m1 = _createMessage 'http', 'request', reqId, 'post'
    dynReplyChannel.handleRequest [m1]
    .then () ->
      m2 = _createMessage 'http', 'data', reqId
      dynReplyChannel.handleRequest [m2, 'timeout request']
    .then () ->
      m3 = _createMessage 'http', 'end', reqId
      dynReplyChannel.handleRequest [m3]
    .fail (err) ->
      done err

    setTimeout () ->
      reqId = "#{reqIdCount++}"
      m1 = _createMessage 'http', 'request', reqId, 'post'
      dynReplyChannel.handleRequest [m1]
      .then () ->
        m2 = _createMessage 'http', 'data', reqId
        dynReplyChannel.handleRequest [m2, 'normal request']
      .then () ->
        m3 = _createMessage 'http', 'end', reqId
        dynReplyChannel.handleRequest [m3]
      .fail (err) ->
        done err
    , 400

    setTimeout () ->
      next = () -> return JSON.parse(dynRequestChannel.getLastSentMessage()[0])
      next().type.should.be.eql 'end'
      next().type.should.be.eql 'data'
      next().type.should.be.eql 'response'
      next().type.should.be.eql 'error'
      httpMessageServer.removeListener 'request', processRequest
      done()
    , 1000


  it 'Upgrade current connection to websocket', (done) ->
    wsServer = new WebSocketServer {
      httpServer: httpMessageServer
      autoAccepConnections: false
      keepalive: true
    }
    wsServer.on 'error', (err) -> done err
    wsServer.on 'connect', (err) -> # do nothing
    wsServer.on 'request', (request) ->
      try
        conn = request.accept()
        conn.on 'error', (err) -> done err
        conn.on 'message', (message) -> # do nothing
      catch err
        done err

    dynRequestChannel.resetSentMesages()
    reqId = "#{reqIdCount++}"
    m1 = _createMessage 'ws', 'upgrade', reqId, 'get', true
    dynReplyChannel.handleRequest [m1]
    .then () ->
      q.delay(100)
    .then () ->
      [received, receivedData] = dynRequestChannel.getLastSentMessage()
      expected = 'HTTP/1.1 101 Switching Protocols\r\n\
                  upgrade: websocket\r\n\
                  connection: Upgrade\r\n\
                  sec-websocket-accept: RYa71pA1xVjMfg1DTxSryaQLpuQ=\r\n\r\n'
      receivedData.should.be.equal expected
      done()
    .fail (err) -> done err


  it 'Process a request setting content-lengt (ticket 656)', (done) ->
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
    reqId = "#{reqIdCount++}"
    contentLength = EXPECTED_PAYLOAD.length
    m1 = _createMessage 'http', 'request', reqId, 'post', false, contentLength
    dynReplyChannel.handleRequest [m1]
    .then () ->
      m2 = _createMessage 'http', 'data', reqId
      dynReplyChannel.handleRequest [m2, EXPECTED_PAYLOAD]
    .then () ->
      # Force ticket656
      q.delay(250)
    .then () ->
      m3 = _createMessage 'http', 'end', reqId
      dynReplyChannel.handleRequest [m3]
    .then () ->
      q.delay(100)
    .then () ->
      r3 = dynRequestChannel.getLastSentMessage()
      r3 = JSON.parse r3
      [r2, r2data] = dynRequestChannel.getLastSentMessage()
      r2 = JSON.parse r2
      r2data = r2data.toString()
      r1 = dynRequestChannel.getLastSentMessage()
      r1 = JSON.parse r1
      r1.type.should.be.eql 'response'
      r1.reqId.should.be.eql reqId
      r2.type.should.be.eql 'data'
      r2.reqId.should.be.eql reqId
      r2data.should.be.eql EXPECTED_REPLY
      r3.type.should.be.eql 'end'
      r3.reqId.should.be.eql reqId
      done()


  it 'Force garbage request collector', (done) ->
    @timeout(5000)
    httpMessageServer._startGarbageRequests(1000)
    httpMessageServer.setTimeout(4000)
    httpMessageServer.once 'garbageRequests', (numRequests) ->
      numRequests.should.be.eql 1
      done()
    httpMessageServer.once 'request', (req, res) ->
      setTimeout () ->
        res.statusCode = 200
        res.setHeader('content-type', 'text/plain')
        res.write EXPECTED_REPLY
        res.end()
      , 2000 # Force garbage requests
    dynRequestChannel.resetSentMesages()
    reqId = "#{reqIdCount++}"
    m1 = _createMessage 'http', 'request', reqId, 'get', true
    dynReplyChannel.handleRequest [m1]
    .then () ->
      m2 = _createMessage 'http', 'end', reqId
      dynReplyChannel.handleRequest [m2]


  it 'Several ServerMessage objects instances', (done) ->
    # Ticket920
    CONCURRENT_SERVERS = 3
    servers = []
    completedListen = 0
    createServer = () ->
      server = http.createServer()
      server.on 'error', (err) -> done err
      server.repChann = new Reply('main_rep_channel_' + servers.length, IID)
      servers.push server
    onListen = () ->
      completedListen++
      if completedListen is servers.length
        server.close() for server in servers
        done()
    createServer() for i in [1 .. CONCURRENT_SERVERS]
    server.listen server.repChann, onListen for server in servers


  _createMessage = (prot, type, reqId, method, use_instancespath, datalength) ->
    if prot is 'http' and type is 'request'
      requestData =
        protocol: 'http'
        url: '/'
        method: method
        headers:
          host:"localhost:8080",
          #connection:"keep-alive"
      if use_instancespath? then requestData.headers.instancespath = ''
      if datalength? then requestData.headers['content-length'] = datalength
    else if prot is 'ws' and type is 'upgrade'
      requestData =
        protocol: 'http'
        url: '/'
        method: method
        headers:
          Upgrade: 'websocket'
          Connection: 'Upgrade'
          'Sec-WebSocket-Version': 13
          'Sec-WebSocket-Key': 'dntc9kLsb1emoxP6D2VnBA=='
    return JSON.stringify {
      protocol: prot
      type: type
      domain: 'uno.empresa.es'
      fromInstance: SEP_IID
      connKey: CONNKEY
      reqId: reqId
      data: requestData
    }


