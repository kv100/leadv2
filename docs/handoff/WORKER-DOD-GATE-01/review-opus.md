LABEL=critic-dispatch-WORKER-DOD-GATE-01-review-1788351560 SESSION_ID=0e721b14-be3b-471c-9134-b19e76f1b913
--- body from: docs/handoff/dispatch-WORKER-DOD-GATE-01-review/critic.full.md ---
# critic — WORKER-DOD-GATE-01 review round 1 (EXHAUSTIVE)

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=1 high=3 medium=5 low=7

FINDING: severity=Critical file=plugins/leadv2/scripts/lib/leadv2-dod-gate.sh line=277 dimension=correctness desc=check (b) mutation sub-check binds diff_hash to review.diff, which is produced after the worker exits — no worker can ever satisfy it, so any brief with a paste+mutation line is permanently refused exit 7 at round 0
FINDING: severity=High file=plugins/leadv2/scripts/lib/leadv2-dod-gate.sh line=455 dimension=correctness desc=gate emits its cause ONLY via cat of out_md; neither call site mkdir -p's the out dir, so rc=1 with empty stdout yields review-gate.md reason=dod_unknown (the REVIEW-GATE-IS-MUTE-01 shape) — live-probed
FINDING: severity=High file=plugins/leadv2/scripts/lib/leadv2-dod-gate.sh line=44 dimension=correctness desc=fix-round-1 finding 1 only half-fixed — empty-file creation, 100%% rename and mode-only change of a runtime-state path emit no ---/+++ lines and still pass check (d) rc=0 (live-probed, 3 shapes)
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-helpers.sh line=77 dimension=correctness desc=_LEADV2_DOD_GATE_CONTRACT_MISSION has zero consumers repo-wide, so the gate hard-refuses rounds for a contract never delivered to any worker; the comment claiming it is consumed is false

---

## 0. Scope and method

Reviewed `/tmp/WORKER-DOD-GATE-01-review.diff` (1813 insertions across 10 files) plus
the live tree at base `5a5bbff6`. No `context.yaml` exists for this review task
(`docs/handoff/dispatch-WORKER-DOD-GATE-01-review/` contains only stream/session
artifacts), so `decisions`/`off_limits` were taken from the D-numbers quoted in
`docs/handoff/WORKER-DOD-GATE-01/report.md` itself.

Every finding below that asserts a runtime behaviour was produced by executing the
new code in this worktree. Probe transcripts are inline.

---

## 1. CRITICAL — check (b)'s mutation sub-check is structurally unsatisfiable on the production path

`lib/leadv2-dod-gate.sh:219,277`

```
219:  [[ -f "${diff_file}" ]] && diff_hash="$(_dod_sha256 "${diff_file}")"
277:              if _dod_valid_mutation_artifact "${f}" "${diff_hash}"; then
```

`_dod_valid_mutation_artifact` requires `diff_hash=` in the artifact to equal
sha256 of the `<diff_file>` argument. On the production call site that argument is
`${diff_file}`, i.e. `${HANDOFF}/review.diff`:

```
$ grep -n 'diff_file=' plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
1933:diff_file="${HANDOFF}/review.diff"          # inside pc_scope_diff(), line 1932
$ grep -n 'pc_scope_diff$' plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
2564:pc_scope_diff
$ grep -n '_DOD_TASK_DIR=' plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
2762:  _DOD_TASK_DIR="${ROOT}/docs/handoff/${FOUNDER_TASK_ID}"
```

`review.diff` is created by `pc_scope_diff` at line 2564 — after the worker arm has
been waited on and exited (the arm wait sits above, ~2506) — and the gate hashes it
at 2765. The worker therefore cannot compute the hash it is required to bind: the
bytes do not exist while the worker is alive, and they are not a plain
`git diff HEAD~1`, they are whatever `pc_scope_diff`'s base resolution plus
cross-repo concatenation produces.

The one helper the new script's own docstring points at as the way to obtain that
hash is private to the reviewer process:

```
$ grep -rn '_review_diff_hash' plugins/leadv2/scripts/*.sh plugins/leadv2/scripts/lib/*.sh
plugins/leadv2/scripts/leadv2-mutation-control.sh:21:#   _review_diff_hash() uses) — bound into the artifact so
plugins/leadv2/scripts/leadv2-review-run.sh:597:_review_diff_hash() { ... }
plugins/leadv2/scripts/leadv2-review-run.sh:1183:_review_diff_hash_raw="$(_review_diff_hash)"
```

`leadv2-mutation-control.sh:21` states "the caller already computed this via the same
`shasum -a 256` pattern `_review_diff_hash()` uses". There is no such caller: the
function is defined only inside `leadv2-review-run.sh`, which runs after the gate.
This unevidenced claim is what drives the 4th positional argument's whole design, so
it is blocking under the claims-without-evidence lens.

**Consequence.** Any task whose `brief.md` has a line matching `/paste/i` that also
matches `/mutation/i` fails `check=mutation_control_not_via_runner` → `lv2_dod_gate_run`
returns 1 → `exit 7` with `_stamp_review_terminal fail`. That is a terminal lane
state, not a retryable soft signal, and no worker action can clear it.

Measured against the live corpus — 8 of 44 tasks with a `brief.md` are refused on
this and on nothing else:

```
$ # full-gate run over docs/handoff/*/ with a benign diff (transcript in §2)
refused_ONLY_for_mutation_artifact=8
$ sed -n '33p' docs/handoff/BRAIN-CLASS-LIVE-01/brief.md
   the guard then enforces. Mutation negative control, RUN and paste red: make the judge call
$ sed -n '41p' docs/handoff/CACHE-TRUTH-01/brief.md
5. Mutation negative control, RUN and paste red: swap numerator to `cache_creation` → ratio case
```

Both briefs asked for exactly what the round-1 design intends and would still be
refused, because the brief says "RUN and paste red" (prose) while the gate demands a
file artifact bound to a hash computed after the worker is gone.

Note also that the author's own `rc=0` self-proof in `report.md` §"This gate against
this task's own diff+report.md" used a hand-built diff
(`git diff main HEAD -- plugins/leadv2/scripts tests/run-all.sh > /tmp/dodgate-report/round.diff`)
whose hash the author controlled — not `${HANDOFF}/review.diff`. The proof does not
exercise the production binding.

**Fix direction (not applied — review only).** Either (i) drop the round-diff binding
and bind the artifact to the lane's HEAD commit sha, which the worker does know at
commit time, or (ii) demote the mutation sub-check to `dod_note` (soft, like check (e))
until a hash the worker can compute exists, or (iii) have the lane write
`${HANDOFF}/review.diff.sha256` and re-run mutation-control lane-side after
`pc_scope_diff`.

---

## 2. HIGH — measured false-refusal rate: 30/44 (68%) of live handoff tasks

D4's stated acceptance was 0 false refusals for check (a) and ≤15% for check (b);
`report.md` tags that calibration `UNVERIFIED` (not re-run this round). Running the
gate as production calls it, over every `docs/handoff/*/` that has a `brief.md`, with
a benign non-violating diff:

```
$ D=$(mktemp); printf -- '--- a/plugins/leadv2/scripts/leadv2-helpers.sh\n+++ b/plugins/leadv2/scripts/leadv2-helpers.sh\n@@\n-x\n+y\n' > "$D"
$ for t in docs/handoff/*/; do [ -f "$t/brief.md" ] || continue
    bash plugins/leadv2/scripts/lib/leadv2-dod-gate.sh "$PWD" "${t%/}" "$D" "$O"; ... done
GATE-ON-REAL-CORPUS: briefs=44 refused_or_blocked=30
ARM-CAPABILITY-FROM-OUTCOMES-01     rc=1 dod_fail check=report_missing_or_unheaded detail=missing_file
BEAT-LOOP-ORPHANS-01                rc=1 dod_fail check=report_missing_or_unheaded detail=no_evidence_heading dod_fail check=paste_evidence_missing brief_line=37 dod_fail check=mutation_control_not_via_runner brief_line=37
BRAIN-CLASS-LIVE-01                 rc=1 dod_fail check=mutation_control_not_via_runner brief_line=33
CACHE-TRUTH-01                      rc=1 dod_fail check=mutation_control_not_via_runner brief_line=41
CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01 rc=1 dod_fail check=report_missing_or_unheaded detail=no_evidence_heading
CODEX-DIES-MID-TEST-01              rc=1 dod_fail check=report_missing_or_unheaded detail=no_evidence_heading
GLM-EFFICIENCY-01                   rc=1 ... 3x paste_evidence_missing
LAND-PATH-IS-BROKEN-01              rc=1 ... 3x paste_evidence_missing + mutation
LEAD-TURN-BUDGET-01                 rc=1 ... 4x
(14 more)
$ # breakdown
report_exists_but_no_evidence_heading=5  refused_ONLY_for_mutation_artifact=8
```

Two of the refused task ids (`GLM-EFFICIENCY-01`, `LAND-PATH-IS-BROKEN-01`) are live
sessions right now per this session's `LEADV2_ACTIVE_OTHER_SESSIONS` header, so
merging this diff refuses in-flight lanes, not just historical ones.

The 5 `no_evidence_heading` cases are unambiguous false refusals: `report.md` exists
and is committed, but its proof section is headed something other than a level-2/3
heading whose text contains "evidence" (`_dod_check_a` requires
`^#{2,3}[[:space:]].*evidence`, case-insensitive). A report headed `## Proof` or
`## What I ran` is substantively compliant and is still refused with `exit 7`.

`detail=missing_file` cases are defensible true positives in intent — but see §4:
no worker is ever told that `report.md` (as opposed to the protocol-mandated
`<role>.full.md`) is the required filename.

This is a product-invariant finding: the gate's purpose is to convert mechanical
misses into a cheap refusal, and at a 68% refusal rate on the existing population it
converts compliant work into terminal lane failures instead.

---

## 3. HIGH — rc=1 with no cause (the REVIEW-GATE-IS-MUTE-01 shape)

`lib/leadv2-dod-gate.sh:455`, call sites `leadv2-dispatch-product-close.sh:2762-2771`
and `leadv2-review-run.sh:1334-1336`.

`lv2_dod_gate_run` writes its check lines to `${out_md}` and then emits them to
stdout **only** by `cat "${out_md}"`. If the `mv`/`cp` both fail the code path is
`|| true`, `cat` fails silently, and the function still returns 1. Neither call site
creates the directory it points `out_md` into
(`${ROOT}/docs/handoff/${FOUNDER_TASK_ID}` is referenced at 2762 and nowhere
`mkdir -p`'d before the gate runs).

Live probe:

```
$ D=$(mktemp); printf -- '--- a/docs/leadv2/active.yaml\n+++ b/docs/leadv2/active.yaml\n@@\n-x\n+y\n' > "$D"
$ MISSING=$(mktemp -d)/no-such-task-dir
$ out="$(bash plugins/leadv2/scripts/lib/leadv2-dod-gate.sh "$PWD" "$MISSING" "$D" "$MISSING/dod-gate.md" 2>&1)"; rc=$?
rc=1  stdout_bytes=0  stdout=[]
$ echo "reason=[$(printf '%s\n' "$out" | sed -n 's/^dod_fail check=\([a-z_]*\).*/\1/p' | head -1)]"
reason=[]
```

Both call sites then write `reason: dod_${_dod_reason:-unknown}` → `reason: dod_unknown`
into `review-gate.md` with an empty body, and `emit decision review_gate ... reason=dod_unknown`.
That is precisely the defect already filed in this repo as
`REVIEW-GATE-IS-MUTE-01` ("arm rc=1 with no cause") — see commit `51af7b48`. The gate
built to remove mute refusals reintroduces one.

Fix direction: print the check lines to stdout unconditionally (tee, or `printf` the
accumulated `a_out..e_out` before the file write) and `mkdir -p "$(dirname "${out_md}")"`.

---

## 4. HIGH — check (d) census: the fix-round-1 deletion fix is one of four shapes

`lib/leadv2-dod-gate.sh:44-47`

```
44:_dod_diff_paths() { # <diff_file> -> stdout, one path per line, deduped
46:  { sed -n 's|^+++ b/||p' "$1" ...; sed -n 's|^--- a/||p' "$1" ...; } \
```

Round 1 found that a pure deletion escaped a `+++`-only parse; the fix unions the two
hunk-header sides. But three other git diff shapes emit **neither** `--- a/` nor
`+++ b/` at all. Confirmed against real `git diff` output first, then against the gate:

```
$ # shapes git actually produces
$ git diff --cached -M | grep -E '^(diff --git|new file|rename|---|\+\+\+|similarity)'
diff --git a/docs/leadv2/.newlock b/docs/leadv2/.newlock
new file mode 100644                          <-- empty-file add: no ---/+++ at all
diff --git a/docs/leadv2/active.yaml b/docs/leadv2/renamed.yaml
similarity index 100%
rename from docs/leadv2/active.yaml           <-- rename: no ---/+++ at all
rename to docs/leadv2/renamed.yaml
$ chmod +x docs/leadv2/active.yaml && git add -A && git diff --cached | head -3
diff --git a/docs/leadv2/active.yaml b/docs/leadv2/active.yaml
old mode 100644
new mode 100755                               <-- mode-only: no ---/+++ at all

$ # the gate against each shape
shape=new file mode 100644   -> rc=0
shape=similarity index 100%  -> rc=0
shape=old mode 100644        -> rc=0
```

So a lane can still (i) create an empty runtime-state file (`docs/leadv2/.bus.lock`,
`.merge.lock`, `.compact-freeze.md` — all plausible, and `.compact-freeze.md` is
untracked in this very worktree right now), (ii) `git mv` a runtime-state file out of
`docs/leadv2/`, or (iii) chmod one, and pass check (d) with `dod_pass`.

The robust source is the `diff --git a/X b/X` header plus `rename from|to`, which is
emitted for every change class including the three above. Parsing only hunk headers
cannot be made complete.

Same-shape census, per the census rule — every consumer of `_dod_diff_paths` inherits
the gap: `_dod_check_d` (line 313-ish, the runtime-state check) and
`_dod_diff_suite_paths` → `_dod_check_c` (line 59, suite registration). A test suite
added as an empty file, or moved by rename, is invisible to check (c) too.

No suite case covers any of the three shapes.

---

## 5. HIGH — the enforced contract is never delivered to the worker

`leadv2-helpers.sh:77` adds `_LEADV2_DOD_GATE_CONTRACT_MISSION` with the comment
"Consumed wherever a caller already concatenates the evidence-contract string into
worker mission text" and a `# shellcheck disable=SC2034  # consumed by
leadv2-dispatch-code.sh / coder-wrapper callers`. Both are false:

```
$ grep -rn '_LEADV2_DOD_GATE_CONTRACT_MISSION' plugins/leadv2/scripts/ | grep -v helpers.sh
(no output)
$ grep -rln '_LEADV2_EVIDENCE_CONTRACT_MISSION' plugins/leadv2/scripts/
plugins/leadv2/scripts/leadv2-dispatch-code.sh
plugins/leadv2/scripts/leadv2-helpers.sh
plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh
plugins/leadv2/scripts/tests/test-parked-worker-resume.sh
```

The sibling contract string it is modelled on **is** explicitly wired into
`leadv2-dispatch-code.sh`; this one is not wired anywhere. The mission text is
therefore dead, and the gate hard-refuses on three requirements the worker is never
told: the deliverable must be named `report.md` (the subagent protocol mandates
`<role>.summary.md` / `<role>.full.md`, never `report.md`), it must carry an
"evidence"-worded `##`/`###` heading, and a mutation claim must be a
`leadv2-mutation-control.sh` artifact rather than the pasted prose the briefs ask for.

Combined with §1 and §2 this is why the corpus refusal rate is 68%. A hard gate whose
predicate is never published to the party it judges is not a definition-of-done, it is
an ambush.

---

## 6. MEDIUM findings

**M1 — check (c) now hard-fails deletions and moves of unregistered suites.**
`lib/leadv2-dod-gate.sh:59` builds on the new two-sided `_dod_diff_paths`, so a
`test-*.sh` path that appears only on the `--- a/` side (deleted, or the old half of a
rename out of a non-self-selecting directory) is treated as "touched" and, having no
`EXTRA_SUITE_MAP` row, yields `dod_fail check=suite_unregistered` → `exit 7`.
Deleting a stray unregistered test file becomes impossible. The fix for finding 1 was
scoped to check (d) but changed check (c)'s input; no suite case covers it.

**M2 — the soft half of the feature is dead code.**
`grep -rn lv2_dod_retry_or_finalize plugins/leadv2/scripts/ | grep -v worker-epilogue.sh`
returns nothing, so `worker_dod=` is never written to any `progress.log`, so
`leadv2-lane-outcome.sh:190`'s new `DOD=` read and both new `dod=`/`outcome_dod:`
emission branches can never fire. `report.md` §"Not done" discloses the missing
wiring honestly, which is why this is Medium and not High — but the reviewer should
know that three of the ten touched files contribute nothing executable.

**M3 — `grep -m1` reads the wrong end of an append-only log.**
`leadv2-lane-outcome.sh:190` takes the **first** `^worker_dod=` line from
`progress.log`. `progress.log` is append-only and `lv2_dod_retry_or_finalize` appends;
if two verdicts are ever appended (retry then finalize, or two rounds sharing a run
dir) the stale first one wins. `... | tail -1` is the correct read.

**M4 — mutation-control's sed branch does not enforce the single-anchor property it
documents.** `leadv2-mutation-control.sh:133-152` claims "require the expression apply
exactly once by convention … and detect a no-op as the anchor-absent signal". Only the
zero-match case is detected (`cmp -s` equality). A `s|foo|bar|` expression matching 40
lines passes, and the artifact records `anchor=` with no match count, so check (b)
accepts a mutation that changed the whole file. The exit-code doc block advertises
`anchor_count` as a real guard; it is a no-op guard.

**M5 — the run-all/falsifiability evidence in `report.md` is partially elided.**
The `--scope changed` transcript shows `... (core-offline shard output, ~30s+) ...` and
a bare `[exited with code 0]`, and asserts the two shard-3 failures are "pre-existing
reds unrelated to this task … not touched by this diff" with no probe on `main` to
establish that. The 27/27 line is pasted but not reproducible from what is shown.
Internal-system claim, so not blocking under the evidence contract, but it is the one
place the report asks to be believed rather than checked.

---

## 7. LOW findings

- **L1** `tests/test-worker-dod-gate.sh:401` passes `LEADV2_TARGET_ROOT_OVERRIDE=1`
  to `leadv2-mutation-control.sh`. No such variable exists in the new script or
  anywhere in the repo — a silent no-op implying a knob that does not exist (§6.5
  unrecognized-entity).
- **L2** The wiring test labels `LEADV2_REVIEW_ENGINE=''` as "unset (production
  default)"; empty-but-set is not unset. Harmless because the extracted block never
  reads the variable — which also means the assertion proves textual ordering (the sed
  anchor range) rather than runtime ordering.
- **L3** `lib/leadv2-dod-gate.sh:440` — `for rc in ...` is not `local`, so calling
  `lv2_dod_gate_run` from a sourced context clobbers the caller's `rc`. The suite
  survives only because every call is inside `$( )`.
- **L4** `_dod_report_sections`' awk uses both an ERE interval (`#{1,6}`) and a `\x01`
  escape. Verified working here (`awk version 20200816`), but macOS 12 and earlier ship
  `awk version 20070501`, which supports neither — the suite explicitly tests
  `/bin/bash` 3.2 compatibility while leaving this awk floor undocumented and untested.
- **L5** Both call sites hardcode `round=0` in the emitted
  `review_gate task=... round=0` decision even when the lane is on a later round.
- **L6** `leadv2-review-run.sh` calls `_review_state_write` in the rc=1 branch but not
  in the rc=2 (blocked) branch — asymmetric state update for two terminal outcomes.
- **L7** `--task-dir` is added to `leadv2-review-run.sh` but no caller passes it (the
  engine=1 invocation in `leadv2-dispatch-product-close.sh` is unchanged), so the
  defense-in-depth path always runs in `${HANDOFF}` fallback mode, where `brief.md`
  never exists and checks (a)/(b) always skip.

---

## 8. Lens-by-lens summary

**correctness** — §1 (unsatisfiable hash binding), §3 (mute rc), §4 (three unparsed
diff shapes), M1, M3.

**tests-can-fail (falsification)** — the suite is genuinely red-capable: every hard
check has a red+green pair, `lv2_dod_gate_run` has both polarities, mutation-control
has all four exit codes, and the wiring harness fails loudly if the anchors are
reordered (END_LINE < START_LINE yields an empty block, `REACHED_ENGINE_SPLIT` prints,
rc=0, assertion fails). Gaps: no case for the production `diff_hash` binding (§1), none
for the three diff shapes in §4, none for the mute-rc path in §3, none for M1's
deletion-of-unregistered-suite refusal, none for a non-numeric/negative `mutated_rc`.
The suite passing 27/27 is consistent with all four blocking findings, which is the
falsification lens's verdict on it: green here does not discriminate the failure modes
that matter.

**product-invariant/contract** — §2 (68% of the live corpus refused, against a D4
budget of 0%/15%), §5 (predicate never published to the worker), and the
`exit 7 → _stamp_review_terminal fail` choice: a mechanical DoD miss is made terminal
rather than retryable, so a false positive is unrecoverable without human intervention.

**census** — the `+++`-only parse shape was enumerated exhaustively (empty add,
rename, mode change) and traced to both consumers (`_dod_check_d`,
`_dod_diff_suite_paths` → `_dod_check_c`). The unwired-contract-string shape was
checked against its sibling (`_LEADV2_EVIDENCE_CONTRACT_MISSION`, which is wired). The
`grep -m1`-on-append-only-log shape appears once (`leadv2-lane-outcome.sh:190`). The
mute-rc shape appears once in the library and is amplified by both call sites.
`MUTATION-CONTROL` sentinel prefix is inconsistent in three places
(`leadv2-mutation-control.sh:84,96,103` print a lowercase `leadv2-mutation-control:`
prefix for `snapshot_failed` / `scratch_git_init_failed` / `snapshot_missing_target`,
while lines 118+ print the documented `MUTATION-CONTROL` prefix) — a caller grepping
the documented sentinel misses the first three.

**claims-without-evidence** — enumerated every external/factual claim in the diff and
report:
| claim | location | verdict |
|---|---|---|
| "the caller already computed this via the same shasum pattern `_review_diff_hash()` uses" | mutation-control.sh:21 | **untagged, false, drives the interface** → folded into §1 (BLOCKING) |
| "Consumed wherever a caller already concatenates the evidence-contract string" | helpers.sh:64-72 comment | **untagged, false** → §5 (BLOCKING) |
| 37-report calibration corpus (D4 targets) | report.md §check (a)/(b) calibration | correctly tagged `UNVERIFIED:` → MEDIUM cap; live measurement contradicts it (§2) |
| shard-3 failures are pre-existing reds from main | report.md §run-all | untagged, internal-system, no probe on main → M5 |
| `LEADV2_REVIEW_ENGINE` production default is 0 | dispatch comment + report | verifiable in-repo, matches the pre-existing ONE-PATH-EVERYWHERE-01 comment → OK |
| `git archive HEAD` is committed-only; `git ls-files -co` includes untracked | mutation-control.sh:12-16, report | local-tool behaviour, correct, exercised by the suite → OK |
| "`git worktree add` registers in .git/worktrees" rationale | mutation-control.sh:29 | local-tool, correct → OK |
No provider/API/rate-limit claims appear in the diff.

## 9. What is right

Worth stating, because it is most of the diff: the gate placement before the
`LEADV2_REVIEW_ENGINE` split is correct and is the right answer to the v1 CRITICAL;
`pc_scope_diff` at 2564 guarantees `diff_file` is set before the gate at 2753, so
there is no `set -u` unbound-variable hazard; the `trap '_pc_exit_handler' EXIT` at
line 292 means `exit 7` does not leak locks; rc=2 "undetermined, never a silent pass"
is modelled consistently across all four hard checks; check (e) really is report-only;
`EXTRA_SUITE_MAP` duplicate keys do both fire (`tests/run-all.sh:367-372` iterates
every row and `add_suite`s each match), so the new `leadv2-worker-epilogue.sh` row does
not displace the existing one; and `_dod_report_sections`' space-joining fix for the
`read`-stops-at-LF bug is correctly reasoned and correctly implemented.

DELIVERABLE_COMPLETE
