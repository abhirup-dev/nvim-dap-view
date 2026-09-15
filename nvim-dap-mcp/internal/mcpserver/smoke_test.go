package mcpserver_test

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/abhirup-dev/nvim-dap-view/nvim-dap-mcp/internal/mcpserver"
	"github.com/abhirup-dev/nvim-dap-view/nvim-dap-mcp/internal/nvimbridge"
	"github.com/abhirup-dev/nvim-dap-view/nvim-dap-mcp/internal/testnvim"
)

// toolCount is the phase 5a registry plus neovim_ping.
const toolCount = 21 + 1

// serve stands up the whole stack -- headless nvim, bridge, MCP server, HTTP
// listener -- and returns the endpoint URL.
func serve(t *testing.T, token string) string {
	t.Helper()

	socket := testnvim.Start(t)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	bridge, err := nvimbridge.Dial(socket, log)
	if err != nil {
		t.Fatalf("dial %s: %v", socket, err)
	}
	t.Cleanup(func() { bridge.Close() })

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	server, err := mcpserver.New(ctx, bridge, mcpserver.Options{Token: token, Log: log})
	if err != nil {
		t.Fatalf("build the mcp server: %v", err)
	}

	http := httptest.NewServer(server.Handler())
	t.Cleanup(http.Close)

	return http.URL + "/mcp"
}

func connect(t *testing.T, url, token string) *mcp.ClientSession {
	t.Helper()

	return connectWith(t, url, token, nil)
}

func connectWith(t *testing.T, url, token string, opts *mcp.ClientOptions) *mcp.ClientSession {
	t.Helper()

	transport := &mcp.StreamableClientTransport{Endpoint: url}
	if token != "" {
		transport.HTTPClient = &http.Client{Transport: bearer{token: token}}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	t.Cleanup(cancel)

	client := mcp.NewClient(&mcp.Implementation{Name: "smoke", Version: "0"}, opts)

	session, err := client.Connect(ctx, transport, nil)
	if err != nil {
		t.Fatalf("connect to %s: %v", url, err)
	}
	t.Cleanup(func() { session.Close() })

	return session
}

type bearer struct{ token string }

func (b bearer) RoundTrip(r *http.Request) (*http.Response, error) {
	r = r.Clone(r.Context())
	r.Header.Set("Authorization", "Bearer "+b.token)

	return http.DefaultTransport.RoundTrip(r)
}

// TestSmoke is the end-to-end check: a real MCP client initializes, lists the
// tools the Lua registry advertises and calls one.
func TestSmoke(t *testing.T) {
	session := connect(t, serve(t, ""), "")

	ctx := context.Background()

	tools, err := session.ListTools(ctx, nil)
	if err != nil {
		t.Fatalf("tools/list: %v", err)
	}
	if len(tools.Tools) != toolCount {
		t.Fatalf("got %d tools, want %d", len(tools.Tools), toolCount)
	}

	var sawPing bool
	for _, tool := range tools.Tools {
		if tool.Name == mcpserver.PingTool {
			sawPing = true
		}
	}
	if !sawPing {
		t.Errorf("%s is missing from tools/list", mcpserver.PingTool)
	}

	result, err := session.CallTool(ctx, &mcp.CallToolParams{Name: mcpserver.PingTool})
	if err != nil {
		t.Fatalf("tools/call %s: %v", mcpserver.PingTool, err)
	}
	if result.IsError {
		t.Fatalf("%s returned an error: %s", mcpserver.PingTool, text(result))
	}

	var ping struct {
		Socket    string `json:"socket"`
		ChannelID int    `json:"channel_id"`
		Version   struct {
			Major int `json:"major"`
			Minor int `json:"minor"`
		} `json:"nvim_version"`
	}
	if err := json.Unmarshal([]byte(text(result)), &ping); err != nil {
		t.Fatalf("decode ping: %v (%s)", err, text(result))
	}
	if ping.Socket == "" {
		t.Error("ping did not report the socket")
	}
	if ping.Version.Major == 0 && ping.Version.Minor == 0 {
		t.Error("ping did not report a Neovim version")
	}
}

// A Lua error code must arrive as an MCP tool error, never as a protocol
// failure: the agent should be able to read it and pick a different move.
func TestToolErrorIsNotATransportError(t *testing.T) {
	session := connect(t, serve(t, ""), "")

	result, err := session.CallTool(context.Background(), &mcp.CallToolParams{
		Name:      "get_stack",
		Arguments: map[string]any{},
	})
	if err != nil {
		t.Fatalf("a refusal surfaced as a protocol error: %v", err)
	}
	if !result.IsError {
		t.Fatal("expected isError with no debug session")
	}
	if !strings.Contains(text(result), "no_session") {
		t.Errorf("error text does not carry the stable code: %s", text(result))
	}
}

// Every tools/list re-reads the Lua registry. If that re-registered the tools
// unconditionally, each one would fire notifications/tools/list_changed, and a
// client that refetches on that notification -- Claude Code does -- would spin.
// An unchanged registry must be silent.
func TestRefreshDoesNotNotify(t *testing.T) {
	var notifications atomic.Int64

	session := connectWith(t, serve(t, ""), "", &mcp.ClientOptions{
		ToolListChangedHandler: func(context.Context, *mcp.ToolListChangedRequest) {
			notifications.Add(1)
		},
	})

	ctx := context.Background()
	for range 3 {
		if _, err := session.ListTools(ctx, nil); err != nil {
			t.Fatalf("tools/list: %v", err)
		}
	}

	// The notification travels on the standalone SSE stream, so give it a
	// moment to arrive before concluding it never will.
	time.Sleep(250 * time.Millisecond)

	if n := notifications.Load(); n != 0 {
		t.Errorf("three tools/list calls produced %d list_changed notifications, want 0", n)
	}
}

func TestTokenIsEnforced(t *testing.T) {
	url := serve(t, "s3cret")

	// No header at all.
	response, err := http.Post(url, "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatalf("post: %v", err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusUnauthorized {
		t.Errorf("unauthenticated request got %d, want 401", response.StatusCode)
	}

	// Wrong token.
	request, _ := http.NewRequest(http.MethodPost, url, strings.NewReader(`{}`))
	request.Header.Set("Authorization", "Bearer wrong")
	response, err = http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("post: %v", err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusUnauthorized {
		t.Errorf("request with a wrong token got %d, want 401", response.StatusCode)
	}

	// The right one gets through the whole handshake.
	session := connect(t, url, "s3cret")
	if _, err := session.ListTools(context.Background(), nil); err != nil {
		t.Fatalf("authenticated tools/list: %v", err)
	}
}

func text(result *mcp.CallToolResult) string {
	var parts []string
	for _, content := range result.Content {
		if t, ok := content.(*mcp.TextContent); ok {
			parts = append(parts, t.Text)
		}
	}

	return strings.Join(parts, "\n")
}
