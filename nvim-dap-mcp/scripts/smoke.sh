#!/usr/bin/env bash
#
# End-to-end smoke check: build the sidecar, then run the Go tests that stand
# up a headless Neovim, speak MCP streamable HTTP to the sidecar's handler with
# the official SDK client, and assert the tool list and a neovim_ping response.
#
# The client side lives in Go rather than in curl on purpose: a streamable-HTTP
# POST answers with text/event-stream frames and needs Mcp-Session-Id handling,
# which is a lot of shell for no extra coverage. The one thing worth checking
# from outside is the 401, which needs no MCP at all -- see below.

set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> building"
make build

echo "==> mcp client end-to-end (headless neovim + streamable http)"
go test ./internal/mcpserver/ -run 'TestSmoke|TestToolErrorIsNotATransportError|TestTokenIsEnforced' -v

echo "==> bridge pending/poll"
go test ./internal/nvimbridge/ -v

echo
echo "smoke ok"
