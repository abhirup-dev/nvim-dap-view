local dap = require("dap")

local util = require("dap-view.util")
local window = require("dap-view.util.window")
local state = require("dap-view.state")
local setup = require("dap-view.setup")
local globals = require("dap-view.globals")
local winbar = require("dap-view.options.winbar")

local api = vim.api

local M = {}

---The text width `tree.max_value_width = "auto"` was last measured against.
---Reset whenever the view goes away, so a reopen measures the new window
---@type integer?
local rendered_width

---Re-render the current section when the dap-view window's usable width changes.
---
---With `"auto"`, every clamped value in the buffer was measured against one
---particular text width. That width moves when the user drags the split, and
---also the moment a window that was never drawn gets drawn, since only then does
---`getwininfo` report its real decorations. Neither is a render trigger by
---itself, so the buffer would otherwise keep lines clamped to the wrong number
local refresh_auto_width = function()
    if not util.is_win_valid(state.winnr) or not util.is_buf_valid(state.bufnr) then
        rendered_width = nil
        return
    end

    if setup.config.tree.max_value_width ~= "auto" then
        return
    end

    local width = require("dap-view.util.truncate").text_width(state.winnr)

    if not width or width == rendered_width then
        return
    end

    rendered_width = width

    if state.current_section then
        -- Reuse the normal render path, leaving the cursor where the user put it.
        -- The scopes view fetches variables synchronously (`session:request` yields), so it
        -- must run inside a coroutine, as upstream does in `refresher.lua`; on the main
        -- thread the request returns nothing and the empty state overwrites the tree
        coroutine.wrap(function()
            require("dap-view.views").switch_to_view(state.current_section, true)
        end)()
    end
end

api.nvim_create_autocmd({ "WinResized", "BufWinEnter" }, {
    callback = function(args)
        -- `v:event.windows` is the cheap filter, not the real one: the width
        -- comparison below is what decides. Absent or empty, just fall through
        local windows = args.event == "WinResized" and vim.v.event.windows or nil

        if windows and next(windows) and not vim.tbl_contains(windows, state.winnr) then
            return
        end

        vim.schedule(refresh_auto_width)
    end,
})

api.nvim_create_autocmd({ "WinClosed", "WinNew" }, {
    callback = function()
        vim.schedule(function()
            if util.is_win_valid(state.winnr) then
                -- Recalculate function labels
                winbar.refresh_winbar()

                -- Resize when closing unrelated windows (#190)
                -- Only if not manually resized (#203)
                local height, width = require("dap-view.util.size").size()
                if state.og_height and height == state.og_height then
                    api.nvim_win_set_height(state.winnr, state.og_height)
                end
                if state.og_width and width == state.og_width then
                    api.nvim_win_set_width(state.winnr, state.og_width)
                end
            end

            refresh_auto_width()
        end)
    end,
})

api.nvim_create_autocmd("TabEnter", {
    callback = function()
        local session = dap.session()
        local adapter = session and session.config.type

        local follow_tab = setup.config.follow_tab
        local follow_tab_ = (type(follow_tab) == "function" and follow_tab(adapter))
            or (type(follow_tab) == "boolean" and follow_tab)

        local open_winnr = window.fetch_window()

        -- When follow_tab is a function, we have to "restore" what otherwise would be a leftover window
        --
        -- Consider the following scenario:
        -- - Tab 1 is active and has a dap-view window
        -- - User switches to tab 2, which is not eligible by `follow_tab`
        -- - `state.winnr` is now set to `nil`, but the window still exists on tab 1 (intended)
        -- - User switches to tab 3, which is eligible by `follow_tab`
        -- - Since there's a dap-view window elsewhere, we have to "reopen" to "follow the tab"
        -- (otherwise, visiting a non eligible tab wouldn't make much sense - afterwards, we'd keep the "closed" state)
        -- - We can do that just fine, since now we track the correct window with a (window) variable
        -- - Buf if the user closes the newly opened dap-view window on tab 3, and switches back to tab 1
        -- The original window will still be there! Since we closed, we don't want that!
        --
        -- This happens because the "close" function does not close all the the valid windows, only the one tracked by
        -- `state.winnr`, which is `nil` by then (massive oversight, I know)
        --
        -- This never came up before the dynamic `follow_tab` because we could always assume `state.winnr` was either
        -- from the current tab or the previous tab (which would then be handle by this very own autocmd)
        --
        -- By assigning `state.winnr` to the open window (which may be anywhere), `open`'s call to `close` will clean it
        if open_winnr and state.winnr == nil then
            state.winnr = open_winnr
        end

        if util.is_win_valid(state.winnr) and follow_tab_ then
            require("dap-view.actions").open(state.term_winnr ~= nil)
        end

        local winnr = window.fetch_window({ current_tab = true })
        local term_winnr = window.fetch_window({ current_tab = true, term = true })

        state.winnr = winnr
        -- Track the state of the last term win, so it can be closed later if becomes a leftover window
        if state.term_winnr and term_winnr ~= state.term_winnr then
            state.last_term_winnr = state.term_winnr
        end
        state.term_winnr = term_winnr

        if winnr ~= nil then
            winbar.wrapped_action(state.current_section)
        end
    end,
})

-- VimLeavePre may run "too late"
-- Session plugins may run "autosave" hooks with this event as well
-- Which chould lead to race conditions
api.nvim_create_autocmd(globals.HAS_0_13 and "SessionWritePre" or "VimLeavePre", {
    callback = function()
        require("dap-view.vim-sessions").save_state()
    end,
})

api.nvim_create_autocmd("CursorMoved", {
    pattern = globals.MAIN_BUF_NAME,
    callback = function()
        -- The window may be invalid when switching tabs, given that now we defer the update when switching tabs
        if util.is_win_valid(state.winnr) then
            state.cur_pos[state.current_section] = api.nvim_win_get_cursor(state.winnr)

            if state.current_section == "scopes" then
                require("dap-view.tree.reroot").hint(state.cur_pos[state.current_section][1])
            end
        end
    end,
})

---Floats emit no `WinResized` (probed on 0.12.4: neither hidden nor visible ones
---do), so the remote host, whose dap-view window *is* a float, has to drive the
---re-render itself after resizing its placeholder. Exported rather than
---duplicated so `rendered_width` stays a single piece of bookkeeping
M.refresh_auto_width = refresh_auto_width

return M
