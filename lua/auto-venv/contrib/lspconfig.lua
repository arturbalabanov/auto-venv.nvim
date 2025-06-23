local M = {}

local utils = require("auto-venv.utils")

local function pyright_set_venv(client, venv)
    client.config.settings.python.pythonPath = venv.python_path
    client.notify("workspace/didChangeConfiguration", { settings = client.config.settings })
end

local set_venv_per_client = {
    pyright = pyright_set_venv,
}


-- TODO: Extract this into a config option, or even better -- make autocommands
--       for entering and leaving an environment and allow the user to hook into them
--       ref: https://github.com/akinsho/toggleterm.nvim/blob/e76134e682c1a866e3dfcdaeb691eb7b01068668/lua/toggleterm.lua#L343
local function post_set_venv_hook(bufnr, client, venv)
    -- TODO: b.py_venv_info should be the same as in M.on_attach
    if (not venv) or (not venv.pyproject_toml) or (vim.b.py_venv_info == nil) or (not vim.b.py_venv_info.pyproject_toml) then
        return
    end

    if vim.fn.filereadable(vim.b.py_venv_info.pyproject_toml) == 0 then
        utils.debug("pyproject.toml not found at " .. vim.b.py_venv_info.pyproject_toml)
        return
    end

    -- TODO: Remove dependancy on dasel and use a lua library instead
    local cmd = { "dasel", "-f", vim.b.py_venv_info.pyproject_toml, "tool.ruff.line-length" }
    local line_length_result = vim.system(cmd, { text = true }):wait()

    if line_length_result.code ~= 0 then
        utils.warn("Failed to get line length from pyproject.toml: " .. line_length_result.stderr)
        return
    end

    local line_length = vim.trim(line_length_result.stdout)

    vim.cmd(string.format('setlocal colorcolumn=%s', line_length))
    vim.cmd(string.format('setlocal textwidth=%s', line_length))
end

-- TODO: Change this to be applied for every file in the project (e.g. yaml when using a linter installed in the venv)
--       Obviously it won't use the LSP's on_attach but it should still "edit" the PATH for that buffer only

function M.on_attach(client, bufnr)
    local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

    if filetype ~= "python" then
        return
    end

    local norm_client_name = client.name:gsub('%-', '_')
    local set_venv = set_venv_per_client[norm_client_name]

    if set_venv == nil then
        return
    end

    -- TODO: Extract to a config option
    local var_name = "py_venv_info"

    local found, saved_venv = pcall(vim.api.nvim_buf_get_var, bufnr, var_name)
    local venv = require("auto-venv").get_python_venv(bufnr)

    -- TODO: Duplication with what we have down
    if venv == nil then
        return
    end

    if not found or saved_venv ~= venv then
        vim.api.nvim_buf_set_var(bufnr, var_name, venv)
        set_venv(client, venv)
        post_set_venv_hook(bufnr, client, venv)
    end

    vim.api.nvim_create_autocmd("BufEnter", {
        group = vim.api.nvim_create_augroup("AutoSetPythonVenv__" .. norm_client_name, { clear = false }),
        buffer = bufnr,
        callback = function(event)
            found, saved_venv = pcall(vim.api.nvim_buf_get_var, bufnr, var_name)
            venv = require("auto-venv").get_python_venv(bufnr)

            if venv == nil then
                return
            end

            if not found or saved_venv ~= venv then
                vim.api.nvim_buf_set_var(bufnr, var_name, venv)
                set_venv(client, venv)
                post_set_venv_hook(bufnr, client, venv)
            end
        end
    })
end

return M
