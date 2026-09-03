# PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 — round 2 report

The collector's `_sc_lanes_section` (`plugins/leadv2/scripts/leadv2-status-collector.sh`)
invokes `leadv2-lanes-snapshot.sh --json` to read `active.yaml`; that snapshot script honors
`LEADV2_LANES_ALL_REPOS` to decide whether it reads only `PROJECT_ROOT`'s own control plane or
scans every registered repo. Without the pin, the snapshot silently scoped to the founder board's
own repo, so a lane registered in a different repo's `active.yaml` (e.g. persona-engine while the
board runs against leadv2, or vice versa) never produced a row and the board rendered `ДОСКА
ПУСТА` even while that lane was writing thousands of bytes to its stream log — the exact incident
reported. Round 1's one-line fix (`LEADV2_LANES_ALL_REPOS=1` pinned inside `_sc_lanes_section`, not
left to ambient env) is correct; round 2 demonstrates it four ways instead of asserting it.

## 1. Diagnosis demonstrated
`test-collector-sees-registered-lane.sh` builds a throwaway state base with two repos (`board`,
`persona-engine`), registers a live lane only in `persona-engine/active.yaml`, sets ambient
`LEADV2_LANES_ALL_REPOS=0`, then runs the real collector against `board`. The lane survives into
the snapshot's `lanes.table` — proving the pin, not the ambient env, is what makes a foreign lane
visible.

## 2. Suite integrity
`test-pulse-empty-board.sh` is unchanged at 553 lines (round 1's 553→75 cut was never committed;
`b63662a` restored it intact). All 10 of its cases pass, including its own RED-falsification runs
of the unrelated empty-board beat/epoch logic it locks down.

## 3. Mutation control (production file, not a scratch copy)
Removed the `LEADV2_LANES_ALL_REPOS=1 \` line from `leadv2-status-collector.sh` in place:
`test-collector-sees-registered-lane.sh` went RED (`[TEST] FAIL: registered lane missing from
collector snapshot`, exit 1). Restored the line; `git diff` against the restored file is empty and
the suite is GREEN again (exit 0). `test-pulse-empty-board.sh` correctly stayed green through the
mutation — it locks a different mechanism (the empty-board beat/epoch rule), not repo-scope.

## 4. Live proof
Ran the real collector against the live `~/Projects/leadv2` project root (`--out /tmp/...`, no
writes into the live repo's own state files): the snapshot's `lanes.table` came back with 20 real
rows, including this very task (`dispatch-42bad5a1`). Then ran `leadv2-broad-status.sh` against the
same live root with all output paths redirected to `/tmp/live-board-proof/` (snapshot, prev,
founder-status, founder-status-full) so no production state was touched: the rendered
`founder-status.md` shows a two-row lane table —
`dispatch-42bad5a1 | round 2 | пишет сейчас (284434 байт в потоке)` and
`dispatch-2bd0e1af | round 2: the ranked models are dead upstream | пишет сейчас (276867 байт в потоке)`
— not `ДОСКА ПУСТА`. (persona-engine's own `active.yaml` currently has zero registered lanes, so
the cross-repo case could not be exercised live against that specific repo pair today; the
mutation-proven fixture in item 1 covers that exact scenario deterministically.)

## 5. `--scope changed` selection from a dirty tree
Added a one-paragraph WHY comment to both `leadv2-status-collector.sh` (at the
`LEADV2_LANES_ALL_REPOS=1` pin) and `leadv2-broad-status.sh` (at `COLLECTOR_SH=`), so both files
are genuinely dirty against HEAD, matching the real-world case (a lane's control plane always has
~20 unrelated files dirty). Extracted `tests/run-all.sh`'s selection logic (lines 1–156, before the
execute loop) and ran it standalone with `--scope changed`: it selected both
`test-pulse-empty-board.sh` (via the `leadv2-broad-status.sh` EXTRA_SUITE_MAP row) and
`test-collector-sees-registered-lane.sh` (via the `leadv2-status-collector.sh` row). Ran both
suites directly (not through the full `run-all.sh`, which was blocked behind
`/tmp/leadv2-core-offline.lock` held by several other concurrently-running lanes' test runs on this
machine) — both green, exit 0.

## Falsification set
- `bash -n` on all 5 touched/read shell files: all OK.
- `test-pulse-empty-board.sh`: 10 passed, 0 failed.
- `test-collector-sees-registered-lane.sh`: 1 passed, 0 failed.
- Mutation: RED with the fix line removed, GREEN restored, byte-identical to original.

## Left alone
`leadv2-dispatch-code.sh`'s `lane_state_register` `NoneType` TypeError — out of scope per mission
(belongs to `DISPATCH-LANE-INFRA-3PACK-01`, not in this lane's write set).
