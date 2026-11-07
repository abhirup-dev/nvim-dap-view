-- Internal UI request validity. Frame identity is deliberately numeric, unlike
-- the stricter frame-object/stopped checks used for mutation refreshes.
local M = {}
local epoch = 0

function M.invalidate()
    epoch = epoch + 1
end

function M.capture(session)
    return {
        session = session,
        frame_id = session.current_frame and session.current_frame.id,
        epoch = epoch,
    }
end

function M.is_current(ctx)
    return epoch == ctx.epoch
        and require("dap").session() == ctx.session
        and (ctx.session.current_frame and ctx.session.current_frame.id) == ctx.frame_id
end

return M
