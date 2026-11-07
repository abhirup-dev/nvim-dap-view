-- Owner-side value decoding. Negative references belong exclusively to this module.
local M = {}
local profiles, cache, nodes = {}, {}, {}
local options = { commands = {}, allow_evaluate = false, max_bytes = 1048576 }
local active, generation, next_ref = nil, 0, -1
local refresh_pending = false

local function refresh()
    if refresh_pending then
        return
    end
    refresh_pending = true
    vim.schedule(function()
        refresh_pending = false
        local dap = require("dap")
        if not dap.session() or not dap.session().current_frame then
            return
        end
        require("dap-view.refresher").refresh_all_expressions()
        require("dap-view.refresher").refresh_session_based_views()
        local state = require("dap-view.state")
        if state.hover_bufnr and vim.api.nvim_buf_is_valid(state.hover_bufnr) and state.hovered_expression then
            coroutine.wrap(function()
                require("dap-view.hover.view").show(state.hover_bufnr)
            end)()
        end
    end)
end

function M.invalidate()
    generation = generation + 1
    cache, nodes = {}, {}
end

local function strings(t)
    assert(type(t) == "table" and vim.islist(t), "expected a list")
    for _, v in ipairs(t) do
        assert(type(v) == "string" and not v:find("%z"), "expected NUL-free strings")
    end
end

local function fields(t, allowed)
    assert(type(t) == "table", "expected an object")
    for k in pairs(t) do
        assert(allowed[k], "unknown decoder field: " .. tostring(k))
    end
end

-- Runtime registration is deliberately data-only. Local setup is the trust boundary.
local function register(profile, trusted)
    if not trusted then
        local count = 0
        local function data(value, depth)
            count = count + 1
            assert(count <= 10000 and depth <= 32, "profile exceeds size/depth limit")
            local kind = type(value)
            assert(
                kind == "table" or kind == "string" or kind == "number" or kind == "boolean",
                "profile must contain data only"
            )
            if kind == "string" then
                assert(#value <= 65536, "profile string too large")
            end
            if kind == "table" then
                assert(getmetatable(value) == nil, "profile metatables are forbidden")
                for k, v in pairs(value) do
                    data(k, depth + 1)
                    data(v, depth + 1)
                end
            end
        end
        data(profile, 0)
    end
    fields(profile, { name = true, decoders = true })
    assert(type(profile.name) == "string" and profile.name:match("^[%w_-]+$"), "invalid profile name")
    assert(type(profile.decoders) == "table" and vim.islist(profile.decoders), "decoders must be an ordered list")
    assert(#profile.decoders <= 64, "too many decoders")
    for _, d in ipairs(profile.decoders) do
        fields(d, {
            name = true,
            kind = true,
            match = true,
            decode = true,
            command = true,
            source = true,
            expression = true,
            hide = true,
            rename = true,
            order = true,
            computed = true,
        })
        assert(type(d.name) == "string" and #d.name > 0, "decoder name required")
        assert(vim.tbl_contains({ "command", "evaluate", "lua", "rules" }, d.kind), "invalid decoder kind")
        if type(d.match) == "function" then
            assert(trusted, "runtime Lua is forbidden")
        else
            fields(d.match, { name = true, type = true, path = true })
            assert(next(d.match), "match must constrain name, type or path")
            for _, v in pairs(d.match) do
                assert(type(v) == "string", "match values must be strings")
            end
        end
        if d.kind == "lua" then
            assert(trusted and type(d.decode) == "function", "Lua decoders require trusted local configuration")
        else
            assert(d.decode == nil, "decode functions are local Lua only")
        end
        if d.kind == "command" then
            -- Only a locally registered command ID; runtime callers cannot change argv.
            assert(type(d.command) == "string" and options.commands[d.command], "command is not allowlisted")
            fields(d.source, { kind = true, field = true, length = true })
            assert(vim.tbl_contains({ "go_bytes", "memory", "value" }, d.source.kind), "invalid payload source")
            if d.source.field then
                assert(type(d.source.field) == "string", "invalid source field")
            end
            if d.source.kind == "memory" then
                assert(
                    type(d.source.length) == "number"
                        and d.source.length >= 0
                        and d.source.length % 1 == 0
                        and d.source.length <= options.max_bytes,
                    "invalid memory length"
                )
            end
        end
        if d.kind == "evaluate" then
            assert(trusted and options.allow_evaluate, "target evaluation requires local opt-in")
            assert(type(d.expression) == "string", "expression required")
        end
        if d.kind == "rules" then
            if d.hide then
                strings(d.hide)
            end
            if d.order then
                strings(d.order)
            end
            if d.rename then
                assert(type(d.rename) == "table", "rename must be an object")
                for k, v in pairs(d.rename) do
                    assert(type(k) == "string" and type(v) == "string", "invalid rename")
                end
            end
            if d.computed then
                assert(trusted and options.allow_evaluate, "computed fields require local evaluation opt-in")
                for k, v in pairs(d.computed) do
                    assert(type(k) == "string" and type(v) == "string", "invalid computed field")
                end
            end
        end
    end
    profiles[profile.name] = vim.deepcopy(profile.decoders)
    M.invalidate()
    refresh()
    return { name = profile.name }
end

function M.register_decoder_profile(profile)
    return register(profile, false)
end

function M.use(name)
    assert(name == "off" or profiles[name], "unknown decoder profile: " .. tostring(name))
    active = name ~= "off" and name or nil
    M.invalidate()
    refresh()
    return { name = name }
end

function M.setup(config)
    config = config or {}
    options = vim.tbl_extend("force", { commands = {}, allow_evaluate = false, max_bytes = 1048576 }, config)
    assert(
        type(options.max_bytes) == "number" and options.max_bytes > 0 and options.max_bytes % 1 == 0,
        "invalid max_bytes"
    )
    assert(
        options.request_timeout_ms == nil
            or (type(options.request_timeout_ms) == "number" and options.request_timeout_ms > 0),
        "invalid request timeout"
    )
    for _, cmd in pairs(options.commands) do
        strings(cmd.argv)
        assert(#cmd.argv > 0 and cmd.argv[1]:sub(1, 1) == "/", "command executable must be an absolute path")
        assert(cmd.timeout_ms == nil or (type(cmd.timeout_ms) == "number" and cmd.timeout_ms > 0), "invalid timeout")
    end
    profiles, active = {}, nil
    for _, profile in ipairs(config.profiles or {}) do
        register(profile, true)
    end
    if config.profile then
        M.use(config.profile)
    else
        M.invalidate()
    end
end

local function context(session, path)
    return {
        session = session,
        path = path,
        frame_id = session.current_frame and session.current_frame.id,
        generation = generation,
    }
end

M.context = context

local function valid(ctx)
    return generation == ctx.generation
        and require("dap").session() == ctx.session
        and (ctx.session.current_frame and ctx.session.current_frame.id) == ctx.frame_id
end

M.is_current = valid

function M.original_value(reference, fallback)
    local node = nodes[reference]
    return node and node.raw and node.raw.value or fallback
end

local function ref(node)
    local id = next_ref
    next_ref = next_ref - 1 -- Never reuse IDs: stale UI actions cannot address a different node.
    nodes[id] = node
    return id
end

local function safe_name(name)
    return name:find("[%z\r\n]") and vim.json.encode(name) or name
end

local function raw_node(var, name)
    local v = vim.deepcopy(var)
    v.name, v.evaluateName, v._decoder_skip = safe_name(name or v.name), nil, true
    if v.variablesReference > 0 then
        v.variablesReference = ref({ raw = var })
    end
    return v
end

local function synthetic(var, depth)
    depth = depth or 0
    assert(depth < 64 and type(var) == "table" and type(var.name) == "string", "invalid decoded tree")
    assert(var.value == nil or type(var.value) == "string", "decoded values must be strings")
    assert(
        not var.variablesReference or var.variablesReference == 0,
        "decoders must return children, not adapter references"
    )
    local v = {
        name = safe_name(var.name),
        value = var.value or "",
        type = var.type,
        variablesReference = 0,
        _decoder_skip = true,
    }
    if var.children then
        assert(type(var.children) == "table" and vim.islist(var.children), "invalid children")
        local children = {}
        for _, child in ipairs(var.children) do
            children[#children + 1] = synthetic(child, depth + 1)
        end
        v.variablesReference = ref({ children = children })
    end
    return v
end

function M.from_json(value, name, depth)
    depth = depth or 0
    assert(depth < 64, "JSON exceeds maximum depth")
    if type(value) ~= "table" or value == vim.NIL then
        return { name = name or "decoded", value = vim.json.encode(value), variablesReference = 0 }
    end
    local node = { name = name or "decoded", value = vim.islist(value) and "[]" or "{}", children = {} }
    local keys = vim.tbl_keys(value)
    table.sort(keys, function(a, b)
        if type(a) == "number" and type(b) == "number" then
            return a < b
        end
        return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(keys) do
        node.children[#node.children + 1] = M.from_json(value[k], tostring(k), depth + 1)
    end
    return node
end

local function request(ctx, method, args)
    assert(valid(ctx), "debug state changed")
    local err, result
    if ctx.session.request_with_timeout then
        local co = assert(coroutine.running(), "decoder adapter work requires a coroutine")
        ctx.session:request_with_timeout(method, args, options.request_timeout_ms or 5000, function(e, r)
            vim.schedule(function()
                local ok, failure = coroutine.resume(co, e, r)
                if not ok then
                    vim.notify(tostring(failure), vim.log.levels.ERROR)
                end
            end)
        end)
        err, result = coroutine.yield()
    else
        err, result = ctx.session:request(method, args)
    end
    assert(valid(ctx), "debug state changed")
    assert(not err, type(err) == "table" and err.message or tostring(err))
    assert(result, "adapter returned no result")
    return result
end

local function children(var, ctx)
    if var.variablesReference == 0 then
        return {}
    end
    return request(ctx, "variables", { variablesReference = var.variablesReference }).variables or {}
end

local function payload(var, source, ctx)
    if source.field then
        local found
        for _, v in ipairs(children(var, ctx)) do
            if v.name == source.field then
                found = v
                break
            end
        end
        assert(found, "payload field not found: " .. source.field)
        var = found
    end
    if source.kind == "value" then
        -- Explicit adapter value input, never claimed to be complete bytes.
        assert(#var.value <= options.max_bytes, "payload exceeds max_bytes")
        return var.value
    elseif source.kind == "memory" then
        assert(var.memoryReference, "adapter did not supply memoryReference")
        local r = request(ctx, "readMemory", { memoryReference = var.memoryReference, count = source.length })
        assert(not r.unreadableBytes or r.unreadableBytes == 0, "adapter returned unreadable bytes")
        local data = vim.base64.decode(r.data or "")
        assert(#data == source.length, "adapter returned incomplete memory")
        return data
    end
    -- Delve byte slices: obtain exact length independently of pretty-printing,
    -- then read every numeric element through DAP paging. Never parse the slice summary.
    assert(var.type == "[]uint8" or var.type == "[]byte", "go_bytes requires []byte/[]uint8")
    assert(var.evaluateName, "go_bytes requires an adapter evaluateName")
    local r = request(
        ctx,
        "evaluate",
        { expression = "len(" .. var.evaluateName .. ")", context = "watch", frameId = ctx.frame_id }
    )
    local count = tonumber(r.result)
    assert(count and count >= 0 and count % 1 == 0 and count <= options.max_bytes, "invalid or oversized byte length")
    local data = {}
    for start = 0, count - 1, 256 do
        local n = math.min(256, count - start)
        local page = request(
            ctx,
            "variables",
            { variablesReference = var.variablesReference, filter = "indexed", start = start, count = n }
        )
        local seen = {}
        for _, byte in ipairs(page.variables or {}) do
            local index = tonumber(byte.name:match("^%[(%d+)%]$"))
            if index and index >= start and index < start + n then
                local b = tonumber(byte.value:match("^(%d+)"))
                assert(b and b >= 0 and b <= 255 and not seen[index], "invalid byte returned by adapter")
                seen[index], data[index + 1] = true, string.char(b)
            end
        end
        for i = start, start + n - 1 do
            assert(seen[i], "adapter returned incomplete bytes (indexed paging required)")
        end
    end
    return table.concat(data)
end
M.read_payload = payload

local function decode(d, var, ctx, done)
    if d.kind == "lua" then
        done(d.decode(var, ctx))
        return
    end
    if d.kind == "evaluate" then
        assert(var.evaluateName, "evaluateName required")
        local expr = d.expression:gsub("{expression}", function()
            return var.evaluateName
        end)
        local r = request(ctx, "evaluate", { expression = expr, context = "watch", frameId = ctx.frame_id })
        done({
            value = r.result,
            _adapter = { name = "decoded", value = r.result, variablesReference = r.variablesReference or 0 },
        })
    elseif d.kind == "rules" then
        local result = {}
        for _, child in ipairs(children(var, ctx)) do
            if not vim.tbl_contains(d.hide or {}, child.name) then
                result[#result + 1] = raw_node(child, (d.rename or {})[child.name] or child.name)
            end
        end
        for name, expr in pairs(d.computed or {}) do
            local r = request(ctx, "evaluate", { expression = expr, context = "watch", frameId = ctx.frame_id })
            result[#result + 1] =
                raw_node({ name = name, value = r.result, variablesReference = r.variablesReference or 0 })
        end
        local rank = {}
        for i, name in ipairs(d.order or {}) do
            rank[name] = i
        end
        table.sort(result, function(a, b)
            if (rank[a.name] or math.huge) == (rank[b.name] or math.huge) then
                return a.name < b.name
            end
            return (rank[a.name] or math.huge) < (rank[b.name] or math.huge)
        end)
        done({ value = "rules", _children = result })
    else
        local input = payload(var, d.source, ctx)
        local cmd = options.commands[d.command]
        local output, errors, size, overflow = {}, {}, 0, false
        vim.system(cmd.argv, {
            stdin = input,
            timeout = cmd.timeout_ms or 5000,
            stdout = function(err, data)
                if err then
                    errors[#errors + 1] = tostring(err)
                end
                if data then
                    size = size + #data
                    if size <= options.max_bytes then
                        output[#output + 1] = data
                    else
                        overflow = true
                    end
                end
            end,
            stderr = function(_, data)
                if data and #errors < 8 then
                    errors[#errors + 1] = data:sub(1, 1024)
                end
            end,
        }, function(result)
            vim.schedule(function()
                if not valid(ctx) then
                    return
                end
                local ok, decoded = pcall(function()
                    assert(result.code == 0, "command failed: " .. table.concat(errors):sub(1, 2048))
                    assert(not overflow, "command output exceeds max_bytes")
                    return M.from_json(vim.json.decode(table.concat(output)))
                end)
                if ok then
                    done({ value = decoded.value, children = decoded.children or { decoded } })
                else
                    done(nil, decoded)
                end
            end)
        end)
    end
end

function M.prepare(var, path, session)
    if not active or not session or not session.current_frame or var._decoder_skip or var.variablesReference < 0 then
        return var
    end
    local ctx = context(session, path)
    local key = table.concat({
        tostring(session),
        tostring(ctx.frame_id),
        path,
        var.value or "",
        var.evaluateName or var.name,
        var.type or "",
    }, "\0")
    local entry = cache[key]
    if not entry then
        local selected
        for _, d in ipairs(profiles[active] or {}) do
            local ok, matches = pcall(function()
                if type(d.match) == "function" then
                    return d.match(var, ctx)
                end
                for k, v in pairs(d.match) do
                    if (k == "path" and path or var[k]) ~= v then
                        return false
                    end
                end
                return true
            end)
            if ok and matches then
                selected = d
                break
            end
        end
        if not selected then
            return var
        end
        entry = {
            raw = vim.deepcopy(var),
            decoder = selected,
            ctx = ctx,
            value = var.value .. " [" .. selected.name .. "]",
        }
        entry.reference = ref(entry)
        cache[key] = entry
    end
    local v = vim.tbl_extend("force", var, { value = entry.value, variablesReference = entry.reference })
    return v
end

function M.format_value(var, path, ctx)
    return M.prepare(var, path, ctx.session).value
end

-- Same resolver used by scopes, watches and hover; never send plugin IDs to DAP.
function M.resolve_children(var, path, ctx)
    local reference = type(var) == "number" and var or var.variablesReference
    local session = ctx.session
    local node = nodes[reference]
    if reference < 0 then
        if not node then
            return nil, { variables = {} }
        end
        if node.ctx and not valid(node.ctx) then
            return nil, { variables = {} }
        end
        if node.children then
            return nil, { variables = node.children }
        end
        if not node.decoder then
            local err, response = session:request("variables", { variablesReference = node.raw.variablesReference })
            if err then
                return err
            end
            return nil,
                {
                    variables = vim.tbl_map(function(v)
                        return raw_node(v)
                    end, response.variables or {}),
                }
        end
        if not node.started then
            node.started = true
            coroutine.wrap(function()
                local function done(result, err)
                    if not valid(node.ctx) then
                        return
                    end
                    local ok, failure = pcall(function()
                        assert(not err, tostring(err))
                        assert(type(result) == "table", "decoder returned no result")
                        assert(result.value == nil or type(result.value) == "string", "decoder value must be a string")
                        local decoded = result._adapter and raw_node(result._adapter)
                            or synthetic({ name = "decoded", value = result.value, children = result.children })
                        if result._children then
                            decoded.variablesReference = ref({ children = result._children })
                        end
                        node.children = { raw_node(node.raw, "raw"), decoded }
                        node.value = result.value or node.value
                    end)
                    if not ok then
                        node.children = {
                            raw_node(node.raw, "raw"),
                            synthetic({ name = "decode error", value = tostring(failure) }),
                        }
                        node.value = node.raw.value .. " [decode failed]"
                    end
                    refresh()
                end
                local ok, err = pcall(decode, node.decoder, node.raw, node.ctx, done)
                if not ok then
                    done(nil, err)
                end
            end)()
        end
        return nil,
            {
                variables = node.children
                    or { raw_node(node.raw, "raw"), synthetic({ name = "decoded", value = "Loading…" }) },
            }
    end
    if reference == 0 then
        return nil, { variables = {} }
    end
    local stamp = context(session, path)
    local err, response = session:request(
        "variables",
        vim.tbl_extend("force", ctx.variables_args or {}, { variablesReference = reference })
    )
    if not valid(stamp) then
        return nil, { variables = {} }
    end
    if err then
        return err
    end
    return nil,
        {
            variables = vim.tbl_map(function(v)
                return M.prepare(v, path .. "." .. v.name, session)
            end, (response or {}).variables or {}),
        }
end

return M
