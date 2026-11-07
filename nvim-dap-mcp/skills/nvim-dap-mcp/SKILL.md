---
name: nvim-dap-mcp
description: Drive the debug session the user already has open in Neovim. Use whenever a Neovim debug session is running or should be started — setting breakpoints, stepping, reading locals, evaluating expressions — instead of adding print statements or starting a second debugger.
---

# Debugging through the user's Neovim

These tools attach to the debug session the user can see. Breakpoints you set
appear in their gutter; the frame you step to is the frame on their screen.
There is one debuggee, shared. Prefer these tools over adding print statements
or launching a separate debugger.

## The loop

1. `list_configurations` → `set_breakpoint` → `start_session`
2. **`wait_for_pause`** — always, after every action that resumes the debuggee
3. Read: `session_status`, `get_variables`, `evaluate`, `get_stack`
4. `control` (`step_over` | `step_into` | `step_out` | `resume` | `pause` |
   `run_to_line`), then back to 2

## Rules

**After any `control` call, call `wait_for_pause`.** `control` returns as soon
as the request is accepted, not when the debuggee stops. `wait_for_pause`
blocks until it does and returns the same fat snapshot as `session_status`,
plus the event that ended the wait.

**Never poll `session_status` in a loop.** It is a snapshot, not a wait.
Polling it burns turns and races the debuggee. `wait_for_pause` exists for
exactly this and takes a `timeout_ms`.

**`session_status` is deliberately fat.** One call gives you the stop reason,
the current frame, source around it, the top of the stack and the current
frame's locals. Read it before reaching for `get_stack` or `get_variables`.

**Clamped values carry `truncated: true` and a `full_value_ref`.** Pass that
ref to `get_value` when you actually need the whole string. Don't re-evaluate
the expression to get around the clamp.

**`get_variables` is paged.** Use `page` rather than asking for everything.

**`evaluate` refuses expressions that look like assignments or calls** unless
the user configured `evaluate.allow_side_effects`. You'll get
`side_effects_refused`. Use `set_variable` for a deliberate change and say so.

## Errors

Every failure carries a stable code. The common ones:

| code | meaning |
|---|---|
| `no_session` | nothing is being debugged — `start_session` first |
| `not_stopped` | running; `wait_for_pause` or `control pause` first |
| `unknown_ref` / `unknown_frame` | stale handle, re-read `session_status` |
| `side_effects_refused` | see above |
| `dap_error` | the adapter itself said no; the message is its text |

`neovim_ping` tells you whether the sidecar can reach Neovim at all. Use it
once when nothing else is working, not as a health check between calls.
