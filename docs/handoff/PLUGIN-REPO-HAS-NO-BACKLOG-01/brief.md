# Mission: PLUGIN-REPO-HAS-NO-BACKLOG-01

Read `docs/handoff/WAVE4/shared-constraints.md` first — binding on this lane, not restated here.

## Goal
Give `~/Projects/leadv2` its own `docs/tasks.yaml` backlog, and move the leadv2-about rows
stuck in persona-engine's backlog into it. Today `/leadv2` run inside this repo has no file to
read or write a plan to.

## Root cause — file:line evidence

**Central decision: FILE-ONLY mode, not a Supabase mirror. This is the one thing to get right.**

- `plugins/leadv2/scripts/leadv2-tasks-lib.sh:20-21` — `_PROJECT_ROOT` = caller's git toplevel (or `PROJECT_ROOT` env override); `_TASKS_FILE="${_PROJECT_ROOT}/docs/tasks.yaml"`. Nothing here requires a DB.
- `leadv2-tasks-lib.sh:98-101` + `leadv2_tasks_yaml_common.py:1-9` — the mapping shape `{total_open, tasks:[...]}` is documented, in the source, as "persona-engine's `scripts/task-sync-yaml.sh` ... a Supabase work_items projection" — an ARTIFACT of persona-engine's own mirror pipeline, not a requirement the lib imposes. `load_tasks()` / `save_tasks()` (119-163) operate purely on the local YAML file + an flock — no DB call.
- `leadv2-tasks-lib.sh:521-532`: a store is opt-in via `LEADV2_TASKS_RELEASE_CMD` (from `state-paths.yaml`'s `tasks_release_cmd` key, 526); "null (m3-market / respiro-ios / campaign-platform have no such store) => behave exactly as before this change (file-only)" (531-532). **3 of 4 live repos already run file-only.**
- Verified empirically: `~/Projects/leadv2/.claude/leadv2-overrides/state-paths.yaml` does not exist → `tasks_release_cmd` unset → this repo is file-only by default already. No stub needed.
- persona-engine's own `scripts/task-add.sh:2-6`: "the DB (work_items) is the single source of truth ... docs/tasks.yaml is a GENERATED MIRROR ... never edited by hand again" — persona-engine's own product infra (its own Supabase project). Nothing to port here.
- **Verdict:** a plain standalone `docs/tasks.yaml`, owned only by `leadv2-tasks-lib.sh`'s own `add`/`claim`/`release`/`update` ops. No Supabase stub, no `work_items` table, no `task-sync-yaml.sh` port.

**Trap — seed the mapping shape, don't grow it.** `load_tasks()` (119-129): a missing file returns `[]` with `_wrapper_key=None` → `save_tasks()` (141, wrap logic 159-163) then writes a BARE LIST. Acceptance requires the MAPPING shape. If the FIRST write to this repo's `docs/tasks.yaml` is a `leadv2_tasks_add` call, it creates the wrong shape and every later `add` preserves the mistake. Seed the empty wrapper directly, once, before the first `add` — Step 2.

## Files this lane may touch
| Path | Why |
|---|---|
| `docs/tasks.yaml` (to-create) | the new backlog |
| `docs/handoff/PLUGIN-REPO-HAS-NO-BACKLOG-01/*` | this mission's artifacts (`source-rows.json` already exists — read it, don't regenerate) |
| `plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh` (to-create) | negative-control suite |
| `tests/run-all.sh` | ONLY the `EXTRA_SUITE_MAP` block (append, never reorder — shared file) |

Read-only reference: `plugins/leadv2/scripts/leadv2-tasks-lib.sh`, `leadv2_tasks_yaml_common.py`. **Never**: anything under `~/Projects/persona-engine` — see Step 5 and Out of scope.

## Steps

1. Read `docs/handoff/PLUGIN-REPO-HAS-NO-BACKLOG-01/source-rows.json` — a frozen snapshot the architect measured against persona-engine's live `docs/tasks.yaml` (rows keyed on `intent`/`node_id`, never title). Predicate: `group_key in {leadv2,leadv2-plugin,plugin,plugin-bug} or node_id.startswith('leadv2:')`. **74 rows** (`count` field) — the source file is live and moved 73→74 between two measurements minutes apart; use the frozen snapshot, do not re-derive the count. `meta_row_excluded.id = 540504d70585` is this task itself (`node_id: human:adhoc`) already sitting in persona-engine's backlog — do NOT migrate it as an open row (Step 5 closes it instead).

2. Seed the wrapper shell (the one narrow non-lib write — a bootstrap, not a hand-edit of a row): `python3 -c "import yaml; yaml.dump({'total_open':0,'tasks':[]}, open('docs/tasks.yaml','w'), default_flow_style=False, allow_unicode=True, sort_keys=False)"`

3. Add all 74 rows through the lib — never hand-edit a row into the YAML: `source plugins/leadv2/scripts/leadv2-tasks-lib.sh` (PROJECT_ROOT auto-resolves to this repo), then per row: `leadv2_tasks_add "<source_id>" action medium --title "<title>" --origin "persona-engine:<source_id>" --note "<note>"`. Generate the 74 calls from `source-rows.json` with Python `shlex.quote()` — `note` carries Cyrillic text and unbalanced parens; do not hand-quote. Native `leadv2_tasks_add` has no equivalent of persona-engine's `group_key` / numeric `priority` (0-99, no verified severity semantics — measured distribution clusters 87-99 with 3 low outliers, not a clean bucket): default `lane=action`, `priority=medium` uniformly (a known simplification for a later re-triage pass — do not invent a mapping formula). Reuse the source `id` as the new `id` (traceability + the close-list key, Step 5).

4. Confirm `total_open` reads 74 after all adds (auto-recomputed by `save_tasks`, 159-163, since the wrapper key was captured at Step 2's seed).

5. **Persona-engine side: produce the commands, do not run them.** shared-constraints.md: "all work happens in `~/Projects/leadv2` ... Never in persona-engine." Recommend MARK, not delete, not leave-open-duplicated: `scripts/task-close.sh` is persona-engine's sanctioned non-hand-edit close path (writes to Supabase; mirror regenerates on next sync). This lane must NOT invoke it (repo-scope violation) — write the ready-to-run text into `persona-engine-close-commands.txt` for the orchestrator to run after merge:
   - 74 `source_id` values, one per line, into an ids file, then `scripts/task-close.sh --from-file <ids-file> --reason "migrated to leadv2 plugin repo docs/tasks.yaml (PLUGIN-REPO-HAS-NO-BACKLOG-01)"`
   - separately: `scripts/task-close.sh 540504d70585 --reason "resolved: leadv2 plugin repo now has its own docs/tasks.yaml (PLUGIN-REPO-HAS-NO-BACKLOG-01 complete)"`

6. Write and register the negative-control suite (below).

## Acceptance commands
```
cd ~/Projects/leadv2 && python3 -c "import yaml; d=yaml.safe_load(open('docs/tasks.yaml')); \
  assert isinstance(d,dict) and 'total_open' in d and isinstance(d['tasks'],list) and len(d['tasks'])>0"

cd ~/Projects/leadv2 && PROJECT_ROOT=~/Projects/leadv2 bash -c \
  'source plugins/leadv2/scripts/leadv2-tasks-lib.sh; leadv2_tasks_top_n 5'
```
The second command must print 5 non-empty tab-separated rows (lane/priority/id/title) — it proves the LIB reads the new file, not just that `yaml.safe_load` can parse it.

## Negative control
Suite: `plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh` (new). Keep `leadv2_tasks_top_n` / `leadv2_tasks_by_id` REAL — source the real lib against the real `docs/tasks.yaml`, fake nothing. Assert both acceptance commands above pass.

Mutation (inside a function body — shared-constraints.md's own rule: never top level): in `load_tasks()`, insert `return []` as the first line of the `if isinstance(doc, dict):` block (right after line 131, before the `_LIST_KEYS` loop at 132) — the exact mechanism the mapping-shape decision depends on. Run the suite: it must go RED (lib reports 0 tasks against a real 74-row file) — this breaks the SECOND acceptance clause specifically; the first is a bare `yaml.safe_load`, untouched by this mutation, which is why the suite needs both. Revert, show GREEN. Record both exit codes verbatim.

Register: append one `EXTRA_SUITE_MAP` row in `tests/run-all.sh:134+` (append-only, shared) mapping this lane's changed stem to the new suite; prove with `tests/run-all.sh --scope changed` showing it selected. Also run on Linux (both exit codes reported, per shared-constraints.md).

## Out of scope
- Anything under `~/Projects/persona-engine` beyond producing the close-command TEXT (Step 5).
- Re-triaging `lane`/`priority` per row beyond the uniform `action`/`medium` default.
- `group_key` buckets not in the selection predicate (`v5`=12, generic `adhoc`=6, `infra`=1): `v5` is persona-engine's own product rebuild (unrelated); the rest weren't topically confirmed. Leave them in persona-engine.
- Premise-checking whether any of the 74 rows is already resolved in code (at least one likely is — this file's own `CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01` comments describe a fix that may already cover one row's complaint). Migrate as-is; that triage is a separate pass.
- Concurrency: the lib's own flock + sha256 stale-base refusal (106-118) already covers concurrent writers to `docs/tasks.yaml`; this mission adds no locking of its own.
