# critic — round-1 EXHAUSTIVE — V3-GLM-LADDER-01 / commit 389820a

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/eb2d7143` (branch `worktree-eb2d7143`)
Diff reviewed: `docs/handoff/dispatch-eb2d7143-review/review.diff` (764 insertions, 0 deletions, 4 files)

## VERDICT: **FAIL**

3 Critical + 3 High. All three levers are green in the author's own suite and **all three
under-report or no-op in the exact production shape the incident described.** The suite is
honest red-first, but it tests the first dispatch of a fresh cache dir — and it explicitly
works around (rather than covers) the multi-dispatch case where the levers die. Lever 1's
recovery half (`--retry-all`) has zero tests and cannot function at all on a real park row.

---

## What the mission constraints demanded — verified, PASS

| Constraint | Result | Evidence |
|---|---|---|
| Routing ORDER unchanged | **PASS** | `git show --numstat 389820a` → `356 0`, `80 0`, `1 0`, `327 0`. **Zero deletions, zero modified lines** in either production script. Every hunk is a pure insertion at a call site; no `candidate_arms` ordering, no ladder, no ceiling is touched. |
| Ceilings unchanged | **PASS** | same — no line inside the quota-gate / reorder block was altered. |
| No new env vars | **PASS** | no new `LEADV2_*` / `PE_*` read introduced. `_LEADV2_EXC_DAY` is a `local` in `cmd_resolve:3649`, not an env var. |
| `leadv2-dispatch-product-close.sh` untouched | **PASS** | `git show --name-only 389820a` → 4 files, none matching `product-close`. |
| `supervise*` untouched | **PASS** | same. |
| `run-core-offline.sh` delta = exactly 1 row | **PASS** | `git show 389820a -- .../run-core-offline.sh \| grep -cE '^[+-][^+-]'` → `1` |
| `bash -n` on the 3 scripts | **PASS** | all three `OK` (raw below) |

### +356 lines in dispatch-code.sh — enumeration (mission item 4)

| Lines | What | Verdict |
|---|---|---|
| 699–706 | design comment header (fd-8/fd-9 rationale) | fine |
| 707–709 | 3 path helpers | fine |
| **710–733** | **`_glm_deferred_is_retried` (24 lines) — ZERO callers** | **dead code, M1** |
| 736–816 | `_glm_park_deferred` | see C2/M3 |
| 818–941 | `cmd_glm_deferred` (of which ~66 lines are `retry-all`) | see C2/C3/H3 |
| 944–998 | `_codex_credits_watch` | works (only lever that does) |
| 1000–1020 | `_arm_exception_bump` | see C1/M2 |
| +4 / +3 / +4 / +12 / +7 / +1 / +1 | usage, `_LEADV2_EXC_DAY`, watch site 1, sonnet bump, park call, watch site 2, case arm | fine |

356 accounted for. **Nothing in the diff changes routing order or ceilings** — that constraint
is met and I am not re-litigating `test-routing-enforcement-p1.sh`. The size itself is not the
violation; 24 lines of dead code and ~66 lines of untested, non-functional `retry-all` are.

---

# CRITICAL

## C1 — Lever 3 (loud sonnet counter) reports `1` on a day where 100% of workers ran sonnet
`plugins/leadv2/scripts/leadv2-dispatch-code.sh:4402-4412` (the `attempted[]` gate)
Category: correctness / lying-green — the exact disease the task exists to cure

The bump only fires when `attempted[]` contains a `glm_refused_*` entry. But after the **first**
glm refusal, `record-quota-lockout` benches glm for 30 min, and every subsequent dispatch
**removes glm from `candidate_arms` before it is ever attempted** — so `attempted[]` is empty of
glm, the counter never bumps, and no park row is written either.

Raw probe (two real dispatches, ONE shared `LEADV2_DISPATCH_CACHE_DIR` = production shape):

```
run1: candidate_chain task=6e24fe04 arms=glm,sonnet
run1: arm_refused by=router model=glm task=6e24fe04 reason=glm_refused_quota_gate
run1: route_resolved by=router model=sonnet task=6e24fe04
run2: candidate_chain task=8be1cd02 arms=sonnet          <-- glm never attempted
run2: route_resolved by=router model=sonnet task=8be1cd02

=== counter file (.arm-exceptions-20260820) — expect count=2 ===
count=1
last_reason=glm quota
=== park rows — expect 2 ===
{"sig8":"6e24fe04",...}          <-- one row, for run1 only
```

And with 5 dispatches through the same cache the bench path is explicit:

```
[leadv2-dispatch-code] quota_precheck_skip model=glm provider=glm task=b56c1ff5 reason=provider_quota_locked class=provider_refusal
[leadv2-dispatch-code] candidate_chain task=b56c1ff5 arms=sonnet
=== counter file after run5 ===  <MISSING>
=== park rows ===  1
```

The author knew: `tests/test-glm-deferred-ladder.sh:739-745` gives each `run_c` its **own** cache
dir with the comment *"the quota-lockout memory written by run N (primary_arm_benched) would
otherwise exclude glm from candidate_arms on run N+1, skipping the refusal branch entirely"*.
That is a workaround for the production defect, written into the harness instead of into the fix.

The founder pulse would have rendered `sonnet-фолбэков сегодня: 1` on 2026-08-19. That is the
same silence the incident is about, with one extra digit.

**Required fix:** bump (and park) on BOTH paths — the `glm_refused_*` entry in `attempted[]`
**and** the `quota_precheck_skip … reason=provider_quota_locked` / bench-exclusion path that
drops glm from `candidate_arms` before attempt. Add a suite leg that runs ≥2 dispatches through
ONE cache dir and asserts `count=2` / 2 park rows. Delete the per-run cache workaround from
`run_c` once the fix lands, or it will keep hiding this.

## C2 — `glm-deferred --retry-all` can never retry a real parked row (two independent blockers)
`leadv2-dispatch-code.sh:742` (mission_path), `:920-923` (dispatch), `:906-910` (terminal guard)
Category: correctness — the recovery half of Lever 1 is inert

**Blocker (a): `mission_path` is always empty on a real dispatch.**
`_glm_park_deferred:742` reads `${PROJECT_ROOT}/docs/handoff/dispatch-${sig8}/lane-mission.md`
at *refusal* time. That file is written at `:4394-4398`, **only when `product_class == "product"`
and only later, at the successful sonnet spawn** — strictly after the glm refusal. So for a
non-product dispatch it never exists, and for a product dispatch it does not exist yet.
`retry-all` then hits `if [[ -n "${_mpath}" && -f "${_mpath}" ]]` = false and dispatches nothing.

Raw — park row from a real end-to-end dispatch:
```
{"sig8":"127e5c8e","mission_path":"","founder_task_id":"","refused_at":"2026-08-20T01:04:02Z","reason":"glm_refused_quota_gate","quota_pct":null,"retried_at":null}
```
`mission_path` empty. Same in every park row produced by every probe I ran.

**Blocker (b): the sonnet fallback lands a terminal row, so the guard skips the sig8 forever.**
`dispatch_terminal_exists` (leadv2-dispatch-ledger.sh) returns 0 for `landed|dead`. The park row
is written *before* the sonnet fallback, and that fallback lands. Raw:

```
=========== CASE 2: park row whose sonnet fallback LANDED ===========
  dispatched sig8=127e5c8e
    terminal_exists=YES
  --- retry-all (quota window reopened, router-v2 stub returns eligible=glm) ---
    already_terminal 127e5c8e
  --- list AFTER retry-all ---
    127e5c8e 2026-08-20T01:04:02Z quota=None -
```

The row is skipped **and never marked retried**, so it stays in `--list` and in the founder-status
`отложено на GLM: N` line permanently (until the 7-day/500-row truncation). Every quota-refused
task on the ladder becomes a permanent phantom in the founder's pulse.

**Required fix:** (1) persist the mission text at park time — write it into the park row or into
a park-owned file, do not point at an artifact that does not exist yet; (2) decide explicitly
what a "retry" means when the sonnet fallback already completed the work — either don't park
tasks whose fallback landed (reap them at terminal-write), or retry under a fresh sig8. Whichever
you pick, `already_terminal` must **remove the row from the queue**, not leave it counting forever.

## C3 — `--retry-all` (~66 lines, the whole recovery path) has ZERO test coverage
`plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh` — legs are (a) park, (b) `--list`,
(c) watchdog, (d) renderer. `grep -c 'retry-all' tests/test-glm-deferred-ladder.sh` = 0.
Category: test coverage — new logic branch with no test

The mission names `--retry-all` in Outcome §1 and in Acceptance. A single leg exercising it
against a realistic park row would have surfaced C2 in the author's own run. Per the standing
rule (new logic branch with no coverage = Critical), and per the repo's own falsification rule
(`.claude/ref/dev-prebuild-checklist.md` §Falsification), this blocks.

**Required fix:** add legs — (i) parked row + reopened quota + real mission → re-dispatch actually
happens (assert the child dispatch's observable effect, not the parent's `printf`); (ii) parked
row whose sig8 has a terminal `landed` row → row is reaped, `--list` no longer shows it;
(iii) parked row with unusable mission_path → does NOT print `retried`.

---

# HIGH

## H1 — the `.gitignore` rules the code depends on are UNCOMMITTED; the `.lock` files are ignored by nothing
`leadv2-dispatch-code.sh:700` claims *"Runtime state lives under docs/leadv2/ (plugin-owned, gitignored)"*.
Category: claim-without-evidence / repo hygiene

```
$ git show HEAD:.gitignore | tail -4
.claude/worktrees/
docs/leadv2/.pulse-*
docs/leadv2/.broad-status-prev.json          <-- no glm-deferred, no arm-exceptions, no stamp

$ git diff -- .gitignore
+docs/leadv2/glm-deferred.jsonl
+docs/leadv2/.arm-exceptions-*
+docs/leadv2/.codex-credits-empty.stamp       <-- UNCOMMITTED working-tree change

$ git log -S'glm-deferred' -- .gitignore      <-- (no output: never committed)

$ git check-ignore -v docs/leadv2/glm-deferred.jsonl.lock
NOT IGNORED (will dirty the repo)
```

Commit 389820a touches 4 files; `.gitignore` is not one of them. As committed, three runtime
files become untracked repo dirt on every checkout, and the three new `.lock` files
(`glm-deferred.jsonl.lock`, `.codex-credits-empty.stamp.lock`, `.arm-exceptions-*.lock`) are not
covered by any rule at all — proven present on disk after a probe run:

```
-rw-r--r--  .codex-credits-empty.stamp.lock
-rw-r--r--  glm-deferred.jsonl.lock
```

**Required fix:** fold the `.gitignore` hunk into this commit and add the `.lock` paths
(`docs/leadv2/*.lock` or the three explicitly). The in-code claim must be true at HEAD.

## H2 — 4 new bare `flock 8` with no `-w` timeout, bypassing the repo's own portable-lock primitive
`leadv2-dispatch-code.sh:773, 934, 971, 1007`
Category: correctness / pattern divergence — `get_why` equivalent: the script's own header

The script documents at `:308-309` — *"SWIFTBAR-R4 RC-1: flock(1) doesn't exist on the widget's
acceptance PATH (no util-linux on macOS) — `lv2_lock_wait` delegates to real flock when present"* —
and `lv2_lock_wait "$lockf" 10` is used 6× across `leadv2-dispatch-code.sh` (2060, 2122, 2129,
2242) and `leadv2-dispatch-ledger.sh` (236, 323), sourced from `leadv2-portable-lock.sh`. The new
code uses none of it.

Raw, with brew's flock off PATH (i.e. stock macOS, which is the founder's own machine):
```
$ PATH=/usr/bin:/bin bash -c 'p=$(mktemp); ( flock 8; echo "wrote-anyway" ) 8>"$p.lock" 2>&1; echo "rc=$?"'
bash: flock: command not found
wrote-anyway
rc=0
```
The critical section runs **unlocked and reports success**. Under the standing 3–4-lanes-in-flight
posture, concurrent `_arm_exception_bump` read-modify-writes lose increments (compounding C1's
under-count) and concurrent `_glm_park_deferred` rewrites interleave against `os.replace`.

Additionally: `grep 'flock -w'` across `plugins/leadv2/scripts` = 0 matches for the new code, and
`.claude/ref/dev-prebuild-checklist.md` states *"Every `flock` includes `-w <timeout>` — no-timeout
flock can hang the whole cycle."* A stale lock holder now blocks `cmd_resolve` indefinitely, which
directly contradicts the diff's own comment at `:702` (*"none may ever abort cmd_resolve"*).

**Required fix:** replace all 4 with `lv2_lock_wait "${path}.lock" 10 || return 0` inside the
subshell, per the existing primitive.

## H3 — `--retry-all` prints `retried` and durably marks the row retried when nothing was dispatched
`leadv2-dispatch-code.sh:920-937`
Category: correctness / silent data loss

```bash
if [[ -n "${_mpath}" && -f "${_mpath}" ]]; then
  bash "${BASH_SOURCE[0]}" "@${_mpath}" >/dev/null 2>&1 || true   # output discarded, rc ignored
fi
... appends a row with retried_at set ...
printf 'retried %s\n' "${_sig8}"
```

The `retried_at` write and the `retried` print are **outside** the dispatch guard and **do not
check the child's exit code**. So: empty/missing mission → nothing runs, row is retired anyway;
failed re-dispatch → nothing runs, row is retired anyway. Raw:

```
=========== CASE 3: park row with EMPTY mission_path ===========
    retried bbbbbbbb
    (nothing was dispatched)
    no deferred glm tasks          <-- the task is gone from the queue, zero work done
```

Combined with C2(a) (`mission_path` is *always* empty), the first `--retry-all` a human runs will
silently wipe the entire park queue while dispatching nothing, and report success for each row.

**Required fix:** only write `retried_at` and print `retried` when a dispatch was actually
launched and returned 0; otherwise print `skipped_no_mission` / `retry_failed` and leave the row
pending. Do not discard the child's stderr — capture it into the printed line.

---

# MEDIUM

## M1 — `_glm_deferred_is_retried` is dead code (24 lines, zero callers)
`leadv2-dispatch-code.sh:710-733`. `grep -rn '_glm_deferred_is_retried' plugins/leadv2/scripts/`
→ one hit, the definition. Its logic is re-implemented inline three more times (in
`cmd_glm_deferred` list/json, in `retry-all`, and in `leadv2-broad-status.sh:68-71`). In a diff
the mission constrained to *"small, focused"*, this is 24 lines of speculative helper with a
single-caller count of zero. **Fix:** delete it, or use it and delete the three inline copies.

## M2 — the founder-visible reason is hardcoded `"glm quota"` for every `glm_refused_*` variant
`leadv2-dispatch-code.sh:4407` → `_arm_exception_bump "glm quota"`.
`LAST_ARM_OUTCOME="glm_refused_${refusal}"` (`:2876`) interpolates whatever the launcher emitted —
`lock_busy` and `postspawn_quota` (`:3443`) among them. A lock-busy fallback is rendered to the
founder as `sonnet-фолбэков сегодня: N (glm quota)` — a wrong diagnosis on the one surface built
to diagnose. The file format already carries `last_reason=`; the caller just never passes the real
one. **Fix:** `_arm_exception_bump "${_attempted_entry}"`.

## M3 — the park gate is `glm_refused_*`, not quota; the mission says "refuses glm **on quota**"
`leadv2-dispatch-code.sh:4444`. Non-quota transient refusals (`glm_refused_lock_busy`) are parked
into a queue the founder sees as `отложено на GLM: N (dispatch glm-deferred --list)` and whose
retry path checks *the quota window*. **Fix:** gate on `glm_refused_quota_gate` (and
`*_refused_postspawn_quota`), or rename the surface to "glm refusals" and stop implying quota.

## M4 — `glm_deferred_count` counts ROWS, not distinct sig8s
`leadv2-broad-status.sh:71` — `len([r for r in _rows if r.get("sig8") not in _retried])`; same in
`cmd_glm_deferred` list/json. A task refused across two days (bench expires after 30 min) is
parked twice and counted twice. With C2 preventing rows from ever leaving, the founder-visible
number only ever grows. **Fix:** dedup by sig8, newest row wins.

## M5 — new shellcheck SC2034 warnings introduced by this diff
```
In leadv2-dispatch-code.sh line 874:
      local -a pending_sig8s pending_missions
               ^-----------^ SC2034 (warning): pending_sig8s appears unused.
                             ^--------------^ SC2034 (warning): pending_missions appears unused.
```
Also `local _line` (`:905`) is declared and never used. The other shellcheck warnings in the file
are pre-existing (SC1090/SC2046/SC2097/SC2098) and not attributable to this commit.
`leadv2-broad-status.sh` and the new test are shellcheck-clean at `-S warning`. **Fix:** delete
the three unused declarations.

---

# LOW

- **L1** — env-var precedence asymmetry between writer and reader. Writer
  `leadv2-dispatch-code.sh:264` = `CLAUDE_PROJECT_ROOT` → `CLAUDE_PROJECT_DIR` → `PROJECT_ROOT` →
  git-toplevel. Reader `leadv2-broad-status.sh:25` = `LEADV2_PROJECT_ROOT` → `CLAUDE_PROJECT_DIR`
  → git-toplevel. They agree in a normal lead session (both land on `CLAUDE_PROJECT_DIR`) but
  diverge if the dispatcher is invoked with cwd inside a lane worktree without
  `CLAUDE_PROJECT_DIR` — the park file lands in the worktree and the renderer never sees it. The
  suite cannot detect this: legs (a)/(b)/(c) set `CLAUDE_PROJECT_ROOT`, leg (d) sets
  `LEADV2_PROJECT_ROOT`, both to the same dir.
- **L2** — the `_truncated` sentinel row survives the next rewrite as an ordinary row (it json-
  parses, has no `refused_at`, so the 7-day filter keeps it) and is re-appended, accumulating one
  per truncation and eating the 500-row budget. `leadv2-dispatch-code.sh:790-796`.
- **L3** — the (d)-negative leg is a weak assertion: it passes against the **pre-patch** scripts
  too (see red-first output below, `PASS: (d) a day with no fallback renders no sonnet-fallback
  line`), because "absent" is also true when the feature does not exist. Fine paired with the
  positive leg; not evidence on its own.
- **L4** — `--retry-all` has no `--dry-run` and discards the child dispatch's output entirely
  (`>/dev/null 2>&1`), so a human running it has no record of what was actually launched.

---

# Raw probe output

## bash -n (all three changed scripts)
```
OK leadv2-dispatch-code.sh
OK leadv2-broad-status.sh
OK tests/test-glm-deferred-ladder.sh
```

## shellcheck -S warning -x (new findings only; full output in M5)
```
leadv2-dispatch-code.sh:874  SC2034  pending_sig8s appears unused
leadv2-dispatch-code.sh:874  SC2034  pending_missions appears unused
leadv2-broad-status.sh       (clean)
tests/test-glm-deferred-ladder.sh (clean)
```

## The suite, GREEN on the lane (reproduces the author's claim)
```
PASS: (a) park row written before sonnet fallback worker spawn (ordering holds)
PASS: (a) poison fence held
PASS: (b) glm-deferred --list prints the parked sig8
PASS: (b) glm-deferred --list prints 'no deferred glm tasks' when empty
PASS: (c) two credit-empty computations within 24h emit exactly ONE journal line
PASS: (c) a third computation after the stamp ages past 24h emits a second journal line
PASS: (d) rendered founder-status.md contains sonnet-фолбэков сегодня: 1 (glm quota)
PASS: (d) a day with no fallback renders no sonnet-fallback line
PASS: poison fence held across the suite
  glm-deferred-ladder suite: FAIL=0
```

## RED-FIRST verified — new suite vs the PRE-PATCH production scripts (389820a^)
Method: copied `plugins/leadv2/scripts` to a scratch dir, overwrote
`leadv2-dispatch-code.sh` + `leadv2-broad-status.sh` with `git show 389820a^:…`, ran the new suite.
```
FAIL: (a) park row missing for sig8=38131d44
PASS: (a) poison fence held
FAIL: (b) glm-deferred
FAIL: (b) empty-state message wrong
FAIL: (c) expected exactly 1 codex_credits_empty line after 2 runs, got 0
FAIL: (c) setup
FAIL: (c) expected 2 codex_credits_empty lines after the back-dated 3rd run, got 0
FAIL: (d) expected sonnet-fallback line missing from rendered artifact
PASS: (d) a day with no fallback renders no sonnet-fallback line
PASS: poison fence held across the suite
SUITE_EXIT=1
```
**The suite is genuinely red-first and non-tautological** on all four legs it covers, and leg (d)
is a real rendered-artifact probe (it runs `leadv2-broad-status.sh` and greps the produced
`founder-status.md`, not the source). That part of the mission is honestly delivered. The problem
is what the suite does **not** cover: `--retry-all` (C3) and the second-dispatch-in-one-cache
shape (C1), which the harness explicitly engineers around.

## C1 probe — two dispatches, ONE cache dir
```
run1: candidate_chain task=6e24fe04 arms=glm,sonnet
run1: arm_refused by=router model=glm task=6e24fe04 reason=glm_refused_quota_gate
run1: route_resolved by=router router=v1 model=sonnet task=6e24fe04
run2: candidate_chain task=8be1cd02 arms=sonnet
run2: route_resolved by=router router=v1 model=sonnet task=8be1cd02

.arm-exceptions-20260820:  count=1 / last_reason=glm quota     (expected 2)
glm-deferred.jsonl:        1 row                                (expected 2)
```
5-dispatch variant:
```
quota_precheck_skip model=glm provider=glm reason=provider_quota_locked class=provider_refusal
candidate_chain arms=sonnet
counter file: <MISSING>       park rows: 1
```

## C2/H3 probe — retry-all
```
CASE 1 (no terminal row, real mission file):        retried aaaaaaaa   -> list: no deferred glm tasks
CASE 2 (MAINLINE: sonnet fallback landed):
  park row: {"sig8":"127e5c8e","mission_path":"", ... }     <-- mission_path ALWAYS empty
  terminal_exists=YES
  retry-all:  already_terminal 127e5c8e
  list after: 127e5c8e 2026-08-20T01:04:02Z quota=None -    <-- never leaves the queue
CASE 3 (empty mission_path):
  retry-all:  retried bbbbbbbb                              <-- nothing dispatched
  list after: no deferred glm tasks                         <-- row silently destroyed
```

## Off-limits / scope
```
$ git show --name-only --format="" 389820a
plugins/leadv2/scripts/leadv2-broad-status.sh
plugins/leadv2/scripts/leadv2-dispatch-code.sh
plugins/leadv2/scripts/tests/run-core-offline.sh
plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh
product-close / supervise touched? NONE (ok)
run-core-offline delta: 1
$ git show --numstat 389820a
80  0   leadv2-broad-status.sh
356 0   leadv2-dispatch-code.sh
1   0   run-core-offline.sh
327 0   test-glm-deferred-ladder.sh      <-- 0 deletions: routing order/ceilings provably unchanged
```

---

# Pre-finalize contradiction scan

1. **Env-var names vs settings** — CONTRADICTION FOUND (L1): writer honours `CLAUDE_PROJECT_ROOT`,
   reader honours `LEADV2_PROJECT_ROOT`; neither honours the other's. Masked by the suite setting
   each script's own preferred variable.
2. **Flag semantics vs other usages** — CONTRADICTION FOUND (H2): 4 bare `flock` calls against a
   repo that ships `lv2_lock_wait` specifically because `flock(1)` is absent on macOS, and against
   its own checklist rule mandating `-w`. Also the diff comment at `:702` ("none may ever abort
   cmd_resolve") is contradicted by an untimed `flock` that can block indefinitely.
3. **Path existence** — CONTRADICTION FOUND (C2a): `docs/handoff/dispatch-<sig8>/lane-mission.md`
   is read at `:742` but only written at `:4394-4398`, product-only and strictly later. The path
   is empty in every park row produced by a real dispatch.
4. **Claim vs committed state** — CONTRADICTION FOUND (H1): the code comment says "gitignored";
   `git show HEAD:.gitignore` says otherwise, and the rules exist only as an uncommitted
   working-tree change.
5. **Commit-message claim** — the message asserts "own suite green FAIL=0" (true, verified) and
   "routing-enforcement red proven env-equal on main via A/B" (out of scope per the mission, not
   re-litigated). No false claim found in the commit message itself.
6. **Everything else** (subcommand help text vs `case` arms; `_LEADV2_EXC_DAY` dynamic scoping
   from `cmd_resolve` into `_arm_exception_bump`; python imports `datetime, json, os` present at
   `leadv2-broad-status.sh:145` so the new block cannot `NameError`; `root` = `$PROJECT_ROOT`
   argv[3]; `@file` mission syntax supported at `:3729`; `attempted[]` expansion safe under
   `set -u` on bash 5.3) — **checked, no contradiction.**

---

## Blocking summary

| ID | Severity | File:line | One line |
|---|---|---|---|
| C1 | Critical | dispatch-code.sh:4402-4412 | counter+park die after the first refusal (glm gets benched out of the chain) — the incident shape reports `1` |
| C2 | Critical | dispatch-code.sh:742, 906-923 | `--retry-all` can never retry: mission_path always empty + terminal row makes every sig8 `already_terminal` forever |
| C3 | Critical | tests/test-glm-deferred-ladder.sh | zero coverage for `--retry-all` (~66 lines), named in the mission's own Acceptance |
| H1 | High | .gitignore (uncommitted) + dispatch-code.sh:700 | "gitignored" is false at HEAD; 3 `.lock` files ignored by nothing |
| H2 | High | dispatch-code.sh:773,934,971,1007 | 4 bare untimed `flock`, bypassing `lv2_lock_wait`; unlocked+silent on stock macOS |
| H3 | High | dispatch-code.sh:920-937 | prints `retried` and retires the row with nothing dispatched — silent queue wipe |
| M1 | Medium | dispatch-code.sh:710-733 | `_glm_deferred_is_retried` dead, 24 lines, zero callers |
| M2 | Medium | dispatch-code.sh:4407 | reason hardcoded `"glm quota"` for every `glm_refused_*` |
| M3 | Medium | dispatch-code.sh:4444 | park gate is any refusal, not quota — contradicts the spec |
| M4 | Medium | broad-status.sh:71 | counts rows not distinct sig8s; number only grows |
| M5 | Medium | dispatch-code.sh:874,905 | new SC2034 — 3 unused local declarations |
| L1 | Low | dispatch-code.sh:264 / broad-status.sh:25 | writer/reader PROJECT_ROOT precedence asymmetry |
| L2 | Low | dispatch-code.sh:790-796 | `_truncated` sentinel accumulates across rewrites |
| L3 | Low | test:836-852 | (d)-negative leg passes pre-patch too — weak on its own |
| L4 | Low | dispatch-code.sh:921 | `--retry-all` discards child output, no `--dry-run` |

**BLOCK.** C1 and C2 mean two of the three levers do not do the thing the incident required, in
the shape the incident had. C3 is why nobody noticed.

DELIVERABLE_COMPLETE
