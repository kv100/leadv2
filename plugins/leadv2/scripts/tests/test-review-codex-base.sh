#!/usr/bin/env bash
# tests/test-review-codex-base.sh — REVIEW-CODEX-EMPTY-BASE-01: a committed lane must
# never hand codex a bare `--base HEAD`, because codex-companion's resolveReviewTarget
# treats an explicit --base as authoritative and never falls back to working-tree mode
# -- diffing HEAD against itself yields an empty branch diff, a short/empty stdout, and
# the REVIEW-BODY-PERSIST-01 guard downstream correctly (but misleadingly) reports
# review_body_lost, because codex always writes its `[codex-task] tier=...` banner to
# stderr regardless of whether a real review body exists.
#
# Drives the REAL leadv2-review-run.sh CLI end to end (never a reimplementation). The
# codex launcher is stubbed via LEADV2_DISPATCH_CODEX_BIN with a recorder script that
# appends its own argv to a file and exits 0 -- the assertion is on WHAT BASE codex was
# handed, never on codex's output.
#
# Run: bash scripts/tests/test-review-codex-base.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

REVIEW_RUN_SH="${SCRIPTS_ROOT}/leadv2-review-run.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

if bash -n "$REVIEW_RUN_SH"; then
  pass "bash -n clean (leadv2-review-run.sh)"
else
  fail "bash -n failed on leadv2-review-run.sh"
fi
if /bin/bash -n "$REVIEW_RUN_SH" 2>/dev/null; then
  pass "/bin/bash 3.2 -n clean (leadv2-review-run.sh)"
else
  fail "/bin/bash 3.2 -n failed on leadv2-review-run.sh"
fi

SUITE_TMP="$(lv2_mktemp_dir "review-codex-base-test")"
trap 'rm -rf "$SUITE_TMP"' EXIT

# make_committed_lane <name> -> prints repo path. History: init commit (becomes
# refs/remotes/origin/main AND the recorded start SHA), then one committed lane change
# on top (becomes HEAD) -- i.e. an ALREADY-COMMITTED lane, the exact Fault A scenario.
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
  printf '%s' "$start_sha"
}

# make_codex_recorder <name> -> prints the stub path. Appends its own argv (one per
# invocation) to ${SUITE_TMP}/<name>/codex-invocations.log and exits 0; never
# invoked means the log file never appears.
make_codex_recorder() {
  local name="$1"
  local stub="${SUITE_TMP}/${name}/codex-recorder.sh"
  local logf="${SUITE_TMP}/${name}/codex-invocations.log"
  mkdir -p "$(dirname "$stub")"
  cat > "$stub" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${logf}"
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\nstub codex review body, long enough to clear the floor check comfortably for this fixture.\n'
exit 0
SH
  chmod +x "$stub"
  printf '%s' "$stub"
}

# make_resolver_stub <name> -> resolver that always selects codex as sole reviewer/pool.
make_resolver_stub() {
  local name="$1"
  local stub="${SUITE_TMP}/${name}/resolver.py"
  mkdir -p "$(dirname "$stub")"
  cat > "$stub" <<'PY'
print("reviewer=codex")
print("pool=codex:ok:")
print("refusal=")
PY
  printf '%s' "$stub"
}

run_review() { # <root> <task> <handoff> <diff-file> <invoc-log-name>
  # Internally this engine shells out to leadv2-dispatch-code.sh record-review, which
  # by default writes a REAL dedup ledger (~/.claude/cache/code-review-ledger) and a
  # REAL docs/leadv2/tasks/review-<hash>/journal.md in THIS repo -- LEADV2_DISPATCH_CACHE_DIR
  # and LEADV2_JOURNAL_BIN redirect both into the scratch tempdir so this test never
  # leaks artifacts into the real repo tree or a shared ledger other lanes read.
  local root="$1" task="$2" handoff="$3" diff_file="$4" name="$5"
  local resolver codex_bin
  resolver="$(make_resolver_stub "$name")"
  codex_bin="$(make_codex_recorder "$name")"
  mkdir -p "$handoff" "${SUITE_TMP}/${name}/cache"
  LEADV2_GLM_POLICY_RESOLVER="$resolver" \
  LEADV2_DISPATCH_CODEX_BIN="$codex_bin" \
  LEADV2_DISPATCH_CACHE_DIR="${SUITE_TMP}/${name}/cache" \
  LEADV2_JOURNAL_BIN=/bin/true \
  LEADV2_REVIEW_FANOUT=1 \
    bash "$REVIEW_RUN_SH" --task "$task" --root "$root" --handoff "$handoff" --diff "$diff_file" --author sonnet >/dev/null 2>&1
  printf '%s' $?
}

make_diff_file() { # <name> -> prints path of a non-empty scratch diff file, content
  # unique per scenario so distinct runs never collide on the real diff-hash dedup
  # ledger leadv2-review-run.sh consults (docs/leadv2/tasks/review-<hash>/journal.md).
  local name="$1"
  local f="${SUITE_TMP}/${name}/diff.txt"
  mkdir -p "$(dirname "$f")"
  printf -- '--- a/file.txt\n+++ b/file.txt\n@@\n-baseline\n+changed-%s-%s\n' "${name}" "$$" > "$f"
  printf '%s' "$f"
}

# ── Scenario 1: LEADV2_LANE_START_SHA set to the pre-commit SHA ─────────────────────
n1="s1"
start1="$(make_committed_lane "$n1")"
root1="${SUITE_TMP}/${n1}/root"
head1="$(git -C "$root1" rev-parse HEAD)"
handoff1="${SUITE_TMP}/${n1}/handoff"
diff1="$(make_diff_file "$n1")"
rc1="$(LEADV2_LANE_START_SHA="$start1" run_review "$root1" "tsig001" "$handoff1" "$diff1" "$n1")"
log1="${SUITE_TMP}/${n1}/codex-invocations.log"
if [[ -f "$log1" ]]; then
  argv1="$(cat "$log1")"
  base1="$(printf '%s\n' "$argv1" | sed -n 's/.*--base \([^ ]*\).*/\1/p' | head -1)"
  if [[ -n "$base1" && "$base1" != "$head1" && "$base1" != "HEAD" ]]; then
    pass "Scenario 1: recorded --base (${base1}) differs from HEAD (${head1})"
  else
    fail "Scenario 1: recorded --base='${base1}' should differ from HEAD='${head1}' -- argv: ${argv1}"
  fi
  if [[ "$argv1" == *"--cwd ${root1}"* ]]; then
    pass "Scenario 1: argv contains --cwd ${root1}"
  else
    fail "Scenario 1: argv missing --cwd ${root1} -- argv: ${argv1}"
  fi
else
  fail "Scenario 1: codex launcher never invoked -- ${log1} missing (rc=${rc1})"
fi

# ── Scenario 2: LEADV2_LANE_START_SHA unset -> falls back to origin/main ────────────
n2="s2"
make_committed_lane "$n2" >/dev/null
root2="${SUITE_TMP}/${n2}/root"
head2="$(git -C "$root2" rev-parse HEAD)"
handoff2="${SUITE_TMP}/${n2}/handoff"
diff2="$(make_diff_file "$n2")"
unset LEADV2_LANE_START_SHA
rc2="$(run_review "$root2" "tsig002" "$handoff2" "$diff2" "$n2")"
log2="${SUITE_TMP}/${n2}/codex-invocations.log"
if [[ -f "$log2" ]]; then
  argv2="$(cat "$log2")"
  base2="$(printf '%s\n' "$argv2" | sed -n 's/.*--base \([^ ]*\).*/\1/p' | head -1)"
  if [[ -n "$base2" && "$base2" != "$head2" && "$base2" != "HEAD" ]]; then
    pass "Scenario 2: base resolves from origin/main, still != HEAD (base=${base2})"
  else
    fail "Scenario 2: recorded --base='${base2}' should differ from HEAD='${head2}' -- argv: ${argv2}"
  fi
else
  fail "Scenario 2: codex launcher never invoked -- ${log2} missing (rc=${rc2})"
fi

# ── Scenario 3: committed lane, no start-SHA and no origin/main -> refused, no base ──
n3="s3"
root3="${SUITE_TMP}/${n3}/root"
mkdir -p "$root3"
git -C "$root3" init -q
git -C "$root3" config user.email "test@test.local"
git -C "$root3" config user.name "test"
printf 'baseline\n' > "$root3/file.txt"
git -C "$root3" add file.txt
git -C "$root3" commit -q -m init
lv2_assert_scratch_repo "$root3"
printf 's3-lane-change\n' >> "$root3/file.txt"
git -C "$root3" add file.txt
git -C "$root3" commit -q -m "lane change"
handoff3="${SUITE_TMP}/${n3}/handoff"
diff3="$(make_diff_file "$n3")"
mkdir -p "$handoff3" "${SUITE_TMP}/${n3}/cache"
resolver3="$(make_resolver_stub "$n3")"
codex_bin3="$(make_codex_recorder "$n3")"
LEADV2_GLM_POLICY_RESOLVER="$resolver3" \
LEADV2_DISPATCH_CODEX_BIN="$codex_bin3" \
LEADV2_DISPATCH_CACHE_DIR="${SUITE_TMP}/${n3}/cache" \
LEADV2_JOURNAL_BIN=/bin/true \
LEADV2_REVIEW_FANOUT=1 \
  bash "$REVIEW_RUN_SH" --task "tsig003" --root "$root3" --handoff "$handoff3" --diff "$diff3" --author sonnet \
  >/dev/null 2>"${SUITE_TMP}/${n3}/stderr.log"
log3="${SUITE_TMP}/${n3}/codex-invocations.log"
if [[ ! -f "$log3" ]]; then
  pass "Scenario 3: codex launcher never invoked (no resolvable base)"
else
  fail "Scenario 3: codex launcher was invoked -- $(cat "$log3")"
fi
if grep -q 'review_arm_skipped arm=codex reason=no_base_resolved' "${SUITE_TMP}/${n3}/stderr.log" 2>/dev/null; then
  pass "Scenario 3: journal shows review_arm_skipped arm=codex reason=no_base_resolved"
else
  fail "Scenario 3: missing review_arm_skipped reason=no_base_resolved -- $(cat "${SUITE_TMP}/${n3}/stderr.log" 2>/dev/null)"
fi
if grep -q 'review_body_lost' "${SUITE_TMP}/${n3}/stderr.log" 2>/dev/null; then
  fail "Scenario 3: unexpectedly reported review_body_lost for a cleanly skipped arm"
else
  pass "Scenario 3: no review_body_lost verdict for the skipped arm"
fi

# ── Scenario 4: lane whose HEAD == base (nothing to review) -> empty_diff skip ──────
n4="s4"
root4="${SUITE_TMP}/${n4}/root"
mkdir -p "$root4"
git -C "$root4" init -q
git -C "$root4" config user.email "test@test.local"
git -C "$root4" config user.name "test"
printf 'baseline\n' > "$root4/file.txt"
git -C "$root4" add file.txt
git -C "$root4" commit -q -m init
lv2_assert_scratch_repo "$root4"
start4="$(git -C "$root4" rev-parse HEAD)"
git -C "$root4" update-ref refs/remotes/origin/main "$start4"
# No further commit: HEAD == start4 == origin/main -> empty diff.
handoff4="${SUITE_TMP}/${n4}/handoff"
diff4="$(make_diff_file "$n4")"
rc4="$(LEADV2_LANE_START_SHA="$start4" run_review "$root4" "tsig004" "$handoff4" "$diff4" "$n4")"
log4="${SUITE_TMP}/${n4}/codex-invocations.log"
if [[ ! -f "$log4" ]]; then
  pass "Scenario 4: codex launcher never invoked (empty diff)"
else
  fail "Scenario 4: codex launcher was invoked -- $(cat "$log4")"
fi

# ── Scenario 5: ROOT is a non-git tempdir -> degenerate escape, literal --base HEAD ─
n5="s5"
root5="${SUITE_TMP}/${n5}/root"
mkdir -p "$root5"
handoff5="${SUITE_TMP}/${n5}/handoff"
diff5="$(make_diff_file "$n5")"
rc5="$(run_review "$root5" "tsig005" "$handoff5" "$diff5" "$n5")"
log5="${SUITE_TMP}/${n5}/codex-invocations.log"
if [[ -f "$log5" ]]; then
  argv5="$(cat "$log5")"
  if [[ "$argv5" == *"--base HEAD"* ]]; then
    pass "Scenario 5: non-git ROOT preserves the degenerate escape (--base HEAD)"
  else
    fail "Scenario 5: expected literal --base HEAD on a non-git ROOT -- argv: ${argv5}"
  fi
else
  fail "Scenario 5: codex launcher never invoked on the degenerate-escape path (rc=${rc5})"
fi

# ── Scenario 6: regression guard -- no committed-lane scenario (1-4) ever recorded a
#    bare '--base HEAD' ─────────────────────────────────────────────────────────────
any_bare_head=0
for n in s1 s2 s4; do
  lf="${SUITE_TMP}/${n}/codex-invocations.log"
  [[ -f "$lf" ]] || continue
  if grep -qE -- '--base HEAD( |$)' "$lf"; then
    any_bare_head=1
    fail "Scenario 6: ${n} recorded a bare --base HEAD -- $(cat "$lf")"
  fi
done
# s3 is the refusal scenario: no invocation at all is the correct outcome, already
# asserted above, so it is excluded from this bare-HEAD scan by construction.
if [[ "$any_bare_head" -eq 0 ]]; then
  pass "Scenario 6: no committed-lane scenario recorded a bare --base HEAD"
fi

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
