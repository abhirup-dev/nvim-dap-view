# nvim-dap-view

Neovim UI for [nvim-dap](https://github.com/mfussenegger/nvim-dap), with a
collocated MCP sidecar and custom value decoders. Requires Neovim 0.11+.

Fork of [igorlfs/nvim-dap-view](https://github.com/igorlfs/nvim-dap-view).

## Install

With lazy.nvim:

```lua
{
  "abhirup-dev/nvim-dap-view",
  dependencies = { "mfussenegger/nvim-dap" },
  opts = {},
}
```

## Use

Start a session through nvim-dap, then run `:DapViewOpen`. Select sections using
winbar shortcuts and press `g?` for the current section's actions.
`:DapViewClose` closes the UI; terminate the debug session separately.

The UI provides scopes, watches, frames/threads, breakpoints, hover, REPL and
virtual values, with split, dedicated-tab and detached-viewer hosts.
Configuration and commands are documented in `:help dap-view.txt`.

- [MCP installation, configuration and tool usage](nvim-dap-mcp/README.md).
- [Custom value decoders, protobuf examples and RPC profile registration](docs/value-decoders.md).
- [Retained Statechart findings and models](docs/audits/statechart/2026-11-07/README.md).

## Develop

```sh
nvim --headless -u NONE -l tests/run.lua
make -C nvim-dap-mcp test
make -C nvim-dap-mcp check
```

The UI harness needs nvim-dap on the runtime path. Set `NVIM_DAP_PATH` when it
is installed outside `~/.local/share/nvim/lazy/nvim-dap`.

## Attribution

See [LICENSE](LICENSE). Upstream credits include nvim-dap-ui,
nvim-dap-virtual-text and nvim-dap-exception-breakpoints, with validation or
highlighting patterns from blink.cmp, quicker.nvim and nvim-treesitter-context.
