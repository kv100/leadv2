#!/usr/bin/env bash
# .claude/hooks/learn-trigger-inject.sh — SessionStart hook
# (PLUGIN-LEARN-LOOP-WRITE-ONLY-01 fix).
#
# Pattern-copy of .claude/hooks/scheduled-decisions-inject.sh (same hook JSON
# contract: emits {"additionalContext": "..."} or "{}", never blocks, never
# fails). leadv2-phase8-close.sh writes docs/leadv2/.learn-trigger every Nth
# close (shared, DO NOT EDIT from here). Nothing previously READ that trigger.
# This hook is the missing reader: when the durable trigger is present at
# session start, it surfaces a single-line reminder telling the lead to run the
# leadv2-learn workflow this session, then consume the trigger via
# .claude/scripts/leadv2-learn-consume.sh.
#
# This hook does NOT run leadv2-learn and does NOT write learn-history.yaml
# (that is leadv2-learn-consume.sh, invoked by the lead AFTER the workflow).
# Pure file inspection — offline, <1s, zero network calls.
#
# Fail-safe: trigger missing / unreadable -> emits `{}` (byte-identical to
# no-hook). Exit 0 always — never blocks session start.
set -euo pipefail
trap 'printf "{}"; exit 0' ERR

# Resolve durable root the same way leadv2-phase8-close.sh does: the one .git
# shared by every worktree (so the trigger written from any worktree is seen
# here), falling back to CLAUDE_PROJECT_DIR / pwd outside a repo.
_resolve_durable_root() {
  local dr
  dr="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | xargs dirname 2>/dev/null || true)"
  if [[ -d "$dr" ]]; then
    printf -- '%s' "$dr"
  else
    printf -- '%s' "${CLAUDE_PROJECT_DIR:-$(pwd)}"
  fi
}

DURABLE_ROOT="$(_resolve_durable_root)"
TRIGGER="${DURABLE_ROOT}/docs/leadv2/.learn-trigger"

if [[ ! -f "$TRIGGER" ]]; then
  printf '{}'
  exit 0
fi

# Parse trigger fields via grep (string-preserving; avoids YAML datetime
# coercion of triggered_at). One-line, no python import cost.
_field() {
  grep -E "^${1}:" "$TRIGGER" 2>/dev/null | head -1 | sed -E 's/^[^:]+:[[:space:]]*//' || true
}
CC="$(_field trigger_close_count)"
TS="$(_field triggered_at)"
[[ -z "$CC" ]] && CC="?"
[[ -z "$TS" ]] && TS="?"

LINE="[LEARN_TRIGGER_PENDING] docs/leadv2/.learn-trigger present (close_count=${CC}, triggered_at=${TS}) — run Workflow(name=\"leadv2-learn\") this session, then: bash .claude/scripts/leadv2-learn-consume.sh <label>"

# Emit hook JSON. The reminder contains double-quotes (Workflow name), so use
# json.dumps to escape rather than hand-building the JSON string.
python3 -c 'import json, sys; print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": sys.argv[1]}}))' "$LINE"
exit 0
