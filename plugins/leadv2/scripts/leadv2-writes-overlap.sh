#!/usr/bin/env bash
# leadv2-writes-overlap.sh — SUPERVISOR-AUDIT-01 T-E: detect file-touch
# overlap between a NEW lane's declared `writes` and every currently-ALIVE
# lane's declared `writes` in active.yaml. Founder point: notify, never
# hard-block — this script only detects and (optionally) notifies; the
# caller (leadv2-fanout.sh) always proceeds with dispatch regardless of
# what this script prints or returns.
#
# Usage:
#   leadv2-writes-overlap.sh --task-id <tid> --writes <csv>
#                             [--project-root <root>] [--notify]
#
# --writes is a comma-separated list of paths (same convention as
# tasks.yaml's `writes` field / _fanout_task_lane_contract in
# leadv2-fanout.sh). Two paths conflict if they are identical, or one is a
# directory-prefix of the other (e.g. "platform/foo/" vs "platform/foo/bar.py").
#
# Output (stdout): one line per conflicting OTHER alive lane —
#   task=<tid> other=<other_tid> paths=<csv>
# Always printed (whether or not --notify is given) so a caller can consume
# it directly; --notify additionally appends a journal finding
# (leadv2-journal.sh) for <tid> and a [SUPERVISE-URGENT] line to the same
# pulse log the (now-retired) supervisor loop wrote (grep SUPERVISE-URGENT there).
#
# LEADV2_WRITES_CONFLICT_NOTIFY=0 makes this ENTIRE script a no-op (exit 0,
# no stdout, no side effects) — the one-flag rollback to today's behavior on
# the fanout dispatch path. Default: 1 (on).
#
# Fail-open: any missing dependency (state-path resolver, active.yaml,
# lane-liveness.sh, PyYAML) yields "no conflicts found" and exit 0 — this
# script must never be why a dispatch fails or hangs. That policy is intact.
#
# What is no longer silent is the DIFFERENCE between "looked and found
# nothing" and "could not look". Measured 2026-09-05: PyYAML on a developer
# machine is a user-site install under $HOME, so on CI, a fresh VPS or any
# container the import failed and this checker printed exactly what it prints
# when the tree is clean. A conflict checker that cannot check must not be
# indistinguishable from one that found no conflict. An unchecked run now says
# so on STDERR (never on stdout, which callers parse as conflict rows) and,
# under --notify, leaves a journal finding. The exit code stays 0.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# One-flag rollback: default ON, =0 restores today (no detection, no
# notification, no side effects at all) byte-for-byte.
if [[ "${LEADV2_WRITES_CONFLICT_NOTIFY:-1}" == "0" ]]; then
  exit 0
fi

PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-${PROJECT_ROOT:-$(pwd)}}}"
TASK_ID=""
WRITES_CSV=""
NOTIFY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) TASK_ID="${2:-}"; shift 2 ;;
    --writes) WRITES_CSV="${2:-}"; shift 2 ;;
    --project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
    --notify) NOTIFY=1; shift ;;
    -h|--help)
      printf -- 'Usage: %s --task-id <tid> --writes <csv> [--project-root <root>] [--notify]\n' "$(basename "$0")"
      exit 0
      ;;
    *) printf -- '[writes-overlap] unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[[ -n "$TASK_ID" && -n "$WRITES_CSV" ]] || exit 0

STATE_PATH_SH="${SCRIPT_DIR}/leadv2-state-path.sh"
ACTIVE_YAML="${PROJECT_ROOT}/docs/leadv2/active.yaml"
if [[ -x "$STATE_PATH_SH" ]]; then
  ACTIVE_YAML="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" --no-link active.yaml 2>/dev/null || printf '%s' "$ACTIVE_YAML")"
fi
[[ -f "$ACTIVE_YAML" ]] || exit 0

LIVENESS_BIN="${LEADV2_WRITES_OVERLAP_LIVENESS_BIN:-${SCRIPT_DIR}/leadv2-lane-liveness.sh}"
LIVENESS_JSON='{"lanes":[]}'
UNCHECKED_REASON=""
if [[ -x "$LIVENESS_BIN" ]]; then
  _liv_rc=0
  LIVENESS_JSON="$(LEADV2_PROJECT_ROOT="$PROJECT_ROOT" bash "$LIVENESS_BIN" --project-root "$PROJECT_ROOT" --all --json 2>/dev/null)" || _liv_rc=$?
  if [[ "$_liv_rc" -ne 0 || -z "$LIVENESS_JSON" ]]; then
    # An empty lane list is a real answer ("nothing is alive"); a probe that
    # failed is not, and the two used to arrive here as the same string.
    LIVENESS_JSON='{"lanes":[]}'
    UNCHECKED_REASON="liveness_probe_failed_rc${_liv_rc}"
  fi
else
  UNCHECKED_REASON="liveness_bin_absent"
fi

WO_ERR="$(mktemp 2>/dev/null || printf '%s' "/tmp/leadv2-wo-$$.err")"
WO_RC=0
CONFLICTS="$(python3 - "$TASK_ID" "$WRITES_CSV" "$ACTIVE_YAML" "$LIVENESS_JSON" <<'PY' 2>"$WO_ERR"
import json, os, sys
# Exit 20 with a reason on stderr means "could not look". Exit 0 keeps its
# old meaning: looked, and printed whatever it found (possibly nothing).
try:
    import yaml
except ImportError:
    print("no_yaml_parser", file=sys.stderr)
    sys.exit(20)

task_id, writes_csv, active_path, liveness_raw = sys.argv[1:5]

def norm_paths(csv):
    out = []
    for p in csv.split(","):
        p = p.strip()
        if p:
            out.append(os.path.normpath(p))
    return out

def overlaps(a, b):
    if a == b:
        return True
    return (b + os.sep).startswith(a + os.sep) or (a + os.sep).startswith(b + os.sep)

cand = norm_paths(writes_csv)
if not cand:
    sys.exit(0)

try:
    liveness = json.loads(liveness_raw)
except Exception:
    print("liveness_unparseable", file=sys.stderr)
    sys.exit(20)
alive_ids = {
    row.get("lane") for row in (liveness.get("lanes") or [])
    if isinstance(row, dict) and str(row.get("verdict") or "").startswith("alive")
    and row.get("lane") and row.get("lane") != task_id
}
if not alive_ids:
    sys.exit(0)

try:
    with open(active_path, encoding="utf-8") as fh:
        active = yaml.safe_load(fh) or {}
except FileNotFoundError:
    sys.exit(0)          # no registry yet is a real "nothing to conflict with"
except Exception:
    print("active_yaml_unreadable", file=sys.stderr)
    sys.exit(20)

sessions = {
    str(s.get("task_id")): s for s in (active.get("sessions") or [])
    if isinstance(s, dict) and s.get("task_id")
}

for other_id in sorted(alive_ids):
    other = sessions.get(other_id)
    if not other:
        continue
    other_writes_raw = other.get("writes") or ""
    if isinstance(other_writes_raw, (list, tuple)):
        other_csv = ",".join(str(w) for w in other_writes_raw)
    else:
        other_csv = str(other_writes_raw)
    other_paths = norm_paths(other_csv)
    if not other_paths:
        continue
    hit = sorted({a for a in cand for b in other_paths if overlaps(a, b)})
    if hit:
        print(f"task={task_id} other={other_id} paths={','.join(hit)}")
PY
)" || WO_RC=$?
if [[ "$WO_RC" -eq 20 ]]; then
  UNCHECKED_REASON="$(head -n1 "$WO_ERR" 2>/dev/null | tr -d '\r\n')"
fi
rm -f "$WO_ERR" 2>/dev/null || true

if [[ -n "$UNCHECKED_REASON" ]]; then
  # STDERR, never stdout: callers parse stdout as conflict rows, so an
  # "I could not look" line there would be read as a conflict -- the opposite
  # error, and just as wrong.
  printf 'writes_overlap: UNCHECKED task=%s reason=%s -- fail-open (exit 0), and this is NOT "no conflicts found"\n' \
    "$TASK_ID" "$UNCHECKED_REASON" >&2
  if [[ "$NOTIFY" -eq 1 ]]; then
    _JOURNAL_SH="${SCRIPT_DIR}/leadv2-journal.sh"
    if [[ -f "$_JOURNAL_SH" ]]; then
      CLAUDE_PROJECT_DIR="$PROJECT_ROOT" bash "$_JOURNAL_SH" append "$TASK_ID" finding \
        "writes_conflict_unchecked reason=${UNCHECKED_REASON}" >/dev/null 2>&1 || true
    fi
  fi
fi

[[ -n "$CONFLICTS" ]] && printf -- '%s\n' "$CONFLICTS"

if [[ "$NOTIFY" -eq 1 && -n "$CONFLICTS" ]]; then
  JOURNAL_SH="${SCRIPT_DIR}/leadv2-journal.sh"
  PULSE_LOG="${PROJECT_ROOT}/docs/leadv2/supervise-loop.log"
  if [[ -x "$STATE_PATH_SH" ]]; then
    PULSE_LOG="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" --no-link supervise-loop.log 2>/dev/null || printf '%s' "$PULSE_LOG")"
  fi
  mkdir -p "$(dirname "$PULSE_LOG")" 2>/dev/null || true
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    # NOTE: leadv2-journal.sh is invoked via `bash`, not executed directly,
    # so it is checked for existence (-f), not the executable bit (-x) --
    # unlike its sibling scripts, it is not chmod +x in this repo.
    if [[ -f "$JOURNAL_SH" ]]; then
      CLAUDE_PROJECT_DIR="$PROJECT_ROOT" bash "$JOURNAL_SH" append "$TASK_ID" finding "writes_conflict $line" >/dev/null 2>&1 || true
    fi
    printf -- '%s [SUPERVISE-URGENT] WRITES_CONFLICT %s\n' \
      "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$line" >> "$PULSE_LOG" 2>/dev/null || true
  done <<< "$CONFLICTS"
fi

exit 0
