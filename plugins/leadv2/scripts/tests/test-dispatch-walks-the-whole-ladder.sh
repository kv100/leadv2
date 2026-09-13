#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code leadv2-phase-record leadv2-dispatch-product-close leadv2-phase8-close
# test-dispatch-walks-the-whole-ladder.sh — THE-LADDER-IS-DECLARED-AND-NEVER-WALKED-01
# (row fad342725656, round 1: RED suite).
#
# The defect: eight `--kind plugin` lanes reached terminal state having recorded
# only `classify` + `build running`. Three mechanisms let that happen:
#   (a) phase8-close records `close done` (or exits 0) for a lane whose ladder
#       stops at build — nothing asserts the LANE's phase store before close;
#   (b) the dispatcher launches the close gate only for product lanes
#       (dispatch-code.sh spawn tail) — non-product lanes land unreviewed by
#       structural exemption (`reason=non_product_class`);
#   (c) a hand-written `review done` from any shell is accepted — `owner:` is
#       caller-supplied text, never checked (phase-record.sh owner write/read).
#
# Round-1 contract: on the pre-fix tree cases 1a/1b/2/5 are RED; case 3 pins a
# refusal that already works (reviewer == author); case 4 pins acceptance that
# must stay. The salvage patch (round0-salvage.patch) + the bootstrap-admit
# sentinel fix turn 1a/1b/2/5 green.
#
# DECLARED NEGATIVE CONTROLS (round-0 prepass §4.5 list, kept):
#   M1: a $TMP copy of leadv2-phase-record.sh with the runner-token refusal
#       block deleted (post-patch only — pre-fix the block does not exist) must
#       redden case 2 (hand-written review accepted again).
#   M2: a $TMP copy of leadv2-phase8-close.sh with the ladder assert deleted
#       (post-patch only) must redden case 1a (partial ladder closes again).
#   Every mutation runs against a $TMP copy injected via env
#   (LEADV2_PHASE_RECORD_BIN / scratch bin) — the LIVE tree is never mutated,
#   and the EXIT trap below asserts the four live scripts' sha256 are unchanged
#   (ROUND0-SALVAGE: an 83-byte stub left in the live tree took every dispatch
#   down).
#
# Never a real lane, never the real dispatch ledger or state root.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE_DIR="${SCRIPT_DIR}/.."
PHASE_RECORD="${LIVE_DIR}/leadv2-phase-record.sh"
DC="${LIVE_DIR}/leadv2-dispatch-code.sh"
PC="${LIVE_DIR}/leadv2-dispatch-product-close.sh"
P8="${LIVE_DIR}/leadv2-phase8-close.sh"
ROUTING="${LIVE_DIR}/../config/leadv2-routing.yaml"
LANE_WT_BIN="${LIVE_DIR}/leadv2-lane-worktree.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-ladder.XXXXXX")"
trap '_live_guard; rm -rf "$TMP_ROOT"' EXIT

# ── live-tree guard: the four scripts this suite exercises must leave the
# live plugin tree byte-identical (negative controls mutate $TMP copies only).
_live_sums_file="${TMP_ROOT}/live.sums"
sha256sum() { shasum -a 256 "$@"; }
for _f in "${LIVE_DIR}/leadv2-phase-record.sh" "${LIVE_DIR}/leadv2-dispatch-code.sh" \
          "${LIVE_DIR}/leadv2-dispatch-product-close.sh" "${LIVE_DIR}/leadv2-phase8-close.sh"; do
  sha256sum "$_f"
done > "${_live_sums_file}"
_live_guard() {
  local _bad=0
  for _f in "${LIVE_DIR}/leadv2-phase-record.sh" "${LIVE_DIR}/leadv2-dispatch-code.sh" \
            "${LIVE_DIR}/leadv2-dispatch-product-close.sh" "${LIVE_DIR}/leadv2-phase8-close.sh"; do
    sha256sum "$_f"
  done | diff -q - "${_live_sums_file}" >/dev/null 2>&1 || _bad=1
  if [[ ${_bad} == 1 ]]; then
    printf 'LIVE-TREE MUTATED by test-dispatch-walks-the-whole-ladder.sh — refusing\n' >&2
    return 1
  fi
  return 0
}

# ── fixture env (idiom: test-phase-precondition-bootstrap.sh:40-50)
# Hermetic vs lane envs: a dispatched lane exports PROJECT_ROOT=<real repo>;
# phase-record fail-closes (rc 4, root conflict) when it inherits that next to
# this suite's per-call LEADV2_PROJECT_ROOT=<scratch>. Drop it — every call
# below names its scratch root explicitly.
unset PROJECT_ROOT
export LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/.cache"
export LEADV2_JOURNAL_BIN="${TMP_ROOT}/journal.sh"
JOURNAL_LOG="${TMP_ROOT}/journal.log"
cat > "${LEADV2_JOURNAL_BIN}" <<'JEOF'
#!/usr/bin/env bash
echo "$@" >> "${LEADV2_JOURNAL_LOG:-/dev/null}" 2>/dev/null || true
JEOF
chmod +x "${LEADV2_JOURNAL_BIN}"
export LEADV2_JOURNAL_LOG="$JOURNAL_LOG"
export LEADV2_PREMISE_PROBE=0
export LEADV2_REQUIRE_PHASES=1
export LEADV2_JUDGE_DISABLE=1

PASS=0
FAIL=0
SKIP=0
ok()     { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
fail()   { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1" >&2; }
skip()   { SKIP=$((SKIP+1)); printf '  SKIP: %s\n' "$1"; }

phases_d() { printf '%s/docs/handoff/dispatch-%s/phases.d' "$1" "$2"; }
mk_dispatch_dir() { mkdir -p "$(dirname "$(phases_d "$1" "$2")")"; }

# ══ Case 1a: a Standard lane with only classify(+class)+build(running) must
# NOT be accepted as terminal by phase8-close. Scratch bin: phase8-close +
# phase-record + journal copied; render stub; assert/e2e-gate absent → skipped.
printf 'test: 1a phase8-close refuses a partial ladder (classify,build)\n'
{
  SIG1A="1abcde01"
  REPO1A="${TMP_ROOT}/repo1a"
  mkdir -p "${REPO1A}/docs/handoff/dispatch-${SIG1A}/phases.d"
  CLAUDE_PROJECT_ROOT="${REPO1A}" LEADV2_PROJECT_ROOT="${REPO1A}" \
  LEADV2_JOURNAL_BIN="${LEADV2_JOURNAL_BIN}" LEADV2_JOURNAL_LOG="${JOURNAL_LOG}" \
    bash "${PHASE_RECORD}" record "${SIG1A}" classify --status done --class Standard \
    --owner test >/dev/null 2>&1
  printf 'phase: build\nstatus: running\n' > "$(phases_d "${REPO1A}" "${SIG1A}")/build.yaml"
  printf 'phase8 passed (fixture)\n' > "${REPO1A}/docs/handoff/dispatch-${SIG1A}/phase8-passed.flag"

  BIN1A="${TMP_ROOT}/bin1a"; mkdir -p "${BIN1A}"
  cp "${P8}" "${BIN1A}/leadv2-phase8-close.sh"
  cp "${PHASE_RECORD}" "${BIN1A}/leadv2-phase-record.sh"
  # phase-record sources lib/ helpers from its own dir — copy them or the
  # ladder assert fails for the wrong reason (missing lib, not missing rungs).
  cp -R "${LIVE_DIR}/lib" "${BIN1A}/lib"
  cp "${LEADV2_JOURNAL_BIN}" "${BIN1A}/leadv2-journal.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${BIN1A}/leadv2-render-close.sh"
  chmod +x "${BIN1A}/leadv2-render-close.sh" "${BIN1A}/leadv2-journal.sh"

  : > "${JOURNAL_LOG}"
  rc1a=0
  CLAUDE_PROJECT_ROOT="${REPO1A}" LEADV2_PROJECT_ROOT="${REPO1A}" \
  LEADV2_HANDOFF_DIR="${REPO1A}/docs/handoff" \
  LEADV2_JOURNAL_BIN="${BIN1A}/leadv2-journal.sh" LEADV2_JOURNAL_LOG="${JOURNAL_LOG}" \
    timeout 60 bash "${BIN1A}/leadv2-phase8-close.sh" "dispatch-${SIG1A}" \
    >"${TMP_ROOT}/1a.out" 2>&1 || rc1a=$?
  if [[ ${rc1a} -ne 0 ]]; then
    ok "phase8-close refused the partial ladder (rc=${rc1a})"
  else
    fail "partial ladder (classify,build) accepted as terminal by phase8-close (rc=0, out=$(tail -3 "${TMP_ROOT}/1a.out" 2>/dev/null | tr '\n' ' '))"
  fi
  if [[ ! -f "$(phases_d "${REPO1A}" "${SIG1A}")/close.yaml" ]]; then
    ok "no close.yaml written for the partial ladder"
  else
    fail "close.yaml recorded for a lane whose ladder stops at build"
  fi
  if grep -q 'close_refused' "${JOURNAL_LOG}" 2>/dev/null && \
     grep 'close_refused' "${JOURNAL_LOG}" | grep -q 'missing=' && \
     grep 'close_refused' "${JOURNAL_LOG}" | grep -q 'review'; then
    ok "close_refused journaled naming review as missing"
  else
    fail "no close_refused journal row naming review (journal_rows=$(grep -c close_refused "${JOURNAL_LOG}" 2>/dev/null || true))"
  fi
}

# ══ Case 1b: a `--kind plugin` Standard dispatch must ARM A CLOSE GATE.
printf 'test: 1b non-product (plugin) dispatch arms the close gate\n'
{
  REPO7="${TMP_ROOT}/repo7"
  mkdir -p "$REPO7"
  ( cd "$REPO7" && git init -q -b main && git config user.email test@example.invalid \
    && git config user.name test && printf 'seed\n' > .gitignore \
    && git add .gitignore && git commit -qm seed ) >/dev/null 2>&1

  mk_stub() { local n="$1"; local stub="${TMP_ROOT}/stub-$n.sh"
    cat > "$stub" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  task|bg) printf '%s\n' "$n" >> "${TMP_ROOT}/spawned.txt"; printf 'task-fixture-0001\n'; exit 0 ;;
  *) exit 0 ;;
esac
EOF
    chmod +x "$stub"; printf '%s' "$stub"; }
  CODEX_STUB="$(mk_stub codex)"; GLM_STUB="$(mk_stub glm)"
  SONNET_STUB="$(mk_stub sonnet)"; FREEPOOL_STUB="$(mk_stub freepool)"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "\$ROUTE_TEST_QUOTA"\n' > "${TMP_ROOT}/live.sh"
  chmod +x "${TMP_ROOT}/live.sh"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${TMP_ROOT}/free.sh"
  chmod +x "${TMP_ROOT}/free.sh"
  QUOTA_JSON="$(python3 -c "import json;print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':1},'weekly':{'pct':1}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':1}]},'anthropic':{'status':'ok','accounts':[{'active':True,'five_hour_pct':1,'seven_day_pct':1}]}}))")"
  CLOSE_STUB="${TMP_ROOT}/close-stub.sh"
  printf '#!/usr/bin/env bash\ntouch "%s/close-armed"\nexit 0\n' "${TMP_ROOT}" > "${CLOSE_STUB}"
  chmod +x "${CLOSE_STUB}"

  : > "${JOURNAL_LOG}"
  rc1b=0
  ( cd "$REPO7" && \
    CLAUDE_PROJECT_ROOT="$REPO7" PROJECT_ROOT="$REPO7" LEADV2_PROJECT_ROOT="$REPO7" \
    LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/cache7" LEADV2_STATE_BASE="${TMP_ROOT}/state7" \
    LEADV2_DISPATCH_E2E_GATE=1 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_PREMISE_PROBE=0 \
    LEADV2_DISPATCH_CODEX_BIN="$CODEX_STUB" LEADV2_DISPATCH_GLM_BIN="$GLM_STUB" \
    LEADV2_DISPATCH_SUBSESSION_BIN="$SONNET_STUB" LEADV2_DISPATCH_FREEPOOL_BIN="$FREEPOOL_STUB" \
    LEADV2_DISPATCH_PRODUCT_CLOSE_BIN="$CLOSE_STUB" \
    LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="${TMP_ROOT}/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="${TMP_ROOT}/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="${TMP_ROOT}/arb7" \
    ROUTE_TEST_QUOTA="$QUOTA_JSON" ROUTE_TEST_FREE_RC=1 \
    timeout 120 bash "$DC" 'LADDER fixture plugin lane writes plugin code' \
      --kind plugin --task-class standard --writes "plugins/x.sh" \
  ) >"${TMP_ROOT}/1b.out" 2>&1 || rc1b=$?
  if [[ -f "${TMP_ROOT}/close-armed" ]]; then
    ok "close gate launched for a --kind plugin lane"
  else
    fail "--kind plugin dispatch spawned no close gate (rc=${rc1b}, out=$(tail -3 "${TMP_ROOT}/1b.out" 2>/dev/null | tr '\n' ' '))"
  fi
  if grep -q 'close_gate_armed' "${JOURNAL_LOG}" 2>/dev/null; then
    ok "journal carries close_gate_armed"
  else
    fail "no close_gate_armed journal row for a plugin-kind lane"
  fi
  if grep -q 'reason=non_product_class' "${JOURNAL_LOG}" 2>/dev/null; then
    fail "plugin lane still declared unenforced (reason=non_product_class)"
  else
    ok "no non_product_class unenforced declaration"
  fi
}

# ══ Case 2: a hand-written `review done` (no runner evidence) must be refused.
printf 'test: 2 hand-written review record refused (runner token)\n'
{
  SIG2="2abcde02"
  REPO2="${TMP_ROOT}/repo2"
  mk_dispatch_dir "$REPO2" "$SIG2"
  mkdir -p "$(phases_d "$REPO2" "$SIG2")"
  printf 'diff content for %s\n' "$SIG2" > "${REPO2}/docs/handoff/dispatch-${SIG2}/review.diff"
  rc2=0
  LEADV2_PROJECT_ROOT="$REPO2" bash "${PHASE_RECORD}" record "${SIG2}" review --status done \
    --artifact "docs/handoff/dispatch-${SIG2}/review.diff" --owner test \
    >"${TMP_ROOT}/2.out" 2>&1 || rc2=$?
  if [[ ${rc2} -eq 7 ]]; then
    ok "hand-written review refused rc=7"
  elif [[ ${rc2} -eq 0 ]]; then
    fail "hand-written review record ACCEPTED (rc=0) — owner text is the only evidence"
  else
    fail "hand-written review refused with unexpected rc=${rc2} (want 7)"
  fi
  if [[ ! -f "$(phases_d "$REPO2" "$SIG2")/review.yaml" ]]; then
    ok "no review.yaml written"
  else
    fail "review.yaml written for a hand-written record"
  fi
  if grep -q 'phase_record_refused' "${JOURNAL_LOG}" 2>/dev/null && \
     grep 'phase_record_refused' "${JOURNAL_LOG}" | grep -q 'runner_token_missing'; then
    ok "journal names runner_token_missing"
  else
    fail "no phase_record_refused runner_token_missing journal row"
  fi
}

# ══ Case 3 (pin): reviewer arm == build arm must be refused by the inline
# review body's defense-in-depth (product-close ~:3775 / review-run ~:1513).
printf 'test: 3 reviewer == author refused (pin)\n'
{
  SIG3="3abcde03"
  REPO3="${TMP_ROOT}/repo3"
  mkdir -p "$REPO3"
  ( cd "$REPO3" && git init -q -b main && git config user.email test@example.invalid \
    && git config user.name test && mkdir -p agent && printf 'seed\n' > agent/seed.py \
    && git add agent/seed.py && git commit -qm seed ) >/dev/null 2>&1
  WT3="$(CLAUDE_PROJECT_ROOT="$REPO3" LEADV2_PROJECT_ROOT="$REPO3" bash "${LANE_WT_BIN}" ensure "ladder-$$" standard >/dev/null 2>&1; printf '%s/.claude/worktrees/ladder-%s\n' "$REPO3" "$$")"
  WT3="${WT3%%[[:space:]]*}"
  if [[ -d "${WT3}" ]]; then
    printf '#!/usr/bin/env bash\necho ok\n' > "${WT3}/agent/good.sh"
    git -C "${WT3}" add -A >/dev/null 2>&1 || true
    RESOLVER3="${TMP_ROOT}/resolver3.py"
    printf '#!/usr/bin/env python3\nprint("reviewer=glm")\nprint("pool=glm")\nprint("refusal=")\n' > "${RESOLVER3}"
    chmod +x "${RESOLVER3}"
    CLAUDE_PROJECT_ROOT="${REPO3}" LEADV2_PROJECT_ROOT="${REPO3}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/good.sh" LEADV2_LANE_WORK_ROOT="${WT3}" \
    LEADV2_GLM_POLICY_RESOLVER="${RESOLVER3}" \
      timeout 120 bash "${PC}" "${REPO3}" "${SIG3}" glm "" 0 1 "ladder-$$" \
      >"${TMP_ROOT}/3.out" 2>&1
    GATE3="${REPO3}/docs/handoff/dispatch-${SIG3}/review-gate.md"
    if [[ -f "${GATE3}" ]] && grep -q '^status: unreviewed' "${GATE3}" \
       && grep -q 'reviewer_equals_author' "${GATE3}"; then
      ok "reviewer==author refused (status unreviewed, reviewer_equals_author)"
    else
      fail "reviewer==author not refused (gate=$(grep -h '^status:' "${GATE3}" 2>/dev/null || printf absent))"
    fi
    if ! grep -q '^status: done' "$(phases_d "$REPO3" "$SIG3")/review.yaml" 2>/dev/null; then
      ok "no review done record for a refused review"
    else
      fail "review recorded done despite reviewer==author refusal"
    fi
  else
    skip "3: lane worktree fixture unavailable"
  fi
}

# ══ Case 4 (pin): a lead-authored brief is valid plan evidence — must STAY
# accepted (the fix touches only review/test/live_verify).
printf 'test: 4 lead-authored brief accepted as plan\n'
{
  SIG4="4abcde04"
  REPO4="${TMP_ROOT}/repo4"
  mk_dispatch_dir "$REPO4" "$SIG4"
  mkdir -p "${REPO4}/docs/handoff/LADDER-${SIG4}"
  { printf '# LADDER-%s\n\n' "$SIG4"
    printf 'Fixture lead-authored plan describing the task scope, acceptance criteria, and\n'
    printf 'the files expected to change during this lane run, long enough to count as a brief.\n'
  } > "${REPO4}/docs/handoff/LADDER-${SIG4}/brief.md"
  rc4=0
  LEADV2_PROJECT_ROOT="$REPO4" bash "${PHASE_RECORD}" record "${SIG4}" plan --status done \
    --artifact "docs/handoff/LADDER-${SIG4}/brief.md" --owner lead:test \
    >"${TMP_ROOT}/4.out" 2>&1 || rc4=$?
  if [[ ${rc4} -eq 0 ]] && [[ -f "$(phases_d "$REPO4" "$SIG4")/plan.yaml" ]] \
     && grep -q '^proof: attested' "$(phases_d "$REPO4" "$SIG4")/plan.yaml"; then
    ok "brief accepted as plan, proof attested"
  else
    fail "brief-based plan record refused (rc=${rc4}, out=$(tail -2 "${TMP_ROOT}/4.out" | tr '\n' ' '))"
  fi
}

# ══ Case 5 (regression guard): the bootstrap-admit SENTINEL admits a fresh
# Standard lane's build stamp; without the sentinel a plan-only store still
# gets the explicit missing=gate1 refusal.
printf 'test: 5 bootstrap-admit sentinel separates admission from completion\n'
{
  # 5a: classify(Standard) + sentinel → build stamp admitted.
  SIG5A="5abcde05"
  REPO5A="${TMP_ROOT}/repo5a"
  mk_dispatch_dir "$REPO5A" "$SIG5A"
  mkdir -p "$(phases_d "$REPO5A" "$SIG5A")"
  LEADV2_PROJECT_ROOT="$REPO5A" bash "${PHASE_RECORD}" record "${SIG5A}" classify \
    --status done --class Standard --owner test >/dev/null 2>&1
  printf '%s %s\n' "${SIG5A}" "$(date -u +%FT%TZ)" > "$(phases_d "$REPO5A" "$SIG5A")/.bootstrap-admit"
  rc5a=0
  LEADV2_PROJECT_ROOT="$REPO5A" bash "${PHASE_RECORD}" record "${SIG5A}" build --status running \
    --handle "dispatch-${SIG5A}-build" --owner dispatcher:test >"${TMP_ROOT}/5a.out" 2>&1 || rc5a=$?
  if [[ ${rc5a} -eq 0 ]]; then
    ok "sentinel-admitted lane's build stamp accepted"
  else
    fail "bootstrap-admitted lane refused at the build stamp (rc=${rc5a}) — admission must not require completion"
  fi
  # 5b: no sentinel, plan only → rc 6 naming gate1.
  SIG5B="5abcde06"
  REPO5B="${TMP_ROOT}/repo5b"
  mk_dispatch_dir "$REPO5B" "$SIG5B"
  mkdir -p "$(phases_d "$REPO5B" "$SIG5B")" "${REPO5B}/docs/handoff/LADDER-${SIG5B}"
  { printf '# brief\n\nplan text long enough to be a brief for the fixture lane here.\n'; } \
    > "${REPO5B}/docs/handoff/LADDER-${SIG5B}/brief.md"
  LEADV2_PROJECT_ROOT="$REPO5B" bash "${PHASE_RECORD}" record "${SIG5B}" classify \
    --status done --class Standard --owner test >/dev/null 2>&1
  LEADV2_PROJECT_ROOT="$REPO5B" bash "${PHASE_RECORD}" record "${SIG5B}" plan --status done \
    --artifact "docs/handoff/LADDER-${SIG5B}/brief.md" --owner lead:test >/dev/null 2>&1
  rc5b=0
  LEADV2_PROJECT_ROOT="$REPO5B" bash "${PHASE_RECORD}" record "${SIG5B}" build --status running \
    --handle "dispatch-${SIG5B}-build" --owner dispatcher:test >"${TMP_ROOT}/5b.out" 2>&1 || rc5b=$?
  if [[ ${rc5b} -eq 6 ]] && grep -q 'gate1' "${TMP_ROOT}/5b.out"; then
    ok "plan-only store (no sentinel) refused missing=gate1"
  else
    fail "plan-only store: want rc=6 missing=gate1, got rc=${rc5b}"
  fi
}

# ══ Negative controls (declared above): activate only when the mechanism
# exists on the tree under test; pre-fix they are skip-marked.
printf 'test: NC1 mutant phase-record without runner-token refusal reddens case 2\n'
{
  if grep -q 'runner_token_missing' "${PHASE_RECORD}" 2>/dev/null; then
    # mutation: switch OFF the runner-owned gate's own condition (INSIDE the
    # record body — the && continuation of the `if`, syntax preserved), never
    # a top-level insert. The mutant lives in its own scratch bin WITH lib/,
    # because phase-record sources lib/ helpers from its own directory.
    BINNC1="${TMP_ROOT}/binnc1"; mkdir -p "${BINNC1}"
    cp -R "${LIVE_DIR}/lib" "${BINNC1}/lib"
    sed 's/^     && \[\[ "$status" == "done" \]\]; then$/     \&\& false; then # NC1 MUTATION/' \
      "${PHASE_RECORD}" > "${BINNC1}/leadv2-phase-record.sh"
    chmod +x "${BINNC1}/leadv2-phase-record.sh"
    MUT="${BINNC1}/leadv2-phase-record.sh"
    if ! grep -q 'NC1 MUTATION' "${MUT}"; then
      fail "NC1: mutation pattern not found in the copy — control not exercised"
    fi
    SIGNC1="nc1abcd1"
    REPONC1="${TMP_ROOT}/reponc1"
    mk_dispatch_dir "$REPONC1" "$SIGNC1"
    mkdir -p "$(phases_d "$REPONC1" "$SIGNC1")"
    printf 'diff content\n' > "${REPONC1}/docs/handoff/dispatch-${SIGNC1}/review.diff"
    rcnc1=0
    LEADV2_PROJECT_ROOT="$REPONC1" LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/.cache-nc1" \
      bash "${MUT}" record "${SIGNC1}" review --status done \
      --artifact "docs/handoff/dispatch-${SIGNC1}/review.diff" --owner test \
      >/dev/null 2>&1 || rcnc1=$?
    if [[ ${rcnc1} -eq 0 ]]; then
      ok "NC1: mutation accepted a hand-written review (control alive — case 2 guards it)"
    else
      fail "NC1: mutated phase-record still refused (rc=${rcnc1}) — the mutation did not remove the mechanism"
    fi
  else
    skip "NC1: runner-token mechanism not on this tree yet (pre-fix)"
  fi
}
{
  if grep -q '_close_assert_rc' "${P8}" 2>/dev/null; then
    # mutation: neutralize the ladder-assert refusal branch INSIDE the copy
    MUTP8="${TMP_ROOT}/mut-phase8-close.sh"
    sed 's/^  if \[\[ ${_close_assert_rc} -ne 0 \]\]; then/  if false; then # NC2 MUTATION/' "${P8}" > "${MUTP8}"
    chmod +x "${MUTP8}"
    if grep -q 'NC2 MUTATION' "${MUTP8}"; then
      SIGNC2="nc2abcd2"
      REPONC2="${TMP_ROOT}/reponc2"
      mkdir -p "${REPONC2}/docs/handoff/dispatch-${SIGNC2}/phases.d"
      CLAUDE_PROJECT_ROOT="${REPONC2}" LEADV2_PROJECT_ROOT="${REPONC2}" \
        bash "${PHASE_RECORD}" record "${SIGNC2}" classify --status done --class Standard \
        --owner test >/dev/null 2>&1
      printf 'phase: build\nstatus: running\n' > "$(phases_d "${REPONC2}" "${SIGNC2}")/build.yaml"
      printf 'phase8 passed (fixture)\n' > "${REPONC2}/docs/handoff/dispatch-${SIGNC2}/phase8-passed.flag"
      BINNC2="${TMP_ROOT}/binnc2"; mkdir -p "${BINNC2}"
      cp "${MUTP8}" "${BINNC2}/leadv2-phase8-close.sh"
      cp "${PHASE_RECORD}" "${BINNC2}/leadv2-phase-record.sh"
      cp -R "${LIVE_DIR}/lib" "${BINNC2}/lib"
      cp "${LEADV2_JOURNAL_BIN}" "${BINNC2}/leadv2-journal.sh"
      printf '#!/usr/bin/env bash\nexit 0\n' > "${BINNC2}/leadv2-render-close.sh"
      chmod +x "${BINNC2}"/*
      rcnc2=0
      CLAUDE_PROJECT_ROOT="${REPONC2}" LEADV2_PROJECT_ROOT="${REPONC2}" \
      LEADV2_HANDOFF_DIR="${REPONC2}/docs/handoff" \
        timeout 60 bash "${BINNC2}/leadv2-phase8-close.sh" "dispatch-${SIGNC2}" \
        >/dev/null 2>&1 || rcnc2=$?
      if [[ ${rcnc2} -eq 0 ]]; then
        ok "NC2: mutated phase8-close closed the partial ladder (control alive — case 1a guards it)"
      else
        fail "NC2: mutated phase8-close still refused (rc=${rcnc2}) — the mutation did not remove the mechanism"
      fi
    else
      fail "NC2: mutation pattern not found in the copy — control not exercised"
    fi
  else
    skip "NC2: ladder assert not on this tree yet (pre-fix)"
  fi
}

printf '\nsummary: pass=%d fail=%d skip=%d\n' "$PASS" "$FAIL" "$SKIP"
[[ "$FAIL" -eq 0 ]]
