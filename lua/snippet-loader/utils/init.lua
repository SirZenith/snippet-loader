local ls = require "luasnip"
local ls_extra = require "luasnip.extras"

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

---@class snippet-loader.LuaSnipNode

---@class snippet-loader.LuaSnipSnippet
---@field condition boolean
---@field regTrig boolean

---@alias snippet-loader.SnipMakerFunc fun(...: any)

---@class snippet-loader.SnipRecord
---@field snippets snippet-loader.LuaSnipSnippet[]
---@field autosnippets snippet-loader.LuaSnipSnippet[]

---@class snippet-loader.SnipMaker
---@field sp snippet-loader.SnipMakerFunc
---@field psp snippet-loader.SnipMakerFunc
---@field asp snippet-loader.SnipMakerFunc
---@field apsp snippet-loader.SnipMakerFunc
--
---@field condsp snippet-loader.SnipMakerFunc
---@field condpsp snippet-loader.SnipMakerFunc
---@field condasp snippet-loader.SnipMakerFunc
---@field condapsp snippet-loader.SnipMakerFunc
--
---@field regsp snippet-loader.SnipMakerFunc
---@field regpsp snippet-loader.SnipMakerFunc
---@field regasp snippet-loader.SnipMakerFunc
---@field regapsp snippet-loader.SnipMakerFunc

-- ----------------------------------------------------------------------------

-- Recording snippet record for each file type.
---@type table<string, snippet-loader.SnipRecord>
local pending_snippets_map = {}

---@param filetype string
---@return snippet-loader.SnipRecord
local function get_snippet_record_for_filetype(filetype)
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

    return record
end

---@param maker fun(...: any): snippet-loader.LuaSnipSnippet
---@param snip_table snippet-loader.LuaSnipSnippet[]
---@return fun(...: any)
local function maker_factory(maker, snip_table)
    return function(...)
        local sp = maker(...)
        table.insert(snip_table, sp)
    end
end

---@param maker fun(...: any): snippet-loader.LuaSnipSnippet
---@param snip_table snippet-loader.LuaSnipSnippet[]
---@return fun(...: any)
local function maker_factory_cond(maker, snip_table)
    return function(cond, trig, nodes)
        local sp = maker(trig, nodes)
        sp.condition = cond
        table.insert(snip_table, sp)
    end
end

---@param maker fun(...: any): snippet-loader.LuaSnipSnippet
---@param snip_table snippet-loader.LuaSnipSnippet[]
---@return fun(...: any)
local function maker_factory_reg(maker, snip_table)
    return function(trig, nodes)
        local sp = maker(trig, nodes)
        sp.regTrig = true
        table.insert(snip_table, sp)
    end
end

---@param filetype string
---@return snippet-loader.SnipMaker
function M.snippet_makers(filetype)
    local record = get_snippet_record_for_filetype(filetype)

    local base_makers = {
        sp = ls.snippet,
        psp = ls.parser.parse_snippet,
    }

    local snip_tables = {
        [""] = record.snippets,
        a = record.autosnippets,
    }

    local factories = {
        [""] = maker_factory,
        cond = maker_factory_cond,
        reg = maker_factory_reg,
    }

    local makers = {}

    -- insert maker keys by making cartesian product of table keys.
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

-- Load snippets created by snippet makers into LuaSnip
function M.finalize()
    for filetype, record in pairs(pending_snippets_map) do
        ls.add_snippets(filetype, record.snippets)
        ls.add_snippets(filetype, record.autosnippets, { type = "autosnippets" })
        pending_snippets_map[filetype] = nil
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
