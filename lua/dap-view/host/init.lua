local setup = require("dap-view.setup")
local state = require("dap-view.state")
local util = require("dap-view.util")

local M = {}

---A host owns *where* the dap-view window lives. It knows nothing about what is
---rendered into `state.bufnr`; it only creates and destroys the window(s).
---
---`close` takes the same `hide_terminal` flag `dap-view.actions.close` receives,
---because terminal placement is part of the layout a host owns.
---@class dapview.Host
---@field open fun(bufnr: integer, hide_terminal?: boolean): integer Returns the window showing `bufnr`
---@field close fun(hide_terminal?: boolean)
---@field is_open fun(): boolean Is a dap-view window visible right now?
---@field follows_tabs boolean Does the host's window live in whatever tabpage the
---user is currently in? Only then may upstream's `TabEnter` handler retrack (and
---nil) `state.winnr` from the current tabpage's contents. A host that parks its
---window in a tabpage of its own, or in a float the user never switches away
---from, keeps owning it while the user is elsewhere
---@field is_active fun(): boolean Does the host still own something (a tabpage, a
---pane, a channel, a window) that `close` has to tear down? A host can own plenty
---while `is_open` is false: upstream's `TabEnter` handler nils `state.winnr`
---whenever the user visits a tabpage without a dap-view window, and a remote
---viewer that died leaves its channel, socket and placeholder behind

---@alias dapview.HostName "split"|"tab"|"remote"

---@type table<string, string>
local modules = {
    split = "dap-view.host.split",
    tab = "dap-view.host.tab",
    remote = "dap-view.host.remote",
}

---Every host the configuration knows about
---@type dapview.HostName[]
M.names = vim.tbl_keys(modules)

table.sort(M.names)

---Live override set by `switch`. The configured default stays untouched
---@type dapview.HostName?
local current

---The host `switch` last moved away from. `:DapViewDock` docks back into it, and
---the remote host falls back to it when its viewer dies
---@type dapview.HostName?
local last

---@return dapview.HostName
M.name = function()
    return current or setup.config.host.default
end

---@param name string
---@return dapview.Host
M.resolve = function(name)
    if not vim.tbl_contains(M.names, name) then
        error("Unknown host: " .. tostring(name))
    end

    return require(modules[name])
end

---@return dapview.Host
M.get = function()
    return M.resolve(M.name())
end

---The host to return to when undocking is undone. Never `remote`, so a dead
---viewer can't fall back into another remote
---@return dapview.HostName
M.previous = function()
    if last and last ~= "remote" then
        return last
    end

    local default = setup.config.host.default

    return default ~= "remote" and default or "split"
end

---Switch to another host, preserving `state.bufnr` (and therefore every view,
---keymap and cursor position already attached to it).
---
---Ownership, not window validity, decides what happens: "no dap-view window is
---visible" says nothing about whether the current host still owns a tabpage, a
---pane or a channel that has to be torn down first.
---@param name string
---@param opts? {reopen?: boolean} `reopen` opens the target even though the
---previous host owned nothing left to tear down. The remote fallback path needs
---it, because it closes itself before switching
M.switch = function(name, opts)
    -- Resolve first, so an unknown or unimplemented host doesn't close anything
    local target = M.resolve(name)

    local from = M.name()
    local previous = M.get()
    local previous_last = last
    local bufnr = state.bufnr
    local active = previous.is_active()

    if active then
        previous.close()
    end

    if name ~= from then
        last = from
    end

    current = name

    -- Undocking a "closed" view during a live session should still bring it up
    -- in the pane, so a dap session counts as a reason to open
    local open = util.is_buf_valid(bufnr) and (active or (opts and opts.reopen) or require("dap").session() ~= nil)

    if not open then
        return
    end

    ---@cast bufnr integer
    state.bufnr = bufnr

    local ok, err = pcall(function()
        require("dap-view.actions").attach_window(target.open(bufnr))
    end)

    if ok then
        return
    end

    -- Never leave `current` pointing at a host that failed to open
    current = from
    last = previous_last

    if active then
        -- Only put back what was actually there
        pcall(function()
            require("dap-view.actions").attach_window(previous.open(bufnr))
        end)
    end

    vim.notify(
        "dap-view: could not switch to the '" .. name .. "' host: " .. (tostring(err):gsub("^.-:%d+: ", "")),
        vim.log.levels.ERROR
    )
end

return M
