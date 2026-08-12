#!/usr/bin/env bash
# tests/test-workflows-copies-are-symlinks.sh — design §7 test 8.
#
# Asserts that ~/.claude/workflows/leadv2-plan.js and leadv2-diagnose.js are
# symlinks into plugins/leadv2/workflows/ (not copies — the 2026-07-29 defect
# root cause was a stale copy drifting from canonical).
#
# NOTE: These files live under $HOME, outside this repo. This test PASSES only
# after the step-0 chore (design step 0) has converted the copies to symlinks.
# If the files don't exist yet (e.g., the JS workflows haven't been installed),
# the test reports SKIP, not FAIL.
#
# Run: bash plugins/leadv2/scripts/tests/test-workflows-copies-are-symlinks.sh
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOME_WORKFLOWS="${HOME}/.claude/workflows"

PASS=0; FAIL=0; SKIP=0
log()  { printf -- '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }
skip() { log "SKIP: $*"; SKIP=$((SKIP + 1)); }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

for _js in leadv2-plan.js leadv2-diagnose.js; do
  _target="${HOME_WORKFLOWS}/${_js}"
  if [[ ! -e "${_target}" ]]; then
    skip "${_js} not found under ${HOME_WORKFLOWS} (step-0 chore may not have run)"
    continue
  fi
  if [[ -L "${_target}" ]]; then
    _link_target="$(readlink "${_target}")"
    case "${_link_target}" in
      *plugins/leadv2/workflows/*|*leadv2*)
        pass "${_js} is a symlink → ${_link_target}"
        ;;
      *)
        fail "${_js} is a symlink but points to unexpected target: ${_link_target}"
        ;;
    esac
  else
    fail "${_js} is a COPY (regular file), not a symlink — violates shared-trees policy"
  fi
done

printf -- '\nResults: %d pass, %d fail, %d skip\n' "${PASS}" "${FAIL}" "${SKIP}"
# Skips are OK — the step-0 chore may not have run in this lane.
[[ "${FAIL}" == "0" ]] || exit 1
exit 0
