#!/usr/bin/env bash
# leadv2-burn-governor.sh — BURN-GOVERNOR-01: 24h local token-burn verdict.
#
# Single-purpose: read ${LEADV2_CLAUDE_BURN_DIR:-$HOME/.claude/burn}/history.db
# (table `hourly`, hour_key format 'YYYY-MM-DD-HH' UTC — NOT the ISO 'T' form;
# see architect prepass §0.1, GLM_FIRST_EXCEPTION dispatch-b22dc98b) and print
# ONE verdict line. ALWAYS exits 0 — this script must never be able to fail a
# caller; fail-open on every telemetry error (missing sqlite3, missing db,
# missing table, locked db, non-numeric query result) collapses to
# reason=no_telemetry, verdict=ok.
#
# Usage: leadv2-burn-governor.sh [verdict]   (verdict is also the default)
# Output (stdout, one line):
#   verdict=<ok|soft|hard> burn24h=<int> soft=<int> hard=<int> reason=<token>
#
# Env:
#   LEADV2_BURN_GOVERNOR    default 1 (0 disables: verdict=ok reason=disabled)
#   LEADV2_BURN_SOFT_24H    default 800000000
#   LEADV2_BURN_HARD_24H    default 1300000000
#   LEADV2_CLAUDE_BURN_DIR  default $HOME/.claude/burn

set -uo pipefail

_LBG_DEFAULT_SOFT=800000000
_LBG_DEFAULT_HARD=1300000000

# $1=soft_raw $2=hard_raw — prints "soft\nhard\nbad_config(0|1)". Never uses
# bash `(( ))` on these values (D6): an operator-supplied 21-digit env would
# overflow bash 3.2 integer arithmetic and could make the comparison wrap
# negative, silently turning a misconfiguration into a global dispatch
# refusal. python's arbitrary-precision ints make that impossible.
_lbg_resolve_thresholds() {
  python3 -c '
import sys
soft_raw, hard_raw, def_soft, def_hard = sys.argv[1:5]
def is_num(x):
    return x.isdigit()
bad = 0
if is_num(soft_raw) and is_num(hard_raw) and int(hard_raw) > int(soft_raw):
    soft, hard = soft_raw, hard_raw
else:
    soft, hard = def_soft, def_hard
    bad = 1
print(soft)
print(hard)
print(bad)
' "$1" "$2" "$3" "$4" 2>/dev/null
}

# $1=burn24h $2=soft $3=hard — prints "verdict\nreason". Same overflow
# avoidance as above; burn24h is a live SUM and soft/hard are already
# validated numerics here, but the comparison stays in python for one code
# path rather than splitting the risk across two.
_lbg_classify() {
  python3 -c '
import sys
burn, soft, hard = (int(x) for x in sys.argv[1:4])
if burn >= hard:
    print("hard"); print("over_hard")
elif burn >= soft:
    print("soft"); print("over_soft")
else:
    print("ok"); print("under_soft")
' "$1" "$2" "$3" 2>/dev/null
}

cmd_verdict() {
  local governor_on="${LEADV2_BURN_GOVERNOR:-1}"
  if [[ "${governor_on}" == "0" ]]; then
    printf 'verdict=ok burn24h=0 soft=%s hard=%s reason=disabled\n' \
      "${LEADV2_BURN_SOFT_24H:-${_LBG_DEFAULT_SOFT}}" "${LEADV2_BURN_HARD_24H:-${_LBG_DEFAULT_HARD}}"
    return 0
  fi

  local soft hard bad_config
  { read -r soft; read -r hard; read -r bad_config; } < <(
    _lbg_resolve_thresholds \
      "${LEADV2_BURN_SOFT_24H:-${_LBG_DEFAULT_SOFT}}" "${LEADV2_BURN_HARD_24H:-${_LBG_DEFAULT_HARD}}" \
      "${_LBG_DEFAULT_SOFT}" "${_LBG_DEFAULT_HARD}"
  )
  if [[ -z "${soft:-}" || -z "${hard:-}" ]]; then
    # the python resolver itself failed (no python3?) — fall back to hardcoded
    # defaults so a broken interpreter cannot brick dispatch either.
    soft="${_LBG_DEFAULT_SOFT}"; hard="${_LBG_DEFAULT_HARD}"; bad_config=1
  fi

  local reason_suffix=""
  [[ "${bad_config:-0}" == "1" ]] && reason_suffix="+bad_config"

  local burn_dir db
  burn_dir="${LEADV2_CLAUDE_BURN_DIR:-${HOME}/.claude/burn}"
  db="${burn_dir}/history.db"

  if ! command -v sqlite3 >/dev/null 2>&1 || [[ ! -r "${db}" ]]; then
    printf 'verdict=ok burn24h=0 soft=%s hard=%s reason=no_telemetry%s\n' "${soft}" "${hard}" "${reason_suffix}"
    return 0
  fi

  # D1: cutoff computed INSIDE sqlite as strftime('%Y-%m-%d-%H', ...) — the
  # table's real hour_key separator is '-', not the ISO 'T' the original
  # mission text specified. Verified live: `sqlite3 history.db ".schema hourly"`
  # / a same-instant side-by-side query, both in the architect prepass §0.1.
  # D7: COALESCE each column before summing — the schema has DEFAULT 0 but not
  # NOT NULL, so an outer-only COALESCE would let one NULL column zero a whole
  # hour's contribution.
  # -cmd '.timeout 2000': the collector writes this db continuously (observed
  # live: a plain SELECT hit "database is locked (5)" with no fixture). The
  # dot-command form is used (not `PRAGMA busy_timeout=2000`, a SQL statement
  # that returns a row and pollutes stdout with an extra "2000" line ahead of
  # the real result — verified live). -readonly is NOT used — it fails
  # outright on this db (WAL mode needs to create/attach -shm/-wal, verified
  # live) — and this statement is a SELECT that writes nothing regardless.
  local burn24h
  burn24h="$(sqlite3 -cmd '.timeout 2000' "${db}" "
SELECT COALESCE(SUM(
  COALESCE(cc_sum,0)+COALESCE(cr_sum,0)+COALESCE(input_sum,0)+COALESCE(output_sum,0)
),0)
FROM hourly
WHERE hour_key >= strftime('%Y-%m-%d-%H','now','-24 hours');
" 2>/dev/null)"

  if [[ -z "${burn24h:-}" ]] || ! [[ "${burn24h}" =~ ^[0-9]+$ ]]; then
    printf 'verdict=ok burn24h=0 soft=%s hard=%s reason=no_telemetry%s\n' "${soft}" "${hard}" "${reason_suffix}"
    return 0
  fi

  local verdict reason
  { read -r verdict; read -r reason; } < <(_lbg_classify "${burn24h}" "${soft}" "${hard}")
  if [[ -z "${verdict:-}" ]]; then
    # classify failed (python3 died mid-run) — fail open, never block on a
    # telemetry-adjacent tooling error.
    printf 'verdict=ok burn24h=0 soft=%s hard=%s reason=no_telemetry%s\n' "${soft}" "${hard}" "${reason_suffix}"
    return 0
  fi

  printf 'verdict=%s burn24h=%s soft=%s hard=%s reason=%s%s\n' \
    "${verdict}" "${burn24h}" "${soft}" "${hard}" "${reason}" "${reason_suffix}"
  return 0
}

case "${1:-verdict}" in
  verdict) cmd_verdict ;;
  *)       cmd_verdict ;;
esac
exit 0
