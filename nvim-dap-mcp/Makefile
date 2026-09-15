BIN := bin/nvim-dap-mcp
GO ?= go
STYLUA ?= stylua
NVIM ?= nvim

.PHONY: all build test test-go test-lua fmt check clean

all: build

## Build the sidecar. lazy.nvim users wire this up with `build = "make build"`.
build:
	$(GO) build -o $(BIN) ./cmd/nvim-dap-mcp

## Everything: Go integration tests against a headless Neovim, then the Lua suite.
test: test-go test-lua

test-go:
	$(GO) test ./...

test-lua:
	$(NVIM) --headless -u NONE -l tests/run.lua

fmt:
	$(GO) fmt ./...
	$(STYLUA) lua plugin tests

check:
	$(GO) vet ./...
	$(STYLUA) --check lua plugin tests

clean:
	rm -rf bin
