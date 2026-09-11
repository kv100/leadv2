#!/usr/bin/env bash
# Negative controls for the two attribution safety boundaries.
# run-all-triggers: leadv2-burn-attribute
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../../../.." && pwd)"
SRC="${ROOT}/plugins/leadv2/scripts/leadv2-burn-attribute.py"
TEST="${HERE}/test-burn-attribute.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-nc-burn-attribute.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

make_mutant() { # <needle> <replacement> <out>
  local needle="$1" replacement="$2" out="$3"
  if git -C "$ROOT" ls-files --error-unmatch -- "$out" >/dev/null 2>&1; then
    echo "NC-SETUP-FAIL: refusing to write mock onto tracked file: $out" >&2
    exit 2
  fi
  python3 - "$SRC" "$needle" "$replacement" "$out" <<'PY'
import pathlib, sys
src, needle, replacement, out = map(pathlib.Path, (sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]))
text = src.read_text()
if text.count(str(needle)) != 1:
    raise SystemExit('NC-SETUP-FAIL: mutation pattern missing or ambiguous: ' + str(needle))
pathlib.Path(out).write_text(text.replace(str(needle), str(replacement), 1))
PY
}

# (a) Must not guess from a non-evidence source. The named orphan case must red.
mut_a="$TMP/guess.py"
make_mutant 'attribution.get(row["session_id"], "unknown")' 'attribution.get(row["session_id"], "work")' "$mut_a"
if LEADV2_BURN_ATTRIBUTE_BIN="$mut_a" bash "$TEST" >"$TMP/a.out" 2>&1; then
  echo 'NC-FAIL: case (a) suite stayed green with unknown session guessed as work' >&2; cat "$TMP/a.out"; exit 1
fi
grep -q 'FAIL: missing profile and orphan are unknown' "$TMP/a.out" || { echo 'NC-FAIL: case (a) reddened the wrong case' >&2; cat "$TMP/a.out"; exit 1; }
echo 'NC-PASS: case (a) no-selected-profile fallback guessed account -> named unknown case red'

# (b) Must use the read-only URI. This mutation makes a rw connection reject a chmod 444 DB.
mut_b="$TMP/rw.py"
make_mutant '?mode=ro"' '?mode=rw"  # NC-MUTATION-RW' "$mut_b"
if LEADV2_BURN_ATTRIBUTE_BIN="$mut_b" bash "$TEST" >"$TMP/b.out" 2>&1; then
  echo 'NC-FAIL: case (b) suite stayed green with read-write SQLite mode' >&2; cat "$TMP/b.out"; exit 1
fi
grep -q 'FAIL: read-only DB opens successfully' "$TMP/b.out" || { echo 'NC-FAIL: case (b) reddened the wrong case' >&2; cat "$TMP/b.out"; exit 1; }
echo 'NC-PASS: case (b) read-write SQLite mode -> named read-only case red'
