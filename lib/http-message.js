(function() {
  var ClientRequest, DEFAULT_CHANNEL_TIMEOUT, MAX_UDS, REQUEST_GARBAGE_EXPIRE_TIME, ServerMessage, UDS_PATH, extend, fs, http, klogger, mkdirp, q, url,
    bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
    extend1 = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
    hasProp = {}.hasOwnProperty;

  fs = require('fs');

  http = require('http');

  url = require('url');

  extend = require('util')._extend;

  q = require('q');

  mkdirp = require('mkdirp');

  klogger = require('k-logger');

  ClientRequest = require('./http-message-client').ClientRequest;

  UDS_PATH = './sockets';

  MAX_UDS = 100;

  DEFAULT_CHANNEL_TIMEOUT = 60 * 60 * 1000;

  REQUEST_GARBAGE_EXPIRE_TIME = 2 * 60 * 60 * 1000;

  ServerMessage = (function(superClass) {
    var _deleteFile;

    extend1(ServerMessage, superClass);

    ServerMessage.prototype.used_uds = [];

    function ServerMessage(requestListener) {
      this._handleWS = bind(this._handleWS, this);
      this._handleHttpRequest = bind(this._handleHttpRequest, this);
      this._handleStaticRequest = bind(this._handleStaticRequest, this);
      var method;
      if (this.logger == null) {
        klogger.setLogger([ServerMessage]);
      }
      method = 'ServerMessage.constructor';
      this.logger.info("" + method);
      this.dynChannels = {};
      this.requests = {};
      this.websockets = {};
      this.currentTimeout = DEFAULT_CHANNEL_TIMEOUT;
      this._startGarbageRequests(REQUEST_GARBAGE_EXPIRE_TIME);
      ServerMessage.__super__.constructor.call(this, requestListener);
    }

    ServerMessage.prototype.listen = function(channel1, cb) {
      var method, ref;
      this.channel = channel1;
      method = 'ServerMessage.listen';
      this.logger.info(method + " channel=" + this.channel.name);
      this.runtime = this.channel.runtimeAgent;
      this.iid = this.runtime.config.iid;
      this.channel.handleRequest = this._handleStaticRequest;
      this.tcpPort = (ref = this.channel.config) != null ? ref.port : void 0;
      if (this.tcpPort) {
        this.logger.info(method + " using tcp-port " + this.tcpPort + " (local-stamp)");
        return ServerMessage.__super__.listen.call(this, this.tcpPort, cb);
      } else {
        return this._getUdsPort().then((function(_this) {
          return function(socketPath) {
            _this.socketPath = socketPath;
            _this.logger.info(method + " socketPath=" + _this.socketPath);
            return ServerMessage.__super__.listen.call(_this, _this.socketPath, cb);
          };
        })(this)).fail((function(_this) {
          return function(err) {
            if (cb != null) {
              cb(err);
            }
            return _this.emit('error', err);
          };
        })(this));
      }
    };

    ServerMessage.prototype.close = function(cb) {
      var method;
      method = 'ServerMessage.close';
      this.logger.info("" + method);
      this._stopGarbageRequests();
      this.channel.handleRequest = null;
      return ServerMessage.__super__.close.call(this, cb);
    };

    ServerMessage.prototype.setTimeout = function(msecs, cb) {
      var dyn, iid, ref;
      this.currentTimeout = msecs;
      ref = this.dynChannels;
      for (iid in ref) {
        dyn = ref[iid];
        this._setChannelTimeout(dyn.request, msecs);
      }
      return ServerMessage.__super__.setTimeout.call(this, msecs, cb);
    };

    ServerMessage.prototype._handleStaticRequest = function(arg, arg1) {
      var dynRequestChannel, method, request;
      request = arg[0];
      dynRequestChannel = arg1[0];
      method = 'ServerMessage:_handleStaticRequest';
      this.logger.debug("" + method);
      return q.promise((function(_this) {
        return function(resolve, reject) {
          var created, dynReplyChannel, e, ref;
          try {
            _this.logger.debug(method + " request = " + (request.toString()));
            request = JSON.parse(request.toString());
            if (request.type === 'getDynChannel') {
              if (((ref = _this.dynChannels[request.fromInstance]) != null ? ref.request : void 0) === dynRequestChannel) {
                dynReplyChannel = _this.dynChannels[request.fromInstance].reply;
                created = false;
              } else {
                dynReplyChannel = _this.runtime.createChannel();
                dynReplyChannel.handleRequest = function(arg2) {
                  var data, message;
                  message = arg2[0], data = arg2[1];
                  message = JSON.parse(message);
                  if (message.protocol === 'ws') {
                    return _this._handleWS([message, data]);
                  } else {
                    return _this._handleHttpRequest([message, data]);
                  }
                };
                _this._setChannelTimeout(dynReplyChannel, _this.currentTimeout);
                _this.dynChannels[request.fromInstance] = {
                  reply: dynReplyChannel,
                  request: dynRequestChannel
                };
                created = true;
              }
              _this.logger.debug(method + " created=" + created + " dynReplyChannel=" + dynReplyChannel.name + ",dynRequestChannel=" + dynRequestChannel.name);
              return resolve([[_this.iid], [dynReplyChannel]]);
            } else {
              throw new Error('Invalid request type');
            }
          } catch (error1) {
            e = error1;
            _this.logger.error(method + " catch error = " + e.message);
            return reject(e);
          }
        };
      })(this));
    };

    ServerMessage.prototype._handleHttpRequest = function(arg) {
      var data, message, method, reqId, type;
      message = arg[0], data = arg[1];
      reqId = message.reqId;
      type = message.type;
      method = "ServerMessage:_handleHttpRequest reqId=" + reqId + " type=" + type;
      this.logger.debug("" + method);
      return q.promise((function(_this) {
        return function(resolve, reject) {
          var e, options, request;
          try {
            switch (type) {
              case 'request':
                options = _this._getOptionsRequest(message.data);
                request = http.request(options);
                _this._addRequest(reqId, request);
                request.on('error', function(err) {
                  _this.logger.warn(method + " onError " + err.stack);
                  return _this._processHttpResponseError(message, err);
                });
                request.on('response', function(response) {
                  var instancespath;
                  if (_this.requests[reqId] != null) {
                    instancespath = options.headers.instancespath;
                    if (instancespath != null) {
                      response.headers.instancespath = instancespath;
                    }
                    return _this._processHttpResponse(response, message);
                  } else {
                    return _this.logger.warn(method + " onResponse request not found");
                  }
                });
                return resolve([['ACK']]);
              case 'data':
                request = _this.requests[reqId];
                if (request != null) {
                  return request.write(data, function() {
                    return resolve([['ACK']]);
                  });
                } else {
                  return resolve([['ACK']]);
                }
                break;
              case 'aborted':
                request = _this.requests[reqId];
                if (request != null) {
                  request.abort();
                  return resolve([['ACK']]);
                } else {
                  return resolve([['ACK']]);
                }
                break;
              case 'end':
                request = _this.requests[reqId];
                if (request != null) {
                  request.end();
                  return resolve([['ACK']]);
                } else {
                  return resolve([['ACK']]);
                }
                break;
              default:
                throw new Error("Invalid message type: " + type);
            }
          } catch (error1) {
            e = error1;
            _this.logger.warn(method + " catch error = " + e.message);
            return reject(e);
          }
        };
      })(this));
    };

    ServerMessage.prototype._processHttpResponse = function(response, requestMessage) {
      var dynRequestChannel, method, reqId, responseMessage;
      reqId = requestMessage.reqId;
      method = "ServerMessage:_processHttpResponse reqId=" + reqId;
      this.logger.debug("" + method);
      dynRequestChannel = this.dynChannels[requestMessage.fromInstance].request;
      if (dynRequestChannel != null) {
        responseMessage = this._createHttpMessage('response', response, requestMessage);
        this._sendMessage(dynRequestChannel, responseMessage);
        response.on('data', (function(_this) {
          return function(chunk) {
            responseMessage = _this._createHttpMessage('data', response, requestMessage);
            return _this._sendMessage(dynRequestChannel, responseMessage, chunk);
          };
        })(this));
        response.on('end', (function(_this) {
          return function() {
            responseMessage = _this._createHttpMessage('end', response, requestMessage);
            _this._sendMessage(dynRequestChannel, responseMessage);
            if (_this.requests[reqId] != null) {
              return _this._deleteRequest(reqId);
            }
          };
        })(this));
        return response.on('error', (function(_this) {
          return function(err) {
            _this.logger.warn(method + " onError " + err.stack);
            if (_this.requests[reqId] != null) {
              return _this._deleteRequest(reqId);
            }
          };
        })(this));
      } else {
        return this.logger.warn(method + " dynRequestChannel not found for iid = " + requestMessage.fromInstance);
      }
    };

    ServerMessage.prototype._processHttpResponseError = function(requestMessage, err) {
      var dynRequestChannel, method, reqId, responseMessage;
      method = 'ServerMessage:_processHttpResponseError';
      this.logger.debug(method + " " + (JSON.stringify(requestMessage)));
      reqId = requestMessage.reqId;
      dynRequestChannel = this.dynChannels[requestMessage.fromInstance].request;
      if (dynRequestChannel != null) {
        responseMessage = this._createHttpMessage('error', null, requestMessage);
        this._sendMessage(dynRequestChannel, responseMessage, err.message);
        if (this.requests[reqId] != null) {
          return this._deleteRequest(reqId);
        }
      } else {
        return this.logger.warn(method + " dynRequestChannel not found for iid = " + requestMessage.fromInstance);
      }
    };

    ServerMessage.prototype._handleWS = function(arg) {
      var data, message, method, reqId;
      message = arg[0], data = arg[1];
      reqId = message.reqId;
      method = "ServerMessage:_handleWS reqId=" + reqId + " type=" + (message != null ? message.type : void 0);
      this.logger.debug("" + method);
      return q.promise((function(_this) {
        return function(resolve, reject) {
          var e, socket;
          try {
            switch (message.type) {
              case 'upgrade':
                return _this._processUpgrade(message, resolve, reject);
              case 'data':
                socket = _this.websockets[reqId];
                if (socket != null) {
                  return socket.write(data, function() {
                    return resolve([['ACK']]);
                  });
                } else {
                  return resolve([['ACK']]);
                }
                break;
              case 'end':
                socket = _this.websockets[reqId];
                if (socket != null) {
                  socket.end();
                  return resolve([['ACK']]);
                } else {
                  return resolve([['ACK']]);
                }
                break;
              default:
                throw new Error("Invalid message type: " + message.type);
            }
          } catch (error1) {
            e = error1;
            _this.logger.warn(method + " catch error = " + e.message);
            return reject(e);
          }
        };
      })(this));
    };

    ServerMessage.prototype._processUpgrade = function(message, resolve, reject) {
      var connKey, dynRequestChannel, method, options, reqId, request, text;
      reqId = message.reqId;
      connKey = message.connKey;
      method = "ServerMessage:_processUpgrade reqId=" + reqId;
      this.logger.debug("" + method);
      dynRequestChannel = this.dynChannels[message.fromInstance].request;
      if (dynRequestChannel != null) {
        options = this._getOptionsRequest(message.data);
        request = http.request(options);
        request.on('error', (function(_this) {
          return function(err) {
            var responseMessage;
            _this.logger.error(method + " onError " + err.message);
            responseMessage = _this._createWsMessage('upgrade', connKey, reqId, err.message);
            return _this._sendMessage(dynRequestChannel, responseMessage);
          };
        })(this));
        request.on('response', (function(_this) {
          return function(response) {
            var err, responseMessage;
            err = 'resonse event unexpected';
            _this.logger.error(method + " onError " + err);
            responseMessage = _this._createWsMessage('upgrade', connKey, reqId, err);
            return _this._sendMessage(dynRequestChannel, responseMessage);
          };
        })(this));
        request.on('upgrade', (function(_this) {
          return function(response, socket, head) {
            var ack, responseMessage;
            _this.logger.debug(method + " upgrade received");
            responseMessage = _this._createWsMessage('upgrade', connKey, reqId);
            ack = _this._createWsUpgradeAck(response);
            _this._sendMessage(dynRequestChannel, responseMessage, ack);
            _this.websockets[reqId] = socket;
            if (_this.requests[reqId] != null) {
              _this._deleteRequest(reqId);
            }
            socket.on('data', function(chunk) {
              message = _this._createWsMessage('data', connKey, reqId);
              return _this._sendMessage(dynRequestChannel, message, chunk);
            });
            return socket.on('close', function() {
              delete _this.websockets[reqId];
              message = _this._createWsMessage('end', connKey, reqId);
              return _this._sendMessage(dynRequestChannel, message);
            });
          };
        })(this));
        request.end();
        return resolve([['ACK']]);
      } else {
        text = "dynRequestChannel not found for iid = " + requestMessage.fromInstance;
        this.logger.warn(method + " " + text);
        return reject(new Error(text));
      }
    };

    ServerMessage.prototype._createHttpMessage = function(type, response, requestMessage) {
      var message;
      message = {
        protocol: 'http',
        type: type,
        domain: requestMessage.domain,
        connKey: requestMessage.connKey,
        reqId: requestMessage.reqId
      };
      if (type === 'response') {
        message.data = {};
        message.data.httpVersionMajor = response.httpVersionMajor;
        message.data.httpVersionMinor = response.httpVersionMinor;
        message.data.httpVersion = response.httpVersion;
        message.data.headers = response.headers;
        message.data.rawHeaders = response.rawHeaders;
        message.data.trailers = response.trailers;
        message.data.rawTrailers = response.rawTrailers;
        message.data.url = response.url;
        message.data.method = response.method;
        message.data.statusCode = response.statusCode;
        message.data.statusMessage = response.statusMessage;
      }
      return message;
    };

    ServerMessage.prototype._createWsMessage = function(type, connKey, reqId, error) {
      var message;
      message = {
        protocol: 'ws',
        type: type,
        connKey: connKey,
        reqId: reqId,
        error: error
      };
      return message;
    };

    ServerMessage.prototype._createWsUpgradeAck = function(response) {
      var ack, key, ref, value;
      ack = '';
      ack = ['HTTP/1.1 101 Switching Protocols'];
      ref = response.headers;
      for (key in ref) {
        value = ref[key];
        ack.push(key + ": " + value);
      }
      ack = ack.join('\r\n');
      ack = ack + '\r\n\r\n';
      return ack;
    };

    ServerMessage.prototype._sendMessage = function(channel, message, data) {
      var aux, method;
      method = "ServerMessage:_sendMessage reqId=" + (message != null ? message.reqId : void 0) + " type=" + (message != null ? message.type : void 0);
      this.logger.debug("" + method);
      aux = [JSON.stringify(message)];
      if (data != null) {
        aux.push(data);
      }
      return channel.sendRequest(aux).fail((function(_this) {
        return function(err) {
          return _this.logger.error(method + " err = " + err.stack);
        };
      })(this));
    };

    ServerMessage.prototype._getOptionsRequest = function(request) {
      var options, ref, ref1;
      options = {};
      if (this.tcpPort != null) {
        options.port = this.tcpPort;
      } else {
        options.socketPath = this.socketPath;
      }
      options.host = 'localhost';
      options.method = request.method;
      options.headers = extend({}, request.headers);
      if ((options.method === 'DELETE' || options.method === 'OPTIONS') && (!options.headers['content-length'])) {
        options.headers['content-length'] = '0';
      }
      if (options.headers.instancespath != null) {
        options.headers.instancespath = options.headers.instancespath + ",iid=" + this.iid;
      }
      options.path = request.path || url.parse(request.url).path;
      if (((ref = options.headers['upgrade']) != null ? ref.toLowerCase() : void 0) === 'websocket' && ((ref1 = options.headers['connection']) != null ? ref1.toLowerCase() : void 0) === 'upgrade') {
        options.agent = false;
      } else {
        options.agent = this.agent;
      }
      return options;
    };

    ServerMessage.prototype._setChannelTimeout = function(channel, msecs) {
      var cfg;
      cfg = channel.config != null ? channel.config : {};
      if (cfg.timeout !== msecs) {
        cfg.timeout = msecs;
        return channel.setConfig(cfg);
      }
    };

    ServerMessage.prototype._getUdsPort = function() {
      var self_used_uds;
      self_used_uds = this.used_uds;
      return q.promise(function(resolve, reject) {
        return mkdirp(UDS_PATH, function(err) {
          var next, socketPath;
          if (err) {
            return reject(err);
          }
          next = self_used_uds.length + 1;
          if (next > MAX_UDS) {
            return reject(Error("Too many sockets " + MAX_UDS));
          }
          socketPath = UDS_PATH + '/' + next + '.sock';
          self_used_uds.push(socketPath);
          return _deleteFile(socketPath).then(function() {
            return resolve(socketPath);
          }).fail(function(err) {
            return reject(err);
          });
        });
      });
    };

    ServerMessage.prototype._addRequest = function(reqId, request) {
      request.timestamp = new Date();
      return this.requests[reqId] = request;
    };

    ServerMessage.prototype._deleteRequest = function(reqId) {
      if (this.requests[reqId] != null) {
        return delete this.requests[reqId];
      } else {
        return this.logger.warn("_deleteRequest request " + reqId + " not found");
      }
    };

    ServerMessage.prototype._garbageRequests = function() {
      var elapsed, now, numZombies, ref, reqId, request;
      now = new Date();
      numZombies = 0;
      ref = this.requests;
      for (reqId in ref) {
        request = ref[reqId];
        elapsed = now - request.timestamp;
        if (elapsed > this.requestGarbageExpireTime) {
          numZombies++;
          delete this.requests[reqId];
        }
      }
      if (numZombies > 0) {
        this.logger.warn("ServerMessage._garbageRequests numZombies=" + numZombies);
        return this.emit('garbageRequests', numZombies);
      }
    };

    ServerMessage.prototype._startGarbageRequests = function(msec) {
      this._stopGarbageRequests();
      this.requestGarbageExpireTime = msec;
      return this.garbageInterval = setInterval((function(_this) {
        return function() {
          return _this._garbageRequests();
        };
      })(this), this.requestGarbageExpireTime);
    };

    ServerMessage.prototype._stopGarbageRequests = function(msec) {
      if (this.garbageInterval != null) {
        return clearInterval(this.garbageInterval);
      }
    };

    ServerMessage._loggerDependencies = function() {
      return [ClientRequest];
    };

    _deleteFile = function(filename) {
      return q.promise(function(resolve, reject) {
        return fs.unlink(filename, function(error) {
          if (error && !error.code === 'ENOENT') {
            reject(new Error('Deleting file: ' + error.message));
          }
          return resolve();
        });
      });
    };

    return ServerMessage;

  })(http.Server);

  module.exports.ServerMessage = ServerMessage;

}).call(this);
//# sourceMappingURL=http-message.js.map