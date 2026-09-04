#!/usr/bin/env bash
# t12-mutation-probe.sh — standalone negative-control target for
# dispatch-e525df4d (T12: missing/unreadable diff file -> exhaustive round 1,
# no sidecar, stderr line). Isolates exactly case_t12_missing_diff from
# plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh, with none of
# that suite's T7 red-first baseline machinery (T7 shells out to
# `git archive <repo-history-commit>`, which only resolves inside the real
# leadv2 repo -- leadv2-mutation-control.sh runs suites inside a from-scratch,
# single-commit scratch git repo with no such history, so T7 fails there
# unconditionally regardless of any mutation and cannot serve as a control
# target). This probe carries the exact same assertions as case_t12_missing_diff,
# with zero git-history dependency, so it is meaningful inside that scratch
# repo. Exit 0 = pass, exit 1 = fail (falsifiable, no `|| true` around the
# checked commands).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# When run by leadv2-mutation-control.sh, this file's own copy is snapshotted
# into the scratch tree at the same relative path as it lives in the real
# repo (docs/handoff/dispatch-e525df4d/), and the target script lives at
# plugins/leadv2/scripts/leadv2-review-run.sh relative to the scratch root.
SCRATCH_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SCRIPTS_ROOT="${SCRATCH_ROOT}/plugins/leadv2/scripts"

STUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-t12-probe.XXXXXX")"
trap 'rm -rf "${STUB_DIR}"' EXIT

cat > "${STUB_DIR}/resolver.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=sonnet")
print("pool=sonnet:ok:,opus:ok:")
print("refusal=")
PY
chmod +x "${STUB_DIR}/resolver.py"

cat > "${STUB_DIR}/architect-ctrl.sh" <<'SH'
#!/usr/bin/env bash
role=""
while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; *) shift ;; esac; done
[[ "${role}" == "hack-detect" ]] && exit 0
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
SH
chmod +x "${STUB_DIR}/architect-ctrl.sh"

cat > "${STUB_DIR}/codex.sh" <<'SH'
#!/usr/bin/env bash
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
SH
chmod +x "${STUB_DIR}/codex.sh"

cat > "${STUB_DIR}/dispatch.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${STUB_DIR}/dispatch.sh"

new_handoff() {
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-t12probe.XXXXXX")"
  local h="${d}/repo/docs/handoff/dispatch-T12PROBE"
  mkdir -p "${h}"
  printf '%s' "${h}"
}

h="$(new_handoff)"
diff="${h}/does-not-exist.diff"
root="${h%/docs/handoff/*}"
mkdir -p "${root}/.claude/ref"
errfile="${h}.err"

LEADV2_GLM_POLICY_RESOLVER="${STUB_DIR}/resolver.py" \
LEADV2_DISPATCH_ARCHITECT_BIN="${STUB_DIR}/architect-ctrl.sh" \
LEADV2_DISPATCH_CODEX_BIN="${STUB_DIR}/codex.sh" \
LEADV2_DISPATCH_BIN="${STUB_DIR}/dispatch.sh" \
LEADV2_REVIEW_FANOUT=1 \
bash "${SCRIPTS_ROOT}/leadv2-review-run.sh" --task T12PROBE --root "${root}" --handoff "${h}" --diff "${diff}" --author glm >/dev/null 2>"${errfile}"

mf="${h}/review-mission-sonnet.md"

if [[ ! -f "${mf}" ]]; then
  printf 'FAIL: T12PROBE no mission file written at %s\n' "${mf}"
  exit 1
fi
if ! grep -q 'EXHAUSTIVE ROUND 1' "${mf}"; then
  printf 'FAIL: T12PROBE mission file missing EXHAUSTIVE ROUND 1\n'
  exit 1
fi
if [[ -f "${h}/.review-round.state" ]]; then
  printf 'FAIL: T12PROBE .review-round.state was written for an unreadable diff\n'
  exit 1
fi
if [[ ! -s "${errfile}" ]]; then
  printf 'FAIL: T12PROBE stderr is empty\n'
  exit 1
fi
if ! grep -qi 'diff file missing' "${errfile}"; then
  printf 'FAIL: T12PROBE stderr missing "diff file missing"\n'
  exit 1
fi
printf 'PASS: T12PROBE missing diff file -> exhaustive, no sidecar, stderr\n'
exit 0
