# Script-size audit — the files are too large, but size is not what makes lanes slow

Measured 2026-08-21 at `7729515b341b41c49d137d273ad94147373b9f56` on Apple
Silicon/Darwin 25.5.0 with GNU Bash 5.3.9. Scope is production shell under
`plugins/leadv2/scripts/` plus `scripts/lib/`; tests are excluded unless explicitly named.

## Executive verdict

The plugin is large: **78,509 physical lines across 214 production shell files** (204 top-level
scripts plus 10 `lib/*.sh`). The brief's 78,509-line total is correct; “204 (+ lib)” is **214
files**, not 204 total.

The evidence does **not** support “lanes are slow because Bash must parse huge files.” An empty Bash
process measured 10.45 ms median. Thirteen of the largest 15 files parsed in 10.0-10.8 ms total;
only the two dispatchers reached about 20.2 ms. Historical provider work is 146-933 seconds median,
so wrapper parse/startup is below 0.01% of the measured provider subsets. The slow local paths are
subprocess-heavy, making process/filesystem churn a profiling hypothesis rather than an established
cause: status rendering took 1.14 s with at least 69 shell-visible external commands, router resolution
346 ms with at least 32, and backlog-pump dry-run 1.62 s with at least 301 (286 were `stat`).

**Repository inference:** the current structure raises correctness and review risk; this audit did
not measure review rounds by touched file. The largest genuine Bash function is 1,009 lines with 136
branch-like lines. The GLM/Kimi coder implementations are 86-88% identical, a copied
exclusion set demonstrably drifted and refused two completed lanes on 2026-08-21, two current
failure paths reproducibly abort under `set -u`, and large files receive most absolute fix touches.
History shows that change and absolute fix touches are concentrated in large files. The
duplicated-policy and failure-path examples demonstrate structural risk but do not establish that
failure-path risk is concentrated by size.

The right response is **not a rewrite**. Keep Bash for thin CLI/process plumbing. Extract existing
Python-in-substance state, rendering, liveness, and reaper programs into importable Python modules;
deduplicate the GLM/Kimi lifecycle in Bash first. Treat three statically unwired scripts totaling
538 lines as versioned removal candidates after an external/manual-use check. Instrument a unified
lane trace before making performance claims about end-to-end shares.

Evidence labels used below:

- **Measured**: reproduced timing, count, test, history calculation, or failure.
- **Repository inference**: static callsite/config evidence; not a runtime trace.
- **Estimate**: engineering cost or expected frequency, explicitly not measured.

## Q1. Runtime: startup cost is tiny; the slow probes are subprocess-heavy

### Measurement contract and limitation

**Measured.** Timings used one warm-up and 15 repetitions for `bash -n`; safe probe paths
normally used 11 repetitions (five for slow real-state paths). “Beyond-parser overhead” is probe
wall minus full-file `bash -n`; it includes initialization,
library sourcing, validation, and lookup—not just lane work. External-command counts are xtrace
lower bounds: Bash builtins/functions were removed, but commands inside an executed binary,
untraced child shell, builtin-only subshell, or some pipelines are not visible. They are not total
descendant-process counts.

Unsafe full paths were deliberately not executed: no provider call, deploy, publish, lane kill,
daemon loop, live product-close, or review engine. A `--help`/validation/status timing is labeled as
such and must not be mistaken for full work. The repository has no unified trace joining lane start,
all helpers, review, deploy, live verification, and close; therefore exact invocations/lane,
descendant-process counts, and percentage of total lane wall are **not measured** for most rows.
The provider percentages below are bounded measured subsets. Q1 is answered for parser cost and
safe probes, but its requested exact whole-lane attribution remains an instrumentation gap.

### Largest 15 production shell files

| Script | LOC | Startup + parse, median | Safe probe | Probe wall / beyond-parser overhead | Shell-visible external commands (lower bound) | Frequency evidence | Measured lane-wall share |
|---|---:|---:|---|---:|---:|---|---|
| `leadv2-dispatch-code.sh` | 5,549 | 20.16 ms | `--help` after initialization | 129.66 / 109.50 ms | 7 | Conditional funnel; exact invocations/lane not traced. Close worker condition at `plugins/leadv2/scripts/leadv2-dispatch-code.sh:3085,3108`. | Not measured. |
| `leadv2-status-surface.sh` | 3,259 | 10.04 ms | real current-state `--oneline` | 1,140.5 / 1,130.5 ms | 69 | Parent/UI work, not awaited lane work; 5 s watcher at `plugins/leadv2/scripts/leadv2-status-watch.sh:54,74`, 8 s cache at `leadv2-status-surface.5s.sh:226`. | Not lane work. |
| `leadv2-dispatch-product-close.sh` | 2,667 | 20.29 ms | parse only | not run | not run | 0/1 per dispatch: one only when E2E or review is enabled; otherwise zero (`leadv2-dispatch-code.sh:3085,3108-3109`). | Not measured. |
| `leadv2-helpers.sh` | 2,594 | 10.81 ms | source/export functions | 20.38 / 9.58 ms | 2 | Library; 70 non-comment literal references in 55 production files; dispatcher source at `leadv2-dispatch-code.sh:420`. Invocations/lane not measured. | Not measured. |
| `leadv2-fanout.sh` | 1,965 | 10.46 ms | `--help`, drift guard off | 19.90 / 9.45 ms | 1 | Parent launcher, zero inside a child lane; resolved by `leadv2-session-spawner.sh:24`. | Not lane work. |
| `codex-task.sh` | 1,862 | 10.62 ms | autoreap-off missing-job `status` | 183.76 / 173.14 ms | 6 | Historical: 183 jobs/104 lane-like worktrees; median 1 job/lane, p90 3, max 11. | Parse is 0.0066% of task and 0.0073% of review provider median. |
| `kimi-coder.sh` | 1,804 | 10.51 ms | isolated missing-run `status` | 39.60 / 29.10 ms | 4 | Historical: 29 runs/26 lane-like repos; median 1, p90 1, max 3. | Parse is 0.0013% of successful-run median. |
| `glm-coder.sh` | 1,773 | 10.58 ms | isolated missing-run `status` | 39.36 / 28.78 ms | 4 | Historical: 165 runs/121 lane-like repos; median 1, p90 2, max 11. | Parse is 0.0011% of successful-run median. |
| `leadv2-lanes-snapshot.sh` | 1,389 | 10.57 ms | `--help` before reconciliation | 20.19 / 9.62 ms | 1 | Parent/status work; called once per collection at `leadv2-status-collector.sh:115`. | Not lane work. |
| `leadv2-review-run.sh` | 1,217 | 10.54 ms | invalid-argument validation | 20.52 / 9.98 ms | 1 | 0/1 per close, gated by `LEADV2_REVIEW_ENGINE=1` at `leadv2-dispatch-product-close.sh:2227,2234-2235`; current default is inline review. | Not measured. |
| `claude-subsession.sh` | 1,139 | 10.44 ms | invalid-argument usage | 40.42 / 29.98 ms | 3 | Artifact population is not an invocation trace: architect streams for 78 signatures, developer for 25; router call at `claude-subsession.sh:617`. | Two parses are 0.0024% of paired architect+developer provider median. |
| `leadv2-router.sh` | 1,125 | 10.10 ms | valid `review/standard`, no task id | 346.01 / 335.91 ms | 32 | Static workflow suggests multiple routes; exact invocations/lane not measured. | Not measured. |
| `leadv2-lane-status-line-tail.sh` | 1,071 | 10.52 ms | full calculation, isolated cache | 128.30 / 117.78 ms | 32 | Detached UI work; 2 s minimum refresh and launch at `leadv2-lane-status-line.sh:106,302-305`. | Not awaited lane work. |
| `leadv2-daemon.sh` | 994 | 10.49 ms | `--help` before state writes | 19.66 / 9.17 ms | 3 | Parent orchestrator, zero inside child; no production executable caller found. | Not lane work. |
| `leadv2-backlog-pump.sh` | 984 | 10.37 ms | real `dry-run 1` | 1,624.4 / 1,614.0 ms | 301 | Parent work; pulse calls `check` at `leadv2-pulse-beat.sh:322-324`, normally throttled to 1,800 s at `:45-46`. | Not lane work. |

**Measured interpretation.** Apart from the two dispatchers, full parsing is indistinguishable from
the 10.45 ms process-start baseline at this resolution. The 1.14-1.62 s local outliers are
subprocess-heavy. That makes process/filesystem churn the first profiling hypothesis, not a measured
cause; Python bodies, lock contention, and the external commands' own work remain alternatives.

### Historical work and bounded lane attribution

- Claude streams with terminal durations: architect n=74, median 229.916 s; developer n=25,
  median 874.926 s; critic n=12, median 77.099 s. Seventeen signatures with architect+developer had
  a summed median of 870.003 s. One concrete pair is recorded at
  `docs/handoff/dispatch-237f8026-architect/architect.stream.jsonl:137` and
  `docs/handoff/dispatch-237f8026/developer.stream.jsonl:137`.
- GLM: 403 timestamp-complete runs; 235 successful runs had median 932 s.
- Kimi: 55 successful timestamp-complete runs had median 783 s; 34 failures had median 2 s because
  fast admission/provider failures mix with long failures.
- Codex: after excluding timestamp spans over two hours (stale/reaper completion outliers), 393
  tasks had median 161.6 s and 409 adversarial reviews had median 146.3 s.

Against those medians, one wrapper parse is 0.0011% of GLM success, 0.0013% of Kimi success,
0.0066% of a Codex task, and 0.0073% of a Codex review. Two `claude-subsession.sh` parses are about
0.0024% of the paired Claude subset. Even adding both dispatcher parse ceilings stays below 0.01%.
These are upper bounds on parse importance within provider work, not exact whole-lane percentages.

## Q2. Correctness: size is a concentration signal, not a causal proof

### History says “where fixes land,” not “LOC causes bugs”

**Measured.** Across the 214 files, LOC versus fix-commit touches has Pearson `r=0.835`. The largest
quartile receives 311/439 (70.8%) of current-file touches from commits whose subject begins `fix`;
the largest 15 receive 163/439 (37.1%). But LOC correlates slightly more strongly with all commit
touches (`r=0.860`), while LOC versus each file's fraction of fix touches is only `r=0.205`.

The defensible conclusion is that large files concentrate change and absolute fix exposure. This
audit did not normalize for age, criticality, or semantic edit size, so it does not establish that a
line added to a large file is more defect-prone.

| File | LOC | Fix-commit touches | All touches | Fix share |
|---|---:|---:|---:|---:|
| `leadv2-dispatch-code.sh` | 5,549 | 49 | 91 | 53.8% |
| `leadv2-dispatch-product-close.sh` | 2,667 | 26 | 44 | 59.1% |
| `leadv2-plugin-sync.sh` | 805 | 20 | 30 | 66.7% |
| `leadv2-phase8-close.sh` | 658 | 19 | 31 | 61.3% |
| `leadv2-helpers.sh` | 2,594 | 15 | 23 | 65.2% |
| `leadv2-status-surface.sh` | 3,259 | 15 | 22 | 68.2% |
| `claude-subsession.sh` | 1,139 | 11 | 22 | 50.0% |
| `codex-task.sh` | 1,862 | 10 | 19 | 52.6% |

The two dispatch/close files alone account for 75/439 (17.1%) of fix-file touches.

### Longest functions and review load

Branch-like counts are a lexical proxy (`if`/`elif`/loops/`case`/`&&`/`||`), not cyclomatic
complexity. Five of the seven longest shell functions are chiefly embedded Python; they remain
monolithic review/test units, but calling their control flow “Bash complexity” would be misleading.

| Function and exact span | Physical LOC | Embedded Python | Branch-like lines |
|---|---:|---:|---:|
| `_ss_lanes_py`, `leadv2-status-surface.sh:339-1530` | 1,192 | 1,188 | 197 |
| `cmd_resolve`, `leadv2-dispatch-code.sh:4278-5286` | 1,009 | 0 | 136 |
| `render_single_lead`, `leadv2-status-surface.sh:2403-3177` | 775 | 712 | 137 |
| `_codex_reap`, `codex-task.sh:571-1025` | 455 | 449 | 49 |
| `lv2_selfcheck_run`, `lib/leadv2-builder-selfcheck.sh:87-534` | 448 | 0 | 73 |
| `_tasks_dispatch`, `leadv2-tasks-lib.sh:38-452` | 415 | 411 | 74 |
| `render_questions`, `leadv2-status-surface.sh:1748-2157` | 410 | 398 | 112 |
| `_leadv2_settings_py_lock`, `leadv2-helpers.sh:1601-1873` | 273 | 266 | 33 |
| `_spawn_worker_body`, `leadv2-dispatch-code.sh:3176-3441` | 266 | 0 | 29 |
| `cmd_probe`, `leadv2-red-first-gate.sh:160-413` | 254 | 149 | 45 |

`cmd_resolve` is the clearest genuinely-Bash outlier: 1,009 lines and 136 branch-like lines with no
language boundary. **Repository inference:** that span is review-hostile, but review rounds by
touched function/file were not measured in this audit.

### Duplicated policy has already drifted

**Measured exact-line overlap:** GLM -> Kimi coder has 1,556 ordered common lines (87.8% of GLM,
86.3% of Kimi); GLM -> Kimi session runner has 388 (87.0%/81.7%). Both coders contain separate
232-line `parse_stream` and roughly 247-line `cmd_supervise` functions
(`glm-coder.sh:563-794,1317-1565`; `kimi-coder.sh:593-824,1341-1586`). Three session runners copy a
26-line `_append_receipt` implementation at `leadv2-glm-session-runner.sh:122-147`,
`leadv2-kimi-session-runner.sh:151-176`, and `leadv2-codex-session-runner.sh:159-184`.

The exact Git pathspec pair excluding `docs/leadv2` and `docs/handoff` appears at 16 production
sites in five files (`leadv2-phase8-e2e-gate.sh:229-230`, `leadv2-e2e-ownership.sh:123-124`,
`leadv2-dispatch-code.sh:4230-4232`, `leadv2-dispatch-product-close.sh:1450-1453,1631-1637,2175-2176`,
and `leadv2-helpers.sh:2518-2519`). The semantics are not necessarily identical, so this is a drift
surface, not a mandate for one global constant.

The demonstrated failure is narrower and stronger. Before `5a792f1`, two porcelain call sites in
`leadv2-dispatch-product-close.sh` carried independent exclusion regexes. One was widened while the
other was not, so two completed 2026-08-21 lanes were refused for orchestration-owned
`docs/LEAD_V2_STATE.md` and `__pycache__/*.pyc` dirt. Current code centralizes
`_PC_PORCELAIN_EXCLUDE_RE` at `:1147` and uses it at `:1154-1155,1872-1873`; the structural test is
`plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh:49-84`.

### Failure-only `set -u` paths are real, current, and historically harmful

All 214 files pass `bash -n`, but syntax does not exercise nounset expansions. ShellCheck surfaced
seven `SC2154` sites in five production files; manual triage reproduced two current failures:

1. A malformed successful queue-claim response enters intended recovery, then expands undeclared
   `_env_file` and aborts at `leadv2-helpers.sh:1988`. No test directly names `leadv2_po_claim`,
   `_env_file`, or its “unexpected output” diagnostic.
2. Failure to read staged `docs/tasks.yaml` reaches typo expansion `$staged` and aborts at
   `leadv2-tasks-clobber-guard.sh:134`. No shell test directly names the guard or `staged_yaml`.

Commit `40922a8` records the same class in production: `PC_STOP_GATE_FOREIGN_REPOS` was unbound on a
timeout-reap path, aborting product-close before intended exit 5 and causing the sixth worker death
on that lane. The current guard is within `leadv2-dispatch-product-close.sh:1461-1573`.

### High-use symbols without directly selectable test seams

These are non-comment token references, not a call graph; zero direct test references does not mean
zero transitive integration coverage.

| Symbol | Production references/files | Direct test references | Definition evidence |
|---|---:|---:|---|
| `leadv2_tasks_unclaim` | 23 / 7 | 0 | `leadv2-tasks-lib.sh:477` |
| `_append_receipt` | 20 / 3 | 0 | three copied runner definitions above |
| `leadv2_active_unregister` | 17 / 7 | 0 | `leadv2-active-registry.sh:604`, `leadv2-helpers.sh:1476` |
| `_leadv2_yaml_lockfile` | 17 / 5 | 0 | `leadv2-active-registry.sh:65` |
| `_leadv2_yaml_py_lock` | 15 / 3 | 0 | `leadv2-active-registry.sh:93` |
| `_atomic_write_yaml` | 6 / 5 | 0 | `leadv2-helpers.sh:1054` |

## Q3. Bash versus Python: keep the boundary, move the substance

### What is already Python

**Measured.** The 214 shell files contain **17,173 embedded-Python body lines in 240 heredocs**
(21.9% of nominal shell LOC). There are also 7,812 lines across 27 standalone production `.py`
files. At least 24,985 production lines are already Python; the decision is about module boundaries,
not introducing a new language.

Largest embedded programs:

| Shell owner | Embedded Python | Evidence |
|---|---:|---|
| `leadv2-status-surface.sh` | 2,338 lines / 5 blocks | openers at `:276,340,1757,2458,3189`; duplicate YAML reader admitted at `:397-400` |
| `leadv2-lanes-snapshot.sh` | 1,125 / 2 | snapshot program `:316-1389` |
| `leadv2-lane-liveness.sh` | 661 / 1 | `:62-724`; process-group probe `:290-374` |
| `leadv2-broad-status.sh` | 607 / 1 | `:174-782` |
| `leadv2-router.sh` | 581 / 1 | `:97-679` |
| `codex-task.sh` reaper | 449 / 1 | `:574-1024` |
| `leadv2-tasks-lib.sh` | 411 / 1 | `:39-451` |

Python JSON load/dump operations occur on 358 lines in 88 shell files, versus `jq` on 48 lines in
15. Structured-data behavior is scattered across interpreter launches. The useful existing model
is `leadv2-router-v2.sh:57-75,202`: Bash owns CLI validation, then calls an independently importable
Python implementation.

### Specific allocation

Keep in Bash:

- stable executable names and CLI argument/environment normalization;
- tiny shell pipelines and platform discovery;
- signal handoff and final `exec` into provider CLIs;
- compatibility adapters while extractions remain shadow/rollbackable.

Move to importable Python:

- JSON/YAML/state parsing, validation, atomic mutations, and receipts;
- status/lane snapshot/liveness/rendering programs already hundreds of Python lines;
- Codex reaper policy and process-group/watchdog classification;
- testable decision logic whose current “unit test” extracts heredoc text with regex.

Keep in Bash for the first refactor, but deduplicate:

- the shared GLM/Kimi provider lifecycle. Removing the synchronized-copy hazard is lower risk than
  changing its language and structure simultaneously.

This is a hybrid verdict, not “Python is faster.” Extraction improves ownership, import-level tests,
and review scope. Performance should be accepted only if p95 wall and subprocess counts improve or
stay within an explicit budget.

## Q4. Smallest reversible refactors, ranked by payoff per risk

Costs are **estimates**. Each seam retains the existing shell executable and CLI, making rollback a
path change/revert rather than a fleet-wide migration.

Before changing code, freeze a 30-day baseline query and event definition for each operational
metric below. Use per-100-launch denominators for worker/reaper/liveness outcomes and per-100
substantive edits for defect/fix outcomes; record both numerator and denominator. The acceptance
rule is zero contract/golden regressions, no >10% p95 latency regression, and no statistically
meaningful increase in the normalized failure rate over the following 30 days. Raw fix
commits/month is not an acceptance metric because change volume confounds it.

| Rank | Seam and what moves | Estimated cost | Main risk | One-month success measurement |
|---:|---|---:|---|---|
| 1 | Codex 449-line reaper (`codex-task.sh:574-1024`) -> importable `leadv2-codex-reaper.py`; Bash keeps argv/env/exit translation. | 1-2 days | Argument order, companion paths, exception-to-exit behavior. | Regex-extracting helpers 2 -> 0; direct branch tests; normalized false-reap rate/100 jobs does not rise; dead-job age p95 stays within 10%. |
| 2 | One sourceable GLM/Kimi provider runtime for 41 shared function names; provider parsing remains adapters. | 3-5 days | Hidden globals under `set -u`, provider defaults, trap/signal order. | Shared lifecycle implementations 2 -> 1; zero parity golden drift; stranded workers/100 launches is below or statistically unchanged from baseline. |
| 3 | Extract the 661-line liveness program and 1,072-line snapshot core; retain both shell CLIs. | 3-5 days | Fail-open/closed distinctions, timestamps, macOS/Linux `ps`. | Import-level terminal/dead/waiting branch coverage; snapshot JSON golden diff 0; false-wait/liveness incidents per 100 launches do not rise. |
| 4 | Move five status-surface blocks totaling 2,338 lines into renderer/parser modules; unify the duplicate mini-YAML reader. | 4-7 days | SwiftBar minimal `PATH`, PyYAML absence, whitespace/output contract. | YAML readers 2 -> 1; direct parser tests; golden render diff 0; p95 latency no worse than +10%; fix touches/100 substantive edits does not rise. |
| 5 | Structured-state CLI one domain at a time (active registry, task store, then receipts), built on existing Python modules. | 2-4 days/domain | Lock ownership, atomicity, missing/null/default semantics. | Shell files with Python JSON operations fall from 88; interpreter launches/traced lane fall; round-trip tests cover each mutation; corrupt writes/100 mutations remain zero. |

Do not combine these into a rewrite. Rank 1 proves packaging/import behavior; rank 2 removes a live
duplication hazard without a language change; ranks 3-5 can migrate independently behind stable
executable names.

Separately, the performance-first experiment is smaller still: add a unified trace ID and monotonic
start/end/child-exec counters around dispatch, plan/build/review, deploy, verify, and close. After a
week, use p50/p95 lane shares to decide whether status/router/backlog subprocess consolidation is
worth a code change. Today that exact attribution does not exist.

## Q5. Versioned removal candidates, not proven external unreachability

### Candidate after compatibility notice/telemetry: deprecated API cache warmer (193 lines)

`plugins/leadv2/scripts/leadv2-cache-warm.sh:3-11` calls itself a deprecated compatibility shim and
explains that it spends tokens but cannot warm Claude Code's different prefix. It is disabled unless
`LEADV2_LEGACY_API_CACHE_WARM=1` (`:46-50`). A production-only callsite census found zero callers
and zero tracked enablements; the only external reference is a test of the disabled no-op at
`plugins/leadv2/scripts/tests/test-hook-token-mode-isolation.sh:175-182`.

Commit `0e02a4f` removed the actual `warm_chain()` launcher from `claude-subsession.sh`, replaced it
with a no-op, and deprecated this script. However, the current regression test says the zero-network
default “must remain,” and static in-repo search cannot rule out direct users or installed-plugin
configuration. Remove it only in a versioned deprecation after checking installed manifests/docs or
collecting usage telemetry; update the compatibility test and notice together.

### High-confidence candidates after manual-use check: wiki index/query pair (345 lines)

There are zero current references to `leadv2-wiki-index.sh` or `leadv2-wiki-query.sh` outside their
own files, including `plugins/leadv2/hooks/hooks.json`. The scripts claim PostToolUse and
UserPromptSubmit wiring (`leadv2-wiki-index.sh:6-10`, `leadv2-wiki-query.sh:2-6`), but the actual
UserPromptSubmit manifest is `plugins/leadv2/hooks/hooks.json:86-133` and contains neither.

The query is default-off at `leadv2-wiki-query.sh:21-25`; there are zero tracked non-test
`LEADV2_WIKI_INJECT=1` settings. Both arrived in `d709d65` on 2026-06-16, whose hook manifest also
did not wire them. All-history search found only a generated inventory mention, not an invocation.
Their documented manual entry points still prevent proof of external unreachability. After checking
external docs/installed manifests or telemetry, remove the 173-line indexer and 172-line query as one
mechanism.

### Do not delete merely because a feature is default-off

- Semantic recall has live callers at `leadv2-immune-aggregate.py:169-178`,
  `leadv2-immune-lookup.sh:44-45`, and `leadv2-semantic-backfill.sh:48-71`.
- The eval harness is vendored/invoked at `leadv2-plugin-sync.sh:579-590` and
  `leadv2-shadow-apply.sh:265,678`.
- Memory backup has callers at `leadv2-immune-aggregate.sh:24-26` and
  `leadv2-negative-memory-compile.sh:44-46`.

Default-off is not reachability evidence. Those mechanisms need outcome/usage data before deletion.

## Recommended order

1. Run the external/manual-use check and deprecation notice for the three statically unwired
   candidates (538 lines); remove only when that check is clean.
2. Add unified lane/process timing; collect at least one week of p50/p95 and child-exec data.
3. Extract the Codex reaper behind the existing CLI as the packaging/testability proof.
4. Deduplicate GLM/Kimi lifecycle code without changing language.
5. Extract liveness/snapshot Python, then status rendering; compare golden output and p95 latency.
6. Decide any further state-domain migration from measured defect/latency deltas after one month.

The founder's original instinct is half right: the files contain review-hostile spans, duplicated
policy, and Python programs without module boundaries. But rewriting them to make lanes faster would
target an unproven mechanism. Full-file parse cost is small; process/filesystem churn is a profiling
hypothesis for the slow safe probes, while external provider work dominates the measured subsets.
Refactor the structural seams incrementally and measure the outcome.

## Reproduction notes

The repository knowledge-graph MCP was attempted first as required by `AGENTS.md`, but the call was
rejected, so discovery fell back to `rg`, `git`, ShellCheck, and focused lexical analysis. Aggregate
inventory can be reproduced with:

```bash
{ find plugins/leadv2/scripts -maxdepth 1 -type f -name '*.sh'; \
  find plugins/leadv2/scripts/lib -maxdepth 1 -type f -name '*.sh'; } \
  | sort | tr '\n' '\0' | xargs -0 wc -l | sort -nr
```

For Q1, set `R=$(git rev-parse --show-toplevel)` and create an equivalent fixture (the original
random temp pathname was not retained, but no argv was lost):

```bash
T=$(mktemp -d /tmp/leadv2-perf-audit.XXXXXX)
mkdir -p "$T/state" "$T/ledger" "$T/runs" "$T/glm" "$T/kimi"
printf '{}\n' > "$T/settings.json"
printf 'meta:\n  hard_limit: 3\nsessions: []\n' > "$T/state/active.yaml"
```

Every parse number used one warm-up plus 15 timed executions of
`env TMPDIR="$T" LC_ALL=C bash -n "$R/plugins/leadv2/scripts/<script>"`; the baseline used one
warm-up plus 21 `bash -c ':'` executions. Timing wrapped Python `subprocess.run` with
`time.perf_counter_ns()`, `cwd=R`, output discarded, 15 s timeout, and reported
`statistics.median`.

| Script | Exact safe-probe argv | Relevant overrides/state | Timed repetitions |
|---|---|---|---:|
| `leadv2-dispatch-code.sh` | `bash "$R/plugins/leadv2/scripts/leadv2-dispatch-code.sh" --help` | `TMPDIR=$T LC_ALL=C LEADV2_DISPATCH_CACHE_DIR=$T/dispatch-cache` | warm-up + 11 |
| `leadv2-status-surface.sh` | `bash "$R/plugins/leadv2/scripts/leadv2-status-surface.sh" --oneline` | inherited live control-plane state; data-dependent | 5, no discarded warm-up |
| `leadv2-dispatch-product-close.sh` | no probe; `bash -n` only | `TMPDIR=$T LC_ALL=C` | parse only |
| `leadv2-helpers.sh` | `bash -c 'source "$1"' audit "$R/plugins/leadv2/scripts/leadv2-helpers.sh"` | `TMPDIR=$T LC_ALL=C` | warm-up + 11 |
| `leadv2-fanout.sh` | `bash "$R/plugins/leadv2/scripts/leadv2-fanout.sh" --help` | `TMPDIR=$T LC_ALL=C LEADV2_SKIP_DRIFT_GUARD=1 LEADV2_PROJECT_ROOT=$R` | warm-up + 11 |
| `codex-task.sh` | `bash "$R/plugins/leadv2/scripts/codex-task.sh" status __audit_missing_job__` | `CODEX_AUTOREAP=0`; state/repair/cooldown dirs under `$T`; normal `HOME` for installed companion | warm-up + 11 |
| `kimi-coder.sh` | `bash "$R/plugins/leadv2/scripts/kimi-coder.sh" status __audit_missing_run__` | `TMPDIR=$T LC_ALL=C KIMI_RUNS_DIR=$T/kimi` | warm-up + 11 |
| `glm-coder.sh` | `bash "$R/plugins/leadv2/scripts/glm-coder.sh" status __audit_missing_run__` | `TMPDIR=$T LC_ALL=C GLM_RUNS_DIR=$T/glm` | warm-up + 11 |
| `leadv2-lanes-snapshot.sh` | `bash "$R/plugins/leadv2/scripts/leadv2-lanes-snapshot.sh" --help` | `TMPDIR=$T LC_ALL=C LEADV2_PROJECT_ROOT=$R` | warm-up + 11 |
| `leadv2-review-run.sh` | `bash "$R/plugins/leadv2/scripts/leadv2-review-run.sh" --audit-invalid` | `TMPDIR=$T LC_ALL=C` | warm-up + 11 |
| `claude-subsession.sh` | `bash "$R/plugins/leadv2/scripts/claude-subsession.sh" --audit-invalid` | `TMPDIR=$T LC_ALL=C` | warm-up + 11 |
| `leadv2-router.sh` | `bash "$R/plugins/leadv2/scripts/leadv2-router.sh" --phase review --step standard --signals '{}'` | `PROJECT_ROOT=$R`; no task id; live routing YAML | warm-up + 11 |
| `leadv2-lane-status-line-tail.sh` | `bash "$R/plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh" '<status-json>' "$T/settings.json" "$R/plugins/leadv2/scripts" 3 "$T/statusline.out"` | `TMPDIR=$T LC_ALL=C LEADV2_STATUSLINE_TRACE=0`; normal `HOME`; temp output/cache | warm-up + 11 |
| `leadv2-daemon.sh` | `bash "$R/plugins/leadv2/scripts/leadv2-daemon.sh" --help` | `TMPDIR=$T LC_ALL=C` | warm-up + 11 |
| `leadv2-backlog-pump.sh` | `bash "$R/plugins/leadv2/scripts/leadv2-backlog-pump.sh" dry-run 1` | fresh temp `TMPDIR`/`LEADV2_BACKLOG_PUMP_CACHE_DIR`; `LEADV2_PROJECT_ROOT=$R`; live reads | 5, no discarded warm-up |

For lower-bound command counts, rerun each argv with `bash -x` and
`PS4='@TRACE|${BASH_SOURCE[0]}|${LINENO}|${BASHPID}| '`. Retain matching trace records, parse the
command with Python `shlex.split`, strip leading assignments, and exclude Bash builtins/keywords
(`compgen -b`, `compgen -k`) plus functions lexically defined in top-level `scripts/*.sh` and
`scripts/lib/*.sh`. Count the remaining first command token. This conservative classifier excludes
untraced grandchildren and work performed inside Python/Node; the table therefore calls the result
a shell-visible lower bound, not a descendant-process total.

All 214 scoped files passed GNU Bash 5.3.9 `bash -n`. No source file was changed during this audit.
