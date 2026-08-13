verdict: APPROVE
next_action: continue

F1+F2 are one defect: predicates run on the whole string, not the launcher's own shell segment. Fix = python3 lexer emits launcher-execution segments; every exemption and the background test re-anchored to a segment.

- Read-only verbs pass by construction — no allowlist needed.
- Mission's `git merge --ff-only origin/main` will fail: lane diverged 9/1. Rebase.
- 2 files, 9 new tests, test 21 replaced.

Full: architect.full.md
