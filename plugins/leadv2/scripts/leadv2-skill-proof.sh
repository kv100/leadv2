#!/usr/bin/env bash
# leadv2-skill-proof.sh — the skill Definition-of-Done proof gate.
#
# Discovers every skill under $SKILLS_DIR, checks for a sibling PROOF.sh,
# validates it against mechanical tautology rules, executes valid proofs,
# and prints a per-skill table with a summary line and non-zero exit when
# any RED skill exists.
#
# Usage:
#   leadv2-skill-proof.sh [run] [--only NAME ...] [--skills-dir D] [--from-state]
#   leadv2-skill-proof.sh validate PATH
#   leadv2-skill-proof.sh list [--skills-dir D]
#
# Exit codes:
#   0 = all skills GREEN
#   1 = one or more RED skills found
#   2 = usage / internal error
#   3 = validate subcommand: proof refused by tautology check

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SKILLS_DIR="${PLUGIN_ROOT}/skills"
ONLY_FILTER=()
FROM_STATE=0
SUBCOMMAND="run"

# ---------------------------------------------------------------------------
# Portable millisecond clock (F1)
#
# GNU date flags (%N, --date=, -d) are Linux-only. This repo runs on macOS
# where BSD date treats %3N as literal text, emitting e.g. "17857718873N"
# and exiting 0 — which poisons downstream arithmetic. Selection is by
# validating the output shape, never by exit status. Tier 4 always succeeds
# (degraded to second resolution); a broken clock is a cosmetic loss (the
# TIME column), never a gate failure — see the shape-guarded duration below.
# ---------------------------------------------------------------------------
now_ms() {
  local val
  val=$(date +%s%3N 2>/dev/null || true)
  if [[ "$val" =~ ^[0-9]+$ ]]; then printf '%s\n' "$val"; return 0; fi
  val=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000' 2>/dev/null || true)
  if [[ "$val" =~ ^[0-9]+$ ]]; then printf '%s\n' "$val"; return 0; fi
  val=$(python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || true)
  if [[ "$val" =~ ^[0-9]+$ ]]; then printf '%s\n' "$val"; return 0; fi
  val=$(date +%s 2>/dev/null || true)
  if [[ "$val" =~ ^[0-9]+$ ]]; then printf '%d\n' "$(( val * 1000 ))"; return 0; fi
  return 1
}

usage() {
  cat >&2 <<'EOF'
Usage: leadv2-skill-proof.sh [run] [--only NAME ...] [--skills-dir D] [--from-state]
       leadv2-skill-proof.sh validate PATH
       leadv2-skill-proof.sh list [--skills-dir D]

  run              Discover, validate, execute all proofs; print table (default).
    --only NAME    Restrict execution to named skill(s); others listed as-is.
    --skills-dir D Override skill discovery directory (test seam).
    --from-state   Print last-known table without executing.
  validate PATH   Run tautology/shape check on a single PROOF.sh; exit 0 ok, 3 refused.
  list            Print skill → proof-present matrix without executing.
EOF
  exit 2
}

# ---------------------------------------------------------------------------
# Tautology / shape validation
# Returns: 0 = valid, non-zero = refused (rule code on stderr)
# ---------------------------------------------------------------------------

# Strip comments and heredoc bodies, leaving operative shell lines.
# Prints the stripped text to stdout.
_strip_proof_text() {
  local file="$1"
  python3 - "$file" <<'PYEOF'
import re, sys

text = open(sys.argv[1]).read()

# Strip heredoc bodies: <<'DELIM' ... DELIM  and  <<-DELIM ... DELIM
# Handles quoted and unquoted delimiters.
text = re.sub(
    r'<<-?["\']?(\w+)["\']?;?.*?\n.*?\n\1',
    '',
    text,
    flags=re.DOTALL,
)

lines_out = []
for line in text.splitlines():
    stripped = line.lstrip()
    # Keep the shebang line
    if stripped.startswith('#!'):
        lines_out.append(line)
        continue
    # Drop full-line comments (but preserve inline content after code)
    if stripped.startswith('#'):
        continue
    # Strip inline comments — crude: cut at ' # ' only if it looks like a comment
    # (not inside a string).  For the tautology check this is sufficient.
    comment_at = re.search(r'\s+#', line)
    if comment_at and "'" not in line[:comment_at.start()] and '"' not in line[:comment_at.start()]:
        line = line[:comment_at.start()]
    lines_out.append(line)

print('\n'.join(lines_out))
PYEOF
}

# Validate a single PROOF.sh. Returns 0 if valid, 1 if refused.
# Sets PROOF_REJECT_RULE and PROOF_REJECT_REASON on failure.
PROOF_REJECT_RULE=""
PROOF_REJECT_REASON=""

validate_proof() {
  local proof_file="$1"
  PROOF_REJECT_RULE=""
  PROOF_REJECT_REASON=""

  # T7: not readable / empty / wrong shebang
  if [[ ! -r "$proof_file" ]]; then
    PROOF_REJECT_RULE="T7"; PROOF_REJECT_REASON="PROOF.sh not readable: $proof_file"
    return 1
  fi
  if [[ ! -s "$proof_file" ]]; then
    PROOF_REJECT_RULE="T7"; PROOF_REJECT_REASON="PROOF.sh is empty"
    return 1
  fi
  local first_line
  first_line=$(head -1 "$proof_file")
  if [[ "$first_line" != '#!/usr/bin/env bash' ]]; then
    PROOF_REJECT_RULE="T7"; PROOF_REJECT_REASON="shebang must be '#!/usr/bin/env bash' (got: $first_line)"
    return 1
  fi

  local stripped
  stripped=$(_strip_proof_text "$proof_file")

  # T4: must contain set -euo pipefail
  if ! printf '%s\n' "$stripped" | grep -qE '(^|\s)set -euo pipefail'; then
    PROOF_REJECT_RULE="T4"; PROOF_REJECT_REASON="missing 'set -euo pipefail'"
    return 1
  fi

  # T3: set +e present (disarms strict mode)
  if printf '%s\n' "$stripped" | grep -qE '^\s*set \+e'; then
    PROOF_REJECT_RULE="T3"; PROOF_REJECT_REASON="'set +e' disarms strict mode"
    return 1
  fi

  # T6: must contain # proof-of: declaration (check raw file for comments)
  if ! grep -qE '^# proof-of: .+' "$proof_file"; then
    PROOF_REJECT_RULE="T6"; PROOF_REJECT_REASON="missing '# proof-of: <claim>' declaration"
    return 1
  fi

  # T5: zero assert_* invocations
  if ! printf '%s\n' "$stripped" | grep -qE 'assert_'; then
    PROOF_REJECT_RULE="T5"; PROOF_REJECT_REASON="zero assert_* invocations"
    return 1
  fi

  # T2: any line ending in || true, || :, || exit 0, || return 0
  if printf '%s\n' "$stripped" | grep -qE '\|\|\s*(true|:|exit\s+0|return\s+0)\s*$'; then
    PROOF_REJECT_RULE="T2"; PROOF_REJECT_REASON="line ends with failure-suppressing || true/:/exit 0/return 0"
    return 1
  fi

  # T1: file's sole operative command is true/:/exit 0/echo
  # Strip meta-lines (set, source, trap, comments, blank, control flow)
  # and check if only trivial commands remain.
  local operative
  operative=$(printf '%s\n' "$stripped" \
    | grep -vE '^\s*$' \
    | grep -vE '^\s*(set |source |\. |trap |if |then |fi$|for |do$|done$|while |case |esac$|else$|elif |function |local |export |readonly |declare |#|\[ |\[\[ )') \
    || true
  if [[ -n "$operative" ]]; then
    # Check if every remaining non-blank line is a trivial no-op
    local non_trivial
    non_trivial=$(printf '%s\n' "$operative" | grep -vE '^\s*(true|:|exit 0|exit\s+0|echo )') || true
    if [[ -z "$non_trivial" ]]; then
      PROOF_REJECT_RULE="T1"; PROOF_REJECT_REASON="file's only operative commands are trivial no-ops (true/:/exit 0/echo)"
      return 1
    fi
  fi

  # T8: trailing bare exit 0 as the final statement after a body with no asserts
  # (belt-and-braces on T2/T5; catches 'echo ok\nexit 0')
  local last_meaningful
  last_meaningful=$(printf '%s\n' "$stripped" | grep -vE '^\s*$' | tail -1)
  if [[ "$last_meaningful" =~ ^[[:space:]]*exit[[:space:]]+0[[:space:]]*$ ]]; then
    # If the second-to-last operative line is also trivial, it's suspicious
    local second_last
    second_last=$(printf '%s\n' "$stripped" | grep -vE '^\s*$' | tail -2 | head -1)
    if [[ "$second_last" =~ ^[[:space:]]*(true|:|echo[[:space:]]) ]]; then
      PROOF_REJECT_RULE="T8"; PROOF_REJECT_REASON="trailing 'exit 0' after trivial-only body"
      return 1
    fi
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Proof execution
# ---------------------------------------------------------------------------

# Execute a proof under timeout, capturing output. Returns exit code.
# Sets PROOF_LOG to the log path, PROOF_DURATION_MS.
PROOF_LOG=""
PROOF_DURATION_MS=0

execute_proof() {
  local proof_file="$1" skill_name="$2"
  local tmp="$LEADV2_PROOF_BASE_TMP/$skill_name"
  rm -rf "$tmp"
  mkdir -p "$tmp/bin"

  local log="$tmp/proof.log"
  PROOF_LOG="$log"

  export LEADV2_PLUGIN_ROOT="$PLUGIN_ROOT"
  export LEADV2_REPO_ROOT="$REPO_ROOT"
  export LEADV2_PROOF_TMP="$tmp"

  local timeout_cmd=""
  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd="gtimeout"
  fi

  local start_ms end_ms rc=0
  start_ms=$(now_ms || true)

  if [[ -n "$timeout_cmd" ]]; then
    "$timeout_cmd" "${LEADV2_PROOF_TIMEOUT:-120}" bash "$proof_file" >"$log" 2>&1 || rc=$?
  else
    bash "$proof_file" >"$log" 2>&1 || rc=$?
  fi

  end_ms=$(now_ms || true)
  # Shape-guarded duration: if either endpoint is non-numeric, degrade to 0.
  # A broken clock must never be able to abort the gate (F1/F3 root cause).
  if [[ "$start_ms" =~ ^[0-9]+$ && "$end_ms" =~ ^[0-9]+$ ]]; then
    PROOF_DURATION_MS=$(( end_ms - start_ms ))
  else
    PROOF_DURATION_MS=0
  fi

  # timeout exit code 124 means killed by timeout
  if [[ "$rc" -eq 124 ]]; then
    return 124
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# State file
# ---------------------------------------------------------------------------

STATE_FILE="${LEADV2_SKILL_PROOF_STATE:-$PLUGIN_ROOT/state/skill-proof-state.json}"

# sha256 of a file
file_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    sha256sum "$1" | cut -d' ' -f1
  fi
}

# Write state file atomically
write_state() {
  local json="$1"
  mkdir -p "$(dirname "$STATE_FILE")"
  local tmp_state="$STATE_FILE.tmp"
  printf '%s\n' "$json" > "$tmp_state"
  mv "$tmp_state" "$STATE_FILE"
}

# Read a field from the state JSON for a skill
state_get() {
  local skill="$1" field="$2"
  python3 -c "
import json,sys
try:
    d=json.load(open('$STATE_FILE'))
    s=d.get('skills',{}).get('$skill',{})
    print(s.get('$field',''))
except: print('')
"
}

# ---------------------------------------------------------------------------
# Main gate logic
# ---------------------------------------------------------------------------

# Discover skills: directories containing SKILL.md (skip archive/, skip dirs without SKILL.md)
discover_skills() {
  local dir
  for dir in "$SKILLS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    local base
    base=$(basename "$dir")
    # Skip archive directory
    [[ "$base" == "archive" ]] && continue
    # Must have SKILL.md at top level
    [[ -f "$dir/SKILL.md" ]] || continue
    printf '%s\n' "$base"
  done | sort
}

# Run the full gate
do_run() {
  local skills
  skills=$(discover_skills)
  local total=0
  local green=0 red=0
  local no_proof=0 failed=0 invalid=0 never_run=0

  # Determine which skills to actually execute
  local only_mode=0
  if [[ ${#ONLY_FILTER[@]} -gt 0 ]]; then
    only_mode=1
  fi

  local state_json='{"version":1,"skills":{}}'
  local table_rows=()
  local failed_logs=()

  while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    total=$((total + 1))

    local proof_file="$SKILLS_DIR/$skill/PROOF.sh"
    local status="" reason="" duration_ms=0
    local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if [[ ! -f "$proof_file" ]]; then
      status="RED-NO-PROOF"
      reason="no PROOF.sh in skill directory"
      table_rows+=("$(printf '%-35s %-15s %5s  %s' "$skill" "$status" "-" "$reason")")
      red=$((red + 1)); no_proof=$((no_proof + 1))
      continue
    fi

    # Validate
    if ! validate_proof "$proof_file"; then
      status="RED-INVALID"
      reason="$PROOF_REJECT_RULE: $PROOF_REJECT_REASON"
      printf '[SKILL-PROOF] REFUSED %s — %s\n' "$skill" "$reason" >&2
      table_rows+=("$(printf '%-35s %-15s %5s  %s' "$skill" "$status" "-" "$reason")")
      red=$((red + 1)); invalid=$((invalid + 1))

      # Record in state
      state_json=$(python3 -c "
import json,sys
d=json.loads('''$state_json''')
d['skills']['$skill']={'status':'RED-INVALID','exit':-1,'ran_at':'$now','proof_sha256':'','duration_ms':0,'last_green_at':null}
print(json.dumps(d))
" 2>/dev/null || printf '%s' "$state_json")
      continue
    fi

    # Check if we should execute this skill
    local should_execute=1
    if [[ "$only_mode" == 1 ]]; then
      should_execute=0
      for f in "${ONLY_FILTER[@]}"; do
        [[ "$f" == "$skill" ]] && should_execute=1 && break
      done
    fi

    if [[ "$FROM_STATE" == 1 ]]; then
      # Read from state
      local recorded_status recorded_sha current_sha
      recorded_status=$(state_get "$skill" "status")
      recorded_sha=$(state_get "$skill" "proof_sha256")
      current_sha=$(file_sha256 "$proof_file")
      if [[ "$recorded_status" == "GREEN" ]]; then
        if [[ "$recorded_sha" != "$current_sha" ]]; then
          status="RED-NEVER-RUN"
          reason="proof changed since last GREEN (sha mismatch)"
        else
          status="GREEN"
          reason="from state"
        fi
      elif [[ -n "$recorded_status" ]]; then
        status="$recorded_status"
        reason="from state"
      else
        status="RED-NEVER-RUN"
        reason="no successful execution recorded"
      fi
    elif [[ "$should_execute" == 0 ]]; then
      # Not selected by --only; report from state if available
      local recorded_status recorded_sha current_sha
      recorded_status=$(state_get "$skill" "status")
      recorded_sha=$(state_get "$skill" "proof_sha256")
      current_sha=$(file_sha256 "$proof_file")
      if [[ "$recorded_status" == "GREEN" && "$recorded_sha" == "$current_sha" ]]; then
        status="GREEN"
        reason="from state (not re-run)"
      elif [[ -n "$recorded_status" ]]; then
        status="RED-NEVER-RUN"
        reason="proof not re-run in this --only pass"
      else
        status="RED-NEVER-RUN"
        reason="no successful execution recorded"
      fi
    else
      # Execute
      export LEADV2_PROOF_BASE_TMP="${LEADV2_PROOF_BASE_TMP:-$(mktemp -d -t leadv2-skill-proof)}"
      local rc=0
      execute_proof "$proof_file" "$skill" || rc=$?
      duration_ms=$PROOF_DURATION_MS

      local current_sha
      current_sha=$(file_sha256 "$proof_file")

      if [[ "$rc" -eq 0 ]]; then
        status="GREEN"
        reason="exit 0"
        green=$((green + 1))
      elif [[ "$rc" -eq 124 ]]; then
        status="RED-FAILED"
        reason="timeout after ${LEADV2_PROOF_TIMEOUT:-120}s"
        red=$((red + 1)); failed=$((failed + 1))
        failed_logs+=("$skill" "$PROOF_LOG")
      else
        status="RED-FAILED"
        reason="exit $rc"
        red=$((red + 1)); failed=$((failed + 1))
        failed_logs+=("$skill" "$PROOF_LOG")
      fi

      # Record last_green_at
      local last_green="null"
      if [[ "$status" == "GREEN" ]]; then
        last_green="\"$now\""
      else
        local prev_green
        prev_green=$(state_get "$skill" "last_green_at")
        last_green=${prev_green:+\"$prev_green\"}
        [[ -z "$prev_green" ]] && last_green="null"
      fi

      state_json=$(python3 -c "
import json
d=json.loads('''$state_json''')
d['skills']['$skill']={'status':'$status','exit':${rc:-0},'ran_at':'$now','proof_sha256':'$current_sha','duration_ms':$duration_ms,'last_green_at':$last_green}
print(json.dumps(d))
" 2>/dev/null || printf '%s' "$state_json")
    fi

    local ms_display="-"
    [[ "$duration_ms" -gt 0 ]] && ms_display="${duration_ms}ms"
    table_rows+=("$(printf '%-35s %-15s %5s  %s' "$skill" "$status" "$ms_display" "$reason")")
  done <<< "$skills"

  # Write state (only if we actually executed something)
  if [[ "$FROM_STATE" == 0 ]]; then
    write_state "$state_json"
  fi

  # Print table
  printf '\n'
  printf '%s\n' "──────────────────────────────────────────────────────────────────────────"
  printf '%-35s %-15s %5s  %s\n' "SKILL" "STATUS" "TIME" "REASON"
  printf '%s\n' "──────────────────────────────────────────────────────────────────────────"
  for row in "${table_rows[@]}"; do
    printf '%s\n' "$row"
  done
  printf '%s\n' "──────────────────────────────────────────────────────────────────────────"

  printf '\ngreen=%d red=%d (no-proof=%d failed=%d invalid=%d never-run=%d) skills=%d\n' \
    "$green" "$red" "$no_proof" "$failed" "$invalid" "$never_run" "$total"

  if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
    :
  else
    printf 'WARN: no timeout/gtimeout — proof time limit not enforced\n'
  fi

  # Print failed logs (last 20 lines)
  if [[ ${#failed_logs[@]} -gt 0 ]]; then
    printf '\n'
    local i
    for (( i=0; i<${#failed_logs[@]}; i+=2 )); do
      local s="${failed_logs[$i]}"
      local l="${failed_logs[$((i+1))]}"
      if [[ -f "$l" ]]; then
        printf '── %s (last 20 lines) ──\n' "$s"
        tail -20 "$l" 2>/dev/null || true
        printf '\n'
      fi
    done
  fi

  # Cleanup base tmp
  [[ -n "${LEADV2_PROOF_BASE_TMP:-}" && -d "$LEADV2_PROOF_BASE_TMP" ]] \
    && rm -rf "$LEADV2_PROOF_BASE_TMP" 2>/dev/null || true

  RUN_COMPLETED=1
  if [[ "$red" -gt 0 ]]; then
    return 1
  fi
  return 0
}

# List subcommand: print skill → proof-present matrix
do_list() {
  local skills
  skills=$(discover_skills)
  local total=0 has_proof=0

  printf '%-35s %-12s\n' "SKILL" "PROOF"
  printf '%s\n' "───────────────────────────────────────"
  while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    total=$((total + 1))
    local proof_file="$SKILLS_DIR/$skill/PROOF.sh"
    if [[ -f "$proof_file" ]]; then
      printf '%-35s %-12s\n' "$skill" "present"
      has_proof=$((has_proof + 1))
    else
      printf '%-35s %-12s\n' "$skill" "absent"
    fi
  done <<< "$skills"
  printf '%s\n' "───────────────────────────────────────"
  printf 'skills=%d proofs=%d missing=%d\n' "$total" "$has_proof" "$((total - has_proof))"
  return 0
}

# Validate subcommand
do_validate() {
  local path="${1:-}"
  [[ -z "$path" ]] && usage
  [[ ! -f "$path" ]] && {
    printf '[SKILL-PROOF] file not found: %s\n' "$path" >&2
    exit 2
  }
  if validate_proof "$path"; then
    printf '[SKILL-PROOF] VALID: %s\n' "$path"
    exit 0
  else
    printf '[SKILL-PROOF] REFUSED %s — %s: %s\n' "$path" "$PROOF_REJECT_RULE" "$PROOF_REJECT_REASON" >&2
    exit 3
  fi
}

# ---------------------------------------------------------------------------
# Completion sentinel + EXIT trap (F3)
#
# RUN_COMPLETED is set to 1 only on the line immediately before do_run's
# final return. If the gate crashes or otherwise reaches exit 0 without
# completing the run subcommand, the trap converts that silent success
# into a loud exit 2 (internal error). This is the exact invariant M-8
# exists to enforce: a gate that cannot exit non-zero cannot gate anything.
#
# The trap only gates the 'run' subcommand. validate (0/2/3) and list (0)
# exit directly and must not be disturbed.
# ---------------------------------------------------------------------------
RUN_COMPLETED=0

# shellcheck disable=SC2329 # invoked indirectly via 'trap _final EXIT'
_final() {
  local rc=$?
  if [[ "${SUBCOMMAND:-run}" == "run" && "$rc" -eq 0 && "$RUN_COMPLETED" -ne 1 ]]; then
    printf '[SKILL-PROOF] INTERNAL ERROR: run exited 0 without completing\n' >&2
    exit 2
  fi
  exit "$rc"
}
trap '_final' EXIT

# ---------------------------------------------------------------------------
# Argument parsing (F2: single entry point, single exit path)
# ---------------------------------------------------------------------------

case "${1:-run}" in
  run) SUBCOMMAND="run"; shift 2>/dev/null || true ;;
  validate) SUBCOMMAND="validate"; shift; do_validate "${1:-}" ;;
  list) SUBCOMMAND="list"; shift ;;
  -h|--help) usage ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY_FILTER+=("$2"); shift 2 ;;
    --skills-dir) SKILLS_DIR="$2"; shift 2 ;;
    --from-state) FROM_STATE=1; shift ;;
    -h|--help) usage ;;
    *) printf '[SKILL-PROOF] unknown arg: %s\n' "$1" >&2; usage ;;
  esac
done

if [[ "$SUBCOMMAND" == "list" ]]; then
  do_list
  exit $?
fi

rc=0
do_run || rc=$?
exit "$rc"
