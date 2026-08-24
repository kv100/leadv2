#!/usr/bin/env bash
# tests/test-fanout-classify-guard.sh — SUPERVISE-V2-01 fix-1 (critic C2):
# leadv2-fanout.sh had ZERO test coverage before this fix. Covers the two
# concrete regressions the review caught:
#   1. classify_task(): a missing/non-executable leadv2-fanout-classify.sh
#      used to silently force-escalate EVERY task to Heavy/opus (via a bare
#      except-Exception branch with no stderr message). Fixed: existence
#      guard -> loud WARN -> safe fallback (existing class or Standard),
#      never a silent Heavy escalation.
#   2. launch_headless(): a missing/non-executable leadv2-session-runner.sh
#      must fail closed. A raw one-shot fallback cannot prove Phase 0..8 or
#      the canonical Phase-8 completion proof.
#
# Tests:
#   1. bash -n syntax check (fanout.sh + the two promoted scripts)
#   2. classify script present -> Standard (no risk keywords), no WARN
#   3. classify script hidden -> WARN on stderr, class falls back to
#      Standard/existing (NOT Heavy) -- calls the REAL fanout.sh --dry-run,
#      not a reimplementation
#   4. session-runner hidden -> real --headless launch is refused loudly
#
# Portable: no GNU-only date/sed -i/timeout/flock. Sandboxed via
# LEADV2_PROJECT_ROOT / LEADV2_STATE_ROOT / LEADV2_FANOUT_CLAUDE_BIN /
# LEADV2_FANOUT_TMUX_SESSION env overrides -- never touches the real repo's
# docs/leadv2/active.yaml or a real "leadv2" tmux session.
# Run: bash scripts/tests/test-fanout-classify-guard.sh
# Exit 0 = all pass; non-zero = failures found.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FANOUT_SH="${SCRIPTS_ROOT}/leadv2-fanout.sh"
CLASSIFY_SH="${SCRIPTS_ROOT}/leadv2-fanout-classify.sh"
RUNNER_SH="${SCRIPTS_ROOT}/leadv2-session-runner.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

_new_sandbox() {
  local d
  d="$(lv2_mktemp_dir "fanoutcg-test")"
  mkdir -p "${d}/proj/docs/leadv2" "${d}/proj/.claude/scripts" "${d}/state"
  # CORE-OFFLINE-WORKTREE-GAP-01: stage the registry helper into the
  # sandbox's vendored path so the guard is hermetic -- never depends on
  # the host's untracked .claude/scripts/ symlink farm or $HOME.
  cp "${SCRIPTS_ROOT}/leadv2-active-registry.sh" "${d}/proj/.claude/scripts/leadv2-active-registry.sh"
  cat > "${d}/proj/docs/leadv2/active.yaml" <<'YAML'
meta:
  schema_version: 2
  hard_limit: 20
  heavy_strategic_solo: true
  light_max: 3
  standard_max: 2
  rendered_at: ""
sessions: []
YAML
  cat > "${d}/proj/docs/tasks.yaml" <<YAML
tasks:
  - id: FCG-T1
    status: queued
    intent: "harmless test task, no risk keywords"
    priority: 5
YAML
  printf -- '%s' "$d"
}

test_1_syntax() {
  log "Test 1: bash -n syntax check"
  if bash -n "$FANOUT_SH" 2>/dev/null \
     && bash -n "$CLASSIFY_SH" 2>/dev/null \
     && bash -n "$RUNNER_SH" 2>/dev/null; then
    pass "Test 1: bash -n OK (fanout + classify + session-runner)"
  else
    fail "Test 1: bash -n FAILED"
  fi
}

test_2_classify_present_standard() {
  log "Test 2: classify script present -> class=Standard, no WARN"
  local sandbox out
  sandbox="$(_new_sandbox)"
  out="$(
    LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" \
      LEADV2_SKIP_DRIFT_GUARD=1 \
      bash "$FANOUT_SH" --provider claude --dry-run --tasks FCG-T1 2>&1
  )" || true
  rm -rf "$sandbox"
  if [[ "$out" == *"class=Standard"* && "$out" != *"classify script unavailable"* ]]; then
    pass "Test 2: class=Standard, classifier ran normally"
  else
    fail "Test 2: out=$out"
  fi
}

test_3_classify_missing_safe_fallback() {
  log "Test 3: classify script hidden -> loud WARN + safe fallback (NOT Heavy)"
  local sandbox out hidden
  sandbox="$(_new_sandbox)"
  hidden="${CLASSIFY_SH}.hidden-for-test"
  mv "$CLASSIFY_SH" "$hidden"
  trap 'mv "'"$hidden"'" "'"$CLASSIFY_SH"'" 2>/dev/null || true' RETURN
  out="$(
    LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" \
      LEADV2_SKIP_DRIFT_GUARD=1 \
      bash "$FANOUT_SH" --provider claude --dry-run --tasks FCG-T1 2>&1
  )" || true
  mv "$hidden" "$CLASSIFY_SH"
  trap - RETURN
  rm -rf "$sandbox"
  if [[ "$out" == *"WARN: leadv2-fanout-classify.sh missing"* && "$out" == *"class=Standard"* && "$out" != *"class=Heavy"* ]]; then
    pass "Test 3: loud WARN printed, class=Standard (no silent Heavy escalation)"
  else
    fail "Test 3: out=$out"
  fi
}

test_4_runner_missing_fails_closed() {
  log "Test 4: session-runner hidden -> real headless launch fails closed"
  local sandbox out hidden stub
  sandbox="$(_new_sandbox)"
  hidden="${RUNNER_SH}.hidden-for-test"
  mv "$RUNNER_SH" "$hidden"
  trap 'mv "'"$hidden"'" "'"$RUNNER_SH"'" 2>/dev/null || true' RETURN
  stub="${sandbox}/claude-stub.sh"
  cat > "$stub" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$stub"
  out="$(
    LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" \
      LEADV2_SKIP_DRIFT_GUARD=1 \
      LEADV2_FANOUT_CLAUDE_BIN="$stub" \
      bash "$FANOUT_SH" --provider claude --headless --tasks FCG-T1 2>&1
  )" || true
  mv "$hidden" "$RUNNER_SH"
  trap - RETURN
  rm -rf "$sandbox"
  if [[ "$out" == *"ERROR: leadv2-session-runner.sh missing/not executable"* && "$out" != *"headless launch: task=FCG-T1"* ]]; then
    pass "Test 4: missing completion runner refused the launch"
  else
    fail "Test 4: out=$out"
  fi
}

# Fanout's fail-closed preflight needs `import yaml`. On hosts where PyYAML
# lives in the USER site-packages, overriding HOME (tests 5/6) hides it and
# python3 dies with ModuleNotFoundError — which fanout misreports as "not
# valid YAML". Carry the real user site-packages via PYTHONPATH so a HOME
# override isolates the registry resolution, not the interpreter.
_PY_SITE="$(python3 -c 'import yaml, os; print(os.path.dirname(os.path.dirname(yaml.__file__)))' 2>/dev/null || true)"

test_5_registry_resolution_no_host_deps() {
  log "Test 5: registry resolves via SCRIPT_DIR sibling alone -- no host \$HOME, no vendored .claude/scripts; active.yaml under LEADV2_STATE_ROOT"
  local sandbox out emptyhome
  sandbox="$(_new_sandbox)"
  rm -rf "${sandbox}/proj/.claude/scripts"
  # H5 (MERGED-BATCH-FIXROUND-01): stage the state-path resolver where the
  # registry looks for it (${LEADV2_PROJECT_ROOT}/scripts/), move the
  # active.yaml fixture into the state root, and remove the repo-relative
  # copy. If the chosen registry copy routes active.yaml through the
  # resolver, the run finds it under the state root and succeeds; a copy
  # that still hardcodes docs/leadv2/active.yaml fails closed instead.
  mkdir -p "${sandbox}/proj/scripts"
  cp "${SCRIPTS_ROOT}/leadv2-state-path.sh" "${sandbox}/proj/scripts/leadv2-state-path.sh"
  chmod +x "${sandbox}/proj/scripts/leadv2-state-path.sh"
  mv "${sandbox}/proj/docs/leadv2/active.yaml" "${sandbox}/state/active.yaml"
  emptyhome="${sandbox}/emptyhome"
  mkdir -p "$emptyhome"
  out="$(
    HOME="$emptyhome" PYTHONPATH="${_PY_SITE:+${_PY_SITE}${PYTHONPATH:+:${PYTHONPATH}}}" \
      LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" \
      LEADV2_SKIP_DRIFT_GUARD=1 \
      bash "$FANOUT_SH" --provider claude --dry-run --tasks FCG-T1 2>&1
  )" || true
  local reg_ok=1
  # The property: registry file lives under the state root; the repo-relative
  # path is at most a symlink the resolver created, never a real file.
  if [[ ! -f "${sandbox}/state/active.yaml" ]] \
     || { [[ -e "${sandbox}/proj/docs/leadv2/active.yaml" ]] && [[ ! -L "${sandbox}/proj/docs/leadv2/active.yaml" ]]; }; then
    reg_ok=0
  fi
  rm -rf "$sandbox"
  if [[ "$out" == *"class=Standard"* && "$reg_ok" == "1" ]]; then
    pass "Test 5: sibling-only resolution sufficient; active.yaml read from state root, no real file at docs/leadv2/"
  else
    fail "Test 5: out=$out reg_ok=$reg_ok"
  fi
}

# H5 (MERGED-BATCH-FIXROUND-01): the resolution chain must SKIP a candidate
# that predates the control-plane state-path resolution (no
# leadv2-state-path.sh reference), not prefer it by position. Sibling-first
# is an availability ordering; the property is the invariant.
test_6_registry_property_rejects_stale_copy() {
  log "Test 6: stale (pre-state-path) registry copy is skipped; all-stale refuses to launch"
  local sandbox out hidden sibling stub
  # -- Part A: sibling stale, vendored copy valid -> chain skips to vendored.
  sandbox="$(_new_sandbox)"
  sibling="${SCRIPTS_ROOT}/leadv2-active-registry.sh"
  hidden="${sibling}.hidden-for-test"
  mv "$sibling" "$hidden"
  trap 'mv "'"$hidden"'" "'"$sibling"'" 2>/dev/null || true' RETURN
  printf '#!/usr/bin/env bash\n# stale copy predating the control-plane state-path resolution\n' > "$sibling"
  out="$(
    LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" \
    LEADV2_CANONICAL_ROOT="${sandbox}/empty" \
      LEADV2_SKIP_DRIFT_GUARD=1 \
      bash "$FANOUT_SH" --provider claude --dry-run --tasks FCG-T1 2>&1
  )" || true
  rm -rf "$sandbox"
  if [[ "$out" == *"class=Standard"* ]]; then
    pass "Test 6a: stale sibling skipped, vendored (state-path-aware) copy used"
  else
    fail "Test 6a: out=$out"
  fi
  # -- Part B: every candidate stale or absent -> refuse to launch.
  sandbox="$(_new_sandbox)"
  rm -rf "${sandbox}/proj/.claude/scripts"
  mkdir -p "${sandbox}/emptyhome" "${sandbox}/empty"
  out="$(
    HOME="${sandbox}/emptyhome" PYTHONPATH="${_PY_SITE:+${_PY_SITE}${PYTHONPATH:+:${PYTHONPATH}}}" \
      LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" \
    LEADV2_CANONICAL_ROOT="${sandbox}/empty" \
      LEADV2_SKIP_DRIFT_GUARD=1 \
      bash "$FANOUT_SH" --provider claude --dry-run --tasks FCG-T1 2>&1
  )" || true
  rm -rf "$sandbox"
  mv "$hidden" "$sibling"
  trap - RETURN
  if [[ "$out" == *"predates the control-plane state-path resolution"* && "$out" != *"class=Standard"* ]]; then
    pass "Test 6b: all candidates stale -> loud refusal, no launch"
  else
    fail "Test 6b: out=$out"
  fi
}

main() {
  log "=== leadv2-fanout.sh classify/runner existence-guard tests ==="
  log "fanout: $FANOUT_SH"
  echo ""
  test_1_syntax
  test_2_classify_present_standard
  test_3_classify_missing_safe_fallback
  test_4_runner_missing_fails_closed
  test_5_registry_resolution_no_host_deps
  test_6_registry_property_rejects_stale_copy
  echo ""
  log "=== Results: PASS=$PASS FAIL=$FAIL ==="
  if [[ "${#ERRORS[@]}" -gt 0 ]]; then
    log "Failures:"
    for e in "${ERRORS[@]}"; do log "  $e"; done
    exit 1
  fi
  log "All tests passed."
  exit 0
}

main "$@"
