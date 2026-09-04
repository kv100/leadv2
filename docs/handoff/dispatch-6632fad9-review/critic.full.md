# Adversarial review — V3-ENV-GUARDS-01 (commit 79c25ed + registration 1806b4f)

Reviewer: critic (opus), 2026-08-20. Method: execution in `~/Projects/leadv2`, no repowise.
Diff hash: `git -C ~/Projects/leadv2 show 79c25ed | shasum -a 256` =
`6a68a6d1b32849909cf97ea0e0b9cc427560c37edbc9ad35da5b9265eda50e63`

## Verdict: PASS_WITH_NITS

All three items are COMPLETE and functionally correct. Nothing in the diff is
half-written residue of the dead worker — the second writer (item 1) and the
detection block (item 2, "in progress at death" per the commit message) are both
whole. Four nits below, none blocking.

---

## Item 1 — PUMP-JUNK-IN-LANE-01 — COMPLETE

**Fix shape.** `leadv2-backlog-pump.sh` adds `_lv2bp_canonical_root()` (bash-3.2 safe,
no `--path-format=absolute`), resolving the MAIN checkout via a `cd` chain through
`git rev-parse --git-common-dir`. `CACHE_DIR` and `EMPTY_STREAK_DIR` both pin to
`CANONICAL_ROOT` instead of `PROJECT_ROOT` (which falls back to `--show-toplevel` =
the lane worktree). `LEADV2_BACKLOG_PUMP_CACHE_DIR` is a deliberate test seam.

**Both writers checked.** The mission's "second writer" is
`hooks/leadv2-supervisor-pump-caller.sh:173-175`. Its fix is complete, not truncated:
it inlines the same 4-line canonical resolution and repoints `BELOW_FLOOR_SENTINEL`.
Grep confirms this file only ever *reads* the sentinel (`-f` test at :177, `stat` at
:180) — the sole writer is `leadv2-backlog-pump.sh:463` via `CACHE_DIR`, now canonical.
So reader and writer agree on one location, and the pump-caller no longer touches the
lane at all.

**Manual reproduction of the original disease** (independent of the test file):
running `leadv2-backlog-pump.sh status` from inside a linked worktree with
`LEADV2_PROJECT_ROOT`/`CLAUDE_PROJECT_DIR`/`PROJECT_ROOT` all unset —

- pre-fix (79c25ed^): **4 files leaked into the worktree**, exactly the live shape from
  task 6cf5d07e — `.claude/cache/backlog-pump/` plus `liveness.json`, `liveness.ts`,
  `liveness.sig`.
- post-fix: worktree clean (0), `liveness.json` present under the main checkout.

Second-writer path resolution reproduced separately from a fixture worktree:
resolved canonical == main checkout root. Non-git identity fallback verified under
`bash`: returns the candidate unchanged.

**Suite:** `test-pump-junk-in-lane.sh` → pass=2 fail=0. Red-first: genuinely fails on
pre-fix code with the 4-file leak listed above (not a stubbed toggle — it runs the real
binary from the real pre-fix tree).

### Nit 1-A (low) — identity fallback rests on bash's `cd ""` failing
Both canonical resolvers rely on `cd "$(git rev-parse --git-common-dir 2>/dev/null)"`
failing when git prints nothing. That holds because **bash** rejects `cd ""` (`cd: null
directory`, rc=1) — verified. It does **not** hold in zsh, where `cd ""` is a no-op
rc=0, so the chain would proceed to `cd ..` and silently resolve the **parent of the
candidate** as the "canonical root". Both files carry `#!/usr/bin/env bash` so this is
inert today, but the invariant is implicit. An explicit
`gcd="$(git rev-parse --git-common-dir 2>/dev/null)"; [[ -n "$gcd" ]] || return-fallback`
would make it structural rather than shell-dialect-dependent. (I initially read this as a
live defect; it was a zsh probe artifact on my side — recording it so the next reader
doesn't repeat the scare.)

### Nit 1-B (low) — the test seam is asymmetric between the two files
`leadv2-backlog-pump.sh` honours `LEADV2_BACKLOG_PUMP_CACHE_DIR`; the pump-caller does
not. With the override set, the writer and the sentinel reader diverge. Test-seam-only
today, but it re-creates the exact reader/writer split this task exists to close.

---

## Item 2 — arm_dead_instant_complete — COMPLETE

Requirements checked against `leadv2-dispatch-code.sh:3440-3550, 3584-3672`:

- **(a) triggers on the dead shape.** `_codex_rollout_dead_shape` scans the rollout from
  the end for the last `event_msg`/`task_complete` payload: rc0 = `last_agent_message`
  null/absent (dead), rc2 = real message (healthy), rc1 = no terminal event yet.
  `_codex_instant_complete_deadline_check` polls up to
  `LEADV2_CODEX_INSTANT_COMPLETE_SECS` (default 30) — that window *is* the mission's
  "<30s", and "empty final output" *is* `last_agent_message: null`. Faithful mapping.
  `_codex_spawn_epoch` is captured before spawn so a prior unrelated rollout cannot be
  mistaken for this one's.
- **(b) journals** `arm_dead_instant_complete arm=codex task=… rollout=…` — present at
  :3536 via `emit decision`.
- **(c) provider strike** — `record-quota-lockout --provider codex --hours 1 --reason
  arm_dead_instant_complete`. Verified `cmd_record_quota_lockout` accepts that arg shape
  (`--hours` integer 1..168, stand-down mode).
- **(d) spills, does not detach as success** — returns 7; the caller sets
  `LAST_ARM_OUTCOME=codex_dead_instant_complete`, emits `arm_refused … reason=instant_complete`,
  calls `dispatch_abort`, returns 7. Traced rc=7 into the candidate loop
  (`leadv2-dispatch-code.sh:4685`): it appends to `attempted[]` and falls through to the
  loop's `continue` — i.e. the next arm. Identical contract to the pre-existing
  `_codex_first_byte_deadline_check` rc=7 path.
- **healthy run does not trip** — `test-codex-instant-complete.sh` case 2 (real
  `last_agent_message`, duration 5000ms) returns rc=2 → `return 0`, proceed. Case 3
  (still running) returns rc=1 → keeps polling, never spills.
- **routing order / ceilings untouched.** The new block sits strictly inside the existing
  `if [[ "${arm}" == "codex" ]]` guard after the first-byte check; no candidate-order or
  ceiling code is in the diff.

**Suite:** `test-codex-instant-complete.sh` → pass=5 fail=0. Red-first: against pre-fix
code all three `check_extracted` guards fire and cases 1-3 return rc=127 (function absent).
The extract-by-`sed`-from-the-real-file harness plus the explicit "extraction broke, or fn
renamed" guard is the opposite of tautological — a rename silently passing is exactly what
it prevents.

### Nit 2-A (medium) — the rollout scan is global, not task-scoped
`_codex_newest_rollout_since` walks all of `$CODEX_HOME/sessions` and returns the newest
file with `mtime >= since`. Nothing binds that file to *this* dispatch. Two codex arms
running concurrently in different lanes (separate dispatch processes — the "one arm at a
time per process" comment in item 3 does not cover cross-process concurrency) can be
judged by each other's rollout: a healthy lane can be killed by a sibling's dead rollout,
or a dead lane can be masked by a sibling's healthy one. Rollout files carry session
metadata (`turn_id`, cwd) that could scope this. Low frequency today (WIP=1 in single-lead
mode), but the guard's whole purpose is to make a dead arm unambiguous, and this is the
one way it can lie in either direction.

### Nit 2-B (low) — +30s on every healthy codex dispatch
The check returns early only on a *terminal* event. A codex job that is genuinely working
produces no `task_complete` inside the window, so the dispatcher blocks the full 30s
before proceeding — on top of the first-byte deadline, which precedes it. No lock is held
(fix-pass-4 reserve→spawn-unlocked→confirm), so this is latency, not contention. Worth a
tuning note; `LEADV2_CODEX_INSTANT_COMPLETE_SECS` makes it adjustable.

### Nit 2-C (low) — the strike is untested and heavier than the mission asked
Mission text said "short `--minutes` lockout"; the implementation uses `--hours 1`. That
matches the sibling `arm_dead_no_first_byte` guard at :3433 exactly, so consistency is the
better defence here — but it is a spec deviation worth a conscious ack. Separately, test
case 5 stubs `DISPATCH_SELF_BIN=/bin/true`, so requirement (c) — the strike actually being
recorded — has **no test coverage**; only the rc=7 spill is asserted.

---

## Item 3 — worker env asserts — COMPLETE

`_worker_env_asserts <arm> <sig8>` is called as the first statement of `spawn_worker()`,
before any launcher is invoked.

- **AGENT_TEAMS assert present.** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` non-empty and
  != "0" → `unset` + journal `action=unset was=…`; otherwise journal `action=ok`. The
  worker therefore never inherits `=1` from a stray profile.
- **TODO_TOOLS audit decision is journaled, not silently absent.** Default path exports
  `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` and journals `action=set value=1`; the opt-out
  (`LEADV2_WORKER_TODO_TOOLS=0`) journals `action=skip reason=opt_out`. The rationale
  (CC 2.1.233 dropped the Task-tool family by default; `leadv2-continuation-guard.sh`
  scores TaskCreate/TaskUpdate as productive and `hooks.json` registers TaskCreated) is
  recorded in the code comment. Exactly two journal lines per call, always.

**Env actually reaches the launcher.** `spawn_worker` is invoked inside `$(...)`, so the
`unset`/`export` are subshell-scoped — but the launcher is `exec`'d from that same
subshell, so the composed env does propagate. The in-code comment calling this a
"process-global mutation" is imprecise; the behaviour is correct.

**No stdout contamination.** `emit()` → `bash "$JOURNAL_BIN" … >/dev/null 2>&1` then
`log()`, and `log()` writes to **stderr** (`leadv2-dispatch-code.sh:475`). Confirmed the
asserts cannot corrupt the handle that `spawn_out="$(spawn_worker …)"` captures — this
was my main suspected break and it is clean.

**Suite:** `test-worker-env-asserts.sh` → pass=6 fail=0. Red-first: against pre-fix code
the extraction guard fires, the harness has no function to call, and cases collapse
(no journal file, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` still present in the env
snapshot). The test extracts the real `emit()` + `_worker_env_asserts()` from
`leadv2-dispatch-code.sh` by `sed` rather than reimplementing them — non-tautological.

---

## Mechanical gates

- `bash -n`: OK on all 6 changed/added files.
- `shellcheck -S warning`: **no delta** vs 79c25ed^ on all three changed scripts
  (diff of sorted findings, pre-fix worktree vs main, is empty). The pre-existing
  SC2034 `LANE_LIVENESS_FAILED` at backlog-pump:342 is present on both sides, as flagged.
- Off-limits: `git show --stat 79c25ed --name-only` matches none of
  `leadv2-dispatch-product-close.sh`, `lib/leadv2-builder-selfcheck.sh`, `supervise*`. Clean.
- Registration: all three suites present in `run-core-offline.sh:229-231` (commit 1806b4f).

## Recommended follow-ups (none blocking)

1. Task-scope the rollout lookup in `_codex_newest_rollout_since` (nit 2-A) — this is the
   only finding that can produce a *wrong verdict* rather than a cosmetic issue.
2. Make the canonical-root fallback explicit instead of relying on `cd ""` semantics
   (nit 1-A), and teach the pump-caller the same `LEADV2_BACKLOG_PUMP_CACHE_DIR` seam
   (nit 1-B).
3. Add one test leg asserting the provider strike is recorded on the dead verdict (nit 2-C).
