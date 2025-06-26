local M = {}

local Path = require("plenary.path")

-- TODO: Use buffer-local variables instead of utils.cache (maybe not since if the project root is the same
--       we don't want to re-fetch it for every buffer? but this may not be a good idea for monorepos anyway)
local cache = require("auto-venv.cache")
local config = require("auto-venv.config")
local utils = require("auto-venv.utils")
local venv_managers = require("auto-venv.venv_managers")

function M.get_project_venv_python_path(project_root, venv_manager)
    return cache.get_or_update('get_project_venv_python_path', project_root, function()
        if vim.env.VIRTUAL_ENV then
            if config.get("enable_notifications") then
                vim.notify("Using activated venv" .. vim.env.VIRTUAL_ENV, vim.log.levels.INFO)
            end

            return Path:new(vim.env.VIRTUAL_ENV):joinpath('bin', 'python'):expand()
        end

        if venv_manager == nil then
            venv_manager = venv_managers.get_venv_manager(project_root)

            if venv_manager == nil then
                return nil
            end
        end

        return venv_manager.get_python_path_func(project_root)
    end)
end

local function get_venv_name(venv_python_path, project_root)
    if venv_python_path == nil then
        return "<system>"
    end

    -- :h is the parent
    -- :t is the last component
    -- The pythonpath is <venv-path>/bin/python

    local venv_dir_path = vim.fn.fnamemodify(venv_python_path, ":h:h")
    local venv_dir_name = vim.fn.fnamemodify(venv_dir_path, ":t")
    local project_name = vim.fn.fnamemodify(project_root, ':t')

    -- TODO: If the venv manager supports getting the venv name, use that instead

    if venv_dir_name == '.venv' then
        return project_name
    end

    return venv_dir_name
end

local function get_python_version(python_path)
    utils.debug("Python path: " .. python_path)

    local py_version_result = vim.system({ python_path, '--version' }, { text = true }):wait()

    if py_version_result.code ~= 0 then
        utils.error("Failed to get Python version: " .. py_version_result.stderr)
        return nil
    end

    local _, _, py_version_string = string.find(py_version_result.stdout, "%s*Python%s*(.+)%s*$")

    utils.debug("Python version output: " .. vim.inspect(py_version_result.stdout))
    utils.debug("Python version string: " .. vim.inspect(py_version_string))

    local _, _, major, minor = string.find(py_version_string, "(%d+).(%d+)")

    if minor == nil then
        return major
    end

    return major .. '.' .. minor
end


-- TODO: Use filenames instead of buffers
local function get_python_venv_no_cache(bufnr)
    local file_path = vim.api.nvim_buf_get_name(bufnr)
    local buftype = vim.api.nvim_buf_get_option(bufnr, 'buftype')
    local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')

    -- TODO: make this a config option
    if buftype == 'nofile' or buftype == 'nowrite' or buftype == 'prompt' then
        -- This is a special buffer type, e.g. a file tree, etc.
        -- it doesn't make sense to set a venv for it
        utils.debug("Buffer " .. bufnr .. " is of type '" .. buftype .. "', ignoring it for venv detection")
        return nil
    end

    if file_path == nil or file_path == '' then
        -- This happens if the buffer is not saved to a file yet
        -- or it's not associated with a file (e.g. a file tree)

        -- TODO: Maybe it should fallback to the current working directory?
        --       But only for some buftypes (e.g. not for a file tree, etc.)
        utils.debug("No file path found for buffer " .. bufnr .. ", cannot determine venv")
        return nil
    end

    if filetype ~= 'python' then
        -- only apply venv detection for Python files
        -- TODO: this is a hack to cover annoying edge cases (e.g. git commits), ideally it should be
        --       applied to any file in the project (e.g. yaml files) as they can still depend on the venv
        utils.debug("Buffer " .. bufnr .. " is of type '" .. filetype .. "', ignoring it for venv detection")
        return nil
    end

    local project_root, venv_manager = venv_managers.get_venv_manager(file_path)

    if venv_manager == nil then
        if not config.get("fallback_to_system_python") then
            utils.error("No venv was found for " .. project_root .. " and fallback to system python is disabled")

            return nil
        end
    end

    -- TODO: Cache the project root and use the filename to retrieve it (i.e. return the first entry from the cache which is
    --       a valid prefix of the file path, sorted by length!
    local venv_python_path = M.get_project_venv_python_path(project_root, venv_manager)
    local python_path = venv_python_path

    if python_path == nil then
        local msg = "No virtual environment found in " .. project_root

        if config.get("fallback_to_system_python") then
            msg = msg .. ", falling back to system python"
        end

        utils.warn(msg)

        if not config.get("fallback_to_system_python") then
            return nil
        end

        python_path = vim.fn.exepath('python3') or vim.fn.exepath('python') or 'python'
    end

    local venv_bin_path = nil

    if venv_python_path ~= nil then
        venv_bin_path = vim.fn.fnamemodify(venv_python_path, ':h')
    end

    local venv_path = nil

    if venv_bin_path ~= nil then
        venv_path = vim.fn.fnamemodify(venv_bin_path, ':h')
    end


    local python_version = get_python_version(python_path)

    local pyproject_toml = Path:new(project_root):joinpath('pyproject.toml')

    if pyproject_toml:exists() then
        pyproject_toml = pyproject_toml:expand()
    else
        pyproject_toml = nil
    end

    return {
        name = get_venv_name(venv_python_path, project_root),
        venv_path = venv_path,
        bin_path = venv_bin_path,
        python_path = python_path,
        python_version = python_version,
        pyproject_toml = pyproject_toml,
        venv_manager_name = utils.tbl_get(venv_manager, "name"),
    }
end

function M.get_python_venv(bufnr)
    if bufnr == nil then
        bufnr = vim.api.nvim_get_current_buf()
    end

    -- TODO: oook, this definitely should be a buffer-local variable. and is?
    return cache.get_or_update('get_python_venv', bufnr, function() return get_python_venv_no_cache(bufnr) end)
end

-- TODO: rename me to env_local_command_path or something similar
--       maybe make it a method of the venv object
function M.buf_local_command_path(command, bufnr)
    local venv = M.get_python_venv(bufnr)

    if venv == nil then
        return command
    end

    return Path:new(venv.bin_path):joinpath(command):expand()
end

M.setup = function(opts)
    config.update(opts)
end

return M
