verdict: APPROVE
next_action: continue

Route the leaking paths through leadv2-state-path.sh; three new migration classes plus a flock.

- 8 dispatch helpers, not 3 — `.codex-credits-empty.stamp` (:878) has the same defect.
- `hooks/leadv2-single-lead-beat.sh:132` is a second raw reader the done-grep can't see.
- Naive migration writes `*.pre-controlplane-backup` into ~30 worktrees — the symptom, reintroduced.

Full: full.md
