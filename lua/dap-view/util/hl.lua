local state = require("dap-view.state")
local globals = require("dap-view.globals")
local mirror = require("dap-view.util.mirror")

local M = {}

---@param hl_group string
---@param start [integer,integer]
---@param finish [integer,integer]
---@param bufnr integer?
---@param opts vim.hl.range.Opts?
M.hl_range = function(hl_group, start, finish, bufnr, opts)
    vim.hl.range(bufnr or state.bufnr, globals.NAMESPACE, "NvimDapView" .. hl_group, start, finish, opts)

    mirror.notify()
end

---The type highlight runs to the end of the line, so the ellipsis needs to sit above it
M.ELLIPSIS_OPTS = { priority = vim.hl.priorities.user + 1 }

---Byte column where the trailing ellipsis of a clamped line starts
---@param content string The rendered line
---@return integer
M.ellipsis_col = function(content)
    return math.max(#content - #require("dap-view.setup").config.tree.ellipsis, 0)
end

M.types_to_hl_group = {
    boolean = "Boolean",
    bool = "Boolean",
    str = "String",
    string = "String",
    int = "Number",
    long = "Number",
    number = "Number",
    double = "Float",
    float = "Float",
    -- debugpy's "None"
    nonetype = "Constant",
    undefined = "Constant",
    ["nil"] = "Constant",
    ["function"] = "Function",
    asyncfunction = "Function",
}

---@param v dap.Variable|dap.EvaluateResponse
M.hl_from_variable = function(v)
    local hl = v.type and M.types_to_hl_group[v.type:lower()]

    if
        globals.HAS_0_12
        and hl
        and v.presentationHint
        and vim.tbl_contains(v.presentationHint.attributes or {}, "readOnly")
    then
        hl = hl .. "Dim"
    end

    return hl
end

return M
