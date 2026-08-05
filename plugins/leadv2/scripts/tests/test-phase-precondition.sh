#!/usr/bin/env bash
# test-phase-precondition.sh — guard matrix for _phase_precondition_guard
# PHASES-ARE-THE-ONLY-PATH-01 §11 test suite 2.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PHASE_RECORD="${SCRIPT_DIR}/../leadv2-phase-record.sh"
DISPATCH_BIN="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export LEADV2_PROJECT_ROOT="$TMP_ROOT"
export LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/.cache"
export LEADV2_JOURNAL_BIN="${TMP_ROOT}/journal.sh"

# Stub journal that records lines to a file
JOURNAL_LOG="${TMP_ROOT}/journal.log"
cat > "${LEADV2_JOURNAL_BIN}" <<'JEOF'
#!/usr/bin/env bash
echo "$@" >> "${LEADV2_JOURNAL_LOG}" 2>/dev/null || true
JEOF
chmod +x "${LEADV2_JOURNAL_BIN}"
export LEADV2_JOURNAL_LOG

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1" >&2; }

# We test phase-record.sh assert directly (it's what the guard calls)

# ── Test 1: Standard, no plan/gate1 → missing=csv on stdout, exit 3 ───────────
printf 'test: Standard missing plan/gate1\n'
OUT="$(bash "$PHASE_RECORD" assert deadbeef --class Standard 2>/dev/null)"; rc=$?
if [[ $rc -eq 3 ]]; then
  ok
else
  fail "assert Standard should exit 3 (got $rc)"
fi
if printf '%s' "$OUT" | grep -q '^missing='; then
  ok
else
  fail "assert should print missing= csv"
fi
if printf '%s' "$OUT" | grep -q 'plan'; then
  ok
else
  fail "missing should include plan"
fi

# ── Test 2: --waiver review=anything → exit 4 ─────────────────────────────────
printf 'test: waiver review refused\n'
for cls in Trivial Light Standard Heavy; do
  bash "$PHASE_RECORD" assert test01 --class "$cls" --waiver "review=anything" 2>/dev/null; rc=$?
  if [[ $rc -eq 4 ]]; then
    ok
  else
    fail "review waiver should exit 4 for class=$cls (got $rc)"
  fi
done

# ── Test 3: --waiver close=anything → exit 4 ─────────────────────────────────
printf 'test: waiver close refused\n'
for cls in Trivial Light Standard Heavy; do
  bash "$PHASE_RECORD" assert test02 --class "$cls" --waiver "close=anything" 2>/dev/null; rc=$?
  if [[ $rc -eq 4 ]]; then
    ok
  else
    fail "close waiver should exit 4 for class=$cls (got $rc)"
  fi
done

# ── Test 4: --waiver plan= (empty reason) → exit 4 ───────────────────────────
printf 'test: waiver empty reason\n'
bash "$PHASE_RECORD" assert test03 --class Standard --waiver "plan=" 2>/dev/null; rc=$?
if [[ $rc -eq 4 ]]; then
  ok
else
  fail "empty reason waiver should exit 4 (got $rc)"
fi

# ── Test 5: phases.yaml with version: 2 → exit 4 ─────────────────────────────
printf 'test: phases.yaml version 2 rejected\n'
mkdir -p "${TMP_ROOT}/.claude/leadv2-overrides"
printf 'version: 2\n' > "${TMP_ROOT}/.claude/leadv2-overrides/phases.yaml"
bash "$PHASE_RECORD" assert test04 --class Standard 2>/dev/null; rc=$?
if [[ $rc -eq 4 ]]; then
  ok
else
  fail "version 2 should exit 4 (got $rc)"
fi

# ── Test 6: phases.yaml with class_overrides.Light.remove → exit 4 ────────────
printf 'test: phases.yaml removal key rejected\n'
cat > "${TMP_ROOT}/.claude/leadv2-overrides/phases.yaml" <<'YEOF'
version: 1
class_overrides:
  Light:
    remove:
      - review
YEOF
ERR="$(bash "$PHASE_RECORD" assert test05 --class Light 2>&1 1>/dev/null)"; rc=$?
if [[ $rc -eq 4 ]]; then
  ok
else
  fail "remove key should exit 4 (got $rc)"
fi
if printf '%s' "$ERR" | grep -q 'removals are not permitted'; then
  ok
else
  fail "error should name removals"
fi

# ── Test 7: phases.yaml with class_overrides.Light.mandatory: [e2e] → union ───
printf 'test: phases.yaml union adds e2e to Light\n'
cat > "${TMP_ROOT}/.claude/leadv2-overrides/phases.yaml" <<'YEOF'
version: 1
class_overrides:
  Light:
    mandatory:
      - e2e
YEOF
PLAN_OUT="$(bash "$PHASE_RECORD" plan-for --class Light 2>/dev/null)"
if printf '%s' "$PLAN_OUT" | grep -q 'MANDATORY.*e2e'; then
  ok
else
  fail "Light + override should make e2e mandatory"
fi

# ── Test 8: waiver plan accepted when in waivers_allowed ──────────────────────
printf 'test: waiver plan accepted\n'
cat > "${TMP_ROOT}/.claude/leadv2-overrides/phases.yaml" <<'YEOF'
version: 1
waivers_allowed:
  - plan
YEOF
bash "$PHASE_RECORD" assert w01 --class Standard --waiver "plan=no_prepass_needed" 2>/dev/null; rc=$?
if [[ $rc -eq 3 ]]; then
  # exit 3 is fine — plan is waived but gate1 still missing
  ok
else
  if [[ $rc -eq 0 ]]; then
    ok  # all satisfied somehow
  else
    fail "accepted waiver should not exit 4 (got $rc)"
  fi
fi
# Verify the waiver was recorded
if [[ -f "${TMP_ROOT}/docs/handoff/dispatch-w01/phases.d/plan.yaml" ]]; then
  if grep -q 'status: waived' "${TMP_ROOT}/docs/handoff/dispatch-w01/phases.d/plan.yaml" \
     && grep -q 'reason: no_prepass_needed' "${TMP_ROOT}/docs/handoff/dispatch-w01/phases.d/plan.yaml"; then
    ok
  else
    fail "waiver record missing fields"
  fi
else
  fail "waived plan.yaml not written"
fi

# ── Test 9: waiver plan NOT in waivers_allowed → exit 4 ───────────────────────
printf 'test: waiver plan not allowed\n'
rm -f "${TMP_ROOT}/.claude/leadv2-overrides/phases.yaml"
bash "$PHASE_RECORD" assert w02 --class Standard --waiver "plan=test" 2>/dev/null; rc=$?
if [[ $rc -eq 4 ]]; then
  ok
else
  fail "waiver not in waivers_allowed should exit 4 (got $rc)"
fi

# ── Test 10: no phases.yaml → base table, no crash ───────────────────────────
printf 'test: no phases.yaml → base table\n'
PLAN_OUT="$(bash "$PHASE_RECORD" plan-for --class Trivial 2>/dev/null)"; rc=$?
if [[ $rc -eq 0 ]]; then
  ok
else
  fail "plan-for Trivial should succeed without phases.yaml (got $rc)"
fi
if printf '%s' "$PLAN_OUT" | grep -q 'MANDATORY.*classify'; then
  ok
else
  fail "Trivial should have classify mandatory"
fi
if printf '%s' "$PLAN_OUT" | grep -q 'MANDATORY.*review'; then
  ok
else
  fail "Trivial should have review mandatory"
fi

# ════════════════════════════════════════════════════════════════════════════
# F3: End-to-end cmd_resolve coverage — drives dispatch-code.sh as subprocess
# Harness template: test-landed-at-spawn.sh
# ════════════════════════════════════════════════════════════════════════════

# Fresh sandbox for dispatch-level tests (the sandbox above uses a non-git
# TMP_ROOT which cannot support the git operations _verify_artifact now does).
E2E_SANDBOX="$(mktemp -d /tmp/leadv2-pc-e2e-XXXXXX)"

# Fixture git repo as LEADV2_PROJECT_ROOT
E2E_REPO="${E2E_SANDBOX}/repo"
mkdir -p "${E2E_REPO}"
( cd "${E2E_REPO}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )

E2E_CACHE="${E2E_SANDBOX}/cache"
E2E_STATE="${E2E_SANDBOX}/state"
E2E_STUB_RUNS="${E2E_SANDBOX}/glm-runs"

# Stub GLM binary: on `bg`, touch a sentinel and echo a handle
GLM_STUB="${E2E_SANDBOX}/glm-stub.sh"
cat > "${GLM_STUB}" <<'SH'
#!/usr/bin/env bash
RUNS="${LEADV2_STUB_GLM_RUNS:-/tmp/leadv2-stub-glm-runs}"
case "${1:-}" in
  bg)
    mkdir -p "$RUNS" 2>/dev/null
    handle="stub-run-$(date +%s)-$$"
    printf '%s' "$handle" > "$RUNS/$handle" 2>/dev/null
    printf '%s\n' "$handle"
    exit 0
    ;;
  status)
    [[ -n "${2:-}" && -f "$RUNS/$2" ]] && exit 0
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
SH
chmod +x "${GLM_STUB}"

# Journal stub: append all args to a log file
E2E_JOURNAL="${E2E_SANDBOX}/journal-stub.sh"
E2E_JOURNAL_LOG="${E2E_SANDBOX}/journal.log"
cat > "${E2E_JOURNAL}" <<'SH'
#!/usr/bin/env bash
echo "$@" >> "${E2E_JOURNAL_LOG}" 2>/dev/null || true
SH
chmod +x "${E2E_JOURNAL}"
export E2E_JOURNAL_LOG

# Per-case setup: resets journal log, sets common env
e2e_setup() {
  : > "${E2E_JOURNAL_LOG}"
  export LEADV2_PROJECT_ROOT="${E2E_REPO}"
  export CLAUDE_PROJECT_DIR="${E2E_REPO}"
  export LEADV2_DISPATCH_CACHE_DIR="${E2E_CACHE}"
  export LEADV2_STATE_BASE="${E2E_STATE}"
  export LEADV2_DISPATCH_GLM_BIN="${GLM_STUB}"
  export LEADV2_STUB_GLM_RUNS="${E2E_STUB_RUNS}"
  export LEADV2_JOURNAL_BIN="${E2E_JOURNAL}"
  export LEADV2_ROUTER_V2=0
  export GLM_POLICY_RESOLVER=""
  export LEADV2_LANE_SHAPE=off
  export LEADV2_DISPATCH_E2E_GATE=0
  export LEADV2_DISPATCH_REVIEW_GATE=0
  export LEADV2_DISPATCH_PENDING_TTL_S=5
  export LEADV2_DISPATCH_CONFIRMED_TTL_S=10
  unset LEADV2_REQUIRE_PHASES LEADV2_LANE_START_SHA 2>/dev/null || true
  mkdir -p "${E2E_STUB_RUNS}"
}

# Sentinel: at least one spawn file exists for this case
spawn_sentinel_exists() {
  [[ -d "${E2E_STUB_RUNS}" ]] && [[ -n "$(ls -A "${E2E_STUB_RUNS}" 2>/dev/null)" ]]
}

# ── G1: REQUIRE_PHASES unset → warn + spawn ─────────────────────────────────
printf '\ntest: G1 REQUIRE_PHASES unset warns and spawns\n'
e2e_setup
E2E_STUB_RUNS="${E2E_SANDBOX}/glm-runs-g1"
export LEADV2_STUB_GLM_RUNS="${E2E_STUB_RUNS}"
mkdir -p "${E2E_STUB_RUNS}"
MISSION_G1="PPC-G1: fix the integration test harness timeout"
SIG_G1="$(printf '%s' "${MISSION_G1}" | tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' | shasum -a 256 | awk '{print $1}')"
SIG8_G1="${SIG_G1:0:8}"
rc_g1=0
bash "$DISPATCH_BIN" --kind tooling "$MISSION_G1" >/dev/null 2>&1 || rc_g1=$?
if grep -q 'phase_precondition_warn' "${E2E_JOURNAL_LOG}" 2>/dev/null; then
  ok
else
  fail "G1: journal should contain phase_precondition_warn"
fi
if spawn_sentinel_exists; then
  ok
else
  fail "G1: spawn sentinel should exist (worker was spawned)"
fi

# ── G2: REQUIRE_PHASES=1 → refused, exit 3, no spawn ────────────────────────
printf 'test: G2 REQUIRE_PHASES=1 refuses and does not spawn\n'
e2e_setup
E2E_STUB_RUNS="${E2E_SANDBOX}/glm-runs-g2"
export LEADV2_STUB_GLM_RUNS="${E2E_STUB_RUNS}"
mkdir -p "${E2E_STUB_RUNS}"
export LEADV2_REQUIRE_PHASES=1
MISSION_G2="PPC-G2: fix the integration test harness failure"
rc_g2=0
bash "$DISPATCH_BIN" --kind tooling "$MISSION_G2" >/dev/null 2>&1 || rc_g2=$?
if [[ $rc_g2 -eq 3 ]]; then
  ok
else
  fail "G2: dispatch should exit 3 (got $rc_g2)"
fi
if ! spawn_sentinel_exists; then
  ok
else
  fail "G2: spawn sentinel should NOT exist"
fi
if grep -q 'phase_precondition_refused' "${E2E_JOURNAL_LOG}" 2>/dev/null; then
  ok
else
  fail "G2: journal should contain phase_precondition_refused"
fi

# ── G3: REQUIRE_PHASES=0 → no warn, spawn ───────────────────────────────────
printf 'test: G3 REQUIRE_PHASES=0 no warn and spawns\n'
e2e_setup
E2E_STUB_RUNS="${E2E_SANDBOX}/glm-runs-g3"
export LEADV2_STUB_GLM_RUNS="${E2E_STUB_RUNS}"
mkdir -p "${E2E_STUB_RUNS}"
export LEADV2_REQUIRE_PHASES=0
MISSION_G3="PPC-G3: fix the integration test harness signal"
rc_g3=0
bash "$DISPATCH_BIN" --kind tooling "$MISSION_G3" >/dev/null 2>&1 || rc_g3=$?
if ! grep -q 'phase_precondition_warn' "${E2E_JOURNAL_LOG}" 2>/dev/null; then
  ok
else
  fail "G3: journal should NOT contain phase_precondition_warn"
fi
if spawn_sentinel_exists; then
  ok
else
  fail "G3: spawn sentinel should exist"
fi

# ── G4: --phase-waiver review=x refused under unset / 1 (NOT 0) ──────────────
# B2: mode 0 is now a full kill switch — the guard returns before any subprocess,
# so the waiver is never processed and dispatch proceeds. G4 tests unset and 1 only.
printf 'test: G4 phase-waiver review refused in modes unset/1 (0 proceeds, see G8)\n'
for mode in unset 1; do
  e2e_setup
  E2E_STUB_RUNS="${E2E_SANDBOX}/glm-runs-g4-${mode}"
  export LEADV2_STUB_GLM_RUNS="${E2E_STUB_RUNS}"
  mkdir -p "${E2E_STUB_RUNS}"
  if [[ "$mode" == "1" ]]; then export LEADV2_REQUIRE_PHASES=1
  elif [[ "$mode" == "0" ]]; then export LEADV2_REQUIRE_PHASES=0
  else unset LEADV2_REQUIRE_PHASES; fi
  MISSION_G4="PPC-G4-${mode}: fix the integration test harness registry"
  rc_g4=0
  bash "$DISPATCH_BIN" --kind tooling --phase-waiver "review=x" "$MISSION_G4" >/dev/null 2>&1 || rc_g4=$?
  if [[ $rc_g4 -ne 0 ]]; then
    ok
  else
    fail "G4/$mode: waiver review should be refused (got rc=$rc_g4)"
  fi
done

# ── G5: forged review ledger (F1 regression guard) ──────────────────────────
printf 'test: G5 forged review diff_hash rejected\n'
# G5 tests phase-record.sh assert directly (about the proof, not the guard)
G5_SANDBOX="$(mktemp -d /tmp/leadv2-pc-g5-XXXXXX)"
G5_REPO="${G5_SANDBOX}/repo"
mkdir -p "${G5_REPO}"
( cd "${G5_REPO}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )

G5_CACHE="${G5_SANDBOX}/cache"
export LEADV2_PROJECT_ROOT="${G5_REPO}"
export LEADV2_DISPATCH_CACHE_DIR="${G5_CACHE}"
G5_SLUG="$(basename "${G5_REPO}" | tr -cd 'A-Za-z0-9._-')"
G5_LEDGER_DIR="${G5_CACHE}/code-review-ledger"
mkdir -p "$G5_LEDGER_DIR"

# Helper: set up a review phase record + review.diff for a given sig8
_g5_setup_review() {
  local sig8="$1"
  mkdir -p "${G5_REPO}/docs/handoff/dispatch-${sig8}"
  printf 'diff content for %s\n' "$sig8" > "${G5_REPO}/docs/handoff/dispatch-${sig8}/review.diff"
  mkdir -p "${G5_REPO}/docs/handoff/dispatch-${sig8}/phases.d"
  bash "$PHASE_RECORD" record "$sig8" review --status done \
    --artifact "docs/handoff/dispatch-${sig8}/review.diff" \
    --owner test >/dev/null 2>&1
}

# G5a: ledger row has a DIFFERENT diff_hash → review should be in missing
G5A_SIG8="f5dea001"
_g5_setup_review "$G5A_SIG8"
FORGED_HASH="$(printf '%064d' 1)"
printf '{"diff_hash":"%s","verdict":"PASS","reviewer":"test","run_id":"r1","repo":"%s","ts":"2026-01-01T00:00:00Z"}\n' \
  "$FORGED_HASH" "$G5_SLUG" > "${G5_LEDGER_DIR}/${G5_SLUG}.jsonl"
G5A_OUT="$(bash "$PHASE_RECORD" assert "$G5A_SIG8" --class Standard 2>/dev/null)"
if printf '%s' "$G5A_OUT" | grep -q 'missing=.*review'; then
  ok
else
  fail "G5a: forged review diff_hash should show review in missing= (got: $G5A_OUT)"
fi

# G5b: ledger row has MATCHING diff_hash but FAIL verdict → review should be in missing
G5B_SIG8="f5deb002"
_g5_setup_review "$G5B_SIG8"
G5B_REAL_HASH="$(shasum -a 256 "${G5_REPO}/docs/handoff/dispatch-${G5B_SIG8}/review.diff" | awk '{print $1}')"
printf '{"diff_hash":"%s","verdict":"FAIL","reviewer":"test","run_id":"r2","repo":"%s","ts":"2026-01-01T00:00:00Z"}\n' \
  "$G5B_REAL_HASH" "$G5_SLUG" > "${G5_LEDGER_DIR}/${G5_SLUG}.jsonl"
G5B_OUT="$(bash "$PHASE_RECORD" assert "$G5B_SIG8" --class Standard 2>/dev/null)"
if printf '%s' "$G5B_OUT" | grep -q 'missing=.*review'; then
  ok
else
  fail "G5b: FAIL verdict should show review in missing= (got: $G5B_OUT)"
fi

rm -rf "$G5_SANDBOX"

# ── G6: artifact integrity regression guards (F2) ───────────────────────────
printf 'test: G6 artifact integrity rejected\n'

# G6a: overwritten test artifact → test in missing
G6A_SANDBOX="$(mktemp -d /tmp/leadv2-pc-g6a-XXXXXX)"
G6A_REPO="${G6A_SANDBOX}/repo"
mkdir -p "${G6A_REPO}"
( cd "${G6A_REPO}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )
G6A_SIG8="g6bee01"
mkdir -p "${G6A_REPO}/docs/handoff/dispatch-${G6A_SIG8}/phases.d"
printf 'original content\n' > "${G6A_REPO}/test-artifact.txt"
LEADV2_PROJECT_ROOT="${G6A_REPO}" bash "$PHASE_RECORD" record "$G6A_SIG8" test --status done \
  --artifact "test-artifact.txt" --owner test >/dev/null 2>&1
printf 'GARBAGE OVERWRITE\n' > "${G6A_REPO}/test-artifact.txt"
G6A_OUT="$(cd "${G6A_REPO}" && LEADV2_PROJECT_ROOT="${G6A_REPO}" bash "$PHASE_RECORD" assert "$G6A_SIG8" --class Standard 2>/dev/null)"
if printf '%s' "$G6A_OUT" | grep -q 'missing=.*test'; then
  ok
else
  fail "G6a: overwritten test artifact should show test in missing= (got: $G6A_OUT)"
fi
rm -rf "$G6A_SANDBOX"

# G6b: overwritten build artifact → build in missing
G6B_SANDBOX="$(mktemp -d /tmp/leadv2-pc-g6b-XXXXXX)"
G6B_REPO="${G6B_SANDBOX}/repo"
mkdir -p "${G6B_REPO}"
( cd "${G6B_REPO}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )
G6B_SIG8="g6bee02"
mkdir -p "${G6B_REPO}/docs/handoff/dispatch-${G6B_SIG8}/phases.d"
printf 'build output original\n' > "${G6B_REPO}/build-out.txt"
LEADV2_PROJECT_ROOT="${G6B_REPO}" bash "$PHASE_RECORD" record "$G6B_SIG8" build --status done \
  --artifact "build-out.txt" --owner test >/dev/null 2>&1
printf 'TAMPERED BUILD\n' > "${G6B_REPO}/build-out.txt"
G6B_OUT="$(cd "${G6B_REPO}" && LEADV2_PROJECT_ROOT="${G6B_REPO}" bash "$PHASE_RECORD" assert "$G6B_SIG8" --class Standard 2>/dev/null)"
if printf '%s' "$G6B_OUT" | grep -q 'missing=.*build'; then
  ok
else
  fail "G6b: overwritten build artifact should show build in missing= (got: $G6B_OUT)"
fi
rm -rf "$G6B_SANDBOX"

# G6c: deploy with non-ancestor commit → deploy in missing
G6C_SANDBOX="$(mktemp -d /tmp/leadv2-pc-g6c-XXXXXX)"
G6C_REPO="${G6C_SANDBOX}/repo"
mkdir -p "${G6C_REPO}"
( cd "${G6C_REPO}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )
# Create a second commit so we have a non-ancestor SHA (a branch off main)
( cd "${G6C_REPO}" && git checkout -q -b side && printf 'side\n' > side.txt \
  && git add side.txt && git commit -qm side && git checkout -q main )
SIDE_SHA="$(cd "${G6C_REPO}" && git rev-parse side)"
G6C_SIG8="g6bee03"
mkdir -p "${G6C_REPO}/docs/handoff/dispatch-${G6C_SIG8}/phases.d"
printf 'deploy artifact\n' > "${G6C_REPO}/deploy-out.txt"
# Record deploy normally, then append a commit line to the yaml
LEADV2_PROJECT_ROOT="${G6C_REPO}" bash "$PHASE_RECORD" record "$G6C_SIG8" deploy --status done \
  --artifact "deploy-out.txt" --owner test >/dev/null 2>&1
# Append commit field manually (avoids using --commit which doesn't exist on 5ba7620)
printf 'commit: %s\n' "$SIDE_SHA" >> "${G6C_REPO}/docs/handoff/dispatch-${G6C_SIG8}/phases.d/deploy.yaml"
# Set up origin/main so the ancestor check can run
( cd "${G6C_REPO}" && git update-ref refs/remotes/origin/main HEAD )
G6C_OUT="$(cd "${G6C_REPO}" && LEADV2_PROJECT_ROOT="${G6C_REPO}" bash "$PHASE_RECORD" assert "$G6C_SIG8" --class Standard --writes "app.py" 2>/dev/null)"
if printf '%s' "$G6C_OUT" | grep -q 'missing=.*deploy'; then
  ok
else
  fail "G6c: deploy with non-ancestor commit should show deploy in missing= (got: $G6C_OUT)"
fi
rm -rf "$G6C_SANDBOX"

# ── G7: B1 review provenance (de-self-attestation) ─────────────────────────
printf 'test: G7 review provenance — de-self-attestation\n'
G7_SANDBOX="$(mktemp -d /tmp/leadv2-pc-g7-XXXXXX)"
G7_REPO="${G7_SANDBOX}/repo"
mkdir -p "${G7_REPO}"
( cd "${G7_REPO}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )
# Unset work-tree env so dispatch-code.sh's LEDGER_REPO_ROOT resolves to G7_REPO,
# not the caller session's worktree (different slug = different ledger file).
unset LEADV2_LANE_WORK_ROOT
G7_CACHE="${G7_SANDBOX}/cache"
G7_SLUG="$(basename "${G7_REPO}" | tr -cd 'A-Za-z0-9._-')"
G7_LEDGER_DIR="${G7_CACHE}/code-review-ledger"
G7_JOURNAL="${G7_SANDBOX}/journal.sh"
G7_JOURNAL_LOG="${G7_SANDBOX}/journal.log"
cat > "${G7_JOURNAL}" <<'SH'
#!/usr/bin/env bash
echo "$@" >> "${G7_JOURNAL_LOG}" 2>/dev/null || true
SH
chmod +x "${G7_JOURNAL}"
export G7_JOURNAL_LOG

_g7_setup_review() {
  local sig8="$1"
  mkdir -p "${G7_REPO}/docs/handoff/dispatch-${sig8}/phases.d"
  printf 'diff content for %s\n' "$sig8" > "${G7_REPO}/docs/handoff/dispatch-${sig8}/review.diff"
  LEADV2_PROJECT_ROOT="${G7_REPO}" LEADV2_DISPATCH_CACHE_DIR="${G7_CACHE}" \
    LEADV2_JOURNAL_BIN="${G7_JOURNAL}" \
    bash "$PHASE_RECORD" record "$sig8" review --status done \
      --artifact "docs/handoff/dispatch-${sig8}/review.diff" --owner test >/dev/null 2>&1
}

# G7a: correctly-hashed row, reviewer="self-forged", sidecar matches → review in missing
G7A_SIG8="g7dea01"
_g7_setup_review "$G7A_SIG8"
G7A_HASH="$(shasum -a 256 "${G7_REPO}/docs/handoff/dispatch-${G7A_SIG8}/review.diff" | awk '{print $1}')"
mkdir -p "$G7_LEDGER_DIR"
printf '{"diff_hash":"%s","verdict":"PASS","reviewer":"self-forged","run_id":"r1","repo":"%s","ts":"2026-01-01T00:00:00Z"}\n' \
  "$G7A_HASH" "$G7_SLUG" > "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl"
printf '1\n' > "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl.rows"
G7A_OUT="$(LEADV2_PROJECT_ROOT="${G7_REPO}" LEADV2_DISPATCH_CACHE_DIR="${G7_CACHE}" \
  LEADV2_JOURNAL_BIN="${G7_JOURNAL}" bash "$PHASE_RECORD" assert "$G7A_SIG8" --class Standard 2>/dev/null)"
if printf '%s' "$G7A_OUT" | grep -q 'missing=.*review'; then
  ok
else
  fail "G7a: self-forged reviewer should show review in missing= (got: $G7A_OUT)"
fi

# G7b: correctly-hashed PASS row, allowlisted "codex" reviewer, hand-appended (sidecar not incremented)
G7B_SIG8="g7deb02"
_g7_setup_review "$G7B_SIG8"
G7B_HASH="$(shasum -a 256 "${G7_REPO}/docs/handoff/dispatch-${G7B_SIG8}/review.diff" | awk '{print $1}')"
printf '{"diff_hash":"%s","verdict":"PASS","reviewer":"codex","run_id":"r2","repo":"%s","ts":"2026-01-01T00:00:00Z"}\n' \
  "$G7B_HASH" "$G7_SLUG" > "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl"
printf '0\n' > "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl.rows"
: > "${G7_JOURNAL_LOG}"
G7B_OUT="$(LEADV2_PROJECT_ROOT="${G7_REPO}" LEADV2_DISPATCH_CACHE_DIR="${G7_CACHE}" \
  LEADV2_JOURNAL_BIN="${G7_JOURNAL}" bash "$PHASE_RECORD" assert "$G7B_SIG8" --class Standard 2>/dev/null)"
if printf '%s' "$G7B_OUT" | grep -q 'missing=.*review'; then
  ok
else
  fail "G7b: hand-appended row (sidecar mismatch) should show review in missing= (got: $G7B_OUT)"
fi
if grep -q 'review_ledger_tamper' "${G7_JOURNAL_LOG}" 2>/dev/null; then
  ok
else
  fail "G7b: review_ledger_tamper should be journaled"
fi

# G7c: row written by real record-review path → review satisfied + sidecar matches
G7C_SIG8="g7dec03"
_g7_setup_review "$G7C_SIG8"
G7C_HASH="$(shasum -a 256 "${G7_REPO}/docs/handoff/dispatch-${G7C_SIG8}/review.diff" | awk '{print $1}')"
rm -f "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl" "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl.rows"
rc_g7c=0
( cd "${G7_REPO}" && env -u LEADV2_LANE_WORK_ROOT \
  LEADV2_PROJECT_ROOT="${G7_REPO}" LEADV2_DISPATCH_CACHE_DIR="${G7_CACHE}" \
  LEADV2_JOURNAL_BIN="${G7_JOURNAL}" bash "$DISPATCH_BIN" record-review \
  --diff-hash "$G7C_HASH" --verdict PASS --reviewer "codex:standard" --run-id "dispatch-test" ) >/dev/null 2>&1 || rc_g7c=$?
if [[ $rc_g7c -eq 0 ]]; then ok; else fail "G7c: record-review should succeed from main root (rc=$rc_g7c)"; fi
G7C_OUT="$(LEADV2_PROJECT_ROOT="${G7_REPO}" LEADV2_DISPATCH_CACHE_DIR="${G7_CACHE}" \
  LEADV2_JOURNAL_BIN="${G7_JOURNAL}" bash "$PHASE_RECORD" assert "$G7C_SIG8" --class Standard 2>/dev/null)"
if ! printf '%s' "$G7C_OUT" | grep -q 'missing=.*review'; then
  ok
else
  fail "G7c: legitimate record-review should satisfy review phase (got: $G7C_OUT)"
fi
G7C_ROWS="$(cat "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl.rows" 2>/dev/null | tr -d ' \n')"
G7C_LINES="$(wc -l < "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl" 2>/dev/null | tr -d ' ')"
if [[ "$G7C_ROWS" == "$G7C_LINES" && -n "$G7C_ROWS" ]]; then
  ok
else
  fail "G7c: sidecar rows ($G7C_ROWS) should equal ledger lines ($G7C_LINES)"
fi

# G7d: record-review from inside a linked worktree with the worktree's OWN diff hash
# → refused (self-attestation); recording a DIFFERENT diff from the same worktree is allowed.
G7D_SIG8="g7ded04"
_g7_setup_review "$G7D_SIG8"
G7D_OTHER_HASH="$(shasum -a 256 "${G7_REPO}/docs/handoff/dispatch-${G7D_SIG8}/review.diff" | awk '{print $1}')"
mkdir -p "${G7_REPO}/.claude/worktrees"
# Set origin/main so the guard's _pc_diff_base finds a valid merge-base.
( cd "${G7_REPO}" && git update-ref refs/remotes/origin/main HEAD \
  && git worktree add -q ".claude/worktrees/${G7D_SIG8}" -b "wt-${G7D_SIG8}" 2>/dev/null )
# Make a committed change inside the worktree so its diff is non-empty.
( cd "${G7_REPO}/.claude/worktrees/${G7D_SIG8}" \
  && mkdir -p src && printf 'changed\n' > src/file.txt && git add src/file.txt && git commit -qm 'worktree change' )
# Compute the worktree's own diff hash using the same scheme as the guard:
# never-smaller of (HEAD-diff, base-diff) with docs/leadv2+docs/handoff excluded.
G7D_BASE="$(cd "${G7_REPO}/.claude/worktrees/${G7D_SIG8}" && git merge-base origin/main HEAD)"
G7D_HEAD_DIFF="$(cd "${G7_REPO}/.claude/worktrees/${G7D_SIG8}" && git diff HEAD -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null || true)"
G7D_BASE_DIFF="$(cd "${G7_REPO}/.claude/worktrees/${G7D_SIG8}" && git diff "$G7D_BASE" -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null || true)"
if [[ ${#G7D_BASE_DIFF} -gt ${#G7D_HEAD_DIFF} ]]; then G7D_WT_DIFF="$G7D_BASE_DIFF"; else G7D_WT_DIFF="$G7D_HEAD_DIFF"; fi
G7D_HASH="$(printf '%s' "${G7D_WT_DIFF}" | shasum -a 256 | awk '{print $1}')"
G7D_LINES_BEFORE="$(wc -l < "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl" 2>/dev/null | tr -d ' ')"
# G7d-1: self-review (own diff hash) → refused
rc_g7d=0
( cd "${G7_REPO}/.claude/worktrees/${G7D_SIG8}" \
  && env -u LEADV2_LANE_WORK_ROOT \
  LEADV2_PROJECT_ROOT="${G7_REPO}" LEADV2_DISPATCH_CACHE_DIR="${G7_CACHE}" \
  LEADV2_JOURNAL_BIN="${G7_JOURNAL}" bash "$DISPATCH_BIN" record-review \
  --diff-hash "$G7D_HASH" --verdict PASS --reviewer "codex:standard" --run-id "dispatch-test" ) >/dev/null 2>&1 || rc_g7d=$?
if [[ $rc_g7d -ne 0 ]]; then ok; else fail "G7d: self-review from worktree should fail (rc=$rc_g7d)"; fi
G7D_LINES_AFTER="$(wc -l < "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl" 2>/dev/null | tr -d ' ')"
if [[ "$G7D_LINES_BEFORE" == "$G7D_LINES_AFTER" ]]; then
  ok
else
  fail "G7d: ledger line count should be unchanged (before=$G7D_LINES_BEFORE after=$G7D_LINES_AFTER)"
fi
# G7d-2: review of a DIFFERENT diff from the same worktree → allowed
rc_g7d2=0
( cd "${G7_REPO}/.claude/worktrees/${G7D_SIG8}" \
  && env -u LEADV2_LANE_WORK_ROOT \
  LEADV2_PROJECT_ROOT="${G7_REPO}" LEADV2_DISPATCH_CACHE_DIR="${G7_CACHE}" \
  LEADV2_JOURNAL_BIN="${G7_JOURNAL}" bash "$DISPATCH_BIN" record-review \
  --diff-hash "$G7D_OTHER_HASH" --verdict PASS --reviewer "codex:standard" --run-id "dispatch-test" ) >/dev/null 2>&1 || rc_g7d2=$?
if [[ $rc_g7d2 -eq 0 ]]; then ok; else fail "G7d-2: review of different diff from worktree should succeed (rc=$rc_g7d2)"; fi
( cd "${G7_REPO}" && git worktree remove -q ".claude/worktrees/${G7D_SIG8}" 2>/dev/null; git branch -q -D "wt-${G7D_SIG8}" 2>/dev/null; true )

# G7e: sidecar absent (legacy), correctly-hashed PASS row with "reviewer":"glm" → review satisfied
G7E_SIG8="g7dee05"
_g7_setup_review "$G7E_SIG8"
G7E_HASH="$(shasum -a 256 "${G7_REPO}/docs/handoff/dispatch-${G7E_SIG8}/review.diff" | awk '{print $1}')"
printf '{"diff_hash":"%s","verdict":"PASS","reviewer":"glm","run_id":"r5","repo":"%s","ts":"2026-01-01T00:00:00Z"}\n' \
  "$G7E_HASH" "$G7_SLUG" > "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl"
rm -f "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl.rows"
G7E_OUT="$(LEADV2_PROJECT_ROOT="${G7_REPO}" LEADV2_DISPATCH_CACHE_DIR="${G7_CACHE}" \
  LEADV2_JOURNAL_BIN="${G7_JOURNAL}" bash "$PHASE_RECORD" assert "$G7E_SIG8" --class Standard 2>/dev/null)"
if ! printf '%s' "$G7E_OUT" | grep -q 'missing=.*review'; then
  ok
else
  fail "G7e: legacy ledger (no sidecar) with valid glm row should pass (got: $G7E_OUT)"
fi

# G7f: malformed JSON line should not hide a good row later in the file
G7F_SIG8="g7def06"
_g7_setup_review "$G7F_SIG8"
G7F_HASH="$(shasum -a 256 "${G7_REPO}/docs/handoff/dispatch-${G7F_SIG8}/review.diff" | awk '{print $1}')"
printf 'this is not json\n' > "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl"
printf '{"diff_hash":"%s","verdict":"PASS","reviewer":"codex","run_id":"r6","repo":"%s","ts":"2026-01-01T00:00:00Z"}\n' \
  "$G7F_HASH" "$G7_SLUG" >> "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl"
printf '2\n' > "${G7_LEDGER_DIR}/${G7_SLUG}.jsonl.rows"
G7F_OUT="$(LEADV2_PROJECT_ROOT="${G7_REPO}" LEADV2_DISPATCH_CACHE_DIR="${G7_CACHE}" \
  LEADV2_JOURNAL_BIN="${G7_JOURNAL}" bash "$PHASE_RECORD" assert "$G7F_SIG8" --class Standard 2>/dev/null)"
if ! printf '%s' "$G7F_OUT" | grep -q 'missing=.*review'; then
  ok
else
  fail "G7f: malformed line should not hide valid row (got: $G7F_OUT)"
fi

rm -rf "$G7_SANDBOX"

# ── G8: B2 REQUIRE_PHASES=0 is a full disable (kill switch) ─────────────────
printf 'test: G8 REQUIRE_PHASES=0 proceeds despite broken phases.yaml + refused waiver\n'
e2e_setup
E2E_STUB_RUNS_G8="${E2E_SANDBOX}/glm-runs-g8"
export LEADV2_STUB_GLM_RUNS="${E2E_STUB_RUNS_G8}"
mkdir -p "${E2E_STUB_RUNS_G8}"
export LEADV2_REQUIRE_PHASES=0
# Create a phases.yaml with a removal key (guaranteed rc-4 producer)
mkdir -p "${E2E_REPO}/.claude/leadv2-overrides"
cat > "${E2E_REPO}/.claude/leadv2-overrides/phases.yaml" <<'YEOF'
version: 1
class_overrides:
  Standard:
    remove: [review]
YEOF
MISSION_G8="PPC-G8: fix the integration test harness timeout"
rc_g8=0
bash "$DISPATCH_BIN" --kind tooling --phase-waiver "review=whatever" "$MISSION_G8" >/dev/null 2>&1 || rc_g8=$?
# With B2: mode 0 returns immediately, never processes the config error or waiver
if ! grep -q 'phase_precondition_' "${E2E_JOURNAL_LOG}" 2>/dev/null; then
  ok
else
  fail "G8: journal should contain NO phase_precondition_* event with mode=0"
fi
if [[ -n "$(ls -A "${E2E_STUB_RUNS_G8}" 2>/dev/null)" ]]; then
  ok
else
  fail "G8: spawn sentinel should exist (worker was spawned despite broken config)"
fi
# Cleanup
rm -f "${E2E_REPO}/.claude/leadv2-overrides/phases.yaml"

# ── G9: deploy ancestor positive-pass test (§4 non-blocking, DO) ─────────────
printf 'test: G9 deploy ancestor positive-pass\n'
G9_SANDBOX="$(mktemp -d /tmp/leadv2-pc-g9-XXXXXX)"
G9_REPO="${G9_SANDBOX}/repo"
mkdir -p "${G9_REPO}"
( cd "${G9_REPO}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )
G9_SIG8="g9bee01"
mkdir -p "${G9_REPO}/docs/handoff/dispatch-${G9_SIG8}/phases.d"
printf 'deploy artifact\n' > "${G9_REPO}/deploy-out.txt"
LEADV2_PROJECT_ROOT="${G9_REPO}" bash "$PHASE_RECORD" record "$G9_SIG8" deploy --status done \
  --artifact "deploy-out.txt" --owner test >/dev/null 2>&1
# The recorded commit should be HEAD (ancestor of origin/main = HEAD → ancestor of itself)
G9_HEAD="$(cd "${G9_REPO}" && git rev-parse HEAD)"
printf 'commit: %s\n' "$G9_HEAD" >> "${G9_REPO}/docs/handoff/dispatch-${G9_SIG8}/phases.d/deploy.yaml"
( cd "${G9_REPO}" && git update-ref refs/remotes/origin/main HEAD )
G9_OUT="$(cd "${G9_REPO}" && LEADV2_PROJECT_ROOT="${G9_REPO}" bash "$PHASE_RECORD" assert "$G9_SIG8" --class Standard --writes "app.py" 2>/dev/null)"
if ! printf '%s' "$G9_OUT" | grep -q 'missing=.*deploy'; then
  ok
else
  fail "G9: deploy with ancestor commit should pass (got: $G9_OUT)"
fi
rm -rf "$G9_SANDBOX"

# ── G10: §3 honesty — PROOF column in show output ───────────────────────────
printf 'test: G10 PROOF column — self-attested vs verified\n'
G10_SANDBOX="$(mktemp -d /tmp/leadv2-pc-g10-XXXXXX)"
G10_REPO="${G10_SANDBOX}/repo"
mkdir -p "${G10_REPO}"
( cd "${G10_REPO}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )
G10_SIG8="g10be01"
mkdir -p "${G10_REPO}/docs/handoff/dispatch-${G10_SIG8}/phases.d"
printf 'review diff\n' > "${G10_REPO}/review.diff"
printf 'test artifact\n' > "${G10_REPO}/test-out.txt"
LEADV2_PROJECT_ROOT="${G10_REPO}" bash "$PHASE_RECORD" record "$G10_SIG8" review --status done \
  --artifact "review.diff" --owner test >/dev/null 2>&1
LEADV2_PROJECT_ROOT="${G10_REPO}" bash "$PHASE_RECORD" record "$G10_SIG8" test --status done \
  --artifact "test-out.txt" --owner test >/dev/null 2>&1
G10_SHOW="$(LEADV2_PROJECT_ROOT="${G10_REPO}" bash "$PHASE_RECORD" show "$G10_SIG8" 2>/dev/null)"
# Header should contain PROOF column
if printf '%s' "$G10_SHOW" | grep -q 'PROOF'; then ok; else fail "G10: show should have PROOF column"; fi
# test row should read self-attested
if printf '%s' "$G10_SHOW" | grep -E '^test\b' | grep -q 'self-attested'; then
  ok
else
  fail "G10: test phase should show self-attested (got: $G10_SHOW)"
fi
# review row should read verified
if printf '%s' "$G10_SHOW" | grep -E '^review\b' | grep -q 'verified'; then
  ok
else
  fail "G10: review phase should show verified (got: $G10_SHOW)"
fi
rm -rf "$G10_SANDBOX"

# Cleanup e2e sandbox
rm -rf "${E2E_SANDBOX}"

printf '\n[PHASE-PRECONDITION] pass=%d fail=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
