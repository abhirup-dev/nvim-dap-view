-- Exact DAP binary extraction + async protobuf/gzip commands; used by binary-init.lua. 2026-11-07.
local directory = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local D = require("dap-view.decoders")
local language = vim.env.DEMO_LANG or "python"
local manifest = vim.json.decode(table.concat(vim.fn.readfile(directory .. "/binary-manifest.json"), "\n"))
_G.binary_metrics = {}
local function evaluate(ctx, expression)
    local err, result = ctx.session:request(
        "evaluate",
        { expression = expression, context = language == "lua" and "repl" or "watch", frameId = ctx.frame_id }
    )
    assert(not err, vim.inspect(err))
    assert(result, "missing evaluate response")
    return result.result
end
local function bytes(variable, ctx)
    if language == "go" then
        return D.read_payload(variable, { kind = "go_bytes" }, ctx)
    end
    local expression = variable.evaluateName or variable.name
    if language == "lua" then
        expression = "(" .. expression .. ").data"
    end
    local count = tonumber(evaluate(ctx, language == "lua" and ("#" .. expression) or ("len(" .. expression .. ")")))
    assert(count and count >= 0 and count < 1048576, "invalid binary length")
    local result = {}
    for start = 0, count - 1, 32 do
        local finish = math.min(count, start + 32)
        if language == "lua" then
            local data = evaluate(ctx, ("vim.base64.encode((%s):sub(%d,%d))"):format(expression, start + 1, finish))
            if data:sub(1, 1) == '"' then
                data = vim.json.decode(data)
            end
            local decoded = vim.base64.decode(data)
            assert(#decoded == finish - start, "truncated Lua binary slice")
            result[#result + 1] = decoded
        else
            assert(variable.type == "bytes" or variable.type == "bytearray", "expected Python bytes")
            local displayed = evaluate(ctx, ("(%s)[%d:%d].hex()"):format(expression, start, finish))
            local hex = displayed:match([[^['"]([0-9a-f]*)['"]$]])
            assert(hex and #hex == 2 * (finish - start), "truncated Python hex slice: " .. displayed)
            result[#result + 1] = (
                hex:gsub("..", function(pair)
                    return string.char(tonumber(pair, 16))
                end)
            )
        end
    end
    return table.concat(result)
end
local function decode(kind)
    return function(variable, ctx)
        local raw = bytes(variable, ctx)
        local co = assert(coroutine.running())
        vim.system(
            { directory .. "/deps/venv/bin/python", directory .. "/binary-codec.py", kind },
            { stdin = raw, text = true },
            function(result)
                vim.schedule(function()
                    assert(coroutine.resume(co, result))
                end)
            end
        )
        local response = coroutine.yield()
        assert(response.code == 0, response.stderr)
        local body = vim.json.decode(response.stdout)
        local matched
        for name, expected in pairs(manifest) do
            if name:find(kind, 1, true) == 1 and expected.sha256 == body.sha256 then
                assert(body.bytes == expected.bytes, "byte length mismatch")
                matched = name
            end
        end
        assert(matched, "DAP bytes do not match any source fixture")
        binary_metrics[variable.name] = {
            bytes = body.bytes,
            sha256 = body.sha256,
            fixture = matched,
            generation = ctx.generation,
            frame_id = ctx.frame_id,
        }
        return D.from_json(body.decoded)
    end
end
return {
    profile = "binary",
    profiles = {
        {
            name = "binary",
            decoders = {
                {
                    name = "Protobuf Person",
                    kind = "lua",
                    match = { name = "protobuf_wire" },
                    decode = decode("protobuf"),
                },
                { name = "Gzip JSON", kind = "lua", match = { name = "gzip_wire" }, decode = decode("gzip") },
            },
        },
    },
}
