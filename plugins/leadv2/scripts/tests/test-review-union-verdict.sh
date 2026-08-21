#!/usr/bin/env bash
# test-review-union-verdict.sh — REVIEW-UNION-VERDICT-01.
#
# WHY THIS TEST EXISTS: the gate used to take the FIRST arm whose review parsed and
# `break`. With the default three-arm fan-out that meant a Critical found by arm 2 or
# 3 did not block — its findings were unioned into the JSON while gating still keyed
# on arm 1's verdict. The Codex process audit (docs/handoff/PROCESS-AUDIT-20260821/)
# put it plainly: "more arms currently buy more prose, not a stronger gate", with the
# effective counters computed and then never used. Paying three reviewers and gating
# on one is the worst of both — the cost of breadth with the assurance of one opinion.
#
# This drives the REAL engine (leadv2-review-run.sh) with stubbed arms, so it asserts
# the shipped decision path rather than a restatement of it. Case 1 is the defect:
# codex PASSes, sonnet FAILs, and the gate must fail.
#
# The negative cases matter as much: escalation must work in the blocking direction
# ONLY. An arm can turn PASS into FAIL; nothing may turn FAIL into PASS, and an
# all-PASS fan-out must still pass, or the gate becomes noise and gets switched off.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="${SCRIPT_DIR}/.."
ENGINE="${SCRIPTS_ROOT}/leadv2-review-run.sh"

PASS=0; FAIL=0; COULD_NOT_RUN=0
declare -a ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }

if [[ ! -f "${ENGINE}" ]]; then
  log "COULD-NOT-RUN: leadv2-review-run.sh absent"; exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/review-union.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

# Build a stub set where each named arm emits the verdict we want, then run the
# engine and report the gate's status line.
# Usage: _run_case <tag> <codex_verdict> <sonnet_verdict>
_run_case() {
  local tag="$1" codex_v="$2" sonnet_v="$3"
  local tmp="${WORK}/${tag}"
  local root="${tmp}/repo"
  local handoff="${root}/docs/handoff/dispatch-${tag}"
  mkdir -p "${handoff}" "${root}/.claude/ref"
  printf 'diff --git a/x b/x\n+hello\n' > "${handoff}/review.diff"

  cat > "${tmp}/resolver.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=codex")
print("pool=codex:ok:,sonnet:ok:")
print("refusal=")
PY
  chmod +x "${tmp}/resolver.py"

  # codex arm — writes to stdout, which the engine redirects to review-codex.md
  cat > "${tmp}/codex.sh" <<SH
#!/usr/bin/env bash
crit=0; [[ "${codex_v}" == FAIL ]] && crit=1
printf 'REVIEW_VERDICT: ${codex_v}\nREVIEW_FINDINGS: critical=%s high=0 medium=0 low=0\n' "\$crit"
SH
  chmod +x "${tmp}/codex.sh"

  # sonnet arm goes through the subsession launcher; hack-detect must stay silent
  cat > "${tmp}/architect.sh" <<SH
#!/usr/bin/env bash
role=""
while [[ \$# -gt 0 ]]; do case "\$1" in --role) role="\$2"; shift 2 ;; *) shift ;; esac; done
[[ "\$role" == "hack-detect" ]] && exit 0
crit=0; [[ "${sonnet_v}" == FAIL ]] && crit=1
printf 'REVIEW_VERDICT: ${sonnet_v}\nREVIEW_FINDINGS: critical=%s high=0 medium=0 low=0\n' "\$crit"
SH
  chmod +x "${tmp}/architect.sh"

  cat > "${tmp}/glm.sh" <<'SH'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do case "$1" in --out) out="$2"; shift 2 ;; *) shift ;; esac; done
[[ -n "$out" ]] && printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n' > "$out"
SH
  chmod +x "${tmp}/glm.sh"

  cat > "${tmp}/dispatch.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "${tmp}/dispatch.sh"

  LEADV2_GLM_POLICY_RESOLVER="${tmp}/resolver.py" \
  LEADV2_DISPATCH_CODEX_BIN="${tmp}/codex.sh" \
  LEADV2_DISPATCH_GLM_BIN="${tmp}/glm.sh" \
  LEADV2_DISPATCH_ARCHITECT_BIN="${tmp}/architect.sh" \
  LEADV2_DISPATCH_BIN="${tmp}/dispatch.sh" \
  LEADV2_REVIEW_FANOUT=2 \
  bash "${ENGINE}" --task "${tag}" --root "${root}" --handoff "${handoff}" \
    --diff "${handoff}/review.diff" --author glm >/dev/null 2>&1

  sed -nE 's/^status:[[:space:]]*([a-z_]+).*/\1/p' "${handoff}/review-gate.md" 2>/dev/null | head -n1
}

_expect() { # <tag> <codex> <sonnet> <expected-status>
  local got; got="$(_run_case "$1" "$2" "$3")"
  [[ -z "${got}" ]] && { COULD_NOT_RUN=$((COULD_NOT_RUN+1)); log "COULD-NOT-RUN: $1 (no gate status)"; return 2; }
  if [[ "${got}" == "$4" ]]; then
    PASS=$((PASS+1)); log "PASS: $1 — codex=$2 sonnet=$3 -> ${got}"
  else
    FAIL=$((FAIL+1)); ERRORS+=("$1: expected $4, got ${got}")
    log "FAIL: $1 — codex=$2 sonnet=$3 -> ${got}, expected $4"
  fi
}

# THE DEFECT: the primary arm passes, a later arm fails. Must FAIL.
_expect union-late-fail-blocks   PASS FAIL fail
# The primary itself fails — unchanged behaviour, must still FAIL.
_expect primary-fail-still-fails FAIL PASS fail
# Both fail — must FAIL, and must not double-count into something odd.
_expect both-fail                FAIL FAIL fail
# All clean — must NOT be dragged to fail by the new union logic.
_expect all-pass-still-passes    PASS PASS pass

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed, ${COULD_NOT_RUN} could-not-run"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
