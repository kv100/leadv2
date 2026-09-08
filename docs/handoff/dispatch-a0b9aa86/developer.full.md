verdict: APPROVE
next_action: continue

# P6a — real complexity estimate (PHASES-ARE-NOT-SCALED-BY-COMPLEXITY-01, row f33ff575078f)

## What changed

New files only (per LANE_WRITES), both committed at `aa18b583` on branch `worktree-f33ff575078f`:

- `plugins/leadv2/scripts/lib/leadv2-complexity-estimate.py` — standalone estimator.
- `plugins/leadv2/scripts/tests/test-complexity-estimate-easy-half.sh` — its test suite.

`leadv2-dispatch-code.sh`, `lib/leadv2-route-arbiter.sh`, `lib/leadv2-glm-policy-resolve.py`,
`config/leadv2-routing.yaml`, `tests/run-all.sh` were **read only** (see next section for the
exact lines matched), never edited, per the mission's scope boundary.

## Vocabulary match — read before designing (mission requirement)

Read `leadv2-dispatch-code.sh:4290-4357` (`_gate_depth_apply`) and the `complexity_gate_applied`
emit at `:4536`. Confirmed live vocabulary:
- `complexity`: `trivial|simple|standard|complex` (off-vocab → `unknown`, §3 of that function).
- `complexity_source` (its `src`): `judge|flag|heuristic|unknown`.
- `pipeline_route`: `plan_first|brief_direct`.
- `review_rounds`: `1|2|3`.
- flag-floor table (Trivial/Light→simple, Standard→standard, Heavy/Strategic→complex) at `:4322-4330`.
- consumed in `leadv2-dispatch-product-close.sh:1906-1910` (review-round ceiling read from the
  journal line by regex).

My estimator's output uses the SAME complexity/pipeline_route/review_rounds vocabulary. For
`complexity_source` it emits `flag|estimate|unknown` — `estimate` is new vocabulary, explicitly
named in the mission text ("complexity_source=estimate with a reason a human can read"); it is
the missing INPUT part B's wiring will map into the existing `judge|flag|heuristic|unknown` set
(most naturally as a new recognized `esrc` value alongside `judge`/`fallback`). I did not touch
`_gate_depth_apply` to add that mapping — that edit lives in the held file.

## Design — three non-negotiable rules, how each is met

1. **Rank sources, log which one wins; flag is the exception.** `estimate(...)` picks exactly one
   of three resolvers per call — `_resolve_flag` (only when the caller passes `--flag` with a
   `--declared-class`, i.e. an explicit operator override), `_resolve_unknown` (no mission text and
   no write-set at all), `_resolve_estimate` (the normal path: computes a real score from mission
   text + write-set + subsystem count). `flag` only appears when the caller explicitly asks — not
   by default. Test (3) below asserts neither default fixture ever returns `complexity_source=flag`.

2. **Asymmetry, deeper never shallower.** `_resolve_unknown()` always returns `complexity=standard`
   → `pipeline_route=plan_first`, `review_rounds=2` — never `trivial`/`simple`/`brief_direct`/`1`,
   regardless of how little is known. This is its own dedicated rule (not an accident of thresholds)
   and its own test (test (4)).

3. **Easy half is reachable.** `_resolve_estimate()` on a genuinely trivial one-line-docs-edit
   fixture (short mission text, one file, one subsystem, containing "typo") scores negative and
   resolves to `trivial` → `brief_direct`/`review_rounds=1`. Proven end to end by test (1), not
   asserted from the implementation — see raw suite output below.

Scoring (`_resolve_estimate`): `score = 0.5*min(files,10) + 4*max(subsystems-1,0) + text-length
bonus (+1 >1200 chars, +3 >3000) + 3 if a COMPLEX_KEYWORDS hit - 2 if a TRIVIAL_KEYWORDS hit`;
thresholds `<=0 trivial, <=2 simple, <=6 standard, else complex`. Subsystem count is the number of
distinct write-set top-level path segments (or an explicit `--subsystem-count` override).

## Self-check (falsification set, raw output)

```
$ bash -n plugins/leadv2/scripts/tests/test-complexity-estimate-easy-half.sh
(no output — OK)
$ /bin/bash --version | head -1
GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)
$ /bin/bash -n plugins/leadv2/scripts/tests/test-complexity-estimate-easy-half.sh
(no output — OK, verified against real bash 3.2, not just the newer bash on PATH)
$ python3 -m py_compile plugins/leadv2/scripts/lib/leadv2-complexity-estimate.py
(no output — OK)
```

## Suite output — baseline (green)

```
$ bash plugins/leadv2/scripts/tests/test-complexity-estimate-easy-half.sh
PASS: trivial mission resolves brief_direct/review_rounds=1 (easy half is reachable): complexity=trivial complexity_source=estimate pipeline_route=brief_direct review_rounds=1 reason="score=-1.5 files=1 subsystems=1 text_len=46 complex_kw=- trivial_kw=typo"
PASS: heavy multi-subsystem mission resolves plan_first/review_rounds=3: complexity=complex complexity_source=estimate pipeline_route=plan_first review_rounds=3 reason="score=18.5 files=5 subsystems=4 text_len=1719 complex_kw=migration trivial_kw=-"
PASS: complexity_source is not flag by default for either fixture
PASS: no-signal input resolves deeper (standard/plan_first), never brief_direct: complexity=standard complexity_source=unknown pipeline_route=plan_first review_rounds=2 reason="no mission text or write-set given; nothing to estimate from, deeper floor applied"
PASS: explicit operator override still reaches complexity_source=flag: complexity=complex complexity_source=flag pipeline_route=plan_first review_rounds=3 reason="operator declared class='Heavy' (explicit override)"
SUMMARY: pass=5 fail=0
EXIT=0
```

Acceptance criterion satisfied literally: trivial mission → `pipeline_route=brief_direct
review_rounds=1 complexity_source=estimate` (not `flag`); heavy multi-subsystem mission →
`pipeline_route=plan_first review_rounds=3`.

## Negative controls (E2E-KILLRATE-01) — run via `leadv2-mutation-control.sh`, not asserted prose

Both mutations inserted **inside** the function body they target, exactly as required. Ran via the
repo's own `plugins/leadv2/scripts/leadv2-mutation-control.sh` against the committed lane
(`aa18b583`) — its own artifacts are the proof, not my prose claim:

**Control 1 — force `brief_direct` inside route-selection (`_route_and_rounds`)**
```
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-complexity-estimate-easy-half.sh \
    plugins/leadv2/scripts/lib/leadv2-complexity-estimate.py \
    's/route = "plan_first"/route = "brief_direct"/' \
    docs/handoff/dispatch-a0b9aa86
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=0
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-complexity-estimate-easy-half.sh file=plugins/leadv2/scripts/lib/leadv2-complexity-estimate.py red_line=FAIL: heavy mission did not resolve deeper: complexity=complex complexity_source=estimate pipeline_route=brief_direct review_rounds=3 reason="score=18.5 files=5 subsystems=4 text_len=1719 complex_kw=migration trivial_kw=-" diff_hash=3977287a7df13952ebbfa39081985ec12c0c7f7101118a87aead68c016099904 lane_diff_hash=14130cb66fc0d92cb5119527bc65f831d500762493ab9d428d07763d07db0611
EXIT=0
```
`EXIT=0` from the tool means "mutation applied, suite went red as required" (its own docstring:
exit 1 = mutant survived). Artifact: `docs/handoff/dispatch-a0b9aa86/mutation-control/20260907T203037Z-4026.txt`.
Note this mutation forces `brief_direct` universally, so the trivial-fixture assertion (test 1)
still passes — it is specifically the complex-fixture assertion (test 2) that catches it, which is
why the suite asserts BOTH ends rather than only the constant `plan_first` row.

**Control 2 — force `complexity_source=flag` inside the source-ranking return (`estimate`)**
```
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-complexity-estimate-easy-half.sh \
    plugins/leadv2/scripts/lib/leadv2-complexity-estimate.py \
    's/"complexity_source": source,/"complexity_source": "flag",/' \
    docs/handoff/dispatch-a0b9aa86
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=0
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-complexity-estimate-easy-half.sh file=plugins/leadv2/scripts/lib/leadv2-complexity-estimate.py red_line=FAIL: flag leaked into a default (non-override) verdict: trivial=complexity=trivial complexity_source=flag pipeline_route=brief_direct review_rounds=1 reason="score=-1.5 files=1 subsystems=1 text_len=46 complex_kw=- trivial_kw=typo" complex=complexity=complex complexity_source=flag pipeline_route=plan_first review_rounds=3 reason="score=18.5 files=5 subsystems=4 text_len=1719 complex_kw=migration trivial_kw=-" diff_hash=7e4c99b226614c566107d7ff8d46b0f421dcbd892da7990c329125fe4281f465 lane_diff_hash=14130cb66fc0d92cb5119527bc65f831d500762493ab9d428d07763d07db0611
EXIT=0
```
Artifact: `docs/handoff/dispatch-a0b9aa86/mutation-control/20260907T203059Z-17795.txt`. This
single-return-statement design (one `estimate()` return referencing a local `source` variable
computed by exactly one of three resolvers) is precisely what makes this one-line mutation cover
ALL three source paths at once — there is no per-branch literal to miss.

Both mutations left the committed working tree untouched (mutation-control.sh mutates a scratch
copy only); `git status` after both runs is clean except for the two new artifact files under
`docs/handoff/dispatch-a0b9aa86/mutation-control/`, which are deliverable-directory writes, not
lane code.

## DoD gate self-assessment

- (a) report.md: mission did not ask for one; not produced.
- (b) mutation-control claims: both backed by `leadv2-mutation-control.sh` artifacts (paths above),
  not asserted prose.
- (c) new suite registration: `test-complexity-estimate-easy-half.sh` self-registers via its own
  `# run-all-triggers: leadv2-complexity-estimate` header line (the SD-SUITE-MAP-SERIALIZES-EVERY-
  WAVE-01 convention, `tests/run-all.sh:145-212`) — **no edit to `tests/run-all.sh` was needed or
  made.** This means the suite already runs under `tests/run-all.sh` once a changed file's stem
  matches `leadv2-complexity-estimate` (e.g. this lib file itself changing) — self-registration is
  live today, not a part-B dependency.
- (d) runtime-state paths: diff touches only the two LANE_WRITES paths plus this task's own
  `docs/handoff/dispatch-a0b9aa86/*` deliverable files — no `docs/leadv2/`, no
  `docs/LEAD_V2_STATE.md`, no `docs/handoff/dispatch-nw*`.

## What I deliberately left alone (scope boundary, explicit per mission)

- `leadv2-dispatch-code.sh` (`_gate_depth_apply` / `complexity_gate_applied` emit) — not edited,
  read only, lines cited above.
- `lib/leadv2-route-arbiter.sh`, `lib/leadv2-glm-policy-resolve.py`, `config/leadv2-routing.yaml` —
  not touched at all (not even read; not needed for this estimator).
- `tests/run-all.sh` `EXTRA_SUITE_MAP` — **not added**, on purpose (mission instruction). Because
  self-registration already covers this suite (see (c) above), the exact row part B would otherwise
  need to add is: none — no `EXTRA_SUITE_MAP` row is required. What part B DOES still owe, stated
  plainly: **wiring `leadv2-complexity-estimate.py`'s verdict into `_gate_depth_apply`'s
  `estimate_json` input** (`leadv2-dispatch-code.sh:4306-4319` builds that JSON from
  `leadv2-task-judge.sh`'s `estimate_source=judge|fallback` output today; it never calls this new
  estimator). Until that wiring lands, `complexity_gate_applied` rows in production will keep
  reading `complexity_source=flag|heuristic` exactly as today — this file is the missing input,
  proven standalone, not yet connected to the live gate.

## Unverified

None — every claim above carries its raw command output or artifact path in this file.

DELIVERABLE_COMPLETE
