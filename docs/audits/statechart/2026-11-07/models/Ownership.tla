\* Bounded nvim-dap-view lifecycle audit; 2026-11-07. Run Statechart with matching cfg/view; Lua probes require DAP_REPO and headless Neovim. No VPN.
---- MODULE Ownership ----
EXTENDS Naturals, Sequences, FiniteSets

VARIABLES pages, owned, marker, saved, phase
vars == <<pages,owned,marker,saved,phase>>
Init == /\ pages = <<"user","debug">> /\ owned = "debug" /\ marker = 2 /\ saved = 0 /\ phase = "live"
Reorder == /\ phase = "live" /\ pages = <<"user","debug">> /\ pages' = <<"debug","user">> /\ UNCHANGED <<marker,owned,saved,phase>>
Save == /\ phase = "live" /\ saved' = marker /\ phase' = "saved" /\ UNCHANGED <<pages,owned,marker>>
Restore == /\ phase = "saved" /\ phase' = "restored" /\ owned' = pages[saved] /\ marker' = 0 /\ UNCHANGED <<pages,saved>>
Close == /\ phase = "restored" /\ pages' = SelectSeq(pages,LAMBDA p:p # owned) /\ phase' = "closed" /\ owned' = "none" /\ UNCHANGED <<marker,saved>>
Done == /\ phase = "closed" /\ UNCHANGED vars
Next == Reorder \/ Save \/ Restore \/ Close \/ Done
NeverCloseUser == "user" \in {pages[i]:i \in 1..Len(pages)}
RestoredIdentity == phase = "restored" => owned = "debug"

====
