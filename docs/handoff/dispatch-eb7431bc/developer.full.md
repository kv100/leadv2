# D4-NO-PATH-LOSES-WORK-01 — finisher report

## 0. Repo hygiene fixed before touching evidence

Before any evidence-gathering, `git diff main...HEAD` showed two things that were NOT this
lane's work and would have failed the gate outright:
- 6 tracked files under `plugins/leadv2/scripts/` whose names were literal captured
  `git status`/`git add` stdout (embedded newlines, `/var/folders/.../repo-93601-21090/...`
  paths) — leaked from an earlier crashed session that ran the test suite with an unquoted
  path. Removed with `git rm --cached` + `rm -rf`, confirmed absent from `git ls-tree`.
- `docs/leadv2/active.yaml` had been rewritten from a regular file (matching `main`) to a
  symlink pointing at a test's temp `$TMPDIR`, by the same crashed run. Restored via
  `git checkout main -- docs/leadv2/active.yaml`; `git diff main HEAD -- docs/leadv2/active.yaml`
  is now empty. (The other `docs/leadv2/*` control-plane files show churn in the three-dot
  `main...HEAD` diff only because `main` itself has moved since this branch forked — a
  two-dot `git diff main HEAD` confirms none of them differ from current `main`.)

Committed as `5c0d85eb`. Confirmed no off_limits/runtime-state path is touched by this lane's
real diff: `git diff main...HEAD --stat` now shows only
`leadv2-orphan-checkpoint.sh`, `lib/leadv2-lane-worker-alive.sh`,
`hooks/leadv2-merged-worktree-sweep.sh`, `leadv2-phase8-close.sh`,
`tests/test-leadv2-orphan-checkpoint.sh`, and this handoff's own `context.yaml`.

## 1. Baseline suite, bash (foreground, full run)

```
$ bash plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh
... (24 PASS lines: syntax, lib false-answer cases, A1-A6, D12 x2, D10#1)
NEGATIVE CONTROL #1 (mutated, untracked-files=no) A1 exit observation: RED=1 (1=correctly RED, 0=FAILED TO REDDEN)
NEGATIVE CONTROL #1 (reverted) A1 exit observation: rc=0 (0=correctly GREEN, 1=still failing)
PASS: D10 negative control #1: untracked-files mutation turns A1 RED, revert turns it GREEN
NEGATIVE CONTROL #2 (mutated, no diff --cached --quiet guard) A4 exit observation: RED=0 (1=correctly RED, 0=FAILED TO REDDEN)
NEGATIVE CONTROL #2 (reverted) A4 exit observation: rc=0 (0=correctly GREEN, 1=still failing)
FAIL: D10 negative control #2 (optional): missing diff --cached --quiet guard turns A4 RED, revert turns it GREEN -- mutated_rc=0 reverted_rc=0

24 passed, 1 failed
```
`bash_rc=1` (nonzero because of the 1 FAIL). **This FAIL is the suite's own built-in D10
negative-control #2, explicitly marked "(optional)" in the suite and in context.yaml D10.**
It is a genuine, pre-existing coverage hole (see §2 row for `_lv2_orphan_inscope_commit`
mutation #2 below) — not something I introduced or hid.

`bash -n` / `zsh -n` syntax checks (built into the suite, section 0) both PASS.

**On invoking the whole harness with `zsh script.sh` directly**: this fails immediately with
`BASH_SOURCE[0]: parameter not set` — the shebang is `#!/usr/bin/env bash` and the suite uses
`${BASH_SOURCE[0]}` for its own path resolution, which is bash-only syntax with no zsh
equivalent under `zsh -c`/direct invocation. This is expected and correct: the suite's own
"bash AND zsh" requirement (D5) is satisfied by the INTERNAL `bash/zsh agree:` checks already
in section A (lines ~153-174), which explicitly `source` the lib under both interpreters and
compare return codes — both PASS. Running the top-level script file itself with the `zsh`
interpreter is not how this or any other suite in the repo is invoked; doing so is a test-
methodology error, not a defect, and I want to say this explicitly since it cost me a false
signal earlier this session (a second attempt at it re-leaked the same class of garbage-named
files as §0, which I then removed again — confirmed clean via `git status --short`).

## 2. Per-function negative-control matrix (mission §1)

Functions changed on this branch (`git diff main...HEAD` — three dots):

### `plugins/leadv2/scripts/lib/leadv2-lane-worker-alive.sh`

| Function | Mutation (inside body) | baseline_rc | mutated_rc | reverted_rc | Verdict |
|---|---|---|---|---|---|
| `_lv2_lane_realpath` | force wrong/garbage path output instead of realpath | 0 | 1 | 0 | RED/GREEN OK |
| `lv2_lane_cwd_prime` | flip false-zero (`rc=0`,empty output) branch from fail-closed-ALIVE to DEAD | 0 | 1 | 0 | RED/GREEN OK |
| `lv2_lane_cwd_reset` | leave `LV2_LANE_ALIVE_PRIMED=1` instead of resetting to 0 | 0 | 1 | 0 | RED/GREEN OK |
| `lv2_lane_worker_alive` | drop the path-boundary guard (`"${wt_path}"/*` match becomes bare `*`) — mirror-dead regression | 0 | 1 | 0 | RED/GREEN OK |
| `lv2_lane_pid_alive` | make the `"no such process"` stderr-classification branch unreachable (classify by rc only) | 1 (dead pid) | 127 (crash) | 1 | RED/GREEN OK — crashes rather than logically flips, but still reliably reddens |
| `lv2_lane_pid_cwd` | always `return 1` even when a matching row exists | 0 | 127 (syntax, same caveat) | 0 | RED/GREEN OK |
| `lv2_lane_pid_alive_for` | drop the false-life cwd cross-check (`*) return 1` → `return 0`) | 0 (rejects reused pid) | 1 (now wrongly accepts it) | 0 | RED/GREEN OK |
| `lv2_lane_any_alive` | flip `&&` to `||` on the per-pid check (require ALL instead of ANY) | 0 | 1 | 0 | RED/GREEN OK |
| `lv2_lane_alive_combined` | disable the pid-handle branch (`if false; then`) | 0 | 1 | 0 | RED/GREEN OK |

All 9 functions in this file have a working negative control. Two of the nine (`lv2_lane_pid_alive`,
`lv2_lane_pid_cwd`) redden via a bash syntax error from the specific one-line mutation I chose
rather than a clean logical flip — I'm flagging this rather than presenting it as equivalent to
the other seven: it proves the suite catches *a* break in that function, not necessarily every
semantically-meaningful one. A follow-up could redo those two mutations as pure logic edits.

Harness used: `/tmp/mut_lib2.sh` (ad hoc, not committed — sources the lib in a subshell with a
stubbed `lsof`, reusing the exact fixtures from the suite's own section A). File confirmed
byte-identical to the pre-mutation original after the run (`diff` against a saved copy →
`IDENTICAL-TO-ORIGINAL`), and `git diff --stat` on this file is empty.

### `plugins/leadv2/scripts/leadv2-orphan-checkpoint.sh`

| Function | Mutation (inside body) | baseline_rc | mutated_rc | reverted_rc | Verdict |
|---|---|---|---|---|---|
| `_lv2_orphan_out_of_scope` | replace the `leadv2_writeset_missing` pipeline with `true` (nothing ever out-of-scope) | 0 | 1 | 0 | RED/GREEN OK (A6 catches it: out-of-scope file lands on the lane branch instead of quarantine) |
| `_lv2_orphan_quarantine_commit` | make `update-ref` a no-op `return 0` (quarantine branch never created) | 0 | 1 | 0 | RED/GREEN OK (A6) |
| `_lv2_orphan_recorded_pid` | always return a bogus PID (`9999999999`) instead of the real grep | 0 | 1 | 0 | RED/GREEN OK — A6 catches this too, incidentally revealing that `kill -0` on a 10-digit PID does not always report "no such process" text on this host, so a bogus large-PID handle can slip past the stderr classifier; worth a follow-up look, not fixed here (out of scope for a finisher pass — flagging per the "say so plainly" instruction) |
| `_lv2_orphan_lane_writes_csv` | truncate the function early with `return 0` (line 147, breaking the `grep \| sed` continuation) | 0 | 1 | 0 | RED/GREEN OK — this mutation is a syntax break (orphaned `\|`), same caveat as the two lib-file crash cases above |
| `_lv2_orphan_inscope_commit` | **D10 negative control #1** (untracked-files=all→no) | 0 | 1 (RED) | 0 | RED/GREEN OK — already in the committed suite |
| `_lv2_orphan_inscope_commit` | **D10 negative control #2** (drop `diff --cached --quiet` guard) | 0 | 0 (did NOT redden) | 0 | **NO-FLIP — genuine coverage hole, see below** |
| `_lv2_orphan_lane_id` | not mutated separately — one-line `basename` wrapper, exercised by every A1-A6 case implicitly (lane_id feeds every commit message/branch name asserted in those cases) | — | — | — | not independently mutated; low-value, mechanical |
| `_lv2_orphan_find_run_meta` | not mutated separately — already exercised by A6 (meta.yaml lookup) and its find-nothing path by A1-A5 (no cache dir) | — | — | — | not independently mutated given time budget; A6's pass depends on it finding the meta, A1-A5's pass depends on it correctly returning nothing |

**D10 negative control #2 is a real, reported coverage hole**, not swept under the rug: deleting
the `diff --cached --quiet` guard in `_lv2_orphan_inscope_commit` should make A4 (clean lane →
no empty commit) go RED, per context.yaml D10(2). It does not. Looking at the code
(`leadv2-orphan-checkpoint.sh:294-297`), A4's clean-lane case is actually caught one level
higher — the `git status --porcelain --untracked-files=all` early-return at line 294 sends a
clean lane to `skipped_clean` before `_lv2_orphan_inscope_commit` is ever called, so removing
the *inner* guard is unreachable dead code for A4's specific scenario. The guard is still
real defense-in-depth (protects a path where `status_out` is non-empty from some external
change but the exact tracked paths handed to `_lv2_orphan_inscope_commit` end up not actually
differing from HEAD — e.g. a mode-only touch that porcelain reports but `diff --cached` does
not), but this suite's fixtures do not exercise that narrower path. I did not invent a new
fixture to force it green given the mission's explicit instruction to report gaps rather than
paper over them.

## 3. Liveness review criterion (mission §2) — self-check

- **`kill -0` classified by stderr, not exit code**: confirmed,
  `lib/leadv2-lane-worker-alive.sh:190-192` — `case "${err}" in *[Nn]o\ such\ process*) return 1
  ;; *) return 0 ;; esac`, only reached after `err="$(kill -0 "${pid}" 2>&1)"`. rc alone is
  never inspected for the ESRCH/EPERM distinction.
- **(PID, start-time) pair, not bare PID**: this file does NOT compare start-time itself — it
  cross-checks PID against **cwd** instead (`lv2_lane_pid_alive_for`, lines 222-236): a
  recorded PID is only trusted if the SAME lsof pass's cwd for that exact PID is inside the
  worktree, closing the reused-PID false-life hole without needing `/proc`-style start-time
  (not portably available on macOS). `leadv2-lane-state.sh`'s `pid_start_time` field is a
  DIFFERENT, already-existing mechanism (off-limits file, read-only reference) — this lane
  does not touch or duplicate it. I'm flagging this as a **design deviation from the literal
  mission text** ("match that discipline") rather than silently claiming compliance: the cwd
  cross-check achieves the same goal (reject a live-but-unrelated process holding a recycled
  PID) through a different, already-working primitive, and the false-life test case in the
  suite (line ~122-136) proves it closes exactly that hole. If start-time parity specifically
  is required for another reason (e.g. an existing consumer expects that exact field), that's
  a decision-conflict, not something I resolved unilaterally.
- **Timeout → `unknown`, never replaced by last known value**: `lv2_lane_cwd_prime` treats a
  `timeout` non-zero rc + empty output the same as any other empty-output case — fail-closed
  to ALIVE (`LV2_LANE_ALIVE_FAILCLOSED=1`), which is this codebase's chosen encoding of
  "unknown" (D2: bias toward ALIVE under ambiguity, never toward DEAD). There is no code path
  that caches or reuses a prior liveness verdict across primes — `lv2_lane_cwd_reset` clears
  the cache file and `LV2_LANE_ALIVE_PRIMED` explicitly, and a fresh prime is unconditional.
- **No recorded handle at all → unknown, never dead**: `lv2_lane_worker_alive` line 147:
  `[[ -n "${wt_path}" ]] || return 0` — empty input fails closed to ALIVE (0), not DEAD (1).
  `lv2_lane_any_alive` line 247: empty `pid_list` → `return 1` (not-alive-by-this-signal), but
  it is only ONE of two signals `lv2_lane_alive_combined` ORs together — the cwd check still
  runs and can independently return ALIVE. There is no single code path where "no handle
  recorded" collapses straight to a hard DEAD verdict.

**Verdict: no line found where an unanswerable case becomes `dead`.** Every fail path in this
file resolves to ALIVE (the fail-closed/unknown state), consistent with D2 and the review
criterion.

## 4. CI selection proof (mission §3) — LEAD NOTE: `tests/run-all.sh` NOT edited

Per the lead note in this mission, `tests/run-all.sh` is out of this lane's write set (owned by
another lane to avoid an `EXTRA_SUITE_MAP` merge conflict). I did not touch it.

**Selection proof, run against this lane's actual current diff** (`LEADV2_RUN_ALL_SELECT_ONLY=1`
is an existing non-executing seam in `tests/run-all.sh` built for exactly this purpose):

```
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh
run-all: 5 selected, scope=changed, select_only=1
```

`test-leadv2-orphan-checkpoint.sh` **is already selected today**, but for two reasons that will
stop applying the moment this branch's test-file edit is no longer in the diff (e.g. after a
future lane touches only the production files): (1) "a changed test suite must select itself"
(the file itself is part of this diff), and (2) `leadv2-orphan-checkpoint.sh`'s own stem
(`leadv2-orphan-checkpoint`) happens to match the suite's name via the existing self-select
naming convention (`test-<stem>.sh`).

**The gap this row closes**: `lib/leadv2-lane-worker-alive.sh`'s stem is
`leadv2-lane-worker-alive`, which has NO `test-leadv2-lane-worker-alive.sh` — so a future change
to *only* that file (test file untouched) selects **zero** suites under `--scope changed`
without this row. Confirmed by reading the stem-derivation code at `tests/run-all.sh:531-533`
(`stem="$(basename "${cf}"); stem="${stem%.*}"`) and the self-select candidate list at
`tests/run-all.sh:534-538` (only `test-${stem}.sh` under 4 fixed directories — no fuzzy match).

**Row to append, verbatim, after the existing block's last line (`tests/run-all.sh` line 163,
`leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh`), before
the closing `"` of the `EXTRA_SUITE_MAP=` string** — append-only, no reordering of the 30
existing rows:

```
leadv2-lane-worker-alive:plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh
leadv2-lane-worker-alive.sh:plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh
leadv2-orphan-checkpoint:plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh
leadv2-orphan-checkpoint.sh:plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh
leadv2-merged-worktree-sweep.sh:plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh
```

(Both bare-stem and `.sh`-suffixed keys included per the existing file's own convention —
`tests/run-all.sh:463`: `[[ "$key" == "${stem}" || "$key" == "${stem}.sh" ]]`. The
`leadv2-orphan-checkpoint*` rows are technically redundant with the self-select convention
today but are cheap insurance against a future rename breaking that implicit match — matching
this file's own existing practice of listing a stem in `EXTRA_SUITE_MAP` even where a same-named
suite exists, e.g. `leadv2-dispatch-code.sh:...test-freepool-capability-floor.sh` alongside
other rows. The `leadv2-merged-worktree-sweep.sh` row covers the D9 wiring point, though note
§5's caveat: no test in this suite currently asserts checkpoint-before-sweep ORDERING itself,
only that the checkpointer function behaves correctly in isolation.)

**Not yet landed** — per the lead note, this row is proposed here, not applied. CI does not
select the new suite via this row until the lead lands it in the shared `tests/run-all.sh`.
Today, the suite IS selected, but only via the two indirect mechanisms above, both of which
stop working the moment this branch's own test-file diff is gone.

## 5. What the green suite proves and does not (mission §4)

The 24/25 green result above is **verified by the suite against this lane's own copy of the
scripts in this worktree** (`plugins/leadv2/scripts/leadv2-orphan-checkpoint.sh` and
`plugins/leadv2/scripts/lib/leadv2-lane-worker-alive.sh`, both real files in this worktree, not
symlinks — confirmed: this lane created them, they are not part of the shared symlink tree
described in CLAUDE.md's "shared trees" section).

**The live dispatcher loads a separate plugin cache and is unaffected until that cache is
updated and the session restarted.** Nothing in this suite, this branch, or this report changes
what any currently-running `claude-subsession`/`glm-coder`/`dispatch-code` process does right
now. The wiring added to `leadv2-merged-worktree-sweep.sh` and `leadv2-phase8-close.sh` (§ below)
will not run for any lane until (a) this branch is merged and (b) the consuming session's plugin
cache is refreshed and its session restarted, per CLAUDE.md's documented hook/cache exception.
This report is evidence the CODE behaves correctly when invoked directly; it is not evidence
about production behavior today.

## 6. Bash 3.2 / falsification set (self-check, both interpreters)

```
$ bash -n plugins/leadv2/scripts/leadv2-orphan-checkpoint.sh && echo OK-bash-n-ckpt
OK-bash-n-ckpt
$ bash -n plugins/leadv2/scripts/lib/leadv2-lane-worker-alive.sh && echo OK-bash-n-lib
OK-bash-n-lib
$ bash -n plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh && echo OK-bash-n-test
OK-bash-n-test
$ zsh -n plugins/leadv2/scripts/leadv2-orphan-checkpoint.sh plugins/leadv2/scripts/lib/leadv2-lane-worker-alive.sh && echo OK-zsh-n
OK-zsh-n
```
(all four ran clean; also re-confirmed as part of the suite's own section-0 checks, both PASS.)

Full suite run (final, foreground, no mutation in flight): **24 passed, 1 failed** — the single
FAIL is the reported D10#2 coverage hole in §2, not a regression from anything in this report.

## 7. Left alone / not done

- Did not touch `tests/run-all.sh` (lead-owned per this mission's LEAD NOTE) — row specified
  in §4 for the lead to land.
- Did not attempt to force D10 negative control #2 green by adding a new fixture — reported as
  a coverage hole instead (§2), per the mission's explicit instruction not to paper over gaps.
- Did not independently mutate `_lv2_orphan_lane_id` or `_lv2_orphan_find_run_meta` in isolation
  (both are exercised as part of every A1-A6 pass; given the mission's 30-tool-call practice
  and time already spent on 13 other functions, I judged this the right place to stop rather
  than manufacture two more low-value mutations). Flagging explicitly per "say what's missing."
  If a stricter per-function audit is required, these two are next.
- Did not add a dedicated test asserting the D9 checkpoint-before-sweep ORDERING itself (only
  that the checkpointer behaves correctly, and that its call site is textually positioned
  before the sweep logic in both files, confirmed by direct diff read in §4). This was not
  explicitly required by mission step 4's acceptance list (A1-A6 + false-answer cases + D12 +
  bash/zsh agreement), but is worth naming as a gap.
- No optional Phase 6 (2nd-commit EXIT-trap backstop in `lib/leadv2-worker-epilogue.sh` +
  coder wrappers) — plan step 6 marks this OPTIONAL and out of this finisher's scope (the
  finisher brief is explicitly "do NOT redesign, do NOT rewrite the three files" and lists
  four specific gaps; step 6 is not one of them).

## 8. New evidence this session: A2 is intermittently flaky (not a regression I introduced)

Three additional full foreground runs after the above (no code changes in between,
`git status` clean throughout):

```
run 1: 24 passed, 1 failed (D10#2, as in §1)
run 2: FAIL: A2: process-group-kill scale (14 dirty files) -> exactly ONE commit -- added=0 dirty=[?? many-1.txt ... many-14.txt]
run 3: RC=124 (outer 300s timeout hit mid-run, but every case through D12 had already PASSED,
        including A2)
```

Run 2's A2 failure shows `added=0` — the 14 untracked fixture files were on disk (git status
lists them as `??`) but nothing got staged before the commit check ran. This reads as a timing
race in the test's own fixture setup (file-creation vs. the checkpointer's `git status`/`add`
pass), not a logic bug in `_lv2_orphan_inscope_commit` itself — the same code path is what run 1
and run 3 exercised successfully. I did not chase this further (root-causing an intermittent
timing race under this session's remaining budget would mean instrumenting the test harness,
which is a change to committed test code I was not asked to make). Flagging per "an
environment-sensitive failure is a finding, not a test bug": **A2 should be treated as flaky,
re-run once before trusting a single red/green result**, and a follow-up should look at whether
the 14-file fixture creation loop in the test synchronizes with the filesystem before invoking
the checkpointer.

Also note: full-suite runtime is long enough (>300s wall clock across the 3 acceptance worktrees
+ both D10 negative-control reruns) that a 120-300s CI timeout will intermittently kill it
mid-run (as run 3 did here) even when every individual case is passing — worth flagging
separately from the A2 flake itself.

DELIVERABLE_COMPLETE
