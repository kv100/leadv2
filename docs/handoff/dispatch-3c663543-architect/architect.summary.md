verdict: APPROVE
next_action: continue

# architect — LANDED-AT-SPAWN-01

Delete the spawn-time `landed` write (no synchronous arm exists on that path), and key every ledger write to the lane worktree's main checkout instead of the caller session's env.

- `:2513` removed; the confirmed reservation stays as the only spawn-time record.
- New `LEDGER_REPO_ROOT` (git-common-dir of WORK_ROOT) threaded into `_dl_note` + `repo_slug()` — covers reserve/confirm/terminal.
- New suite `scripts/tests/test-landed-at-spawn.sh`, registered in run-core-offline.sh.

Full: architect.full.md
