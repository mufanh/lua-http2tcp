local require = require

local log = require("http2tcp.pkg.log")
local version = require("http2tcp.version")

log.info("http2tcp version:", version)

return {
    version = version,
    log = log,
    json = require("http2tcp.pkg.json"),
    io = require("http2tcp.pkg.io"),
    ctx = require("http2tcp.pkg.ctx"),
    request = require("http2tcp.pkg.request"),
    tablepool = require("tablepool"),
    response = require("http2tcp.pkg.response"),
}

