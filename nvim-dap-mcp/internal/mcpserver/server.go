// Package mcpserver exposes the Lua tool registry over MCP.
//
// It authors nothing: names, descriptions and JSON schemas are read from
// `require("dap-mcp").tools()` at startup and re-read whenever a client sends
// `tools/list`, so the Lua core stays the single source of truth. Tool results
// are passed through as raw JSON for the same reason -- modelling them in Go
// would quietly turn "absent" into "null" and lose the distinction the Lua
// author relies on.
//
// The one exception is `neovim_ping`, which answers from the RPC connection
// itself so a client can tell "Neovim is gone" from "the plugin is broken".
package mcpserver

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/abhirup-dev/nvim-dap-view/nvim-dap-mcp/internal/nvimbridge"
)

// PingTool is the one tool implemented in Go. It does not go through
// `require("dap-mcp")`, so it still answers when the plugin failed to load.
const PingTool = "neovim_ping"

const pingSchema = `{"type":"object","properties":{},"required":[],"additionalProperties":false}`

// syncTimeout bounds the registry re-read that runs on every tools/list.
const syncTimeout = 5 * time.Second

// Options configures the HTTP surface.
type Options struct {
	// Token, when non-empty, is required as `Authorization: Bearer <token>`.
	Token string
	// Path the MCP endpoint is served under. Defaults to "/mcp".
	Path string
	Log  *slog.Logger
}

// Server binds a bridge to an MCP server and an HTTP handler.
type Server struct {
	bridge *nvimbridge.Bridge
	mcp    *mcp.Server
	log    *slog.Logger
	opts   Options

	// registered is the tool set currently advertised, keyed by name and
	// fingerprinted by description plus schema. A failed refresh keeps serving
	// it, and an unchanged registry re-registers nothing -- see Sync.
	registered map[string]string
}

// New builds the server and performs the first registry sync. A sync failure
// here is fatal: with no tools there is nothing to serve.
func New(ctx context.Context, bridge *nvimbridge.Bridge, opts Options) (*Server, error) {
	if opts.Log == nil {
		opts.Log = slog.Default()
	}
	if opts.Path == "" {
		opts.Path = "/mcp"
	}

	s := &Server{
		bridge:     bridge,
		log:        opts.Log,
		opts:       opts,
		registered: map[string]string{},
	}

	s.mcp = mcp.NewServer(&mcp.Implementation{
		Name:    "nvim-dap-mcp",
		Title:   "Neovim DAP",
		Version: "0.1.0",
	}, &mcp.ServerOptions{
		Logger: opts.Log,
		Instructions: "Drive the debug session the user already has open in Neovim. " +
			"After any control action call wait_for_pause instead of polling session_status.",
	})

	s.addPing()

	// Re-read the Lua registry on every tools/list. The Lua side registers its
	// tools lazily on first `require`, and a user may reload the plugin under
	// a running sidecar.
	s.mcp.AddReceivingMiddleware(func(next mcp.MethodHandler) mcp.MethodHandler {
		return func(ctx context.Context, method string, req mcp.Request) (mcp.Result, error) {
			if method == "tools/list" {
				// Bounded: a Neovim sitting in a modal prompt must not hang
				// the client's discovery call.
				refresh, cancel := context.WithTimeout(ctx, syncTimeout)
				err := s.Sync(refresh)
				cancel()

				if err != nil {
					// Best effort: keep serving the last good set rather than
					// failing the client's discovery call.
					s.log.Warn("could not refresh the tool registry", "error", err)
				}
			}
			return next(ctx, method, req)
		}
	})

	if err := s.Sync(ctx); err != nil {
		return nil, err
	}

	return s, nil
}

// Sync reads the Lua registry and reconciles the advertised tool set with it.
//
// It compares before it writes. `Server.AddTool` assumes every call is a
// change and fires `notifications/tools/list_changed`, so re-registering all
// 21 tools on each `tools/list` would send a client that refetches on that
// notification straight back into `tools/list`. In the steady state -- the
// registry has not changed -- this touches the MCP server not at all.
func (s *Server) Sync(ctx context.Context) error {
	tools, err := s.bridge.Tools(ctx)
	if err != nil {
		return fmt.Errorf("read the dap-mcp tool registry: %w", err)
	}
	if len(tools) == 0 {
		return fmt.Errorf("the dap-mcp tool registry is empty")
	}

	// neovim_ping is ours, registered once at startup, and never part of what
	// the Lua side advertises.
	seen := map[string]string{PingTool: s.registered[PingTool]}

	for _, tool := range tools {
		tool := tool

		schema := tool.InputSchema
		if len(schema) == 0 {
			// AddTool panics on a nil schema, and a tool with no schema is a
			// registry bug worth reporting rather than crashing over.
			s.log.Warn("tool has no input schema, using the empty object", "tool", tool.Name)
			schema = json.RawMessage(pingSchema)
		}

		fingerprint := tool.Description + "\x00" + string(schema)
		seen[tool.Name] = fingerprint

		if s.registered[tool.Name] == fingerprint {
			continue
		}

		s.mcp.AddTool(&mcp.Tool{
			Name:        tool.Name,
			Description: tool.Description,
			InputSchema: schema,
		}, s.forward(tool.Name))
	}

	// Drop tools the Lua side no longer advertises.
	var stale []string
	for name := range s.registered {
		if _, ok := seen[name]; !ok {
			stale = append(stale, name)
		}
	}
	if len(stale) > 0 {
		s.mcp.RemoveTools(stale...)
	}

	s.registered = seen

	return nil
}

// Tools reports the advertised tool names. Test seam.
func (s *Server) Tools() []string {
	names := make([]string, 0, len(s.registered))
	for name := range s.registered {
		names = append(names, name)
	}

	return names
}

// forward is the whole tool implementation: hand the call to Lua, hand the
// answer back.
func (s *Server) forward(name string) mcp.ToolHandler {
	return func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		var args json.RawMessage
		if req.Params != nil {
			args = req.Params.Arguments
		}

		result, toolErr, err := s.bridge.Call(ctx, name, args)
		if toolErr != nil {
			// A refusal from the debugger is an answer, not a transport
			// failure: the agent should read it and adapt.
			return errorResult(fmt.Sprintf("%s: %s", toolErr.Code, toolErr.Message)), nil
		}
		if err != nil {
			if isConnectionError(err) {
				// Neovim is genuinely gone. Say so at the protocol level.
				return nil, err
			}
			// Timeouts and decode failures are more useful to the agent as a
			// readable tool error than as an opaque JSON-RPC failure.
			return errorResult(err.Error()), nil
		}

		return jsonResult(result), nil
	}
}

func (s *Server) addPing() {
	s.mcp.AddTool(&mcp.Tool{
		Name: PingTool,
		Description: "Check that the sidecar can reach Neovim. Returns the RPC socket, channel id " +
			"and Neovim version. Does not touch the debugger, so it answers even when dap-mcp " +
			"itself is misconfigured.",
		InputSchema: json.RawMessage(pingSchema),
	}, func(ctx context.Context, _ *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		info, err := s.bridge.Ping(ctx)
		if err != nil {
			return nil, err
		}

		return jsonResult(info), nil
	})
	s.registered[PingTool] = pingSchema
}

func jsonResult(payload json.RawMessage) *mcp.CallToolResult {
	if len(payload) == 0 {
		payload = json.RawMessage("null")
	}

	return &mcp.CallToolResult{
		Content: []mcp.Content{&mcp.TextContent{Text: string(payload)}},
	}
}

func errorResult(message string) *mcp.CallToolResult {
	return &mcp.CallToolResult{
		IsError: true,
		Content: []mcp.Content{&mcp.TextContent{Text: message}},
	}
}

// isConnectionError distinguishes "the editor went away" from "this call did
// not work out".
func isConnectionError(err error) bool {
	return strings.Contains(err.Error(), "neovim connection closed")
}

// Handler returns the streamable-HTTP handler, bearer auth included.
func (s *Server) Handler() http.Handler {
	streamable := mcp.NewStreamableHTTPHandler(func(*http.Request) *mcp.Server {
		return s.mcp
	}, &mcp.StreamableHTTPOptions{Logger: s.log})

	mux := http.NewServeMux()
	mux.Handle(s.opts.Path, s.authorize(streamable))
	mux.Handle(s.opts.Path+"/", s.authorize(streamable))

	return mux
}

func (s *Server) authorize(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.opts.Token == "" {
			next.ServeHTTP(w, r)
			return
		}

		const prefix = "Bearer "
		header := r.Header.Get("Authorization")
		if len(header) <= len(prefix) || !strings.EqualFold(header[:len(prefix)], prefix) ||
			header[len(prefix):] != s.opts.Token {
			w.Header().Set("WWW-Authenticate", `Bearer realm="nvim-dap-mcp"`)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		next.ServeHTTP(w, r)
	})
}
