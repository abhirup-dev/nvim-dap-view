\* Bounded nvim-dap-view lifecycle audit; 2026-11-07. Run Statechart with matching cfg/view; Lua probes require DAP_REPO and headless Neovim. No VPN.
---- MODULE Remote ----
EXTENDS Naturals, Sequences, FiniteSets

VARIABLES phase, queued, host, acted
vars == <<phase,queued,host,acted>>
Init == /\ phase = "starting" /\ queued = FALSE /\ host = "remote" /\ acted = FALSE
Ready == /\ phase = "starting" /\ phase' = "ready" /\ UNCHANGED <<queued,host,acted>>
Fail == /\ phase = "starting" /\ phase' = "closed" /\ host' = "split" /\ UNCHANGED <<queued,acted>>
QueueKey == /\ phase = "ready" /\ ~queued /\ queued' = TRUE /\ UNCHANGED <<phase,host,acted>>
Dock == /\ phase = "ready" /\ phase' = "closed" /\ host' = "split" /\ UNCHANGED <<queued,acted>>
RunKey == /\ queued /\ queued' = FALSE /\ acted' = (acted \/ host # "remote") /\ UNCHANGED <<phase,host>>
Done == /\ phase = "closed" /\ ~queued /\ UNCHANGED vars
Next == Ready \/ Fail \/ QueueKey \/ Dock \/ RunKey \/ Done
NoOldCallback == ~acted

====
