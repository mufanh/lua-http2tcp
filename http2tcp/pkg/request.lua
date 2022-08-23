local require = require
local ngx = ngx
local tonumber = tonumber
local error = error
local type = type
local string = string

local lfs = require("lfs")
local log = require("http2tcp.pkg.log")
local io = require("http2tcp.pkg.io")
local json = require("http2tcp.pkg.json")

local get_headers = ngx.req.get_headers
local clear_header = ngx.req.clear_header
local str_fmt = string.format
local str_lower = string.lower
local req_read_body = ngx.req.read_body
local req_get_body_data = ngx.req.get_body_data
local req_get_body_file = ngx.req.get_body_file
local req_get_post_args = ngx.req.get_post_args
local req_get_uri_args = ngx.req.get_uri_args
local req_set_uri_args = ngx.req.set_uri_args

local _M = {}

local function _headers(ctx)
    if not ctx then
        ctx = ngx.ctx.route_ctx
    end
    local headers = ctx.headers
    if not headers then
        headers = get_headers()
        ctx.headers = headers
    end
    return headers
end

local function _validate_header_name(name)
    local tname = type(name)
    if tname ~= "string" then
        return nil, str_fmt("invalid header name %q: got %s, " ..
                "expected string", name, tname)
    end
    return name
end

_M.headers = _headers

function _M.header(ctx, name)
    if not ctx then
        ctx = ngx.ctx.route_ctx
    end
    return _headers(ctx)[name]
end


function _M.set_header(ctx, header_name, header_value)
    local err
    header_name, err = _validate_header_name(header_name)
    if err then
        error(err)
    end

    if ctx and ctx.headers then
        ctx.headers[header_name] = header_value
    end

    ngx.req.set_header(header_name, header_value)
end

function _M.get_ip(ctx)
    if not ctx then
        ctx = ngx.ctx.route_ctx
    end
    return ctx.var.realip_remote_addr or ctx.var.remote_addr or ''
end

function _M.get_remote_client_ip(ctx)
    if not ctx then
        ctx = ngx.ctx.route_ctx
    end
    return ctx.var.remote_addr or ''
end

function _M.get_remote_client_port(ctx)
    if not ctx then
        ctx = ngx.ctx.route_ctx
    end
    return tonumber(ctx.var.remote_port)
end

function _M.get_uri_args(ctx)
    if not ctx then
        ctx = ngx.ctx.route_ctx
    end

    if not ctx.req_uri_args then
        -- use 0 to avoid truncated result and keep the behavior as the
        -- same as other platforms
        local args = req_get_uri_args(0)
        ctx.req_uri_args = args
    end

    return ctx.req_uri_args
end

function _M.set_uri_args(ctx, args)
    if not ctx then
        ctx = ngx.ctx.route_ctx
    end

    ctx.req_uri_args = nil
    return req_set_uri_args(args)
end

function _M.get_post_args(ctx)
    if not ctx then
        ctx = ngx.ctx.route_ctx
    end

    if not ctx.req_post_args then
        req_read_body()

        -- use 0 to avoid truncated result and keep the behavior as the
        -- same as other platforms
        local args, err = req_get_post_args(0)
        if not args then
            -- do we need a way to handle huge post forms?
            log.error("the post form is too large: ", err)
            args = {}
        end
        ctx.req_post_args = args
    end

    return ctx.req_post_args
end

local function check_size(size, max_size)
    if max_size and size > max_size then
        return nil, "request size " .. size .. " is greater than the "
                    .. "maximum size " .. max_size .. " allowed"
    end

    return true
end

local function test_expect(var)
    local expect = var.http_expect
    return expect and str_lower(expect) == "100-continue"
end


local function get_body(max_size, ctx)
    if ctx.req_body then
        return ctx.req_body
    end

    if max_size then
        local var = ctx and ctx.var or ngx.var
        local content_length = tonumber(var.http_content_length)
        if content_length then
            local ok, err = check_size(content_length, max_size)
            if not ok then
                -- When client_max_body_size is exceeded, Nginx will set r->expect_tested = 1 to
                -- avoid sending the 100 CONTINUE.
                -- We use trick below to imitate this behavior.
                if test_expect(var) then
                    clear_header("expect")
                end

                return nil, err
            end
        end
    end

    req_read_body()

    local req_body = req_get_body_data()
    if req_body then
        local ok, err = check_size(#req_body, max_size)
        if not ok then
            return nil, err
        end

        ctx.req_body = req_body
        return req_body
    end

    local file_name = req_get_body_file()
    if not file_name then
        return nil
    end

    log.info("attempt to read body from file: ", file_name)

    if max_size then
        local size, err = lfs.attributes (file_name, "size")
        if not size then
            return nil, err
        end

        local ok, err = check_size(size, max_size)
        if not ok then
            return nil, err
        end
    end

    local req_body, err = io.get_file(file_name)
    ctx.req_body = req_body

    return req_body, err
end
_M.get_body = get_body

function _M.get_body_json(max_size, ctx)
    if ctx.req_json then
        return ctx.req_json
    end

    local body = get_body(max_size, ctx)
    if body then
        local req_json = json.decode(body)
        ctx.req_json = req_json
        return req_json
    end
    return nil
end

function _M.get_path(ctx)
    if not ctx then
        ctx = ngx.ctx.route_ctx
    end

    return ctx.var.uri or ''
end


function _M.get_scheme(ctx)
    if not ctx then
        ctx = ngx.ctx.route_ctx
    end
    return ctx.var.scheme or ''
end


function _M.get_host(ctx)
    if not ctx then
        ctx = ngx.ctx.route_ctx
    end
    return ctx.var.host or ''
end


function _M.get_port(ctx)
    if not ctx then
        ctx = ngx.ctx.route_ctx
    end
    return tonumber(ctx.var.server_port)
end


function _M.get_path(ctx)
    if not ctx then
        ctx = ngx.ctx.route_ctx
    end

    return ctx.var.uri or ''
end

function _M.get_http_version()
    return ngx.req.http_version()
end

_M.get_method = ngx.req.get_method

return _M