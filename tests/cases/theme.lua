-- Theme roles, providers, precedence and transparency
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")

vim.o.termguicolors = true

H.setup({ host = { default = os.getenv("HOST") or "tab" } })

local highlight = require("dap-view.highlight")
local themes = require("dap-view.themes")

local get = function(name)
    return vim.api.nvim_get_hl(0, { name = "NvimDapView" .. name })
end

local hex = function(color)
    return tonumber(color:sub(2), 16)
end

local ROLES = {
    "fg",
    "muted",
    "panel",
    "selection",
    "accent",
    "ok",
    "warn",
    "error",
    "changed",
    "raw",
    "decoded",
    "header",
    "string",
    "number",
    "float",
    "boolean",
    "constant",
    "function",
}

local check_roles = function(colorscheme)
    local roles = highlight.roles()
    local missing = {}
    for _, role in ipairs(ROLES) do
        if type(roles[role]) ~= "string" then
            missing[#missing + 1] = role
        end
    end
    if not (roles.selected and roles.selected.fg and roles.selected.bg) then
        missing[#missing + 1] = "selected"
    end
    H.eq(missing, {}, colorscheme .. ": every role is derived")
    H.eq(get("TabFill").bg, hex(roles.panel), colorscheme .. ": winbar fill uses the panel role")
    H.ok(get("ControlTerminate").fg ~= nil, colorscheme .. ": terminate control is visible")
end

H.group("auto derives roles from the active colorscheme")
vim.cmd.colorscheme("habamax")
check_roles("habamax")
-- habamax's StatusLine is an inverted light bar; it must not become the panel surface
H.ok(highlight.roles().panel ~= "#9e9e9e", "habamax: an inverted status line is not used as the panel")
vim.cmd.colorscheme("default")
check_roles("default")

local lazy = vim.fn.expand("~/.local/share/nvim/lazy/")
for _, extra in ipairs({ { "jb.nvim", "jb" }, { "tokyonight.nvim", "tokyonight" } }) do
    if vim.uv.fs_stat(lazy .. extra[1]) then
        vim.opt.runtimepath:append(lazy .. extra[1])
        if pcall(vim.cmd.colorscheme, extra[2]) then
            check_roles(extra[2])
        end
    else
        print("  skip " .. extra[2] .. " (not installed)")
    end
end

H.group("ColorScheme switch re-derives")
vim.cmd.colorscheme("habamax")
local habamax_fill = get("TabFill").bg
vim.cmd.colorscheme("default")
H.ok(habamax_fill ~= get("TabFill").bg, "winbar fill follows the new colorscheme")
H.eq(get("Tab").fg, hex(highlight.roles().muted), "tabs follow the new colorscheme")

H.group("dap-view window draws on the panel surface")
H.install_session(H.new_fake_session())
require("dap-view").open()
H.pump(60)
local winhighlight = vim.wo[state.winnr].winhighlight
H.ok(winhighlight:find("Normal:NvimDapViewPanel", 1, true), "window maps Normal to the panel", winhighlight)
H.ok(winhighlight:find("WinBar:NvimDapViewTabFill", 1, true), "winbar sits on the panel", winhighlight)
H.ok(vim.wo[state.winnr].fillchars:find("eob: ", 1, true), "end-of-buffer filler is hidden")

local scratch = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, { split = "below" })
vim.wo[scratch][0].winhighlight = "Normal:MyPanel"
require("dap-view.views.options").apply_panel(scratch)
winhighlight = vim.wo[scratch].winhighlight
H.ok(winhighlight:find("Normal:MyPanel", 1, true), "a user's own winhighlight entry is kept", winhighlight)
H.ok(not winhighlight:find("Normal:NvimDapViewPanel", 1, true), "and not duplicated", winhighlight)
H.ok(winhighlight:find("EndOfBuffer:NvimDapViewPanel", 1, true), "missing entries are added", winhighlight)
vim.api.nvim_win_close(scratch, true)

H.group("precedence")
vim.api.nvim_set_hl(0, "NvimDapViewTab", { fg = "#123456" })
require("dap-view").setup({ theme_overrides = { default = { muted = "#654321" } } })
vim.cmd.doautocmd("ColorScheme")
H.eq(get("Tab"), { fg = 0x123456 }, "user nvim_set_hl beats the theme")
H.eq(get("Separator").fg, 0x654321, "per-colorscheme overrides apply")

local user_autocmd = vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
        vim.api.nvim_set_hl(0, "NvimDapViewTabSelected", { fg = "#010203" })
    end,
})
vim.cmd.colorscheme("habamax")
H.eq(get("TabSelected"), { fg = 0x010203 }, "user ColorScheme autocmd survives a colorscheme switch")
H.ok(get("Tab").fg ~= 0x123456, "colorscheme switch re-themes a group the user set only once")
vim.api.nvim_del_autocmd(user_autocmd)

themes.register("mine", function(ctx)
    H.ok(type(ctx.get) == "function" and ctx.get("Normal").fg, "providers can read resolved groups")
    return { accent = "#ff00ff", ok = "#00ff00" }
end)
H.ok(vim.tbl_contains(themes.list(), "mine"), "registered theme is listed")
H.ok(themes.get("mine") ~= nil, "registered theme can be fetched")
require("dap-view").setup({ theme = "mine", theme_overrides = { habamax = { ok = "#0000ff" } } })
H.eq(get("ControlStepInto").fg, 0xff00ff, "registered provider supplies roles")
H.eq(get("ControlPlay").fg, 0x0000ff, "overrides beat the provider")
H.ok(get("WatchError").fg ~= nil, "roles the provider omits fall back to auto")

require("dap-view").setup({
    theme = function()
        return { error = "#aa0000" }
    end,
})
H.eq(get("WatchError").fg, 0xaa0000, "a function provider supplies roles")

H.group("colorscheme-defined groups win")
local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. "/colors", "p")
vim.fn.writefile({
    'vim.cmd("highlight clear")',
    'vim.g.colors_name = "glass"',
    'vim.api.nvim_set_hl(0, "Normal", { fg = "#dddddd" })',
    'vim.api.nvim_set_hl(0, "TabLineSel", { fg = "#000000", bg = "#88aaff" })',
    'vim.api.nvim_set_hl(0, "NvimDapViewThread", { fg = "#abcdef" })',
}, dir .. "/colors/glass.lua")
vim.opt.runtimepath:append(dir)
require("dap-view").setup({ theme = "auto" })
vim.cmd.colorscheme("glass")
H.eq(get("Thread"), { fg = 0xabcdef }, "colorscheme's own NvimDapView group is kept")

H.group("transparency")
H.ok(highlight.roles() and select(2, highlight.roles()).transparent, "Normal without bg is detected as transparent")
H.eq(get("TabFill").bg, nil, "winbar fill has no background")
H.eq(get("Panel").bg, nil, "panel has no background")
H.eq(get("ControlPlay").bg, nil, "controls have no background")
H.eq(get("Tab").bg, nil, "unselected tabs have no background")
H.eq(get("TabSelected").bg, 0x88aaff, "selected tab keeps its chip")
require("dap-view").setup({ transparent = false })
H.ok(get("TabFill").bg ~= nil, "transparent = false keeps surfaces opaque")
vim.cmd.colorscheme("habamax")
require("dap-view").setup({ transparent = true })
H.eq(get("TabFill").bg, nil, "transparent = true strips an opaque colorscheme")

H.group("links theme reproduces the legacy groups")
require("dap-view").setup({ theme = "links", transparent = "auto" })
local LEGACY = {
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
    Truncated = "Comment",
    VariableInternal = "Comment",
    Boolean = "Boolean",
    String = "String",
    Number = "Number",
    Float = "Float",
    Function = "Function",
    Constant = "Constant",
    VirtualText = "NonText",
}
local mismatched = {}
for name, link in pairs(LEGACY) do
    if get(name).link ~= link then
        mismatched[#mismatched + 1] = name
    end
end
H.eq(mismatched, {}, "every legacy group links to its legacy target")
H.eq(get("SectionHeader").link, "NvimDapViewThread", "scope headers keep the legacy Thread look")
for _, name in ipairs({ "VirtualTextUpdated", "BooleanDim", "StringDim", "NumberDim" }) do
    H.ok(get(name).dim, "links: " .. name .. " is dimmed", vim.inspect(get(name)))
end
H.group("auto takes over again after links")
-- `:hi clear` restores the links' `default` definitions; they must not pass for user groups
require("dap-view").setup({ theme = "auto" })
vim.cmd.colorscheme("default")
H.eq(get("TabFill").bg, hex(highlight.roles().panel), "auto re-derives after a colorscheme switch")
H.ok(get("ControlTerminate").fg ~= nil, "terminate control is visible again")
require("dap-view").setup({ theme = "links" })

require("dap-view").close()
require("dap-view").open()
H.pump(60)
H.eq(vim.wo[state.winnr].winhighlight:find("NvimDapView", 1, true), nil, "links: new windows keep their highlights")

H.done()
