\* Bounded nvim-dap-view lifecycle audit; 2026-11-07. Run Statechart with matching cfg/view; Lua probes require DAP_REPO and headless Neovim. No VPN.
---- MODULE Startup ----
EXTENDS Naturals
VARIABLES phase, resource, pending, reply, ready
vars == <<phase,resource,pending,reply,ready>>
Init == /\ phase = "idle" /\ resource = FALSE /\ pending = 0 /\ reply = 0 /\ ready = FALSE
Start == /\ phase = "idle" /\ phase' = "waiting" /\ resource' = TRUE /\ pending' = 1 /\ UNCHANGED <<reply,ready>>
Reply == /\ phase = "waiting" /\ pending = 1 /\ reply' = 1 /\ phase' = "ready" /\ ready' = TRUE /\ pending' = 0 /\ UNCHANGED resource
Cancel == /\ phase \in {"waiting","ready"} /\ phase' = "closed" /\ resource' = FALSE /\ ready' = FALSE /\ pending' = 0 /\ UNCHANGED reply
LateReply == /\ phase = "closed" /\ reply = 0 /\ reply' = 1 /\ UNCHANGED <<phase,resource,pending,ready>>
Done == /\ phase = "closed" /\ UNCHANGED vars
Next == Start \/ Reply \/ Cancel \/ LateReply \/ Done
ClosedReleases == phase = "closed" => ~resource
ClosedNotReady == phase = "closed" => ~ready
ReadyOwns == ready => resource
====
