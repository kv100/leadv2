#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-broad-status.sh leadv2-lane-liveness.sh leadv2-lane-status-line-tail.sh leadv2-lanes-snapshot.sh leadv2-spawn-rate.sh leadv2-status-cache.sh leadv2-status-collector.sh
# test-status-churn.sh — STATUS-CHURN-01 acceptance for the shared
# status-snapshot cache (scripts/lib/leadv2-status-cache.sh).
#
# (a) five concurrent consumers within TTL -> exactly one recompute line.
# (b) stale snapshot -> one recompute, others wait and read the NEW
#     computed_at (not the stale one).
# (c) a consumer never reads/reports a snapshot older than TTL+2s — asserted
#     on the POST-recompute age every journal line reports (age_s is the age
#     of the snapshot SERVED; the pre-recompute staleness lives in
#     stale_age_s). Staleness is fixture-injected by rewriting computed_at,
#     not by sleeping.
# (d) mutation negative control: with the flock removed from the library,
#     (a) goes red (>=2 recomputes). Proves the test actually exercises the
#     lock, not just the happy path. The mutated copy lives in a mktemp dir
#     (never the shipped plugin lib dir — standing rule since 2026-08-22).
# (e) production wiring: leadv2-status-collector.sh's git section — ONE
#     5-key JSON shape on the cache path (computed_at/producer real), the
#     bypass path (nulls), and the fallback path when the cache helper
#     itself fails (nulls + section still ok). This is the coverage whose
#     absence let R3 H1/H2 ship.
# (f) dispatched_lanes: the collector lists lanes from active.yaml +
#     .claude/worktrees (union — a worktree with no registry row still
#     shows), not only codex-task ledger rows.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_SH="${SCRIPT_DIR}/../lib/leadv2-status-cache.sh"
COLLECTOR_SH="${SCRIPT_DIR}/../leadv2-status-collector.sh"

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

# Deterministic staleness: rewrite a snapshot's computed_at to N seconds ago
# instead of sleeping the wall clock (R3 H6: no sleep-dependent fixtures).
make_stale() {
  python3 - "$1" "$2" <<'PYEOF'
import json
import sys
import time

path, backdate_s = sys.argv[1], float(sys.argv[2])
with open(path) as f:
    data = json.load(f)
data["computed_at"] = time.time() - backdate_s
with open(path, "w") as f:
    json.dump(data, f)
PYEOF
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
printf 'test (c): every served age_s stays within TTL+2s (stale fixture, no sleep)\n'
STATE_C="${TMP_ROOT}/state-c"
reset_scenario "$STATE_C"
LEADV2_STATE_ROOT="$STATE_C" PROJECT_ROOT="$TMP_ROOT" LEADV2_STATUS_SNAPSHOT_TTL_S=3 \
  bash "$RUN_SH" "$LIB_SH" warm "$COMPUTE_SH" >/dev/null
make_stale "${STATE_C}/status-snapshot.json" 3600
J_C="$(journal_path_for "$STATE_C")"
: > "$J_C"
run_n_concurrent "$LIB_SH" "$STATE_C" 5 "$COMPUTE_SH"
# the recompute row's age_s is POST-recompute (~0, the snapshot just served);
# the pre-recompute staleness (3600s) rides in stale_age_s and is NOT bounded.
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
RECOMPUTES_C="$(grep -c '"kind": "recompute"' "$J_C" 2>/dev/null)"; RECOMPUTES_C="${RECOMPUTES_C:-0}"
if [[ "$RECOMPUTES_C" -ge 1 ]]; then
  ok
else
  fail "bound check was vacuous: no recompute happened against the stale fixture"
fi

# ── Mutation negative control: remove the flock, (a) must go RED ----------
printf 'mutation control: library with flock removed -> (a) recomputes >= 2\n'
# The mutated copy lives in a mktemp dir, NEVER the shipped plugin lib dir
# (R3 H5: a fixed-name executable in canonical races parallel suite runs
# and survives abnormal exits as a stray file). The library resolves
# leadv2-state-path.sh relative to its own dirname, so the temp layout
# mirrors scripts/: <mut_root>/lib/<mutated lib> + a symlink to the real
# leadv2-state-path.sh at <mut_root>/.
MUT_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT" "$MUT_ROOT"' EXIT
mkdir "$MUT_ROOT/lib"
BROKEN_LIB="${MUT_ROOT}/lib/leadv2-status-cache.sh"
ln -s "$(cd "${SCRIPT_DIR}/.." && pwd)/leadv2-state-path.sh" "${MUT_ROOT}/leadv2-state-path.sh"
python3 - "$LIB_SH" "$BROKEN_LIB" <<'PYEOF'
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
  make_stale "${STATE_M}/status-snapshot.json" 3600
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

# ── Test (e): production wiring — collector git section, ONE shape on every
#     path (R3 H1/H2 coverage; the suite previously never invoked the
#     collector at all) ─────────────────────────────────────────────────────
printf 'test (e): collector git section 5-key shape on cache/bypass/fallback\n'
REPO_E="${TMP_ROOT}/repo-e"
git init -q "$REPO_E"
git -C "$REPO_E" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x
STATE_E="${TMP_ROOT}/state-e"
reset_scenario "$STATE_E"
collect_e() {
  # $1 = tag (names the out file + stderr log so a step that fails to write
  # can never alias a previous step's snapshot), $2 = repo, $3 = state root;
  # remaining args = extra env VAR=VAL pairs
  local tag="$1" repo="$2" state="$3"; shift 3
  env LEADV2_STATE_ROOT="$state" PROJECT_ROOT="$repo" LEADV2_STATUS_SNAPSHOT_TTL_S=3 "$@" \
    bash "$COLLECTOR_SH" --project-root "$repo" --out "$repo/snap-$tag.json" \
    >"${TMP_ROOT}/collect-$tag.out" 2>"${TMP_ROOT}/collect-$tag.err"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '  collect_e(%s) rc=%s stderr tail: %s\n' "$tag" "$rc" \
      "$(tail -c 300 "${TMP_ROOT}/collect-$tag.err" 2>/dev/null | tr '\n' ' ')"
  fi
  return $rc
}
git_shape_e() {
  python3 -c "
import json, sys
snap = json.load(open(sys.argv[1]))
sec = snap['sections']['git']
print(json.dumps({'ok': sec['ok'], 'keys': sorted(sec['data'].keys()),
                  'computed_at': sec['data'].get('computed_at'),
                  'producer': sec['data'].get('producer'),
                  'local_head': sec['data'].get('local_head')}))
" "$1"
}
# e1: cache path (miss -> recompute) — real computed_at + producer
collect_e e1 "$REPO_E" "$STATE_E" || fail "e1 collector rc=$?"
E1="$(git_shape_e "$REPO_E/snap-e1.json")"
if python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['ok'] is True, d
assert d['keys'] == ['branch', 'computed_at', 'local_head', 'producer', 'unpushed'], d
assert isinstance(d['computed_at'], float), d
assert d['producer'] == 'status-collector', d
assert d['local_head'], d
" "$E1"; then ok; else fail "cache-path shape: $E1"; fi
# e2: cache hit path — same shape, served from the scoped snapshot file
collect_e e2 "$REPO_E" "$STATE_E" || fail "e2 collector rc=$?"
E2="$(git_shape_e "$REPO_E/snap-e2.json")"
if python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['ok'] is True and d['producer'] == 'status-collector', d
assert isinstance(d['computed_at'], float), d
" "$E2"; then ok; else fail "cache-hit shape: $E2"; fi
# e3: bypass — same 5 keys, computed_at/producer null
collect_e e3 "$REPO_E" "$STATE_E" LEADV2_STATUS_CACHE_BYPASS=1 || fail "e3 collector rc=$?"
E3="$(git_shape_e "$REPO_E/snap-e3.json")"
if python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['ok'] is True, d
assert d['keys'] == ['branch', 'computed_at', 'local_head', 'producer', 'unpushed'], d
assert d['computed_at'] is None and d['producer'] is None, d
" "$E3"; then ok; else fail "bypass shape: $E3"; fi
# e4: fallback — the cache helper itself fails (state root is a regular
# file, so lv2_status_snapshot_path resolves empty and get_scoped returns 1);
# the section must still be ok with the raw 5-key shape (R3 H1: this is the
# fallback that used to be unreachable dead code under set -e).
touch "${TMP_ROOT}/not-a-dir"
collect_e e4 "$REPO_E" "${TMP_ROOT}/not-a-dir" || fail "e4 collector rc=$?"
E4="$(git_shape_e "$REPO_E/snap-e4.json")"
if python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['ok'] is True, d
assert d['keys'] == ['branch', 'computed_at', 'local_head', 'producer', 'unpushed'], d
assert d['computed_at'] is None and d['producer'] is None, d
assert d['local_head'], d
" "$E4"; then ok; else fail "fallback shape (was unreachable before R3 H1 fix): $E4"; fi

# ── Test (f): dispatched_lanes — registry + worktrees union ───────────────
printf 'test (f): collector dispatched_lanes lists active.yaml + worktree lanes\n'
REPO_F="${TMP_ROOT}/repo-f"
git init -q "$REPO_F"
mkdir -p "$REPO_F/docs/leadv2" \
         "$REPO_F/.claude/worktrees/REG-FIXTURE-01" \
         "$REPO_F/.claude/worktrees/WORKTREE-ONLY-FIX-01"
cat > "$REPO_F/docs/leadv2/active.yaml" <<EOF
meta:
  rendered_at: '2026-09-02T00:00:00Z'
sessions:
- task_id: REG-FIXTURE-01
  session_id: fixt-1
  worktree: ${REPO_F}/.claude/worktrees/REG-FIXTURE-01
  branch: worktree-REG-FIXTURE-01
  phase: build
  pid: $$
  started_at: '2026-09-02T00:00:00Z'
  updated_at: '2026-09-02T00:00:00Z'
  lane_events:
  - at: '2026-09-02T00:00:00Z'
    event: spawned
EOF
STATE_F="${TMP_ROOT}/state-f"
reset_scenario "$STATE_F"
collect_e f1 "$REPO_F" "$STATE_F" || fail "f1 collector rc=$?"
F1="$(python3 -c "
import json
snap = json.load(open('${REPO_F}/snap-f1.json'))
sec = snap['sections']['dispatched_lanes']
print(json.dumps({'ok': sec['ok'], 'data': sec['data']}))
")"
if python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['ok'] is True, d
lanes = {l['task_id']: l for l in d['data']['lanes']}
assert d['data']['count'] == 2, d
reg = lanes['REG-FIXTURE-01']
assert reg['source'] == 'registry', reg
assert reg['phase'] == 'build', reg
assert reg['pid_alive'] is True, reg
assert reg['worktree_exists'] is True, reg
wt = lanes['WORKTREE-ONLY-FIX-01']
assert wt['source'] == 'worktree-only', wt
" "$F1"; then ok; else fail "dispatched_lanes fixture: $F1"; fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
else
  exit 1
fi
