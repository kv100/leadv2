# Writer census — active.yaml (D1-SINGLE-WRITER-FOR-LANE-STATE)

Enumerated by grepping the tree (2026-09-06, worktree @ 3631cfba), not from the
brief. The live registry is `~/.claude/leadv2-state/<repo>/active.yaml`,
resolved by `leadv2-state-path.sh` (both op engines honor
`LEADV2_STATE_PATH_BIN`). One file, one `sessions:` list, TWO op engines plus
THREE inline python writers, and a fifth function-name collision writing a
different file entirely.

## Op engines (mutating code paths)

| # | Path | Mechanism | Ops |
|---|------|-----------|-----|
| W1 | `plugins/leadv2/scripts/leadv2-active-registry.sh` | `_leadv2_yaml_py_lock` | register, unregister, update_phase, update_pulse, update_pid, mark_stale, mark_finished, heartbeat, set_worktree/log_path/writes/attempt/worker_pid, append_provider_receipt, render_index, read, check_writes |
| W2 | `plugins/leadv2/scripts/lib/leadv2-lane-state.sh` | `_lv2_lane_state_mutate` | register (lane cap, worker pid, lead lineage), transition, deregister (tombstone `dead_at`, row KEPT), reconcile (recovered / recovered_unowned / reconciled_dead), count, alive, lead_alive |
| W3 | `plugins/leadv2/scripts/leadv2-helpers.sh:1476-1558` | `_leadv2_active_py_lock` | DUPLICATE public names `leadv2_active_register/update_phase/unregister/list` writing a DIFFERENT FILE: `$LEADV2_PROJECT_ROOT/docs/leadv2/active.md` (repo-relative, md format). Whichever of helpers/registry is sourced LAST wins the name — source order decides whether a registration is visible at all. Reader: `hooks/leadv2-auto-status.sh:189`. helpers:663 `legacy_lock_acquire` calls the name too. |
| W4 | `leadv2-fanout.sh` `_fanout_register_session` (~:1000-1130) | inline python, own lock fd | append row w/ own shape: window_title, provider_receipts, lead_model/effort, first_seen_at, pid_pending + admission checks |
| W5 | `leadv2-fanout-lane-launcher.sh:137` | VERBATIM copy of W4 | comment: "keep the two copies in sync" — hand-synced duplicate body |
| W6 | `leadv2-backlog-pump.sh:662` `_pump_reserve_lane` / `_pump_update_lane_pid` | direct W1 register op (pid=null, class=backlog-pump, sid `p-…`) / update_pid op | bypasses the public fn because it "has no null-pid mode" |
| W7 | `leadv2-dispatch-code.sh:4997` `_release_registered_lane` | inline python | owner-verified compare-and-delete under flock |
| W8 | `leadv2-lanes-snapshot.sh:1081,:1335` | inline python | tmux adopt (append `origin: adopted` rows), tombstone+prune (remove dead rows), abandon (escalation answer → tombstone+prune). Header line 20 claims "does not write" — it does. |
| W9 | `leadv2-stale-sweeper.sh:216` | direct W1 `mark_stale` op | |

## Call-site matrix (lifecycle event → writer)

- **register** (dispatch lane): dispatch-code:7694 (W1 fn) AND :7736 (`lane_register`
  W2 — the same row is registered back-to-back by two engines); gate1-prompt:68;
  fork-session:209; provider-canary:273/274; pump W6; fanout W4/W5.
  (lane worker adoption: `lane_adopt_pid` W2 ← session-runner:204,
  codex-session-runner:108, dispatch:6164/:6295.)
- **phase advance**: W1 `update_phase` ← dispatch-code:701, phase-record:993,
  dispatch-product-close:334; W2 `lane_transition` ← adopt_pid only; snapshot
  calls repo override `.claude/scripts/leadv2-phase-backfill.sh` (absent in leadv2).
- **finished**: W1 `mark_finished` ← lane-heartbeat:111 (sole caller — already single).
- **release**: W1 `unregister` (REMOVES row) ← phase8-close:748, fanout:1743/1785/1986+,
  fanout-lane-launcher x6, pump; W2 `lane_deregister` (TOMBSTONES, row kept,
  phase frozen) ← dispatch:3707 trap, product-close:3785, session-runner:205 /
  codex-runner:109 EXIT traps; W7 inline release ← dispatch-code.
  Two release semantics on one file = the rc=4 "task not registered" cross-talk.
- **recovered / recovered_unowned**: W2 `lane_reconcile` ONLY ← dispatch-code:7336,
  hooks/leadv2-stale-pid-sweep.sh:13. TTL (`LEADV2_RECOVERED_UNOWNED_TTL_SEC`=900s)
  marks `dead_at`+`recovered_unowned_expired` — but NOTHING ever removes the row:
  24 such rows live today (78 string hits), all dead_at'd 2026-09-04, i.e. expired
  rows accumulating forever. Ghost pulses render exactly these rows.
- **pulse/heartbeat**: heartbeat op ← lane-heartbeat:79/:256. `update_pulse` has NO
  production caller (dead op, only a test calls it).
- **journal address** (`pulse_log`/`log_path`): register op stamps default
  `docs/leadv2/tasks/<id>/pulse.md`; fanout/launcher `log_path_override`;
  `set_log_path` ← dispatch:7757 (stream.jsonl); heartbeat writes pulse.json
  (artifact, not a registry field).

## Consequences measured live (2026-09-06)

- 24 rows `phase=recovered_unowned`, `session_id: recovered`, dead_at set — unowned,
  expired, never removed.
- Row `RECOVERY-ATTACHES…` carries BOTH engines' fields (`registered_refresh` lane
  event + registry `writes`/`log_path`) — proof both engines mutate one row.
- dispatch double-registers each lane (W1 then W2 within ~40 lines).
- Merged lane shows `phase=build` for hours: W2 tombstone keeps the row+phase; W1
  unregister may have already removed a row W2 still expects (rc=4), or never ran.

## Hazards beyond duplication

- Sourcing `leadv2-active-registry.sh` sets `set -euo pipefail` in the CALLER
  (line ~57); `leadv2-helpers.sh:10` does the same. Band-aids already exist:
  backlog-pump:170 `set +e` right after sourcing, fanout:321 `set +e`.
- `update_phase` op silently no-ops when the row is missing (dispatch:7631 comment
  depends on register-before-update ordering), and patches DEAD rows (frozen-phase
  ghost rendering).
