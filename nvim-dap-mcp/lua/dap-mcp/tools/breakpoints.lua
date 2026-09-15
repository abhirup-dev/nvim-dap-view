---Breakpoint tools.
---
---These go through `dap.breakpoints` rather than `dap.set_breakpoint` /
---`dap.list_breakpoints`: the former delegates to `toggle_breakpoint`, which
---operates on the current buffer and cursor, and the latter writes a quickfix
---list and returns nothing. Neither can be pointed at a file:line. Signs and
---the adapter therefore stay in sync exactly the way the human path keeps them.
local registry = require("dap-mcp.registry")
local util = require("dap-mcp.util")

---@return table[]
local function list()
    local breakpoints = require("dap.breakpoints")
    local result = {}

    for bufnr, buf_bps in pairs(breakpoints.get()) do
        for _, bp in pairs(buf_bps) do
            local state = bp.state or {}
            table.insert(result, {
                file = util.path_of(bufnr),
                line = bp.line,
                condition = bp.condition,
                hit_condition = bp.hitCondition,
                log_message = bp.logMessage,
                verified = state.verified,
                message = state.message,
            })
        end
    end

    table.sort(result, function(a, b)
        if a.file == b.file then
            return a.line < b.line
        end
        return a.file < b.file
    end)

    return result
end

---Breakpoints for one buffer, in the shape `set_breakpoints` expects.
---
---`breakpoints.get(bufnr)` early-returns `{}` when the buffer has no signs left
---(lua/dap/breakpoints.lua:167), not `{ [bufnr] = {} }`. Broadcasting that empty
---map would never mention the source, so the adapter would keep the breakpoint
---we just removed. `dap.clear_breakpoints` works around it the same way.
---@param bufnr integer
---@return table<integer, dap.bp[]>
local function bps_for(bufnr)
    local bps = require("dap.breakpoints").get(bufnr)
    if not bps[bufnr] then
        bps[bufnr] = {}
    end

    return bps
end

registry.register({
    name = "list_breakpoints",
    description = "All breakpoints currently set in Neovim, with their conditions and verification state.",
    schema = registry.schema(),
    handler = function()
        return { breakpoints = list() }
    end,
})

registry.register({
    name = "set_breakpoint",
    description = "Set (or replace) a breakpoint at file:line. Optionally conditional, hit-counted "
        .. "or a log point. Visible to the human in Neovim like any other breakpoint.",
    schema = registry.schema({
        file = { type = "string", description = "Path to the source file" },
        line = { type = "integer", description = "1-based line number" },
        condition = { type = "string", description = "Expression that must be true to stop" },
        hit_condition = { type = "string", description = 'Hit count expression, e.g. ">5"' },
        log_message = { type = "string", description = "Log this instead of stopping; makes it a log point" },
    }, { "file", "line" }),
    handler = function(args)
        if type(args.line) ~= "number" then
            util.fail("invalid_argument", "`line` must be a number")
        end

        local bufnr = util.bufnr_for(args.file)
        local line = math.floor(args.line)

        require("dap.breakpoints").set({
            condition = args.condition,
            hit_condition = args.hit_condition,
            log_message = args.log_message,
        }, bufnr, line)

        util.broadcast_breakpoints(bps_for(bufnr))

        return { file = util.path_of(bufnr), line = line, breakpoints = list() }
    end,
})

registry.register({
    name = "remove_breakpoint",
    description = "Remove the breakpoint at file:line.",
    schema = registry.schema({
        file = { type = "string", description = "Path to the source file" },
        line = { type = "integer", description = "1-based line number" },
    }, { "file", "line" }),
    handler = function(args)
        if type(args.line) ~= "number" then
            util.fail("invalid_argument", "`line` must be a number")
        end

        local bufnr = util.bufnr_for(args.file)
        local line = math.floor(args.line)

        local removed = require("dap.breakpoints").remove(bufnr, line) or false
        util.broadcast_breakpoints(bps_for(bufnr))

        return { removed = removed, file = util.path_of(bufnr), line = line, breakpoints = list() }
    end,
})
