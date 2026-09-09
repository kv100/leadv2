#!/usr/bin/env bash
# run-all-triggers: leadv2-state-path
# tests/test-state-path-zsh-refusal.sh — STATE-PATH-RESOLVER-FAILS-OPEN-UNDER-ZSH-01
#
# leadv2-state-path.sh locates itself via BASH_SOURCE[0]. Sourced from zsh
# that variable does not exist, and the resolver used to fail OPEN: either a
# `set -u` crash whose diagnostic named the wrong thing ("no such file:
# <cwd>/leadv2-portable-lock.sh", rc 127) or — when the caller's cwd happened
# to sit next to a leadv2-portable-lock.sh — a silent continue with SCRIPT_DIR
# pinned to the CALLER'S CWD. Measured 2026-09-04: the sourced-from-zsh shape
# handed callers the repo-relative <repo>/docs/leadv2/active.yaml instead of
# the live control-plane path and returned rc=0.
#
# The contract under test (row 518b42814626):
#   * source from zsh MUST refuse closed — non-zero rc, zero stdout bytes,
#     one stderr line naming the real cause (not_file_backed_bash), never a
#     repo-relative path — independent of cwd.
#   * the same file, executed (or sourced from real bash), MUST keep
#     resolving the control-plane root.
#
# Every green assertion has a paired in-suite negative control: the guard is
# deleted from a scratch copy and the same zsh probe must then FAIL OPEN
# (rc=0 + a printed path). A suite that cannot go red cannot prove green.
#
# Portable: no GNU-only date/sed -i/timeout/flock. bash 3.2 compatible.
# Run: bash plugins/leadv2/scripts/tests/test-state-path-zsh-refusal.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
source "${SCRIPT_DIR}/../leadv2-temp.sh"

STATE_PATH_SH="${SCRIPT_DIR}/../leadv2-state-path.sh"
PORTABLE_LOCK_SH="${SCRIPT_DIR}/../leadv2-portable-lock.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# zsh may be absent on lean CI images: the zsh-dependent cases then SKIP
# loudly (printed, not hidden) instead of failing. On every dev mac and the
# machines this row was measured on, zsh is present and nothing skips.
ZSH_BIN="$(command -v zsh 2>/dev/null || true)"

# ── shared probe ─────────────────────────────────────────────────────────────
# _zsh_source_probe <cwd> <resolver-path> -> sets PROBE_RC/OUT/ERR
_zsh_source_probe() {
  local cwd="$1" resolver="$2"
  PROBE_OUT="$(cd "$cwd" && "$ZSH_BIN" -c "source '$resolver'" 2>"${TMPDIR:-/tmp}/zsr.err.$$")"
  PROBE_RC=$?
  PROBE_ERR="$(cat "${TMPDIR:-/tmp}/zsr.err.$$" 2>/dev/null || true)"
  rm -f "${TMPDIR:-/tmp}/zsr.err.$$"
}

# ── Test 1: sourced from zsh, cwd = the scripts dir (the fail-open trap) ────
# The scripts dir is exactly the cwd where the old code "found" a sibling
# leadv2-portable-lock.sh by accident and kept going. It must refuse here.
test_1_zsh_source_refuses_in_scripts_dir() {
  [[ -n "$ZSH_BIN" ]] || { log "SKIP: zsh not installed — test 1 needs a zsh to source with"; return 0; }
  _zsh_source_probe "${SCRIPT_DIR}/.." "${STATE_PATH_SH}"
  if [[ "$PROBE_RC" -ne 0 && -z "$PROBE_OUT" \
        && "$PROBE_ERR" == *'ABORT rc=4 reason=not_file_backed_bash'* ]]; then
    pass "zsh source from the scripts dir refuses closed (rc=$PROBE_RC, stdout empty)"
  else
    fail "zsh source from the scripts dir: rc=$PROBE_RC out='${PROBE_OUT}' err='${PROBE_ERR:0:200}'"
  fi
  # The old crash named the WRONG cause (a missing portable-lock at the
  # caller's cwd). The refusal must name BASH_SOURCE, not a file lookup.
  if [[ "$PROBE_ERR" != *'portable-lock'* ]]; then
    pass "refusal names the real cause, not a bogus portable-lock lookup"
  else
    fail "refusal diagnostic mentions portable-lock (misleading old shape): ${PROBE_ERR:0:200}"
  fi
}

# ── Test 2: sourced from zsh, cwd with no sibling scripts (neutral cwd) ─────
test_2_zsh_source_refuses_in_neutral_cwd() {
  [[ -n "$ZSH_BIN" ]] || { log "SKIP: zsh not installed — test 2 needs a zsh to source with"; return 0; }
  local d; d="$(lv2_mktemp_dir zsh-refusal-neutral)"
  _zsh_source_probe "$d" "${STATE_PATH_SH}"
  if [[ "$PROBE_RC" -ne 0 && -z "$PROBE_OUT" \
        && "$PROBE_ERR" == *'ABORT rc=4 reason=not_file_backed_bash'* ]]; then
    pass "zsh source from a neutral cwd refuses closed (rc=$PROBE_RC)"
  else
    fail "zsh source from a neutral cwd: rc=$PROBE_RC out='${PROBE_OUT}' err='${PROBE_ERR:0:200}'"
  fi
  rm -rf "$d"
}

# ── Test 3: executed under bash resolves the control-plane root ─────────────
test_3_bash_exec_resolves_state_root() {
  local d sbx out rc
  d="$(lv2_mktemp_dir zsh-refusal-exec)"
  sbx="${d}/state"
  mkdir -p "${d}/nogit"
  out="$(LEADV2_STATE_ROOT="$sbx" PROJECT_ROOT="${d}/nogit" \
    bash "${STATE_PATH_SH}" --no-link active.yaml 2>/dev/null)"
  rc=$?
  if [[ "$rc" -eq 0 && "$out" == "${sbx}/active.yaml" && "$out" != *'/docs/leadv2/'* ]]; then
    pass "executed under bash: control-plane root, not a repo-relative path"
  else
    fail "bash exec: rc=$rc out='$out'"
  fi
  rm -rf "$d"
}

# ── Test 4: sourced from a REAL bash file context still works ───────────────
# The guard must refuse zsh/no-file-backing sourcing, never bash itself.
test_4_bash_file_context_source_works() {
  local d sbx out rc runner
  d="$(lv2_mktemp_dir zsh-refusal-bsrc)"
  sbx="${d}/state"
  mkdir -p "${d}/nogit"
  runner="${d}/call-resolver.sh"
  cat > "$runner" <<EOF
#!/usr/bin/env bash
source "${STATE_PATH_SH}" --no-link active.yaml
EOF
  out="$(LEADV2_STATE_ROOT="$sbx" PROJECT_ROOT="${d}/nogit" \
    HOME="$d" bash "$runner" 2>/dev/null)"
  rc=$?
  if [[ "$rc" -eq 0 && "$out" == "${sbx}/active.yaml" ]]; then
    pass "sourced from a real bash file context: resolves normally"
  else
    fail "bash file-context source: rc=$rc out='$out'"
  fi
  rm -rf "$d"
}

# ── Test 5: negative control — guard deleted from a scratch copy ────────────
# With the guard gone, the SAME zsh-source probe (cwd holding a copied
# leadv2-portable-lock.sh — the trap shape) must FAIL OPEN: rc=0 and a printed
# path. If the mutated copy still refuses, this suite cannot detect guard
# removal and its green proves nothing.
test_5_negative_control_guard_removed() {
  [[ -n "$ZSH_BIN" ]] || { log "SKIP: zsh not installed — test 5 negative control needs zsh"; return 0; }
  local d mutated out rc
  d="$(lv2_mktemp_dir zsh-refusal-mut)"
  mkdir -p "${d}/nogit"
  cp "${STATE_PATH_SH}" "${d}/leadv2-state-path.sh"
  cp "${PORTABLE_LOCK_SH}" "${d}/leadv2-portable-lock.sh"
  mutated="${d}/leadv2-state-path.sh"
  python3 - "$mutated" <<'PYEOF' || { fail "negative control: patcher could not find the guard block"; rm -rf "$d"; return 0; }
import sys
path = sys.argv[1]
lines = open(path).read().split('\n')
start = end = None
for i, ln in enumerate(lines):
    if ln.startswith('if [[ -z "${BASH_VERSION:-}" || -z "${BASH_SOURCE[0]:-}" ]]'):
        start = i
        break
if start is not None:
    for j in range(start + 1, len(lines)):
        if lines[j] == 'fi':
            end = j
            break
if start is None or end is None:
    sys.exit(1)
open(path, 'w').write('\n'.join(lines[:start] + lines[end + 1:]))
PYEOF
  # env sandboxed: even the fail-open mutant can only resolve inside $d
  out="$(cd "$d" && LEADV2_STATE_ROOT="${d}/state2" PROJECT_ROOT="${d}/nogit" HOME="$d" \
    "$ZSH_BIN" -c "source '${mutated}'" 2>/dev/null)"
  rc=$?
  if [[ "$rc" -eq 0 && -n "$out" ]]; then
    pass "negative control confirmed: guard-less copy fails OPEN under zsh (rc=0, printed '$out')"
  else
    fail "negative control did NOT flip: mutated copy still refused (rc=$rc out='$out') — green assertions may be testing nothing"
  fi
  rm -rf "$d"
}

# ── Test 6: syntax ──────────────────────────────────────────────────────────
test_6_syntax() {
  if bash -n "${STATE_PATH_SH}" 2>/dev/null; then
    pass "bash -n clean"
  else
    fail "bash -n failed on leadv2-state-path.sh"
  fi
}

test_1_zsh_source_refuses_in_scripts_dir
test_2_zsh_source_refuses_in_neutral_cwd
test_3_bash_exec_resolves_state_root
test_4_bash_file_context_source_works
test_5_negative_control_guard_removed
test_6_syntax

log "----------------------------------------"
log "RESULTS: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  for e in "${ERRORS[@]}"; do log "$e"; done
  exit 1
fi
exit 0
