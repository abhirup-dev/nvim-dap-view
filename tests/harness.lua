-- Shared headless harness for the dap-view parity suite.
--
-- Each case under `tests/cases` is a standalone script run as
-- `nvim --headless -u NONE -l tests/cases/<name>.lua`; `tests/run.lua` spawns
-- them one process each, because the plugin keeps module level state that a
-- single process could not reset between cases.
local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

vim.opt.runtimepath:prepend(vim.fn.expand("~/.local/share/nvim/lazy/nvim-nio"))
vim.opt.runtimepath:prepend(vim.fn.expand("~/.local/share/nvim/lazy/nvim-dap"))
vim.opt.runtimepath:prepend(repo)

local H = {}

H.passed, H.failed, H.failures = 0, 0, {}

function H.ok(cond, name, detail)
    if cond then
        H.passed = H.passed + 1
        print(("  ok   %s"):format(name))
    else
        H.failed = H.failed + 1
        local line = ("  FAIL %s%s"):format(name, detail and (" -- " .. tostring(detail)) or "")
        print(line)
        table.insert(H.failures, line)
    end
end

function H.eq(actual, expected, name)
    H.ok(
        vim.deep_equal(actual, expected),
        name,
        ("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual))
    )
end

function H.group(name)
    print("\n== " .. name)
end

function H.done()
    print(("\n%d passed, %d failed"):format(H.passed, H.failed))
    for _, f in ipairs(H.failures) do
        print(f)
    end
    vim.cmd(H.failed > 0 and "cq!" or "qa!")
end

-- Drive the event loop for `ms`, since fake responses land via vim.schedule.
function H.pump(ms)
    vim.wait(ms or 60, function()
        return false
    end, 5)
end

--------------------------------------------------------------------------------
-- Fake session
--------------------------------------------------------------------------------

local fixtures = {
    threads = { threads = { { id = 1, name = "main" } } },
    stackTrace = {
        totalFrames = 1,
        stackFrames = { { id = 11, name = "compute", line = 12, column = 3, source = { path = nil } } },
    },
    scopes = { scopes = { { name = "Locals", variablesReference = 100 } } },
}

local children = {}
for i = 1, 5 do
    table.insert(children, {
        name = ("var%02d"):format(i),
        value = ("value-%d"):format(i),
        type = "int",
        variablesReference = 0,
    })
end

function H.new_fake_session(opts)
    opts = opts or {}
    local session
    session = {
        id = 1,
        stopped_thread_id = 1,
        initialized = true,
        capabilities = { supportsSetVariable = true, exceptionBreakpointFilters = {} },
        config = { type = opts.adapter or "fake" },
        parent = nil,
        term_buf = opts.term_buf,
        threads = { [1] = { id = 1, name = "main", frames = fixtures.stackTrace.stackFrames } },
        current_frame = fixtures.stackTrace.stackFrames[1],
        received = {},
        request = function(_, command, arguments, on_result)
            table.insert(session.received, { command = command, arguments = arguments })
            local co, is_main
            if not on_result then
                co, is_main = coroutine.running()
                if co and not is_main then
                    on_result = function(...)
                        coroutine.resume(co, ...)
                    end
                else
                    co = nil
                    on_result = function() end
                end
            end
            local response
            if command == "variables" then
                response = { variables = arguments.variablesReference == 100 and children or {} }
            elseif command == "setVariable" then
                response = { value = arguments.value, type = "int", variablesReference = 0 }
            elseif command == "evaluate" then
                response = { result = "evaluated:" .. arguments.expression, type = "int", variablesReference = 0 }
            else
                response = fixtures[command] or {}
            end
            vim.schedule(function()
                on_result(nil, response)
            end)
            if co then
                return coroutine.yield()
            end
        end,
        evaluate = function(self, args, fn)
            args.frameId = args.frameId or (self.current_frame or {}).id
            return self:request("evaluate", args, fn)
        end,
        _frame_set = function() end,
        set_breakpoints = function() end,
        _step = function() end,
        _pause = function() end,
    }
    return session
end

---Install `fake` as the active session for nvim-dap's public API.
function H.install_session(fake)
    local dap = require("dap")
    dap.session = function()
        return fake
    end
    dap.sessions = function()
        return fake and { [1] = fake } or {}
    end
end

---Create a scratch terminal-ish buffer that can stand in for `session.term_buf`.
function H.make_term_buf()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "dap-view-term"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "program output" })
    return buf
end

function H.setup(opts)
    vim.cmd("runtime! plugin/*.lua")
    require("dap-view").setup(opts)
end

return H
