#!/usr/bin/env bash
# PreToolUse:Bash dispatcher.  Keep this fail-open: a dispatcher failure must
# never prevent a Bash call; deliberate guard blocks (exit 2) still win.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0

# Parse only the dispatch key here; each selected guard receives the same input.
COMMAND="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    print((json.load(sys.stdin).get("tool_input") or {}).get("command") or "")
except Exception:
    pass
' 2>/dev/null || true)"
[[ -n "$COMMAND" ]] || exit 0

STDOUT_FILE="$(mktemp "${TMPDIR:-/tmp}/leadv2-bash-pre-out.XXXXXX" 2>/dev/null || true)"
STDERR_FILE="$(mktemp "${TMPDIR:-/tmp}/leadv2-bash-pre-err.XXXXXX" 2>/dev/null || true)"
[[ -n "$STDOUT_FILE" && -n "$STDERR_FILE" ]] || {
  [[ -n "$STDOUT_FILE" ]] && rm -f "$STDOUT_FILE"
  [[ -n "$STDERR_FILE" ]] && rm -f "$STDERR_FILE"
  exit 0
}
FIRST_STDOUT_FILE="$(mktemp "${TMPDIR:-/tmp}/leadv2-bash-pre-first.XXXXXX" 2>/dev/null || true)"
[[ -n "$FIRST_STDOUT_FILE" ]] || {
  rm -f "$STDOUT_FILE" "$STDERR_FILE"
  exit 0
}
trap 'rm -f "$STDOUT_FILE" "$STDERR_FILE" "$FIRST_STDOUT_FILE"' EXIT HUP INT TERM

# Manifest format: script|ERE trigger.  ALWAYS is reserved for guards whose
# command cannot be safely prefiltered.  Exit-2 guards precede stdout-JSON
# guards; deny-only JSON guards precede the two guards that always emit allow
# JSON.  Every matching guard still runs so a later exit 2 takes precedence,
# while only the first non-empty stdout result is retained.
#
# leadv2-deny-floor.sh: ALWAYS — enabled regexes are dynamically loaded from
# YAML (leadv2-deny-floor.sh:92-105).
# leadv2-block-bash-heredoc.sh: after length/override exits, a heredoc token
# is the command predicate (leadv2-block-bash-heredoc.sh:22-28).
# leadv2-block-fg-dispatch.sh: guarded launcher names (leadv2-block-fg-dispatch.sh:35-41).
# leadv2-codex-round-cap.sh: codex-task adversarial launch (leadv2-codex-round-cap.sh:24).
# leadv2-codex-nopoll-guard.sh: codex-task status only (leadv2-codex-nopoll-guard.sh:30-31).
# leadv2-close-ritual-guard.sh: git commit only (leadv2-close-ritual-guard.sh:29-30).
# leadv2-context-glossary-close.sh: git commit only (leadv2-context-glossary-close.sh:45-46).
# leadv2-codex-direct-exec-guard.sh: standalone codex exec (leadv2-codex-direct-exec-guard.sh:45-47).
# leadv2-bash-lint-pre-gate.sh: git commit only (leadv2-bash-lint-pre-gate.sh:58-65).
# leadv2-env-audit-pre-gate.sh: ALWAYS — unconditional placeholder (leadv2-env-audit-pre-gate.sh:1-6).
# leadv2-schema-audit-pre-gate.sh: git commit only (leadv2-schema-audit-pre-gate.sh:80-86).
# leadv2-warn-bash-diff-read.sh: diff/patch path or unsummarized git diff/show (advisory
# stdout JSON by default; LEADV2_DIFF_READ_DENY=1 upgrades to exit-2 block). Last in the
# manifest so it can never pre-empt another guard's stdout JSON (only the first is kept).
MANIFEST='leadv2-deny-floor.sh|ALWAYS
leadv2-block-bash-heredoc.sh|<<-?[[:space:]]*
leadv2-block-fg-dispatch.sh|leadv2-dispatch-code\.sh|leadv2-codex-session-runner\.sh|leadv2-fanout\.sh|glm-coder\.sh|omp-task\.sh
leadv2-codex-direct-exec-guard.sh|(^|[^A-Za-z0-9_/.-])codex[[:space:]]+exec([[:space:]]|$)
leadv2-codex-round-cap.sh|codex-task\.sh[[:space:]].*adversarial
leadv2-codex-nopoll-guard.sh|codex-task\.sh[[:space:]]+status
leadv2-close-ritual-guard.sh|^git[[:space:]]+commit
leadv2-context-glossary-close.sh|^git[[:space:]]+commit
leadv2-bash-lint-pre-gate.sh|git[[:space:]]+commit
leadv2-env-audit-pre-gate.sh|ALWAYS
leadv2-schema-audit-pre-gate.sh|git[[:space:]]+commit
leadv2-warn-bash-diff-read.sh|\.(diff|patch)([[:space:]]|"|'"'"'|$)|(^|[^A-Za-z0-9_-])git[[:space:]]+(diff|show)([[:space:]]|$)'

HAVE_STDOUT=0

while IFS='|' read -r SCRIPT TRIGGER; do
  [[ -n "$SCRIPT" ]] || continue
  if [[ "$TRIGGER" != "ALWAYS" && ! "$COMMAND" =~ $TRIGGER ]]; then
    continue
  fi
  [[ -x "$SCRIPT_DIR/$SCRIPT" ]] || continue
  [[ "${LEADV2_DISPATCH_TRACE:-0}" == "1" ]] && printf '%s\n' "$SCRIPT" >&2

  : > "$STDOUT_FILE"
  : > "$STDERR_FILE"
  printf '%s' "$INPUT" | "$SCRIPT_DIR/$SCRIPT" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  RC=$?

  # Runner-side verdict record (GUARD-CENSUS-IS-WRONG-01): most guards routed
  # through this dispatcher never call hooks/lib/leadv2-guard-verdict.sh
  # themselves, so the census sees zero "ran" evidence and calls a guard that
  # fires every day "never-ran". Recording once, HERE, at the one place every
  # dispatched guard's exit is already observed, gets ran/fired evidence for
  # all of them without editing each guard file. Best-effort, never fatal.
  {
    _lv2_gv_dir="${LEADV2_GUARD_VERDICT_DIR:-${CLAUDE_PROJECT_DIR:-$HOME}/.claude/cache/guard-verdicts}"
    mkdir -p "$_lv2_gv_dir" 2>/dev/null
    _lv2_gv_ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown-ts)"
    printf '%s\t%s\t%s\t%s\t%s\n' "$_lv2_gv_ts" "$SCRIPT" "PreToolUse" "ran" "-" \
      >> "$_lv2_gv_dir/journal.tsv"
    _lv2_gv_kind="log"
    if [[ "$RC" -eq 2 ]] || grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' "$STDOUT_FILE" 2>/dev/null; then
      _lv2_gv_kind="block"
    elif [[ ! -s "$STDOUT_FILE" && ! -s "$STDERR_FILE" ]]; then
      _lv2_gv_kind="allow"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$_lv2_gv_ts" "$SCRIPT" "PreToolUse" "verdict" "$_lv2_gv_kind" \
      >> "$_lv2_gv_dir/journal.tsv"
  } 2>/dev/null || true

  if [[ "$RC" -eq 2 ]]; then
    cat "$STDERR_FILE" >&2
    exit 2
  fi
  if [[ "$HAVE_STDOUT" -eq 0 && -s "$STDOUT_FILE" ]]; then
    # A guard may accidentally mix diagnostics into stdout.  Retain the whole
    # stream when it is JSON, otherwise retain its first valid JSON line.
    python3 - "$STDOUT_FILE" >"$FIRST_STDOUT_FILE" 2>/dev/null <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        raw = fh.read()
except Exception:
    sys.exit(1)

candidates = [raw] + raw.splitlines(keepends=True)
for candidate in candidates:
    if not candidate.strip():
        continue
    try:
        json.loads(candidate)
    except Exception:
        continue
    sys.stdout.write(candidate)
    sys.exit(0)
sys.exit(1)
PY
    if [[ "$?" -eq 0 && -s "$FIRST_STDOUT_FILE" ]]; then
      HAVE_STDOUT=1
    else
      : > "$FIRST_STDOUT_FILE"
    fi
  fi
done <<EOF
$MANIFEST
EOF

if [[ "$HAVE_STDOUT" -eq 1 ]]; then
  cat "$FIRST_STDOUT_FILE" 2>/dev/null || true
fi
exit 0
