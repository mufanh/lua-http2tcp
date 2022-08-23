local require  = require
local ngx = ngx
local select = select
local setmetatable = setmetatable
local tostring = tostring
local unpack = unpack

local ngx_log  = ngx.log
-- avoid loading other module since core.log is the most foundational one
local tab_clear = require("table.clear")
local ngx_errlog = require("ngx.errlog")
local ngx_get_phase = ngx.get_phase

local _M = {version = 0.1}

local log_levels = {
    stderr = ngx.STDERR,
    emerg  = ngx.EMERG,
    alert  = ngx.ALERT,
    crit   = ngx.CRIT,
    error  = ngx.ERR,
    warn   = ngx.WARN,
    notice = ngx.NOTICE,
    info   = ngx.INFO,
    debug  = ngx.DEBUG,
}

local cur_level
local do_nothing = function() end

local function update_log_level()
    -- Nginx use `notice` level in init phase instead of error_log directive config
    -- Ref to src/core/ngx_log.c's ngx_log_init
    if ngx_get_phase() ~= "init" then
        cur_level = ngx.config.subsystem == "http" and ngx_errlog.get_sys_filter_level()
    end
end

function _M.new(prefix)
    local m = {version = _M.version}
    setmetatable(m, {__index = function(self, cmd)
        local log_level = log_levels[cmd]
        local method
        update_log_level()

        if cur_level and (log_level > cur_level)
        then
            method = do_nothing
        else
            method = function(...)
                return ngx_log(log_level, prefix, ...)
            end
        end

        -- cache the lazily generated method in our
        -- module table
        if ngx_get_phase() ~= "init" then
            self[cmd] = method
        end

        return method
    end})

    return m
end

setmetatable(_M, {__index = function(self, cmd)
    local log_level = log_levels[cmd]
    local method
    update_log_level()

    if cur_level and (log_level > cur_level)
    then
        method = do_nothing
    else
        method = function(...)
            return ngx_log(log_level, ...)
        end
    end

    -- cache the lazily generated method in our
    -- module table
    if ngx_get_phase() ~= "init" then
        self[cmd] = method
    end

    return method
end})

local delay_tab = setmetatable({
    func = function() end,
    args = {},
    res = nil,
    }, {
    __tostring = function(self)
        -- the `__tostring` will be called twice, the first to get the length and
        -- the second to get the data
        if self.res then
            local res = self.res
            -- avoid unexpected reference
            self.res = nil
            return res
        end

        local res, err = self.func(unpack(self.args))
        if err then
            ngx.log(ngx.WARN, "failed to exec: ", err)
        end

        -- avoid unexpected reference
        tab_clear(self.args)
        self.res = tostring(res)
        return self.res
    end
})

-- It works well with log.$level, eg: log.info(..., log.delay_exec(func, ...))
-- Should not use it elsewhere.
function _M.delay_exec(func, ...)
    delay_tab.func = func

    tab_clear(delay_tab.args)
    for i = 1, select('#', ...) do
        delay_tab.args[i] = select(i, ...)
    end

    delay_tab.res = nil
    return delay_tab
end

return _M
