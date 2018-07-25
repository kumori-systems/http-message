debug = require 'debug'
uuid = require 'node-uuid'

BASE = 'http-message'

exports.getLogger = ->
  return {
    error: debug("#{BASE}:error")
    warn: debug("#{BASE}:warn")
    info: debug("#{BASE}:info")
    debug: debug("#{BASE}:debug")
    silly: debug("#{BASE}:silly")
  }

exports.generateId = ->
  return uuid.v4()
