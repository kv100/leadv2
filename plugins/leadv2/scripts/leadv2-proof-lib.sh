#!/usr/bin/env bash
# leadv2-proof-lib.sh — assertion helpers for skill PROOF.sh scripts.
# Sourced by every PROOF.sh; provides assert_* helpers, proof_fail, proof_tmpdir.
#
# Usage (inside a PROOF.sh):
#   source "$LEADV2_PLUGIN_ROOT/scripts/leadv2-proof-lib.sh"
#   tmp=$(proof_tmpdir)
#   assert_eq 1 "$(cat "$tmp/count")" "model called exactly once"

_PROOF_LIB_LOADED=1

# Immediately fail the proof with a message and non-zero exit.
proof_fail() {
  printf '[PROOF-FAIL] %s\n' "$*" >&2
  exit 1
}

# Assert two strings are equal.
assert_eq() {
  local expected="$1" actual="$2" msg="${3:-assert_eq failed}"
  if [[ "$expected" != "$actual" ]]; then
    proof_fail "$msg (expected=<$expected> actual=<$actual>)"
  fi
}

# Assert two strings are NOT equal.
assert_ne() {
  local unexpected="$1" actual="$2" msg="${3:-assert_ne failed}"
  if [[ "$unexpected" == "$actual" ]]; then
    proof_fail "$msg (both=<$actual>)"
  fi
}

# Assert needle appears in haystack.
assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-assert_contains failed}"
  if [[ -z "$needle" ]]; then
    return 0  # empty needle trivially contained
  fi
  if [[ "$haystack" != *"$needle"* ]]; then
    proof_fail "$msg (needle=<$needle> not found in haystack)"
  fi
}

# Assert a pattern appears in a file (grep -E).
assert_file_contains() {
  local file="$1" pattern="$2" msg="${3:-assert_file_contains failed}"
  if [[ ! -f "$file" ]]; then
    proof_fail "$msg (file not found: $file)"
  fi
  if ! grep -qE "$pattern" "$file"; then
    proof_fail "$msg (pattern=<$pattern> not in $file)"
  fi
}

# Create a throwaway temp directory for the proof, export it, and register
# auto-cleanup on exit. Prints the directory path to stdout.
# The directory is also exported as LEADV2_PROOF_TMP for child processes.
proof_tmpdir() {
  local d
  # Portable template (GNU mktemp rejects `-t name` without X's); fall back
  # to the explicit -t form for BSD variants where plain `mktemp -d` needs it.
  d=$(mktemp -d 2>/dev/null || mktemp -d -t leadv2-proof.XXXXXX 2>/dev/null) || true
  if [[ -z "${d:-}" || ! -d "${d:-}" ]]; then
    proof_fail "could not create a temp directory for the proof"
  fi
  export LEADV2_PROOF_TMP="$d"
  # Register cleanup only once
  if [[ -z "${_PROOF_TMP_CLEANUP_REGISTERED:-}" ]]; then
    _PROOF_TMP_CLEANUP_REGISTERED=1
    trap '_proof_tmpdir_cleanup' EXIT INT TERM
  fi
  _PROOF_TMP_DIRS+=("$d")
  printf '%s' "$d"
}

_PROOF_TMP_DIRS=()
_proof_tmpdir_cleanup() {
  local d
  for d in "${_PROOF_TMP_DIRS[@]}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d" 2>/dev/null || true
  done
}
