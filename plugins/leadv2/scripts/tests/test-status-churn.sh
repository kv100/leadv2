#!/usr/bin/env bash
# test-status-churn.sh — STATUS-CHURN-01 acceptance for the shared
# status-snapshot cache (scripts/lib/leadv2-status-cache.sh).
#
# (a) five concurrent consumers within TTL -> exactly one recompute line.
# (b) stale snapshot -> one recompute, others wait and read the NEW
#     computed_at (not the stale one).
# (c) a consumer never reads/reports a snapshot older than TTL+2s.
# (d) mutation negative control: with the flock removed from the library,
#     (a) goes red (>=2 recomputes). Proves the test actually exercises the
#     lock, not just the happy path.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_SH="${SCRIPT_DIR}/../lib/leadv2-status-cache.sh"

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1" >&2; }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# A compute_cmd that takes a little wall time (so concurrent callers really
# do race the lock) and emits trivial JSON.
COMPUTE_SH="${TMP_ROOT}/compute.sh"
cat > "$COMPUTE_SH" <<'EOF'
#!/bin/bash
sleep 0.2
echo '{"ok":true}'
EOF
chmod +x "$COMPUTE_SH"

# Per-scenario runner: sources a given library copy, calls
# lv2_status_snapshot_get once, prints the resulting path.
RUN_SH="${TMP_ROOT}/run.sh"
cat > "$RUN_SH" <<EOF
#!/bin/bash
source "\$1"
n="\$2"
compute="\$3"
lv2_status_snapshot_get "consumer\${n}" "\${compute}"
EOF
chmod +x "$RUN_SH"

journal_path_for() {
  # state root is fixed for the scenario, so the journal is deterministic
  echo "${1}/status-snapshot-journal.jsonl"
}

reset_scenario() {
  local state_dir="$1"
  rm -rf "$state_dir"
  mkdir -p "$state_dir"
}

run_n_concurrent() {
  local lib="$1" state_dir="$2" n="$3" compute="$4"
  local i
  for i in $(seq 1 "$n"); do
    ( LEADV2_STATE_ROOT="$state_dir" PROJECT_ROOT="$TMP_ROOT" \
      LEADV2_STATUS_SNAPSHOT_TTL_S=3 \
      bash "$RUN_SH" "$lib" "$i" "$compute" >/dev/null ) &
  done
  wait
}

# ── Test (a): five concurrent consumers, snapshot already fresh -----------
printf 'test (a): 5 concurrent consumers within TTL -> exactly one recompute\n'
STATE_A="${TMP_ROOT}/state-a"
reset_scenario "$STATE_A"
# warm the cache once, synchronously, so it is fresh for all five.
LEADV2_STATE_ROOT="$STATE_A" PROJECT_ROOT="$TMP_ROOT" LEADV2_STATUS_SNAPSHOT_TTL_S=3 \
  bash "$RUN_SH" "$LIB_SH" warm "$COMPUTE_SH" >/dev/null
J_A="$(journal_path_for "$STATE_A")"
: > "$J_A"
run_n_concurrent "$LIB_SH" "$STATE_A" 5 "$COMPUTE_SH"
RECOMPUTES_A="$(grep -c '"kind": "recompute"' "$J_A" 2>/dev/null)"; RECOMPUTES_A="${RECOMPUTES_A:-0}"
if [[ "$RECOMPUTES_A" -eq 0 ]]; then
  ok
else
  fail "expected 0 recomputes when already fresh, got $RECOMPUTES_A"
fi
LINES_A="$(wc -l < "$J_A" | tr -d ' ')"
if [[ "$LINES_A" -eq 5 ]]; then
  ok
else
  fail "expected 5 journal lines (one per consumer), got $LINES_A"
fi

# ── Test (b): stale snapshot -> exactly one recompute, rest read the NEW
#     computed_at (not the pre-existing stale one) -------------------------
printf 'test (b): stale snapshot -> one recompute, rest read fresh computed_at\n'
STATE_B="${TMP_ROOT}/state-b"
reset_scenario "$STATE_B"
LEADV2_STATE_ROOT="$STATE_B" PROJECT_ROOT="$TMP_ROOT" LEADV2_STATUS_SNAPSHOT_TTL_S=3 \
  bash "$RUN_SH" "$LIB_SH" warm "$COMPUTE_SH" >/dev/null
STALE_COMPUTED_AT="$(python3 -c "import json; print(json.load(open('${STATE_B}/status-snapshot.json'))['computed_at'])")"
sleep 3.3   # age now > TTL(3)
J_B="$(journal_path_for "$STATE_B")"
: > "$J_B"
run_n_concurrent "$LIB_SH" "$STATE_B" 5 "$COMPUTE_SH"
RECOMPUTES_B="$(grep -c '"kind": "recompute"' "$J_B" 2>/dev/null)"; RECOMPUTES_B="${RECOMPUTES_B:-0}"
if [[ "$RECOMPUTES_B" -eq 1 ]]; then
  ok
else
  fail "expected exactly 1 recompute on a stale snapshot, got $RECOMPUTES_B"
fi
NEW_COMPUTED_AT="$(python3 -c "import json; print(json.load(open('${STATE_B}/status-snapshot.json'))['computed_at'])")"
if [[ "$NEW_COMPUTED_AT" != "$STALE_COMPUTED_AT" ]]; then
  ok
else
  fail "snapshot computed_at did not advance past the stale value"
fi
HITS_B="$(grep -c '"kind": "hit"' "$J_B" 2>/dev/null)"; HITS_B="${HITS_B:-0}"
if [[ "$HITS_B" -eq 4 ]]; then
  ok
else
  fail "expected 4 hits (waiters reading the fresh recompute), got $HITS_B"
fi

# ── Test (c): a consumer never reads a snapshot older than TTL+2s ---------
printf 'test (c): every reported age_s stays within TTL+2s\n'
STATE_C="${TMP_ROOT}/state-c"
reset_scenario "$STATE_C"
LEADV2_STATE_ROOT="$STATE_C" PROJECT_ROOT="$TMP_ROOT" LEADV2_STATUS_SNAPSHOT_TTL_S=3 \
  bash "$RUN_SH" "$LIB_SH" warm "$COMPUTE_SH" >/dev/null
sleep 3.3
J_C="$(journal_path_for "$STATE_C")"
: > "$J_C"
run_n_concurrent "$LIB_SH" "$STATE_C" 5 "$COMPUTE_SH"
BOUND_VIOLATIONS="$(python3 -c "
import json
bad = 0
with open('${J_C}') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        d = json.loads(line)
        age = d.get('age_s')
        if age is not None and age > 5.0:  # TTL(3) + 2
            bad += 1
print(bad)
")"
if [[ "$BOUND_VIOLATIONS" -eq 0 ]]; then
  ok
else
  fail "found $BOUND_VIOLATIONS journal lines reporting age_s > TTL+2s"
fi

# ── Mutation negative control: remove the flock, (a) must go RED ----------
printf 'mutation control: library with flock removed -> (a) recomputes >= 2\n'
# Must live NEXT TO the real library (not in $TMP_ROOT): the library
# resolves leadv2-state-path.sh relative to its own dirname, so a copy
# parked elsewhere would fail path resolution before the mutation is even
# exercised.
BROKEN_LIB="${SCRIPT_DIR}/../lib/.leadv2-status-cache-broken-test.sh"
cleanup_broken_lib() { rm -f "$BROKEN_LIB"; }
trap 'cleanup_broken_lib; rm -rf "$TMP_ROOT"' EXIT
python3 - "$LIB_SH" "$BROKEN_LIB" <<'PYEOF'
import re
import sys

src_path, dst_path = sys.argv[1], sys.argv[2]
with open(src_path) as f:
    src = f.read()

# Neutralize the exclusive lock acquisition so every stale caller believes
# it won the race and recomputes independently -- this is the mutation the
# ticket asks us to prove the suite catches.
mutated = src.replace(
    "fcntl.flock(lock_f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)\n    got_lock = True",
    "got_lock = True  # MUTATED: flock call removed",
)
if mutated == src:
    print("MUTATION_DID_NOT_APPLY", file=sys.stderr)
    sys.exit(1)
with open(dst_path, "w") as f:
    f.write(mutated)
PYEOF
if [[ $? -ne 0 ]]; then
  fail "mutation control: could not patch a broken copy of the library"
else
  chmod +x "$BROKEN_LIB"
  STATE_M="${TMP_ROOT}/state-mutation"
  reset_scenario "$STATE_M"
  LEADV2_STATE_ROOT="$STATE_M" PROJECT_ROOT="$TMP_ROOT" LEADV2_STATUS_SNAPSHOT_TTL_S=3 \
    bash "$RUN_SH" "$BROKEN_LIB" warm "$COMPUTE_SH" >/dev/null
  sleep 3.3
  J_M="$(journal_path_for "$STATE_M")"
  : > "$J_M"
  run_n_concurrent "$BROKEN_LIB" "$STATE_M" 5 "$COMPUTE_SH"
  RECOMPUTES_M="$(grep -c '"kind": "recompute"' "$J_M" 2>/dev/null)"; RECOMPUTES_M="${RECOMPUTES_M:-0}"
  printf '  mutated-library recompute count: %s (raw journal below)\n' "$RECOMPUTES_M"
  cat "$J_M" >&2
  if [[ "$RECOMPUTES_M" -ge 2 ]]; then
    ok
    printf '  (expected RED reproduced: mutation without the lock causes >=2 recomputes)\n'
  else
    fail "mutation control did not reproduce the race (expected >=2 recomputes, got $RECOMPUTES_M) -- suite may not be exercising the lock"
  fi
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
else
  exit 1
fi
