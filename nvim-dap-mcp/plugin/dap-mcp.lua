if vim.g.loaded_dap_mcp then
    return
end
vim.g.loaded_dap_mcp = true

local function print_tools()
    for _, tool in ipairs(require("dap-mcp").tools()) do
        print(("%-22s %s"):format(tool.name, tool.description))
    end
end

---`:DapMcp call <name> [json]` -- manual testing only. Pending results are
---polled here so the command always prints a finished answer.
local function call(name, json)
    if not name then
        vim.notify("Usage: :DapMcp call <tool> [json args]", vim.log.levels.ERROR)
        return
    end

    local args = {}
    if json and json ~= "" then
        local ok, decoded = pcall(vim.json.decode, json)
        if not ok or type(decoded) ~= "table" then
            vim.notify("Could not parse arguments as a JSON object: " .. json, vim.log.levels.ERROR)
            return
        end
        args = decoded
    end

    require("dap-mcp").call_async(name, args, function(result)
        vim.notify(vim.inspect(result))
    end)
end

local function print_status()
    local status = require("dap-mcp.sidecar").status()

    local lines = {
        ("running:   %s"):format(status.running),
        ("url:       %s"):format(status.url or "-"),
        ("pid:       %s"):format(status.pid or "-"),
        ("binary:    %s"):format(status.binary),
        ("autostart: %s"):format(status.autostart),
    }
    if status.last_error then
        table.insert(lines, ("last error: %s"):format(status.last_error))
    end

    print(table.concat(lines, "\n"))
end

local ACTIONS = { "tools", "call", "start", "stop", "status" }

vim.api.nvim_create_user_command("DapMcp", function(opts)
    local action = opts.fargs[1]
    local sidecar = require("dap-mcp.sidecar")

    if action == "tools" then
        print_tools()
    elseif action == "call" then
        call(opts.fargs[2], table.concat(vim.list_slice(opts.fargs, 3), " "))
    elseif action == "start" then
        sidecar.start()
    elseif action == "stop" then
        if not sidecar.stop() then
            vim.notify("dap-mcp: the sidecar is not running", vim.log.levels.WARN)
        end
    elseif action == "status" then
        print_status()
    else
        vim.notify("Usage: :DapMcp start | stop | status | tools | call <tool> [json args]", vim.log.levels.ERROR)
    end
end, {
    nargs = "*",
    complete = function(_, line)
        if line:match("^%s*DapMcp%s+%S*$") then
            return ACTIONS
        end

        if line:match("^%s*DapMcp%s+call%s+%S*$") then
            return vim.tbl_map(function(tool)
                return tool.name
            end, require("dap-mcp").tools())
        end

        return {}
    end,
    desc = "Drive the nvim-dap-mcp sidecar and tool surface",
})
