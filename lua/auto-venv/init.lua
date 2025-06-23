local M = {}

local Path = require("plenary.path")
local apply_defaults = require("plenary.tbl").apply_defaults

-- TODO: Use buffer-local variables instead of utils.cache (maybe not since if the project root is the same
--       we don't want to re-fetch it for every buffer? but this may not be a good idea for monorepos anyway)
local cache = require("auto-venv.cache")
local config = require("auto-venv.config")
local utils = require("auto-venv.utils")
local venv_managers = require("auto-venv.venv_managers")

function M.get_project_venv_python_path(project_root, opts)
    opts = apply_defaults(opts, { venv_manager = nil })

    return cache.get_or_update('get_project_venv_python_path', project_root, function()
        if vim.env.VIRTUAL_ENV then
            if config.get("enable_notifications") then
                vim.notify("Using activated venv" .. vim.env.VIRTUAL_ENV, vim.log.levels.INFO)
            end

            return Path:new(vim.env.VIRTUAL_ENV):joinpath('bin', 'python'):expand()
        end

        local venv_manager = opts.venv_manager

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

local function get_python_version(python_path, opts)
    -- TODO: replace opts.full_version with a config option
    opts = apply_defaults(opts, { full_version = false })

    utils.debug("Python path: " .. python_path)

    local py_version_result = vim.system({ python_path, '--version' }, { text = true }):wait()

    if py_version_result.code ~= 0 then
        utils.error("Failed to get Python version: " .. py_version_result.stderr)
        return nil
    end

    local _, _, py_version_string = string.find(py_version_result.stdout, "%s*Python%s*(.+)%s*$")

    utils.debug("Python version output: " .. vim.inspect(py_version_result.stdout))
    utils.debug("Python version string: " .. vim.inspect(py_version_string))

    if opts.full_version then
        return py_version_string
    end

    local _, _, major, minor = string.find(py_version_string, "(%d+).(%d+)")

    if minor == nil then
        return major
    end

    return major .. '.' .. minor
end


local function get_python_venv_no_cache(bufnr, opts)
    -- TODO: replace fallback_to_system_python with a config option
    opts = apply_defaults(opts,
        { fallback_to_system_python = false, venv_manager = nil, full_version = false })

    local file_path = Path:new(vim.api.nvim_buf_get_name(bufnr))

    -- TODO: make this configurable and probably move to the venv managers, also make it independent of git
    local git_dir = file_path:find_upwards('.git')

    if git_dir == nil then
        utils.error("No .git directory found for " .. file_path:expand())
        return nil
    end

    local project_root = git_dir:parent():expand()

    if opts.venv_manager == nil then
        opts.venv_manager = venv_managers.get_venv_manager(project_root)

        if opts.venv_manager == nil then
            if not opts.fallback_to_system_python then
                utils.error("No venv was found for " .. project_root .. " and fallback to system python is disabled")

                return nil
            end
        end
    end

    local venv_manager = opts.venv_manager

    local venv_python_path = M.get_project_venv_python_path(project_root, opts)
    local python_path = venv_python_path

    if python_path == nil then
        local msg = "No virtual environment found in " .. project_root

        if opts.fallback_to_system_python then
            msg = msg .. ", falling back to system python"
        end

        utils.warn(msg)

        if not opts.fallback_to_system_python then
            return nil
        end

        -- TODO: Don't special-case this and use it the built-in venv manager
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


    local python_version = get_python_version(python_path, { full_version = opts.full_version })

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

function M.get_python_venv(bufnr, opts)
    opts = apply_defaults(opts, { fallback_to_system_python = false, venv_manager = nil, full_version = false })

    if bufnr == nil then
        bufnr = vim.api.nvim_get_current_buf()
    end

    -- TODO: oook, this definitely should be a buffer-local variable. and is?
    return cache.get_or_update('get_python_venv', bufnr, function() return get_python_venv_no_cache(bufnr, opts) end)
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
