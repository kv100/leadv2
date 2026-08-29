#!/usr/bin/env bash
# LANE-WRITESET-REGISTRY-01: admission must be atomic, distinguish legacy
# unknown rows, and make the commit-time drift re-check observable.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_SH="${SCRIPT_DIR}/../leadv2-active-registry.sh"

PASS=0; FAIL=0
log()  { printf '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

new_sandbox() {
  local root
  root="$(lv2_mktemp_dir "writeset-admission")"
  mkdir -p "${root}/docs/leadv2"
  printf '%s\n' "$root"
}

run_live_signal() {
  local root="$1" out rc active
  active="${root}/docs/leadv2/active.yaml"
  out="$(
    LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" \
      LEADV2_WRITESET_ENFORCE=block bash -s "$REGISTRY_SH" "$root" <<'EOF'
set -e
source "$1"
root="$2"
leadv2_active_register "LANE-A" Standard "$root" wt-A false "" "" "plugins/leadv2/scripts/leadv2-dispatch-code.sh" >/dev/null
set +e
out="$(leadv2_active_register "LANE-B" Standard "$root" wt-B false "" "" "plugins/leadv2/scripts/leadv2-dispatch-code.sh" 2>&1)"; rc=$?
set -e
printf 'rc=%s\n%s\n' "$rc" "$out"
EOF
  )" || true
  rc="$(printf '%s\n' "$out" | sed -n 's/^rc=//p' | head -1)"
  if [[ "$rc" == 5 ]] && grep -q 'writeset conflict: other=LANE-A' <<<"$out" \
      && ! grep -q 'task_id: LANE-B' "$active"; then
    pass "live signal: rc=5, conflict names LANE-A, LANE-B not appended"
  else
    fail "live signal: ${out}"
  fi
}

run_race() {
  local root="$1" rca rcb total
  (
    LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" LEADV2_WRITESET_ENFORCE=block \
      bash -c 'source "$1"; leadv2_active_register RACE-A Standard "$2" a false "" "" target/path >/dev/null' _ "$REGISTRY_SH" "$root"
  ) & local pa=$!
  (
    LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" LEADV2_WRITESET_ENFORCE=block \
      bash -c 'source "$1"; leadv2_active_register RACE-B Standard "$2" b false "" "" target/path >/dev/null' _ "$REGISTRY_SH" "$root"
  ) & local pb=$!
  set +e; wait "$pa"; rca=$?; wait "$pb"; rcb=$?; set -e
  total="$(grep -c 'task_id: RACE-' "${root}/docs/leadv2/active.yaml" 2>/dev/null || true)"
  if [[ "$total" == 1 ]] && { [[ "$rca" == 0 && "$rcb" == 5 ]] || [[ "$rca" == 5 && "$rcb" == 0 ]]; }; then
    pass "race: exactly one intersecting register wins under the registry lock"
  else
    fail "race: rc_a=${rca} rc_b=${rcb} registered=${total}"
  fi
}

run_legacy_and_drift() {
  local root="$1" warn_rc block_rc free_rc hit_rc
  cat > "${root}/docs/leadv2/active.yaml" <<'YAML'
meta: {}
sessions:
  - task_id: LEGACY
    stale: false
YAML
  set +e
  LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" LEADV2_WRITESET_ENFORCE=warn \
    bash -c 'source "$1"; leadv2_active_register CANDIDATE Standard "$2" c false "" "" declared/a >/dev/null' _ "$REGISTRY_SH" "$root"; warn_rc=$?
  LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" LEADV2_WRITESET_ENFORCE=block \
    bash -c 'source "$1"; leadv2_active_register BLOCKED Standard "$2" b false "" "" declared/b >/dev/null' _ "$REGISTRY_SH" "$root"; block_rc=$?
  set -e
  cat > "${root}/docs/leadv2/active.yaml" <<'YAML'
meta: {}
sessions:
  - task_id: PEER
    stale: false
    writes: contested/b
YAML
  set +e
  LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" LEADV2_WRITESET_ENFORCE=block \
    bash -c 'source "$1"; leadv2_active_check_writes_conflict SELF free/a' _ "$REGISTRY_SH" "$root"; free_rc=$?
  LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" LEADV2_WRITESET_ENFORCE=block \
    bash -c 'source "$1"; leadv2_active_check_writes_conflict SELF contested/b' _ "$REGISTRY_SH" "$root"; hit_rc=$?
  set -e
  if [[ "$warn_rc" == 0 && "$block_rc" == 6 && "$free_rc" == 0 && "$hit_rc" == 5 ]]; then
    pass "legacy and drift re-check: warn admits, block=6, free=0, contested=5"
  else
    fail "legacy and drift re-check: warn=${warn_rc} block=${block_rc} free=${free_rc} hit=${hit_rc}"
  fi
}

main() {
  local a b c
  log "=== lane write-set admission block (LANE-WRITESET-REGISTRY-01) ==="
  a="$(new_sandbox)"; b="$(new_sandbox)"; c="$(new_sandbox)"
  trap 'rm -rf "${a:-}" "${b:-}" "${c:-}"' EXIT
  run_live_signal "$a"
  run_race "$b"
  run_legacy_and_drift "$c"
  log "=== Results: PASS=${PASS} FAIL=${FAIL} ==="
  [[ "$FAIL" == 0 ]]
}

main "$@"
