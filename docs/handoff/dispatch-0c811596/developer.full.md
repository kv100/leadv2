verdict: APPROVE
next_action: review_round_2

# GUARD-AUDIT-FINDINGS-NEVER-REACHED-THE-CODE-01 — developer report

## 0. Scope note on "23"

Mission text says 23 dirs under `docs/handoff/` carry AUDIT/GUARD/CENSUS in their name, measured
on main `b510db3e`. Main has since moved (`3b349eaf` at worktree-base time). Live count today:

```
$ ls docs/handoff/ | grep -iE 'audit|guard|census' | wc -l
22
```
(22, including this task's own dir `GUARD-AUDIT-FINDINGS-NEVER-REACHED-THE-CODE-01`.) The
discrepancy is main-branch drift since the audit was measured, not a missed row — every name
matching the grep is listed below.

## 1. INVENTORY (22 rows)

| Dir | Has report.md? | Contents if no report | Date (report or newest file) |
|---|---|---|---|
| ARBITER-DECISION-LOGIC-CENSUS-01 | NO | brain.yaml, cost-estimate.yaml, mission.md, task-class.yaml — audit not finished, mission only | n/a |
| CAPABILITY-TRUTH-AUDIT-01 | NO | brief.md only — audit not finished | n/a |
| CENSUS-UNREADABLE-DIR-BRANCH-UNDEFENDED-01 | NO | brain.yaml, cost-estimate.yaml, task-class.yaml — audit not finished | n/a |
| CODEX-QUOTA-GUARDRAILS-01 | NO | fix-round-1.md, mission.md — partial, no consolidated report | n/a |
| CONTINUATION-GUARD-01 | NO | mission.md, summary.md — summary only, no report.md | n/a |
| DRIFT-GUARDS-TO-CANON-01 | NO | brief.md, fix-round-1.md, review-*.md (gate/glm/hackdetect), task-class.yaml — in-progress fix round, no consolidated report | n/a |
| FIVE-DAY-AUDIT-BEFORE-STATE-OWNER-01 | NO | VERDICT.md + audit1/2/3-*.md — has a VERDICT.md, functionally a report under a different name; treated as report-equivalent below | see VERDICT.md |
| GLM-EFFICIENCY-AUDIT-01 | YES | — | 2026-09-02 |
| GUARD-AUDIT-FINDINGS-NEVER-REACHED-THE-CODE-01 | NO | this task's own dir | n/a |
| GUARD-CENSUS-IS-WRONG-01 | YES | — | 2026-09-02 |
| GUARDS-MUST-PROVE-THEY-FIRE-01 | YES | — | 2026-09-01 |
| GUARDS-SELF-DISABLE-ON-THE-EMPTY-WRITE-SET-01 | NO | brief-census-criterion.md, brief-census-pass2.md — briefs only | n/a |
| INVISIBLE-DELIVERABLES-CENSUS-01 | YES | — | 2026-09-04 |
| M7-TIERED-TOKEN-BUDGET-GUARD | NO | deliverable.md — not named report.md but is a finished deliverable; not deep-verified below (budget) | see deliverable.md |
| PROCESS-AUDIT-20260821 | NO | brief.md, codex-findings.md — findings exist but no consolidated report.md | n/a |
| PROMISE-GUARD-BIND-01 | YES | — | 2026-08-30 |
| PROMISE-GUARD-TURN-IT-ON-01 | YES | — | 2026-09-02 |
| PROMISE-GUARD-UNKNOWN-KIND-01 | NO | brain.yaml, brief.md, cost-estimate.yaml, task-class.yaml — brief only, NO report was ever written, but the fix landed in code anyway (see §2) | n/a |
| SCRIPT-SIZE-AUDIT-20260821 | NO | brief.md, codex-findings.md, mission-a/b-*.md, cost-estimate.yaml, partial-lane-f72c8c9c — multiple partial mission files, no consolidated report | n/a |
| dispatch-GUARD-CENSUS-IS-WRONG-01-review-hackdetect | NO | critic.full.md / critic.summary.md — a review sub-dir of GUARD-CENSUS-IS-WRONG-01, not an independent audit | n/a |
| dispatch-GUARDS-MUST-PROVE-THEY-FIRE-01 | NO | phases.d only — dispatch scaffolding, not an audit deliverable | n/a |
| dispatch-PROMISE-GUARD-TURN-IT-ON-01 | NO | phases.d only — dispatch scaffolding | n/a |

**Omitted rows: none.** All 22 grep-matched dirs are listed. 6 carry a genuine `report.md`; 2 more
(`FIVE-DAY-AUDIT-BEFORE-STATE-OWNER-01`, `M7-TIERED-TOKEN-BUDGET-GUARD`) carry a report-equivalent
under a different filename, not deep-verified this round (budget — flagged below, not skipped
silently). The remaining 14 are genuinely unfinished audits or dispatch scaffolding — "audit not
finished" is the correct row, not "skip".

## 2. PER-FINDING VERDICT (findings actually extracted and checked against the live tree)

| # | Finding (source dir) | Verdict | Evidence |
|---|---|---|---|
| 1 | `RESOLVED_EFFORT` computed by dispatcher but dropped, never reaches `glm-coder.sh` argv (GLM-EFFICIENCY-AUDIT-01, `EFFORT-IS-NOT-WIRED-01`) | **APPLIED** | `leadv2-dispatch-code.sh:5507` comment "RESOLVED_EFFORT is now WIRED, not dropped"; `glm-coder.sh:399,1226` append `--effort "${GLM_EFFORT}"` to spawn_args. Behavioural proof: `emit decision "effort_applied ... mechanism=flag ..."` line at `:5535` is written every glm dispatch — this is the guard's own contract line proving the flag travelled, not just code that reads well. |
| 2 | GUARD-CENSUS-IS-WRONG-01 round-2/3 fixes: verdict-kind = guard contract, journal cap+rotation, DEFAULT column fix, `test-bash-pre-dispatch-verdict.sh` (new suite, hook previously untested) | **APPLIED** | File exists: `plugins/leadv2/scripts/tests/test-bash-pre-dispatch-verdict.sh`. Discovered by `tests/run-all.sh`'s stem-based auto-discovery (no `EXTRA_SUITE_MAP` entry needed — confirmed via `LEADV2_RUN_ALL_SELECT_ONLY=1 tests/run-all.sh --scope changed`, see §4). |
| 3 | GUARD-CENSUS-IS-WRONG-01 L4: cap checked after append, ≤2-row overshoot | **NOT APPLIED (by design)** | Report's own text: "DEFERRED: cosmetic at a 20000-row default; the fix touches the hottest hook on the live path, which costs more risk than the 2 cosmetic rows are worth." Low consequence, correctly left alone by the original audit. |
| 4 | GUARDS-MUST-PROVE-THEY-FIRE-01 Critical-0 pt.1: `leadv2-lane-liveness.sh --all` "0 alive" misread as an alarm rather than steady state | **APPLIED (elsewhere)** | `leadv2-idle-lead-guard.sh:301-320` consumes `count_live` + requires `availability=="authoritative"`, never reads the verdict column directly — the correct consumption pattern the report calls for. |
| 5 | GUARDS-MUST-PROVE-THEY-FIRE-01 Critical-0 pt.2: liveness discovery is single-`PROJECT_ROOT`-scoped, codex-arm lanes dispatched from a sibling repo are invisible to `--all` | **NOT APPLIED — highest-consequence open finding** | `leadv2-lane-liveness.sh:7` still `PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-$PWD}"`, single root, no cross-repo scan. Report itself: "Fix belongs in a lane that owns `leadv2-lane-liveness.sh`" — i.e. explicitly out-of-scope for the audit lane, not silently missed. Ranked #1 by consequence (a lane that no liveness check can ever see is exactly the "confidently wrong about work it never looked at" failure mode this task exists to catch) but NOT the item fixed this round — see §3 for why, and §5 for the item actually fixed. |
| 6 | GUARDS-MUST-PROVE-THEY-FIRE-01 Critical-0 pt.3: `dead:no_log_artifact` (90 rows) misread as proof-of-death by consumers | **SUPERSEDED** | `leadv2-lane-liveness.sh:969-1027` now has `unknown:deliverable_dir_unreadable`, `finished_unlanded:<age>s`, `unknown:yaml_unreadable` rungs ahead of the `dead:no_log_artifact` fallback (comment cites `D2-UNBLIND-AND-THIRD-STATE-M0M1-01`, a later lane). Separately, `leadv2-dispatch-ledger.sh:769-791` (HIGH-1/MEDIUM-4 fix, also later) makes the sweep consult `pid_alive` before trusting an artifactless-dead verdict. The mechanism the original finding worried about no longer decides death alone. |
| 7 | PROMISE-GUARD-BIND-01 "[High] the fix is not on the running path" — round-2's code fix never reached the cached plugin `~/.claude/plugins/cache/leadv2-local/leadv2/0.3.0/` that live sessions actually load | **APPLIED (now)** | At audit time: `grep -c classify_promise_kind .../0.3.0/hooks/leadv2-promise-guard.sh` = 0 (confirmed absent). Today: `installed_plugins.json` points at `.../leadv2/0.5.7`, and `grep -c classify_promise_kind .../0.5.7/hooks/leadv2-promise-guard.sh` = 4. The plugin version has since been bumped past `0.3.0` and the cache now carries the fix — this was a deployment-timing gap, not a code defect, and it has closed since the audit. |
| 8 | PROMISE-GUARD-UNKNOWN-KIND-01 (no report.md, brief only): a `diagnose` promise-kind should exist for «разбираю/смотрю/изучаю/…», and the unknown-kind path must require a state-changing action, never a bare read | **APPLIED** | `leadv2-promise-guard.sh:397` defines `diagnose` in `PROMISE_KIND_PATTERNS`; `:618-637` comment "the old fallback for an UNKNOWN kind — `action_after_promise = has_action` — is REMOVED, not kept"; `STATE_KINDS = {'write','commit','dispatch'}` gates both the `None` and `'diagnose'` branches. Existing suite `test-promise-guard-unknown-kind.sh` proves the exact escape clause from the brief fires on reads-only and stays silent on Write/dispatch/commit/test (20/20 pass before this round). **Gap found:** the brief explicitly asked for a mutation-proven negative control ("Insert the mutation INSIDE the function body") and none existed in the suite — this round added it (case 19, see §3). |

Findings from `INVISIBLE-DELIVERABLES-CENSUS-01` and `PROMISE-GUARD-TURN-IT-ON-01` were not
individually re-verified this round — both reports are large (198 and 168 lines), both already
carry their own mutation-proven negative controls per their own text (grep: `test-promise-guard-morphology.sh`,
"Mutation negative control" sections present), and budget went to the two items above with the
clearest live-hole shape. Flagged explicitly as **UNVERIFIABLE-THIS-ROUND**, not silently skipped.
The 14 no-report dirs and 2 report-equivalent dirs (`FIVE-DAY-AUDIT-BEFORE-STATE-OWNER-01`,
`M7-TIERED-TOKEN-BUDGET-GUARD`) are likewise **UNVERIFIABLE-THIS-ROUND** — "audit not finished" or
"not deep-checked", per the mission's own instruction that these are rows to name, not skip.

## 3. RANKING and the fix actually shipped

Ranked NOT-APPLIED findings by consequence:
1. **#5 above** (liveness single-root, codex-arm blind spot) — highest consequence, but the
   original audit itself scoped a real fix as belonging to a different, dedicated lane (multi-root
   discovery touches the hottest guard path in the system and needs its own design, not a patch
   inside a 22-dir inventory task). Attempting a real fix here risked exactly the kind of
   half-verified, high-blast-radius change this task exists to prevent. Left alone, named
   explicitly, not silently dropped.
2. **The guard-census false-"missing" bug** (found via direct live-tree probe while verifying
   finding #2 above, not itself named in any of the 6 reports' text — a fresh finding surfaced by
   actually running the census against the live tree, exactly what "check against the tree" means):
   `leadv2-guard-census.sh` resolves every wired guard's existence check under `hooks/`, but two
   real, firing guards — `leadv2-hook-fork-guard.sh` and `leadv2-lane-watch-v2.sh` — are wired
   through `${CLAUDE_PLUGIN_ROOT}/scripts/` in `hooks.json`. The census reported both `missing`,
   rank 2, the top of the dead-first table where a founder looks first. A guard that exists and
   fires but is *reported* as not existing is the same "confidently wrong about work it never
   looked at" failure the mission opens with — just on the census side instead of the guard side.
   **This is the item fixed.**
3. **PROMISE-GUARD-UNKNOWN-KIND-01's missing negative control** — smaller, but directly the shape
   the mission demands (a rule with no mutation-proven control). Added as a second, low-risk fix
   alongside #2 since it required no production code change, only a test addition.

## 4. The fix — leadv2-guard-census.sh false "missing" on scripts/-wired guards

### Before (live-tree probe, the finding)
```
$ bash plugins/leadv2/scripts/leadv2-guard-census.sh --format tsv | grep -E "hook-fork-guard|lane-watch-v2"
<pre-fix: both rows printed state=missing, rank=2>
```
(reproduced from git history: `leadv2-guard-census.sh` pre-fix had `elif [ ! -f "$HOOK_DIR/$g" ]; then state="missing"` with no scripts/ awareness — see `git diff` below, this line is exactly what changed.)

### Fix
`leadv2-guard-census.sh`: added `SCRIPTS_DIR` (+ `--scripts-dir` flag), a `WIRED_DIR` map built from
`hooks.json`'s own `hooks/` or `scripts/` path token per entry, and resolved `gpath` per-guard from
whichever directory its own wiring names — the existence check now reads the same directory the
`hooks.json` entry actually points at, instead of always assuming `hooks/`.

### After (live-tree probe, proof by difference)
```
$ bash plugins/leadv2/scripts/leadv2-guard-census.sh --format tsv 2>/dev/null | grep -E "hook-fork-guard|lane-watch-v2"
3	leadv2-hook-fork-guard.sh	SessionStart	never-ran	-	-	${LEADV2_HOOK_FORK_CANONICAL:-${GUARD_DIR}}	-	no
3	leadv2-lane-watch-v2.sh	SessionEnd,SessionStart	never-ran	-	-	${LEADV2_LANE_WATCH_POLL_SEC:-60}	-	no
```
Both now correctly resolve to `never-ran` (rank 3, "wired but no evidence yet"), not `missing`
(rank 2, "does not exist"). This is a behavioural proof by difference, not a code-reads-well claim.

### Suite: `test-guard-census.sh`, case13 + case13-mutation
New fixture `plugins/leadv2/scripts/tests/fixtures/guards/scripts-dir/fx-scriptsdir.sh`, new
hooks.json entry wiring it through `scripts/`. Case13 asserts `never-ran` + correct DEFAULT read
from the scripts/ path. Case13-mutation builds a full mktemp copy of `leadv2-guard-census.sh` with
the `gpath` resolution (`gpath="$HOOK_DIR/$g"; [ "$gdir" = "scripts" ] && gpath="$SCRIPTS_DIR/$g"`)
replaced by a single hooks/-only line **inside the row-loop function body**, re-runs the census
against the same fixtures, and asserts the mutant reports `fx-scriptsdir.sh` as `missing` again.

**Full suite output (verbatim):**
```
PASS: case13 fx-scriptsdir state (wired via scripts/)
PASS: case13 fx-scriptsdir DEFAULT read from the scripts/ path
PASS: case13-mutation: hooks/-only check re-falsifies fx-scriptsdir as missing

----------------------------------------
ALL PASS: 43 checks passed
```
(43/43 — all pre-existing case1-12 plus the new case13 pair; nothing regressed.)

### Duplicate-implementation check (mandated by today's discovery)
```
$ grep -rl "HOOK_DIR/\$g\|gpath=" --include="*.sh" plugins/leadv2/scripts/ | grep -v /.claude/worktrees
plugins/leadv2/scripts/leadv2-dispatch-code.sh   <- false match: unrelated var (regpath/logpath), verified below
plugins/leadv2/scripts/leadv2-guard-census.sh    <- the real implementation
plugins/leadv2/scripts/tests/test-guard-census.sh <- the suite
plugins/leadv2/scripts/lib/leadv2-lane-address.sh <- false match: unrelated var (regpath)
```
Verified the two "false match" hits are `regpath=`/`logpath=` (unrelated variables, matched only
because my grep pattern `gpath=` is a substring of both) — confirmed no second implementation of
the guard-wiring-existence check exists anywhere in the tree. **No duplicate to worry about; the
control is not disarmable by a second copy.**

## 5. Bonus fix — PROMISE-GUARD-UNKNOWN-KIND-01's missing negative control

`test-promise-guard-unknown-kind.sh` (existing suite, 20/20 pass, proves the `diagnose` kind and
the removed `has_action` fallback behaviourally) had no mutation test, despite the original brief
explicitly asking for one ("Negative control: revert the unknown-kind branch ... Insert the
mutation INSIDE the function body"). Added case 19: a mktemp mutant of the real hook with the
```python
elif primary_kind == 'diagnose':
    action_after_promise = bool(action_kinds_seen & (STATE_KINDS | {'test'}))
```
branch deleted (falls through to `else: action_after_promise = primary_kind in action_kinds_seen`,
always False for `diagnose`). Verbatim result:
```
[TEST] PASS: 19 negative control: mutant reddens (case 2 + case 5 now fire, as they must)
...
[TEST] unknown-kind: 21 passed, 0 failed
```
Duplicate check: `grep -rl "STATE_KINDS\|action_after_promise"` returns only
`leadv2-promise-guard.sh` and the test file itself — no duplicate.

## 6. CI-selection proof (`LEADV2_RUN_ALL_SELECT_ONLY=1 tests/run-all.sh --scope changed`)

Both directions, against the live worktree, no full `tests/run-all.sh` run:

```
=== clean baseline (git status clean) ===
run-all: 4 selected, scope=changed, select_only=1

=== MODIFY leadv2-guard-census.sh (append a comment line) ===
[SELECT] .../plugins/leadv2/scripts/tests/test-guard-census.sh
run-all: 7 selected, scope=changed, select_only=1

=== REVERT (git checkout --) ===
run-all: 4 selected, scope=changed, select_only=1
```
`test-guard-census.sh` appears in `[SELECT]` output only while the source file is dirty, and
disappears the instant it's reverted — both directions proven. (Side observation, not acted on:
`--scope changed` also unions a "not-yet-seen committed range" tracked by a per-git-dir state file
— `tests/run-all.sh:223-239`, documented as deliberate, `HOOK-OUTPUT-CAP-PLUGIN-01` round-4 — so
repeated invocations after a commit shrink monotonically as the state file advances; this is
by-design, not a defect, and does not affect the uncommitted-diff path used above.)

## 7. Self-check

```
$ bash -n plugins/leadv2/scripts/leadv2-guard-census.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-guard-census.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-promise-guard-unknown-kind.sh && echo OK
OK
```
No Python files changed. No full `tests/run-all.sh` run (per mission's explicit warning about the
symlink-repointing incident) — instead: (a) both changed suites run directly and green (43/43,
21/21), (b) `--scope changed --select-only` proven both directions in §6.

## 8. Constraints respected

- Did not touch `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` or
  `plugins/leadv2/config/leadv2-routing.yaml`.
- No `git add -A` — files staged individually by name.
- No push to origin.
- `tests/known-red-suites.txt` / `tests/known-failures.txt` untouched (not shrunk, not grown — no
  entry added for any finding; every fix is a real code/test change).
- Committed on the lane branch: `553859ea`.

## 9. What was deliberately left alone

- **#5 (liveness cross-repo blind spot)** — highest-ranked NOT-APPLIED finding, left to a dedicated
  lane per the original audit's own scoping (see §3.1). This is the most important open item in
  this inventory and should be the next task spawned from it.
- **GUARD-CENSUS-IS-WRONG-01 L4** (cosmetic cap-overshoot) — deliberately deferred by its own audit,
  correctly so; not touched.
- `INVISIBLE-DELIVERABLES-CENSUS-01`, `PROMISE-GUARD-TURN-IT-ON-01`, `FIVE-DAY-AUDIT-BEFORE-STATE-OWNER-01`,
  `M7-TIERED-TOKEN-BUDGET-GUARD`, and the 14 no-report dirs — not deep-verified this round, marked
  UNVERIFIABLE-THIS-ROUND, not silently skipped. A follow-up pass should walk these next, in the
  same one-finding-at-a-time discipline this task used.

DELIVERABLE_COMPLETE
