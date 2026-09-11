#!/usr/bin/env bash
# .claude/hooks/scheduled-decisions-inject.sh — SessionStart hook
# (Deferred-actions hard rule, .claude/CLAUDE.md §"Deferred actions").
#
# Pattern-copy of .claude/hooks/anti-silence-pulse-arm-inject.sh's nested
# {"hookSpecificOutput": {"hookEventName": ..., "additionalContext": ...}}
# JSON contract (SESSIONSTART-HOOKS-DISCARDED-01: the harness silently
# discards a bare top-level {"additionalContext": ...} for SessionStart --
# see ANTI-SILENCE-HOOK-SCHEMA-AND-KEY-01). Emits the nested shape or "{}",
# never blocks, never fails. Reads docs/leadv2/scheduled-decisions.md and, for every row
# under "## OPEN" whose Due has arrived (a parseable date in the past) or
# whose Due is condition-bound (not a fixed date — always surfaced, since we
# cannot tell offline whether the condition has cleared), prints a compact,
# visually unmissable block at session start.
#
# This hook does NOT evaluate GO-conditions against Supabase (that's
# scripts/scheduled-decisions-run.sh on the VPS, the layer that actually
# guarantees the action happens without a session). This hook is pure text
# parsing of the ledger — offline, <300ms, zero network calls.
#
# Fail-safe: file missing / malformed / zero OPEN rows -> emits `{}`
# (byte-identical to no-hook).
#
# Exit 0 always — never blocks session start.
set -euo pipefail
trap 'printf "{}"; exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
LEDGER="${PROJECT_ROOT}/docs/leadv2/scheduled-decisions.md"

if [[ ! -f "$LEDGER" ]]; then
  printf '{}'
  exit 0
fi

# Emits additionalContext JSON from a pre-rendered block of lines (arg1, may
# be empty). Passed via argv (not interpolated into python source) since the
# lines come from ledger parsing and must never be treated as code.
_emit() {
  python3 - "$1" "$2" <<'PYEOF'
import json, sys
block = sys.argv[1]
event_name = sys.argv[2]
if not block:
    print("{}")
else:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": event_name, "additionalContext": block}}))
PYEOF
}

# Parse the ledger: scan the WHOLE document (not a "## OPEN" .. "## CLOSED"
# positional slice — SCAN-SCOPE-01 proved that boundary can't survive a doc
# that only ever grows at the bottom) for each "##"/"###" row, gate on the
# row's OWN self-declared status (title contains CLOSED/OBSOLETE/SUPERSEDED
# -> skip), extract the Due / GO-condition / Action / Rollback fields across
# all three filing eras (pipe-table, bullet, bold-paragraph), then classify
# OVERDUE vs CONDITION-BOUND vs not-yet-due (silently skipped). Never raises
# — any parse failure on a single row degrades that row to skipped, not a
# hook crash (the ERR trap above is the final backstop). Grammar copied
# verbatim from scripts/scheduled-decisions-run.sh (LEDGER-HOOK-PARSER-01).
block="$(python3 - "$LEDGER" <<'PYEOF' 2>/dev/null
import re, sys, datetime

path = sys.argv[1]
try:
    content = open(path, encoding="utf-8").read()
except Exception:
    print("")
    raise SystemExit(0)

CLOSED_TITLE_RE = re.compile(r"\b(CLOSED|OBSOLETE|SUPERSEDED)\b", re.IGNORECASE)

rows = re.split(r"(?=^#{2,3} )", content, flags=re.MULTILINE)
today = datetime.date.today()
lines = []

for row in rows:
    hm = re.match(r"^#{2,3} (\S+)\s+—\s+(.+?)\s*$", row, re.MULTILINE)
    if not hm:
        continue
    row_id, title = hm.group(1), hm.group(2)

    if CLOSED_TITLE_RE.search(title):
        continue

    fields = {}
    for fm in re.finditer(r"^\|\s*\*\*(.+?)\*\*\s*\|\s*(.*?)\s*\|\s*$", row, re.MULTILINE):
        fields[fm.group(1).strip().lower()] = fm.group(2).strip()
    for fm in re.finditer(r"^-\s*\*\*(.+?)[:.]\*\*\s*(.*?)\s*$", row, re.MULTILINE):
        key = fm.group(1).strip().lower()
        fields.setdefault(key, fm.group(2).strip())
    for fm in re.finditer(r"^\*\*(.+?)[:.]\*\*\s*(.*?)\s*$", row, re.MULTILINE):
        key = fm.group(1).strip().lower()
        fields.setdefault(key, fm.group(2).strip())

    due_raw = fields.get("due", "")
    go = fields.get("go-condition", "")
    action = fields.get("action", "")
    rollback = fields.get("rollback", "")

    date_m = re.search(r"\b(\d{4}-\d{2}-\d{2})(?!\d)", due_raw)
    status = None
    detail = due_raw
    if date_m:
        try:
            due_date = datetime.date.fromisoformat(date_m.group(1))
        except ValueError:
            due_date = None
        if due_date is not None and due_date <= today:
            days = (today - due_date).days
            status = "OVERDUE" if days > 0 else "DUE TODAY"
            detail = f"{due_raw} ({days}d overdue)" if days > 0 else due_raw
    elif due_raw:
        # No fixed date at all -> condition-bound; always surface since an
        # offline hook cannot know whether the condition has cleared.
        status = "CONDITION-BOUND"

    if status is None:
        continue

    line = f"[{status}] {row_id} — {title} | Due: {detail}"
    if go:
        line += f" | GO: {go[:160]}"
    if action:
        line += f" | Action: {action[:120]}"
    if rollback:
        line += f" | Rollback: {rollback[:80]}"
    lines.append(line)

# SD-INJECT-CAP-01 (2026-08-24, founder order): this hook was emitting ~22KB
# into the top of EVERY session — 100+ rows, most of them 8-25 days overdue and
# unactionable. A ledger nobody can read is the same as no ledger, and it was
# crowding out the actual task. Cap the printed rows; the count line keeps the
# rest honest and the file itself is one Read away.
import os
try:
    CAP = int(os.environ.get("PE_SD_INJECT_MAX", "8"))
except ValueError:
    CAP = 8

if not lines:
    print("")
else:
    total = len(lines)
    shown = lines if (CAP <= 0 or total <= CAP) else lines[:CAP]
    header = "SCHEDULED-DECISIONS: {} row(s) due/condition-bound — see docs/leadv2/scheduled-decisions.md".format(total)
    out = header + "\n" + "\n".join(shown)
    if len(shown) < total:
        out += "\n(+{} more rows not shown — PE_SD_INJECT_MAX={})".format(total - len(shown), CAP)
    print(out)
PYEOF
)" || block=""

_emit "$block" "SessionStart"
exit 0
