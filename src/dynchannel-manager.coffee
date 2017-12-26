q = require 'q'
klogger = require 'k-logger'

# Control over which dyn-channels we must use / are using for each http request
#
# State example:
#
#   ComponentA has 3 request channels:
#   - RQ1 is connectect to ComponentB-RP1
#   - RQ2 is connectect to ComponentB-RP2
#   - RQ3 is connectect to ComponentC-RP3
#
#   In this example, instance A1 has stablished dynamic channels with B1, B2,
#   C1 and C2.
#   A1 has created several agents, associated to several (not all) requests.
#   Two requests using the same static request channel and agent, must use
#   the same dynamic channels (sticky with destination instances)
#
#   (This dictionary associates static request channels with dynamic reply
#   channels. One static request channel is associated with ONE dynamic reply
#   channel. One static request channel is associatged with SEVERAL dynamic
#   request channel - one for each destination instance. When we share
#   dynamic reply channel between all dynamic request channels, we reduce the
#   number of messages to send)
#   staRequestToDynReply = {
#     'RQ1' : 'dynRep1',
#     'RQ2' : 'dynRep2',
#     'RQ3' : 'dynRep3'
#   }
#
#   (This dictionary associates agents+static_channel with destination
#   instances and dynamic request channel. Promise contains instance+dynRequest,
#   or indicates that resolution is in process)
#   agentsMap = {
#     'ag1': {
#       'RQ1': promise (solved with B1,dynreq1),
#       'RQ3': promise (solved with C1,dynreq4)
#     },
#     'ag2': {
#       'RQ1': promise (solved with B1,dynreq1)
#     },
#     'ag3': {
#       'RQ1': promise (solved with B2,dynreq2)
#     },
#     'ag4': {
#       'RQ2': promise (solved with B1,dynreq3)
#     },
#     'ag5': {
#       'RQ2': promise (pending)
#     }
#   }
#
#   (This dictionary stores current requests (key is request id))
#   requestsMap = {
#     'r1': object_request_1,
#     'r2': object_request_2,
#     'r3': object_request_3,
#     'r4': object_request_4,
#     'r5': object_request_5,
#     'r6': object_request_6
#   }
#
#
# WORKFLOW EXAMPLE
#
#
# User code creates a new agent (optional)
#
#   ag1 = new agent()
#
# State:
#   agentsMap = {
#     (...)
#     'ag1': {}
#   }
#   requestsMap = {
#     (...)
#   }
#   staRequestToDynReply = {
#     (...)
#   }
#
# User code creates a new httpRequest through RQ1, with ag1 associated
# ClientRequest code creates (if not exists) a dyn reply channel for this
# static request (this is a synchronous operation)
# Assuming there is no entry agentMap.ag1.RQ1, ClientRequest code sends a
# 'getDynChannel' message through RQ1. So we are waiting an instance+dynRequest
# resolution. (Other possibilities: there is an entry agentMap.ag1.RQ1 and (1)
# itspromise is not yet solved or (2) its promise is already solved).
#
#   r1 = new ClientRequest {agent:ag1, channel:RQ1}, (response) ->
#     doThinghs(response)
#
# State:
#   agentsMap = {
#     (...)
#     'ag1': {
#       'RQ1': promise (pending)
#     }
#   }
#   requestsMap = {
#     (...)
#   }
#   staRequestToDynReply = {
#     (...)
#     'RQ1' : 'dynRep1'
#   }
#
#
# 'getDynDhannel' message receives its response: a dynamic request channel
# (dynreq1) and a destination instance (B1).
# ClientRequest changes its state.
# Invokes its callback or emits a '(http)response' event.
#
#   r1 = new ClientRequest {agent:ag1, channel:RQ1}, (response) ->
#     doThinghs(response) <<<<< executed when dynamic request resolved
#
# State:
#   agentsMap = {
#     (...)
#     'ag1': {
#       'RQ1': promise(solved with B1,dynreq1)
#     }
#   }
#   requestsMap = {
#     (...)
#     'r1': object_request_1
#     }
#   }
#   staRequestToDynReply = {
#     (...)
#     'RQ1' : 'dynRep1'
#   }
#
# Now ...
#   r1.write()/end() will use dynreq1 to send data.
#   r1.response will receive data/end events, through dynrep1.
#
#   If a second ClientRequest (r2) is created with {agent:ag1, channel:RQ1},
#   then will check that agentsMap.ag1.RQ1.promise is solved, and will get
#   agentMap.ag1.RQ1.instance (B1)
#
DEFAULT_EXPIRE_TIME = 60 * 60 * 1000   # 1 hour
class DynChannManager

  constructor: (options) ->
    if not @logger? # If logger hasn't been injected from outside
      klogger.setLogger [DynChannManager]

    method = 'DynChannManager.constructor'
    @logger.debug "#{method}"

    # This dictionary associates static request channels with dynamic reply
    # channels. One static request channel is associated with ONE dynamic reply
    # channel. One static request channel is associatged with SEVERAL dynamic
    # request channel - one for each destination instance. When we share
    # dynamic reply channel between all dynamic request channels, we reduce the
    # number of messages
    @staRequestToDynReply = {}

    # This dictionary associates agents+static_channel with destination
    # instances. Promise indicates that resolution is in process.
    # This dictionary associates agents+static_channel with destination
    # instances and dynamic request channel. Promise contains instance +
    # dynRequest, or indicates that resolution is in process)
    @agentsMap = {}

    # This dictionary stores current requests (key is request id)
    @requestsMap = {}

    # Checks if exists requests "zombies"
    if options?.expireTime? then @expireTime = options?.expireTime
    else @expireTime = DEFAULT_EXPIRE_TIME
    @garbageInterval = setInterval () =>
      @_garbageRequests()
    , @expireTime


  close: () ->
    method = 'DynChannManager.close'
    if @garbageInterval? then clearInterval(@garbageInterval)


  # Returns the promise associated to the pair static request channel and
  # agent.
  # If this pair isnt registered, returns null
  #
  getInstancePromise: (staRequest, agent) ->
    return @agentsMap[agent.name]?[staRequest.name]


  # Adds the promise associated to the pair static request channel and agent.
  #
  addInstancePromise: (staRequest, agent, promise) ->
    @logger.debug "DynChannManager.addInstancePromise \
                   staRequest=#{staRequest.name}, agent=#{agent.name}"
    try
      if not @agentsMap[agent.name]? then @agentsMap[agent.name] = {}
      @agentsMap[agent.name][staRequest.name] = promise
    catch e
      @logger.warn "DynChannManager.addInstancePromise #{e.stack}"
      throw e


  # Resets info associated to an agent + static request channel.
  # Used when an error occurs, and a new instance must be choosen
  #
  resetInstancePromise: (staRequest, agent) ->
    @logger.debug "DynChannManager.resetInstancePromise \
                   staRequest=#{staRequest.name}, agent=#{agent.name}"
    try
      if @agentsMap[agent.name]?[staRequest.name]?
        delete @agentsMap[agent.name][staRequest.name]
    catch e
      @logger.warn "DynChannManager.resetInstancePromise #{e.stack}"
      throw e


  # Gets a dynamic reply channel associated with a static request channel, and
  # saves it in a dictionary
  #
  getDynReply: (staRequest) ->
    try
      if not @staRequestToDynReply[staRequest.name]?
        dynReply = staRequest.runtimeAgent.createChannel()
        @staRequestToDynReply[staRequest.name] = dynReply
        dynReply.handleRequest = @_onDynReply
      return @staRequestToDynReply[staRequest.name]
    catch e
      @logger.error "DynChannManager.getDynReply #{e.stack}"
      throw e


  # Adds a request to current requests
  #
  addRequest: (request) ->
    @logger.debug "DynChannManager.addRequest reqId=#{request._reqId}"
    try
      request.timestamp = new Date()
      @requestsMap[request._reqId] = request
    catch e
      @logger.warn "DynChannManager.addRequest #{e.stack}"
      throw e


  # Removs a request from current requests
  #
  removeRequest: (reqId) ->
    @logger.debug "DynChannManager.removeRequest reqId=#{reqId}"
    try
      delete @requestsMap[reqId]
    catch e
      @logger.warn "DynChannManager.removeRequest #{e.stack}"
      throw e


  # Checks is exists a request.
  # Used only in unitary tests.
  #
  checkRequest: (reqId) ->
    @logger.debug "DynChannManager.checkRequest reqId=#{reqId}"
    try
      return @requestsMap[reqId]?
    catch e
      @logger.warn "DynChannManager.addRequest #{e.stack}"
      throw e


  # A message (response/data/end/error) has been received from an instance.
  # Searchs wich request (and response) must attend this message.
  # Message contains:
  #  - type: 'response'/'data'/'end'/'error'
  #  - headers (only if type is 'response')
  #  - statusCode (only if type is 'response')
  #  - protocol (always 'http')
  #  - domain
  #  - connKey
  #  - reqId
  #
  _onDynReply: ([message, chunk]) =>
    method = "DynChannManager._onDynReply"
    try
      message = JSON.parse message
      if not message?.reqId?
        throw new Error 'message.reqId=null'
      else if not @requestsMap[message.reqId]?
        throw new Error "Message #{message.reqId} not found"
      else
        @logger.debug "#{method} message #{message.reqId}"
        @requestsMap[message.reqId].onDynReply [message, chunk]
    catch e
      @logger.warn "#{method} #{e.message}"
      return q.reject(e)


  # Each hour, checks if exists requests "zombies"
  #
  _garbageRequests: () ->
    now = new Date()
    numZombies = 0
    for reqId, request of @requestsMap
      elapsed = now - request.timestamp
      if elapsed > @expireTime
        numZombies++
        @removeRequest reqId
    if numZombies > 0
      @logger.warn "DynChannManager._garbageRequests numZombies=#{numZombies}"


# This is used only for logger injection
module.exports.DynChannManager = DynChannManager

# Singleton pattern
#
singletonInstance = null
module.exports.getDynChannManager = (options) ->
  if not singletonInstance?
    singletonInstance = new DynChannManager(options)
  return singletonInstance

