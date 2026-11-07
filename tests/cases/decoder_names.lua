local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local D = require("dap-view.decoders")
local state = require("dap-view.state")
local keys = { "a\nb", "c\rd", "e\0f" }
local data = {}
for i, key in ipairs(keys) do
    data[key] = i
end
H.setup({
    host = { default = os.getenv("HOST") or "split" },
    winbar = { default_section = "watches" },
    decoders = {
        profile = "keys",
        profiles = {
            {
                name = "keys",
                decoders = {
                    {
                        name = "Keys",
                        kind = "lua",
                        match = { name = "payload" },
                        decode = function()
                            return D.from_json(data)
                        end,
                    },
                },
            },
        },
    },
})
local fake = H.new_fake_session()
H.install_session(fake)
require("dap-view").open()
H.pump(30)
local prepared = D.prepare({ name = "payload", value = "{}", variablesReference = 0 }, "payload", fake)
local failure, response = D.resolve_children(prepared, "payload", { session = fake })
assert(not failure, vim.inspect(failure))
local raw, decoded = response.variables[1], response.variables[2]
local child_error, children = D.resolve_children(decoded, "payload.decoded", { session = fake })
assert(not child_error, vim.inspect(child_error))
local views, names = {}, {}
for _, variable in ipairs(children.variables) do
    names[variable.name] = true
    views[#views + 1] = {
        variable = variable,
        path = "payload.decoded." .. variable.name,
        expanded = false,
        reference = decoded.variablesReference,
    }
    H.ok(not variable.name:find("[%z\r\n]"), "synthetic name is one printable line")
end
for _, key in ipairs(keys) do
    H.ok(names[vim.json.encode(key)], "decoded key is preserved through JSON escaping")
end
state.watched_expressions = {
    payload = {
        id = 1,
        expanded = true,
        response = { result = prepared.value, variablesReference = prepared.variablesReference },
        children = {
            { variable = raw, path = "payload.raw", expanded = false, reference = prepared.variablesReference },
            {
                variable = decoded,
                path = "payload.decoded",
                expanded = true,
                children = views,
                reference = prepared.variablesReference,
            },
        },
    },
}
local rendered, error_message = pcall(require("dap-view.watches.view").show)
H.ok(rendered, "watch renderer accepts valid decoded JSON control-character keys", error_message)
H.done()
