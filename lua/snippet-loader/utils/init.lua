--[[
This module provides a Maker object containing different kinds of maker factory
function by
    local makers = M.snippet_makers()

and snippet makers are store as fields in makers table
    local sp = makers.sp

current basic makers are: sp, psp, asp, apsp.

By prefixing these names with `cond` and `reg`, you get conditional and regex
makers. For example we have `condsp`.

After all snippets are made with maker, one have to call finalize to add all
snippet into luasnip module.

    local utils = require "utils"
    utils.finalize()
]]
local ls = require "luasnip"
local ls_extra = require "luasnip.extras"

local fs = vim.fs
local loop = vim.loop
local config = require "snippet-loader.config"

local M = {
    t = ls.text_node,
    i = ls.insert_node,
    f = ls.function_node,
    c = ls.choice_node,
    s = ls.snippet_node,
    is = ls.indent_snippet_node,
    d = ls.dynamic_node,
    r = ls.restore_node,
    l = ls_extra.lambda,
    rep = ls_extra.rep,
    p = ls_extra.partial,
    m = ls_extra.match,
    n = ls_extra.nonempty,
    dl = ls_extra.dynamic_lambda,
    fmt = require("luasnip.extras.fmt").fmt,
    fmta = require("luasnip.extras.fmt").fmta,
    types = require("luasnip.util.types"),
    conds = require("luasnip.extras.expand_conditions"),
    conds_ext = require "snippet-loader.utils.cond",
}

-- ----------------------------------------------------------------------------

local pending_snippets_map = {}

---@type { [string]: boolean }
M.loaded_snippets_set = {}

local function maker_factory(maker, snip_table)
    return function(...)
        local sp = maker(...)
        table.insert(snip_table, sp)
    end
end

local function maker_factory_cond(maker, snip_table)
    return function(cond, trig, nodes)
        local sp = maker(trig, nodes)
        sp.condition = cond
        table.insert(snip_table, sp)
    end
end

local function maker_factory_reg(maker, snip_table)
    return function(trig, nodes)
        local sp = maker(trig, nodes)
        sp.regTrig = true
        table.insert(snip_table, sp)
    end
end

---@param filetype string
function M.snippet_makers(filetype)
    -- snippets are stored in tables before finalize
    local record = pending_snippets_map[filetype]
    if not record then
        record = {}
        pending_snippets_map[filetype] = record
    end

    local snippets = record.snippets
    if not snippets then
        snippets = {}
        record.snippets = snippets
    end

    local autosnippets = record.autosnippets
    if not autosnippets then
        autosnippets = {}
        record.autosnippets = autosnippets
    end

    local snip_tables = {
        [""] = snippets, a = autosnippets,
    }
    local base_makers = {
        sp = ls.snippet, psp = ls.parser.parse_snippet,
    }
    local factories = {
        [""] = maker_factory,
        cond = maker_factory_cond,
        reg = maker_factory_reg,
    }
    local makers = {}

    for maker_name, maker_func in pairs(base_makers) do
        for table_name, tbl in pairs(snip_tables) do
            for factory_name, factory in pairs(factories) do
                local name = factory_name .. table_name .. maker_name
                local maker = factory(maker_func, tbl)
                makers[name] = maker
            end
        end
    end

    return makers
end

-- ----------------------------------------------------------------------------

---@param dir string
---@return string[]? full_paths
local function listdir(dir)
    if vim.fn.isdirectory(dir) == 0 then return end

    local scan_data = loop.fs_scandir(dir)
    if not scan_data then return end

    local files = {}
    local filename = loop.fs_scandir_next(scan_data)
    while filename do
        table.insert(files, dir .. "/" .. filename)
        filename = loop.fs_scandir_next(scan_data)
    end

    return files
end

local function finalize()
    for filetype, record in pairs(pending_snippets_map) do
        ls.add_snippets(filetype, record.snippets)
        ls.add_snippets(filetype, record.autosnippets, { type = "autosnippets" })
        pending_snippets_map[filetype] = nil
    end
end

---@param filename string
function M.load_snip(filename)
    if M.loaded_snippets_set[filename] then return end

    if vim.fn.filereadable(filename) == 0 then return end

    xpcall(function()
        require(filename)
    end, function(err)
        local thread = coroutine.running()
        local traceback = debug.traceback(thread, err)
        vim.notify(traceback or err, vim.log.levels.WARN)
    end)
    finalize()

    M.loaded_snippets_set[filename] = true
end

function M.load_autoload()
    local snippet_dir = fs.normalize(config.root_path) .. "/auto-load"
    local files = listdir(snippet_dir)
    if not files then return end

    for _, filename in ipairs(files) do
        M.load_snip(filename)
    end
end

function M.init_lazy_load()
    local snippet_dir = fs.normalize(config.root_path) .. "/lazy-load"
    local files = listdir(snippet_dir)
    if not files then return end

    local lazyload_group = vim.api.nvim_create_augroup("user.snippets.lazy-load", { clear = true })

    for _, filename in ipairs(files) do
        local basename = fs.basename(filename)
        local filetype = vim.split(basename, ".", { plain = true })[1]
        vim.api.nvim_create_autocmd("FileType", {
            group = lazyload_group,
            pattern = {
                filetype,
                filetype .. ".*",
                "*." .. filetype,
                "*." .. filetype .. ".*",
            },
            callback = function() M.load_snip(filename) end,
        })
    end
end

function M.init_conditional_load()
    local snippet_dir = fs.normalize(config.root_path) .. "/conditional-load"
    local files = listdir(snippet_dir)
    if not files then return end

    local conditional_group = vim.api.nvim_create_augroup("user.snippets.conditional-load", { clear = true })

    for _, filename in ipairs(files) do
        local import_ok, module = xpcall(function()
            return require(filename)
        end, function(err)
            local thread = coroutine.running()
            local traceback = debug.traceback(thread, err)
            vim.notify(traceback or err, vim.log.levels.WARN)
        end)

        module = import_ok and module or {}

        local ok = xpcall(
            function()
                vim.validate {
                    event = { module.event, { "s", "t" } },
                    pattern = { module.pattern, { "s", "t" } },
                    cond_func = { module.cond_func, "f", true },
                    setup = { module.setup, "f" },
                }
            end,
            function(msg)
                msg = ("while loading '%s':\n    %s"):format(filename, msg)
                vim.notify(msg)
            end
        )

        if ok and module then
            vim.api.nvim_create_autocmd(module.event, {
                group = conditional_group,
                pattern = module.pattern,
                callback = function(info)
                    if module.cond_func and not module.cond_func(info) then
                        return
                    end
                    module.setup()
                    finalize()
                end,
            })
        end
    end
end

-- Substitute jump index/string in snippet table with string in given translation table.
---@param row string | number | SnippetNodeInfoTable
---@param translate table<number | string, string>
---@return string | number | SnippetNodeInfoTable
function M.snippet_row_substitute(row, translate)
    local result = nil

    if translate[row] then
        result = translate[row]
    elseif type(row) == 'table' then
        result = {}
        for _, element in ipairs(row) do
            local new_element = M.snippet_row_substitute(element, translate)
            table.insert(result, new_element)
        end
    end

    return result or row
end

---@param snippet_tbl SnippetNodeInfoTable[]
---@param translate table<number | string, string>
---@return SnippetNodeInfoTable[]
function M.snippet_tbl_substitute(snippet_tbl, translate)
    local result = {}

    for _, row in ipairs(snippet_tbl) do
        local new_row = M.snippet_row_substitute(row, translate)
        table.insert(result, new_row)
    end

    return result
end

return M
