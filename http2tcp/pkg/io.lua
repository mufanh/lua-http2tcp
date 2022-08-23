local io = io

local _M = {}

function _M.get_file(file_name)
    local f, err = io.open(file_name, 'r')
    if not f then
        return nil, err
    end

    local content = f:read("*all")
    f:close()
    return content
end


return _M
