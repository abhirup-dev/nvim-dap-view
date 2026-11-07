\* Bounded nvim-dap-view lifecycle audit; 2026-11-07. Run Statechart with matching cfg/view; Lua probes require DAP_REPO and headless Neovim. No VPN.
---- MODULE Preview ----
EXTENDS Naturals
VARIABLES origin, channel, sent, writable, phase
vars == <<origin,channel,sent,writable,phase>>
Init == /\ origin = "preview" /\ channel \in {"ui","mcp"} /\ sent = FALSE /\ writable = FALSE /\ phase = "shown"
Edit == /\ phase = "shown" /\ phase' = "done" /\ sent' = (channel = "mcp") /\ writable' = (channel = "mcp") /\ UNCHANGED <<origin,channel>>
Done == /\ phase = "done" /\ UNCHANGED vars
Next == Edit \/ Done
PreviewReadOnly == ~writable
PreviewNeverAdapterRef == ~sent
====
