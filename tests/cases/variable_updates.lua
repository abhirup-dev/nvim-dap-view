local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local D = require("dap-view.decoders")
local view, state = require("dap-view"), require("dap-view.state")
H.setup({
    host = { default = os.getenv("HOST") or "split" },
    winbar = { default_section = "scopes" },
    decoders = {
        profile = "json",
        profiles = {
            {
                name = "json",
                decoders = {
                    {
                        name = "JSON",
                        kind = "lua",
                        match = { name = "payload" },
                        decode = function(v)
                            return D.from_json(vim.json.decode(v.value))
                        end,
                    },
                },
            },
        },
    },
})
local fake = H.new_fake_session()
fake.current_frame.scopes = { { name = "Locals", variablesReference = 100 } }
local count, age = 1, 37
local function variables()
    return {
        { name = "count", value = tostring(count), type = "int", variablesReference = 0 },
        { name = "unchanged", value = "99", type = "int", variablesReference = 0 },
        {
            name = "payload",
            value = vim.json.encode({ age = age, name = "Ada" }),
            type = "string",
            variablesReference = 0,
        },
    }
end
fake.request = function(_, command, _, callback)
    local response = command == "variables" and { variables = variables() }
        or { result = variables()[3].value, type = "string", variablesReference = 0 }
    if callback then
        vim.schedule(function()
            callback(nil, response)
        end)
        return
    end
    return nil, response
end
H.install_session(fake)
local function updates()
    local paths = {}
    for _, mark in
        ipairs(
            vim.api.nvim_buf_get_extmarks(state.bufnr, require("dap-view.globals").NAMESPACE, 0, -1, { details = true })
        )
    do
        if mark[4].hl_group == "NvimDapViewWatchUpdated" then
            local line = mark[2] + 1
            local path = state.line_to_variable_path[line]
            if state.current_section == "watches" then
                local v, e = state.variable_views_by_line[line], state.expression_views_by_line[line]
                path = v and v.view.path or e and e.expression
            end
            if path then
                paths[path] = true
            end
        end
    end
    return paths
end
local function render(section)
    view.show_view(section)
    H.pump(100)
end
local function stop(section)
    D.invalidate()
    if section == "watches" then
        coroutine.wrap(function()
            require("dap-view.watches.eval").evaluate_expression("payload", true)
        end)()
    end
    render(section)
end
view.open()
state.variable_path_is_expanded["Locals.payload"] = true
state.variable_path_is_expanded["Locals.payload.decoded"] = true
render("scopes")
stop("scopes")
H.eq(updates(), {}, "unchanged stop has no scopes update markers")
count = 2
stop("scopes")
H.eq(updates(), { ["Locals.count"] = true }, "only changed native variable is marked after decoder redraws")
render("scopes")
H.eq(updates(), { ["Locals.count"] = true }, "redraw retains native change marker for this stop")
age = 38
stop("scopes")
H.ok(updates()["Locals.payload.decoded.age"], "changed decoded scalar is marked after async completion")
H.ok(not updates()["Locals.payload.decoded.name"], "unchanged decoded sibling keeps ordinary color")
H.ok(not updates()["Locals.count"], "previous stop's change is cleared")
render("scopes")
H.ok(updates()["Locals.payload.decoded.age"], "redraw retains decoded change marker")
stop("scopes")
H.eq(updates(), {}, "next no-op stop clears all changes")

view.add_expr("payload", true)
H.pump(80)
state.watched_expressions.payload.children[2].expanded = true
stop("watches")
stop("watches")
H.eq(updates(), {}, "unchanged watch evaluation is not marked")
age = 39
stop("watches")
H.ok(updates()["payload.decoded.age"], "changed decoded watch child is marked")
H.ok(not updates()["payload.decoded.name"], "unchanged decoded watch child keeps ordinary color")
coroutine.wrap(function()
    require("dap-view.watches.eval").evaluate_expression("payload", true)
end)()
render("watches")
H.ok(updates()["payload.decoded.age"], "watch re-evaluation within same stop retains marker")
stop("watches")
H.eq(updates(), {}, "next no-op stop clears watch changes")
fake.current_frame = { id = 12, scopes = { { name = "Locals", variablesReference = 100 } } }
age = 40
stop("watches")
H.eq(updates(), {}, "another frame starts a fresh comparison")
fake.stopped_thread_id = 2
age = 41
stop("scopes")
H.eq(updates(), {}, "another thread starts a fresh comparison")
local other = H.new_fake_session()
other.current_frame.scopes = fake.current_frame.scopes
other.request = fake.request
H.install_session(other)
age = 42
stop("scopes")
H.eq(updates(), {}, "another session cannot inherit old change markers")
local function frame(id, name)
    other.current_frame = {
        id = id,
        name = name,
        source = { path = "/demo/program.lua" },
        scopes = fake.current_frame.scopes,
    }
    other.threads[1].frames = { other.current_frame }
end
frame(20, "run")
stop("scopes")
count = 3
frame(21, "run")
stop("scopes")
H.eq(updates(), { ["Locals.count"] = true }, "logical frame survives adapter reallocation of frame IDs")
count = 4
frame(21, "another_function")
stop("scopes")
H.eq(updates(), {}, "reused frame ID for another function does not compare unrelated locals")
H.done()
