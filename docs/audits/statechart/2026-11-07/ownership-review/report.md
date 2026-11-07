# Ownership

TLC reached 8 states and 9 steps. The chart draws 8 states and 7 arrows.
The chart does not draw 2 steps that stay in one chart state.

## RestoredIdentity breaks
The shortest path has 3 steps:
0. live / original order
1. you move the debugger tab without switching tabs: live / debugger moved first
2. you save the stale index: saved / debugger moved first
3. the saved index selects its restored tab: restored / user claimed

## NeverCloseUser breaks
The shortest path has 4 steps:
0. live / original order
1. you move the debugger tab without switching tabs: live / debugger moved first
2. you save the stale index: saved / debugger moved first
3. the saved index selects its restored tab: restored / user claimed
4. the claimed tab closes: closed / user tab lost

## Rules that hold
NoDeadlock
