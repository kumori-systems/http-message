#-------------------------------------------------------------------------------
klogger = require 'k-logger'
http = require '../src/index'
httpNode = require 'http'
express = require 'express'
bodyParser = require 'body-parser'
q = require 'q'
should = require 'should'

#-------------------------------------------------------------------------------
class Router
  constructor: () ->
    @channels = {}
  addChannels: (channels) ->
    @channels[channel.name] = channel for channel in channels
  getDynChannel: (staChannel) ->
    @logger.silly "Router.getDynChannel #{staChannel.name}"
    if staChannel.name is STAREQUEST1_NAME
      return @channels[DYNREPLY2_NAME]
    else if staChannel.name is STAREPLY1_NAME
      return @channels[DYNREPLY1_NAME]
    else
      throw new Error 'Router.getDynChannel Invalid channel'
  send: (srcChannel, message, dynchannels) ->
    return q.promise (resolve, reject) =>
      dstChannel = null
      switch srcChannel.name
        when STAREQUEST1_NAME then dstChannel = @channels[STAREPLY1_NAME]
        when DYNREQUEST1_NAME then dstChannel = @channels[DYNREPLY1_NAME]
        when DYNREQUEST2_NAME then dstChannel = @channels[DYNREPLY2_NAME]
        else throw new Error 'Router.send invalid channel'
      @_changeChannels(dynchannels)
      @logger.silly "Router.send #{srcChannel.name} --> #{dstChannel.name}"
      dstChannel.handleRequest message, dynchannels
      .then (result) =>
        @_changeChannels(result[1])
        result[0].unshift({status: 'OK'})
        resolve result
      .fail (err) ->
        reject err
  _changeChannels: (channels) ->
    if channels? and channels.length is 1
      rep = channels.pop()
      switch rep.name
        when DYNREPLY1_NAME then channels.push @channels[DYNREQUEST1_NAME]
        when DYNREPLY2_NAME then channels.push @channels[DYNREQUEST2_NAME]
        else throw new Error 'Router.send invalid dynamic channel'


class Channel
  constructor: (@name, iid, @router, config) ->
    @config = {}
    if config? then @config[key] = value for key, value of config
    @runtimeAgent = {
      config: {
        iid: iid
      },
      instance: {
        iid: iid
      },
      createChannel: () =>
        return @router.getDynChannel(@)
    }
  setConfig: () ->
  handleRequest: () -> throw new Error 'NOT IMPLEMENTED'

class Request extends Channel
  constructor: (@name, iid, @router, config) ->
    super
  sendRequest: (message, dynchannels) ->
    @logger.silly "Request.sendRequest channel=#{@name}"
    return @router.send @, message, dynchannels

class Reply extends Channel
  constructor: (@name, iid, @router, config) ->
    super

#-------------------------------------------------------------------------------
IID_REQUESTER = 'A1'
STAREQUEST1_NAME = 'starequest1'
DYNREQUEST1_NAME = 'dynrequest1'
DYNREPLY2_NAME = 'dynreply2'

IID_REPLIER = 'B1'
STAREPLY1_NAME = 'stareply1'
DYNREPLY1_NAME = 'dynreply1'
DYNREQUEST2_NAME = 'dynrequest2'

GET_RESPONSE = 'Hello Radiola'
POST_REQUEST = JSON.stringify {
  request: 'Hello'
}
POST_DELTA = {
  response: 'Radiola'
}
POST_RESPONSE = JSON.stringify {
  request: 'Hello',
  response: 'Radiola'
}

EXPIRE_TIME = 1000

#-------------------------------------------------------------------------------

router = null
staRequest1 = null
dynRequest1 = null
dynReply2 = null
staReply1 = null
dynReply1 = null
dynRequest2 = null
agent = null
httpserver = null
logger = null


describe 'http-message-client test', ->


  before (done) ->
    klogger.setLogger [http]
    klogger.setLoggerOwner 'http-message-client'
    logger = klogger.getLogger 'http-message-client'
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
    klogger.setLogger [Request, Reply, Channel, Router]
    router = new Router()
    staRequest1 = new Request(STAREQUEST1_NAME, IID_REQUESTER, router)
    dynRequest1 = new Request(DYNREQUEST1_NAME, IID_REQUESTER, router)
    dynReply2 = new Reply(DYNREPLY2_NAME, IID_REQUESTER, router)
    staReply1 = new Reply(STAREPLY1_NAME, IID_REPLIER, router)
    dynReply1 = new Reply(DYNREPLY1_NAME, IID_REPLIER, router)
    dynRequest2 = new Request(DYNREQUEST2_NAME, IID_REPLIER, router)
    router.addChannels [staRequest1, dynRequest1, dynReply2, \
                        staReply1, dynReply1, dynRequest2]
    agent = new http.Agent()
    startServer(staReply1)
    .then (value) ->
      http._getDynChannManager({expireTime: EXPIRE_TIME}) # For test purposes
      httpserver = value
      done()


  after (done) ->
    http._getDynChannManager().close()
    if httpserver? then stopServer(httpserver)
    if agent? then agent.destroy()
    done()


  it 'Get with agent', (done) ->
    doGet(staRequest1, agent)
    .then (value) ->
      value.toString().should.be.eql GET_RESPONSE
      done()


  it 'Post with agent', (done) ->
    doPost(staRequest1, agent)
    .then (value) ->
      value.toString().should.be.eql POST_RESPONSE
      done()


  it 'Get without agent', (done) ->
    doGet(staRequest1)
    .then (value) ->
      value.toString().should.be.eql GET_RESPONSE
      done()


  it 'Post without agent', (done) ->
    doPost(staRequest1)
    .then (value) ->
      value.toString().should.be.eql POST_RESPONSE
      done()


  it 'Get+Post simultaneous', (done) ->
    promises = []
    promises.push doGet(staRequest1)
    promises.push doPost(staRequest1)
    q.all promises
    .then (values) ->
      v0 = values[0]
      v0.toString().should.be.eql GET_RESPONSE
      v1 = values[1]
      v1.toString().should.be.eql POST_RESPONSE
      done()


  it 'Check not implemented functions', (done) ->
    opt =
      channel: staRequest1
      method: 'GET'
      path: '/myget'
    req = http.request opt, (res) ->
      res.on 'data', () -> # Do nothing
      res.on 'end', () -> done()
      res.on 'error', (err) -> done err
    req.flushHeaders()
    req.setNoDelay()
    req.setSocketKeepAlive()
    abortFail = true
    try
      req.abort()
      abortFail = false
    catch e
      abortFail.should.be.equal true
    setTimeoutFail = true
    try
      req.setTimeout()
      setTimeoutFail = false
    catch e
      setTimeoutFail.should.be.equal true
    req.end()


  it 'Slow get', (done) ->
    @timeout 6*EXPIRE_TIME
    reqId = doSlowGet(staRequest1)
    q.delay(2*EXPIRE_TIME)
    .then () ->
      http._getDynChannManager().checkRequest(reqId).should.be.eql false
      q.delay(2*EXPIRE_TIME) # Wait slow get ..
      done()


  it 'Use a node-httpRequest (without channel)', (done) ->
    port = 8085
    nodeServer = httpNode.createServer (req, res) ->
      res.end GET_RESPONSE
    nodeServer.listen port, () ->
      doGet(port) # We want to use node-clientRequest
      .then (value) ->
        value.toString().should.be.eql GET_RESPONSE
        done()


#-------------------------------------------------------------------------------
startServer = (staReply) ->
  method = 'startServer'
  return q.promise (resolve, reject) ->
    getRouter = () ->
      router = express.Router()
      jsonParser = bodyParser.json()
      router.get '/myget', (req, res, next) ->
        logger.silly "#{method} router.myget"
        res.send GET_RESPONSE
      router.post '/mypost', jsonParser, (req, res, next) ->
        logger.silly "#{method} router.mypost"
        data = req.body
        data[key] = value for key, value of POST_DELTA
        res.send data
      router.get '/myslowget', (req, res, next) ->
        logger.silly "#{method} router.myget"
        setTimeout () ->
          res.send GET_RESPONSE
        , 3*EXPIRE_TIME
      return router
    getExpress = () ->
      app = express()
      app.use '/', getRouter()
      app.use (req, res, next) ->
        logger.error "#{method} router not found"
        return res.status(404).send('Not Found')
      return app
    httpserver = http.createServer getExpress()
    httpserver.listen staReply, () ->
      logger.silly "#{method} listening"
      resolve httpserver

#-------------------------------------------------------------------------------
stopServer = (httpserver) ->
  method = 'stopServer'
  return q.promise (resolve, reject) ->
    httpserver.close()
    resolve()

#-------------------------------------------------------------------------------
doGet = (staRequest1, agent) ->
  method = 'doGet'
  logger.silly "#{method}"
  return q.promise (resolve, reject) ->
    opt =
      method: 'GET'
      path: '/myget'
      agent: agent
    if staRequest1.constructor?.name is 'Request' then opt.channel = staRequest1
    else opt.port = staRequest1 # Use with node-clientRequest
    req = http.request opt, (res) ->
      postData = ''
      logger.silly "#{method} onResponse"
      res.on 'data', (chunk) ->
        logger.silly "#{method} onData : #{chunk.toString()}"
        postData = postData + chunk
      res.on 'end', () ->
        logger.silly "#{method} onEnd"
        resolve(postData)
    req.on 'error', (err) ->
      logger.error "#{method} onError: #{err.message}"
      reject(err)
    req.end()

#-------------------------------------------------------------------------------
doSlowGet = (staRequest1, agent) ->
  method = 'doGet'
  logger.silly "#{method}"
  opt =
    channel: staRequest1
    method: 'GET'
    path: '/myslowget'
    agent: agent
  req = http.request opt, (res) ->
    postData = ''
    logger.silly "#{method} onResponse"
    res.on 'data', (chunk) ->
      logger.silly "#{method} onData : #{chunk.toString()}"
      postData = postData + chunk
    res.on 'end', () ->
      logger.silly "#{method} onEnd"
  req.on 'error', (err) ->
    logger.error "#{method} onError: #{err.message}"
  req.end()
  return req._reqId

#-------------------------------------------------------------------------------
doPost = (staRequest1, agent) ->
  method = 'doPost'
  logger.silly "#{method}"
  return q.promise (resolve, reject) ->
    opt = {
      channel: staRequest1
      method: 'POST'
      path: '/mypost'
      agent: agent
      headers: {
        'Content-Type': 'application/json'
      }
    }
    req = http.request opt, (res) ->
      postData = ''
      logger.silly "#{method} onResponse"
      res.on 'data', (chunk) ->
        logger.silly "#{method} onData : #{chunk.toString()}"
        postData = postData + chunk
      res.on 'end', () ->
        logger.silly "#{method} onEnd"
        resolve(postData)
    req.on 'error', (err) ->
      logger.error "#{method} onError: #{err.message}"
      reject(err)
    req.write POST_REQUEST
    req.end()

#-------------------------------------------------------------------------------