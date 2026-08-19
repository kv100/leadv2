#!/usr/bin/env bash
# tests/test-claim-evidence-gate.sh — CLAIM-EVIDENCE-GATE-01.
#
# Round 1: two text contracts gained an evidence rule -- the subagent preamble
# (SHARED_PROTOCOL_BOILERPLATE in claude-subsession.sh) and the round-1
# exhaustive review mission (leadv2-review-run.sh's _review_build_contract).
# Round 2 (this file): the WRITING side for the arms round 1 never touched --
# the claude-arm protocol-reference appendix was resolving to nothing under
# every live project root (H1), and glm/kimi/codex dispatch missions carried
# no evidence-contract text at all (H2). No gate machinery, no new env vars,
# no new runtime code paths -- pure text plus one resolution-order fix.
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

# ── cleanup (L5): trap-based, covers every scratch dir this run creates.
# Populated as each scratch dir is minted below; idempotent (rm -rf on an
# already-removed path is a no-op), so the trap firing after an explicit
# early rm is harmless.
CLEANUP_PATHS=()
_cleanup() {
  local p
  for p in "${CLEANUP_PATHS[@]+"${CLEANUP_PATHS[@]}"}"; do
    rm -rf "${p}" 2>/dev/null || true
  done
}
trap _cleanup EXIT INT TERM

# ── C5: bash 3.2 syntax check on every edited script ──────────────────────────
for f in claude-subsession.sh leadv2-review-run.sh leadv2-helpers.sh leadv2-dispatch-code.sh glm-coder.sh; do
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
# green-pre-fix forever. Content-probe first, checking THREE markers (L4) --
# claims-without-evidence (round 1's review-side lens) AND the round-2 mission-
# side EVIDENCE CONTRACT / UNVERIFIED: markers -- because after the rebase this
# lane sits on, merge-base(origin/main, HEAD) is 512ecda, which carries NONE of
# the three (round 1's own commit is ahead of that point in this lane), so the
# merge-base path stays live and honest for round 2. Pinned floor is 559cf15
# (L2, not HEAD): HEAD post-rebase already contains round 1's fix for C1/C2, so
# falling back to HEAD would self-nullify those cases the moment a merge-base
# probe fails for any transient reason.
PREFIX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-prefix-ceg.XXXXXX")"
CLEANUP_PATHS+=("${PREFIX_DIR}")
LEADV2_REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
LEADV2_TEST_BASELINE_REF="${LEADV2_TEST_BASELINE_REF:-}"
if [[ -z "${LEADV2_TEST_BASELINE_REF}" ]]; then
  LEADV2_TEST_BASELINE_REF="$(git -C "${LEADV2_REPO}" merge-base origin/main HEAD 2>/dev/null || true)"
  if [[ -n "${LEADV2_TEST_BASELINE_REF}" ]] \
     && git -C "${LEADV2_REPO}" grep -q claims-without-evidence "${LEADV2_TEST_BASELINE_REF}" -- plugins/leadv2/scripts/leadv2-review-run.sh 2>/dev/null \
     && git -C "${LEADV2_REPO}" grep -q 'EVIDENCE CONTRACT' "${LEADV2_TEST_BASELINE_REF}" -- plugins/leadv2/scripts/claude-subsession.sh 2>/dev/null \
     && git -C "${LEADV2_REPO}" grep -q 'UNVERIFIED:' "${LEADV2_TEST_BASELINE_REF}" -- plugins/leadv2/scripts/claude-subsession.sh 2>/dev/null; then
    LEADV2_TEST_BASELINE_REF="559cf15"
  fi
fi
# L2: NEVER fall back to HEAD -- HEAD (post-rebase) already carries round 1's
# fix, which would self-nullify C1/C2. The pinned floor is the only safe default.
[[ -n "${LEADV2_TEST_BASELINE_REF}" ]] || LEADV2_TEST_BASELINE_REF="559cf15"
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
    # M2: a green-pre-fix case is a floor problem (the baseline doesn't
    # actually predate the fix), not silent noise -- surface it in the
    # tail's FAIL listing too, same as a real failure, so it can't hide.
    ERRORS+=("${name}: GREEN-PRE-FIX (baseline already passes, pre_rc=0)")
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
# through the PRIOR_FINDINGS_BODY printf) must NOT gain the new lens text --
# round 2+ stays verification-only per REVIEW-ROUND1-EXHAUSTIVE-01.
verify_only_block="$(sed -n '/if \[\[ "\${REVIEW_MODE}" == "verify_only" \]\]; then/,/else/p' "${SCRIPT_DIR}/leadv2-review-run.sh")"
if [[ -n "${verify_only_block}" ]] && ! grep -q 'claims-without-evidence' <<<"${verify_only_block}"; then
  PASS=$((PASS + 1)); log "PASS: verify_only branch does not contain claims-without-evidence"
else
  FAIL=$((FAIL + 1)); ERRORS+=("verify_only branch purity"); log "FAIL: verify_only branch does not contain claims-without-evidence"
fi

# ── C4: the NEW content itself never contains a double-quote or backtick
# (codex --focus is a single shell word, per _review_flatten's own R6
# comment; the round-2 mission text also flows into codex argv via
# leadv2-dispatch-code.sh and into double-quoted shell strings in
# leadv2-helpers.sh / glm-coder.sh). Scoped to the added lines only -- the
# surrounding shell source legitimately uses "${var}" interpolation and
# existing bullets legitimately use escaped quotes (e.g. ask-lead.sh's
# \"<question>\"), so a whole-block check would false-positive on
# pre-existing, unrelated text. ─────────────────────────────────────────────
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
# L3 (round 2 extension): the mission-side copies in leadv2-helpers.sh and
# glm-coder.sh, and the dispatch-side injection lines in
# leadv2-dispatch-code.sh, get the same guard.
helpers_new_lines="$(grep -E '_LEADV2_EVIDENCE_CONTRACT_MISSION=' "${SCRIPT_DIR}/leadv2-helpers.sh")"
if [[ -n "${helpers_new_lines}" ]] && ! grep -qE '`' <<<"${helpers_new_lines}"; then
  PASS=$((PASS + 1)); log "PASS: leadv2-helpers.sh mission contract has no backtick"
else
  FAIL=$((FAIL + 1)); ERRORS+=("leadv2-helpers.sh mission contract backtick safety"); log "FAIL: leadv2-helpers.sh mission contract has no backtick"
fi
glm_new_lines="$(grep -E 'EVIDENCE_CONTRACT_PREAMBLE=' "${SCRIPT_DIR}/glm-coder.sh")"
if [[ -n "${glm_new_lines}" ]] && ! grep -qE '["`]' <<<"${glm_new_lines}"; then
  PASS=$((PASS + 1)); log "PASS: glm-coder.sh evidence preamble has no quote/backtick"
else
  FAIL=$((FAIL + 1)); ERRORS+=("glm-coder.sh evidence preamble quote/backtick safety"); log "FAIL: glm-coder.sh evidence preamble has no quote/backtick"
fi
dispatch_new_lines="$(grep -E '_LEADV2_EVIDENCE_CONTRACT_MISSION' "${SCRIPT_DIR}/leadv2-dispatch-code.sh")"
if [[ -n "${dispatch_new_lines}" ]] && ! grep -qE '`' <<<"${dispatch_new_lines}"; then
  PASS=$((PASS + 1)); log "PASS: leadv2-dispatch-code.sh injection lines have no backtick"
else
  FAIL=$((FAIL + 1)); ERRORS+=("leadv2-dispatch-code.sh injection backtick safety"); log "FAIL: leadv2-dispatch-code.sh injection lines have no backtick"
fi

# ── C9 (new, H2 drift pin): the canonical evidence-contract marker sentence
# is byte-identical across the three definition sites -- leadv2-helpers.sh
# (mission-side, dispatch/codex/kimi arms), glm-coder.sh (direct-invocation
# path), claude-subsession.sh (claude-arm preamble). Three textual copies by
# design decision (glm-coder.sh sources no shared lib today); this is the
# drift pin that makes that decision safe. Fails if any file has 0 or >1
# occurrences of the pinned sentence.
CEG_MARKER='EVIDENCE CONTRACT: every factual claim you write about an external system or API (endpoint behaviour, rate limit, auth flow, schema, provider quirk, version) must be immediately followed by its probe artifact — a curl/CLI invocation with its output, a log excerpt, or a doc URL plus the live check that confirmed it. If you have no artifact, prefix the claim with the literal token UNVERIFIED: — an untagged evidence-free external-system claim is a protocol violation, and round-1 reviewers treat one that drives a decision as BLOCKING.'
c9_ok=1
for f in leadv2-helpers.sh glm-coder.sh claude-subsession.sh; do
  c9_count="$(grep -cF -- "${CEG_MARKER}" "${SCRIPT_DIR}/${f}" 2>/dev/null || true)"
  if [[ "${c9_count}" != "1" ]]; then
    c9_ok=0
    log "C9: ${f} has ${c9_count:-0} occurrences of the canonical marker (expected 1)"
  fi
done
if [[ "${c9_ok}" == "1" ]]; then
  PASS=$((PASS + 1)); log "PASS: C9 canonical marker sentence identical (count=1) in all three sites"
else
  FAIL=$((FAIL + 1)); ERRORS+=("C9: canonical marker sentence drift across the three sites"); log "FAIL: C9 canonical marker sentence drift"
fi
# Baseline-side (red-first): PREFIX_SCRIPTS must NOT have the marker anywhere
# (H2 is a round-2-only fix) -- proves C9 is a real red-then-green case, not
# vacuously true because the baseline also happens to contain it.
c9_pre_ok=1
for f in leadv2-helpers.sh glm-coder.sh claude-subsession.sh; do
  if [[ -f "${PREFIX_SCRIPTS}/${f}" ]] && grep -qF -- "${CEG_MARKER}" "${PREFIX_SCRIPTS}/${f}" 2>/dev/null; then
    c9_pre_ok=0
  fi
done
if [[ "${c9_pre_ok}" == "1" ]]; then
  PASS=$((PASS + 1)); log "PASS: C9 marker absent from baseline (red-first confirmed)"
else
  GREEN_PRE_FIX=$((GREEN_PRE_FIX + 1))
  ERRORS+=("C9: GREEN-PRE-FIX -- baseline already carries the canonical marker")
  log "GREEN-PRE-FIX: C9 marker present in baseline"
fi

# ── C6: the actually-rendered round-1 mission contains the fifth lens ────────
# Invokes the real engine (stub resolver/arm, zero network) rather than
# sourcing _review_build_contract in isolation -- leadv2-review-run.sh runs
# its full pipeline unconditionally once invoked, so isolation-by-source would
# either hang on missing args or execute the whole gate. This mirrors the
# proven harness in test-review-round-exhaustive.sh.
c6_stub_dir="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-ceg-stubs.XXXXXX")"
CLEANUP_PATHS+=("${c6_stub_dir}")
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
CLEANUP_PATHS+=("${c6_root}")
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

# ── C7 (new, H1): rendered-prefix probe -- the case that would have caught
# H1. A scratch PROJECT_ROOT with ONLY .claude/agents/critic.md (minimal
# frontmatter + one body line) and DELIBERATELY NO .claude/skills/... -- this
# is exactly the live-repo shape (persona-engine, m3-market, respiro-ios)
# that produced H1: the "Protocol reference:" section rendered empty in
# every claude-arm prefix. Runs the real claude-subsession.sh through
# LEADV2_DRY_RUN=1 --wait (R7): build_cached_prefix() runs BEFORE the D5
# dry-run chokepoint, so the prefix is still materialised and its path still
# logged even though no claude CLI process is ever launched. Never deletes
# anything under /tmp/leadv2-cache (R8) -- only reads the path the run
# reports.
case_c7_rendered_prefix() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local f="${scripts_dir}/claude-subsession.sh"
  [[ -f "${f}" ]] || return 2

  local c7_root c7_mission c7_err prefix_path
  c7_root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-ceg-c7root.XXXXXX")"
  mkdir -p "${c7_root}/.claude/agents"
  cat > "${c7_root}/.claude/agents/critic.md" <<'EOF'
---
name: critic
model: sonnet
---
You are the critic. Review the diff for correctness.
EOF
  c7_mission="$(mktemp "${TMPDIR:-/tmp}/leadv2-ceg-c7mission.XXXXXX")"
  printf 'Mission: review the attached diff for correctness.\n' > "${c7_mission}"
  c7_err="$(mktemp "${TMPDIR:-/tmp}/leadv2-ceg-c7err.XXXXXX")"

  # Hermetic (L4-adjacent): unset any ambient CLAUDE_PLUGIN_ROOT so the case
  # exercises the resolution logic itself, not whatever install happens to be
  # cached on the machine running the suite -- a stale local plugin cache
  # (separate copy from this repo, see repo CLAUDE.md's own note on hook/cache
  # drift) would otherwise make this case flake independent of the fix.
  ( unset CLAUDE_PLUGIN_ROOT; PROJECT_ROOT="${c7_root}" LEADV2_DRY_RUN=1 bash "${f}" \
      --role critic --model sonnet --task-id CEGP7 \
      --mission-file "${c7_mission}" --wait ) >/dev/null 2>"${c7_err}"

  prefix_path="$(grep -o 'prefix path: .*' "${c7_err}" 2>/dev/null | tail -1 | sed 's/^prefix path: //')"

  local result=1
  if [[ -n "${prefix_path}" && -f "${prefix_path}" ]] \
     && grep -q 'EVIDENCE CONTRACT' "${prefix_path}" \
     && grep -q 'Evidence contract for external-system claims' "${prefix_path}"; then
    result=0
  fi

  rm -f "${c7_mission}" "${c7_err}"
  rm -rf "${c7_root}"
  return "${result}"
}
run_case "rendered-prefix-h1"           case_c7_rendered_prefix

# R7 companion assertion: post-fix run's stderr must show the DRY_RUN marker,
# proving nothing left the sandbox (real claude CLI never launched).
c7v_root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-ceg-c7v-root.XXXXXX")"
CLEANUP_PATHS+=("${c7v_root}")
mkdir -p "${c7v_root}/.claude/agents"
cat > "${c7v_root}/.claude/agents/critic.md" <<'EOF'
---
name: critic
model: sonnet
---
You are the critic.
EOF
c7v_mission="$(mktemp "${TMPDIR:-/tmp}/leadv2-ceg-c7v-mission.XXXXXX")"
printf 'Mission: review.\n' > "${c7v_mission}"
CLEANUP_PATHS+=("${c7v_mission}")
c7v_err="$(mktemp "${TMPDIR:-/tmp}/leadv2-ceg-c7v-err.XXXXXX")"
CLEANUP_PATHS+=("${c7v_err}")
( unset CLAUDE_PLUGIN_ROOT; PROJECT_ROOT="${c7v_root}" LEADV2_DRY_RUN=1 bash "${SCRIPT_DIR}/claude-subsession.sh" \
    --role critic --model sonnet --task-id CEGP7V \
    --mission-file "${c7v_mission}" --wait ) >/dev/null 2>"${c7v_err}"
if grep -q '\[DRY_RUN\]' "${c7v_err}" 2>/dev/null; then
  PASS=$((PASS + 1)); log "PASS: C7 companion -- DRY_RUN marker present, no real claude CLI launched"
else
  FAIL=$((FAIL + 1)); ERRORS+=("C7 companion: DRY_RUN marker absent"); log "FAIL: C7 companion -- DRY_RUN marker absent"
fi

# ── C8 (new, H2): rendered dispatch-mission probe. Live dispatch through
# leadv2-dispatch-code.sh, GLM arm, reusing the proven stub scaffolding of
# test-lane-placement-pin.sh (v1 router with resolver missing -> defaults to
# arm=glm, per that suite's own comment). Asserts the mission text handed to
# the GLM launcher's bg call carries the evidence-contract paragraph AND the
# UNVERIFIED: token.
#
# Codex arm: a full dispatch run through router-v2 forcing arm=codex needs
# THREE additional stub binaries (router-v2.sh filter+resolve, task-judge.sh,
# route-bandit.sh) wired through resolve_v2_dispatch() -- per the design's own
# accepted fallback ("if a full dispatch run proves too heavy or flaky ...
# the acceptable fallback is a _spawn_worker_body-scoped probe"), this case
# instead asserts STRUCTURALLY that the injection in _spawn_worker_body (a)
# is unconditional -- appears before `case "${arm}" in`, so every arm
# including codex passes through it -- and (b) the codex launch line consumes
# the SAME `${mission}` variable the injection mutated (no reassignment
# between the two). This is verified against the real leadv2-dispatch-code.sh
# source, not a live run; see developer.full.md for the honest caveat.
case_c8_dispatch_mission_glm() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local dc="${scripts_dir}/leadv2-dispatch-code.sh"
  [[ -f "${dc}" ]] || return 2

  local sandbox target glm_stub journal_stub mission_out
  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-ceg-c8-XXXXXX")"
  target="${sandbox}/target"
  mkdir -p "${target}"
  ( cd "${target}" && git init -q -b main \
    && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed ) >/dev/null 2>&1

  glm_stub="${sandbox}/glm-stub.sh"
  journal_stub="${sandbox}/journal-stub.sh"
  mission_out="${sandbox}/mission.txt"
  cat > "${glm_stub}" <<'SH'
#!/usr/bin/env bash
RUNS="${LEADV2_STUB_GLM_RUNS:-/tmp/leadv2-stub-glm-runs}"
MISSION_OUT="${LEADV2_STUB_MISSION_OUT:-}"
case "${1:-}" in
  bg)
    shift
    mission="$1"; shift
    [[ -z "${MISSION_OUT}" ]] || printf '%s' "${mission:-}" > "${MISSION_OUT}" 2>/dev/null
    mkdir -p "$RUNS" 2>/dev/null
    handle="stub-run-$(date +%s)-$$"
    printf '%s' "$handle" > "$RUNS/$handle" 2>/dev/null
    printf '%s\n' "$handle"
    exit 0
    ;;
  status) [[ -n "${2:-}" && -f "$RUNS/$2" ]] && exit 0; exit 1 ;;
  *) exit 0 ;;
esac
SH
  chmod +x "${glm_stub}"
  cat > "${journal_stub}" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "${journal_stub}"

  (
    export CLAUDE_PROJECT_DIR="${target}"
    export CLAUDE_PROJECT_ROOT="${target}"
    unset PROJECT_ROOT 2>/dev/null || true
    unset LEADV2_LANE_WORK_ROOT 2>/dev/null || true
    export LEADV2_DISPATCH_GLM_BIN="${glm_stub}"
    export LEADV2_STUB_GLM_RUNS="${sandbox}/glm-runs"
    export LEADV2_STUB_MISSION_OUT="${mission_out}"
    export LEADV2_JOURNAL_BIN="${journal_stub}"
    export LEADV2_DISPATCH_CACHE_DIR="${sandbox}/cache"
    export LEADV2_STATE_BASE="${sandbox}/state"
    export LEADV2_ROUTER_V2=0
    export GLM_POLICY_RESOLVER=""
    export LEADV2_LANE_SHAPE=off
    export LEADV2_DISPATCH_E2E_GATE=0
    export LEADV2_DISPATCH_REVIEW_GATE=0
    bash "${dc}" --kind tooling "C8 rendered dispatch mission probe fix the build" >/dev/null 2>&1
  )

  local result=1
  if [[ -f "${mission_out}" ]] && grep -q 'EVIDENCE CONTRACT' "${mission_out}" && grep -q 'UNVERIFIED:' "${mission_out}"; then
    result=0
  fi
  rm -rf "${sandbox}"
  return "${result}"
}
run_case "dispatch-mission-glm-h2"      case_c8_dispatch_mission_glm

# Structural companion for the codex arm (documented compromise, see above).
spawn_body="$(awk '/^_spawn_worker_body\(\) \{/{p=1} p{print} p && /^\}/{exit}' "${SCRIPT_DIR}/leadv2-dispatch-code.sh")"
inject_line_no="$(grep -n '_LEADV2_EVIDENCE_CONTRACT_MISSION' <<<"${spawn_body}" | head -1 | cut -d: -f1)"
case_line_no="$(grep -n 'case "\${arm}" in' <<<"${spawn_body}" | head -1 | cut -d: -f1)"
codex_launch_line="$(grep -n 'CODEX_BIN.*task.*mission' <<<"${spawn_body}" | head -1)"
c8_codex_ok=0
if [[ -n "${inject_line_no}" && -n "${case_line_no}" && "${inject_line_no}" -lt "${case_line_no}" \
      && -n "${codex_launch_line}" && "${codex_launch_line}" == *'"${mission}"'* ]]; then
  c8_codex_ok=1
fi
if [[ "${c8_codex_ok}" == "1" ]]; then
  PASS=$((PASS + 1)); log "PASS: C8 codex structural -- injection precedes arm case, codex consumes the same \${mission}"
else
  FAIL=$((FAIL + 1)); ERRORS+=("C8 codex structural check")
  log "FAIL: C8 codex structural -- injection/case ordering or mission-var mismatch"
fi

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ "${FAIL}" -gt 0 || "${GREEN_PRE_FIX}" -gt 0 ]]; then
  printf -- 'FAIL: %s\n' "${ERRORS[@]+"${ERRORS[@]}"}"
  exit 1
fi
exit 0
