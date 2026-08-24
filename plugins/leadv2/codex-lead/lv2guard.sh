#!/bin/bash
# lv2guard.sh — Codex-lead bash reimplementation of the CATASTROPHIC-tier
# deny-floor (see plugins/leadv2/hooks/leadv2-deny-floor.sh, the Claude-side
# PreToolUse hook this mirrors). Codex HAS PreToolUse/blocking hooks since
# codex-cli 0.145.0-alpha.1 (verified empirically CODEX-LEAD-PLUGIN-01:
# permissionDecision:deny blocks the tool call; allow = empty output rc 0),
# so this script runs BOTH as a prose-mandated wrapper and, via --check,
# as the decision core of the enforced plugin hook
# marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh.
#
# Deliberate divergences from the canonical hook (CODEX-LEAD-FULL-01 prepass
# §0.3, §2a, CB-1, CB-8):
#   - Fails CLOSED (rc 97) on a missing/unreadable/empty patterns file or a
#     missing python3, where the canonical hook fails open. lv2guard has no
#     sibling guards to fall back on.
#   - Does NOT honor LEADV2_DENY_FLOOR=0. A floor a lead can disable with one
#     env var is no floor.
#   - Honors the yaml's own allow_inline_override tiering (6 CATASTROPHIC +
#     3 SOFT canonical rules), same as the Claude hook, plus 3 codex-lead-only
#     rules in deny-extra.yaml (worktree prune, direct `codex exec`, oversize
#     heredoc advisory) that do not exist in the canonical file.
#
# Usage:
#   lv2guard.sh <command...>                  # argv form; exec replaces this process
#   lv2guard.sh -c '<command string>'         # -c form; required for the
#                                                "# deny-floor: allow" inline token
#   lv2guard.sh --check -c '<command string>' # adjudicate only: NEVER exec; used
#                                                by the Codex PreToolUse adapter
#
# Exit codes:
#   97   refused — reserved; a guarded invocation exiting 97 always means
#        "lv2guard refused", never the wrapped command's own code.
#   2    usage error (no args, or empty -c string)
#   127  command not found (ordinary shell behavior)
#   *    otherwise the wrapped command's own exit code (--check: only 0)
#
# Test seam: LEADV2_CODEX_GUARD_EXEC=<prog> replaces the final exec target
# (e.g. `echo`) so tests can observe what WOULD have run without running it.
# Ignored (never honoured) in --check mode — that mode must not exec anything.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CANON_PATTERNS_FILE="${LEADV2_DENY_PATTERNS_FILE:-$REPO_ROOT/plugins/leadv2/config/leadv2-deny-patterns.yaml}"
EXTRA_PATTERNS_FILE="$SCRIPT_DIR/deny-extra.yaml"
HEREDOC_WARN_BYTES="${LEADV2_CODEX_HEREDOC_WARN_BYTES:-2048}"
MATCH_CAP_BYTES=65536

usage() {
  printf 'usage: lv2guard.sh <command...>\n       lv2guard.sh -c "<command string>"\n       lv2guard.sh --check -c "<command string>"\n' >&2
}

refuse() {
  local rule_name="$1" message="$2"
  printf '[lv2guard] REFUSED: command matches rule '"'"'%s'"'"'.\n%s\n' "$rule_name" "$message" >&2
  exit 97
}

if [[ $# -eq 0 ]]; then
  usage
  exit 2
fi

FORM="argv"
CMDSTR=""
if [[ "$1" == "--check" ]]; then
  FORM="check"
  shift
  if [[ "${1:-}" != "-c" ]]; then
    usage
    exit 2
  fi
fi
if [[ "$1" == "-c" ]]; then
  if [[ "$FORM" != "check" ]]; then
    FORM="c"
  fi
  if [[ $# -lt 2 || -z "${2:-}" ]]; then
    usage
    exit 2
  fi
  CMDSTR="$2"
elif [[ "$FORM" == "check" ]]; then
  # --check was consumed above; anything but -c here is a usage error.
  usage
  exit 2
fi

if [[ "$FORM" == "argv" ]]; then
  MATCH_STRING="$*"
else
  MATCH_STRING="$CMDSTR"
fi

# CB-7 / R-2: normalise $HOME -> ~ before matching so rm_rf_home catches the
# literal expanded path too (the shell expands $HOME before we ever see it).
if [[ -n "${HOME:-}" ]]; then
  MATCH_STRING="${MATCH_STRING//$HOME/~}"
fi

# CB-3: cap the string used for MATCHING only; the real command still runs
# in full — refusing a long-but-legitimate command would take down more than
# the operation it belongs to.
MATCH_FOR_REGEX="$MATCH_STRING"
if [[ ${#MATCH_FOR_REGEX} -gt $MATCH_CAP_BYTES ]]; then
  MATCH_FOR_REGEX="${MATCH_FOR_REGEX:0:$MATCH_CAP_BYTES}"
  printf '[lv2guard] warning: command exceeds %d bytes; matching only the first %d.\n' "$MATCH_CAP_BYTES" "$MATCH_CAP_BYTES" >&2
fi

# CB-6: the inline override token is only honored in string forms (-c and
# --check -c, which share the same string). In argv form the token would
# just be a literal argument to the wrapped command.
HAS_INLINE_ALLOW=0
if [[ "$FORM" != "argv" ]] && printf '%s' "$MATCH_STRING" | grep -q '# deny-floor: allow'; then
  HAS_INLINE_ALLOW=1
fi

if ! [[ "$HEREDOC_WARN_BYTES" =~ ^[0-9]+$ ]]; then
  printf '[lv2guard] warning: LEADV2_CODEX_HEREDOC_WARN_BYTES=%s is not numeric; using default 2048.\n' "$HEREDOC_WARN_BYTES" >&2
  HEREDOC_WARN_BYTES=2048
fi

# --- fail-closed prerequisites ----------------------------------------------
command -v python3 >/dev/null 2>&1 || refuse "python3_missing" "python3 is required to evaluate deny rules and is not on PATH — failing closed."
[[ -r "$CANON_PATTERNS_FILE" ]] || refuse "patterns_file_missing" "Canonical deny patterns file is missing or unreadable at $CANON_PATTERNS_FILE — failing closed."
[[ -r "$EXTRA_PATTERNS_FILE" ]] || refuse "extra_patterns_file_missing" "codex-lead deny-extra.yaml is missing or unreadable at $EXTRA_PATTERNS_FILE — failing closed."

# --- worktree-prune predicate: fail closed for THIS rule only on a bad
# active.yaml; every other command must be unaffected (CB-4 blast radius).
worktree_prune_active_lanes() {
  local rule_name="$1" message="$2"
  local resolver="$SCRIPT_DIR/../scripts/leadv2-state-path.sh"
  if [[ ! -r "$resolver" ]]; then
    refuse "$rule_name" "Cannot resolve active.yaml (state-path resolver missing at $resolver) — failing closed for this prune only. $message"
  fi
  local active_yaml
  active_yaml="$(bash "$resolver" --no-link active.yaml 2>/dev/null)"
  if [[ -z "$active_yaml" ]]; then
    refuse "$rule_name" "Cannot resolve active.yaml path — failing closed for this prune only. $message"
  fi
  if [[ ! -f "$active_yaml" ]]; then
    return 0
  fi
  local result
  result="$(python3 - "$active_yaml" <<'PYEOF'
import sys
path = sys.argv[1]
try:
    import yaml
    with open(path) as f:
        data = yaml.safe_load(f) or {}
    sessions = data.get('sessions') or []
    ids = [str(s.get('task_id', '?')) for s in sessions if isinstance(s, dict)]
    print('OK|' + ','.join(ids[:3]) + '|' + str(len(sessions)))
except Exception as e:
    print('MALFORMED|' + str(e)[:80])
PYEOF
)"
  if [[ "$result" == MALFORMED* ]]; then
    refuse "$rule_name" "active.yaml is malformed (${result#MALFORMED|}) — cannot prove no lane is active, failing closed for this prune only. $message"
  fi
  local status ids count
  IFS='|' read -r status ids count <<< "$result"
  if [[ "${count:-0}" -gt 0 ]]; then
    refuse "$rule_name" "Active lane(s) registered: ${ids} — $message"
  fi
  return 0
}

# --- heredoc-size predicate: advisory only, never refuses -------------------
heredoc_oversize() {
  local rule_name="$1" message="$2"
  local len=${#MATCH_STRING}
  if [[ $len -gt $HEREDOC_WARN_BYTES ]]; then
    printf '[lv2guard] warning: heredoc-bearing command is %d bytes (advisory threshold %d) — %s\n' "$len" "$HEREDOC_WARN_BYTES" "$message" >&2
  fi
  return 0
}

# --- match canonical + extra rules ------------------------------------------
# Mirrors leadv2-deny-floor.sh's line-based parse + re.search(..., IGNORECASE);
# a single bad regex is skipped, not fatal to the rest of the rule set.
HIT="$(python3 - "$MATCH_FOR_REGEX" "$CANON_PATTERNS_FILE" "$EXTRA_PATTERNS_FILE" <<'PYEOF'
import re, sys

cmd, canon_file, extra_file = sys.argv[1], sys.argv[2], sys.argv[3]


def parse_rules(path):
    try:
        with open(path, 'r') as f:
            lines = f.readlines()
    except Exception:
        return None
    rules = []
    cur = {}
    for raw in lines:
        s = raw.strip()
        if s.startswith('- name:'):
            if cur.get('name'):
                rules.append(cur)
            cur = {'name': s.split(':', 1)[1].strip().strip('"\'')}
        elif s.startswith('kind:') and cur:
            cur['kind'] = s.split(':', 1)[1].strip().strip('"\'')
        elif s.startswith('predicate:') and cur:
            cur['predicate'] = s.split(':', 1)[1].strip().strip('"\'')
        elif s.startswith('regex:') and cur:
            v = s.split(':', 1)[1].strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
                v = v[1:-1]
            cur['regex'] = v
        elif s.startswith('enabled:') and cur:
            cur['enabled'] = s.split(':', 1)[1].strip().lower() == 'true'
        elif s.startswith('allow_inline_override:') and cur:
            cur['allow_inline_override'] = s.split(':', 1)[1].strip().lower() == 'true'
        elif s.startswith('message:') and cur:
            v = s.split(':', 1)[1].strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
                v = v[1:-1]
            cur['message'] = v
    if cur.get('name'):
        rules.append(cur)
    return rules


canon = parse_rules(canon_file)
if canon is None or len(canon) == 0:
    print('__FAILCLOSED__canon')
    sys.exit(0)

extra = parse_rules(extra_file)
if extra is None or len(extra) == 0:
    print('__FAILCLOSED__extra')
    sys.exit(0)

all_rules = []
for r in canon:
    r.setdefault('kind', 'regex')
    all_rules.append(r)
for r in extra:
    kind = r.get('kind', 'regex')
    if kind not in ('regex', 'predicate'):
        print("[lv2guard] warning: rule '%s' has unknown kind '%s' - skipped" % (r.get('name'), kind), file=sys.stderr)
        continue
    all_rules.append(r)

for r in all_rules:
    if not r.get('enabled', False):
        continue
    regex = r.get('regex')
    if not regex:
        continue
    try:
        if re.search(regex, cmd, re.IGNORECASE):
            allow = 'true' if r.get('allow_inline_override', False) else 'false'
            kind = r.get('kind', 'regex').upper()
            print(kind + '|' + r.get('name', 'unknown') + '|' + r.get('predicate', '') + '|' + allow + '|' + r.get('message', 'Blocked by lv2guard.'))
            sys.exit(0)
    except re.error:
        continue
PYEOF
)"

if [[ "$HIT" == "__FAILCLOSED__canon" ]]; then
  refuse "patterns_file_missing" "Canonical deny patterns file at $CANON_PATTERNS_FILE is unreadable or has zero rules — failing closed."
fi
if [[ "$HIT" == "__FAILCLOSED__extra" ]]; then
  refuse "extra_patterns_file_missing" "codex-lead deny-extra.yaml at $EXTRA_PATTERNS_FILE is unreadable or has zero rules — failing closed."
fi

if [[ -n "$HIT" ]]; then
  IFS='|' read -r KIND RULE_NAME PREDICATE_NAME ALLOW_OVERRIDE MESSAGE <<< "$HIT"
  if [[ "$KIND" == "PREDICATE" ]]; then
    case "$PREDICATE_NAME" in
      worktree_prune_active_lanes) worktree_prune_active_lanes "$RULE_NAME" "$MESSAGE" ;;
      heredoc_oversize) heredoc_oversize "$RULE_NAME" "$MESSAGE" ;;
      *) printf '[lv2guard] warning: unknown predicate "%s" for rule "%s" — skipped\n' "$PREDICATE_NAME" "$RULE_NAME" >&2 ;;
    esac
  else
    if [[ "$HAS_INLINE_ALLOW" == "1" && "$ALLOW_OVERRIDE" == "true" ]]; then
      :
    else
      refuse "$RULE_NAME" "$MESSAGE"
    fi
  fi
fi

# --- no refusal: execute (or, in --check mode, just allow) -------------------
if [[ "$FORM" == "check" ]]; then
  exit 0
fi
if [[ "$FORM" == "argv" ]]; then
  if [[ -n "${LEADV2_CODEX_GUARD_EXEC:-}" ]]; then
    exec "$LEADV2_CODEX_GUARD_EXEC" "$@"
  fi
  exec "$@"
else
  if [[ -n "${LEADV2_CODEX_GUARD_EXEC:-}" ]]; then
    exec "$LEADV2_CODEX_GUARD_EXEC" "$CMDSTR"
  fi
  exec bash -c "$CMDSTR"
fi

printf '%s: command not found\n' "$(basename "$0")" >&2
exit 127
