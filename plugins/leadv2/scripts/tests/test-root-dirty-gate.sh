#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-product-close.sh leadv2-land.sh
# test-root-dirty-gate.sh — W18-ROOT-DIRTY-GATE-01.
#
# One scratch fixture carries a lane that changes src/merge-modified.txt and
# creates src/created-by-merge.txt.  Every case changes only whether root dirt
# intersects that prospective merged-tree set.  The final non-intersecting
# tracked-dirt case performs the real merge, proving the probe does not merely
# print a permissive verdict.
#
# Negative control: leadv2-mutation-control.sh replaces the membership test
# inside land_root_dirt_check with the old whole-root porcelain condition. T1
# then goes red because unrelated tracked dirt is falsely refused.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PASS=0; FAIL=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/root-dirty-gate.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

ok() { PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }
same() { [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (expected [$2], got [$3])"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing [$3] in [$(printf '%.180s' "$2")])" ;; esac; }

REPO="${TMP}/repo"
git init -q "${REPO}"
git -C "${REPO}" checkout -q -b main
mkdir -p "${REPO}/plugins/leadv2/scripts" "${REPO}/src"
for f in leadv2-land.sh leadv2-branch-merged.sh; do
  cp "${SRC_DIR}/${f}" "${REPO}/plugins/leadv2/scripts/${f}"
done
printf 'base\n' > "${REPO}/src/merge-modified.txt"
printf 'foreign base\n' > "${REPO}/src/foreign.txt"
git -C "${REPO}" add -A
git -C "${REPO}" -c user.name=t -c user.email=t@t commit -q -m base
git -C "${REPO}" checkout -q -b lane-root-dirt
printf 'lane result\n' > "${REPO}/src/merge-modified.txt"
printf 'created by lane\n' > "${REPO}/src/created-by-merge.txt"
git -C "${REPO}" add -A
git -C "${REPO}" -c user.name=t -c user.email=t@t commit -q -m 'lane changes'
git -C "${REPO}" checkout -q main
LAND="${REPO}/plugins/leadv2/scripts/leadv2-land.sh"

run_probe() { # sets PROBE_OUT and PROBE_RC
  PROBE_OUT="$(LEADV2_LAND_ROOT="${REPO}" bash "${LAND}" --root-dirt-check lane-root-dirt 2>&1)"
  PROBE_RC=$?
}
restore() { git -C "${REPO}" checkout -q -- src/foreign.txt src/merge-modified.txt 2>/dev/null || true; rm -f "${REPO}/tmp-unrelated.txt" "${REPO}/src/created-by-merge.txt"; }

# T1 / required negative control target: tracked dirt outside the merged tree.
printf 'foreign local edit\n' > "${REPO}/src/foreign.txt"
run_probe; OUT="${PROBE_OUT}"
same 'T1 tracked non-intersection permits merge' 0 "${PROBE_RC}"
restore

# T2: only the intersecting tracked pathname differs from T1.
printf 'conflicting local edit\n' > "${REPO}/src/merge-modified.txt"
run_probe; OUT="${PROBE_OUT}"
same 'T2 tracked intersection refuses' 1 "${PROBE_RC}"
has 'T2 refusal names tracked intersecting path' "${OUT}" 'src/merge-modified.txt'
restore

# T3/T4: identical rule for untracked files, depending only on intersection.
printf 'harmless residue\n' > "${REPO}/tmp-unrelated.txt"
run_probe; OUT="${PROBE_OUT}"
same 'T3 untracked non-intersection permits merge' 0 "${PROBE_RC}"
restore

printf 'would obstruct merge\n' > "${REPO}/src/created-by-merge.txt"
run_probe; OUT="${PROBE_OUT}"
same 'T4 untracked merge-created path refuses' 1 "${PROBE_RC}"
has 'T4 refusal names untracked intersecting path' "${OUT}" 'src/created-by-merge.txt'
restore

# The passing case must reach a real merge while unrelated tracked dirt remains.
printf 'foreign local edit\n' > "${REPO}/src/foreign.txt"
run_probe; OUT="${PROBE_OUT}"
if [[ ${PROBE_RC} -eq 0 ]] && git -C "${REPO}" -c user.name=t -c user.email=t merge --no-edit --no-ff lane-root-dirt >/dev/null 2>&1 \
    && grep -qx 'lane result' "${REPO}/src/merge-modified.txt" \
    && grep -qx 'foreign local edit' "${REPO}/src/foreign.txt"; then
  ok 'T5 non-intersecting root dirt reaches a real merge unchanged'
else
  bad "T5 non-intersecting root dirt did not merge (probe_rc=${PROBE_RC}, out=${OUT})"
fi

printf '# root-dirty-gate pass=%d fail=%d\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
