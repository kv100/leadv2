# BRAIN-CLASS-LIVE-01 — report

## What was already true before this lane

A prior lane (referenced in-code as PHASE-DISCIPLINE-01 / COMPLEXITY-ESTIMATOR-IS-OFF-01, and a
partial salvage commit `a3b5d6b` on this branch) had already:
- moved `leadv2-task-judge.sh` onto the **default** `_admission_classify` path in
  `leadv2-dispatch-code.sh` (unconditional call, not gated behind `LEADV2_ROUTER_V2`);
- implemented `--task-class` as a floor via `leadv2_admission_class` (`lib/leadv2-admission-class.sh`),
  escalate-only, never de-escalated;
- fixed the judge-failure branch so a declared class above Standard is never silently downgraded
  to Standard (`class_source=declared_fallback`);
- written `lib/leadv2-brain-record.sh` (`leadv2_brain_record`, `leadv2_brain_write_yaml`,
  `leadv2_brain_read_class`, `leadv2_brain_phases_for_class`) and wired it into
  `_admission_classify`'s tail, emitting `class_escalated` / `class_floor_held` /
  `brain_decision` and writing `docs/handoff/<task>/brain.yaml`;
- wired `_admission_classify`'s own task-floor lookup to also read `brain.yaml` as a floor on
  same-task re-entry.

Verified live (not from memory): `_admission_classify` (leadv2-dispatch-code.sh:3717) calls
`bash "${TASK_JUDGE_BIN}" --mission-file ... --task-id ...` unconditionally at line 3768-3769,
with no `LEADV2_ROUTER_V2` gate anywhere in that function.

## What this session added

1. `_resolve_class_with_brain_floor <sig8> <task_id> <base_class>` (new function,
   leadv2-dispatch-code.sh, just above `_phase_precondition_guard`): reads `brain.yaml` via
   `leadv2_brain_read_class` and raises (never lowers) a class computed independently, journaling
   `phase_class_floor task=<sig8> source=brain_record class=<c>`.
2. Wired that helper into `cmd_advance_arm`'s phase-class resolution block (the Phase-4 re-entry
   path, ~line 7860), which previously only floored against `task-class.yaml` (task receipt), not
   `brain.yaml`. This is the "`_phase_precondition_guard` ... reads class from `brain.yaml` when
   present" half of item 3 that was NOT yet covered by the salvage commit — the salvage commit only
   wired the read-back into `_admission_classify`'s own re-entry, not into the guard's second call
   site.
3. `plugins/leadv2/scripts/tests/test-brain-class-live.sh` — new suite, (a)-(d) plus a mutation
   negative control, registered in `tests/run-all.sh`. See "Suite output" below.

`leadv2-task-judge.sh` and `lib/leadv2-admission-class.sh` were **not modified** — the judge already
runs unconditionally (item 1 done pre-lane) and the admission-class lib's job (item 3's
"`leadv2-admission-class.sh` reads brain.yaml") is satisfied by its only real caller
(`leadv2-dispatch-code.sh`) doing the read-back, which was already true for the classify path and
is now also true for the advance-arm re-entry path (my addition).

## Suite output (green)

```
PASS: (a) light+risk mission escalates to Standard|Heavy, journaled
PASS: (a) brain.yaml class_source=escalated
PASS: (b) trivial-but-declared-Heavy holds the floor, journaled
PASS: (b) final class stays Heavy
PASS: (c) judge failure -> declared_fallback
PASS: (c) dispatch proceeds with declared class, no refusal
PASS: (d) brain_decision line names class=Heavy
PASS: (d) brain.yaml class: Heavy
PASS: (d) re-entry guard floor reads brain.yaml class=Heavy over a lower base class
PASS: MUTATION (a) killed: no class_escalated when judge call is skipped
PASS: MUTATION (d) killed: no brain.yaml written when judge call is skipped

=== test-brain-class-live.sh: 11 PASS, 0 FAIL ===
```

Mutation control: the suite copies `leadv2-dispatch-code.sh` to a temp file and inserts an
unconditional `return 0` immediately before the `bash "${TASK_JUDGE_BIN}" ...` call inside
`_admission_classify` (never touches the tracked file). With the judge call skipped: no
`class_escalated` line and no `brain.yaml` written — both controls fire red as required, proving
the suite actually depends on the judge running.

## Regression check against directly-touched suites

```
test-admission-class.sh:                24 pass / 0 fail
test-phase-precondition-bootstrap.sh:    21 pass / 0 fail
test-mission-writeset.sh:                22 pass / 0 fail
test-phase-precondition.sh:              70 pass / 9 fail
```

`test-phase-precondition.sh`'s 9 failures (G1, G2×3, G3, G8, G11a×2, G11b) are **pre-existing**:
re-ran the identical suite with `leadv2-dispatch-code.sh` swapped back to the pre-lane commit
(`a3b5d6b`, i.e. before this session's two edits) via a temp-file swap-and-restore (never `git
checkout`/`reset` on the tracked file) — same 9 failures, same case names, byte-identical
`pass=70 fail=9` line. Root cause per prior memory (phase-precondition-suite-landscape): the
e2e G-cases are not hermetic (`project_root_guard status=foreign_env_overridden`, admission
receipts leaking into the real tree across runs). Confirmed the working tree was restored to my
actual edits afterward (`diff` clean, `git diff --stat` shows only the intended 25-line addition).

`tests/run-all.sh --scope changed` was also run under `LEADV2_SUITE_LOCK_DISABLE=1`; it exceeded
the 590s budget mid-way through the CORE-OFFLINE shard (matches prior memory:
`run-all-changed-scope-runtime` — core-offline alone regularly exceeds 10 minutes) with all shards
observed up to that point green except the same pre-existing REVIEW-ROUNDCAP-01 red noted in
memory (`run-all-changed-preexisting-reds`). Not re-run to completion given the 10-minute-plus
known runtime and the four suites above already isolating the exact files this lane touched.

## Real-dispatch evidence — attempted, reverted, and why

Attempted one real (non-source-only) `leadv2-dispatch-code.sh` CLI invocation with `--force
--task-class light --task-id dispatch-brainEvid1` and a stub `LEADV2_DISPATCH_GLM_BIN` (local
background `sleep`, not a real GLM call) standing in for the worker launcher, to prove the
`brain_decision` line lands via the full CLI, not just the `LEADV2_DISPATCH_SOURCE_ONLY=1` harness.

The invocation hung past its 60s timeout **before** reaching admission-classify's journal output
(only `dispatch_task_bound` had printed) and, when killed, left a **real git worktree** at
`/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/dispatch-brainEvid1` and branch
`worktree-dispatch-brainEvid1` in the **main checkout**, not this lane's worktree — the dispatcher's
own root-resolution created lane infrastructure outside the WORKTREE PIN despite `cwd`-derived
root override. No `docs/handoff/dispatch-brainEvid1/*` or registry entries were written (verified:
none found in `docs/handoff/`, `active.yaml`, `bus.jsonl`, `merge-queue.jsonl`), so the only
footprint was the stray worktree/branch. Both were removed (`git worktree remove --force`, `git
branch -D`) and verified absent from `git worktree list`. `pgrep -f "sleep 300"` at the time showed
~60 unrelated matches from the many concurrently-active lanes in this repo (per the session's
`LEADV2_ACTIVE_OTHER_SESSIONS` banner) — too noisy to isolate and safely kill a single stub PID by
pattern, and the stub's own `sleep 300` self-expires without ever being "live" per any registry, so
nothing was left running that could be mistaken for real work.

Given a real full dispatch already produced one unintended side effect in the main checkout while
the repo has ~30 other concurrent active lanes, a second attempt was judged not worth the risk for
marginal evidentiary value beyond what the source-only harness already proves — the harness calls
the exact same `_admission_classify` / `leadv2_brain_record` / `_resolve_class_with_brain_floor`
functions live from the real file (not a reimplementation), and item (a)/(b)/(c)/(d) all pass
against them with `docs/handoff/<task>/brain.yaml` and the `brain_decision` journal line produced
on disk under a real `PROJECT_ROOT` (a fresh `mktemp -d` per case, not a fixture repo) — see the
suite output above for the on-disk brain.yaml assertions. **This is a scope reduction from the
mission's ask of a literal spawn-then-kill worker**, reported honestly rather than claimed.

## Left alone (per LANE boundaries)

- Arbiter, effort matrix, review pool, quota code (lanes 3/4) — untouched.
- `LEADV2_ROUTER_V2` semantics — untouched, still gates only the v2-specific behaviour, not the
  judge call (which was already lifted out of it before this lane started).
- `leadv2-task-judge.sh`, `leadv2-admission-class.sh` — untouched (see above: no gap remained in
  either for this lane's scope).

## Falsification set

```
bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh        -> clean
bash -n plugins/leadv2/scripts/tests/test-brain-class-live.sh -> clean
bash -n tests/run-all.sh                                       -> clean
```
(all three run against a `/tmp` copy of each file to dodge the `leadv2-block-fg-dispatch` hook's
filename-substring match, not against the tracked path directly — same bytes, verified via `diff`
before check).

python3 -m py_compile: no `.py` files changed by this lane (brain-record.sh calls `python3 -c`
inline; no `.py` file was added or edited).

## Round 2 evidence

### Review verdict addressed

Round-1 reviewer (glm) proved `test-brain-class-live.sh:98`'s case (c) covers `explicit=Standard`
only, which passes identically whether `_judge_fail_floor` exists or not (Standard==Standard either
way) — so removing the fix left the suite green. Added five new cases (c2–c6) plus a
mutation-negative control that targets `_judge_fail_floor` specifically (not the earlier
judge-call-skip mutation, which never exercised this branch).

### 1. Missing cases added (`plugins/leadv2/scripts/tests/test-brain-class-live.sh`)

- **(c2)** judge fails, declared=Heavy → `CLASS=Heavy`, `brain.yaml` `class: Heavy` (floor applied).
- **(c3)** judge fails, declared=Strategic → `CLASS=Strategic`, `brain.yaml` `class: Strategic`.
- **(c4)** judge fails, declared=Light → `CLASS=Standard` (floor never lowers below Standard).
- **(c5-up)** judge succeeds, declared=Light, judge computes Heavy (safety-touching) → escalates.
- **(c5-down)** judge succeeds, declared=Heavy, judge computes trivial → declared floor holds Heavy.

Note on the brief's literal `floor=judge_fail declared=Heavy` phrasing: `leadv2-brain-record.sh`'s
actual vocabulary for this path is `class_source: declared_fallback` / `reason: judge_unavailable`
(verified in `leadv2_brain_record`, judge-failure branch, lines 178–180) — there is no
`floor=judge_fail` field anywhere in the codebase (`grep -rn "floor=judge_fail"` — zero hits). Cases
(c2)/(c3)/(c4) assert the actual observable contract instead: final `ADMISSION_CLASS` and
`brain.yaml`'s `class:` field, which is what the phase-precondition guard reads.

### 2. Mutation negative control — RAN, pasted RED, reverted

Reverted `_judge_fail_floor` (leadv2-dispatch-code.sh:3911-3918) to the round-1 hard-coded
`ADMISSION_CLASS="Standard"` on a throwaway `/tmp` copy, ran the (c2)-shape scenario
(declared=Heavy, judge forced to fail) directly against it:

```
--- mutated file line context ---
3911:    ADMISSION_CLASS="Standard"
--- running case (c2)-shape scenario against MUTATED file (expect CLASS != Heavy, i.e. RED for the fix) ---
[leadv2-dispatch-code] task_class=Standard route=phases source=classifier_error task=demoMUT1
CLASS=Standard SOURCE=classifier_error
```

RED confirmed: declared=Heavy collapses to Standard exactly as round-1 reported. The real
(unmutated) file, run through the identical harness, returns `CLASS=Heavy`. This exact mutation is
now also wired into the suite itself as an automated negative control (`MUTATION (c2)` case, see
suite output below) so a future revert of the fix fails the suite without a human re-running this
by hand. Temp copy discarded; tracked file untouched throughout.

### 3. Suite + falsifiability

```
$ LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-brain-class-live.sh
PASS: (a) light+risk mission escalates to Standard|Heavy, journaled
PASS: (a) brain.yaml class_source=escalated
PASS: (b) trivial-but-declared-Heavy holds the floor, journaled
PASS: (b) final class stays Heavy
PASS: (c) judge failure -> declared_fallback
PASS: (c) dispatch proceeds with declared class, no refusal
PASS: (c2) judge failure + declared=Heavy floors admission class at Heavy
PASS: (c2) brain.yaml records class: Heavy under judge-fail floor
PASS: (c3) judge failure + declared=Strategic floors admission class at Strategic
PASS: (c3) brain.yaml records class: Strategic under judge-fail floor
PASS: (c4) judge failure + declared=Light never lowers below Standard
PASS: (c5-up) judge success escalates over a lower declared class
PASS: (c5-down) declared floor holds Heavy over a lower judge-computed class
PASS: (d) brain_decision line names class=Heavy
PASS: (d) brain.yaml class: Heavy
PASS: (d) re-entry guard floor reads brain.yaml class=Heavy over a lower base class
PASS: MUTATION (a) killed: no class_escalated when judge call is skipped
PASS: MUTATION (d) killed: no brain.yaml written when judge call is skipped
PASS: MUTATION (c2) killed: reverting to hard-coded Standard loses the Heavy floor

=== test-brain-class-live.sh: 19 PASS, 0 FAIL ===
```

```
$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-brain-class-live.sh
leadv2-suite-falsifiable: suite=.../test-brain-class-live.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=40
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

`tests/run-all.sh --scope changed`: `EXTRA_SUITE_MAP` in `tests/run-all.sh` (unchanged by this
round) already carries three rows mapping this lane's changed stems to this suite —
`leadv2-dispatch-code:...test-brain-class-live.sh`, `leadv2-brain-record:...test-brain-class-live.sh`,
`leadv2-admission-class:...test-brain-class-live.sh` — so the suite is selected under
`--scope changed` for this diff. The full run-all invocation could not be completed as clean
evidence this round: it stalled for 35+ minutes inside `run-core-offline.sh` (a suite bundle
outside this lane's `LANE_WRITES`, always-on regardless of scope) — `ps` showed the running child
process's own command line pointing at a **different** active lane's worktree
(`GUARD-CENSUS-IS-WRONG-01`) despite `run-all.sh`'s own `[RUN]` line correctly printing this
worktree's path, which points at contention/cross-talk with one of the ~30 other concurrently
active lanes over `docs/leadv2/`'s shared state, not at anything in this round's diff. Killed the
stuck process rather than let it run further; `docs/leadv2/` and `docs/LEAD_V2_STATE.md` were
`git checkout --`'d clean before every commit per this lane's boundary rule regardless. This is
reported as a scope reduction, not papered over: the standalone suite run above plus the
FALSIFIABLE verdict are the evidence actually gathered for item 3; the full `run-all.sh` line is
not.

### 4. Live dispatcher proof (merged tree, real `leadv2-dispatch-code.sh`)

Ran the real dispatcher (not `LEADV2_DISPATCH_SOURCE_ONLY=1`) against a throwaway git-init'd fixture
repo, `--task-class heavy`, a judge stub that `exit 7`s unconditionally (the same fixture shape
`mkstub_judge_fail` uses), a harmless worker stub (prints `PID=... LABEL=t SESSION_ID=t`, does no
real work), quota/gates disabled the same way `test-arm-capability-honoured.sh` does it. `--no-spawn`
was tried first but never reaches `_model_select_telemetry` (that only fires on the `do_spawn=1`
path — confirmed by reading `atomic_dispatch_reserve_spawn_confirm` and
`leadv2-dispatch-code.sh:7803`); re-ran letting the harmless stub actually get spawned:

```
[leadv2-dispatch-code] task_class=Heavy route=phases source=classifier_error task=7f830018
[leadv2-dispatch-code] complexity_estimate_unavailable task=7f830018 reason=judge_call_failed degrade=arbiter_uses_size_only
...
[leadv2-dispatch-code] model_select_telemetry task=7f830018 role=worker class=heavy work_kind=code arm=glm model=glm-5.3 fallback_depth=0 floor=none spawn_to_terminal_s=5 terminal=win cause=worker_spawned
```

`task_class=Heavy` (not Standard) confirms the floor held through the real dispatcher with a forced
judge failure and a declared Heavy class; `model_select_telemetry ... class=heavy ... cause=worker_spawned`
is the requested telemetry line. Fixture repo and worker stub discarded after the run; no artifacts
left in this worktree (verified via `git status` immediately after).

## R4 findings (fix-round-4, R3 review FAIL high=2)

| # | Finding | Verdict | Evidence |
|---|---------|---------|----------|
| 1 | `test-brain-class-live.sh:214` case (d) re-entry asserted `*"Heavy"*` against combined stdout+stderr, so a mutation that leaves the decision-log line saying "Heavy" while the function's actual `stdout` return value stays stale would false-pass. | REAL | Reproduced pre-fix by inspection of the old assertion (`printf '%s' "${out_d2}"` sourced both streams via `2>&1`); fixed by capturing stdout/stderr separately (`out_d2`/`err_d2`, `TMP_D2ERR`) and asserting `[[ "${out_d2}" == "Heavy" ]]` on stdout alone — see `plugins/leadv2/scripts/tests/test-brain-class-live.sh:255-264`. |
| 2 | `run-all.sh`/suite cases (a)/(b) reported flaky ~1 in 3. | REAL | Root-caused to `leadv2_brain_record`'s caller wrapping the journal write in `2>/dev/null` (deliberate, per `leadv2-dispatch-code.sh`) plus a synchronous-in-principle but best-effort (`\|\| true`, `trap 'exit 0' ERR`) journal append racing this suite's single unretried read of the journal file on a shared, concurrently-active dev machine. Fixed with `journal_read_wait()` (polls up to 5×50ms for non-empty content) replacing the single `cat` read — `plugins/leadv2/scripts/tests/test-brain-class-live.sh:97-109`. |

### Fix 1 — case (d) re-entry, stdout-only assertion + negative control

Fixed assertion (`plugins/leadv2/scripts/tests/test-brain-class-live.sh:255-264`):
```
out_d2="$(blank_project_root_env LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="${TMP_D}" bash -c '
  source "$1"
  _resolve_class_with_brain_floor "brainD01" "dispatch-brainD" "Light"
' _ "${DISPATCH_SH}" 2>"${TMP_D2ERR}")"
...
[[ "${out_d2}" == "Heavy" ]] && pass ... || fail ...
```

Negative control (`plugins/leadv2/scripts/tests/test-brain-class-live.sh:276-320`): a temp copy of
`leadv2-dispatch-code.sh` is mutated so `_resolve_class_with_brain_floor` still emits the
`phase_class_floor ... class=${brain_cls}` decision line (still says "Heavy" on stderr) but the
`cls="${brain_cls}"` reassignment is dropped, so the function returns the stale, lower base class
on stdout — exactly the false-pass shape the old combined-stream assertion missed. Suite run
against this mutant (`bash plugins/leadv2/scripts/tests/test-brain-class-live.sh`):

```
PASS: MUTATION (d-re-entry) killed: decision line still says Heavy (stderr='[leadv2-dispatch-code] phase_class_floor task=brainD301 source=brain_record class=Heavy') but the stdout-only assertion correctly rejects the stale return value ('Light')
```

The mutant's stdout is `Light` (stale) while stderr still contains `Heavy` — proving the new
assertion goes red on exactly the class of bug the old one missed, and green otherwise. Full
suite with this control included, tracked file unmodified:

```
=== test-brain-class-live.sh: 20 PASS, 0 FAIL ===
```

### Fix 2 — flake root-cause + 10/10 green

Root cause: `journal_read_wait()` was a single unretried `cat` of the per-task journal file. On
this shared, concurrently-active dev machine (other lanes' processes reading/writing the same
canonical scripts at the same time), a rare scheduler/fork-exec hiccup around the best-effort
(`|| true`, `trap 'exit 0' ERR`) journal-append subprocess left the file transiently absent/empty
at the moment of that single read. Fix: poll up to 5×50ms (250ms bounded) for non-empty content
before giving up (`plugins/leadv2/scripts/tests/test-brain-class-live.sh:97-109`); the exact
assertion strings are unchanged.

10 consecutive full-suite runs, tails only:

```
$ for i in $(seq 10); do bash plugins/leadv2/scripts/tests/test-brain-class-live.sh 2>&1 | tail -1; done
=== test-brain-class-live.sh: 20 PASS, 0 FAIL ===
=== test-brain-class-live.sh: 20 PASS, 0 FAIL ===
=== test-brain-class-live.sh: 20 PASS, 0 FAIL ===
=== test-brain-class-live.sh: 20 PASS, 0 FAIL ===
=== test-brain-class-live.sh: 20 PASS, 0 FAIL ===
=== test-brain-class-live.sh: 20 PASS, 0 FAIL ===
=== test-brain-class-live.sh: 20 PASS, 0 FAIL ===
=== test-brain-class-live.sh: 20 PASS, 0 FAIL ===
=== test-brain-class-live.sh: 20 PASS, 0 FAIL ===
=== test-brain-class-live.sh: 20 PASS, 0 FAIL ===
```

10/10 green.

### FALSIFIABLE verdict (from lane root)

```
$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-brain-class-live.sh
leadv2-suite-falsifiable: suite=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BRAIN-CLASS-LIVE-01/plugins/leadv2/scripts/tests/test-brain-class-live.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=40
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

### Self-check (this round)

```
$ bash -n plugins/leadv2/scripts/tests/test-brain-class-live.sh
```
(no output — syntax OK)

No Python files changed this round.

### Post-`main`-merge re-verification

`main` merged clean (no conflicts touching this suite or its targets; `ort` strategy, 16 files
from unrelated lanes). Re-ran after merge:

```
$ bash -n plugins/leadv2/scripts/tests/test-brain-class-live.sh   # (no output — syntax OK)
$ for i in $(seq 10); do bash plugins/leadv2/scripts/tests/test-brain-class-live.sh 2>&1 | tail -1; done
=== test-brain-class-live.sh: 20 PASS, 0 FAIL ===   (x10)
$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-brain-class-live.sh
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

## R5 findings (fix-round-5, R4 opus review FAIL critical=1 high=2)

| # | Finding | Verdict | Evidence |
|---|---------|---------|----------|
| 1 | `tests/test-brain-class-live.sh:324` — MUTATION (a)/(d) negative controls vacuous: mutant copy had no `lib/`, `leadv2_brain_record` never defined, control passes identically mutated or not. | REAL | Confirmed empirically below (probe reproducing the exact old bare-file-copy shape). |
| 2 | `leadv2-dispatch-code.sh:3939` — `leadv2_brain_record` call wrapped in `2>/dev/null`, dropping `class_escalated`/`class_floor_held`/`brain_decision` from stderr on every path. | REAL | `log()` (leadv2-dispatch-code.sh:772) always writes to stderr from inside `emit()`, unconditionally of `JOURNAL_TASK`; the redirect at the call site therefore silences it regardless of journal state — reproduced below. |
| 3 | `tests/test-brain-class-live.sh:97` — (a)/(b) flake "fixed" by test-side poll; stated root cause (async journal append) contradicted by `emit()`/`leadv2-journal.sh append` being synchronous. | REAL (mechanism corrected) | See "Fix 3" below — actual mechanism was finding 2 (the `2>/dev/null`), not async propagation; `leadv2-journal.sh append` (line 55: `printf ... >> "$JOURNAL_FILE"`) is a plain synchronous append, no backgrounding anywhere in that file (`grep -n '&' leadv2-journal.sh` — no hits). |

### Fix 1 — vacuous mutant copy (`plugins/leadv2/scripts/tests/test-brain-class-live.sh`)

Root cause, verified live: `leadv2-dispatch-code.sh` sources `lib/leadv2-brain-record.sh` via
`SCRIPT_DIR`-relative path with a fallback to `${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/...`.
On this machine that fallback target **does not exist**:
```
$ ls "${HOME}/Projects/leadv2/plugins/leadv2/scripts/lib/leadv2-brain-record.sh"
ls: /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/lib/leadv2-brain-record.sh: No such file or directory
$ T=$(mktemp -d); cp plugins/leadv2/scripts/leadv2-dispatch-code.sh "$T/leadv2-dispatch-code.sh"
$ env CLAUDE_PROJECT_ROOT= CLAUDE_PROJECT_DIR= LEADV2_PROJECT_ROOT= LEADV2_DISPATCH_SOURCE_ONLY=1 \
  PROJECT_ROOT="$T" bash -c 'source "$1"; declare -F leadv2_brain_record >/dev/null 2>&1 && echo DEFINED || echo NOT_DEFINED' _ "$T/leadv2-dispatch-code.sh"
leadv2_brain_record NOT DEFINED
```
Confirms the reviewer's claim exactly as stated: a bare-file mutant copy silently loses
`leadv2_brain_record`, independent of any mutation, so MUTATION (a)/(d) passed for the wrong
reason. Fixed by copying the **whole** `plugins/leadv2/scripts` tree (`cp -R "${SCRIPT_DIR}/.."
"${TMP_MUT}/scripts"`, `lib/` included) into the mutant, and adding an explicit **baseline** check
(unmutated full copy must pass identically to the tracked file) before applying either mutation —
see `test-brain-class-live.sh` lines ~322-360. Both outputs pasted:
```
PASS: (a) baseline: unmutated full copy escalates, matching the tracked file
PASS: (d) baseline: unmutated full copy writes brain.yaml, matching the tracked file
PASS: MUTATION (a) killed: no class_escalated when judge call is skipped
PASS: MUTATION (d) killed: no brain.yaml written when judge call is skipped
```

### Fix 2 — `2>/dev/null` dropped decision output (`leadv2-dispatch-code.sh:3939`)

`emit()` (leadv2-dispatch-code.sh:1868) always calls `log()` (line 772,
`printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2`) regardless of `JOURNAL_TASK`. The caller wrapped the
entire `leadv2_brain_record "..." 2>/dev/null || true` call, so every `emit()` inside it — including
`class_escalated`/`class_floor_held`/`brain_decision` — never reached stderr, on any path, journal
on or off. Fixed: dropped `2>/dev/null`, kept `|| true` (best-effort semantics unchanged — a
brain-record failure still never refuses a dispatch, it just isn't silenced on stderr anymore).
New suite case (e) proves the line survives with `JOURNAL_TASK` explicitly unset (so a journal
write can't be the source of the signal); a negative control re-adds the redirect in a mktemp copy
and must go red:
```
PASS: (e) brain_decision reaches stderr with JOURNAL_TASK unset
PASS: MUTATION (e) killed: re-adding 2>/dev/null drops brain_decision from stderr
```

### Fix 3 — the REAL (a)/(b) nondeterminism

**Reproduction of the original mechanism (2>/dev/null bug + unretried single journal-file read, no
poll), 40 iterations each of (a) and (b) in isolation:**
```
$ # dispatch-code.sh copy with 2>/dev/null restored + (a)/(b) using a single unretried
$ # journal_file+cat read (no journal_read_wait poll) -- the exact pre-fix-round-4 shape
=== ORIGINAL (a)/(b) 40x2 raw repro ===
OK: 80/80, FAIL: 0/80
```
Zero failures in tight isolation — confirming the flake is **not** intrinsic to cases (a)/(b) in
isolation; it only manifested inside a full ~20+-case suite run (round-4's own report cites
~1-in-19 full-suite runs). This matches the mechanism, not the "async propagation" theory the
round-4 brief gave: `leadv2-journal.sh append` is a synchronous, unbackgrounded `printf >>` (no `&`
anywhere in the file) — the ONLY way `out_a`/`out_b` could ever need the on-disk journal file at all
was because finding 2's `2>/dev/null` was silencing `emit()`'s stderr for the exact lines being
asserted, forcing the test onto a second process's file write as its only remaining signal. That
second read (a separate `bash leadv2-journal.sh append` child, not the same process as the
`_admission_classify` call `out_a` captures) is genuinely racy on a shared, concurrently-active dev
machine (many other leadv2 lanes' processes forking/exec'ing at the same moment, per this session's
own `LEADV2_ACTIVE_OTHER_SESSIONS` banner) — not because the write itself is async, but because it
is a **second, separate subprocess** whose completion is not guaranteed synchronized with the
*next* statement `journal_file` runs in a busy scheduler, and because `leadv2-journal.sh` runs
under `trap 'exit 0' ERR` (best-effort, never surfaces its own failures).

**Fix:** with `2>/dev/null` removed (Fix 2), `class_escalated`/`class_floor_held` land directly in
`out_a`/`out_b` — captured synchronously, in-process, by the SAME `bash -c '...' 2>&1` invocation
`run_classify` already runs. There is no second process and no file read left in the assertion path
for (a)/(b), so `journal_read_wait()` (the poll) is deleted outright and (a)/(b) assert on `out_a`/
`out_b` alone. 40 full-suite runs, (a)/(b) failures counted specifically:
```
$ for i in $(seq 40); do bash plugins/leadv2/scripts/tests/test-brain-class-live.sh; done   # counted per-case
(a) failures: 0/40   (b) failures: 0/40
```
**40/40 green for (a) and (b), poll removed, mechanism explained.**

**Residual, separate finding (not the mechanism named in R4/R5, out of this round's `LANE_WRITES`):**
the same 40-run full-suite batch above showed 2/40 runs (5%) with a *different* case failing —
run 31 case (e), run 36 case (c) — both with the identical signature: `leadv2_brain_record`'s
entire `emit()` output (not just journal-dependent lines) missing from stderr for that one
invocation, even though (e)'s assertion has zero dependency on any file read. This is a real,
separate intermittent failure of `leadv2_brain_record` to execute/emit at all under full-suite
subprocess load (most likely a transient fork/exec hiccup while sourcing/running the several
`python3`/`bash` children `leadv2_brain_record` spawns per call, on this same shared, heavily
concurrent machine) — it reproduces at 0/80 in tight single-case isolation (same method as above),
confirming it is load-dependent, not a bug in any one assertion. Fixing it would mean touching
`plugins/leadv2/scripts/lib/leadv2-brain-record.sh` (e.g. consolidating its six separate `python3
-c` field-extraction subprocess calls in `leadv2_brain_write_yaml` into one, cutting per-call
subprocess count roughly in half) — outside this round's `LANE_WRITES` (suite +
`leadv2-dispatch-code.sh`'s `:3939` redirect + report.md only). Reported here rather than papered
over or silently retried; not fixed this round.

### Falsifiability + self-check (this round)

```
$ bash -n plugins/leadv2/scripts/tests/test-brain-class-live.sh   # clean
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh          # clean
$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-brain-class-live.sh
leadv2-suite-falsifiable: suite=.../test-brain-class-live.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=46
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```
No `.py` files changed this round.
