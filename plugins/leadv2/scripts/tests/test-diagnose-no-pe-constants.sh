#!/usr/bin/env bash
# tests/test-diagnose-no-pe-constants.sh — design §7 test 10.
#
# Asserts that the diagnose engine's assembled prompt contains NEITHER
# journalctl -u persona-engine NOR persona-engine table names — i.e., the
# engine is portable across repos and does not hardcode PE-specific constants.
#
# This is a source-level assertion: grep the engine for any PE constant.
#
# Run: bash plugins/leadv2/scripts/tests/test-diagnose-no-pe-constants.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${SCRIPTS_ROOT}/leadv2-plan-run.sh"

PASS=0; FAIL=0
log()  { printf -- '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

# Search for any persona-engine constant in NON-COMMENT lines only
# (engine comments may reference the concept without embedding it in code).
_engine_nocomments="$(grep -vE '^\s*#' "${ENGINE}" 2>/dev/null)"
_pe_found=""
if printf '%s\n' "${_engine_nocomments}" | grep -qi 'journalctl.*persona-engine' 2>/dev/null; then
  _pe_found="${_pe_found} journalctl-persona-engine"
fi
if printf '%s\n' "${_engine_nocomments}" | grep -qiE 'persona_engine\b' 2>/dev/null; then
  _pe_found="${_pe_found} persona_engine-identifier"
fi
if printf '%s\n' "${_engine_nocomments}" | grep -qi 'persona-engine' 2>/dev/null; then
  _pe_found="${_pe_found} persona-engine-string"
fi

if [[ -z "${_pe_found}" ]]; then
  pass "engine contains no persona-engine constants"
else
  fail "engine contains PE constants:${_pe_found}"
fi

# Also verify the engine does not default --log-path to any PE-specific path.
if printf '%s\n' "${_engine_nocomments}" | grep -q 'journalctl' 2>/dev/null; then
  fail "engine contains a journalctl call (not portable)"
else
  pass "engine has no journalctl calls"
fi

printf -- '\nResults: %d pass, %d fail\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == "0" ]] || exit 1
exit 0
