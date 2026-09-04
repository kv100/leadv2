# GUARD-AUDIT-FINDINGS-NEVER-REACHED-THE-CODE-01 — report

Date: 2026-09-04. Worktree: `.claude/worktrees/GUARD-AUDIT-FINDINGS-NEVER-REACHED-THE-CODE-01`.
Code commit: `553859ea` (+ this report). Question: did the guard/audit handoffs' findings reach the code?

## 1. Inventory (22 rows, not 23)

Measured live 2026-09-04: `ls docs/handoff/ | grep -iE 'audit|guard|census'` → **22 unique dirs**
(17 tracked at `main` tip `3b349eaf` and at the mission's `b510db3e` alike — `git ls-tree` both,
17/17 — plus 5 live-only dirs). The mission's 23 does not reproduce at either commit nor on disk;
most likely a non-deduplicated `ls -d` glob count (the same glob prints 19 with duplicates in a
clean worktree). One row below (`GUARD-AUDIT-FINDINGS…`) is this task's own mission dir. **Zero
rows omitted.**

| # | dir | report? | claim / content | date |
|---|---|---|---|---|
| 1 | ARBITER-DECISION-LOGIC-CENSUS-01 | no (mission/brain only) | audit not finished | 2026-09-04 |
| 2 | CAPABILITY-TRUTH-AUDIT-01 | no (brief only) | audit not finished | — |
| 3 | CENSUS-UNREADABLE-DIR-BRANCH-UNDEFENDED-01 | no (task scaffolding) | audit not finished; its subject was defended by #15's C6 | — |
| 4 | CODEX-QUOTA-GUARDRAILS-01 | no report; `fix-round-1.md` carries 6 concrete findings | circuit + tests + escape-hatch removal | 2026-09-0x |
| 5 | CONTINUATION-GUARD-01 | `summary.md` (report-equivalent) | new Stop hook + wiring + 13-case suite | 2026-08-xx |
| 6 | DRIFT-GUARDS-TO-CANON-01 | no report; brief + `fix-round-1.md` | lift 2 drift hooks to canon, wire both places, repo-install drift check, symlink persona-engine copies | 2026-09-02 |
| 7 | FIVE-DAY-AUDIT-BEFORE-STATE-OWNER-01 | `VERDICT.md` | 3 audits, 8 not-clean rows w/ dispositions | 2026-09-03 |
| 8 | GLM-EFFICIENCY-AUDIT-01 | **report.md** | 8 ranked recs (effort wiring, flash default, capability yaml, probes) | 2026-09-04 |
| 9 | GUARD-AUDIT-FINDINGS-NEVER-REACHED-THE-CODE-01 | this file | this task | 2026-09-04 |
| 10 | GUARD-CENSUS-IS-WRONG-01 | **report.md** (r2+r3) | census parser/dispatcher/fixtures/columns/rotation fixes | 2026-09-02..04 |
| 11 | GUARDS-MUST-PROVE-THEY-FIRE-01 | **report.md** | census + verdict lib + suite + 4 fixtures; Critical-0 liveness defects named, fix deferred to liveness owner | 2026-09-01 |
| 12 | GUARDS-SELF-DISABLE-ON-THE-EMPTY-WRITE-SET-01 | no (2 census briefs) | audit not finished | — |
| 13 | INVISIBLE-DELIVERABLES-CENSUS-01 | **report.md** (r2) | unreadable-dir branch defended (C6a/C6b) + 2 mutation controls | 2026-09-04 |
| 14 | M7-TIERED-TOKEN-BUDGET-GUARD | `deliverable.md` (report-equivalent) | 3-tier compact-warn + measurement + suite + doc | — |
| 15 | PROCESS-AUDIT-20260821 | no report; `codex-findings.md` is the audit | process recs: falsification ritual, review synthesis, marker block | 2026-08-21 |
| 16 | PROMISE-GUARD-BIND-01 | **report.md** (r1+r2) | 6 review-driven fixes (sandbox, fixture, verbs, regex, sd-row, cache deploy) | 2026-09-0x |
| 17 | PROMISE-GUARD-TURN-IT-ON-01 | **report.md** (r3+r4) | flip promise-guard to blocking + anchored regexes + rc=2 sentinel | 2026-09-0x |
| 18 | PROMISE-GUARD-UNKNOWN-KIND-01 | no report; `brief.md` | diagnose kind for «разбираю» family | — |
| 19 | SCRIPT-SIZE-AUDIT-20260821 | no (brief + partial lane) | audit not finished | 2026-08-21 |
| 20 | dispatch-GUARD-CENSUS-IS-WRONG-01-review-hackdetect | critic artifacts | not an audit (review of #10) | 2026-09-04 |
| 21 | dispatch-GUARDS-MUST-PROVE-THEY-FIRE-01 | phases.d only | lane scaffolding of #11, not an audit | 2026-09-01 |
| 22 | dispatch-PROMISE-GUARD-TURN-IT-ON-01 | phases.d only | lane scaffolding of #17, not an audit | 2026-09-0x |

7 of 22 carry `report.md` — matches the mission's count.

## 2. Verdict per finding

Legend: APPLIED (file:line today), NOT APPLIED, SUPERSEDED, UNVERIFIABLE. Behavioural APPLIEDs
carry a command + output further down or in §3.

### GLM-EFFICIENCY-AUDIT-01 (8 recs)
| finding | verdict | evidence |
|---|---|---|
| R1 wire RESOLVED_EFFORT into glm-coder spawn | **APPLIED** | `glm-coder.sh:113-116` (`--effort <v>` on every spawn site), `leadv2-dispatch-code.sh:5310-5325` `effort_applied … mechanism=flag`; the remaining `EFFORT-IS-NOT-WIRED-01` comments (:5384,:5437,:5501) are about kimi/freepool/claude arms which have no knob. Live dispatch row not re-probed this session (magnitude stays UNVERIFIED, as the audit itself said) |
| R2 default Standard/Light to glm-flash | **APPLIED** (policy layer) | `leadv2-dispatch-code.sh:2084-2092` — capability+eligible cell wins, glm-flash never special-cased (GLM-53-FLASH-ARM-01) |
| R3 refresh model-capability.yaml glm row | **APPLIED** | `model-capability.yaml:213` "GLM-5.2-era stale flag is gone", glm/glm-flash rows :201-228 with z.ai doc URLs |
| R4 native cache probe / R5 ask Z.AI | not code — open | no artifact in tree; UNVERIFIABLE from the repo |
| R6 `[1m]` trial | UNVERIFIABLE | no probe artifact found |
| R7 stop trusting local usage estimates | **APPLIED** (partial, policy) | quota gating reads dashboard % (`leadv2-quota-read.py`); no local usage_estimate treated as cost truth in dispatch |
| R8 rate limits from dashboard | open (founder action) | — |

### FIVE-DAY-AUDIT-BEFORE-STATE-OWNER-01 (8 rows)
| row | verdict | evidence |
|---|---|---|
| 1 hook-fork-guard zero callers | **APPLIED** | wired `hooks.json:102` (SessionStart); fired live at this session's start (FORK-GUARD FAIL output, 2 violations) |
| 2 hook-fork-budget zero callers → wire or delete | **NOT APPLIED — live hole #2** | census row `leadv2-hook-fork-budget.sh - not-wired`; zero wiring in hooks.json + pre-dispatch (`grep -c` 0/0); FORK-BUDGET-IS-DEAD-01 never landed |
| 3 CI never ran the suites | **APPLIED** | `.github/workflows/test-suites.yml` — per-PR `run-all --scope changed` job (:15-16) + nightly full sweep (:74-75). Required-status-checks (SD-CI-…) state UNVERIFIABLE offline |
| 4/5 salvage worktrees / 4 decisions | other tasks (SALVAGE-UNMERGED-LANES-01) | out of this audit's code scope |
| 6 pasted pass counts | other task (REPORT-PASS-COUNTS-…-01) | superseded in practice by `leadv2-suite-falsifiable.sh` + mutation-control artifacts |
| 7 115 empty worktrees | explicit no-fix (recorded reason) | — |
| 8 wrong path in prose | explicit no-fix (recorded reason) | — |

### GUARDS-MUST-PROVE-THEY-FIRE-01
| finding | verdict | evidence |
|---|---|---|
| census script / verdict lib / suite / fixtures | **APPLIED** | all four paths exist; suite 43/43 green this session; live census rc=0 `fixtures run: 13, fixture-proven: 13, regressions: 0` |
| run-all EXTRA_SUITE_MAP rows | **SUPERSEDED** | map replaced by self-registration (`# run-all-triggers:` header, `tests/run-all.sh:186-207`); `test-guard-census.sh:1-2` carries the declaration and CI selects it (proved §5) |
| Critical-0 lane-liveness single-root blindness | **NOT APPLIED** | `leadv2-lane-liveness.sh:7,41-44` still discovers only `$PROJECT_ROOT`; no multi-root merge in its history (last commits are E4-dir/third-state fixes). Partially compensated by worktree-mtime watchdog, but the named defect stands |
| Critical-0 `dead:no_log_artifact` third state | **APPLIED** | `171ca2b2` "finished_unlanded before dead:no_log_artifact" |

### GUARD-CENSUS-IS-WRONG-01
| finding | verdict | evidence |
|---|---|---|
| parser capture regex (degrade-wrapped names) | **APPLIED** | `leadv2-guard-census.sh:101-103`; locked by suite case 9 |
| dispatcher MANIFEST follow-through | **APPLIED** | census §1b (`:107-142`); case 10 |
| dispatcher records ran/verdict rows | **APPLIED** | `leadv2-bash-pre-dispatch.sh` sources guard-verdict lib; rotation `:84-91` |
| 13 real fire-path fixtures | **APPLIED** | `fixtures/guards/real/` = 13 drivers; census run this session: `fixture-proven: 13, regressions: 0` |
| DEFAULT / FIRE-DAYS / CANDIDATES-TO-DELETE | **APPLIED** | census `:521,:527` |
| R2 verdict-kind contract + journal rotation + 1-pass read | **APPLIED** | pre-dispatch rotation vars; census single-pass `$TMP/jlast.tsv` |
| R3 stale dflt on not-wired/missing rows | **APPLIED** | per-row `dflt="-"` reset (`:403-406`); case 12 |
| (new, found this task) scripts/-wired guards falsely `missing` | **was NOT APPLIED → fixed here** | §3 |

### PROMISE-GUARD-BIND-01
| finding | verdict | evidence |
|---|---|---|
| sandbox HOME + real-journal control | **APPLIED** | `test-promise-action-binding.sh` (3 sandbox-control refs); classified-block run this session: `control: real journal has no rows from this run (before=2413 after=2413)` |
| checked-in pre-fix fixture + unresolvable→FAIL | **APPLIED** | `docs/handoff/PROMISE-GUARD-BIND-01/fixtures/leadv2-promise-guard.pre-bind01.sh`; both suites reference it |
| COMMIT_RU_VERBS +поправлю/прогоню/закоммичу | **APPLIED** | `leadv2-promise-guard.sh:137-139` |
| write-regex excludes `2>/dev/null`/`2>&1` | **APPLIED** | `:306` `r'|>>?\s*(?!/dev/null\b)(?!&)\S'` |
| scheduled-decisions row parseable | **APPLIED** | `docs/leadv2/scheduled-decisions.md:9` header matches task-anchor grammar |
| fix on the running (cache) path | **APPLIED** | `grep -c classify_promise_kind` = 4 in `~/.claude/plugins/cache/leadv2-local/leadv2/0.5.7/hooks/leadv2-promise-guard.sh` |

### PROMISE-GUARD-TURN-IT-ON-01
| finding | verdict | evidence |
|---|---|---|
| flip to blocking | **APPLIED (behavioural)** | hook default `LEADV2_PROMISE_GUARD_BLOCK` = "1" (`:22`); `test-promise-guard-classified-block.sh` 8/0 green this session — the suite drives the real hook into `decision:block` |
| anchored чин/обнов regexes | **APPLIED (behavioural)** | `:375-376` `\b(?:по)?чин(?:ю|…)\b`, `\bобнов(?:лю|им|ляю)\b`; `test-promise-guard-morphology.sh` rc=0, 18 red→green + 34 green-pre-fix this session |
| rc=2 could-not-run sentinel, `_journal_lines` -1 | **APPLIED** | in `test-promise-guard-classified-block.sh` (round-3 fix); suite green |

### PROMISE-GUARD-UNKNOWN-KIND-01
| finding | verdict | evidence |
|---|---|---|
| `diagnose` kind for разбираю/смотрю/… family | **APPLIED** | `leadv2-promise-guard.sh:378-384`; `test-promise-guard-unknown-kind.sh` 21/0 green this session (suite landed in `553859ea` from a parallel session on this branch) |

### CODEX-QUOTA-GUARDRAILS-01 (fix-round-1 findings)
| finding | verdict | evidence |
|---|---|---|
| C1 session-runner opens circuit on usage-limit | **APPLIED** | `leadv2-codex-session-runner.sh:549-558` (grep signature → `codex_circuit_open` → stop retrying) |
| C2 Group F tests | **APPLIED** | `test-codex-quota-guardrails.sh:455+` (F1/F2 drive `$RUNNER_SH`) |
| H3 remove LEADV2_CODEX_SANCTIONED | **APPLIED** | `grep` in `leadv2-codex-direct-exec-guard.sh` → 0 hits |
| M4/M5 reuse spawn_gate / real c2 path | **APPLIED** | `:240` "Drives the real two-step the session-runner now performs (M5)" |
| (report.md itself) | **NOT APPLIED** | no report was ever written — the round-1 brief's acceptance ("Report per-finding status") unmet |

### CONTINUATION-GUARD-01
| finding | verdict | evidence |
|---|---|---|
| Stop hook + wiring + suite | **APPLIED** | `hooks/leadv2-continuation-guard.sh`, `hooks.json` (1 entry), `tests/test-continuation-guard.sh`; summary claims 13/13 (not re-run this session) |

### M7-TIERED-TOKEN-BUDGET-GUARD
| finding | verdict | evidence |
|---|---|---|
| 3-tier edge-triggered compact-warn + measurement + suite + doc | **APPLIED** | all 4 files exist (`hooks/leadv2-compact-warn.sh` 14 tier refs, `scripts/leadv2-turn-cost-measure.py`, `tests/test-compact-warn-tiers.sh`, `docs/context-tier-guard.md`); suite not re-run this session |

### DRIFT-GUARDS-TO-CANON-01
| finding | verdict | evidence |
|---|---|---|
| 1 lift both hooks to canon + wire BOTH places | **APPLIED** | `hooks/plugin-scripts-drift-guard.sh` + `-session-warn.sh` exist; hooks.json 8 drift refs, pre-dispatch 2; census: drift-guard `blocking`, last-fired 2026-09-02 |
| 1b persona-engine copies become symlinks | **NOT APPLIED — live hole #1** | this session's SessionStart FORK-GUARD FAIL: `persona-engine/.claude/hooks/plugin-scripts-drift-guard.sh` + `…-session-warn.sh` are REAL copies. Outside this worktree's authorized tree — left, named |
| 2 repo-install --check fails on drift | **APPLIED** | `leadv2-repo-install.sh:156-178` (drift section, uses the guard lib, never a second classifier) |

### PROCESS-AUDIT-20260821
| finding | verdict | evidence |
|---|---|---|
| falsification gate is an attestation ritual → executed paired falsification | **SUPERSEDED (landed differently)** | `leadv2-suite-falsifiable.sh` exists on main (blob 4fccc4a) and is used as a gate (PROMISE-GUARD-TURN-IT-ON r4 §6); marker-block RED-noise class gone from current dispatch selfchecks |
| review synthesis / mechanism closure pilots | **UNVERIFIABLE** | process-level, no single file:line to check; partially visible in `leadv2-review-run.sh:583-710` shape |

### Not-finished audits (rows 1,2,3,12,19)
No findings exist to check — the honest row is "audit not finished", per the mission. Row 3's
subject (unreadable-dir branch) is nonetheless defended by #13's C6a/C6b.

## 3. The fix shipped here (live hole #3, ranked below the two left standing)

**Defect:** `leadv2-guard-census.sh` resolved EVERY wired guard's file under `hooks/`. Two
guards are wired through `${CLAUDE_PLUGIN_ROOT}/scripts/` (`hooks.json:102` hook-fork-guard,
`:95/:695` lane-watch-v2). Both files exist and fire — hook-fork-guard fired at this session's
own start — yet the census printed both `missing` (rank 2, top of the dead-first table): a guard
that exists, runs, and reports its own liveness, lied about by the one table built to stop that
class of lie. Same shape as `permissionDecision: allow`: reads like a guard, isn't one.

**Fix** (`leadv2-guard-census.sh`, commit `553859ea`): new `--scripts-dir` (default
`$PLUGIN_ROOT/scripts`); a `WIRED_DIR` map built from the wiring's own directory token
(`hooks/`|`scripts/` captured off the same `hooks.json` commands); the row loop resolves
`gpath` by that map, and both the `missing` check and the DEFAULT-column grep read `gpath`.

Before (this worktree, pre-fix):
```
2  leadv2-hook-fork-guard.sh   SessionStart          missing    …  DEFAULT -
2  leadv2-lane-watch-v2.sh     SessionEnd,SessionStart missing   …  DEFAULT -
```
After:
```
leadv2-hook-fork-guard.sh  SessionStart          never-ran  ${LEADV2_HOOK_FORK_CANONICAL:-${GUARD_DIR}}
leadv2-lane-watch-v2.sh    SessionEnd,SessionStart never-ran ${LEADV2_LANE_WATCH_POLL_SEC:-60}
leadv2-hook-fork-budget.sh -                     not-wired  -   (true, unchanged)
```

**Suite + negative control inside the function body.** `test-guard-census.sh` case 13 +
`fx-scriptsdir.sh` fixture (wired via scripts/, existing only in the scripts dir):

Green (real census, this session):
```
PASS: case13 fx-scriptsdir state (wired via scripts/)
PASS: case13 fx-scriptsdir DEFAULT read from the scripts/ path
PASS: case13-mutation: hooks/-only check re-falsifies fx-scriptsdir as missing
ALL PASS: 43 checks passed            (rc=0)
```
Red (mutation applied inside the census row loop — `[ "$gdir" = "scripts" ] && gpath=…`
dropped, whole suite run against the mutant via `LEADV2_CENSUS_UNDER_TEST`):
```
FAIL: case13 fx-scriptsdir state (wired via scripts/) (got 'missing', want 'never-ran')
FAIL: case13 fx-scriptsdir DEFAULT read from the scripts/ path (got '-', want '${LEADV2_FX_SCRIPTSDIR:-0}')
FAIL: case13-mutation: hooks/-only check re-falsifies fx-scriptsdir as missing (got '', want 'missing')
SUITE RED: 40 passed, 3 FAILED         (rc=1)
```
Mutation-control at committed HEAD:
```
MUTATION-CONTROL ok suite=…test-guard-census.sh file=…leadv2-guard-census.sh \
  red_line=FAIL: case13 fx-scriptsdir state (wired via scripts/) (got 'missing', want 'never-ran') \
  diff_hash=cbf4ee58… lane_diff_hash=f1bd4055…
```

**Second implementation of the touched rule: NONE.** The rule "resolve a hooks.json-wired
guard's file by its wiring directory before declaring missing" exists only in the census.
Checked: `leadv2-bash-pre-dispatch.sh` dispatches MANIFEST guards by name (existence never
classified), `plugin-scripts-drift-guard.sh` implements symlink-vs-copy (different rule),
`leadv2-dispatch-ledger.sh:985`'s `missing` is deliverable state. The census's other consumers
are symlinks to the same inode (`~/.claude/leadv2-shared/scripts/leadv2-guard-census.sh`,
`persona-engine/.claude/scripts/leadv2-guard-census.sh` — `cmp` IDENTICAL), so no duplicate can
disarm the control.

## 4. NOT-APPLIED findings left standing, ranked

1. **persona-engine holds real copies of the two drift hooks** (DRIFT-GUARDS-TO-CANON-01 §1b) —
   fires FORK-GUARD FAIL every session start; the exact 2026-07-29 disease class. Left: outside
   this worktree's authorized tree; the fork-guard's own printed fix (`rm && ln -s`) is a
   30-second founder action in persona-engine.
2. **`leadv2-hook-fork-budget.sh` shipped dead** (FIVE-DAY row 2) — wired nowhere; fork-wall
   measurement never runs automatically. Left: wire-vs-delete is FORK-BUDGET-IS-DEAD-01's owned
   decision, and wiring touches shared hooks.json + plugin-cache deploy semantics.
3. ~~census false-missing~~ — fixed here.
4. **lane-liveness single-root scoping** (GUARDS-MUST-PROVE Critical-0) — codex-arm lanes
   dispatched from other roots stay invisible to `--all`. Left: a liveness-owning lane; large.

## 5. CI selection proof (both directions)

State file `$(git rev-parse --git-dir)/leadv2-run-all-last-checked-sha` (worktree-scoped).

Direction 1 — range `35192125..HEAD` (my change in range):
```
$ echo 35192125 > "$(...)/leadv2-run-all-last-checked-sha"
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed | grep '\[SELECT\]'
[SELECT] …/plugins/leadv2/scripts/tests/test-guard-census.sh        ← present
```
Direction 2 — range starting at HEAD (change out of range):
```
$ echo 553859ea > "$(...)/leadv2-run-all-last-checked-sha"
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed | grep '\[SELECT\]'
(no test-guard-census.sh line — only the always-on core-offline + status-surface rows)
```
State restored to `35192125` before the real changed-scope run.

## 6. Self-check

- `bash -n`: `leadv2-guard-census.sh`, `test-guard-census.sh`, `test-promise-guard-unknown-kind.sh` — OK.
- `python3 -m py_compile`: no Python files changed.
- `bash tests/run-all.sh --scope changed` (foreground via background-capture, ~25 min):

```
run-all: 6 passed, 1 failed, scope=changed
  Failures (blocking):
    - plugins/leadv2/scripts/tests/run-core-offline.sh
```

  All 6 selected suites that cover this diff PASSED (incl. `test-guard-census.sh` 43/43,
  `test-promise-guard-unknown-kind.sh` 21/0). The one failure is the ALWAYS-ON
  `run-core-offline.sh`; its 11 internal `FAILED:` labels break down as 9 on
  `tests/known-red-suites.txt` (pre-existing, FIFTEEN-RED-SUITES-01) + 2 off-list:
  `T14 worker MCP (glm spawn role config)` — its pinned pre-T14 argv baseline lacks the
  `--effort low` that GLM-EFFICIENCY-01's effort wiring now appends to the glm spawn —
  and `prepass resume invalidation (LANE-OBSERVABILITY-02)`. Neither path is touched by
  this lane's diff (census + fixtures + report only). A FOREIGN concurrent
  `tests/run-all.sh --scope changed` (pid 70437, cwd
  `worktrees/WRITESET-REFUSAL-NEVER-NAMES-THE-BLOCKER-01`, live at check time) was running
  core-offline in parallel — the measured condition that flips nested core-offline suites
  NOT-KNOWN-RED. Left for the liveness/CI owners; not widened into any known-red list.
