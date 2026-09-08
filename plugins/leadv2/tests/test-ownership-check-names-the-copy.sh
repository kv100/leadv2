#!/usr/bin/env bash
# run-all-triggers: plugin-scripts-drift-guard plugin-scripts-drift-guard.sh
# C2-OWNERSHIP-CHECK (E2E-KILLRATE-01): two negative controls, both run, red
# then green —
#   control 1 (the symptom): a planted real copy of a plugin-owned file is
#     reported BY NAME, with the canonical it shadows and a non-zero count.
#     Neutering the REGRESSION|DRIFT arm inside plugin_script_ownership_scan's
#     body must break the symptom assertions (a survived mutation is a FAIL).
#   control 2 (the guard): a copy-free tree passes with checked=N asserted
#     strictly > 0. Mutating the scan's find to examine nothing must break
#     that assertion — a green meaning "I looked at nothing" is the prevented
#     failure (a fresh leadv2 worktree materializes no .claude/scripts at all
#     because the tree is .gitignore'd, so count-blind green is reachable).
# Mutations are applied to a SCRATCH COPY of the guard, never the live file,
# inside the function body, via a patcher that asserts exactly one occurrence
# of its anchor (a drifted anchor must abort, not silently mutate nothing).
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${TESTS_DIR}/../hooks/plugin-scripts-drift-guard.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }
finish() { printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"; [[ "$FAIL" -eq 0 ]]; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/own-check.XXXXXX")"
trap '[[ "${OWNCHK_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"' EXIT

bash -n "$GUARD" || { fail "bash syntax" "$(basename "$GUARD")"; finish; exit 1; }
pass "bash syntax: guard"

# ── fixture: scratch canonical + scratch repos ──────────────────────────────
CANON="$TMP/canonical"; REPO="$TMP/repo"; CLEAN="$TMP/clean-repo"; EMPTY="$TMP/empty-repo"
mkdir -p "$CANON/plugins/leadv2/scripts/sub" "$REPO/.claude/scripts/sub" \
         "$CLEAN/.claude/scripts" "$EMPTY"
# canonical layout mirrors the copy model: same relative path on both sides
for n in alpha gamma; do
  printf '#!/usr/bin/env bash\ncanonical %s\n' "$n" > "$CANON/plugins/leadv2/scripts/leadv2-${n}.sh"
done
printf '#!/usr/bin/env bash\ncanonical beta\n' > "$CANON/plugins/leadv2/scripts/sub/leadv2-beta.sh"
# dirty repo: identical copy + nested diverged copy + correct symlink + native
cp "$CANON/plugins/leadv2/scripts/leadv2-alpha.sh" "$REPO/.claude/scripts/leadv2-alpha.sh"
printf '#!/usr/bin/env bash\nrepo-mutated beta\n' > "$REPO/.claude/scripts/sub/leadv2-beta.sh"
ln -s "$CANON/plugins/leadv2/scripts/leadv2-gamma.sh" "$REPO/.claude/scripts/leadv2-gamma.sh"
printf '#!/usr/bin/env bash\nrepo native\n' > "$REPO/.claude/scripts/repo-native.sh"
# clean repo: two correct symlinks + one repo-native file, zero copies
ln -s "$CANON/plugins/leadv2/scripts/leadv2-alpha.sh" "$CLEAN/.claude/scripts/leadv2-alpha.sh"
ln -s "$CANON/plugins/leadv2/scripts/leadv2-gamma.sh" "$CLEAN/.claude/scripts/leadv2-gamma.sh"
printf '#!/usr/bin/env bash\nrepo native\n' > "$CLEAN/.claude/scripts/repo-native.sh"

OUT=""; RC=0
run_check() { # <guard-file> <repo-dir>
  OUT="$(LEADV2_CANONICAL_ROOT="$CANON" bash "$1" --check "$2" 2>&1)"; RC=$?
}

mutate() { # <src> <dst> <anchor> <replacement> — anchor must occur exactly once
  python3 - "$1" "$2" "$3" "$4" <<'PY' || { fail "mutation patcher" "$3"; exit 1; }
import sys
src, dst, old, new = sys.argv[1:5]
data = open(src).read()
n = data.count(old)
assert n == 1, "anchor occurs %dx (need exactly 1): %r" % (n, old)
open(dst, "w").write(data.replace(old, new))
PY
}

# ── the symptom, green: copies found, named, counted ────────────────────────
run_check "$GUARD" "$REPO"
[[ "$RC" -eq 1 ]] && pass "dirty repo: rc=1" || fail "dirty repo rc" "want 1 got $RC"
grep -qF "COPY: $REPO/.claude/scripts/leadv2-alpha.sh shadows canonical $CANON/plugins/leadv2/scripts/leadv2-alpha.sh (identical," <<<"$OUT" \
  && pass "names identical copy + its canonical" || fail "identical copy not named by path" "$OUT"
grep -qF "COPY: $REPO/.claude/scripts/sub/leadv2-beta.sh shadows canonical $CANON/plugins/leadv2/scripts/sub/leadv2-beta.sh (diverged," <<<"$OUT" \
  && pass "names nested diverged copy + its canonical" || fail "nested copy not named by path" "$OUT"
grep -qE '^checked=4 linked=1 native=1 copies=2$' <<<"$OUT" \
  && pass "tally counted every file (checked=4)" || fail "tally" "$(grep -E '^checked=' <<<"$OUT")"

# ── the guard, green: copy-free tree passes with a real count ───────────────
run_check "$GUARD" "$CLEAN"
[[ "$RC" -eq 0 ]] && pass "clean repo: rc=0" || fail "clean repo rc" "want 0 got $RC"
CK="$(sed -n 's/^checked=\([0-9]*\).*/\1/p' <<<"$OUT")"
[[ -n "$CK" && "$CK" -gt 0 ]] \
  && pass "clean pass carries checked=$CK (> 0)" || fail "clean pass count" "checked='${CK}' in: $OUT"
grep -qE '^checked=3 linked=2 native=1 copies=0$' <<<"$OUT" \
  && pass "clean tally exact" || fail "clean tally" "$OUT"

# ── fail-closed: a missing canonical is never a silent clean ────────────────
OUT="$(LEADV2_CANONICAL_ROOT="$TMP/no-such-canonical" bash "$GUARD" --check "$CLEAN" 2>&1)"; RC=$?
[[ "$RC" -eq 1 && "$OUT" == *"FATAL canonical scripts tree missing"* ]] \
  && pass "missing canonical fails closed" || fail "missing canonical" "rc=$RC out=$OUT"

# ── honest zero: a repo with no .claude/scripts prints checked=0, rc=0 ──────
run_check "$GUARD" "$EMPTY"
[[ "$RC" -eq 0 && "$OUT" == checked=0* ]] \
  && pass "no-tree repo prints honest checked=0" || fail "no-tree repo" "rc=$RC out=$OUT"

# ── control 1: neuter detection inside the scan body → symptom goes red ─────
MUT1="$TMP/guard-mut1.sh"
mutate "$GUARD" "$MUT1" \
  'REGRESSION|DRIFT)
        copies=$((copies + 1))' \
  'REGRESSION|DRIFT)
        :  # C2-MUTATION-1 detection disabled'
run_check "$MUT1" "$REPO"
if [[ "$RC" -eq 1 ]] && grep -qF "shadows canonical" <<<"$OUT"; then
  fail "control 1: mutation SURVIVED (copy still detected with arm neutered)"
else
  pass "control 1 red: neutered detection reports nothing (rc=$RC, no COPY lines)"
fi

# ── control 2: scan examines nothing → clean-tree green must go red ─────────
MUT2="$TMP/guard-mut2.sh"
mutate "$GUARD" "$MUT2" \
  "-name '*.py' \) -print0)" \
  "-name '*.py' \) -false -print0)"
run_check "$MUT2" "$CLEAN"
CKM="$(sed -n 's/^checked=\([0-9]*\).*/\1/p' <<<"$OUT")"
if [[ -n "$CKM" && "$CKM" -gt 0 ]]; then
  fail "control 2: mutation SURVIVED (scan still examined files)"
else
  [[ "$CKM" == "0" ]] \
    && pass "control 2 red: empty scan yields checked=0, failing the >0 assertion" \
    || fail "control 2: mutated scan produced no tally" "$OUT"
fi

finish
