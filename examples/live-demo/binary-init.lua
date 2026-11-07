-- Real Python/Go/Lua binary decoding and selective update demo. 2026-11-07.
-- DEMO_LANG=python|go|lua nvim -u binary-init.lua; Lua also requires lua-target.lua running.
local directory = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
dofile(directory .. "/init.lua")
local dap, view, state = require("dap"), require("dap-view"), require("dap-view.state")
local language = vim.env.DEMO_LANG or "python"
require("dap-view.setup").setup({
    decoders = dofile(directory .. "/binary-profile.lua"),
    tree = { max_value_width = 52 },
})
local source = directory .. "/binary." .. ({ python = "py", go = "go", lua = "lua" })[language]
local configuration = demo.configuration
configuration.name = language .. " protobuf + gzip"
if language == "go" then
    configuration.program = directory .. "/binary-go"
elseif language == "python" then
    configuration.program = source
else
    local info = vim.json.decode(table.concat(vim.fn.readfile("/tmp/nvim-dap-live-demo/lua-server.json"), "\n"))
    dap.adapters.nlua = { type = "server", host = info.host, port = info.port }
    configuration = { type = "nlua", request = "attach", name = "Lua protobuf + gzip" }
    dap.listeners.after.configurationDone["binary-run"] = function()
        if demo.target_channel then
            return
        end
        demo.target_channel = vim.fn.sockconnect("pipe", "/tmp/nvim-dap-live-demo/lua-target.sock", { rpc = true })
        assert(demo.target_channel > 0)
        vim.rpcnotify(demo.target_channel, "nvim_exec_lua", "dofile(...)", { source })
    end
end
demo.configuration = configuration
function demo.start()
    demo.focus_source()
    dap.run(configuration)
end
dap.listeners.after.scopes["live-demo"] = function()
    demo.stops = demo.stops + 1
    vim.schedule(function()
        for _, name in ipairs({ "protobuf_wire", "gzip_wire" }) do
            state.variable_path_is_expanded["Locals." .. name] = true
            state.variable_path_is_expanded["Locals." .. name .. ".decoded"] = true
        end
        if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
            view.open()
        elseif state.current_section == "scopes" then
            view.show_view("scopes")
        end
    end)
end
function demo.capture()
    local values, updates = {}, {}
    for line, path in pairs(state.line_to_variable_path) do
        values[path] = state.variable_path_to_value[path]
    end
    for _, mark in
        ipairs(
            vim.api.nvim_buf_get_extmarks(state.bufnr, require("dap-view.globals").NAMESPACE, 0, -1, { details = true })
        )
    do
        if mark[4].hl_group == "NvimDapViewWatchUpdated" then
            local path = state.line_to_variable_path[mark[2] + 1]
            if path then
                updates[path] = true
            end
        end
    end
    local frame = dap.session() and dap.session().current_frame
    return {
        language = language,
        stops = demo.stops,
        line = frame and frame.line,
        values = values,
        updates = updates,
        bytes = binary_metrics,
    }
end
function demo.await(counter, proto, gzip, changed)
    assert(
        vim.wait(20000, function()
            local stamp = require("dap-view.decoders").context(dap.session(), "capture")
            local visible = {}
            for _, path in pairs(state.line_to_variable_path) do
                visible[path] = true
            end
            local function ready(name)
                local metric = binary_metrics[name]
                return metric
                    and metric.generation == stamp.generation
                    and metric.frame_id == stamp.frame_id
                    and visible["Locals." .. name .. ".decoded.age"]
            end
            return ready("protobuf_wire")
                and ready("gzip_wire")
                and state.variable_path_to_value["Locals.counter"] == tostring(counter)
                and state.variable_path_to_value["Locals.protobuf_wire.decoded.age"] == tostring(proto)
                and state.variable_path_to_value["Locals.gzip_wire.decoded.age"] == tostring(gzip)
        end, 20),
        vim.inspect(demo.capture())
    )
    -- Allow both asynchronous decoder completions and their queued redraws to settle.
    vim.wait(150, function()
        return false
    end, 10)
    local snapshot = demo.capture()
    local tracked = {
        "Locals.counter",
        "Locals.unchanged",
        "Locals.protobuf_wire.decoded.age",
        "Locals.protobuf_wire.decoded.name",
        "Locals.gzip_wire.decoded.age",
        "Locals.gzip_wire.decoded.name",
    }
    for _, path in ipairs(tracked) do
        assert(
            (snapshot.updates[path] or false) == (path == changed),
            "unexpected update marker: " .. path .. " " .. vim.inspect(snapshot.updates)
        )
    end
    assert(snapshot.bytes.protobuf_wire and snapshot.bytes.gzip_wire, "missing exact-byte checks")
    if changed == nil then
        assert(next(snapshot.updates) == nil, vim.inspect(snapshot.updates))
    end
    demo.history[#demo.history + 1] = snapshot
    vim.fn.writefile({ vim.json.encode(demo.history) }, directory .. "/binary-" .. language .. "-evidence.json")
    return {
        language = language,
        stop = snapshot.stops,
        bytes = snapshot.bytes,
        changed = changed or "none",
        counter = counter,
        protobuf_age = proto,
        gzip_age = gzip,
    }
end
vim.keymap.set("n", "<leader>dd", function()
    demo.decoder_off = not demo.decoder_off
    require("dap-view.decoders").use(demo.decoder_off and "off" or "binary")
end)
vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
        dap.clear_breakpoints()
        vim.cmd.edit(source)
        demo.source = vim.api.nvim_get_current_buf()
        for line, text in ipairs(vim.api.nvim_buf_get_lines(demo.source, 0, -1, false)) do
            if text:find("STOP:", 1, true) then
                vim.api.nvim_win_set_cursor(0, { line, 0 })
                dap.set_breakpoint()
            end
        end
        vim.schedule(function()
            vim.o.statusline = " "
                .. language:upper()
                .. " | PROTOBUF + GZIP | F5 next snapshot | Space dd decoder on/off %=%f %l:%c "
        end)
    end,
})
