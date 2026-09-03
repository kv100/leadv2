#!/usr/bin/env bash
# test-quota-reset-arbiter.sh — CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01
#
# Proves the route arbiter (lib/leadv2-route-arbiter.sh) reads BOTH remaining
# budget and reset time per arm, not just raw used-pct, and applies the
# wait-vs-switch rule: an over-ceiling provider whose binding window resets
# within 10% of that window's own period is waited on (stays in the running,
# journaled wait_applied=<provider>) instead of forced to switch; a provider
# whose reset is far stays capped exactly as before.
#
# Source of truth for hours_to_reset: leadv2-quota-read.py:113-142
# (normalize_window/with_window_truth) already computes and embeds this field
# into the same JSON leadv2-quota-live.sh json returns for glm/codex/anthropic
# — the arbiter fixture below simulates that already-normalized shape (the
# fake LEADV2_ROUTE_ARBITER_QUOTA_LIVE seam bypasses the real reader, same
# convention test-route-arbiter.sh already uses).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# LEADV2_TEST_ARBITER_BIN: injection seam for negative controls (nc-*.sh) --
# lets a control run this whole suite against a mutated PRIVATE COPY of the
# arbiter without ever touching the tracked file. Mirrors the
# LEADV2_TEST_SELECT_BIN convention used by test-claude-profile-select.sh /
# nc-claude-account-collapse.sh.
ARBITER="${LEADV2_TEST_ARBITER_BIN:-${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh}"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "$TMP/free.sh"

# quota_reset <glm_pct> <glm_hours_to_reset> <codex_pct> <claude_pct>
# glm's five_hour window carries the forged pct/hours_to_reset; its weekly
# window and both other providers are given healthy, far-reset numbers so
# they are always capable alternatives — the assertions below are about
# whether glm specifically stays in the running, not about whether anything
# resolves at all.
quota_reset() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json,sys
g,h,c,a=sys.argv[1:]
print(json.dumps({
  'glm': {'status':'ok',
          'five_hour':{'pct':float(g),'hours_to_reset':float(h),'reset_iso':'forged-fixture'},
          'weekly':{'pct':5.0,'hours_to_reset':1000.0,'reset_iso':'forged-fixture'}},
  'codex': {'status':'ok','binding_window':'primary',
            'windows':[{'kind':'primary','used_percent':float(c),'hours_to_reset':1000.0,'reset_iso':'forged-fixture'}]},
  'anthropic': {'status':'ok','accounts':[{'active':True,
            'five_hour_pct':float(a),'seven_day_pct':float(a),
            'five_hour':{'pct':float(a),'hours_to_reset':1000.0,'reset_iso':'forged-fixture'},
            'seven_day':{'pct':float(a),'hours_to_reset':1000.0,'reset_iso':'forged-fixture'}}]}
}))
PY
}

cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
chmod +x "$TMP/live.sh"

run_with() { # <arbiter-path> <quota-json> <descriptor-json> [free_rc=0]
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" \
  ROUTE_TEST_QUOTA="$2" ROUTE_TEST_FREE_RC="${4:-0}" bash -c 'source "$0"; route_arbiter worker "$1"' "$1" "$3"
}

# (a) WAIT: glm at 85% (over the 80% work ceiling, config/leadv2-routing.yaml
# quota_ceilings.glm.work_pct) with its five_hour window resetting in 20
# minutes = 0.333h — well under 10% of the 5h period (30min) — must NOT be
# excluded: it stays in the chain and is journaled wait_applied=glm.
rm -f "$TMP/state"
out_wait="$(run_with "$ARBITER" "$(quota_reset 85 0.333 20 20)" '{"kind":"code","size":"standard"}')"
if [[ "$out_wait" == *'wait_applied=glm'* ]]; then
  pass '(a) near-reset over-ceiling glm is waited on, not switched away'
else
  fail "(a) wait_applied=glm missing: $out_wait"
fi

# (b) SWITCH: identical 85% burn, but hours_to_reset=96 (far past the 0.5h
# threshold for a five_hour-named window) — glm must be excluded/switched
# exactly like the pre-existing (no-reset-awareness) behaviour.
rm -f "$TMP/state"
out_switch="$(run_with "$ARBITER" "$(quota_reset 85 96 20 20)" '{"kind":"code","size":"standard"}')"
if [[ "$out_switch" != *'wait_applied=glm'* && "$out_switch" != *'arm=glm '* && "$out_switch" != *'arm=glm-flash '* ]]; then
  pass '(b) far-reset over-ceiling glm switches away as before'
else
  fail "(b) unexpected wait/selection: $out_switch"
fi

# (c) The winning arm's own remaining=/reset_in= ride the SAME journal line
# it was picked on — "a decision that cannot be read back from the journal
# did not happen" (mission item 2).
if [[ "$out_wait" =~ remaining=(unknown|n/a|[0-9.]+) && "$out_wait" =~ reset_in=(n/a|[0-9.]+h) ]]; then
  pass '(c) journal line carries remaining= and reset_in= for the winning arm'
else
  fail "(c) remaining=/reset_in= missing: $out_wait"
fi

# (d) Per-provider reset_<provider>= tokens are present even on a refusal
# path (ufmt() feeds both the win line and the two refusal prints) — a
# refused round is diagnosable from the journal too, not just a win.
rm -f "$TMP/state"
out_refuse="$(run_with "$ARBITER" "$(quota_reset 96 96 96 96)" '{"kind":"code","size":"standard"}' 1 || true)"
if [[ "$out_refuse" == *'reason=all_arms_capped'* && "$out_refuse" == *'reset_glm='* ]]; then
  pass '(d) refusal path still names each provider reset_<provider>='
else
  fail "(d) refusal path missing reset_ tokens: $out_refuse"
fi

# (e) NEGATIVE CONTROL — mutation on a PRIVATE COPY, never the tracked file
# (the checked-in production file is never touched, so a crash mid-test
# cannot leave the repo dirty for a concurrent lane). Zero out
# WAIT_FRACTION_OF_PERIOD so near_reset_wait() can never fire, then rerun
# case (a)'s exact fixture — must go RED (wait_applied=glm absent), proving
# the assertion is load-bearing and not a vacuous pass.
mutated="$TMP/mutated-route-arbiter.sh"
sed 's/WAIT_FRACTION_OF_PERIOD=0.10/WAIT_FRACTION_OF_PERIOD=0.0/' "$ARBITER" > "$mutated"
if diff -q "$ARBITER" "$mutated" >/dev/null; then
  fail '(e) mutation anchor not found -- cannot prove the control'
else
  rm -f "$TMP/state"
  out_mutated="$(run_with "$mutated" "$(quota_reset 85 0.333 20 20)" '{"kind":"code","size":"standard"}')"
  if [[ "$out_mutated" != *'wait_applied=glm'* ]]; then
    pass '(e RED) threshold=0 mutation flips case (a) to switch -- control is load-bearing'
  else
    fail "(e RED) mutation did not flip the outcome: $out_mutated"
  fi
fi

# (e2) REVERT — the real (unmutated) file, same fixture as (a), is green
# again: proves the mutation (not something else) caused (e)'s red.
rm -f "$TMP/state"
out_revert="$(run_with "$ARBITER" "$(quota_reset 85 0.333 20 20)" '{"kind":"code","size":"standard"}')"
if [[ "$out_revert" == *'wait_applied=glm'* ]]; then
  pass '(e2 GREEN) revert to the real file: green again'
else
  fail "(e2 GREEN) revert did not restore green: $out_revert"
fi

# (f) Reader-level default (mission item 1: "say what happens when a
# provider does not publish a reset time"): leadv2-quota-read.py's own
# normalize_window degrades a missing/malformed reset_iso to
# remaining_pct=None/hours_to_reset=None/usable_now=None — unknown, never a
# silent zero. This is the reader-side half of the contract; the arbiter's
# own default (full window period, case a/b above) is the consumer-side half.
READER="${SCRIPTS_DIR}/leadv2-quota-read.py"
reader_out="$(python3 -c "
import sys; sys.path.insert(0, '${SCRIPTS_DIR}')
import importlib.util
spec = importlib.util.spec_from_file_location('qr', '${READER}')
qr = importlib.util.module_from_spec(spec); spec.loader.exec_module(qr)
print(qr.normalize_window(85.0, None))
print(qr.normalize_window(85.0, 'not-a-timestamp'))
")"
if [[ "$reader_out" == *"'remaining_pct': None, 'hours_to_reset': None, 'usable_now': None"* ]]; then
  pass '(f) reader-level normalize_window degrades a missing/malformed reset to unknown, never zero'
else
  fail "(f) reader default changed: $reader_out"
fi

# (g) UNKNOWN WINDOW NAME (fix-round item 1): codex's binding window is named
# 'primary' -- not one of the known names in WINDOW_PERIOD_HOURS
# (five_hour/weekly/seven_day) -- and carries no limit_window_seconds, so its
# period cannot be derived at all. codex is over its 90% work ceiling
# (config/leadv2-routing.yaml quota_ceilings.codex.work_pct) with a real,
# very short hours_to_reset=0.1. The pre-fix bug guessed
# DEFAULT_PERIOD_HOURS=168h for any unknown name, so 0.1<=16.8h WAITED on a
# burnt codex; an unknown window NAME must degrade the same direction as an
# unknown RESET -- away, never toward staying on a possibly-burnt provider --
# so this must SWITCH (no wait_applied=codex) and the journal must name the
# basis reset_basis=unknown_window for codex specifically (never
# default_full_period, which means a different case: a KNOWN period with an
# unreadable reset).
quota_reset_unknown_window() { # <codex_pct> <codex_hours_to_reset>
  python3 - "$1" "$2" <<'PY'
import json,sys
c,h=sys.argv[1:]
print(json.dumps({
  'glm': {'status':'ok',
          'five_hour':{'pct':5.0,'hours_to_reset':1000.0,'reset_iso':'forged-fixture'},
          'weekly':{'pct':5.0,'hours_to_reset':1000.0,'reset_iso':'forged-fixture'}},
  'codex': {'status':'ok','binding_window':'primary',
            'windows':[{'kind':'primary','used_percent':float(c),'hours_to_reset':float(h),'reset_iso':'forged-fixture'}]},
  'anthropic': {'status':'ok','accounts':[{'active':True,
            'five_hour_pct':5.0,'seven_day_pct':5.0,
            'five_hour':{'pct':5.0,'hours_to_reset':1000.0,'reset_iso':'forged-fixture'},
            'seven_day':{'pct':5.0,'hours_to_reset':1000.0,'reset_iso':'forged-fixture'}}]}
}))
PY
}
rm -f "$TMP/state"
out_unknown_window="$(run_with "$ARBITER" "$(quota_reset_unknown_window 96 0.1)" '{"kind":"code","size":"standard"}')"
if [[ "$out_unknown_window" != *'wait_applied=codex'* && "$out_unknown_window" == *'reset_codex=0.10h_unknown_window'* ]]; then
  pass '(g) unknown window NAME switches away, never waits, and reports reset_basis=unknown_window'
else
  fail "(g) unexpected unknown-window handling: $out_unknown_window"
fi

# (h) UNREADABLE RESET AT THE ARBITER LEVEL: glm's five_hour window carries
# NO hours_to_reset field at all (the live payload genuinely could not
# compute one) while its window NAME stays known ('five_hour') -- this is the
# case window_reset()'s default_full_period branch exists for, and it is
# distinct from (f), which only proves the READER's normalize_window default
# — this proves the ARBITER's own consumer-side default. glm is 85% (over
# its 80% work ceiling); the arbiter must degrade the unreadable reset to the
# window's FULL period (5h), never a silent zero, so glm still SWITCHES
# (never wait_applied=glm) and the journal names reset_basis=default_full_period.
quota_reset_unreadable_glm_reset() { # <glm_pct>
  python3 - "$1" <<'PY'
import json,sys
g=sys.argv[1]
print(json.dumps({
  'glm': {'status':'ok',
          'five_hour':{'pct':float(g)},
          'weekly':{'pct':5.0,'hours_to_reset':1000.0,'reset_iso':'forged-fixture'}},
  'codex': {'status':'ok','binding_window':'primary',
            'windows':[{'kind':'primary','used_percent':5.0,'hours_to_reset':1000.0,'reset_iso':'forged-fixture'}]},
  'anthropic': {'status':'ok','accounts':[{'active':True,
            'five_hour_pct':5.0,'seven_day_pct':5.0,
            'five_hour':{'pct':5.0,'hours_to_reset':1000.0,'reset_iso':'forged-fixture'},
            'seven_day':{'pct':5.0,'hours_to_reset':1000.0,'reset_iso':'forged-fixture'}}]}
}))
PY
}
rm -f "$TMP/state"
out_unreadable="$(run_with "$ARBITER" "$(quota_reset_unreadable_glm_reset 85)" '{"kind":"code","size":"standard"}')"
if [[ "$out_unreadable" != *'wait_applied=glm'* && "$out_unreadable" == *'reset_glm=5.00h_default_full_period'* ]]; then
  pass '(h) unreadable reset at the arbiter level degrades to the full period, never a silent zero'
else
  fail "(h) unexpected unreadable-reset handling: $out_unreadable"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
