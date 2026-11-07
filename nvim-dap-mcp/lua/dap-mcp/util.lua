---Small shared helpers: the single session accessor, structured errors, JSON
---hygiene and the two nvim-dap internals we have to replicate.
local M = {}

---@class dapmcp.Error
---@field code string
---@field message string

---Raise a structured error. `dispatch` turns it into `{ ok = false, error = ... }`.
---Anything else that escapes a handler becomes `code = "internal"`.
---@param code string
---@param message string
---@param ... any Formatted into `message` when present
M.fail = function(code, message, ...)
    if select("#", ...) > 0 then
        message = message:format(...)
    end

    error({ __dap_mcp_error = true, code = code, message = message }, 0)
end

---@param err any Value caught by `pcall`
---@return dapmcp.Error
M.as_error = function(err)
    if type(err) == "table" and err.__dap_mcp_error then
        return { code = err.code, message = err.message }
    end

    return { code = "internal", message = type(err) == "string" and err or vim.inspect(err) }
end

---Every session read goes through here so tests can install a fake with one
---assignment. `dap.set_session` is deliberately left alone: it does real
---listener work and expects a genuine `dap.Session`.
---@type fun(): dap.Session?
M.session = function()
    return require("dap").session()
end

---The focused session, or a structured error if there is none.
---@return dap.Session
M.need_session = function()
    local session = M.session()
    if not session then
        M.fail("no_session", "No active debug session")
    end

    return session
end

---@return dap.Session
M.need_stopped_session = function()
    local session = M.need_session()
    if not session.stopped_thread_id then
        M.fail("not_stopped", "The debug session is running; it must be stopped at a breakpoint")
    end

    return session
end

---All sessions, children included.
---Replicates the file-local `broadcast` in nvim-dap `lua/dap.lua:1018`, which
---has no public entry point.
---@param fn fun(session: dap.Session)
M.for_each_session = function(fn)
    local function walk(sessions)
        for _, session in pairs(sessions) do
            fn(session)
            if session.children then
                walk(session.children)
            end
        end
    end

    walk(require("dap").sessions())
end

---Push the given breakpoint map to every live session, as
---`dap.toggle_breakpoint` (`lua/dap.lua:1030`) does after mutating signs.
---@param bps table<integer, dap.bp[]>
M.broadcast_breakpoints = function(bps)
    M.for_each_session(function(session)
        session:set_breakpoints(bps)
    end)
end

---Resolve a path to a loaded buffer. `sign_place` returns -1 for an unloaded
---buffer and `breakpoints.toggle` then silently drops the breakpoint, so the
---load is mandatory. Neither call touches a window, so the user's layout is
---untouched.
---@param file string
---@return integer bufnr
M.bufnr_for = function(file)
    if type(file) ~= "string" or file == "" then
        M.fail("invalid_argument", "`file` must be a non-empty path")
    end

    local path = vim.fn.fnamemodify(file, ":p")
    local bufnr = vim.fn.bufadd(path)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        vim.fn.bufload(bufnr)
    end

    return bufnr
end

---@param bufnr integer
---@return string
M.path_of = function(bufnr)
    return vim.api.nvim_buf_get_name(bufnr)
end

---An empty Lua table encodes as `[]`. Use this everywhere JSON demands an
---object, or MCP clients reject the payload.
---@param tbl table?
---@return table
M.object = function(tbl)
    if tbl == nil or next(tbl) == nil then
        return vim.empty_dict()
    end

    return tbl
end

---A DAP request that yields the current coroutine, with the adapter's error
---surfaced as a structured one.
---@param session dap.Session
---@param command string
---@param arguments table?
---@return table response
M.request = function(session, command, arguments)
    local err, response = session:request(command, arguments)
    if err then
        M.fail("dap_error", "%s failed: %s", command, err.message or vim.inspect(err))
    end

    return response or {}
end

return M
