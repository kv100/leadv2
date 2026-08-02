#!/usr/bin/env bash
# The old test proved two unbounded readers agreed on 2099.  This one proves
# the public status front-end and the real gate share a bounded policy.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCKOUT_SH="${SCRIPT_DIR}/leadv2-codex-lockout.sh"
CODEX_TASK_SH="${SCRIPT_DIR}/codex-task.sh"
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-cooldown.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"
export LEADV2_ARM_COOLDOWN_DIR="$ROOT/cooldowns"
export LEADV2_ARM_COOLDOWN_NOW_EPOCH=1000000000
export LEADV2_QUOTA_LIVE="$ROOT/quota-live"
export GLM_BIN="$ROOT/glm" CODEX_BIN="$ROOT/codex"
mkdir -p "$HOME/.claude/plugins/cache/openai-codex/v1/scripts"
printf 'process.exit(0);\n' > "$HOME/.claude/plugins/cache/openai-codex/v1/scripts/codex-companion.mjs"
printf '#!/usr/bin/env bash\nprintf %s\\n '\''{"status":"ok","windows":[]} '\''\n' > "$LEADV2_QUOTA_LIVE"
chmod +x "$LEADV2_QUOTA_LIVE"

if bash -n "$LOCKOUT_SH" && bash -n "$CODEX_TASK_SH"; then pass 'shell syntax'; else fail 'shell syntax'; fi

source "${SCRIPT_DIR}/lib/leadv2-arm-cooldown.sh"
arm_cooldown_record codex quota 2099-08-05T10:55:00Z >/dev/null
line="$(tail -n 1 "$LEADV2_ARM_COOLDOWN_DIR/codex.state")"
case "$line" in
  *'cooldown_s=900'*'advisory=ignored'*) pass 'policy: 2099 advisory is bounded to 900 seconds' ;;
  *) fail "policy: future advisory extended cooldown ($line)" ;;
esac

helper="$(bash "$LOCKOUT_SH")"
[ "$helper" = 'locked 2001-09-09T02:01:40Z' ] && pass 'front-end reports shared reprobe time' || fail "front-end (got: $helper)"

out="$(CODEX_AUTOREAP=0 timeout 20 bash "$CODEX_TASK_SH" task --cwd /tmp 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -q 'reason=cooldown' \
  && printf '%s\n' "$out" | grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate'; then
  pass 'real gate refuses with unchanged quota_gate grammar'
else
  fail "real gate cooling refusal (rc=$rc, got: $out)"
fi

export LEADV2_ARM_COOLDOWN_NOW_EPOCH=1000000901
helper="$(bash "$LOCKOUT_SH")"
[ "$helper" = clear ] && pass 'front-end self-heals after reprobe time' || fail "expiry front-end (got: $helper)"
out="$(CODEX_AUTOREAP=0 timeout 20 bash "$CODEX_TASK_SH" task --cwd /tmp 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s\n' "$out" | grep -q 'reason=cooldown'; then
  pass 'real gate re-probes rather than preserving a remembered verdict'
else
  fail "expiry gate (rc=$rc, got: $out)"
fi

printf '[TEST] === %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
