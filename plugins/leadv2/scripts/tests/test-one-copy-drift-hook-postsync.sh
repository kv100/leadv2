#!/usr/bin/env bash
# tests/test-one-copy-drift-hook-postsync.sh — T16 §7: the plugin-sync
# drift-warn leg lives INSIDE leadv2-one-copy-drift.sh now (single hook, one
# report). Pins the merged hook's three contracts against a scratch canonical
# root (TEST-DESTROYS-PRODUCTION-SCRIPT-01 containment; same pattern as
# test-one-copy-drift.sh):
#   T1  PostToolUse payload whose command ran leadv2-plugin-sync.sh
#       -> BOTH checks run and land in ONE report block
#   T2  PostToolUse payload for any other command -> silent, NO check runs
#   T3  SessionStart-style payload (no tool_name) -> one-copy check only,
#       drift-guard NOT invoked
#   T4  LEADV2_ONE_COPY_DRIFT=0 -> silent even after a sync
#
# Run: bash scripts/tests/test-one-copy-drift-hook-postsync.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/leadv2-one-copy-drift.sh"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

bash -n "${HOOK}" 2>/dev/null && pass "bash -n hook" || fail "bash -n hook"

# Fixture canonical root: CLAUDE_PLUGIN_ROOT=<root>/plugins/leadv2 makes the
# hook's resolve_canonical_root land on <root> (needs <root>/.git). Both
# checked scripts are stubs so the verdicts are deterministic and observable.
mk_fixture() {
  local tmp; tmp="$(lv2_mktemp_dir one-copy-hook-fixture)"
  local root="${tmp}/canon"
  mkdir -p "${root}/.git" "${root}/plugins/leadv2/scripts"
  cat > "${root}/plugins/leadv2/scripts/leadv2-one-copy-convert.sh" <<'STUB'
#!/usr/bin/env bash
echo "[one-copy] REGRESSION: fixture-copy.sh is a real file, identical to canonical" >&2
echo "[one-copy] tally: 1 regression, 0 badlinks" >&2
exit 1
STUB
  cat > "${root}/plugins/leadv2/scripts/leadv2-drift-guard.sh" <<'STUB'
#!/usr/bin/env bash
echo "fixture drift detail" >&2
: > "$DRIFT_GUARD_PROBE"
[[ -f "$DRIFT_GUARD_FAIL" ]]
STUB
  chmod +x "${root}/plugins/leadv2/scripts/leadv2-one-copy-convert.sh" \
            "${root}/plugins/leadv2/scripts/leadv2-drift-guard.sh"
  printf '%s' "$root"
}

run_hook() { # <payload-json> -> sets STDOUT, STDERR, RC
  local base
  base="$(lv2_mktemp_dir one-copy-hook-output)"
  printf '%s' "$1" | \
    HOME="${ROOT}" \
    CLAUDE_PLUGIN_ROOT="${ROOT}/plugins/leadv2" \
    DRIFT_GUARD_PROBE="${PROBE}" DRIFT_GUARD_FAIL="${FAILFLAG}" \
    bash "${HOOK}" >"${base}/stdout" 2>"${base}/stderr"
  RC=$?
  STDOUT="$(<"${base}/stdout")"
  STDERR="$(<"${base}/stderr")"
}

ROOT="$(mk_fixture)"
PROBE="${ROOT}/.drift-guard-probe"
FAILFLAG="${ROOT}/.drift-guard-should-fail"

# ── T1: post-sync -> one report with both legs ──────────────────────────
rm -f "$PROBE" "$FAILFLAG"   # drift-guard FAILS (divergence persists)
run_hook '{"tool_name":"Bash","tool_input":{"command":"bash ~/x/leadv2-plugin-sync.sh --apply"}}'
if [[ "$RC" -eq 0 ]] \
   && grep -q 'one-copy drift' <<<"$STDOUT" \
   && grep -q 'regression(s)/badlink(s)' <<<"$STDOUT" \
   && ! grep -q 'drift-guard\] WARNING' <<<"$STDOUT" \
   && grep -q '\[drift-guard\] WARNING: leadv2-plugin-sync.sh just ran' <<<"$STDERR" \
   && ! grep -q 'one-copy drift' <<<"$STDERR"; then
  pass "T1 post-sync: base report stdout, WARNING stderr, rc 0"
else
  fail "T1 post-sync: base report stdout, WARNING stderr, rc 0 (rc=$RC stdout=$STDOUT stderr=$STDERR)"
fi
[[ -f "$PROBE" ]] && pass "T1 drift-guard was actually invoked" || fail "T1 drift-guard was actually invoked"

# Same invocation, drift now clean -> one-copy lines only, no WARNING
rm -f "$PROBE"; : > "$FAILFLAG"
run_hook '{"tool_name":"Bash","tool_input":{"command":"bash leadv2-plugin-sync.sh"}}'
if [[ "$RC" -eq 0 ]] && grep -q 'regression(s)/badlink(s)' <<<"$STDOUT" && [[ -z "$STDERR" ]]; then
  pass "T1b post-sync, drift-guard clean: no WARNING leg"
else
  fail "T1b post-sync, drift-guard clean: no WARNING leg (rc=$RC stdout=$STDOUT stderr=$STDERR)"
fi

# ── T2: ordinary PostToolUse command -> silent, no checks ───────────────
rm -f "$PROBE"
run_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
if [[ "$RC" -eq 0 && -z "$STDOUT" && -z "$STDERR" && ! -f "$PROBE" ]]; then
  pass "T2 ordinary PostToolUse: silent, no check"
else
  fail "T2 ordinary PostToolUse: silent, no check (rc=$RC stdout=$STDOUT stderr=$STDERR probe=$PROBE)"
fi

# ── T3: SessionStart payload -> one-copy only, drift-guard not run ──────
rm -f "$PROBE"
run_hook '{"source":"startup","cwd":"/tmp"}'
if [[ "$RC" -eq 0 ]] && grep -q 'one-copy drift' <<<"$STDOUT" && grep -q 'regression(s)/badlink(s)' <<<"$STDOUT" \
   && [[ -z "$STDERR" ]] && [[ ! -f "$PROBE" ]]; then
  pass "T3 SessionStart payload: one-copy leg only"
else
  fail "T3 SessionStart payload: one-copy leg only (rc=$RC stdout=$STDOUT stderr=$STDERR)"
fi

# ── T4: kill switch ─────────────────────────────────────────────────────
rm -f "$PROBE"
OUT="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"leadv2-plugin-sync.sh"}}' | \
  LEADV2_ONE_COPY_DRIFT=0 \
  HOME="${ROOT}" \
  CLAUDE_PLUGIN_ROOT="${ROOT}/plugins/leadv2" bash "${HOOK}" 2>&1)"
if [[ $? -eq 0 && -z "$OUT" && ! -f "$PROBE" ]]; then
  pass "T4 LEADV2_ONE_COPY_DRIFT=0: fully silent"
else
  fail "T4 LEADV2_ONE_COPY_DRIFT=0: fully silent (out=$OUT)"
fi

printf -- '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
