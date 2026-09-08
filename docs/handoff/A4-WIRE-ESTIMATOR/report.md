# A4-WIRE-ESTIMATOR (P6b) — wire the complexity estimator into the depth gate

Commits: `d6b59ecd` (implementation + suite), `6a217acc` (mutation-control
artifacts), plus this report. LANE_WRITES respected:
`plugins/leadv2/scripts/leadv2-dispatch-code.sh` + the new suite. The estimator
(`lib/leadv2-complexity-estimate.py`) was NOT modified.

## What changed

1. **`_gate_depth_apply` (leadv2-dispatch-code.sh ~:4460)** — new params `<mission>
   <write-set-csv>`; when the task-judge estimate is NOT a real judge estimate
   (`estimate_source` != judge — the line-count fallback or nothing at all, ~100% of
   live traffic), the deterministic estimator is consulted over mission text + the
   caller-declared `--writes`. On-vocabulary output is taken at face value and
   labelled `complexity_source=estimate`.
2. **`COMPLEXITY_ESTIMATOR_BIN`** env seam (`LEADV2_COMPLEXITY_ESTIMATOR_BIN`),
   default the real lib path — mirrors `LEADV2_TASK_JUDGE_BIN`.
3. **`_admission_classify` call site** threads `mission` + `lane_writes` into the gate.
4. **Addendum fix**: the three re-arbitration descriptors — `_bf_desc`
   (bench-fallback), `_e76_desc` (exit76-continuation), `_adv_desc` (arm-advance) —
   now carry `complexity`/`duration_class`/`complexity_source` identical to the
   initial descriptor (`:8719` region).

## Addendum question 1 — what the judge is, and who wins

`complexity_source=judge` is **leadv2-task-judge.sh** (haiku model call with a
code-only fallback + sig8 cache), invoked twice per dispatch: by
`_admission_classify` (no `--class`) and by `_dispatch_complexity_estimate` (with
`--class`, feeding `DC_COMPLEXITY` → the arbiter descriptor). It emits
`estimate_source ∈ {judge, fallback}`; only `judge` is a real model verdict.

**Precedence wired: judge > estimate > deeper floor; flag raises over both.**
A judge estimate (conf 0.9, actually read the mission) is never clobbered — the
estimator is not even consulted when `src == judge` (suite S1d). They CAN disagree
(judge=complex vs estimator=trivial on a short mission with hot keywords); judge
wins because the estimator exists to fill exactly the slot the judge left degraded,
not to overrule it. `flag` stays raise-only and only a raise relabels the source
(S1e/S1f).

## Addendum question 2 — the dropped signal, and the fix

The second resolution is `cmd_resolve`'s bench-fallback block (`_bf_desc`,
ARM-BENCH-FALLBACK-GAP-01): after the quota precheck benches the primary arm, it
re-enters `route_arbiter` with a descriptor built from kind/size/arm_pool/
launchable/requested/task only. The arbiter's `SRC_CONF`/`req_eff` math
(leadv2-route-arbiter.sh:865-873) then saw no complexity → `complexity=unknown
conf=0.0 req_eff=3.0` — so the arm actually spawned was chosen under a LOWER effort
requirement than the judge had established seconds earlier. The fix threads
`DC_COMPLEXITY/DC_DURATION_CLASS/DC_COMPLEXITY_SOURCE` into all three
re-arbitration descriptors (same defect class at exit76 and arm-advance).

Note: wiring the estimator does NOT feed `estimate` into the arbiter descriptor —
the DC_* side keeps its own judge+floor provenance; the `estimate` source exists
only on the gate line. Out of scope by the mission's "feed the gate block" framing.

## Acceptance evidence (observable: log_line)

Harness: the REAL dispatcher loaded as a library (definitions above the CLI footer),
run inside a fixture repo (cd-before-source so FOREIGN-PROJECT-ROOT-GUARD-01 keeps
the fixture authoritative), real `_admission_classify` → real `emit decision`
journal, real `spawn_product_close` env handoff. Stubbed: task-judge binary
(returns the live fallback condition), close-gate binary. Same repo suite
convention as test-complexity-routing.sh ("fixture-only, never a live provider").
Live-lane proof (a real dispatch journal from the merged path) accumulates only
after merge — that residual is stated, not hidden.

Trivial task `A4WIRE01` (mission "Fix the typo in the README heading.", writes
`README.md`, judge at fallback):

    decision complexity_gate_applied task=A4WIRE01 complexity=trivial complexity_source=estimate pipeline_route=brief_direct forced_plan=0 review_rounds=1

    close-gate capture: LEADV2_DISPATCH_REVIEW_ROUNDS=1   (S3a)

Heavy task `A4WIRE02` (migration across 4 subsystems, judge at fallback):

    decision complexity_gate_applied task=A4WIRE02 complexity=complex complexity_source=estimate pipeline_route=plan_first forced_plan=0 review_rounds=3

    close-gate capture: LEADV2_DISPATCH_REVIEW_ROUNDS=3   (S3b)

One sample proves reachability, the opposite sample proves the branch is a branch.
Rounds=1 means the close gate's retry ceiling is 1 — one review round for the
trivial task, not two with one skipped (LEADV2_DISPATCH_REVIEW_ROUNDS is the
value leadv2-dispatch-product-close.sh resolves its ceiling from).

Bench-parity (addendum negative control, values on BOTH legs, through the REAL
route_arbiter): all four descriptor legs emit
`complexity=complex … complexity_source=judge conf=0.9 req_eff=4.0` (S4 ×4).

## Negative controls (mutation-control artifacts)

Artifacts: `docs/handoff/A4-WIRE-ESTIMATOR/mutation-control/2026-09-08T*.txt`
(3 files, committed). Runner: `leadv2-mutation-control.sh`, baseline green,
mutation applied in scratch, suite red:

- **ctl-1** (`20260908T161046Z-63510.txt`) — `eff="standard"` hardcoded inside
  `_gate_depth_apply`'s body → red:
  `FAIL: S1a trivial fixture: got [standard estimate plan_first 2], want trivial/estimate/brief_direct/1`
- **ctl-2** (`20260908T161145Z-16780.txt`) — missing estimate falls to
  `eff="${cx:-trivial}"` (shallow fall-through) → red:
  `FAIL: S1c no-signal fixture: got [unknown unknown brief_direct 3], want standard/*/plan_first/2`
- **ctl-3** (`20260908T161245Z-64742.txt`) — `_bf_desc` rebuilt with
  unknown/unknown/unknown instead of the DC_* triple → red with the live failure
  signature:
  `FAIL: S4 bench-fallback leg lost the signal: complexity=unknown complexity_source=unknown conf=0.0 req_eff=3.0`

## Falsification set (raw)

    bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh   -> rc=0
    bash -n plugins/leadv2/scripts/tests/test-depth-gate-uses-the-estimate.sh -> rc=0
    python files changed: 0 (py_compile N/A; estimator untouched)

Suite (self-registered, trigger map):

    LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | grep depth-gate
    -> leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-depth-gate-uses-the-estimate.sh

    bash plugins/leadv2/scripts/tests/test-depth-gate-uses-the-estimate.sh
    -> depth-gate-uses-the-estimate: pass=15 fail=0

Changed-scope sweep (`bash tests/run-all.sh --scope changed`): see final report
message — result recorded there when the run completed.

## Honest residuals

- "REAL dispatch" here = real dispatcher code path + real journal emit, stubbed
  model-facing binaries (judge, close gate). No live provider was spent from a
  worker lane; the first live trivial dispatch after merge is the final confirmation.
- The gate sees the CLI-declared `--writes`, not the prepass-derived write-set
  (admission runs before `_prepass_writes`). Declared intent is the honest input at
  that stage; noted, not fixed here.
- `complexity_source=estimate` is a new token on the gate line only; the arbiter's
  SRC_CONF has no `estimate` entry (never sees it — DC-side keeps judge/flag/
  heuristic/unknown).
