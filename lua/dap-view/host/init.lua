local setup = require("dap-view.setup")

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

---@type table<dapview.HostName, true>
M.hosts = {
    split = true,
    tab = true,
}

---@return dapview.HostName
M.name = function()
    return setup.config.host.default
end

---@param name string
---@return dapview.Host
M.resolve = function(name)
    if not M.hosts[name] then
        error("Unknown host: " .. tostring(name))
    end

    return require("dap-view.host." .. name)
end

---@return dapview.Host
M.get = function()
    return M.resolve(M.name())
end

return M
