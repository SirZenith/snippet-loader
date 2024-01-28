local config = require "snippet-loader.config"
local loader = require "snippet-loader.loader"
local utils = require "snippet-loader.utils"

local M = {}

vim.api.nvim_create_user_command("SnipList", function()
    local buffer = {}
    for filename in pairs(utils.loaded_snippets_set) do
        local basename = vim.fs.basename(filename)
        local name = basename:sub(-4) == ".lua"
            and basename:sub(1, -5)
            or basename
        table.insert(buffer, name)
    end

    table.sort(buffer)
    local msg = table.concat(buffer, "\n")
    vim.notify(msg)
end, {
    desc = "list all loaded snippets"
})

function M.setup(option)
    for k, v in pairs(vim.deepcopy(option)) do
        config[k] = v
    end

    loader.load_autoload()
    loader.init_lazy_load()
    loader.init_conditional_load()
end

return M
