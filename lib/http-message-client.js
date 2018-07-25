(function() {
  var Agent, ClientRequest, DynChannManager, EventEmitter, IncomingMessage, extend, getDynChannManager, kutil, q,
    extend1 = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
    hasProp = {}.hasOwnProperty;

  EventEmitter = require('events').EventEmitter;

  extend = require('util')._extend;

  DynChannManager = require('./dynchannel-manager').DynChannManager;

  getDynChannManager = require('./dynchannel-manager').getDynChannManager;

  IncomingMessage = require('./http-message-incoming').IncomingMessage;

  Agent = require('./http-message-agent').Agent;

  q = require('q');

  kutil = require('./util');

  ClientRequest = (function(superClass) {
    extend1(ClientRequest, superClass);

    function ClientRequest(options, cb) {
      var method;
      this.cb = cb;
      if (this.logger == null) {
        this.logger = kutil.getLogger();
      }
      ClientRequest.__super__.constructor.call(this);
      this._reqId = kutil.generateId();
      method = "ClientRequest.constructor reqId=" + this._reqId;
      this.logger.debug("" + method);
      this._dynChannManager = getDynChannManager();
      this._staRequest = this._getStaRequest(options);
      this._agent = this._getAgent(options);
      this._dynReply = this._dynChannManager.getDynReply(this._staRequest);
      this._endIsSent = false;
      this.waitingDynRequest = q.promise((function(_this) {
        return function(resolve, reject) {
          _this._instance = null;
          _this._dynRequest = null;
          _this._response = null;
          _this._responseSource = null;
          return _this._selectDynRequest().then(function() {
            _this.logger.debug(method + " dynReply=" + _this._dynReply.name + ", dynRequest=" + _this._dynRequest.name);
            _this._send('request', options);
            return resolve();
          }).fail(function(err) {
            _this.logger.error(method + " " + err.stack);
            _this.emit('error', err);
            return reject(err);
          });
        };
      })(this));
    }

    ClientRequest.prototype.write = function(chunk, encoding, callback) {
      this.logger.debug("ClientRequest.write reqId=" + this._reqId);
      this.waitingDynRequest.then((function(_this) {
        return function() {
          if (_this._dynRequest == null) {
            throw new Error('DynRequest is null');
          }
          if (_this._endIsSent) {
            throw new Error('Write after end');
          }
          return _this._send('data', chunk, encoding, callback);
        };
      })(this)).fail((function(_this) {
        return function(err) {
          return _this.emit('error', err);
        };
      })(this));
      return true;
    };

    ClientRequest.prototype.end = function(chunk, encoding, callback) {
      this.logger.debug("ClientRequest.end reqId=" + this._reqId);
      this.waitingDynRequest.then((function(_this) {
        return function() {
          if (_this._dynRequest == null) {
            throw new Error('DynRequest is null');
          }
          if (_this._endIsSent) {
            throw new Error('End after end');
          }
          return _this._send('end', chunk, encoding, callback);
        };
      })(this)).fail((function(_this) {
        return function(err) {
          return _this.emit('error', err);
        };
      })(this));
      return true;
    };

    ClientRequest.prototype.abort = function() {
      var str;
      str = 'ClientRequest.abort is not implemented';
      this.logger.warn(str);
      throw new Error(str);
    };

    ClientRequest.prototype.setTimeout = function(msecs, callback) {
      var str;
      str = 'ClientRequest.setTimeout is not implemented';
      this.logger.warn(str);
      throw new Error(str);
    };

    ClientRequest.prototype.flushHeaders = function() {
      return this.logger.debug('ClientRequest.flushHeaders is not implemented');
    };

    ClientRequest.prototype.setNoDelay = function() {
      return this.logger.debug('ClientRequest.setNoDelay is not implemented');
    };

    ClientRequest.prototype.setSocketKeepAlive = function() {
      return this.logger.debug('ClientRequest.setSocketKeepAlive is not implemented');
    };

    ClientRequest.prototype.onDynReply = function(arg) {
      var data, message, method;
      message = arg[0], data = arg[1];
      method = "ClientRequest.onDynReply reqId=" + message.reqId + " type=" + message.type;
      this.logger.debug("" + method);
      return q.promise((function(_this) {
        return function(resolve, reject) {
          var e;
          try {
            if (message.type === 'response') {
              _this._responseSource = new EventEmitter();
              _this._response = new IncomingMessage({
                source: _this._responseSource,
                originalMessage: message
              });
              if (_this.cb != null) {
                _this.cb(_this._response);
              } else {
                _this.emit('response', _this._response);
              }
            } else {
              if (_this._response == null) {
                throw new Error('Response not yet received');
              }
              switch (message.type) {
                case 'data':
                  _this._responseSource.emit('data', data);
                  break;
                case 'end':
                  _this._dynChannManager.removeRequest(message.reqId);
                  _this._responseSource.emit('end');
                  break;
                case 'error':
                  _this._dynChannManager.removeRequest(message.reqId);
                  _this._responseSource.emit('error', data);
                  break;
                default:
                  _this.logger.warn(method + " invalid message type");
              }
            }
            return resolve([['ACK']]);
          } catch (error) {
            e = error;
            _this.logger.warn(method + " catch error = " + e.message);
            _this._dynChannManager.removeRequest(message.reqId);
            return reject(e);
          }
        };
      })(this));
    };

    ClientRequest.prototype._send = function(type, data, encoding, callback) {
      var message, options;
      message = {};
      message.type = type;
      message.reqId = this._reqId;
      message.connKey = null;
      message.fromInstance = this._staRequest.runtimeAgent.instance.iid;
      message.protocol = 'http';
      message.domain = null;
      if (type === 'request') {
        options = data;
        data = null;
        message.data = {
          protocol: 'http',
          path: options.path,
          method: options.method,
          headers: extend({}, options.headers)
        };
      } else if (type === 'data' || type === 'end') {
        message.data = null;
        if (typeof data === 'function') {
          callback = data;
          data = null;
          encoding = null;
        } else if (typeof encoding === 'function') {
          callback = encoding;
          encoding = null;
        }
      } else {
        throw new Error("Invalid message type=" + type);
      }
      return (data != null ? this._dynRequest.sendRequest([JSON.stringify(message), data]) : this._dynRequest.sendRequest([JSON.stringify(message)])).then((function(_this) {
        return function() {
          if (callback != null) {
            callback();
          }
          if (type === 'request') {
            return _this._endIsSent = true;
          }
        };
      })(this)).fail((function(_this) {
        return function(err) {
          _this.logger.error("ClientRequest._send reqId=" + _this._reqId + " err=" + err.message);
          _this._dynChannManager.removeRequest(_this._reqId);
          return emit('error', err);
        };
      })(this));
    };

    ClientRequest.prototype._getStaRequest = function(options) {
      var e, method;
      method = "ClientRequest._getStaRequest reqId=" + this._reqId;
      try {
        if (options.channel == null) {
          throw new Error('options.channel is mandatory');
        }
        if (options.channel.constructor.name !== 'Request') {
          throw new Error('options.channel must be a request channel');
        }
        if (options.channel.runtimeAgent == null) {
          throw new Error('options.channel has not a runtimeAgent property');
        }
        return options.channel;
      } catch (error) {
        e = error;
        this.logger.error(method + " " + e.stack);
        throw e;
      }
    };

    ClientRequest.prototype._getAgent = function(options) {
      var e, method, ref;
      method = "ClientRequest._getAgent reqId=" + this._reqId;
      try {
        if (options.agent == null) {
          return null;
        }
        if ((((ref = options.agent.constructor) != null ? ref.name : void 0) !== 'Agent') || (options.agent.name == null)) {
          throw new Error('options.agent must be an Agent');
        }
        return options.agent;
      } catch (error) {
        e = error;
        this.logger.error(method + " " + e.stack);
        throw e;
      }
    };

    ClientRequest.prototype._selectDynRequest = function() {
      var method, ref;
      method = "ClientRequest._selectDynRequest reqId=" + this._reqId + " channel=" + this._staRequest.name + ", agent=" + ((ref = this._agent) != null ? ref.name : void 0);
      return q.promise((function(_this) {
        return function(resolve, reject) {
          var e, instancePromise, ref1;
          try {
            instancePromise = null;
            if (((ref1 = _this._agent) != null ? ref1.name : void 0) != null) {
              instancePromise = _this._dynChannManager.getInstancePromise(_this._staRequest, _this._agent);
              if (instancePromise != null) {
                _this.logger.debug(method + " case[1]/[2]");
              } else {
                _this.logger.debug(method + " case[3]");
                instancePromise = _this._sendGetDynChannel();
                _this._dynChannManager.addInstancePromise(_this._staRequest, _this._agent, instancePromise);
              }
            } else {
              _this.logger.debug(method + " case[4]");
              instancePromise = _this._sendGetDynChannel();
            }
            return instancePromise.then(function(arg) {
              var dynRequest, instance;
              instance = arg[0], dynRequest = arg[1];
              _this._instance = instance;
              _this._dynRequest = dynRequest;
              _this._dynChannManager.addRequest(_this);
              _this.logger.debug(method + " instance=" + instance + ", dynRequest=" + dynRequest.name);
              return resolve(dynRequest);
            }).fail(function(err) {
              _this.logger.error(method + " " + err.stack);
              return reject(err);
            });
          } catch (error) {
            e = error;
            _this.logger.error(method + " " + e.stack);
            return reject(e);
          }
        };
      })(this));
    };

    ClientRequest.prototype._sendGetDynChannel = function() {
      var method;
      method = "ClientRequest._sendGetDynChannel reqId=" + this._reqId;
      this.logger.debug("" + method);
      return q.promise((function(_this) {
        return function(resolve, reject) {
          var request;
          request = JSON.stringify({
            type: 'getDynChannel',
            fromInstance: _this._staRequest.runtimeAgent.instance.iid
          });
          return _this._staRequest.sendRequest([request], [_this._dynReply]).then(function(value) {
            var dynRequest, instance, ref, status;
            _this.logger.debug(method + " solved");
            status = value[0][0];
            if (status.status === 'OK') {
              if (value.length > 1 && ((ref = value[1]) != null ? ref.length : void 0) > 0) {
                instance = value[0][1];
                dynRequest = value[1][0];
                return resolve([instance, dynRequest]);
              } else {
                throw new Error('Response doesnt have dynChannel');
              }
            } else {
              throw new Error("Status=" + (JSON.stringify(status)));
            }
          }).fail(function(err) {
            _this.logger.warn(method + " " + err.stack);
            _this._dynChannManager.resetInstancePromise(_this._staRequest, _this._agent);
            return reject(err);
          });
        };
      })(this));
    };

    ClientRequest._loggerDependencies = function() {
      return [DynChannManager, IncomingMessage, Agent];
    };

    return ClientRequest;

  })(EventEmitter);

  module.exports.ClientRequest = ClientRequest;

}).call(this);
//# sourceMappingURL=http-message-client.js.map