#!/usr/bin/env bash
# CODEX-TRANSPORT-DIES-ROOT-CAUSE-01 — the measurement §3 is missing.
#
# READ-ONLY. It starts nothing and kills nothing. Run it in a session while a codex
# job is running elsewhere; it watches that job's broker sessionDir and reports the
# moment the directory disappears, together with whether the broker record survived.
#
# The point: if the dir vanishes while the record stays, teardown did NOT run -- the
# directory was removed by something outside the vendor's lifecycle, and the only
# candidate seen in the data is a session-scoped TMPDIR being torn down with its
# session (14 of 360 records live under /tmp/claude-503/, which is exactly that).
#
# usage: repro.sh <state-key-dir-name>        e.g. repro.sh leadv2-c74f96a6c35224f2
#        repro.sh --list                      show keys that currently HAVE a broker record
set -uo pipefail
STATE="${HOME}/.claude/plugins/data/codex-openai-codex/state"

if [[ "${1:-}" == "--list" || $# -eq 0 ]]; then
  printf 'state keys holding a broker record right now:\n'
  for f in "$STATE"/*/broker.json; do
    [[ -e "$f" ]] || continue
    sd="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("sessionDir",""))' "$f" 2>/dev/null)"
    printf '  %-52s sessionDir_exists=%s\n' "$(basename "$(dirname "$f")")" "$([[ -d "$sd" ]] && echo yes || echo NO)"
  done
  exit 0
fi

KEY="$1"
REC="${STATE}/${KEY}/broker.json"
[[ -f "$REC" ]] || { printf 'no broker record at %s\n' "$REC" >&2; exit 2; }

SD="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("sessionDir",""))' "$REC")"
EP="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("endpoint",""))' "$REC")"
PID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("pid",""))' "$REC")"
SOCK="${EP#unix:}"

printf 'watching %s\n  sessionDir=%s\n  socket=%s\n  pid=%s\n' "$KEY" "$SD" "$SOCK" "$PID"
printf '%-21s %-6s %-7s %-7s %s\n' 'time' 'dir' 'socket' 'record' 'pid'

# NOTE ON PID: `kill -0` answers yes for a REUSED pid number too, and answers EPERM
# (also success) for a process we do not own. It is reported here as a hint, never as
# proof that the broker itself is alive.
while :; do
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  d=$([[ -d "$SD" ]] && echo yes || echo NO)
  s=$([[ -S "$SOCK" ]] && echo yes || echo NO)
  r=$([[ -f "$REC" ]] && echo yes || echo NO)
  p='-'
  [[ -n "$PID" ]] && { kill -0 "$PID" 2>/dev/null && p=hint-alive || p=absent; }
  printf '%-21s %-6s %-7s %-7s %s\n' "$now" "$d" "$s" "$r" "$p"
  # the finding is this exact combination: the directory is gone while the record stays.
  if [[ "$d" == "NO" && "$r" == "yes" ]]; then
    printf '\nFOUND: sessionDir removed while the broker record survived.\n'
    printf 'teardownBrokerSession did not run (it clears the record right after), so the\n'
    printf 'directory was removed from outside the vendor lifecycle. Capture NOW which\n'
    printf 'Claude session just ended, and whether its scratch TMPDIR is a prefix of:\n  %s\n' "$SD"
    exit 0
  fi
  [[ "$r" == "NO" ]] && { printf '\nrecord cleared normally (ordinary teardown) — not the failure mode.\n'; exit 1; }
  sleep 5
done
