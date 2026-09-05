# nvim-dap-mcp

Agent-facing MCP layer over [nvim-dap](https://github.com/mfussenegger/nvim-dap).
One debug session, shared between the human's Neovim UI and an MCP client.

Phase 5a (this repo, so far) is the Lua core only: a tool registry, a
coroutine-based dispatcher with a `pending`/`ticket` contract, and the tools
themselves. The Go sidecar that speaks MCP over HTTP is Phase 5b.

    require("dap-mcp").setup({})
    require("dap-mcp").call("session_status", {})

See the contract paragraph at the top of `lua/dap-mcp/init.lua`.
