#!/usr/bin/env bash
# tests/test-broad-status-relay-scope.sh — BROAD-STATUS-RELAY-SCOPE-01
#
# The founder hit this in production: a focused session received the
# verbatim 25-row founder-status.md dump meant for the session running
# supervise. This suite proves the fix — leadv2-single-lead-beat.sh now
# resolves an "owner"/"guest"/"unresolved" role per hook-invoking session
# (via leadv2-beat-owner.sh) and injects a different shape of
# additionalContext depending on the role — without ever silently dropping
# the beat.
#
# Cases:
#   T1  owner session, fresh beat -> full relay (ready-line + RELAY=full)
#   T2  guest session, same beat  -> exactly ONE line, RELAY=none, no
#       BROAD_STATUS_READY bytes, no founder-status.md body rows
#   T3  R1 regression: guest fires first, then owner -> owner STILL gets the
#       full relay (per-session watermark, not a shared one)
#   T4  owner fires twice, body unchanged -> second fire delivers nothing
#       (idempotence preserved)
#   T5  ownership unresolvable (no override, no owner file) -> full relay,
#       fail-open, never empty
#   T6  LEADV2_BEAT_RELAY_SCOPE=0 -> byte-identical to the pre-change
#       (unresolved / full-relay) behaviour, even for what would otherwise be
#       a guest session
#   T7  PostToolUse event, guest role -> flat {"additionalContext":...},
#       still exactly one line
#   T8  anchor directive: both blocks say RELAY=full; sibling
#       test-broad-status-duty.sh T8a/T8b assertions (2x BROAD_STATUS_READY,
#       "verbatim relay of a") still hold — run separately, not duplicated
#       here.
#
# Ownership is driven entirely through LEADV2_BEAT_OWNER_OVERRIDE (the
# resolver's test seam) — no real pids needed.
#
# Hermetic: LEADV2_PROJECT_ROOT/LEADV2_STATE_ROOT point at a throwaway repo;
# supervise-loop.log + founder-status.md are synthetic fixtures, not a real
# composer run (that composer is out of scope for this lane; its own beat
# duty is covered by test-broad-status-duty.sh and test-single-lead-beat.sh).
# Run: bash scripts/tests/test-broad-status-relay-scope.sh

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"   # plugins/leadv2
source "${SCRIPT_DIR}/leadv2-temp.sh"

HOOK_SH="${PLUGIN_DIR}/hooks/leadv2-single-lead-beat.sh"
STATE_PATH_SH="${SCRIPT_DIR}/leadv2-state-path.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir broad-status-relay-scope)"
REPO="$TMP/proj"
STATE="$TMP/state"
mkdir -p "$REPO" "$STATE"
git -C "$REPO" init -q
lv2_assert_scratch_repo "$REPO"

export LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" CLAUDE_PROJECT_DIR="$REPO"

LOG_FILE="$(PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" bash "$STATE_PATH_SH" supervise-loop.log)"
STATE_DIR="$(PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" bash "$STATE_PATH_SH" --no-link root)"
ACTIVE_YAML="$(PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" bash "$STATE_PATH_SH" active.yaml)"
FOUNDER_STATUS="$REPO/docs/leadv2/founder-status.md"
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$FOUNDER_STATUS")" "$STATE_DIR" "$(dirname "$ACTIVE_YAML")"

write_beat() {  # <at-stamp> <body-marker>
  local at="$1" marker="$2"
  printf -- '%s\n%s\n' "$at" "row: $marker" > "$FOUNDER_STATUS"
  printf -- '%s [SUPERVISE-URGENT] BROAD_STATUS_READY at=%s path=docs/leadv2/founder-status.md rows=1 dispatched=0\n' \
    "$at" "$at" >> "$LOG_FILE"
}

# Disable the hook's own TRIGGER call reaching a real pulse-beat run: point
# it at a stub that never composes anything, so DELIVER is the only thing
# under test (PULSE_BEAT_SH is resolved from CLAUDE_PLUGIN_ROOT, so give it
# a plugin root whose scripts/leadv2-pulse-beat.sh is a harmless stub).
STUB_PLUGIN_ROOT="$TMP/plugin-stub"
mkdir -p "$STUB_PLUGIN_ROOT/scripts"
cp "$SCRIPT_DIR/leadv2-state-path.sh" "$STUB_PLUGIN_ROOT/scripts/leadv2-state-path.sh"
cp "$SCRIPT_DIR/leadv2-beat-owner.sh" "$STUB_PLUGIN_ROOT/scripts/leadv2-beat-owner.sh"
# T9-T14/T18 exercise the REAL leadv2_session_has_live_lane read side, which
# resolves leadv2-lane-heartbeat.sh as a sibling of wherever beat-owner.sh
# was sourced from -- since the hook sources it from CLAUDE_PLUGIN_ROOT (the
# stub), the stub needs real copies of both, not stand-ins.
cp "$SCRIPT_DIR/leadv2-lane-heartbeat.sh" "$STUB_PLUGIN_ROOT/scripts/leadv2-lane-heartbeat.sh"
cp "$SCRIPT_DIR/leadv2-active-registry.sh" "$STUB_PLUGIN_ROOT/scripts/leadv2-active-registry.sh"
cat > "$STUB_PLUGIN_ROOT/scripts/leadv2-pulse-beat.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUB_PLUGIN_ROOT/scripts/leadv2-pulse-beat.sh"

hook_fire() {  # <event> <session_id> [owner_override]
  local evt="$1" sid="$2" override="${3:-}"
  printf '{"cwd":"%s","hook_event_name":"%s","session_id":"%s"}' "$REPO" "$evt" "$sid" \
    | env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" CLAUDE_PROJECT_DIR="$REPO" \
        CLAUDE_PLUGIN_ROOT="$STUB_PLUGIN_ROOT" \
        LEADV2_BEAT_OWNER_OVERRIDE="$override" \
        bash "$HOOK_SH"
}

extract_ctx() {  # <hook stdout> -> best-effort additionalContext string
  printf -- '%s' "$1" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print('')
    sys.exit(0)
if 'hookSpecificOutput' in d:
    print(d['hookSpecificOutput'].get('additionalContext',''))
else:
    print(d.get('additionalContext',''))
" 2>/dev/null || true
}

# ── T1: owner session, fresh beat -> full relay ───────────────────────────
write_beat "2026-08-19T09:00:00Z" "alpha"
OUT1="$(hook_fire UserPromptSubmit sess-owner sess-owner)"
CTX1="$(extract_ctx "$OUT1")"
if printf -- '%s' "$CTX1" | grep -q 'BROAD_STATUS_READY' && printf -- '%s' "$CTX1" | grep -q 'RELAY=full'; then
  pass "T1: owner session receives the verbatim ready-line + RELAY=full"
else
  fail "T1: owner did not get full relay: $CTX1"
fi

# ── T2: guest session, SAME beat -> exactly one line, RELAY=none ─────────
OUT2="$(hook_fire UserPromptSubmit sess-guest sess-owner)"
CTX2="$(extract_ctx "$OUT2")"
LINES2="$(printf -- '%s' "$CTX2" | grep -c '.' || true)"
if [[ "$LINES2" -eq 1 ]] \
  && printf -- '%s' "$CTX2" | grep -q 'RELAY=none' \
  && printf -- '%s' "$CTX2" | grep -q 'full status in owning session' \
  && ! printf -- '%s' "$CTX2" | grep -q 'BROAD_STATUS_READY' \
  && ! printf -- '%s' "$CTX2" | grep -q 'row: alpha'; then
  pass "T2: guest session gets exactly one RELAY=none line, no ledger body"
else
  fail "T2: guest shape wrong (lines=$LINES2): $CTX2"
fi

# ── T3: R1 regression — guest fired FIRST, then owner fires on the SAME
#        beat -> owner must still get the full relay (per-session watermark,
#        not a shared one that the guest's fire would have consumed) ──────
write_beat "2026-08-19T09:30:00Z" "bravo"
OUT3_GUEST="$(hook_fire UserPromptSubmit sess-guest2 sess-owner2)"
CTX3_GUEST="$(extract_ctx "$OUT3_GUEST")"
OUT3_OWNER="$(hook_fire UserPromptSubmit sess-owner2 sess-owner2)"
CTX3_OWNER="$(extract_ctx "$OUT3_OWNER")"
if printf -- '%s' "$CTX3_GUEST" | grep -q 'RELAY=none' \
  && printf -- '%s' "$CTX3_OWNER" | grep -q 'BROAD_STATUS_READY' \
  && printf -- '%s' "$CTX3_OWNER" | grep -q 'RELAY=full'; then
  pass "T3: owner still gets the full relay after a guest fired first on the same beat"
else
  fail "T3: R1 regressed — guest=[$CTX3_GUEST] owner=[$CTX3_OWNER]"
fi

# ── T4: owner fires twice on the SAME beat, body unchanged -> silence on
#        the second fire (idempotence preserved) ─────────────────────────
OUT4="$(hook_fire UserPromptSubmit sess-owner2 sess-owner2)"
CTX4="$(extract_ctx "$OUT4")"
if [[ -z "$CTX4" ]]; then
  pass "T4: owner's second fire on an unchanged beat is silent"
else
  fail "T4: expected silence on repeat fire, got: $CTX4"
fi

# ── T5: unresolvable ownership (no override at all) -> full relay,
#        fail-open, never empty ──────────────────────────────────────────
write_beat "2026-08-19T10:00:00Z" "charlie"
OUT5="$(hook_fire UserPromptSubmit sess-unknown "")"
CTX5="$(extract_ctx "$OUT5")"
if printf -- '%s' "$CTX5" | grep -q 'BROAD_STATUS_READY' && printf -- '%s' "$CTX5" | grep -q 'RELAY=full'; then
  pass "T5: unresolvable ownership fails open to full relay"
else
  fail "T5: fail-open broke — expected full relay, got: $CTX5"
fi

# ── T6: kill-switch LEADV2_BEAT_RELAY_SCOPE=0 -> full relay even for a
#        session that would otherwise be a guest ─────────────────────────
write_beat "2026-08-19T10:30:00Z" "delta"
OUT6="$(printf '{"cwd":"%s","hook_event_name":"UserPromptSubmit","session_id":"sess-guest3"}' "$REPO" \
  | env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" CLAUDE_PROJECT_DIR="$REPO" \
      CLAUDE_PLUGIN_ROOT="$STUB_PLUGIN_ROOT" \
      LEADV2_BEAT_OWNER_OVERRIDE="sess-owner3" LEADV2_BEAT_RELAY_SCOPE=0 \
      bash "$HOOK_SH")"
CTX6="$(extract_ctx "$OUT6")"
if printf -- '%s' "$CTX6" | grep -q 'BROAD_STATUS_READY' && printf -- '%s' "$CTX6" | grep -q 'RELAY=full'; then
  pass "T6: kill-switch restores full relay for every session"
else
  fail "T6: kill-switch did not restore full relay: $CTX6"
fi

# ── T7: PostToolUse event, guest role -> flat additionalContext shape,
#        still exactly one line ──────────────────────────────────────────
write_beat "2026-08-19T11:00:00Z" "echo"
OUT7="$(hook_fire PostToolUse sess-guest4 sess-owner4)"
if printf -- '%s' "$OUT7" | python3 -c "
import sys, json
d = json.load(sys.stdin)
sys.exit(0 if 'hookSpecificOutput' not in d and 'additionalContext' in d else 1)
" 2>/dev/null; then
  pass "T7a: PostToolUse guest output is flat (no hookSpecificOutput wrapper)"
else
  fail "T7a: PostToolUse output shape wrong: $OUT7"
fi
CTX7="$(extract_ctx "$OUT7")"
LINES7="$(printf -- '%s' "$CTX7" | grep -c '.' || true)"
if [[ "$LINES7" -eq 1 ]] && printf -- '%s' "$CTX7" | grep -q 'RELAY=none'; then
  pass "T7b: PostToolUse guest context is still exactly one RELAY=none line"
else
  fail "T7b: PostToolUse guest context malformed (lines=$LINES7): $CTX7"
fi

# ── Round 2 (HIGH-1/HIGH-2/HIGH-3): real-state cases, no
#    LEADV2_BEAT_OWNER_OVERRIDE seam — these drive the actual mechanism:
#    .pulse-beat-owner, .pulse-session.<sid>, and
#    leadv2_session_has_live_lane against a real active.yaml +
#    arm-registered file. ────────────────────────────────────────────────

write_owner_file() {  # <sid> <age_s> -> .pulse-beat-owner = "<sid> <now-age_s>"
  local sid="$1" age_s="${2:-0}" now
  now="$(date +%s)"
  printf -- '%s %s' "$sid" "$(( now - age_s ))" > "$STATE_DIR/.pulse-beat-owner"
}

write_session_file() {  # <sid> <age_s> -> .pulse-session.<sid> = now-age_s
  local sid="$1" age_s="${2:-0}" now
  now="$(date +%s)"
  printf -- '%s' "$(( now - age_s ))" > "$STATE_DIR/.pulse-session.${sid}"
}

write_live_lane() {  # <task_id> <lead_session_sid> -> active.yaml row (fresh
                      # last_pulse_at, verdict=running) + arm-registered file
                      # carrying LEAD_SESSION=<sid>.
  local task_id="$1" sid="$2"
  python3 -c "
import yaml, datetime, sys
task_id, yaml_file = sys.argv[1], sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
data = {}
try:
    with open(yaml_file, encoding='utf-8') as fh:
        data = yaml.safe_load(fh) or {}
except FileNotFoundError:
    pass
sessions = [s for s in (data.get('sessions') or []) if s.get('task_id') != task_id]
sessions.append({'session_id': 'test-' + task_id, 'task_id': task_id,
                  'last_pulse_at': now, 'started_at': now, 'pid': None,
                  'backend': 'test'})
data['sessions'] = sessions
with open(yaml_file, 'w', encoding='utf-8') as fh:
    yaml.safe_dump(data, fh)
" "$task_id" "$ACTIVE_YAML"
  mkdir -p "$REPO/docs/handoff/${task_id}"
  printf -- 'arm=sonnet handle=PID=1 epoch=%s LEAD_SESSION=%s\n' "$(date +%s)" "$sid" \
    >> "$REPO/docs/handoff/${task_id}/arm-registered"
}

clear_active_yaml() {
  rm -f "$ACTIVE_YAML"
}

real_hook_fire() {  # <event> <sid> -> fires with NO override, real beat-owner
  local evt="$1" sid="$2"
  printf '{"cwd":"%s","hook_event_name":"%s","session_id":"%s"}' "$REPO" "$evt" "$sid" \
    | env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" CLAUDE_PROJECT_DIR="$REPO" \
        CLAUDE_PLUGIN_ROOT="$STUB_PLUGIN_ROOT" \
        bash "$HOOK_SH"
}

# ── T9: owner session, fresh owner file + fresh .pulse-session + one live
#        lane attributed to it -> owner (full relay) ─────────────────────
rm -f "$STATE_DIR"/.pulse-delivered* "$STATE_DIR"/.pulse-body-hash*
clear_active_yaml
write_beat "2026-08-19T12:00:00Z" "foxtrot"
write_owner_file "sess-t9" 0
write_session_file "sess-t9" 0
write_live_lane "dispatch-t9" "sess-t9"
OUT9="$(real_hook_fire UserPromptSubmit sess-t9)"
CTX9="$(extract_ctx "$OUT9")"
if printf -- '%s' "$CTX9" | grep -q 'BROAD_STATUS_READY' && printf -- '%s' "$CTX9" | grep -q 'RELAY=full'; then
  pass "T9: owner with fresh session + live attributed lane gets the full relay"
else
  fail "T9: expected full relay, got: $CTX9"
fi

# ── T10: owner file names sess-t9 (still fresh/live from T9); a DIFFERENT
#        session fires -> guest ──────────────────────────────────────────
OUT10="$(real_hook_fire UserPromptSubmit sess-t10-guest)"
CTX10="$(extract_ctx "$OUT10")"
if printf -- '%s' "$CTX10" | grep -q 'RELAY=none' && ! printf -- '%s' "$CTX10" | grep -q 'BROAD_STATUS_READY'; then
  pass "T10: a non-owner session with the same live owner on record gets guest"
else
  fail "T10: expected guest, got: $CTX10"
fi

# ── T11 (reviewer Scenario E): fresh owner file naming sess-other, but NO
#        .pulse-session.sess-other -> unresolved -> full relay ───────────
rm -f "$STATE_DIR"/.pulse-delivered* "$STATE_DIR"/.pulse-body-hash*
write_beat "2026-08-19T12:30:00Z" "golf"
write_owner_file "sess-other" 0
rm -f "$STATE_DIR/.pulse-session.sess-other"
OUT11="$(real_hook_fire UserPromptSubmit sess-random11)"
CTX11="$(extract_ctx "$OUT11")"
if printf -- '%s' "$CTX11" | grep -q 'BROAD_STATUS_READY' && printf -- '%s' "$CTX11" | grep -q 'RELAY=full'; then
  pass "T11: owner naming a session with no liveness stamp fails open to full relay"
else
  fail "T11: expected full relay (Scenario E), got: $CTX11"
fi

# ── T12: fresh owner file, but .pulse-session.sess-other is STALE
#        (older than beat_s) -> unresolved -> full relay ─────────────────
rm -f "$STATE_DIR"/.pulse-delivered* "$STATE_DIR"/.pulse-body-hash*
write_beat "2026-08-19T13:00:00Z" "hotel"
write_owner_file "sess-other" 0
write_session_file "sess-other" 1801
OUT12="$(real_hook_fire UserPromptSubmit sess-random12)"
CTX12="$(extract_ctx "$OUT12")"
if printf -- '%s' "$CTX12" | grep -q 'BROAD_STATUS_READY' && printf -- '%s' "$CTX12" | grep -q 'RELAY=full'; then
  pass "T12: owner with a stale liveness stamp fails open to full relay"
else
  fail "T12: expected full relay, got: $CTX12"
fi

# ── T13: torn / malformed .pulse-beat-owner content -> unresolved, no crash
T13_I=0
for BAD_CONTENT in "" "onlyfield" "sess-x epoch=abc" "sess-x 123 extra fourth"; do
  T13_I=$(( T13_I + 1 ))
  T13_SID="sess-random13-${T13_I}"
  rm -f "$STATE_DIR"/.pulse-delivered* "$STATE_DIR"/.pulse-body-hash*
  write_beat "2026-08-19T13:3${T13_I}:00Z" "india${T13_I}"
  printf -- '%s' "$BAD_CONTENT" > "$STATE_DIR/.pulse-beat-owner"
  OUT13="$(real_hook_fire UserPromptSubmit "$T13_SID" 2>&1)"
  CTX13="$(extract_ctx "$OUT13")"
  if printf -- '%s' "$CTX13" | grep -q 'RELAY=full'; then
    pass "T13: malformed owner content '$BAD_CONTENT' resolves to unresolved/full relay, no crash"
  else
    fail "T13: malformed owner content '$BAD_CONTENT' broke the resolver: $CTX13"
  fi
done

# ── T14: fresh owner + fresh session heartbeat, but ZERO live lanes for
#        that sid -> unresolved (HIGH-2 read-side gate) ──────────────────
rm -f "$STATE_DIR"/.pulse-delivered* "$STATE_DIR"/.pulse-body-hash*
clear_active_yaml
write_beat "2026-08-19T14:00:00Z" "juliet"
write_owner_file "sess-nolane" 0
write_session_file "sess-nolane" 0
OUT14="$(real_hook_fire UserPromptSubmit sess-random14)"
CTX14="$(extract_ctx "$OUT14")"
if printf -- '%s' "$CTX14" | grep -q 'BROAD_STATUS_READY' && printf -- '%s' "$CTX14" | grep -q 'RELAY=full'; then
  pass "T14: alive owner with zero live lanes still fails open to full relay"
else
  fail "T14: expected full relay (no qualifying lane), got: $CTX14"
fi

# ── T15/T16/T17: the REAL leadv2-pulse-beat.sh write side (HIGH-2) ────────
REAL_PULSE_BEAT_SH="$SCRIPT_DIR/leadv2-pulse-beat.sh"
run_real_pulse_beat_check() {  # <owner_session_env_value>
  local owner="$1" tmp_repo tmp_state
  tmp_repo="$TMP/pulsecheck-$RANDOM"
  tmp_state="$tmp_repo/state"
  mkdir -p "$tmp_repo/repo" "$tmp_state"
  git -C "$tmp_repo/repo" init -q
  env LEADV2_PROJECT_ROOT="$tmp_repo/repo" LEADV2_STATE_ROOT="$tmp_state" \
      LEADV2_BEAT_OWNER_SESSION="$owner" LEADV2_BACKLOG_PUMP=0 \
      LEADV2_BROAD_STATUS_BIN="$STUB_PLUGIN_ROOT/scripts/leadv2-pulse-beat.sh" \
      bash "$REAL_PULSE_BEAT_SH" --check >/dev/null 2>&1
  printf -- '%s' "$tmp_repo"
}

# T15: LEADV2_BEAT_OWNER_SESSION set + a live attributed lane -> file created
T15_REPO="$TMP/pulsecheck-t15"
T15_STATE="$T15_REPO/state"
mkdir -p "$T15_REPO/repo" "$T15_STATE"
git -C "$T15_REPO/repo" init -q
T15_ACTIVE_YAML="$(PROJECT_ROOT="$T15_REPO/repo" LEADV2_STATE_ROOT="$T15_STATE" bash "$STATE_PATH_SH" active.yaml)"
mkdir -p "$(dirname "$T15_ACTIVE_YAML")"
python3 -c "
import yaml, datetime, sys
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
data = {'sessions': [{'session_id': 'test-t15', 'task_id': 'dispatch-t15',
                       'last_pulse_at': now, 'started_at': now, 'pid': None,
                       'backend': 'test'}]}
with open(sys.argv[1], 'w', encoding='utf-8') as fh:
    yaml.safe_dump(data, fh)
" "$T15_ACTIVE_YAML"
mkdir -p "$T15_REPO/repo/docs/handoff/dispatch-t15"
printf -- 'arm=sonnet handle=PID=1 epoch=%s LEAD_SESSION=sess-t15\n' "$(date +%s)" \
  > "$T15_REPO/repo/docs/handoff/dispatch-t15/arm-registered"
T15_STATE_DIR="$(PROJECT_ROOT="$T15_REPO/repo" LEADV2_STATE_ROOT="$T15_STATE" bash "$STATE_PATH_SH" --no-link root)"
mkdir -p "$T15_STATE_DIR"
env LEADV2_PROJECT_ROOT="$T15_REPO/repo" LEADV2_STATE_ROOT="$T15_STATE" \
    LEADV2_BEAT_OWNER_SESSION="sess-t15" LEADV2_BACKLOG_PUMP=0 \
    LEADV2_BROAD_STATUS_BIN="$STUB_PLUGIN_ROOT/scripts/leadv2-pulse-beat.sh" \
    bash "$REAL_PULSE_BEAT_SH" --check >/dev/null 2>&1
if [[ -f "$T15_STATE_DIR/.pulse-beat-owner" ]] && grep -q '^sess-t15 [0-9]\+$' "$T15_STATE_DIR/.pulse-beat-owner"; then
  pass "T15: real pulse-beat --check writes the owner file for a session with a live attributed lane"
else
  fail "T15: owner file not written / wrong content: $(cat "$T15_STATE_DIR/.pulse-beat-owner" 2>/dev/null || echo '<absent>')"
fi

# T16: same but NO live lane for the arming session -> file NOT created
T16_REPO="$TMP/pulsecheck-t16"
T16_STATE="$T16_REPO/state"
mkdir -p "$T16_REPO/repo" "$T16_STATE"
git -C "$T16_REPO/repo" init -q
T16_STATE_DIR="$(PROJECT_ROOT="$T16_REPO/repo" LEADV2_STATE_ROOT="$T16_STATE" bash "$STATE_PATH_SH" --no-link root)"
mkdir -p "$T16_STATE_DIR"
env LEADV2_PROJECT_ROOT="$T16_REPO/repo" LEADV2_STATE_ROOT="$T16_STATE" \
    LEADV2_BEAT_OWNER_SESSION="sess-t16" LEADV2_BACKLOG_PUMP=0 \
    LEADV2_BROAD_STATUS_BIN="$STUB_PLUGIN_ROOT/scripts/leadv2-pulse-beat.sh" \
    bash "$REAL_PULSE_BEAT_SH" --check >/dev/null 2>&1
if [[ ! -f "$T16_STATE_DIR/.pulse-beat-owner" ]]; then
  pass "T16: real pulse-beat --check does NOT write an owner file for a session with no live lane"
else
  fail "T16: owner file was written despite no live lane: $(cat "$T16_STATE_DIR/.pulse-beat-owner")"
fi

# T17: LEADV2_BEAT_OWNER_SESSION empty -> file untouched (round-1 invariant)
T17_REPO="$TMP/pulsecheck-t17"
T17_STATE="$T17_REPO/state"
mkdir -p "$T17_REPO/repo" "$T17_STATE"
git -C "$T17_REPO/repo" init -q
T17_STATE_DIR="$(PROJECT_ROOT="$T17_REPO/repo" LEADV2_STATE_ROOT="$T17_STATE" bash "$STATE_PATH_SH" --no-link root)"
mkdir -p "$T17_STATE_DIR"
env LEADV2_PROJECT_ROOT="$T17_REPO/repo" LEADV2_STATE_ROOT="$T17_STATE" \
    LEADV2_BEAT_OWNER_SESSION="" LEADV2_BACKLOG_PUMP=0 \
    LEADV2_BROAD_STATUS_BIN="$STUB_PLUGIN_ROOT/scripts/leadv2-pulse-beat.sh" \
    bash "$REAL_PULSE_BEAT_SH" --check >/dev/null 2>&1
if [[ ! -f "$T17_STATE_DIR/.pulse-beat-owner" ]]; then
  pass "T17: empty LEADV2_BEAT_OWNER_SESSION leaves the owner file untouched"
else
  fail "T17: owner file was written despite empty LEADV2_BEAT_OWNER_SESSION"
fi

# ── T18: .supervise-active with a LIVE real child pid must be INERT
#        (D3: the ancestry ladder rows were deleted, not just bypassed) ───
rm -f "$STATE_DIR"/.pulse-delivered* "$STATE_DIR"/.pulse-body-hash*
clear_active_yaml
write_beat "2026-08-19T14:30:00Z" "kilo"
write_owner_file "sess-t18" 0
write_session_file "sess-t18" 0
write_live_lane "dispatch-t18" "sess-t18"
sleep 30 &
T18_CHILD_PID=$!
printf -- '{"pid": %s}' "$T18_CHILD_PID" > "$STATE_DIR/.supervise-active"
OUT18="$(real_hook_fire UserPromptSubmit sess-t18)"
kill "$T18_CHILD_PID" 2>/dev/null || true
wait "$T18_CHILD_PID" 2>/dev/null || true
rm -f "$STATE_DIR/.supervise-active"
CTX18="$(extract_ctx "$OUT18")"
if printf -- '%s' "$CTX18" | grep -q 'BROAD_STATUS_READY' && printf -- '%s' "$CTX18" | grep -q 'RELAY=full'; then
  pass "T18: a live .supervise-active pid does not change the owner's role (retired path is inert)"
else
  fail "T18: .supervise-active affected the outcome (should be inert): $CTX18"
fi

# ── T19: BEAT_OWNER_SH deleted -> unresolved, full relay, ONE stderr line
rm -f "$STATE_DIR"/.pulse-delivered* "$STATE_DIR"/.pulse-body-hash*
write_beat "2026-08-19T15:00:00Z" "lima"
MISSING_STUB_ROOT="$TMP/plugin-stub-nobeat"
mkdir -p "$MISSING_STUB_ROOT/scripts"
cp "$STUB_PLUGIN_ROOT/scripts/leadv2-state-path.sh" "$MISSING_STUB_ROOT/scripts/leadv2-state-path.sh"
cp "$STUB_PLUGIN_ROOT/scripts/leadv2-pulse-beat.sh" "$MISSING_STUB_ROOT/scripts/leadv2-pulse-beat.sh"
T19_ERR="$TMP/t19.stderr"
OUT19="$(printf '{"cwd":"%s","hook_event_name":"UserPromptSubmit","session_id":"sess-t19"}' "$REPO" \
  | env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" CLAUDE_PROJECT_DIR="$REPO" \
      CLAUDE_PLUGIN_ROOT="$MISSING_STUB_ROOT" \
      bash "$HOOK_SH" 2>"$T19_ERR")"
CTX19="$(extract_ctx "$OUT19")"
ERR_LINES19="$(grep -c '.' "$T19_ERR" 2>/dev/null || true)"
if printf -- '%s' "$CTX19" | grep -q 'BROAD_STATUS_READY' && printf -- '%s' "$CTX19" | grep -q 'RELAY=full' \
  && [[ "$ERR_LINES19" -eq 1 ]] && grep -q 'beat-owner resolver missing' "$T19_ERR"; then
  pass "T19: missing beat-owner resolver -> unresolved/full relay + exactly one stderr line"
else
  fail "T19: missing-resolver path wrong (stderr lines=$ERR_LINES19): ctx=$CTX19 stderr=$(cat "$T19_ERR" 2>/dev/null)"
fi

# ── T20/T21: _dispatch_register_arm's LEAD_SESSION source (round 3) ──────
# The dispatch script has no sourcing guard and parses argv when run
# top-level, so we extract the two real functions verbatim into a driver
# script rather than reimplementing them (a reimplemented stub would pass
# while prod stayed broken).
DISPATCH_SH="${SCRIPT_DIR}/leadv2-dispatch-code.sh"
T20_DRIVER="$TMP/t20-driver.sh"
{
  printf -- '#!/usr/bin/env bash\nset -uo pipefail\n'
  sed -n '/^_dispatch_arm_registered_file() {/,/^}/p;/^_dispatch_register_arm() {/,/^}/p' "$DISPATCH_SH"
  printf -- '_dispatch_register_arm deadbeef claude "PID=1"\n'
} > "$T20_DRIVER"

if grep -q '_dispatch_arm_registered_file() {' "$T20_DRIVER" && grep -q '_dispatch_register_arm() {' "$T20_DRIVER"; then
  pass "T20: extraction guard — both functions present in the driver"
else
  fail "T20: extraction failed — function renamed in leadv2-dispatch-code.sh"
fi

# T20: only CLAUDE_CODE_SESSION_ID set (real prod shape) -> LEAD_SESSION non-empty
T20_ARMF="$TMP/t20-arm-registered"
env -u CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID="f5096a7e-4c5b-4a1e-9d33-000000000001" \
    PROJECT_ROOT="$TMP" LEADV2_DISPATCH_ARM_REGISTERED_FILE="$T20_ARMF" \
    bash "$T20_DRIVER" >/dev/null 2>&1
if [[ -f "$T20_ARMF" ]] && grep -qE 'LEAD_SESSION=f5096a7e-4c5b-4a1e-9d33-000000000001$' "$T20_ARMF"; then
  pass "T20: CLAUDE_CODE_SESSION_ID alone produces a non-empty LEAD_SESSION field"
else
  fail "T20: LEAD_SESSION not populated from CLAUDE_CODE_SESSION_ID: $(cat "$T20_ARMF" 2>/dev/null || echo '<absent>')"
fi

# T21: only legacy CLAUDE_SESSION_ID set -> fallback still works
T21_ARMF="$TMP/t21-arm-registered"
env -u CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID="legacy-sid-1" \
    PROJECT_ROOT="$TMP" LEADV2_DISPATCH_ARM_REGISTERED_FILE="$T21_ARMF" \
    bash "$T20_DRIVER" >/dev/null 2>&1
if [[ -f "$T21_ARMF" ]] && grep -qE 'LEAD_SESSION=legacy-sid-1$' "$T21_ARMF"; then
  pass "T21: legacy CLAUDE_SESSION_ID still populates LEAD_SESSION (fallback preserved)"
else
  fail "T21: legacy CLAUDE_SESSION_ID fallback broken: $(cat "$T21_ARMF" 2>/dev/null || echo '<absent>')"
fi

# ── Summary ─────────────────────────────────────────────────────────────
rm -rf "$TMP"
printf -- '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
