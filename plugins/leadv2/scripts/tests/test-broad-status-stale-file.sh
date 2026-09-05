#!/usr/bin/env bash
# tests/test-broad-status-stale-file.sh — BROAD-STATUS-READY-FIRES-ON-A-DAY-OLD-FILE-01.
# run-all-triggers: leadv2-broad-status.sh leadv2-single-lead-beat.sh
#
# ACROSS-TIME staleness — the half test-beat-stamp-agreement.sh deliberately
# does not cover (it locks WITHIN-RUN agreement only, which is why a day-old
# file was relayed to the founder as current in the first place):
#   T1  25h-old confirmed-write epoch + a successful artifact write ->
#       READY carries stale=1 and at= = the FILE's own epoch stamp, never
#       the beat's wall clock ($BEAT_AT).
#   T2  fresh beat -> plain READY (no stale=1), at= = this run's epoch
#       stamp, path= = the ABSOLUTE path of the file this run wrote.
#   T3  `mv` of the artifact write fails -> BROAD_STATUS_FAILED fires and NO
#       READY does: a failed write must not fire a fresh READY over the
#       day-old file left behind (the proximate bug).
#   T4  hook DELIVER, stale epoch -> RELAY=refused, never RELAY=full.
#   T5  hook DELIVER, ready-line at= vs file line-1 disagree >= BEAT_S ->
#       RELAY=refused (addendum: a stamp mismatch REFUSES publication).
#   T6  hook DELIVER, fresh + stamps agree -> RELAY=full (no over-refusal).
#   T7  one gathering, one timestamp: a real run's artifact line-1 stamp and
#       its product HH:MM line derive from the SAME pinned $BEAT_AT (two
#       clock reads inside one snapshot was the addendum-1 defect).
#
# Hermetic: scratch repo, stub collector, LEADV2_SESSION_KIND pin (the
# session-kind classifier treats a transcript-less hook payload as worker
# and exits silently — pin `lead`, same seam test-beat-stamp-agreement-style
# stubs use). Never touches the real repo's docs/leadv2.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../tests/lib/test-helpers.sh" 2>/dev/null || {
  # minimal stand-ins if the helper lib is absent (hermetic suites carry
  # their own fallbacks; do not fail the whole suite on a helper rename)
  lv2_mktemp_dir() { mktemp -d "${TMPDIR:-/tmp}/$(basename "$1").XXXXXX"; }
  lv2_assert_scratch_repo() { [[ "$1" != "$HOME/Projects/leadv2"* ]] || { echo "scratch repo inside the real repo: $1" >&2; exit 2; }; }
}
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }
PASS=0; FAIL=0; ERRORS=()

TMP="$(lv2_mktemp_dir broad-status-stale-file)"
REPO="$TMP/proj"
STATE="$TMP/state"
STUBS="$TMP/stubs"
mkdir -p "$REPO" "$STATE" "$STUBS"
git -C "$REPO" init -q
lv2_assert_scratch_repo "$REPO"

export LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE"

STATE_PATH_SH="${SCRIPT_DIR}/../leadv2-state-path.sh"
BROAD_STATUS_SH="${SCRIPT_DIR}/../leadv2-broad-status.sh"
HOOK_SH="${SCRIPT_DIR}/../../hooks/leadv2-single-lead-beat.sh"
LOG_FILE="$(PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" bash "$STATE_PATH_SH" supervise-loop.log)"
mkdir -p "$(dirname "$LOG_FILE")"

# Plain files OUTSIDE the resolver's link-tree: the composer writes through
# these pins, so every prelude rm/pre-seed acts on real bytes (rm-ing a
# resolver-maintained symlink leaves the state-side target alive — the trap
# test-beat-stamp-agreement.sh documents).
F="$TMP/founder-status.md"
E="$TMP/.founder-status-epoch"

cleanup() { chmod -R u+w "$TMP" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

cat >"$STUBS/collector.sh" <<'COLLECTOR_EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -z "$out" ]] && exit 1
printf '{"sections": {}}' >"$out"
COLLECTOR_EOF
chmod +x "$STUBS/collector.sh"

beat_env() {  # <beat-at> [extra env assignments via caller]
  local beat_at="$1"; shift
  env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" \
    LEADV2_STATUS_COLLECTOR_BIN="$STUBS/collector.sh" \
    LEADV2_FOUNDER_STATUS_PATH="$F" \
    LEADV2_FOUNDER_STATUS_EPOCH_PATH="$E" \
    LEADV2_BROAD_STATUS_BEAT_AT="$beat_at" \
    LEADV2_BROAD_STATUS_DISPATCHED="2" \
    "$@" bash "$BROAD_STATUS_SH" >/dev/null 2>&1
}

last_ready() { grep -E '\[SUPERVISE-URGENT\] BROAD_STATUS_READY ' "$LOG_FILE" 2>/dev/null | tail -n1; }
ready_at()   { last_ready | sed -n 's/.* at=\([^ ]*\).*/\1/p'; }
epoch_iso() {  # ISO-8601 UTC of whatever integer $1 holds
  local v; v="$(cat "$1" 2>/dev/null || true)"
  [[ "$v" =~ ^[0-9]+$ ]] || { printf ''; return; }
  date -u -r "$v" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$v" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}
iso_minus_s() {  # <iso> <seconds> -> ISO that many seconds earlier (portable)
  local ep; ep="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s 2>/dev/null)"
  ep=$(( ep - $2 ))
  date -u -r "$ep" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$ep" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

# ── T1: 25h-old confirmed write -> stale=1, at= = the FILE's stamp ────────
RO_EPOCH_DIR="$TMP/ro-epoch"
mkdir -p "$RO_EPOCH_DIR"
E_OLD="$RO_EPOCH_DIR/.founder-status-epoch"
printf '%s' "$(( $(date +%s) - 25*3600 ))" >"$E_OLD"
chmod 555 "$RO_EPOCH_DIR"   # read+traverse, never write (root caveat: same
                            # class as test-beat-stamp-agreement T3b's RO dir)
: >"$LOG_FILE"; rm -f "$F"
BEAT_AT_PINNED="2026-08-19T09:00:00Z"
beat_env "$BEAT_AT_PINNED" LEADV2_FOUNDER_STATUS_EPOCH_PATH="$E_OLD"
LAST_READY="$(last_ready)"
EXPECTED_AT="$(epoch_iso "$E_OLD")"
if [[ -n "$LAST_READY" && "$LAST_READY" == *' stale=1' ]] \
    && [[ "$(ready_at)" == "$EXPECTED_AT" ]] \
    && [[ "$(ready_at)" != "$BEAT_AT_PINNED" ]]; then
  pass "T1: 25h-old confirmed write -> READY stale=1, at= is the file's epoch stamp (not the beat clock)"
else
  fail "T1: stale labeling wrong: ready=[$LAST_READY] expected_at=[$EXPECTED_AT] beat_at=[$BEAT_AT_PINNED]"
fi

# ── T2: fresh beat -> plain READY, absolute path ──────────────────────────
: >"$LOG_FILE"; rm -f "$F" "$E"
beat_env "2026-08-19T10:00:00Z"
LAST_READY="$(last_ready)"
if [[ -n "$LAST_READY" && "$LAST_READY" != *'stale=1'* ]] \
    && [[ "$(ready_at)" == "$(epoch_iso "$E")" ]] \
    && [[ "$LAST_READY" == *"path=$F "* ]]; then
  pass "T2: fresh beat -> plain READY, at= = this run's epoch stamp, path= absolute"
else
  fail "T2: fresh ready wrong: ready=[$LAST_READY] epoch_iso=[$(epoch_iso "$E")] path_want=[$F]"
fi

# ── T3: mv fails -> FAILED fires, READY never does ────────────────────────
# Destination exists as a directory containing a NON-EMPTY entry named like
# the composer's tmp file, so printf to "$F.tmp" succeeds but
# `mv "$F.tmp" "$F"` dies (rename onto dir/same-name -> ENOTEMPTY) —
# the mv-failure half of the write guard, not the printf-failure half
# (that one is test-beat-stamp-agreement T3b).
: >"$LOG_FILE"
F_DIR="$TMP/mv-fails/founder-status.md"
E3="$TMP/mv-fails/.founder-status-epoch"
mkdir -p "$F_DIR/founder-status.md.tmp/occupied"
beat_env "2026-08-19T11:00:00Z" \
  LEADV2_FOUNDER_STATUS_PATH="$F_DIR" \
  LEADV2_FOUNDER_STATUS_EPOCH_PATH="$E3"
if grep -q 'BROAD_STATUS_FAILED.*founder-status.md write failed' "$LOG_FILE" \
    && ! grep -q 'BROAD_STATUS_READY' "$LOG_FILE"; then
  pass "T3: failed mv -> BROAD_STATUS_FAILED fires, no READY over the day-old file"
else
  fail "T3: write-guard wrong: log=[$(grep -E 'BROAD_STATUS_(READY|FAILED)' "$LOG_FILE" | tail -n1)]"
fi

# ── T4-T6: hook DELIVER gates (fresh log+file+epoch per scenario) ─────────
STUB_PLUGIN_ROOT="$TMP/plugin-stub"
mkdir -p "$STUB_PLUGIN_ROOT/scripts"
# leadv2-portable-lock.sh: main resolver sources it unconditionally
# (leadv2-state-path.sh:86) since the portable-lock rework; without the
# copy the stub resolver dies and every hook-side case silently loses CTX.
for helper in leadv2-state-path.sh leadv2-portable-lock.sh leadv2-beat-owner.sh leadv2-lane-heartbeat.sh leadv2-active-registry.sh; do
  cp "${SCRIPT_DIR}/../$helper" "$STUB_PLUGIN_ROOT/scripts/$helper"
done
printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB_PLUGIN_ROOT/scripts/leadv2-pulse-beat.sh"
chmod +x "$STUB_PLUGIN_ROOT/scripts/leadv2-pulse-beat.sh"

hook_ctx() {  # <epoch-value> <file-line1-stamp> <ready-line-at>
  local epoch_v="$1" line1="$2" at_v="$3" sid="sess-$RANDOM$RANDOM"
  printf -- '%s\n%s\n' "$line1" "row: hook-probe" >"$F"
  printf -- '%s' "$epoch_v" >"$E"
  printf -- '%s [SUPERVISE-URGENT] BROAD_STATUS_READY at=%s path=%s rows=1 dispatched=0\n' \
    "$at_v" "$at_v" "$F" >>"$LOG_FILE"
  printf '{"cwd":"%s","hook_event_name":"UserPromptSubmit","session_id":"%s"}' "$REPO" "$sid" \
    | env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" CLAUDE_PROJECT_DIR="$REPO" \
        CLAUDE_PLUGIN_ROOT="$STUB_PLUGIN_ROOT" \
        LEADV2_FOUNDER_STATUS_PATH="$F" \
        LEADV2_FOUNDER_STATUS_EPOCH_PATH="$E" \
        LEADV2_BEAT_OWNER_OVERRIDE="$sid" \
        LEADV2_SESSION_KIND=lead \
        bash "$HOOK_SH" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    print(d.get('hookSpecificOutput', {}).get('additionalContext', ''))
except Exception:
    print('')
"
}

# T4: confirmed write 25h old -> refused
: >"$LOG_FILE"
CTX4="$(hook_ctx "$(( $(date +%s) - 25*3600 ))" "2026-08-19T12:00:00Z" "2026-08-19T12:00:00Z")"
if printf -- '%s' "$CTX4" | grep -q 'RELAY=refused' \
    && ! printf -- '%s' "$CTX4" | grep -q 'RELAY=full'; then
  pass "T4: hook refuses to relay a 25h-old confirmed write"
else
  fail "T4: expected refusal, got: [$CTX4]"
fi

# T5: stamps disagree by 2h (>= BEAT_S 1800) -> refused
: >"$LOG_FILE"
CTX5="$(hook_ctx "$(date +%s)" "$(iso_minus_s 2026-08-19T12:00:00Z 7200)" "2026-08-19T12:00:00Z")"
if printf -- '%s' "$CTX5" | grep -q 'RELAY=refused' \
    && ! printf -- '%s' "$CTX5" | grep -q 'RELAY=full'; then
  pass "T5: hook refuses on ready-line vs file line-1 stamp mismatch (7200s apart)"
else
  fail "T5: expected mismatch refusal, got: [$CTX5]"
fi

# T6: fresh + stamps agree -> full relay (guards against over-refusing)
: >"$LOG_FILE"
CTX6="$(hook_ctx "$(date +%s)" "2026-08-19T12:00:00Z" "2026-08-19T12:00:00Z")"
if printf -- '%s' "$CTX6" | grep -q 'RELAY=full' \
    && ! printf -- '%s' "$CTX6" | grep -q 'RELAY=refused'; then
  pass "T6: fresh agreeing stamps still get RELAY=full"
else
  fail "T6: over-refusal or wrong ctx: [$CTX6]"
fi

# ── T7: one gathering, one timestamp inside a real artifact ───────────────
: >"$LOG_FILE"; rm -f "$F" "$E"
beat_env "2026-08-19T13:37:00Z"
if head -n1 "$F" 2>/dev/null | grep -q '^2026-08-19T13:37:00Z ' \
    && grep -q '^13:37' "$F" 2>/dev/null; then
  pass "T7: artifact line-1 stamp and product HH:MM both come from the pinned BEAT_AT"
else
  fail "T7: two-clock snapshot: line1=[$(head -n1 "$F" 2>/dev/null)] 1337-lines=[$(grep -c '^13:37' "$F" 2>/dev/null)]"
fi

echo "----------------------------------------"
echo "test-broad-status-stale-file: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
