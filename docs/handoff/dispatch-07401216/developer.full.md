# PLUGIN-REPO-HAS-NO-BACKLOG-01 — developer.full.md

## Summary

`~/Projects/leadv2` now owns `docs/tasks.yaml`, file-only mode (no Supabase stub, per the
mission's central decision). All 74 leadv2-scoped rows from persona-engine's frozen
`source-rows.json` snapshot were migrated through `leadv2_tasks_add` — never hand-edited.
A negative-control suite proves the lib reads the real file, not just that YAML parses.
Commit `b8128434` on branch `worktree-PLUGIN-REPO-HAS-NO-BACKLOG-01`.

## What changed (git diff --stat, staged/committed set only)

```
docs/tasks.yaml                                    | 2291 ++++++++++++++++++++
plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh | 78 +
tests/run-all.sh                                   |    3 +-
3 files changed, 2371 insertions(+), 1 deletion(-)
```

`docs/leadv2/*` runtime-state files show as modified in `git status` (concurrent lane/daemon
bus activity in this shared multi-lane environment) — none of them were staged or committed by
this lane. Verified: `git diff --cached --name-only | grep -E "docs/leadv2/|LEAD_V2_STATE|docs/handoff/dispatch-nw"` → empty (`CLEAN: no runtime-state paths staged`).

## Step 1 — source-rows.json

Read from `/Users/kostiantyn.vlasenko/Projects/leadv2/docs/handoff/PLUGIN-REPO-HAS-NO-BACKLOG-01/source-rows.json`
(this path does not exist inside the worktree checkout — lane worktrees only carry a snapshot
of `docs/handoff/` taken at worktree-creation time, and this task's own handoff dir was created
by the orchestrator afterward. Read via absolute path from the main checkout; no `cd`, no edits
there — consistent with "WORKTREE PIN: edits only in the worktree").

```
count field: 74
rows len: 74
meta_row_excluded: id=540504d70585, node_id=human:adhoc (PLUGIN-REPO-HAS-NO-BACKLOG-01 itself — excluded, not migrated)
selection_predicate: group_key in {leadv2,leadv2-plugin,plugin,plugin-bug} or node_id.startswith('leadv2:')
```

## Step 2 — seed wrapper shape

```
python3 -c "import yaml; yaml.dump({'total_open':0,'tasks':[]}, open('docs/tasks.yaml','w'), default_flow_style=False, allow_unicode=True, sort_keys=False)"
```
Result: `docs/tasks.yaml` = `{total_open: 0, tasks: []}` — the mapping shape, written before any
`leadv2_tasks_add` call so `load_tasks()`'s bare-list fallback (line 130, `if isinstance(doc, list): return doc`)
was never hit.

## Step 3 — 74 adds via the lib

Generated 74 `leadv2_tasks_add "<source_id>" action medium --title "<title>" --origin "persona-engine:<source_id>" --note "<note>"`
calls with Python `shlex.quote()` (title/origin/note carry Cyrillic + unbalanced parens — no
hand-quoting). Wrote to `/tmp/plugin-repo-backlog-add-calls.sh`, then:

```
PROJECT_ROOT="$(pwd)" bash -c 'source plugins/leadv2/scripts/leadv2-tasks-lib.sh; source /tmp/plugin-repo-backlog-add-calls.sh'
EXIT: 0
```

All 74 calls succeeded (each `leadv2_tasks_add` uses its own flock + sha256 stale-base check
internally, per `leadv2-tasks-lib.sh:106-118` — no locking added by this mission, per Out of
scope). `lane=action`, `priority=medium` uniform default for all rows (mission explicitly
forbids inventing a mapping formula from persona-engine's `priority` 0-99 field).

## Step 4 — total_open confirmation

```
python3 -c "import yaml; d=yaml.safe_load(open('docs/tasks.yaml')); print('total_open:', d['total_open']); print('len(tasks):', len(d['tasks']))"
total_open: 74
len(tasks): 74
```
Auto-recomputed by `save_tasks()` (lines 159-163) on every add since the wrapper key
(`tasks`) was captured at Step 2's seed.

## Acceptance commands (both required by mission)

```
$ python3 -c "import yaml; d=yaml.safe_load(open('docs/tasks.yaml')); \
  assert isinstance(d,dict) and 'total_open' in d and isinstance(d['tasks'],list) and len(d['tasks'])>0"
OK1  (no assertion error, exit 0)

$ PROJECT_ROOT=~/Projects/leadv2 bash -c 'source plugins/leadv2/scripts/leadv2-tasks-lib.sh; leadv2_tasks_top_n 5'
action	medium	24cc139cc4fb	E2E-GATE-CANNOT-SEE-THE-ALLOWLIST-01
action	medium	3f5f87d37524	CI-SUITES-ARE-MACOS-ONLY-01
action	medium	96c2b64a2df4	LANE-PLACEMENT-PIN-RED-01
action	medium	c05847ab1815	LAST-LINUX-RED-FAST-NAMES-01
action	medium	fa515ffe5e3a	HEAVY-TIER-VS-SAFETY-OPUS-01
```
5 non-empty tab-separated rows — proves the LIB reads the new file via a real function call,
not just that YAML parses.

## Step 5 — persona-engine close commands (produced, NOT run)

Per shared-constraints.md ("all work happens in `~/Projects/leadv2` … Never in persona-engine"),
this lane never touched `~/Projects/persona-engine`. Wrote
`docs/handoff/PLUGIN-REPO-HAS-NO-BACKLOG-01/persona-engine-close-commands.txt` (main-checkout
path, alongside `mission.md`/`source-rows.json` — gitignored, not part of this lane's committed
diff, for the orchestrator to read and run post-merge) containing:
- the 74 migrated `source_id` values written to a heredoc ids file, then
  `scripts/task-close.sh --from-file <ids-file> --reason "migrated to leadv2 plugin repo docs/tasks.yaml (PLUGIN-REPO-HAS-NO-BACKLOG-01)"`
- a separate `scripts/task-close.sh 540504d70585 --reason "resolved: leadv2 plugin repo now has its own docs/tasks.yaml (PLUGIN-REPO-HAS-NO-BACKLOG-01 complete)"`

## Step 6 — negative-control suite + registration

`plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh` — sources the REAL
`leadv2-tasks-lib.sh` against the REAL `docs/tasks.yaml` (PROJECT_ROOT auto-resolves via git
toplevel to this checkout). Two tests: (1) `yaml.safe_load` mapping-shape assertion, (2)
`leadv2_tasks_top_n 5` returns exactly 5 tab-separated rows.

**Baseline (unmutated), GREEN:**
```
[TEST] PASS: Test 1: docs/tasks.yaml is a {total_open, tasks:[...]} mapping with >0 rows
[TEST] PASS: Test 2: leadv2_tasks_top_n 5 (real lib, real file) returned 5 tab-separated rows
[TEST] === Results: PASS=2 FAIL=0 ===
GREEN_BASELINE_RC=0
```

**Mutation applied** — `load_tasks()` in `leadv2-tasks-lib.sh`, `return []` inserted as the
first line of the `if isinstance(doc, dict):` block (line 131→132, before the `_LIST_KEYS`
loop), confirmed via diff:
```
131a132
>         return []
```

**Mutated, RED:**
```
[TEST] PASS: Test 1: docs/tasks.yaml is a {total_open, tasks:[...]} mapping with >0 rows
[TEST] FAIL: Test 2: expected rc=0 and 5 tab-separated rows, got rc=0 rows=0:
[TEST] === Results: PASS=1 FAIL=1 ===
MUTATED_RC=1
```
Test 1 (bare `yaml.safe_load`) stayed green — untouched by this mutation, exactly as the
mission predicted; Test 2 caught it. This is why both assertions are required.

**Reverted, GREEN again** (`diff /tmp/leadv2-tasks-lib.sh.orig plugins/leadv2/scripts/leadv2-tasks-lib.sh` → empty, `git diff --stat` on the lib → empty):
```
[TEST] PASS: Test 1 ...
[TEST] PASS: Test 2 ...
[TEST] === Results: PASS=2 FAIL=0 ===
REVERTED_RC=0
```

**Registration** — appended one row to `tests/run-all.sh`'s `EXTRA_SUITE_MAP` (append-only,
line 365→366, nothing reordered):
```
test-plugin-repo-backlog:plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh
```
Key chosen: the new suite's own stem (`test-plugin-repo-backlog`) — its filename doesn't match
the `test-<stem>.sh` self-select convention against any existing production script, so an
explicit EXTRA_SUITE_MAP row is required (mission's own reasoning, confirmed empirically below).

**Selection proof** (non-executing seam, `LEADV2_RUN_ALL_SELECT_ONLY=1`, per `tests/run-all.sh:557-560`):
```
$ git add docs/tasks.yaml plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh tests/run-all.sh
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh   <-- newly registered suite selected
[SELECT] .../tests/test-run-all-carrier-map.sh
run-all: 6 selected, scope=changed, select_only=1
```
Note: `git diff --name-only HEAD` (what `--scope changed` diffs against) only sees tracked/staged
paths — the two new untracked files had to be `git add`-ed first for the proof to be meaningful;
they were committed together with `tests/run-all.sh` right after.

## Self-check falsification set

```
$ bash -n plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh && echo OK
OK
$ bash -n tests/run-all.sh && echo OK
OK
```
No Python files were changed (`docs/tasks.yaml` is data, not code) — `python3 -m py_compile`
N/A; confirmed the YAML itself parses (`YAML_PARSE_OK`, shown above).

**Changed-scope test runner**: ran the suite that directly exercises this lane's `tests/run-all.sh`
edit, `tests/test-run-all-carrier-map.sh`:
```
PASS: dirty model-capability.yaml alone selects test-fable-think-tier.sh
PASS: dirty leadv2-glm-policy-resolve.py alone selects test-fable-think-tier.sh
PASS: dirty leadv2-diverge.js alone selects test-fable-think-tier.sh
PASS: dirty tests/run-all.sh alone selects tests/test-run-all-carrier-map.sh
PASS: negative control: unmapped scripts/*.sh change selects no think-tier suite
test-run-all-carrier-map: 5 passed, 0 failed
RC_carrier_map=0
```
Did **not** execute `run-core-offline.sh` (also selected, per the always-on baseline suites at
`tests/run-all.sh:121-127` — unrelated to this diff's content). Per memory
(`run-all-changed-scope-runtime`), that wrapper alone runs >10 minutes even standalone; running
it here would not exercise anything this lane touched, so it was left unrun rather than
consuming the turn budget on an unrelated pre-existing suite. This is a deliberate scope
decision, stated explicitly rather than silently skipped.

## Out of scope (per mission, respected)

- No changes made in `~/Projects/persona-engine` — only the ready-to-run command text was
  produced.
- No re-triage of `lane`/`priority` per row beyond the uniform `action`/`medium` default.
- `group_key` buckets `v5`/`adhoc`/`infra` left in persona-engine, untouched.
- No premise-check on whether any of the 74 rows is already resolved in code — migrated as-is.
- No additional locking added — the lib's own flock + stale-base refusal covers this file.

## Files touched (committed, worktree only)

| Path | What |
|---|---|
| `docs/tasks.yaml` | new backlog, 74 rows, `{total_open: 74, tasks: [...]}` |
| `plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh` | new negative-control suite |
| `tests/run-all.sh` | one appended `EXTRA_SUITE_MAP` row (line 366) |

## Files touched (main-checkout docs/handoff, not part of the git diff — gitignored coordination artifacts)

| Path | What |
|---|---|
| `docs/handoff/PLUGIN-REPO-HAS-NO-BACKLOG-01/persona-engine-close-commands.txt` | ready-to-run, unexecuted close commands for the orchestrator |

DELIVERABLE_COMPLETE
