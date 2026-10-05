local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local D = require("dap-view.decoders")
H.setup({})
local fake = H.new_fake_session()
H.install_session(fake)
local python = vim.fn.exepath("python3")
assert(python ~= "", "python3 required for decoder subprocess tests")
D.setup({
    commands = {
        slow = { argv = { python, "-c", "import sys,time; time.sleep(.15); print(sys.stdin.read())" } },
        broken = { argv = { python, "-c", 'print("not JSON")' } },
        timeout = { argv = { python, "-c", "import time; time.sleep(3)" }, timeout_ms = 30 },
        huge = { argv = { python, "-c", 'print("x"*4096)' } },
    },
    max_bytes = 1024,
})
local function profile(command)
    return {
        name = command,
        decoders = {
            {
                name = command,
                kind = "command",
                match = { name = "payload" },
                command = command,
                source = {
                    kind = "value",
                },
            },
        },
    }
end
for _, name in ipairs({ "slow", "broken", "timeout", "huge" }) do
    H.ok(pcall(D.register_decoder_profile, profile(name)), "validated command ID: " .. name)
end
local var = {
    name = "payload",
    value = '{"text":"$(touch /tmp/never-decoder-shell); `id`"}',
    type = "string",
    variablesReference = 0,
}
local function resolve(v)
    local e, r = D.resolve_children(v, "payload", { session = fake })
    assert(not e)
    return r.variables
end
D.use("slow")
local prepared = D.prepare(var, "payload", fake)
local time = vim.uv.hrtime()
H.eq(resolve(prepared)[2].value, "Loading…", "async loading placeholder")
H.ok((vim.uv.hrtime() - time) / 1e6 < 100, "subprocess does not block UI")
local tick = false
vim.schedule(function()
    tick = true
end)
H.pump(30)
H.ok(tick, "event loop runs during command")
H.ok(
    vim.wait(2000, function()
        return resolve(prepared)[2].value ~= "Loading…"
    end, 10),
    "command completes"
)
local decoded = resolve(prepared)[2]
local fields = resolve(decoded)
H.eq(fields[1].value, '"$(touch /tmp/never-decoder-shell); `id`"', "payload passed literally through stdin")
H.ok(not vim.uv.fs_stat("/tmp/never-decoder-shell"), "no shell interpolation")
for _, name in ipairs({ "broken", "timeout", "huge" }) do
    D.use(name)
    local v = D.prepare(var, "payload", fake)
    resolve(v)
    H.ok(
        vim.wait(2000, function()
            return resolve(v)[2].name == "decode error"
        end, 10),
        name .. " fallback"
    )
    H.eq(resolve(v)[1].name, "raw", name .. " keeps raw")
end
D.use("slow")
local old = D.prepare(var, "payload", fake)
resolve(old)
D.use("off")
H.pump(250)
H.eq(resolve(old), {}, "late completion after profile switch discarded")
D.use("slow")
old = D.prepare(var, "payload", fake)
resolve(old)
fake.current_frame = { id = 999 }
H.pump(250)
H.eq(resolve(old), {}, "late completion after frame switch discarded")
old = D.prepare(var, "payload", fake)
resolve(old)
H.install_session(nil)
H.pump(250)
H.eq(resolve(old), {}, "late completion after session termination discarded")
H.install_session(fake)
local invalid = profile("slow")
invalid.decoders[1].argv = { "/bin/sh" }
H.ok(not pcall(D.register_decoder_profile, invalid), "runtime argv injection rejected")
invalid = profile("slow")
invalid.decoders[1].hide = { function() end }
H.ok(not pcall(D.register_decoder_profile, invalid), "nested code rejected even in unused field")
D.setup({
    allow_evaluate = true,
    profiles = {
        {
            name = "eval",
            decoders = {
                { name = "eval", kind = "evaluate", match = { name = "x" }, expression = "{expression}" },
            },
        },
    },
    profile = "eval",
})
local v = D.prepare({ name = "x", value = "1", evaluateName = "x", variablesReference = 0 }, "x", fake)
resolve(v)
H.pump(100)
H.eq(resolve(v)[2].value, "evaluated:x", "locally opted-in evaluate decoder")
D.setup({})
-- An adapter that ignores paging must never supply partial binary to the subprocess.
fake.request = function(_, method, args)
    if method == "evaluate" then
        return nil, { result = "300" }
    end
    return nil, { variables = { { name = "[0]", value = "0 = 0x0", variablesReference = 0 } } }
end
local bytes = { name = "bytes", type = "[]uint8", value = "truncated", evaluateName = "bytes", variablesReference = 20 }
local ok, err = pcall(D.read_payload, bytes, { kind = "go_bytes" }, D.context(fake, "bytes"))
H.ok(not ok and tostring(err):find("incomplete bytes", 1, true), "incomplete adapter paging rejected")
fake.request = function()
    return nil, { data = vim.base64.encode("abc"), unreadableBytes = 0 }
end
H.eq(
    D.read_payload({ memoryReference = "opaque" }, { kind = "memory", length = 3 }, D.context(fake, "bytes")),
    "abc",
    "complete readMemory payload"
)
H.ok(
    not pcall(D.read_payload, { memoryReference = "opaque" }, { kind = "memory", length = 4 }, D.context(fake, "bytes")),
    "short readMemory rejected"
)
local array = {}
for i = 1, 12 do
    array[i] = i
end
local tree = D.from_json(array)
H.eq(tree.children[2].name, "2", "JSON arrays retain numeric order past nine elements")
H.eq(tree.children[12].value, "12", "JSON array final element")
D.use("off")
H.done()
