---Render notification hook.
---
---Every write to the dap-view buffer goes through `dap-view.util.set_lines` or
---`dap-view.util.hl.hl_range`; both poke `notify` afterwards. A host that mirrors
---the buffer somewhere else (`dap-view.host.remote`) installs `on_render` and
---uses it as a dirty flag, then snapshots the buffer on its own schedule.
---
---A hook rather than a monkeypatch: it survives a plugin reload, keeps the call
---sites greppable, and merges with upstream instead of fighting it.
local M = {}

---@type fun()?
M.on_render = nil

M.notify = function()
    if M.on_render then
        M.on_render()
    end
end

return M
