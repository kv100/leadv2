#!/usr/bin/env bash
# leadv2-inbox.sh — LEAD-WORKER-CHANNEL-01 durable, cross-repo lead inbox.
#
# A worker cannot reliably reach a lead via SendMessage (busy/dead/headless
# model on the other end), so every lead-addressed event lands HERE first,
# unconditionally, with no network and no model involved. SendMessage is an
# optimisation layered on top by the caller (leadv2-notify-lead.sh) -- this
# script never sends anything, it only durably records and durably drains.
#
# CROSS-REPO PLACEMENT (verified, not assumed): leadv2-state-path.sh
# resolves a control-plane root that is PER-REPO (${base}/${repo-slug},
# repo-slug = basename of the main repo toplevel, see its own header) --
# that isolation is the entire point of LEAD-CONTROL-PLANE-01, so reusing
# it verbatim (the way leadv2-bus.sh does for bus.jsonl) would put
# persona-engine's events and leadv2's events in TWO DIFFERENT files, and a
# lead draining from one repo would never see a worker's event from the
# other. This inbox instead lives ONE LEVEL UP, at the shared base itself
# (dirname of the per-repo root) -- the same physical disk location for
# every repo on this machine, so a worker in ANY repo and a lead in ANY
# repo resolve to the SAME lead-inbox.jsonl. See _lv2_inbox_dir below.
#
# Storage: one JSONL file, one row per event, appended and drained through
# a python3 fcntl.flock(LOCK_EX) critical section -- the same primitive
# leadv2-bus.sh uses and its test suite proves safe for concurrent writers
# on darwin (BSD flock is a real advisory lock on APFS/HFS+).
#
# Usage:
#   leadv2-inbox.sh append <lead-id> <repo> <task-id> <lane> <event> <text>
#     Appends one durable row. Exits 0 on success, 1 if the write itself
#     failed (e.g. unwritable inbox dir). This script reports failure
#     honestly on its own exit code -- it is leadv2-notify-lead.sh's job
#     (the caller) to never let that failure propagate into a lane's exit
#     code, never this script's.
#   leadv2-inbox.sh drain [--lead <id>]
#     Prints unread rows for that lead, oldest-first, one rendered line
#     each (never raw JSON -- the lead renders it straight into a status
#     line without opening anything else), and atomically advances that
#     lead's read-offset so a second drain call never re-prints the same
#     row. Exits 0 with no output when nothing is unread. `--lead` defaults
#     to the same resolution order leadv2-dispatch-code.sh uses to compute
#     _lead_session_id.
#
# Env overrides (tests sandbox with these -- never the real ~/.claude
# state root from a test):
#   PROJECT_ROOT          - repo root (used only to derive the per-repo
#                           root before taking its dirname; see below)
#   LEADV2_LEAD_INBOX_DIR - full override of the inbox's directory. Tests
#                           MUST set this to a throwaway dir; production
#                           never sets it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

_lv2_inbox_dir() {
  if [[ -n "${LEADV2_LEAD_INBOX_DIR:-}" ]]; then
    printf '%s' "${LEADV2_LEAD_INBOX_DIR}"
    return 0
  fi
  local per_repo_root
  per_repo_root="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link 2>/dev/null)" || per_repo_root=""
  if [[ -n "$per_repo_root" ]]; then
    dirname "$per_repo_root"
  else
    printf '%s/.claude/leadv2-state' "$HOME"
  fi
}

LEADV2_DIR="$(_lv2_inbox_dir)"
INBOX_FILE="${LEADV2_DIR}/lead-inbox.jsonl"
INBOX_LOCK="${LEADV2_DIR}/.lead-inbox.lock"
OFFSETS_DIR="${LEADV2_DIR}/.lead-inbox-offsets"

usage() {
  printf -- 'Usage:\n' >&2
  printf -- '  leadv2-inbox.sh append <lead-id> <repo> <task-id> <lane> <event> <text>\n' >&2
  printf -- '  leadv2-inbox.sh drain [--lead <id>]\n' >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
CMD="$1"; shift

case "$CMD" in
  append)
    [[ $# -eq 6 ]] || usage
    LEAD_ID="$1"; REPO="$2"; TASK_ID="$3"; LANE="$4"; EVENT="$5"; TEXT="$6"
    mkdir -p "$LEADV2_DIR" 2>/dev/null || { printf -- '[inbox] cannot create %s\n' "$LEADV2_DIR" >&2; exit 1; }
    python3 - "$INBOX_FILE" "$INBOX_LOCK" "$LEAD_ID" "$REPO" "$TASK_ID" "$LANE" "$EVENT" "$TEXT" <<'PYEOF'
import fcntl, json, os, sys, time

inbox_file, inbox_lock, lead, repo, task_id, lane, event, text = sys.argv[1:9]

line = json.dumps({
    "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "lead": lead,
    "repo": repo,
    "task_id": task_id,
    "lane": lane,
    "event": event,
    "text": text,
}, sort_keys=True)

try:
    lockf = open(inbox_lock, "a+")
    try:
        fcntl.flock(lockf, fcntl.LOCK_EX)
        with open(inbox_file, "a", encoding="utf-8") as f:
            f.write(line + "\n")
            f.flush()
            os.fsync(f.fileno())
    finally:
        fcntl.flock(lockf, fcntl.LOCK_UN)
        lockf.close()
except OSError as e:
    sys.stderr.write("[inbox] append failed: %s\n" % e)
    sys.exit(1)
PYEOF
    ;;

  drain)
    LEAD_ID="${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-${CLAUDE_SESSION_ID:-direct}}}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --lead) LEAD_ID="$2"; shift 2 ;;
        *) usage ;;
      esac
    done
    mkdir -p "$LEADV2_DIR" "$OFFSETS_DIR" 2>/dev/null || true
    python3 - "$INBOX_FILE" "$INBOX_LOCK" "$OFFSETS_DIR" "$LEAD_ID" <<'PYEOF'
import fcntl, json, os, sys

inbox_file, inbox_lock, offsets_dir, lead = sys.argv[1:5]

def read_lines():
    if not os.path.exists(inbox_file):
        return []
    with open(inbox_file, encoding="utf-8") as f:
        return [l for l in f.read().splitlines() if l.strip()]

# Shared lock while reading the whole file -- appenders hold this SAME lock
# exclusively, so a reader never observes a torn write.
lockf = open(inbox_lock, "a+")
fcntl.flock(lockf, fcntl.LOCK_SH)
try:
    lines = read_lines()
finally:
    fcntl.flock(lockf, fcntl.LOCK_UN)
    lockf.close()

# Offset is keyed by lead id ONLY (never by caller/pid): two concurrent
# `drain` calls for the SAME lead must split the unread rows between them,
# not both see the same ones. The exclusive flock below is what makes that
# atomic -- the second caller only starts reading once the first has
# advanced the offset and released the lock.
os.makedirs(offsets_dir, exist_ok=True)
offset_path = os.path.join(offsets_dir, lead)
offset_lock_path = offset_path + ".lock"
olockf = open(offset_lock_path, "a+")
try:
    fcntl.flock(olockf, fcntl.LOCK_EX)
    try:
        with open(offset_path, encoding="utf-8") as f:
            start = int(f.read().strip() or "0")
    except (FileNotFoundError, ValueError):
        start = 0

    out = []
    for l in lines[start:]:
        try:
            ev = json.loads(l)
        except Exception:
            continue
        if ev.get("lead") == lead:
            out.append(ev)

    tmp = offset_path + (".tmp.%d" % os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(str(len(lines)))
    os.replace(tmp, offset_path)
finally:
    fcntl.flock(olockf, fcntl.LOCK_UN)
    olockf.close()

for ev in out:
    print("%s [%s/%s] lane=%s event=%s: %s" % (
        ev.get("at", "?"), ev.get("repo", "?"), ev.get("task_id", "?"),
        ev.get("lane", "?"), ev.get("event", "?"), ev.get("text", ""),
    ))
PYEOF
    ;;

  *)
    usage
    ;;
esac
