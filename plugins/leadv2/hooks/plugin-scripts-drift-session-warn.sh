#!/usr/bin/env bash
# .claude/hooks/plugin-scripts-drift-session-warn.sh — SessionStart hook.
#
# Single-source sibling of plugin-scripts-drift-guard.sh. The commit guard
# blocks staged regressions; this hook surfaces real plugin-owned files in the
# working tree, including in non-git trees where a commit-time guard cannot run.
#
# Same JSON contract as the other SessionStart hooks in this repo
# (scheduled-decisions-inject.sh, feature-liveness-session-inject.sh):
# emits the nested {"hookSpecificOutput": {"hookEventName": ...,
# "additionalContext": "..."}} shape or "{}", never blocks, never fails
# (SESSIONSTART-HOOKS-DISCARDED-01: a bare top-level {"additionalContext"}
# is silently discarded by the harness for SessionStart).
#
# Scope matches the pre-commit guard exactly: .claude/scripts/*.sh|*.py that
# also exist in canonical (plugins/leadv2/scripts/). Compares WORKING-TREE
# content (not just staged) — a session start should surface all drift,
# committed or not.
set -euo pipefail
trap 'printf "{}"; exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
VENDORED="${PROJECT_ROOT}/.claude/scripts"

# shellcheck source=plugin-scripts-drift-guard.sh
source "${SCRIPT_DIR}/plugin-scripts-drift-guard.sh"

CANONICAL_ROOT="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}"
CANONICAL_SCRIPTS="${CANONICAL_ROOT}/plugins/leadv2/scripts"

if [[ ! -d "$VENDORED" || ! -d "$CANONICAL_SCRIPTS" ]]; then
  printf '{}'
  exit 0
fi

DRIFT_LINES=""
while IFS= read -r -d '' path; do
  relpath="${path#${VENDORED}/}"
  classification="$(plugin_script_classify "$PROJECT_ROOT" "$relpath" filesystem)"
  case "$classification" in
    REGRESSION|DRIFT) DRIFT_LINES+="${classification} .claude/scripts/${relpath}"$'\n' ;;
  esac
done < <(find "$VENDORED" -name node_modules -prune -o -type f \( -name '*.sh' -o -name '*.py' \) -print0)

if [[ -z "$DRIFT_LINES" ]]; then
  printf '{}'
  exit 0
fi

python3 - "$DRIFT_LINES" "SessionStart" <<'PYEOF'
import json, sys

drift_block = sys.argv[1]
event_name = sys.argv[2]
files = [l for l in drift_block.splitlines() if l]
header = (
    f"PLUGIN-SCRIPTS-REGRESSION: {len(files)} real plugin-owned .claude/scripts/ file(s) "
    "exist where symlinks belong. Land intended changes in canonical, then restore "
    "symlinks with leadv2-scripts-symlink-plan.sh. A git tree's staged copies are "
    "blocked by plugin-scripts-drift-guard.sh."
)
body = "\n".join(f"  - {f}" for f in files[:20])
if len(files) > 20:
    body += f"\n  ... and {len(files) - 20} more"
print(json.dumps({"hookSpecificOutput": {"hookEventName": event_name, "additionalContext": header + "\n" + body}}))
PYEOF
