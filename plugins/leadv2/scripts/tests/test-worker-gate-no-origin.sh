#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-worker-output-gate
# GATE-ORIGIN-MAIN-01 — the worker output gate must not hard-fail just
# because `origin/main` doesn't resolve. A checkout with no remote, a
# differently-named default branch, or a fresh clone that hasn't fetched yet
# all have a usable base under a different name; the gate must find it. Only
# when NO base at all can be resolved may the gate refuse -- and that
# refusal must name every attempt it made and be distinguishable from a
# worker-produced parse failure. Fixture repos only, built in a temp dir,
# torn down on every exit path.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GATE="${SCRIPTS_ROOT}/lib/leadv2-worker-output-gate.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wog-no-origin-test.XXXXXX")"
GATE_BACKUP=""
restore_production_gate() {
  [[ -z "${GATE_BACKUP}" || ! -f "${GATE_BACKUP}" ]] || cp "${GATE_BACKUP}" "${GATE}"
}
cleanup() {
  restore_production_gate
  [[ "${WOG_KEEP:-0}" == "1" ]] || rm -rf "$TMP"
}
trap cleanup EXIT

bash -n "$GATE" || { fail "bash syntax: gate"; exit 1; }
pass "bash syntax: gate"

mk_repo() { # <path> <initial-branch>
  local d="$1" branch="$2"
  mkdir -p "$d"
  git -C "$d" init -q -b "$branch"
  git -C "$d" config user.email t@e.com
  git -C "$d" config user.name t
  : > "$d/seed"
  git -C "$d" add seed
  git -C "$d" commit -qm seed
}

add_broken_commit() { # <path>
  local d="$1"
  printf '#!/usr/bin/env bash\necho "unclosed\n' > "$d/broken.sh"
  git -C "$d" add broken.sh
  git -C "$d" commit -qm 'worker committed broken shell'
}

# ── case 1: origin/main present -- behaves exactly as today ────────────────
R1="$TMP/r1-origin-main"
mk_repo "$R1" main
git -C "$R1" update-ref refs/remotes/origin/main HEAD
out="$(bash "$GATE" "$R1" --from-git-diff HEAD 2>&1)"; rc=$?
if [[ $rc -eq 0 && -z "$out" ]]; then
  pass "case1 origin/main: clean tree passes silently"
else
  fail "case1 origin/main: expected rc0/no output" "rc=$rc out=$out"
fi

add_broken_commit "$R1"
out="$(bash "$GATE" "$R1" --from-git-diff HEAD 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q 'worker_output_gate_reject file=broken.sh tool=bash-n'; then
  pass "case1 origin/main: broken committed shell still rejected via origin/main"
else
  fail "case1 origin/main: expected reject via origin/main" "rc=$rc out=$out"
fi

# ── case 2: no remote at all, but a resolvable local base (local main) ─────
R2="$TMP/r2-local-main"
mk_repo "$R2" main
git -C "$R2" checkout -qb feature
out="$(bash "$GATE" "$R2" --from-git-diff HEAD 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && ! printf '%s' "$out" | grep -q 'worker_output_gate_reject\|worker_output_gate_error'; then
  pass "case2 local main, no remote: clean feature branch passes (falls through origin attempts to local main)"
else
  fail "case2 local main, no remote: expected rc0/no reject-or-error" "rc=$rc out=$out"
fi

add_broken_commit "$R2"
out="$(bash "$GATE" "$R2" --from-git-diff HEAD 2>&1)"; rc=$?
if [[ $rc -eq 1 ]] && printf '%s' "$out" | grep -q 'worker_output_gate_reject file=broken.sh tool=bash-n'; then
  pass "case2 local main, no remote: gate runs and judges output (rejects broken shell)"
else
  fail "case2 local main, no remote: expected worker-level reject (rc=1)" "rc=$rc out=$out"
fi

# ── case 3: no base resolvable at all -- named refusal, not a silent pass ──
R3="$TMP/r3-no-base"
mk_repo "$R3" lonely
add_broken_commit "$R3"
out="$(bash "$GATE" "$R3" --from-git-diff HEAD 2>&1)"; rc=$?
if [[ $rc -eq 2 ]] \
  && printf '%s' "$out" | grep -q 'worker_output_gate_error reason=committed_range_unresolved' \
  && printf '%s' "$out" | grep -q 'worker_output_gate_base_attempt ref=origin/main result=unresolved' \
  && printf '%s' "$out" | grep -q 'worker_output_gate_base_attempt ref=main result=unresolved'; then
  pass "case3 no base: refuses (rc=2) and names each resolution attempt"
else
  fail "case3 no base: expected named refusal rc=2" "rc=$rc out=$out"
fi

# ── case 4: refusal (case 3) is distinguishable from a worker reject ───────
# Different exit code (2 vs 1) AND a different message prefix
# (worker_output_gate_error vs worker_output_gate_reject) -- a caller can
# tell "the gate couldn't judge" apart from "the gate judged and failed".
R2_REJECT_OUT="$(bash "$GATE" "$R2" --from-git-diff HEAD 2>&1)"; r2_rc=$?
R3_REFUSAL_OUT="$(bash "$GATE" "$R3" --from-git-diff HEAD 2>&1)"; r3_rc=$?
if [[ $r2_rc -eq 1 && $r3_rc -eq 2 ]] \
  && printf '%s' "$R2_REJECT_OUT" | grep -q '^worker_output_gate_reject' \
  && ! printf '%s' "$R2_REJECT_OUT" | grep -q '^worker_output_gate_error' \
  && printf '%s' "$R3_REFUSAL_OUT" | grep -q 'worker_output_gate_error' \
  && ! printf '%s' "$R3_REFUSAL_OUT" | grep -q '^worker_output_gate_reject'; then
  pass "case4: gate refusal (rc=2, _error) is distinguishable from a worker reject (rc=1, _reject)"
else
  fail "case4: refusal and worker-reject must differ in rc and message prefix" \
    "r2_rc=$r2_rc r3_rc=$r3_rc r2_out=$R2_REJECT_OUT r3_out=$R3_REFUSAL_OUT"
fi

# ── mutation control: restore the unconditional origin/main-only refusal ───
# on the fixture that case2 proves the fix fixed (no remote, resolvable
# local base). The un-fixed gate must turn this fixture RED (rc=2, silent
# pass is not acceptable either -- it must reproduce the ORIGINAL refusal).
GATE_BACKUP="$TMP/leadv2-worker-output-gate.original.sh"
cp "$GATE" "$GATE_BACKUP"
python3 - "$GATE" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
anchor = '''local resolved committed_base
    if ! resolved="$(worker_output_gate_resolve_base "$repo_root")"; then
      # worker_output_gate_resolve_base already printed the per-attempt
      # trail and the aggregate reason to stderr.
      rm -f "$files_file"
      return 2
    fi
    committed_base="${resolved#* }"'''
if src.count(anchor) != 1:
    sys.exit("mutation anchor must match exactly once -- zero-match or ambiguous")
mutated = '''local committed_base
    if ! committed_base="$(git -C "$repo_root" merge-base origin/main HEAD 2>/dev/null)"; then
      printf 'worker_output_gate_error reason=committed_range_unresolved base=origin/main head=HEAD\\n' >&2
      rm -f "$files_file"
      return 2
    fi'''
open(path, "w").write(src.replace(anchor, mutated, 1))
PY
if [[ $? -ne 0 ]]; then
  fail "mutation: production anchor missing" "zero-match"
else
  out_red="$(bash "$GATE" "$R2" --from-git-diff HEAD 2>&1)"; rc_red=$?
  if [[ $rc_red -eq 2 ]] && printf '%s' "$out_red" | grep -q 'worker_output_gate_error reason=committed_range_unresolved base=origin/main head=HEAD'; then
    printf 'RED control: mutated gate reverts to unconditional origin/main-only refusal on a no-remote repo with a resolvable local base (rc=%s)\n' "$rc_red"
    pass "(red) MUTATION KILLED: reverting the fix reproduces the unconditional refusal on case2"
  else
    fail "(red) mutation did not reproduce the original unconditional refusal" "rc=$rc_red out=$out_red"
  fi
fi
restore_production_gate
GATE_BACKUP=""
out_green="$(bash "$GATE" "$R2" --from-git-diff HEAD 2>&1)"; rc_green=$?
if [[ $rc_green -eq 1 ]] && printf '%s' "$out_green" | grep -q 'worker_output_gate_reject file=broken.sh tool=bash-n'; then
  pass "(green) restored production gate resolves the local base again on case2"
else
  fail "(green) restored production gate did not resolve local base" "rc=$rc_green out=$out_green"
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
