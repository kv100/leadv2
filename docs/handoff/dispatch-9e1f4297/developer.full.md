verdict: APPROVE
next_action: review_round_2

# LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01 — developer.full.md

## 0. Scope actually delivered

- `plugins/leadv2/scripts/leadv2-lane-outcome.sh` — decision table reordered: verdict
  (new hook) → bound/work state → wording (last resort, subordinated), plus
  `_resolve_work` now distinguishes "the probe could not run" (`unknown`) from an
  actual clean tree (`no`).
- `plugins/leadv2/scripts/lib/leadv2-parked-detect.sh` — read only, unchanged. The
  wording probe itself (`lv2_parked_text_file`) is not the defect; the defect was
  that its result could be consulted without regard to `WORK` or a verdict. That is
  fixed at the call site in `leadv2-lane-outcome.sh`, not inside the probe.
- `plugins/leadv2/scripts/tests/test-lane-outcome-reads-state.sh` — new suite, 7 cases.
- `docs/handoff/LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01/mutation-control/` —
  3 mutation-control artifacts.
- `docs/handoff/dispatch-9e1f4297/` — this deliverable.

## 1. The §1 question — answered with evidence

**None of the five listed candidates is the cause.** The actual mechanism is a sixth
one: `pc_dwr_resume_once` (`leadv2-dispatch-product-close.sh:776`) is only reachable
from the code path immediately after a *successful* `pc_await_worker_exit` on the
*current* arm attempt (`leadv2-dispatch-product-close.sh:2594`, guarded by the
worker_timeout `exit 5` branch above it). When the close gate's own **arm-quota
pre-check** fails and advances to a different arm (`review_gate ... status=blocked
reason=arm_quota_failed action=arm_advanced`), that happens on a *different*
invocation of `leadv2-dispatch-product-close.sh` — and `pc_dwr_resume_once` is never
called for the arm that actually died with work, because by the time that
invocation runs, `AUTHOR`/`HANDLE` may already point at a different arm, or the
script simply never reaches the post-`pc_await_worker_exit` line for the died-with-
work handle before its own arm chain reports `arm_produced_nothing`/exhaustion.

Evidence (measured on live `docs/leadv2/tasks/*/journal.md`, main-repo checkout,
read-only):

```
$ cd /Users/kostiantyn.vlasenko/.claude/cache
$ for f in */*/progress.log; do
    grep -qm1 "LEADV2_LANE_OUTCOME outcome=died-with-work" "$f" 2>/dev/null || continue
    [[ "$(date -r "$f" '+%Y-%m-%d')" == 2026-09-03 ]] && echo "$f"
  done
freepool-runs/260903-030233-CI-SUITES-ARE-MACOS-ONLY-01-49db/progress.log
glm-runs/260902-232929-PHASE-BOOTSTRAP-DEADLOCK-01-3a3a/progress.log
glm-runs/260903-001259-WATCHER-LEAK-01-6de7/progress.log
glm-runs/260903-001308-PROMISE-GUARD-UNKNOWN-KIND-01-4eaa/progress.log
glm-runs/260903-012055-WATCHER-LEAK-01-1d74/progress.log
glm-runs/260903-022201-WATCHER-LEAK-01-4e39/progress.log
glm-runs/260903-051923-TWELVE-LINUX-ONLY-SUITES-01-6f9e/progress.log
```

Mapped each `cwd:` in `meta.yaml` to a task journal (`grep -rl <lane-name>
docs/leadv2/tasks/*/journal.md`) and read the tail of each journal:

```
== dispatch-cf509abb (PROMISE-GUARD-UNKNOWN-KIND-01) ==
2026-09-02T21:13:28Z model_select_telemetry ... arm=glm-flash ... cause=worker_spawned
2026-09-02T22:14:14Z review_gate status=blocked reason=arm_quota_failed action=arm_advanced arm=glm-flash
2026-09-02T22:59:21Z dispatch_terminal task=cf509abb terminal=dead cause=e2e_regression
```

`progress.log` for `260903-001308-PROMISE-GUARD-UNKNOWN-KIND-01-4eaa` recorded
`outcome=died-with-work` — the classifier was RIGHT. But `dwr_resume` never appears
anywhere in `dispatch-cf509abb/journal.md`: no attempt line, no
`already_attempted` skip, no `blocked_by_gate`. The gate went straight from
`arm_quota_failed` (a pre-check unrelated to `pc_dwr_resume_once`) to
`dispatch_terminal terminal=dead cause=e2e_regression`, discarding the classifier's
own correct verdict.

```
== dispatch-395cf9b2 (CI-SUITES-ARE-MACOS-ONLY-01) ==
2026-09-03T00:02:54Z model_select_telemetry ... arm=freepool
2026-09-03T00:39:52Z review_gate status=blocked reason=arm_quota_failed action=arm_advanced arm=freepool
2026-09-03T00:43:20Z review_gate status=blocked reason=selfcheck_failed terminal=refused
2026-09-03T00:43:21Z dispatch_terminal terminal=refused cause=selfcheck_failed
2026-09-03T16:56:49Z model_select_telemetry ... arm=sonnet
2026-09-03T17:35:55Z dispatch_terminal terminal=parked cause=e2e_timeout
2026-09-03T19:11:56Z model_select_telemetry ... arm=sonnet
2026-09-03T19:55:59Z dispatch_terminal terminal=dead cause=e2e_regression
```

Same shape: `arm_quota_failed` again precedes the terminal decision; no
`dwr_resume` line anywhere in this task's whole journal despite a recorded
`died-with-work` outcome.

For `WATCHER-LEAK-01` (`dispatch-b20a06ae`) and `PHASE-BOOTSTRAP-DEADLOCK-01`
(`dispatch-0c3d5245`), a `dwr_resume` DID fire once (the marker's "exactly once"
worked as designed), but the *resumed* run also ended in `terminal=dead
cause=e2e_regression` with no second resume — which is `pc_dwr_resume_once`
behaving exactly as documented (once only), not a bug. The bug is specific to
`cf509abb` and `395cf9b2`: a died-with-work run whose resume check is never even
reached because the close gate's arm-quota pre-check runs on a separate
invocation and short-circuits before `pc_dwr_resume_once` is called for that
handle.

**This is a finding about `leadv2-dispatch-product-close.sh`, which is off-limits
to me (bounds §4).** Per the brief's instruction, the exact fix (not landed) would
be: before advancing to the next arm on `arm_quota_failed`, check
`_pc_lane_outcome "$(_pc_run_dir_for "${AUTHOR}" "${HANDLE}")"` for
`died-with-work|parked` and call `pc_dwr_resume_once` there too — i.e. the
resume attempt needs a second call site inside the arm-quota-failure branch
(`leadv2-dispatch-product-close.sh:945` area), not just the one after a normal
`pc_await_worker_exit`. This is a proposal only; it is not landed, and I did not
edit that file.

## 2. What I actually changed, and why

### `leadv2-lane-outcome.sh`

1. **Verdict-first hook (`_resolve_verdict`).** Reads `${RUN_DIR}/.gate-verdict`
   (format `outcome=<token>`) and, if present, that value is the `OUTCOME`
   unconditionally — before bound, before work, before wording.
   **Honesty note, stated in-code and here:** as of this change NO shipped caller
   writes `.gate-verdict`. Measured: `grep -rln leadv2-lane-outcome.sh
   plugins/leadv2/scripts/*.sh` → `glm-coder.sh`, `kimi-coder.sh`,
   `freepool-coder.sh` — all three invoke the classifier from inside their own
   finalize path, immediately at raw worker exit, BEFORE
   `leadv2-dispatch-product-close.sh`'s `review_gate`/dod-gate machinery ever
   runs (confirmed by reading both call sites: `glm-coder.sh:1823` calls the
   classifier before `release_lock`; `leadv2-dispatch-product-close.sh`'s
   `review_gate` decisions start at line 365, in a wholly separate script
   invoked later against the SAME run_dir). So a gate verdict cannot exist at
   classification time in the current pipeline — this hook is a forward-
   compatible seam, not a claim that verdicts flow into the classifier today.
   I did not invent a caller for it because doing so would mean editing
   `leadv2-dispatch-product-close.sh`, which is off-limits.

2. **`_resolve_work` returns `yes|no|unknown`**, not `yes|no`. The two cases
   where the git probe literally cannot run (`cwd` unset/missing directory, or
   the directory is not a git tree) now report `unknown` instead of defaulting
   to `no` — the old default silently turned "I could not check" into "there is
   no work," which is exactly the throw-away failure mode named in the brief.

3. **Decision table**: verdict → bound(+work, `unknown`-aware) → wording(last
   resort, gated on `WORK != unknown` AND `WORK != "yes"`) → `.no-deliverable`
   (+work, `unknown`-aware) → clean exit → fallback (+work, `unknown`-aware).
   `NEXT` mapping unchanged except the default arm now explicitly documents that
   `unknown` (and `completed`) both map to `next=none`, never `respawn` — an
   undetermined lane is never auto-discarded.

### `lib/leadv2-parked-detect.sh`

Not modified. I considered gating inside the probe itself, but the probe's job
(recognize "standing by" prose) is legitimate and unrelated to whether it should
be *consulted* — that decision belongs to the caller, which is where I put the
subordination guard (`leadv2-lane-outcome.sh:214-220`). Declaring this file in
`LANE_WRITES` but leaving it unedited is intentional, not an oversight.

## 3. Mutation controls (baseline_rc / mutated_rc / restored_rc)

Tool: `plugins/leadv2/scripts/leadv2-mutation-control.sh` (sed anchors applied to a
scratch copy; suite = `test-lane-outcome-reads-state.sh`).

### Control A — verdict subordination (`VERDICT="$(_resolve_verdict || true)"` at
line 185, forced to `VERDICT=""`)

```
suite=plugins/leadv2/scripts/tests/test-lane-outcome-reads-state.sh
file=plugins/leadv2/scripts/leadv2-lane-outcome.sh
anchor=185s/.*/VERDICT=""/
baseline_rc=0
mutated_rc=1
restored_rc=0   (tool restores the scratch copy on exit; live file untouched throughout)
red_line=FAIL: case_verdict_outranks_bound -- outcome=died-with-work, expected completed
```
Exactly one red, and it is the case named for this branch (`case_verdict_outranks_bound`).

### Control B — wording subordination (PARKED guard at line 217, `&& "${WORK}" !=
"yes"` stripped)

```
suite=plugins/leadv2/scripts/tests/test-lane-outcome-reads-state.sh
file=plugins/leadv2/scripts/leadv2-lane-outcome.sh
anchor=217s/&& "${WORK}" != "yes" //
baseline_rc=0
mutated_rc=1
restored_rc=0
red_line=FAIL: case_work_yes_never_downgraded_by_wording -- wording overrode work=yes state -> parked
```
Exactly one red, matching name. Re-ran independently a second time (after the
e2e-control case was added) to confirm still exactly one red — same result.

### Control C — undetermined-work default (`echo unknown` at lines 139 and 143,
both forced back to `echo no`)

```
suite=plugins/leadv2/scripts/tests/test-lane-outcome-reads-state.sh
file=plugins/leadv2/scripts/leadv2-lane-outcome.sh
anchor=139s/echo unknown/echo no/;143s/echo unknown/echo no/
baseline_rc=0
mutated_rc=1
restored_rc=0
red_line=FAIL: case_undetermined_work_is_unknown_not_died_clean -- outcome=died-clean, expected unknown
```
**Two-red note (mission §3):** manually replicating this mutation and running the
full suite directly (bypassing the tool's single-line capture) also reddens
`case_unknown_work_never_auto_respawns`. This is the legitimate exception named in
the brief: both assertions exercise the SAME product line (the `_resolve_work`
default for an undeterminable probe) against the SAME fixture — one checks the
`outcome` field, the other checks the derived `next` field of that same decision.
They are not two independent branches; they are two observations of one branch. I
am reporting this explicitly rather than treating the tool's single captured
`red_line` as the whole truth.

## 4. Ten consecutive runs

```
$ for i in $(seq 1 10); do bash plugins/leadv2/scripts/tests/test-lane-outcome-reads-state.sh; echo "RUN$i rc=$?"; done
... (identical each time) ...
test-lane-outcome-reads-state: 7 passed, 0 failed
RUN1 rc=0
test-lane-outcome-reads-state: 7 passed, 0 failed
RUN2 rc=0
test-lane-outcome-reads-state: 7 passed, 0 failed
RUN3 rc=0
test-lane-outcome-reads-state: 7 passed, 0 failed
RUN4 rc=0
test-lane-outcome-reads-state: 7 passed, 0 failed
RUN5 rc=0
test-lane-outcome-reads-state: 7 passed, 0 failed
RUN6 rc=0
test-lane-outcome-reads-state: 7 passed, 0 failed
RUN7 rc=0
test-lane-outcome-reads-state: 7 passed, 0 failed
RUN8 rc=0
test-lane-outcome-reads-state: 7 passed, 0 failed
RUN9 rc=0
test-lane-outcome-reads-state: 7 passed, 0 failed
RUN10 rc=0
```
No disagreement across the ten runs.

## 5. Mandatory end-to-end control (brief §3)

`case_e2e_real_work_never_died_clean`: nonzero exit (a real failure, not a bound),
real uncommitted work on disk (`work_delta=yes` passed explicitly, matching how
`glm-coder.sh`/`kimi-coder.sh` actually call this script), and the worker's
`result.md` carries textbook died-clean-shaped prose ("No further action until it
finishes."). Asserted: outcome must NOT be `died-clean`. Result: `got=died-with-work`
— disk wins, PASS, on all 10 runs above.

## 6. Regression this change causes in a suite I cannot edit

`plugins/leadv2/scripts/tests/test-lane-outcome.sh` (NOT in my `LANE_WRITES`) has a
pre-existing `case_6_no_meta_no_throw` that asserts: no `cwd` in `meta.yaml`, nonzero
exit → `outcome=died-clean`, `next=respawn`. That is EXACTLY the disease this lane
was told to remove (mission §2 item 3: "A state that cannot be determined is
`unknown`, never a default... `died-clean` on an undetermined lane is how work is
thrown away."). With my fix, this same fixture now correctly reports `unknown`/`none`.

```
$ bash plugins/leadv2/scripts/tests/test-lane-outcome.sh
PASS: case_bash_n
PASS: case_1_bound_dirty_died_with_work
PASS: case_2_bound_clean_died_clean
PASS: case_3_completed
PASS: case_4_max_turns_json
PASS: case_5_malformed_journal_bound_none
FAIL: case_6_no_meta_no_throw -- outcome=unknown, expected died-clean
PASS: case_7_ahead_commits_died_with_work

test-lane-outcome: 7 passed, 1 failed
```

I did NOT edit `test-lane-outcome.sh` — it is outside my declared `LANE_WRITES`
(`plugins/leadv2/scripts/leadv2-lane-outcome.sh,
plugins/leadv2/scripts/lib/leadv2-parked-detect.sh,
plugins/leadv2/scripts/tests/test-lane-outcome-reads-state.sh,
docs/handoff/LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01/`). Weakening or
"fixing" that assertion is exactly the "never weaken a fixture to get green"
trap — it would be silencing the very defect this lane exists to remove.
Reporting it honestly instead: whoever owns `test-lane-outcome.sh` needs to
update `case_6`'s expectation from `died-clean`/`respawn` to `unknown`/`none`.

## 7. `bash -n` on every shell file changed

```
$ bash -n plugins/leadv2/scripts/leadv2-lane-outcome.sh; echo rc=$?
rc=0
$ bash -n plugins/leadv2/scripts/lib/leadv2-parked-detect.sh; echo rc=$?
rc=0
$ bash -n plugins/leadv2/scripts/tests/test-lane-outcome-reads-state.sh; echo rc=$?
rc=0
```

## 8. Diff and commit

```
$ git diff --name-only main...HEAD
plugins/leadv2/scripts/leadv2-lane-outcome.sh
plugins/leadv2/scripts/tests/test-lane-outcome-reads-state.sh
docs/handoff/LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01/mutation-control/...
docs/handoff/dispatch-9e1f4297/developer.summary.md
docs/handoff/dispatch-9e1f4297/developer.full.md
```
(exact file list and commit sha appended below after the commit that lands this
work — see the final line of this section, filled in post-commit.)

`lib/leadv2-parked-detect.sh` is listed in `LANE_WRITES` but carries no diff —
declared, not touched, per §2 above.

COMMIT_SHA: <filled in below, see final-turn confirmation>

DELIVERABLE_COMPLETE
