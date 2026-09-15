#!/usr/bin/env bash
# run-all-triggers: leadv2-spawn-arbiter-gate leadv2-model-inherit-guard leadv2-route-arbiter
# SPAWN-GATE-AND-MODEL-GUARD-DEADLOCK-01 (row bd9c35163b33). Two single-hook
# suites (test-spawn-arbiter-gate.sh, test-spawn-speakable-pool.sh) already
# cover each guard in isolation and were green before this row opened -- an
# isolated pass on both sides is exactly what let the deadlock go unnoticed:
# a REAL Agent spawn is judged by BOTH hooks on the SAME PreToolUse event
# (Claude Code fires every matching hook and denies if any one denies), and
# nothing exercised that composition. This suite runs the two hook scripts
# in sequence for the same payload and asserts the COMBINED verdict, the way
# a live spawn actually experiences them.
#
# Finding (see docs/handoff/SPAWN-GATE-AND-MODEL-GUARD-DEADLOCK-01/report.md
# for the full reproduction): after BUILTIN-AGENT-SPAWN-DEADLOCK-01
# (55d40e29, 2026-09-10) the intersection of spawns both hooks accept is
# NON-EMPTY -- a bare built-in spawn with an explicit non-opus model that
# the arbiter is willing to honour passes both hooks on the first attempt.
# The remaining gap was NOT a code deadlock: it was (a) untested composition
# and (b) one leftover documentation hole -- the gate's own DENY message
# suggests a manual `bash leadv2-route-arbiter.sh worker '{...}'` fallback
# for a spawn whose true work_kind isn't recon, and that suggested command
# did not carry speakable_models, so a human following it verbatim could
# still receive an unspeakable decision (arm=freepool model=freepool-default)
# and walk into the exact deadlock this row exists to close. Fixed by
# threading the same SPEAKABLE_JSON the auto-consult path already uses into
# that suggested command (leadv2-spawn-arbiter-gate.sh, one text edit, no
# decision-logic change). Section F is the test for this.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GATE="${SCRIPTS_DIR}/../hooks/leadv2-spawn-arbiter-gate.sh"
GUARD="${SCRIPTS_DIR}/../hooks/leadv2-model-inherit-guard.sh"
ARB="${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"
export LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING"
export LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh"
export LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh"
export LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state"
export LEADV2_ROUTE_ARBITER_DECISIONS_FILE="$TMP/decisions.jsonl"
export ROUTE_TEST_QUOTA='{"glm":{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":10}]},"anthropic":{"status":"ok","accounts":[{"active":true,"five_hour_pct":10,"seven_day_pct":10}]}}'
reset_journal(){ : > "$LEADV2_ROUTE_ARBITER_DECISIONS_FILE"; }

# guard_verdict: model-inherit-guard is silent (rc0, no stdout) on pass;
# it only prints a JSON deny blob when it denies.
guard_verdict(){
  local out; out="$(printf '%s' "$1" | bash "$GUARD" "${@:2}")"
  if [[ -z "$out" ]]; then echo "allow"; else
    printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])'
  fi
}
guard_reason(){
  local out; out="$(printf '%s' "$1" | bash "$GUARD")"
  [[ -z "$out" ]] && { echo ""; return; }
  printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"].get("permissionDecisionReason",""))'
}
gate_verdict(){ printf '%s' "$1" | bash "$GATE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])'; }
gate_reason(){ printf '%s' "$1" | bash "$GATE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"].get("permissionDecisionReason",""))'; }
gate_ctx(){ printf '%s' "$1" | bash "$GATE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"].get("additionalContext",""))'; }
# combined_verdict: BOTH hooks fire on the same PreToolUse(Agent) event in the
# real harness; any deny wins. This mirrors that, running both, never one
# short-circuiting the other -- exactly what let the deadlock hide before.
combined_verdict(){
  local g v; g="$(guard_verdict "$1")"; v="$(gate_verdict "$1")"
  if [[ "$g" == "deny" || "$v" == "deny" ]]; then echo "deny"; else echo "allow"; fi
}

echo "== A: the reproducer, live -- Explore+haiku through BOTH hooks, first attempt =="
reset_journal
PAY_EH='{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","model":"haiku"}}'
g="$(guard_verdict "$PAY_EH")"; v="$(gate_verdict "$PAY_EH")"; c="$(gate_ctx "$PAY_EH")"
[[ "$g" == "allow" ]] && pass 'A1 model-inherit-guard: explicit non-opus model always passes' || fail "A1 guard=$g"
[[ "$v" == "allow" ]] && pass 'A2 spawn-arbiter-gate: auto-consult grants a fresh decision' || fail "A2 gate=$v"
[[ "$(combined_verdict "$PAY_EH")" == "allow" ]] && pass 'A3 COMBINED (both hooks, same event) -> allow' || fail 'A3 combined denied'
[[ "$c" == *'arm='* && "$c" == *'model=haiku'* ]] && pass "A4 journal line names the decided arm: $c" || fail "A4 ctx=$c"

echo "== B: the still-refused cases must STAY refused (a deadlock 'fix' that opens everything is the same bug, sign flipped) =="
reset_journal
PAY_NOMODEL='{"tool_name":"Agent","tool_input":{"subagent_type":"Explore"}}'
g="$(guard_verdict "$PAY_NOMODEL")"; r="$(guard_reason "$PAY_NOMODEL")"
[[ "$g" == "deny" ]] && pass 'B1 built-in, no model -> model-inherit-guard still denies (its job, not the gate'"'"'s)' || fail "B1 guard=$g"
[[ "$r" == *'inherits the caller'* ]] && pass 'B2 denial names the inheritance reason' || fail "B2 reason=$r"
[[ "$(combined_verdict "$PAY_NOMODEL")" == "deny" ]] && pass 'B3 COMBINED still denies (gate alone would allow via its own consult -- guard is the one holding this line)' || fail 'B3 combined wrongly allowed'
reset_journal
PAY_OPUS='{"tool_name":"Agent","tool_input":{"subagent_type":"developer","model":"opus"}}'
g="$(guard_verdict "$PAY_OPUS")"; r="$(guard_reason "$PAY_OPUS")"
[[ "$g" == "deny" ]] && pass 'B4 non-allowlisted subtype + opus -> model-inherit-guard denies' || fail "B4 guard=$g"
[[ "$r" == *'reserved for high-judgment agents'* ]] && pass 'B5 denial names the opus allowlist reason' || fail "B5 reason=$r"
[[ "$(combined_verdict "$PAY_OPUS")" == "deny" ]] && pass 'B6 COMBINED denies (opus misuse never slips through on the gate side)' || fail 'B6 combined wrongly allowed'

echo "== C: the two-attempt happy path resolves in exactly 2, never loops (the denial's own guidance is actionable) =="
reset_journal
v1="$(combined_verdict "$PAY_NOMODEL")"
# the auto-consult inside the gate call above already recorded a decision for
# subtype=Explore even though the COMBINED verdict was deny (guard vetoed).
rec="$(python3 -c 'import json,sys; rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; r=[x for x in rows if x.get("subtype")=="Explore" and x.get("arm") not in (None,"","refuse")]; print(r[-1]["model"] if r else "")' "$LEADV2_ROUTE_ARBITER_DECISIONS_FILE")"
[[ "$v1" == "deny" && -n "$rec" ]] && pass "C1 attempt 1 denied, but a decision was already recorded (model=$rec) for the retry" || fail "C1 v1=$v1 rec=$rec"
PAY_RETRY="{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"Explore\",\"model\":\"$rec\"}}"
v2="$(combined_verdict "$PAY_RETRY")"
[[ "$v2" == "allow" ]] && pass "C2 attempt 2 (model=$rec, matching the recorded decision) -> COMBINED allow" || fail "C2 v2=$v2"

echo "== D: frontmatter-pinned custom agent, no model on the call -- both hooks pass, no deadlock for the common lane-worker shape =="
reset_journal
PAY_DEV='{"tool_name":"Agent","tool_input":{"subagent_type":"developer"}}'
[[ "$(guard_verdict "$PAY_DEV")" == "allow" ]] && pass 'D1 developer.md pins model: -> model-inherit-guard allows model-less' || fail 'D1 guard denied'
[[ "$(gate_verdict "$PAY_DEV")" == "allow" ]] && pass 'D2 spawn-arbiter-gate allows via consult (binds subtype only)' || fail 'D2 gate denied'
[[ "$(combined_verdict "$PAY_DEV")" == "allow" ]] && pass 'D3 COMBINED allow' || fail 'D3 combined denied'

echo "== E: kill switches on both hooks together still allow (founder escape hatch composes) =="
reset_journal
v="$(LEADV2_ROUTE_ENFORCE=0 gate_verdict "$PAY_EH")"
gv="$(guard_verdict "$PAY_EH")"
[[ "$v" == "allow" && "$gv" == "allow" ]] && pass 'E1 LEADV2_ROUTE_ENFORCE=0 (gate) + explicit model (guard) -> both allow' || fail "E1 gate=$v guard=$gv"

echo "== F: the DENY's own manual-CLI way-forward must carry speakable_models (else IT reopens the deadlock) =="
reset_journal
r="$(LEADV2_SPAWN_GATE_AUTO_CONSULT=0 gate_reason "$PAY_EH")"
[[ "$r" == *'speakable_models'* ]] && pass 'F1 manual way-forward command names speakable_models' || fail "F1 way-forward missing speakable_models: $r"
[[ "$r" == *'"sonnet"'*'"opus"'*'"haiku"'*'"fable"'* ]] && pass 'F2 the suggested JSON carries the full speakable pool, not a partial list' || fail "F2 pool incomplete: $r"

echo "== MUTATION CONTROL 1: strip the way-forward speakable_models translation -> F1 goes RED =="
python3 - "$GATE" "$TMP/gate.nospeak" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
needle = ',\\"speakable_models\\":$SPEAKABLE_JSON'
assert needle in text, "mutation target string not found -- test is stale vs the hook source"
open(dst, 'w').write(text.replace(needle, '', 1))
PY
r="$(printf '%s' "$PAY_EH" | LEADV2_SPAWN_GATE_AUTO_CONSULT=0 bash "$TMP/gate.nospeak" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"].get("permissionDecisionReason",""))')"
if [[ "$r" != *'speakable_models'* ]]; then
  pass 'MC1 mutation bites: without the translation the way-forward omits speakable_models (F1 would be RED)'
else
  fail 'MC1 mutation had no effect -- the check is not testing the real code path'
fi

echo "== MUTATION CONTROL 2: remove the opus-allowlist check -> B4/B6 (still-refused case) goes RED =="
sed 's/architect|critic|security-auditor|leadv2:architect|leadv2:critic|leadv2:security-auditor)/*)/' "$GUARD" > "$TMP/guard.noallowlist"
g="$(printf '%s' "$PAY_OPUS" | bash "$TMP/guard.noallowlist")"
gv="$([[ -z "$g" ]] && echo allow || printf '%s' "$g" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])')"
if [[ "$gv" == "allow" ]]; then
  pass 'MC2 mutation bites: opus misuse now passes model-inherit-guard (B4/B6 would be RED) -- the allowlist check is the operative part'
else
  fail "MC2 mutation had no effect -- guard still denies ($gv)"
fi

printf 'SUMMARY: pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
