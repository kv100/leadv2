#!/usr/bin/env bash
# test-phase-gate-inversion.sh — real dispatch-path regression for
# PHASE-GATE-IS-INVERTED-01. All stores and launchers are fixtures.
set -uo pipefail

export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_RECORD="${SCRIPT_DIR}/../leadv2-phase-record.sh"
DISPATCH_BIN="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"

TMP_ROOT="$(mktemp -d /tmp/leadv2-phase-gate-XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

REPO="${TMP_ROOT}/repo"
CACHE="${TMP_ROOT}/cache"
RUNS="${TMP_ROOT}/runs"
JOURNAL_LOG="${TMP_ROOT}/journal.log"
JOURNAL_BIN="${TMP_ROOT}/journal.sh"
GLM_BIN="${TMP_ROOT}/glm.sh"

mkdir -p "$REPO" "$RUNS"
(
  cd "$REPO" || exit 1
  git init -q -b main
  git config user.email test@example.invalid
  git config user.name test
  printf 'seed\n' > .gitignore
  git add .gitignore
  git commit -qm seed
)

cat > "$JOURNAL_BIN" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${LEADV2_TEST_JOURNAL_LOG}"
EOF
chmod +x "$JOURNAL_BIN"

cat > "$GLM_BIN" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  bg)
    mkdir -p "${LEADV2_TEST_RUNS}"
    handle="fixture-${$}"
    : > "${LEADV2_TEST_RUNS}/${handle}"
    printf '%s\n' "$handle"
    ;;
  status)
    [[ -f "${LEADV2_TEST_RUNS}/${2:-}" ]]
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$GLM_BIN"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

setup_case() {
  rm -rf "$RUNS"
  mkdir -p "$RUNS"
  : > "$JOURNAL_LOG"
  export CLAUDE_PROJECT_DIR="$REPO"
  export LEADV2_PROJECT_ROOT="$REPO"
  export LEADV2_DISPATCH_CACHE_DIR="$CACHE"
  export LEADV2_JOURNAL_BIN="$JOURNAL_BIN"
  export LEADV2_TEST_JOURNAL_LOG="$JOURNAL_LOG"
  export LEADV2_TEST_RUNS="$RUNS"
  export LEADV2_DISPATCH_GLM_BIN="$GLM_BIN"
  export LEADV2_DISPATCH_E2E_GATE=0
  export LEADV2_DISPATCH_REVIEW_GATE=0
  export LEADV2_DISPATCH_PENDING_TTL_S=5
  export LEADV2_DISPATCH_CONFIRMED_TTL_S=10
  export LEADV2_LANE_SHAPE=off
  export LEADV2_ROUTER_V2=0
  export GLM_POLICY_RESOLVER=""
  export LEADV2_REQUIRE_PHASES=1
}

mission_sig8() {
  printf '%s' "$1" | tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' \
    | shasum -a 256 | awk '{print substr($1, 1, 8)}'
}

run_dispatch() {
  local mission="$1"
  bash "$DISPATCH_BIN" --kind tooling --task-class standard "$mission" 2>&1
}

record_approved_phases() {
  local sig8="$1" task="$2" brief="docs/handoff/${task}/brief.md"
  mkdir -p "${REPO}/docs/handoff/${task}"
  printf '# %s\n\nfixture plan\n' "$task" > "${REPO}/${brief}"
  LEADV2_PROJECT_ROOT="$REPO" bash "$PHASE_RECORD" record "$sig8" plan --status done \
    --artifact "$brief" --owner fixture >/dev/null
  LEADV2_PROJECT_ROOT="$REPO" bash "$PHASE_RECORD" record "$sig8" gate1 --status done \
    --reason 'fixture gate approval' --owner fixture >/dev/null
}

printf 'test: 1 new Standard dispatch without plan/gate1 is refused before spawn\n'
setup_case
MISSION_1='PGI-1 fixture Standard lane writes production code'
SIG_1="$(mission_sig8 "$MISSION_1")"
OUT_1="$(run_dispatch "$MISSION_1")"; RC_1=$?
if [[ $RC_1 -eq 3 ]]; then ok; else fail "new Standard dispatch should exit 3 (got $RC_1, out=$OUT_1)"; fi
if [[ -z "$(find "$RUNS" -type f -print -quit)" ]]; then ok; else fail 'refused dispatch spawned a fixture worker'; fi
if printf '%s' "$OUT_1" | grep -q 'missing=.*plan' && printf '%s' "$OUT_1" | grep -q 'missing=.*gate1'; then
  ok
else
  fail "refusal should identify plan and gate1 (out=$OUT_1)"
fi

printf 'test: 2 approved new Standard dispatch is admitted\n'
setup_case
MISSION_2='PGI-2 fixture approved Standard lane writes production code'
SIG_2="$(mission_sig8 "$MISSION_2")"
record_approved_phases "$SIG_2" TASK-PGI-2
OUT_2="$(run_dispatch "$MISSION_2")"; RC_2=$?
if [[ $RC_2 -eq 0 ]]; then ok; else fail "approved Standard dispatch should exit 0 (got $RC_2, out=$OUT_2)"; fi
if [[ -n "$(find "$RUNS" -type f -print -quit)" ]]; then ok; else fail 'approved dispatch did not spawn fixture worker'; fi

printf 'test: 3 resumed approved Standard lane is admitted\n'
setup_case
MISSION_3='PGI-3 fixture resumed Standard lane writes production code'
SIG_3="$(mission_sig8 "$MISSION_3")"
record_approved_phases "$SIG_3" TASK-PGI-3
OUT_3="$(run_dispatch "$MISSION_3")"; RC_3=$?
if [[ $RC_3 -eq 0 ]]; then ok; else fail "resumed approved dispatch should exit 0 (got $RC_3, out=$OUT_3)"; fi

printf 'test: 4 caller bootstrap claim cannot override recorded store history\n'
setup_case
SIG_4='claim001'
LEADV2_PROJECT_ROOT="$REPO" bash "$PHASE_RECORD" record "$SIG_4" classify --status done --owner fixture >/dev/null
OUT_4="$(LEADV2_PROJECT_ROOT="$REPO" bash "$PHASE_RECORD" assert "$SIG_4" --class Standard --pre-build --at-bootstrap 2>&1)"; RC_4=$?
if [[ $RC_4 -eq 3 ]]; then ok; else fail "caller bootstrap claim should be ignored (got $RC_4, out=$OUT_4)"; fi

printf 'test: 5 project-root mismatch fails loudly and leaves dispatcher store unchanged\n'
setup_case
SIG_5='root0001'
MISMATCH_ROOT="${TMP_ROOT}/other-root"
mkdir -p "$MISMATCH_ROOT"
OUT_5="$(PROJECT_ROOT="$MISMATCH_ROOT" LEADV2_PROJECT_ROOT="$REPO" bash "$PHASE_RECORD" record "$SIG_5" classify --status done --owner fixture 2>&1)"; RC_5=$?
if [[ $RC_5 -ne 0 ]]; then ok; else fail "mismatched roots should fail (out=$OUT_5)"; fi
if [[ ! -f "${REPO}/docs/handoff/dispatch-${SIG_5}/phases.d/classify.yaml" ]]; then ok; else fail 'mismatched write appeared in dispatcher phase store'; fi

printf '\n[PHASE-GATE-INVERSION] pass=%d fail=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
