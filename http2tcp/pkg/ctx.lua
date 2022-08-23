local require = require
local ngx = ngx
local string = string
local setmetatable = setmetatable
local type = type
local error = error

local core_str = require("http2tcp.pkg.string")
local core_tab = require("http2tcp.pkg.table")
local request = require("http2tcp.pkg.request")
local log = require("http2tcp.pkg.log")
local tablepool = require("tablepool")
local get_var = require("resty.ngxvar").fetch
local get_request = require("resty.ngxvar").request
local ck = require "resty.cookie"

local sub_str = string.sub
local ngx_var = ngx.var
local re_gsub = ngx.re.gsub

local _M = {
    version = 0.1,
}

do
    local var_methods = {
        method = ngx.req.get_method,
        cookie = function ()
            if ngx.var.http_cookie then
                return ck:new()
            end
        end
    }

    local no_cacheable_var_names = {
        -- var.args should not be cached as it can be changed via set_uri_args
        args = true,
        is_args = true,
    }

    local ngx_var_names = {
        upstream_scheme = true,
        upstream_host = true,
        upstream_upgrade = true,
        upstream_connection = true,
        upstream_uri = true,

        upstream_mirror_host = true,

        upstream_cache_zone = true,
        upstream_cache_zone_info = true,
        upstream_no_cache = true,
        upstream_cache_key = true,
        upstream_cache_bypass = true,

        var_x_forwarded_proto = true,
    }

    local route_var_names = {
    }

    local mt = {
        __index = function(t, key)
            local cached = t._cache[key]
            if cached ~= nil then
                return cached
            end

            if type(key) ~= "string" then
                error("invalid argument, expect string value", 2)
            end

            local val
            local method = var_methods[key]
            if method then
                val = method()

            elseif core_str.has_prefix(key, "cookie_") then
                local cookie = t.cookie
                if cookie then
                    local err
                    val, err = cookie:get(sub_str(key, 8))
                    if err then
                        log.warn("failed to fetch cookie value by key: ",
                                 key, " error: ", err)
                    end
                end

            elseif core_str.has_prefix(key, "arg_") then
                local arg_key = sub_str(key, 5)
                local args = request.get_uri_args()[arg_key]
                if args then
                    if type(args) == "table" then
                        val = args[1]
                    else
                        val = args
                    end
                end

            elseif core_str.has_prefix(key, "post_arg_") then
                -- only match default post form
                if request.header(t, "Content-Type") == "application/x-www-form-urlencoded" then
                    local arg_key = sub_str(key, 10)
                    local args = request.get_post_args()[arg_key]
                    if args then
                        if type(args) == "table" then
                            val = args[1]
                        else
                            val = args
                        end
                    end
                end

            elseif core_str.has_prefix(key, "http_") then
                key = key:lower()
                key = re_gsub(key, "-", "_", "jo")
                val = get_var(key, t._request)

            elseif route_var_names[key] then
                val = ngx.ctx.route_ctx and ngx.ctx.route_ctx[key]

            else
                val = get_var(key, t._request)

            end

            if val ~= nil and not no_cacheable_var_names[key] then
                t._cache[key] = val
            end

            return val
        end,

        __newindex = function(t, key, val)
            if ngx_var_names[key] then
                ngx_var[key] = val
            end

            -- log.info("key: ", key, " new val: ", val)
            t._cache[key] = val
        end,
    }

    function _M.set_vars_meta(ctx)
        local var = tablepool.fetch("ctx_var", 0, 32)
        if not var._cache then
            var._cache = {}
        end

        var._request = get_request()

        setmetatable(var, mt)
        ctx.var = var
    end

    function _M.release_vars(ctx)
        if ctx.var == nil then
            return
        end

        core_tab.clear(ctx.var._cache)
        tablepool.release("ctx_var", ctx.var, true)
        ctx.var = nil
    end
end

return _M
