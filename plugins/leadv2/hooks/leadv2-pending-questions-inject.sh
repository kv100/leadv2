#!/usr/bin/env bash
# SessionStart hook — QUESTION-DELIVERY-OWNERSHIP-01: surface unanswered
# control-plane questions older than 10 min with their owner tags so a NEW
# session start also sees them — not only UserPromptSubmit.
#
# THE GAP this closes: the pending-questions delivery fired only on
# UserPromptSubmit (an autonomous lead session with no founder input NEVER
# saw pending questions — starvation). A SessionStart hook fires even when
# the lead resumes autonomously, giving parity with scheduled-decisions
# surfacing. Questions younger than 10 min are left to the existing delivery
# paths (they are not yet "stale"); older ones are injected on session start.
#
# Contract: non-blocking, exit 0 always. stdout = JSON {additionalContext: "..."}.
set -euo pipefail
export PYTHONWARNINGS="ignore::DeprecationWarning"
trap 'exit 0' ERR

INPUT="$(cat 2>/dev/null || true)"

CWD="$(printf -- '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read() or '{}')
    print(d.get('cwd', ''))
except Exception:
    print('')
" 2>/dev/null || true)"
[[ -z "$CWD" ]] && CWD="${CLAUDE_PROJECT_DIR:-${PWD:-}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_PATH_BIN="${SCRIPT_DIR}/../scripts/leadv2-state-path.sh"
[[ -f "$STATE_PATH_BIN" ]] || exit 0

QDIR="$(PROJECT_ROOT="$CWD" bash "$STATE_PATH_BIN" questions 2>/dev/null || true)"
[[ -n "$QDIR" && -d "$QDIR" ]] || exit 0

# Minimum age for a question to be surfaced on session start (default 600s / 10 min).
MIN_AGE="${LEADV2_Q_SESSIONSTART_MIN_AGE_S:-600}"

LEADV2_PQI_QDIR="$QDIR" LEADV2_PQI_MIN_AGE="$MIN_AGE" python3 2>/dev/null <<'PYEOF' || true
import datetime, glob, json, os, sys, yaml

qdir = os.environ.get("LEADV2_PQI_QDIR", "")
min_age = int(os.environ.get("LEADV2_PQI_MIN_AGE", "600"))
if not qdir:
    sys.exit(0)

now = datetime.datetime.utcnow()
stale = []

for fp in sorted(glob.glob(os.path.join(qdir, "*.yaml"))):
    try:
        with open(fp, encoding="utf-8") as f:
            d = yaml.safe_load(f) or {}
    except Exception:
        continue
    if d.get("status") != "pending":
        continue
    asked = d.get("asked_at", "") or ""
    age_s = None
    try:
        dt = datetime.datetime.strptime(asked, "%Y-%m-%dT%H:%M:%SZ")
        age_s = int((now - dt).total_seconds())
    except Exception:
        pass
    # Skip young questions (existing delivery paths handle them) and
    # questions whose age we cannot determine.
    if age_s is None or age_s < min_age:
        continue
    qid = d.get("qid", os.path.basename(fp).replace(".yaml", ""))
    task = d.get("task_id") or d.get("owner_task") or "?"
    owner = d.get("owner_session") or "<untracked>"
    summary = (d.get("summary_for_lead") or d.get("question") or "")[:80]
    stale.append(f"  qid={qid} task={task} age={age_s}s owner={owner} — {summary}")

if not stale:
    sys.exit(0)

msg = (
    "[PENDING_QUESTIONS] %d unanswered question(s) older than %ds:\n%s\n"
    "These questions are waiting for a reply. Use `/leadv2 reply <qid> <option>` "
    "to answer, or check docs/handoff for context." % (len(stale), min_age, "\n".join(stale))
)
print(json.dumps({"additionalContext": msg}))
PYEOF

exit 0
