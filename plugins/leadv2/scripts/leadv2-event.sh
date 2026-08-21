#!/usr/bin/env bash
# leadv2-event.sh — V3-WORKER-MESSAGING-01 slice 1 (docs/specs/worker-messaging-v3.md §1-2,§6).
# Tier-0 durable event emitter: one append-only JSONL per repo, one line per
# event. This alone makes every fault the spec documents (D1-D4) recoverable
# after the fact; later slices (transport tiers 1-3, subscriptions, renderer)
# build on top of this file and are out of scope here.
#
# Rollback: delete this file. Every call site emits via `|| true` (fail-open,
# same convention as leadv2-dispatch-code.sh's own `emit()` at :1172-1186) --
# removing the binary degrades a caller to a no-op, never a crash.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=leadv2-portable-lock.sh
source "${SCRIPT_DIR}/leadv2-portable-lock.sh"

LEADV2_EVENT_LOG_DIR="${LEADV2_EVENT_LOG_DIR:-${HOME}/.claude/cache/leadv2-events}"
_EVENT_ROTATE_MAX_BYTES=10485760   # 10MB, spec §1 "Rotation: 10MB, keep 3"
_EVENT_ROTATE_KEEP=3

usage() {
  printf 'usage: leadv2-event.sh emit --repo <repo> --kind <kind> [--task <sig8>] [--lane <name>] [--arm <arm>] [--handle <handle>] [--ttl-s <n>] [--detail <text>]\n' >&2
  exit 2
}

# _event_rotate_if_needed <logfile> -- called under the seq lock (below), so a
# rotation can never race a concurrent writer's own rotation decision.
_event_rotate_if_needed() {
  local f="$1" size
  [[ -f "${f}" ]] || return 0
  size="$(stat -f '%z' "${f}" 2>/dev/null || stat -c '%s' "${f}" 2>/dev/null || printf 0)"
  [[ "${size}" =~ ^[0-9]+$ ]] || return 0
  (( size < _EVENT_ROTATE_MAX_BYTES )) && return 0
  local i
  for (( i = _EVENT_ROTATE_KEEP - 1; i >= 1; i-- )); do
    [[ -f "${f}.${i}" ]] && { mv -f "${f}.${i}" "${f}.$((i + 1))" 2>/dev/null || true; }
  done
  mv -f "${f}" "${f}.1" 2>/dev/null || true
}

# cmd_emit -- fail-open at every stage: a malformed call, a lock timeout, or a
# write failure all return 0 rather than propagate an error to the caller (a
# lane driver or dispatcher that must never abort over an observability write).
cmd_emit() {
  local repo="" task="" lane="" arm="" handle="" kind="" ttl_s="" detail=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)   repo="${2:-}"; shift 2 ;;
      --task)   task="${2:-}"; shift 2 ;;
      --lane)   lane="${2:-}"; shift 2 ;;
      --arm)    arm="${2:-}"; shift 2 ;;
      --handle) handle="${2:-}"; shift 2 ;;
      --kind)   kind="${2:-}"; shift 2 ;;
      --ttl-s)  ttl_s="${2:-}"; shift 2 ;;
      --detail) detail="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "${repo}" && -n "${kind}" ]] || return 0

  mkdir -p "${LEADV2_EVENT_LOG_DIR}" 2>/dev/null || return 0
  local logf="${LEADV2_EVENT_LOG_DIR}/${repo}.jsonl"
  local seqf="${logf}.seq"
  local lockf="${logf}.lock"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '')"

  (
    lv2_lock_wait "${lockf}" 5 || exit 0
    local seq
    seq="$(cat "${seqf}" 2>/dev/null || printf 0)"
    [[ "${seq}" =~ ^[0-9]+$ ]] || seq=0
    seq=$((seq + 1))
    { printf '%s' "${seq}" > "${seqf}.tmp" && mv -f "${seqf}.tmp" "${seqf}"; } 2>/dev/null || true
    _event_rotate_if_needed "${logf}"
    python3 -c '
import json, sys
repo, task, lane, arm, handle, kind, ttl_s, detail, seq, ts = sys.argv[1:11]
row = {"seq": int(seq), "ts": ts, "repo": repo}
if task:   row["task"] = task
if lane:   row["lane"] = lane
if arm:    row["arm"] = arm
if handle: row["handle"] = handle
row["kind"] = kind
if ttl_s:
    row["ttl_s"] = int(ttl_s) if ttl_s.isdigit() else ttl_s
if detail: row["detail"] = detail
print(json.dumps(row, separators=(",", ":")))
' "${repo}" "${task}" "${lane}" "${arm}" "${handle}" "${kind}" "${ttl_s}" "${detail}" "${seq}" "${ts}" >> "${logf}" 2>/dev/null || true
  ) 9>"${lockf}" || true
  return 0
}

case "${1:-}" in
  emit) shift; cmd_emit "$@" ;;
  *) usage ;;
esac
