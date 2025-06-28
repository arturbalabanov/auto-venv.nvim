---@diagnostic disable: undefined-global
---@diagnostic disable: undefined-field
-- https://github.com/nvim-lua/plenary.nvim/blob/master/TESTS_README.md
-- https://github.com/lunarmodules/luassert

local Path = require("plenary.path")

-- TODO: maybe move (some of) this to the minimal_init.lua
local auto_venv = require("auto-venv")
local venv_managers = require("auto-venv.venv_managers")

assert(auto_venv ~= nil, "auto-venv should be loaded")
auto_venv.setup({ debug = false })

local PROJECT_ROOT = Path:new(vim.fn.fnamemodify(debug.getinfo(1, "Sl").source:sub(2), ":h:h:h"))
local TEST_PROJECTS_DIR = PROJECT_ROOT:joinpath("tests", "test_projects")

local function get_project_dir(venv_manager_id, project_type)
    return TEST_PROJECTS_DIR:joinpath(venv_manager_id, project_type)
end

local function setup_project(venv_manager_id, project_type)
    -- TODO: add support for other project types: script, monorepo etc.
    if project_type ~= "app" then
        error("Unsupported project type: " .. project_type)
        return
    end

    local setup_project_cmds

    if venv_manager_id == "uv" then
        setup_project_cmds = {
            { 'uv', 'init', '--vcs', 'none' },
            { 'uv', 'sync' },
        }
    elseif venv_manager_id == "poetry" then
        setup_project_cmds = {
            { 'poetry', 'init',    '--no-interaction' },
            { 'poetry', 'install', '--no-root' },
            { 'touch',  'main.py' },
        }
    elseif venv_manager_id == "builtin" then
        setup_project_cmds = {
            { 'python3', '-m',              'venv', '.venv' },
            { 'touch',   'main.py' },
            { 'touch',   'requirements.txt' },
        }
    elseif venv_manager_id == "pipenv" then
        setup_project_cmds = {
            { 'pipenv', 'install', '--python', '3.12' },
            { 'touch',  'main.py' },
        }
    elseif venv_manager_id == "pdm" then
        setup_project_cmds = {
            { 'pdm',   'init',   '--python', '3.12', '--non-interactive', '--no-git' },
            { 'pdm',   'install' },
            { 'touch', 'main.py' },
        }
    else
        error("Unknown VENV manager: " .. venv_manager_id)
        return
    end

    local project_dir = get_project_dir(venv_manager_id, project_type)

    if project_dir:exists() then
        print(string.format("Skipping setting up %s project using %s -- already exists", project_type, venv_manager_id))
        return
    end

    print(string.format("Setting up %s project using %s at %s", project_type, venv_manager_id, project_dir:expand()))
    vim.fn.mkdir(project_dir:expand(), "p")

    for _, cmd in ipairs(setup_project_cmds) do
        local result = vim.system(cmd, { text = true, cwd = project_dir:expand() }):wait()

        if result.code ~= 0 then
            local error_msg_parts = {
                "Failed to setup project",
                "\tVirtual environment manager: " .. venv_manager_id,
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

-- TODO: Add MOAR!!
local supported_project_types = {
    "app",
    -- "script",
    -- "monorepo",
}


for venv_manager_id, _ in pairs(venv_managers.all_venv_managers) do
    for _, project_type in ipairs(supported_project_types) do
        setup_project(venv_manager_id, project_type)
    end
end

local make_assert_msg = function(main_msg, msg)
    if main_msg == nil then
        return msg
    end

    return main_msg .. ": " .. msg
end

local assert_path_equals = function(expected, actual, msg, opts)
    opts = opts or {}

    if opts.follow_symlinks == nil then
        opts.follow_symlinks = false
    end

    if expected == nil then
        assert.is.Nil(actual, make_assert_msg(msg, "expected path is nil but actual is not"))
        return
    end

    assert.is.Not.Nil(expected, make_assert_msg(msg, "expected path is nil"))
    assert.is.Not.Nil(actual, make_assert_msg(msg, "actual path is nil"))

    if type(expected) == "string" then
        expected = Path:new(expected)
    end

    expected = expected:expand()

    if type(actual) == "string" then
        actual = Path:new(actual)
    end

    actual = actual:expand()

    if opts.follow_symlinks then
        expected = vim.loop.fs_realpath(expected)
        actual = vim.loop.fs_realpath(actual)
    end

    assert.equals(expected, actual, make_assert_msg(msg, "paths are not equal"))
end

describe("venv manager detection", function()
    for venv_manager_id, venv_manager in pairs(venv_managers.all_venv_managers) do
        it("works in " .. venv_manager_id .. " app project", function()
            local project_dir = get_project_dir(venv_manager_id, "app")
            local main_py_path = project_dir:joinpath("main.py"):expand()

            vim.cmd("e " .. main_py_path)

            local venv = auto_venv.get_python_venv(vim.api.nvim_get_current_buf())

            assert(venv ~= nil, "venv not found")
            assert.equals(venv_manager.name, venv.venv_manager_name,
                "venv.venv_manager_name doesn't match the expected name")

            assert.equals(project_dir:expand(), venv.project_root,
                "venv.project_root doesn't match the project directory")

            -- NOTE: poetry names its virtual enviroments like this: app-oFWtJehf-py3.11, thus the weird check bellow
            --       we need to add a poetry-specific test to check for that but for now checking that it starts with
            --       app is good enough
            assert.equals("app", venv.name:match("^(app).*$"), "venv.name doesn't match the expected name")

            local actual_venv_path = Path:new(venv.venv_path)
            assert.is.True(actual_venv_path:exists() and actual_venv_path:is_dir(),
                "venv.venv_path is not a valid directory")

            local actual_bin_path = Path:new(venv.bin_path)
            assert_path_equals(actual_venv_path:joinpath("bin"), venv.bin_path,
                "venv.bin_path is a subdirectory of venv_path")
            assert.is.True(actual_bin_path:exists() and actual_bin_path:is_dir(),
                "venv.bin_path is not a valid directory")

            assert_path_equals(actual_venv_path:joinpath("bin", "python"), venv.python_path,
                "venv.python_path doesn't match the bin/python path in the venv",
                { follow_symlinks = true })

            local pyproject_toml = project_dir:joinpath("pyproject.toml")

            if not pyproject_toml:exists() then
                assert.is.Nil(venv.pyproject_toml, "venv.pyproject_toml should be nil as pyproject.toml does not exist")
            else
                assert_path_equals(project_dir:joinpath("pyproject.toml"), venv.pyproject_toml,
                    "venv.pyproject_toml doesn't match the pyproject.toml file in the project")
            end

            local python_version_res = vim.system({ venv.python_path, "--version" }, { text = true }):wait()

            if python_version_res.code ~= 0 then
                error("Failed to get Python version: " .. python_version_res.stderr)
            end

            local actual_python_version = python_version_res.stdout:match("Python%s+(%d+%.%d+)")

            assert.equals(actual_python_version, venv.python_version,
                "venv.python_version doesn't match the version of the python binary")

            local pin_python_version_file = project_dir:joinpath(".python-version")

            if pin_python_version_file:exists() then
                local pinned_python_version = vim.trim(pin_python_version_file:read())
                assert.equals(
                    pinned_python_version,
                    venv.python_version,
                    "Contents of .python-version file does not match venv.python_version"
                )
            end
        end)
    end
end)

describe("venv file detection", function()
    it("is applied for new python files", function()
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

    it("is not applied for a new unnamed file", function()
        vim.cmd.tabnew() -- Open a new unnamed buffer
        local bufnr = vim.api.nvim_get_current_buf()
        assert.equals(vim.api.nvim_buf_get_name(bufnr), "", "current buffer should not have a name")

        local venv = auto_venv.get_python_venv(bufnr)
        assert.is.Nil(venv, "venv should be nil for unnamed buffers")
    end)

    it("is not applied for nofile buffers", function()
        local project_dir = get_project_dir("builtin", "app")
        local file_path = project_dir:joinpath("some_name.py")
        vim.cmd.tabnew(file_path:expand())                  -- open a new buffer with a name
        vim.api.nvim_buf_set_option(0, 'buftype', 'nofile') -- Set the buffer type to nofile
        local bufnr = vim.api.nvim_get_current_buf()
        assert.equals(vim.api.nvim_buf_get_name(bufnr), file_path:expand(), "current buffer should have a name")

        local venv = auto_venv.get_python_venv(bufnr)
        assert.is.Nil(venv, "venv should be nil for nofile buffers")
    end)

    -- TODO: Eventually we want to remove this test as we want to still apply the venv for non-python files
    it("is not applied for non-python files", function()
        local project_dir = get_project_dir("builtin", "app")
        local file_path = project_dir:joinpath("some_name.lua")
        vim.cmd.edit(file_path:expand())
        local venv = auto_venv.get_python_venv(bufnr)
        assert.is.Nil(venv, "venv should be nil for non-python buffers")
    end)
end)
