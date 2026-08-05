#!/usr/bin/env bash
# PreToolUse:Bash — block foreground invocation of long-running leadv2 worker launchers.
# The Bash tool's 2-minute foreground timeout SIGTERMs the whole process group, killing
# a dispatch mid-flight with no diagnostic. This hook forces those launchers into the
# background (run_in_background / trailing & / nohup / setsid).
#
# Round 2: predicates evaluate per launcher-execution segment, not the whole command
# string.  A single python3 pass lexes and segments the command; only segments that
# actually execute a guarded launcher are checked, fixing F1 (exemption-in-sibling) and
# F2 (read-only-verb false positives).
#
# Known residual: subshells $(...), heredocs, xargs/find -exec, and ssh-remote
# invocations are not parsed as execution-position launchers (needs a real shell
# parser).  The override comment and run_in_background paths keep these recoverable.
# The failure mode for exotic shapes is a false negative, matching fail-open philosophy.
#
# Fail-open: empty stdin, parse failure, or any uncaught error → exit 0 (never wedge the lead).
# Override: append "# fg-dispatch: allow" to the command, or set LEADV2_ALLOW_FG_DISPATCH=1.
set -euo pipefail
trap 'echo "[$(basename "$0")] error at line $LINENO" >&2; exit 0' ERR

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

# Secondary escape hatch (mirrors LEADV2_ALLOW_FG in leadv2-block-fg-agent.sh).
[[ "${LEADV2_ALLOW_FG_DISPATCH:-0}" == "1" ]] && exit 0

# Single python3 pass: emit RIB (line 1), SEGS (line 2, \x1f-joined launcher-exec segments),
# CMD (line 3+, verbatim — must be last because CMD may contain newlines).
# On any exception the script writes nothing → fail-open.
# NOTE: python code is inside bash single quotes — no single-quote chars allowed inside.
_PARSE_OUT="$(printf '%s' "$INPUT" | python3 -c '
import sys, json, os, re, shlex

GUARDED = {
    "leadv2-dispatch-code.sh",
    "leadv2-codex-session-runner.sh",
    "leadv2-fanout.sh",
    "glm-coder.sh",
    "omp-task.sh",
}
WRAPPERS = {"nohup", "setsid", "env", "command", "exec", "time", "sudo"}
INTERPRETERS = {"bash", "sh", "zsh", "dash", "source", "."}
VAR_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
SQ = chr(39)   # single quote
DQ = chr(34)   # double quote

def split_segments(cmd):
    segs = []
    cur = []
    i = 0
    n = len(cmd)
    sq_on = False
    dq_on = False
    while i < n:
        c = cmd[i]
        if sq_on:
            cur.append(c)
            if c == SQ:
                sq_on = False
            i += 1
            continue
        if dq_on:
            cur.append(c)
            if c == "\\":
                if i + 1 < n:
                    cur.append(cmd[i + 1])
                    i += 2
                    continue
            elif c == DQ:
                dq_on = False
            i += 1
            continue
        # Not inside quotes
        if c == SQ:
            cur.append(c); sq_on = True; i += 1; continue
        if c == DQ:
            cur.append(c); dq_on = True; i += 1; continue
        if c == "\\":
            if i + 1 < n:
                cur.append(c); cur.append(cmd[i + 1]); i += 2; continue
            cur.append(c); i += 1; continue
        two = cmd[i:i+2]
        if two in ("&&", "||"):
            segs.append("".join(cur)); cur = []; i += 2; continue
        if c in (";", "|", "\n"):
            segs.append("".join(cur)); cur = []; i += 1; continue
        cur.append(c); i += 1
    segs.append("".join(cur))
    return segs

def is_launcher_exec(seg):
    try:
        tokens = shlex.split(seg)
    except ValueError:
        tokens = seg.split()
    if not tokens:
        return False
    j = 0
    # Drop leading VAR=value assignments.
    while j < len(tokens) and VAR_RE.match(tokens[j]):
        j += 1
    # Drop leading wrapper commands.
    while j < len(tokens) and os.path.basename(tokens[j]) in WRAPPERS:
        j += 1
    if j >= len(tokens):
        return False
    head = os.path.basename(tokens[j])
    if head in GUARDED:
        return True
    if head in INTERPRETERS:
        for t in tokens[j + 1:]:
            if os.path.basename(t) in GUARDED:
                return True
    return False

try:
    r = json.loads(sys.stdin.read())
    ti = r.get("tool_input", {})
    cmd = ti.get("command", "")
    rib = ti.get("run_in_background")
    rib_norm = "" if rib is None else ("true" if rib else "false")

    raw_segs = split_segments(cmd)
    launcher_segs = []
    for s in raw_segs:
        flat = " ".join(s.split())
        if flat and is_launcher_exec(flat):
            launcher_segs.append(flat)

    segs_field = chr(31).join(launcher_segs)
    sys.stdout.write(rib_norm + "\n" + segs_field + "\n" + cmd)
except Exception:
    pass
' 2>/dev/null || true)"

# Bash-side split: line 1 = RIB, line 2 = SEGS, remainder = CMD.
RIB="${_PARSE_OUT%%$'\n'*}"
_REST="${_PARSE_OUT#*$'\n'}"
SEGS_RAW="${_REST%%$'\n'*}"
CMD="${_REST#*$'\n'}"

# CMD empty → parse failed → fail-open.  (python3 absent → empty → exit 0.)
[[ -z "${CMD:-}" ]] && exit 0

# Override escape hatch (intentionally whole-string: author-intent marker).
printf '%s' "$CMD" | grep -q '# fg-dispatch: allow' && exit 0

# No launcher-execution segment → allow.  This is the F2 fix:
# cat, git log, grep, etc. never execute a launcher.
[[ -z "${SEGS_RAW:-}" ]] && exit 0

# Evaluate each launcher-exec segment.  If ANY segment is unguarded → deny.
# RIB is a tool-level field (global) — applies to all segments.
_DENIED=0
while IFS= read -r -d $'\x1f' _seg; do
  [[ -z "$_seg" ]] && continue
  _allowed=0
  # a. run_in_background == true (tool-level field).
  [[ "${RIB:-}" == "true" ]] && _allowed=1
  # b. --no-spawn / LEADV2_DISPATCH_SPAWN=0.
  [[ $_allowed -eq 0 ]] && printf '%s' "$_seg" | grep -Eq -- '--no-spawn|LEADV2_DISPATCH_SPAWN=0' && _allowed=1
  # c. --help or whole-word -h.
  [[ $_allowed -eq 0 ]] && printf '%s' "$_seg" | grep -Eq -- '--help|(^|[[:space:]])-h([[:space:]]|$)' && _allowed=1
  # d. whole-word status or record-review subcommand.
  [[ $_allowed -eq 0 ]] && printf '%s' "$_seg" | grep -Eq '[[:space:]](status|record-review)([[:space:]]|$)' && _allowed=1
  # e. trailing & (background).
  [[ $_allowed -eq 0 ]] && printf '%s' "$_seg" | grep -Eq '[[:space:]]&[[:space:]]*(#.*)?$' && _allowed=1
  # f. nohup ... &.
  [[ $_allowed -eq 0 ]] && printf '%s' "$_seg" | grep -Eq 'nohup.*&' && _allowed=1
  # g. setsid.
  [[ $_allowed -eq 0 ]] && printf '%s' "$_seg" | grep -Eq 'setsid' && _allowed=1
  # Any unguarded segment → deny.
  if [[ $_allowed -eq 0 ]]; then
    _DENIED=1
    break
  fi
done < <(printf '%s\x1f' "$SEGS_RAW")

[[ $_DENIED -eq 0 ]] && exit 0

# Deny.
cat >&2 <<MSG
[leadv2-block-fg-dispatch] BLOCKED
Foreground invocation of a leadv2 worker launcher — the 2-minute Bash tool timeout
would SIGTERM the process group and silently kill the dispatch mid-flight.
Run this instead:
  ${CMD} &
Override: set LEADV2_ALLOW_FG_DISPATCH=1
MSG

exit 2
