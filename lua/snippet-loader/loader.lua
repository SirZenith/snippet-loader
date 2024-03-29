local config = require "snippet-loader.config"
local util = require "snippet-loader.utils"

local fs = vim.fs
local loop = vim.loop

local M = {}

-- Recording loaded snippet module name
---@type { [string]: boolean }
M.loaded_snippets_set = {}

local lazyload_initialized = false
local pending_filetype_event = nil ---@type string[]?
-- Map filetype to pending snippet modules
---@type table<string, string[]>
M.filetype_dict = {}

---@param dir string
---@param callback fun(err: string?, full_paths: string[]?)
local function listdir(dir, callback)
    if vim.fn.isdirectory(dir) == 0 then
        callback(dir .. " is not a directory")
    end

    callback = vim.schedule_wrap(callback)

    loop.fs_scandir(dir, function(err, data)
        if err or not data then
            callback(err or ("failed to read directory " .. dir))
            return
        end

        local entries = {}
        local name = loop.fs_scandir_next(data)
        while name do
            table.insert(entries, dir .. "/" .. name)
            name = loop.fs_scandir_next(data)
        end

        callback(nil, entries)
    end)
end

-- load module with absolute path
local function require_absolute(module_name)
    local errmsg = { "" }
    local err_template = "no file '%s' (absolute path loader)"

    local paths = {
        module_name,
        module_name .. ".lua",
        module_name .. "/init.lua",
    }

    for _, filename in ipairs(paths) do
        if vim.fn.filereadable(filename) == 1 then
            local file = io.open(filename, "rb")
            if file then
                local content = assert(file:read("*a"))
                return assert(loadstring(content, filename))
            end
        end
        table.insert(errmsg, err_template:format(filename))
    end

    error(table.concat(errmsg, "\n\t"))
end

---@param module_name string
function M.load_snip(module_name)
    if M.loaded_snippets_set[module_name] then return end

    local ok, module = xpcall(
        require_absolute,
        function(err)
            err = debug.traceback(err) or err
            vim.notify("error occured while loading snippet\n" .. err, vim.log.levels.WARN)
        end,
        module_name
    )
    if ok then
        module()
    end

    util.finalize()

    M.loaded_snippets_set[module_name] = true
end

---@param filetype string
function M.try_load_snip_by_filetype(filetype)
    if not lazyload_initialized then
        pending_filetype_event = pending_filetype_event or {}
        pending_filetype_event[#pending_filetype_event + 1] = filetype
    end

    local types = vim.split(filetype, ".", { plain = true })
    for _, type in ipairs(types) do
        local names = M.filetype_dict[type]
        M.filetype_dict[type] = nil

        if names then
            for _, name in ipairs(names) do
                M.load_snip(name)
            end
        end
    end
end

function M.load_autoload()
    local snippet_dir = fs.normalize(config.root_path) .. "/auto-load"
    snippet_dir = vim.fn.fnamemodify(snippet_dir, ":p")

    listdir(snippet_dir, function(err, entries)
        if err or not entries then
            vim.notify(err or "failed to load auto-load snippets", vim.log.levels.WARN)
            return
        end

        for _, module_name in ipairs(entries) do
            M.load_snip(module_name)
        end
    end)
end

-- Setup filetype autocommand for loading snippet in `lazy-load` directory. All
-- snippet under lazy-load directory should have their target file type in file
-- name. Loader will create auto event using the part before first `.` in their
-- file name as target filetype.
function M.init_lazy_load()
    local snippet_dir = fs.normalize(config.root_path) .. "/lazy-load"
    snippet_dir = vim.fn.fnamemodify(snippet_dir, ":p")

    local lazyload_group = vim.api.nvim_create_augroup("snippet-loader.lazy-load", { clear = true })

    vim.api.nvim_create_autocmd("FileType", {
        group = lazyload_group,
        callback = function(args)
            M.try_load_snip_by_filetype(args.match)
        end,
    })

    listdir(snippet_dir, function(err, entries)
        if err or not entries then
            vim.notify(err or "failed to load lazy-load info", vim.log.levels.WARN)
            return
        end

        local dict = M.filetype_dict
        for _, module_name in ipairs(entries) do
            local basename = fs.basename(module_name)
            local filetype = vim.split(basename, ".", { plain = true })[1]
            local names = dict[filetype]
            if not names then
                names = {}
                dict[filetype] = names
            end

            names[#names + 1] = module_name
        end

        lazyload_initialized = true
        if pending_filetype_event then
            for _, filetype in ipairs(pending_filetype_event) do
                M.try_load_snip_by_filetype(filetype);
            end
            pending_filetype_event = nil
        end
    end)
end

-- Load conditional snippet and setup autocommand by infomation provided in
-- snippet module.
function M.init_conditional_load()
    local snippet_dir = fs.normalize(config.root_path) .. "/conditional-load"
    snippet_dir = vim.fn.fnamemodify(snippet_dir, ":p")

    listdir(snippet_dir, function(load_err, entries)
        if load_err or not entries then
            vim.notify(load_err or "failed to conditional-load info", vim.log.levels.WARN)
            return
        end

        local conditional_group = vim.api.nvim_create_augroup("snippet-loader.conditional-load", { clear = true })

        for _, module_name in ipairs(entries) do
            local import_ok, result = xpcall(
                require_absolute,
                function(err)
                    err = debug.traceback(err) or err
                    vim.notify(err, vim.log.levels.WARN)
                end,
                module_name
            )

            local module = import_ok and result() or {}

            local ok = xpcall(
                vim.validate,
                function(msg)
                    msg = ("while loading '%s':\n    %s"):format(module_name, msg)
                    vim.notify(msg, vim.log.levels.WARN)
                end,
                {
                    event = { module.event, { "s", "t" } },
                    pattern = { module.pattern, { "s", "t" } },
                    cond_func = { module.cond_func, "f", true },
                    setup = { module.setup, "f" },
                }
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
                        util.finalize()
                    end,
                })
            end
        end
    end)
end

return M
