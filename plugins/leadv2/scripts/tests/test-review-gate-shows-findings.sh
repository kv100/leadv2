#!/usr/bin/env bash
# tests/test-review-gate-shows-findings.sh — REVIEW-GATE-SHOWS-FINDINGS-01: the
# review gate must SHOW the findings, not only their counts.
#
# Part A exercises the shared renderer (leadv2-review-findings.sh) as the CLI the
# evidence procedure uses: markdown-section extraction across the three real report
# shapes (numbered-bold items, **H1 — path: desc** bold items, Cyrillic sections),
# the structured FINDING:/json paths, the do-not-merge advisory, the parse-failure
# degrade, and the rc-always-0 contract.
#
# Parts B/C drive the REAL writers end to end (same harness pattern as
# test-review-arm-no-verdict.sh / test-leadv2-review-routing.sh — stub resolver and
# stub reviewer launchers, never a reimplementation of the gate's logic), because the
# R1 lesson of this task is that a renderer nobody calls changes nothing: BOTH
# leadv2-dispatch-product-close.sh (the lane path that wrote every real gate to date)
# and leadv2-review-run.sh must append the block, keep their head lines byte-identical
# and first, and keep verdict/exit semantics unchanged (a PASS_WITH_NITS +
# do-not-merge report still exits 0 with status: pass).
#
# Run: bash scripts/tests/test-review-gate-shows-findings.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

FINDINGS_SH="${SCRIPTS_ROOT}/leadv2-review-findings.sh"
PRODUCT_CLOSE_SH="${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh"
ENGINE_SH="${SCRIPTS_ROOT}/leadv2-review-run.sh"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

bash -n "$FINDINGS_SH" 2>/dev/null || { echo "ERROR: renderer syntax check failed"; exit 1; }

SUITE_TMP="$(lv2_mktemp_dir "review-gate-shows-findings-test")"
trap 'rm -rf "$SUITE_TMP"' EXIT

has_line() { # <haystack> <needle> — whole-substring match
  grep -qF -- "$2" <<<"$1"
}

# ═══ Part A: renderer CLI ═════════════════════════════════════════════════════

# Fixture A1: dispatch-82e1056d shape — FAIL, **H1 — `path`: desc** bold items,
# continuation lines that must NOT become items, a Verified-clean section whose
# bullets must not leak in.
R1="${SUITE_TMP}/r1.md"
{
  printf 'REVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=0 high=2 medium=1 low=6\n\n'
  printf '## High\n\n'
  printf '**H1 — `scripts/gate-cost-report.sh`: the only anchor proven present in the prod journal is computed and then silently discarded — the report can never produce output on live data.**\n'
  printf 'Continuation prose that belongs to H1 and must not render as its own finding.\n'
  printf '**H2 — `scripts/gate-cost-report.sh`: `^`-anchored anchor regexes can never match the actual journal MESSAGE format.**\n\n'
  printf '## Medium\n\n'
  printf '**M1 — new `PE_*` flag has no ENGINE-REFERENCE.md row.**\n\n'
  printf '## Low\n\n'
  printf '**L1 — a low nit that must never render.**\n\n'
  printf '## Verified clean\n\n'
  printf '%s\n' '- not a finding, wrong section'
} > "$R1"
out="$("${FINDINGS_SH}" --report "$R1" --report-path docs/handoff/dispatch-t1/review-glm.md 2>/dev/null)"; rc=$?
[[ $rc -eq 0 ]] && pass "A1: rc 0" || fail "A1: rc ${rc}"
n="$(grep -c '^- \[High\] scripts/gate-cost-report.sh' <<<"$out")"
[[ "$n" -eq 2 ]] && pass "A1: both Highs rendered with their anchor" || fail "A1: expected 2 '- [High] scripts/gate-cost-report.sh' lines, got ${n}: ${out}"
has_line "$out" 'findings_source: markdown_sections' && pass "A1: findings_source=markdown_sections" || fail "A1: findings_source wrong"
has_line "$out" 'omitted: low=6' && pass "A1: lows folded into omitted: low=6" || fail "A1: omitted low line missing"
has_line "$out" 'report: docs/handoff/dispatch-t1/review-glm.md' && pass "A1: report pointer present" || fail "A1: report pointer missing"
has_line "$out" 'the only anchor proven present' && pass "A1: H1 desc on the face of the gate" || fail "A1: H1 desc missing"
has_line "$out" 'anchored anchor regexes can never match' && pass "A1: H2 desc on the face of the gate" || fail "A1: H2 desc missing"
has_line "$out" 'Continuation prose' && fail "A1: continuation line leaked as an item" || pass "A1: continuation lines not items"
has_line "$out" 'L1' && fail "A1: a Low rendered" || pass "A1: no Low rendered"
has_line "$out" 'not a finding, wrong section' && fail "A1: non-severity section leaked" || pass "A1: Verified-clean section excluded"

# Fixture A2: dispatch-95eb1cb9 shape — PASS_WITH_NITS, Cyrillic Medium, a Cyrillic
# do-not-merge verdict section. status is the WRITER's business; the renderer's job
# is the advisory + the blocking Medium on the face of the gate.
R2="${SUITE_TMP}/r2.md"
{
  printf 'REVIEW_VERDICT: PASS_WITH_NITS\nREVIEW_FINDINGS: critical=0 high=0 medium=1 low=1\n\n'
  printf '## Medium\n\n'
  printf '1. **`wire_shared_links` затирает git-трекнутые файлы симлинками** (`scripts/vps-release-deploy.sh`) — будущие коммиты никогда не доедут до VPS.\n\n'
  printf '## Вердикт\n\n'
  printf 'Код не мержить как есть без багфикса.\n'
} > "$R2"
out="$("${FINDINGS_SH}" --report "$R2" --report-path docs/handoff/dispatch-t2/review-glm.md 2>/dev/null)"; rc=$?
[[ $rc -eq 0 ]] && pass "A2: rc 0" || fail "A2: rc ${rc}"
has_line "$out" 'reviewer_says: do_not_merge' && pass "A2: Cyrillic «не мержить как есть» -> reviewer_says: do_not_merge" || fail "A2: do_not_merge advisory missing"
has_line "$out" '- [Medium] scripts/vps-release-deploy.sh' && pass "A2: blocking Medium rendered with anchor" || fail "A2: Medium line missing: ${out}"
has_line "$out" 'затирает git-трекнутые файлы' && pass "A2: Cyrillic desc survives byte-boundary truncation intact" || fail "A2: Cyrillic desc mangled"

# No false positive: an English PASS report that merely discusses merging.
R2b="${SUITE_TMP}/r2b.md"
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\nClean; nothing blocks the merge window.\n' > "$R2b"
out="$("${FINDINGS_SH}" --report "$R2b" 2>/dev/null)"
has_line "$out" 'reviewer_says' && fail "A2b: do_not_merge false positive" || pass "A2b: no false-positive do_not_merge"

# Fixture A3: counts say findings exist but no section parses -> explicit
# unavailability, never a silent clean-looking gate.
R3="${SUITE_TMP}/r3.md"
printf 'REVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=0 high=1 medium=1 low=0\nProse table arm shapes the extractor does not know.\n' > "$R3"
out="$("${FINDINGS_SH}" --report "$R3" --report-path docs/handoff/dispatch-t3/review-glm.md 2>/dev/null)"; rc=$?
[[ $rc -eq 0 ]] && pass "A3: rc 0 on parse failure" || fail "A3: rc ${rc} — renderer must never kill the gate"
has_line "$out" 'findings: unavailable' && has_line "$out" 'findings_reason: parse_failed' && \
  pass "A3: parse failure -> findings: unavailable + findings_reason: parse_failed" || fail "A3: degrade block wrong: ${out}"
has_line "$out" 'report: docs/handoff/dispatch-t3/review-glm.md' && pass "A3: report pointer on degrade" || fail "A3: pointer missing"

# A4: report missing entirely.
out="$("${FINDINGS_SH}" --report "${SUITE_TMP}/nope.md" --report-path docs/handoff/dispatch-t4/review-glm.md 2>/dev/null)"; rc=$?
[[ $rc -eq 0 ]] && has_line "$out" 'findings_reason: report_missing' && pass "A4: missing report -> report_missing, rc 0" || fail "A4: rc ${rc} out=${out}"

# A5: zero counts and zero items is the one quiet case.
R5="${SUITE_TMP}/r5.md"
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\nClean.\n' > "$R5"
out="$("${FINDINGS_SH}" --report "$R5" 2>/dev/null)"
has_line "$out" 'findings: none' && pass "A5: zero/zero -> findings: none (explicit)" || fail "A5: ${out}"

# A6: structured FINDING: lines (the review-run.sh reviewer contract).
R6="${SUITE_TMP}/r6.md"
{
  printf 'REVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=1 high=1 medium=0 low=0\n'
  printf 'FINDING: severity=Critical file=lib/core.sh line=42 dimension=correctness desc=off-by-one drops the last window\n'
  printf 'FINDING: severity=High file=scripts/deploy.sh line=7 dimension=security desc=unquoted expansion in remote ssh string\n'
} > "$R6"
out="$("${FINDINGS_SH}" --report "$R6" 2>/dev/null)"
has_line "$out" 'findings_source: finding_lines' && pass "A6: FINDING: lines -> finding_lines" || fail "A6: source wrong: ${out}"
has_line "$out" '- [Critical] lib/core.sh:42 — off-by-one drops the last window' && pass "A6: Critical rendered with file:line anchor" || fail "A6: Critical line wrong"
has_line "$out" '- [High] scripts/deploy.sh:7 — unquoted expansion in remote ssh string' && pass "A6: High rendered" || fail "A6: High line wrong"

# A7: non-empty review-findings.json wins (deduped, carries verifier_verdict);
# refuted findings still render — they are information, the verdict ignores them.
R7="${SUITE_TMP}/r7.md"
printf 'REVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=0 high=2 medium=0 low=0\nprose\n' > "$R7"
J7="${SUITE_TMP}/r7.json"
printf '{"task":"t7","arms":["glm"],"fanout":1,"findings":[{"dimension":"correctness","severity":"High","file":"scripts/gate.sh","line":10,"arm":"glm","verifier_arm":"sonnet","verifier_verdict":"upheld","desc":"anchor discarded"},{"dimension":"perf","severity":"High","file":"scripts/gate.sh","line":20,"arm":"glm","verifier_arm":"sonnet","verifier_verdict":"refuted","desc":"regex cannot match"}]}' > "$J7"
out="$("${FINDINGS_SH}" --report "$R7" --json "$J7" 2>/dev/null)"
has_line "$out" '- [High] scripts/gate.sh:10 — anchor discarded (verified: upheld)' && pass "A7: upheld verdict carried through" || fail "A7: upheld line wrong: ${out}"
has_line "$out" '(verified: refuted)' && pass "A7: refuted finding still renders" || fail "A7: refuted finding dropped"

# A8: non-blocking Mediums cap at LEADV2_GATE_MEDIUM_MAX (5); remainder folded.
R8="${SUITE_TMP}/r8.md"
{
  printf 'REVIEW_VERDICT: PASS_WITH_NITS\nREVIEW_FINDINGS: critical=0 high=0 medium=7 low=0\n\n## Medium\n\n'
  for i in 1 2 3 4 5 6 7; do printf '%d. **nit %d** — plain non-blocking prose\n' "$i" "$i"; done
} > "$R8"
out="$("${FINDINGS_SH}" --report "$R8" 2>/dev/null)"
n="$(grep -c '^- \[Medium\]' <<<"$out")"
[[ "$n" -eq 5 ]] && has_line "$out" 'omitted: medium=2' && pass "A8: Mediums capped at 5, remainder in omitted:" || fail "A8: rendered=${n} out=${out}"

# ═══ Part B: the lane writer (leadv2-dispatch-product-close.sh) end to end ══════

make_fixture_root() {
  local name="$1" content="$2"
  local repo="${SUITE_TMP}/${name}/root"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@test.local"
  git -C "$repo" config user.name "test"
  printf 'baseline\n' > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m init
  lv2_assert_scratch_repo "$repo"
  printf '%s\n' "$content" >> "$repo/file.txt"
  printf '%s' "$repo"
}

make_resolver_stub() {
  local name="$1"
  local stub="${SUITE_TMP}/${name}/resolver.py"
  mkdir -p "$(dirname "$stub")"
  printf 'print("reviewer=glm")\nprint("pool=glm:ok:")\nprint("refusal=")\n' > "$stub"
  printf '%s' "$stub"
}

# make_glm_stub <name> <mode> — writes the report to --out.
#   fail_dnm   : FAIL report with a High + an English do-not-merge line
#   pass_dnm   : PASS_WITH_NITS report with a Cyrillic Medium + «не мержить как есть»
#   pass_clean : plain PASS, zero counts
make_glm_stub() {
  local name="$1" mode="$2"
  local stub="${SUITE_TMP}/${name}/glm-stub.sh"
  mkdir -p "$(dirname "$stub")"
  cat > "$stub" <<'SH'
#!/usr/bin/env bash
outfile=""
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
  if [[ "${args[$i]}" == "--out" ]]; then
    outfile="${args[$((i+1))]}"
  fi
  i=$((i+1))
done
SH
  case "$mode" in
    fail_dnm)
      cat >> "$stub" <<'SH'
{
printf 'REVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=0 high=1 medium=0 low=1\n'
printf '## High\n\n'
printf '**H1 — `scripts/gate-cost-report.sh`: the only anchor proven present is computed and then silently discarded — must not land in this shape.**\n'
} > "$outfile"
exit 0
SH
      ;;
    pass_dnm)
      cat >> "$stub" <<'SH'
{
printf 'REVIEW_VERDICT: PASS_WITH_NITS\nREVIEW_FINDINGS: critical=0 high=0 medium=1 low=1\n\n'
printf '## Medium\n\n'
printf '1. **`wire_shared_links` затирает git-трекнутые файлы симлинками** (`scripts/vps-release-deploy.sh`) — будущие коммиты никогда не доедут до VPS.\n\n'
printf '## Вердикт\n\n'
printf 'Код не мержить как есть без багфикса по пункту 1.\n'
} > "$outfile"
exit 0
SH
      ;;
    pass_clean)
      cat >> "$stub" <<'SH'
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\nClean diff, no issues found by the stub reviewer arm.\n' > "$outfile"
exit 0
SH
      ;;
  esac
  chmod +x "$stub"
  printf '%s' "$stub"
}

# Recording stubs so ledger tokens are assertable.
make_journal_stub() { # <name> -> prints path; appends argv to <name>.journal.log
  local name="$1"
  local stub="${SUITE_TMP}/${name}/journal.sh" logf="${SUITE_TMP}/${name}/journal.log"
  mkdir -p "$(dirname "$stub")"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\nexit 0\n' "$logf" > "$stub"
  chmod +x "$stub"
  printf '%s' "$stub"
}
make_ledger_stub() { # <name> -> prints path; appends argv to <name>.ledger.log
  local name="$1"
  local stub="${SUITE_TMP}/${name}/ledger.sh" logf="${SUITE_TMP}/${name}/ledger.log"
  mkdir -p "$(dirname "$stub")"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\nexit 0\n' "$logf" > "$stub"
  chmod +x "$stub"
  printf '%s' "$stub"
}

run_close() { # <root> <sig8> <author> <resolver> <journal> <ledger>
  local root="$1" sig8="$2" author="$3" resolver="$4" journal="$5" ledger="$6"
  local cache="${SUITE_TMP}/${sig8}/cache"
  mkdir -p "$cache"
  LEADV2_GLM_POLICY_RESOLVER="$resolver" \
  LEADV2_DISPATCH_CACHE_DIR="$cache" \
  LEADV2_JOURNAL_BIN="$journal" \
  LEADV2_DISPATCH_LEDGER_BIN="$ledger" \
  LEADV2_E2E_OWNERSHIP=0 \
    bash "$PRODUCT_CLOSE_SH" "$root" "$sig8" "$author" "" 0 1 "" 2>&1
}

# B1: FAIL report -> gate shows the High by name; head lines and exit code unchanged.
rootB1="$(make_fixture_root b1 "b1-unique-diff-content")"
glmB1="$(make_glm_stub b1 fail_dnm)"
outB1="$(LEADV2_DISPATCH_GLM_BIN="$glmB1" run_close "$rootB1" b1sig001 codex "$(make_resolver_stub b1)" "$(make_journal_stub b1)" "$(make_ledger_stub b1)")"; rcB1=$?
gateB1="${rootB1}/docs/handoff/dispatch-b1sig001/review-gate.md"
[[ $rcB1 -eq 7 ]] && pass "B1: fail verdict still exits 7" || fail "B1: expected exit 7, got ${rcB1} -- ${outB1}"
[[ "$(head -n1 "$gateB1" 2>/dev/null)" == 'status: fail' ]] && pass "B1: head -1 still 'status: fail'" || fail "B1: gate head changed: $(head -n1 "$gateB1" 2>/dev/null)"
grep -q '^- \[High\] scripts/gate-cost-report.sh' "$gateB1" 2>/dev/null && \
  pass "B1: the High is ON the gate, not just 'high: 1'" || fail "B1: no rendered High -- $(cat "$gateB1" 2>/dev/null)"
grep -q '^report: docs/handoff/dispatch-b1sig001/review-glm.md$' "$gateB1" 2>/dev/null && pass "B1: report pointer present" || fail "B1: pointer missing"
grep -q 'review_gate task=b1sig001 status=fail critical=0 high=1 do_not_merge=1' "${SUITE_TMP}/b1/journal.log" 2>/dev/null && \
  pass "B1: additive do_not_merge=1 ledger token on the fail line" || fail "B1: ledger token missing -- $(cat "${SUITE_TMP}/b1/journal.log" 2>/dev/null)"

# B2: PASS_WITH_NITS + «не мержить как есть» -> status: pass and exit 0 UNCHANGED,
# but the advisory and the blocking Medium are on the face of the gate (mission case 2).
rootB2="$(make_fixture_root b2 "b2-unique-diff-content")"
glmB2="$(make_glm_stub b2 pass_dnm)"
outB2="$(LEADV2_DISPATCH_GLM_BIN="$glmB2" run_close "$rootB2" b2sig002 codex "$(make_resolver_stub b2)" "$(make_journal_stub b2)" "$(make_ledger_stub b2)")"; rcB2=$?
gateB2="${rootB2}/docs/handoff/dispatch-b2sig002/review-gate.md"
[[ $rcB2 -eq 0 ]] && pass "B2: do-not-merge report still exits 0 (advisory, not a verdict change)" || fail "B2: expected exit 0, got ${rcB2} -- ${outB2}"
[[ "$(head -n1 "$gateB2" 2>/dev/null)" == 'status: pass' ]] && pass "B2: status: pass unchanged" || fail "B2: status changed: $(head -n1 "$gateB2" 2>/dev/null)"
grep -q '^reviewer_says: do_not_merge$' "$gateB2" 2>/dev/null && pass "B2: reviewer_says: do_not_merge on the gate" || fail "B2: advisory missing -- $(cat "$gateB2" 2>/dev/null)"
grep -q '^- \[Medium\] scripts/vps-release-deploy.sh' "$gateB2" 2>/dev/null && pass "B2: blocking Medium rendered" || fail "B2: Medium missing"
grep -q 'review_verdict_pass.*do_not_merge=1' "${SUITE_TMP}/b2/ledger.log" 2>/dev/null && \
  pass "B2: do_not_merge=1 token on the landed ledger note" || fail "B2: ledger token missing -- $(cat "${SUITE_TMP}/b2/ledger.log" 2>/dev/null)"

# B3: clean pass -> findings: none, gate still well-formed.
rootB3="$(make_fixture_root b3 "b3-unique-diff-content")"
glmB3="$(make_glm_stub b3 pass_clean)"
outB3="$(LEADV2_DISPATCH_GLM_BIN="$glmB3" run_close "$rootB3" b3sig003 codex "$(make_resolver_stub b3)" "$(make_journal_stub b3)" "$(make_ledger_stub b3)")"; rcB3=$?
gateB3="${rootB3}/docs/handoff/dispatch-b3sig003/review-gate.md"
[[ $rcB3 -eq 0 ]] && grep -q '^findings: none$' "$gateB3" 2>/dev/null && \
  pass "B3: clean pass exits 0 with findings: none" || fail "B3: rc=${rcB3} gate=$(cat "$gateB3" 2>/dev/null)"

# ═══ Part C: the engine writer (leadv2-review-run.sh) end to end ═══════════════

mk_engine_fixture() { # <tag> -> sets ROOT/HANDOFF/DIFF
  local tag="$1"
  ROOT="${SUITE_TMP}/repo-${tag}"
  mkdir -p "$ROOT/.claude/ref"
  HANDOFF="${ROOT}/docs/handoff/dispatch-${tag}"
  mkdir -p "$HANDOFF"
  DIFF="${HANDOFF}/review.diff"
  printf 'diff --git a/x b/x\n+hello\n' > "$DIFF"
}

cat > "${SUITE_TMP}/resolver-c.py" <<'PY'
print("reviewer=codex")
print("pool=codex:ok:,glm:ok:")
print("refusal=")
PY

# codex stub: FAIL report with a High — stdout is the report body the engine saves.
cat > "${SUITE_TMP}/codex-fail.sh" <<'SH'
#!/usr/bin/env bash
printf 'REVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=0 high=1 medium=1 low=2\n\n'
printf '## High\n\n'
printf '**H1 — `lib/engine.sh`: the writer can drop the mirror file on the failure path — must not land.**\n\n'
printf '## Medium\n\n'
printf '1. **Stale mirror on request-failure paths** — `lib/engine.sh` can lie in the case it diagnoses.\n'
SH
chmod +x "${SUITE_TMP}/codex-fail.sh"

cat > "${SUITE_TMP}/architect-c.sh" <<'SH'
#!/usr/bin/env bash
role=""
while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; *) shift ;; esac; done
[[ "$role" == "hack-detect" ]] && exit 0
exit 0
SH
chmod +x "${SUITE_TMP}/architect-c.sh"

cat > "${SUITE_TMP}/dispatch-c.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${SUITE_TMP}/dispatch-c.sh"

mk_engine_fixture CFR1
LEADV2_GLM_POLICY_RESOLVER="${SUITE_TMP}/resolver-c.py" \
LEADV2_DISPATCH_CODEX_BIN="${SUITE_TMP}/codex-fail.sh" \
LEADV2_DISPATCH_ARCHITECT_BIN="${SUITE_TMP}/architect-c.sh" \
LEADV2_DISPATCH_BIN="${SUITE_TMP}/dispatch-c.sh" \
LEADV2_REVIEW_FANOUT=1 \
  bash "$ENGINE_SH" --task CFR1 --root "$ROOT" --handoff "$HANDOFF" --diff "$DIFF" --author sonnet \
  >"${SUITE_TMP}/cf-r1.out" 2>"${SUITE_TMP}/cf-r1.err"; rcC1=$?
gateC1="${HANDOFF}/review-gate.md"
[[ $rcC1 -eq 7 ]] && pass "C1: engine fail verdict still exits 7" || fail "C1: expected exit 7, got ${rcC1} -- $(tail -5 "${SUITE_TMP}/cf-r1.err")"
[[ "$(head -n1 "$gateC1" 2>/dev/null)" == 'arms: '* ]] && pass "C1: arms: still the first line" || fail "C1: gate head changed: $(head -n1 "$gateC1" 2>/dev/null)"
grep -q '^- \[High\] lib/engine.sh' "$gateC1" 2>/dev/null && pass "C1: High rendered on the engine-written gate" || fail "C1: no rendered High -- $(cat "$gateC1" 2>/dev/null)"
grep -q '^- \[Medium\] lib/engine.sh' "$gateC1" 2>/dev/null && pass "C1: Medium rendered" || fail "C1: no rendered Medium"
grep -q 'review_gate task=CFR1 status=fail.*do_not_merge=1' "${SUITE_TMP}/cf-r1.err" && \
  pass "C1: additive do_not_merge=1 token on the engine's fail decision" || fail "C1: decision token missing -- $(grep 'status=fail' "${SUITE_TMP}/cf-r1.err")"

log ""
log "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
