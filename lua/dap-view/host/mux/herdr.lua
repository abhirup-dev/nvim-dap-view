local mux = require("dap-view.host.mux")

---herdr adapter, the primary target. Verified against herdr 0.8.2.
---
---Every subcommand prints JSON on its own, so `--json` is neither needed nor
---accepted. Two shapes matter: `pane split` answers with `.result.pane.pane_id`,
---`tab create` with `.result.root_pane.pane_id`. Closing a tab's root pane closes
---the tab.
---@type dapview.Mux
local M = {}

---`pane split --direction` only takes `right` and `down` on 0.8.2
local DIRECTIONS = { right = true, down = true }

---A freshly created pane needs to reach a shell prompt before `pane run` types
---into it, so this is the budget for waiting on one
local PROMPT_TIMEOUT_MS = 3000

M.available = function()
    return vim.env.HERDR_ENV == "1" and vim.fn.executable("herdr") == 1
end

---@param handle string
M.is_alive = function(handle)
    return mux.succeeds({ "herdr", "pane", "read", handle, "--source", "visible" })
end

---@param out string
---@param ... string Path to the pane id inside `.result`
---@return string
local pane_id = function(out, ...)
    local ok, decoded = pcall(vim.json.decode, out)

    local id = ok and vim.tbl_get(decoded, "result", ...)

    if not id then
        error("herdr returned no pane id: " .. vim.trim(out))
    end

    return tostring(id)
end

---@param opts dapview.MuxSpawnOpts
---@return string
local split = function(opts)
    if not DIRECTIONS[opts.direction] then
        error(
            "herdr only splits 'right' or 'down', got '"
                .. tostring(opts.direction)
                .. "'. Use host.remote.pane.kind = 'tab' for a full pane"
        )
    end

    local argv = { "herdr", "pane", "split" }

    -- `--current` also works, but only when this Neovim *is* the pane; being
    -- explicit keeps a viewer spawned from an odd context in the right place
    if vim.env.HERDR_PANE_ID then
        vim.list_extend(argv, { "--pane", vim.env.HERDR_PANE_ID })
    else
        argv[#argv + 1] = "--current"
    end

    vim.list_extend(argv, { "--direction", opts.direction, "--cwd", opts.cwd, "--no-focus" })

    -- `--ratio` is a fraction; a size given in cells has no herdr equivalent
    if opts.size < 1 then
        vim.list_extend(argv, { "--ratio", tostring(opts.size) })
    end

    local out, err = mux.run(argv)

    if not out then
        error("herdr pane split failed: " .. tostring(err))
    end

    return pane_id(out, "pane", "pane_id")
end

---@param opts dapview.MuxSpawnOpts
---@return string
local tab = function(opts)
    local argv = { "herdr", "tab", "create" }

    if vim.env.HERDR_WORKSPACE_ID then
        vim.list_extend(argv, { "--workspace", vim.env.HERDR_WORKSPACE_ID })
    end

    vim.list_extend(argv, { "--cwd", opts.cwd, "--label", opts.label, "--no-focus" })

    local out, err = mux.run(argv)

    if not out then
        error("herdr tab create failed: " .. tostring(err))
    end

    return pane_id(out, "root_pane", "pane_id")
end

---@param cmd string
---@param opts dapview.MuxSpawnOpts
---@return string
M.spawn = function(cmd, opts)
    local handle = opts.kind == "tab" and tab(opts) or split(opts)

    -- `pane run` types the command and presses Enter, so the shell has to be
    -- there to receive it. Reading the pane back is the cheapest proof it is up
    vim.wait(PROMPT_TIMEOUT_MS, function()
        return M.is_alive(handle)
    end, 50)

    local _, err = mux.run({ "herdr", "pane", "run", handle, cmd })

    if err then
        M.close(handle)
        error("herdr pane run failed: " .. err)
    end

    return handle
end

---@param handle string
M.close = function(handle)
    mux.run({ "herdr", "pane", "close", handle })
end

return M
