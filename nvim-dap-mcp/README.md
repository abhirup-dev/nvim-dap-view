# nvim-dap-mcp

Agent-facing MCP layer over [nvim-dap](https://github.com/mfussenegger/nvim-dap).
One debug session, shared between the human's Neovim UI and an MCP client:
breakpoints the agent sets show up in the gutter, and the frame it steps to is
the frame on screen.

```
 Claude / Pi ──MCP streamable HTTP (127.0.0.1:28911/mcp)──► nvim-dap-mcp (Go)
                                                                 │ msgpack-rpc
                                                                 ▼
                                                       lua/dap-mcp/*.lua
                                                                 │
                                                            nvim-dap ──► delve / debugpy
```

The Go sidecar authors nothing. It reads the tool list and JSON schemas from
`require("dap-mcp").tools()` and forwards every call to one Lua entry point,
`require("dap-mcp").call(name, args)`. See the contract paragraph at the top of
`lua/dap-mcp/init.lua`.

## Install

The sidecar is a Go binary and has to be built. With lazy.nvim:

```lua
{
  "abhirup-dev/nvim-dap-mcp",
  dependencies = { "mfussenegger/nvim-dap" },
  build = "make build",
  opts = {},
}
```

`make build` writes `bin/nvim-dap-mcp` inside the plugin directory, which is
where the plugin looks for it. Point `sidecar.bin` elsewhere if you build it
somewhere else. Requires Go 1.25 or newer to build; nothing at runtime.

## Configure

```lua
require("dap-mcp").setup({
  port = 28911,
  bind = "127.0.0.1",
  token = nil,             -- nil = no auth; safe because the bind is loopback
  autostart = "on_session", -- "never" | "on_session" | "always"
  response = { source_context = 10, max_value_width = 200, max_children = 50 },
  evaluate = { allow_side_effects = false },
  ui = { integrate_dap_view = true },
  sidecar = { bin = nil }, -- defaults to <plugin root>/bin/nvim-dap-mcp
})
```

`autostart = "on_session"` brings the sidecar up on the first
`event_initialized`, so it is running exactly when there is something to debug.
`"always"` starts it in `setup()`; `"never"` waits for `:DapMcp start`.

Set `token` to a string to require `Authorization: Bearer <token>`. Do that if
you change `bind` away from loopback — the sidecar logs a warning if you don't.

## Commands

    :DapMcp start           start the sidecar
    :DapMcp stop            stop it
    :DapMcp status          pid, url, binary path, last error
    :DapMcp tools           print the tool surface
    :DapMcp call <tool> [json]   run one tool by hand

## Register with a client

`examples/mcp.json` is ready to copy into `.mcp.json` for Claude Code:

```json
{
  "mcpServers": {
    "nvim-dap": { "type": "http", "url": "http://127.0.0.1:28911/mcp" }
  }
}
```

Start Neovim first — the sidecar is its child, and with no editor there is
nothing to connect to. If you set a `token`, add the header:

```json
"headers": { "Authorization": "Bearer <the token from setup()>" }
```

`skills/nvim-dap-mcp/SKILL.md` is a companion skill worth installing alongside
it: it tells the agent to call `wait_for_pause` after every control action and
never to poll `session_status`.

## Develop

    make build     # bin/nvim-dap-mcp
    make test      # go test ./... then the Lua suite
    make check     # go vet + stylua --check
    scripts/smoke.sh

The Go tests start a real headless Neovim with the plugin loaded and talk to it
over a socket; no debug adapter is involved, so what they cover is the bridge
(the registry, immediate calls, the pending/poll loop, error codes) and the MCP
handshake. The Lua suite runs against a fake session.
