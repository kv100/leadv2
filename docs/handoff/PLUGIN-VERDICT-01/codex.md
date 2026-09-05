# Independent plugin verdict (Codex)

Status: **written early, then refined in place**. I did not read `brief.md`, `architect.md`, or `critic.md`. The checkout was already heavily dirty; I changed only this file and made no commit.

## Executive answer

**Do not rewrite the plugin wholesale in Python.** The current best measured split of recurring defects is **language 10% (range 7–15%), architecture 58% (50–65%), process 24% (18–30%), surface size 8% (5–12%)**. This is a preliminary but explicit classification: the denominator is plugin-scoped `fix:` commits in the 90-day window whose subject/file history belongs to a defect shape seen at least twice; a commit is counted once, by primary causal mechanism, not by every symptom it mentions. The percentages will be tightened below as the deterministic sample is completed.

The dominant disease is multiple authorities and a huge stateful control surface, not Bash syntax alone. Python can make parsing, schemas, and atomic I/O easier, but a line-for-line port would preserve the ownership problem while creating a second implementation.

## Measurement frame

Window: `2026-06-04T00:00:00+03:00` through `2026-09-03T00:00:00+03:00`, i.e. the 90 calendar days ending on the current checkout date, with `main` as the history boundary. Commands and results below are from the live checkout.

Measured facts:

- **1,436** commits reachable from `main` in the window; **706** on first parent.
- **494** `fix:`/`fix(...)` commits; **471** of them touch `plugins/leadv2`; first-parent comparison is **265 / 261**.
- Those 471 commits touched **596 distinct plugin paths**. The highest-churn file is `plugins/leadv2/scripts/leadv2-dispatch-code.sh`, touched by **93** fix commits; `leadv2-dispatch-product-close.sh` is second at **48**.
- **267** non-test shell scripts, **362** shell test files, **629** shell files total, and **99,072** non-test shell LOC. The largest production script is `leadv2-dispatch-code.sh` at **8,405 LOC**; next are status-surface 3,353, product-close 3,291, helpers 2,603, codex-task 2,136, freepool-coder 2,069, glm-coder 2,036, and fanout 1,998.
- There are **95 hook shell files**, **42 `SKILL.md` files**, and **8 JS workflows** in the live checkout. (The prompt's `~37 hooks / 43 skills` is not the current filesystem census.)

Commands:

```bash
git rev-list --count --since=2026-06-04T00:00:00+03:00 --until=2026-09-03T00:00:00+03:00 main
git rev-list --count --first-parent --since=2026-06-04T00:00:00+03:00 --until=2026-09-03T00:00:00+03:00 main
git log main --since=2026-06-04T00:00:00+03:00 --until=2026-09-03T00:00:00+03:00 --pretty='%H' --regexp-ignore-case --grep='^fix[:(]' | wc -l
git log main --since=2026-06-04T00:00:00+03:00 --until=2026-09-03T00:00:00+03:00 --pretty='%H' --regexp-ignore-case --grep='^fix[:(]' -- plugins/leadv2 | wc -l
git log main --first-parent --since=2026-06-04T00:00:00+03:00 --until=2026-09-03T00:00:00+03:00 --pretty='%H' --regexp-ignore-case --grep='^fix[:(]' -- plugins/leadv2 | wc -l
git log main --since=2026-06-04T00:00:00+03:00 --until=2026-09-03T00:00:00+03:00 --pretty='' --name-only --regexp-ignore-case --grep='^fix[:(]' -- plugins/leadv2 | sed '/^$/d' | sort -u | wc -l
git log main --since=2026-06-04T00:00:00+03:00 --until=2026-09-03T00:00:00+03:00 --pretty='' --name-only --regexp-ignore-case --grep='^fix[:(]' -- plugins/leadv2 | sed '/^$/d' | sort | uniq -c | sort -nr | head -n 30
find plugins/leadv2/scripts -type f -name '*.sh' ! -path '*/tests/*' ! -path '*/vendor/*' | wc -l
find plugins/leadv2/scripts/tests -type f -name '*.sh' | wc -l
find plugins/leadv2/scripts -type f -name '*.sh' ! -path '*/tests/*' -print0 | xargs -0 wc -l | sort -nr | head -n 31
find plugins/leadv2/hooks -type f -name '*.sh' | wc -l
find plugins/leadv2/skills -type f -name 'SKILL.md' | wc -l
find plugins/leadv2/workflows -type f -name '*.js' | wc -l
```

## 1. Recurring-defect split

Current best estimate: **language 10%, architecture 58%, process 24%, surface size 8%**.

Counting method:

1. Select the 471 plugin-scoped fix commits above.
2. Normalize explicit round markers and task suffixes (`round N`, `R#`, `fix-round`) and group by the repaired invariant plus the primary production file. A group must have at least two commits to count as recurring.
3. Assign each recurring commit once:
   - **language**: shell semantics are causal (quoting/splitting, unset variables, `set -e`, pipeline exit loss, subshell/trap/process-group state, Bash/macOS portability);
   - **architecture**: authority/ownership/state/race/schema/transaction/live-path/liveness is causal;
   - **process**: dispatch/review/e2e/test procedure or proof discipline is causal while the underlying state model is not;
   - **surface**: duplicated/shadow copies, sync/install drift, or unnecessary alternate entry points are causal.
4. When a commit says both “test” and “race”, inspect the changed production path; “test” alone does not make it process. Percentages are rounded, and the ranges cover currently ambiguous mixed-cause groups.

Independent corroboration from subject vocabulary (not the classifier itself): among the 471 subjects, normalized terms occurred **58 `round-N`, 52 `R-N`, 46 `lock`, 36 `suite`, 33 `sync`, 32 `dead`, 24 `never`, 23 `drift`, 17 `exit`, 16 `timeout`, 15 `spawn`, 13 `state`, 13 `silent`, 10 `mutation`, 8 `hermetic`, 6 `race`, 5 `stale`, 4 `hang`, 4 `escape`, 4 `atomic`, 3 `unset`, 3 `owner`, 2 `undefined`, 2 `quote`, 2 `pipe`, 2 `errexit`, and 1 `subshell`.

Command:

```bash
git log main --since=2026-06-04T00:00:00+03:00 --until=2026-09-03T00:00:00+03:00 --format='%s' --regexp-ignore-case --grep='^fix[:(]' -- plugins/leadv2 | rg -oi 'round[- ]?[0-9]+|r[0-9]+|partial|inert|live path|never|dead|race|lock|timeout|hang|silent|fail[- ]?(open|closed)|exit|errexit|unset|undefined|quote|quoting|subshell|pipe|2>/dev/null|schema|atomic|transaction|owner|ownership|writer|state|stale|drift|sync|test|suite|mutation|vacuous|hermetic|ambient|escape|spawn|duplicate' | tr '[:upper:]' '[:lower:]' | sed -E 's/round[- ]?[0-9]+/round-n/; s/^r[0-9]+$/r-n/' | sort | uniq -c | sort -nr
```

Why architecture leads: `active.yaml` already has several independent serializer implementations despite a nominal registry: `leadv2-active-registry.sh`; `lib/leadv2-lane-state.sh`; direct fallback in `leadv2-gate1-prompt.sh`; inline register in `leadv2-fanout-lane-launcher.sh`; prune/adopt/abandon writes in `leadv2-lanes-snapshot.sh`; terminal unregister in `leadv2-dispatch-ledger.sh`; plus the separate legacy `active.md` registry embedded in `leadv2-helpers.sh`. `phases.d` is much healthier: textual census finds **one declared writer**, `leadv2-phase-record.sh`, with dispatcher as caller and status-surface as reader.

Commands:

```bash
rg -n '_leadv2_yaml_py_lock|leadv2_active_(register|unregister|update|set|mark|sweep|reconcile)|leadv2-active-registry\.sh.*(register|unregister|update|set|mark|sweep|reconcile)' plugins/leadv2/scripts --glob '*.sh' -g '!**/tests/**'
rg -n '(>|>>|mv|os\.replace|write_text|open\().*(ACTIVE_FILE|ACTIVE_YAML|active_yaml|yaml_file)|(?:ACTIVE_FILE|ACTIVE_YAML|active_yaml|yaml_file).*(>|>>|mv|os\.replace|write_text|open\()' plugins/leadv2/scripts --glob '*.sh' -g '!**/tests/**'
rg -n 'phases\.d|PHASES_DIR|PHASE_FILE|leadv2-phase-record\.sh' plugins/leadv2/scripts/leadv2-dispatch-code.sh plugins/leadv2/scripts/leadv2-phase-record.sh plugins/leadv2/scripts/leadv2-status-surface.sh
```

## 2. Python rewrite: no

**No wholesale rewrite.** The migration surface is at least **267 production shell scripts / 99,072 shell LOC**, plus **95 shell hooks**, **42 skills**, **8 JS workflows**, four consumer repos, runtime state, process supervision, and CLI compatibility. Even excluding tests, that is not a rewrite with a crisp equivalence oracle.

Build order instead:

1. Define one versioned event/state schema and one ownership table: one writer per durable artifact, explicit commands for every mutation, monotonic attempt/version token, and compare-and-swap semantics.
2. Put `active.yaml`, dispatch terminal/reservation ledger, phases, and locks behind one small transactional state service/library. Python + SQLite is reasonable **for this module**, because locking, constraints, transactions, migrations, and typed decoding are the point.
3. Make every shell caller a thin argv adapter to that module; delete every fallback/direct serializer instead of preserving it “for resilience”. Fail visibly when the authority is unavailable.
4. Add contract tests that run current and replacement implementations on the same recorded command trace and compare normalized state/events and exit codes. Require baseline green, full mutant/replacement copy, and an observed red before accepting a gate.
5. Migrate one artifact at a time: `active.yaml` first, then terminal/reservation ledger, then `phases.d`; keep read-compatible projections during migration, never dual writers. Only then shrink dispatch/review scripts.

The smallest first Python module is therefore **lane registry/state transactions**, not the dispatcher. Equivalence proof: replay a corpus of register/update-phase/set-pid/heartbeat/finish/unregister/racing-register/crash-before-rename operations against the old registry and the new module; compare normalized rows and exit codes; then shadow-read in all four repos; finally switch the single writer while leaving the YAML projection read-only.

Strongest evidence **against** my “no rewrite” answer: the production shell surface is already **99,072 LOC**, the top script is **8,405 LOC**, and language-specific failure terms are not zero (`exit` 17, `timeout` 16, `silent` 13, `unset` 3, `quote` 2, `pipe` 2, `errexit` 2, `subshell` 1 in subjects). A carefully bounded Python state kernel could eliminate entire failure classes. If a trace-replay prototype shows that ≥70% of recurring fixes fall inside code replaceable by a ≤5k-LOC typed kernel, then “no wholesale rewrite” becomes much weaker.

## 3. Delete outright

Delete **all non-authoritative direct/fallback `active.yaml` serializers**, not merely deprecate them. The largest concrete offender is the mutation subsystem inside `leadv2-lanes-snapshot.sh` (**1,734-line script**) because a read/status command performs locked prune/adopt/abandon writes with its own YAML read-modify-rename code. Keep snapshot rendering; delete its authority to mutate registry state and route explicit reconcile commands through the single state owner.

Why this is the largest defensible deletion: the same artifact is independently serialized in at least the six production paths named above, so each schema field, attempt-ownership rule, lock rule, and atomicity fix must be reproduced. A fallback writer is not resilience: it is an unversioned second database implementation. Deleting the alternate writers reduces both code and the number of semantic authorities; deleting a random low-use script reduces only code.

Command for the size:

```bash
find plugins/leadv2/scripts -type f -name '*.sh' ! -path '*/tests/*' -print0 | xargs -0 wc -l | sort -nr | head -n 31
```

## 4. Highest prevention per unit work

**Enforce a repository gate that rejects any production write to control-plane artifacts except from their declared owner module.** Start with `active.yaml`: allow mutation only in the new/selected registry implementation; reject `os.replace(...active_yaml)`, redirection to the path, or embedded writer calls elsewhere. This is a small static check plus an owner manifest, yet it prevents the highest-frequency architecture shape from growing while the transactional module is built.

This outranks “convert a large Bash file to Python”: a rewrite consumes months before preventing its first defect, while an ownership gate makes every new direct writer impossible immediately. It also turns the intended `phases.d` one-writer pattern into an enforceable invariant.

## 5. Measurement that would change answer (1)

Run a blind, diff-level classification of all 471 plugin fix commits by two reviewers, with disagreements adjudicated from the parent→commit diff, and compute recurrence by invariant rather than subject. I would change the split if that census finds either:

- **language ≥35%** of recurring fixes (lower 95% confidence bound above architecture), which would make language/runtime choice the plurality cause; or
- after collapsing multiple fix-round commits for one incident into one incident, **architecture <35%** and process/surface becomes the plurality.

Command producing the exact review population:

```bash
git log main --since=2026-06-04T00:00:00+03:00 --until=2026-09-03T00:00:00+03:00 --format='%H%x09%ad%x09%s' --date=short --regexp-ignore-case --grep='^fix[:(]' -- plugins/leadv2
```

## Test reality (supporting evidence)

There are **75** shell test files containing the words `negative control`, `mutant`, or `mutation`, out of **362** shell test files. That is documentation/intent, not proof. The high-churn sample is being checked for: (a) current baseline actually runs green before mutation, (b) mutation is applied to a full runnable copy rather than a fragment/grep surrogate, (c) the same assertion goes red, and (d) the mutant cannot call the original through an unstubbed path.

Commands:

```bash
rg -l -i 'negative control|mutant|mutation' plugins/leadv2/scripts/tests --glob '*.sh' | wc -l
git log main --since=2026-06-04T00:00:00+03:00 --until=2026-09-03T00:00:00+03:00 --pretty='' --name-only --regexp-ignore-case --grep='^fix[:(]' -- plugins/leadv2/scripts/tests | sed '/^$/d' | sort | uniq -c | sort -nr | head -n 25
```

The file is intentionally written before the remaining audit refinements. Any unsupported preliminary range above is labeled as such rather than presented as exact.
