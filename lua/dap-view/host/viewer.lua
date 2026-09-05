---Viewer for the remote host. Runs as the init file of a bare Neovim living in a
---multiplexer pane:
---
---    nvim --clean --listen <sock> -u <this file>
---
---It owns no state. The owner Neovim connects to `<sock>`, calls `attach` over
---RPC and from then on pushes buffer contents, extmarks and the winbar into the
---buffer created here. Keypresses travel the other way as `(lhs, line)` pairs;
---the owner resolves them through its line indexed state.
---
---`--clean` already implies `-u NONE -i NONE --noplugin`; a later `-u <file>`
---overrides only the config file, so no plugin or user config is loaded (verified
---on Neovim 0.12.4).
local api = vim.api

if vim.g.dapview_viewer then
    return _G.dapview_viewer
end

vim.g.dapview_viewer = true

---Groups the owner does not send are left at their `--clean` defaults
---@param highlights table<string, vim.api.keyset.highlight>?
local apply_highlights = function(highlights)
    for name, attrs in pairs(highlights or {}) do
        pcall(api.nvim_set_hl, 0, name, attrs)
    end
end

local buf = api.nvim_create_buf(false, true)

api.nvim_buf_set_name(buf, "dap-view://remote")

vim.bo[buf].buftype = "nofile"
vim.bo[buf].swapfile = false
vim.bo[buf].bufhidden = "hide"
vim.bo[buf].filetype = "dap-view"
vim.bo[buf].modifiable = false

local win = api.nvim_get_current_win()

api.nvim_win_set_buf(win, buf)

vim.o.laststatus = 0
vim.o.ruler = false
vim.o.showmode = false
vim.o.showcmd = false
vim.o.mouse = "a"
vim.o.termguicolors = true
vim.o.swapfile = false
vim.o.shortmess = vim.o.shortmess .. "I"

local set_win_options = function(target)
    local wo = vim.wo[target][0]

    wo.number = false
    wo.relativenumber = false
    wo.signcolumn = "no"
    wo.statuscolumn = ""
    wo.foldcolumn = "0"
    wo.wrap = false
    wo.list = false
    wo.cursorline = true
    wo.cursorlineopt = "line"
    wo.scrolloff = 99
end

set_win_options(win)

local ns = api.nvim_create_namespace("dap-view-remote")

---The owner is the only socket peer that identified itself as `dap-view-owner`
---@return integer?
local owner_chan = function()
    for _, chan in ipairs(api.nvim_list_chans()) do
        if chan.client and chan.client.name == "dap-view-owner" then
            return chan.id
        end
    end
end

---@class dapview.ViewerAttachOpts
---@field keymaps string[] Left hand sides to forward to the owner
---@field tabstop integer?
---@field shiftwidth integer?
---@field fold boolean?
---@field fold_level integer?
---@field winbar string?
---@field background string?
---@field highlights table<string, vim.api.keyset.highlight>?

local M = {
    buf = buf,
    win = win,
    ns = ns,
}

---@param opts dapview.ViewerAttachOpts
---@return table
M.attach = function(opts)
    opts = opts or {}

    local owner = owner_chan()

    if opts.background then
        vim.o.background = opts.background
    end

    apply_highlights(opts.highlights)

    if opts.tabstop then
        vim.bo[buf].vartabstop = ""
        vim.bo[buf].tabstop = opts.tabstop
    end

    if opts.fold then
        vim.bo[buf].shiftwidth = opts.shiftwidth or 0

        local wo = vim.wo[win][0]

        wo.foldmethod = "indent"
        wo.foldenable = true
        wo.foldlevel = opts.fold_level or 2
    end

    if opts.winbar then
        vim.wo[win][0].winbar = opts.winbar
    end

    -- Nothing here knows what a key *means*: the owner owns the line indexed
    -- state, so the line number is the whole payload
    for _, lhs in ipairs(opts.keymaps or {}) do
        pcall(vim.keymap.set, "n", lhs, function()
            if not owner then
                return
            end

            -- Custom RPC method names are not dispatchable by Neovim (only API
            -- method names are), so the notification is an `nvim_exec_lua` with
            -- the payload passed as arguments, never interpolated into the code
            pcall(
                vim.rpcnotify,
                owner,
                "nvim_exec_lua",
                "require('dap-view.host.remote').on_key(...)",
                { lhs, vim.fn.line(".") }
            )
        end, { buffer = buf, nowait = true, desc = "dap-view remote: " .. lhs })
    end

    return {
        buf = buf,
        win = win,
        ns = ns,
        owner = owner,
        width = api.nvim_win_get_width(win),
        height = api.nvim_win_get_height(win),
    }
end

_G.dapview_viewer = M

return M
