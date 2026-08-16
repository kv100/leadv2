Product implementation task dispatch-5e57c5ff. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# ARCHITECT PREPASS — REPORT-ONLY-GATE-01

Scoped design for: a lane may declare its deliverable is a **file (report)**, not a diff, and be
gated on that file existing and being non-trivial. Plugin repo `~/Projects/leadv2` only.

## 1. Where the bug actually lives

| Fact | Evidence |
|---|---|
| The gate's only success predicate is diff bytes | `leadv2-dispatch-product-close.sh:1451` / `:1458` — `[[ -s "${diff_file}" ]] \|\| blocked_reason="unscopable_diff"` |
| Empty diff + clean worktree ⇒ `no_work / empty_diff` | same file `:1487` |
| A report can never enter the diff | every diff call carries `':(exclude)docs/handoff'` (`:1325`–`:1331`) |
| The report is therefore unrepresentable in `LANE_WRITES` | prepass prompt (`leadv2-dispatch-code.sh:1923`,`:1925`) forbids `docs/handoff` entries |
| `review-gate.md` prints only `status/reason/base` for every blocked case | `:1499`–`:1501` |
| The report dies with the worktree | worker `--cwd` is `LEADV2_LANE_WORK_ROOT` (`:1286`); `HANDOFF="${ROOT}/docs/handoff/dispatch-${TASK}"` (`:93`) is the **main checkout** — nothing copies worktree→ROOT |

So: three distinct outcomes (diff lane, report lane, dead worker) collapse onto one string. The fix
is a **declared deliverable kind**, a **harvest step**, and a **third rendered shape**.

## 2. Design

### 2.1 Declaration — the mission says it, the gate never guesses

New optional lane attribute, parallel in every way to `LANE_WRITES`:

```
LANE_DELIVERABLE: report:<repo-relative path>
```

Precedence, mirroring `lane_writes` (`leadv2-dispatch-code.sh:3152`–`:3158`):

1. row/CLI `--lane-deliverable report:<path>` (highest — the dispatcher's declaration)
2. the **mission file's own** `LANE_DELIVERABLE:` line, harvested with the same tolerant matcher as
   `_prepass_writes` (`:1673`) so `**LANE_DELIVERABLE:**` also matches
3. absent ⇒ `kind=diff`, i.e. **today's behaviour byte-for-byte**

Harvested from the *mission*, not the architect prepass: the mission is the founder's statement of
intent, and a report lane is a property of the ask, not of a design.

Plumbing: `spawn_product_close` (`:2098`–`:2123`) gains `LEADV2_DISPATCH_LANE_DELIVERABLE=` next to
the existing `LEADV2_DISPATCH_LANE_WRITES=`. `LEADV2_*` prefix, consistent with the surrounding env
block.

Path grammar: only `report:` is accepted in this task. Anything else ⇒ the declaration is ignored
and journalled `lane_deliverable task=… status=ignored reason=unknown_kind` — an unparsable
declaration must never silently convert a code lane into a report lane.

### 2.2 Guard exemption

`_lane_writes_guard` (`:1750`) parks a lane with no `LANE_WRITES`. A report lane legitimately has
none (its deliverable lives under `docs/handoff/`, excluded by contract). Exemption: when
`kind=report` **and** the declared path parses, the guard returns 0 with
`emit decision "lane_writes task=… source=report_deliverable"`. `REQUIRE_LANE_WRITES` semantics for
diff lanes are untouched.

### 2.3 The gate — new shared lib `lib/leadv2-report-deliverable.sh`

One mechanism, sourced by both `leadv2-dispatch-code.sh` (parse) and
`leadv2-dispatch-product-close.sh` (validate + harvest), guarded-source + no-op stub exactly like
`_REVIEW_FINDINGS_SH` (`:56`–`:60`) so a missing lib degrades to today's gate, never to a broken one.

| Function | Contract |
|---|---|
| `lv2_deliverable_parse <decl>` | prints `report\x1f<path>`; rc1 if not a report declaration |
| `lv2_report_locate <diff_root> <root> <rel>` | prints first existing abs path, preferring the lane worktree; rc1 if neither exists |
| `lv2_report_substantive <abs>` | rc0 iff ≥ `LEADV2_REPORT_MIN_BYTES` (default **600**) of non-whitespace **and** ≥ `LEADV2_REPORT_MIN_LINES` (default **12**) non-blank lines. Deliberately dumb — no LLM, no keyword sniff; "non-trivial" must be a fact a human can re-check by eye |
| `lv2_report_harvest <abs> <handoff_dir>` | copies to `<handoff_dir>/report.md` (ROOT-side, survives sweep); prints the destination |

Placement in `pc_scope_diff`: a `kind=report` branch runs **before** the `blocked_reason` block
(`:1461`). It never falls into the empty-diff path, so the diff gate for normal lanes is not
touched — no predicate a code lane traverses is edited.

```
kind=report ?
├─ locate fails                 → blocked / reason: report_missing   → ledger no_work:report_missing
├─ located, not substantive     → blocked / reason: report_too_thin  → ledger no_work:report_too_thin
└─ located + substantive        → harvest → review body := report → continue to review
```

`report_missing` / `report_too_thin` are **causes**, not terminals — the ledger enum
(`landed|parked|refused|dead|no_work`, `leadv2-dispatch-ledger.sh:201`) is unchanged. A report lane
that passes review stamps `landed` with `deliverable=docs/handoff/dispatch-<TASK>/report.md` using
`write-terminal`'s existing `[<deliverable>]` parameter (`:908`) and no commit sha.

### 2.4 The report *is* reviewed — prose review, not a skipped review

Minimum-blast-radius choice: the report lane **substitutes the review body**, then runs the
unmodified review path. `diff_file` is populated with

```
# REPORT-ONLY LANE — review the ANALYSIS, not a diff.
# deliverable: <rel path>   bytes: <n>
<report text, head -c ${LEADV2_REPORT_REVIEW_MAX_BYTES:-60000}>
```

and the reviewer mission gains a prose rubric: (a) is every load-bearing claim backed by a quoted
file/line or command output present in the report; (b) list unsupported claims; (c) does the
recommendation follow from the evidence; (d) emit the same verdict marker as a code review. Because
the body flows through the existing channel, the findings renderer, verdict-marker check
(`:2027`), `review_body_lost` guard (`:1965`) and pass/fail rendering all work unchanged. A wrong
analysis is thus rejected by the same machinery that rejects a wrong diff.

### 2.5 The three rendered shapes (the deliverable of this task)

`review-gate.md` after the change — each case distinguishable without opening a worktree:

| Case | `review-gate.md` |
|---|---|
| **diff lane** (unchanged) | `status: pass` / `reason: -` / `base: <sha>` + findings block |
| **report lane** | `status: pass` · `kind: report` · `deliverable: docs/handoff/dispatch-<TASK>/report.md` · `bytes: <n>` · `review: <verdict>` + findings block |
| **report lane, no report** | `status: blocked` · `kind: report` · `reason: report_missing` · `declared: <rel path>` |
| **report lane, stub report** | `status: blocked` · `kind: report` · `reason: report_too_thin` · `bytes: <n>` · `min: <threshold>` |
| **dead worker** | `status: blocked` · `kind: diff` · `reason: no_work` · `base: <sha>` (an explicit `kind:` line is added to the existing blocked writer so the two blocked families never read alike) |

`kind:` on the existing blocked writer is the only edit to a line a code lane can reach; it is
purely additive (new key, existing keys byte-identical).

## 3. Files

| File | Change |
|---|---|
| `plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh` | **(to-create)** parse / locate / substantive / harvest |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | mission harvest of `LANE_DELIVERABLE:`, `--lane-deliverable` arg, writes-guard exemption, `LEADV2_DISPATCH_LANE_DELIVERABLE` in `spawn_product_close` |
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | guarded source of lib; `kind=report` branch in `pc_scope_diff`; harvest; review-body substitution + prose rubric; `kind:` line in blocked + pass writers |
| `plugins/leadv2/scripts/tests/test-report-only-gate.sh` | **(to-create)** see §5 |

Not in `LANE_WRITES` by contract but produced by the lane:
`docs/handoff/REPORT-ONLY-GATE-01/report.md` — naming what `review-gate.md` prints for the three
cases (§2.5), ending `DELIVERABLE_COMPLETE`.

## 4. Non-goals (implementer: ignore these)

- No change to the diff predicate, `unscopable_diff`, `partial_diff`, `unscoped_lane_work`, or
  `asked_into_void` for code lanes.
- No new ledger terminal word; no schema/DB work; no `open-threads.md` edit.
- No heuristic detection of report lanes (explicitly rejected by the mission).
- No `deliverable:` kinds beyond `report:` (no `artifact:`, no multi-file lists).
- No merge/deploy — the lead merges.
- No retrofit of past lanes (`d44ddd50`, `cbc3e960`).
- No LLM-based "is this report substantive" scoring.

## 5. Tests — `test-report-only-gate.sh` (offline, no network, fixture worktrees)

1. **report lane, good report** → rc0, `review-gate.md` contains `kind: report` and
   `deliverable: …/report.md`; the file exists under ROOT `docs/handoff/dispatch-<TASK>/` after the
   lane worktree is deleted (proves survival).
2. **report lane, no file** → `status: blocked`, `reason: report_missing`, ledger row
   `no_work:report_missing`.
3. **report lane, 3-line stub** → `reason: report_too_thin`, `bytes:` printed.
4. **diff lane regression** → declaration absent, real diff present ⇒ output identical to
   pre-change (golden compare), proving the code path is untouched.
5. **dead worker regression** → empty diff, clean tree ⇒ `reason: no_work` with `kind: diff`.
6. **unknown kind** (`LANE_DELIVERABLE: artifact:x`) ⇒ treated as a diff lane, journal line
   `status=ignored`.

Auto-discovery in `plugins/leadv2/scripts/tests/run-core-offline.sh` is glob-based — implementer
confirms the new suite is picked up (a suite that never runs is worse than no suite).

## 6. Risks

| Risk | Mitigation |
|---|---|
| A code lane gets an accidental `LANE_DELIVERABLE:` line and stops being diff-gated | only exact `report:` parses; ignored otherwise + journalled; the declaration must come from the mission/row, never from worker output |
| Harvest overwrites a real handoff artifact | destination is the fixed `report.md` inside the lane's own `dispatch-<TASK>` handoff dir; write to `report.md.tmp` + `mv -f` (same idiom as `:2056`) |
| Report lives only in ROOT because the worker ran in the main checkout | `lv2_report_locate` checks lane worktree **then** ROOT; harvest is a no-op copy-onto-itself guard |
| `kind:` key breaks a consumer parsing `review-gate.md` positionally | additive key appended after `reason:`; implementer greps consumers of `review-gate.md` (`leadv2-dispatch-code.sh`, `hooks/leadv2-workflow-*`, `phases.md`) before landing |
| Prose review floods context with a huge report | `LEADV2_REPORT_REVIEW_MAX_BYTES` head-truncation, default 60000, with a truncation notice line |
| Concurrent access: worker still writing the report while the gate reads it | the gate runs only after `pc_await_worker_exit` for the report branch — the branch is placed after that await, not before |
| Editing canonical `.sh` under `LEADV2_LEAD_GUARD=1` is blocked for the Edit tool | implementer patches via `/tmp` python patcher + Bash (known constraint) |
| `LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC` too low for this repo's prepass | raise before dispatch; not an implementation change |

## 7. Acceptance

```
acceptance:
  - surface: file_artifact
    observable: |
      docs/handoff/dispatch-<TASK>/review-gate.md for a report-declaring lane shows the
      line "kind: report" and a "deliverable:" line naming a report file that a human can
      open in the main checkout after the lane worktree is gone.
    authored_at: 2026-08-15T00:00:00Z
  - surface: rendered_line
    observable: |
      A lane whose worker died shows "reason: no_work" together with "kind: diff", so a
      human reading review-gate.md alone can tell it apart from a finished report lane.
    authored_at: 2026-08-15T00:00:00Z
  - surface: file_artifact
    observable: |
      docs/handoff/REPORT-ONLY-GATE-01/report.md names, case by case, what review-gate.md
      prints for a diff lane, a report lane and a dead worker, and ends with
      DELIVERABLE_COMPLETE.
    authored_at: 2026-08-15T00:00:00Z
```

## 8. Constraint checklist

1. Env naming — `LEADV2_DISPATCH_LANE_DELIVERABLE`, `LEADV2_REPORT_MIN_BYTES`,
   `LEADV2_REPORT_MIN_LINES`, `LEADV2_REPORT_REVIEW_MAX_BYTES`: all `LEADV2_*`. ✅
2. Paths — all four listed files verified on disk except the two marked **(to-create)**. ✅
3. `claude -p` — this design introduces no new `claude -p` invocation. ✅ (the reviewer spawn reuses
   the existing call site with its existing flags)
4. Concurrent access — report read happens post-worker-exit; harvest uses tmp+`mv -f`. ✅
5. Config contradiction — no existing env var is redefined; `LEADV2_REQUIRE_LANE_WRITES` semantics
   preserved for diff lanes, exemption is additive. ✅

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-report-only-gate.sh

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# MISSION — REPORT-ONLY-GATE-01 (diagnosis lanes are judged by a diff gate they cannot satisfy)

Plugin repo: `~/Projects/leadv2`. Founder-authorised plugin work. Track 5.2.

## Why this is worth doing now

Today six of the engine's most valuable lanes were **diagnosis** lanes — they produce a report, not
a diff. The dispatch gate judges a lane by whether it produced a diff, so a finished analysis and a
worker that died look identical: both come back `no_work`. That ambiguity has already cost three
dispatches and zero output on one lane (`d44ddd50`), and today it returned `blocked: no_work` on
`cbc3e960` whose report was in fact complete and correct on disk.

The lead currently works around it by hand — reading the worktree, finding the report, copying it
out before the worktree is swept. That is exactly the sort of manual step that gets skipped at 2am,
and when it is skipped the analysis is lost.

## What to build

A lane must be able to declare that its deliverable is a **file**, not a diff, and be gated on that
file existing and being non-trivial.

Get these right:
- **The mission declares it, not the gate guesses it.** A heuristic ("no diff but a new .md
  appeared") will misfire in both directions. An explicit declaration in the mission is
  unambiguous.
- **`no_work` must stop meaning two things.** After this change, "the worker produced nothing" and
  "this lane's deliverable is a report and here it is" must be distinguishable in `review-gate.md`
  without reading a worktree.
- **The report still gets reviewed.** A report-only lane is not an unreviewed lane — a wrong
  analysis is more dangerous than a wrong diff, because it redirects everything downstream. Decide
  what review means for prose and say so; do not silently skip it.
- **The deliverable must survive worktree cleanup.** Today the report lives in the lane worktree and
  dies with it unless the lead copies it out by hand.

## Hard constraints
- Plugin repo. `~/Projects/leadv2` is the single source — never a copy inside a consuming project.
- Do not weaken the diff gate for normal code lanes.
- No deploy. The lead merges.
- Do not touch `docs/leadv2/open-threads.md`.

## Note on this repo's dispatch
Lanes here previously died at `architect_prepass` with rc=124. That was diagnosed
(`docs/handoff/PLUGIN-PREPASS-HANGS-01/report.md`): it is not a hang — the architect shelled out to
a 900–2400s offline suite inside a 420s budget. Raise `LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC` if you
hit it.

## Deliverable
The working gate plus tests, and `docs/handoff/REPORT-ONLY-GATE-01/report.md` naming what
`review-gate.md` now prints for each of the three cases (diff lane, report lane, dead worker).
End with DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-5e57c5ff" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.