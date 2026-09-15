// Command nvim-dap-mcp is the sidecar that lets an MCP client drive the debug
// session a human already has open in Neovim.
//
//	agent --MCP streamable HTTP--> nvim-dap-mcp --msgpack-rpc--> Neovim --> nvim-dap
//
// It is normally started and stopped by the plugin (`:DapMcp start|stop`), but
// runs fine by hand against any Neovim with a listening socket:
//
//	nvim-dap-mcp --socket "$NVIM_LISTEN_ADDRESS" --port 28911
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/abhirup-dev/nvim-dap-view/nvim-dap-mcp/internal/mcpserver"
	"github.com/abhirup-dev/nvim-dap-view/nvim-dap-mcp/internal/nvimbridge"
)

// shutdownGrace bounds the wait for in-flight requests. A `wait_for_pause` can
// legitimately be thirty seconds deep; the user pressing Ctrl-C should not
// have to sit through it.
const shutdownGrace = 5 * time.Second

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "nvim-dap-mcp: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	socket := flag.String("socket", "", "Neovim RPC socket (defaults to $NVIM_LISTEN_ADDRESS, then $NVIM)")
	port := flag.Int("port", 28911, "TCP port for the MCP endpoint")
	bind := flag.String("bind", "127.0.0.1", "address to bind the MCP endpoint to")
	token := flag.String("token", "", "when set, require `Authorization: Bearer <token>`")
	logLevel := flag.String("log", "info", "stderr log level: debug, info, warn or error")
	path := flag.String("path", "/mcp", "URL path the MCP endpoint is served under")
	flag.Parse()

	level, err := parseLevel(*logLevel)
	if err != nil {
		return err
	}

	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level}))

	addr := resolveSocket(*socket)
	if addr == "" {
		return errors.New("no Neovim socket: pass --socket, or set NVIM_LISTEN_ADDRESS or NVIM")
	}

	if *token == "" && !isLoopback(*bind) {
		log.Warn("serving without a token on a non-loopback address; anyone who can reach this port can drive the debugger",
			"bind", *bind)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	bridge, err := nvimbridge.Dial(addr, log)
	if err != nil {
		return err
	}
	defer bridge.Close()

	startup, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	server, err := mcpserver.New(startup, bridge, mcpserver.Options{
		Token: *token,
		Path:  *path,
		Log:   log,
	})
	if err != nil {
		return err
	}

	listen := net.JoinHostPort(*bind, fmt.Sprint(*port))
	listener, err := net.Listen("tcp", listen)
	if err != nil {
		return fmt.Errorf("listen on %s: %w", listen, err)
	}

	httpServer := &http.Server{Handler: server.Handler()}

	serveErr := make(chan error, 1)
	go func() {
		serveErr <- httpServer.Serve(listener)
	}()

	log.Info("nvim-dap-mcp listening",
		"url", fmt.Sprintf("http://%s%s", listener.Addr().String(), *path),
		"socket", addr,
		"tools", len(server.Tools()),
		"auth", *token != "")

	select {
	case <-ctx.Done():
		log.Info("shutting down on signal")
	case <-bridge.Closed():
		// Neovim exited. There is no session left to drive, so this is a
		// normal end of life, not a failure.
		log.Info("neovim closed the rpc channel, shutting down")
	case err := <-serveErr:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			return fmt.Errorf("http server: %w", err)
		}
	}

	shutdown, cancelShutdown := context.WithTimeout(context.Background(), shutdownGrace)
	defer cancelShutdown()

	if err := httpServer.Shutdown(shutdown); err != nil {
		// Requests still in flight past the grace period get cut off rather
		// than holding the process open.
		httpServer.Close()
	}

	return nil
}

// resolveSocket prefers the flag, then the two variables Neovim exports to its
// children.
func resolveSocket(flagValue string) string {
	if flagValue != "" {
		return flagValue
	}
	if v := os.Getenv("NVIM_LISTEN_ADDRESS"); v != "" {
		return v
	}

	return os.Getenv("NVIM")
}

func isLoopback(bind string) bool {
	if bind == "localhost" || bind == "" {
		return true
	}

	ip := net.ParseIP(bind)

	return ip != nil && ip.IsLoopback()
}

func parseLevel(name string) (slog.Level, error) {
	switch strings.ToLower(name) {
	case "debug":
		return slog.LevelDebug, nil
	case "info":
		return slog.LevelInfo, nil
	case "warn", "warning":
		return slog.LevelWarn, nil
	case "error":
		return slog.LevelError, nil
	default:
		return 0, fmt.Errorf("unknown log level %q: use debug, info, warn or error", name)
	}
}
