local globals = require("dap-view.globals")

local api = vim.api

local M = {}

---The `links` theme: every group links to a stock group
local LINKS = {
    MissingData = "DapBreakpoint",
    FileName = "qfFileName",
    LineNumber = "qfLineNr",
    Separator = "Comment",

    Thread = "Tag",
    ThreadStopped = "Conditional",
    ThreadError = "DiagnosticError",

    FrameCurrent = "DiagnosticVirtualTextWarn",

    ExceptionFilterEnabled = "DiagnosticOk",
    ExceptionFilterDisabled = "DiagnosticError",

    Tab = "TabLine",
    TabSeparator = "NvimDapViewTab",
    TabSelected = "TabLineSel",
    TabSelectedSeparator = "NvimDapViewTabSelected",
    TabFill = "TabLineFill",

    ControlNC = "Comment",
    ControlPlay = "Keyword",
    ControlPause = "Boolean",
    ControlStepInto = "Function",
    ControlStepOut = "Function",
    ControlStepOver = "Function",
    ControlStepBack = "Function",
    ControlRunLast = "Keyword",
    ControlTerminate = "DapBreakpoint",
    ControlDisconnect = "DapBreakpoint",

    WatchExpr = "Identifier",
    WatchError = "DiagnosticError",
    WatchUpdated = "DiagnosticVirtualTextWarn",
    WatchUpdatedName = "DiagnosticWarn",
    Truncated = "Comment",
    VariableInternal = "Comment",

    SectionHeader = "NvimDapViewThread",
    Raw = "Comment",
    Decoded = "Function",
    Panel = "Normal",

    Boolean = "Boolean",
    String = "String",
    Number = "Number",
    Float = "Float",
    Function = "Function",
    Constant = "Constant",
}

local TYPES = {
    Boolean = "boolean",
    String = "string",
    Number = "number",
    Float = "float",
    Function = "function",
    Constant = "constant",
}

---@alias dapview.HlSpecs table<string, vim.api.keyset.highlight[]> Applied in order to each group

---@return dapview.HlSpecs
local links = function()
    ---@type dapview.HlSpecs
    local specs = {}

    for name, link in pairs(LINKS) do
        specs[name] = { { default = true, link = link } }
    end

    if globals.HAS_0_12 then
        local dim = { dim = true, update = true }

        specs.VirtualText = { { default = true, link = "NonText" } }
        specs.VirtualTextUpdated = { { default = true, link = "NvimDapViewWatchUpdated" }, dim }

        for name in pairs(TYPES) do
            specs[name .. "Dim"] = { { default = true, link = name }, dim }
        end
    end

    return specs
end

---@param roles dapview.ThemeRoles
---@param transparent boolean
---@return dapview.HlSpecs
local from_roles = function(roles, transparent)
    local themes = require("dap-view.themes")

    -- The selected tab keeps its chip; every other surface follows the editor
    local surface = not transparent and roles.panel or nil
    local tint = function(color)
        return surface and themes.blend(color, surface, 0.16) or nil
    end

    ---@type table<string, vim.api.keyset.highlight>
    local groups = {
        MissingData = { fg = roles.error },
        FileName = { fg = roles.accent },
        LineNumber = { fg = roles.muted },
        Separator = { fg = roles.muted },

        Thread = { fg = roles.accent },
        ThreadStopped = { fg = roles.warn, bold = true },
        ThreadError = { fg = roles.error },

        FrameCurrent = { bg = roles.selection, bold = true },

        ExceptionFilterEnabled = { fg = roles.ok },
        ExceptionFilterDisabled = { fg = roles.error },

        Tab = { fg = roles.muted, bg = surface },
        TabSeparator = { link = "NvimDapViewTab" },
        TabSelected = { fg = roles.selected.fg, bg = roles.selected.bg, bold = true },
        TabSelectedSeparator = { link = "NvimDapViewTabSelected" },
        TabFill = { bg = surface },

        ControlNC = { fg = roles.muted, bg = surface },
        ControlPlay = { fg = roles.ok, bg = surface },
        ControlPause = { fg = roles.warn, bg = surface },
        ControlStepInto = { fg = roles.accent, bg = surface },
        ControlStepOut = { fg = roles.accent, bg = surface },
        ControlStepOver = { fg = roles.accent, bg = surface },
        ControlStepBack = { fg = roles.accent, bg = surface },
        ControlRunLast = { fg = roles.ok, bg = surface },
        ControlTerminate = { fg = roles.error, bg = surface },
        ControlDisconnect = { fg = roles.error, bg = surface },

        WatchExpr = { fg = roles.fg },
        WatchError = { fg = roles.error },
        WatchUpdated = { fg = roles.changed, bg = tint(roles.changed), bold = true },
        WatchUpdatedName = { fg = roles.changed, bold = true },
        Truncated = { fg = roles.muted },
        VariableInternal = { fg = roles.muted },

        SectionHeader = { fg = roles.header, bold = true },
        Raw = { fg = roles.raw },
        Decoded = { fg = roles.decoded, bold = true },
        Panel = { fg = roles.fg, bg = surface },
    }

    for name, role in pairs(TYPES) do
        groups[name] = { fg = roles[role] }
    end

    if globals.HAS_0_12 then
        groups.VirtualText = { fg = roles.muted }
        groups.VirtualTextUpdated = { fg = roles.changed }

        -- Read-only values: blended towards muted, so the meaning survives terminals without `dim`
        for name, role in pairs(TYPES) do
            groups[name .. "Dim"] = { fg = themes.blend(roles[role], roles.muted, 0.5) }
        end
    end

    ---@type dapview.HlSpecs
    local specs = {}
    for name, opts in pairs(groups) do
        opts.default = true
        specs[name] = { opts }
    end
    return specs
end

---What this module last wrote to each group, read back. A group that no longer matches
---was redefined by the user or the colorscheme, which always win.
---@type table<string, table>
local written = {}

---`:hi clear` brings back the last `default` link a group had, even after other attributes
---replaced it, so that link is ours too
---@type table<string, table>
local restored = {}

---A colorscheme's `:hi clear` can reload the default colorscheme mid-switch and drop the
---`default` flag from what it re-applies, so ownership ignores that flag
---@param name string
local read = function(name)
    local hl = api.nvim_get_hl(0, { name = name })
    hl.default = nil
    return hl
end

---@param name string
---@param specs vim.api.keyset.highlight[]
local set = function(name, specs)
    local full = globals.HL_PREFIX .. name
    local current = read(full)

    if
        not vim.tbl_isempty(current)
        and not vim.deep_equal(current, written[full])
        and not vim.deep_equal(current, restored[full])
    then
        return
    end

    -- `default = true` alone never replaces an existing definition, including our previous one
    for i, opts in ipairs(specs) do
        api.nvim_set_hl(0, full, i == 1 and vim.tbl_extend("force", opts, { force = true }) or opts)
    end

    written[full] = read(full)
    if specs[1].link then
        restored[full] = { link = specs[1].link }
    end
end

---Whether groups come from theme roles rather than the `links` theme.
---Roles carry GUI colors only, so without 'termguicolors' the links stay in charge.
---@return boolean
M.themed = function()
    return require("dap-view.setup").config.theme ~= "links" and vim.o.termguicolors
end

---The roles currently in effect, or `nil` for the `links` theme
---@return dapview.ThemeRoles?, dapview.ThemeContext?
M.roles = function()
    if not M.themed() then
        return nil
    end
    local config = require("dap-view.setup").config
    local themes = require("dap-view.themes")
    local ctx = themes.context(config.transparent)
    return themes.resolve(config, ctx), ctx
end

---(Re)define every group from the configured theme
M.apply = function()
    local specs = links()

    local roles, ctx = M.roles()
    if roles and ctx then
        specs = vim.tbl_extend("force", specs, from_roles(roles, ctx.transparent))
    end

    -- An `update` resolves the link it extends, so the groups it links to must exist first
    for _, pass in ipairs({ false, true }) do
        for name, group_specs in vim.spairs(specs) do
            if (#group_specs > 1) == pass then
                set(name, group_specs)
            end
        end
    end
end

M.apply()

api.nvim_create_autocmd("ColorScheme", {
    callback = M.apply,
})

api.nvim_create_autocmd("OptionSet", {
    pattern = "termguicolors",
    callback = M.apply,
})

return M
