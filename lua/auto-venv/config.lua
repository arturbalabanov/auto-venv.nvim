local M = {}

local utils = require("auto-venv.utils")
local venv_managers = require("auto-venv.venv_managers")

-- defaults
M.plugin_opts = {
    debug = false,
    -- TODO: More granular notifications options, e.g. enabling all errors and warnings but not info
    enable_notifications = true,
    fallback_to_system_python = false,
    managers = {},
}

for venv_manager_id, venv_manager in pairs(venv_managers.all_venv_managers) do
    if vim.fn.executable(venv_manager.executable_name) == 1 then
        M.plugin_opts.managers[venv_manager_id] = venv_manager
    end
end

-- TODO: allow for key1.key2.key3 to be specified as an argument, there is already utils.tbl_get for that I think
M.get = function(key)
    if M.plugin_opts[key] == nil then
        utils.error("unexpected config option " .. key)
        return nil
    end

    return M.plugin_opts[key]
end

M.update = function(opts)
    vim.tbl_deep_extend("force", M.plugin_opts, opts or {})
end

return M
