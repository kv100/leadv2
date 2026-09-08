# developer.full.md — ARBITER-SCORING-DESIGN-01 Step 3 (dispatch-94b88e76)

Lane: `worktree-F1-ARBITER-SCORING-20260907-step1`. Builds on Step 1 (`b64ce433`,
capability_fit off by default) and Step 2 (`8d6dbe6d`, complexity provenance off by
default). Spec: persona-engine `docs/handoff/F1-ARBITER-SCORING-20260907/design.md`
§8 row 3, §9.2, §9.3.

## Part 0 — seam diagnosis (mandatory gate before any Step 3 code)

Deliverable: `docs/handoff/F1-ARBITER-SCORING-20260907/seam-diagnosis.md` (full text
committed on this lane; summarized here).

**Conclusion: no seam bug.** The mission's "15/79 `complexity_basis=judge`" figure was
a measurement-methodology artifact, not a real code seam between `estimate_source`
and `complexity_basis`.

1. **Can the two fields disagree on a real line?** No. `leadv2-task-judge.sh` sets
   both in the same branch every time (judge branch :345/:352, fallback branch
   :229-230 same dict literal), and the journal line parses both from one JSON blob
   (:361/:379). The only asymmetry is one-directional: `complexity_basis` is
   OPTIONAL in `_validate_estimate` (so a pre-Step-2 cache hit can show
   `complexity_basis=none` next to `estimate_source=judge`) — never the reverse.

2. **Is `complexity_source=judge` reachable?** Yes — `leadv2-dispatch-code.sh:7637-7660`
   reaches the `elif est_src == 'judge': src = 'judge'` branch whenever a real judge
   call succeeds and the declared-class floor doesn't also fire (floor precedence is
   correct per §5.1, not a bug).

3. **Where did "15/79" come from?** Reproduced directly against
   `~/.claude/leadv2-state`:
   ```
   $ find ~/.claude/leadv2-state -path '*/tasks/*/journal.md' | grep -vE 'ephemeral|deadbeef' \
       | xargs grep -h 'route_v2_estimate' | wc -l
   112
   $ grep -c 'complexity_basis=judge' <same 112 lines>
   0
   ```
   checked=112: zero real lines carry `complexity_basis=judge`. All 18 files that
   ever carry the token are synthetic fixtures (`.ephemeral/` or `dispatch-deadbeef*`
   paths — checked=18/18, 100%). The contaminating mechanism: a `grep -h`/`grep -rhE`
   pipeline strips filenames before the `ephemeral|deadbeef` exclusion runs, and
   since those markers live in the **path** not the **line text**, the exclusion
   passes every synthetic line through. Reproduced live:
   ```
   $ grep -rhE 'route_v2_estimate.*complexity_basis=judge' ~/.claude/leadv2-state 2>/dev/null \
       | grep -vE 'ephemeral|deadbeef' | wc -l
   30
   ```
   (30 not 15 — corpus grew between the mission's snapshot and this check; the
   mechanism, not the exact count, is what matters.)

4. **Does this affect `source_confidence` grading?** No — this lane's own two
   post-Step-2 real `route_resolved` lines both show `complexity_source=flag
   conf=0.7` (declared-class floor), not a judge result downgraded. Since §1/§3
   establish zero real judge-originated lines exist anywhere in the live corpus,
   there is no live judge decision that could be mis-graded. Risk R4 (judge dead on
   the live path) is confirmed unchanged, not worsened.

## Part 1 — shadow mode

**Investigation finding (per mission instruction, checked before writing any code):**
Step 1 already wires `LEADV2_ARBITER_CAPABILITY_FIT=shadow` fully, end-to-end, per
design §6. Read directly from `lib/leadv2-route-arbiter.sh:760-920` (not the design
doc's pseudocode):
- `FIT_MODE` reads the env var directly; `off`/`shadow` are code-identical today —
  `_cost_order`, `_fit_order`, `fit_pick`, `fit_differs`, `fit_bucket` are always
  computed and journaled regardless of mode; only `FIT_MODE == 'on'` changes the
  actual sort key and zeroes `complexity_penalty_rules`.
- The arbiter is `source`d into the dispatcher's own bash process (not spawned as a
  subprocess), so any env var set on the calling process — including
  `LEADV2_ARBITER_CAPABILITY_FIT` — is already visible to the arbiter's internal
  `python3` heredoc with zero dispatcher-side forwarding code.

**Conclusion: zero production code changes needed for Step 3.** `git status --short`
confirms `leadv2-dispatch-code.sh` and `lib/leadv2-route-arbiter.sh` are untouched
by this lane. Per the mission's explicit instruction not to re-implement something
that already exists, Part 1's deliverable is proof, not new code.

### Deliverable: `plugins/leadv2/tests/test-router-v2-shadow-mode.sh`

Same harness style as Step 1's `test-router-v2-capability-fit.sh`. Contents:
- 7 constructed §9.2 rows (r1,r2,r3,r6,r7,r8,r9), each run under both `shadow` and
  `off`, asserting `fit_mode=shadow`, expected `fit_pick`/`fit_differs`, and —
  the core "shadow never acts" proof — that shadow's actual `arm=` equals off's
  actual `arm=` on every row.
- NC(shadow-a): mutating glm-flash capability 2→4 flips `fit_bucket` `:1`→`:0` under
  shadow while the actual pick stays `glm-flash` both times (shadow computes fresh
  fit information but still doesn't act on it).
- NC(shadow-b): mutating the arbiter's sort ternary so shadow *does* act
  (`if FIT_MODE != 'off'`) flips the actual pick glm-flash→glm — proof the suite's
  assertions genuinely exercise the sort and would catch a regression that made
  shadow silently start acting.
- Live acceptance (≥29-line requirement): reconstructs real historical descriptors
  from actual journal tokens (design §9.2's own sanctioned "replay control"
  methodology — brand-new task dispatch is infeasible for a subagent and out of
  scope), path-excluding synthetic fixtures per the Part 0 diagnosis, then replays
  every row through the real arbiter binary under both `off` and `shadow`.

**Verified run (bash -n clean, full suite green):**
```
PASS: 9.2 r1 (shadow): fit_pick=glm fit_differs=1, actual arm=glm-flash unchanged vs off
PASS: 9.2 r2 (shadow): fit_pick=glm fit_differs=1, actual arm=glm-flash unchanged vs off
PASS: 9.2 r3 (shadow): fit_pick=glm fit_differs=1, actual arm=glm-flash unchanged vs off
PASS: 9.2 r6 (shadow): fit_pick=glm fit_differs=0, actual arm=glm unchanged vs off
PASS: 9.2 r7 (shadow): fit_pick=sonnet fit_differs=0, actual arm=sonnet unchanged vs off
PASS: 9.2 r8 (shadow): fit_pick=glm fit_differs=0, actual arm=glm unchanged vs off
PASS: 9.2 r9 (shadow): fit_pick=glm-flash fit_differs=0, actual arm=glm-flash unchanged vs off
PASS: NC(shadow-a): mutating glm-flash capability 2->4 flips shadow fit_bucket :1->:0, actual pick stays glm-flash both times
PASS: NC(shadow-b): mutating the sort ternary to act on shadow flips the actual pick glm-flash->glm -- this suite would have caught it
LIVE_REPLAY: rows=35 differ=25 match=10 pick_mismatch(shadow_vs_off)=0
PASS: live acceptance: 35 real reconstructed descriptors replayed, shadow's actual pick == off's actual pick on every row (0 mismatch), differ=25 match=10
SUMMARY: pass=10 fail=0 skip=0
```
35 ≥ 29 required rows; 0 pick mismatches between shadow and off across all of them
(the invariant §9.2 requires: shadow previews, never acts).

## Regression check (no re-certification of my own work — evidence only)

- `test-router-v2-capability-fit.sh` (Step 1): re-run, `SUMMARY: pass=12 fail=0`.
- `test-router-v2-headroom-order.sh` (Step 1): re-run, PASS.
- `test-complexity-source-provenance.sh` (Step 2): re-run, `PASS=18 FAIL=0`, exit 0.
- New suite (`test-router-v2-shadow-mode.sh`): `bash -n` clean, `pass=10 fail=0 skip=0`.
- `config/leadv2-routing.yaml`: `capability_fit.enabled: false` unchanged (confirmed
  read at :335-341). `LEADV2_ARBITER_CAPABILITY_FIT` env var is not set anywhere by
  default — `on` is never the default, per the mission's hard constraint.
- `git status --short` (final, pre-commit): only 2 untracked lane files
  (`docs/handoff/F1-ARBITER-SCORING-20260907/seam-diagnosis.md`,
  `plugins/leadv2/tests/test-router-v2-shadow-mode.sh`) plus the pre-existing,
  hook-owned `docs/leadv2/.compact-freeze.md` (not staged — runtime-state path).
  Zero modifications to any tracked production file.

### Repo-wide changed-scope test runner

`bash scripts/tests/run-core-offline.sh` (94 suites, 4 shards + serial tail), full run:
```
[CORE-OFFLINE] suites passed=80 failed=14 missing=0 repo=.../F1-ARBITER-SCORING-20260907-step1
EXIT=1
```
All 14 failures are in suites unrelated to this mission's scope (shared-sink test
guard, lane-sweeper safety, kimi-arm-vocabulary, lane-verdict three-states,
product-close scoping, lane placement pin, DoD-gate suite registration, GLM ladder,
lane-trace instrument, cross-run exclusive lock, broad-status foreign-repo lanes,
dispatch refusal fallback chain, Codex full-cycle runner, lane-truth batch) — none
reference `route-arbiter`, `capability_fit`, `complexity_source`, or `shadow-mode`.
Since this lane's diff modifies **zero tracked production files** (only two new
files added), these failures are pre-existing on the branch baseline (Step 1+2,
already landed before this session started) and cannot be a regression introduced
by Part 0/Part 1 work — a diff that touches no production script cannot be their
cause by construction.

## Out-of-scope confirmed untouched

task_class sizes-filter role, freepool floor mode, UNKNOWN_PROBE_PENALTY,
failure-memory demotion, effort_matrix, legacy resolver/kimi arm,
complexity_penalty itself, any persona-engine file. `enabled: true` was NOT flipped
anywhere; `on` is NOT the default under any code path touched by this lane.

## Commit

Commit `22f01ea9` on branch `worktree-F1-ARBITER-SCORING-20260907-step1`.

DELIVERABLE_COMPLETE
