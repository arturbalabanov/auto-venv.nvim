local Path = require("plenary.path")

local M = {}

M.file_present_in_proj_checker = function(file_name)
    return function(project_root)
        local match = vim.fn.glob(Path:new(project_root):joinpath(file_name):expand())
        return match ~= ''
    end
end

M.project_local_command_runner = function(cmd)
    return function(project_root)
        local result = vim.system(cmd, { text = true, cwd = project_root }):wait()

        if result.code ~= 0 then
            return nil
        end

        return vim.trim(result.stdout)
    end
end

return M
