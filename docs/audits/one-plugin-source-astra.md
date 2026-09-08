# One plugin source, no project copies — independent design arm B (astra)

Report only, 2026-09-08. No conversion or runtime change is authorized by this report. The only lane deliverable is this file. Inspection used live absolute paths; edits remain in `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea`. The independent design arm was not consulted or read.

## Decision

Choose **a declared, small, machine-checked per-project layer**. Plugin implementation, default policies, shared agent definitions, hooks, schemas, and generic quality rules belong in tracked `leadv2/plugins/leadv2/`. Projects own application code, deployment/verification adapters, application-specific rules, and explicit configuration deltas. A manifest identifies those deltas and their typed extension points. There is no executable search order that allows a project file to replace a plugin function by basename.

This is not principally a project-copy cleanup. The measurement below confirms a large untracked shadow inside leadv2 itself, and a copy-producing writer still exists. Deleting that directory while leaving its producer intact would reproduce the problem. Conversely, deleting every override would remove deliberate deployment, quality, and routing behavior. The hidden override state file and the recognized-null example are concrete counterexamples to treating every file alike.

The final layout is:

```text
~/Projects/leadv2/plugins/leadv2/          # sole editable plugin source
  scripts/, hooks/, agents/, config/, contracts/
  config/exports.json                    # PROPOSED export/ownership registry
  contracts/project.schema.json          # PROPOSED closed extension schema
<repo>/.claude/leadv2.project.yaml        # PROPOSED tracked configuration, no code
<repo>/scripts/leadv2-project/<slug>/     # PROPOSED declared application adapters
<repo>/tests/leadv2-project/              # application adapter tests and fixtures
<repo>/docs/leadv2-project/               # project policy and decision references
~/.claude/leadv2-state/<repo-id>/         # mutable state, never plugin source
```

Plugin runtime selection uses a single checked absolute source root and records its canonical realpath, Git revision, and export-manifest digest in each lane's evidence. A lane must use one root for helpers, hooks, commands, agents, and tests. In development, a pinned lane can explicitly select its tracked plugin tree; no implicit fallback to main or a cache is allowed. In production, the root is the tracked live checkout. Main publication requires the quiet boundary below because a filesystem path into a mutable main checkout is not a revision pin.

UNVERIFIED: the host-specific mechanism for making every command/agent/hook load from that root has not been demonstrated in this audit. Implementation must probe it in an isolated host session. Cache directories may hold derived installation metadata; they must not become an independently editable runtime authority. If a host requires a materialized payload, its supported source-binding mechanism and exact root/digest behavior are a prerequisite decision, not something to infer from marketplace configuration. Failure to prove a single selected runtime source blocks acceptance.

Projects eventually have **no plugin-owned files in `.claude/scripts/`, `.claude/hooks/`, or `.claude/agents/`**, including same-named links. Native hooks/agents may stay at host-required discovery paths, but must be declared project assets with distinct IDs. Host settings reference canonical plugin hooks or declared native hook IDs; shared agents are canonical plus project context, not copied role prompts. During migration only, an explicit compatibility manifest permits old links. `~/.claude/leadv2-shared/scripts` may remain as one checked directory symlink to canonical scripts for legacy global callers, after shared-only assets have been classified and relocated. `~/.claude/agents-shared` gets the same treatment only after its intentional agent deltas are extracted. Neither alias is an editable source or a place to write state.

`leadv2/.claude/scripts` is removed after its consumers and producer are migrated; it does not survive as a second distribution target. Its temporary compatibility links are tracked by the migration inventory even while ignored by Git. The separately filed `GATE-RUNS-AN-UNTRACKED-HALF-SIZED-CORE-RUNNER-01` must agree with this: core tests resolve the tracked runner directly and never require this directory. No P0 fix is made here. Current branch selection falsifies the brief's claim that line 152 is the unconditional runner; see the evidence below.

Why reject the other readings:

| Reading | Consequence |
|---|---|
| Every project file is a symlink into the plugin | Application deploy scripts and policies become plugin code; per-file inventories keep missing additions and retain deleted exports. Links also let edits from a project reach shared live source. Useful transition mechanism, poor final ownership boundary. |
| Projects hold nothing; everything resolves through `~/.claude/plugins/` | Cannot express application deployment, build targets, project policy, and native hooks without hiding them elsewhere. Local installation metadata already names more than one source and a cache. UNVERIFIED: which source an arbitrary current host session actually loaded; settle with a session root/revision emission, not installation metadata alone. |
| Declared project layer, one checked plugin root | Preserves application behavior while forbidding implicit plugin substitution. Requires a resolver contract, schema, and enforced inventory; those are the migration deliverables, not assumptions about existing behavior. |

## Measurement scope and corrections

Counts use the reproducible commands in the evidence appendix. `real` means a regular non-symlink file; recursive traversal does not follow directory symlinks. `shadow` is a same-relative-path file in the live plugin counterpart, not a semantic ownership judgment. A cache collision therefore appears in the all-file census and is excluded from the shell census. `drift` means byte inequality, not evidence that either version is correct. These distinctions matter: matching a basename is insufficient to establish ownership, and having no counterpart does not establish that a script is application-native.

Initial live revisions from E1: leadv2 `70801308b76e445a3ddca4a2c45a5bfb772cb01a`; persona-engine `c3ae97afdc26a0d275e93fe037c5481b23db5b00`; getmany-followup-bot `0c8466dcb7be25db7bb542d48953cf7cae02495f`; respiro-ios `9043ca864002adfbbfded156f923ea3f0d52cfd6`. Lane anchor: `26bf9186edff56b6dcc53c8b77fb4ba3ab6980b3`. Untracked files are not pinned by those revisions; E1 snapshots the filesystem separately.

The brief mixes link counts for all extensions with apparently narrower real-file counts. Recursive shell counting reproduces persona-engine and getmany real-file counts, but does not reproduce respiro or leadv2's reported shell totals. Do not retain the original table as a current census. The all-file and shell-only E1 outputs are the authoritative measurements for this report. In particular, cache bytecode and quarantined backups must not become new application adapters merely because they lack a canonical counterpart.

Condensed E1 result; command is the full recursive Python census under E1, with shell files filtered by `.sh` and `node_modules` excluded:

| Tree `.claude/scripts` | All symlinks | All real files | Real shell files | Shell shadows | Drifted shell shadows |
|---|---:|---:|---:|---:|---:|
| persona-engine | 616 | 82 | 48 | 0 | 0 |
| getmany-followup-bot | 318 | 22 | 13 | 0 | 0 |
| respiro-ios | 403 | 47 | 21 | 1 | 1 |
| leadv2 | 21 | 563 | 477 | 476 | 332 |

E1 also finds shared scripts are a real directory with 149 same-path canonical shell files, of which 111 differ. That is a matched-shell count, not the directory's complete file count. Shared and main both retain `leadv2-wiki-index.sh` with no live canonical counterpart: a retirement/ownership question, not an application-native classification.

`m3-market` is absent locally. The stale active-repo sentence is in **persona-engine's** `.claude/CLAUDE.md:141`, not the currently read leadv2 `.claude/CLAUDE.md`. Replace it with the adopted-repo registry's verified active roots when implementing; do not create or enroll a nonexistent project. Evidence E2 contains the path check and matching sentence.

## Why the existing doctrine fails

These are source observations, not claims about a server or an unobserved host session. Reproduce with E3.

* `leadv2-plugin-sync.sh:1002-1023` explicitly syncs leadv2's own ignored `.claude/scripts` using `_rsync_or_dry ... --recursive --delete`. This is a different path from `_link_project_scripts`, which links project files and refuses divergent content. `.gitignore` explicitly describes `.claude/scripts` as a sync target. The fix must remove copy production, not make its output tracked.
* `plugin-scripts-drift-guard.sh:20-77` checks staged `.sh`/`.py` files, classifies a symlink by type without verifying its target, returns when canonical is missing, and permits the documented commit bypass. It cannot catch ignored on-disk copies, agents, hooks, or all other extensions.
* `plugin-scripts-drift-session-warn.sh` reports filesystem drift but traps errors to an empty successful output. `leadv2-one-copy-drift.sh` intentionally always exits successfully and can be disabled. `leadv2-link-tree-heal.sh` adds missing links and reports occupied real-file positions, preserving them. Warning output is not an execution gate.
* `leadv2-repo-install.sh:45-49,129-229` derives script links from canonical but agents from `~/.claude/agents-shared`. It checks presence before its narrower drift check; an existing bad link is not a verified export. Its install mode also writes project settings, so it must not be run casually as a report probe.
* `leadv2-helpers.sh:116-149` has plugin → override scripts → project scripts lookup. Other direct path call sites exist. A new resolver cannot fix callers that bypass it; the migration's source scan and runtime path trace must cover both.
* `ref/one-copy-exceptions.txt` intentionally preserves shared `architect.md`, `critic.md`, and `security-auditor.md`, citing the founder's 2026-07-30 decision: PE framing versus canonical capabilities are not supersets. Preserve and extract that delta; a raw canonical link would lose policy.

## The machine boundary

The implementation must generate the plugin export registry from **tracked plugin files**, with stable IDs, relative paths, asset kind, supported extension slots, and schema version. It must never derive ownership solely from whichever files happen to exist today. Retired IDs remain tombstones until all references are removed. The registry also records script dependencies and host entry points so a missing helper cannot fall back to a project copy.

Each project manifest declares its immutable repo identity, configuration keys, native adapter IDs/paths, required interfaces, native hook/agent IDs, and policy references. Configuration is merged through one typed API with explicit missing/null/empty semantics. Unknown fields, duplicate IDs, expired compatibility entries, dangling links, path traversal, and assets outside declared roots fail validation. Plugin export IDs and their canonical relative paths are reserved; they cannot be relabeled as a project exception. A new adapter is registered at an existing typed slot (`deploy`, `verify`, `outcome`, `status_facts`, `truth_probe`, `business_signal`) rather than overriding `dispatch`, `review`, or a helper implementation. New generic functionality requires a plugin export or extension-schema change first.

This makes the structural ownership decision mechanical for a new file: tracked plugin export; declared project asset under its project namespace; declared mutable state; or reject. There is no default “no canonical counterpart, therefore native.” Content hashes reject exact plugin copies renamed into a project namespace. Arbitrary semantic equivalence is not decidable by this inventory checker; it must not pretend to detect every handwritten reimplementation. The stronger guarantee is that unregistered implementation cannot participate in plugin resolution and project adapters cannot replace reserved core functions. The initial semantic classification of legacy leftovers remains an evidence-backed migration decision; uncertainties stay quarantined and block removal.

“Small” applies to the integration surface, not to the application's own code. Proposed budgets, **not measured performance or current compliance**: manifest/configuration at most 16 KiB excluding referenced application data; core extension policy at most 200 nonblank lines, with larger application reference documents linked by topic; no executable YAML or arbitrary shell strings for core overrides. Adapter implementations live with application tests and can be substantial. Failure to fit means split out application documentation or propose a typed plugin capability; never truncate policy to pass a size check. Manifest growth and new slots require an explicit reviewed contract change, not an unbounded exception entry.

Before treating a legacy native candidate as safe, inventory its callers, Git ownership, content digest, export collisions, and dependencies. Preserve deploy scripts, App Store pollers, engine probes, and their project tests. PE/getmany scripts named `leadv2-*` but lacking counterparts are **unclassified legacy assets**, not automatic natives. Generic wrappers should move into plugin source after reconciling their deltas; actual application integration moves into declared adapters. Backups and `.pyc` go to excluded archive/cache roots, never the runtime namespace. `codex-guard.sh` in respiro is the shell shadow found by E1: the diff adds canonical fast-fail, grace, identity, and reaper logic. Replacing it changes behavior; first recover why that old copy survives and exercise job-lifecycle tests in a fixture.

Exact relocation convention for implementation planning (each old caller is migrated in the same transaction):

| Legacy asset | Destination / representation |
|---|---|
| Consumed `stack`, limits, routing, toolsets and quality-selection YAML | Typed fields in `.claude/leadv2.project.yaml`; no default restatements. Application-only stability settings go to application configuration referenced by an adapter, not the plugin's core schema. |
| `extensions.md` | `docs/leadv2-project/policy.md` plus topic references, explicitly loaded through the manifest. Generic process rules move into canonical command/policy source after reconciliation. |
| Application `deploy`, `verify`, `deploy-verify`, `outcome-watch`, `gate1`, status-fact and truth-probe scripts | `scripts/leadv2-project/<slug>/<adapter-name>.sh`, registered at typed slots. Source mode, environment and result semantics are preserved before interface modernization. |
| Core review fallback (`omp-task.sh`) and generic shared guards/rules | Canonical plugin implementation; projects retain only supported policy inputs and selected rule IDs. |
| Golden data, self-tests and rule fixtures | `tests/leadv2-project/` with an explicit registered runner and real target/engine. A migration must not label inaccessible fixtures as passing coverage. |
| `.state/trust-alarm.json` and other mutable outputs | Declared state root, with persisted preimage and paired reader/writer path change. Never imported into a tracked source/config manifest. |
| Shared agents with application framing | Canonical role prompt plus `docs/leadv2-project/agent-context/` entries referenced by the manifest. Native specialist agents keep host-required discovery paths with declared noncolliding IDs. |
| Unreferenced archive or obsolete compatibility file | Transaction backup/archive outside runtime discovery; delete only after explicit retirement evidence and restore rehearsal. |

## Override decisions, file by file

Paths below are relative to each project's `.claude/leadv2-overrides/`. E1 includes hidden files and nested archives. E4 gives the content/reader/history commands. **Configured** means a source consumer or model instruction was found; it does not mean a current lane executed it. **UNVERIFIED: actual production reads/execution for these files were not traced in this report.** Before removal, record resolved config and consumer paths in a representative fresh session and a resumed lane; do not invoke deployment, notification, or outcome scripts merely to test reachability. Use recording stubs for their external commands.

“Keep” below means preserve behavior and move into the declared layer; “promote” means generic behavior belongs in plugin source. “Retire candidate” requires the stated proof. No table row authorizes deletion. Defaults are the current consumer's no-file behavior, not example template text. The pure loader comparison in E5 demonstrates why this matters.

### persona-engine

| File | Consumer and default comparison | Disposition and rationale |
|---|---|---|
| `active-limits.yaml` | `leadv2-active-registry.sh:1677,1733`, `fanout.sh:303`; sets hard/heavy/light/standard admission limits rather than inheriting them. | Keep declarative limits until canonical policy decision; comments and `b83afe76f` record founder approval. Do not normalize against only one reader's default. |
| `backlog-pump.yaml` | `leadv2-backlog-pump.sh:194-204`; explicit `enabled: 1`, environment has precedence. | Keep current opt-in; comment and `5165d72da` identify soak purpose. Moving it must preserve environment precedence. |
| `codex-policy.yaml` | Helpers `:243-264`, block/routing hooks; `codex_enabled: true` versus missing-file false. | Keep opt-in and recover consumed timeout/tier fields independently; `9374cb0ae`. Do not replace with a default-off empty manifest. |
| `deploy.sh` | `leadv2-deploy-merge.sh:165-174`, deployment skill and helper executable check; no generic equivalent for application deployment. | Keep application adapter. Its source contains deployment/stage operations; `0d8d49e89` documents its change. Preserve argv, cwd, env, ordering, executable mode, and exit semantics. |
| `deploy-verify.sh` | `leadv2-deploy-merge.sh:180-191`; executable conditional hook, bounded by caller. | Keep separate verification adapter, preserving evidence output and failure visibility; `07c36f2a8`. |
| `extensions.md` | `commands/leadv2.md:46-62` loads project context before Phase 0. No no-file default supplies these project rules. | Split application constraints/references from generic orchestration policy; reconcile contradictions before removing any paragraph. `70fc43efc` is history evidence, not proof every paragraph is current. |
| `gate1.sh` | PE `leadv2-preflight-business-signal/SKILL.md` instructs invocation; extends then delegates to shared gate. | Keep business-signal adapter; promote generic delegation into a typed gate hook. Instruction-mediated invocation needs session evidence. `d73eeb871`. |
| `gemini-policy.yaml` | No current reader found in the bounded code/policy scan; corrected drift checker also flags it. | Retire candidate. Its historical integration assertion (`2381b5385`) is not current wiring. Search dynamic policy loaders and capture session reads before archiving it. |
| `golden/bandit-sample-seeded.json` | `leadv2-eval-harness.sh:49,70-99` discovers JSON but requires missing `golden/eval_engine.py`. | Blocked evaluation artifact, not redundant plugin default. Recover/rehome the engine and fixture together or explicitly retire the evaluation. `33c30b939`. |
| `omp-task.sh` | Review runner `:537-554` and product-close `:3479-3491` use executable fallback after quota return code. | Preserve while extracting generic review/provider fallback into plugin. A repository override for core review is outside the final extension boundary. `74feb00df`; local script's external-provider behavior is UNVERIFIED without a probe. |
| `outcome-watch.sh` | `leadv2-outcome-watch.sh:295-334`; executable hook replaces missing-hook handling, which is inconclusive for Standard/Heavy. | Keep application outcome adapter and its unknown/failure distinction; `c4c4747be`. No live remote metric claims are made here. |
| `quality-engine.yaml` | Helpers quality loader and `leadv2-rules-load.sh`; explicit master/rule-engine enablement, rules directory and severity configuration. Missing/disabled config causes no-op. | Keep typed enablement and project-specific rules; promote generic rule definitions. Current directory paths must be rewritten together with the loader config. |
| `rules/R-001-bash-syntax-check.rule.md` | Loaded through configured `*.rule.md`; no equivalent enabled-by-default rule established. | Generic shell validation: promote rule implementation, preserve enabled ID and severity in project config. |
| `rules/R-002-emit-retry-zero.rule.md` | Same configured rule loader; checks retry/exit behavior. | Reconcile and promote generic orchestration rule; retain active selection until parity is proven. |
| `rules/R-003-grep-only-schema-verify.rule.md` | Same configured rule loader; schema-verification policy. | Promote general rule if its project assumptions are parameterized; preserve present behavior meanwhile. |
| `rules/R-004-silent-source-fail.rule.md` | Same configured rule loader; silent source failure policy. | Promote generic rule; no deletion on the theory that plugin code already intends the same behavior. |
| `rules/R-005-live-state-in-repo.rule.md` | Same configured rule loader; runtime-state placement policy. | Promote generic invariant after aligning with control-plane path resolver; keep enabled project selection. |
| `rules/R-006-silent-feature-gate.rule.md` | Same configured glob loads this rule despite no matching local fixture pair found. | Promote generic rule and add registered coverage in implementation; `abc7ce066`. |
| `stability-policy.yaml` | PE `platform/cron/autopilot-watcher.sh`, `health-digest.sh`, tests and stability skill; project policy beyond plugin defaults. | Keep in application config; comments say an older trigger retired, so observe current watcher reads before moving. `e16cc9ddd`. |
| `stack.yaml` | Helpers stack readers, deploy/verify and other gates; `deploy-verify.sh` also reads deployment metadata. | Keep consumed application metadata with a schema per consumer; isolate prose-only fields. Comments and `34d49a230` record prior stale-target correction. Values describing remote systems are UNVERIFIED here. |
| `state-paths.yaml` | `_lv2_load_paths`, `_lv2_statepath`, hooks and project readers. E5 shows explicit old lead-state path and nonempty task-release adapter differ from defaults. | Keep task-release capability. Reconcile old state-path override with control-plane intent rather than blindly porting it. `persona_id: respiro-brand` and host metadata require project-reader/rationale verification. `3f9acf8ac`. |
| `status-collector-facts.sh` | `leadv2-status-collector.sh:373-386` sources it when present; generic collector otherwise lacks these facts. | Keep typed status adapter; preserve sourced-variable contract until changed to explicit structured output. Header and `30b2e3aa7` explain prior fallback defect. |
| `supervise-truth-probe.sh` | `leadv2-lanes-snapshot.sh:232-246` executable probe plus PE supervisor/tests. | Keep application truth adapter, preserve unknown results and relocate its state separately. `f49f0758a`. |
| `.state/trust-alarm.json` | `supervise-truth-probe.sh:29` selects this mutable alarm-state path. Git ignores it. Not configuration or a plugin default. | Preserve runtime state; move via state migration after writer/reader drain. Exclude from source manifest but account for it in the full file census. Never commit its contents as an override. |
| `tests/gate1-businesssignal-selftest.sh` | Manually addressable test of `gate1.sh`; no standard runner registration found. | Keep/rehome and register before counting it as gate coverage. `b2e4caf26`; registration status remains an implementation proof obligation. |
| `tests/test-canary-soak-probe.sh` | Relative target `../canary-soak-probe.sh` is absent; project `.claude/scripts/canary-soak-probe.sh` exists. | Broken-path test artifact; fix target and register in the application test runner before migration. `495ca2d9f`. |
| `tests/rule-fixtures/R-001-bash-syntax-check.negative.txt` | Neither exact nor generic fixture-directory scan found a current harness reader; rule loader does not load `.txt`. | Preserve/rehome with rule coverage; retire only if evaluation ownership is deliberately ended. |
| `tests/rule-fixtures/R-001-bash-syntax-check.positive.txt` | Same fixture scan; not a runtime override/default. | Preserve/rehome with its rule test. |
| `tests/rule-fixtures/R-002-emit-retry-zero.negative.txt` | Same fixture scan; no standard harness reader established. | Preserve/rehome with its rule test. |
| `tests/rule-fixtures/R-002-emit-retry-zero.positive.txt` | Same fixture scan; no standard harness reader established. | Preserve/rehome with its rule test. |
| `tests/rule-fixtures/R-003-grep-only-schema-verify.negative.txt` | Same fixture scan; no standard harness reader established. | Preserve/rehome with its rule test. |
| `tests/rule-fixtures/R-003-grep-only-schema-verify.positive.txt` | Same fixture scan; no standard harness reader established. | Preserve/rehome with its rule test. |
| `tests/rule-fixtures/R-004-silent-source-fail.negative.txt` | Same fixture scan; no standard harness reader established. | Preserve/rehome with its rule test. |
| `tests/rule-fixtures/R-004-silent-source-fail.positive.txt` | Same fixture scan; no standard harness reader established. | Preserve/rehome with its rule test. |
| `tests/rule-fixtures/R-005-live-state-in-repo.negative.txt` | Same fixture scan; no standard harness reader established. | Preserve/rehome with its rule test. |
| `tests/rule-fixtures/R-005-live-state-in-repo.positive.txt` | Same fixture scan; no standard harness reader established. | Preserve/rehome with its rule test. |
| `toolsets.yaml` | Plan skill `SKILL.md:388`, schema/reference docs; advisory `allowed_tools` context, not hook-enforced policy. | Keep only consumed project tool selection; stale m3 comment is documentation to retire. Do not mistake advisory config for a permission boundary. `eaae80498`. |
| `verify.sh` | Verification skill and deploy workflow; project health/cycle checks with no generic equivalent. | Keep project verification adapter, preserve evidence/exit contract. `9ff2853b0`. |

### getmany-followup-bot

| File | Consumer and default comparison | Disposition and rationale |
|---|---|---|
| `archive/leadv2.md.fork-2026-08-12` | No current reader found; archive rather than recognized override entry point. | Archive candidate outside runtime roots; deletion status UNVERIFIED until dynamic/model glob reads are excluded. Preserve historical policy recovery evidence. |
| `codex-policy.yaml` | Helpers and routing hooks; current `true` versus generic missing-file false. Git diff shows an uncommitted false → true change. | Preserve dirty decision. Tracked `123c927` and `extensions.md:52-55` say disabled by default; recover enabling rationale before choosing policy. A migration must not commit or erase this unrelated dirty state. |
| `deploy.sh` | Deployment merge helper and deploy skill; executable application hook. | Keep bundle/upload/migration/deploy-state logic as application adapter. History `9ed3643`, `a630c61`, `d26feb7`, `bdd57de` and handover document the intended sequence; this report does not verify remote behavior. |
| `extensions.md` | Canonical command reads it before Phase 0. Contains application constraints beyond generic defaults. | Keep verified application policy; separate TODOs and reconcile Codex contradiction. No wholesale deletion. |
| `outcome-watch.sh` | Executable outcome hook; different from generic missing-hook inconclusive behavior. | Keep adapter; audit-log TODO is incomplete intended coverage, not evidence of redundancy. |
| `stack.yaml` | Helpers' top-level scalar/list consumers; contains application deployment metadata. | Keep consumed keys; its git-pull deploy description conflicts with bundle-based deploy source. Recover intent and revise documentation as a separate behavior-preserving cleanup. External target facts UNVERIFIED here. |
| `state-paths.yaml` | All keys are comments; E5 parses it equivalently to absent config. | Strong redundant-config retirement candidate. Preserve comments in history; run every path-reader parity test and environment-precedence case before deleting. |
| `verify.sh` | Verification skill and phase flow; application container/HTTP/log checks. | Keep adapter. Its default health path is a source literal, not proof the endpoint works; UNVERIFIED: settle the health-path TODO with an authorized probe before changing it. |

### respiro-ios

| File | Consumer and default comparison | Disposition and rationale |
|---|---|---|
| `codex-policy.yaml` | Helpers/routing hooks read `codex_enabled: true`; missing-file policy is false. | Keep explicit opt-in until a central policy decision deliberately supersedes it. |
| `deploy.sh` | Deploy merge helper executes this project router; routes application surfaces. | Keep application adapter. Source includes broad staging/build-bump publication (`:61-63`), so tests must stub those commands. Do not run it in this audit or combine a deployment redesign with file relocation. |
| `extensions.md` | Canonical command consumes it. `d6cbf0a` deliberately replaced a command fork and moved iOS policy here. | Keep Swift-write, security, release-approval, and project-context rules; split marked-stale model rows from application invariants. A canonical command alone does not replace the extracted constraints. |
| `outcome-watch.sh` | Executable outcome hook; missing hook changes Standard/Heavy result to inconclusive. | Keep application adapter; source contains TODO crash checks and optional probes/notifications. Those services were not contacted, so actual behavior is UNVERIFIED. |
| `stack.yaml` | Top-level language/DB/hosting/CI/deploy fields have helper consumers. Nested detail/pricing/surface blocks are not consumed by those helpers. | Keep typed consumed keys and policy-readable context; scan specific nested-key readers before classifying the rest as dead. External metadata is UNVERIFIED here. |
| `state-paths.yaml` | Recognized `leadv2_tasks_dir: null` exports an empty task path in full loader; another reader and some callers default empty values. E5 proves the export delta. | **Not equivalent to deletion.** Preserve explicit-null semantics until all callers agree and intent is recovered. Old unrecognized keys are schema-migration candidates, not evidence the whole file is inert. |
| `verify.sh` | Verification skill loads the project hook. Source defaults to iOS, prints manual-check TODOs and can return success without an automated build check; backend branch performs an HTTP check. No generic default supplies this application logic. | Keep application adapter; `d8463ea` records its introduction. Its successful exit alone cannot prove the iOS rollout is healthy. Preserve source behavior during relocation but require separate verification evidence before trusting rollout acceptance. Remote endpoint/build behavior is UNVERIFIED; this script was read, not executed. |

### Leadv2's own overrides — additional self-consumer surface

The application table above covers the requested set. E1 separately finds leadv2's own overrides, so the self-consumer migration must preserve them too. Read-only command: `for f in /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/leadv2-overrides/*; do printf '%s\n' "$f"; nl -ba "$f"; done`.

| File | Current source behavior | Migration disposition |
|---|---|---|
| `deploy.sh` | Checks for `plugins/leadv2/scripts/leadv2-plugin-cache-sync.sh`, sets `LEADV2_PLUGIN_SRC`, then executes it. Same project deploy extension consumer as the application hooks. | Substantive installation/deployment behavior, not a stale default. Replace only when the host root-selection and metadata/payload contract is proven. Its historical comments about host cache behavior are UNVERIFIED in this audit; E2 only proves current filesystem links and byte differences. |
| `stack.yaml` | Declares this repository's local Bash/plugin deployment identity to the stack readers. | Keep typed self-project identity. Reconcile its cache-refresh description with the chosen installation contract. |
| `status-collector-facts.sh` | Defines `collect_repo_facts()`, calls plugin code-intel-rate script and emits structured status fields. `leadv2-status-collector.sh` sources the project fact hook. | Preserve this self-project status adapter and its degradation behavior; do not discard with the shadow scripts directory. |

## Durable enforcement and cost

Agents and hooks need the same treatment as scripts. E6 inventories every local entry and records shared-agent hash differences and project hook registration paths. PE and respiro's shared role links point into `~/.claude/agents-shared`, while getmany has differing regular files at canonical role basenames. Preserve role deltas through project context parameters. PE's `leadv2-supervisor-mode-reinject.sh` is a broken hook link still named by project settings; resolve that retired-hook reference explicitly. Local hook filenames absent from the plugin include generic workflow guards as well as native checks, so they remain candidates until their consumers and rationale are classified. A log file in a hooks directory is runtime output, not a hook to migrate. Compare project and plugin registrations by event, matcher and resolved target to prevent duplicate execution; do not remove local hooks just because a similarly named plugin hook exists. Settings changes, if needed later, must be narrowly scoped to verified registration entries and separately authorized; this lane does not touch them or permission data.

Implement a single read-only ownership checker in tracked plugin source, consumed by installation, CI, the local commit path, and runtime launch. It checks index modes **and** filesystem types/realpaths, including ignored plugin-owned namespaces. It must reject a correct-content real copy, a symlink to the wrong tree, a broken link, a retired export, and an unexpected fallback. A missing registry/canonical root or parse error fails closed for new launches and publication. It must not scan `.claude/worktrees/` recursively as an arbitrary directory: enumerate Git worktrees and check each as its own root, with its own declared revision. Exclude only declared caches, dependencies, and runtime state, never the entire `.claude/` tree.

Run boundaries:

* At install/upgrade and adoption: full root/manifest audit before writing, postcondition audit after writing; refuse unclassified or dirty destinations. The installer must not copy plugin exports.
* At every dispatch, review, resume, and test entry point: verify root/revision/schema identity and the relevant export closure, then emit source evidence. A stale session can finish under its old recorded root; it cannot silently switch helper trees mid-lane.
* At commits and CI: incremental staged check plus filesystem scan of plugin-owned runtime namespaces; CI also materializes a fresh project and worktree fixture so ignored-directory problems are represented. Direct terminal edits must still be caught at the next launch. SessionStart warning is supplemental and cannot be the only enforcement.
* At plugin publication: full fleet dry run, export removal/addition impact check, source-root trace, and quiescence proof. Reconcile every compatibility exception with an owner, rationale, expiry milestone, and executable check. An exception cannot authorize a second core implementation indefinitely.

Proposed normal-edit budget: one process, no network/model calls, no recursive content hashing of application trees; O(changed paths + declared compatibility entries) metadata checks. Cache verified registry digest by source revision; invalidate on index/worktree change or realpath change. Hash content only when it is a real candidate copy or changed export. Target p95 under 250 ms for incremental checks and under 2 s for full local metadata checks; these are **unmeasured acceptance targets**, not claims about current speed. Measure cold/warm runs on each active repo and a large worktree fleet before enabling fail-closed launch gates. Never trade a parse failure for a successful empty inventory to meet a budget.

Required implementation falsification cases: ignored main shadow; byte-identical copy; wrong-target and broken symlink; renamed exact copy; deleted export with lingering caller; added export absent in a consumer; native adapter sharing a basename but not an export ID; unknown YAML key; missing versus null versus empty; inherited environment; dirty local policy; shared agent delta; source-writing script through a symlink; a fresh worktree; a resumed lane pinned to old revision; concurrent conversion; rollback after partial application; permission/backup failure; nonzero or empty checker output. Register any added suites using the repo's trigger convention. A red fixture and a post-fix green transcript are required for each invariant; no such future test coverage is claimed by this design.

## Migration order, quiet boundaries, proof, and rollback

Every step below is future implementation work. No step, rollback, or deployment was executed by this report. The sequence is a dependency chain; applications can be canaried independently only after the common resolver and writer changes are proven. Start with leadv2's own shadow risk and shared-root safety, not a mass deletion across the applications.

Before any filesystem mutation, build a transactional migration tool in the plugin, **proposed interface** `leadv2-source-migrate.sh`. Its `plan` produces an immutable manifest containing absolute roots, before/after file type, mode, symlink target, digest, tracked state, source revision, consumers, and operation order. `apply --plan` refuses any changed preimage, copies preserved bytes/modes/targets into a checksummed backup outside runtime roots, journals each rename, and never follows a destination symlink while writing. `rollback --transaction` verifies postimages, restores preimages in reverse order with the same quiet check, and leaves concurrent edits untouched on conflict. Do not use the existing broad `--revert` “newest backup” interface as a fleet transaction identifier.

The one-command rollbacks below are **interface requirements to implement and test**, not currently available commands. Let `MIGRATE` be the absolute path to the new script in the verified tracked plugin root, and each `Tn` the immutable transaction ID emitted for that step. Each transaction bundles path changes and the paired configuration/code reversal plan. For plugin code, apply records the enabling commit and rollback makes a new targeted revert commit only after checking ancestry and an unchanged affected write set; it must not reset main or restore an entire repository. A rollback conflict stops with preserved backup and an exact path list; it must not overwrite newer work. Implement and successfully rehearse rollback before applying the corresponding live step.

| Step | What must be quiet | Change and proof before progressing | One-command rollback contract |
|---|---|---|---|
| 0. Inventory and preservation | Nothing for read-only inventory. No claims of quiet from registry rows alone. | Enumerate active roots, Git worktrees, process PID/birth/cwd and runtime locks; record source roots and dirty baselines. Snapshot ignored shadows, shared files, override/state paths, agent deltas and settings references without changing permissions. Hash/copy restore rehearsal into a disposable fixture. | `bash "$MIGRATE" rollback --transaction "$T0"` removes only transaction-owned inventory artifacts; preserved originals untouched. |
| 1. Pure registry/checker and resolver contract | No live quiet needed while code remains isolated. Publication to locally live main requires pause/drain of all plugin users, including leads, workers, review/fix loops, hooks, scheduled sync/heal, monitors and auto-resume. | Add registry/schema/checker, root identity emission and compatibility mode. Test direct callers and worktree roots. Keep old resolution behavior explicit during transition; do not silently route old lanes through a new root. Establish P0 tracked-runner provenance independently. | `bash "$MIGRATE" rollback --transaction "$T1"` reverts only contract publication and reinstates prior launch configuration under the same drain. |
| 2. Stop copy producers | All sync/install/heal writers across shared and leadv2 roots; also drain users before publishing their code change. | Replace main self-rsync and other executable-copy outputs with resolver/manifest-aware installation. Refuse writes through source aliases and prevent source-self-overwrite. Dry-run all targets, then fixture install/update twice and prove idempotence with no real export copies. Main shadow remains preserved until callers are migrated. | `bash "$MIGRATE" rollback --transaction "$T2"` restores prior writer version/configuration only with writers held paused; resume them only if old target layout is restored. |
| 3. Preserve policy and classify deltas | None for read-only classification; relevant project sessions and policy readers quiet before moving live policy. | Recover the dirty getmany opt-in, shared agent founder decision, respiro null, PE old lead-state path, and core fallback/rule deltas. Extract generic code into plugin, project specifics into manifest/adapters. Compare effective config and recorded command traces before/after; retain unresolved files unchanged. | `bash "$MIGRATE" rollback --transaction "$T3"` restores each project's paired policy/layout preimages; no unrelated dirty paths are staged. |
| 4. Leadv2 self-consumer canary | All leadv2 test/review/dispatch/close processes and source writers using the old directory; publication users also quiet. | Route gate, shell helpers and host entry points to tracked source. Quarantine untracked shadow with byte-preserving manifest, then remove runtime path only when references and runtime traces are clear. Run changed-scope, explicit all-scope runner selection tests, install/sync repeat, and start/finish a fixture lane. P0 owner signs off on tracked runner identity. | `bash "$MIGRATE" rollback --transaction "$T4"` restores the shadow **and** old caller mapping in one transaction while publication is held. Never restore just a stale runner beneath new callers. |
| 5. Shared tree conversion | Fleet-wide quiet: every project/worktree/global caller, SessionStart healer, scheduled sync, shared agent reader and monitor. This is a global dependency even if one app is the canary. | Move shared-only assets to declared ownership roots, preserve intentional agent deltas, then replace shared directories with checked canonical aliases if legacy callers remain. Test no script writes adjacent mutable files into canonical via the alias; prove full export closure. | `bash "$MIGRATE" rollback --transaction "$T5"` restores original shared directories, link targets, and paired references from the exact transaction, with all users still drained. |
| 6. Application rollout | Drain one application's leads, workers/reviews, scheduled adapters and relevant worktree consumers. Shared source publication still needs fleet drain. Never alter running worktree paths. | Canary getmany after its dirty policy is resolved, then respiro, then PE's broader integration surface. Preserve native adapters; replace command/policy references atomically; test fresh/resumed fixture lanes, project gate, safe deployment argv traces and native hooks. Observe representative normal and recovery paths before retiring compatibility entries. Do not use a real deploy as a reachability test. | `bash "$MIGRATE" rollback --transaction "$T6_REPO"` restores that repo's adapter/config/link preimages and source selection, including its declared worktree compatibility mappings. |
| 7. Remove compatibility, enforce | All remaining users of aliases being removed and writers; global quiet for root publication. | Require every adopted root/worktree declaration to pass, no unresolved caller references, and observed representative reads. Remove fallback branches, obsolete exporters, stale m3 text, dead default restatements, expired exceptions and unused archives in separate explicit transactions. Enable fail-closed launch/publication checker. | `bash "$MIGRATE" rollback --transaction "$T7"` restores compatibility mapping and prior enforcement mode without reenabling unsafe writers against the new layout. |

Quiescence is a machine certificate, not “the board looks idle”: dispatch/admission lock acquired; no running or resumable-but-unpinned users of the affected root; PID/birth/cwd checks reconciled with registry and locks; periodic writers paused; a second scan under the lock finds no new entrants. UNVERIFIED: current live process ownership and whether a global maintenance window is available; this report does not claim the fleet is quiet. Git worktree counts in E2 are inventory only. A lane that cannot drain keeps its old root/layout and blocks the global shared conversion. Do not prune, clean, stash, or rewrite worktrees. Long-lived control-plane services must be explicitly included in the drain or restarted under the verified new root before reopening admission.

Rollback for a future main change is also publication. It must satisfy the same drain and provenance gate. No archive is deleted during initial rollout; retain until both restore rehearsal and the chosen observation window complete. An observation window must include fresh launch, resume, review failure/fallback, close, and the project's scheduled adapter cycle; elapsed wall time alone is insufficient.

## Acceptance and remaining decisions

The end state is accepted only when the clean-source invariant is proven for leadv2 itself, every active application, all adopted worktrees, global script/agent aliases, and the runtime root actually selected by each host. All remaining project assets have manifest ownership and callers; all intentionally retained policy deltas have recovered rationale and effective-config parity. New install, upgrade, export addition/removal, direct terminal edits, and interrupted migration must fail or recover predictably. Unknown liveness or reader reachability blocks deletion, not completion of this design.

Decisions intentionally deferred to implementation owners: getmany's uncommitted opt-in; PE shared-agent delta extraction; explicit-null meaning across path APIs; retirement versus repair of orphan/evaluation/test artifacts; consolidation of core policy from extensions and `omp-task.sh`; and the maintenance window. This report recommends preserving current behavior as the reversible default. It does not assert authorization for destructive cleanup or permission-file edits.

## Evidence appendix

The following probes are read-only local evidence except the final report checks and lane commit. Commands specify live roots independently of lane source. Source citations above refer to `~/Projects/leadv2/plugins/leadv2/` unless prefixed with a project. Graph discovery was attempted first and returned `MCP tool call requires approval, but approval policy is never`; shell/config discovery used `rg` thereafter. No other arm's design was read.

### E1 — complete recursive census

Command (inline Python; no reliance on a retained temporary file):

```bash
python3 - <<'PY'
from pathlib import Path
import datetime, subprocess
P = Path.home() / "Projects"
C = P / "leadv2/plugins/leadv2"
print("UTC", datetime.datetime.now(datetime.timezone.utc).isoformat())
for name in ["leadv2", "persona-engine", "getmany-followup-bot", "respiro-ios"]:
    r = P / name
    print("TREE", name, "HEAD", subprocess.check_output(["git", "-C", str(r), "rev-parse", "HEAD"], text=True).strip())
    for kind in ["scripts", "agents", "hooks", "leadv2-overrides"]:
        d = r / ".claude" / kind
        entries = list(d.rglob("*"))
        links = [p for p in entries if p.is_symlink()]
        files = [p for p in entries if p.is_file() and not p.is_symlink()]
        shadows = [p for p in files if (C / kind / p.relative_to(d)).is_file()]
        print(kind, "all: links", len(links), "real", len(files), "shadow", len(shadows), "drift", sum(p.read_bytes() != (C / kind / p.relative_to(d)).read_bytes() for p in shadows), "broken", sum(not p.exists() for p in links))
        if kind == "scripts":
            shell = [p for p in files if p.suffix == ".sh" and "node_modules" not in p.parts]
            owned = [p for p in shell if (C / kind / p.relative_to(d)).is_file()]
            print("scripts recursive .sh excluding node_modules: real", len(shell), "shadow", len(owned), "drift", sum(p.read_bytes() != (C / kind / p.relative_to(d)).read_bytes() for p in owned))
    if name == "leadv2":
        print("tracked .claude/scripts", len(subprocess.check_output(["git", "-C", str(r), "ls-files", ".claude/scripts/"], text=True).splitlines()))
d = Path.home() / ".claude/leadv2-shared/scripts"
files = [p for p in d.rglob("*") if p.is_file() and not p.is_symlink()]
shell = [p for p in files if p.suffix == ".sh" and "node_modules" not in p.parts]
owned = [p for p in shell if (C / "scripts" / p.relative_to(d)).is_file()]
print("shared: directory_is_symlink", d.is_symlink(), "all_real", len(files), "shell_real", len(shell), "shell_owned", len(owned), "shell_drift", sum(p.read_bytes() != (C / "scripts" / p.relative_to(d)).read_bytes() for p in owned))
PY
```

Raw output:

```text
UTC 2026-09-08T12:18:34.790008+00:00
TREE leadv2 HEAD 70801308b76e445a3ddca4a2c45a5bfb772cb01a
scripts all: links 21 real 563 shadow 562 drift 348 broken 0
scripts recursive .sh excluding node_modules: real 477 shadow 476 drift 332
agents all: links 3 real 2 shadow 0 drift 0 broken 0
hooks all: links 0 real 0 shadow 0 drift 0 broken 0
leadv2-overrides all: links 0 real 3 shadow 0 drift 0 broken 0
tracked .claude/scripts 0
TREE persona-engine HEAD c3ae97afdc26a0d275e93fe037c5481b23db5b00
scripts all: links 616 real 82 shadow 9 drift 9 broken 16
scripts recursive .sh excluding node_modules: real 48 shadow 0 drift 0
agents all: links 3 real 10 shadow 0 drift 0 broken 0
hooks all: links 6 real 35 shadow 0 drift 0 broken 1
leadv2-overrides all: links 0 real 38 shadow 0 drift 0 broken 0
TREE getmany-followup-bot HEAD 0c8466dcb7be25db7bb542d48953cf7cae02495f
scripts all: links 318 real 22 shadow 2 drift 2 broken 1
scripts recursive .sh excluding node_modules: real 13 shadow 0 drift 0
agents all: links 0 real 9 shadow 3 drift 3 broken 0
hooks all: links 1 real 4 shadow 0 drift 0 broken 0
leadv2-overrides all: links 0 real 8 shadow 0 drift 0 broken 0
TREE respiro-ios HEAD 9043ca864002adfbbfded156f923ea3f0d52cfd6
scripts all: links 403 real 47 shadow 5 drift 5 broken 12
scripts recursive .sh excluding node_modules: real 21 shadow 1 drift 1
agents all: links 3 real 15 shadow 0 drift 0 broken 0
hooks all: links 1 real 5 shadow 0 drift 0 broken 0
leadv2-overrides all: links 0 real 7 shadow 0 drift 0 broken 0
shared: directory_is_symlink False all_real 358 shell_real 150 shell_owned 149 shell_drift 111
```

### E2 — runner selection, worktrees, stale repo reference and local installation metadata

Command (inline Python; no reliance on a retained temporary file):

```bash
python3 - <<'PY'
from pathlib import Path
import subprocess,json
P=Path.home()/"Projects"
for r in [P/"leadv2",Path.cwd()]:
    print("RUNNER_TREE",r)
    for rel in [".claude/scripts/tests/run-core-offline.sh","plugins/leadv2/scripts/tests/run-core-offline.sh"]:
        p=r/rel
        if p.exists():
            t=p.read_text();print(rel,"lines",len(t.splitlines()),"SCOPE_SELECTION_REASON",t.count("SCOPE_SELECTION_REASON"),"fail-open",t.count("fail-open"))
        else: print(rel,"ABSENT")
    print(subprocess.check_output(["sed","-n","149,153p",str(r/"tests/run-all.sh")],text=True).strip())
for n in ["leadv2","persona-engine","getmany-followup-bot","respiro-ios"]:
    r=P/n
    print("WORKTREE_ENTRIES",n,sum(s.startswith("worktree ") for s in subprocess.check_output(["git","-C",str(r),"worktree","list","--porcelain"],text=True).splitlines()))
    f=r/".claude/CLAUDE.md"
    if f.exists():
        for i,s in enumerate(f.read_text().splitlines(),1):
            if "m3-market" in s: print(str(f)+":"+str(i),s)
print("m3-market exists",(P/"m3-market").exists())
for fn in ["known_marketplaces.json","installed_plugins.json"]:
    f=Path.home()/".claude/plugins"/fn
    print("LOCAL_METADATA",f)
    if not f.exists():print("ABSENT");continue
    d=json.loads(f.read_text())
    if fn=="installed_plugins.json": d=d.get("plugins",{})
    for k,v in d.items():
        if "leadv2" in k:print(k,json.dumps(v,sort_keys=True))
PY
```

Raw output:

```text
RUNNER_TREE /Users/kostiantyn.vlasenko/Projects/leadv2
.claude/scripts/tests/run-core-offline.sh lines 496 SCOPE_SELECTION_REASON 0 fail-open 0
plugins/leadv2/scripts/tests/run-core-offline.sh lines 1114 SCOPE_SELECTION_REASON 3 fail-open 1
if [[ -f "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh" ]]; then
  add_suite "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh"
else
  add_suite "${ROOT}/.claude/scripts/tests/run-core-offline.sh"
fi
RUNNER_TREE /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea
.claude/scripts/tests/run-core-offline.sh ABSENT
plugins/leadv2/scripts/tests/run-core-offline.sh lines 1114 SCOPE_SELECTION_REASON 3 fail-open 1
if [[ -f "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh" ]]; then
  add_suite "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh"
else
  add_suite "${ROOT}/.claude/scripts/tests/run-core-offline.sh"
fi
WORKTREE_ENTRIES leadv2 200
WORKTREE_ENTRIES persona-engine 17
/Users/kostiantyn.vlasenko/Projects/persona-engine/.claude/CLAUDE.md:141 The live repos sharing this tree are `persona-engine`, `m3-market`, and `respiro-ios`.
WORKTREE_ENTRIES getmany-followup-bot 7
WORKTREE_ENTRIES respiro-ios 1
m3-market exists False
LOCAL_METADATA /Users/kostiantyn.vlasenko/.claude/plugins/known_marketplaces.json
leadv2-local {"installLocation": "/Users/kostiantyn.vlasenko/.claude/plugins/local/leadv2", "lastUpdated": "2026-07-09T23:23:50.381Z", "source": {"path": "/Users/kostiantyn.vlasenko/.claude/plugins/local/leadv2", "source": "directory"}}
leadv2 {"installLocation": "/Users/kostiantyn.vlasenko/Projects/leadv2", "lastUpdated": "2026-07-24T08:46:02.289Z", "source": {"path": "/Users/kostiantyn.vlasenko/Projects/leadv2", "source": "directory"}}
LOCAL_METADATA /Users/kostiantyn.vlasenko/.claude/plugins/installed_plugins.json
leadv2@leadv2-local [{"installPath": "/Users/kostiantyn.vlasenko/.claude/plugins/cache/leadv2-local/leadv2/0.5.7", "installedAt": "2026-05-12T10:29:28.990Z", "lastUpdated": "2026-09-01T23:00:10.973Z", "scope": "user", "version": "0.5.7"}]
```

Supplemental direct filesystem probe (does not establish which host code path was executed):

```bash
python3 - <<'PYPROBE'
from pathlib import Path
h=Path.home(); c=h/'Projects/leadv2/plugins/leadv2'
for p in [h/'.claude/plugins/local/leadv2/plugins/leadv2',h/'.claude/plugins/cache/leadv2-local/leadv2/0.5.7']:
    print('LOCAL_ROOT',p,'exists',p.exists(),'symlink',p.is_symlink(),'realpath',p.resolve())
    for rel in ['hooks/hooks.json','.claude-plugin/plugin.json','scripts/leadv2-helpers.sh']:
        q=p/rel; ref=c/rel
        print(rel,'exists',q.exists(),'same_bytes_as_source',q.exists() and ref.exists() and q.read_bytes()==ref.read_bytes())
PYPROBE
```

```text
LOCAL_ROOT /Users/kostiantyn.vlasenko/.claude/plugins/local/leadv2/plugins/leadv2 exists True symlink True realpath /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2
hooks/hooks.json exists True same_bytes_as_source True
.claude-plugin/plugin.json exists True same_bytes_as_source True
scripts/leadv2-helpers.sh exists True same_bytes_as_source True
LOCAL_ROOT /Users/kostiantyn.vlasenko/.claude/plugins/cache/leadv2-local/leadv2/0.5.7 exists True symlink False realpath /Users/kostiantyn.vlasenko/.claude/plugins/cache/leadv2-local/leadv2/0.5.7
hooks/hooks.json exists True same_bytes_as_source False
.claude-plugin/plugin.json exists True same_bytes_as_source True
scripts/leadv2-helpers.sh exists True same_bytes_as_source False
```

A concrete wrong-root/broken compatibility link (the cause of its creation is not established):

```bash
readlink /Users/kostiantyn.vlasenko/Projects/persona-engine/.claude/scripts/dummy.sh
test -e /Users/kostiantyn.vlasenko/Projects/persona-engine/.claude/scripts/dummy.sh
printf 'dummy_target_exists_rc=%s\n' "$?"
```

```text
/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.fa8ggdXi7t/case5/canonical/plugins/leadv2/scripts/dummy.sh
dummy_target_exists_rc=1
```

### E3 — writer and guard source evidence

Commands used to inspect the named decisions (run from the pinned lane; the relevant source agrees with the live tree at the audited revision):

```bash
sed -n '18,105p' plugins/leadv2/hooks/plugin-scripts-drift-guard.sh
sed -n '1,170p' plugins/leadv2/hooks/leadv2-one-copy-drift.sh
sed -n '998,1028p' plugins/leadv2/scripts/leadv2-plugin-sync.sh
sed -n '1,230p' plugins/leadv2/scripts/leadv2-repo-install.sh
cat plugins/leadv2/hooks/leadv2-link-tree-heal.sh
cat plugins/leadv2/ref/one-copy-exceptions.txt
git blame -L 149,153 tests/run-all.sh
```

Key raw excerpts:

```text
.gitignore:9:# Plugin sync writes canonical scripts here — not source, not committed.
.gitignore:10:.claude/scripts/
plugins/leadv2/ref/one-copy-exceptions.txt:5:#   .claude/scripts/) or top-level curated-scripts override (relpath "toplevel/<name>"),
plugins/leadv2/ref/one-copy-exceptions.txt:12:agents/architect.md
plugins/leadv2/ref/one-copy-exceptions.txt:13:agents/critic.md
plugins/leadv2/ref/one-copy-exceptions.txt:14:agents/security-auditor.md
plugins/leadv2/scripts/leadv2-plugin-sync.sh:8:#   (c) <project>/.claude/scripts/                          (per-repo runtimes from cross-repo-paths.yaml)
plugins/leadv2/scripts/leadv2-plugin-sync.sh:10:#   (e) ~/.claude/scripts/                                  (user-global leadv2-* scripts; ADDITIVE, no --delete)
plugins/leadv2/scripts/leadv2-plugin-sync.sh:138:# under .claude/scripts/ for (c) or "toplevel/<name>" for (c2).
plugins/leadv2/scripts/leadv2-plugin-sync.sh:139:ONE_COPY_EXCEPTIONS_FILE="${LEADV2_ONE_COPY_EXCEPTIONS_FILE:-${PLUGIN_ROOT}/ref/one-copy-exceptions.txt}"
plugins/leadv2/scripts/leadv2-plugin-sync.sh:404:# LEADV2_SKIP_DRIFT_GUARD=1. ~/Projects/leadv2/.claude/scripts/ (the vendored
plugins/leadv2/scripts/leadv2-plugin-sync.sh:729:# $2 (vendors_scripts, default "true"): when "false", skip (c) .claude/scripts/
plugins/leadv2/scripts/leadv2-plugin-sync.sh:779:  # <root>/scripts/ (top-level, NOT .claude/scripts/) — e.g. persona-engine's
plugins/leadv2/scripts/leadv2-plugin-sync.sh:900:# ── (e) ~/.claude/scripts/ — user-global leadv2-* scripts ───────────────────
plugins/leadv2/scripts/leadv2-plugin-sync.sh:1004:# ~/Projects/leadv2/.claude/scripts/ is not this repo's own canonical (that's
plugins/leadv2/scripts/leadv2-plugin-sync.sh:1020:  _rsync_or_dry "leadv2-repo-vendored/scripts" "${PLUGIN_ROOT}/scripts/" "${LEADV2_REPO_VENDORED}" --recursive --delete "${SYNC_HYGIENE_FILTERS[@]}" "${_unsafe_excludes[@]}"
813e56479 (Claude Code 2026-08-04 05:03:23 +0300 149) if [[ -f "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh" ]]; then
813e56479 (Claude Code 2026-08-04 05:03:23 +0300 150)   add_suite "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh"
813e56479 (Claude Code 2026-08-04 05:03:23 +0300 151) else
813e56479 (Claude Code 2026-08-04 05:03:23 +0300 152)   add_suite "${ROOT}/.claude/scripts/tests/run-core-offline.sh"
813e56479 (Claude Code 2026-08-04 05:03:23 +0300 153) fi
```

The old fallback is present but conditional; line existence does not prove execution. E2 shows the tracked file exists. The changed-scope output below proves which runner this lane executed. Main was inspected, not tested by running its gate.

### E4 — override reader, content, and history evidence

Reproduction for every table row: use its relative filename for `REL` and its full application root for `REPO`; `PL` is the live plugin directory, not its repository parent. Content reads were static; no deploy, verify, notification, or truth probe was executed.

```bash
PL=/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2
REPO=/Users/kostiantyn.vlasenko/Projects/persona-engine
REL=state-paths.yaml
nl -ba "$REPO/.claude/leadv2-overrides/$REL"
rg -n --hidden --glob '!node_modules/**' --glob '!**/__pycache__/**' \
  --glob '!**/worktrees/**' --glob '!**/docs/handoff/**' \
  "$(basename "$REL")" "$PL/scripts" "$PL/hooks" "$PL/skills" "$PL/commands" \
  "$REPO/.claude/skills" "$REPO/.claude/hooks" "$REPO/.claude/leadv2-overrides/extensions.md"
git -C "$REPO" log -1 --format='%h %s' -- ".claude/leadv2-overrides/$REL"
```

A basename match is only a discovery aid. Consumers were read to distinguish paths, invocation, conditions, defaults, tests and prose. Additional generic-loader search, because fixtures/rules need not have literal filename readers:

```bash
rg -n 'rule-fixtures|\.negative\.txt|\.positive\.txt|R-00[1-5]|rule_glob|rules_dir' \
  "$PL/scripts" "$PL/hooks" "$PL/skills" \
  "$REPO/scripts" "$REPO/tests" "$REPO/.claude/skills" \
  "$REPO/.claude/hooks" "$REPO/.claude/scripts"
sed -n '145,285p' "$PL/scripts/leadv2-helpers.sh"
sed -n '30,110p' "$PL/scripts/leadv2-eval-harness.sh"
sed -n '285,335p' "$PL/scripts/leadv2-outcome-watch.sh"
git -C /Users/kostiantyn.vlasenko/Projects/getmany-followup-bot diff -- .claude/leadv2-overrides/codex-policy.yaml
git -C /Users/kostiantyn.vlasenko/Projects/respiro-ios show d6cbf0a -- .claude/leadv2-overrides/extensions.md
```

Observed getmany policy diff hunk:

```diff
-codex_enabled: false
+codex_enabled: true
```

The hidden PE file was missed by the first `rg --files` inventory. Full pathlib traversal in E1 includes it; the report coverage check below checks hidden files as well. `git ls-files --error-unmatch .claude/leadv2-overrides/.state/trust-alarm.json` in PE returned nonzero; `git check-ignore -v` returned:

```text
.gitignore:501:.claude/leadv2-overrides/.state/ .claude/leadv2-overrides/.state/trust-alarm.json
```

The existing override drift script is a literal-reference/documentation heuristic, not proof of runtime execution, default equivalence, or nested fixture coverage. Its `--plugin-root` argument must be the plugin directory. An initial helper probe passed the repository parent and was discarded; it falsely called wired files orphaned. Correctly rooted probe is recorded below; its orphan/undocumented result is existing audit debt, not a failed test caused by this Markdown change.

```bash
timeout 20 bash /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/leadv2-overrides-drift.sh \
  --repo /Users/kostiantyn.vlasenko/Projects/persona-engine \
  --plugin-root /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2
```

Raw correctly rooted drift-check output:

```text
=== leadv2-overrides-drift: /Users/kostiantyn.vlasenko/Projects/persona-engine ===
-- ORPHAN (file exists, zero readers found) --
  gemini-policy.yaml
-- UNDOCUMENTED (has a real reader, missing from docs/OVERRIDES.md) --
  backlog-pump.yaml
  deploy-verify.sh
  gate1.sh
  omp-task.sh
  outcome-watch.sh
  quality-engine.yaml
  stability-policy.yaml
  status-collector-facts.sh
  supervise-truth-probe.sh
  toolsets.yaml
rc=1
```

Override content identity and executable-mode snapshot (hashes are evidence of inspected bytes, not behavior or correctness):

```bash
python3 - <<'PY'
from pathlib import Path
import hashlib,stat
P=Path.home()/"Projects"
for n in ["persona-engine","getmany-followup-bot","respiro-ios"]:
    root=P/n/".claude/leadv2-overrides"
    for p in sorted(root.rglob("*")):
        if p.is_file() and not p.is_symlink():
            print(n+"/"+str(p.relative_to(root)),"mode="+oct(stat.S_IMODE(p.stat().st_mode)),"sha256="+hashlib.sha256(p.read_bytes()).hexdigest())
PY
```

```text
persona-engine/.state/trust-alarm.json mode=0o644 sha256=bf4bf883fc7dde1a25bc97dfc91d7dcc59e7c453b3dc8ec6f82fe88c3d794dda
persona-engine/active-limits.yaml mode=0o644 sha256=efaedd2865a3fc55a8912c34a6b23cb569d7420fe76d852bcc3b2ad58db6b3a7
persona-engine/backlog-pump.yaml mode=0o644 sha256=2bd5bb37166f2a61c5af0eb84aee2de55499cef403ff72289416451632957175
persona-engine/codex-policy.yaml mode=0o644 sha256=8c4bc465eb9a2968c5611ddb11275d18ab1995901c6d1f213ee934d98257e11f
persona-engine/deploy-verify.sh mode=0o755 sha256=e8dad54b5901e1deeac7d12f98823639dcb056bbd60a13c6c58f47e87e7c1c6f
persona-engine/deploy.sh mode=0o755 sha256=468a7fd9c6c1942b1ed1566b2b0a7efa0e40cc664589e96d1100873322801559
persona-engine/extensions.md mode=0o644 sha256=5cab2649d2b3cf8a8d3fda3f54e934b3ea112a892e15f193a05ec54efe57df15
persona-engine/gate1.sh mode=0o755 sha256=21b95308c38eae22a6ff2403808f0efc7ab28932b7ae8477d903801b86be921a
persona-engine/gemini-policy.yaml mode=0o644 sha256=42df4c3aef2cf1d9165404a8971c1c8cd1a1e5921696ddf6bb8d4a8787cef127
persona-engine/golden/bandit-sample-seeded.json mode=0o644 sha256=5118f5fae3f5bd3d97d82e6fec00bb34627ed77722c22c1a0bf3f85e7dc5ba45
persona-engine/omp-task.sh mode=0o755 sha256=9469888718cea257e9a0cce390ee94d8b654b2ac6ef56d35c3fa012c205878a8
persona-engine/outcome-watch.sh mode=0o755 sha256=9a5956c02266052f25942519618f66265da2d05981d684a438e957737680bed4
persona-engine/quality-engine.yaml mode=0o644 sha256=349e22098e1b2eb2501afb18e260858e4269d0ba9ec27af95564e5da9e5cb384
persona-engine/rules/R-001-bash-syntax-check.rule.md mode=0o644 sha256=4e244e41459870775001d93de6997234fff72d301154fd67c6aa1d8df4e9c289
persona-engine/rules/R-002-emit-retry-zero.rule.md mode=0o644 sha256=6566111952fd9f1bdbba9c2f649ec48af33e4c41a167b17caf1547f32727779f
persona-engine/rules/R-003-grep-only-schema-verify.rule.md mode=0o644 sha256=cdc9c07a7c6bd4e5e05b03b92703fe79f0dd30620a9851e79b789b3915a9ff29
persona-engine/rules/R-004-silent-source-fail.rule.md mode=0o644 sha256=39e13e7472a4114c8bd6ab7bd627b917a97ff7c45742c51c072c1760f5a94bc8
persona-engine/rules/R-005-live-state-in-repo.rule.md mode=0o644 sha256=cac5dd9ab1268ebebd1a47b77c6d27d82f05c4d1be63d121ce5fba6a6c2072ed
persona-engine/rules/R-006-silent-feature-gate.rule.md mode=0o644 sha256=33643bba98511a96e31fb95862f2ec354ee3a5f5d1643bdc026b7f28db395294
persona-engine/stability-policy.yaml mode=0o644 sha256=e5e73c3013aa30aad2d78b2cf5e849b19eccfc9622e227f3f8eae14b889ba62d
persona-engine/stack.yaml mode=0o644 sha256=d68f8066388ffa926c9f2f309dd3480c36ce0f2ef1e4338ff8279467f9f7ff38
persona-engine/state-paths.yaml mode=0o644 sha256=f87c333eaf8cde34d88436c9fab0a99c6adb409630046007223833905e3d387b
persona-engine/status-collector-facts.sh mode=0o755 sha256=fc77ac2cdfcf7c958f44c5478e0408af259d6c4873efb46475b0bee5dcbc3413
persona-engine/supervise-truth-probe.sh mode=0o755 sha256=f51fba67a9836d6071cb505f6b882b97f14d85dd1dc752b45a4a124bc0d18700
persona-engine/tests/gate1-businesssignal-selftest.sh mode=0o644 sha256=c74382f81e358d1e1d6e43f3bf69886b26902166ca052fa9f473b10ba50f716d
persona-engine/tests/rule-fixtures/R-001-bash-syntax-check.negative.txt mode=0o644 sha256=813ad42db3ffdf6dfbd031daf642d58287c528bfbac42bc85c00accdf5d6e23b
persona-engine/tests/rule-fixtures/R-001-bash-syntax-check.positive.txt mode=0o644 sha256=69acce5f231924add6337bb77cdd08d0ece4c2a677526fb7df2edf651871ff93
persona-engine/tests/rule-fixtures/R-002-emit-retry-zero.negative.txt mode=0o644 sha256=cfb7938b8e239200a339faad247de248a4642ddb4a43ec4f53bb77aac1fc8338
persona-engine/tests/rule-fixtures/R-002-emit-retry-zero.positive.txt mode=0o644 sha256=16b0c414cf4ea8d17bd7f1d592b709f95d2e9536a800f5b1700d840b880f706e
persona-engine/tests/rule-fixtures/R-003-grep-only-schema-verify.negative.txt mode=0o644 sha256=2a920656ae82913005c06dd9e3c58f13ea54ab2f742359d88e3a0e451dd3ef8b
persona-engine/tests/rule-fixtures/R-003-grep-only-schema-verify.positive.txt mode=0o644 sha256=022675013090600b4d20d24b27f9690fbd05ab814c2285598f5714eb8a84f10f
persona-engine/tests/rule-fixtures/R-004-silent-source-fail.negative.txt mode=0o644 sha256=7b9d9775bd33d7ca05c3be9b1b1f77072348214537ac82af3aa42bd91d56a3c8
persona-engine/tests/rule-fixtures/R-004-silent-source-fail.positive.txt mode=0o644 sha256=d2434c53ba7ddd6839cdb316d0db912a34b2f9e1365f0eacc7d05276abce8ae0
persona-engine/tests/rule-fixtures/R-005-live-state-in-repo.negative.txt mode=0o644 sha256=936c8b9731696f1d8d889da351212a8080840d691c98b2162694bc7d3395c714
persona-engine/tests/rule-fixtures/R-005-live-state-in-repo.positive.txt mode=0o644 sha256=4dc0fb26d05e5310796cb20eca4a893df0ccdc7fd1994922a374ea1b4ad46c4f
persona-engine/tests/test-canary-soak-probe.sh mode=0o644 sha256=4fa4511b0d883841ddcaf2f381a125cdf1759dd5656f9fcff014315407d73f30
persona-engine/toolsets.yaml mode=0o644 sha256=9f44080bbea1eb7c8ff9ddd08f8616b4c829ce59dde86e5b4d621798310e32c5
persona-engine/verify.sh mode=0o755 sha256=aa949366c8bec8f89be2031b9ecf0283a121436ebfa6194d8156417252ef5706
getmany-followup-bot/archive/leadv2.md.fork-2026-08-12 mode=0o644 sha256=8ac7d3a2538a7970dbb7c20aa765fcce79f4c78c7ac5ebeddb0f3b6a83e7eb22
getmany-followup-bot/codex-policy.yaml mode=0o644 sha256=c62e411330e04ea1e2a9c8a9e4212651ac3026db13408a936e9ce2a1a25dff7a
getmany-followup-bot/deploy.sh mode=0o755 sha256=2c8af5f695063cbcf417be19eaccfc799457dd13a6603f82fb6b84bf137369c9
getmany-followup-bot/extensions.md mode=0o644 sha256=847992fa93289ee304db996b3611fa44803787166a0dff1f2b302b6d13555861
getmany-followup-bot/outcome-watch.sh mode=0o755 sha256=ec58dd1661cdd83aa99a890656cf991f6d2352df0b8bd6d6516f36109708db80
getmany-followup-bot/stack.yaml mode=0o644 sha256=e49263393ba816b90310421af700ff86d93cbf81fded73949778bc78c2cde89f
getmany-followup-bot/state-paths.yaml mode=0o644 sha256=e59f5cf2e49f5cc25d4423b93a7c50ae5bb96d240c83dd0d29f9740efc7324c2
getmany-followup-bot/verify.sh mode=0o755 sha256=bc509438e8f8da0fb5a0705bea9ccc1e0e7ccba1e5a28d28ff067313810e2f91
respiro-ios/codex-policy.yaml mode=0o644 sha256=a0456084b3d14a770b4bc7fecdaa3233782501c6b8fc2e1ed1b0233f9db0274e
respiro-ios/deploy.sh mode=0o755 sha256=91e888336a3f49066face732e5148ce73a1a342c06cc4593026119cd1be5b8ef
respiro-ios/extensions.md mode=0o644 sha256=95ad4b679647aecc92a8212850c90b557c64dbbf651746cbc878c9255d21e96d
respiro-ios/outcome-watch.sh mode=0o755 sha256=f1d2b9cd2713d9490956b87c114b259872cded806b00ac4a2d4e398e5edccf44
respiro-ios/stack.yaml mode=0o644 sha256=2fd7966199fc977cd7ea2d4dc5813144e69a9fa2e99ba4969def29b49ab2a876
respiro-ios/state-paths.yaml mode=0o644 sha256=db9999578d9c0bb5831c458c1f133cc1d4beb666b941b67f38022a009c2dcbe5
respiro-ios/verify.sh mode=0o755 sha256=7a15f582a1aafc2ec6d07d18bf2d7584414073efdbc205040dffd212f5902720
```

### E5 — actual path-loader semantics, pure parser probe

Extract and execute only the embedded Python parser, with a controlled default sentinel. This avoids sourcing shell startup logic or accessing any remote service.

```bash
python3 - <<'PY'
from pathlib import Path
import re,subprocess,tempfile
p=Path("plugins/leadv2/scripts/leadv2-helpers.sh")
text=p.read_text();block=text[text.index("_lv2_load_paths()"):text.index("# ── Codex policy")]
code=re.search(r"_py_script='\n(.*?)\n'",block,re.S).group(1)
with tempfile.TemporaryDirectory(prefix="astra-state-") as t:
    empty=Path(t)/"empty.yaml";empty.write_text("{}\n")
    for n in ["persona-engine","getmany-followup-bot","respiro-ios"]:
        r=Path.home()/"Projects"/n; f=r/".claude/leadv2-overrides/state-paths.yaml"
        def read(q):
            return dict(x.split("=",1) for x in subprocess.check_output(["python3","-c",code,str(q),str(r),"<state-default>"],text=True).splitlines())
        a,b=read(empty),read(f)
        print(n,"LOADER_DELTAS",{k:{"absent":a[k],"present":b[k]} for k in a if a[k]!=b[k]})
PY
```

```text
persona-engine LOADER_DELTAS {'LEADV2_LEAD_STATE_PATH': {'absent': '<state-default>', 'present': '/Users/kostiantyn.vlasenko/Projects/persona-engine/docs/LEAD_V2_STATE.md'}, 'LEADV2_TASKS_RELEASE_CMD': {'absent': '', 'present': '/Users/kostiantyn.vlasenko/Projects/persona-engine/scripts/work-item-release.sh'}}
getmany-followup-bot LOADER_DELTAS {}
respiro-ios LOADER_DELTAS {'LEADV2_TASKS_DIR': {'absent': '/Users/kostiantyn.vlasenko/Projects/respiro-ios/docs/leadv2/tasks', 'present': ''}}
```

### E6 — agents, hooks, real targets, and registrations

Regular files with no exact plugin match are candidates pending ownership classification. Hash inequality proves a delta, not that it is stale. The source settings were read only for hook paths, never changed. Duplicate path registration is a risk to test with host event traces; UNVERIFIED: whether a given current session executes both project and plugin registrations.

```bash
python3 - <<'PY'
from pathlib import Path
import hashlib,json,re
P=Path.home()/"Projects"; C=P/"leadv2/plugins/leadv2"
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
for n in ["persona-engine","getmany-followup-bot","respiro-ios"]:
    for kind in ["agents","hooks"]:
        d=P/n/".claude"/kind
        canon={digest(p) for p in (C/kind).rglob("*") if p.is_file() and not p.is_symlink()}
        print("INVENTORY",n,kind)
        for p in sorted(d.rglob("*")):
            rel=p.relative_to(d)
            if p.is_symlink():
                print(rel,"LINK",str(p.readlink()),"exists="+str(p.exists()))
            elif p.is_file():
                tag="SHADOW" if (C/kind/rel).is_file() else "candidate"
                print(rel,tag,"exact_plugin_content="+str(digest(p) in canon))
    f=P/n/".claude/settings.json"
    if f.exists():
        data=json.loads(f.read_text())
        print("HOOK_PATH_REFERENCES",n,"(paths only; no settings mutation)")
        for event,items in data.get("hooks",{}).items():
            def walk(x):
                if isinstance(x,dict):
                    for k,v in x.items():
                        if k=="command" and isinstance(v,str):
                            for q in re.findall(r'[^\s";]+/hooks/[^\s";]+',v): print(event,q)
                        else:walk(v)
                elif isinstance(x,list):
                    for v in x:walk(v)
            walk(items)
for name in ["architect.md","critic.md","security-auditor.md"]:
    for p in [C/"agents"/name,Path.home()/".claude/agents-shared"/name,P/"getmany-followup-bot/.claude/agents"/name]:
        print("SHA256",p,digest(p))
PY
```

```text
INVENTORY persona-engine agents
architect.md LINK /Users/kostiantyn.vlasenko/.claude/agents-shared/architect.md exists=True
critic.md LINK /Users/kostiantyn.vlasenko/.claude/agents-shared/critic.md exists=True
developer.md candidate exact_plugin_content=False
devops-engineer.md candidate exact_plugin_content=False
frontend-developer.md candidate exact_plugin_content=False
postgres-pro.md candidate exact_plugin_content=False
product-owner.md candidate exact_plugin_content=False
recon.md candidate exact_plugin_content=False
security-auditor.md LINK /Users/kostiantyn.vlasenko/.claude/agents-shared/security-auditor.md exists=True
shared/RULES.md candidate exact_plugin_content=False
shared/codebase-memory.md candidate exact_plugin_content=False
shared/minimalism-ladder.md candidate exact_plugin_content=False
strategist.md candidate exact_plugin_content=False
INVENTORY persona-engine hooks
anti-silence-pulse-arm-inject.sh candidate exact_plugin_content=False
anti-silence-pulse-detector.sh candidate exact_plugin_content=False
control-truth-reminder.sh candidate exact_plugin_content=False
current-plan-inject.sh candidate exact_plugin_content=False
dev-prebuild-checklist.sh candidate exact_plugin_content=False
docs-truth-inject.sh candidate exact_plugin_content=False
feature-liveness-session-inject.sh candidate exact_plugin_content=False
guard-shared-git-destructive.py candidate exact_plugin_content=False
guard-worktree-scope.sh candidate exact_plugin_content=False
lane-lesson-capture-hook.sh candidate exact_plugin_content=False
leadv2-bash-hook-dispatcher.sh candidate exact_plugin_content=False
leadv2-close-diff-guard.sh candidate exact_plugin_content=False
leadv2-compress-tool-output candidate exact_plugin_content=False
leadv2-glm-first-agent-gate.sh candidate exact_plugin_content=False
leadv2-immune-intake-inject.sh LINK /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/hooks/leadv2-immune-intake-inject.sh exists=True
leadv2-model-inherit-guard.sh LINK /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/hooks/leadv2-model-inherit-guard.sh exists=True
leadv2-phase-pulse-sync.sh candidate exact_plugin_content=False
leadv2-phase8-gate.sh candidate exact_plugin_content=False
leadv2-pulse-json.sh LINK /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/hooks/leadv2-pulse-json.sh exists=True
leadv2-queue-archiver.sh candidate exact_plugin_content=False
leadv2-reflect-enforcer.sh candidate exact_plugin_content=False
leadv2-supervisor-fanout-guard.sh candidate exact_plugin_content=False
leadv2-supervisor-mode-reinject.sh LINK /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/hooks/leadv2-supervisor-mode-reinject.sh exists=False
learn-trigger-inject.sh candidate exact_plugin_content=False
learnings-recent-inject.sh candidate exact_plugin_content=False
lifecycle-close-sync.sh candidate exact_plugin_content=False
mojibake-guard.sh candidate exact_plugin_content=False
open-threads-anchor-inject.sh candidate exact_plugin_content=False
open-threads-shrink-guard.sh candidate exact_plugin_content=False
pending-questions-inject.sh candidate exact_plugin_content=False
plugin-scripts-drift-guard.sh LINK /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/hooks/plugin-scripts-drift-guard.sh exists=True
plugin-scripts-drift-session-warn.sh LINK /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/hooks/plugin-scripts-drift-session-warn.sh exists=True
pre-commit-pnpm-build candidate exact_plugin_content=False
pre-commit-python-lint candidate exact_plugin_content=False
probe-coverage-guard.sh candidate exact_plugin_content=False
scheduled-decisions-inject.sh candidate exact_plugin_content=False
scheduled-decisions-nearest.sh candidate exact_plugin_content=False
session-start-safe-pull.log candidate exact_plugin_content=False
session-start-safe-pull.sh candidate exact_plugin_content=False
test-supervisor-fanout-guard.sh candidate exact_plugin_content=False
work-queue-inject.sh candidate exact_plugin_content=False
HOOK_PATH_REFERENCES persona-engine (paths only; no settings mutation)
SessionStart ${CLAUDE_PROJECT_DIR}/.claude/hooks/session-start-safe-pull.sh
SessionStart ${CLAUDE_PROJECT_DIR}/.claude/hooks/leadv2-queue-archiver.sh
SessionStart ${CLAUDE_PROJECT_DIR}/.claude/hooks/scheduled-decisions-inject.sh
SessionStart ${CLAUDE_PROJECT_DIR}/.claude/hooks/learn-trigger-inject.sh
SessionStart ${CLAUDE_PROJECT_DIR}/.claude/hooks/docs-truth-inject.sh
SessionStart ${CLAUDE_PROJECT_DIR}/.claude/hooks/feature-liveness-session-inject.sh
SessionStart ${CLAUDE_PROJECT_DIR}/.claude/hooks/plugin-scripts-drift-session-warn.sh
SessionStart ${CLAUDE_PROJECT_DIR}/.claude/hooks/learnings-recent-inject.sh
SessionStart ${CLAUDE_PROJECT_DIR}/.claude/hooks/anti-silence-pulse-arm-inject.sh
PreToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/leadv2-bash-hook-dispatcher.sh
PreToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/leadv2-model-inherit-guard.sh
PreToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/leadv2-glm-first-agent-gate.sh
PreToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/leadv2-supervisor-fanout-guard.sh
PreToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/dev-prebuild-checklist.sh
PreToolUse ~/.claude/hooks/guard-agent-state-write.sh
PreToolUse ~/.claude/hooks/guard-voice-dna-edit.sh
PreToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/guard-worktree-scope.sh
PreToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/dev-prebuild-checklist.sh
PreToolUse ~/.claude/hooks/guard-agent-state-write.sh
PreToolUse ~/.claude/hooks/guard-voice-dna-edit.sh
PreToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/guard-worktree-scope.sh
PreToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/guard-worktree-scope.sh
PostToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/lifecycle-close-sync.sh
PostToolUse ~/.claude/hooks/anatomy-index.sh
PostToolUse ~/.claude/hooks/auto-migration-risk.sh
PostToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/leadv2-phase-pulse-sync.sh
PostToolUse ~/.claude/hooks/anatomy-index.sh
PostToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/leadv2-phase-pulse-sync.sh
PostToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/lifecycle-close-sync.sh
PostToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/lane-lesson-capture-hook.sh
PostToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/control-truth-reminder.sh
PostToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/leadv2-pulse-json.sh
PostToolUse ~/.claude/hooks/leadv2-wiki-reindex
Stop ${CLAUDE_PROJECT_DIR}/.claude/hooks/mojibake-guard.sh
UserPromptSubmit ${CLAUDE_PROJECT_DIR}/.claude/hooks/pending-questions-inject.sh
UserPromptSubmit ${CLAUDE_PROJECT_DIR}/.claude/hooks/open-threads-anchor-inject.sh
UserPromptSubmit ${CLAUDE_PROJECT_DIR}/.claude/hooks/anti-silence-pulse-detector.sh
PostCompact ${CLAUDE_PROJECT_DIR}/.claude/hooks/leadv2-supervisor-mode-reinject.sh
INVENTORY getmany-followup-bot agents
architect.md SHADOW exact_plugin_content=False
codebase-auditor.md candidate exact_plugin_content=False
critic.md SHADOW exact_plugin_content=False
developer.md candidate exact_plugin_content=False
devops-engineer.md candidate exact_plugin_content=False
postgres-pro.md candidate exact_plugin_content=False
product-owner.md candidate exact_plugin_content=False
security-auditor.md SHADOW exact_plugin_content=False
shared/codebase-memory.md candidate exact_plugin_content=False
INVENTORY getmany-followup-bot hooks
leadv2-compress-tool-output candidate exact_plugin_content=False
leadv2-immune-intake-inject.sh LINK /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/hooks/leadv2-immune-intake-inject.sh exists=True
leadv2-phase8-gate.sh candidate exact_plugin_content=False
leadv2-reflect-enforcer.sh candidate exact_plugin_content=False
pre-commit-pnpm-build candidate exact_plugin_content=False
HOOK_PATH_REFERENCES getmany-followup-bot (paths only; no settings mutation)
PreToolUse ~/.claude/hooks/check-careful.sh
PreToolUse ~/.claude/hooks/pre-commit-tsc-check
PreToolUse ${CLAUDE_PROJECT_DIR}/.claude/hooks/leadv2-phase8-gate.sh
PostToolUse ~/.claude/hooks/anatomy-index.sh
PostToolUse ~/.claude/hooks/auto-migration-risk.sh
PostToolUse ~/.claude/hooks/anatomy-index.sh
INVENTORY respiro-ios agents
01-tca-architect.md candidate exact_plugin_content=False
02-swift-developer.md candidate exact_plugin_content=False
03-reviewer.md candidate exact_plugin_content=False
04-tester.md candidate exact_plugin_content=False
05-builder.md candidate exact_plugin_content=False
06-product-owner.md candidate exact_plugin_content=False
07-designer.md candidate exact_plugin_content=False
08-stress-researcher.md candidate exact_plugin_content=False
09-swiftui-pro.md candidate exact_plugin_content=False
10-debugger.md candidate exact_plugin_content=False
11-explorer.md candidate exact_plugin_content=False
12-founder.md candidate exact_plugin_content=False
13-marketing-strategist.md candidate exact_plugin_content=False
14-metal-specialist.md candidate exact_plugin_content=False
README.md candidate exact_plugin_content=False
architect.md LINK /Users/kostiantyn.vlasenko/.claude/agents-shared/architect.md exists=True
critic.md LINK /Users/kostiantyn.vlasenko/.claude/agents-shared/critic.md exists=True
security-auditor.md LINK /Users/kostiantyn.vlasenko/.claude/agents-shared/security-auditor.md exists=True
INVENTORY respiro-ios hooks
leadv2-immune-intake-inject.sh LINK /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/hooks/leadv2-immune-intake-inject.sh exists=True
leadv2-phase8-gate.sh candidate exact_plugin_content=False
leadv2-pulse-write.sh candidate exact_plugin_content=False
leadv2-reflect-enforcer.sh candidate exact_plugin_content=False
pre-commit-xcodebuild.sh candidate exact_plugin_content=False
session-start-safe-pull.sh candidate exact_plugin_content=False
HOOK_PATH_REFERENCES respiro-ios (paths only; no settings mutation)
SessionStart ${CLAUDE_PROJECT_DIR}/.claude/hooks/session-start-safe-pull.sh
PreToolUse ~/.claude/hooks/check-careful.sh
PreToolUse .claude/hooks/leadv2-phase8-gate.sh
PreToolUse .claude/hooks/leadv2-reflect-enforcer.sh
PreToolUse .claude/hooks/pre-commit-xcodebuild.sh
PreToolUse ~/.claude/hooks/read-dedup.sh
PostToolUse ~/.claude/hooks/anatomy-index.sh
PostToolUse ~/.claude/hooks/anatomy-index.sh
PostToolUse .claude/hooks/leadv2-immune-intake-inject.sh
PostToolUse ~/.claude/hooks/leadv2-wiki-reindex
SHA256 /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/agents/architect.md 11f281650b18709824cf45a2da17bbe55d020bce646e21cef2f63b7a87fdf95f
SHA256 /Users/kostiantyn.vlasenko/.claude/agents-shared/architect.md 7a30a485c6e07c36db589d8a23850b05a05b60b84c309418df067271d81eaa7b
SHA256 /Users/kostiantyn.vlasenko/Projects/getmany-followup-bot/.claude/agents/architect.md f3a37dee738274362170a7fd4e05d58d476dff6503bb637f8eef44277d303718
SHA256 /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/agents/critic.md edf1605ac4da803370287c297637d8810cbc1f68211a7fa67da4017c207f7f7e
SHA256 /Users/kostiantyn.vlasenko/.claude/agents-shared/critic.md e8ef4adc903b5417f89c034145caa38d003936beb116678bc7f0456b63a68869
SHA256 /Users/kostiantyn.vlasenko/Projects/getmany-followup-bot/.claude/agents/critic.md 29f8221443b91fab9343fb359f6473eeddbe02e00c6126697a57ebf006bae400
SHA256 /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/agents/security-auditor.md 2e8cb36b3fea5abd8249a766c84faa7499f25e2515f11dae9ee2511fa62eb7a5
SHA256 /Users/kostiantyn.vlasenko/.claude/agents-shared/security-auditor.md 700713f4016d0cd62e2136b937d1f70d949d77ce48a3cb421d7c0230be3ae3cb
SHA256 /Users/kostiantyn.vlasenko/Projects/getmany-followup-bot/.claude/agents/security-auditor.md 143f7f2fd42491a9ac28e4f5ad031fed45189c0904c38906d4e7b35154c60211
```

## Self-check and falsification evidence

### Report completeness — real red, correction, green

This deterministic check compares each application's live recursive override inventory, including hidden state and archives, with its report table. The initial draft omitted respiro's `verify.sh`. The red output exposed that omission; the correction was to read that script and add its substantive/manual-verification finding. This tests census completeness, not the proposed runtime checker.

Command:

```bash
python3 - <<'PYCHECK'
from pathlib import Path
import re, sys
report=Path("docs/audits/one-plugin-source-astra.md").read_text()
failed=False
for n in ["persona-engine","getmany-followup-bot","respiro-ios"]:
    section=report.split("### "+n+"\n",1)[1].split("\n##",1)[0]
    rows=re.findall(r"^\| `([^`]+)` \|",section,re.M)
    root=Path.home()/"Projects"/n/".claude/leadv2-overrides"
    files=sorted(str(p.relative_to(root)) for p in root.rglob("*") if p.is_file() and not p.is_symlink())
    missing=sorted(set(files)-set(rows)); extra=sorted(set(rows)-set(files))
    bad=bool(missing or extra or len(rows)!=len(set(rows)))
    print(("FAIL" if bad else "PASS"),n,"disk",len(files),"report_rows",len(rows),"missing",missing,"extra",extra)
    failed |= bad
sys.exit(1 if failed else 0)
PYCHECK
```

Initial raw red output:

```text
PASS persona-engine disk 38 report_rows 38 missing [] extra []
PASS getmany-followup-bot disk 8 report_rows 8 missing [] extra []
FAIL respiro-ios disk 7 report_rows 6 missing ['verify.sh'] extra []
rc=1
```

Raw green output after the report fix:

```text
PASS persona-engine disk 38 report_rows 38 missing [] extra []
PASS getmany-followup-bot disk 8 report_rows 8 missing [] extra []
PASS respiro-ios disk 7 report_rows 7 missing [] extra []
rc=0
```

### bash -n and python3 -m py_compile — changed files

The changed repository scope is Markdown only. The syntax-check selection was run after staging only the named report; no shell/Python repository file was changed and no new test suite needs registration.

```bash
git add -- docs/audits/one-plugin-source-astra.md
python3 - <<'PYCHECK'
import subprocess
names=subprocess.check_output(['git','diff','--cached','--name-only','--diff-filter=ACMR'],text=True).splitlines()
assert names==['docs/audits/one-plugin-source-astra.md'],names
for suffix,cmd in [('.sh',['bash','-n']),('.py',['python3','-m','py_compile'])]:
    files=[f for f in names if f.endswith(suffix)]
    print('CHECK', ' '.join(cmd), 'changed_files='+str(len(files)))
    for f in files: subprocess.run(cmd+[f],check=True,timeout=30)
    if not files: print('N/A: no changed '+suffix+' files')
print('PASS lane write set')
PYCHECK
git diff --cached --check
printf 'diff_check_rc=%s\n' "$?"
```

Raw output:

```text
CHECK bash -n changed_files=0
N/A: no changed .sh files
CHECK python3 -m py_compile changed_files=0
N/A: no changed .py files
PASS lane write set
diff_check_rc=0
```

The temporary evidence-probe Python scripts were also compiled successfully; they are not repository deliverables. Their complete source is embedded in this report for reproduction.

```bash
timeout 30 python3 -m py_compile /tmp/astra-source-audit-6b9a8dea/census.py /tmp/astra-source-audit-6b9a8dea/paths.py /tmp/astra-source-audit-6b9a8dea/agents-hooks.py /tmp/astra-source-audit-6b9a8dea/state-compare.py /tmp/astra-source-audit-6b9a8dea/check-report.py /tmp/astra-source-audit-6b9a8dea/override-metadata.py
printf 'probe_py_compile_rc=%s\n' "$?"
```

```text
probe_py_compile_rc=0
```

### tests/run-all.sh --scope changed — initial bounded run

```bash
timeout 240 bash tests/run-all.sh --scope changed
```

Raw output and captured exit status:

```text
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] scope=changed running 0 of 95 suites (base=main@70801308b7, 0 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=0 total=95 base=main@70801308b7 changed=0 unmapped=0 verdict=nothing_to_run reason=no_relevant_changed_files
[CORE-OFFLINE] suites passed=0 failed=0 missing=0 verdict=nothing_to_run reason=no_relevant_changed_files repo=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea
[PASS] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea/plugins/leadv2/scripts/tests/run-core-offline.sh
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea/tests/test-status-surface-bash32.sh
== T1: /bin/bash -n on the renderer ==
  ok   - renderer parses clean under bash 3.2
== T2: /bin/bash -n on the wrapper ==
  ok   - wrapper parses clean under bash 3.2
== T2b: /bin/bash -n on the broad-status composer ==
  ok   - broad-status composer parses clean under bash 3.2
== T3: env -i minimal PATH (the actual SwiftBar launch shape) renders lanes ==
  ok   - wrapper renders 2 lane row(s) under minimal PATH + bash 3.2
== T4: a dead renderer produces the failure title, never a confident 0/0 ==
  ok   - wrapper reports renderer failure, not a confident 0/0
== T5: STATUS-SURFACE-R5-01 — name resolution, unnamed, age-out, limits ==
  ok   - R5-C1: legacy stays unnamed; single-lead may resolve handoff title
  ok   - R5-C2: no-name lane renders exactly 'unnamed' (no dispatch-<sig8> in NAME)
  ok   - R5-C3: age-out boundary — live@100000 + done@899 present, done@901 absent, header counts drop
  ok   - R5-C4: heuristic cap -> 'не измеряется', no fabricated 'claude: N%'

== T6: STATUS-SURFACE-R5-01 round 2 — minimal-env parity (PyYAML-optional reader) ==
changed_scope_rc=124
```

The wrapper selected the tracked core runner, which correctly reported no relevant executable changes. The overall run did not pass: the outer time bound expired in the always-on status suite's live minimal-environment parity section. No test code or selection was changed. A longer explicitly bounded repeat follows; do not interpret the initial timeout as a clean gate or a change-induced runtime defect.

### tests/run-all.sh --scope changed — completed bounded repeat

```bash
timeout -k 10 900 bash tests/run-all.sh --scope changed
```

Complete raw output and exit status:

```text
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] scope=changed running 0 of 95 suites (base=main@70801308b7, 0 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=0 total=95 base=main@70801308b7 changed=0 unmapped=0 verdict=nothing_to_run reason=no_relevant_changed_files
[CORE-OFFLINE] suites passed=0 failed=0 missing=0 verdict=nothing_to_run reason=no_relevant_changed_files repo=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea
[PASS] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea/plugins/leadv2/scripts/tests/run-core-offline.sh
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea/tests/test-status-surface-bash32.sh
== T1: /bin/bash -n on the renderer ==
  ok   - renderer parses clean under bash 3.2
== T2: /bin/bash -n on the wrapper ==
  ok   - wrapper parses clean under bash 3.2
== T2b: /bin/bash -n on the broad-status composer ==
  ok   - broad-status composer parses clean under bash 3.2
== T3: env -i minimal PATH (the actual SwiftBar launch shape) renders lanes ==
  ok   - wrapper renders 2 lane row(s) under minimal PATH + bash 3.2
== T4: a dead renderer produces the failure title, never a confident 0/0 ==
  ok   - wrapper reports renderer failure, not a confident 0/0
== T5: STATUS-SURFACE-R5-01 — name resolution, unnamed, age-out, limits ==
  ok   - R5-C1: legacy stays unnamed; single-lead may resolve handoff title
  ok   - R5-C2: no-name lane renders exactly 'unnamed' (no dispatch-<sig8> in NAME)
  ok   - R5-C3: age-out boundary — live@100000 + done@899 present, done@901 absent, header counts drop
  ok   - R5-C4: heuristic cap -> 'не измеряется', no fabricated 'claude: N%'

== T6: STATUS-SURFACE-R5-01 round 2 — minimal-env parity (PyYAML-optional reader) ==
  ok   - _t6a: minimal-env render has no broken substring
  ok   - _t6b: lane row-count parity (min=2 full=2)
  ok   - _t6c: urgent parity (min=0 full=0)

== T7: env -i minimal PATH single-lead render (MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01) ==
  ok   - T7: single-lead source-list loop parses/runs under stripped env (rc=0, no ⚠)
== T8: bash 3.2 param-expansion split on the multibyte '·' delimiter ==
  ok   - T8a: multi-field line splits into first field + untouched remainder
  ok   - T8b: line with no ' · ' delimiter leaves remainder equal to the input (no-suffix case)
  ok   - T8c: same split verified under /bin/bash 3.2 runtime

test-status-surface-bash32: 16 passed, 0 failed, 0 skipped
[PASS] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea/tests/test-status-surface-bash32.sh
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea/tests/test-status-surface-single-lead.sh
== single-lead fixture titles ==
  ok   - status-render consumes snapshot single_lead section
  ok   - no-dispatch idle -> ⚪ idle
  ok   - active dispatch -> 🛠 abcdef12 codex 2m
  ok   - bogus state filtered -> 🛠 abcdef12 codex 2m
  ok   - pending question -> ❓1
  ok   - malformed ledger -> ⚠
  ok   - python3 unavailable -> ⚠ (no legacy fallthrough)

== process census (SWIFTBAR-ACTIVE-SOURCE-02) ==
  ok   - (a) live claude-subsession → active with sig8
  ok   - (a-registry) seeded registry label -> 🛠 FIXTURE-REGISTRY sonnet now
  ok   - (a2) human task_id from reservation preferred over sig8
  ok   - (b) worker gone + terminal → idle
  ok   - (c) exactly 3 entries (2 live + 1 reservation-only)
  ok   - (d) glm worker + terminal → idle (no terminal lanes in body)
  ok   - (e) empty everything → idle

== founder-named lanes (human task_id in run-id segment) ==
  ok   - (f) founder-named glm lane → ACTIVE once with human name
  ok   - (g) founder-named codex pid-file → ACTIVE once with human name

== T-term: fresh vs stale terminal rows (Rule R retention) ==
  ok   - (T-term-1) stale terminal (10m) drops the lane entirely
  ok   - (T-term-2) fresh terminal (60s) drops the lane entirely

== T-lead: the lead's own session is never a lane (C3) ==
  ok   - (T-lead-1) lead's own session excluded from lanes
  ok   - (T-lead-2) real codex session-runner still visible (exclusion is targeted)

== T-multi: aggregation across repos (repo label on foreign lanes) ==
  ok   - (T-multi) foreign-repo lane visible with its repo label

== T-unverifiable: repo lacking a terminal ledger contributes zero rows ==
  ok   - (T-unverifiable) repo with unreadable terminals contributes no rows

== T-name: lane_label fallback + architect phase (C4) ==
  ok   - (T-name-1) lane_label resolves the human name + legacy architect phase
  ok   - (T-name-2) no name fields at all -> sig8 fallback (legacy ~ phase)

test-status-surface-single-lead: 24 passed, 0 failed
[PASS] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea/tests/test-status-surface-single-lead.sh
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea/tests/test-status-surface-fast-names.sh
== T1: resolve_lane_label fallback chain ==
  ok   - ledger lane_label hit
  ok   - active.yaml worktree fallback
  ok   - mission heading fallback (MISSION-HEADING-TASK — implementation de)
  ok   - miss -> sig8 unchanged
  ok   - lane_label pipe stripped (got 'AB')
== T2: cold cache ==
  ok   - cold cache shows «нет кэша», no spinner
  ok   - cold render <1s (wall 0s)
  ok   - cold render kicked a refresh (lock held)
== T3: warm cache ==
  ok   - warm cache: label in title+row, no sig8 sub-row
  ok   - warm render <1s (wall 1s)
== T4: stale cache ==
  ok   - stale cache -> «⚠️ кэш устарел»
== T5: rename hygiene (SELF_PATH) ==
  ok   - copy-reply bash= path is the .5s.sh and exists (/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea/plugins/leadv2/scripts/leadv2-status-surface.5s.sh)

test-status-surface-fast-names: 12 passed, 0 failed
[PASS] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6b9a8dea/tests/test-status-surface-fast-names.sh
run-all: 4 passed, 0 failed, scope=changed
changed_scope_retry_rc=0
```

The repeat completed successfully without changing the runner, tests, or their scope. The Markdown-only diff selected no core executable regression suites; the always-on status suites completed. This is validation of the report lane's required gate, not proof that the proposed migration is implemented or safe to execute. The full-scope migration proof and host source-selection probes remain future acceptance work.
