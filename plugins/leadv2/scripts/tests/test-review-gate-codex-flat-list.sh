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
# Negative control (mutation): disable the new bracket-list branch inside a
# scratch copy of the engine and prove S1 goes RED, then restore.
# ===========================================================================
ENGINE_SCRATCH="${SUITE_TMP}/leadv2-review-run.mutated.sh"
cp "$ENGINE" "$ENGINE_SCRATCH"
python3 - "$ENGINE_SCRATCH" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
marker = "if ! grep -qE '^FINDING:' \"${_file}\" 2>/dev/null; then"
assert s.count(marker) == 1, f"expected exactly 1 occurrence, found {s.count(marker)}"
s = s.replace(marker, "if false; then", 1)
open(p, "w", encoding="utf-8").write(s)
PY
if bash -n "$ENGINE_SCRATCH"; then
  pass "MUTATION: scratch engine still bash -n clean after neutering the bracket-list branch"
else
  fail "MUTATION: scratch engine failed bash -n after edit"
fi
sm_root="$(make_plain_root sm)"
sm_handoff="${SUITE_TMP}/sm/handoff"
sm_diff="$(make_diff_file sm)"
sm_resolver="$(make_resolver_stub sm sonnet "sonnet:ok:")"
sm_arch="$(make_flat_list_arch_stub sm "$FIXTURE")"
sm_rc="$(run_review_with_engine "$ENGINE_SCRATCH" "$sm_root" "sm" "$sm_handoff" "$sm_diff" "$sm_resolver" kimi \
  LEADV2_DISPATCH_ARCHITECT_BIN="$sm_arch")"
sm_gate="${sm_handoff}/review-gate.md"
if [[ "$sm_rc" == "6" ]] && grep -q '^reason: findings_lost$' "$sm_gate" 2>/dev/null; then
  pass "MUTATION RED: with the bracket-list branch neutered, the real specimen (mis)reports findings_lost again"
else
  fail "MUTATION RED FAILED: expected findings_lost with the fix disabled -- rc=${sm_rc} gate=$(cat "$sm_gate" 2>/dev/null || echo MISSING)"
fi
rm -f "$ENGINE_SCRATCH"

echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
