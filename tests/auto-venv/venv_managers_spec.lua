---@diagnostic disable: undefined-global
---@diagnostic disable: undefined-field
-- https://github.com/nvim-lua/plenary.nvim/blob/master/TESTS_README.md
-- https://github.com/lunarmodules/luassert

local Path = require("plenary.path")

-- TODO: maybe move (some of) this to the minimal_init.lua
local auto_venv = require("auto-venv")
assert(auto_venv ~= nil, "auto-venv should be loaded")
auto_venv.setup({ debug = false })

local PROJECT_ROOT = Path:new(vim.fn.fnamemodify(debug.getinfo(1, "Sl").source:sub(2), ":h:h:h"))
local TEST_PROJECTS_DIR = PROJECT_ROOT:joinpath("tests", "test_projects")

local function get_project_dir(venv_manager_name, project_type)
    return TEST_PROJECTS_DIR:joinpath(venv_manager_name, project_type)
end

local function setup_project(venv_manager_name, project_type)
    -- TODO: add support for other project types: script, monorepo etc.
    if project_type ~= "app" then
        error("Unsupported project type: " .. project_type)
        return
    end

    local setup_project_cmds

    if venv_manager_name == "uv" then
        setup_project_cmds = {
            { 'uv', 'init' },
            { 'uv', 'sync' },
        }
    elseif venv_manager_name == "poetry" then
        setup_project_cmds = {
            { 'poetry', 'init',    '--no-interaction' },
            { 'poetry', 'install', '--no-root' },
            { 'touch',  'main.py' },
        }
    elseif venv_manager_name == "builtin" then
        setup_project_cmds = {
            { 'python3', '-m',              'venv', '.venv' },
            { 'touch',   'main.py' },
            { 'touch',   'requirements.txt' },
        }
    elseif venv_manager_name == "pipenv" then
        setup_project_cmds = {
            { 'pipenv', 'install', '--python', '3.12' },
            { 'touch',  'main.py' },
        }
    elseif venv_manager_name == "pdm" then
        setup_project_cmds = {
            { 'pdm',   'init',   '--python', '3.12', '--non-interactive', '--no-git' },
            { 'pdm',   'install' },
            { 'touch', 'main.py' },
        }
    else
        error("Unknown VENV manager: " .. venv_manager_name)
        return
    end

    local project_dir = get_project_dir(venv_manager_name, project_type)

    if project_dir:exists() then
        print(string.format("Skipping setting up %s project using %s -- already exists", project_type, venv_manager_name))
        return
    end

    print(string.format("Setting up %s project using %s at %s", project_type, venv_manager_name, project_dir:expand()))
    vim.fn.mkdir(project_dir:expand(), "p")

    for _, cmd in ipairs(setup_project_cmds) do
        local result = vim.system(cmd, { text = true, cwd = project_dir:expand() }):wait()

        if result.code ~= 0 then
            local error_msg_parts = {
                "Failed to setup project",
                "\tVirtual environment manager: " .. venv_manager_name,
                "\tProject type: " .. project_type,
                "\tProject directory: " .. project_dir:expand(),
                "\tCommand: " .. vim.inspect(cmd),
                "\tError code: " .. result.code,
            }

            if result.stdout ~= "" then
                table.insert(error_msg_parts, "\tStdout: " .. result.stdout)
            end

            if result.stderr ~= "" then
                table.insert(error_msg_parts, "\tStderr: " .. result.stderr)
            end

            error(table.concat(error_msg_parts, "\n"))
            return
        end
    end
end

-- TODO: Use the list from auto-venv.venv_managers instead of duplicating it here
local supported_venv_managers = {
    "uv",
    "poetry",
    "pipenv",
    "pdm",
    "builtin",
}

local supported_project_types = {
    "app",
    -- "script",
    -- "monorepo",
}


for _, venv_manager_name in ipairs(supported_venv_managers) do
    for _, project_type in ipairs(supported_project_types) do
        setup_project(venv_manager_name, project_type)
    end
end

local make_assert_msg = function(main_msg, msg)
    if main_msg == nil then
        return msg
    end

    return main_msg .. ": " .. msg
end

local assert_path_equals = function(expected, actual, msg)
    if expected == nil then
        assert(actual == nil, make_assert_msg(msg, "expected path is nil but actual is not"))
        return
    end

    assert(actual ~= nil, make_assert_msg(msg, "actual path is nil"))
    assert(expected ~= nil, make_assert_msg(msg, "expected path is nil"))

    if type(actual) == "string" then
        actual = Path:new(actual)
    end

    if type(expected) == "string" then
        expected = Path:new(expected)
    end

    assert.equals(expected:expand(), actual:expand(), make_assert_msg(msg, "paths are not equal"))
end

describe("simple usage", function()
    it("works in uv app project", function()
        local project_dir = get_project_dir("uv", "app")
        local main_py_path = project_dir:joinpath("main.py"):expand()

        vim.cmd("e " .. main_py_path)

        local venv = auto_venv.get_python_venv(vim.api.nvim_get_current_buf())

        assert(venv ~= nil, "venv not found")
        assert.equals("uv", venv.venv_manager_name, "venv.manager_name")
        assert.equals("3.13", venv.python_version, "venv.python_version")
        assert.equals("app", venv.name, "venv.name")
        assert_path_equals(project_dir:joinpath(".venv"), venv.venv_path, "venv.venv_path")
        assert_path_equals(project_dir:joinpath(".venv", "bin"), venv.bin_path, "venv.bin_path")
        assert_path_equals(project_dir:joinpath(".venv", "bin", "python3"), venv.python_path, "venv.python_path")
        assert_path_equals(project_dir:joinpath("pyproject.toml"), venv.pyproject_toml, "venv.pyproject_toml")
    end)

    it("works in poetry app project", function()
        local project_dir = get_project_dir("poetry", "app")
        local main_py_path = project_dir:joinpath("main.py"):expand()

        vim.cmd("e " .. main_py_path)

        local venv = auto_venv.get_python_venv(vim.api.nvim_get_current_buf())

        local get_venv_dir_result = vim.system(
            { "poetry", "env", "info", "--project", project_dir:expand(), "--path" },
            { text = true }
        ):wait()
        local expected_venv_dir = Path:new(vim.trim(get_venv_dir_result.stdout))

        assert(venv ~= nil, "venv not found")
        assert.equals("Poetry", venv.venv_manager_name, "venv.manager_name")
        assert.equals("3.13", venv.python_version, "venv.python_version")
        assert.equals(vim.fn.fnamemodify(expected_venv_dir:expand(), ":t"), venv.name, "venv.name")
        assert_path_equals(expected_venv_dir, venv.venv_path, "venv.venv_path")
        assert_path_equals(expected_venv_dir:joinpath("bin"), venv.bin_path, "venv.bin_path")
        assert_path_equals(expected_venv_dir:joinpath("bin", "python"), venv.python_path, "venv.python_path")
        assert_path_equals(project_dir:joinpath("pyproject.toml"), venv.pyproject_toml, "venv.pyproject_toml")
    end)

    it("works in pipenv app project", function()
        local project_dir = get_project_dir("pipenv", "app")
        local main_py_path = project_dir:joinpath("main.py"):expand()

        vim.cmd("e " .. main_py_path)

        local venv = auto_venv.get_python_venv(vim.api.nvim_get_current_buf())

        local get_venv_dir_result = vim.system({ "pipenv", "--venv" }, { text = true, cwd = project_dir:expand() }):wait()
        local expected_venv_dir = Path:new(vim.trim(get_venv_dir_result.stdout))

        assert(venv ~= nil, "venv not found")
        assert.equals("Pipenv", venv.venv_manager_name, "venv.manager_name")
        assert.equals("3.12", venv.python_version, "venv.python_version")
        assert.equals("app", venv.name, "venv.name")
        assert_path_equals(expected_venv_dir, venv.venv_path, "venv.venv_path")
        assert_path_equals(expected_venv_dir:joinpath("bin"), venv.bin_path, "venv.bin_path")
        assert_path_equals(expected_venv_dir:joinpath("bin", "python"), venv.python_path, "venv.python_path")
        assert.is.Nil(venv.pyproject_toml, "venv.pyproject_toml")
    end)

    it("works in pdm app project", function()
        local project_dir = get_project_dir("pdm", "app")
        local main_py_path = project_dir:joinpath("main.py"):expand()

        vim.cmd("e " .. main_py_path)

        local venv = auto_venv.get_python_venv(vim.api.nvim_get_current_buf())

        local get_venv_dir_result = vim.system(
            { "pdm", "venv", "--path", "in-project" },
            { text = true, cwd = project_dir:expand() }
        ):wait()
        local expected_venv_dir = Path:new(vim.trim(get_venv_dir_result.stdout))

        assert(venv ~= nil, "venv not found")
        assert.equals("PDM", venv.venv_manager_name, "venv.manager_name")
        assert.equals("3.12", venv.python_version, "venv.python_version")
        assert.equals("app", venv.name, "venv.name")
        assert_path_equals(expected_venv_dir, venv.venv_path, "venv.venv_path")
        assert_path_equals(expected_venv_dir:joinpath("bin"), venv.bin_path, "venv.bin_path")
        assert_path_equals(expected_venv_dir:joinpath("bin", "python"), venv.python_path, "venv.python_path")
        assert_path_equals(project_dir:joinpath("pyproject.toml"), venv.pyproject_toml, "venv.pyproject_toml")
    end)

    it("works in builtin app project", function()
        local project_dir = get_project_dir("builtin", "app")
        local main_py_path = project_dir:joinpath("main.py"):expand()

        vim.cmd("e " .. main_py_path)

        local venv = auto_venv.get_python_venv(vim.api.nvim_get_current_buf())

        assert(venv ~= nil, "venv not found")
        assert.equals("Built-in venv manager (python -m venv)", venv.venv_manager_name, "venv.venv_manager_name")
        assert.equals("3.9", venv.python_version, "venv.python_version")
        assert.equals("app", venv.name, "venv.name")
        assert_path_equals(project_dir:joinpath(".venv"), venv.venv_path, "venv.venv_path")
        assert_path_equals(project_dir:joinpath(".venv", "bin"), venv.bin_path, "venv.bin_path")
        assert_path_equals(project_dir:joinpath(".venv", "bin", "python"), venv.python_path, "venv.python_path")
        assert.is.Nil(venv.pyproject_toml, "venv.pyproject_toml")
    end)

    it("applies venv to new python files", function()
        local project_dir = get_project_dir("builtin", "app")
        local file_path = project_dir:joinpath("new_file.py")
        assert.is.False(file_path:exists(), "new_file.py should not exist yet")

        vim.cmd("e " .. file_path:expand())
        local bufnr = vim.api.nvim_get_current_buf()

        assert.equals(vim.api.nvim_buf_get_name(bufnr), file_path:expand(), "Buffer name should match the new file path")

        local venv = auto_venv.get_python_venv(bufnr)

        assert(venv ~= nil, "venv not found")
        assert.equals("Built-in venv manager (python -m venv)", venv.venv_manager_name, "venv.venv_manager_name")
        assert.equals("app", venv.name, "venv.name")
        assert_path_equals(project_dir:joinpath(".venv"), venv.venv_path, "venv.venv_path")
    end)

    it("doesn't apply venv to a new unnamed file", function()
        vim.cmd.tabnew() -- Open a new unnamed buffer
        local bufnr = vim.api.nvim_get_current_buf()
        assert.equals(vim.api.nvim_buf_get_name(bufnr), "", "current buffer should not have a name")

        local venv = auto_venv.get_python_venv(bufnr)
        assert.is.Nil(venv, "venv should be nil for unnamed buffers")
    end)

    it("doesn't apply venv to nofile buffers", function()
        local project_dir = get_project_dir("builtin", "app")
        local file_path = project_dir:joinpath("some_name.py")
        vim.cmd.tabnew(file_path:expand())                  -- open a new buffer with a name
        vim.api.nvim_buf_set_option(0, 'buftype', 'nofile') -- Set the buffer type to nofile
        local bufnr = vim.api.nvim_get_current_buf()
        assert.equals(vim.api.nvim_buf_get_name(bufnr), file_path:expand(), "current buffer should have a name")

        local venv = auto_venv.get_python_venv(bufnr)
        assert.is.Nil(venv, "venv should be nil for nofile buffers")
    end)

    it("doesn't apply venv to non-python files", function()
        local project_dir = get_project_dir("builtin", "app")
        local file_path = project_dir:joinpath("some_name.lua")
        vim.cmd.edit(file_path:expand())
        local venv = auto_venv.get_python_venv(bufnr)
        assert.is.Nil(venv, "venv should be nil for non-python buffers")
    end)
end)
