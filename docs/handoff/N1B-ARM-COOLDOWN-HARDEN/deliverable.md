# N1B-ARM-COOLDOWN-HARDEN — deliverable

Base: `30ad24e`. Repo: `~/Projects/leadv2`. Findings: `docs/handoff/ARMS-ALWAYS-AVAILABLE-01/codex-review.md`.

The one thing this task protects: **an arm's availability must be decided by a value no environment variable and no write ordering can push outside a range fixed in reviewed source.** All five findings put the three-day-silent-fallback failure back within reach by a different door; each door is now closed.

## Files changed (6, all pre-existing — NO new file created)

| File | Change |
|---|---|
| `plugins/leadv2/scripts/lib/leadv2-arm-cooldown.sh` | F1 hard bound, F2 octal sanitizer + writer guard, F3 max-reprobe scan + portable lock |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | F4 `_dispatch_append_pending_locked` gains `lane_label` (9th positional); `dispatch_reserve` passes `DISPATCH_FOUNDER_TASK_ID` as task_id, `DISPATCH_LANE_NAME` as lane_label |
| `plugins/leadv2/scripts/leadv2-status-surface.sh` | F4 `resolve_name(task_id, lane_label, …)` rule ladder; merge gains `lane_label`; `add_row` threads it |
| `plugins/leadv2/scripts/tests/test-arm-cooldown.sh` | F1/F1b/F2/F2b/F3/F3b assertions |
| `plugins/leadv2/scripts/tests/test-codex-lockout-agreement.sh` | F5 `_run_bounded` portable runner + branch tests |
| `plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh` | F4/F4b rendered-row assertions; C1 updated to the fixed schema |

No new file under `plugins/leadv2/scripts/` — so no per-file symlink was owed (the 2026-08-02 outage class is structurally impossible here). Every edited file already had its three symlinks; editing canonical updates all live repos.

## Finding 1 — a bound the operator cannot raise

`ARM_COOLDOWN_HARD_MAX_S=3600` and `ARM_COOLDOWN_HARD_MIN_S=1` are **literals in the library body, not read from the environment.** Clamp order (every path):

```
max     = clamp(env MAX_S , HARD_MIN, HARD_MAX)   # bounded BEFORE used as a ceiling
min     = clamp(env MIN_S , HARD_MIN, max)
default = clamp(env COOLDOWN, min, max)
```

An operator may LOWER the ceiling (shorter cooldown = re-probe sooner, always safe); cannot RAISE it past 3600. Raising 3600 requires editing the library — a reviewed commit with a symlink-visible diff, the exact gate a `LEADV2_*` export bypasses.

Evidence (`LEADV2_ARM_COOLDOWN_S=99999 LEADV2_ARM_COOLDOWN_MAX_S=99999`, NOW=1000000000=2001-09-09T01:46:40Z):

```
… reprobe_at=2001-09-09T02:46:40Z cooldown_s=3600 …
```

reprobe is exactly 3600 s after the refusal — not the ~27.8 h the same command produced on `30ad24e`. Operator-lowered (`MAX_S=120`) is still honoured (test F1b).

## Finding 2 — octal + the empty reprobe_at that read `clear`

Three independent guards, all required:
- **(a) `_arm_cooldown_int`** is the ONE sanitizer: pure-digit only, strips leading zeros (`08`→`8`), rejects >10 digits (signed-32 overflow). Every numeric that reaches `$(( ))` or `[ -gt ]` is routed through it — `now_epoch`, the `iso_epoch` *return*, and min/max/default/effective.
- **(b) writer guard:** after computing `reprobe`, if it is empty or fails to parse to a future epoch for *any* reason, fall back to `now+min` and mark `src=fallback`. A record is well-formed or it is not written — no third state.
- **(c) reader guard:** lines whose `reprobe_at` does not parse are skipped (redundant with the reader's max-scan, see F3).

Evidence (`LEADV2_ARM_COOLDOWN_MAX_S=08`):

```
… reprobe_at=2001-09-09T01:46:48Z cooldown_s=8 … src=default
state(glm) = cooling 2001-09-09T01:46:48Z quota
```

No `value too great for base`; non-empty parseable reprobe; state reads `cooling` right after a real refusal (on `30ad24e` it read `clear`). `cooldown_s=8` is correct: `08`→`8` is a valid lowered ceiling, honoured as-is.

## Finding 3 — the stale writer cannot un-cool an arm

Two parts; **(b) is the real one.**
- **(a) ordering:** the append takes the existing `leadv2-portable-lock.sh` (sourced defensively, guarded on `command -v lv2_lock_wait`; degrades to unlocked if absent). Fail-open on a 2 s timeout — a single sub-`PIPE_BUF` `>>` append is atomic on APFS/ext4; the lock buys ordering, not atomicity.
- **(b) semantics:** the reader no longer takes `tail -n 1`. An arm is **cooling if any record in the last 200 carries a future `reprobe_at`**; the verdict reports the **latest** such `reprobe_at` + reason. Append order is now irrelevant to the verdict — strictly stronger than locking, and deterministic (which is what makes the test possible).

Evidence — record at `t0+800` first (newer refusal, cools to `t0+1700`), **then** record at `t0` (stalled writer landing late, cools only to `t0+900`), read at `t0+1000`:

```
state(sonnet)@t0+1000 -> cooling 2033-05-18T04:01:40Z quota
```

The newer `t0+1700` reprobe wins — on `30ad24e` `tail -n 1` picked the stale `t0+900` row and read `clear`. `arm_cooldown_clear` still truncates → `clear` (test F3b). `tail -n 200` bounds the read O(1) as the file ages.

## Finding 4 — a display label and an identity must not share a field

Two fields, two meanings, at every hop:

| field | meaning | written from | eligible for `tasks.yaml` lookup |
|---|---|---|---|
| `task_id` | identity (founder-bound) | `DISPATCH_FOUNDER_TASK_ID` only (empty when absent) | **yes** |
| `lane_label` | display label (prose-derived) | `DISPATCH_LANE_NAME` when no `--task-id` | **never** |

The `DISPATCH_LANE_NAME` resolution (`:1926-1930`) is unchanged — only its destination field changed. Reader `resolve_name(task_id, lane_label, …)`: (1) `tasks.yaml` by `task_id` (the ONLY lookup) → (2) `task_id` verbatim → (3) `lane_label` verbatim, **never looked up** → (4) `unnamed`. `lane_label` absent → empty string → rule 3 skipped (backward-compatible with pre-change rows).

Evidence — mission headed `# OPS-42 — cleanup`, `tasks.yaml` has id `OPS-42` titled `Totally unrelated record`:

- **no `--task-id`:** rendered name = **`OPS-42`** (the label verbatim), not the unrelated title.
- **`--task-id OPS-42`:** rendered name = **`Totally unrelated record`** (identity lookup preserved — the fix did not over-reach).

C1 in `test-dispatch-ledger-task-id.sh` previously asserted the *buggy* behaviour (`task_id` == H1 name-token for a no-`--task-id` lane); it now asserts the fixed schema (`task_id` empty **and** `lane_label` == H1 name-token). That is the test evolving with the fix, not a weakening — it still proves the lane name is captured, in the correct field.

**R3 pre-landing grep (done):** every other consumer of the dispatch-ledger `task_id` JSON field reads it as an identity — `leadv2-lane-liveness.sh` reads `task_id` from `active.yaml` sessions (a sig8 identity), `lv2-ledger-emit.py`/`lv2-ledger-last-phase.py` read a *separate* phase ledger keyed by an identity arg, and the terminal-ledger writer's display-name `task_id` is consumed only by this same reader via the unchanged `task_id or founder_task_id` merge (terminal rows explicitly out of scope per the design — they carry `founder_task_id`, an identity). No consumer other than `leadv2-status-surface.sh` read the pending-ledger `task_id` as a display label.

## Finding 5 — the agreement test on a clean macOS

`_run_bounded <secs> <cmd…>` lives **inside** the test file (no new file):
- **fast path:** `command -v timeout` → delegate, preserving stdout+stderr + rc.
- **fallback (bash 3.2, no coreutils):** background with output to a temp file under the suite's existing `$ROOT` (covered by its `trap rm -rf`), poll `kill -0` on a 0.2 s step, on expiry `kill -TERM` then `kill -KILL`, emit **rc 124** (GNU semantics). Uses only POSIX `kill`/`wait`/`sleep` — if it cannot run, the environment is broken and the test fails loudly, never skips.

**Note on the design's literal acceptance command.** The design's observable proof was `env PATH=/usr/bin:/bin bash tests/test-codex-lockout-agreement.sh`. On this host that command additionally fails at `node` (`codex-task.sh:1183` calls `node`, which lives in `/opt/homebrew/bin`, outside `/usr/bin:/bin`) — an unrelated host dependency, not a code one (`codex-task.sh` is *already* its own portable-timeout, see `:1175`: it has the same sleep+kill fallback). `timeout` and `node` both live in `/opt/homebrew/bin`, so no PATH filter can exclude one without the other here. F5's actual code is the `_run_bounded` helper; the F5 test proves its two branches directly (fast path delegates; fallback runs+captures+rc 0; fallback kills a hung command → rc 124).

## Tests

Every assertion below **fails on `30ad24e`, passes after.** Final counts (baselines in parens):

| suite | result | baseline |
|---|---|---|
| `test-arm-cooldown.sh` | **18 passed** (10) | +F1, F1b, F2(+state), F2b, F3(+newer-stamp), F3b |
| `test-codex-lockout-agreement.sh` | **10 passed** (6) | +F5 fast(+bound) / fallback-run / fallback-rc124 |
| `test-dispatch-ledger-task-id.sh` | **14 passed** (11) | C1 split + F4 + F4b |
| `test-supervisor-reason-honest.sh` | **9 passed** (9) | regression fence, exact |
| `test-status-surface.sh` | **90 passed** (90) | regression fence, exact |
| `test-status-surface-cwd.sh` | **7 passed** (7) | regression fence, exact |

All six green; the three fences sit at exactly their baseline counts. `/bin/bash -n` (macOS system bash 3.2) passes on every edited file.

**Output grammar preserved:** `cooling <reprobe_iso> <reason>` / bare `clear` — `test-codex-lockout-agreement.sh` still asserts the exact `locked 2001-09-09T02:01:40Z` / `clear` front-end strings and passes.

## Pre-existing failures (NOT regressions)

Four related suites fail on this machine. Verified **identically on pristine `HEAD`** (my changes backed out via `git show HEAD:` → run → restored; zero git mutation): `test-dispatch-ledger-partial-close`, `test-leadv2-dispatch-outcome-ledger` (both `rc=3` in a process-death-wait setup — dispatch-LOCK timing, code I did not touch), `test-lane-liveness-authoritative` C2 (live-PID/artifact, no cooldown/ledger surface), `test-codex-quota-gate` q5 watcher idempotency. None assert on a field or clamp this task changes.

## Out of scope (preserved)

No change to which arms exist / routing / arm exclusion. No bound weakened. Parsed `until` stays advisory, permanently. No `_dispatch_lane_name_from_mission` H1 rework. No `.state` GC beyond `tail -n 200`. `leadv2-portable-lock.sh` untouched. No destructive git.

## Cross-provider review gate

Codex adversarial review of the production diff (`/tmp/n1b-prod.diff`). Five
points raised; disposition below — two fixed, three honest scope notes.

**FIXED — F5 fast path did not enforce the bound.** Codex caught a real
regression: `_run_bounded`'s `timeout`-present branch checked `command -v timeout`
but then ran `"$@"` directly — so on a host WITH `timeout` (this machine) a hung
command ran to completion under rc 0 instead of rc 124. Reproduced (`rc=0
elapsed=2s`). Fixed: the fast path now runs `timeout "$secs" "$@"`. Added a test
that asserts the fast path itself enforces the deadline (rc 124 in <3s on
`_run_bounded 1 bash -c 'sleep 3'`); agreement suite now 10.

**FIXED — portable-lock env-sourcing injection vector.** The library's lock
bootstrap fell back to sourcing an env-selected path (`LEADV2_PORTABLE_LOCK_SH`),
letting an env var execute arbitrary code in the caller shell. Removed: the
library now sources ONLY its own sibling path
(`${BASH_SOURCE[0]%/*}/../leadv2-portable-lock.sh`), which is correct because the
lib is always sourced from `scripts/lib/`. No env-selected source remains.

**SCOPE NOTE (not fixed — by design) — F3 `tail -n 200` cap.** Codex's repro
writes 1 live refusal + 200 stale rows so the live one falls outside the scan
window → `clear`. This is the bound the design §4 deliberately chose ("200
refusals of one arm inside one bounded hour is orders of magnitude past anything
real … the cap keeps the read O(1) as the file ages"), and `.state` GC beyond it
is explicitly out of scope. The 201-refusal repro is artificial; the design owner
accepted the trade-off. Likewise a stale writer appending after an
`arm_cooldown_clear` can restore cooling — the design's fail-open ordering
philosophy accepts this (clear is an operator action; the max-scan is the
correctness mechanism, clear truncates).

**SCOPE NOTE (not fixed — by design) — F4 terminal writer still puts the display
label in `task_id`.** Codex correctly notes that a no-`--task-id` product lane
whose terminal row carries `"task_id":"OPS-42"` re-introduces the collision once
the terminal row is written (the reader's `task_id or founder_task_id` merge
picks it). This is the terminal writer (`leadv2-dispatch-ledger.sh`), which the
design §5 explicitly leaves unchanged ("Terminal rows … already carry
`founder_task_id` … need no change") and which is NOT in this task's
`LANE_WRITES`. The pending-row path — the path F4 targets and its test exercises
— is fixed. Widening to the terminal writer is a deliberate scope boundary, not
an oversight; it would be a separate task (and would touch the C4 back-compat
contract).

**SCOPE NOTE (not fixed — pre-existing) — JSON control-char injection.** The
pending-writer sanitizer strips only `\` and `"` (then clamps to 64), so a
`--task-id $'OPS-42\nINJECT'` yields multiline invalid JSON. The design §5
instructed "apply the same sanitize already applied to `task_id`" — which is
exactly this incomplete sanitizer (pre-existing in `task_id`, now also in
`lane_label`). Hardening it (strip all chars < 0x20, as the terminal writer
already does at `leadv2-dispatch-ledger.sh:93`) is a strict improvement but is
JSON-hardening scope, not the field-collision fix; left for a dedicated task
rather than expanded into here.

Final suite state after the two fixes: **18 / 10 / 14 / 9 / 90 / 7**, all green.

DELIVERABLE_COMPLETE
