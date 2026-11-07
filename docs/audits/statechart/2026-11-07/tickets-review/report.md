# Tickets

TLC reached 42 states and 151 steps. The chart draws 10 states and 8 arrows.
The chart does not draw 83 steps that stay in one chart state.
The step event or timeout settles the wait changes Ticket and Wait at the same time.
The step caller collects its reply changes Ticket and Caller at the same time.

## Rules that hold
AtMostOnce, CanceledCannotDeliver, SettledReleasesWait, OldExitKeepsReplacement, NoDeadlock
