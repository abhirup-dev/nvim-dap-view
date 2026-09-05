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
---@field is_open fun(): boolean

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
---keymap and cursor position already attached to it)
---@param name string
M.switch = function(name)
    -- Resolve first, so an unknown or unimplemented host doesn't close anything
    local target = M.resolve(name)

    local from = M.name()
    local previous = M.get()
    local bufnr = state.bufnr
    local was_open = previous.is_open()

    if was_open then
        previous.close()
    end

    if name ~= from then
        last = from
    end

    current = name

    if was_open and util.is_buf_valid(bufnr) then
        ---@cast bufnr integer
        state.bufnr = bufnr
        require("dap-view.actions").attach_window(target.open(bufnr))
    end
end

return M
