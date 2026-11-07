-- Real Delve matrix-hover timing, isolated from the user's editor and adapters.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local dap = require("dap")
local state = require("dap-view.state")
local source = vim.fn.tempname() .. ".go"
local binary = vim.fn.tempname()
local program = {
    "package main",
    "func main() {",
    "  var matrix [30][30]int",
    "  for i := range matrix {",
    "    for j := range matrix[i] { matrix[i][j] = i*30+j }",
    "  }",
    "  println(matrix[29][29]) // BREAK",
    "}",
}
vim.fn.writefile(program, source)
local ok, err = xpcall(function()
    local build = vim.system({ "go", "build", "-gcflags=all=-N -l", "-o", binary, source }, { text = true }):wait()
    assert(build.code == 0, build.stderr)
    H.setup({ host = { default = os.getenv("HOST") or "split" }, winbar = { default_section = "breakpoints" } })
    dap.adapters.go = {
        type = "server",
        port = "${port}",
        executable = { command = assert(vim.env.DLV, "set DLV"), args = { "dap", "-l", "127.0.0.1:${port}" } },
    }
    vim.cmd.edit(source)
    vim.api.nvim_win_set_cursor(0, { 7, 0 })
    dap.toggle_breakpoint()
    local stopped = false
    dap.listeners.after.scopes["matrix-hover-integration"] = function()
        stopped = true
    end
    dap.run({ type = "go", request = "launch", name = "matrix hover", mode = "exec", program = binary })
    assert(
        vim.wait(20000, function()
            return stopped
        end, 10),
        "Delve did not stop"
    )
    require("dap-view").open()
    H.pump(100)
    local session = assert(dap.session())
    local original = session.request
    local adapter_ms, requests = 0, 0
    session.request = function(self, command, arguments, callback)
        if callback or (command ~= "evaluate" and command ~= "variables") then
            return original(self, command, arguments, callback)
        end
        local started = vim.uv.hrtime()
        local failure, response = original(self, command, arguments)
        adapter_ms = adapter_ms + (vim.uv.hrtime() - started) / 1e6
        requests = requests + 1
        return failure, response
    end
    local started = vim.uv.hrtime()
    require("dap-view").hover("matrix", true)
    H.ok(
        vim.wait(5000, function()
            return state.hover_winnr ~= nil
        end, 5),
        "real matrix hover publishes float within 5s"
    )
    assert(state.hover_winnr, "matrix hover did not open")
    local elapsed = (vim.uv.hrtime() - started) / 1e6
    H.eq(vim.api.nvim_buf_line_count(state.hover_bufnr), 31, "real matrix hover renders thirty rows")
    H.eq(requests, 2, "collapsed real matrix fetches only evaluation and direct children")
    print(
        ("real matrix initial: total=%.1fms adapter=%.1fms rendering/event-loop=%.1fms"):format(
            elapsed,
            adapter_ms,
            elapsed - adapter_ms
        )
    )
    for i = 0, 29 do
        state.hover_path_is_expanded["matrix.[" .. i .. "]"] = true
    end
    adapter_ms, requests = 0, 0
    started = vim.uv.hrtime()
    local done, failure = false, nil
    coroutine.wrap(function()
        local success, message = pcall(require("dap-view.hover.view").show, state.hover_bufnr)
        if not success then
            failure = message
        end
        done = true
    end)()
    H.ok(
        vim.wait(10000, function()
            return done
        end, 5),
        "real expanded matrix completes within 10s"
    )
    assert(not failure, failure)
    elapsed = (vim.uv.hrtime() - started) / 1e6
    H.eq(vim.api.nvim_buf_line_count(state.hover_bufnr), 931, "real matrix renders all nine hundred cells")
    H.eq(requests, 31, "real expanded matrix fetches each expanded row once")
    local text = table.concat(vim.api.nvim_buf_get_lines(state.hover_bufnr, 0, -1, false), "\n")
    H.ok(text:find("899", 1, true), "final real matrix element remains visible in buffer")
    print(
        ("real matrix expanded: total=%.1fms adapter=%.1fms rendering/event-loop=%.1fms"):format(
            elapsed,
            adapter_ms,
            elapsed - adapter_ms
        )
    )
end, debug.traceback)
if dap.session() then
    dap.terminate()
    vim.wait(5000, function()
        return dap.session() == nil
    end, 10)
end
vim.fn.delete(source)
vim.fn.delete(binary)
if not ok then
    error(err)
end
H.done()
