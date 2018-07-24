(function() {
  var IncomingMessage, Readable, klogger,
    bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
    extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
    hasProp = {}.hasOwnProperty;

  Readable = require('stream').Readable;

  klogger = require('k-logger');

  IncomingMessage = (function(superClass) {
    extend(IncomingMessage, superClass);

    function IncomingMessage(options) {
      this._onSourceError = bind(this._onSourceError, this);
      this._onSourceEnd = bind(this._onSourceEnd, this);
      this._onSourceData = bind(this._onSourceData, this);
      var method;
      if (this.logger == null) {
        klogger.setLogger([IncomingMessage]);
      }
      method = 'IncomingMessage.constructor';
      this.logger.debug("" + method);
      IncomingMessage.__super__.constructor.call(this, options);
      this._source = options.source;
      this._source.on('data', this._onSourceData);
      this._source.on('end', this._onSourceEnd);
      this._source.on('error', this._onSourceError);
      this._originalMessage = options.originalMessage;
      if ((this._originalMessage != null) && this._originalMessage.data) {
        this.httpVersionMajor = this._originalMessage.data.httpVersionMajor;
        this.httpVersionMinor = this._originalMessage.data.httpVersionMinor;
        this.httpVersion = this._originalMessage.data.httpVersion;
        this.headers = this._originalMessage.data.headers;
        this.rawHeaders = this._originalMessage.data.rawHeaders;
        this.trailers = this._originalMessage.data.trailers;
        this.rawTrailers = this._originalMessage.data.rawTrailers;
        this.url = this._originalMessage.data.url;
        this.method = this._originalMessage.data.method;
        this.statusCode = this._originalMessage.data.statusCode;
        this.statusMessage = this._originalMessage.data.statusMessage;
      } else {
        this.logger.warn(method + " originalMessage is not defined");
        this.httpVersionMajor = null;
        this.httpVersionMinor = null;
        this.httpVersion = null;
        this.headers = {};
        this.rawHeaders = [];
        this.trailers = {};
        this.rawTrailers = [];
        this.url = '';
        this.method = null;
        this.statusCode = null;
        this.statusMessage = null;
      }
    }

    IncomingMessage.prototype.setTimeout = function(msecs, callback) {
      var str;
      str = 'IncomingMessage.setTimeout is not implemented';
      this.logger.warn(str);
      throw new Error(str);
    };

    IncomingMessage.prototype.destroy = function() {
      var str;
      str = 'IncomingMessage.destroy is not implemented';
      return this.logger.warn(str);
    };

    IncomingMessage.prototype._onSourceData = function(chunk) {
      var method;
      method = 'IncomingMessage._onSourceData';
      this.logger.debug(method + " " + (chunk.toString()));
      if (this.push(chunk) === false) {
        this.logger.warn(method + " Push has returned false (higthWaterMark)");
        if (this._source.readStop != null) {
          return this._source.readStop();
        }
      }
    };

    IncomingMessage.prototype._onSourceEnd = function() {
      this.push(null);
      return this.emit('close');
    };

    IncomingMessage.prototype._onSourceError = function(e) {
      var method;
      method = 'IncomingMessage._onSourceError';
      this.logger.warn(method + " Source has emitted an error: " + e.message);
      return this.emit('error');
    };

    IncomingMessage.prototype._read = function(size) {
      if (this._source.readStart != null) {
        return this._source.readStart();
      }
    };

    return IncomingMessage;

  })(Readable);

  module.exports.IncomingMessage = IncomingMessage;

}).call(this);
//# sourceMappingURL=http-message-incoming.js.map