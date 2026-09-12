#!/usr/bin/env bash
# HOOK-DISPATCH-01: collapses the 9 project PreToolUse/Bash hooks into one
# entry so the harness performs 1 hook execution instead of 9.
#
# Deliberately NO `set -e` / `set -u`: a dispatcher that dies on its own
# unset-variable or a child's SIGPIPE would fail-open on EVERY guard for
# that Bash call, which is worse than the token cost this file exists to
# cut. See docs/handoff/dispatch-2b494b78/developer.full.md counterexample #1.
set -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME:-$HOME}"

# stdin read exactly ONCE; fed to every child via printf, never re-read.
INPUT="$(cat 2>/dev/null || true)"

# "timeout_seconds:path" — order MUST match the current settings.json
# PreToolUse[0] (commands 1-8) followed by PreToolUse[7] (command 9).
CHILDREN=(
  "5:${HOME_DIR}/.claude/hooks/check-careful.sh"
  "60:${HOME_DIR}/.claude/hooks/pre-commit-tsc-check"
  "10:${DIR}/leadv2-phase8-gate.sh"
  "10:${DIR}/leadv2-close-diff-guard.sh"
  "5:${DIR}/leadv2-supervisor-fanout-guard.sh"
  "5:${DIR}/guard-shared-git-destructive.py"
  "10:${DIR}/plugin-scripts-drift-guard.sh"
  "10:${DIR}/leadv2-reflect-enforcer.sh"
)

HAVE_TIMEOUT=0
if command -v timeout >/dev/null 2>&1; then
  HAVE_TIMEOUT=1
fi

pending_ask=""

for spec in "${CHILDREN[@]}"; do
  t="${spec%%:*}"
  child="${spec#*:}"

  if [ ! -e "$child" ] || { [ ! -x "$child" ] && [ ! -r "$child" ]; }; then
    echo "[hook-dispatch] child missing or not runnable, skipping (fail-open): $child" >&2
    continue
  fi

  errfile="$(mktemp "${TMPDIR:-/tmp}/leadv2-hookdisp-err.XXXXXX" 2>/dev/null || echo /tmp/leadv2-hookdisp-err.$$)"

  case "$child" in
    *.py) interp="python3" ;;
    *) interp="" ;;
  esac

  if [ "$HAVE_TIMEOUT" -eq 1 ]; then
    if [ -n "$interp" ]; then
      out="$(printf '%s' "$INPUT" | timeout "$t" "$interp" "$child" 2>"$errfile")"
    else
      out="$(printf '%s' "$INPUT" | timeout "$t" "$child" 2>"$errfile")"
    fi
    rc=$?
  else
    # B1 (Codex HIGH, rounds 2+3): without a per-child deadline here, ONE hung child
    # blocks every LATER guard in the chain until the harness's own outer timeout —
    # silently disabling guard-shared-git-destructive.py and plugin-scripts-drift-guard.sh,
    # which is the exact failure this dispatcher must not introduce. Portable fallback:
    # background the child, poll to its budget, kill, reap, continue.
    outfile="$(mktemp "${TMPDIR:-/tmp}/leadv2-hookdisp-out.XXXXXX" 2>/dev/null || echo /tmp/leadv2-hookdisp-out.$$)"
    infile="$(mktemp "${TMPDIR:-/tmp}/leadv2-hookdisp-in.XXXXXX" 2>/dev/null || echo /tmp/leadv2-hookdisp-in.$$)"
    printf '%s' "$INPUT" > "$infile"

    # Round-3 Codex HIGH: killing only the child PID leaves its DESCENDANTS running —
    # a guard that shelled out to git/python would outlive its own deadline. So the child
    # must be its own process-group leader and the whole GROUP must be signalled.
    # `set -m` (job control) makes a background job a group leader with pgid == pid.
    # stdin comes from a file, not a pipe: a pipeline's $! is the LAST element, whose pid
    # is not the group's pgid, so `kill -$!` would signal the wrong group.
    set -m 2>/dev/null
    if [ -n "$interp" ]; then
      "$interp" "$child" <"$infile" >"$outfile" 2>"$errfile" &
    else
      "$child" <"$infile" >"$outfile" 2>"$errfile" &
    fi
    child_pid=$!
    set +m 2>/dev/null

    waited=0
    killed=0
    while kill -0 "$child_pid" 2>/dev/null; do
      if [ "$waited" -ge "$t" ]; then
        # Negative pid = the whole process group. Fall back to the bare pid if the
        # platform refused the group signal (job control unavailable).
        kill -TERM -"$child_pid" 2>/dev/null || kill -TERM "$child_pid" 2>/dev/null
        sleep 1
        # Codex round-3 follow-up: gating the KILL on `kill -0 $child_pid` asks whether the
        # GROUP LEADER is still alive, which says nothing about its descendants. A leader that
        # exits cleanly on TERM while a child ignores TERM would leave that child running and
        # we would never escalate. So the KILL goes to the GROUP unconditionally; it is
        # harmless when the group is already gone (errors are discarded).
        kill -KILL -"$child_pid" 2>/dev/null || true
        kill -0 "$child_pid" 2>/dev/null && kill -KILL "$child_pid" 2>/dev/null
        killed=1
        break
      fi
      sleep 1
      waited=$((waited + 1))
    done

    wait "$child_pid" 2>/dev/null
    rc=$?
    out="$(cat "$outfile" 2>/dev/null)"
    rm -f "$outfile" "$infile"

    if [ "$killed" -eq 1 ]; then
      # Killed on timeout is FAIL-OPEN, never a deny: a hung guard must not be able to
      # block the tool call, and must not stop the remaining guards from running.
      echo "[hook-dispatch] child exceeded ${t}s budget, killed (fail-open): $child" >&2
      rm -f "$errfile"
      continue
    fi
  fi

  decision=""
  if [ -n "$out" ] && command -v jq >/dev/null 2>&1; then
    decision="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  fi

  if [ "$decision" = "deny" ] || [ "$rc" -eq 2 ]; then
    [ -n "$out" ] && printf '%s\n' "$out"
    cat "$errfile" >&2
    rm -f "$errfile"
    if [ "$rc" -eq 2 ]; then
      exit 2
    fi
    exit 0
  fi

  cat "$errfile" >&2
  rm -f "$errfile"

  if [ "$rc" -ne 0 ]; then
    if [ "$rc" -eq 124 ]; then
      echo "[hook-dispatch] child timed out after ${t}s (fail-open): $child" >&2
    else
      echo "[hook-dispatch] child exited ${rc} (fail-open): $child" >&2
    fi
    continue
  fi

  if [ "$decision" = "ask" ] && [ -z "$pending_ask" ]; then
    pending_ask="$out"
  fi
done

if [ -n "$pending_ask" ]; then
  printf '%s\n' "$pending_ask"
  exit 0
fi

exit 0
