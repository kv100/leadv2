# DISPATCH-FG-GUARD-01 — fix round 2 (plugin repo ~/Projects/leadv2)

Round 1 (commit `b40800f`) was reviewed and BLOCKED. Continue from your existing edits in this
lane — do not start over, do not revert round 1. Full review:
`~/Projects/persona-engine/docs/handoff/DISPATCH-KILLED-BY-FG-TIMEOUT-01/fgguard-review.md`.

## F1 — CRITICAL, blocking. The exemption defeats the guard.
`plugins/leadv2/hooks/leadv2-block-fg-dispatch.sh:56-58` greps the WHOLE command string for the
`status` / `record-review` / `--help` / `-h` / `--no-spawn` exemptions, instead of the launcher's
own argv. So this is silently ALLOWED and the dispatch still dies to SIGTERM:

    bash .../leadv2-dispatch-code.sh @m.md && git status
    bash .../leadv2-dispatch-code.sh @m.md ; git status

Reproduced live against this worktree.

Fix: split the command on `&&`, `||`, `;` and `|` FIRST, find the segment that contains the matched
launcher basename, and evaluate every exemption against that segment alone. Apply the same scoping
to all four exemptions, not only `status` — `--help` and `--no-spawn` have the identical shape and
the identical hole.

## F2 — HIGH, non-blocking but fix it now. Read-only commands are blocked.
The target match (around :48) is a bare grep for the launcher basename with no verb check, so
`cat leadv2-dispatch-code.sh`, `git log -- leadv2-dispatch-code.sh`, `grep -n foo
leadv2-dispatch-code.sh` are all denied. These are exactly the files a lead reads while working on
this subsystem, so it will fire constantly. Require that the launcher appear in an EXECUTION
position — first word of the segment, or the argument to `bash`/`sh`/`zsh`/`source`/`.` — and let
read-only verbs (`cat`, `less`, `head`, `tail`, `grep`, `rg`, `git`, `ls`, `stat`, `wc`, `diff`)
through without needing the override.

## F3 — the test suite passes 24/24 and covers NEITHER bug.
Test 21, "status subcommand does not match path fragment", is mislabeled: its input
(`leadv2-status-surface.sh`) fails the basename target-match before it ever reaches the exemption
regex it claims to exercise. It proves nothing.

Add tests that FAIL against round 1's code and pass after the fix:
- `bash .../leadv2-dispatch-code.sh @m.md && git status` → DENIED
- `bash .../leadv2-dispatch-code.sh @m.md ; git status` → DENIED
- `bash .../leadv2-dispatch-code.sh @m.md && echo done --help` → DENIED
- `bash .../leadv2-dispatch-code.sh status` → ALLOWED (real subcommand, unchanged)
- `bash .../leadv2-dispatch-code.sh @m.md --no-spawn` → ALLOWED
- `cat leadv2-dispatch-code.sh` → ALLOWED, no override needed
- `git log -- plugins/leadv2/scripts/leadv2-dispatch-code.sh` → ALLOWED
- `bash .../leadv2-dispatch-code.sh @m.md &` → ALLOWED
Fix test 21's label, or delete it and replace it with one that actually reaches the exemption path.

## Unchanged and confirmed clean by review — do not touch
Internal-subprocess deadlock, python3-absent degradation, argv-replay quoting, fail-open discipline.
The C3 message change is accepted as-is.

## Write set
Same as round 1. Do not widen it.

## Acceptance
All new tests above green, the existing 24 still green, from a base that is up to date with
`origin/main` (`git fetch && git merge --ff-only origin/main` first — round 1 branched from a stale
base and its diff read as 1628 phantom deletions).

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit + raw test output.
