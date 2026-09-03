#!/usr/bin/env bash
# PreToolUse:Bash — warn (default) or block (LEADV2_DIFF_READ_DENY=1) when a Bash command
# pulls a diff-shaped artifact (unbounded, or a bounded window past LEADV2_DIFF_READ_MAX_LINES)
# into the transcript. Measured worst case: the same review.diff read twice via `sed -n` at
# ~7.4K tokens each, re-sent on every later turn.
#
# Advisory by default: warn emits stdout allow-JSON with additionalContext (the dispatcher only
# forwards stdout on a non-exit-2 rc — stderr on a non-block path is read by nobody). Deny (rc 2)
# still uses stderr, matching every other guard in this dispatcher.
# LEADV2_DIFF_READ_GUARD=0 disables entirely. LEADV2_DIFF_READ_DENY=1 upgrades warn to block.
# LEADV2_DIFF_READ_MAX_LINES (default 200) is the bounded-read cap.
#
# Fail-open: empty/non-JSON stdin, missing python3, or any parse error → silent, exit 0.
set -euo pipefail
trap 'echo "[$(basename "$0")] error at line $LINENO" >&2; exit 0' ERR

[[ "${LEADV2_DIFF_READ_GUARD:-}" == "0" ]] && exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

export LV2_DIFF_READ_MAX_LINES="${LEADV2_DIFF_READ_MAX_LINES:-200}"

DECISION="$(printf '%s' "$INPUT" | python3 -c '
import sys, json, os, re, shlex

def env_int(name, default):
    v = os.environ.get(name, "")
    if v == "":
        return default
    try:
        n = int(v)
    except Exception:
        return default
    if n < 0:
        return default
    return n

MAX_LINES = env_int("LV2_DIFF_READ_MAX_LINES", 200)

SQ = chr(39)
DQ = chr(34)

def split_clauses(cmd):
    # Split on unquoted ;  &&  ||  and newline — compound-command boundaries.
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
            if c == "\\" and i + 1 < n:
                cur.append(cmd[i + 1])
                i += 2
                continue
            if c == DQ:
                dq_on = False
            i += 1
            continue
        if c == SQ:
            cur.append(c); sq_on = True; i += 1; continue
        if c == DQ:
            cur.append(c); dq_on = True; i += 1; continue
        if c == "\\" and i + 1 < n:
            cur.append(c); cur.append(cmd[i + 1]); i += 2; continue
        two = cmd[i:i + 2]
        if two in ("&&", "||"):
            segs.append("".join(cur)); cur = []; i += 2; continue
        if c in (";", "\n"):
            segs.append("".join(cur)); cur = []; i += 1; continue
        cur.append(c); i += 1
    segs.append("".join(cur))
    return segs

def split_pipes(seg):
    # Split a clause on unquoted single "|" (not "||", already resolved at clause level).
    segs = []
    cur = []
    i = 0
    n = len(seg)
    sq_on = False
    dq_on = False
    while i < n:
        c = seg[i]
        if sq_on:
            cur.append(c)
            if c == SQ:
                sq_on = False
            i += 1
            continue
        if dq_on:
            cur.append(c)
            if c == "\\" and i + 1 < n:
                cur.append(seg[i + 1])
                i += 2
                continue
            if c == DQ:
                dq_on = False
            i += 1
            continue
        if c == SQ:
            cur.append(c); sq_on = True; i += 1; continue
        if c == DQ:
            cur.append(c); dq_on = True; i += 1; continue
        if c == "\\" and i + 1 < n:
            cur.append(c); cur.append(seg[i + 1]); i += 2; continue
        if c == "|" and seg[i:i + 2] != "||":
            segs.append("".join(cur)); cur = []; i += 1; continue
        cur.append(c); i += 1
    segs.append("".join(cur))
    return segs

def has_redirect(seg):
    # A bare unquoted ">" anywhere in the clause means the stage writes to a file,
    # not the transcript — silent regardless of what it reads.
    i = 0
    n = len(seg)
    sq_on = False
    dq_on = False
    while i < n:
        c = seg[i]
        if sq_on:
            if c == SQ:
                sq_on = False
            i += 1
            continue
        if dq_on:
            if c == "\\" and i + 1 < n:
                i += 2
                continue
            if c == DQ:
                dq_on = False
            i += 1
            continue
        if c == SQ:
            sq_on = True; i += 1; continue
        if c == DQ:
            dq_on = True; i += 1; continue
        if c == "\\" and i + 1 < n:
            i += 2
            continue
        if c == ">":
            return True
        i += 1
    return False

def strip_quotes(tok):
    if len(tok) >= 2 and tok[0] == tok[-1] and tok[0] in (SQ, DQ):
        return tok[1:-1]
    return tok

def tokenize(seg):
    try:
        return shlex.split(seg)
    except ValueError:
        return seg.split()

WRAPPERS = {"nohup", "setsid", "env", "command", "exec", "time", "sudo"}
VAR_RE = re.compile("^[A-Za-z_][A-Za-z0-9_]*=")
DIFF_PATH_RE = re.compile(r"\.(diff|patch)$")
SUMMARY_FLAGS = {"--stat", "--numstat", "--shortstat", "--name-only", "--name-status", "-s"}
NON_READER = {
    "wc", "ls", "stat", "find", "test", "[", "du", "shasum", "md5", "md5sum",
    "basename", "dirname", "rm", "cp", "mv", "touch", "chmod", "echo", "printf",
    "diffstat", "repowise",
}

def stage_head(stage):
    toks = tokenize(stage)
    j = 0
    while j < len(toks) and VAR_RE.match(toks[j]):
        j += 1
    while j < len(toks) and os.path.basename(toks[j]) in WRAPPERS:
        j += 1
    if j >= len(toks):
        return None, []
    return os.path.basename(toks[j]), toks[j:]

def is_git_diffshow_unsummarized(toks):
    if not toks or os.path.basename(toks[0]) != "git":
        return False
    if len(toks) < 2 or toks[1] not in ("diff", "show"):
        return False
    rest = set(toks[2:])
    return not (rest & SUMMARY_FLAGS)

def is_diff_shaped(stages):
    for stage in stages:
        for tok in tokenize(stage):
            if DIFF_PATH_RE.search(strip_quotes(tok)):
                return True
    for stage in stages:
        _, toks = stage_head(stage)
        if is_git_diffshow_unsummarized(toks):
            return True
    return False

def bounded_window(head, toks):
    if head in ("head", "tail"):
        i = 1
        while i < len(toks):
            t = toks[i]
            if t.startswith("-") and t[1:].isdigit():
                return int(t[1:])
            if t == "-n" and i + 1 < len(toks) and toks[i + 1].lstrip("-").isdigit():
                return int(toks[i + 1].lstrip("-"))
            i += 1
        return 10
    if head == "sed":
        for t in toks[1:]:
            m = re.match(r"^(\d+),(\d+)p?$", strip_quotes(t))
            if m:
                a, b = int(m.group(1)), int(m.group(2))
                return max(0, b - a + 1)
        return None
    if head == "grep":
        i = 1
        while i < len(toks):
            t = toks[i]
            if t == "-m" and i + 1 < len(toks) and toks[i + 1].isdigit():
                return int(toks[i + 1])
            if t.startswith("-m") and t[2:].isdigit():
                return int(t[2:])
            i += 1
        return None
    return None

def classify(head, toks):
    if head is None or head in NON_READER:
        return ("silent", None)
    if head == "grep":
        flags = set()
        for t in toks[1:]:
            if t.startswith("-") and not t.startswith("--"):
                flags.update(t[1:])
        if flags & {"c", "q", "l", "L"}:
            return ("silent", None)
        w = bounded_window(head, toks)
        return ("bounded", w) if w is not None else ("unbounded", None)
    if head == "git":
        sub = toks[1] if len(toks) > 1 else ""
        if sub in ("apply", "add"):
            return ("silent", None)
        if sub in ("diff", "show"):
            if is_git_diffshow_unsummarized(toks):
                return ("unbounded", None)
            return ("silent", None)
        return ("silent", None)
    if head in ("head", "tail", "sed"):
        w = bounded_window(head, toks)
        return ("bounded", w) if w is not None else ("unbounded", None)
    if head in ("cat", "less", "more", "bat", "awk", "perl"):
        return ("unbounded", None)
    return ("silent", None)

try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)

if (data.get("agent_type") or ""):
    sys.exit(0)

ti = data.get("tool_input") or {}
cmd = ti.get("command") or ""
if not cmd.strip():
    sys.exit(0)

fired = False
for clause in split_clauses(cmd):
    if not clause.strip() or has_redirect(clause):
        continue
    stages = split_pipes(clause)
    if not is_diff_shaped(stages):
        continue
    head, toks = stage_head(stages[-1])
    kind, window = classify(head, toks)
    if kind == "unbounded":
        fired = True
        break
    if kind == "bounded" and window is not None and window > MAX_LINES:
        fired = True
        break

if fired:
    sys.stdout.write("FIRE")
' 2>/dev/null || true)"

[[ "$DECISION" == "FIRE" ]] || exit 0

MSG='[leadv2-warn-bash-diff-read] this pulls a whole diff into the conversation (measured: 7.4K tokens, re-sent every later turn).
Cheaper, in order: `git diff --stat` -> the handoff dir'"'"'s review-findings.json -> `repowise distill <cmd>`.
`repowise expand <ref>` recovers what was elided — never re-run the command to see it.'

if [[ "${LEADV2_DIFF_READ_DENY:-}" == "1" ]]; then
  printf '%s\n' "$MSG" >&2
  exit 2
fi

MSG_TEXT="$MSG" python3 -c '
import json, os
out = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "additionalContext": os.environ.get("MSG_TEXT", ""),
    }
}
print(json.dumps(out))
'

exit 0
