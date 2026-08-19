#!/usr/bin/env bash
# scripts/leadv2-beat-owner.sh — BROAD-STATUS-RELAY-SCOPE-01 (round 2)
#
# Resolves whether THIS hook-invoking session owns the current BROAD_STATUS
# beat, so leadv2-single-lead-beat.sh can inject the full relay only into the
# owner and a single one-line pointer into every other live session.
#
# Sourced (not exec'd) by the hook. Public entry point:
#   leadv2_beat_role <safe_sid> <state_dir> [beat_s]
# prints exactly one of: owner | guest | unresolved   (rc is ALWAYS 0 — this
# is a fail-open resolver; the caller treats "unresolved" as "relay in full",
# same as today's un-scoped behaviour, so a bug here never silently drops the
# beat for everyone).
#
# Ladder (first match wins, round 2 — ROUND-2 fixes HIGH-1/HIGH-2 from the
# round-1 review: an epoch alone cannot prove the owner is alive, and a race
# winner alone cannot prove it is actually dispatching anything):
#   0. LEADV2_BEAT_RELAY_SCOPE=0 (kill-switch)                         -> unresolved
#   1. LEADV2_BEAT_OWNER_OVERRIDE set (test seam)                      -> owner/guest
#   2. .pulse-beat-owner missing/unparseable/epoch >= 1x beat_s old    -> unresolved
#   3. owner's .pulse-session.<sid> missing/>=1x beat_s old (HIGH-1)   -> unresolved
#   4. owner session has 0 live lanes attributed to it (HIGH-2)        -> unresolved
#   5. owner sid == my safe_sid                                       -> owner
#   6. otherwise                                                       -> guest
#
# The `.supervise-active` + ancestry rows from round 1 are DELETED here
# (D3, round-2 architect design): the supervisor is retired, and lanes
# detach via setsid+disown, which makes process ancestry structurally
# incapable of linking a lane pid back to the dispatching session. Keeping
# them would be dead code with a test that proves nothing; T18 in the suite
# pins that a live `.supervise-active` pid is inert going forward.
#
# Never `set -e` in here — every internal helper must be able to fail
# harmlessly into the fail-open "unresolved" branch.
set -uo pipefail

_lv2_beat_owner_fresh() {
  # <state_dir> <beat_s> -> rc0 if .pulse-beat-owner exists and its stamped
  # epoch is within EXACTLY beat_s (round 2: no 2x multiplier, no 3600 floor
  # — those masked a dead owner for up to an hour, HIGH-1); prints its
  # safe_sid on stdout. A 3rd+ field on the line is tolerated and ignored
  # (LOW-1: `read -r sid epoch _` can never be corrupted by trailing junk).
  local state_dir="$1" beat_s="$2" f line sid epoch now max_age
  f="${state_dir}/.pulse-beat-owner"
  [[ -f "$f" ]] || return 1
  line="$(cat "$f" 2>/dev/null || true)"
  read -r sid epoch _ <<<"$line" || true
  [[ -n "$sid" && "$epoch" =~ ^[0-9]+$ ]] || return 1
  [[ "$beat_s" =~ ^[0-9]+$ ]] || beat_s=1800
  max_age="$beat_s"
  now="$(date +%s 2>/dev/null || echo 0)"
  [[ "$now" =~ ^[0-9]+$ ]] || return 1
  (( now - epoch < max_age )) || return 1
  printf -- '%s' "$sid"
  return 0
}

_lv2_session_alive() {
  # <state_dir> <safe_sid> <beat_s> -> rc0 iff
  # ${state_dir}/.pulse-session.<safe_sid> exists, parses as a decimal epoch,
  # and now - epoch < beat_s (strict, no floor, no multiplier). This is
  # HIGH-1's fix: an owner-file epoch alone cannot prove the NAMED session is
  # still alive — the mandated cache-copy restart mints a brand new
  # session_id, so a fresh owner file can name a session that no longer
  # exists (reviewer Scenario E). This is the liveness cross-check.
  local state_dir="$1" safe_sid="$2" beat_s="$3" f epoch now
  [[ -n "$safe_sid" ]] || return 1
  f="${state_dir}/.pulse-session.${safe_sid}"
  [[ -f "$f" ]] || return 1
  epoch="$(cat "$f" 2>/dev/null || true)"
  [[ "$epoch" =~ ^[0-9]+$ ]] || return 1
  [[ "$beat_s" =~ ^[0-9]+$ ]] || beat_s=1800
  now="$(date +%s 2>/dev/null || echo 0)"
  [[ "$now" =~ ^[0-9]+$ ]] || return 1
  (( now - epoch < beat_s )) || return 1
  return 0
}

# leadv2_session_has_live_lane <safe_sid> <state_dir> <project_root>
# rc0 iff >=1 lane is live (leadv2-lane-heartbeat.sh status --all --json
# verdict == "running", the ONLY verdict that means "I know this is alive
# right now" — running_stale is an honest "don't know" and must not confer
# ownership) AND that lane's arm-registered file carries a LEAD_SESSION=
# field matching <safe_sid>. rc1 on "no live lane", "no attribution
# possible" (pre-upgrade lane, or CLAUDE_SESSION_ID unset at dispatch), or
# any internal failure. Never prints. Fail-open by construction: HIGH-2's
# read side is authoritative, so any parse/exec failure here must be
# treated as "not qualified" (rc1), not "qualified" — a bad write must never
# be able to grant ownership through a resolver bug.
#
# Bounded: at most one `leadv2-lane-heartbeat.sh status --all --json` call
# (itself a single python3 pass over active.yaml) plus at most 12
# arm-registered file reads — this runs on EVERY hook fire once a fresh,
# alive owner is on record, so it must stay cheap.
leadv2_session_has_live_lane() {
  local safe_sid="$1" state_dir="$2" project_root="$3"
  [[ -n "$safe_sid" ]] || return 1
  local self_dir hb_sh
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || return 1
  hb_sh="${self_dir}/leadv2-lane-heartbeat.sh"
  [[ -x "$hb_sh" ]] || return 1
  local json
  json="$( (LEADV2_PROJECT_ROOT="$project_root" bash "$hb_sh" status --all --json 2>/dev/null || true) )"
  [[ -n "$json" ]] || return 1
  python3 -c "
import sys, json, os

safe_sid = sys.argv[1]
project_root = sys.argv[2]

def sanitize(s):
    out = []
    for ch in s:
        out.append(ch if (ch.isalnum() or ch in '._-') else '_')
    return ''.join(out)[:64]

try:
    rows = json.loads(sys.argv[3])
except Exception:
    sys.exit(1)
if not isinstance(rows, list):
    sys.exit(1)

checked = 0
for row in rows:
    if not isinstance(row, dict):
        continue
    if row.get('status') != 'running':
        continue
    task_id = row.get('task_id')
    if not task_id:
        continue
    checked += 1
    if checked > 12:
        break
    f = os.path.join(project_root, 'docs', 'handoff', str(task_id), 'arm-registered')
    try:
        with open(f, encoding='utf-8', errors='ignore') as fh:
            body = fh.read()
    except Exception:
        continue
    for line in body.splitlines():
        for tok in line.split():
            if tok.startswith('LEAD_SESSION='):
                if sanitize(tok[len('LEAD_SESSION='):]) == safe_sid:
                    print('match')
                    sys.exit(0)
sys.exit(1)
" "$safe_sid" "$project_root" "$json" 2>/dev/null | grep -q '^match$'
}

leadv2_beat_role() {
  # <safe_sid> <state_dir> [beat_s] -> prints owner|guest|unresolved, rc0.
  local safe_sid="${1:-}" state_dir="${2:-}" beat_s="${3:-1800}"

  # 0. kill-switch
  if [[ "${LEADV2_BEAT_RELAY_SCOPE:-1}" == "0" ]]; then
    printf -- 'unresolved\n'
    return 0
  fi

  # 1. test seam
  if [[ -n "${LEADV2_BEAT_OWNER_OVERRIDE:-}" ]]; then
    if [[ -n "$safe_sid" && "${LEADV2_BEAT_OWNER_OVERRIDE}" == "$safe_sid" ]]; then
      printf -- 'owner\n'
    else
      printf -- 'guest\n'
    fi
    return 0
  fi

  [[ -n "$state_dir" ]] || { printf -- 'unresolved\n'; return 0; }

  # 2. fresh .pulse-beat-owner
  local owner_sid
  owner_sid="$(_lv2_beat_owner_fresh "$state_dir" "$beat_s" 2>/dev/null || true)"
  [[ -n "$owner_sid" ]] || { printf -- 'unresolved\n'; return 0; }

  # 3. owner session alive (HIGH-1)
  if ! _lv2_session_alive "$state_dir" "$owner_sid" "$beat_s" 2>/dev/null; then
    printf -- 'unresolved\n'
    return 0
  fi

  # 4. owner session has >=1 live lane attributed to it (HIGH-2). project_root
  # comes from LEADV2_PROJECT_ROOT (the caller must export it before invoking
  # leadv2_beat_role); absent -> leadv2_session_has_live_lane fails closed to
  # rc1, which the ladder below already treats as unresolved (fail-open).
  if ! leadv2_session_has_live_lane "$owner_sid" "$state_dir" "${LEADV2_PROJECT_ROOT:-}" 2>/dev/null; then
    printf -- 'unresolved\n'
    return 0
  fi

  # 5/6.
  if [[ -n "$safe_sid" && "$owner_sid" == "$safe_sid" ]]; then
    printf -- 'owner\n'
  else
    printf -- 'guest\n'
  fi
  return 0
}
