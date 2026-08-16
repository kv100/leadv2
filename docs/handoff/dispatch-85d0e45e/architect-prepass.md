# REPORT-ONLY-MISSIONS-01 — architect prepass

## 0. Correction to the mission's premise (read first)

The mission names `leadv2-review-run.sh` as the gate that returns `no_work`. It does not.
`leadv2-review-run.sh` is a diff-consuming review **engine** (`--diff <file>` is a required
arg, header lines 1–28) and never emits `no_work`. The verdict comes from
`pc_scope_diff()` in **`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`**
(:1450–1508) and from `pc_silent_arm_probe` (:1556–1566). Those two are the change
surface. `leadv2-review-run.sh` is untouched by this design.

Reproduced verdict path today:

| site | condition | review-gate.md | ledger |
|---|---|---|---|
| product-close :1487 | empty scoped diff, lane worktree clean | `status: blocked` / `reason: no_work` / `base: HEAD` | `no_work` / `empty_diff` |
| product-close :1564 | worker exited, stream never engaged | `reason: arm_produced_nothing` | `no_work` / `arm_produced_nothing` |

Both are reachable whether the worker wrote a brilliant report to `docs/handoff/…` or
died on spawn — that is the defect. Note also why report lanes are *structurally* invisible:
`LANE_WRITES` is required to exclude `docs/leadv2` and `docs/handoff` (dispatch-code.sh
:1923), and the dirty-lane fallback filters the same two prefixes out of `git status`
(:1485). A report written where reports belong cannot produce a diff the gate will look at.

## 1. Change summary

Add a second, parallel declaration to `LANE_WRITES`:

```
LANE_DELIVERABLE: docs/handoff/OP-CONCURRENCY-01/report.md
```

A lane carrying that line is gated on **that file**, not on a diff. A lane without it is
gated exactly as today, byte-identical.

### 1.1 Where the declaration lives, and why

**Chosen: a `LANE_DELIVERABLE:` line in the lane mission file, with the architect-prepass
artifact as fallback.**

Rejected alternatives:

- *A field in `docs/tasks.yaml` / the dispatch row.* Rows are lead-authored and already
  carry a `writes` CSV, but a report mission is frequently dispatched straight from a
  mission markdown file with no row edit; the declaration would be missable in exactly
  the case that motivated the task.
- *Prepass-artifact only (mirroring `LANE_WRITES` exactly).* Report missions are short
  and often skip the architect prepass entirely (`provably_one_file` / `ARCHITECT_GATE`
  early returns), so the declaration would be unharvestable for half the target lanes.
- *Infer it from the mission prose ("Report to X").* Guessing a path out of free text is
  the kind of heuristic that produces a confident wrong verdict. Rejected.

The mission file is the one artifact every lane has, the harvest grep already exists in a
tolerant form for `LANE_WRITES` (`_prepass_writes`, dispatch-code.sh :1668–1688), and the
prepass fallback costs one extra call to the same helper.

### 1.2 Gate semantics

Compute `_pc_deliverable_state` once, before `pc_silent_arm_probe`:

| state | meaning |
|---|---|
| `undeclared` | no `LANE_DELIVERABLE:` — everything below is skipped, today's behaviour |
| `satisfied` | file resolves, is non-trivial (§2), is fresh |
| `missing` | declared path does not exist under the lane worktree or the main root |
| `incomplete` | exists, but trivial by §2 |
| `stale` | exists and non-trivial, but predates this dispatch's worker run dir |

Then:

| situation | outcome |
|---|---|
| declared + `satisfied` + empty scoped diff | `status: pass`, `mode: report_only`, `deliverable:`, `bytes:` → terminal `landed` cause `deliverable`, exit 0. e2e + review skipped (no diff exists for them to act on), each journaled `skipped reason=report_only`. |
| declared + `satisfied` + **non-empty** diff | **unchanged full path** — e2e and review run as today. A satisfied deliverable removes the empty-diff block; it never buys code a review bypass. |
| declared + `missing`/`incomplete`/`stale` | `status: blocked`, `reason: deliverable_<state>`, and a `deliverable: <path>` line naming the path → terminal **`refused`**, cause `deliverable_<state>`, exit 5. |
| declared + unsatisfied + silent-arm probe fires | probe keeps its evidence (`arm=`, `stream=`) but stamps `refused` / `deliverable_<state>`, not `no_work`. |
| declared + `satisfied` | the silent-arm probe is skipped outright — the worker demonstrably produced its deliverable. |
| undeclared | byte-identical to today, including `no_work`/`empty_diff`. |

`no_work` therefore becomes unreachable for a lane that declared a deliverable, which is
the mission's core requirement. `refused` is chosen over a new ledger word deliberately:
`leadv2-dispatch-ledger.sh:201` validates the terminal against a closed set
(`landed|parked|refused|dead|no_work`); *causes* are free-form. `refused` is retryable and
already carries the sibling "the worker produced something the gate could not accept"
case (`unscoped_lane_work`). No enum change, no status-surface change, no blast radius.

## 2. "Non-trivial", and its defence

Three conjunctive tests, all content-blind. The gate must never judge whether a report is
*good* — only whether one is *there and finished*.

1. **Non-whitespace size ≥ `LEADV2_LANE_DELIVERABLE_MIN_BYTES` (default 32).**
   Deliberately low. The mission is explicit that "I could not determine this, because the
   instrumentation does not exist" is a legitimate report and must pass. A byte floor in
   the hundreds would fail exactly that case, so size is used only to reject zero-byte
   files, whitespace-only files, and a bare `# Title` line.
2. **Terminates with the literal `DELIVERABLE_COMPLETE`** (last non-blank line), unless
   `LEADV2_LANE_DELIVERABLE_REQUIRE_MARKER=0`. This is the real discriminator, and it is
   already the protocol every subagent operates under (`leadv2-subagent-protocol`, and
   this mission's own closing instruction). A worker that died mid-write has no marker; a
   worker that finished a three-sentence honest report does. That separates "unfinished
   stub" from "short but complete" without any content judgement — the length test alone
   cannot.
3. **Freshness**: file mtime ≥ mtime of this dispatch's worker run dir
   (`_pc_run_dir_for "${AUTHOR}" "${HANDLE}"`), unless
   `LEADV2_LANE_DELIVERABLE_REQUIRE_FRESH=0`. Directly targets incident 2: a lane
   dispatched three times must not pass on attempt 3 because attempt 1 left a file. If the
   run dir cannot be resolved, the check is skipped fail-open and journaled `fresh=unknown`
   — an unresolvable run dir is an infrastructure fact, not evidence of a stale report.

Path validation before any of the above: the declared path must be repo-relative (reject
leading `/`), must contain no `..` segment, and must not be a glob. Resolution order is
lane worktree (`_lane_root`, already resolved at :1550–1553) first, then `ROOT` — a report
written inside the worktree is real work even though it was never committed or merged.

## 3. Interface contracts

| producer | contract |
|---|---|
| mission file / prepass artifact | one line matching `^[[:space:]*_]*LANE_DELIVERABLE[*_]*:` — a single repo-relative path (first path wins if a CSV is given; extra entries journaled and ignored) |
| `_lane_deliverable <sig8> <mission_path>` (new, dispatch-code.sh) | echoes the normalised path or empty |
| `spawn_product_close` | exports `LEADV2_DISPATCH_LANE_DELIVERABLE=<path>` beside the existing `LEADV2_DISPATCH_LANE_WRITES` (:2123) |
| `leadv2-dispatch-product-close.sh` | reads `DELIVERABLE="${LEADV2_DISPATCH_LANE_DELIVERABLE:-}"` at :31–32 |
| `_lane_writes_guard` | a present `LANE_DELIVERABLE:` independently satisfies the guard — **required**, otherwise `REQUIRE_LANE_WRITES=1` parks every report-only lane before it ever spawns |

New env vars (all `LEADV2_*`, matching convention; none collide — grepped):

| var | default | effect |
|---|---|---|
| `LEADV2_REPORT_ONLY_LANES` | `1` | `0` ignores every declaration → today's behaviour exactly |
| `LEADV2_DISPATCH_LANE_DELIVERABLE` | — | the threaded path (set by dispatch, not by a human) |
| `LEADV2_LANE_DELIVERABLE_MIN_BYTES` | `32` | non-whitespace floor |
| `LEADV2_LANE_DELIVERABLE_REQUIRE_MARKER` | `1` | require `DELIVERABLE_COMPLETE` |
| `LEADV2_LANE_DELIVERABLE_REQUIRE_FRESH` | `1` | require mtime ≥ run-dir mtime |

New journal lines (`emit decision`), so a report lane is diagnosable without a re-run:

```
lane_deliverable task=<t> declared=<path> state=<satisfied|missing|incomplete|stale> bytes=<n> marker=<present|absent> fresh=<yes|no|unknown> root=<lane|main>
review_gate task=<t> status=pass mode=report_only terminal=landed cause=deliverable
review_gate task=<t> status=blocked reason=deliverable_missing terminal=refused cause=deliverable_missing
```

## 4. Files

| file | change |
|---|---|
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | `_lane_deliverable()` harvester; `_lane_writes_guard` accepts a declaration; export in `spawn_product_close` |
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | read env; `pc_deliverable_state()`; skip silent-arm probe when satisfied; report-only pass exit and the three `refused` exits inside `pc_scope_diff`'s blocked branch |
| `plugins/leadv2/scripts/tests/test-report-only-lane.sh` | *(to-create)* the fixture suite, §6 |
| `plugins/leadv2/scripts/tests/run-core-offline.sh` | register the new suite (one `run_check` line beside :86) |
| `docs/missions/REPORT-ONLY-MISSIONS-01.report.md` | *(to-create)* evidence report |

## 5. Risks

| risk | mitigation |
|---|---|
| A code lane adds `LANE_DELIVERABLE:` and buys itself a review bypass | the report-only pass fires **only** when the scoped diff is empty; a non-empty diff always takes the full e2e+review path. Assert this in the fixture suite. |
| Declaration points outside the repo (`/etc/passwd`, `../../x`) | absolute paths, `..` segments and globs rejected at harvest; resolution confined to `_lane_root` then `ROOT` |
| A stale report from a prior dispatch passes the gate | freshness test (§2.3) against the worker run dir mtime |
| Reconcile (`leadv2-dispatch-ledger.sh:700`) can still stamp `no_work` for a crashed close gate on a report lane | **out of scope, real.** Reconcile is an after-the-fact anti-join and does not see the declaration. It only fires when product-close never wrote a terminal. Follow-up: persist `deliverable=<path>` on the reservation row so reconcile can apply the same test. Flagged, not built. |
| `DELIVERABLE_COMPLETE` requirement rejects a report from a worker that does not follow the subagent protocol | `LEADV2_LANE_DELIVERABLE_REQUIRE_MARKER=0` per-lane escape; the miss is loud (`reason: deliverable_incomplete` + `marker: absent`), never silent |
| bash 3.2 (dispatch resolves `bash` from PATH) | no associative arrays, no `mapfile`, no `stat -c` — use `wc -c` and `find -newer`/`stat -f %m` with a portable wrapper, as the surrounding code already does |
| `review-gate.md` write race | unchanged: product-close is the sole writer on this path; `leadv2-review-run.sh` is not reached for a report-only lane |

## 6. Evidence plan (fixture runs the implementer must produce)

Four runs against the existing `test-no-work-terminal.sh` stub harness (same seams:
`LEADV2_JOURNAL_BIN`, `LEADV2_DISPATCH_LEDGER_BIN` stubs — never the real ledger):

1. report-only lane, deliverable written with marker → `status: pass` / `mode: report_only`, ledger `landed`/`deliverable`, exit 0.
2. same fixture, deliverable absent → `status: blocked` / `reason: deliverable_missing` / `deliverable: <path>`, ledger `refused`, exit 5.
3. **contrast:** both fixtures with `LEADV2_REPORT_ONLY_LANES=0` → both produce today's `reason: no_work`, indistinguishable — the defect, demonstrated.
4. regression: a lane with no declaration and an empty diff still yields `no_work`/`empty_diff`; a declared lane with a non-empty diff still runs review.

## 7. Non-goals

- No change to `leadv2-review-run.sh`.
- No new ledger terminal word; the `landed|parked|refused|dead|no_work` set is untouched.
- No relaxation of the diff gate for undeclared lanes — not one byte.
- No quality judgement of report content.
- No reconcile-path deliverable awareness (§5, flagged as follow-up).
- No status-surface / dashboard rendering work.
- Plugin repo only; nothing in persona-engine.

## 8. Constraint checklist

1. Env naming — all new vars `LEADV2_*`, grepped for collisions, none found. ✓
2. Paths — every listed file exists on disk except the two marked *(to-create)*. ✓
3. `claude -p` — this design introduces no `claude -p` invocation. ✓ (n/a)
4. Concurrent access — `review-gate.md` keeps its single-writer property on this path. ✓
5. Config contradiction — `LEADV2_REQUIRE_LANE_WRITES` semantics are *widened* (a deliverable now satisfies it), not contradicted; called out explicitly in §3 because silently leaving it would park every report lane. ✓

```
acceptance:
  surface: file_artifact
  observable: |
    docs/handoff/<task>/review-gate.md for a lane whose mission declared
    LANE_DELIVERABLE reads "status: pass" with a "mode: report_only" line and a
    "deliverable:" line naming the report path when that report is on disk and
    ends with DELIVERABLE_COMPLETE; and for the same lane with the report absent
    it reads "status: blocked" with "reason: deliverable_missing" and a
    "deliverable:" line naming the path that is not there. The word "no_work"
    appears in neither file.
  authored_at: 2026-08-15T00:00:29Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-report-only-lane.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, docs/missions/REPORT-ONLY-MISSIONS-01.report.md

DELIVERABLE_COMPLETE
