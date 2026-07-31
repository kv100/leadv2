#!/usr/bin/env bash
# leadv2-supervise-watchdog.sh — out-of-loop watchdog (SUPERVISOR-HARDENING-01
# items 2+3). A loop-side self-check is structurally unable to detect its own
# death, so the silence alarm + self-heal live OUTSIDE the watched process.
# Cron-owned (item 3): one crontab entry installed by leadv2-supervise-loop.sh
# --ensure runs this every 10 min. It both ALARMS on loop silence AND calls
# --ensure to self-heal, so one entry covers failure classes 1 (silent loop)
# and 2 (dead loop, beat dies with it).
#
# Silence threshold = 2 × LEADV2_SUPERVISE_PULSE_S (default 300 → 600s). If
# now - mtime(heartbeat) > threshold, OR the heartbeat exists but its pid is
# dead → append ONE [SUPERVISE-URGENT] LOOP_SILENT line to the loop log THROUGH
# the item-5 dedupe (key loop_silent, value = a staleness bucket so the line
# fires once per bucket, not every 10-min poll), then run --ensure.
#
# --ensure is only invoked when SILENT=1 (proven dead/stale), never on a
# healthy loop — a watchdog firing while the loop is merely slow now does
# nothing but sweep the alarm state. (Before SESSION-CLOSE-FIXES-01 fix 1A/1B
# --ensure could not recognise a live loop, so an unconditional call re-spawned
# a sibling 6x/hour; the gate below closes that.)
#
# Env (test sandboxing): LEADV2_SUPERVISE_PULSE_S, LEADV2_PROJECT_ROOT /
# CLAUDE_PROJECT_DIR / PROJECT_ROOT, LEADV2_STATE_ROOT, LEADV2_SUPERVISE_BEAT_CRON.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT=""
for _v in LEADV2_PROJECT_ROOT CLAUDE_PROJECT_DIR PROJECT_ROOT; do
  if [[ -n "${!_v:-}" ]]; then PROJECT_ROOT="${!_v}"; break; fi
done
# --project-root arg wins over env.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$PROJECT_ROOT" ]] || exit 0
export PROJECT_ROOT

STATE_PATH_SH="${SCRIPT_DIR}/leadv2-state-path.sh"
SUPERVISE_LOOP_SH="${SCRIPT_DIR}/leadv2-supervise-loop.sh"
[[ -x "$STATE_PATH_SH" ]] || exit 0

HEARTBEAT_FILE="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" .supervise-loop.heartbeat 2>/dev/null || true)"
LOG_FILE="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" supervise-loop.log 2>/dev/null || true)"
[[ -n "$HEARTBEAT_FILE" && -n "$LOG_FILE" ]] || exit 0

PULSE_S="${LEADV2_SUPERVISE_PULSE_S:-300}"
THRESHOLD=$(( PULSE_S * 2 ))
[[ "$THRESHOLD" -gt 0 ]] || THRESHOLD=600

_now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# Decide whether the loop is silent, without spawning python unless needed.
SILENT=0
BUCKET="none"
_hb_pid="?"; _hb_age=0
if [[ ! -f "$HEARTBEAT_FILE" ]]; then
  # No heartbeat at all yet — only treat as silent if a loop log exists (i.e.
  # supervision was started) but is stale. A never-started loop is not silent.
  if [[ -f "$LOG_FILE" ]]; then
    SILENT=1; BUCKET="no_heartbeat"
  fi
else
  # One python process: <pid> <age_s> <alive|dead>.
  read -r _hb_pid _hb_age _hb_alive < <(python3 -c '
import sys, os, json, time
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        d = json.load(fh) or {}
    pid = d.get("pid")
    alive = False
    if pid is not None:
        try:
            os.kill(int(pid), 0); alive = True
        except Exception:
            alive = False
    age = int(time.time() - os.path.getmtime(sys.argv[1]))
    print(int(pid) if pid is not None else 0, age, "alive" if alive else "dead")
except Exception:
    print(0, 0, "dead")
' "$HEARTBEAT_FILE" 2>/dev/null)
  if [[ "${_hb_alive:-}" == "dead" ]]; then
    SILENT=1; BUCKET="pid_dead:${_hb_pid}"
  elif [[ "${_hb_age:-0}" -gt "$THRESHOLD" ]]; then
    # Bucket (the dedupe VALUE) is the constant "stale" — NOT the live age,
    # which would change every poll and defeat the transition dedupe. The age
    # is kept in the rendered line for diagnosis.
    SILENT=1; BUCKET="stale"
  fi
fi

# Route through the item-5 dedupe (transition on bucket). The lib lives next
# to this script; fall back to a plain append if it is unavailable.
if [[ -f "${SCRIPT_DIR}/lib/leadv2-alarm-dedupe.sh" ]]; then
  # shellcheck source=lib/leadv2-alarm-dedupe.sh
  source "${SCRIPT_DIR}/lib/leadv2-alarm-dedupe.sh"
  # Cycle token unique per invocation: $$ differs every run (each watchdog is
  # a fresh process), so back-to-back invocations never share a cycle even
  # within the same epoch second.
  cyc="$$-$(date +%s)"
  if [[ "$SILENT" == "1" ]]; then
    LINE="$(_now_iso) [SUPERVISE-URGENT] LOOP_SILENT pid=${_hb_pid:-?} silent=${_hb_age:-?}s bucket=${BUCKET}"
    printf 'loop_silent\t%s\t%s\n' "$BUCKET" "${LINE:0:220}" \
      | leadv2_alarm_filter_seen loop_silent "$cyc" >>"$LOG_FILE"
  fi
  # ALWAYS sweep: a recovered loop (not silent) must CLEAR the loop_silent key
  # so the NEXT silence re-fires. Sweeping is a no-op when the key was seen
  # this cycle (silent) and only acts on absent-but-previously-recorded keys.
  leadv2_alarm_sweep loop_silent "$cyc"
elif [[ "$SILENT" == "1" ]]; then
  LINE="$(_now_iso) [SUPERVISE-URGENT] LOOP_SILENT pid=${_hb_pid:-?} silent=${_hb_age:-?}s bucket=${BUCKET}"
  printf '%s\n' "${LINE:0:220}" >>"$LOG_FILE"
fi

# Self-heal ONLY when the loop is proven dead/silent (SILENT=1). When the loop
# is healthy (SILENT=0) there is nothing to heal — this predicate (pid dead, or
# hb age > threshold, or hb absent while a log exists) is exactly the same
# definition supervise-loop.sh --ensure adopts on, so calling --ensure on a
# healthy loop every 10 min would be pointless and, before fix 1A/1B, spawned a
# sibling 6x/hour. Gate here too so a stale --ensure path can never reintroduce
# it. After a real respawn the new pid is written by the loop's own flock'd
# sentinel claim (FOREIGN/NEW in supervise-loop.sh) — no extra writer here.
# Keep the LEADV2_SUPERVISE_BEAT_CRON kill-switch.
if [[ "$SILENT" == "1" && "${LEADV2_SUPERVISE_BEAT_CRON:-1}" == "1" && -x "$SUPERVISE_LOOP_SH" ]]; then
  LEADV2_PROJECT_ROOT="$PROJECT_ROOT" bash "$SUPERVISE_LOOP_SH" --ensure >/dev/null 2>&1 || true
fi
exit 0
