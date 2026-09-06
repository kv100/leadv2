# D2-M4 (1/17) — hooks/leadv2-active-cache.sh

Part of D2-M3-M6-REMAINDER-01's M4 step (convert the 18 lane-registry PID
readers with no liveness call). This is conversion 1 of 18 (17 genuine
conversions after `leadv2-pulse-beat.sh` was reclassified — see below).

## Reclassification: leadv2-pulse-beat.sh is a self-probe, not a conversion

Before starting, re-ran the brief's own classifier
(`grep -q "worker_pid\|pid_role\|active\.yaml\|\bsessions\b"`) against all 18
named files. 17 classify `LANE` (genuine lane-registry PID readers). One --
`leadv2-pulse-beat.sh` -- classifies `OWN`: its only `kill`/`ps` usage
(`os.kill(int(pid), 0)` in `_loop_is_live()`) checks a specific KNOWN
sentinel-recorded pid (the supervise loop's own pid, from
`.supervise-loop.json`), never a lane's. Its actual lane-count logic
(`_lv2_current_live_count`) already delegates to
`leadv2-lane-heartbeat.sh status --all --json` and never appears in the
census's own `kill -0|os\.kill(|ps aux|pgrep|ps -p |ps -o ` grep -- it
wasn't why this file was flagged. Per the brief's own instruction
("confirm each file's probe target before converting it, and move any that
turn out to be self-probes into the out-of-scope column with a one-line
note"): reclassified out of scope. **The remaining 17 files are the real
M4 list.**

## Change

`hooks/leadv2-active-cache.sh`, `leadv2_read_active_yaml()`: the cache-miss
path decided "is this session's pid alive" with a bare
`os.kill(int(pid), 0)` in Python -- `except (OSError, ValueError)` collapsed
ESRCH (genuinely dead) and EPERM (pid exists, owned by someone else, e.g. a
leadv2 watcher reparented to ppid=1) into the same branch, and a bare
`kill(0)==0` never proves the pid is THIS session's own worker (D2 brief
#9/#14).

Converted to one batched `leadv2-lane-liveness.sh --all --json` call against
the SAME `active.yaml` this function already reads, building a
`task_id -> pid_alive` map from the response (whose `pid_alive` field
already carries the ESRCH/EPERM split and the process-kind check) instead of
a raw per-session `kill(0)` loop. A lane absent from the liveness map (not
covered by `--all`'s enumeration) degrades to the pre-conversion fail-open
behavior (included), never a silent drop.

**Test-hostility fix, incidental:** `LEADV2_STATE_DIR` was a bare assignment
with no env override -- any test exercising this function would have written
directly into the real `~/.claude/state/leadv2/active.cache`. Added
`LEADV2_ACTIVE_CACHE_STATE_DIR` as the override (additive default, identical
value when unset).

## New tests

`test-active-cache-liveness.sh`:
- **C1**: an EPERM pid (1) session is still reported as the active task, not
  dropped.
- **C2**: a genuinely dead (ESRCH, pid 999999) session is still dropped,
  matching pre-conversion behavior.
2/2 pass.

## Mandatory negative control (mutation-control-proven)

Mutated the new liveness-consuming condition
(`if tid not in alive_by_lane or alive_by_lane.get(tid):` → `if False:`),
simulating a revert to strict per-session exclusion that ignores the
liveness map's positive answer. Suite goes RED exactly on C1
(`baseline_rc=0`, `mutated_rc=1`, red_line names C1 by test id). Artifact:
`mutation-control/` (this directory).

## Commit

`ff4e7af8`.

## Remaining M4 (16 more)

`hooks/leadv2-orphan-monitor-sweep.sh`, `hooks/leadv2-task-anchor.sh`,
`hooks/leadv2-worktree-enforce.sh`, `hooks/leadv2-stale-pid-sweep.sh`,
`leadv2-fanout.sh`, `leadv2-fanout-lane-launcher.sh`, `leadv2-helpers.sh`,
`leadv2-lane-heartbeat.sh`, `leadv2-lane-pulse-watch.sh`,
`leadv2-lane-status-line.sh`, `leadv2-merge-queue.sh`,
`leadv2-provider-canary.sh`, `leadv2-status-collector.sh`,
`lib/leadv2-worktree-protected.sh`, `codex-guard.sh`, `leadv2-codex-lead.sh`
(the last two remain "borderline" per the brief -- confirm each is a real
lane-registry reader, not a provider-child self-probe, before converting).
