// Package testnvim starts a throwaway headless Neovim with the plugin loaded,
// for tests that need a real RPC peer rather than a mock.
//
// No debug adapter is involved: the tools under test are the ones that answer
// with no session (the registry, the breakpoint list, the status composer and
// the wait timeout), which is exactly enough to exercise the bridge's
// immediate and pending/poll paths.
package testnvim

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

// Start launches headless Neovim on a fresh socket and returns its path. The
// process is killed when the test ends.
//
// The test is skipped, not failed, when nvim or nvim-dap is missing: this
// suite is about the bridge, and a machine without them cannot say anything
// about it either way.
func Start(t *testing.T) string {
	t.Helper()

	nvimBin, err := exec.LookPath("nvim")
	if err != nil {
		t.Skip("nvim is not on PATH")
	}

	dapPath := nvimDapPath()
	if dapPath == "" {
		t.Skip("nvim-dap not found; set NVIM_DAP_PATH to run this test")
	}

	// Unix socket paths are capped near 104 bytes on macOS, and the usual
	// TempDir under /var/folders eats most of that budget. Keep it short.
	socket := filepath.Join("/tmp", "dapmcp-test-"+randomSuffix()+".sock")
	t.Cleanup(func() { os.Remove(socket) })

	cmd := exec.Command(nvimBin,
		"--headless", "--clean",
		"--listen", socket,
		"-c", "set rtp+="+repoRoot(),
		"-c", "set rtp+="+dapPath,
		"-c", `lua require("dap-mcp").setup({})`,
	)
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		t.Fatalf("start nvim: %v", err)
	}

	t.Cleanup(func() {
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
	})

	// The socket appears some time after the process does.
	deadline := time.Now().Add(15 * time.Second)
	for {
		if _, err := os.Stat(socket); err == nil {
			return socket
		}
		if time.Now().After(deadline) {
			t.Fatalf("nvim never created its socket at %s", socket)
		}
		time.Sleep(25 * time.Millisecond)
	}
}

// repoRoot is this file's directory, two levels up.
func repoRoot() string {
	_, file, _, _ := runtime.Caller(0)

	return filepath.Dir(filepath.Dir(filepath.Dir(file)))
}

func nvimDapPath() string {
	if v := os.Getenv("NVIM_DAP_PATH"); v != "" {
		return v
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}

	candidates := []string{
		filepath.Join(home, ".local/share/nvim/lazy/nvim-dap"),
		filepath.Join(home, ".local/share/nvim/site/pack/packer/start/nvim-dap"),
	}
	for _, candidate := range candidates {
		if info, err := os.Stat(candidate); err == nil && info.IsDir() {
			return candidate
		}
	}

	return ""
}

func randomSuffix() string {
	f, err := os.CreateTemp("/tmp", "dapmcp")
	if err != nil {
		return "fallback"
	}
	name := filepath.Base(f.Name())
	f.Close()
	os.Remove(f.Name())

	return name[len("dapmcp"):]
}
