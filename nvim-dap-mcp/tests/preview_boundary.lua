local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local H = dofile(repo .. "/../tests/harness.lua")
vim.opt.runtimepath:prepend(repo)
H.setup({ host = { default = "split" } })
local fake = H.new_fake_session()
H.install_session(fake)
local calls = {}
fake.request = function(_, method, args)
    calls[#calls + 1] = { method = method, args = args }
    return nil, { value = "9", variables = {} }
end
require("dap-mcp.tools.variables")
local decoders = require("dap-view.decoders")
decoders.setup({
    profile = "preview",
    profiles = {
        {
            name = "preview",
            decoders = {
                {
                    name = "preview",
                    kind = "lua",
                    match = { name = "x" },
                    decode = function()
                        return { value = "decoded" }
                    end,
                },
            },
        },
    },
})
local preview = decoders.prepare({ name = "x", value = "raw", variablesReference = 100 }, "Locals.x", fake)
H.ok(preview.variablesReference < 0, "real decoder produces synthetic reference")
local dispatch = require("dap-mcp.dispatch")
for _, ref in ipairs({ preview.variablesReference, 0, -1.5, 1.5, math.huge }) do
    local result = dispatch.call("set_variable", { variables_reference = ref, name = "decoded", value = "9" })
    H.ok(not result.ok and result.error.code == "invalid_argument", "invalid mutation reference rejected: " .. ref)
end
H.eq(#calls, 0, "preview and invalid references never reach adapter")
local result = dispatch.call("set_variable", { variables_reference = 100, name = "x", value = "9" })
H.ok(result.ok and result.result.value == "9", "ordinary adapter variable remains writable")
H.eq(calls[1].args.variablesReference, 100, "positive reference forwarded unchanged")
H.done()
