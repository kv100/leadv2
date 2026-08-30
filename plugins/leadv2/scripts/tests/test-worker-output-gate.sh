#!/usr/bin/env bash
# FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 — the worker output gate must reject any
# changed *.sh/*.py that does not parse, for EVERY arm, not just freepool.
# Two of the three unusable free-arm results measured 2026-08-30 were a
# syntactically broken hook line (literal \n, unclosed quote) and a
# bash -n-failing test suite committed four times -- both are exactly what
# this gate exists to catch before the result is recorded as done.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GATE="${SCRIPTS_ROOT}/lib/leadv2-worker-output-gate.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wog-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

bash -n "$GATE" || { fail "bash syntax: gate"; exit 1; }
pass "bash syntax: gate"

REPO="$TMP/repo"
mkdir -p "$REPO"

# ── clean *.sh and *.py: gate passes ───────────────────────────────────────
printf '#!/usr/bin/env bash\necho ok\n' > "$REPO/good.sh"
printf 'x = 1\nprint(x)\n' > "$REPO/good.py"
out="$(bash "$GATE" "$REPO" good.sh good.py 2>&1)"; rc=$?
if [[ $rc -eq 0 && -z "$out" ]]; then
  pass "clean sh+py: gate exits 0 with no reject lines"
else
  fail "clean sh+py: expected rc0/no output, got rc=$rc out=$out"
fi

# ── broken *.sh (exact shape of the 2026-08-30 incident: unclosed quote) ──
printf '#!/usr/bin/env bash\necho "unclosed\n' > "$REPO/broken.sh"
out="$(bash "$GATE" "$REPO" broken.sh 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q 'worker_output_gate_reject file=broken.sh tool=bash-n'; then
  pass "broken sh: gate rejects with bash-n error attached (behavioural, real bash -n run)"
else
  fail "broken sh: expected reject, got rc=$rc out=$out"
fi

# ── broken *.py (empty function body -- exact shape of the other incident) ─
printf 'def f():\n    pass\n\ndef g():\n' > "$REPO/broken.py"
out="$(bash "$GATE" "$REPO" broken.py 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q 'worker_output_gate_reject file=broken.py tool=py_compile'; then
  pass "broken py: gate rejects with py_compile error attached"
else
  fail "broken py: expected reject, got rc=$rc out=$out"
fi

# ── non-code file (e.g. *.md) is never checked ─────────────────────────────
printf '# not shell, not python, has "quotes and (parens\n' > "$REPO/notes.md"
out="$(bash "$GATE" "$REPO" notes.md 2>&1)"; rc=$?
if [[ $rc -eq 0 && -z "$out" ]]; then
  pass "non-code file: ignored, gate exits 0"
else
  fail "non-code file: expected pass-through, got rc=$rc out=$out"
fi

# ── --from-git-diff mode: real git repo, staged broken file ───────────────
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@e.com; git -C "$REPO" config user.name t
: > "$REPO/seed"; git -C "$REPO" add seed; git -C "$REPO" commit -qm seed
cp "$REPO/broken.sh" "$REPO/worker-change.sh"
git -C "$REPO" add worker-change.sh
out="$(bash "$GATE" "$REPO" --from-git-diff --cached 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q 'worker_output_gate_reject file=worker-change.sh tool=bash-n'; then
  pass "--from-git-diff: staged broken .sh caught from real git diff output"
else
  fail "--from-git-diff: expected reject, got rc=$rc out=$out"
fi

# ── mutation control: disable the *.sh branch in the PRODUCTION gate file ──
# and prove the exact broken.sh from above now passes (RED), then restore
# and prove it is rejected again (GREEN). Mutates the real committed file
# in place for the duration of this one check only.
MUT_MARK='*.sh)'
if ! grep -qF "$MUT_MARK" "$GATE"; then
  fail "mutation anchor not found in production gate -- cannot prove the control" "zero-match"
else
  cp "$GATE" "$TMP/gate.orig"
  # Replace the *.sh case arm with a no-op arm so a broken .sh is never
  # checked -- the exact regression this gate exists to prevent.
  python3 - "$GATE" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
anchor = '''      *.sh)
        if ! err="$(bash -n "$abspath" 2>&1 1>/dev/null)"; then
          printf 'worker_output_gate_reject file=%s tool=bash-n\\n' "$f"
          printf '%s\\n' "$err"
          rc=1
        fi
        ;;'''
replacement = '''      *.sh)
        :  # MUTATED: sh check disabled
        ;;'''
if anchor not in src:
    sys.exit("mutation anchor not found -- zero-match, hard failure")
open(path, 'w').write(src.replace(anchor, replacement, 1))
PY
  if [[ $? -ne 0 ]]; then
    fail "mutation replace failed -- anchor text drifted" "zero-match"
    cp "$TMP/gate.orig" "$GATE"
  else
    bash -n "$GATE" || fail "mutated gate fails its own bash -n"
    out_red="$(bash "$GATE" "$REPO" broken.sh 2>&1)"; rc_red=$?
    cp "$TMP/gate.orig" "$GATE"
    if [[ $rc_red -eq 0 ]]; then
      pass "(red) mutated gate silently accepts the broken .sh -- control is falsifiable"
    else
      fail "(red) mutation did not flip the outcome" "rc=$rc_red out=$out_red"
    fi
    out_green="$(bash "$GATE" "$REPO" broken.sh 2>&1)"; rc_green=$?
    if [[ $rc_green -ne 0 ]] && printf '%s' "$out_green" | grep -q 'worker_output_gate_reject file=broken.sh tool=bash-n'; then
      pass "(green) restored gate rejects the broken .sh again"
    else
      fail "(green) restore did not bring back the reject" "rc=$rc_green out=$out_green"
    fi
  fi
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
