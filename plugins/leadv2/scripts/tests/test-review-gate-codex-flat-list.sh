#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, discovered by scan_suite_triggers):
# run-all-triggers: leadv2-review-run.sh leadv2-review-findings.sh
# tests/test-review-gate-codex-flat-list.sh — PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01.
#
# Live defect: a real Codex adversarial review (specimen copied verbatim into
# fixtures/review-gate-codex-flat-list/review-codex.md from
# persona-engine docs/handoff/V5-M1-CI-SELECTION-R2/review-codex.md) declares
# REVIEW_VERDICT: FAIL and REVIEW_FINDINGS: critical=0 high=1 medium=0 low=0,
# with its one finding written as a flat bracket-severity bullet
# ("- [high] Title (path:line)"), never a `FINDING:` line. leadv2-review-run.sh's
# own per-arm union loop understood only `^FINDING:` lines, so the union array
# stayed empty, tripped the "declared FAIL but zero Critical/High" impossible-
# state check, and the gate reported status=blocked reason=findings_lost over a
# review that was never lost.
#
# Drives the REAL leadv2-review-run.sh CLI end to end (same harness pattern as
# test-review-body-recovery.sh: stub the reviewer arm via
# LEADV2_DISPATCH_ARCHITECT_BIN, arm selection via LEADV2_GLM_POLICY_RESOLVER --
# no real provider call, no reimplementation of the gate's parsing logic).
#
# Run: bash scripts/tests/test-review-gate-codex-flat-list.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

ENGINE="${SCRIPTS_ROOT}/leadv2-review-run.sh"
FIXTURE="${SCRIPT_DIR}/fixtures/review-gate-codex-flat-list/review-codex.md"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

[[ -s "$FIXTURE" ]] || { fail "fixture missing: $FIXTURE"; }

if bash -n "$ENGINE"; then
  pass "bash -n clean (leadv2-review-run.sh)"
else
  fail "bash -n failed on leadv2-review-run.sh"
fi

# The acceptance probe's own count: bracketed [high] findings actually present
# in the specimen. This must equal what the gate derives, independent of the
# production script's own counting logic (no shared-bug tautology).
EXPECTED_HIGH="$(grep -c '\[high\]' "$FIXTURE" 2>/dev/null | tr -d '[:space:]')"
if [[ "${EXPECTED_HIGH:-0}" -ge 1 ]]; then
  pass "fixture carries ${EXPECTED_HIGH} bracketed [high] finding(s)"
else
  fail "fixture has no bracketed [high] findings -- test fixture is wrong"
fi

SUITE_TMP="$(lv2_mktemp_dir "review-gate-codex-flat-list-test")"
trap 'rm -rf "$SUITE_TMP"' EXIT

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

make_resolver_stub() { # <name> <reviewer> <pool-csv>
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

# make_flat_list_arch_stub <name> <fixture-file> -> prints stub path. Emits the
# fixture VERBATIM as the reviewer body -- the real Codex flat bracket-severity
# shape, never a synthetic FINDING:-line reconstruction of it.
make_flat_list_arch_stub() {
  local name="$1" fixture="$2"
  local stub="${SUITE_TMP}/${name}/farch-${RANDOM}.sh"
  mkdir -p "$(dirname "$stub")"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'role=""; task_id=""\n'
    printf 'while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; --task-id) task_id="$2"; shift 2 ;; *) shift ;; esac; done\n'
    printf '[[ "$task_id" == *-review-hackdetect ]] && exit 0\n'
    printf 'cat %q\n' "$fixture"
    printf 'exit 0\n'
  } > "$stub"
  chmod +x "$stub"
  printf '%s' "$stub"
}

run_review() { # <root> <task> <handoff> <diff> <resolver> <author> [extra env...]
  run_review_with_engine "$ENGINE" "$@"
}

# run_review_with_engine <engine> <root> <task> <handoff> <diff> <resolver> <author> [extra env...]
# -- same as run_review but against an arbitrary engine copy, so the mutation
# control below can drive a scratch engine through the identical harness path.
run_review_with_engine() {
  local engine="$1" root="$2" task="$3" handoff="$4" diff_file="$5" resolver="$6" author="$7"; shift 7
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
    LEADV2_BURN_GOVERNOR=0 \
    bash "$engine" --task "$task" --root "$root" --handoff "$handoff" --diff "$diff_file" --author "$author" \
    >/dev/null 2>"${SUITE_TMP}/${task}.err"
  printf '%s' $?
}

# ===========================================================================
# Scenario 1 (positive) — the real specimen, fed through the real engine.
# ===========================================================================
s1_root="$(make_plain_root s1)"
s1_handoff="${SUITE_TMP}/s1/handoff"
s1_diff="$(make_diff_file s1)"
s1_resolver="$(make_resolver_stub s1 sonnet "sonnet:ok:")"
s1_arch="$(make_flat_list_arch_stub s1 "$FIXTURE")"
s1_rc="$(run_review "$s1_root" "s1" "$s1_handoff" "$s1_diff" "$s1_resolver" kimi \
  LEADV2_DISPATCH_ARCHITECT_BIN="$s1_arch")"
s1_gate="${s1_handoff}/review-gate.md"
s1_json="${s1_handoff}/review-findings.json"
s1_err="${SUITE_TMP}/s1.err"

if grep -q '^status: blocked$' "$s1_gate" 2>/dev/null && grep -q '^reason: findings_lost$' "$s1_gate" 2>/dev/null; then
  fail "S1: gate STILL reports findings_lost over a real flat-bracket-list review -- rc=${s1_rc} gate=$(cat "$s1_gate" 2>/dev/null || echo MISSING)"
else
  pass "S1: gate does not misreport findings_lost for the flat bracket-list specimen"
fi
if [[ "$s1_rc" == "7" ]] && grep -q '^status: fail$' "$s1_gate" 2>/dev/null; then
  pass "S1: gate correctly reports status=fail (exit 7) for the declared FAIL verdict"
else
  fail "S1: expected exit 7 / status: fail -- rc=${s1_rc} gate=$(cat "$s1_gate" 2>/dev/null || echo MISSING)"
fi
if grep -q "^high: ${EXPECTED_HIGH}\$" "$s1_gate" 2>/dev/null; then
  pass "S1: gate's high count (${EXPECTED_HIGH}) equals the fixture's bracketed [high] finding count"
else
  fail "S1: gate high count does not match fixture bracket count (${EXPECTED_HIGH}) -- gate=$(cat "$s1_gate" 2>/dev/null || echo MISSING)"
fi
if grep -q "^findings_total: ${EXPECTED_HIGH}\$" "$s1_gate" 2>/dev/null; then
  pass "S1: gate's findings_total (${EXPECTED_HIGH}) is present on the normal fail path"
else
  fail "S1: findings_total missing or wrong on the normal fail path -- gate=$(cat "$s1_gate" 2>/dev/null || echo MISSING)"
fi
s1_json_high="$(python3 - "$s1_json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print(0)
    raise SystemExit
print(sum(1 for x in d.get("findings", []) if x.get("severity") == "High"))
PY
)"
if [[ "$s1_json_high" == "$EXPECTED_HIGH" ]]; then
  pass "S1: review-findings.json independently counts ${EXPECTED_HIGH} High finding(s) -- agrees with gate"
else
  fail "S1: review-findings.json High count -- expected ${EXPECTED_HIGH}, got '${s1_json_high}' -- $(cat "$s1_json" 2>/dev/null)"
fi

# ===========================================================================
# Scenario 2 (negative control, real empty/unreadable report) — findings_lost
# must remain reachable for the case it was written for: a declared FAIL with
# a genuinely empty union (no FINDING: lines, no bracket lines at all).
# ===========================================================================
s2_root="$(make_plain_root s2)"
s2_handoff="${SUITE_TMP}/s2/handoff"
s2_diff="$(make_diff_file s2)"
s2_resolver="$(make_resolver_stub s2 sonnet "sonnet:ok:")"
s2_arch="${SUITE_TMP}/s2/farch.sh"
mkdir -p "$(dirname "$s2_arch")"
{
  printf '#!/usr/bin/env bash\n'
  printf 'role=""; task_id=""\n'
  printf 'while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; --task-id) task_id="$2"; shift 2 ;; *) shift ;; esac; done\n'
  printf '[[ "$task_id" == *-review-hackdetect ]] && exit 0\n'
  printf 'printf "REVIEW_VERDICT: FAIL\\n"\n'
  printf 'printf "REVIEW_FINDINGS: critical=0 high=5 medium=0 low=0\\n"\n'
  printf 'printf "Padding sentence so the review body clears the floor comfortably every run.\\n"\n'
  printf 'exit 0\n'
} > "$s2_arch"
chmod +x "$s2_arch"
s2_rc="$(run_review "$s2_root" "s2" "$s2_handoff" "$s2_diff" "$s2_resolver" kimi \
  LEADV2_DISPATCH_ARCHITECT_BIN="$s2_arch")"
s2_gate="${s2_handoff}/review-gate.md"
if [[ "$s2_rc" == "6" ]] && grep -q '^status: blocked$' "$s2_gate" 2>/dev/null && grep -q '^reason: findings_lost$' "$s2_gate" 2>/dev/null; then
  pass "S2: a genuinely empty union (no FINDING:, no bracket lines) still blocks as findings_lost"
else
  fail "S2: findings_lost no longer reachable for a truly empty review -- rc=${s2_rc} gate=$(cat "$s2_gate" 2>/dev/null || echo MISSING)"
fi

# ===========================================================================
# Scenario 3 (round 2, mixed shape) — a report carrying BOTH a structured
# `FINDING:` line and a flat bracket bullet must have every finding of both
# shapes counted (Codex round-1-review defect #3: bracket parsing used to be
# gated behind "zero FINDING: lines", so a mixed report lost the bracket one).
# ===========================================================================
MIXED_FIXTURE="${SCRIPT_DIR}/fixtures/review-gate-codex-flat-list/review-codex-mixed.md"
[[ -s "$MIXED_FIXTURE" ]] || fail "mixed fixture missing: $MIXED_FIXTURE"
s3_root="$(make_plain_root s3)"
s3_handoff="${SUITE_TMP}/s3/handoff"
s3_diff="$(make_diff_file s3)"
s3_resolver="$(make_resolver_stub s3 sonnet "sonnet:ok:")"
s3_arch="$(make_flat_list_arch_stub s3 "$MIXED_FIXTURE")"
s3_rc="$(run_review "$s3_root" "s3" "$s3_handoff" "$s3_diff" "$s3_resolver" kimi \
  LEADV2_DISPATCH_ARCHITECT_BIN="$s3_arch")"
s3_gate="${s3_handoff}/review-gate.md"
if [[ "$s3_rc" == "7" ]] && grep -q '^findings_total: 2$' "$s3_gate" 2>/dev/null && grep -q '^high: 2$' "$s3_gate" 2>/dev/null; then
  pass "S3: mixed report (FINDING: line + bracket bullet) counts BOTH findings (findings_total=2)"
else
  fail "S3: mixed report lost a finding -- rc=${s3_rc} gate=$(cat "$s3_gate" 2>/dev/null || echo MISSING)"
fi

# ===========================================================================
# Scenario 4 (round 2, unanchored multi) — several bracket findings of the
# SAME severity with NO trailing (path:line) anchor must not collapse into
# one dedup row (Codex round-1-review defect #2).
# ===========================================================================
UNANCHORED_FIXTURE="${SCRIPT_DIR}/fixtures/review-gate-codex-flat-list/review-codex-unanchored.md"
[[ -s "$UNANCHORED_FIXTURE" ]] || fail "unanchored fixture missing: $UNANCHORED_FIXTURE"
s4_root="$(make_plain_root s4)"
s4_handoff="${SUITE_TMP}/s4/handoff"
s4_diff="$(make_diff_file s4)"
s4_resolver="$(make_resolver_stub s4 sonnet "sonnet:ok:")"
s4_arch="$(make_flat_list_arch_stub s4 "$UNANCHORED_FIXTURE")"
s4_rc="$(run_review "$s4_root" "s4" "$s4_handoff" "$s4_diff" "$s4_resolver" kimi \
  LEADV2_DISPATCH_ARCHITECT_BIN="$s4_arch")"
s4_gate="${s4_handoff}/review-gate.md"
if [[ "$s4_rc" == "7" ]] && grep -q '^findings_total: 3$' "$s4_gate" 2>/dev/null && grep -q '^high: 3$' "$s4_gate" 2>/dev/null; then
  pass "S4: 3 unanchored same-severity bracket findings all survive dedup (findings_total=3)"
else
  fail "S4: unanchored findings collapsed during dedup -- rc=${s4_rc} gate=$(cat "$s4_gate" 2>/dev/null || echo MISSING)"
fi

# ===========================================================================
# Scenario 5 (round 2, real specimen) — the acceptance fixture named in the
# task: Codex's own adversarial review of round 1's fix
# (docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/review-codex.md, copied
# verbatim), which itself carries 3 anchored [high] bracket findings. The
# gate must report findings_total=3, never findings_lost.
# ===========================================================================
ROUND2_FIXTURE="${SCRIPT_DIR}/fixtures/review-gate-codex-flat-list/review-codex-round2-specimen.md"
[[ -s "$ROUND2_FIXTURE" ]] || fail "round-2 specimen fixture missing: $ROUND2_FIXTURE"
EXPECTED_R2_HIGH="$(grep -c '\[high\]' "$ROUND2_FIXTURE" 2>/dev/null | tr -d '[:space:]')"
s5_root="$(make_plain_root s5)"
s5_handoff="${SUITE_TMP}/s5/handoff"
# The real specimen declares BOTH REVIEW_CODE_VERDICT and REVIEW_MISSION_VERDICT
# (it was produced against a real mission snapshot) -- parse_review_verdict
# requires a mission snapshot to be available for that dual-dimension shape to
# parse, so give it one (matches how it was actually produced: a lane-mission.md
# sits next to review-codex.md under this task's own HANDOFF).
mkdir -p "$s5_handoff"
printf '# mission\nRound-2 specimen mission snapshot for S5.\n' > "${s5_handoff}/lane-mission.md"
s5_diff="$(make_diff_file s5)"
s5_resolver="$(make_resolver_stub s5 sonnet "sonnet:ok:")"
s5_arch="$(make_flat_list_arch_stub s5 "$ROUND2_FIXTURE")"
s5_rc="$(run_review "$s5_root" "s5" "$s5_handoff" "$s5_diff" "$s5_resolver" kimi \
  LEADV2_DISPATCH_ARCHITECT_BIN="$s5_arch")"
s5_gate="${s5_handoff}/review-gate.md"
if grep -q '^reason: findings_lost$' "$s5_gate" 2>/dev/null; then
  fail "S5: the real round-2 specimen STILL reports findings_lost -- rc=${s5_rc} gate=$(cat "$s5_gate" 2>/dev/null || echo MISSING)"
else
  pass "S5: the real round-2 specimen no longer reports findings_lost"
fi
if [[ "$s5_rc" == "7" ]] && grep -q "^findings_total: ${EXPECTED_R2_HIGH}\$" "$s5_gate" 2>/dev/null; then
  pass "S5: gate's findings_total (${EXPECTED_R2_HIGH}) equals the real specimen's bracketed [high] finding count"
else
  fail "S5: findings_total mismatch for the real specimen -- expected ${EXPECTED_R2_HIGH}, gate=$(cat "$s5_gate" 2>/dev/null || echo MISSING)"
fi

# ===========================================================================
# Negative controls (mutation, one per independent fix): each of the three
# defects Codex's own review found in round 1 is reverted ALONE inside a
# scratch copy of the engine, re-run against the scenario that exercises it,
# and must go RED -- one mutation is not a control for three independent
# defects.
# ===========================================================================
# run_mutation <label> <python-patch-file> <fixture> <task> -- sets globals
# MUT_RC / MUT_GATE (never a command-substitution return: pass()/fail() write
# to stdout, and capturing this function's stdout would swallow those log
# lines into the data channel instead of the terminal / PASS/FAIL counters).
MUT_RC=""; MUT_GATE=""
run_mutation() {
  local label="$1" patch="$2" fixture="$3" task="$4"
  local engine_scratch="${SUITE_TMP}/leadv2-review-run.mutated-${task}.sh"
  MUT_RC=""; MUT_GATE=""
  cp "$ENGINE" "$engine_scratch"
  if ! python3 "$patch" "$engine_scratch"; then
    fail "MUTATION ${label}: python patch failed to apply"
    rm -f "$engine_scratch"
    return
  fi
  if bash -n "$engine_scratch"; then
    pass "MUTATION ${label}: scratch engine still bash -n clean after the revert"
  else
    fail "MUTATION ${label}: scratch engine failed bash -n after edit"
  fi
  local m_root m_handoff m_diff m_resolver m_arch
  m_root="$(make_plain_root "$task")"
  m_handoff="${SUITE_TMP}/${task}/handoff"
  m_diff="$(make_diff_file "$task")"
  m_resolver="$(make_resolver_stub "$task" sonnet "sonnet:ok:")"
  m_arch="$(make_flat_list_arch_stub "$task" "$fixture")"
  MUT_RC="$(run_review_with_engine "$engine_scratch" "$m_root" "$task" "$m_handoff" "$m_diff" "$m_resolver" kimi \
    LEADV2_DISPATCH_ARCHITECT_BIN="$m_arch")"
  MUT_GATE="$(cat "${m_handoff}/review-gate.md" 2>/dev/null || echo MISSING)"
  rm -f "$engine_scratch"
}

# Mutation 1 (bug #1): revert the findings_total print back to the round-1
# shape (per-severity fields only, no findings_total) -- S1 must go RED.
cat > "${SUITE_TMP}/mutate1.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
marker = "    printf 'status: fail\\nfindings_total: %s\\ncritical: %s\\nhigh: %s\\nmedium: %s\\nlow: %s\\n' \\\n      \"${FINDINGS_TOTAL_ALL}\" \"${FINDINGS_CRITICAL_TOTAL}\" \"${FINDINGS_HIGH_TOTAL}\" \"${FINDINGS_MEDIUM_TOTAL}\" \"${FINDINGS_LOW_TOTAL}\""
assert s.count(marker) == 1, f"marker1 occurrences: {s.count(marker)}"
replacement = "    printf 'status: fail\\ncritical: %s\\nhigh: %s\\nmedium: %s\\nlow: %s\\n' \\\n      \"${FINDINGS_CRITICAL_TOTAL}\" \"${FINDINGS_HIGH_TOTAL}\" \"${FINDINGS_MEDIUM_TOTAL}\" \"${FINDINGS_LOW_TOTAL}\""
s = s.replace(marker, replacement, 1)
open(p, "w", encoding="utf-8").write(s)
PY
run_mutation "1-findings_total-absent" "${SUITE_TMP}/mutate1.py" "$FIXTURE" mut1
if ! printf '%s' "$MUT_GATE" | grep -q 'findings_total:'; then
  pass "MUTATION 1 RED: with findings_total reverted out, the normal fail gate omits it again"
else
  fail "MUTATION 1 RED FAILED: findings_total still present after reverting the fix -- rc=${MUT_RC} gate=${MUT_GATE}"
fi

# Mutation 2 (bug #2): revert the dedup key to the round-1 shape (no
# description fallback for unanchored rows) -- S4 must collapse back to 1.
cat > "${SUITE_TMP}/mutate2.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
marker = """awk -F'\\t' '{key=$3"|"$4"|"$2"|"$5; if ($3 == "" && $4 == "") { key = key "|" $6 }; if (!(key in seen)) {seen[key]=1; print}}' "${FINDINGS_RAW}" > "${FINDINGS_DEDUP}" 2>/dev/null || : > "${FINDINGS_DEDUP}\""""
assert s.count(marker) == 1, f"marker2 occurrences: {s.count(marker)}"
replacement = """awk -F'\\t' '{key=$3"|"$4"|"$2"|"$5; if (!(key in seen)) {seen[key]=1; print}}' "${FINDINGS_RAW}" > "${FINDINGS_DEDUP}" 2>/dev/null || : > "${FINDINGS_DEDUP}\""""
s = s.replace(marker, replacement, 1)
open(p, "w", encoding="utf-8").write(s)
PY
run_mutation "2-unanchored-dedup-collapse" "${SUITE_TMP}/mutate2.py" "$UNANCHORED_FIXTURE" mut2
if printf '%s' "$MUT_GATE" | grep -q '^findings_total: 1$'; then
  pass "MUTATION 2 RED: with the dedup fix reverted, 3 unanchored findings collapse back to 1"
else
  fail "MUTATION 2 RED FAILED: expected findings_total: 1 after reverting the dedup fix -- rc=${MUT_RC} gate=${MUT_GATE}"
fi

# Mutation 3 (bug #3): re-gate the bracket-list branch behind "no FINDING:
# lines present" (the round-1 shape) -- S3's mixed report must lose its
# bracket finding again.
cat > "${SUITE_TMP}/mutate3.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
open_marker = '  { grep -E \'^[[:space:]]*-[[:space:]]*\\[[A-Za-z]+\\]\' "${_file}" 2>/dev/null || :; } | while IFS= read -r _line; do\n'
assert s.count(open_marker) == 1, f"open marker occurrences: {s.count(open_marker)}"
s = s.replace(open_marker, "  if ! grep -qE '^FINDING:' \"${_file}\" 2>/dev/null; then\n" + open_marker, 1)
close_marker = "    printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \"${_arm}\" \"${_sev}\" \"${_f}\" \"${_ln}\" \"${_dim}\" \"${_desc}\" >> \"${FINDINGS_RAW}\"\n  done\ndone\n{ grep -E '^FINDING:' \"${HACKDETECT_OUT}\""
assert s.count(close_marker) == 1, f"close marker occurrences: {s.count(close_marker)}"
s = s.replace(close_marker, close_marker.replace("  done\ndone", "  done\n  fi\ndone", 1), 1)
open(p, "w", encoding="utf-8").write(s)
PY
run_mutation "3-mixed-shape-suppressed" "${SUITE_TMP}/mutate3.py" "$MIXED_FIXTURE" mut3
if printf '%s' "$MUT_GATE" | grep -q '^findings_total: 1$'; then
  pass "MUTATION 3 RED: with bracket-parsing re-gated behind FINDING:-line presence, the mixed report loses its bracket finding again"
else
  fail "MUTATION 3 RED FAILED: expected findings_total: 1 after re-gating bracket parsing -- rc=${MUT_RC} gate=${MUT_GATE}"
fi

echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
