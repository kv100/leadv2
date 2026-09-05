# PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 — the board says "empty" while lanes write (Standard)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-status-collector.sh,plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/tests/test-pulse-empty-board.sh,plugins/leadv2/scripts/tests/test-collector-sees-registered-lane.sh,tests/run-all.sh,docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/

The founder status pulse is the one surface that shows him lane state **without the lead relaying
anything**. On 2026-08-30 at 11:16:54Z it rendered `⚠ ДОСКА ПУСТА — ничего не выполняется` while
four lane worktrees existed and two were actively writing. That is the worst direction for this
surface to fail in: it tells him to intervene when he should not, and it will hide a real stall
when there finally is one.

## The evidence, all from the same minute

- `docs/leadv2/founder-status.md`, beat `2026-08-30T11:16:54Z`: `⚠ ДОСКА ПУСТА`, and the only table
  row is `(живых линий нет)`.
- On disk: four lane worktrees. `ANTI-SILENCE-HOOK-SCHEMA-AND-KEY-01` had **5673 files written in
  the preceding 15 minutes**; `DISPATCH-CLOSE-GATE-01` had 15.
- `docs/leadv2/active.yaml` in persona-engine **did** carry a live lane —
  `dispatch-f9ecad31`, event `registered_refresh` at `11:06:44Z`.

So the renderer had a registered live lane available in the registry and still printed empty.

## Scope — this lane fixes ONE of the two stacked failures

There are two independent failures here. **Only the second is yours.**

- *Not yours*: in the `leadv2` repo, lane registration fails outright — every dispatch prints
  `lane_state_register_failed rc=1` after `TypeError: 'NoneType' object is not iterable`. That is
  filed separately as `DISPATCH-LANE-INFRA-3PACK-01` and touches `leadv2-dispatch-code.sh`, which
  is **not** in your write set. Do not fix it here; two lanes editing that file will collide.
- *Yours*: the collector/renderer printed empty **despite a populated registry**. Registration
  worked in persona-engine and the board still showed nothing. Find out what the collector actually
  reads and why the registered row did not survive into a table row.

Start by checking whether the renderer running live is the one merged in `53247bc` (the row-identity
work) or an older copy on the live path — a stale copy on the live path is a failure shape this
repo has been burned by before.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body, RED, revert, GREEN. A
  top-level insert makes everything red for the wrong reason and reads as a pass. Logs in
  `docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/red/`.
- A control is a behavioural assertion on real rendered output. Never `grep` against script source
  — that asserts a string exists in a file while the runtime result is thrown away — and never a
  negated command as the assertion (`set -e` does not trip on it, so it can never fail).
- Bash 3.2.57 only: no `read -N`, no bash-4 array idioms, no unbound array under `set -u`.
- Prove `--scope changed` selects your suites, from a dirty tree — a lane's control plane is always
  ~20 files dirty, so a fallback that needs a clean tree silently selects nothing.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

A fixture with one registered live lane in `active.yaml` renders that lane as a row and does NOT
render `ДОСКА ПУСТА`, with the fix mutation-proven RED; the root cause named in one sentence in
`report.md` (what the collector read, and why the row was lost); `--scope changed` selecting the
suites from a dirty tree; and a **live** proof — dispatch or point at a real lane, wait one beat,
and paste the board showing its row.
