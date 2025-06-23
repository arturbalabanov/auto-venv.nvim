local Path = require("plenary.path")
local utils = require("auto-venv.venv_managers.utils")

local M = {}

local function get_builtin_get_python_executable_name()
    if vim.fn.exepath('python3') then
        return 'python3'
    end

    return 'python'
end

M.default_venv_managers = {
    {
        name = 'uv',
        executable_name = 'uv',
        is_managing_proj_func = utils.file_present_in_proj_checker('uv.lock'),
        get_python_path_func = utils.project_local_command_runner({ 'uv', 'python', 'find' }),
    },
    {
        name = "PDM",
        executable_name = 'pdm',
        is_managing_proj_func = utils.file_present_in_proj_checker('pdm.lock'),
        get_python_path_func = utils.project_local_command_runner({ 'pdm', 'venv', '--python', 'in-project' }),
    },
    {
        name = 'Poetry',
        executable_name = 'poetry',
        is_managing_proj_func = utils.file_present_in_proj_checker('poetry.lock'),
        get_python_path_func = utils.project_local_command_runner({ 'poetry', 'env', 'info', '--executable' }),
    },
    {
        name = "Pipenv",
        executable_name = 'pipenv',
        is_managing_proj_func = utils.file_present_in_proj_checker('Pipfile.lock'),
        get_python_path_func = utils.project_local_command_runner({ 'pipenv', '--py' }),
    },
    {
        name = "Built-in venv manager (python -m venv)",
        executable_name = get_builtin_get_python_executable_name(),
        is_managing_proj_func = utils.file_present_in_proj_checker("requirements.txt"),
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

-- TODO: maybe this should be a config option
M.enabled_venv_managers = {}

-- TODO: clean up this fucking mess
for _, venv_manager in pairs(M.default_venv_managers) do
    if vim.fn.executable(venv_manager.executable_name) == 1 then
        table.insert(M.enabled_venv_managers, venv_manager)
    end
end

function M.get_venv_manager(project_root)
    for _, venv_manager in pairs(M.enabled_venv_managers) do
        if venv_manager.is_managing_proj_func(project_root) then
            return venv_manager
        end
    end

    return nil
end

return M
