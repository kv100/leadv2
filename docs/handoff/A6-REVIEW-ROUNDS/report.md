# A6-REVIEW-ROUNDS — report

Row A6 of `PRE-WAVES-PLAN.md`: *does review actually run N rounds scaled by
complexity, or does it run one?* Measurement round first; the answer changed
the shape of the work: the scaling mechanism EXISTS on the live path (landed
2026-09-07 as GATE-DEPTH-MUST-SCALE-WITH-COMPLEXITY-01 §2), so this lane
measured it from real journals, found one real defect in the only lane that
ever exercised it, fixed that defect inside the close gate, and pinned all
of it with a registered suite + two mutation controls.

## The three questions, answered from measurement

**Q1 — where is the round number decided?** It is derived, not constant:
`plugins/leadv2/scripts/leadv2-dispatch-code.sh:4655-4659` maps effective
complexity to rounds (`trivial|simple -> 1`, `standard -> 2`, `else -> 3`),
where the effective complexity is resolved judge -> estimator -> flag with a
§3 standard floor for unknown provenance (`:4641-4649`). The decision is
journaled at `:4838` as `complexity_gate_applied task=… complexity=…
complexity_source=… review_rounds=N`, and threaded to the close gate at
`:6072` as `LEADV2_DISPATCH_REVIEW_ROUNDS`, where
`_pc_review_round_ceiling` (`leadv2-dispatch-product-close.sh:1969`) resolves
it (env -> journal -> §3 default 2) and `_pc_review_round_retry`
(`:2005`) spends it on `selfcheck_failed` verdicts — a CONTENT verdict gets a
rebuild round via advance-arm before any terminal refusal (`:3204` region).
Note the separate engine-side cap in `leadv2-review-run.sh`
(REVIEW-ROUNDCAP-01, `LEADV2_REVIEW_MAX_ROUNDS` default 2) caps attempts
inside ONE review invocation; the complexity-scaled budget is the close-gate
one, and that is what A6 is about.

**Q2 — does the number change with complexity?** Yes, in real journals, not
just in code. Across all live journals (`~/.claude/leadv2-state/*/tasks/`,
read 2026-09-09): **50 lanes journaled `complexity=standard …
review_rounds=2` and 23 lanes `complexity=complex … review_rounds=3`**,
including the day-one Heavy lane:

```
- 2026-09-08T23:17:25Z [decision] complexity_gate_applied task=d6cd245f complexity=complex complexity_source=flag pipeline_route=plan_first forced_plan=0 review_rounds=3
```

(`d6cd245f` is the `class=Heavy class_source=escalated` lane the lead
quoted; the flag floor raised it to complex -> 3.) The `trivial|simple -> 1`
branch has **zero live instances** — no dispatch has ever resolved below
standard — so that half of the scale is pinned by the suite instead (see
`default_is_named` + mutation M1).

**Q3 — does a finding lead to another round?** Yes — exactly one live lane
has ever exercised the loop, and it did hand off a rebuild round:
persona-engine `dispatch-2f652446` (2026-09-08), round 1 selfcheck verdict
`selfcheck_failed failed=falsification:…test-codex-config-prune.sh:test_failed`
was followed by `review_round_retry task=2f652446 round=1 ceiling=3 …` and a
re-dispatched worker. But that lane also exposes the defect:

```
- 2026-09-08T01:16:25Z [decision] review_round_retry task=2f652446 round=1 ceiling=3 reason=selfcheck_failed failed=falsification:plugins/leadv2/scripts/tests/test-codex-config-prune.sh:test_failed
- 2026-09-08T01:19:02Z [decision] review_round_exhausted task=2f652446 round=2 ceiling=2 reason=selfcheck_failed
```

**The ceiling shrank 3 -> 2 mid-lane, silently.** Root cause, all measured:
the dispatcher journaled `complexity_gate_applied … review_rounds=3` into the
*leadv2* project journal and threaded `LEADV2_DISPATCH_REVIEW_ROUNDS=3` to
the INITIAL close gate only (`:6072` is its single threading site); the
advance-arm successor close gate ran with no env, and its journal fallback
read the *persona-engine* journal, which has no `complexity_gate_applied`
line at all (15 lines, `route_v2_estimate` … `dispatch_terminal_dedup`) — so
round 2 resolved the §3 default 2 and a complex lane exhausted its budget a
round early, with no journal line naming why 2. That is exactly the A6
disease: a number nobody can audit, silently degrading.

## The fix (LANE_WRITES: `leadv2-dispatch-product-close.sh` only)

Two properties added to the close gate, both visible in the journal:

1. **STICKY** — `_pc_review_round_ceiling` (`:1969`) now reads
   `${HANDOFF}/.review-round-ceiling` FIRST. `_pc_review_round_retry` pins
   the marker write-once on first resolution, BEFORE the exhaustion check
   (`:2010-2019`), so every successor close gate — advance-arm handoff,
   respawn — inherits the same number whatever env or journal it sees. The
   budget can no longer change mid-lane in either direction (the suite's
   `sticky_wins` case pins the "conflicting env cannot move it" direction
   too).
2. **NAMED** — every `review_round_retry` / `review_round_exhausted` /
   `review_round_retry_failed` line now carries
   `ceiling_source=marker|env|journal|default`. A §3 default is a named
   outcome, never an unremarked number, and after the sticky marker it can
   only ever be resolved by a lane's FIRST close gate.

`_pc_review_round_ceiling` now sets globals `_PC_CEILING`/`_PC_CEILING_SRC`
instead of printing stdout (a `$( )` subshell would drop the source before
it reaches the journal line). The kill switch
(`LEADV2_REVIEW_ROUND_RETRY=0`) and the infra-verdict single-pass semantics
are byte-identical to before.

## The suite

`plugins/leadv2/tests/test-review-rounds-scale-with-complexity.sh`
(`# run-all-triggers: leadv2-dispatch-product-close`) extracts the two REAL
functions byte-for-byte from the live script at run time (loud FATAL on a
renamed/moved function — it cannot drift green past a refactor) and drives
them with stubbed emit/journal/dispatcher bins. Seven cases:

| case | pins |
|---|---|
| `env_scale_complex` | complex(3) round-1 finding -> round-2 advance-arm handoff, `ceiling_source=env`, marker pinned |
| `successor_keeps_ceiling` | **the 2f652446 replay**: env-less successor with marker 3 keeps ceiling 3 (pre-fix: the 3->2 shrink) |
| `journal_source` | journal `complexity_gate_applied … review_rounds=3` resolves 3, named `journal` |
| `default_is_named` | underivable budget degrades loudly: `ceiling=2 ceiling_source=default` |
| `exhausted_at_ceiling` | complex lane ends at round 3 of 3, loudly |
| `kill_switch` | pre-gate single-pass refusal preserved, nothing pinned |
| `sticky_wins` | pinned 3 beats a later conflicting env 2 |

**Registration proof** (suite staged before running, per C5b tracked
admission):

```
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | grep review-rounds-scale
857:leadv2-dispatch-product-close:plugins/leadv2/tests/test-review-rounds-scale-with-complexity.sh
```

## Negative controls (E2E-KILLRATE-01) — both run, both red

Declared in the suite header, applied by `leadv2-mutation-control.sh` to
lines INSIDE function bodies. The current artifacts below are force-added
past the `docs/handoff/*/*` blanket ignore:

```
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/tests/test-review-rounds-scale-with-complexity.sh \
    plugins/leadv2/scripts/leadv2-dispatch-product-close.sh \
    's|return 0  # a6-mut-1: forced-collapse anchor.*|_PC_CEILING=1|' \
    docs/handoff/A6-REVIEW-ROUNDS
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=0
MUTATION-CONTROL ok suite=plugins/leadv2/tests/test-review-rounds-scale-with-complexity.sh file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh red_line=  FAIL: env_scale_complex: rc=1, expected handed-off rc0 diff_hash=fee3ceab7881d2d97f8f11460acefdc47b0710bebaa8a4676930dc8ece813771 lane_diff_hash=2624046ad9806cc5d4d0de2510442800e982b9abb3fb756bc8f7f65b8a89c291
control-1 exit=0
```

- **M1 `a6-mut-1`** (force the ceiling to 1 regardless of complexity — the
  row's symptom) — artifact `mutation-control/20260909T010207Z-99508.txt`:
  baseline_rc=0, mutated_rc=1, suite RED (`FAIL: env_scale_complex: rc=1,
  expected handed-off rc0`).
- **M2 `a6-mut-2`** (`if (( round >= ceiling ))` -> `>= 0` — the follow-up
  round unreachable, a round-1 finding terminating like a clean lane) —
  artifact `mutation-control/20260909T010244Z-11207.txt`: baseline_rc=0,
  mutated_rc=1, suite RED (same first red line). Both artifacts carry
  `lane_diff_hash=29571dc5…`, binding them to the committed code plus this
  report before the artifact paths themselves were added.

## Falsification set

`bash -n` on both changed shell files (the only changed code files; no
Python changed, so `py_compile` is vacuous):

```
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-product-close.sh && echo ok
ok
$ bash -n plugins/leadv2/tests/test-review-rounds-scale-with-complexity.sh && echo ok
ok
```

Suite **red on the pre-fix tree** (symptom first — `successor_keeps_ceiling`
is the measured shrink, verbatim):

```
  FAIL: env_scale_complex: decision line missing ceiling=3 or ceiling_source=env: decision review_round_retry task=a6case01ab01 round=1 ceiling=3 reason=selfcheck_failed failed=falsification:suite/red:test_failed
  FAIL: successor_keeps_ceiling: rc=1 — ceiling collapsed (the measured 3->2 shrink is back)
  FAIL: journal_source: expected ceiling=3 ceiling_source=journal, got: decision review_round_retry task=a6case03ab01 round=1 ceiling=3 reason=selfcheck_failed failed=falsification:suite/red:test_failed
  FAIL: default_is_named: default ceiling not NAMED: decision review_round_exhausted task=a6case04ab01 round=2 ceiling=2 reason=selfcheck_failed
  FAIL: exhausted_at_ceiling: expected round=3 ceiling=3 ceiling_source=marker, got: decision review_round_exhausted task=a6case05ab01 round=3 ceiling=2 reason=selfcheck_failed
  ok: kill_switch: single-pass refusal preserved, no budget pinned
  FAIL: sticky_wins: rc=1, expected handoff at pinned 3
pass=1 fail=6
SUITE RED
```

Suite **green post-fix**:

```
  ok: env_scale_complex: complex(3) round-1 finding -> round-2 handoff, ceiling_source=env
  ok: successor_keeps_ceiling: env-less successor keeps ceiling=3 via marker
  ok: journal_source: complexity_gate_applied line resolves ceiling=3, named
  ok: default_is_named: underivable budget degrades loudly (ceiling=2 ceiling_source=default)
  ok: exhausted_at_ceiling: complex lane ends at round 3 of 3, loudly
  ok: kill_switch: single-pass refusal preserved, no budget pinned
  ok: sticky_wins: pinned ceiling 3 beats conflicting env 2
pass=7 fail=0
SUITE GREEN
```

Changed-scope runner (`bash tests/run-all.sh --scope changed`) exited 0. Its
raw stdout was unusually sparse, so selection was also independently dumped
from the exact delegated runner; it selected the new A6 suite (51 of 95
suites) from `main@2062d2ed22` with 2 changed code files and no unmapped
files.

## run-all --scope changed verdict

(RUN_ALL_VERDICT)

```
$ timeout 600 bash tests/run-all.sh --scope changed
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/A6-REVIEW-ROUNDS/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh

$ timeout 300 env LEADV2_CORE_OFFLINE_SCOPE_DUMP=1 bash plugins/leadv2/scripts/tests/run-core-offline.sh --scope changed
[CORE-OFFLINE] scope=changed running 51 of 95 suites (base=main@2062d2ed22, 2 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=51 total=95 base=main@2062d2ed22 changed=2 unmapped=0 verdict=selected reason=-
[CORE-OFFLINE] SCOPE_SELECTED plugins/leadv2/tests/test-review-rounds-scale-with-complexity.sh
```

The deterministic pre-review gate passed the two applicable mechanical
checks. Its report/paste checks were skipped because no machine-readable task
brief is present under this lane's handoff directory:

```
$ bash plugins/leadv2/scripts/lib/leadv2-dod-gate.sh "$PWD" "$PWD/docs/handoff/A6-REVIEW-ROUNDS" /tmp/a6-main-head.diff /tmp/a6-dod-gate.md
# dod-gate report — 2026-09-09T01:04:56Z

dod_skip check=report_not_required
dod_skip check=paste_not_required reason=no_brief
dod_pass check=suite_registration
dod_pass check=runtime_state
```

## Diff

The post-commit `main...HEAD` diffstat is recorded with the commit handoff.

## Row disposition

The premise "review runs one round" has expired — the scaling, the journal
line, and the retry loop all exist and fire on live lanes. What was real is
the silent 3->2 collapse in the only lane that ever consumed budget, plus
the absence of any `ceiling_source` in the decision lines. Both are fixed
and pinned. The `trivial|simple -> 1` branch remains unexercised by real
traffic (zero instances) — it is now guarded by the suite, but the first
live trivial dispatch is still the real proof.
