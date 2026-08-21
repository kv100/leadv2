#!/usr/bin/env bash
# test-core-offline-shards-01.sh — SUITE-SPEED-01 item 3
# Verifies the round-robin shard partition of SUITE_DEFS via
# LEADV2_SUITE_SHARDS_DUMP=1 (lists shard assignments without running suites):
#   - every suite index appears in exactly one shard, for several shard counts
#   - the resolved default shard count is a sane positive integer <= 4
#   - LEADV2_SUITE_SHARDS=1 dump still enumerates the full list (no suite lost)

set -euo pipefail

_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
TEST_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _dir
RUNNER="$TEST_DIR/run-core-offline.sh"

pass=0
fail=0

total="$(LEADV2_SUITE_SHARDS=1 LEADV2_SUITE_SHARDS_DUMP=1 bash "$RUNNER" | wc -l | tr -d ' ')"
echo "[SHARDS-01] total suites in SUITE_DEFS = $total"
if [[ "$total" -gt 0 ]]; then
  pass=$((pass + 1))
else
  echo "[SHARDS-01]   FAILED: no suites enumerated"
  fail=$((fail + 1))
fi

for n in 1 2 3 4 5 7; do
  out="$(LEADV2_SUITE_SHARDS=$n LEADV2_SUITE_SHARDS_DUMP=1 bash "$RUNNER")"
  lines="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
  uniq_idx="$(printf '%s\n' "$out" | grep -oE 'idx=[0-9]+' | sort -u | wc -l | tr -d ' ')"
  bad_shard="$(printf '%s\n' "$out" | grep -oE 'shard=[0-9]+' | sed -E 's/shard=//' \
    | awk -v n="$n" '$1 >= n {print; exit}')"

  if [[ "$lines" -eq "$total" && "$uniq_idx" -eq "$total" && -z "$bad_shard" ]]; then
    echo "[SHARDS-01]   shards=$n: $lines lines, $uniq_idx unique indices, no out-of-range shard ✓"
    pass=$((pass + 1))
  else
    echo "[SHARDS-01]   shards=$n FAILED lines=$lines uniq_idx=$uniq_idx bad_shard=$bad_shard"
    fail=$((fail + 1))
  fi
done

echo "[SHARDS-01] case: default shard count is sane (1..4)"
default_n="$(LEADV2_SUITE_SHARDS_DUMP=1 bash "$RUNNER" | grep -oE 'shard=[0-9]+' \
  | sed -E 's/shard=//' | sort -un | tail -1)"
default_n=$((default_n + 1)) # highest shard index + 1 = shard count actually used
if [[ "$default_n" -ge 1 && "$default_n" -le 4 ]]; then
  echo "[SHARDS-01]   default resolves to $default_n shards ✓"
  pass=$((pass + 1))
else
  echo "[SHARDS-01]   FAILED: default resolved to $default_n shards (expected 1..4)"
  fail=$((fail + 1))
fi

echo "[SHARDS-01] pass=$pass fail=$fail"
(( fail == 0 ))
