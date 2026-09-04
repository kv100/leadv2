#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# PHASE-GATE-IS-INVERTED-01: the inversion regression lives in its own suite
# and is exercised THROUGH the dispatcher, so both changed stems map to it.
# run-all-triggers: leadv2-dispatch-code leadv2-phase-record
# test-phase-gate-inversion.sh — PHASE-GATE-IS-INVERTED-01.
#
# Real dispatch-path regression for the inverted phase gate. The guard must be
# exercised THROUGH leadv2-dispatch-code.sh, the way production calls it —
# faee3fc5 shipped to main precisely because test-phase-precondition-bootstrap
# only ever tested the guard in isolation with a correctly-computed bootstrap
# answer. Cases:
#   1. a brand-new Standard lane with no plan/gate1 ⇒ dispatch REFUSED, no
#      worker spawned, refusal names plan AND gate1;
#   2. the same shape after plan+gate1 are recorded ⇒ admitted, worker spawned;
#   3. a resumed lane already carrying classify+plan+gate1 ⇒ admitted
#      (regression guard — this is what broke FORK-STORM);
#   4. a caller passing --at-bootstrap for a lane that HAS records ⇒ the claim
#      is ignored, the store wins; a zero-record lane is still admitted by the
#      guard's OWN store probe (the surviving, self-computed exemption);
#   5. PROJECT_ROOT vs LEADV2_PROJECT_ROOT conflict ⇒ loud failure, no silent
#      write into either store; PROJECT_ROOT alone is honoured as the store
#      root (the name an operator types must not resolve to a different store).
#
# Fixture repo + stub launcher binaries + fixture quota reader throughout
# (harness shape: test-effort-routing.sh). Never a live provider, never the
# real phase store, never the real state base. Bash 3.2 safe.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DC="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
PHASE_RECORD="${SCRIPTS_DIR}/leadv2-phase-record.sh"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"

TMP="$(mktemp -d /tmp/leadv2-phase-gate-XXXXXX)"
# `|| true`: the dispatcher arms leadv2-lane-pulse-watch.sh, a deliberately
# async watcher that can still be writing artifacts under "$TMP" when this
# suite exits; a racing rm must not turn a green run red (test-effort-routing
# measured this 2026-08-31). On failure the dir is KEPT and its path printed —
# a red run with no artifacts cannot be diagnosed.
cleanup() {
  if [[ ${FAIL:-1} -eq 0 ]]; then
    rm -rf "$TMP" 2>/dev/null || true
  else
    printf '[PHASE-GATE-INVERSION] artifacts kept at %s\n' "$TMP" >&2
  fi
}
trap cleanup EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

# ── fixtures ─────────────────────────────────────────────────────────────────
# Quota seam for the route arbiter: never read a live provider.
cat > "$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat > "$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"
quota_json() {
  python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}

# Every arm's launcher is a stub that records its own spawn into
# LEADV2_TEST_SPAWN_DIR — whichever arm the arbiter picks (and the fallback
# ladder walks), a "worker" appears only if the dispatcher genuinely got past
# the phase guard. Cover ALL four spawn paths, including freepool: an unstubbed
# arm is a real provider call.
mk_arm_stub() { # <name>
  # two statements: in one `local`, `$name` expands before it is assigned
  local name="$1"
  local stub="$TMP/stub-$name.sh"
  cat > "$stub" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  task|bg)
    mkdir -p "\${LEADV2_TEST_SPAWN_DIR}"
    printf '%s\n' "$name" >> "\${LEADV2_TEST_SPAWN_DIR}/spawned.txt"
    printf 'task-fixture-0001\n'
    exit 0 ;;
  status) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$stub"
  printf '%s' "$stub"
}
CODEX_STUB="$(mk_arm_stub codex)"
GLM_STUB="$(mk_arm_stub glm)"
SONNET_STUB="$(mk_arm_stub sonnet)"
FREEPOOL_STUB="$(mk_arm_stub freepool)"

mk_repo() { # <dir>
  mkdir -p "$1"
  (
    cd "$1" || exit 1
    git init -q -b main
    git config user.email test@example.invalid
    git config user.name test
    printf 'seed\n' > .gitignore
    git add .gitignore
    git commit -qm seed
  ) >/dev/null 2>&1
}

# dispatch <case-tag> <repo> <mission> — full real dispatch run from inside the
# fixture repo (cwd-derived root must equal the fixture, else the
# FOREIGN-PROJECT-ROOT-GUARD would override the env root and the lane would
# escape the fixture). Output → $TMP/<tag>.out, rc → stdout.
run_dispatch() {
  local tag="$1" repo="$2" mission="$3"
  (
    cd "$repo" || exit 111
    CLAUDE_PROJECT_ROOT="$repo" PROJECT_ROOT="$repo" LEADV2_PROJECT_ROOT="$repo" \
    LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-$tag" LEADV2_STATE_BASE="$TMP/state-$tag" \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_DISPATCH_PENDING_TTL_S=5 LEADV2_DISPATCH_CONFIRMED_TTL_S=10 \
    LEADV2_DISPATCH_CODEX_BIN="$CODEX_STUB" LEADV2_DISPATCH_GLM_BIN="$GLM_STUB" \
    LEADV2_DISPATCH_SUBSESSION_BIN="$SONNET_STUB" LEADV2_DISPATCH_FREEPOOL_BIN="$FREEPOOL_STUB" \
    LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/arb-$tag" \
    ROUTE_TEST_QUOTA="$(quota_json 1 1 1)" ROUTE_TEST_FREE_RC=1 \
    LEADV2_TEST_SPAWN_DIR="$TMP/spawn-$tag" \
    timeout 120 bash "$DC" "$mission" --kind code --task-class standard \
      --writes src/x.py >"$TMP/$tag.out" 2>&1
  )
  return $?
}

mission_sig8() {
  printf '%s' "$1" | tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' \
    | shasum -a 256 | awk '{print substr($1, 1, 8)}'
}

# record_lead_phases <repo> <sig8> [classify] — the lead-authored pre-spawn
# evidence path: a non-empty brief.md is attested plan proof, a recorded
# non-empty Gate-1 --reason is attested gate1 proof (leadv2-phase-record.sh
# _verify_artifact). `classify` additionally writes the record a prior,
# interrupted run of the lane would have left behind (resumed-lane shape).
record_lead_phases() {
  local repo="$1" sig8="$2" with_classify="${3:-}"
  local brief="docs/handoff/PGI-$sig8/brief.md"
  mkdir -p "$repo/docs/handoff/PGI-$sig8"
  printf '# PGI-%s\n\nfixture lead-authored plan\n' "$sig8" > "$repo/$brief"
  if [[ -n "$with_classify" ]]; then
    ( cd "$repo" && PROJECT_ROOT="$repo" LEADV2_PROJECT_ROOT="$repo" bash "$PHASE_RECORD" record "$sig8" classify \
        --status done --owner lead:fixture ) >/dev/null 2>&1
  fi
  ( cd "$repo" && PROJECT_ROOT="$repo" LEADV2_PROJECT_ROOT="$repo" bash "$PHASE_RECORD" record "$sig8" plan \
      --status done --artifact "$brief" --owner lead:fixture ) >/dev/null 2>&1
  ( cd "$repo" && PROJECT_ROOT="$repo" LEADV2_PROJECT_ROOT="$repo" bash "$PHASE_RECORD" record "$sig8" gate1 \
      --status done --reason 'fixture Gate 1 decision' --owner lead:fixture ) >/dev/null 2>&1
  # --task-class is escalate-only: the admission estimator may map the mission
  # to Heavy, whose table also mandates diverge. Record it n/a so the case
  # under test is exactly plan+gate1, not the class table.
  ( cd "$repo" && PROJECT_ROOT="$repo" LEADV2_PROJECT_ROOT="$repo" bash "$PHASE_RECORD" record "$sig8" diverge \
      --status n/a --reason 'fixture: no diverge round for this lane' --owner lead:fixture ) >/dev/null 2>&1
}

# ── case 1: brand-new Standard lane, no plan/gate1 ⇒ refused before spawn ────
printf 'test: 1 new Standard dispatch without plan/gate1 is refused before spawn\n'
REPO1="$TMP/repo1"; mk_repo "$REPO1"
M1='PGI case1 fixture Standard lane writes production code'
run_dispatch c1 "$REPO1" "$M1"; RC1=$?
if [[ $RC1 -eq 3 ]]; then ok; else fail "case1: new Standard dispatch should exit 3 (got $RC1, out=$(tail -3 "$TMP/c1.out" 2>/dev/null | tr '\n' ' '))"; fi
if [[ ! -f "$TMP/spawn-c1/spawned.txt" ]]; then ok; else fail "case1: refused dispatch spawned a worker ($(cat "$TMP/spawn-c1/spawned.txt"))"; fi
if grep -q 'missing=.*plan' "$TMP/c1.out" && grep -q 'missing=.*gate1' "$TMP/c1.out"; then
  ok
else
  fail "case1: refusal should name plan and gate1 ($(grep 'missing=' "$TMP/c1.out" | tail -1))"
fi

# ── case 2: plan+gate1 recorded ⇒ admitted, worker spawned ───────────────────
printf 'test: 2 approved new Standard dispatch is admitted\n'
REPO2="$TMP/repo2"; mk_repo "$REPO2"
M2='PGI case2 fixture approved Standard lane writes production code'
S2="$(mission_sig8 "$M2")"
record_lead_phases "$REPO2" "$S2"
run_dispatch c2 "$REPO2" "$M2"; RC2=$?
if [[ $RC2 -eq 0 ]]; then ok; else fail "case2: approved Standard dispatch should exit 0 (got $RC2, out=$(tail -3 "$TMP/c2.out" 2>/dev/null | tr '\n' ' '))"; fi
if [[ -f "$TMP/spawn-c2/spawned.txt" ]]; then ok; else fail 'case2: approved dispatch spawned no worker'; fi

# ── case 3: resumed lane carrying classify+plan+gate1 ⇒ admitted ─────────────
printf 'test: 3 resumed approved Standard lane is admitted\n'
REPO3="$TMP/repo3"; mk_repo "$REPO3"
M3='PGI case3 fixture resumed Standard lane writes production code'
S3="$(mission_sig8 "$M3")"
record_lead_phases "$REPO3" "$S3" classify
run_dispatch c3 "$REPO3" "$M3"; RC3=$?
if [[ $RC3 -eq 0 ]]; then ok; else fail "case3: resumed approved dispatch should exit 0 (got $RC3, out=$(tail -3 "$TMP/c3.out" 2>/dev/null | tr '\n' ' '))"; fi
if [[ -f "$TMP/spawn-c3/spawned.txt" ]]; then ok; else fail 'case3: resumed dispatch spawned no worker'; fi

# ── case 4: caller-attested --at-bootstrap is ignored; store decides ─────────
printf 'test: 4 caller bootstrap claim cannot override the recorded store\n'
REPO4="$TMP/repo4"; mk_repo "$REPO4"
S4="$(mission_sig8 'PGI case4 classify-only lane')"
( cd "$REPO4" && PROJECT_ROOT="$REPO4" LEADV2_PROJECT_ROOT="$REPO4" bash "$PHASE_RECORD" record "$S4" classify \
    --status done --owner lead:fixture ) >/dev/null 2>&1
OUT4="$( cd "$REPO4" && PROJECT_ROOT="$REPO4" LEADV2_PROJECT_ROOT="$REPO4" bash "$PHASE_RECORD" assert "$S4" \
    --class Standard --pre-build --at-bootstrap 2>&1 )"; RC4=$?
if [[ $RC4 -eq 3 && "$(printf '%s' "$OUT4" | grep -c 'missing=.*plan')" -gt 0 ]]; then
  ok
else
  fail "case4a: claim should be ignored, store should win (rc=$RC4 out=$OUT4)"
fi
S4Z="$(mission_sig8 'PGI case4 zero-record lane')"
OUT4Z="$( cd "$REPO4" && PROJECT_ROOT="$REPO4" LEADV2_PROJECT_ROOT="$REPO4" bash "$PHASE_RECORD" assert "$S4Z" \
    --class Standard --pre-build --at-bootstrap 2>&1 )"; RC4Z=$?
if [[ $RC4Z -eq 0 ]]; then ok; else fail "case4b: zero-record lane should still be admitted by the guard's own store probe (rc=$RC4Z out=$OUT4Z)"; fi

# ── case 5: root-name mismatch is loud, never a silent second store ──────────
printf 'test: 5 project-root mismatch fails loudly and PROJECT_ROOT alone is honoured\n'
REPO5="$TMP/repo5"; mk_repo "$REPO5"
OTHER="$TMP/other-root"; mkdir -p "$OTHER"
S5="$(mission_sig8 'PGI case5 root mismatch lane')"
OUT5="$( cd "$REPO5" && PROJECT_ROOT="$OTHER" LEADV2_PROJECT_ROOT="$REPO5" bash "$PHASE_RECORD" \
    record "$S5" classify --status done --owner lead:fixture 2>&1 )"; RC5=$?
if [[ $RC5 -ne 0 ]]; then ok; else fail "case5a: conflicting roots should fail loudly (out=$OUT5)"; fi
if [[ ! -f "$REPO5/docs/handoff/dispatch-$S5/phases.d/classify.yaml" ]]; then
  ok
else
  fail 'case5a: record landed in the dispatcher store despite the conflict'
fi
if [[ ! -f "$OTHER/docs/handoff/dispatch-$S5/phases.d/classify.yaml" ]]; then
  ok
else
  fail 'case5a: record landed in the conflicting store'
fi
S5B="$(mission_sig8 'PGI case5 plain PROJECT_ROOT lane')"
OUT5B="$( cd "$REPO5" && env -u LEADV2_PROJECT_ROOT PROJECT_ROOT="$REPO5" bash "$PHASE_RECORD" record "$S5B" classify \
    --status done --owner lead:fixture 2>&1 )"; RC5B=$?
if [[ $RC5B -eq 0 && -f "$REPO5/docs/handoff/dispatch-$S5B/phases.d/classify.yaml" ]]; then
  ok
else
  fail "case5b: PROJECT_ROOT alone must resolve the store (rc=$RC5B out=$OUT5B)"
fi

printf '\n[PHASE-GATE-INVERSION] pass=%d fail=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
