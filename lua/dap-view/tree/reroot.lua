local dap = require("dap")

local state = require("dap-view.state")
local setup = require("dap-view.setup")
local util = require("dap-view.util")

local M = {}

---Hint at most once per Neovim session, it's a nudge and not an error
local hinted = false

local redraw = function()
    coroutine.wrap(function()
        require("dap-view.views").switch_to_view("scopes", true)
    end)()
end

---Render the scopes tree with the variable at `line` as its root, keeping the ancestors
---in a breadcrumb header. Expansion state is untouched: the render is a filter over the
---regular pass, so every line indexed table stays valid.
---@param line integer? Defaults to the cursor
M.reroot = function(line)
    if not util.is_win_valid(state.winnr) then
        vim.notify("nvim-dap-view window is not open")
        return
    end

    line = line or vim.api.nvim_win_get_cursor(state.winnr)[1]

    local path = state.line_to_variable_path[line]

    if path == nil then
        vim.notify("No variable under the cursor to re-root at")
        return
    end

    if (state.variable_path_to_reference[path] or 0) == 0 then
        vim.notify("Can't re-root at " .. (state.variable_path_to_name[path] or path) .. ": it has no children")
        return
    end

    state.tree_root_stack[#state.tree_root_stack + 1] = path

    redraw()
end

---Pop one level off the breadcrumb
M.root_up = function()
    if #state.tree_root_stack == 0 then
        vim.notify("Already at the root of the tree")
        return
    end

    table.remove(state.tree_root_stack)

    redraw()
end

---Nudge the user towards `:DapViewReroot` the first time the cursor sits on a node
---deeper than `tree.reroot_depth`
---@param line integer
M.hint = function(line)
    local reroot_depth = setup.config.tree.reroot_depth

    if hinted or reroot_depth == false or #state.tree_root_stack > 0 then
        return
    end

    local path = state.line_to_variable_path[line]
    local depth = path and state.variable_path_to_depth[path]

    if depth and depth > reroot_depth then
        hinted = true

        vim.notify(
            ("Variable is %d levels deep. `:DapViewReroot` focuses this subtree, `:DapViewRootUp` goes back"):format(
                depth
            )
        )
    end
end

---Distinct from the "dap-view" id used by `dap-view.listeners`: reusing it would overwrite
---the handlers registered there
local SUBSCRIPTION_ID = "dap-view-tree-reroot"

-- The re-root stack is a view over one session's variables, so it can't outlive it.
-- Expansion state (`variable_path_is_expanded`) is deliberately kept across sessions
local session_end = { "event_terminated", "event_exited", "disconnect" }

for _, listener in ipairs(session_end) do
    dap.listeners.after[listener][SUBSCRIPTION_ID] = function()
        state.tree_root_stack = {}
        hinted = false
    end
end

return M
