(function() {
  var DEFAULT_EXPIRE_TIME, DynChannManager, kutil, q, singletonInstance,
    bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

  q = require('q');

  kutil = require('./util');

  DEFAULT_EXPIRE_TIME = 60 * 60 * 1000;

  DynChannManager = (function() {
    function DynChannManager(options) {
      this._onDynReply = bind(this._onDynReply, this);
      var method;
      if (this.logger == null) {
        this.logger = kutil.getLogger();
      }
      method = 'DynChannManager.constructor';
      this.logger.debug("" + method);
      this.staRequestToDynReply = {};
      this.agentsMap = {};
      this.requestsMap = {};
      if ((options != null ? options.expireTime : void 0) != null) {
        this.expireTime = options != null ? options.expireTime : void 0;
      } else {
        this.expireTime = DEFAULT_EXPIRE_TIME;
      }
      this.garbageInterval = setInterval((function(_this) {
        return function() {
          return _this._garbageRequests();
        };
      })(this), this.expireTime);
    }

    DynChannManager.prototype.close = function() {
      var method;
      method = 'DynChannManager.close';
      if (this.garbageInterval != null) {
        return clearInterval(this.garbageInterval);
      }
    };

    DynChannManager.prototype.getInstancePromise = function(staRequest, agent) {
      var ref;
      return (ref = this.agentsMap[agent.name]) != null ? ref[staRequest.name] : void 0;
    };

    DynChannManager.prototype.addInstancePromise = function(staRequest, agent, promise) {
      var e;
      this.logger.debug("DynChannManager.addInstancePromise staRequest=" + staRequest.name + ", agent=" + agent.name);
      try {
        if (this.agentsMap[agent.name] == null) {
          this.agentsMap[agent.name] = {};
        }
        return this.agentsMap[agent.name][staRequest.name] = promise;
      } catch (error) {
        e = error;
        this.logger.warn("DynChannManager.addInstancePromise " + e.stack);
        throw e;
      }
    };

    DynChannManager.prototype.resetInstancePromise = function(staRequest, agent) {
      var e, ref;
      this.logger.debug("DynChannManager.resetInstancePromise staRequest=" + staRequest.name + ", agent=" + agent.name);
      try {
        if (((ref = this.agentsMap[agent.name]) != null ? ref[staRequest.name] : void 0) != null) {
          return delete this.agentsMap[agent.name][staRequest.name];
        }
      } catch (error) {
        e = error;
        this.logger.warn("DynChannManager.resetInstancePromise " + e.stack);
        throw e;
      }
    };

    DynChannManager.prototype.getDynReply = function(staRequest) {
      var dynReply, e;
      try {
        if (this.staRequestToDynReply[staRequest.name] == null) {
          dynReply = staRequest.runtimeAgent.createChannel();
          this.staRequestToDynReply[staRequest.name] = dynReply;
          dynReply.handleRequest = this._onDynReply;
        }
        return this.staRequestToDynReply[staRequest.name];
      } catch (error) {
        e = error;
        this.logger.error("DynChannManager.getDynReply " + e.stack);
        throw e;
      }
    };

    DynChannManager.prototype.addRequest = function(request) {
      var e;
      this.logger.debug("DynChannManager.addRequest reqId=" + request._reqId);
      try {
        request.timestamp = new Date();
        return this.requestsMap[request._reqId] = request;
      } catch (error) {
        e = error;
        this.logger.warn("DynChannManager.addRequest " + e.stack);
        throw e;
      }
    };

    DynChannManager.prototype.removeRequest = function(reqId) {
      var e;
      this.logger.debug("DynChannManager.removeRequest reqId=" + reqId);
      try {
        return delete this.requestsMap[reqId];
      } catch (error) {
        e = error;
        this.logger.warn("DynChannManager.removeRequest " + e.stack);
        throw e;
      }
    };

    DynChannManager.prototype.checkRequest = function(reqId) {
      var e;
      this.logger.debug("DynChannManager.checkRequest reqId=" + reqId);
      try {
        return this.requestsMap[reqId] != null;
      } catch (error) {
        e = error;
        this.logger.warn("DynChannManager.addRequest " + e.stack);
        throw e;
      }
    };

    DynChannManager.prototype._onDynReply = function(arg) {
      var chunk, e, message, method;
      message = arg[0], chunk = arg[1];
      method = "DynChannManager._onDynReply";
      try {
        message = JSON.parse(message);
        if ((message != null ? message.reqId : void 0) == null) {
          throw new Error('message.reqId=null');
        } else if (this.requestsMap[message.reqId] == null) {
          throw new Error("Message " + message.reqId + " not found");
        } else {
          this.logger.debug(method + " message " + message.reqId);
          return this.requestsMap[message.reqId].onDynReply([message, chunk]);
        }
      } catch (error) {
        e = error;
        this.logger.warn(method + " " + e.message);
        return q.reject(e);
      }
    };

    DynChannManager.prototype._garbageRequests = function() {
      var elapsed, now, numZombies, ref, reqId, request;
      now = new Date();
      numZombies = 0;
      ref = this.requestsMap;
      for (reqId in ref) {
        request = ref[reqId];
        elapsed = now - request.timestamp;
        if (elapsed > this.expireTime) {
          numZombies++;
          this.removeRequest(reqId);
        }
      }
      if (numZombies > 0) {
        return this.logger.warn("DynChannManager._garbageRequests numZombies=" + numZombies);
      }
    };

    return DynChannManager;

  })();

  module.exports.DynChannManager = DynChannManager;

  singletonInstance = null;

  module.exports.getDynChannManager = function(options) {
    if (singletonInstance == null) {
      singletonInstance = new DynChannManager(options);
    }
    return singletonInstance;
  };

}).call(this);
//# sourceMappingURL=dynchannel-manager.js.map