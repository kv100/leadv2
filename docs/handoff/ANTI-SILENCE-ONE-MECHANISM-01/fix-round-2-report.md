# ANTI-SILENCE-ONE-MECHANISM-01 round 2 — completion report (lane ANTI-SILENCE-BEAT-ABORT-04, 2026-08-31)

## Root cause (proven from the runtime, not by reading)

The abort block at `leadv2-broad-status.sh:1292-1301` was correct and never ran.
`plugins/leadv2/scripts/leadv2-active-registry.sh:45` declares its own standalone policy
`set -euo pipefail`; `leadv2-broad-status.sh` sources that file on its main path
(`:69`, `2>/dev/null || true`). `|| true` guards the source command's exit status, not the
shell option it leaves ON in the sourcing shell. With errexit active, the failed command
substitution `RENDER_JSON="$(python3 render.py ...)"` (`:1301` on the rebased tree) killed the
script before `RC=$?` — no render-failure log, no degraded artifact, no ready line, exit 1.
Total silence. bash `xtrace` showed the shell terminating exactly at that assignment.

Runtime proof (collector that writes non-JSON, fixture tree):

- default (registry sourced): `REAL_EXIT=1`, no `supervise-loop.log` anywhere, no artifact.
- `LEADV2_ACTIVE_REGISTRY_BIN=/nonexistent-registry` (source skipped, no errexit leak):
  `REAL_EXIT=0`, log carries `render failure: table unavailable` + `BROAD_STATUS_READY at=...
  degraded=1`, artifact line-1 stamp == `at=`.

## Fix (plugins/leadv2/scripts/leadv2-broad-status.sh, 2 edits)

1. `set +e` immediately after the active-registry source block — re-asserts the script's own
   policy from `:22` (`set -uo pipefail`, no `-e`), with a comment carrying the incident.
2. The render-failure log line (`:1304`) now stamps `$BEAT_AT` instead of `$(_now_iso)` —
   round 1 unified the artifact's line-1 clock; this log line was still on the other clock.

Every abort path now ends in either a degraded artifact + ready line (collector garbage,
missing snapshot, render traceback) or a FAILED line with no `path=` token (unwritable
artifact) — all four covered by the suite.

## Evidence

- Before the fix, on the rebased branch (main's `cat > render.py` heredoc path):
  `test-beat-stamp-agreement: 5 passed, 1 failed / FAIL: T3a: stamp mismatch: at= line1=`.
- After: `6 passed, 0 failed`, suite exit 0.
- Mutation (inside `_write_degraded_status`, real call path — artifact write removed):
  suite RED, exit 1 (T2/T3a/T4/T5 fail). Reverted -> GREEN. Clean `git diff --stat` afterwards.
- Round-1 control held: `lane_facts="$(_live_lane_facts)"` -> `""` makes the suite RED
  (4 passed, 2 failed, exit 1); restored -> GREEN.
- `bash -n` clean on both changed executable files (no Python files changed in this round).
- `tests/run-all.sh --scope changed`: hit its own `timeout 1800` mid-flight (exit 124, runner
  needs >30 min here) — partial. Relevant suites: `test-beat-stamp-agreement` 6/6 exit 0;
  `test-broad-status-duty.sh` fails 10 — verified PRE-EXISTING: the same suite run against
  HEAD's (unfixed) `leadv2-broad-status.sh` fails the same T4b-T4f/T7/T8b live-loop cluster
  (wall-clock waits), exit 1 both. LANE-PLACEMENT-01 and C5-registered-arm-silent failures in
  the log match the documented baseline reds. Remaining failures (LANDED-AT-SPAWN-01,
  product-close reroute wiring, shellcheck on leadv2-review-run.sh, CORE-OFFLINE batches)
  exercise files this lane did not touch.

## Not reintroduced

The heredoc-in-command-substitution form stays gone; render runs main's
`cat >"$RENDER_TMPDIR/render.py"` path. Bash 3.2 compatible (`set +e` is POSIX; no `mapfile`).
