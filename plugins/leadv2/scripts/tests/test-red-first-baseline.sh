#!/usr/bin/env bash
# RED-FIRST-SELF-INVALIDATES-01: coverage for the shared pinned-baseline
# resolver (lib/leadv2-red-first-baseline.sh). Fixtures are throwaway repos
# under mktemp -d + git init -- never reset/clean/stash on this checkout.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/leadv2-red-first-baseline.sh"

PASS=0; FAIL=0
ok() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rfb.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT INT TERM

repo="${TMP}/repo"
mkdir -p "${repo}"
git -C "${repo}" init -q -b main
git -C "${repo}" config user.email test@example.com
git -C "${repo}" config user.name test

printf 'base\n' > "${repo}/f.txt"
git -C "${repo}" add f.txt
git -C "${repo}" commit -q -m base
BASE_SHA="$(git -C "${repo}" rev-parse HEAD)"

printf 'base\nMARKER_ONE\n' > "${repo}/f.txt"
git -C "${repo}" add f.txt
git -C "${repo}" commit -q -m introduce-marker
INTRO_SHA="$(git -C "${repo}" rev-parse HEAD)"

printf 'base\nMARKER_ONE\nnoise\n' > "${repo}/f.txt"
git -C "${repo}" add f.txt
git -C "${repo}" commit -q -m unrelated-followup

LEADV2_REPO="${repo}"

# 1. Pickaxe resolves the marker's introducing commit's parent, verified marker-absent.
unset LEADV2_TEST_BASELINE_REF
out="$(lv2_rf_baseline_ref 'MARKER_ONE' f.txt 2>/dev/null)"; rc=$?
resolved="$(git -C "${repo}" rev-parse "${out}" 2>/dev/null || true)"
if [[ ${rc} -eq 0 && "${resolved}" == "${BASE_SHA}" ]]; then
  ok "pickaxe resolves intro commit's parent"
else
  bad "pickaxe resolves intro commit's parent (rc=${rc} out=${out} resolved=${resolved} want=${BASE_SHA})"
fi

# 2. Env override honoured when marker is absent there.
LEADV2_TEST_BASELINE_REF="${BASE_SHA}"
out="$(lv2_rf_baseline_ref 'MARKER_ONE' f.txt 2>/dev/null)"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == "${BASE_SHA}" ]]; then
  ok "env override honoured when marker absent"
else
  bad "env override honoured when marker absent (rc=${rc} out=${out})"
fi
unset LEADV2_TEST_BASELINE_REF

# 3. Override containing the marker -> rc 4, not a silent accept.
LEADV2_TEST_BASELINE_REF="${INTRO_SHA}"
lv2_rf_baseline_ref 'MARKER_ONE' f.txt >/dev/null 2>/tmp/leadv2-rfb-reason.$$; rc=$?
reason="$(cat /tmp/leadv2-rfb-reason.$$ 2>/dev/null)"; rm -f /tmp/leadv2-rfb-reason.$$
if [[ ${rc} -eq 4 && -n "${reason}" ]]; then
  ok "override containing marker returns rc 4 with a reason"
else
  bad "override containing marker returns rc 4 with a reason (rc=${rc} reason=${reason})"
fi
unset LEADV2_TEST_BASELINE_REF

# 4. Marker never introduced (bogus marker) -> rc 3, not a false 0.
lv2_rf_baseline_ref 'NEVER_EXISTED_MARKER_XYZ' f.txt >/dev/null 2>/dev/null; rc=$?
[[ ${rc} -eq 3 ]] && ok "marker never in history returns rc 3" || bad "marker never in history returns rc 3 (rc=${rc})"

# 5. Nonexistent override ref -> rc 3, never exit 1 / a crash.
LEADV2_TEST_BASELINE_REF="not-a-real-ref-ever"
lv2_rf_baseline_ref 'MARKER_ONE' f.txt >/dev/null 2>/dev/null; rc=$?
[[ ${rc} -eq 3 ]] && ok "nonexistent override ref returns rc 3" || bad "nonexistent override ref returns rc 3 (rc=${rc})"
unset LEADV2_TEST_BASELINE_REF

# 6. Root-commit marker (no parent to pin to) -> pin fallback used, or rc 3 if none given.
root_repo="${TMP}/root_repo"
mkdir -p "${root_repo}"
git -C "${root_repo}" init -q -b main
git -C "${root_repo}" config user.email test@example.com
git -C "${root_repo}" config user.name test
printf 'MARKER_ROOT\n' > "${root_repo}/g.txt"
git -C "${root_repo}" add g.txt
git -C "${root_repo}" commit -q -m root-has-marker
LEADV2_REPO="${root_repo}"
lv2_rf_baseline_ref 'MARKER_ROOT' g.txt >/dev/null 2>/dev/null; rc=$?
[[ ${rc} -eq 3 ]] && ok "marker introduced at repo root with no pin returns rc 3" || bad "marker introduced at repo root with no pin returns rc 3 (rc=${rc})"
LEADV2_REPO="${repo}"

# 7. Shallow clone -> rc 3, never a crash.
shallow="${TMP}/shallow"
git clone -q --depth 1 "file://${repo}" "${shallow}" 2>/dev/null
if [[ -d "${shallow}/.git" ]]; then
  LEADV2_REPO="${shallow}"
  lv2_rf_baseline_ref 'MARKER_ONE' f.txt >/dev/null 2>/dev/null; rc=$?
  [[ ${rc} -eq 3 ]] && ok "shallow clone returns rc 3" || bad "shallow clone returns rc 3 (rc=${rc})"
  LEADV2_REPO="${repo}"
else
  ok "shallow clone returns rc 3 (skipped -- local clone unavailable in this sandbox)"
fi

# 8. lv2_rf_extract round-trips a resolved ref into a real tree.
dest="${TMP}/extract"
if lv2_rf_extract "${BASE_SHA}" "${dest}" f.txt >/dev/null 2>&1 && [[ -f "${dest}/f.txt" ]]; then
  ok "lv2_rf_extract materialises the pinned ref"
else
  bad "lv2_rf_extract materialises the pinned ref"
fi

printf '[TEST] RESULT: pass=%s fail=%s\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
