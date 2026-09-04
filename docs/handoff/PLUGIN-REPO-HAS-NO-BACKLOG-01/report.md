# PLUGIN-REPO-HAS-NO-BACKLOG-01 — report

## What changed

This lane gives `~/Projects/leadv2` its own `docs/tasks.yaml` backlog (file-only mode, no
Supabase mirror) and migrates the 74 leadv2-scoped rows out of persona-engine's backlog.

A prior partial run of this lane had already produced and committed the substantive change
(commit `b8128434`, "feat(tasks): give leadv2 plugin repo its own docs/tasks.yaml backlog"),
present at the start of this session:

- `docs/tasks.yaml` — seeded `{total_open: 0, tasks: []}` per Step 2, then all 74 rows added
  through `leadv2_tasks_add` (never hand-edited), `lane=action` `priority=medium` uniformly,
  `id` = source `source_id` for traceability, `origin: persona-engine:<source_id>`.
- `plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh` — new negative-control suite.
- `tests/run-all.sh` — one `EXTRA_SUITE_MAP` row appended at the end of the block (not reordered).
- `docs/handoff/PLUGIN-REPO-HAS-NO-BACKLOG-01/persona-engine-close-commands.txt` — ready-to-run
  `task-close.sh` commands for the orchestrator to execute in persona-engine post-merge (this
  lane never touches that repo).

What this session did on top of that prior commit: verified every claim empirically rather than
trusting the commit message, and closed one real gap — the suite's own mutation-control comment
said "recorded manually, not run by this script"; the mission requires the mutation to be run for
real with verbatim exit codes, so this session applied the mutation to the live file, ran the
suite RED, reverted, ran it GREEN, and confirmed the revert left `git diff` on
`leadv2-tasks-lib.sh` empty (clean revert, no stray change committed). No further code changes
were needed — `docs/tasks.yaml`, the suite, and the `EXTRA_SUITE_MAP` row were already correct.

**Left alone:** `docs/tasks.yaml`, `test-plugin-repo-backlog.sh`, and the `EXTRA_SUITE_MAP` row —
already correct from the prior partial run, verified below rather than rewritten.

## Acceptance commands — raw output

```
$ python3 -c "import yaml; d=yaml.safe_load(open('docs/tasks.yaml')); \
  assert isinstance(d,dict) and 'total_open' in d and isinstance(d['tasks'],list) and len(d['tasks'])>0; \
  print('OK total_open=',d['total_open'],'len=',len(d['tasks']))"
OK total_open= 74 len= 74
exit=0
```

```
$ PROJECT_ROOT="$PWD" bash -c 'source plugins/leadv2/scripts/leadv2-tasks-lib.sh; leadv2_tasks_top_n 5'
action	medium	24cc139cc4fb	E2E-GATE-CANNOT-SEE-THE-ALLOWLIST-01
action	medium	3f5f87d37524	CI-SUITES-ARE-MACOS-ONLY-01
action	medium	96c2b64a2df4	LANE-PLACEMENT-PIN-RED-01
action	medium	c05847ab1815	LAST-LINUX-RED-FAST-NAMES-01
action	medium	fa515ffe5e3a	HEAVY-TIER-VS-SAFETY-OPUS-01
exit=0
```

5 non-empty tab-separated `lane/priority/id/title` rows — proves `leadv2-tasks-lib.sh`'s real
`load_tasks()`/`leadv2_tasks_top_n` read the new file, not just that `yaml.safe_load` can parse it.

## Row-count / identity verification (this session, not just re-trusting the commit)

```
source rows: 74 unique ids: 74
tasks.yaml total_open: 74 len tasks: 74
ids match source exactly: True
missing from tasks.yaml: set()
extra in tasks.yaml: set()
meta excluded id (540504d70585) present in tasks.yaml? False
close-commands id count: 74
close ids match source: True
dup check (no duplicate ids in close list): True
meta close line present in persona-engine-close-commands.txt: True
```

## Mutation control — negative control, run for real

Mutation applied inside `load_tasks()`'s function body in
`plugins/leadv2/scripts/leadv2-tasks-lib.sh` (this file is a bash script whose body is a large
embedded Python heredoc `<<'DISPATCHER'`; `load_tasks()` lives inside that heredoc), exactly per
mission spec: `return []` inserted as the first line of the `if isinstance(doc, dict):` block,
before the `_LIST_KEYS` loop.

```python
    if isinstance(doc, dict):
        return []  # MUTATION-CONTROL: PLUGIN-REPO-HAS-NO-BACKLOG-01 (temporary, reverted below)
        for key in _LIST_KEYS:
```

RED run:
```
$ bash plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh; echo "MUTATION_EXIT=$?"
[TEST] === PLUGIN-REPO-HAS-NO-BACKLOG-01 negative control (PROJECT_ROOT=.../PLUGIN-REPO-HAS-NO-BACKLOG-01) ===

[TEST] PASS: Test 1: docs/tasks.yaml is a {total_open, tasks:[...]} mapping with >0 rows
[TEST] FAIL: Test 2: expected rc=0 and 5 tab-separated rows, got rc=0 rows=0:

[TEST] === Results: PASS=1 FAIL=1 ===
[TEST] Failures:
[TEST]   FAIL: Test 2: expected rc=0 and 5 tab-separated rows, got rc=0 rows=0:
MUTATION_EXIT=1
```

Test 1 (bare `yaml.safe_load`) stays green because the mutation only affects the *lib's own*
`load_tasks()`, not a raw YAML parse — Test 2 (the lib's `leadv2_tasks_top_n`) goes red exactly as
predicted, proving the suite exercises the real mechanism and not a decoy.

Revert (removed the inserted `return []` line — `git diff` on `leadv2-tasks-lib.sh` came back
empty after, confirming a clean revert with no stray leftover change):

GREEN run:
```
$ bash plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh; echo "REVERT_EXIT=$?"
[TEST] === PLUGIN-REPO-HAS-NO-BACKLOG-01 negative control (PROJECT_ROOT=.../PLUGIN-REPO-HAS-NO-BACKLOG-01) ===

[TEST] PASS: Test 1: docs/tasks.yaml is a {total_open, tasks:[...]} mapping with >0 rows
[TEST] PASS: Test 2: leadv2_tasks_top_n 5 (real lib, real file) returned 5 tab-separated rows

[TEST] === Results: PASS=2 FAIL=0 ===
[TEST] All tests passed.
REVERT_EXIT=0
```

**Verbatim exit codes: RED=1, GREEN=0.**

## EXTRA_SUITE_MAP registration and `--scope changed` selection proof

Row already present (append-only, at the end of the block, not reordered — verified by reading
the full `EXTRA_SUITE_MAP` block, line 366 of `tests/run-all.sh`, the last row before the closing
quote):

```
test-plugin-repo-backlog:plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh"
```

`--scope changed` diffs against a persisted "last-checked SHA" state file
(`$(git rev-parse --git-dir)/leadv2-run-all-last-checked-sha`, HOOK-OUTPUT-CAP-PLUGIN-01) so a
lane's already-committed, already-selected suite does not re-select on every future unrelated
commit. This worktree already had that state file pointing at the current HEAD from the prior
partial run's own `run-all.sh` invocation, so a plain re-run selects nothing new — expected
behaviour, not a bug. To prove selection honestly (the documented "first run on a lane" fallback
path, not a workaround), the state file was backed up, removed, the selection re-run, then the
original state file restored byte-for-byte:

```
$ rm -f "$(git rev-parse --git-dir)/leadv2-run-all-last-checked-sha"
$ LEADV2_RUN_ALL_SELECT_ONLY=1 tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh
[SELECT] .../tests/test-run-all-carrier-map.sh
run-all: 6 selected, scope=changed, select_only=1
```

`test-plugin-repo-backlog.sh` is in the selected set. (`test-run-all-carrier-map.sh` selects too
because `tests/run-all.sh` itself is in this lane's diff — its own `EXTRA_SUITE_MAP` row,
`run-all.sh:tests/test-run-all-carrier-map.sh`, correctly fires.) State file restored after the
proof run so no other lane's future `--scope changed` invocation is affected by this probe.

## Deletion check (shared-constraints.md, three dots)

```
$ git diff --diff-filter=D --name-only main...HEAD
(empty)
exit=0
```

No file is deleted relative to the merge base.

## Linux run

Not available in this environment — no Linux container/runner was reachable from this session.
Only the macOS run above is reported; this is stated explicitly per shared-constraints.md rather
than fabricated.

## Syntax checks

```
$ bash -n plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh && echo OK1
OK1
$ bash -n tests/run-all.sh && echo OK2
OK2
$ bash -n plugins/leadv2/scripts/leadv2-tasks-lib.sh && echo OK3
OK3
```

No `.py` files were changed by this lane (`docs/tasks.yaml` is YAML; the mutation touched an
embedded Python heredoc inside a `.sh` file and was reverted before commit), so
`python3 -m py_compile` has no target — noted rather than fabricated.

## Off-limits / scope

- Did not touch `~/Projects/persona-engine` at all.
- Did not touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` or
  `plugins/leadv2/scripts/leadv2-claude-profile-select.sh` (Wave-4 hard prohibitions).
- Did not re-triage `lane`/`priority` per row beyond the uniform `action`/`medium` default.
- Did not pull in `v5`/`adhoc`/`infra` group_key rows — out of scope per brief.
- Did not premise-check whether any of the 74 rows is already resolved in code — migrated as-is.

## Commit

Work is already committed on this worktree branch as `b8128434`
("feat(tasks): give leadv2 plugin repo its own docs/tasks.yaml backlog") from the prior partial
run. This session made no code changes beyond the mutation-control apply/revert cycle (which left
the tree clean, confirmed via `git diff` before and after) and this report, committed separately.
