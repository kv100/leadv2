#!/usr/bin/env bash
# PULSE-BEATS-IN-IDLE-REPOS-01 / PULSE-BEATS-A-FILE-NOBODY-REWRITES-01 — the beat must
# say WHAT it is asserting, and whether the bytes behind it moved.
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: leadv2-broad-status leadv2-backlog-pump
#
# THE FRAME, before any fix. `live=0` was unfalsifiable: a reader could not tell a
# broken pulse from a correct one reporting an idle repository while lanes ran in a
# sibling one. Measured 2026-09-05 — two `live=0` beats in persona-engine while the
# reporting session's lanes were live in leadv2, and the pulse was RIGHT both times.
# So the work is not "stop beating", it is "declare the claim": live= counts LIVE LANE
# ROWS IN THIS REPOSITORY'S REGISTRY, joined from the liveness probe against that
# repo's active.yaml — not "is anyone working", and not "anywhere".
#
# THE SECOND HALF. at= is the artifact's mtime/epoch stamp, and mtime freshness is not
# CONTENT freshness: anything that touches the file without rewriting it leaves a fresh
# stamp on stale text, and the beat announces the past as the present. The artifact's
# first line carries its own stamp, so the comparison the relay contract asks a reader
# to do by eye is done at the emitter instead.
#
# WHAT IS REAL HERE. The production _emit_ready_line body is lifted out of
# leadv2-broad-status.sh and sourced with the closure its real caller provides; only
# _now_iso and _file_age_s are faked, to fixed values. No rule is restated.
#
# DECLARED NEGATIVE CONTROL (tests/mutations/catalog.yaml): the content_at extraction
# is blanked, so a touched-but-unrewritten artifact reads fresh again. Kills (c) and
# leaves (d) — the file that IS rewritten — green, which is the pair.
set -uo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
BS="${ROOT}/scripts/leadv2-broad-status.sh"
PUMP="${ROOT}/scripts/leadv2-backlog-pump.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# ── (a),(b): the pump's own line must declare the scope of live= ───────────────
# HONEST LABEL: these two are SOURCE-FORMAT assertions, not behaviour. Driving the
# pump's check-complete line for real means running cmd_check, which dispatches --
# real worktrees, real ledger rows, a real spawned worker -- and a probe with side
# effects is not a probe. They pin that the format carries a scope and derives it from
# the registry actually counted; they cannot prove the value is right at runtime. The
# behavioural half of this suite is (c)/(d) below.
if grep -q 'live_scope=' "$PUMP" && grep -q 'live_means=lane_rows_in_this_repo_registry' "$PUMP"; then
  ok "[source-format] the check-complete line declares live_scope= and what live= means"
else
  bad "a: check complete line does not declare its scope"
fi
# and the scope must be DERIVED from the registry it actually counted, never a literal
if grep -q '_live_scope="\$(basename "\$(dirname "\${ACTIVE_YAML}")"' "$PUMP"; then
  ok "[source-format] the declared scope is derived from the registry that was counted"
else
  bad "b: scope is not derived from ACTIVE_YAML"
fi

# ── (c),(d): the beat must not call a touched-but-unrewritten artifact fresh ───
python3 - "$BS" "$T/ready.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
start = s.index('_emit_ready_line() {')
end = s.index('\n}\n', start) + 3
open(sys.argv[2], 'w').write(s[start:end])
PY
_now_iso(){ printf '2026-09-06T00:00:00Z'; }
_file_age_s(){ printf '10'; }   # young by mtime: the age rung must NOT be what fires
BEAT_AT='2026-09-06T00:00:00Z'; DISPATCHED=0; PROJECT_ROOT="$T"
LOG_FILE="$T/beat.log"; : > "$LOG_FILE"
FOUNDER_STATUS_PATH="$T/founder-status.md"
FOUNDER_STATUS_EPOCH_PATH="$T/founder-status.epoch"
source "$T/ready.sh" 2>/dev/null || { bad "could not source _emit_ready_line"; }

# (c) the artifact was TOUCHED (fresh epoch) but its text is from an earlier beat.
printf '2026-09-04T12:51:55Z [BROAD_STATUS] dispatched=unavailable\nold body\n' > "$FOUNDER_STATUS_PATH"
printf '%s\n' "$(date -u +%s)" > "$FOUNDER_STATUS_EPOCH_PATH"
: > "$LOG_FILE"; _emit_ready_line 3 2>/dev/null
C="$(cat "$LOG_FILE")"
if [[ "$C" == *"content_at=2026-09-04T12:51:55Z"* && "$C" == *"stale=1"* ]]; then
  ok "a touched-but-unrewritten artifact is announced stale, with its content stamp"
else
  bad "c: got '$(printf '%s' "$C" | tr '\n' ' ' | cut -c1-200)'"
fi

# (d) THE MANDATORY PAIRED NEGATIVE: an artifact that IS rewritten must still read
# fresh. Without this, "stop calling things fresh" would pass on a beat that calls
# everything stale, which is just as useless.
now_epoch="$(date -u +%s)"
now_iso="$(date -u -r "$now_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$now_epoch" +%Y-%m-%dT%H:%M:%SZ)"
printf '%s [BROAD_STATUS] dispatched=0\nfresh body\n' "$now_iso" > "$FOUNDER_STATUS_PATH"
printf '%s\n' "$now_epoch" > "$FOUNDER_STATUS_EPOCH_PATH"
: > "$LOG_FILE"; _emit_ready_line 3 2>/dev/null
D="$(cat "$LOG_FILE")"
if [[ "$D" == *"content_at=${now_iso}"* && "$D" != *"stale=1"* ]]; then
  ok "an artifact that really was rewritten is still fresh"
else
  bad "d: got '$(printf '%s' "$D" | tr '\n' ' ' | cut -c1-200)'"
fi

printf '[PULSE-DECLARES-ITS-SCOPE] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
