local require = require
local string = string
local tonumber = tonumber

local core = require("http2tcp.core")

local _M = {
    version = 0.1,
    name = "example-codec",
}

-- HTTP message to TCP message
function _M.build_tcp_msg(ctx)
    local request_body = core.request.get_body(nil, ctx)
    if not request_body then
        return false, 400, "empty request body"
    end
    local len = string.len(request_body)
    if len == 0 then
        return false, 400, "request body blank"
    end
    return true, nil, string.format("%08d%s", len, request_body)
end

-- TCP message to HTTP message
function _M.recieve_tcp_msg(sock)
    local len, err = sock:receiveany(8)
    if not len then
        return false, 500, "recieve msg err, " .. err
    end

    local len = tonumber(len)
    if not len then
        return false, 500, "recieve msg format err, " .. err
    end

    local res_data, err = sock:receiveany(len)
    if not res_data then
        return false, 500, "recieve msg err, " .. err
    end

    core.response.say(res_data)
    return true
end

return _M