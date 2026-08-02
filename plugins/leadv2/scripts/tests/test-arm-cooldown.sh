#!/usr/bin/env bash
# Offline contract tests for the bounded, arm-generic cooldown store.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="${SCRIPT_DIR}/lib/leadv2-arm-cooldown.sh"
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }
expect() { [ "$1" = "$2" ] && pass "$3" || fail "$3 (got: $1)"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/arm-cooldown.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"
export LEADV2_ARM_COOLDOWN_DIR="$ROOT/cooldowns"
export LEADV2_ARM_COOLDOWN_NOW_EPOCH=1000000000
mkdir -p "$HOME"
# shellcheck source=../lib/leadv2-arm-cooldown.sh
source "$LIB"

if bash -n "$LIB" && /bin/bash -n "$LIB"; then pass 'bash 3.2 syntax'; else fail 'bash 3.2 syntax'; fi

arm_cooldown_record codex quota 2099-08-05T10:55:00Z >/dev/null
line="$(tail -n 1 "$LEADV2_ARM_COOLDOWN_DIR/codex.state")"
# Assert the three tokens independently rather than as one ordered glob. The
# library emits `advisory_until=<iso> advisory=ignored`, i.e. the reverse of the
# order the single glob demanded, so this failed while the BEHAVIOUR under test
# -- a 2099 advisory bounded to the 900s default -- was exactly right. A test
# that fails on field order is a test that will be silenced rather than read.
if printf '%s' "$line" | grep -q 'cooldown_s=900' \
   && printf '%s' "$line" | grep -q 'advisory=ignored' \
   && printf '%s' "$line" | grep -q 'advisory_until=2099-08-05T10:55:00Z'; then
  pass 'five-day advisory cannot extend default cooldown'
else
  fail "five-day advisory cap (got: $line)"
fi
expect "$(arm_cooldown_state codex)" 'cooling 2001-09-09T02:01:40Z quota' 'state reports bounded reprobe time'

arm_cooldown_clear glm
arm_cooldown_record glm peak 2001-09-09T01:48:20Z >/dev/null
line="$(tail -n 1 "$LEADV2_ARM_COOLDOWN_DIR/glm.state")"
case "$line" in *'cooldown_s=100'*'advisory=shortened'*) pass 'future short advisory shortens cooldown' ;; *) fail "shorten rule (got: $line)" ;; esac

arm_cooldown_clear kimi
arm_cooldown_record kimi quota 2001-09-09T01:46:41Z >/dev/null
line="$(tail -n 1 "$LEADV2_ARM_COOLDOWN_DIR/kimi.state")"
case "$line" in *'cooldown_s=60'*'advisory=shortened'*) pass 'floor applies to near advisory' ;; *) fail "floor rule (got: $line)" ;; esac

arm_cooldown_clear sonnet
LEADV2_ARM_COOLDOWN_S=99999 arm_cooldown_record sonnet quota >/dev/null
line="$(tail -n 1 "$LEADV2_ARM_COOLDOWN_DIR/sonnet.state")"
case "$line" in *'cooldown_s=3600'*) pass 'hard cap applies to configuration too' ;; *) fail "hard cap (got: $line)" ;; esac

export LEADV2_ARM_COOLDOWN_NOW_EPOCH=1000000901
expect "$(arm_cooldown_state codex)" clear 'expired record self-heals to clear'
printf '%s\n' junk > "$LEADV2_ARM_COOLDOWN_DIR/bad.state"
expect "$(arm_cooldown_state bad)" clear 'malformed store fails open'
expect "$(arm_cooldown_state '../escape')" clear 'invalid arm fails open'
arm_cooldown_ladder_note codex quota 2001-09-09T02:01:40Z >/dev/null
[ -s "$LEADV2_ARM_COOLDOWN_DIR/codex.journal" ] && pass 'ladder journal is durable' || fail 'ladder journal is durable'

# ── N1B-ARM-COOLDOWN-HARDEN ──────────────────────────────────────────────────
# Pin a fixed clock for this block -- the suite mutates NOW_EPOCH to 1000000901
# at its midpoint and never restores it, so every expected stamp is derived, not
# hardcoded. Use the library's own formatter so the assertion mirrors behaviour.
export LEADV2_ARM_COOLDOWN_NOW_EPOCH=1000000000
N1B_NOW=1000000000

# F1: an operator cannot RAISE the ceiling. LEADV2_ARM_COOLDOWN_S=99999
# LEADV2_ARM_COOLDOWN_MAX_S=99999 must record cooldown_s=3600 (the hard bound)
# and a reprobe_at exactly 3600s after now -- not the ~27.8h the same env
# produces on 30ad24e.
arm_cooldown_clear f1max
LEADV2_ARM_COOLDOWN_S=99999 LEADV2_ARM_COOLDOWN_MAX_S=99999 arm_cooldown_record f1max quota >/dev/null
line="$(tail -n 1 "$LEADV2_ARM_COOLDOWN_DIR/f1max.state")"
f1_exp_reprobe="$(_arm_cooldown_epoch_iso $((N1B_NOW + 3600)))"
if printf '%s' "$line" | grep -q 'cooldown_s=3600' \
   && printf '%s' "$line" | grep -q "reprobe_at=${f1_exp_reprobe}"; then
  pass "F1: env ceiling above HARD_MAX is clamped to 3600, reprobe exactly 3600s out (${f1_exp_reprobe})"
else
  fail "F1: hard ceiling clamp (got: $line)"
fi

# F1b: an operator MAY lower the ceiling (a shorter cooldown only re-probes
# sooner; always safe). Guards against over-clamping.
arm_cooldown_clear f1min
LEADV2_ARM_COOLDOWN_MAX_S=120 arm_cooldown_record f1min quota >/dev/null
line="$(tail -n 1 "$LEADV2_ARM_COOLDOWN_DIR/f1min.state")"
case "$line" in *'cooldown_s=120'*) pass 'F1b: operator-lowered ceiling (120) is honoured' ;; *) fail "F1b: lowered ceiling (got: $line)" ;; esac

# F2: octal input. LEADV2_ARM_COOLDOWN_MAX_S=08 used to write reprobe_at= empty
# (value too great for base) and state then read `clear` right after a refusal.
arm_cooldown_clear f2oct
err="$(LEADV2_ARM_COOLDOWN_MAX_S=08 arm_cooldown_record f2oct quota 2>&1 >/dev/null)"
line="$(tail -n 1 "$LEADV2_ARM_COOLDOWN_DIR/f2oct.state")"
reprobe_f2="$(printf '%s' "$line" | sed -n 's/.* reprobe_at=\([^ ]*\).*/\1/p')"
if [ -n "$reprobe_f2" ] && [ "$(_arm_cooldown_iso_epoch "$reprobe_f2")" -gt 0 ] \
   && ! printf '%s' "$err" | grep -qi 'value too great for base'; then
  pass 'F2: MAX_S=08 produces a non-empty parseable reprobe_at, no octal error'
else
  fail "F2: octal sanitize (reprobe_at=[$reprobe_f2], err=[$err])"
fi
state_f2="$(arm_cooldown_state f2oct)"
case "$state_f2" in cooling\ *) pass 'F2: MAX_S=08 state reads cooling after a real refusal' ;; *) fail "F2: octal state (got: $state_f2)" ;; esac

# F2b: same class via the now-epoch test hook and MIN_S. A leading-zero NOW or
# MIN must not detonate arithmetic either.
arm_cooldown_clear f2b
LEADV2_ARM_COOLDOWN_NOW_EPOCH=08 LEADV2_ARM_COOLDOWN_MIN_S=09 arm_cooldown_record f2b quota 2>/dev/null >/dev/null
line="$(tail -n 1 "$LEADV2_ARM_COOLDOWN_DIR/f2b.state")"
reprobe_f2b="$(printf '%s' "$line" | sed -n 's/.* reprobe_at=\([^ ]*\).*/\1/p')"
if [ -n "$reprobe_f2b" ] && [ "$(_arm_cooldown_iso_epoch "$reprobe_f2b")" -gt 0 ]; then
  pass 'F2b: NOW_EPOCH=08 + MIN_S=09 produce a parseable reprobe_at'
else
  fail "F2b: now/min octal (reprobe_at=[$reprobe_f2b])"
fi
# restore the suite's canonical fixed clock for any later assertions
export LEADV2_ARM_COOLDOWN_NOW_EPOCH=1000000000

# F3: the stale-writer race is no longer possible. Record at t0+800 first
# (newer refusal, cooling until t0+1700), THEN record at t0 (a writer that
# sampled now=t0 and stalled, landing late -- cooling only until t0+900), then
# read at t0+1000. On 30ad24e tail -n 1 picks the stale t0+900 row -> clear;
# after the fix the max-reprobe_at scan reads cooling with the t0+1700 stamp.
arm_cooldown_clear f3
t0=2000000000
LEADV2_ARM_COOLDOWN_NOW_EPOCH=$((t0 + 800)) arm_cooldown_record f3 quota >/dev/null
LEADV2_ARM_COOLDOWN_NOW_EPOCH="$t0" arm_cooldown_record f3 quota >/dev/null
LEADV2_ARM_COOLDOWN_NOW_EPOCH=$((t0 + 1000)) true
state_f3="$(LEADV2_ARM_COOLDOWN_NOW_EPOCH=$((t0 + 1000)) arm_cooldown_state f3)"
# t0+1700 = 2000001700 -> 2033-05-18T03:21:40Z
case "$state_f3" in
  *'2033-05-18T03:21:40Z'*|cooling\ *) pass 'F3: stale late writer cannot shorten a live cooldown' ;;
  *) fail "F3: stale-writer race (got: $state_f3)" ;;
esac
# tighten: the verdict must carry the NEWER (t0+1700) stamp, not t0+900
exp_f3="$(_arm_cooldown_epoch_iso $((t0 + 1700)))"
if [ "$state_f3" = "cooling ${exp_f3} quota" ]; then
  pass 'F3: verdict reports the t0+1700 reprobe (the newer refusal wins)'
else
  fail "F3: newer-stamp wins (got: $state_f3, want: cooling ${exp_f3} quota)"
fi

# F3b: clear still clears (the max-scan must not leak past a truncation).
arm_cooldown_clear f3
state_f3b="$(LEADV2_ARM_COOLDOWN_NOW_EPOCH=$((t0 + 1000)) arm_cooldown_state f3)"
[ "$state_f3b" = clear ] && pass 'F3b: arm_cooldown_clear after the race -> clear' || fail "F3b: clear after race (got: $state_f3b)"

export LEADV2_ARM_COOLDOWN_NOW_EPOCH=1000000000

printf '[TEST] === %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
