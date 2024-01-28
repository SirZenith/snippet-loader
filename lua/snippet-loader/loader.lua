local config = require "snippet-loader.config"
local util = require "snippet-loader.utils"

local fs = vim.fs
local loop = vim.loop

local M = {}

-- Recording loaded snippet module name
---@type { [string]: boolean }
M.loaded_snippets_set = {}

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

---@param module_name string
function M.load_snip(module_name)
    if M.loaded_snippets_set[module_name] then return end

    xpcall(
        require,
        function(err)
            err = debug.traceback(err) or err
            vim.notify(err, vim.log.levels.WARN)
        end,
        module_name
    )

    util.finalize()

    M.loaded_snippets_set[module_name] = true
end

function M.load_autoload()
    local snippet_dir = fs.normalize(config.root_path) .. "/auto-load"
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
    listdir(snippet_dir, function(err, entries)
        if err or not entries then
            vim.notify(err or "failed to load lazy-load info", vim.log.levels.WARN)
            return
        end

        local lazyload_group = vim.api.nvim_create_augroup("snippet-loader.lazy-load", { clear = true })

        for _, module_name in ipairs(entries) do
            local basename = fs.basename(module_name)
            local filetype = vim.split(basename, ".", { plain = true })[1]

            vim.api.nvim_create_autocmd("FileType", {
                group = lazyload_group,
                pattern = {
                    filetype,
                    filetype .. ".*",
                    "*." .. filetype,
                    "*." .. filetype .. ".*",
                },
                callback = function() M.load_snip(module_name) end,
            })
        end
    end)
end

-- Load conditional snippet and setup autocommand by infomation provided in
-- snippet module.
function M.init_conditional_load()
    local snippet_dir = fs.normalize(config.root_path) .. "/conditional-load"
    listdir(snippet_dir, function(load_err, files)
        if load_err or not files then
            vim.notify(load_err or "failed to conditional-load info", vim.log.levels.WARN)
            return
        end

        local conditional_group = vim.api.nvim_create_augroup("snippet-loader.conditional-load", { clear = true })

        for _, module_name in ipairs(files) do
            local import_ok, module = xpcall(
                require,
                function(err)
                    err = debug.traceback(err) or err
                    vim.notify(err, vim.log.levels.WARN)
                end,
                module_name
            )

            module = import_ok and module or {}

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
