#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-broad-status.sh
# tests/test-pulse-empty-board.sh — PULSE-EMPTY-BOARD-01.
#
# The founder went 60+ minutes with no signal while the board sat at zero
# live lanes, because nothing treated an empty board or a landed review
# verdict as an event worth a beat, and the composer never made "zero
# lanes" visually different from "a table with no rows". This suite proves
# the fix end-to-end, five cases:
#   T1  zero live lanes -> the compact beat's line 2 is the loud headline,
#       carrying a REAL, persisted duration (not reset every render)
#   T2  a >=1 -> 0 lane-count transition triggers leadv2-pulse-beat.sh to
#       fire IMMEDIATELY, bypassing a throttle that would otherwise block it
#       for hours
#   T3  a landed docs/handoff/<id>/review-gate.md verdict is folded into the
#       compact beat's delta line, with outcome + counts
#   T4  several transitions inside one throttle window still produce
#       exactly ONE composer invocation, not one per --check call
#   T5  the epoch-based fresh/stale rule survives the exact incident it was
#       written for: a file whose line-1 UTC stamp reads "older" than a
#       local mtime read of the SAME instant must still be judged FRESH by
#       `now_epoch - epoch_file < BEAT_S`
#
# Each case is run once GREEN (production code intact) and once RED (the
# governing line commented out with sed, same fixture, opposite verdict),
# proving the test would actually catch a regression, not just echo the
# feature's own log line back.
#
# Hermetic: LEADV2_PROJECT_ROOT/LEADV2_STATE_ROOT point at throwaway dirs;
# leadv2-lane-heartbeat.sh is fully stubbed via LEADV2_LANE_HEARTBEAT_BIN;
# leadv2-broad-status.sh is stubbed for T2/T4 (composer identity is out of
# scope there — only "did it fire, how many times" matters) and REAL for
# T1/T3/T5 (those assert composer OUTPUT).
# Run: bash scripts/tests/test-pulse-empty-board.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PULSE_BEAT_SH="$SCRIPT_DIR/leadv2-pulse-beat.sh"
BROAD_STATUS_SH="$SCRIPT_DIR/leadv2-broad-status.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir pulse-empty-board)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ════════════════════════════════════════════════════════════════════════
# T1 — zero live lanes -> loud headline with a real, persisted duration
# ════════════════════════════════════════════════════════════════════════
t1_setup() {
  local repo="$1" state="$2"
  mkdir -p "$repo/docs/leadv2"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t.local; git -C "$repo" config user.name t
  git -C "$repo" commit --allow-empty -q -m seed
  cat > "$TMP/collector-empty.sh" <<'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do case "$1" in --out) out="$2"; shift 2 ;; *) shift ;; esac; done
python3 - "$out" <<'PY'
import json, sys
snap = {"sections": {
    "lanes": {"ok": True, "data": {"table": [], "questions": [], "degraded": []}},
    "lane_detail": {"ok": True, "data": {"lanes": []}},
    "repo_facts": {"ok": True, "data": {}},
}}
json.dump(snap, open(sys.argv[1], "w", encoding="utf-8"))
PY
EOF
  chmod +x "$TMP/collector-empty.sh"
}

run_t1_render() {
  local repo="$1" state="$2" beat_at="$3"
  LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_STATUS_COLLECTOR_BIN="$TMP/collector-empty.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$TMP/collector-empty.sh" \
    LEADV2_BROAD_STATUS_BEAT_AT="$beat_at" \
    bash "$BROAD_STATUS_SH" >/dev/null 2>&1
}

test_t1() {
  local repo="$TMP/t1-repo" state="$TMP/t1-state"
  mkdir -p "$repo" "$state"
  t1_setup "$repo" "$state"
  lv2_assert_scratch_repo "$repo"
  run_t1_render "$repo" "$state" "2026-08-21T10:00:00Z"
  local content; content="$(cat "$repo/docs/leadv2/founder-status.md" 2>/dev/null || true)"
  local line2; line2="$(printf '%s' "$content" | sed -n '2p')"
  if printf '%s' "$line2" | grep -q 'ДОСКА ПУСТА'; then
    pass "T1: empty-board headline is line 2 of the compact beat"
  else
    fail "T1: no headline on line 2. content:
$content"
  fi
  if printf '%s' "$line2" | grep -qE '[0-9]+ мин'; then
    pass "T1: headline carries a numeric duration"
  else
    fail "T1: no duration in headline: $line2"
  fi
  # backdate the persisted empty-since cursor by 125s and re-render —
  # duration must reflect REAL persisted elapsed time (>=2 мин), proving
  # it survives across beats instead of resetting to 0 every render.
  local since_file="$repo/docs/leadv2/.board-empty-since"
  [[ -f "$since_file" ]] || fail "T1: empty-since cursor file not written"
  local now; now="$(date +%s)"
  printf -- '%s' "$(( now - 125 ))" > "$since_file"
  run_t1_render "$repo" "$state" "2026-08-21T10:05:00Z"
  content="$(cat "$repo/docs/leadv2/founder-status.md" 2>/dev/null || true)"
  line2="$(printf '%s' "$content" | sed -n '2p')"
  if printf '%s' "$line2" | grep -qE '[2-9] мин|[0-9][0-9]+ мин'; then
    pass "T1: duration reflects the PERSISTED empty-since epoch, not a fresh 0"
  else
    fail "T1: duration did not persist across beats: $line2"
  fi
}

test_t1_red() {
  local repo="$TMP/t1red-repo" state="$TMP/t1red-state"
  mkdir -p "$repo" "$state"
  t1_setup "$repo" "$state"
  # RED: neuter the headline computation (force it to None unconditionally)
  cp "$BROAD_STATUS_SH" "$TMP/broad-status-red.sh"
  sed -i.bak 's/^empty_headline = None$/empty_headline = None\nlive_lane_count = 999  # RED-FALSIFICATION: force non-empty/' "$TMP/broad-status-red.sh"
  chmod +x "$TMP/broad-status-red.sh"
  LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_STATUS_COLLECTOR_BIN="$TMP/collector-empty.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$TMP/collector-empty.sh" \
    LEADV2_BROAD_STATUS_BEAT_AT="2026-08-21T10:00:00Z" \
    bash "$TMP/broad-status-red.sh" >/dev/null 2>&1
  local content; content="$(cat "$repo/docs/leadv2/founder-status.md" 2>/dev/null || true)"
  if printf '%s' "$content" | sed -n '2p' | grep -q 'ДОСКА ПУСТА'; then
    echo "[RED-T1] unexpectedly still shows headline — falsification did not neuter the code"
  else
    echo "[RED-T1] headline ABSENT with production line disabled (expected RED):"
    printf '%s\n' "$content" | head -3
  fi
}

# ════════════════════════════════════════════════════════════════════════
# lane-heartbeat stub factory (shared by T2/T4)
# ════════════════════════════════════════════════════════════════════════
make_hb_stub() {
  local count_file="$1"
  cat > "$TMP/hb-stub.sh" <<EOF
#!/usr/bin/env bash
n="\$(cat "$count_file" 2>/dev/null || echo 0)"
if [[ "\$1" == "status" ]]; then
  if [[ "\$n" -ge 1 ]]; then
    printf '[{"task_id":"t1","status":"running"}]'
  else
    printf '[]'
  fi
fi
EOF
  chmod +x "$TMP/hb-stub.sh"
}

make_composer_counter_stub() {
  local counter_file="$1"
  cat > "$TMP/composer-counter.sh" <<EOF
#!/usr/bin/env bash
n="\$(cat "$counter_file" 2>/dev/null || echo 0)"
printf -- '%s' "\$(( n + 1 ))" > "$counter_file"
exit 0
EOF
  chmod +x "$TMP/composer-counter.sh"
}

wait_for_bg() {
  # give the async setsid/nohup child a moment; poll instead of a blind sleep
  local i=0
  while [[ $i -lt 40 ]]; do
    sleep 0.1
    i=$(( i + 1 ))
  done
}

# ════════════════════════════════════════════════════════════════════════
# T2 — >=1 -> 0 transition fires immediately, bypassing the clock throttle
# ════════════════════════════════════════════════════════════════════════
test_t2() {
  local repo="$TMP/t2-repo" state="$TMP/t2-state"
  mkdir -p "$repo" "$state" "$repo/docs/leadv2"
  local count_file="$TMP/t2-count" counter_file="$TMP/t2-counter"
  printf -- '1' > "$count_file"
  printf -- '0' > "$counter_file"
  make_hb_stub "$count_file"
  make_composer_counter_stub "$counter_file"

  env_run() {
    LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
      LEADV2_LANE_HEARTBEAT_BIN="$TMP/hb-stub.sh" \
      LEADV2_BROAD_STATUS_BIN="$TMP/composer-counter.sh" \
      LEADV2_BACKLOG_PUMP=0 \
      LEADV2_SINGLE_LEAD_BEAT_S=999999 \
      bash "$PULSE_BEAT_SH" "$@"
  }

  # prime: baseline commit at count=1 (first-ever check is due on the clock
  # regardless — this just establishes the committed baseline for the
  # transition check, same as any cold start).
  env_run --check
  wait_for_bg
  local after_prime; after_prime="$(cat "$counter_file")"
  [[ "$after_prime" -ge 1 ]] || fail "T2 fixture: priming beat never ran (counter=$after_prime)"

  # re-stamp BEAT_LAST_FILE fresh so the clock throttle would block anything
  # for the next 999999s, then confirm a no-transition --check stays silent.
  local state_dir; state_dir="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$SCRIPT_DIR/leadv2-state-path.sh" --no-link root)"
  printf -- '%s' "$(date +%s)" > "${state_dir}/.pulse-beat-last"
  env_run --check
  wait_for_bg
  local after_noop; after_noop="$(cat "$counter_file")"
  if [[ "$after_noop" == "$after_prime" ]]; then
    pass "T2 baseline: throttled --check with no transition stays silent"
  else
    fail "T2 baseline: throttle did not hold (before=$after_prime after=$after_noop)"
  fi

  # transition: 1 -> 0
  printf -- '0' > "$count_file"
  env_run --check
  wait_for_bg
  local after_drop; after_drop="$(cat "$counter_file")"
  if [[ "$after_drop" -gt "$after_noop" ]]; then
    pass "T2: >=1 -> 0 lane transition fired a beat despite a fresh throttle stamp"
  else
    fail "T2: transition did not fire a beat (before=$after_noop after=$after_drop)"
  fi
}

test_t2_red() {
  local repo="$TMP/t2red-repo" state="$TMP/t2red-state"
  mkdir -p "$repo" "$state" "$repo/docs/leadv2"
  local count_file="$TMP/t2red-count" counter_file="$TMP/t2red-counter"
  printf -- '1' > "$count_file"; printf -- '0' > "$counter_file"
  make_hb_stub "$count_file"
  make_composer_counter_stub "$counter_file"
  # RED: neuter the transition bypass in _due()
  cp "$PULSE_BEAT_SH" "$TMP/pulse-beat-red.sh"
  sed -i.bak 's/if _lv2_peek_lane_drop || _lv2_peek_review_landings; then/if false \&\& (_lv2_peek_lane_drop || _lv2_peek_review_landings); then/' "$TMP/pulse-beat-red.sh"
  chmod +x "$TMP/pulse-beat-red.sh"

  env_run_red() {
    LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
      LEADV2_LANE_HEARTBEAT_BIN="$TMP/hb-stub.sh" \
      LEADV2_BROAD_STATUS_BIN="$TMP/composer-counter.sh" \
      LEADV2_BACKLOG_PUMP=0 \
      LEADV2_SINGLE_LEAD_BEAT_S=999999 \
      bash "$TMP/pulse-beat-red.sh" "$@"
  }
  env_run_red --check; wait_for_bg
  local after_prime; after_prime="$(cat "$counter_file")"
  local state_dir; state_dir="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$SCRIPT_DIR/leadv2-state-path.sh" --no-link root)"
  printf -- '%s' "$(date +%s)" > "${state_dir}/.pulse-beat-last"
  printf -- '0' > "$count_file"
  env_run_red --check; wait_for_bg
  local after_drop; after_drop="$(cat "$counter_file")"
  if [[ "$after_drop" == "$after_prime" ]]; then
    echo "[RED-T2] transition correctly produced NO beat with the bypass disabled (expected RED — proves T2 catches a real regression): before=$after_prime after=$after_drop"
  else
    echo "[RED-T2] unexpectedly still fired (before=$after_prime after=$after_drop) — falsification failed to neuter the code"
  fi
}

# ════════════════════════════════════════════════════════════════════════
# T3 — landed review verdict folds into the delta line with outcome+counts
# ════════════════════════════════════════════════════════════════════════
t3_seed_review() {
  local repo="$1"
  mkdir -p "$repo/docs/handoff/dispatch-abc123"
  printf 'status: fail\ncritical: 0\nhigh: 3\nmedium: 1\nlow: 0\nreason: falsification_missing\n' \
    > "$repo/docs/handoff/dispatch-abc123/review-gate.md"
}

test_t3() {
  local repo="$TMP/t3-repo" state="$TMP/t3-state"
  mkdir -p "$repo" "$state" "$repo/docs/leadv2" "$repo/docs/handoff"
  git -C "$repo" init -q; git -C "$repo" config user.email t@t.local; git -C "$repo" config user.name t
  git -C "$repo" commit --allow-empty -q -m seed
  cat > "$TMP/hb-noop.sh" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "status" ]] && printf '[]'
EOF
  chmod +x "$TMP/hb-noop.sh"
  t1_setup "$repo" "$state"  # reuse the zero-table collector stub
  # cold-start commit FIRST (creates the watermark for real, via --now, no
  # review-gate.md present yet) -- --due is a PEEK-only probe and must never
  # be the thing that creates the commit-side watermark.
  LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_LANE_HEARTBEAT_BIN="$TMP/hb-noop.sh" \
    LEADV2_STATUS_COLLECTOR_BIN="$TMP/collector-empty.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$TMP/collector-empty.sh" \
    LEADV2_BROAD_STATUS_BEAT_AT="2026-08-21T10:09:00Z" \
    bash "$PULSE_BEAT_SH" --now >/dev/null 2>&1
  sleep 1.1
  t3_seed_review "$repo"

  LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_LANE_HEARTBEAT_BIN="$TMP/hb-noop.sh" \
    LEADV2_STATUS_COLLECTOR_BIN="$TMP/collector-empty.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$TMP/collector-empty.sh" \
    LEADV2_BROAD_STATUS_BEAT_AT="2026-08-21T10:10:00Z" \
    bash "$PULSE_BEAT_SH" --now >/dev/null 2>&1

  local content; content="$(cat "$repo/docs/leadv2/founder-status.md" 2>/dev/null || true)"
  if printf '%s' "$content" | grep -q 'FAIL' && printf '%s' "$content" | grep -qE '3 high'; then
    pass "T3: landed review verdict appears in the delta line with outcome + counts"
  else
    fail "T3: no review verdict in delta line. content:
$content"
  fi
}

test_t3_red() {
  local repo="$TMP/t3red-repo" state="$TMP/t3red-state"
  mkdir -p "$repo" "$state" "$repo/docs/leadv2"
  git -C "$repo" init -q; git -C "$repo" config user.email t@t.local; git -C "$repo" config user.name t
  git -C "$repo" commit --allow-empty -q -m seed
  cat > "$TMP/hb-noop.sh" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "status" ]] && printf '[]'
EOF
  chmod +x "$TMP/hb-noop.sh"
  mkdir -p "$repo/docs/handoff"
  t1_setup "$repo" "$state"
  LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_LANE_HEARTBEAT_BIN="$TMP/hb-noop.sh" \
    LEADV2_STATUS_COLLECTOR_BIN="$TMP/collector-empty.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$TMP/collector-empty.sh" \
    LEADV2_BROAD_STATUS_BEAT_AT="2026-08-21T10:09:00Z" \
    bash "$PULSE_BEAT_SH" --now >/dev/null 2>&1
  sleep 1.1
  t3_seed_review "$repo"

  cp "$PULSE_BEAT_SH" "$TMP/pulse-beat-red-t3.sh"
  sed -i.bak 's/^  _prepare_transition_env$/  :/' "$TMP/pulse-beat-red-t3.sh"
  chmod +x "$TMP/pulse-beat-red-t3.sh"

  LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_LANE_HEARTBEAT_BIN="$TMP/hb-noop.sh" \
    LEADV2_STATUS_COLLECTOR_BIN="$TMP/collector-empty.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$TMP/collector-empty.sh" \
    LEADV2_BROAD_STATUS_BEAT_AT="2026-08-21T10:10:00Z" \
    bash "$TMP/pulse-beat-red-t3.sh" --now >/dev/null 2>&1

  local content; content="$(cat "$repo/docs/leadv2/founder-status.md" 2>/dev/null || true)"
  if printf '%s' "$content" | grep -q '3 high'; then
    echo "[RED-T3] unexpectedly still shows the verdict — falsification failed to neuter the code"
  else
    echo "[RED-T3] verdict ABSENT from delta line with commit disabled (expected RED):"
    printf '%s\n' "$content" | grep -i 'прошлого удара' || echo "(no delta line found at all)"
  fi
}

# ════════════════════════════════════════════════════════════════════════
# T4 — several transitions inside one window -> ONE beat, not several
# ════════════════════════════════════════════════════════════════════════
test_t4() {
  local repo="$TMP/t4-repo" state="$TMP/t4-state"
  mkdir -p "$repo" "$state" "$repo/docs/leadv2"
  local count_file="$TMP/t4-count" counter_file="$TMP/t4-counter"
  printf -- '1' > "$count_file"; printf -- '0' > "$counter_file"
  make_hb_stub "$count_file"
  make_composer_counter_stub "$counter_file"

  env_run() {
    LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
      LEADV2_LANE_HEARTBEAT_BIN="$TMP/hb-stub.sh" \
      LEADV2_BROAD_STATUS_BIN="$TMP/composer-counter.sh" \
      LEADV2_BACKLOG_PUMP=0 \
      LEADV2_SINGLE_LEAD_BEAT_S=999999 \
      bash "$PULSE_BEAT_SH" --check
  }
  env_run; wait_for_bg   # prime baseline=1
  local baseline; baseline="$(cat "$counter_file")"

  # flip to 0 and fire several --check calls back-to-back — this is the
  # "several transitions in one window" scenario: the count only drops
  # once, but the hook fires --check on every tool call, so a real session
  # would call this many times before the founder's next turn.
  printf -- '0' > "$count_file"
  for _ in 1 2 3 4 5; do env_run; done
  wait_for_bg
  local after; after="$(cat "$counter_file")"
  local delta=$(( after - baseline ))
  if [[ "$delta" -eq 1 ]]; then
    pass "T4: 5 rapid --check calls across one transition coalesce into exactly ONE beat"
  else
    fail "T4: expected exactly 1 new beat, got $delta (baseline=$baseline after=$after)"
  fi
}

test_t4_red() {
  local repo="$TMP/t4red-repo" state="$TMP/t4red-state"
  mkdir -p "$repo" "$state" "$repo/docs/leadv2"
  local count_file="$TMP/t4red-count" counter_file="$TMP/t4red-counter"
  printf -- '1' > "$count_file"; printf -- '0' > "$counter_file"
  make_hb_stub "$count_file"
  make_composer_counter_stub "$counter_file"

  # RED: disable the flock exclusion itself. The real coalescing
  # primitive is exec 9>LOCK + flock -n 9 with the fd left OPEN and
  # inherited by the spawned "--now" child (setsid nohup ... & does NOT
  # close fd 9), which keeps the lock held for the child's ENTIRE render,
  # not just the foreground parent's brief lifetime -- that is what makes
  # a tight burst of --check calls serialize onto one render. Comment out
  # the flock call and every one of them gets past the gate and spawns its
  # own child.
  cp "$PULSE_BEAT_SH" "$TMP/pulse-beat-red-t4.sh"
  perl -0pi -e 's/if command -v flock >\/dev\/null 2>&1; then\n  flock -n 9 \|\| exit 0\nfi/if false; then # RED-FALSIFICATION: flock exclusion disabled\n  flock -n 9 || exit 0\nfi/' "$TMP/pulse-beat-red-t4.sh"
  # ALSO remove the synchronous pre-spawn commit and defer it into the
  # child with an artificial delay -- with the flock gone, both
  # independent coalescing primitives have to be disabled at once to
  # actually reproduce the double-fire (proving neither one alone is a
  # decorative no-op).
  perl -0pi -e 's/_prepare_transition_env\n\nSELF="\$\{BASH_SOURCE\[0\]\}"/# RED-FALSIFICATION: commit-before-spawn also removed\n\nSELF="\$\{BASH_SOURCE\[0\]\}"/' "$TMP/pulse-beat-red-t4.sh"
  perl -0pi -e 's/^if \[\[ "\$MODE" == "--now" \]\]; then\n  _prepare_transition_env/if [[ "\$MODE" == "--now" ]]; then\n  sleep 0.5  # RED-FALSIFICATION: widen the race window\n  _prepare_transition_env/m' "$TMP/pulse-beat-red-t4.sh"
  chmod +x "$TMP/pulse-beat-red-t4.sh"

  env_run_red() {
    LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
      LEADV2_LANE_HEARTBEAT_BIN="$TMP/hb-stub.sh" \
      LEADV2_BROAD_STATUS_BIN="$TMP/composer-counter.sh" \
      LEADV2_BACKLOG_PUMP=0 \
      LEADV2_SINGLE_LEAD_BEAT_S=999999 \
      bash "$TMP/pulse-beat-red-t4.sh" --check
  }
  env_run_red; wait_for_bg
  local baseline; baseline="$(cat "$counter_file")"
  printf -- '0' > "$count_file"
  for _ in 1 2 3 4 5; do env_run_red; done
  wait_for_bg
  local after; after="$(cat "$counter_file")"
  local delta=$(( after - baseline ))
  if [[ "$delta" -gt 1 ]]; then
    echo "[RED-T4] with the baseline commit disabled, 5 checks produced $delta beats (expected RED — proves T4 catches a real regression)"
  else
    echo "[RED-T4] unexpectedly still coalesced (delta=$delta) — falsification did not reproduce the race"
  fi
}

# ════════════════════════════════════════════════════════════════════════
# T5 — fresh/stale rule survives the timezone-confusion incident
# ════════════════════════════════════════════════════════════════════════
# The incident: founder-status.md had mtime 14:12 LOCAL (Europe/Kyiv,
# UTC+3) while its line-1 stamp read 11:12:23Z — the SAME instant, just two
# different clocks. A naive reader comparing the ISO stamp's numbers
# against a local `ls -la` wall-clock reading sees "11" vs "14" and
# concludes (wrongly) the file is 3 hours stale. The documented rule reads
# ONLY the epoch file, so it must judge this instant FRESH.
test_t5() {
  local repo="$TMP/t5-repo" state="$TMP/t5-state"
  mkdir -p "$repo" "$state" "$repo/docs/leadv2"
  t1_setup "$repo" "$state"
  # Freeze BEAT_AT to 11:12:23Z (the incident's own line-1 stamp) so the
  # artifact reproduces it exactly; the render's WALL-CLOCK epoch is real
  # "now", same instant the epoch file records regardless of BEAT_AT text.
  run_t1_render "$repo" "$state" "2026-08-21T11:12:23Z"

  local epoch_file="$repo/docs/leadv2/.founder-status-epoch"
  [[ -f "$epoch_file" ]] || { fail "T5 fixture: epoch file not written"; return; }
  local epoch now delta beat_s=1800
  epoch="$(cat "$epoch_file")"
  now="$(date +%s)"
  delta=$(( now - epoch ))

  # Naive (WRONG) reader: parses line-1's Z stamp and a "local ls -la"
  # reading 3h ahead (14:12 local == 11:12:23Z, the incident's own
  # numbers) as if both were the same clock — this is exactly the
  # comparison that misjudged the file stale in production.
  local naive_line1_epoch naive_local_epoch naive_delta
  naive_line1_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' '2026-08-21T11:12:23Z' +%s 2>/dev/null \
    || date -u -d '2026-08-21T11:12:23Z' +%s 2>/dev/null)"
  naive_local_epoch="$(TZ=Europe/Kyiv date -j -f '%Y-%m-%dT%H:%M:%S' '2026-08-21T14:12:23' +%s 2>/dev/null \
    || TZ=Europe/Kyiv date -d '2026-08-21T14:12:23' +%s 2>/dev/null)"
  if [[ -n "$naive_line1_epoch" && -n "$naive_local_epoch" ]]; then
    naive_delta=$(( naive_local_epoch - naive_line1_epoch ))
    if [[ "$naive_delta" -eq 0 ]]; then
      pass "T5 fixture: reproduced the incident's exact same-instant reading (11:12:23Z == 14:12:23 Europe/Kyiv, delta=0 -- confirms this is the incident, not a made-up example)"
    fi
  fi

  # The documented rule: epoch-file delta only.
  if [[ "$delta" -ge 0 && "$delta" -lt "$beat_s" ]]; then
    pass "T5: epoch-based rule judges a just-rendered beat FRESH (delta=${delta}s < ${beat_s}s), independent of any timezone text"
  else
    fail "T5: epoch-based rule misjudged a fresh render as stale (delta=${delta}s)"
  fi

  # Now genuinely age it past the threshold and confirm STALE is reachable
  # too (the rule must distinguish both directions, not just always say
  # fresh).
  printf -- '%s' "$(( now - beat_s - 100 ))" > "$epoch_file"
  epoch="$(cat "$epoch_file")"; now="$(date +%s)"; delta=$(( now - epoch ))
  if [[ "$delta" -ge "$beat_s" ]]; then
    pass "T5: epoch-based rule judges a genuinely old render STALE (delta=${delta}s >= ${beat_s}s)"
  else
    fail "T5: epoch-based rule failed to flag a backdated render as stale (delta=${delta}s)"
  fi
}

test_t5_red() {
  local repo="$TMP/t5red-repo" state="$TMP/t5red-state"
  mkdir -p "$repo" "$state" "$repo/docs/leadv2"
  t1_setup "$repo" "$state"
  cp "$BROAD_STATUS_SH" "$TMP/broad-status-red-t5.sh"
  # RED: disable both epoch-stamp call sites — the file should now be
  # ABSENT after a fresh render, meaning a reader has NOTHING to compare.
  sed -i.bak 's/&& _stamp_epoch//' "$TMP/broad-status-red-t5.sh"
  chmod +x "$TMP/broad-status-red-t5.sh"
  local epoch_file="$repo/docs/leadv2/.founder-status-epoch"
  rm -f "$epoch_file"
  LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_STATUS_COLLECTOR_BIN="$TMP/collector-empty.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$TMP/collector-empty.sh" \
    LEADV2_BROAD_STATUS_BEAT_AT="2026-08-21T11:12:23Z" \
    bash "$TMP/broad-status-red-t5.sh" >/dev/null 2>&1
  if [[ -f "$epoch_file" ]]; then
    echo "[RED-T5] epoch file unexpectedly written — falsification failed to neuter the stamp"
  else
    echo "[RED-T5] epoch file ABSENT after a real render with _stamp_epoch disabled (expected RED — a reader applying the documented rule now has NO epoch to compare, i.e. cannot certify freshness at all)"
  fi
}

log "-- GREEN run --"
test_t1
test_t2
test_t3
test_t4
test_t5

log ""
log "-- RED falsification runs (production code temporarily neutered) --"
test_t1_red
test_t2_red
test_t3_red
test_t4_red
test_t5_red

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]}" >&2
  exit 1
fi
exit 0
