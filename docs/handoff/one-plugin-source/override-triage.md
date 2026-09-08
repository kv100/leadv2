# Override triage — 59 files, 4 repos, per-file proof (row C4)

Task: `ONE-PLUGIN-SOURCE-TRIAGE-THE-64-OVERRIDES-01` · lane `C4-OVERRIDE-TRIAGE` · 2026-09-09.
Machine table: `plugins/leadv2/config/override-triage.yaml` · checker: `plugins/leadv2/scripts/leadv2-override-triage.sh`
(+ negative-control suite `plugins/leadv2/tests/test-override-triage-names-the-live-file.sh`).

**Nothing was deleted.** Deletion is a lead action after reading this table.

## 1. The census — the real numbers

| repo | override files | keep | unproven | retire |
|---|---|---|---|---|
| leadv2 | 3 | 3 | 0 | 0 |
| persona-engine | 38 | 24 | 13 | 1 |
| m3-market | 11 | 8 | 2 | 1 |
| respiro-ios | 7 | 7 | 0 | 0 |
| **total** | **59** | **42** | **15** | **2** |

- **The "64" was wrong.** Recursive census of `.claude/leadv2-overrides/` in all four live repos
  (leadv2 worktree, persona-engine, m3-market, respiro-ios) counts **59 files**. campaign-platform
  (decommissioned 2026-07-28) no longer exists on disk, so its overrides cannot contribute.
- **The "24 zero-reader" list was wrong too — it is 17 candidates.** 42 of 59 files have live
  static readers; 17 have none (live=0, backup=0, loose=0 under the matcher below). fable's
  original 24-file list is **unrecoverable** (`docs/audits/one-plugin-source-fable.md` referenced by
  the §B doc does not exist), so 24 can be neither reconciled nor trusted — this table re-derives
  everything from the live trees.
- The §B source doc itself lives **outside leadv2**, untracked, at
  `persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/ONE-PLUGIN-SOURCE-RECONCILIATION.md`.

## 2. Method

**Scan domain** (per repo): leadv2 = `plugins/`, `tests/`, `.claude/` minus
{worktrees, leadv2-overrides, cache, projects, leadv2-tasks, auth-profiles, screenshots}; other
repos = `.claude/`, `scripts/`, `bin/`, `.circleci/`, `.github/` (as exist) minus the overrides
dir itself. Everywhere excluded: `docs/` (mentions are not readers), `__pycache__`,
`node_modules`, `.git`, symlinks (not followed — plugin readers are covered once by scanning
canonical leadv2), files >2 MB, and NUL-containing files. The runtime/browser-artifact exclusions
are deliberate: `m3-market/.claude/auth-profiles/` contains hundreds of MB of cache, not possible
code consumers; including it made the checker exceed a bounded foreground gate. Shared trees
(`~/.claude/leadv2-shared`, `~/.claude/agents-shared`, `~/.claude/scripts`, `~/.claude/settings.json`)
were additionally hand-searched for every candidate — zero hits.

**Matcher**, three classes per file: `path` (literal `leadv2-overrides/<relpath>`), `dir-loader`
(literal `leadv2-overrides/<parent-dir>/` — catches runtime globs like `find "$GOLDEN_DIR" -name
'*.json'`), `basename` (loose mention; blocks RETIRE, never grants liveness). `vendor-backup*`
trees count as `backup` — inert copies are not liveness but do refuse retirement.

**Dynamic loaders found** (the astra step — what a basename grep misses):
- `plugins/leadv2/scripts/leadv2-helpers.sh:120,138` — resolves `<overrides>/scripts/<name>` on
  every `_lv2_script`-style lookup (no repo currently has that subdir);
- `plugins/leadv2/scripts/leadv2-rules-eval.sh:83` + `leadv2-rules-load.sh` — globs
  `<overrides>/rules/` (persona-engine's 6 rule files are alive through it);
- `plugins/leadv2/scripts/leadv2-eval-harness.sh:49,86` — `find <overrides>/golden -name '*.json'`
  (bandit-sample-seeded.json is consumed by a dir-glob whose *engine* is otherwise unreferenced);
- `plugins/leadv2/scripts/leadv2-helpers.sh:348` — `rules_dir` key of quality-engine.yaml redirects
  the rules glob at runtime;
- fixed-name readers: state-paths.yaml, codex-policy.yaml, quality-engine.yaml, stack.yaml,
  nested-spawn-policy.yaml (hooks + helpers, plugin and repo-native copies).

**Session evidence**: path-qualified + bare-name search over all four projects' transcript corpora
(`~/.claude/projects/<proj>*`, every session, own audit session excluded) plus
`~/.claude/leadv2-state/`; hits classified `tool_use` vs prose. Only `ls -la` listings by census /
audit sessions were found for the two retire candidates — no production-path read.

## 3. RETIRE — both files pass all four proofs (2)

#### `persona-engine/gemini-policy.yaml`

PROOF4/4: (1) consumer: zero static readers in plugin (plugins/,tests/,.claude), repo (.claude,scripts,bin,.circleci,.github), shared trees (~/.claude/leadv2-shared, agents-shared, ~/.claude/scripts, ~/.claude/settings.json), whole-repo rg. (2) dynamic: bare 'gemini-policy' searched same surfaces — zero code references; every located loader composes a fixed name (state-paths/codex-policy/quality-engine/stack) or one of overrides/scripts/*, overrides/rules/*, overrides/golden/* (leadv2-helpers.sh:120,138; leadv2-rules-eval.sh:83; leadv2-eval-harness.sh:49) — none reaches this file. (3) absent-file default: no consumer, so deletion changes nothing. (4) session: only ls -la listings by census/audit sessions (persona-engine 123266e0 + 376135a4 subagents, 1PLUGIN-FABLE-2); no production-path read in any recorded session corpus.

#### `m3-market/gemini-policy.yaml`

PROOF4/4: same method as persona-engine/gemini-policy.yaml — zero static readers, zero dynamic-loader compositions (plugin + m3 .claude/scripts/codex-liveness.sh reads only codex-policy.yaml:15 + shared trees + whole-repo rg), absence unobservable, session corpus shows only ls listings by audit sessions; no production read.


## 4. UNPROVEN — proofs recorded, retirement refused (15)

These satisfy the four-proof recording requirement but something blocks deletion; `UNPROVEN` is
not rounded down.

| repo | path | why not RETIRE |
|---|---|---|
| persona-engine | `.state/trust-alarm.json` | (1) no external consumer; writer is inside the overrides dir (excluded from scan domain). (2) dynamic: 'trust-alarm' searched plugin+repo+shared trees — single hit is that writer. (3) absent-file default = state reset on next probe run. (4) session: read only by 1PLUGIN-FABLE-2 audit session (tool_use 8c64cbf9). Verdict: runtime state misplaced in overrides dir — RELOCATION candidate, lead decision, not a delete candidate. |
| persona-engine | `tests/gate1-businesssignal-selftest.sh` | (1) zero static readers anywhere. (2) dynamic: persona-engine run-all selects tests/unit/test-*.sh only (run-all.sh:383,543); gate1.sh never invokes its selftest; no glob reaches overrides/tests. (3) absence unobservable. (4) zero hits in all four projects' session corpora (path-qualified + bare). BUT the file is an acceptance test of LIVE gate1.sh (consumed by .claude/skills/leadv2-preflight-business-signal/SKILL.md:139) — deletion loses the self-check; wire into run-all or delete is a lead decision. |
| persona-engine | `tests/rule-fixtures/R-001-bash-syntax-check.negative.txt` | evaluation fixture (positive/negative sample) mirroring LIVE rule rules/R-001-bash-syntax-check.rule.md (rules engine consumes rules/*.rule.md via leadv2-rules-load.sh dir-glob); zero static readers (no code references rule-fixtures), zero dynamic loaders, absence unobservable, zero session hits. Same deliberate-keep class as golden/bandit-sample-seeded.json — lead decision. |
| persona-engine | `tests/rule-fixtures/R-001-bash-syntax-check.positive.txt` | evaluation fixture (positive/negative sample) mirroring LIVE rule rules/R-001-bash-syntax-check.rule.md (rules engine consumes rules/*.rule.md via leadv2-rules-load.sh dir-glob); zero static readers (no code references rule-fixtures), zero dynamic loaders, absence unobservable, zero session hits. Same deliberate-keep class as golden/bandit-sample-seeded.json — lead decision. |
| persona-engine | `tests/rule-fixtures/R-002-emit-retry-zero.negative.txt` | evaluation fixture (positive/negative sample) mirroring LIVE rule rules/R-002-emit-retry-zero.rule.md (rules engine consumes rules/*.rule.md via leadv2-rules-load.sh dir-glob); zero static readers (no code references rule-fixtures), zero dynamic loaders, absence unobservable, zero session hits. Same deliberate-keep class as golden/bandit-sample-seeded.json — lead decision. |
| persona-engine | `tests/rule-fixtures/R-002-emit-retry-zero.positive.txt` | evaluation fixture (positive/negative sample) mirroring LIVE rule rules/R-002-emit-retry-zero.rule.md (rules engine consumes rules/*.rule.md via leadv2-rules-load.sh dir-glob); zero static readers (no code references rule-fixtures), zero dynamic loaders, absence unobservable, zero session hits. Same deliberate-keep class as golden/bandit-sample-seeded.json — lead decision. |
| persona-engine | `tests/rule-fixtures/R-003-grep-only-schema-verify.negative.txt` | evaluation fixture (positive/negative sample) mirroring LIVE rule rules/R-003-grep-only-schema-verify.rule.md (rules engine consumes rules/*.rule.md via leadv2-rules-load.sh dir-glob); zero static readers (no code references rule-fixtures), zero dynamic loaders, absence unobservable, zero session hits. Same deliberate-keep class as golden/bandit-sample-seeded.json — lead decision. |
| persona-engine | `tests/rule-fixtures/R-003-grep-only-schema-verify.positive.txt` | evaluation fixture (positive/negative sample) mirroring LIVE rule rules/R-003-grep-only-schema-verify.rule.md (rules engine consumes rules/*.rule.md via leadv2-rules-load.sh dir-glob); zero static readers (no code references rule-fixtures), zero dynamic loaders, absence unobservable, zero session hits. Same deliberate-keep class as golden/bandit-sample-seeded.json — lead decision. |
| persona-engine | `tests/rule-fixtures/R-004-silent-source-fail.negative.txt` | evaluation fixture (positive/negative sample) mirroring LIVE rule rules/R-004-silent-source-fail.rule.md (rules engine consumes rules/*.rule.md via leadv2-rules-load.sh dir-glob); zero static readers (no code references rule-fixtures), zero dynamic loaders, absence unobservable, zero session hits. Same deliberate-keep class as golden/bandit-sample-seeded.json — lead decision. |
| persona-engine | `tests/rule-fixtures/R-004-silent-source-fail.positive.txt` | evaluation fixture (positive/negative sample) mirroring LIVE rule rules/R-004-silent-source-fail.rule.md (rules engine consumes rules/*.rule.md via leadv2-rules-load.sh dir-glob); zero static readers (no code references rule-fixtures), zero dynamic loaders, absence unobservable, zero session hits. Same deliberate-keep class as golden/bandit-sample-seeded.json — lead decision. |
| persona-engine | `tests/rule-fixtures/R-005-live-state-in-repo.negative.txt` | evaluation fixture (positive/negative sample) mirroring LIVE rule rules/R-005-live-state-in-repo.rule.md (rules engine consumes rules/*.rule.md via leadv2-rules-load.sh dir-glob); zero static readers (no code references rule-fixtures), zero dynamic loaders, absence unobservable, zero session hits. Same deliberate-keep class as golden/bandit-sample-seeded.json — lead decision. |
| persona-engine | `tests/rule-fixtures/R-005-live-state-in-repo.positive.txt` | evaluation fixture (positive/negative sample) mirroring LIVE rule rules/R-005-live-state-in-repo.rule.md (rules engine consumes rules/*.rule.md via leadv2-rules-load.sh dir-glob); zero static readers (no code references rule-fixtures), zero dynamic loaders, absence unobservable, zero session hits. Same deliberate-keep class as golden/bandit-sample-seeded.json — lead decision. |
| persona-engine | `tests/test-canary-soak-probe.sh` | (1) zero static readers. (2) dynamic: skills leadv2-canary-soak/leadv2-soak-watch reference repo-native .claude/scripts/canary-soak-probe.sh, not this test; no test-discovery glob reaches overrides/tests. (3) absence unobservable. (4) zero session hits. BUT tests a LIVE probe — dead test of live code; lead decision. |
| m3-market | `archive/leadv2.md.fork-2026-08-17` | deliberate archive of the pre-fork /leadv2 command (created by mv in persona-engine session 123266e0 on 2026-08-17); zero static/dynamic readers since; zero session reads after creation. Deletion is a history decision (content preserved in git), not a liveness one — lead decision. |
| m3-market | `mission-templates.md` | (1) no reader outside the overrides dir (extensions.md itself is KEEP — read at session bootstrap). (2) dynamic: no loader composes it; bare 'mission-templates' hits only extensions.md + docs. (3) absence degrades extensions.md instructions. (4) session: referenced as live working documentation in m3-market session e0381adf ('exact stop-condition wording that works'). ALIVE-BY-INSTRUCTION — not a delete candidate. |

## 5. KEEP — live consumers (42)

| repo | path | verdict | consumer (pinned) |
|---|---|---|---|
| leadv2 | `deploy.sh` | keep | `leadv2:plugins/leadv2/scripts/leadv2-deploy-merge.sh` |
| leadv2 | `stack.yaml` | keep | `leadv2:plugins/leadv2/commands/leadv2.md` |
| leadv2 | `status-collector-facts.sh` | keep | `leadv2:plugins/leadv2/scripts/leadv2-status-collector.sh` |
| persona-engine | `active-limits.yaml` | keep | `leadv2:plugins/leadv2/scripts/leadv2-active-registry.sh` |
| persona-engine | `backlog-pump.yaml` | keep | `leadv2:plugins/leadv2/scripts/leadv2-backlog-pump.sh` |
| persona-engine | `codex-policy.yaml` | keep | `leadv2:plugins/leadv2/commands/leadv2mode.md` |
| persona-engine | `deploy-verify.sh` | keep | `leadv2:plugins/leadv2/scripts/leadv2-deploy-merge.sh` |
| persona-engine | `deploy.sh` | keep | `leadv2:plugins/leadv2/scripts/leadv2-deploy-merge.sh` |
| persona-engine | `extensions.md` | keep | `leadv2:plugins/leadv2/agents/README.txt` |
| persona-engine | `gate1.sh` | keep | `persona-engine:.claude/skills/leadv2-preflight-business-signal/SKILL.md` |
| persona-engine | `golden/bandit-sample-seeded.json` | keep | `leadv2:plugins/leadv2/scripts/leadv2-eval-harness.sh` |
| persona-engine | `omp-task.sh` | keep | `leadv2:plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` |
| persona-engine | `outcome-watch.sh` | keep | `leadv2:plugins/leadv2/skills/leadv2-close/SKILL.md` |
| persona-engine | `quality-engine.yaml` | keep | `leadv2:plugins/leadv2/scripts/leadv2-helpers.sh` |
| persona-engine | `rules/R-001-bash-syntax-check.rule.md` | keep | `leadv2:plugins/leadv2/scripts/leadv2-helpers.sh` |
| persona-engine | `rules/R-002-emit-retry-zero.rule.md` | keep | `leadv2:plugins/leadv2/scripts/leadv2-helpers.sh` |
| persona-engine | `rules/R-003-grep-only-schema-verify.rule.md` | keep | `leadv2:plugins/leadv2/scripts/leadv2-helpers.sh` |
| persona-engine | `rules/R-004-silent-source-fail.rule.md` | keep | `leadv2:plugins/leadv2/scripts/leadv2-helpers.sh` |
| persona-engine | `rules/R-005-live-state-in-repo.rule.md` | keep | `leadv2:plugins/leadv2/scripts/leadv2-helpers.sh` |
| persona-engine | `rules/R-006-silent-feature-gate.rule.md` | keep | `leadv2:plugins/leadv2/scripts/leadv2-helpers.sh` |
| persona-engine | `stability-policy.yaml` | keep | `persona-engine:.claude/scripts/confidence-score.sh` |
| persona-engine | `stack.yaml` | keep | `leadv2:plugins/leadv2/commands/leadv2.md` |
| persona-engine | `state-paths.yaml` | keep | `leadv2:plugins/leadv2/hooks/leadv2-lead-prose-guard.sh` |
| persona-engine | `status-collector-facts.sh` | keep | `leadv2:plugins/leadv2/scripts/leadv2-status-collector.sh` |
| persona-engine | `supervise-truth-probe.sh` | keep | `leadv2:plugins/leadv2/scripts/leadv2-lanes-snapshot.sh` |
| persona-engine | `toolsets.yaml` | keep | `leadv2:plugins/leadv2/skills/leadv2-plan/REFERENCE.md` |
| persona-engine | `verify.sh` | keep | `leadv2:plugins/leadv2/scripts/leadv2-mythicalgames-overrides-gen.sh` |
| m3-market | `codex-policy.yaml` | keep | `leadv2:plugins/leadv2/commands/leadv2mode.md` |
| m3-market | `deploy.sh` | keep | `leadv2:plugins/leadv2/scripts/leadv2-deploy-merge.sh` |
| m3-market | `extensions.md` | keep | `leadv2:plugins/leadv2/agents/README.txt` |
| m3-market | `frontend-paths.txt` | keep | `leadv2:plugins/leadv2/skills/leadv2-verify/BROWSER-QA.md` |
| m3-market | `outcome-watch.sh` | keep | `leadv2:plugins/leadv2/skills/leadv2-close/SKILL.md` |
| m3-market | `stack.yaml` | keep | `leadv2:plugins/leadv2/commands/leadv2.md` |
| m3-market | `state-paths.yaml` | keep | `leadv2:plugins/leadv2/hooks/leadv2-lead-prose-guard.sh` |
| m3-market | `verify.sh` | keep | `leadv2:plugins/leadv2/scripts/leadv2-mythicalgames-overrides-gen.sh` |
| respiro-ios | `codex-policy.yaml` | keep | `leadv2:plugins/leadv2/commands/leadv2mode.md` |
| respiro-ios | `deploy.sh` | keep | `leadv2:plugins/leadv2/scripts/leadv2-deploy-merge.sh` |
| respiro-ios | `extensions.md` | keep | `leadv2:plugins/leadv2/agents/README.txt` |
| respiro-ios | `outcome-watch.sh` | keep | `leadv2:plugins/leadv2/skills/leadv2-close/SKILL.md` |
| respiro-ios | `stack.yaml` | keep | `leadv2:plugins/leadv2/commands/leadv2.md` |
| respiro-ios | `state-paths.yaml` | keep | `leadv2:plugins/leadv2/hooks/leadv2-lead-prose-guard.sh` |
| respiro-ios | `verify.sh` | keep | `leadv2:plugins/leadv2/scripts/leadv2-mythicalgames-overrides-gen.sh` |

## 6. Checker and negative controls

`leadv2-override-triage.sh` re-derives every verdict from the live trees and compares to the yaml.
Contract: `checked=N` printed on every run (N=0 ⇒ exit 4, a failure, never a pass); every
disagreement names the file, the yaml verdict, the derived verdict and the reason
(`retire-blocked` / `keep-broken` / `consumer-gone` / `file-missing` / `verdict-drift`).

Live table, live repos:

```
$ plugins/leadv2/scripts/leadv2-override-triage.sh
checked=59 skipped=0 disagree=0
```

Negative control 1 — the symptom (RETIRE file gains a real reader), real checker vs
comparison-disabled mutant (mutation applied inside `compare_entry()`'s body):

```
$ .../leadv2-override-triage.sh          # real checker, planted reader
MISMATCH leadv2/alpha.yaml yaml=retire derived=keep reason=retire-blocked detail=gained reader: leadv2:.claude/scripts/run.sh:2
checked=3 skipped=0 disagree=1
rc=1

$ bash mut-compare.sh                    # 'if entry_verdict != derived:' -> 'if False:'
checked=3 skipped=0 disagree=0
rc=0        <- the red the control exists to catch: detection genuinely depends on the comparison
```

Negative control 2 — the guard (scan mutated to examine nothing must refuse to pass):

```
$ bash mut-empty.sh                      # 'for entry in entries:' -> 'for entry in []:'
[override-triage] FAILURE: examined zero entries — an empty scan is a failure, not a pass
checked=0 skipped=0 disagree=0
rc=4
```

Full suite (5 cases incl. both mutations as killrate assertions):

```
$ bash plugins/leadv2/tests/test-override-triage-names-the-live-file.sh
case 1 GUARD: matching tree passes with checked>0
  ok   guard green, checked=3
case 2 SYMPTOM: retire file gains a reader -> named + non-zero
  ok   symptom named, rc=1
case 3 KEEP-BROKEN: consumer vanishes -> named + non-zero
  ok   keep-broken named, rc=1
case 4 MUTATION m1: comparison disabled in function body -> symptom detection lost
  ok   m1 killed: detection genuinely depends on compare_entry()
case 5 MUTATION m2: scan examines nothing -> checked=0 refuses to pass
  ok   m2 killed: empty scan exits rc=4
PASS test-override-triage-names-the-live-file
```

Registration (stateless selection oracle):

```
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | grep override-triage
leadv2-override-triage:plugins/leadv2/tests/test-override-triage-names-the-live-file.sh
override-triage:plugins/leadv2/tests/test-override-triage-names-the-live-file.sh
```

## 7. Falsification set

```
$ bash -n plugins/leadv2/scripts/leadv2-override-triage.sh   -> OK
$ bash -n plugins/leadv2/tests/test-override-triage-names-the-live-file.sh -> OK
$ python3 -m py_compile ...                                   -> n/a (no .py files changed)
```

Red → green on the live tree (first run of the checker against the real yaml — it caught its own
scan-domain bug: the overrides dir itself, the yaml table and the checker were being scanned as
"readers", producing 13 false disagreements; after the domain fix, full agreement):

```
$ plugins/leadv2/scripts/leadv2-override-triage.sh        # RED, before the fix
MISMATCH persona-engine/.state/trust-alarm.json yaml=unproven derived=keep reason=verdict-drift detail=live=15 backup=0 loose=17
MISMATCH persona-engine/gemini-policy.yaml yaml=retire derived=unproven reason=retire-blocked detail=gained reader: backup/loose hit
MISMATCH persona-engine/tests/gate1-businesssignal-selftest.sh yaml=unproven derived=keep reason=verdict-drift detail=live=15 backup=0 loose=1
MISMATCH persona-engine/tests/test-canary-soak-probe.sh yaml=unproven derived=keep reason=verdict-drift detail=live=16 backup=0 loose=16
MISMATCH persona-engine/rules/R-001-bash-syntax-check.rule.md yaml=keep reason=consumer-gone: ... (+8 more of the same classes)
checked=59 skipped=0 disagree=13
rc=1

$ plugins/leadv2/scripts/leadv2-override-triage.sh        # GREEN, after the fix
checked=59 skipped=0 disagree=0
rc=0
```

Changed-scope runner:

```
$ LEADV2_SUITE_LOCK_DISABLE=1 timeout 300s bash tests/run-all.sh --scope changed
changed-scope rc=124
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/C4-OVERRIDE-TRIAGE/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
```

This is a **bounded ambient-gate failure**, not a green result: the delegated core runner emitted
no suite result before the 300-second limit. `LEADV2_SUITE_LOCK_DISABLE=1` was used so this result
cannot be a contended-lock wait. The focused lane proof is green (checker + the full five-case
negative-control suite above), and the stateless selection oracle chose this suite; a lead must
resolve the core-runner timeout before treating the broad changed-scope gate as closure evidence.

## 8. Corrections to the record

- census total: **59**, not 64 (fable's audit basis unrecoverable);
- zero-reader candidates: **17**, not 24;
- the hook self-reference trap is real and bit during development: the triage yaml and the checker
  itself name every candidate path, so both are excluded from the scan domain
  (`SELF_FILES`), and the overrides dir itself is excluded because intra-override references
  (extensions.md → mission-templates.md, supervise-truth-probe.sh → .state/trust-alarm.json) are
  recorded by hand in the evidence fields instead of being counted as liveness.
