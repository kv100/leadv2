#!/usr/bin/env bash
# tests/test-claim-evidence-gate.sh — CLAIM-EVIDENCE-GATE-01.
#
# Two text contracts gain an evidence rule: the subagent preamble
# (SHARED_PROTOCOL_BOILERPLATE in claude-subsession.sh) and the round-1
# exhaustive review mission (leadv2-review-run.sh's _review_build_contract).
# No gate machinery, no env vars, no new runtime code paths — pure text.
#
# Red-first harness, same convention as test-review-gate-scope-evidence.sh:
# every content-probe case runs TWICE, once against a `git archive` extraction
# of a pre-fix baseline (PREFIX_SCRIPTS) and once against this working tree
# (SCRIPT_DIR). A case must FAIL against PREFIX_SCRIPTS and PASS against
# SCRIPT_DIR. NEVER git stash/reset/clean.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
GREEN_PRE_FIX=0
COULD_NOT_RUN=0
ERRORS=()

log() { printf -- '[TEST] %s\n' "$*"; }

# ── C5: bash 3.2 syntax check on both edited scripts ─────────────────────────
for f in claude-subsession.sh leadv2-review-run.sh; do
  if bash -n "${SCRIPT_DIR}/${f}" 2>/dev/null; then
    PASS=$((PASS + 1)); log "PASS: bash -n ${f}"
  else
    FAIL=$((FAIL + 1)); ERRORS+=("bash -n ${f}"); log "FAIL: bash -n ${f}"
  fi
  if /bin/bash -n "${SCRIPT_DIR}/${f}" 2>/dev/null; then
    PASS=$((PASS + 1)); log "PASS: /bin/bash -n ${f} (bash 3.2 syntax)"
  else
    FAIL=$((FAIL + 1)); ERRORS+=("/bin/bash -n ${f} (3.2)"); log "FAIL: /bin/bash -n ${f} (bash 3.2 syntax)"
  fi
done

# ── shared baseline extraction (red-first floor) ──────────────────────────────
# Same self-nullification trap as test-review-gate-scope-evidence.sh:229-242 and
# the 9e03dc0 pin (8cc6bf8/85ae886): once this lane lands on origin/main, a plain
# merge-base baseline would already contain the fix and every case would report
# green-pre-fix forever. Content-probe first; pinned floor is 559cf15 (HEAD
# immediately before this lane, the last commit before CLAIM-EVIDENCE-GATE-01).
PREFIX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-prefix-ceg.XXXXXX")"
LEADV2_REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
LEADV2_TEST_BASELINE_REF="${LEADV2_TEST_BASELINE_REF:-}"
if [[ -z "${LEADV2_TEST_BASELINE_REF}" ]]; then
  LEADV2_TEST_BASELINE_REF="$(git -C "${LEADV2_REPO}" merge-base origin/main HEAD 2>/dev/null || true)"
  if [[ -n "${LEADV2_TEST_BASELINE_REF}" ]] && git -C "${LEADV2_REPO}" grep -q claims-without-evidence "${LEADV2_TEST_BASELINE_REF}" -- plugins/leadv2/scripts/leadv2-review-run.sh 2>/dev/null; then
    LEADV2_TEST_BASELINE_REF="559cf15"
  fi
fi
[[ -n "${LEADV2_TEST_BASELINE_REF}" ]] || LEADV2_TEST_BASELINE_REF="HEAD"
git -C "${LEADV2_REPO}" archive "${LEADV2_TEST_BASELINE_REF}" plugins/leadv2/scripts 2>/dev/null | tar -x -C "${PREFIX_DIR}" 2>/dev/null
PREFIX_SCRIPTS="${PREFIX_DIR}/plugins/leadv2/scripts"
if [[ ! -f "${PREFIX_SCRIPTS}/leadv2-review-run.sh" ]]; then
  log "FATAL: git archive ${LEADV2_TEST_BASELINE_REF} extraction failed -- cannot run red-first harness"
  exit 1
fi

# ── C1: subagent preamble carries the evidence contract ──────────────────────
case_c1_preamble_evidence_contract() { # <scripts_dir> -> 0 pass, 1 fail
  local scripts_dir="$1"
  local f="${scripts_dir}/claude-subsession.sh"
  [[ -f "${f}" ]] || return 2
  grep -q 'EVIDENCE CONTRACT' "${f}" && grep -q 'UNVERIFIED:' "${f}"
}

# ── C2: round-1 exhaustive branch names the fifth lens ────────────────────────
case_c2_exhaustive_five_lenses() { # <scripts_dir> -> 0 pass, 1 fail
  local scripts_dir="$1"
  local f="${scripts_dir}/leadv2-review-run.sh"
  [[ -f "${f}" ]] || return 2
  grep -q 'FIVE lenses' "${f}" && grep -q 'claims-without-evidence' "${f}"
}

run_case() { # <name> <fn>
  local name="$1" fn="$2"
  local pre_rc post_rc
  "${fn}" "${PREFIX_SCRIPTS}" >/dev/null 2>&1; pre_rc=$?
  "${fn}" "${SCRIPT_DIR}" >/dev/null 2>&1; post_rc=$?

  if [[ ${pre_rc} -eq 2 || ${post_rc} -eq 2 ]]; then
    COULD_NOT_RUN=$((COULD_NOT_RUN + 1))
    log "COULD-NOT-RUN: ${name} (pre_rc=${pre_rc} post_rc=${post_rc})"
    return
  fi
  if [[ ${post_rc} -ne 0 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix did not pass (rc=${post_rc})")
    log "FAIL: ${name} -- post-fix rc=${post_rc}, expected 0"
    return
  fi
  if [[ ${pre_rc} -eq 0 ]]; then
    GREEN_PRE_FIX=$((GREEN_PRE_FIX + 1))
    log "GREEN-PRE-FIX: ${name} -- passed against baseline too (pre_rc=0)"
    return
  fi
  PASS=$((PASS + 1))
  log "RED-then-GREEN: ${name} (pre_rc=${pre_rc} -> post_rc=0)"
}

run_case "preamble-evidence-contract"   case_c1_preamble_evidence_contract
run_case "exhaustive-five-lenses"       case_c2_exhaustive_five_lenses

# ── C3: verify_only branch stays pure (working-tree-only invariant) ──────────
# _review_build_contract's verify_only branch (printf 'VERIFICATION-ONLY ROUND...
# through the PRIOR_FINDINGS_BODY printf) must NOT gain the new lens text —
# round 2+ stays verification-only per REVIEW-ROUND1-EXHAUSTIVE-01.
verify_only_block="$(sed -n '/if \[\[ "\${REVIEW_MODE}" == "verify_only" \]\]; then/,/else/p' "${SCRIPT_DIR}/leadv2-review-run.sh")"
if [[ -n "${verify_only_block}" ]] && ! grep -q 'claims-without-evidence' <<<"${verify_only_block}"; then
  PASS=$((PASS + 1)); log "PASS: verify_only branch does not contain claims-without-evidence"
else
  FAIL=$((FAIL + 1)); ERRORS+=("verify_only branch purity"); log "FAIL: verify_only branch does not contain claims-without-evidence"
fi

# ── C4: the NEW content itself never contains a double-quote or backtick
# (codex --focus is a single shell word, per _review_flatten's own R6
# comment). Scoped to the added lines only -- the surrounding shell source
# legitimately uses "${var}" interpolation and existing bullets legitimately
# use escaped quotes (e.g. ask-lead.sh's \"<question>\"), so a whole-block
# check would false-positive on pre-existing, unrelated text. ────────────────
exhaustive_new_lines="$(grep -E 'claims-without-evidence|Claims-without-evidence rule' "${SCRIPT_DIR}/leadv2-review-run.sh")"
if [[ -n "${exhaustive_new_lines}" ]] && ! grep -qE '["`]' <<<"${exhaustive_new_lines}"; then
  PASS=$((PASS + 1)); log "PASS: exhaustive branch new text has no quote/backtick"
else
  FAIL=$((FAIL + 1)); ERRORS+=("exhaustive branch quote/backtick safety"); log "FAIL: exhaustive branch new text has no quote/backtick"
fi
preamble_new_lines="$(grep -E 'EVIDENCE CONTRACT|UNVERIFIED:' "${SCRIPT_DIR}/claude-subsession.sh")"
if [[ -n "${preamble_new_lines}" ]] && ! grep -qE '["`]' <<<"${preamble_new_lines}"; then
  PASS=$((PASS + 1)); log "PASS: preamble evidence bullets have no quote/backtick"
else
  FAIL=$((FAIL + 1)); ERRORS+=("preamble backtick safety"); log "FAIL: preamble evidence bullets have no quote/backtick"
fi

# ── C6: the actually-rendered round-1 mission contains the fifth lens ────────
# Invokes the real engine (stub resolver/arm, zero network) rather than
# sourcing _review_build_contract in isolation -- leadv2-review-run.sh runs
# its full pipeline unconditionally once invoked, so isolation-by-source would
# either hang on missing args or execute the whole gate. This mirrors the
# proven harness in test-review-round-exhaustive.sh.
c6_stub_dir="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-ceg-stubs.XXXXXX")"
cat > "${c6_stub_dir}/resolver.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=sonnet")
print("pool=sonnet:ok:,opus:ok:")
print("refusal=")
PY
chmod +x "${c6_stub_dir}/resolver.py"
cat > "${c6_stub_dir}/architect.sh" <<'SH'
#!/usr/bin/env bash
role=""
while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; *) shift ;; esac; done
[[ "${role}" == "hack-detect" ]] && exit 0
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
SH
chmod +x "${c6_stub_dir}/architect.sh"
cat > "${c6_stub_dir}/codex.sh" <<'SH'
#!/usr/bin/env bash
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
SH
chmod +x "${c6_stub_dir}/codex.sh"
cat > "${c6_stub_dir}/dispatch.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${c6_stub_dir}/dispatch.sh"

c6_root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-ceg-root.XXXXXX")"
c6_handoff="${c6_root}/repo/docs/handoff/dispatch-CEGT1"
mkdir -p "${c6_handoff}" "${c6_root}/repo/.claude/ref"
c6_diff="${c6_handoff}/review.diff"
printf 'diff --git a/x b/x\n+hello\n' > "${c6_diff}"

LEADV2_GLM_POLICY_RESOLVER="${c6_stub_dir}/resolver.py" \
LEADV2_DISPATCH_ARCHITECT_BIN="${c6_stub_dir}/architect.sh" \
LEADV2_DISPATCH_CODEX_BIN="${c6_stub_dir}/codex.sh" \
LEADV2_DISPATCH_BIN="${c6_stub_dir}/dispatch.sh" \
LEADV2_REVIEW_FANOUT=1 \
bash "${SCRIPT_DIR}/leadv2-review-run.sh" --task CEGT1 --root "${c6_root}/repo" --handoff "${c6_handoff}" --diff "${c6_diff}" --author glm >/dev/null 2>&1

c6_mf="${c6_handoff}/review-mission-sonnet.md"
if [[ -f "${c6_mf}" ]] && grep -q 'FIVE lenses' "${c6_mf}" && grep -q 'claims-without-evidence' "${c6_mf}"; then
  PASS=$((PASS + 1)); log "PASS: rendered round-1 mission contains claims-without-evidence lens"
else
  FAIL=$((FAIL + 1)); ERRORS+=("rendered round-1 mission missing claims-without-evidence lens")
  log "FAIL: rendered round-1 mission contains claims-without-evidence lens"
fi
rm -rf "${c6_stub_dir}" "${c6_root}"

rm -rf "${PREFIX_DIR}"

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ "${FAIL}" -gt 0 || "${GREEN_PRE_FIX}" -gt 0 ]]; then
  printf -- 'FAIL: %s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
