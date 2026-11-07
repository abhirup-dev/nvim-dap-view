# Project issue tracking

Use `bd prime` for workflow context and `bd ready` to find available work.
Repository policy is in [AGENTS.md](../AGENTS.md); detailed CLI guidance is in
the [Beads skill](../.agents/skills/beads/SKILL.md).

Issues are stored in the local Dolt database. `bd dolt pull` and `bd dolt push`
sync the issue data through `refs/dolt/data`, separately from code branches.
The JSONL file is a passive export; do not use it as a normal import/sync path.

See [Beads sync concepts](https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md)
for the storage model. Git commits, pushes and remote sync still require the
authorization described in the repository policy.
