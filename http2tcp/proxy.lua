local ngx = ngx
local require = require
local setmetatable = setmetatable

local core = require("http2tcp.core")

local DEFAULT_CFG = {
    connect_timeout = 1000,
    read_timeout = 1000,
    write_timeout = 1000,
    pool_keepalive = 2000,
    pool_size = 300,
}
local mt = { __index = DEFAULT_CFG }

local _M = {
    version = 0.1,
}

local function fetch_ctx()
    local ctx = ngx.ctx.route_ctx
    if ctx == nil then
        ctx = core.tablepool.fetch("route_ctx", 0, 32)
        ngx.ctx.route_ctx = ctx
        core.ctx.set_vars_meta(ctx)
    end
    return ctx
end

local function release_ctx(ctx)
    core.ctx.release_vars(ctx)
    core.tablepool.release("route_ctx", ctx, false)
end

function _M.process(host, port, codec, cfg)
    if not cfg then
        cfg = {}
    end
    cfg = setmetatable(cfg, mt)

    local sock = ngx.socket.tcp()
    sock:settimeouts(cfg.connect_timeout, cfg.write_timeout, cfg.read_timeout)

    local ok, err = sock:connect(host, port)
    if not ok then
        core.log.error("fail to connect, ", err)
        core.response.exit(500, "failed to connect, " .. err)
        return
    end

    local ctx = fetch_ctx()
    local r, code, msg = codec.build_tcp_msg(ctx)
    if r == false then
        release_ctx(ctx)
        core.log.error("build tcp msg fail, ", msg)
        core.response.exit(code, msg)
        return
    end

    local _, err = sock:send(msg)
    if err then
        release_ctx(ctx)
        sock:close()
        core.log.error("failed to send, ", err)
        core.response.exit(500, "failed to send, " .. err)
        return
    end

    -- recieve_tcp_msg
    local r, code, msg = codec.recieve_tcp_msg(sock)
    if r == false then
        release_ctx(ctx)
        sock:close()
        core.log.error("failed to recieve, ", msg)
        core.response.exit(code, msg)
        return
    end

    local ok, err = sock:setkeepalive(cfg.pool_keepalive, cfg.pool_size)
    if not ok then
        core.log.warn("failed to set reusable: ", err)
        sock:close()
    end

    release_ctx(ctx)
end

return _M