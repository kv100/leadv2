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

printf '[TEST] === %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
