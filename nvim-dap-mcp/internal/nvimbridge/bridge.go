// Package nvimbridge is the sidecar's only door into Neovim.
//
// It speaks msgpack-rpc to a running instance and forwards every tool call to
// the single Lua entry point described at the top of lua/dap-mcp/init.lua:
//
//	require("dap-mcp").call(name, args)  -> { ok, result } | { ok, error }
//	                                     | { ok = true, result = { pending, ticket } }
//	require("dap-mcp").poll(ticket)      -> the same, once resolved
//
// Two decisions worth knowing before reading on:
//
//   - Everything crosses the wire as a JSON *string*, encoded and decoded by
//     `vim.json` on the Lua side. msgpack would round-trip the values but not
//     their shape: the Lua core deliberately omits `frame`, `source`,
//     `locals`, `truncated` and `full_value_ref` rather than sending null, and
//     tool results are passed through to MCP clients untouched as
//     json.RawMessage. A JSON string preserves absent-vs-null exactly.
//
//   - The mutex is held for one RPC round-trip, never across the poll loop.
//     A `wait_for_pause` that blocks for thirty seconds must not stop another
//     agent from reading the breakpoint list.
package nvimbridge

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/neovim/go-client/nvim"
)

// PollInterval is how often a pending ticket is collected. `nvim_exec_lua` is
// cheap and the Lua side answers off a table lookup, so this is nearly free.
const PollInterval = 25 * time.Millisecond

// DefaultTimeout bounds a single tool call. `wait_for_pause` overrides it; see
// callTimeout.
const DefaultTimeout = 60 * time.Second

// WaitGrace is added to `wait_for_pause`'s own `timeout_ms` so the bridge
// always outlives the Lua timer and reports the tool's `timed_out` snapshot
// rather than a bridge timeout.
const WaitGrace = 5 * time.Second

// waitTool is the one tool that carries its own deadline.
const waitTool = "wait_for_pause"

// waitDefaultTimeoutMS mirrors DEFAULT_TIMEOUT_MS in lua/dap-mcp/tools/wait.lua.
const waitDefaultTimeoutMS = 30000

// ToolError is the Lua core's error envelope. Code is one of a stable set --
// no_session, not_stopped, no_thread, unknown_tool, unknown_ticket,
// unknown_ref, unknown_frame, unknown_configuration, invalid_argument,
// side_effects_refused, dap_error, ui_unavailable, internal -- and callers are
// expected to surface it as a tool error, never as a transport failure.
type ToolError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (e *ToolError) Error() string {
	return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

// envelope is the shape `call` and `poll` always return.
type envelope struct {
	OK     bool            `json:"ok"`
	Result json.RawMessage `json:"result"`
	Error  *ToolError      `json:"error"`
}

// pendingProbe reads just enough of a result to tell "not finished yet" from a
// real answer. Both fields are pointers so a tool result that happens to carry
// neither key is unambiguously not pending.
type pendingProbe struct {
	Pending *bool  `json:"pending"`
	Ticket  *int64 `json:"ticket"`
}

// Tool is one entry of the Lua registry. InputSchema is passed through to the
// MCP layer verbatim; the sidecar never authors a schema.
type Tool struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	InputSchema json.RawMessage `json:"input_schema"`
}

// Bridge owns the Neovim connection.
type Bridge struct {
	socket string
	log    *slog.Logger

	mu sync.Mutex // serialises RPC round-trips, one at a time, in order
	nv *nvim.Nvim

	closed chan struct{} // closed when Neovim goes away
	once   sync.Once
}

// Dial connects to a Neovim RPC socket and starts serving the connection in
// the background. Closed() fires when that connection ends.
func Dial(socket string, log *slog.Logger) (*Bridge, error) {
	nv, err := nvim.Dial(socket,
		nvim.DialServe(false),
		nvim.DialLogf(func(string, ...interface{}) {}),
	)
	if err != nil {
		return nil, fmt.Errorf("connect to neovim at %s: %w", socket, err)
	}

	b := &Bridge{
		socket: socket,
		log:    log,
		nv:     nv,
		closed: make(chan struct{}),
	}

	go func() {
		err := nv.Serve()
		if err != nil {
			b.log.Debug("neovim rpc connection ended", "error", err)
		}
		b.once.Do(func() { close(b.closed) })
	}()

	return b, nil
}

// Closed is closed once the Neovim channel is gone. The sidecar shuts down
// with it: without an editor there is nothing to debug.
func (b *Bridge) Closed() <-chan struct{} { return b.closed }

// Socket is the address this bridge dialled.
func (b *Bridge) Socket() string { return b.socket }

// Close hangs up on Neovim.
func (b *Bridge) Close() error {
	b.mu.Lock()
	defer b.mu.Unlock()

	return b.nv.Close()
}

// execLua runs one `nvim_exec_lua` and decodes its string result. This is the
// only place the mutex is taken.
func (b *Bridge) execLua(code string, args ...interface{}) (string, error) {
	b.mu.Lock()
	defer b.mu.Unlock()

	var out string
	if err := b.nv.ExecLua(code, &out, args...); err != nil {
		return "", err
	}

	return out, nil
}

// Every snippet below wraps the real work in pcall and encodes the failure as
// an `internal` envelope. Without this, a Lua error escapes as an RPC error,
// and the wire contract says a tool problem must never look like a transport
// problem.
const luaPreamble = `
local ok, encoded = pcall(function(...)
`

const luaPostamble = `
end, ...)
if ok then
  return encoded
end
return vim.json.encode({
  ok = false,
  error = { code = "internal", message = "dap-mcp lua error: " .. tostring(encoded) },
})
`

func luaSnippet(body string) string {
	return luaPreamble + body + luaPostamble
}

var (
	luaTools = luaSnippet(`
  return vim.json.encode(require("dap-mcp").tools())
`)

	luaCall = luaSnippet(`
  local name, args_json = ...
  return vim.json.encode(require("dap-mcp").call(name, vim.json.decode(args_json)))
`)

	luaPoll = luaSnippet(`
  local ticket = ...
  return vim.json.encode(require("dap-mcp").poll(ticket))
`)

	luaPing = `
local info = vim.fn.api_info()
return vim.json.encode({
  socket = vim.v.servername,
  channel_id = info.channel_id,
  nvim_version = info.version,
})
`
)

// Tools reads the Lua registry. The sidecar advertises exactly this and never
// hard-codes a tool.
func (b *Bridge) Tools(ctx context.Context) ([]Tool, error) {
	out, err := b.execLuaCtx(ctx, luaTools)
	if err != nil {
		return nil, err
	}

	// `tools()` returns a plain list, not an envelope: the registry cannot
	// fail, and a failure inside pcall comes back as an envelope we would fail
	// to decode -- which is the correct outcome, an error either way.
	var tools []Tool
	if err := json.Unmarshal([]byte(out), &tools); err != nil {
		return nil, fmt.Errorf("decode tool registry: %w (payload: %s)", err, truncateForLog(out))
	}

	return tools, nil
}

// Ping reports liveness without touching the dap-mcp Lua at all, so it answers
// even when the plugin is broken or was never set up.
func (b *Bridge) Ping(ctx context.Context) (json.RawMessage, error) {
	out, err := b.execLuaCtx(ctx, luaPing)
	if err != nil {
		return nil, err
	}

	return json.RawMessage(out), nil
}

// Call runs one tool to completion.
//
// The three return values are three different kinds of outcome and callers
// must keep them apart:
//
//	(result, nil, nil)   the tool succeeded; result is its JSON, untouched
//	(nil, toolErr, nil)  the tool refused; surface as an MCP tool error
//	(nil, nil, err)      the bridge itself failed; a transport error
//
// argsJSON may be nil or empty, which is read as `{}`.
func (b *Bridge) Call(ctx context.Context, name string, argsJSON json.RawMessage) (json.RawMessage, *ToolError, error) {
	if len(argsJSON) == 0 {
		argsJSON = json.RawMessage("{}")
	}

	ctx, cancel := context.WithTimeout(ctx, callTimeout(name, argsJSON))
	defer cancel()

	out, err := b.execLuaCtx(ctx, luaCall, name, string(argsJSON))
	if err != nil {
		return nil, nil, err
	}

	env, err := decodeEnvelope(out)
	if err != nil {
		return nil, nil, err
	}

	for {
		if env.Error != nil {
			return nil, env.Error, nil
		}
		if !env.OK {
			return nil, nil, fmt.Errorf("neovim returned a failed envelope with no error: %s", truncateForLog(out))
		}

		ticket, pending := ticketOf(env.Result)
		if !pending {
			return env.Result, nil, nil
		}

		select {
		case <-ctx.Done():
			return nil, nil, fmt.Errorf("tool %q did not finish in time (ticket %d): %w", name, ticket, ctx.Err())
		case <-b.closed:
			return nil, nil, errors.New("neovim connection closed while waiting for a pending result")
		case <-time.After(PollInterval):
		}

		out, err = b.execLuaCtx(ctx, luaPoll, ticket)
		if err != nil {
			return nil, nil, err
		}

		env, err = decodeEnvelope(out)
		if err != nil {
			return nil, nil, err
		}
	}
}

// execLuaCtx runs execLua on a goroutine so a cancelled context returns
// promptly. The RPC itself is not cancellable -- it is a single round-trip to
// a local socket, so an abandoned one costs nothing and the mutex is released
// by the goroutine when it finishes.
func (b *Bridge) execLuaCtx(ctx context.Context, code string, args ...interface{}) (string, error) {
	type reply struct {
		out string
		err error
	}

	done := make(chan reply, 1)
	go func() {
		out, err := b.execLua(code, args...)
		done <- reply{out, err}
	}()

	select {
	case <-ctx.Done():
		return "", ctx.Err()
	case <-b.closed:
		return "", errors.New("neovim connection closed")
	case r := <-done:
		if r.err != nil {
			return "", fmt.Errorf("nvim_exec_lua: %w", r.err)
		}
		return r.out, nil
	}
}

func decodeEnvelope(payload string) (*envelope, error) {
	var env envelope
	if err := json.Unmarshal([]byte(payload), &env); err != nil {
		return nil, fmt.Errorf("decode dap-mcp envelope: %w (payload: %s)", err, truncateForLog(payload))
	}

	return &env, nil
}

// ticketOf reports whether a result is the `{pending=true, ticket=N}` stand-in
// rather than a real answer.
func ticketOf(result json.RawMessage) (int64, bool) {
	if len(result) == 0 {
		return 0, false
	}

	var probe pendingProbe
	if err := json.Unmarshal(result, &probe); err != nil {
		// A tool result that is not an object (a list, a string) is never
		// pending.
		return 0, false
	}

	if probe.Pending == nil || !*probe.Pending || probe.Ticket == nil {
		return 0, false
	}

	return *probe.Ticket, true
}

// callTimeout gives `wait_for_pause` room to hit its own deadline first, so
// the agent gets the tool's `timed_out` snapshot instead of a bridge error.
func callTimeout(name string, argsJSON json.RawMessage) time.Duration {
	if name != waitTool {
		return DefaultTimeout
	}

	timeoutMS := int64(waitDefaultTimeoutMS)

	var args struct {
		TimeoutMS *int64 `json:"timeout_ms"`
	}
	if err := json.Unmarshal(argsJSON, &args); err == nil && args.TimeoutMS != nil && *args.TimeoutMS > 0 {
		timeoutMS = *args.TimeoutMS
	}

	return time.Duration(timeoutMS)*time.Millisecond + WaitGrace
}

func truncateForLog(s string) string {
	const max = 300
	if len(s) <= max {
		return s
	}

	return s[:max] + "..."
}
