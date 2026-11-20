local state = require("dap-view.state")
local setup = require("dap-view.setup")

local M = {}

M.PANEL_WINHIGHLIGHT = {
    Normal = "NvimDapViewPanel",
    NormalNC = "NvimDapViewPanel",
    EndOfBuffer = "NvimDapViewPanel",
    WinBar = "NvimDapViewTabFill",
    WinBarNC = "NvimDapViewTabFill",
}

---Draw the window on the panel surface without clobbering mappings the user already made,
---and hide the `~` past the end of the buffer
---@param winnr integer
M.apply_panel = function(winnr)
    local win = vim.wo[winnr]
    local entries = vim.split(win.winhighlight, ",", { trimempty = true })
    local mapped = {}
    for _, entry in ipairs(entries) do
        mapped[entry:match("^([^:]+):") or entry] = true
    end
    for from, to in vim.spairs(M.PANEL_WINHIGHLIGHT) do
        if not mapped[from] then
            entries[#entries + 1] = from .. ":" .. to
        end
    end
    vim.wo[winnr][0].winhighlight = table.concat(entries, ",")

    -- 'fillchars' is global-local: extend the effective value so the user's other fill chars survive
    local fillchars = win.fillchars
    if not fillchars:find("eob:") then
        vim.wo[winnr][0].fillchars = fillchars == "" and "eob: " or fillchars .. ",eob: "
    end
end

M.set_options = function()
    local win = vim.wo[state.winnr][0]
    win.scrolloff = 99
    win.wrap = false
    win.number = false
    win.relativenumber = false
    win.cursorlineopt = "line"
    win.cursorline = true
    win.statuscolumn = ""
    win.foldcolumn = "0"
    win.winfixbuf = true

    local position = setup.config.windows.position
    local pos = (type(position) == "function" and position and position(state.win_pos))
        or (type(position) == "string" and position)

    if pos == "above" or pos == "below" then
        win.winfixheight = true
    else
        win.winfixwidth = true
    end

    if require("dap-view.highlight").themed() then
        M.apply_panel(state.winnr)
    end

    local buf = vim.bo[state.bufnr]
    buf.buftype = "nofile"
    buf.swapfile = false
    buf.modifiable = false
    buf.filetype = "dap-view"

    local tree = setup.config.tree

    if tree.indent_width then
        -- Six levels of a Go struct spend 48 cells on indent alone at the default `tabstop`
        buf.vartabstop = ""
        buf.tabstop = tree.indent_width
    end

    if tree.fold then
        -- `foldlevel` is indent divided by `shiftwidth`. A `shiftwidth` of 0 follows `tabstop`,
        -- so one fold level is one tab of the tree, whatever the user's global `shiftwidth` is
        buf.shiftwidth = 0

        win.foldmethod = "indent"
        win.foldenable = true
        win.foldlevel = tree.fold_level
        win.foldtext = "v:lua.require'dap-view.tree.fold'.foldtext()"
    end
end

return M
