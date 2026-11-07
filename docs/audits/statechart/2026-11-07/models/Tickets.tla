\* Bounded nvim-dap-view lifecycle audit; 2026-11-07. Run Statechart with matching cfg/view; Lua probes require DAP_REPO and headless Neovim. No VPN.
---- MODULE Tickets ----
EXTENDS Naturals, Sequences, FiniteSets

VARIABLES ticket, client, settled, deliveries, age, resources, sidecar, oldExit
vars == <<ticket,client,settled,deliveries,age,resources,sidecar,oldExit>>
Init == /\ ticket = "pending" /\ client = "waiting" /\ settled = FALSE /\ deliveries = 0 /\ age = 0 /\ resources = TRUE /\ sidecar = 1 /\ oldExit = FALSE
Poll == /\ ticket # "absent" /\ client = "waiting" /\ age' = 0 /\ UNCHANGED <<ticket,client,settled,deliveries,resources,sidecar,oldExit>>
Age == /\ age = 0 /\ age' = 1 /\ UNCHANGED <<ticket,client,settled,deliveries,resources,sidecar,oldExit>>
Expire == /\ age = 1 /\ ticket # "absent" /\ ticket' = "absent" /\ UNCHANGED <<client,settled,deliveries,age,resources,sidecar,oldExit>>
Cancel == /\ client = "waiting" /\ client' = "canceled" /\ UNCHANGED <<ticket,settled,deliveries,age,resources,sidecar,oldExit>>
Finish == /\ ~settled /\ settled' = TRUE /\ resources' = FALSE /\ ticket' = (IF ticket = "pending" THEN "done" ELSE ticket) /\ UNCHANGED <<client,deliveries,age,sidecar,oldExit>>
Collect == /\ ticket = "done" /\ client = "waiting" /\ ticket' = "absent" /\ client' = "delivered" /\ deliveries' = deliveries + 1 /\ UNCHANGED <<settled,age,resources,sidecar,oldExit>>
Restart == /\ sidecar = 1 /\ sidecar' = 2 /\ UNCHANGED <<ticket,client,settled,deliveries,age,resources,oldExit>>
OldExit == /\ sidecar = 2 /\ ~oldExit /\ oldExit' = TRUE /\ UNCHANGED <<ticket,client,settled,deliveries,age,resources,sidecar>>
Idle == UNCHANGED vars
Next == Poll \/ Age \/ Expire \/ Cancel \/ Finish \/ Collect \/ Restart \/ OldExit \/ Idle
AtMostOnce == deliveries <= 1
CanceledCannotDeliver == client = "canceled" => deliveries = 0
SettledReleasesWait == settled => ~resources
OldExitKeepsReplacement == oldExit => sidecar = 2

====
