-- Trusted local Lua configuration, loaded with dofile().
local directory = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
return {
    profile = "protobuf",
    max_bytes = 1024 * 1024,
    request_timeout_ms = 5000,
    commands = {
        person = {
            argv = {
                vim.fn.exepath("python3"),
                directory .. "/decode.py",
                "--descriptor",
                directory .. "/fixture.pb",
                "--type",
                "example.Person",
            },
            timeout_ms = 5000,
        },
    },
    profiles = {
        {
            name = "protobuf",
            decoders = {
                {
                    name = "Person protobuf",
                    kind = "command",
                    match = { type = "main.Envelope" },
                    command = "person",
                    source = { kind = "go_bytes", field = "Payload" },
                },
                {
                    name = "Person bytes",
                    kind = "command",
                    match = { name = "Payload", type = "[]uint8" },
                    command = "person",
                    source = { kind = "go_bytes" },
                },
            },
        },
        {
            name = "json",
            decoders = {
                {
                    name = "JSON",
                    kind = "lua",
                    match = { name = "json" },
                    decode = function(var)
                        local value = vim.json.decode(var.value)
                        -- Accommodate an adapter that quotes the JSON string once.
                        if type(value) == "string" then
                            value = vim.json.decode(value)
                        end
                        return require("dap-view.decoders").from_json(value)
                    end,
                },
            },
        },
        {
            name = "fields",
            decoders = {
                {
                    name = "Envelope fields",
                    kind = "rules",
                    match = { type = "main.Envelope" },
                    rename = { Payload = "serialized protobuf" },
                    order = { "serialized protobuf" },
                },
            },
        },
    },
}
