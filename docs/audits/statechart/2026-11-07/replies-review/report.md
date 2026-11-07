# Replies

TLC reached 26 states and 33 steps. The chart draws 26 states and 22 arrows.
The chart does not draw 11 steps that stay in one chart state.

## CurrentContext breaks
The shortest path has 3 steps:
0. edit / idle
1. you request a value: edit / pending
2. session, frame or decoder profile changes: edit / pending / changed context
3. the adapter replies: edit / done / changed context / published

## RequestedHover breaks
The shortest path has 3 steps:
0. hover / idle
1. you request a value: hover / pending
2. you replace the requested view or expression: hover / pending / request replaced
3. the adapter replies: hover / done / request replaced / published

## RemovedWatchStaysRemoved breaks
The shortest path has 3 steps:
0. watch / idle
1. you request a value: watch / pending
2. you remove the watch: watch / pending / watch removed
3. the adapter replies: watch / done / watch removed / published

## Rules that hold
RequestedScopes, NoDeadlock
