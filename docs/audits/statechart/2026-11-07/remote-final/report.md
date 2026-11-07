# Remote

TLC reached 6 states and 9 steps. The chart draws 6 states and 7 arrows.
The chart does not draw 2 steps that stay in one chart state.

## NoOldCallback breaks
The shortest path has 4 steps:
0. starting
1. viewer attaches: ready
2. viewer sends a key: ready / key queued
3. you dock into a local host: closed / key queued
4. scheduled key runs: closed / key applied

## Rules that hold
NoDeadlock
