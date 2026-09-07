#!/usr/bin/env bash
# run-all-triggers: leadv2-claude-profile-select.sh claude-subsession.sh
# test-claude-profile-requested.sh — NO-WAY-TO-PIN-A-DISPATCH-TO-A-NAMED-ACCOUNT-01.
#
# Acceptance, three points: (1) the requested label appears in the selector's
# own output line alongside identity=; (2) a requested-but-unavailable profile
# is a HARD refusal (non-zero exit), never a silent fall-through to the
# balancer; (3) with no request at all, the balancer's existing behaviour
# (including its own soft single_profile fallback) is byte-identical to
# before this feature landed.
#
# Warning kept from the founder's own correction earlier tonight: a bare
# "selected label == requested" check is a fine test HERE (pinning is exactly
# what this suite verifies), but is the WRONG criterion for testing the
# balancer itself -- it reads red on a healthy balanced system and green on a
# stuck one. This suite tests pinning only; it says nothing about balancing.
set -uo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEL="${_HERE}/../leadv2-claude-profile-select.sh"
FAIL=0
ok()  { echo "  PASS: $1"; }
bad() { echo "  FAIL: $1"; FAIL=1; }

SBX="$(mktemp -d)"
trap 'rm -rf "$SBX"' EXIT
mkdir -p "$SBX/work-dir" "$SBX/personal-dir"
REGISTRY="$SBX/registry.tsv"
cat > "$REGISTRY" <<TSV
work	${SBX}/work-dir	file:${SBX}/work-dir/.credentials.json
personal	${SBX}/personal-dir	file:${SBX}/personal-dir/.credentials.json
TSV

echo "== 1: requested + registry has it + probe completes -> selects it, identity= present =="
out="$(LEADV2_CLAUDE_PROFILES_FILE="$REGISTRY" LEADV2_CLAUDE_PROFILE_REQUESTED=work bash "$SEL" 2>/dev/null)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "exits 0"; else bad "expected rc=0, got $rc"; fi
[[ "$out" == profile=work* ]] && ok "selector line names the requested label (profile=work)" \
  || bad "expected profile=work, got: $out"
[[ "$out" == *identity=* ]] && ok "selector line carries identity=" \
  || bad "missing identity= in: $out"

echo "== 2: NEGATIVE CONTROL a -- requested label absent from registry: HARD refusal =="
out="$(LEADV2_CLAUDE_PROFILES_FILE="$REGISTRY" LEADV2_CLAUDE_PROFILE_REQUESTED=doesnotexist bash "$SEL" 2>/dev/null)"
rc=$?
[[ $rc -ne 0 ]] && ok "exits non-zero (rc=$rc)" || bad "expected non-zero exit, got 0"
[[ "$out" == "profile=- reason=requested_profile_unknown requested=doesnotexist" ]] \
  && ok "names the exact reason and the requested label" \
  || bad "unexpected output: $out"

echo "== 3: NEGATIVE CONTROL b -- requested label present but its probe cannot complete: HARD refusal, not the balancer's soft fallback =="
BADPROBE="$SBX/always-fail.py"
printf 'import sys\nsys.exit(1)\n' > "$BADPROBE"
out="$(LEADV2_CLAUDE_PROFILES_FILE="$REGISTRY" LEADV2_CLAUDE_PROFILE_REQUESTED=work \
      LEADV2_CLAUDE_PROFILE_PROBE="$BADPROBE" bash "$SEL" 2>/dev/null)"
rc=$?
[[ $rc -ne 0 ]] && ok "exits non-zero (rc=$rc)" || bad "expected non-zero exit, got 0"
[[ "$out" == "profile=- reason=requested_profile_unavailable requested=work" ]] \
  && ok "names requested_profile_unavailable, not single_profile" \
  || bad "unexpected output (must not silently fall back to the balancer): $out"

echo "== 4: REGRESSION -- no request at all, same failing probe: balancer's own soft fallback is unchanged (exit 0, single_profile) =="
out="$(LEADV2_CLAUDE_PROFILES_FILE="$REGISTRY" LEADV2_CLAUDE_MULTIPROFILE=1 \
      LEADV2_CLAUDE_PROFILE_PROBE="$BADPROBE" bash "$SEL" 2>/dev/null)"
rc=$?
[[ $rc -eq 0 ]] && ok "exits 0 (balancer path untouched)" || bad "expected rc=0, got $rc"
[[ "$out" == "profile=- reason=single_profile" ]] \
  && ok "still soft single_profile, byte-identical to pre-feature behaviour" \
  || bad "unexpected output: $out"

if [[ "$FAIL" == "1" ]]; then echo "[CLAUDE-PROFILE-REQUESTED] FAILED"; exit 1; fi
echo "[CLAUDE-PROFILE-REQUESTED] All checks passed"
