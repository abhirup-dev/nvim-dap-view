# Live debugger demos

These demos use the repository harness with locally installed nvim-dap and Mason
Python/Go adapters. Override `NVIM_DAP_PATH` if needed. No editor configuration is
installed or changed globally.

From this directory, prepare binary fixtures and the Go programs:

```sh
uv venv deps/venv
uv pip install --python deps/venv/bin/python protobuf
deps/venv/bin/python binary-fixtures.py
go build -gcflags='all=-N -l' -o cart-go main.go
go build -gcflags='all=-N -l' -o binary-go binary.go
mkdir -p /tmp/nvim-dap-live-demo
```

For the cart demo, run `DEMO_LANG=python nvim -u init.lua` (or `DEMO_LANG=go`).
F5 starts/continues; its conditional breakpoint skips Cake and stops on Coffee
and Tea. Space dd toggles decoding; Space ds/dw/db selects scopes/watches/breakpoints.

For protobuf and gzip, start a fresh editor:

```sh
DEMO_LANG=python nvim --listen /tmp/python-demo.sock -u binary-init.lua
# In another terminal, drive and verify five stopped snapshots:
python3 binary-drive.py --socket /tmp/python-demo.sock
```

Use `DEMO_LANG=go` for Go. The checker verifies exact fixture lengths/checksums,
current-generation decoder completion, changed fields, unchanged siblings and a
no-op stop. The sequence changes only counter, then protobuf age, then gzip age.

For an actual Lua debuggee and Lua decoder callback, additionally prepare OSV:

```sh
git clone https://github.com/jbyuki/one-small-step-for-vimkind deps/osv
nvim --headless -u lua-target.lua --listen /tmp/nvim-dap-live-demo/lua-target.sock
# In another terminal:
DEMO_LANG=lua nvim --listen /tmp/lua-demo.sock -u binary-init.lua
python3 binary-drive.py --socket /tmp/lua-demo.sock
```

The tested OSV revision is recorded in Beads issues dv-srz and dv-6au. It requires
REPL evaluation context and a buffer wrapper for arbitrary binary data. The Lua
callback reads actual wrapper bytes in bounded base64 slices; Python reads bounded
hex slices and Go uses indexed byte paging. Protocol display summaries are never
used as complete binary data. Protobuf parsing uses Google's descriptor runtime;
gzip decompression uses Python's standard library asynchronously from the callback.

Default internal styling uses DAP presentation hints. The demo explicitly opts
into overrides for unmarked debugpy groups and Delve return slots. These overrides
are examples, not universal detection of language internals.
