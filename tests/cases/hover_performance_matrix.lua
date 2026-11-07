local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
H.setup({ host = { default = os.getenv("HOST") or "tab" } })
local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
local base = fake.request
local adapter_ms, requests = 0, 0
fake.request = function(self, cmd, args, cb)
    if cmd ~= "evaluate" and cmd ~= "variables" then
        return base(self, cmd, args, cb)
    end
    local response
    if cmd == "evaluate" then
        response = { result = "[30][30]int", variablesReference = 200 }
    else
        local vars = {}
        for i = 1, 30 do
            vars[i] = {
                name = tostring(i),
                value = args.variablesReference == 200 and "[30]int" or tostring(i),
                variablesReference = args.variablesReference == 200 and 200 + i or 0,
            }
        end
        response = { variables = vars }
    end
    requests = requests + 1
    local co, started = coroutine.running(), vim.uv.hrtime()
    vim.defer_fn(function()
        adapter_ms = adapter_ms + (vim.uv.hrtime() - started) / 1e6
        if cb then
            cb(nil, response)
        else
            assert(coroutine.resume(co, nil, response))
        end
    end, 20)
    if not cb then
        return coroutine.yield()
    end
end
H.install_session(fake)
-- Exercise actual evaluate + float publication; collapsed rows must not fetch 900 cells.
local started = vim.uv.hrtime()
require("dap-view").hover("matrix", true)
local ticked = false
vim.schedule(function()
    ticked = true
end)
H.ok(
    vim.wait(1000, function()
        return state.hover_winnr ~= nil
    end, 5),
    "matrix hover float published within 1s"
)
local elapsed = (vim.uv.hrtime() - started) / 1e6
H.ok(ticked, "event loop runs while adapter request is pending")
H.eq(requests, 2, "initial matrix hover fetches evaluate and direct children only")
H.eq(vim.api.nvim_buf_line_count(state.hover_bufnr), 31, "30 matrix rows rendered")
H.ok(elapsed - adapter_ms < 500, "initial rendering overhead below 500ms")
-- Expand all 30 rows: measure 900-cell rendering separately from sequential adapter waits.
for i = 1, 30 do
    state.hover_path_is_expanded["matrix." .. i] = true
end
requests, adapter_ms = 0, 0
started = vim.uv.hrtime()
local done = false
coroutine.wrap(function()
    require("dap-view.hover.view").show(state.hover_bufnr)
    done = true
end)()
H.ok(
    vim.wait(3000, function()
        return done
    end, 5),
    "900-cell hover finishes"
)
elapsed = (vim.uv.hrtime() - started) / 1e6
H.eq(requests, 31, "expanded matrix uses one request per expanded row")
H.eq(vim.api.nvim_buf_line_count(state.hover_bufnr), 931, "900 cells and row headers rendered")
H.ok(elapsed - adapter_ms < 500, "900-cell rendering overhead below 500ms")
print(
    ("matrix expanded: total=%.1fms adapter=%.1fms rendering/event-loop=%.1fms"):format(
        elapsed,
        adapter_ms,
        elapsed - adapter_ms
    )
)
H.done()
