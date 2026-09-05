#!/usr/bin/env bash
# REVIEW-SENTINELS-LANGUAGE-01 — what the syntax sentinels undertake to assert.
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: leadv2-builder-selfcheck
#
# THE CLAIM UNDER TEST. `bash-n:foo.sh` / `py_compile:foo.py` read as "this lane wrote
# a file that does not parse". In production the lib is handed TWO different trees --
# diff_root is the lane worktree, project_root is the shared checkout -- and a path can
# be in the lane's diff while being absent from the lane's tree: a deletion, or the old
# side of a rename. The resolver then falls back to project_root and syntax-checks
# MAIN's copy of a file this lane removed, filing the verdict under a bare basename. If
# the lane deleted that file precisely because it was broken, the sentinel names the
# lane for the very thing the lane fixed.
#
# WHAT IS REAL HERE: the production `lv2_selfcheck_run` is sourced and called. Nothing
# is stubbed. Only the two trees are synthetic.
#
# THE FIX IS A NAMING FIX, NOT A DISABLING. The fallback check still runs and still
# fails -- a caller whose diff_root does not carry the files must not silently lose its
# syntax gate. Case (a) is the paired negative that pins this: a broken file that IS in
# the lane's tree must still fail, under the plain unqualified name.
#
# DECLARED NEGATIVE CONTROL (tests/mutations/catalog.yaml): inside the resolve loop,
# `resolved_src="main_copy_not_lane"` becomes `resolved_src="lane"` -- the sentinel goes
# back to claiming main's bytes are the lane's. Kills (b) and (c); leaves (a) and (d)
# green, which is exactly the separator between "the name got more precise" and "the
# sentinel stopped firing".
set -uo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
LIB="${ROOT}/scripts/lib/leadv2-builder-selfcheck.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

LANE="$T/lane"; MAIN="$T/main"
mkdir -p "$LANE/s" "$MAIN/s"

# in the lane and broken -> the lane genuinely owns this one
printf '#!/usr/bin/env bash\nif [ 1 -eq 1 ]; then\n' > "$LANE/s/broken.sh"
# deleted by the lane, still present and broken on main
printf '#!/usr/bin/env bash\nfor x in a b; do\n'      > "$MAIN/s/gone.sh"
# same shape for python
printf 'def f(:\n'                                     > "$MAIN/s/gone.py"
printf 'def g():\n    return 1\n'                      > "$LANE/s/ok.py"

D="$T/d.diff"
{
  for f in s/broken.sh s/gone.sh s/gone.py s/ok.py; do
    printf 'diff --git a/%s b/%s\nindex 1111111..2222222 100644\n--- a/%s\n+++ b/%s\n@@ -1,1 +1,1 @@\n-x\n+y\n' "$f" "$f" "$f" "$f"
  done
} > "$D"

names(){ # -> CSV of failed names from the REAL lib
  local md="$T/out.md"; : > "$md"
  ( set +e
    # shellcheck disable=SC1090
    source "$LIB" >/dev/null 2>&1 || exit 2
    command -v lv2_selfcheck_run >/dev/null 2>&1 || exit 2
    LEADV2_E2E_GATE=0 LEADV2_SCOPE_DISCIPLINE=0 \
      lv2_selfcheck_run "$D" "$LANE" "$MAIN" "$md" "" 2>/dev/null
  ) || true
}
N="$(names)"

# (a) PAIRED NEGATIVE — a broken file that IS the lane's must still fail, plainly named.
# This is the case a "fix" that merely silenced the fallback would also have to keep, and
# it is the one that fails if the sentinel is ever narrowed into muteness.
if [[ "$N" == *"bash-n:broken.sh"* && "$N" != *"bash-n:broken.sh:"* ]]; then
  ok "a broken file inside the lane still fails, under the unqualified name"
else
  bad "a: expected a plain bash-n:broken.sh, got '$N'"
fi

# (b) the fallback still FIRES -- naming it precisely must not silence it.
if [[ "$N" == *"bash-n:gone.sh:main_copy_not_lane"* ]]; then
  ok "main's copy of a file the lane deleted still fails, and says whose bytes they are"
else
  bad "b: expected bash-n:gone.sh:main_copy_not_lane, got '$N'"
fi

# (c) the qualifier lands on the right file, not on every file in the run.
if [[ "$N" != *"broken.sh:main_copy_not_lane"* ]]; then
  ok "the qualifier attaches per file, not to the whole run"
else
  bad "c: the lane's own file was labelled as main's: '$N'"
fi

# (d) python takes the same treatment, and a valid lane file is not made to fail by it.
if [[ "$N" == *"py_compile:gone.py:main_copy_not_lane"* && "$N" != *"py_compile:ok.py"* ]]; then
  ok "py_compile names its root too, and a valid lane file stays green"
else
  bad "d: expected py_compile:gone.py:main_copy_not_lane and no ok.py, got '$N'"
fi

printf '[SYNTAX-SENTINEL-ROOT] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
