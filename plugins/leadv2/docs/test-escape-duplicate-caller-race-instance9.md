# Test escape: `test-dispatch-duplicate-caller-race.sh` (instance #9)

**Date:** 2026-09-06 16:02 EEST (glm run `260906-160232-a7f74519-4e66`)
**Escaped lane:** `worktree-a7f74519` (this worktree), dispatch id `dispatch-a7f74519`
**Worker model:** sonnet via `claude -p --model sonnet --effort low`
**Precedent:** the original 2026-08-24 duplicate-caller-race escape (lane
dispatch-adbc3304, see `plugins/leadv2/docs/test-escape-duplicate-caller-race.md`)
and instances #4–#8 recorded alongside it. This is the same suite escaping again.

## What happened

This worker's mission string is verbatim the fixture mission:
`docs-only: duplicate-caller-race 62383 1788699682` — pid 62383, epoch
1788699682 = 2026-09-06 13:01:22 UTC, seconds before this lane's registry
row started (13:02:16Z). The env confirms it live:

```
LEADV2_DISPATCH_SUBSESSION_BIN=/var/folders/.../dispatch-race-62383-1788699682.R3gg8x/fake-claude-subsession.sh
LEADV2_DISPATCH_TERMINAL_LEDGER_FILE=/var/folders/.../dispatch-race-62383-1788699682.R3gg8x/terminal-ledger.jsonl
LEADV2_DISPATCH_RACE_DELAY=0
```

`LEADV2_DISPATCH_GLM_BIN` is ABSENT from the env (probed live: only
SUBSESSION_BIN / RACE_DELAY / TERMINAL_LEDGER_FILE / CACHE_DIR / three gate
flags). `leadv2-dispatch-code.sh:5541` therefore fell back to the real
`glm-coder.sh`, which supervised this `claude -p` child. The fixture-owner
shell (pid 62383) had already exited by the time this worker probed
(`ps -p 62383` empty), so the suite run is finished; no live runner to wait on.

## Root cause — the 2026-08-24 fix never landed in THIS suite

New fact versus instance #8: there, the escaping suite
(`test-dispatch-ledger-task-id.sh`) had the `LEADV2_DISPATCH_GLM_BIN=/usr/bin/false`
guard on main and the escape came from a stale pre-fix worktree copy. Here the
opposite holds:

```
$ git show origin/main:plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh | grep -c GLM_BIN
0
$ grep -n GLM_BIN plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh   # live checkout
(only LEADV2_DISPATCH_SUBSESSION_BIN at :87)
```

So the original 2026-08-24 recommendation — "add `LEADV2_DISPATCH_GLM_BIN`
stub to the test" — was applied to `test-dispatch-ledger-task-id.sh:34`
(instance #5 follow-up) but NOT to the suite that started the whole escape
family. Every engine-side run of `test-dispatch-duplicate-caller-race.sh` on
current main still spawns a real GLM worker per winning racer. Do not re-run
that suite until it is stubbed.

## Action from inside the escape

None engine-side (standing policy from #6/#7/#8: the escaped worker does no
mission work; this document is the deliverable, committed docs-only on the
lane branch). Suggested follow-up for the owning lane: copy the
`LEADV2_DISPATCH_GLM_BIN=/usr/bin/false` guard (plus CODEX/KIMI siblings as in
`test-dispatch-ledger-task-id.sh:34`) into
`plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh`, and
audit the other suites named in `test-escape-duplicate-caller-race.md` the
same way against current main, not stale worktree copies.
