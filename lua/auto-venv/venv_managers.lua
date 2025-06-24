local Path = require("plenary.path")
local utils = require("auto-venv.utils")

local M = {}

local function get_builtin_get_python_executable_name()
    if vim.fn.exepath('python3') then
        return 'python3'
    end

    return 'python'
end

local project_local_command_runner = function(cmd)
    return function(project_root)
        local result = vim.system(cmd, { text = true, cwd = project_root }):wait()

        if result.code ~= 0 then
            return nil
        end

        return vim.trim(result.stdout)
    end
end

M.all_venv_managers = {
    uv = {
        name = 'uv',
        executable_name = 'uv',
        project_root_file = 'uv.lock',
        get_python_path_func = project_local_command_runner({ 'uv', 'python', 'find' }),
    },
    pdm = {
        name = "PDM",
        executable_name = 'pdm',
        project_root_file = 'pdm.lock',
        get_python_path_func = project_local_command_runner({ 'pdm', 'venv', '--python', 'in-project' }),
    },
    poetry = {
        name = 'Poetry',
        executable_name = 'poetry',
        project_root_file = 'poetry.lock',
        get_python_path_func = project_local_command_runner({ 'poetry', 'env', 'info', '--executable' }),
    },
    pipenv = {
        name = "Pipenv",
        executable_name = 'pipenv',
        project_root_file = 'Pipfile.lock',
        get_python_path_func = project_local_command_runner({ 'pipenv', '--py' }),
    },
    builtin = {
        name = "Built-in venv manager (python -m venv)",
        executable_name = get_builtin_get_python_executable_name(),
        project_root_file = "requirements.txt",
        get_python_path_func = function(project_root)
            for _, expected_dir_name in ipairs({ '.venv', 'venv', }) do
                local venv_path = Path:new(project_root):joinpath(expected_dir_name)

                if venv_path:is_dir() then
                    if venv_path:joinpath('bin', 'python'):exists() then
                        return venv_path:joinpath('bin', 'python'):expand()
                    end

                    if venv_path:joinpath('bin', 'python3'):exists() then
                        return venv_path:joinpath('bin', 'python3'):expand()
                    end
                end
            end

            return vim.fn.exepath('python3') or vim.fn.exepath('python') or 'python'
        end,
    },
    -- TODO: add support for rye
    -- TODO: Add support for hatch
    -- TODO: Add support for virtualenvwrapper
    -- TODO: Add support for conda
}

function M.get_venv_manager(file_path)
    -- imporing config here to avoid circular dependency issues
    local config = require('auto-venv.config')

    local enabled_venv_managers = config.get("managers")
    if enabled_venv_managers == nil or vim.tbl_isempty(enabled_venv_managers) then
        utils.warn("No venv managers are enabled in the configuration.")
        return nil, nil
    end

    -- TODO: extract max_depth into a config option
    local max_depth = 10 -- necessary to avoid potential infinite loops caused by circular symlinks
    local depth = 0

    local potential_project_root = Path:new(file_path)
    while depth < max_depth do
        potential_project_root = potential_project_root:parent()
        depth = depth + 1

        for _, venv_manager in pairs(enabled_venv_managers) do
            if venv_manager ~= nil then
                if potential_project_root:joinpath(venv_manager.project_root_file):exists() then
                    -- TODO: don't return two values, split it into seperate functions instead
                    return potential_project_root:expand(), venv_manager
                end
            end
        end
    end

    utils.warn("No venv manager found for file: " .. file_path)
    return nil, nil
end

return M
