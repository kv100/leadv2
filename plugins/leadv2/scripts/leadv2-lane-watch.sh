#!/usr/bin/env bash
# leadv2-lane-watch.sh — LANE-OBSERVABILITY-02 change 4: poll-based lane watcher.
#
# Lane journals are written via atomic replace (tmp + mv), so `tail -F` watchers
# silently miss events: -F follows the OLD inode after the swap. This watcher
# POLLS with LINE-COUNT offsets instead — the journal is append-only, so the
# previous content is always a line-prefix of the new file and
# `tail -n +$((seen+1))` is exactly-once and inode-independent. If the current
# line count is LOWER than the stored offset, the file was rotated/truncated —
# reset to 0 and re-read (an in-place mid-file edit is not a shape this journal
# produces; the ledger appends and the writer replaces atomically).
#
# Usage:
#   leadv2-lane-watch.sh [--interval N=60] [--heartbeat N=1800] [--once]
#                        [--state-dir DIR] <journal.md|repo-root> ...
#
#   A repo-root argument expands to <root>/docs/leadv2/tasks/dispatch-*/journal.md.
#   Emits ONLY new lines matching  dispatch_terminal |question|ask-lead|stall
#   (dispatch_terminal with a trailing space so dispatch_terminal_dedup rows —
#   the same event already delivered — never double-fire), printed as
#   `<repo-slug>/<task-id> <line>`. Line-per-printf stdout, usable under a Monitor.
#   Heartbeat: every --heartbeat seconds one `hb <lane> stream_age=<s>s phase=<p>`
#   line per watched lane. Clock injectable via LEADV2_LANE_WATCH_NOW (a literal
#   epoch) or LEADV2_LANE_WATCH_NOW_BIN (a command printing one) so the
#   heartbeat is testable without sleeping.
#   Exit 0 once EVERY watched lane's journal has emitted a `dispatch_terminal task=`
#   line; --once does a single pass and exits regardless.
#
# Read-only w.r.t. journals; the only writes are its own offset files under
#   <state-dir>/lane-watch/<sha1(abspath)>.lines   (state-dir from
#   leadv2-state-path.sh --no-link — never links into a repo — or --state-dir).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INTERVAL=60
HEARTBEAT=1800
ONCE=0
STATE_DIR=""
ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)  INTERVAL="${2:-}"; shift 2 ;;
    --heartbeat) HEARTBEAT="${2:-}"; shift 2 ;;
    --once)      ONCE=1; shift ;;
    --state-dir) STATE_DIR="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --*) printf '[lane-watch] unknown arg: %s\n' "$1" >&2; exit 1 ;;
    *)  ARGS+=("$1"); shift ;;
  esac
done
[[ "${INTERVAL}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { printf '[lane-watch] bad --interval: %s\n' "$INTERVAL" >&2; exit 1; }
[[ "${HEARTBEAT}" =~ ^[0-9]+$ ]] || { printf '[lane-watch] bad --heartbeat: %s\n' "$HEARTBEAT" >&2; exit 1; }
[[ ${#ARGS[@]} -gt 0 ]] || { printf '[lane-watch] no journals or repo roots given\n' >&2; exit 1; }

# ── expand args into parallel indexed arrays (bash-3.2: no assoc arrays) ────
JOURNALS=(); LANE_IDS=(); SLUGS=(); OFFSETS=()
for a in "${ARGS[@]}"; do
  if [[ -d "$a" ]]; then
    root="$(cd "$a" && pwd -P)"
    slug="$(basename "$root")"
    found=0
    while IFS= read -r j; do
      [[ -n "$j" ]] || continue
      JOURNALS+=("$j"); LANE_IDS+=("$(basename "$(dirname "$j")")"); SLUGS+=("$slug"); found=1
    done < <(ls -1 "${root}/docs/leadv2/tasks/"dispatch-*/journal.md 2>/dev/null || true)
    [[ "$found" == "1" ]] || printf '[lane-watch] WARN: no lane journals under %s\n' "$root" >&2
  elif [[ -f "$a" ]]; then
    j="$(cd "$(dirname "$a")" && pwd -P)/$(basename "$a")"
    # journal lives at <root>/docs/leadv2/tasks/<task>/journal.md -> root is 4 up
    # from the journal's dir (dispatch-X -> tasks -> lev2 -> docs -> root)
    root="$(cd "$(dirname "$j")/../../../.." 2>/dev/null && pwd -P || true)"
    JOURNALS+=("$j"); LANE_IDS+=("$(basename "$(dirname "$j")")"); SLUGS+=("$(basename "$root")")
  else
    printf '[lane-watch] WARN: not a journal or repo root: %s\n' "$a" >&2
  fi
done
[[ ${#JOURNALS[@]} -gt 0 ]] || { printf '[lane-watch] nothing to watch\n' >&2; exit 1; }

# ── state dir + per-journal offset files (sha1 of the absolute path) ────────
if [[ -z "$STATE_DIR" ]]; then
  STATE_DIR="$(PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-$PWD}" bash "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link lane-watch 2>/dev/null || true)"
fi
[[ -n "$STATE_DIR" ]] || STATE_DIR="${TMPDIR:-/tmp}/leadv2-lane-watch"
mkdir -p "${STATE_DIR}/lane-watch" 2>/dev/null || true
for ((i = 0; i < ${#JOURNALS[@]}; i++)); do
  h="$(printf '%s' "${JOURNALS[$i]}" | python3 -c 'import hashlib,sys; print(hashlib.sha1(sys.argv[1].encode()).hexdigest())' 2>/dev/null || printf '%s' "$i")"
  OFFSETS+=("${STATE_DIR}/lane-watch/${h}.lines")
done

_now_epoch() {
  if [[ -n "${LEADV2_LANE_WATCH_NOW:-}" ]]; then printf '%s' "${LEADV2_LANE_WATCH_NOW}"; return 0; fi
  if [[ -n "${LEADV2_LANE_WATCH_NOW_BIN:-}" && -x "${LEADV2_LANE_WATCH_NOW_BIN}" ]]; then
    local v; v="$("${LEADV2_LANE_WATCH_NOW_BIN}" 2>/dev/null)"
    if [[ "${v:-}" =~ ^[0-9]+$ ]]; then printf '%s' "$v"; return 0; fi
  fi
  date +%s
}

# stream age of a lane = seconds since the newest mtime in its handoff dir
_stream_age_s() {  # <journal_path>
  local hdir p newest m
  hdir="$(dirname "$1")"
  # journal dir is <root>/docs/leadv2/tasks/<dispatch-X>; handoff is the
  # sibling tree <root>/docs/handoff/<dispatch-X> (4 up from the journal dir)
  hdir="$(cd "$hdir/../../../../handoff/$(basename "$hdir")" 2>/dev/null && pwd -P)"
  [[ -n "${hdir}" && -d "${hdir}" ]] || { printf '?'; return 0; }
  newest=""
  while IFS= read -r p; do
    m="$( [[ "$(uname -s)" == "Darwin" ]] && stat -f %m "$p" 2>/dev/null || stat -c %Y "$p" 2>/dev/null || true)"
    [[ -n "${m}" ]] || continue
    if [[ -z "${newest}" || "${m}" -gt "${newest}" ]]; then newest="${m}"; fi
  done < <(find "${hdir}" -maxdepth 1 -type f 2>/dev/null)
  if [[ -n "${newest}" ]]; then
    local now; now="$(_now_epoch)"
    printf '%s' "$(( now > newest ? now - newest : 0 ))"
  else
    printf '?'
  fi
}

_last_phase() {  # <journal_path>
  local p
  p="$(grep -o 'phase=[^ ]*' "$1" 2>/dev/null | tail -n 1)"
  printf '%s' "${p#phase=}"
  [[ -n "${p}" ]] || printf '?'
}

# ── the pass: one poll of every journal ─────────────────────────────────────
# EMIT_PAT: dispatch_terminal with a trailing space excludes dispatch_terminal_dedup.
EMIT_PAT='dispatch_terminal |question|ask-lead|stall'
TERMINAL_COUNT=0

_pass() {
  local i f n seen new term
  TERMINAL_COUNT=0
  for ((i = 0; i < ${#JOURNALS[@]}; i++)); do
    f="${JOURNALS[$i]}"
    term=0
    if [[ -f "${OFFSETS[$i]}.terminal" ]]; then term=1; fi
    [[ -f "$f" ]] || { [[ "$term" == "1" ]] && TERMINAL_COUNT=$((TERMINAL_COUNT + 1)); continue; }
    n="$(wc -l < "$f" | tr -d ' ')"
    seen=0
    [[ -f "${OFFSETS[$i]}" ]] && seen="$(cat "${OFFSETS[$i]}" 2>/dev/null | tr -d ' ')"
    [[ "${seen}" =~ ^[0-9]+$ ]] || seen=0
    if [[ "${n}" -lt "${seen}" ]]; then
      # rotation / truncate — the old offset points past EOF; restart from 0
      printf '[lane-watch] %s/%s rotated (lines %s < seen %s), re-reading\n' \
        "${SLUGS[$i]}" "${LANE_IDS[$i]}" "$n" "$seen" >&2
      seen=0
    fi
    if [[ "${n}" -gt "${seen}" ]]; then
      new="$(tail -n +"$((seen + 1))" "$f" | grep -E --line-buffered "${EMIT_PAT}" || true)"
      if [[ -n "${new}" ]]; then
        while IFS= read -r l; do
          printf '%s/%s %s\n' "${SLUGS[$i]}" "${LANE_IDS[$i]}" "$l"
        done <<< "${new}"
        if printf '%s\n' "${new}" | grep -q 'dispatch_terminal task='; then
          term=1
          : > "${OFFSETS[$i]}.terminal"
        fi
      fi
    fi
    printf '%s\n' "${n}" > "${OFFSETS[$i]}" 2>/dev/null || true
    [[ "$term" == "1" ]] && TERMINAL_COUNT=$((TERMINAL_COUNT + 1))
  done
}

_heartbeat() {
  local i f age phase
  for ((i = 0; i < ${#JOURNALS[@]}; i++)); do
    f="${JOURNALS[$i]}"
    if [[ -f "$f" ]]; then
      age="$(_stream_age_s "$f")"
      phase="$(_last_phase "$f")"
    else
      age="?"; phase="?"
    fi
    printf 'hb %s stream_age=%ss phase=%s\n' "${LANE_IDS[$i]}" "${age}" "${phase}"
  done
}

_last_hb="$(_now_epoch)"
while :; do
  _pass
  if [[ "${ONCE}" == "1" ]]; then exit 0; fi
  if [[ "${TERMINAL_COUNT}" -ge ${#JOURNALS[@]} ]]; then
    printf '[lane-watch] all %s watched lane(s) terminal, exiting\n' "${#JOURNALS[@]}" >&2
    exit 0
  fi
  _now="$(_now_epoch)"
  if [[ "${HEARTBEAT}" -gt 0 && $((_now - _last_hb)) -ge "${HEARTBEAT}" ]]; then
    _heartbeat
    _last_hb="${_now}"
  fi
  sleep "${INTERVAL}"
done
