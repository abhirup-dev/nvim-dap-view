# Statechart audit: 7 November 2026

This is historical evidence for **29aa630ae440f73a9ef421ce12df6bf30edd406a**,
before the fixes below. The models deliberately retain that implementation's
defects. Their failing invariants are evidence to preserve, not current test
failures to suppress. Updated models must identify their new source revision.

The audit explored **91 states and 213 transitions** in six finite models.
Every final counterexample was replayed against code. It found seven defects;
the child-watch tooltip defect came from source review, outside the models.
This is bounded safety checking, not a proof of complete runtime correctness.

| Finding | Durable issue | Regression / fix |
| --- | --- | --- |
| Tab reorder leaves stale saved ownership and closes a user tab | dv-c5r.14 | `eef1446`; session reorder regression |
| Stale JS edit reply changes replacement session cache | dv-c5r.15 | `cb64a82`; `tests/cases/external_mutation_refresh.lua` |
| Old hover reply replaces the requested expression | dv-c5r.13 | `b9ec7a6`; hover/watch reply regression |
| Removed watch is resurrected by a pending refresh | dv-c5r.13 | `b9ec7a6`; hover/watch reply regression |
| Queued remote key acts in a replacement host | dv-c5r.14 | `eef1446`; real PTY key ownership regression |
| MCP forwards decoder preview reference to adapter mutation | dv-c5r.15 | `52315c5`; `nvim-dap-mcp/tests/preview_boundary.lua` |
| Child-watch value tooltip reads the wrong record shape | dv-c5r.13 | `b9ec7a6`; hover/watch reply regression |

The independent HTTP audit also found premature pause snapshots and unstable
Delve frame selection (`dv-c5r.10`, `1435a34`), missing scopes refresh after MCP
mutation (`dv-c5r.12`, `cb64a82`) and lost breakpoints after interrupted run-to-line
(`dv-c5r.11`, `52315c5`). The composed select-frame/wait regression is repaired
by `5df148d`. These are runtime findings, not additional formal-model results.

## Evidence

- [Full audit and model exclusions](audit.md), including shortest numbered paths.
- [Per-file coverage and baseline hashes](coverage.tsv) and
  [async operation inventory](async-boundaries.txt).
- Reusable [TLA+, configuration and view sources](models/).
- Historical [code replay programs](replays/). These **assert the defective
  behavior** and should fail after the relevant fix. Use normal regression
  tests to validate the corrected behavior. Run historical replays only against
  an isolated checkout of the named baseline; they create their own Neovim
  processes and fixtures. No live editor or personal RPC socket is needed.

| Model | States / transitions | Original result | Reports and charts |
| --- | --- | --- | --- |
| Ownership | 8 / 9 | Two failed rules | [Report](ownership-review/report.md), [Mermaid](ownership-review/chart.mmd), [SVG](ownership-review/chart.svg) |
| Replies | 26 / 33 | Three failed rules | [Report](replies-review/report.md), [Mermaid](replies-review/chart.mmd), [SVG](replies-review/chart.svg) |
| Remote | 6 / 9 | One failed rule | [Report](remote-final/report.md), [Mermaid](remote-final/chart.mmd), [SVG](remote-final/chart.svg) |
| Tickets | 42 / 151 | Four safety rules hold | [Report](tickets-review/report.md), [Mermaid](tickets-review/chart.mmd), [SVG](tickets-review/chart.svg) |
| Preview | 4 / 4 | Two failed rules, one defect | [Report](preview/report.md), [Mermaid](preview/chart.mmd), [SVG](preview/chart.svg) |
| Startup | 5 / 7 | Three safety rules hold | [Report](startup/report.md), [Mermaid](startup/chart.mmd), [SVG](startup/chart.svg) |

All six deadlock checks hold. No temporal/liveness properties, fairness,
exhaustive payload validation, arbitrary interleavings or OS cleanup guarantees
were proven. The full audit describes the precise omissions. Raw TLC output
is retained beside each report, including individual rule traces when emitted.

## Reproduce the original model checks

From the repository root, with the pstack Statechart skill installed:

```sh
statechart=/path/to/pstack/skills/statechart/scripts/statechart
models="$PWD/docs/audits/statechart/2026-11-07/models"
for name in Ownership Replies Remote Tickets Preview Startup; do
  "$statechart" "$models/$name.tla" \
    --config "$models/$name.cfg" --view "$models/$name.view.mjs" \
    --out "/tmp/dap-view-statechart-rerun-$name"
done
```

Use fresh output directories. Exit 1 is expected for models with failed rules.
The skill requires a compatible Java/TLC and TypeScript runtime; its installer
and renderer are not vendored here. SVGs were rendered with **Pele 1.9.0**, using
`limit=1000000`, `outputLimit=8000000`, and `maxEdges=10000`.

For future changes, retain this snapshot, write a separate revision-specific
model, and replay every new counterexample against code. Preserve invariants
when revising implementation guards. Track maintainability proposals in the
separate Beads epic **dv-8x5**; they are not stabilization requirements.
