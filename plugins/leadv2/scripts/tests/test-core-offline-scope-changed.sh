#!/usr/bin/env bash
# run-all-triggers: run-core-offline
#
# test-core-offline-scope-changed.sh — E2E-GATE-RUNS-ALL-94-SUITES-BECAUSE-
# THE-ENTRYPOINT-IGNORES-SCOPE-CHANGED-01.
#
# run-core-offline.sh used to parse NO arguments: the phase-8 gate's
# `--scope changed` was silently discarded and every gate run executed all 94
# suites (lane d2823c51e670 parked e2e_timeout rc=124 on a 4-file diff,
# 2026-09-07). The runner now implements run-all's --scope contract, reusing
# its `# run-all-triggers:` self-registration + EXTRA_SUITE_MAP rows so a
# suite registers its triggers in exactly one place no matter which runner
# executes it.
#
# Every count assertion below reads the runner's OWN summary line
# (`suites passed=N failed=N missing=N`) — executed = P+F+M — never a log
# string, so a mutant cannot pass by rewording output.
#
# DECLARED NEGATIVE CONTROLS (E2E-KILLRATE-01), applied by
# leadv2-mutation-control.sh to marker lines INSIDE
# _core_offline_scope_changed_select()'s body in run-core-offline.sh:
#   M1 scope-mut-1  an unresolvable base returns an EMPTY selection as
#      success -> case (c) goes RED on executed == 0 (today's assertion
#      expects the full set). The exact shape of a gate that passes forever.
#   M2 scope-mut-2  the changed-file list is ignored, everything is selected
#      -> case (b) goes RED on executed == total for a 1-file narrow diff.
#      A runner that "supports" --scope by parsing the flag and running
#      everything anyway — today's bug wearing the new flag.
# A top-level insert is NOT a valid control for this suite: it reddens every
# case for the wrong reason and reads as a pass.
#
# Hermetic: every fixture is a throwaway git repo under mktemp -d; nothing
# under docs/leadv2 is touched. Run: bash test-core-offline-scope-changed.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_RUNNER="${SCRIPT_DIR}/run-core-offline.sh"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"

PASS=0; FAIL=0; NOTRUN=0; ERRORS=()
log()    { printf -- '[TEST] %s\n' "$*"; }
pass()   { PASS=$((PASS + 1)); log "PASS: $1"; }
fail()   { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }
notrun() { NOTRUN=$((NOTRUN + 1)); log "NOT RUN: $1"; }

FIXTURES=()
cleanup() { local d; for d in ${FIXTURES[@]+"${FIXTURES[@]}"}; do rm -rf "$d"; done; }
trap cleanup EXIT

# ── executed-suite count from the runner's own summary ─────────────────────
executed_from() { # <transcript> -> number of suites actually executed
  printf '%s\n' "$1" \
    | sed -n 's/.*suites passed=\([0-9]*\) failed=\([0-9]*\) missing=\([0-9]*\).*/\1 \2 \3/p' \
    | awk '{ s += $1 + $2 + $3 } END { print s + 0 }'
}
scope_field() { # <transcript> <field>= -> value
  printf '%s\n' "$1" | grep -o "$2=[^ ]*" | head -1 | cut -d= -f2-
}

# ── fixture: a throwaway git repo with a copied runner + fake suites ────────
# modes: narrow | nobase | unmapped | clean | extra | baddecl
build_fix() { # <mode> -> sets FIX, DEFS
  local mode="$1"
  FIX="$(mktemp -d "${TMPDIR:-/tmp}/scope-fix.XXXXXX")"
  FIXTURES+=("$FIX")
  mkdir -p "$FIX/plugins/leadv2/scripts" "$FIX/plugins/leadv2/scripts/tests" "$FIX/tests"
  cp "${REAL_RUNNER}" "$FIX/plugins/leadv2/scripts/tests/run-core-offline.sh"
  local s
  for s in aaa bbb ccc greeble zap; do
    { printf '#!/usr/bin/env bash\nexit 0\n'; } > "$FIX/tests/test-${s}.sh"
  done
  # zap registers itself for the `greeble` stem: the run-all self-registration
  # convention, honoured by BOTH runners from the same line.
  printf '# run-all-triggers: greeble\n' >> "$FIX/tests/test-zap.sh"
  printf 'v1\n' > "$FIX/plugins/leadv2/scripts/greeble.sh"
  DEFS="fake aaa|||bash $FIX/tests/test-aaa.sh
fake bbb|||bash $FIX/tests/test-bbb.sh
fake ccc|||bash $FIX/tests/test-ccc.sh
greeble contract|||bash $FIX/tests/test-greeble.sh"
  case "$mode" in
    extra)
      rm -f "$FIX/plugins/leadv2/scripts/greeble.sh" "$FIX/tests/test-greeble.sh"
      printf 'v1\n' > "$FIX/plugins/leadv2/scripts/weeble.sh"
      printf '#!/usr/bin/env bash\nexit 0\n' > "$FIX/tests/test-weeble-extra.sh"
      # FORM 1 EXTRA row, the leadv2 literal shape: only this row maps the
      # weeble stem (no test-weeble.sh convention candidate exists).
      cat > "$FIX/tests/run-all.sh" <<'RAEOF'
EXTRA_SUITE_MAP="weeble:tests/test-weeble-extra.sh"
RAEOF
      DEFS="fake aaa|||bash $FIX/tests/test-aaa.sh
fake bbb|||bash $FIX/tests/test-bbb.sh
fake ccc|||bash $FIX/tests/test-ccc.sh
weeble extra row|||bash $FIX/tests/test-weeble-extra.sh"
      ;;
    baddecl)
      printf '# run-all-triggers: bad!stem\n' > "$FIX/tests/test-oops.sh"
      ;;
  esac
  git -C "$FIX" init -q
  git -C "$FIX" config user.email scope@test.local
  git -C "$FIX" config user.name scope-test
  case "$mode" in
    nobase)
      # Single commit on a non-main branch, no origin, no HEAD~1: the changed
      # set exists (uncommitted dirt below) but no base can bound the lane.
      git -C "$FIX" symbolic-ref HEAD refs/heads/lane-only
      git -C "$FIX" add -A
      git -C "$FIX" commit -qm base
      printf 'v2-dirty\n' > "$FIX/plugins/leadv2/scripts/greeble.sh"
      ;;
    clean)
      git -C "$FIX" symbolic-ref HEAD refs/heads/main
      git -C "$FIX" add -A
      git -C "$FIX" commit -qm base
      ;;
    *)
      git -C "$FIX" symbolic-ref HEAD refs/heads/main
      git -C "$FIX" add -A
      git -C "$FIX" commit -qm base
      git -C "$FIX" checkout -q -b lane
      if [[ "$mode" == "extra" ]]; then
        printf 'v2\n' > "$FIX/plugins/leadv2/scripts/weeble.sh"
      else
        printf 'v2\n' > "$FIX/plugins/leadv2/scripts/greeble.sh"
      fi
      [[ "$mode" == "unmapped" ]] && printf 'note\n' > "$FIX/notes.txt"
      git -C "$FIX" add -A
      git -C "$FIX" commit -qm lane-work
      ;;
  esac
}

run_fix() { # <lock-disable 0|1> <shards> [runner args...] -> transcript, rc in $?
  local lockdis="$1" shards="$2"
  shift 2
  (
    cd "$FIX" || exit 9
    exec env LEADV2_SUITE_SHARDS="$shards" \
      LEADV2_SUITE_LOCK_DISABLE="$lockdis" \
      LEADV2_SUITE_DEFS_OVERRIDE="$DEFS" \
      bash "$FIX/plugins/leadv2/scripts/tests/run-core-offline.sh" "$@"
  ) 2>&1
}

# ── (a) argument contract: loud, never swallowed ───────────────────────────
args_case() {
  local out rc
  out="$(bash "${REAL_RUNNER}" --definitely-not-a-flag 2>&1)"; rc=$?
  if [[ $rc -eq 2 && "$out" == *"unknown argument: --definitely-not-a-flag"* ]]; then
    pass "unknown flag -> exit 2 naming the flag"
  else
    fail "unknown flag: rc=$rc out=$out"
  fi
  out="$(bash "${REAL_RUNNER}" --scope=bogus 2>&1)"; rc=$?
  if [[ $rc -eq 2 && "$out" == *"--scope must be changed|all"* ]]; then
    pass "--scope=bogus -> exit 2"
  else
    fail "--scope=bogus: rc=$rc out=$out"
  fi
  out="$(bash "${REAL_RUNNER}" --scope 2>&1)"; rc=$?
  [[ $rc -eq 2 ]] && pass "--scope without value -> exit 2" || fail "--scope no-value: rc=$rc"
  out="$(bash "${REAL_RUNNER}" -h 2>&1)"; rc=$?
  [[ $rc -eq 0 && "$out" == *"--scope changed|all"* ]] && pass "-h -> usage, exit 0" \
    || fail "-h: rc=$rc"
}

# ── (b) narrow run: fewer suites, base + counts named, suites REALLY run ────
# Lock ENABLED here on purpose: the flock re-exec must forward "$@" — a runner
# that drops the flag on re-exec silently un-scopes every real invocation.
narrow_case() { # <label> <lock-disable> <shards>
  local label="$1" lockdis="$2" shards="$3" out rc executed sel base changed unmapped reason
  build_fix narrow
  out="$(run_fix "$lockdis" "$shards" --scope changed)"; rc=$?
  executed="$(executed_from "$out")"
  sel="$(scope_field "$out" selected)"
  base="$(scope_field "$out" base)"
  changed="$(scope_field "$out" changed)"
  unmapped="$(scope_field "$out" unmapped)"
  reason="$(scope_field "$out" reason)"
  if [[ $rc -eq 0 ]]; then
    pass "$label: exit 0"
  else
    fail "$label: rc=$rc (last: $(printf '%s\n' "$out" | tail -3 | tr '\n' ' '))"
    return
  fi
  # greeble contract (stem convention) + test-zap.sh (trigger declaration,
  # ad-hoc — not in the curated defs). 2 of 4, strictly less than the total.
  [[ "$executed" == "2" ]] && pass "$label: executed 2 of 4 suites (got $executed)" \
    || fail "$label: expected 2 executed suites, got $executed"
  [[ "$sel" == "2" ]] && pass "$label: SCOPE_RESULT selected=2 total=4" \
    || fail "$label: SCOPE_RESULT selected=$sel"
  [[ "$base" == main@* ]] && pass "$label: base names the ref ($(printf '%s' "$base" | head -c 18)...)" \
    || fail "$label: base=[$base]"
  [[ "$changed" == "1" && "$unmapped" == "0" ]] && pass "$label: 1 changed file, 0 unmapped" \
    || fail "$label: changed=[$changed] unmapped=[$unmapped]"
  [[ "$reason" == "-" ]] && pass "$label: no fallback claimed" \
    || fail "$label: reason=[$reason]"
  printf '%s\n' "$out" | grep -q 'greeble contract' \
    && pass "$label: mapped curated suite executed" \
    || fail "$label: mapped curated suite not in transcript"
  printf '%s\n' "$out" | grep -q 'zap (scope-selected ad-hoc)\|test-zap.sh' \
    && pass "$label: trigger-declared suite executed (ad-hoc)" \
    || fail "$label: ad-hoc zap suite not in transcript"
}

# ── (c) no resolvable base -> FULL set + reason (M1's bite) ─────────────────
nobase_case() {
  local out rc executed reason
  build_fix nobase
  out="$(run_fix 1 1 --scope changed)"; rc=$?
  executed="$(executed_from "$out")"
  reason="$(scope_field "$out" reason)"
  [[ $rc -eq 0 ]] && pass "nobase: exit 0" || fail "nobase: rc=$rc"
  [[ "$executed" == "4" ]] && pass "nobase: full set executed (4 of 4)" \
    || fail "nobase: expected 4 executed (full-set fallback), got $executed — a zero here is the lying-green shape"
  [[ "$reason" == *no_base_ref* ]] && pass "nobase: reason names no_base_ref" \
    || fail "nobase: reason=[$reason]"
}

# ── (d) an unmapped changed file -> FULL set + reason ───────────────────────
unmapped_case() {
  local out rc executed reason unmapped
  build_fix unmapped
  out="$(run_fix 1 1 --scope changed)"; rc=$?
  executed="$(executed_from "$out")"
  reason="$(scope_field "$out" reason)"
  unmapped="$(scope_field "$out" unmapped)"
  [[ $rc -eq 0 ]] && pass "unmapped: exit 0" || fail "unmapped: rc=$rc"
  [[ "$executed" == "4" ]] && pass "unmapped: full set executed (4 of 4)" \
    || fail "unmapped: expected 4 executed, got $executed"
  [[ "$unmapped" == "1" && "$reason" == *unmapped* ]] && pass "unmapped: names the unmapped file" \
    || fail "unmapped: unmapped=[$unmapped] reason=[$reason]"
}

# ── (e) only .md/docs housekeeping -> FULL set + reason ─────────────────────
clean_case() {
  local out rc executed reason
  build_fix clean
  out="$(run_fix 1 1 --scope changed)"; rc=$?
  executed="$(executed_from "$out")"
  reason="$(scope_field "$out" reason)"
  [[ $rc -eq 0 ]] && pass "clean: exit 0" || fail "clean: rc=$rc"
  [[ "$executed" == "4" ]] && pass "clean: full set executed (4 of 4)" \
    || fail "clean: expected 4 executed, got $executed"
  [[ "$reason" == *no_relevant_changed_files* ]] && pass "clean: reason names no_relevant_changed_files" \
    || fail "clean: reason=[$reason]"
}

# ── (f) no flag = today's behaviour: full set, no scope output ─────────────
default_scope_case() {
  local out rc executed
  build_fix narrow
  out="$(run_fix 1 1)"; rc=$?
  executed="$(executed_from "$out")"
  [[ $rc -eq 0 ]] && pass "default: exit 0" || fail "default: rc=$rc"
  [[ "$executed" == "4" ]] && pass "default: full set executed (4 of 4)" \
    || fail "default: expected 4 executed, got $executed"
  if printf '%s\n' "$out" | grep -q 'scope=changed running'; then
    fail "default: scope line printed without the flag"
  else
    pass "default: no narrowing without the flag"
  fi
}

# ── (g) malformed trigger declaration -> FATAL exit 2, file named ──────────
baddecl_case() {
  local out rc
  build_fix baddecl
  out="$(run_fix 1 1 --scope changed)"; rc=$?
  if [[ $rc -eq 2 && "$out" == *"bad_trigger_decl"* && "$out" == *"test-oops.sh"* ]]; then
    pass "baddecl: exit 2 naming the file"
  else
    fail "baddecl: rc=$rc out=$(printf '%s\n' "$out" | tail -2 | tr '\n' ' ')"
  fi
}

# ── (h) EXTRA_SUITE_MAP form-1 row honoured (run-all's other half) ─────────
extra_case() {
  local out rc executed sel
  build_fix extra
  out="$(run_fix 1 1 --scope changed)"; rc=$?
  executed="$(executed_from "$out")"
  sel="$(scope_field "$out" selected)"
  [[ $rc -eq 0 ]] && pass "extra: exit 0" || fail "extra: rc=$rc"
  [[ "$executed" == "1" && "$sel" == "1" ]] \
    && pass "extra: EXTRA row selected exactly its suite (1 of 4, got $executed)" \
    || fail "extra: executed=$executed selected=$sel"
  printf '%s\n' "$out" | grep -q 'weeble extra row' \
    && pass "extra: mapped suite executed" || fail "extra: suite not in transcript"
}

# ── (i) one registration, both runners ──────────────────────────────────────
# run-all's own scanner must list this suite for the run-core-offline key —
# the SAME declaration this runner's fixture cases consumed in (b).
registration_case() {
  local run_all="${REPO_ROOT}/tests/run-all.sh" rows
  if [[ -z "${REPO_ROOT}" || ! -f "${run_all}" ]]; then
    notrun "registration: no tests/run-all.sh in this checkout"
    return
  fi
  rows="$(LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash "${run_all}" 2>/dev/null \
    | grep -E '^run-core-offline(\.sh)?:' | grep -c 'test-core-offline-scope-changed.sh')"
  if [[ "${rows}" -ge 1 ]]; then
    pass "registration: run-all lists this suite under the run-core-offline key"
  else
    fail "registration: run-all trigger list has no row for this suite"
  fi
}

args_case
narrow_case "narrow/serial/lock" 0 1
narrow_case "narrow/sharded" 1 ""
nobase_case
unmapped_case
clean_case
default_scope_case
baddecl_case
extra_case
registration_case

printf -- '\n[TEST-RESULT] scope-changed passed=%d failed=%d notrun=%d\n' "$PASS" "$FAIL" "$NOTRUN"
for e in ${ERRORS[@]+"${ERRORS[@]}"}; do printf -- '  %s\n' "$e"; done
(( FAIL == 0 ))
