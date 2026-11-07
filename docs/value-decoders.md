# Value decoders

Decoders make serialized values expandable in scopes, watches and expression hover.
They run in the DAP owner; split, tab and detached viewers use the same rendered
text and expansion actions. Unmatched variables keep their normal rendering.
Decoding starts when you expand a matching node. Its `raw` child preserves the
adapter representation; its `decoded` child exposes the transformed tree. Expand
those children with the normal toggle key. The original variable remains editable;
preview children are read-only. `:DapViewProfile use off` restores normal rendering.

## Try serialized Go protobuf

Requirements: Neovim 0.11+, nvim-dap, nvim-nio, Go, Delve, Python 3 and the Python
`protobuf` package. No changes to an existing editor or its debug session are needed.
From this repository:

```sh
python3 examples/decoders/make_fixture.py
go build -gcflags='all=-N -l' -o examples/decoders/fixture examples/decoders/main.go
export NVIM_DAP_PATH=/path/to/nvim-dap
export NVIM_NIO_PATH=/path/to/nvim-nio
export DLV=/path/to/dlv
nvim --listen /tmp/dap-decoder.sock -u examples/decoders/init.lua examples/decoders/main.go
```

Put breakpoints with F9 on the three `// BREAK` lines. Start with F5, then
`:DapViewOpen`. Expand `wrapper`, then `decoded`, `address` and `tags`. You should
see `Ada`, age `37`, city `Kolkata`, and tags `debugger` and `protobuf`. Expand
`raw` to inspect the wrapper and its actual byte slice. The payload is 641 bytes,
including 600 padding bytes alternating NUL and `0xff`; it is serialized protobuf,
not a decoded Go struct. F10 twice advances past the assignment and changes age
to `38`. Continuing to the last breakpoint demonstrates malformed-wire fallback.
`:DapViewWatch wrapper` and `:DapViewHover wrapper` expose the same tree.

Switch live with `:DapViewProfile use fields`, `protobuf`, or `off`. `fields` is a
wrapper rule example; `json` is a local Lua decoder for a variable named `json`.
Use `:DapViewHost tab` / `split` to move the view. A configured remote host receives
the same tree through the existing owner/viewer transport.

For an existing LazyVim/plugin configuration, add this option to dap-view's `opts`
(using the actual absolute repository path):

```lua
decoders = dofile('/absolute/path/nvim-dap-view/examples/decoders/profiles.lua')
```

For your schema, generate a descriptor set with dependencies (for example,
`protoc --include_imports --descriptor_set_out=app.pb app.proto`) and change the
locally configured command's descriptor path and fully qualified message type.
The included `decode.py` uses those descriptors with the protobuf runtime and emits
JSON. Other tools, including `buf convert`, can be registered as fixed argv commands
if they accept binary stdin and emit JSON. `protoc --decode` emits protobuf text,
so it needs a locally configured converter to JSON; its output is not JSON by itself.
Missing schemas and invalid wire data show `decode error` alongside `raw`.

## Configuration and decoder contract

```lua
require('dap-view').setup({
  decoders = {
    profile = 'my-profile',
    max_bytes = 1048576,             -- input and command output limit
    request_timeout_ms = 5000,      -- decoder DAP work
    allow_evaluate = false,         -- only local configuration may enable this
    commands = {
      codec = { argv = { '/absolute/program', 'fixed-argument' }, timeout_ms = 5000 },
    },
    profiles = {
      { name = 'my-profile', decoders = {
        { name = 'Codec', kind = 'command', match = { name = 'payload' },
          command = 'codec', source = { kind = 'go_bytes' } },
      } },
    },
  },
})
```

Profiles are ordered decoder lists: the first matching decoder wins. Declarative
`match` uses exact `name`, `type`, and/or `path` equality; all supplied constraints
must match. Paths in scopes start with the scope name, e.g. `Locals.wrapper`;
watch and hover paths start with the expression. Local Lua may instead supply
`match(var, ctx)` and `kind='lua', decode=function(var, ctx) ... end`.
`ctx` includes `session`, `frame_id`, `path` and a stop/profile `generation`.
Local callbacks must finish quickly or yield through DAP requests; blocking Lua
cannot be made asynchronous by the plugin. Errors are caught and preserve raw data.

`decode` returns `{ value?: string, children?: Node[] }`. A Node has `name`,
optional string `value` and `type`, and optional nested `children`. Set
`variablesReference` to zero or omit it: plugin-owned references are allocated for
trees, and fabricated adapter references are rejected. `from_json(object)` builds
this result from a JSON-compatible Lua value. Trees have a maximum depth of 64.
Decoded values pass through the existing scope/watch truncation; full raw and
decoded nodes remain accessible. JSON arrays display one-based indices.

Kinds:

- `command`: the registered command ID selects an immutable local argv list. The
  exact payload goes to binary stdin, with no shell or value interpolation. Stdout
  must be JSON. Execution is asynchronous and bounded by timeout/output limits.
- `lua`: trusted local functions only. Useful for JSON parsing and custom wrappers.
- `rules`: `hide={'internal'}`, `rename={old='new'}`, `order={'first','second'}`
  transform immediate adapter children. Remaining fields sort by name; order uses
  renamed names. Raw children are still available. Local `computed={name='expr'}`
  requires `allow_evaluate=true` and explicitly evaluates the supplied expressions.
- `evaluate`: trusted local configuration plus `allow_evaluate=true` only. An
  `expression` template may contain `{expression}`, replaced by the adapter's
  `evaluateName`. It runs in the target with DAP watch context and **can have side
  effects**. It is never accepted through runtime profile registration.

## Payload integrity and adapter limits

`source={kind='go_bytes', field='Payload'}` optionally selects an immediate wrapper
field, requires Delve `[]uint8`/`[]byte` and `evaluateName`, evaluates the read-only
Go builtin `len(...)`, then requests every indexed byte in pages of 256. It never
parses the truncated slice summary. Every index must be present exactly once in
its requested page, with a numeric value in 0–255. An adapter that ignores paging,
lacks an evaluateName, refuses length evaluation, or returns incomplete bytes
produces a visible error and raw fallback. This path does not call target functions
or require the opt-in for arbitrary evaluate templates. Go strings are not supported
by this binary path; expose a byte slice instead. Pointer wrappers must be matched
and traversed to a slice explicitly.

`source={kind='memory', length=N}` uses the adapter's opaque `memoryReference` and
DAP `readMemory`, verifying both byte count and unreadable-byte reporting. Availability
is adapter-specific; Delve byte extraction does not depend on readMemory.
`source={kind='value'}` explicitly sends the adapter's displayed string verbatim.
It offers **no completeness or binary guarantee**: only use it when that display
is the intended input. Likewise, a Lua JSON decoder cannot recover a string that
the adapter truncated. Wrapper field selection applies to all three sources.

The cache includes session, frame, variable path/expression/type and raw displayed
value, with a generation invalidated on stepping, continuation, stops, scopes/frame
refreshes, mutation responses, profile changes and session end. Delve references
are intentionally excluded because it reallocates them when rereading unchanged
values. Async results from older generations or different sessions/frames are
ignored. If the debuggee mutates without a stop/event and keeps an identical
summary, explicitly call `require('dap-view.decoders').invalidate()` and refresh.

## Runtime registration: Lua, MCP and CLI

`require('dap-view.decoders').register_decoder_profile(profile)` is the data-only
runtime entry point; `use(name)` selects a profile. Registration invalidates cached
results but does not select a different profile. Runtime profiles can contain rules
and command IDs already allowlisted in local Lua. They cannot add argv, functions,
Lua strings to execute, evaluate templates or computed evaluations. Unknown fields,
invalid source specifications, non-data values and oversized profiles are rejected.

The MCP tools `register_decoder_profile({profile=...})` and
`use_decoder_profile({name='...'})` use this same validator when dap-view integration
is enabled. MCP's existing raw DAP variable tools retain their usual behavior; the
decoder tree is a UI feature, not a replacement for those adapter responses.

The included CLI needs only Python's standard library and Neovim. It passes data as
RPC arguments, never as Lua source or shell fragments:

```sh
python3 examples/decoders/profile.py --server /tmp/dap-decoder.sock register examples/decoders/profile.json
python3 examples/decoders/profile.py --server /tmp/dap-decoder.sock use rpc-protobuf
python3 examples/decoders/profile.py --server /tmp/dap-decoder.sock use off
```

The Neovim socket itself is a trusted local-control endpoint; these data-only APIs
are not a sandbox for a caller already allowed arbitrary Neovim RPC execution.

## Validation

```sh
# NVIM_DAP_PATH and NVIM_NIO_PATH may point at isolated test dependencies.
nvim --headless -u NONE -l tests/run.lua
nvim --headless -u NONE -l nvim-dap-mcp/tests/run.lua
(cd nvim-dap-mcp && go test ./...)
# Build fixtures first using the commands above. Starts its own debuggee and editor.
HOST=split nvim --headless -u NONE -l tests/integration/decoder_delve.lua
HOST=tab nvim --headless -u NONE -l tests/integration/decoder_delve.lua
python3 tests/integration/decoder_rpc.py  # optional NVIM=/absolute/path/to/nvim
```

The ordinary harness now exits nonzero on failed assertions. Decoder tests cover
JSON/rules, input validation, async completion and invalidation, output/timeout
failures, byte completeness, mutation protection, and actual detached-viewer RPC.
The integration test uses real Delve and compares every extracted binary byte to
the serialized fixture before exercising scopes/watches/hover and stepping.
Headless assertions verify buffer contents and interactions, not visual appearance
in a human's terminal or a specific multiplexer.
