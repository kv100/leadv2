# ESCALATION-OFFERS-DESTRUCTIVE-DEFAULTS-FOR-FINISHED-LANES-01 — report

## Root cause (why the escalation bypassed the existing veto)

The two-poll dead escalation in `leadv2-lanes-snapshot.sh` (~:1069–:1085) asks
`inspect`/`restart`/`abandon` for every row that survives the finished-veto
(LANE-LIVENESS-THREE-STATES-02, ~:899–:933). That veto had exactly one arm:
`_commit_age_s(s.get("worktree"))` against `_LANE_FINISHED_WINDOW_S`.

For the rows that produced the four 2026-09-04 escalations, `worktree` names
the MAIN checkout (`/Users/kostiantyn.vlasenko/Projects/leadv2`), not the lane's
own worktree — the worker's final commits live in
`.claude/worktrees/<LANE>/`, a different git dir. So the veto read the main
HEAD's age, which is routinely older than the 1800s window, and the finished
lane escalated anyway. The ladder already computes the correct answer for
exactly these rows — `finished_unlanded:<age>s`, source `deliverable`
(`leadv2-lane-liveness.sh` E4 rung: a fresh non-empty `*.full.md`/`*.summary.md`
under the lane's handoff dirs) — and the veto never consulted it.

Deterministic reproduction (pre-fix, scratch fixture: row `worktree` → repo with
HEAD aged 7200s, deliverable `report.full.md` mtime 600s, dead pid):

```
== LADDER VERDICT ==
{"lane": "ESCAL-MUTGATE-01", "verdict": "finished_unlanded:602s", "source": "deliverable", ...}
== SNAPSHOT POLL 1+2 (pre-fix) ==
row_present: False
== QUESTIONS ==
question: 'Task ESCAL-MUTGATE-01 corroborated dead: pid dead. Escalate.'
- label: restart
- label: abandon
```

(600s is deliberately between `LEADV2_LANE_FRESH_S`=120 and the finished window
1800: with a fresher deliverable the pre-existing LIES-01 freshness veto also
clears `reasons`, so the defect window is exactly 120s–1800s after the
deliverable lands — which is where all four real lanes sat.)

## Fix (one rule, one implementation)

Inside the SAME veto block, the ladder verdict is now consulted — the same
`lane_liveness_by_id` oracle Change 1b already uses, no second oracle, no
second window:

```python
_lv_row = lane_liveness_by_id.get(tid) or {}
_lv_verdict = str(_lv_row.get("verdict") or "")
_lv_source = str(_lv_row.get("source") or "")
if _lv_verdict.startswith("finished") and _lv_source != "git_commit":
    reasons = []
```

A lane whose ladder verdict starts with `finished` escalates nothing (no
tombstone, no question — "prefer emitting nothing"). The `source != "git_commit"`
filter is what keeps this from being a duplicate of the commit-age arm: a
`source=git_commit` verdict is computed from the SAME session `worktree` the
arm above already reads, so consulting it would only mirror the arm and make
`test-lane-finished-state.sh` Test 5b's mutation (which kills that arm's line)
vacuous — the exact 10/10→9/10 regression the mission forbids. Test 5b stays
10/10 with the fix in place. The question text is unchanged, so the :1223
de-dup matcher stays consistent. Genuine deaths (no commit, no deliverable,
gone pid) still escalate exactly as before — `finished_unlanded` requires a
fresh non-empty deliverable.

## Negative control (the deliverable)

`plugins/leadv2/scripts/tests/test-finished-lane-no-escalation.sh`,
self-registered: `# run-all-triggers: leadv2-lanes-snapshot.sh` (selected by
`LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed`, 8 suites
total; `tests/run-all.sh` untouched).

- Test 1 baseline: finished lane (ladder `finished_unlanded:602s`, commit inside
  the window in the lane's OWN worktree, row `worktree` → stale main checkout,
  gone pid) → row kept, NO abandon/restart question.
- Test 2 mutation: REGEXP anchor
  `if _lv_verdict.startswith("finished") and _lv_source != "git_commit":`
  asserted to match exactly once, replaced in place by
  `if False:  # ESCALATION-...-01 mutation gate` → the finished lane is offered
  `inspect,restart,abandon` again → RED, asserted on the option labels offered,
  not wording.
- Test 3: revert restores no-escalation.
- Test 4: genuine death still escalates.

Artifact: `docs/handoff/ESCALATION-OFFERS-DESTRUCTIVE-DEFAULTS-FOR-FINISHED-LANES-01/mutation-control/mutation-control.txt`
(anchor=, anchor_matches=1, baseline_rc=0, mutated_rc=0, red_line=).

## Falsification set

- `bash -n` on both changed shell files: OK.
- `test-finished-lane-no-escalation.sh`: RESULTS: 4 passed, 0 failed.
- `test-lane-finished-state.sh`: RESULTS: 10 passed, 0 failed (Test 5b's
  mutation gate non-vacuous with the fix).
- `test-lane-liveness-lies.sh`: RESULTS: 4 passed, 0 failed.
- `test-lanes-snapshot.sh`: PASS=13 FAIL=0.
- Status-surface consumers (selected by changed-scope): see final report line.

## Test-harness notes discovered on the way

- The dead-escalation ask child (`leadv2-ask.sh` → `leadv2-state-path.sh`)
  resolves `LINK_ROOT` from `PROJECT_ROOT` only; a test that passes
  `LEADV2_PROJECT_ROOT`/`CLAUDE_PROJECT_DIR` but not `PROJECT_ROOT` gets a
  correct state-path ABORT (sandbox signal vs real repo) and the question file
  is never written — silently, because the snapshot swallows the ask's rc.
  The new suite threads `PROJECT_ROOT` explicitly (commented in
  `_snapshot_poll`). Pre-existing in `test-lane-finished-state.sh` Test 5b
  (it asserts on the prune, not the question), left as is — out of this lane's
  write set.
- `leadv2-lane-liveness.sh --all` drops tombstoned tids from `lanes`
  (~:1211); a suite phase that re-registers a pruned row must clear the stale
  tombstone or the ladder emits no row for the lane at all.
