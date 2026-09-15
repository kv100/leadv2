#!/usr/bin/env bash
# changed-scope triggers, self-registered (scan_suite_triggers convention):
# run-all-triggers: leadv2-routing-guard.sh leadv2-bash-pre-dispatch.sh
#
# Real-hook regression for GUARD-READ-ONLY-IS-A-NAME-NOT-A-PROPERTY-01.
# The hook input carries agent_type for a nested caller. Explore and recon may
# inspect local state, but cannot run the named mutation classes. general-purpose
# is instead a write role and is refused at direct lead spawn by the same
# _is_write_role function used by the nested path.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTING_HOOK="$SCRIPT_DIR/../../hooks/leadv2-routing-guard.sh"
BASH_HOOK="$SCRIPT_DIR/../../hooks/leadv2-bash-pre-dispatch.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/readonly-caller-guard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

make_bash_input() { # caller command
  python3 -c '
import json, sys
print(json.dumps({"tool_name": "Bash", "agent_type": sys.argv[1],
                  "tool_input": {"command": sys.argv[2]}}))
' "$1" "$2"
}

make_spawn_input() { # type cwd
  python3 -c '
import json, sys
print(json.dumps({"tool_name": "Agent", "cwd": sys.argv[2],
                  "tool_input": {"subagent_type": sys.argv[1], "model": "sonnet"}}))
' "$1" "$2"
}

RC=0
run_bash_hook() { # hook caller command
  RC=0
  make_bash_input "$2" "$3" | LEADV2_GUARD_VERDICT_DIR="$TMP/verdicts" \
    bash "$1" >"$TMP/last.out" 2>&1 || RC=$?
  cat "$TMP/last.out"
}

run_spawn_hook() { # hook type
  RC=0
  make_spawn_input "$2" "$TMP" | bash "$1" >"$TMP/last.out" 2>&1 || RC=$?
  cat "$TMP/last.out"
}

mutate_once() { # source destination anchor replacement
  python3 - "$@" <<'PY'
import sys
src, dst, anchor, replacement = sys.argv[1:]
text = open(src, encoding="utf-8").read()
count = text.count(anchor)
if count != 1:
    raise SystemExit("mutation anchor matched %d times, expected 1: %r" % (count, anchor))
open(dst, "w", encoding="utf-8").write(text.replace(anchor, replacement, 1))
PY
}

[[ -f "$ROUTING_HOOK" && -f "$BASH_HOOK" ]] || { echo 'FATAL: real hook missing' >&2; exit 66; }

# GREEN A: a real nested Explore Bash input is refused and names role + class.
run_bash_hook "$BASH_HOOK" Explore 'git commit -m prohibited'
if [[ "$RC" -eq 2 ]] && grep -Fq 'agent_type="explore" command_class="git_commit"' "$TMP/last.out"; then
  pass 'GREEN A: Explore git commit refused by real Bash hook with named cause'
else
  fail "GREEN A: Explore git commit rc=$RC; expected rc=2 and named cause"
fi

# GREEN B: local discovery and a GET-style curl stay open. Each command reaches
# the real dispatcher; none is executed by this test.
for command in 'git log -1 --oneline' 'grep needle local-file' 'curl https://example.invalid/health'; do
  run_bash_hook "$BASH_HOOK" Explore "$command"
  if [[ "$RC" -eq 0 ]]; then
    pass "GREEN B: Explore read-only command admitted: $command"
  else
    fail "GREEN B: read-only command over-refused (rc=$RC): $command"
  fi
done

# The named mutation classes are all refused. `ssh host true` is deliberately
# in this set: a local hook cannot prove remote effects, so ssh is treated as a
# mutating-capable boundary rather than guessing from its remote argv.
while IFS='|' read -r command command_class; do
  run_bash_hook "$BASH_HOOK" Explore "$command"
  if [[ "$RC" -eq 2 ]] && grep -Fq "command_class=\"$command_class\"" "$TMP/last.out"; then
    pass "GREEN B2: Explore mutation class refused: $command_class"
  else
    fail "GREEN B2: command '$command' did not refuse as $command_class (rc=$RC)"
  fi
done <<'EOF'
git push origin main|git_push
sed -i s/old/new/ local-file|sed_in_place
ssh host true|ssh
docker exec container true|docker_exec
curl -X POST https://example.invalid/write|curl_mutating_method
EOF

# GREEN C: direct lead general-purpose spawn is a write-role denial.
run_spawn_hook "$ROUTING_HOOK" general-purpose
if [[ "$RC" -eq 2 ]] && grep -Fq 'leadv2-dispatch-code.sh' "$TMP/last.out"; then
  pass 'GREEN C: lead general-purpose spawn refused with dispatch remedy'
else
  fail "GREEN C: general-purpose spawn rc=$RC; expected rc=2 and remedy"
fi

# RED CONTROL 1: remove general-purpose from the ONE role list. The spawn
# assertion above must fail loudly (mutant admits it).
MUT_ROUTING="$TMP/routing-without-general-purpose.sh"
if mutate_once "$ROUTING_HOOK" "$MUT_ROUTING" \
  'developer|frontend-developer|postgres-pro|devops-engineer|architect|product-owner|general-purpose) return 0 ;;' \
  'developer|frontend-developer|postgres-pro|devops-engineer|architect|product-owner) return 0 ;;'; then
  run_spawn_hook "$MUT_ROUTING" general-purpose
  if [[ "$RC" -eq 0 ]]; then
    pass 'RED CONTROL 1: without general-purpose classification, spawn assertion goes RED (mutant admitted)'
  else
    fail "RED CONTROL 1: classification mutant rc=$RC; expected admission rc=0"
  fi
else
  fail 'RED CONTROL 1: classification mutation anchor did not match exactly once'
fi

# RED CONTROL 2: remove the mutation sub-hook. The real input above must then
# be admitted; otherwise the suite has a second, accidental blocker.
MUT_NO_SUBHOOK="$TMP/bash-without-readonly-subhook.sh"
READONLY_CASE='  case "$_lv2_readonly_caller" in
    explore|recon) ;;
    *) return 0 ;;
  esac'
if mutate_once "$BASH_HOOK" "$MUT_NO_SUBHOOK" "$READONLY_CASE" '  return 0  # mutant: read-only mutation sub-hook removed'; then
  run_bash_hook "$MUT_NO_SUBHOOK" Explore 'git commit -m prohibited'
  if [[ "$RC" -eq 0 ]]; then
    pass 'RED CONTROL 2: without sub-hook, git-commit refusal assertion goes RED (mutant admitted)'
  else
    fail "RED CONTROL 2: sub-hook mutant rc=$RC; expected admission rc=0"
  fi
else
  fail 'RED CONTROL 2: sub-hook mutation anchor did not match exactly once'
fi

# RED CONTROL 3: make the sub-hook refuse every Explore command. The admitted
# git-log assertion must go RED, proving this is not an all-Bash outage.
MUT_REFUSE_ALL="$TMP/bash-refuse-all.sh"
if mutate_once "$BASH_HOOK" "$MUT_REFUSE_ALL" \
  '  local _lv2_command_class=""' '  local _lv2_command_class="all_commands"'; then
  run_bash_hook "$MUT_REFUSE_ALL" Explore 'git log -1 --oneline'
  if [[ "$RC" -eq 2 ]]; then
    pass 'RED CONTROL 3: refuse-all mutant makes read-only-command assertion go RED'
  else
    fail "RED CONTROL 3: refuse-all mutant rc=$RC; expected refusal rc=2"
  fi
else
  fail 'RED CONTROL 3: over-refusal mutation anchor did not match exactly once'
fi

printf '%s\n' '---'
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
