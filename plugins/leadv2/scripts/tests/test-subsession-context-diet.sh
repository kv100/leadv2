#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
# tests/test-subsession-context-diet.sh — WORKER-CONTEXT-DIET-01
#
# Integration test for resolve_role_mcp_config() and the two
# LEADV2_SUBSESSION_* flag appends in claude-subsession.sh. Sources the REAL
# script under LEADV2_DRY_RUN=1 (D5 chokepoint — `claude` is never invoked),
# same harness style as test-leadv2-model-arg-rebuild.sh: trap EXIT dumps
# CLAUDE_ARGS + stderr to a capture file.
#
# Every fail-open case (missing config, malformed JSON, unresolvable server)
# must still let the DRY_RUN spawn reach its normal exit — a resolver failure
# must never abort claude-subsession.sh under set -e.
#
# Run: bash scripts/tests/test-subsession-context-diet.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBSESSION_SH="${SCRIPT_DIR}/../claude-subsession.sh"

PASS=0
FAIL=0
ERRORS=()

log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

_it_fixture_root() {
  local root; root="$(lv2_mktemp_dir "context-diet-it")"
  mkdir -p "$root/.claude/ref" "$root/.claude/agents"
  # Fixture-local repowise definition (§3b source 1: $PROJECT_ROOT/.mcp.json).
  # Deliberately NOT relying on the ambient $HOME/.claude/settings.json: the
  # core-offline runner scrubs HOME per suite for TMPDIR isolation
  # (SUITE-SPEED-01), so a test that only resolves via the real $HOME passes
  # standalone but fails under run-core-offline.sh.
  cat > "$root/.mcp.json" <<'MCPEOF'
{"mcpServers": {"repowise": {"command": "stub-repowise", "args": []}}}
MCPEOF
  cat > "$root/.claude/ref/leadv2-routing.yaml" <<'YAML'
phases:
  build:
    single_file:
      default: sonnet-subsession
      tool: claude-subsession
      expected_cost_usd: 0.10
      expected_tokens: 20000
stop_rules:
  cost_ceiling_per_task:
    Standard: 2.00
    warn_threshold_pct: 60
    hard_stop_threshold_pct: 95
downgrade_chain:
  opus: sonnet
  sonnet: haiku
  haiku: haiku
YAML
  cat > "$root/.claude/agents/developer.md" <<'ROLEEOF'
---
model: sonnet
---
Integration-test developer role body.
ROLEEOF
  # hack-detect: a real role with no dedicated mcp-role-hack-detect.json,
  # used to exercise the default-fallback path (Test 2) -- it must clear the
  # earlier, unrelated agents/<role>.md existence gate before reaching
  # resolve_role_mcp_config() at all.
  cat > "$root/.claude/agents/hack-detect.md" <<'ROLEEOF'
---
model: sonnet
---
Integration-test hack-detect role body.
ROLEEOF
  printf 'Integration-test mission body.\n' > "$root/mission.md"
  printf '%s' "$root"
}

# _it_run_subsession — sources the REAL script, captures CLAUDE_ARGS + stderr.
# Args: $1=task_id $2=role $3=extra env (space-separated NAME=VALUE) $4=plugin_root (config dir parent)
# Prints "ARGS<newline>...<newline>---STDERR---<newline>..." to stdout.
_it_run_subsession() {
  local task_id="$1" role="$2" extra_env="${3:-}" plugin_root="${4:-}"
  local root; root="$(_it_fixture_root)"
  mkdir -p "$root/docs/handoff/$task_id"

  local capture; capture="$(lv2_mktemp_file "context-diet-it-capture" "tmp")"
  local stderr_capture; stderr_capture="$(lv2_mktemp_file "context-diet-it-stderr" "tmp")"

  (
    set +e
    if [[ -n "$extra_env" ]]; then
      # shellcheck disable=SC2086,SC2163
      export $extra_env
    fi
    export PROJECT_ROOT="$root"
    export LEADV2_ROUTE_BANDIT=0
    export LEADV2_TASK_CLASS="Standard"
    export LEADV2_DRY_RUN=1
    if [[ -n "$plugin_root" ]]; then
      export CLAUDE_PLUGIN_ROOT="$plugin_root"
    else
      unset CLAUDE_PLUGIN_ROOT 2>/dev/null || true
    fi
    trap 'printf "%s\n" "${CLAUDE_ARGS[@]:-__NO_ARGS__}" > "'"$capture"'"' EXIT
    # shellcheck disable=SC1090
    source "$SUBSESSION_SH" --role "$role" --model sonnet \
      --task-id "$task_id" --mission-file "$root/mission.md" --wait \
      >/dev/null 2>"$stderr_capture"
  )

  printf 'ARGS\n'
  cat "$capture" 2>/dev/null
  printf -- '---STDERR---\n'
  cat "$stderr_capture" 2>/dev/null
  rm -rf "$root" "$capture" "$stderr_capture"
}

_has_flag() { # $1=output $2=flag
  printf '%s' "$1" | awk -v f="$2" '/^ARGS$/{on=1;next} /^---STDERR---$/{on=0} on && $0==f{found=1} END{exit !found}'
}

_stderr_of() { # $1=output
  printf '%s' "$1" | awk '/^---STDERR---$/{on=1;next} on'
}

REAL_PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ── Test 1: role→file mapping — developer picks up mcp-role-developer.json ──
test_1_role_mapping() {
  log "Test 1: role=developer resolves --strict-mcp-config + --mcp-config"
  local out; out="$(_it_run_subsession "CD-01" "developer")"
  if _has_flag "$out" "--strict-mcp-config"; then
    pass "developer role appends --strict-mcp-config"
  else
    fail "developer role missing --strict-mcp-config: $(_stderr_of "$out")"
  fi
}

# ── Test 2: unknown role falls back to mcp-role-default.json ──────────────
test_2_unknown_role_falls_back_to_default() {
  log "Test 2: role=hack-detect (no dedicated file) falls back to default"
  local out; out="$(_it_run_subsession "CD-02" "hack-detect")"
  if _has_flag "$out" "--strict-mcp-config"; then
    pass "hack-detect falls back to mcp-role-default.json"
  else
    fail "hack-detect did not resolve via default fallback: $(_stderr_of "$out")"
  fi
}

# ── Test 3: missing config dir (role AND default absent) → fail-open + WARN ──
test_3_missing_config_fails_open_with_warn() {
  log "Test 3: no allowlist anywhere -> fail open, WARN logged, no flags"
  local empty_plugin_root; empty_plugin_root="$(lv2_mktemp_dir "context-diet-empty-plugin")"
  mkdir -p "$empty_plugin_root/config" "$empty_plugin_root/skills/leadv2-subagent-protocol"
  local out; out="$(_it_run_subsession "CD-03" "developer" "" "$empty_plugin_root")"
  local stderr; stderr="$(_stderr_of "$out")"
  if _has_flag "$out" "--strict-mcp-config"; then
    fail "expected no --strict-mcp-config when no allowlist exists"
  elif printf '%s' "$stderr" | grep -q "context-diet: no mcp allowlist for role=developer"; then
    pass "missing allowlist fails open with expected WARN, no flags appended"
  else
    fail "missing allowlist: WARN not found in stderr: $stderr"
  fi
  rm -rf "$empty_plugin_root"
}

# ── Test 4: malformed JSON allowlist → fail-open + WARN ────────────────────
test_4_malformed_json_fails_open() {
  log "Test 4: malformed allowlist JSON -> fail open, WARN logged"
  local plugin_root; plugin_root="$(lv2_mktemp_dir "context-diet-malformed-plugin")"
  mkdir -p "$plugin_root/config"
  printf '{not valid json' > "$plugin_root/config/mcp-role-developer.json"
  local out; out="$(_it_run_subsession "CD-04" "developer" "" "$plugin_root")"
  local stderr; stderr="$(_stderr_of "$out")"
  if _has_flag "$out" "--strict-mcp-config"; then
    fail "expected no --strict-mcp-config on malformed JSON"
  elif printf '%s' "$stderr" | grep -q "context-diet:.*malformed"; then
    pass "malformed allowlist fails open with expected WARN"
  else
    fail "malformed allowlist: WARN not found in stderr: $stderr"
  fi
  rm -rf "$plugin_root"
}

# ── Test 5: {"servers": []} explicit empty → flags present, empty mcpServers ─
test_5_explicit_empty_servers_still_appends_flags() {
  log "Test 5: explicit {\"servers\":[]} still appends flags (deliberate no-MCP)"
  local plugin_root; plugin_root="$(lv2_mktemp_dir "context-diet-empty-servers-plugin")"
  mkdir -p "$plugin_root/config"
  printf '{"servers": []}' > "$plugin_root/config/mcp-role-developer.json"
  local out; out="$(_it_run_subsession "CD-05" "developer" "" "$plugin_root")"
  if _has_flag "$out" "--strict-mcp-config"; then
    pass "explicit empty servers list still appends flags"
  else
    fail "explicit empty servers list should still append flags: $(_stderr_of "$out")"
  fi
  rm -rf "$plugin_root"
}

# ── Test 6: allowlist names an unresolvable server → fail-open + WARN ──────
test_6_unresolvable_server_fails_open() {
  log "Test 6: allowlist names a server absent from every config source -> fail open"
  local plugin_root; plugin_root="$(lv2_mktemp_dir "context-diet-unresolvable-plugin")"
  mkdir -p "$plugin_root/config"
  printf '{"servers": ["nonexistent-server-xyz"]}' > "$plugin_root/config/mcp-role-developer.json"
  local out; out="$(_it_run_subsession "CD-06" "developer" "" "$plugin_root")"
  local stderr; stderr="$(_stderr_of "$out")"
  if _has_flag "$out" "--strict-mcp-config"; then
    fail "expected no --strict-mcp-config when zero servers resolve"
  elif printf '%s' "$stderr" | grep -q "context-diet:.*unresolved"; then
    pass "unresolvable server fails open with expected WARN"
  else
    fail "unresolvable server: WARN not found in stderr: $stderr"
  fi
  rm -rf "$plugin_root"
}

# ── Test 7: LEADV2_SUBSESSION_SLIM_MCP=0 kill-switch — no flags, no WARN ───
test_7_slim_mcp_killswitch() {
  log "Test 7: LEADV2_SUBSESSION_SLIM_MCP=0 -> no flags, no WARN (deliberate operator choice)"
  local out; out="$(_it_run_subsession "CD-07" "developer" "LEADV2_SUBSESSION_SLIM_MCP=0")"
  local stderr; stderr="$(_stderr_of "$out")"
  if _has_flag "$out" "--strict-mcp-config"; then
    fail "kill-switch=0 should suppress --strict-mcp-config"
  elif printf '%s' "$stderr" | grep -q "context-diet"; then
    fail "kill-switch=0 should log NO context-diet WARN: $stderr"
  else
    pass "kill-switch=0 suppresses flags with no WARN"
  fi
}

# ── Test 8: LEADV2_SUBSESSION_EXCLUDE_DYNAMIC=0 — flag absent ──────────────
test_8_exclude_dynamic_killswitch() {
  log "Test 8: LEADV2_SUBSESSION_EXCLUDE_DYNAMIC=0 -> --exclude-dynamic-system-prompt-sections absent"
  local out; out="$(_it_run_subsession "CD-08" "developer" "LEADV2_SUBSESSION_EXCLUDE_DYNAMIC=0")"
  if _has_flag "$out" "--exclude-dynamic-system-prompt-sections"; then
    fail "EXCLUDE_DYNAMIC=0 should suppress the flag"
  else
    pass "EXCLUDE_DYNAMIC=0 suppresses --exclude-dynamic-system-prompt-sections"
  fi
}

# ── Test 9: default (both flags unset) — exclude-dynamic present ──────────
test_9_exclude_dynamic_default_on() {
  log "Test 9: default (unset) -> --exclude-dynamic-system-prompt-sections present"
  local out; out="$(_it_run_subsession "CD-09" "developer")"
  if _has_flag "$out" "--exclude-dynamic-system-prompt-sections"; then
    pass "default appends --exclude-dynamic-system-prompt-sections"
  else
    fail "default should append --exclude-dynamic-system-prompt-sections"
  fi
}

# ── Test 10: ROLE sanitisation inside resolve_role_mcp_config() itself ─────
# The full-script path can never reach resolve_role_mcp_config with an unsafe
# ROLE (an earlier agents/<role>.md existence gate rejects it first), so this
# extracts the REAL function body (same technique as
# tests/test-sonnet-arm-detach-01.sh extracting setsid_wrapper()) to prove the
# in-function regex guard directly: a role containing path-traversal chars
# must coerce to "default", never be interpolated raw into a config path.
test_10_role_sanitised() {
  log "Test 10: resolve_role_mcp_config('../../evil', ...) coerces to default, no traversal"
  local funcs_file; funcs_file="$(lv2_mktemp_file "context-diet-funcs" "sh")"
  sed -n '/^resolve_role_mcp_config() {/,/^}$/p' "$SUBSESSION_SH" > "$funcs_file"
  if [[ ! -s "$funcs_file" ]]; then
    fail "could not extract resolve_role_mcp_config() from claude-subsession.sh -- renamed/removed?"
    rm -f "$funcs_file"
    return
  fi

  local plugin_root; plugin_root="$(lv2_mktemp_dir "context-diet-sanitise-plugin")"
  mkdir -p "$plugin_root/config"
  printf '{"servers": []}' > "$plugin_root/config/mcp-role-default.json"
  local handoff_dir; handoff_dir="$(lv2_mktemp_dir "context-diet-sanitise-handoff")"

  local resolved_path stderr_out rc
  stderr_out="$(lv2_mktemp_file "context-diet-sanitise-stderr" "tmp")"
  (
    set +e
    export CLAUDE_PLUGIN_ROOT="$plugin_root"
    export PROJECT_ROOT="$plugin_root"
    export HOME="$plugin_root"
    export LEADV2_SUBSESSION_SLIM_MCP=1
    # shellcheck disable=SC1090
    source "$funcs_file"
    resolve_role_mcp_config "../../evil" "$handoff_dir" >/dev/null 2>"$stderr_out"
  )
  rc=$?
  resolved_path="$(
    set +e
    export CLAUDE_PLUGIN_ROOT="$plugin_root"
    export PROJECT_ROOT="$plugin_root"
    export HOME="$plugin_root"
    export LEADV2_SUBSESSION_SLIM_MCP=1
    # shellcheck disable=SC1090
    source "$funcs_file"
    resolve_role_mcp_config "../../evil" "$handoff_dir" 2>/dev/null
  )"

  local stderr; stderr="$(cat "$stderr_out" 2>/dev/null)"
  if [[ -f "${handoff_dir}/mcp-role-evil.resolved.json" || -f "${plugin_root}/config/../evil.json" ]]; then
    fail "unsafe role produced a file named after the raw role value -- traversal not sanitised"
  elif [[ "$resolved_path" == "${handoff_dir}/mcp-role-default.resolved.json" ]]; then
    pass "unsafe role coerced to 'default', resolved config written under expected safe path"
  else
    fail "expected resolved path ${handoff_dir}/mcp-role-default.resolved.json, got '${resolved_path}' (stderr: ${stderr})"
  fi
  rm -rf "$plugin_root" "$handoff_dir" "$funcs_file" "$stderr_out"
}

test_1_role_mapping
test_2_unknown_role_falls_back_to_default
test_3_missing_config_fails_open_with_warn
test_4_malformed_json_fails_open
test_5_explicit_empty_servers_still_appends_flags
test_6_unresolvable_server_fails_open
test_7_slim_mcp_killswitch
test_8_exclude_dynamic_killswitch
test_9_exclude_dynamic_default_on
test_10_role_sanitised

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
