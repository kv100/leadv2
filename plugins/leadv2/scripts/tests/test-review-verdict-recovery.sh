#!/usr/bin/env bash
# tests/test-review-verdict-recovery.sh — REVIEW-GATE-INFRA-01 D-B regression.
#
# pc_persist_review_body copies every arm's review body to a STABLE path
# (docs/handoff/dispatch-<TASK>-review/review-<arm>.md) immediately after
# run_reviewer_arm, before any verdict parsing or loss classification. Two
# behaviours this buys:
#  (1) when resolve_review_artifact picks a fresh-but-marker-less deliverable file
#      (REVIEW_ARTIFACT) while the arm's own transport (review_out, mirrored into the
#      persisted body) DID carry a verdict marker, the gate retries against the
#      persisted body and recovers the verdict instead of blocking.
#  (2) every review_body_lost / exhausted no_verdict_marker artifact names the exact
#      persisted body path and its byte count, not just an arm name.
#
# Red-first harness (git-archive-HEAD, same convention as test-lane-writes-scoping.sh
# and test-review-gate-scope-evidence.sh). NEVER git stash/reset/clean.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
GREEN_PRE_FIX=0
COULD_NOT_RUN=0
ERRORS=()

log() { printf -- '[TEST] %s\n' "$*"; }

if bash -n "${SCRIPT_DIR}/leadv2-dispatch-product-close.sh" 2>/dev/null; then
  PASS=$((PASS + 1)); log "PASS: bash -n leadv2-dispatch-product-close.sh"
else
  FAIL=$((FAIL + 1)); ERRORS+=("bash -n product-close.sh"); log "FAIL: bash -n leadv2-dispatch-product-close.sh"
fi
if /bin/bash -n "${SCRIPT_DIR}/leadv2-dispatch-product-close.sh" 2>/dev/null; then
  PASS=$((PASS + 1)); log "PASS: /bin/bash -n leadv2-dispatch-product-close.sh (bash 3.2 syntax)"
else
  FAIL=$((FAIL + 1)); ERRORS+=("/bin/bash -n product-close.sh (3.2)"); log "FAIL: /bin/bash -n leadv2-dispatch-product-close.sh (bash 3.2)"
fi

new_repo() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rvr.XXXXXX")"
  ( cd "${d}" && git init -q -b main && git config user.email test@example.com \
    && git config user.name test && printf 'baseline\n' > file.txt \
    && git add file.txt && git commit -qm init ) >/dev/null 2>&1
  printf 'baseline\nedited\n' > "${d}/file.txt"
  printf '%s' "${d}"
}

make_resolver_stub() { # <path> <reviewer-arm>
  cat > "$1" <<PYEOF
print("reviewer=$2")
print("pool=$2")
print("refusal=")
PYEOF
}

run_close() { # <pc> <root> <sig8> <resolver> [arch_bin]
  local pc="$1" root="$2" sig8="$3" resolver="$4" arch="${5:-}"
  local cache="${root}/.cache-${sig8}"
  mkdir -p "${cache}"
  LEADV2_GLM_POLICY_RESOLVER="${resolver}" \
  LEADV2_DISPATCH_CACHE_DIR="${cache}" \
  LEADV2_JOURNAL_BIN=/bin/true \
  LEADV2_E2E_OWNERSHIP=0 \
  LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
  LEADV2_DISPATCH_ARCHITECT_BIN="${arch}" \
    bash "${pc}" "${root}" "${sig8}" codex "" 0 1 "" 2>&1
}

# ── Case 1 (D-B iii): verdict recovered from the persisted body when the resolved
# deliverable artifact lacks the marker but the arm's own transport (review_out /
# persisted copy) carries it. ────────────────────────────────────────────────────────
case_recovers_from_persisted_body() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root sig8 d resolver arch
  root="$(new_repo)"
  sig8="rcv$$"
  d="$(mktemp -d)"
  resolver="${d}/resolver.py"; make_resolver_stub "${resolver}" sonnet
  # arch stub: stdout (-> review_out) carries the FULL marker contract directly;
  # a SEPARATE, staler-content critic.full.md (fresh per REVIEW_STAMP, so
  # resolve_review_artifact picks it) deliberately LACKS the marker -- the exact
  # divergence a lost/rewritten deliverable produces in production.
  arch="${d}/arch.sh"
  cat > "${arch}" <<'ARCHEOF'
#!/usr/bin/env bash
tid=""
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "--task-id" ]]; then j=$((i+1)); tid="${!j}"; fi
done
adir="${PROJECT_ROOT}/docs/handoff/${tid}"
mkdir -p "${adir}"
cat > "${adir}/critic.full.md" <<'BODY'
This deliverable file lost its verdict marker somewhere in transport. Long
enough prose to clear the review floor on its own, but no REVIEW_VERDICT or
REVIEW_FINDINGS line anywhere in this text, by construction, for the test.
Additional filler line one. Additional filler line two. Additional filler
line three to make sure the byte floor is cleared regardless of markers.
BODY
cat <<'STDOUT'
REVIEW_VERDICT: PASS
REVIEW_FINDINGS: critical=0 high=0 medium=0 low=0

The diff is clean. This is the arm's own transport output, carrying the
verdict marker directly, distinct from the (marker-less) deliverable file.
STDOUT
exit 0
ARCHEOF
  chmod +x "${arch}"
  run_close "${pc}" "${root}" "${sig8}" "${resolver}" "${arch}" >/dev/null 2>&1
  local gate="${root}/docs/handoff/dispatch-${sig8}/review-gate.md"
  local persisted="${root}/docs/handoff/dispatch-${sig8}-review/review-sonnet.md"
  local ok=1
  if [[ -f "${gate}" ]] && grep -q '^status: pass$' "${gate}" && [[ -s "${persisted}" ]] \
     && grep -q 'REVIEW_VERDICT: PASS' "${persisted}"; then
    ok=0
  fi
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── Case 2 (D-B iv): the exhausted no_verdict_marker terminal names the persisted
# body path and its byte count, not just an arm name. ───────────────────────────────
case_no_verdict_names_body() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root sig8 d resolver arch
  root="$(new_repo)"
  sig8="nvb$$"
  d="$(mktemp -d)"
  resolver="${d}/resolver.py"; make_resolver_stub "${resolver}" sonnet
  arch="${d}/arch.sh"
  cat > "${arch}" <<'ARCHEOF'
#!/usr/bin/env bash
cat <<'STDOUT'
This is a long enough prose body to clear the byte floor, but it never
contains a REVIEW_VERDICT or REVIEW_FINDINGS marker anywhere, by construction,
so parse_review_verdict must fail on both the primary parse and the recovery
retry against the persisted copy of this exact same text.
STDOUT
exit 0
ARCHEOF
  chmod +x "${arch}"
  run_close "${pc}" "${root}" "${sig8}" "${resolver}" "${arch}" >/dev/null 2>&1
  local gate="${root}/docs/handoff/dispatch-${sig8}/review-gate.md"
  local ok=1
  if [[ -f "${gate}" ]] && grep -q '^reason: no_verdict_marker$' "${gate}" \
     && grep -q '^body: docs/handoff/dispatch-'"${sig8}"'-review/review-sonnet.md$' "${gate}" \
     && grep -qE '^bytes: [0-9]+$' "${gate}"; then
    ok=0
  fi
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── harness runner (falsifiable red-first baseline, F6) ─────────────────────────────
# `git archive HEAD` stopped being a valid pre-fix baseline once this round's own fix
# landed on HEAD -- every case would then run identically pre- and post-fix and
# silently report green-pre-fix forever. Baseline against the merge-base with
# origin/main instead (or an explicit override), falling back to HEAD only when
# neither resolves (e.g. no network / no origin remote in this checkout).
PREFIX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-prefix-rvr.XXXXXX")"
LEADV2_REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
LEADV2_TEST_BASELINE_REF="${LEADV2_TEST_BASELINE_REF:-}"
if [[ -z "${LEADV2_TEST_BASELINE_REF}" ]]; then
  LEADV2_TEST_BASELINE_REF="$(git -C "${LEADV2_REPO}" merge-base origin/main HEAD 2>/dev/null || true)"
  # pinned pre-fix floor: merge-base self-nullifies once e6815f5 reaches origin/main
  case "20 20 12 61 79 80 81 703 701 33 98 100 204 250 395 398 399 400git -C "" merge-base --is-ancestor e6815f5 "" 2>/dev/null; echo 0)" in 0) LEADV2_TEST_BASELINE_REF="9e03dc0";; esac
fi
[[ -n "${LEADV2_TEST_BASELINE_REF}" ]] || LEADV2_TEST_BASELINE_REF="HEAD"
git -C "${LEADV2_REPO}" archive "${LEADV2_TEST_BASELINE_REF}" plugins/leadv2/scripts 2>/dev/null | tar -x -C "${PREFIX_DIR}" 2>/dev/null
PREFIX_SCRIPTS="${PREFIX_DIR}/plugins/leadv2/scripts"
if [[ ! -f "${PREFIX_SCRIPTS}/leadv2-dispatch-product-close.sh" ]]; then
  log "FATAL: git archive ${LEADV2_TEST_BASELINE_REF} extraction failed -- cannot run red-first harness"
  exit 1
fi

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
    log "GREEN-PRE-FIX: ${name} -- passed against HEAD too (pre_rc=0)"
    return
  fi
  PASS=$((PASS + 1))
  log "RED-then-GREEN: ${name} (pre_rc=${pre_rc} -> post_rc=0)"
}

run_case "verdict-recovered-from-persisted-body" case_recovers_from_persisted_body
run_case "no-verdict-marker-names-persisted-body" case_no_verdict_names_body

rm -rf "${PREFIX_DIR}"

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ "${FAIL}" -gt 0 || "${GREEN_PRE_FIX}" -gt 0 ]]; then
  printf -- 'FAIL: %s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
