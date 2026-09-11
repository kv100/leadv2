# PREMISE-PROBE-BEFORE-A-LANE-IS-DISPATCHED-01 — lane report

Repos: leadv2 (worktree `29e2668a9383`, base = origin/main `a3ac0067`, which is an
ancestor of this lane — the DISPATCH-HONESTY-01 merge `0a06591c` sits BELOW this
work, not beside it). Date: 2026-09-11.

## What changed

### `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (+246/−1, commit `2d989b80`)

New gate `_premise_probe_gate`, defined before `usage()` (~:7900), called in
`cmd_resolve` immediately BEFORE the burn gate — i.e. before the placement pin,
the ensure block, the architect prepass, any registry/ledger row, reservation or
spawn (same "nothing paid for" zone B5-HANDOFF-WRITESET documents):

- **Probe resolution** (fail-closed python resolver, mirrors phase8-close's
  `[backlog-row]` resolver): `--task-id` founder id → `docs/tasks.yaml` rows via
  the shared colon-anchored matcher `leadv2_tasks_yaml_common.row_matches` (never
  a substring). Roots: `PROJECT_ROOT`, then the git-common-dir parent (worktree
  durable root). **The premise is a property of the ROW**: the gate runs only
  when exactly one row resolves. The row's probe command comes from the caller's
  `--acceptance-cmd` (leadv2-fanout.sh already forwards the row's
  `acceptance_cmd` field through it) or the row's own `acceptance_cmd` field.
  A bare `--acceptance-cmd` with no row is a downstream-gate declaration, never
  a premise — measured 2026-09-11: `test-leadv2-lane-shape.sh` and
  `test-plugin-papercuts.sh` dispatch with `--acceptance-cmd 'true'` and no row;
  gating those would have refused them on a green `true` (regression control:
  suite case T10). `acceptance_probe_id` alone points into the Supabase
  `probe_registry`, which no plugin-side path can read — refused as
  `probe_cmd_unreadable` with the remedy naming the runnable forms.
- **Verdicts** (probe runs via `bash -c`, cwd = the root that resolved the row):
  - rc=0 → **premise dead**: journal `premise_dead task=<sig8> row=<sid>`; close
    the row through the repo-native seam `${PROJECT_ROOT}/scripts/task-close.sh
    <shortid> --reason ...` (seam absent → logged, row left to its owner; close
    failure → loud, row stays queued and re-probes next dispatch); exit **7**,
    no ledger row, no worktree, no spawn.
  - rc≠0 (and 125/126/127 excluded) → **premise alive**: journal
    `premise_probe ... verdict=alive`, dispatch proceeds byte-identically.
  - rc 125/126/127 → `probe_not_runnable`; killed at deadline →
    `probe_budget_exceeded` — both **premise_unknown**, exit **8**.
  - No readable probe → exit **8** `no_premise_probe`; 2+ rows match → exit **8**
    `row_ambiguous`; resolver crash → exit **8** `resolver_failed`. Every exit-8
    refusal prints reason + remedy as the LAST stderr line (the repo's
    repeat-the-reason-last discipline).
- **Budget**: `LEADV2_PREMISE_PROBE_BUDGET_SEC` (default 120, non-numeric or <1
  falls back to 120), enforced by a kill -0 poll + kill (house liveness idiom;
  GNU timeout(1) does not exist on stock macOS).
- **Scope**: `--task-id` resolving to no row keeps today's ad-hoc contract
  (journal `premise_probe verdict=skipped reason=no_backlog_row`); `--resume-lane`
  / `--worktree` pins skip the gate (in-flight lanes finish their own work).
  `LEADV2_PREMISE_PROBE=0` disables (journaled skip), the emergency-valve
  convention of `LEADV2_BURN_GOVERNOR=0`.
- `usage()` documents exits 7/8 + the two env vars.

Ordering rationale (also in the code): the gate runs BEFORE `_burn_gate` — a
dead premise makes every later check moot, and burn's parked-retry flow must
never absorb what is actually a premise verdict.

### `plugins/leadv2/scripts/tests/test-dispatch-refuses-a-dead-premise.sh` (new, 324 lines)

`# run-all-triggers: leadv2-dispatch-code`, committed (suite-discovery admission).
Drives the REAL dispatch script end to end in a hermetic fixture git repo; the
only fakery is one level BELOW the dispatch path (fake launcher bins, recording
journal bin, argument-recording `scripts/task-close.sh` interceptor — the same
seam discipline as `test-phase8-closes-the-backlog-row.sh`). The probes are REAL
greps/sleeps against REAL fixture files (green probe greps a fixed lib for an
absent defect marker; red probe greps a lib that genuinely carries it).

| case | premise | expected | status |
|---|---|---|---|
| T1 | row probe green | rc=7, row closed (shortid+reason), journal `premise_dead task= row=`, worker NEVER started | PASS |
| T2 | row probe red | rc=0, worker started, row NOT closed | PASS |
| T3 | row, no probe | rc=8 `no_premise_probe`, remedy names task-add/--acceptance-cmd/acceptance_cmd, nothing spent | PASS |
| T4 | probe id Supabase-only | rc=8 `probe_cmd_unreadable`, remedy | PASS |
| T5 | probe `sleep 30`, budget 1s | rc=8 `probe_budget_exceeded` | PASS |
| T6 | probe cmd missing | rc=8 `probe_not_runnable` | PASS |
| T7 | --task-id, no row | rc=0, worker started (ad-hoc contract preserved) | PASS |
| T8 | green, no task-close.sh | rc=7, row left to owning repo, logged | PASS |
| T9 | 2 rows match founder id | rc=8 `row_ambiguous`, nothing closed | PASS |
| T10 | `--acceptance-cmd 'true'`, NO row | rc=0, worker started (declarative callers intact) | PASS |
| T0 | bash -n both files | PASS |

Result: **37 passed, 0 failed** (rc 0) — number re-verified in the falsification section below.

## Acceptance mapping (brief §Приёмка)

- зелёная проба → ряд закрыт, воркер НЕ запущен: **T1** (close interceptor +
  journal line + spawn-marker absence, on the real dispatch path).
- красная → диспатч идёт: **T2** (full spawn path in the fixture, fake launchers
  one level below).
- пробы нет → отказ с remedy: **T3** (+ T4 unreadable, T5 budget, T6
  not-runnable, T9 ambiguous — every refusal class names itself).
- "Держать НАСТОЯЩИЙ путь диспатча под утверждением": the suite never
  reimplements gate logic; it dispatches the real script. Probes/registry are
  real (real tasks.yaml rows through the real shared matcher; real greps).
- Бюджет в переменной, `premise_unknown` отдельный класс: **T5** with
  `LEADV2_PREMISE_PROBE_BUDGET_SEC`.

## Negative control (brief §Негативный контроль)

Declared mutation (suite header, run via `leadv2-mutation-control.sh`):
**(а)** the premise-dead exit is neutralised —
`s/exit "${PREMISE_DEAD_RC}"/return 0/` — so a green premise falls through to a
spent lane. Expected: T1 reds. Raw output: `round1-red.txt` (this dir) + the
mutation-control artifact under `mutation-control/`.

## Falsification set (self-check)

- `bash -n` dispatch script: OK (after every edit, including the rescope).
- `bash -n` suite: OK.
- No Python files changed (`py_compile` n/a; the resolver heredoc lives in the
  shell file and is exercised by every T-case through the real dispatch).
- Suite on the real dispatch path: `37 passed, 0 failed`, rc=0 (rerun after the
  rescope, log tail: `SUITE_RC=0 … 37 passed, 0 failed`).
- `test-plugin-papercuts.sh` (uses `--acceptance-cmd 'true'` with no row; its
  triggers header DOES list `leadv2-dispatch-code.sh`, so changed-scope selects
  it too). Direct run on my head: **9 passed, 5 failed** — with a three-point
  control proving the red is INHERITED, not from this lane's commits:
  - `a3ac0067` (origin/main, pristine): **14 passed, 0 failed**
  - `5d55007c` (my lane parent — the DISPATCH-HONESTY-01 /
    SELECTOR-SKIPS-EXHAUSTED-01 merges, WITHOUT my two commits): **9 passed,
    5 failed** — the IDENTICAL five (P1a, P1b, P2a loop-arm flakes; P3
    route_tier_invalid expectation; P4 codex spawn_failed journal expectation)
  - my head `f86a7732`: same 9/5, same five lines — zero NEW failures from the
    premise gate.
  The P3/P4 expectations collide with the earlier lane merge's honest-fallback
  behavior (same file the brief warned about); fixing those assertions belongs
  to that merge's lane, not this one. Flagging for the lead: when this branch
  merges, papercuts P3/P4 ride along red regardless of the premise gate.
  Also note: leadv2's own `docs/tasks.yaml` exists (74 rows, a different
  schema from persona-engine's work_items mirror) — the gate reads it via the
  shared tolerant loader; papercuts dispatches carry no resolvable founder row,
  so the gate skips there (the T10 regression control covers exactly this).
- `tests/run-all.sh --scope changed` (merge-base a3ac0067..HEAD, commits
  `2d989b80` + `f86a7732`): chain log `CHAIN-DONE runall rc=` line below.

Commits: `2d989b80` (gate + suite) → `f86a7732` (row-scoping fix + T10).

## Out-of-bounds compliance

- Branched from fresh main (origin/main a3ac0067 is the lane's merge-base;
  DISPATCH-HONESTY-01 is below this work and intact — the gate inserts before
  `_burn_gate`, disjoint from the honesty fixes).
- Suite writes only to its own `lv2_mktemp_dir` TMP; never touches
  `~/.claude/leadv2-state/` (journal bin is overridden to a recorder; dispatch
  cache dir and lane work root point into TMP).

## Remedy text (what a refused caller sees)

`no_premise_probe`: "the row carries no acceptance probe; add one:
scripts/task-add.sh \"<subject>\" --acceptance-cmd '<cmd>' --expect '<expr>' in
the repo-owner, or add acceptance_cmd: '<cmd>' to the row and regenerate the
mirror (scripts/task-sync-yaml.sh), or dispatch with --acceptance-cmd '<cmd>'
(probe rc=0 = premise dead = row closed before any lane is spent)"

Note on the 45%/55% split (measured 2026-09-11 against the live persona-engine
`docs/tasks.yaml`): 554 rows — 260 (46%) carry `acceptance_probe_id`, 294 (53%)
carry none, and **0** carry a runnable inline `acceptance_cmd`. Probe BODIES
live in Supabase's `probe_registry`, which the plugin cannot read; until rows
carry a runnable `acceptance_cmd` (or the caller passes `--acceptance-cmd`),
those dispatches refuse loudly with the remedy above — the brief's intended
default (refuse more often than wave through; a visible refusal costs seconds,
a silently misspent lane costs the lane).
