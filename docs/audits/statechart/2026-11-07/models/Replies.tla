\* Bounded nvim-dap-view lifecycle audit; 2026-11-07. Run Statechart with matching cfg/view; Lua probes require DAP_REPO and headless Neovim. No VPN.
---- MODULE Replies ----
EXTENDS Naturals, Sequences, FiniteSets

VARIABLES kind, phase, epoch, requested, present, published, wrong
vars == <<kind,phase,epoch,requested,present,published,wrong>>
Init == /\ kind \in {"scopes","hover","watch","edit"} /\ phase = "idle" /\ epoch = 0 /\ requested = TRUE /\ present = TRUE /\ published = FALSE /\ wrong = FALSE
Begin == /\ phase = "idle" /\ phase' = "pending" /\ UNCHANGED <<kind,epoch,requested,present,published,wrong>>
ContextChanges == /\ phase = "pending" /\ epoch = 0 /\ requested /\ present /\ epoch' = 1 /\ UNCHANGED <<kind,phase,requested,present,published,wrong>>
RequestChanges == /\ phase = "pending" /\ kind \in {"scopes","hover"} /\ epoch = 0 /\ requested /\ present /\ requested' = FALSE /\ UNCHANGED <<kind,phase,epoch,present,published,wrong>>
RemoveWatch == /\ phase = "pending" /\ kind = "watch" /\ epoch = 0 /\ requested /\ present /\ present' = FALSE /\ UNCHANGED <<kind,phase,epoch,requested,published,wrong>>
Reply == /\ phase = "pending" /\ phase' = "done"
 /\ published' = (IF kind = "edit" THEN TRUE ELSE epoch = 0 /\ (kind # "scopes" \/ requested))
 /\ wrong' = FALSE /\ UNCHANGED <<kind,epoch,requested,present>>
Done == /\ phase = "done" /\ UNCHANGED vars
Next == Begin \/ ContextChanges \/ RequestChanges \/ RemoveWatch \/ Reply \/ Done
CurrentContext == ~(published /\ epoch # 0)
RequestedHover == ~(kind = "hover" /\ published /\ ~requested)
RemovedWatchStaysRemoved == ~(kind = "watch" /\ published /\ ~present)
RequestedScopes == ~(kind = "scopes" /\ published /\ ~requested)

====
