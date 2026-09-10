<!-- BEGIN DEVFLOW -->
## This repo uses DevFlow

Read `.planning/STATE.md` first. It names the current phase, what is in flight, and the
next command to run. Everything DevFlow knows lives on disk under `.planning/` — not in
chat history — so a cold session loses nothing.

| Need | Read |
|------|------|
| Where the project stands | `.planning/STATE.md` |
| What we're building, in what order | `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md` |
| Binding technical constraints | `.planning/ARCHITECTURE.md` |
| Recent activity | `.planning/JOURNAL.md` |
| Existing-codebase map | `.planning/codebase/MAP.md` |

`.planning/ARCHITECTURE.md` is **law, not advice**: use exactly the versions it pins,
nothing from its Forbidden list, and treat its `## Principles` as binding. Work that
needs something outside it is a decision for the human, never an improvisation.

**Git**: never commit to the base branch. Work lands on a `flow/<slug>` feature branch
and integrates by pull request. Never commit credential material — reference env vars by
name and do not open `.env*` files.

**Evidence over assertion**: a claim that something works needs a command that ran, a
test that passed, or a code path traced. "Should work" is not a result.

Drive the workflow with the `flow-*` skills — `/flow-*` in Claude Code, `$flow-*` in
Codex. `/flow-status` reports where things are and what to run next.
<!-- END DEVFLOW -->
