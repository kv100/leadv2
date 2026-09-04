#!/usr/bin/env bash
# WORKER-STREAM-IS-OVERWRITTEN-BY-THE-NEXT-ATTEMPT-01 — attempt-scoped worker
# streams. The stream file used to be keyed by TASK_ID alone, so re-dispatching
# the same lane re-derived the SAME filename and the second `claude` process's
# truncating redirect destroyed the first attempt's transcript (2026-09-03:
# five workers believed dead, four re-dispatches, four streams lost before the
# investigation could read them). This suite proves the fix end to end:
#
#   A1  two --wait dispatches with the IDENTICAL --task-id produce two
#       distinct immutable per-attempt stream files whose contents differ, and
#       the flat <role>.stream.jsonl is a symlink newest-pointer resolving to
#       attempt #2 (every existing flat-literal/glob readers keep working
#       unmodified). This is also mutation-control #5's fixture shape: fake
#       `claude` binary, real launcher logic, launcher exit codes checked
#       explicitly and synchronously before any filesystem assertion.
#   A2  the newest-pointer exists and resolves after the FIRST attempt too
#       (repoint is unconditional, never lags).
#   A3  detached arm: each attempt writes its own
#       <role>.<attempt-id>.cost-pending.yaml marker; two pending attempts'
#       markers coexist (the flat name would overwrite attempt #1's), and
#       each marker records its own attempts/<id> stream path — the exact
#       path leadv2-cost-flush.sh flushes from marker content.
#   B1  leadv2-budget-check.sh's fallback token sum counts ALL attempts
#       (old-shape flat regular file + tests, every attempts/* file) and does NOT
#       double-count the flat newest-pointer against its own target.
#
# Containment (TEST-DESTROYS-PRODUCTION-SCRIPT-01 pattern): the whole scripts
# tree is copied to a tmp plugin dir and every case runs THE COPY; an md5
# tripwire proves the real production files were never touched. The copy for
# the detached marker case additionally no-ops the two `rm -f MARKER_FILE`
# cleanup sites — both cleanup waiters cannot `wait` across the setsid/
# subshell boundary in any case, so in production the marker window is
# milliseconds and a coexistence assertion would be racy; neutralizing the
# rm in the test copy only makes the marker observable without changing the
# naming contract under test. Production files are never modified.
# Bash 3.2-safe throughout (repo standing decision: no Bash 4+ features).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

tmp="$(lv2_mktemp_dir stream-attempt-isolation)"

_lv2_md5() { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}'; }
REAL_SUBSESSION="${REAL_PLUGIN_DIR}/scripts/claude-subsession.sh"
REAL_BUDGET="${REAL_PLUGIN_DIR}/scripts/leadv2-budget-check.sh"
MD5_BEFORE="$(_lv2_md5 "$REAL_SUBSESSION")$(_lv2_md5 "$REAL_BUDGET")"
lv2_tripwire() {
  local after; after="$(_lv2_md5 "$REAL_SUBSESSION")$(_lv2_md5 "$REAL_BUDGET")"
  if [[ "$after" != "$MD5_BEFORE" ]]; then
    printf '[TEST-SAFETY] FATAL: test mutated a production script\n' >&2
    exit 91
  fi
}
trap 'lv2_tripwire; rm -rf "$tmp"' EXIT

# Copy of the plugin scripts tree the cases actually run.
PLUGIN_DIR="$tmp/plugin"
mkdir -p "$PLUGIN_DIR"
cp -a "${REAL_PLUGIN_DIR}/scripts" "$PLUGIN_DIR/"
SUBSESSION="$PLUGIN_DIR/scripts/claude-subsession.sh"
BUDGET="$PLUGIN_DIR/scripts/leadv2-budget-check.sh"

# TEST-ONLY (copy, never production): keep pending-cost markers observable by
# no-oping both cleanup rm sites (setsid waiter + inline waiter).
sed -i '' "s|rm -f '\$MARKER_FILE'|: # TEST-ONLY marker kept for assertion|" "$SUBSESSION"
sed -i '' 's|rm -f "$MARKER_FILE"|: # TEST-ONLY marker kept for assertion|' "$SUBSESSION"
if ! grep -q "TEST-ONLY marker kept" "$SUBSESSION" 2>/dev/null; then
  echo "FATAL: test-only sed did not apply" >&2
  exit 90
fi

pass=0; fail=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; fail=$((fail+1)); }
check() { # <label> <0-or-1>
  if [[ "$2" == "0" ]]; then ok "$1"; else bad "$1"; fi
}

FX_N=0
new_fixture() { # -> FIXTURE_ROOT / HANDOFF / BIN
  FX_N=$((FX_N+1))
  FIXTURE_ROOT="$tmp/fx$FX_N"
  HANDOFF="$FIXTURE_ROOT/docs/handoff/dispatch-attfix"
  BIN="$tmp/bin$FX_N"
  mkdir -p "$FIXTURE_ROOT/.claude/agents" "$HANDOFF" "$BIN"
  printf -- '---\nname: developer\nmodel: sonnet\n---\nYou are a test developer role body.\n' \
    > "$FIXTURE_ROOT/.claude/agents/developer.md"
  printf 'Test mission body.\n' > "$FIXTURE_ROOT/mission.md"
}

# Fake `claude` one level below the function under claim: emits a line
# embedding its own pid/nonce (so two invocations are trivially
# distinguishable) plus one valid usage event for the cost parser.
make_fake_claude() { # $1=bin-dir $2=sleep-secs
  cat > "$1/claude" <<SH
#!/usr/bin/env bash
sleep "$2"
printf "LV2-FAKE-CLAUDE-MARKER pid=\$\$ nonce=\$RANDOM\n"
printf '{"type":"assistant","message":{"usage":{"input_tokens":11,"output_tokens":7}}}\n'
SH
  chmod +x "$1/claude"
}

run_wait() { # runs the launcher synchronously (--wait), propagates its rc
  ( cd "$FIXTURE_ROOT" && PROJECT_ROOT="$FIXTURE_ROOT" PATH="$BIN:$PATH" \
      bash "$SUBSESSION" --role developer --model sonnet \
        --task-id dispatch-attfix --mission-file "$FIXTURE_ROOT/mission.md" --wait )
}

precreate_deliverables() {
  # Pre-created so the --wait wrapper exits 0 without a real claude run: the
  # two-file protocol needs DELIVERABLE_COMPLETE in .full.md plus .summary.md.
  printf '## deliverable\nDELIVERABLE_COMPLETE\n' > "$HANDOFF/developer.full.md"
  printf '%s\n' "Summary of the test deliverable padded well past fifty words so the empty-session detector stays quiet; this filler sentence exists purely to lift the word count beyond the fifty word threshold without meaning anything at all, which is completely fine for a throwaway fixture like this one." \
    > "$HANDOFF/developer.summary.md"
}

# ---------------------------------------------------------------------------
# A2 — pointer exists after the FIRST attempt (repoint is unconditional)
# ---------------------------------------------------------------------------
new_fixture
make_fake_claude "$BIN" 0
precreate_deliverables
rc_a2=0
run_wait >"$tmp/a2.out" 2>"$tmp/a2.err" || rc_a2=$?
check "A2: launcher exits 0 on first attempt (rc=$rc_a2)" "$([[ "$rc_a2" -eq 0 ]]; echo $?)"
n_a2="$(ls -1 "$HANDOFF/attempts" 2>/dev/null | wc -l | tr -d ' ' || true)"
check "A2: exactly one attempt dir exists (got $n_a2)" "$([[ "$n_a2" -eq 1 ]]; echo $?)"
a2_file="$HANDOFF/attempts/$(ls "$HANDOFF/attempts" | head -1)/developer.stream.jsonl"
check "A2: attempt stream is a regular file (not a symlink)" "$([[ -f "$a2_file" && ! -L "$a2_file" ]]; echo $?)"
check "A2: flat newest-pointer is a symlink" "$([[ -L "$HANDOFF/developer.stream.jsonl" ]]; echo $?)"
if [[ "$(readlink "$HANDOFF/developer.stream.jsonl" 2>/dev/null)" == "$a2_file" ]]; then
  ok "A2: pointer resolves to attempt #1's real file"
else
  bad "A2: pointer resolves to attempt #1's real file (got: $(readlink "$HANDOFF/developer.stream.jsonl" 2>/dev/null))"
fi
check "A2: setup self-check — fake claude marker in stream" \
  "$(grep -q 'LV2-FAKE-CLAUDE-MARKER' "$a2_file" 2>/dev/null; echo $?)"

# ---------------------------------------------------------------------------
# A1 — the defect: two dispatches, IDENTICAL task-id, both attempts survive
# (control #5 fixture shape)
# ---------------------------------------------------------------------------
new_fixture
make_fake_claude "$BIN" 0
precreate_deliverables
rc1=0; rc2=0
run_wait >"$tmp/a1.out1" 2>"$tmp/a1.err1" || rc1=$?
before="$(ls -1 "$HANDOFF/attempts" 2>/dev/null | sort || true)"
run_wait >"$tmp/a1.out2" 2>"$tmp/a1.err2" || rc2=$?
after="$(ls -1 "$HANDOFF/attempts" 2>/dev/null | sort || true)"
# Launcher exit codes FIRST (a fixture that cannot tell "launcher failed" from
# "mutation worked" proves nothing) — synchronous, never discarded.
check "A1: launcher attempt#1 exits 0 (rc=$rc1)" "$([[ "$rc1" -eq 0 ]]; echo $?)"
check "A1: launcher attempt#2 exits 0 (rc=$rc2)" "$([[ "$rc2" -eq 0 ]]; echo $?)"
n_att="$(ls -1 "$HANDOFF/attempts" 2>/dev/null | wc -l | tr -d ' ' || true)"
check "A1: setup self-check — fake claude ran twice (2 attempt dirs, got $n_att)" \
  "$([[ "$n_att" -eq 2 ]]; echo $?)"
new_id="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -1)"
first_id="$(ls "$HANDOFF/attempts" | grep -v "^${new_id}$" | head -1 || true)"
f1="$HANDOFF/attempts/$first_id/developer.stream.jsonl"
f2="$HANDOFF/attempts/$new_id/developer.stream.jsonl"
check "A1: attempt#1 real stream file exists" "$([[ -f "$f1" && ! -L "$f1" ]]; echo $?)"
check "A1: attempt#2 real stream file exists" "$([[ -f "$f2" && ! -L "$f2" ]]; echo $?)"
if diff -q "$f1" "$f2" >/dev/null 2>&1; then
  bad "A1: two attempts' streams DIFFER (no truncation)"
else
  ok "A1: two attempts' streams DIFFER (no truncation)"
fi
check "A1: flat name is a symlink (pointer, not the file itself)" \
  "$([[ -L "$HANDOFF/developer.stream.jsonl" ]]; echo $?)"
if [[ "$(readlink "$HANDOFF/developer.stream.jsonl" 2>/dev/null)" == "$f2" ]]; then
  ok "A1: pointer resolves to attempt #2 (newest), not #1"
else
  bad "A1: pointer resolves to attempt #2 (newest), not #1 (got: $(readlink "$HANDOFF/developer.stream.jsonl" 2>/dev/null))"
fi
both_markers="$(grep -q 'LV2-FAKE-CLAUDE-MARKER' "$f1" 2>/dev/null && grep -q 'LV2-FAKE-CLAUDE-MARKER' "$f2" 2>/dev/null; echo $?)"
check "A1: setup self-check — fake marker in BOTH streams" "$both_markers"

# ---------------------------------------------------------------------------
# A3 — detached arm: per-attempt cost markers, two pending attempts coexist
# ---------------------------------------------------------------------------
new_fixture
make_fake_claude "$BIN" 4   # slow fake claude keeps the pending window open
det_out1="$tmp/a3.out1"; det_out2="$tmp/a3.out2"
PROJECT_ROOT="$FIXTURE_ROOT" PATH="$BIN:$PATH" \
  bash "$SUBSESSION" --role developer --model sonnet \
    --task-id dispatch-attfix --mission-file "$FIXTURE_ROOT/mission.md" \
    >"$det_out1" 2>&1 &
det_wrap1=$!
# Deterministic observation: poll (bounded) for attempt #1's marker BEFORE
# spawning attempt #2 — ordering matters, #2 must not have started yet.
m1=""
for _ in $(seq 1 100); do
  m1="$(ls "$HANDOFF"/*.cost-pending.yaml 2>/dev/null | sed -n '1p' || true)"
  if [[ -n "$m1" ]]; then break; fi
  sleep 0.1
done
check "A3: attempt#1 pending-cost marker appears" "$([[ -n "$m1" && -f "$m1" ]]; echo $?)"
PROJECT_ROOT="$FIXTURE_ROOT" PATH="$BIN:$PATH" \
  bash "$SUBSESSION" --role developer --model sonnet \
    --task-id dispatch-attfix --mission-file "$FIXTURE_ROOT/mission.md" \
    >"$det_out2" 2>&1 &
det_wrap2=$!
for _ in $(seq 1 100); do
  n_m="$(ls -1 "$HANDOFF"/*.cost-pending.yaml 2>/dev/null | wc -l | tr -d ' ' || true)"
  if [[ "${n_m:-0}" -ge 2 ]]; then break; fi
  sleep 0.1
done
m1_now="$(ls "$HANDOFF"/*.cost-pending.yaml 2>/dev/null | sed -n '1p' || true)"
m2_now="$(ls "$HANDOFF"/*.cost-pending.yaml 2>/dev/null | sed -n '2p' || true)"
check "A3: TWO pending-cost markers coexist (attempt#1 not overwritten)" \
  "$([[ -n "$m1_now" && -n "$m2_now" ]]; echo $?)"
check "A3: marker filenames are attempt-scoped (distinct)" \
  "$([[ "$m1_now" != "$m2_now" ]]; echo $?)"
s1="$(grep '^stream_file:' "$m1_now" 2>/dev/null | awk '{print $2}' || true)"
s2="$(grep '^stream_file:' "$m2_now" 2>/dev/null | awk '{print $2}' || true)"
check "A3: marker#1 records its own attempts/<id> stream path" \
  "$([[ "${s1:-}" == "$HANDOFF/attempts/"*"/developer.stream.jsonl" && -f "$s1" ]]; echo $?)"
check "A3: marker#2 records a DIFFERENT attempt's stream path" \
  "$([[ "${s2:-}" == "$HANDOFF/attempts/"*"/developer.stream.jsonl" && -f "$s2" && "$s1" != "$s2" ]]; echo $?)"
# reap the slow fake claudes + wrappers; assertions are already taken
p1="$(sed -n 's/^PID=\([0-9]*\) .*/\1/p' "$det_out1" 2>/dev/null | head -1)"
p2="$(sed -n 's/^PID=\([0-9]*\) .*/\1/p' "$det_out2" 2>/dev/null | head -1)"
[[ -n "$p1" ]] && kill "$p1" 2>/dev/null || true
[[ -n "$p2" ]] && kill "$p2" 2>/dev/null || true
wait "$det_wrap1" "$det_wrap2" 2>/dev/null || true

# ---------------------------------------------------------------------------
# B1 — budget fallback: all attempts summed, newest-pointer not double-counted
# ---------------------------------------------------------------------------
BFX="$tmp/bfx"; BHAND="$BFX/docs/handoff/budget-fixture"
mkdir -p "$BFX/docs/handoff/budget-fixture/attempts/a1" "$BFX/docs/handoff/budget-fixture/attempts/a2"
# old-shape flat REGULAR file: 7+3 = 10
printf '{"usage":{"input_tokens":7,"output_tokens":3}}\n' > "$BHAND/critic.stream.jsonl"
# newest-pointer (symlink) -> attempts/a1: 40+10 = 50
printf '{"usage":{"input_tokens":40,"output_tokens":10}}\n' > "$BHAND/attempts/a1/developer.stream.jsonl"
ln -s attempts/a1/developer.stream.jsonl "$BHAND/developer.stream.jsonl"
# a second attempt: 90+10 = 100
printf '{"message":{"usage":{"input_tokens":90,"output_tokens":10}}}\n' > "$BHAND/attempts/a2/developer.stream.jsonl"
# expected total = 10 + 50 + 100 = 160 (pointer itself never counted)
b_out="$(PROJECT_ROOT="$BFX" bash "$BUDGET" --task-id budget-fixture --class Light 2>&1)" || true
check "B1: fallback sums ALL attempts exactly (spent: 160)" \
  "$(printf '%s' "$b_out" | grep -q 'spent: 160'; echo $?)"
if printf '%s' "$b_out" | grep -q 'spent: 210'; then
  bad "B1: newest-pointer must not be double-counted (found 210)"
else
  ok "B1: newest-pointer must not be double-counted (found 210)"
fi

# ---------------------------------------------------------------------------
printf '\n[TEST] %s: %d passed, %d failed\n' "test-stream-attempt-isolation" "$pass" "$fail"
[[ "$fail" -eq 0 ]]
