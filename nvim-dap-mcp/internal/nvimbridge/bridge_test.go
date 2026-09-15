package nvimbridge_test

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/abhirup-dev/nvim-dap-view/nvim-dap-mcp/internal/nvimbridge"
	"github.com/abhirup-dev/nvim-dap-view/nvim-dap-mcp/internal/testnvim"
)

// toolCount is the size of the phase 5a registry. It is asserted rather than
// read so a tool silently disappearing from the Lua side fails here.
const toolCount = 21

func dial(t *testing.T) *nvimbridge.Bridge {
	t.Helper()

	socket := testnvim.Start(t)

	bridge, err := nvimbridge.Dial(socket, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil {
		t.Fatalf("dial %s: %v", socket, err)
	}
	t.Cleanup(func() { bridge.Close() })

	return bridge
}

func TestToolsComeFromLua(t *testing.T) {
	bridge := dial(t)

	tools, err := bridge.Tools(context.Background())
	if err != nil {
		t.Fatalf("Tools: %v", err)
	}

	if len(tools) != toolCount {
		names := make([]string, len(tools))
		for i, tool := range tools {
			names[i] = tool.Name
		}
		t.Fatalf("got %d tools, want %d: %v", len(tools), toolCount, names)
	}

	for _, tool := range tools {
		if tool.Name == "" || tool.Description == "" {
			t.Errorf("tool %+v is missing a name or description", tool)
		}
		// A missing schema would panic mcp.Server.AddTool at startup.
		if len(tool.InputSchema) == 0 {
			t.Errorf("tool %q has no input_schema", tool.Name)
		}
	}
}

// list_breakpoints is purely local, so the Lua side answers on the first call
// and never hands out a ticket.
func TestImmediateCall(t *testing.T) {
	bridge := dial(t)

	result, toolErr, err := bridge.Call(context.Background(), "list_breakpoints", nil)
	if err != nil {
		t.Fatalf("Call: %v", err)
	}
	if toolErr != nil {
		t.Fatalf("unexpected tool error: %v", toolErr)
	}

	var payload struct {
		Breakpoints []any `json:"breakpoints"`
	}
	if err := json.Unmarshal(result, &payload); err != nil {
		t.Fatalf("decode list_breakpoints: %v (%s)", err, result)
	}
	if len(payload.Breakpoints) != 0 {
		t.Errorf("expected no breakpoints in a fresh nvim, got %d", len(payload.Breakpoints))
	}
}

// With no session, `status.compose` returns without issuing a DAP request, so
// this too is an immediate answer -- see the note in the report to nvim-d6.
func TestSessionStatusWithNoSession(t *testing.T) {
	bridge := dial(t)

	result, toolErr, err := bridge.Call(context.Background(), "session_status", nil)
	if err != nil {
		t.Fatalf("Call: %v", err)
	}
	if toolErr != nil {
		t.Fatalf("unexpected tool error: %v", toolErr)
	}

	var status struct {
		State string          `json:"state"`
		Stack []any           `json:"stack"`
		Frame json.RawMessage `json:"frame"`
	}
	if err := json.Unmarshal(result, &status); err != nil {
		t.Fatalf("decode session_status: %v (%s)", err, result)
	}

	if status.State != "none" {
		t.Errorf("state = %q, want \"none\"", status.State)
	}
	if len(status.Stack) != 0 {
		t.Errorf("stack = %v, want empty", status.Stack)
	}
	// The wire notes are explicit that these keys are absent, not null.
	if status.Frame != nil {
		t.Errorf("frame should be absent with no session, got %s", status.Frame)
	}
}

// wait_for_pause always suspends its coroutine when nothing is stopped, which
// makes it the one tool that exercises ticket + poll without a debug adapter.
func TestPendingPollPath(t *testing.T) {
	bridge := dial(t)

	start := time.Now()

	result, toolErr, err := bridge.Call(context.Background(), "wait_for_pause",
		json.RawMessage(`{"timeout_ms":300}`))
	if err != nil {
		t.Fatalf("Call: %v", err)
	}
	if toolErr != nil {
		t.Fatalf("unexpected tool error: %v", toolErr)
	}

	elapsed := time.Since(start)
	if elapsed < 300*time.Millisecond {
		t.Errorf("returned after %s, so it cannot have waited out its own timeout", elapsed)
	}

	var snapshot struct {
		State    string `json:"state"`
		Event    string `json:"event"`
		TimedOut bool   `json:"timed_out"`
		Pending  *bool  `json:"pending"`
	}
	if err := json.Unmarshal(result, &snapshot); err != nil {
		t.Fatalf("decode wait_for_pause: %v (%s)", err, result)
	}

	if snapshot.Pending != nil {
		t.Fatalf("Call returned the pending envelope instead of the resolved result: %s", result)
	}
	if snapshot.Event != "timeout" || !snapshot.TimedOut {
		t.Errorf("event = %q timed_out = %v, want \"timeout\" true", snapshot.Event, snapshot.TimedOut)
	}
	if snapshot.State != "none" {
		t.Errorf("state = %q, want \"none\"", snapshot.State)
	}
}

// A bad tool name is the debugger declining, not the transport breaking.
func TestUnknownToolIsAToolError(t *testing.T) {
	bridge := dial(t)

	result, toolErr, err := bridge.Call(context.Background(), "no_such_tool", nil)
	if err != nil {
		t.Fatalf("unknown tool surfaced as a transport error: %v", err)
	}
	if result != nil {
		t.Fatalf("unexpected result: %s", result)
	}
	if toolErr == nil {
		t.Fatal("expected a tool error")
	}
	if toolErr.Code != "unknown_tool" {
		t.Errorf("code = %q, want \"unknown_tool\"", toolErr.Code)
	}
	if toolErr.Message == "" {
		t.Error("tool error has no message")
	}
}

// Bad arguments must come back with the stable code too, not as a Lua stack
// trace escaping through the RPC layer.
func TestInvalidArgumentIsAToolError(t *testing.T) {
	bridge := dial(t)

	_, toolErr, err := bridge.Call(context.Background(), "get_variables",
		json.RawMessage(`{"variables_reference":-1}`))
	if err != nil {
		t.Fatalf("unexpected transport error: %v", err)
	}
	if toolErr == nil {
		t.Fatal("expected a tool error for a bogus variables reference")
	}
	if toolErr.Code == "" {
		t.Error("tool error has no code")
	}
}

func TestContextCancellationStopsTheCall(t *testing.T) {
	bridge := dial(t)

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()

	_, _, err := bridge.Call(ctx, "wait_for_pause", json.RawMessage(`{"timeout_ms":30000}`))
	if err == nil {
		t.Fatal("expected the cancelled context to end the poll loop")
	}
}
