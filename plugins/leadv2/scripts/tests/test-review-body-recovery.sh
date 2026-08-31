#!/usr/bin/env bash
# tests/test-review-body-recovery.sh — REVIEW-RUN-LOSES-VERDICTS-01.
#
# Two live-found defects in leadv2-review-run.sh:
#
#   1. A completed codex review whose captured body is housekeeping-only (the
#      `[codex] Thread ready (...)` / `[codex] Turn started (...)` progress
#      lines codex-task.sh's own _strip_meta does NOT filter) was declared
#      `review_body_lost` and spilled to another arm WITHOUT ever checking
#      codex-companion's own job store, even though the store held the real
#      verdict the whole time (`codex-task.sh result` -- no id needed, it
#      resolves the latest completed job for the current session).
#   2. An arm refusing on its own declared cooldown (e.g. GLM peak-hours,
#      `LEADV2_DISPATCH_REFUSED: <reason>` + rc 1/2/75) is a distinct outcome
#      from a genuine provider error, but nothing proved it stays distinct
#      and non-blocking as the classification/spill logic evolves.
#
# Drives the REAL leadv2-review-run.sh CLI end to end (never a
# reimplementation of its logic, never a scratch copy). Codex/glm/sonnet arms
# are stubbed via the engine's own injection points (LEADV2_DISPATCH_CODEX_BIN,
# LEADV2_DISPATCH_GLM_BIN, LEADV2_DISPATCH_ARCHITECT_BIN) and arm selection via
# LEADV2_GLM_POLICY_RESOLVER -- no real codex job, no real review.
#
# Run: bash scripts/tests/test-review-body-recovery.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

ENGINE="${SCRIPTS_ROOT}/leadv2-review-run.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

if bash -n "$ENGINE"; then
  pass "bash -n clean (leadv2-review-run.sh)"
else
  fail "bash -n failed on leadv2-review-run.sh"
fi
if /bin/bash -n "$ENGINE" 2>/dev/null; then
  pass "/bin/bash 3.2 -n clean (leadv2-review-run.sh)"
else
  fail "/bin/bash 3.2 -n failed on leadv2-review-run.sh"
fi

SUITE_TMP="$(lv2_mktemp_dir "review-body-recovery-test")"
trap 'rm -rf "$SUITE_TMP"' EXIT

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

# make_committed_lane <name> -> prints repo path. init commit becomes
# refs/remotes/origin/main, then one committed lane change on top becomes
# HEAD -- gives _review_resolve_codex_base a real ancestor to diff from.
make_committed_lane() {
  local name="$1"
  local repo="${SUITE_TMP}/${name}/root"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@test.local"
  git -C "$repo" config user.name "test"
  printf 'baseline\n' > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m init
  lv2_assert_scratch_repo "$repo"
  local start_sha
  start_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" update-ref refs/remotes/origin/main "$start_sha"
  printf '%s\n' "${name}-lane-change" >> "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m "lane change"
  printf '%s' "$repo"
}

# make_plain_root <name> -> a scratch git repo with NO codex ancestry needed
# (used for arm scenarios that never invoke the codex branch).
make_plain_root() {
  local name="$1"
  local repo="${SUITE_TMP}/${name}/root"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@test.local"
  git -C "$repo" config user.name "test"
  printf 'baseline\n' > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m init
  lv2_assert_scratch_repo "$repo"
  printf '%s\n' "${name}-change" >> "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m "lane change"
  printf '%s' "$repo"
}

make_diff_file() { # <name> -> prints path of a non-empty scratch diff file
  local name="$1"
  local f="${SUITE_TMP}/${name}/diff.txt"
  mkdir -p "$(dirname "$f")"
  printf -- '--- a/file.txt\n+++ b/file.txt\n@@\n-baseline\n+changed-%s-%s\n' "${name}" "$$" > "$f"
  printf '%s' "$f"
}

# make_resolver_stub <name> <reviewer> <pool-csv> -> prints stub path. pool
# entries must be "<arm>:ok:" per leadv2-glm-policy-resolve.py's own contract.
make_resolver_stub() {
  local name="$1" reviewer="$2" pool="$3"
  local stub="${SUITE_TMP}/${name}/resolver.py"
  mkdir -p "$(dirname "$stub")"
  cat > "$stub" <<PY
print("reviewer=${reviewer}")
print("pool=${pool}")
print("refusal=")
PY
  printf '%s' "$stub"
}

# make_codex_stub <name> <review-mode> <store-mode> -> prints stub path.
# Dispatches on argv[1] ("adversarial-review" vs "result") the same way the
# real codex-task.sh does.
#   review-mode: housekeeping (short, no REVIEW_VERDICT, real-looking) | healthy
#   store-mode:  has_verdict (FAIL, 4 findings) | empty (housekeeping only)
make_codex_stub() {
  local name="$1" review_mode="$2" store_mode="$3"
  local stub="${SUITE_TMP}/${name}/codex-stub.sh"
  mkdir -p "$(dirname "$stub")"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'sub="${1:-}"\n'
    printf 'if [[ "$sub" == "adversarial-review" ]]; then\n'
    if [[ "$review_mode" == healthy ]]; then
      printf '  printf "REVIEW_VERDICT: PASS\\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\\nHealthy codex stub body, long enough to clear the 300-byte body floor comfortably.\\n"\n'
    else
      printf '  printf "[codex] Thread ready (thread-abc).\\n[codex] Turn started (turn-1).\\n" >&2\n'
      printf '  printf "Thread ready (thread-abc).\\nTurn started (turn-1).\\n"\n'
    fi
    printf '  exit 0\n'
    printf 'elif [[ "$sub" == "result" ]]; then\n'
    if [[ "$store_mode" == has_verdict ]]; then
      printf '  printf "REVIEW_VERDICT: FAIL\\nREVIEW_FINDINGS: critical=0 high=4 medium=0 low=0\\nFour High findings recovered from the codex job store: gate integrity issues.\\n"\n'
      printf '  exit 0\n'
    else
      printf '  printf "[codex] Thread ready (thread-abc).\\n[codex] Turn started (turn-1).\\n"\n'
      printf '  exit 0\n'
    fi
    printf 'else\n'
    printf '  exit 0\n'
    printf 'fi\n'
  } > "$stub"
  chmod +x "$stub"
  printf '%s' "$stub"
}

# make_refusing_bin <name> <reason> -> prints stub path. Generic cooldown-
# refusal launcher: writes the LEADV2_DISPATCH_REFUSED marker + exits 2, same
# admission-refusal contract every real arm launcher uses.
make_refusing_bin() {
  local name="$1" reason="$2"
  local stub="${SUITE_TMP}/${name}/refuse-${reason}.sh"
  mkdir -p "$(dirname "$stub")"
  cat > "$stub" <<SH
#!/usr/bin/env bash
echo "LEADV2_DISPATCH_REFUSED: ${reason}" >&2
echo "[stub] declined: ${reason}" >&2
exit 2
SH
  chmod +x "$stub"
  printf '%s' "$stub"
}

# make_crash_bin <name> -> a genuine transport failure: no marker, just dies.
make_crash_bin() {
  local name="$1"
  local stub="${SUITE_TMP}/${name}/crash.sh"
  mkdir -p "$(dirname "$stub")"
  cat > "$stub" <<'SH'
#!/usr/bin/env bash
echo "connection reset by peer" >&2
exit 1
SH
  chmod +x "$stub"
  printf '%s' "$stub"
}

# make_arch_stub <name> <mode> -> drives run_reviewer_arm's sonnet/opus branch.
# mode=healthy writes a clean PASS to stdout (captured into review_out).
# mode=refuse:<reason> writes the marker to stderr and exits 1.
# mode=crash writes an unmarked failure and exits 1.
make_arch_stub() {
  local name="$1" mode="$2"
  local stub="${SUITE_TMP}/${name}/arch-${RANDOM}.sh"
  mkdir -p "$(dirname "$stub")"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'role=""\n'
    printf 'while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; *) shift ;; esac; done\n'
    printf '[[ "$role" == "hack-detect" ]] && exit 0\n'
    case "$mode" in
      healthy)
        printf 'printf "REVIEW_VERDICT: PASS\\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\\nReviewed the diff end to end, nothing blocking, padded past the body floor.\\n"\n'
        printf 'exit 0\n'
        ;;
      refuse:*)
        printf 'echo "LEADV2_DISPATCH_REFUSED: %s" >&2\n' "${mode#refuse:}"
        printf 'exit 1\n'
        ;;
      crash)
        printf 'echo "connection reset by peer" >&2\n'
        printf 'exit 1\n'
        ;;
    esac
  } > "$stub"
  chmod +x "$stub"
  printf '%s' "$stub"
}

# run_review <root> <task> <handoff> <diff> <resolver> <author> [extra env assignments...]
# echoes "<engine-exit>"; stderr captured to $SUITE_TMP/<task>.err. <author>
# must never equal a name present in the scenario's pool -- the engine's own
# self-review guard (reviewer_equals_author) refuses up front if it does.
run_review() {
  local root="$1" task="$2" handoff="$3" diff_file="$4" resolver="$5" author="$6"; shift 6
  mkdir -p "$handoff" "${SUITE_TMP}/${task}-cache"
  local dispatch_bin="${SUITE_TMP}/${task}-cache/dispatch-noop.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dispatch_bin"
  chmod +x "$dispatch_bin"
  env "$@" \
    LEADV2_GLM_POLICY_RESOLVER="$resolver" \
    LEADV2_DISPATCH_BIN="$dispatch_bin" \
    LEADV2_DISPATCH_CACHE_DIR="${SUITE_TMP}/${task}-cache" \
    LEADV2_JOURNAL_BIN=/bin/true \
    LEADV2_REVIEW_FANOUT=1 \
    bash "$ENGINE" --task "$task" --root "$root" --handoff "$handoff" --diff "$diff_file" --author "$author" \
    >/dev/null 2>"${SUITE_TMP}/${task}.err"
  printf '%s' $?
}

# ===========================================================================
# Scenario 1 — codex rc=0, housekeeping-only body, STORE HAS a verdict:
# verdict is recovered, findings preserved, no retry, no body_lost.
# ===========================================================================
s1_root="$(make_committed_lane s1)"
s1_handoff="${SUITE_TMP}/s1/handoff"
s1_diff="$(make_diff_file s1)"
s1_resolver="$(make_resolver_stub s1 codex "codex:ok:")"
s1_codex="$(make_codex_stub s1 housekeeping has_verdict)"
s1_rc="$(run_review "$s1_root" "s1" "$s1_handoff" "$s1_diff" "$s1_resolver" sonnet \
  LEADV2_DISPATCH_CODEX_BIN="$s1_codex")"
s1_gate="${s1_handoff}/review-gate.md"
s1_err="${SUITE_TMP}/s1.err"

if [[ "$s1_rc" == "7" ]] && grep -q '^status: fail$' "$s1_gate" 2>/dev/null; then
  pass "S1: gate reports the RECOVERED verdict (FAIL, from the store) -- exit 7, status: fail"
else
  fail "S1: expected exit 7 / status: fail from the recovered verdict -- rc=${s1_rc} gate=$(cat "$s1_gate" 2>/dev/null || echo MISSING)"
fi
if grep -q 'high: 4' "$s1_gate" 2>/dev/null; then
  pass "S1: recovered findings preserved (high: 4)"
else
  fail "S1: recovered findings not in gate -- $(cat "$s1_gate" 2>/dev/null)"
fi
if grep -q 'review_body_recovered task=s1 arm=codex source=codex_store' "$s1_err"; then
  pass "S1: decision log names the recovery (review_body_recovered ... source=codex_store)"
else
  fail "S1: missing review_body_recovered decision -- $(cat "$s1_err")"
fi
if grep -q 'review_arm_retry' "$s1_err"; then
  fail "S1: unexpected review_arm_retry -- recovery must skip the retry-to-another-arm path"
else
  pass "S1: no review_arm_retry (recovery skipped the spill path)"
fi
if grep -q 'reason=review_body_lost' "$s1_err"; then
  fail "S1: unexpected review_body_lost -- the verdict was recoverable"
else
  pass "S1: no review_body_lost declared"
fi

# ===========================================================================
# Scenario 2 — codex rc=0, housekeeping-only body, STORE HAS NOTHING EITHER:
# body_lost is declared AND the log names both retrieval attempts.
# ===========================================================================
s2_root="$(make_committed_lane s2)"
s2_handoff="${SUITE_TMP}/s2/handoff"
s2_diff="$(make_diff_file s2)"
s2_resolver="$(make_resolver_stub s2 codex "codex:ok:")"
s2_codex="$(make_codex_stub s2 housekeeping empty)"
s2_rc="$(run_review "$s2_root" "s2" "$s2_handoff" "$s2_diff" "$s2_resolver" sonnet \
  LEADV2_DISPATCH_CODEX_BIN="$s2_codex")"
s2_gate="${s2_handoff}/review-gate.md"
s2_err="${SUITE_TMP}/s2.err"

if [[ "$s2_rc" == "6" ]] && grep -q '^reason: review_body_lost$' "$s2_gate" 2>/dev/null; then
  pass "S2: gate correctly declares review_body_lost (store also empty) -- exit 6"
else
  fail "S2: expected exit 6 / reason: review_body_lost -- rc=${s2_rc} gate=$(cat "$s2_gate" 2>/dev/null || echo MISSING)"
fi
if grep -q '^retrieval_attempts: body,codex_store$' "$s2_gate" 2>/dev/null; then
  pass "S2: gate names BOTH retrieval attempts (body,codex_store)"
else
  fail "S2: gate missing retrieval_attempts line -- $(cat "$s2_gate" 2>/dev/null)"
fi
if grep -q 'reason=review_body_lost .*retrieval_attempts=body,codex_store' "$s2_err"; then
  pass "S2: decision log names both retrieval attempts"
else
  fail "S2: decision log missing retrieval_attempts -- $(cat "$s2_err")"
fi

# ===========================================================================
# Scenario 3 — an arm refusing on a DECLARED COOLDOWN (mission-literal: glm,
# peak_hours) spills to the next arm, WITHOUT blocking the gate, and is
# distinguishable in the log from a provider error.
# ===========================================================================
s3_root="$(make_plain_root s3)"
s3_handoff="${SUITE_TMP}/s3/handoff"
s3_diff="$(make_diff_file s3)"
s3_resolver="$(make_resolver_stub s3 glm "glm:ok:,sonnet:ok:")"
s3_glm="$(make_refusing_bin s3 peak_hours)"
s3_arch="$(make_arch_stub s3 healthy)"
s3_rc="$(run_review "$s3_root" "s3" "$s3_handoff" "$s3_diff" "$s3_resolver" kimi \
  LEADV2_DISPATCH_GLM_BIN="$s3_glm" LEADV2_DISPATCH_ARCHITECT_BIN="$s3_arch")"
s3_gate="${s3_handoff}/review-gate.md"
s3_err="${SUITE_TMP}/s3.err"

if [[ "$s3_rc" == "0" ]] && grep -q '^status: pass$' "$s3_gate" 2>/dev/null; then
  pass "S3: cooldown spill reached a real gate (status: pass), exit 0 -- gate NOT blocked"
else
  fail "S3: cooldown incorrectly blocked the gate -- rc=${s3_rc} gate=$(cat "$s3_gate" 2>/dev/null || echo MISSING)"
fi
if grep -q 'status=arm_refused arm=glm reason=refused_peak_hours' "$s3_err"; then
  pass "S3: decision log names the cooldown refusal distinctly (arm_refused reason=refused_peak_hours)"
else
  fail "S3: missing arm_refused reason=refused_peak_hours -- $(cat "$s3_err")"
fi
if grep -q 'status=blocked reason=provider_error' "$s3_err"; then
  fail "S3: cooldown misclassified as provider_error"
else
  pass "S3: cooldown never logged as provider_error"
fi

# ===========================================================================
# Scenario 4 — a GENUINE provider error (no refusal marker, real transport
# failure) still blocks the gate, exactly as today. Control for S3/S5.
# ===========================================================================
s4_root="$(make_plain_root s4)"
s4_handoff="${SUITE_TMP}/s4/handoff"
s4_diff="$(make_diff_file s4)"
s4_resolver="$(make_resolver_stub s4 sonnet "sonnet:ok:")"
s4_arch="$(make_arch_stub s4 crash)"
s4_rc="$(run_review "$s4_root" "s4" "$s4_handoff" "$s4_diff" "$s4_resolver" kimi \
  LEADV2_DISPATCH_ARCHITECT_BIN="$s4_arch")"
s4_gate="${s4_handoff}/review-gate.md"
s4_err="${SUITE_TMP}/s4.err"

if [[ "$s4_rc" == "6" ]] && grep -q '^reason: provider_error$' "$s4_gate" 2>/dev/null; then
  pass "S4: genuine provider error still blocks the gate (exit 6, reason: provider_error)"
else
  fail "S4: expected provider_error block -- rc=${s4_rc} gate=$(cat "$s4_gate" 2>/dev/null || echo MISSING)"
fi

# ===========================================================================
# Scenario 5 — a DIFFERENT arm name and a DIFFERENT reason string (neither
# "glm" nor "peak_hours") gets the identical cooldown-spill treatment: the
# decision path must key on "refused via a declared marker", never on a
# literal arm or reason string.
# ===========================================================================
s5_root="$(make_plain_root s5)"
s5_handoff="${SUITE_TMP}/s5/handoff"
s5_diff="$(make_diff_file s5)"
s5_resolver="$(make_resolver_stub s5 opus "opus:ok:,sonnet:ok:")"
s5_opus="$(make_arch_stub s5 refuse:widget_shortage)"
s5_sonnet="$(make_arch_stub s5 healthy)"
# Both opus and sonnet go through LEADV2_DISPATCH_ARCHITECT_BIN in the real
# engine (arm name is passed as --model), so a single stub must branch on it.
s5_arch="${SUITE_TMP}/s5/arch-router.sh"
cat > "$s5_arch" <<SH
#!/usr/bin/env bash
role=""; model=""
args=("\$@")
i=0
while [[ \$i -lt \${#args[@]} ]]; do
  case "\${args[\$i]}" in
    --role) role="\${args[\$((i+1))]}" ;;
    --model) model="\${args[\$((i+1))]}" ;;
  esac
  i=\$((i+1))
done
[[ "\$role" == "hack-detect" ]] && exit 0
if [[ "\$model" == "opus" ]]; then
  bash "$s5_opus" "\$@"
  exit \$?
fi
bash "$s5_sonnet" "\$@"
exit \$?
SH
chmod +x "$s5_arch"
s5_rc="$(run_review "$s5_root" "s5" "$s5_handoff" "$s5_diff" "$s5_resolver" kimi \
  LEADV2_DISPATCH_ARCHITECT_BIN="$s5_arch")"
s5_gate="${s5_handoff}/review-gate.md"
s5_err="${SUITE_TMP}/s5.err"

if [[ "$s5_rc" == "0" ]] && grep -q '^status: pass$' "$s5_gate" 2>/dev/null; then
  pass "S5: novel arm (opus) + novel reason (widget_shortage) spills identically, gate NOT blocked"
else
  fail "S5: novel arm/reason cooldown incorrectly blocked -- rc=${s5_rc} gate=$(cat "$s5_gate" 2>/dev/null || echo MISSING)"
fi
if grep -q 'status=arm_refused arm=opus reason=refused_quota' "$s5_err"; then
  pass "S5: refusal classified generically (refused_quota, not a peak_hours-only path)"
else
  fail "S5: missing generic arm_refused classification -- $(cat "$s5_err")"
fi
if grep -q 'status=blocked reason=provider_error' "$s5_err"; then
  fail "S5: novel-reason cooldown misclassified as provider_error"
else
  pass "S5: novel-reason cooldown never logged as provider_error"
fi

# ===========================================================================
# Mutation controls — prove S1 (recovery) and S3 (cooldown-vs-error) actually
# assert something: mutate the REAL production function, expect RED, revert
# byte-for-byte, expect GREEN again. Never a scratch copy of the engine.
# ===========================================================================
ENGINE_BACKUP="${SUITE_TMP}/engine.orig"
cp "$ENGINE" "$ENGINE_BACKUP"

# --- Mutation A: disable codex-store recovery (targets S1) -----------------
# _review_recover_from_codex_store's success path always returns 1 instead of
# 0, so a recoverable body must fall through to the old lost/retry behavior.
sed -i.bak 's/^  printf '"'"'%s\\n'"'"' "\${store_out}" > "\${rfile}.tmp"$/  return 1  # MUTATION-A/' "$ENGINE"
rm -f "${ENGINE}.bak"
if bash -n "$ENGINE"; then
  pass "MUTATION-A: mutated engine still parses (bash -n)"
else
  fail "MUTATION-A: mutated engine failed bash -n -- aborting mutation checks"
fi

s1m_root="$(make_committed_lane s1m)"
s1m_handoff="${SUITE_TMP}/s1m/handoff"
s1m_diff="$(make_diff_file s1m)"
s1m_resolver="$(make_resolver_stub s1m codex "codex:ok:")"
s1m_codex="$(make_codex_stub s1m housekeeping has_verdict)"
s1m_rc="$(run_review "$s1m_root" "s1m" "$s1m_handoff" "$s1m_diff" "$s1m_resolver" sonnet \
  LEADV2_DISPATCH_CODEX_BIN="$s1m_codex")"
s1m_gate="${s1m_handoff}/review-gate.md"
if grep -q 'reason: review_body_lost' "$s1m_gate" 2>/dev/null; then
  pass "MUTATION-A RED: with recovery disabled, S1's recoverable body is now (wrongly) lost -- rc=${s1m_rc}"
else
  fail "MUTATION-A RED FAILED: mutation did not turn S1 red -- gate=$(cat "$s1m_gate" 2>/dev/null || echo MISSING) rc=${s1m_rc}"
fi

cp "$ENGINE_BACKUP" "$ENGINE"
if bash -n "$ENGINE"; then
  pass "MUTATION-A: engine reverted, bash -n clean"
else
  fail "MUTATION-A: engine failed bash -n after revert"
fi

s1g_root="$(make_committed_lane s1g)"
s1g_handoff="${SUITE_TMP}/s1g/handoff"
s1g_diff="$(make_diff_file s1g)"
s1g_resolver="$(make_resolver_stub s1g codex "codex:ok:")"
s1g_codex="$(make_codex_stub s1g housekeeping has_verdict)"
s1g_rc="$(run_review "$s1g_root" "s1g" "$s1g_handoff" "$s1g_diff" "$s1g_resolver" sonnet \
  LEADV2_DISPATCH_CODEX_BIN="$s1g_codex")"
s1g_gate="${s1g_handoff}/review-gate.md"
if [[ "$s1g_rc" == "7" ]] && grep -q '^status: fail$' "$s1g_gate" 2>/dev/null; then
  pass "MUTATION-A GREEN: reverted engine recovers S1 again"
else
  fail "MUTATION-A GREEN FAILED: revert did not restore recovery -- rc=${s1g_rc} gate=$(cat "$s1g_gate" 2>/dev/null || echo MISSING)"
fi

# --- Mutation B: disable declared-refusal classification (targets S3/S5) ---
# classify_arm_failure's marker branch is neutered so a declared cooldown
# refusal (rc 1/2/75 + LEADV2_DISPATCH_REFUSED marker) is no longer
# recognised as refused_* at all -- it must fall through to "ran", which the
# union-verdict path with no parseable body turns into a blocked gate.
sed -i.bak "s/if \[\[ -n \"\${marker}\" \&\& ( \"\${rc}\" == \"1\" || \"\${rc}\" == \"2\" || \"\${rc}\" == \"75\" ) \]\]; then/if [[ -n \"\${marker}\" \&\& 0 -eq 1 ]]; then  # MUTATION-B/" "$ENGINE"
rm -f "${ENGINE}.bak"
if bash -n "$ENGINE"; then
  pass "MUTATION-B: mutated engine still parses (bash -n)"
else
  fail "MUTATION-B: mutated engine failed bash -n -- aborting mutation checks"
fi

s3m_root="$(make_plain_root s3m)"
s3m_handoff="${SUITE_TMP}/s3m/handoff"
s3m_diff="$(make_diff_file s3m)"
s3m_resolver="$(make_resolver_stub s3m glm "glm:ok:,sonnet:ok:")"
s3m_glm="$(make_refusing_bin s3m peak_hours)"
s3m_arch="$(make_arch_stub s3m healthy)"
s3m_rc="$(run_review "$s3m_root" "s3m" "$s3m_handoff" "$s3m_diff" "$s3m_resolver" kimi \
  LEADV2_DISPATCH_GLM_BIN="$s3m_glm" LEADV2_DISPATCH_ARCHITECT_BIN="$s3m_arch")"
s3m_gate="${s3m_handoff}/review-gate.md"
if grep -q '^reason: provider_error$' "$s3m_gate" 2>/dev/null; then
  pass "MUTATION-B RED: with refusal-classification disabled, a cooldown now (wrongly) blocks as provider_error -- rc=${s3m_rc}"
else
  fail "MUTATION-B RED FAILED: mutation did not turn S3 red -- gate=$(cat "$s3m_gate" 2>/dev/null || echo MISSING) rc=${s3m_rc}"
fi

cp "$ENGINE_BACKUP" "$ENGINE"
if bash -n "$ENGINE"; then
  pass "MUTATION-B: engine reverted, bash -n clean"
else
  fail "MUTATION-B: engine failed bash -n after revert"
fi

s3g_root="$(make_plain_root s3g)"
s3g_handoff="${SUITE_TMP}/s3g/handoff"
s3g_diff="$(make_diff_file s3g)"
s3g_resolver="$(make_resolver_stub s3g glm "glm:ok:,sonnet:ok:")"
s3g_glm="$(make_refusing_bin s3g peak_hours)"
s3g_arch="$(make_arch_stub s3g healthy)"
s3g_rc="$(run_review "$s3g_root" "s3g" "$s3g_handoff" "$s3g_diff" "$s3g_resolver" kimi \
  LEADV2_DISPATCH_GLM_BIN="$s3g_glm" LEADV2_DISPATCH_ARCHITECT_BIN="$s3g_arch")"
s3g_gate="${s3g_handoff}/review-gate.md"
if [[ "$s3g_rc" == "0" ]] && grep -q '^status: pass$' "$s3g_gate" 2>/dev/null; then
  pass "MUTATION-B GREEN: reverted engine spills the cooldown again, gate not blocked"
else
  fail "MUTATION-B GREEN FAILED: revert did not restore cooldown spill -- rc=${s3g_rc} gate=$(cat "$s3g_gate" 2>/dev/null || echo MISSING)"
fi

# Final proof the mutation cycle left the production file byte-identical.
if diff -q "$ENGINE_BACKUP" "$ENGINE" >/dev/null 2>&1; then
  pass "engine file is byte-identical to pre-mutation backup after both revert cycles"
else
  fail "engine file DIFFERS from pre-mutation backup -- mutation revert is incomplete"
fi

# ---------------------------------------------------------------------------
log "PASS=${PASS} FAIL=${FAIL}"
if [[ "$FAIL" -gt 0 ]]; then
  for e in "${ERRORS[@]}"; do log "$e"; done
  exit 1
fi
exit 0
