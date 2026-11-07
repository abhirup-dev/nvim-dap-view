local state = require("dap-view.state")
local eval = require("dap-view.watches.eval")

local M = {}
local pending_mutation
local mutation_version = 0

---Refresh after a successful mutation, including edits made by another DAP
---client such as MCP. Coalesce the response listener and the UI callback.
M.refresh_variables = function(session, frame)
    local function owns_frame()
        return require("dap").session() == session
            and session.current_frame == frame
            and session.stopped_thread_id ~= nil
    end
    if not owns_frame() then
        return
    end
    if pending_mutation and pending_mutation.session == session and pending_mutation.frame == frame then
        return
    end
    mutation_version = mutation_version + 1
    local version = mutation_version
    local pending = { session = session, frame = frame }
    pending_mutation = pending
    vim.schedule(function()
        if pending_mutation ~= pending then
            return
        end
        pending_mutation = nil
        if not owns_frame() then
            return
        end
        M.refresh_all_expressions()
        if frame then
            coroutine.wrap(function()
                -- Delve caches values under old scope references after edits.
                local err, response = session:request("scopes", { frameId = frame.id })
                if err or not response or version ~= mutation_version or not owns_frame() then
                    return
                end
                frame.scopes = response.scopes
                if state.current_section == "scopes" then
                    require("dap-view.views").switch_to_view("scopes")
                end
            end)()
        end
    end)
end

---Refresh views that may get updated on session events
---
---threads => may get outdated when finishing / switching sessions
---exceptions => no longer valid after finishing a session
---scopes => no longer valid after finishing a session
---sessions => obviously needs to be updated when switching / finishing a session
M.refresh_session_based_views = function()
    if vim.tbl_contains({ "threads", "exceptions", "watches", "sessions" }, state.current_section) then
        require("dap-view.views").switch_to_view(state.current_section)
    elseif state.current_section == "scopes" then
        coroutine.wrap(function()
            require("dap-view.views").switch_to_view("scopes")
        end)()
    end
end

M.refresh_all_expressions = function()
    coroutine.wrap(function()
        for expr, _ in pairs(state.watched_expressions) do
            eval.evaluate_expression(expr, true)
        end

        if state.current_section == "watches" then
            require("dap-view.views").switch_to_view("watches")
        end
    end)()
end

return M
