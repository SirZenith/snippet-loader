local M = {}

---@alias CondFunc fun(line: string, trig: string, captures: string[]): boolean
---@alias CondTab { func: CondFunc }
---@alias Condition CondFunc | CondTab

-- ----------------------------------------------------------------------------

---@type fun(a: Condition, b: Condition): CondFunc
M.and_ = function(a, b)
    return function(line, trig, captures)
        return a(line, trig, captures) and b(line, trig, captures)
    end
end

---@type fun(a: Condition, b: Condition): CondFunc
M.or_ = function(a, b)
    return function(line, trig, captures)
        return a(line, trig, captures) or b(line, trig, captures)
    end
end

---@type fun(a: Condition, b: Condition): CondFunc
M.not_ = function(a)
    return function(line, trig, captures)
        return not a(line, trig, captures)
    end
end

-- ----------------------------------------------------------------------------

local WHITE_SPACE = " \t\r\n\v\f"

-- check if there are only spaces before cursor at current line
---@type CondFunc
M.line_begin_smart = function(line, trig)
    return line:sub(1, #line - #trig):match("^%s*$") ~= nil
end

return M
