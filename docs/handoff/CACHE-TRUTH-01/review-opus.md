LABEL=critic-dispatch-CACHE-TRUTH-01-review-1788305091 SESSION_ID=c3f5e055-e508-4361-8954-e58a6371f984
--- body from: docs/handoff/dispatch-CACHE-TRUTH-01-review/critic.full.md ---
REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=3 medium=5 low=6
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-cache-truth.sh line=178 dimension=correctness desc=zero denominator prints a fabricated hit_ratio 0.0000 instead of unreported, violating the tool's own missing-is-not-zero invariant (probe: one reported turn with all-zero usage -> "unknown tmp 1 0 0 0 0.0000 none 1/1" rc=0)
FINDING: severity=High file=plugins/leadv2/scripts/tests/test-cache-truth.sh line=236 dimension=correctness desc=mutation controls 2 and 3 print "control proven red-capable" when their python assert fires and the mutant was never created (probe: perturbed anchor -> turns='' -> suite still PASS=16 FAIL=0)
FINDING: severity=High file=docs/LEAD_V2_STATE.md line=7 dimension=design desc=diff carries lead-owned and other-lane runtime files outside LANE_WRITES; applying it deletes 8 live lanes' active-session rows plus rewrites 6 phases.d yamls and 2 task journals

---

# Adversarial review — CACHE-TRUTH-01 / build-attempt-2.diff

Reviewer: critic (independent of author `glm`). Target: `docs/handoff/CACHE-TRUTH-01/build-attempt-2.diff`
(886 lines, 13 files, 746 insertions / 16 deletions). Base: worktree `.claude/worktrees/CACHE-TRUTH-01` @ a1a2a51.

`docs/handoff/dispatch-CACHE-TRUTH-01-review/context.yaml` does **not** exist (`cat` -> "No such file or
directory"), so there are no `decisions` / `off_limits` constraints to honour for this review; `brief.md`
was used as the authoritative spec.

## What is genuinely good (verified, not assumed)

These were re-run, not read:

- **Suite is green and fast.** `bash plugins/leadv2/scripts/tests/test-cache-truth.sh` -> `PASS=16 FAIL=0`
  in ~3.6s, inside the mission's 10s cap.
- **Every number in the report table reproduces byte-for-byte.** Running the committed tool against the
  real artifacts returned:
  ```
  claude-native  dispatch-c293c1d5           95  190  15070604  238676  0.9844  94  95/95
  freepool       260901-175619-repo-53e9     67    0         0       0  0.0000  none 1/67
  glm            260901-165920-...-53f1      38    0         0       0  unreported unreported 0/38
  ```
- **The de-dup claim is real.** `grep -c '"type":"assistant"'` on `dispatch-c293c1d5` = 176 raw events vs
  95 unique `message.id` -> the ~1.81x inflation the report describes is a fact, and the fix removes it.
- **`arm_for_path` matches reality.** All four run dirs exist under `~/.claude/cache/`, and
  `claude-subsession.sh:1215` sets `RUN_DIR="…/claude-runs/$RUN_ID"` — the case arms are correct, not guessed.
- **The core product invariant is honoured on the main path.** Fixture 3 (no cache keys) renders
  `unreported`; fixture 4 (keys present, genuinely 0) renders `0.0000`. That distinction is the point of
  the lane and it works.

The findings below are what survived trying to break it.

---

## HIGH

### H1 — a zero denominator prints a measured `0.0000` where the tool's own invariant demands `unreported`

`plugins/leadv2/scripts/leadv2-cache-truth.sh`, the overall-ratio computation:

```python
denom = total_in + total_cr + total_cc
overall_ratio = (total_cr / denom) if denom > 0 else 0.0
```

The per-turn break scan two lines below gets this right — `if d <= 0: continue` — but the overall ratio
coerces "no tokens at all" to a printed measurement.

**Probe (run, not reasoned):** a stream with exactly one turn whose `usage` carries the cache keys but all
zero values:

```
$ plugins/leadv2/scripts/leadv2-cache-truth.sh /tmp/zerodenom.jsonl
arm      run  turns input_tokens cache_read cache_creation hit_ratio first_break reported
unknown  tmp  1     0            0          0              0.0000    none        1/1
rc=0
```

`0.0000` here does not mean "0% cache hit rate". It means "there is nothing to divide". A reader — and the
report itself — cannot tell that apart from the freepool row, where `0.0000` *is* a real measurement. The
header of this very file states the invariant it breaks: a missing measurement must never be coerced to zero.

This is not hypothetical for the arms under test: a run whose reported turns are all zero-usage (an aborted
or empty request that still carried the keys) prints as a confidently-measured 0% cache hit. The report then
builds prose on exactly this kind of value ("a real 0.0000 for that one request").

Fix shape: `unreported` (or a distinct `nodata` sentinel) when `denom == 0`, matching the per-turn guard.

### H2 — two of the three mutation negative controls report success when they fail to run at all

`plugins/leadv2/scripts/tests/test-cache-truth.sh`, controls 2 (dedup) and 3 (per-turn classification),
identical shape:

```bash
python3 - "$TOOL" "$MUTANT_DEDUP" <<'PYEOF'
...
assert needle in text, "mutation anchor not found in tool source"
...
PYEOF
chmod +x "$MUTANT_DEDUP"
mutant_dedup_out="$("$MUTANT_DEDUP" "$DUP_DIR" 2>/dev/null | tail -1)"
mutant_dedup_turns="$(printf '%s\n' "$mutant_dedup_out" | awk -F'\t' '{print $3}')"
if [[ "$mutant_dedup_turns" == "2" ]]; then
  fail 'MUTATION CONTROL (dedup): ... not falsifiable'
else
  pass "MUTATION CONTROL (dedup): mutant reported turns='$mutant_dedup_turns' … control proven red-capable"
fi
```

The `needle` is a verbatim multi-line source excerpt **including an inline comment**. When the tool source
drifts by one character in that window, `assert` kills python, the mutant file is never written, `chmod`
fails silently (`set -u` without `set -e`, stderr discarded), the mutant invocation produces empty output,
`[[ "" == "2" ]]` is false — and the suite takes the `else` branch and prints *"control proven red-capable"*.

**Probe (run):** perturbing the anchor comment produced exactly that:

```
[TEST] PASS: MUTATION CONTROL (dedup): mutant reported turns='' (expected 5, not 2) — control proven red-capable
PASS=16 FAIL=0
```

A control that cannot detect its own non-execution is worse than no control: it is a green light that
asserts falsification capability while having asserted nothing. This is the same defect class the lane was
opened to eliminate, reproduced inside the lane's own falsification machinery.

**Census (rule applied — all same-shape instances in the touched files):**
- control 2 (dedup mutation) — affected.
- control 3 (per-turn classification / `reported_turns` mutation) — affected, byte-identical shape.
- control 1 (`sed`-based ratio mutation) — *not* affected, but only accidentally: `sed` with a
  non-matching pattern still emits a runnable file, so the mutant exists and misbehaves visibly. It is
  immune by luck of tooling, not by design.

Fix shape: assert the mutant differs from the original and is executable and produced parseable output,
before interpreting the comparison; and anchor on structure, not on a comment.

### H3 — the diff carries lead-owned and other-lane runtime files that are outside LANE_WRITES

`brief.md` declares LANE_WRITES as the tool, the four runner scripts, the new suite, `tests/run-all.sh`,
and `docs/handoff/CACHE-TRUTH-01/`. The diff also modifies:

| file | change | in LANE_WRITES |
|---|---|---|
| `docs/LEAD_V2_STATE.md` | −13: removes 8 active-session rows, rewrites "Sessions: 8 / 3 max" -> "1 / 3 max" | no — explicitly a file subagents must never write |
| `docs/handoff/dispatch-nw5sig005/phases.d/{e2e,review}.yaml` | `started_at` rewrites | no — another dispatch |
| `docs/handoff/dispatch-nw9sig009/phases.d/{e2e,review}.yaml` | `started_at` rewrites | no — another dispatch |
| `docs/handoff/dispatch-nwcm0012/phases.d/{e2e,review}.yaml` | `started_at` rewrites | no — another dispatch |
| `docs/leadv2/tasks/dispatch-567ba028/journal.md` | +1 `route_v2_estimate` line | no — another task |
| `docs/leadv2/tasks/dispatch-59ae8b51/journal.md` | +1 `route_v2_estimate` line | no — another task |

The eight rows deleted from `LEAD_V2_STATE.md` are live lanes (DISPATCH-PIN-CLUSTER-01, CODEX-DETACH-01,
PULSE-BEATS-IN-IDLE-REPOS-01, GATE-PROVES-ITS-OWN-CONTROL-01, ANTI-SILENCE-ONE-MECHANISM-01,
LANE-FINISHED-IS-NOT-DEAD-01, DISPATCH-PHASE-DEADLOCK-01, EFFORT-IS-NOT-WIRED-01). Applying this diff
does not just add noise — it silently retires other lanes' state.

These look like incidental captures of runtime churn rather than intent, which is exactly why they are
dangerous: nothing in the report mentions them, so a reviewer approving "the cache-truth tool" also
approves an eight-lane state deletion. The diff should be reduced to LANE_WRITES before merge.

---

## MEDIUM

### M1 — one row mixes two scopes: `turns` counts everything, the token columns count only the reported subset

For `freepool 260901-175619-repo-53e9` the row reads `turns=67 … 0 0 0 0.0000 none 1/67`. `turns` is all
unique requests; `input/cache_read/cache_creation/hit_ratio` are computed over `reported_turns` only (1 of
them). A reader dividing the token columns by `turns` gets a per-turn average that is wrong by 67x. The
`reported` column makes the mix *recoverable*, not *visible*. Either scope both to the reported subset or
label the columns.

### M2 — one of the four required arms has no row, and the gap is not disclosed

Mission step 1 asks for a table per arm. The table has `claude-native`, `glm` (x2), `freepool` (x2), `kimi`
— and no `claude-subsession` row. Verified cause: `ls ~/.claude/cache/claude-runs | grep -c '^260901'` = **0**
— there is genuinely no same-day sample. That is a legitimate reason, but the table presents itself as the
per-arm result without stating that one arm was unmeasurable. A missing arm should be a visible
`unreported`/`no runs` row, by the same principle the tool enforces for missing fields.

### M3 — the report documents five `EXTRA_SUITE_MAP` rows; the diff adds one

`report.md` lists as added:

```
leadv2-cache-truth.sh:…/test-cache-truth.sh
glm-coder.sh:…/test-cache-truth.sh
freepool-coder.sh:…/test-cache-truth.sh
kimi-coder.sh:…/test-cache-truth.sh
claude-subsession.sh:…/test-cache-truth.sh
```

`tests/run-all.sh` in the diff gains exactly one line (`leadv2-cache-truth.sh:…`). The four runner-script
rows do not exist. Consequence: a later change to `glm-coder.sh` / `freepool-coder.sh` / `kimi-coder.sh` /
`claude-subsession.sh` under `--scope changed` will **not** pull in this suite, contrary to what the report
tells the next reader. Either add the rows or correct the report.

### M4 — "last event for this id wins" is asserted, not justified

```python
by_id[mid] = rec  # last event for this id wins
```

For `dispatch-c293c1d5` this is safe — I checked all 95 ids: 76 have >1 event and **0** have duplicate
usages that differ, so last-wins and first-wins are identical there. But the rule is applied to every
provider, including ones whose streaming shape was never sampled (kimi's run had 0 turns). If any provider
emits cumulative-then-final or partial usage under one id, last-wins silently picks a value with no
warning. A one-line justification plus a guard (differing usages under one id -> flag) would make the
assumption testable instead of load-bearing.

### M5 — the mission's `--scope changed` proof was not run; a simulation was substituted

Mission step 4 requires the suite proven wired "via `--scope changed`". The report states plainly that
`run-all.sh --scope changed` was not run to completion (it invokes `run-core-offline.sh` first, >10min) and
that wiring was proven by a stem-lookup simulation against the `EXTRA_SUITE_MAP` string instead. Credit for
disclosing it rather than claiming it. It is still a substituted proof: the simulation checks the map
string, not `add_suite`'s containment check or the root-escape guard, which are the parts that have failed
before. I attempted the real run myself; it exceeded the turn's timeout and produced no output, so I
cannot certify it either — the requirement remains open, not satisfied.

---

## LOW

- **L1 — inconsistent `first_break` sentinel.** The no-turns branch prints `first_break=none`; the
  zero-reported branch prints `first_break=unreported`. Two spellings for the same "not applicable", in
  adjacent branches of the same function. The `kimi … 0 0 0 0 unreported none 0/0` row shows the seam.
- **L2 — the report's reproduce block does not run from the lane.** It uses a repo-relative path to
  `docs/handoff/dispatch-c293c1d5`, which does not exist in the lane worktree; reproducing required the
  absolute main-repo path. A copy-paste reproduce instruction that fails from the lane it shipped in is a
  small but real evidence defect.
- **L3 — one causal claim in the report is falsified.** Round 1's `first_break=2` is attributed to "a
  partial-delta message". Across `dispatch-c293c1d5`: 95 ids, 76 with >1 event, **0** whose duplicate
  usages differ — so no partial delta exists in that data. The observed break at index 2 came from the
  duplicate of turn 1 landing there. The de-dup inflation finding is correct; only this explanation of it
  is not.
- **L4 — mode drift.** The diff declares `new file mode 100755`; the on-disk file is `711`. Harmless today
  (it executes), but the committed mode and the working tree disagree.
- **L5 — stale round-1 prose retained.** The suite section still says "10 cases, <2s wall" and the step-5
  control block still pastes `PASS=9 FAIL=1`, while the shipped suite is 16 assertions / ~3.6s and the
  round-2 section says `PASS=16 FAIL=0`. Two different truths about the same file in one document.
- **L6 — the step-5 red run is a fixture, not a pasted standalone run.** Mission step 5 asks for the
  control RUN and the red output pasted, then reverted. What shipped is the control folded into the suite
  as a permanently-green fixture, plus a transcript of the red run in prose. The transcript is plausible
  and I did not find it contradicted — but combined with H2 it is the mechanism by which a broken control
  stays invisible.

---

## Verdict

**FAIL** — three High findings. H1 and H2 are the same defect class the lane exists to eliminate,
reproduced inside the lane's own deliverable: a value that means "no data" rendered as a measurement, and a
falsification control that reports success when it does not execute. H3 is a merge-safety problem
independent of the tool's quality. M1–M5 and L1–L6 are correctable in place.

The underlying work is sound: the de-dup fix, the per-turn classification fix, and the reported/unreported
distinction are all real, verified against real artifacts, and the report's headline numbers reproduce
exactly. This is a fixable diff, not a wrong one.

DELIVERABLE_COMPLETE
