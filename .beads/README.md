# Project issue tracking

Use `bd prime` for workflow context and `bd ready` to find available work.
Repository policy is in [AGENTS.md](../AGENTS.md); detailed CLI guidance is in
the [Beads skill](../.agents/skills/beads/SKILL.md).

Issues are stored in the local Dolt database. `bd dolt pull` and `bd dolt push`
sync the issue data through `refs/dolt/data`, separately from code branches.
The JSONL file is a passive export; do not use it as a normal import/sync path.

On a new machine, run `bd bootstrap --yes` before creating issues. Do not run
`bd init` against a project that already has remote history. The shared remote
is `git+ssh://git@github.com/abhirup-dev/nvim-dap-view.git`; SSH authentication
must have access to this repository.

Before starting shared work, run `bd dolt pull`. After finishing authorized
issue updates, run `bd dolt push`. Code pushes alone do not publish issues.
Resolve a reported conflict explicitly; do not force-push or reinitialize the
database. Linked worktrees on one machine share the primary checkout's store;
their tracked JSONL exports can be older than the live database.

The 2026-11-07 recovery reconciled 58 issues and two memories from Mac and Moj;
VPS's 12 older issues were a subset. The original native histories remain in
Dolt branches `archive/mac-original`, `archive/stabilization-original`, and
`archive/remote-original`, all carried by `refs/dolt/data`. The canonical `main`
retains the original remote ancestry and adds the recovered current records.
The archived Mac and Moj histories contain 100 and 168 commits respectively;
the original remote history contains 15. Historical snapshots before recovery
remain on those archive branches rather than being rewritten into one timeline.
The full Moj native snapshot is also preserved on Git branch
`abhirup/beads-recovery-moj-20261107` at
`629ab508a5d1f25d36fe27217883c741d16a22f9`. Never extract its archive over a live DB.

Auto-export writes regular issues only and does not stage files. Memories and
complete history travel through Dolt; use `bd export --all` for a deliberate
issue-and-memory snapshot, not as a replacement for a native backup.

See [Beads sync concepts](https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md)
for the storage model. Git commits, pushes and remote sync still require the
authorization described in the repository policy.
