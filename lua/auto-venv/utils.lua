-- TODO: Investigate logging in neovim

local M = {}

M.tbl_get = function(tbl, ...)
    local path = { ... }

    if tbl == nil then
        return nil
    end

    local next_key = table.remove(path, 1)
    local value = tbl[next_key]

    if #path == 0 then
        return value
    end

    if type(value) ~= "table" then
        return nil
    end

    return M.tbl_get(value, unpack(path))
end

M.debug = function(msg)
    -- importing here instead at top level to avoid circular dependency
    if require('auto-venv.config').get("debug") then
        print(msg)
    end
end

M.info = function(msg)
    -- importing here instead at top level to avoid circular dependency
    if require('auto-venv.config').get("debug") then
        print(msg)
    end
end

M.warn = function(msg)
    if require('auto-venv.config').get("enable_notifications") then
        vim.notify(string.format("auto-venv.nvim: %s", msg), vim.log.levels.WARN)
    else
        print(string.format("auto-venv.nvim WARNING: %s", msg))
    end
end

M.error = function(msg)
    if require('auto-venv.config').get("enable_notifications") then
        vim.notify(string.format("auto-venv.nvim: %s", msg), vim.log.levels.ERROR)
    else
        print(string.format("auto-venv.nvim ERROR: %s", msg))
    end
end

return M
