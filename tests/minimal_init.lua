local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
if vim.fn.isdirectory(plenary_dir) == 0 then
    vim.fn.system({ "git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir })
end

-- TODO: Remove me when dependency on project.nvim is removed
local project_nvim_dir = os.getenv("PROJECT_NVIM_DIR") or "/tmp/project.nvim"
if vim.fn.isdirectory(project_nvim_dir) == 0 then
    vim.fn.system({ "git", "clone", "https://github.com/ahmedkhalf/project.nvim", project_nvim_dir })
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

-- TODO: Remove me when dependency on project.nvim is removed
vim.opt.rtp:append(project_nvim_dir)

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
