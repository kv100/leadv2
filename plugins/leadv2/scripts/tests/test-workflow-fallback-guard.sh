#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# FABLE-THINK-TIER-01 R9: the unguarded-fallback behavioural proof (executes the workflow .js via
# a Node harness, not a grep) lives in its own suite — map every workflow file it actually runs.
# run-all-triggers: leadv2-audit.js leadv2-diverge.js leadv2-po-feedback-loop.js
# FABLE-THINK-TIER-01 R9 — closes the "unguarded resilience-fallback" pattern that survived two
# review rounds (leadv2-diverge.js:146 judge-opus-fallback, leadv2-po-feedback-loop.js:194
# audit-opus-fallback): a fallback call that exists ONLY to survive a primary agent() failure was
# itself a bare `await agent(...)` (or a `.then()` chain with no `.catch`) outside any try/catch —
# so a REJECTION of the fallback itself aborted the whole workflow before its own reconciliation
# step (Select phase / Build-Verify-Iterate) ever ran.
#
# This suite actually EXECUTES the workflow .js files (not a grep) via a minimal Node harness that
# stubs the runtime globals (agent/parallel/phase/log) the Workflow tool would otherwise provide,
# and drives the fallback call to REJECT. Proves two things per file:
#   1. baseline (current, fixed tree) — the workflow reaches its final `return` (reconciliation)
#      even when every fallback attempt rejects; it never throws.
#   2. negative control (git HEAD's pre-round-9 committed source, i.e. the actual reviewed defect)
#      — the SAME scenario against the SAME harness DOES throw, proving the harness is falsifiable
#      and the fix is what closes the gap (not a harness artifact).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPTS_ROOT/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

if ! command -v node >/dev/null 2>&1; then
  fail "node not found on PATH — required to execute the workflow .js files under test"
  log "PASS=$PASS FAIL=$FAIL"
  exit 1
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── Node harness: loads a workflow source file as an AsyncFunction body and runs it with stubbed
# runtime globals. agent() behaviour per call-site is driven entirely by the scenario JSON, keyed
# by the call's `label` option — this is the ONLY thing the harness controls, so a scenario that
# stubs a fallback label to reject is testing exactly (and only) that call site's guard.
cat > "$TMP/harness.mjs" <<'HARNESS_EOF'
import fs from 'fs'
const [, , wfPath, scenarioPath] = process.argv
// The real Workflow tool parses the leading `export const meta = {...}` separately and runs the
// rest of the file as an async function body — an AsyncFunction body can't contain a top-level
// `export`, so strip it the same way here (harmless: `meta` just becomes an unused local const).
const source = fs.readFileSync(wfPath, 'utf8').replace(/^export const meta/, 'const meta')
const scenario = JSON.parse(fs.readFileSync(scenarioPath, 'utf8'))
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor

const calls = []
async function agent(prompt, opts) {
  const label = (opts && opts.label) || '(no-label)'
  calls.push(label)
  const stub = scenario.stubs[label]
  if (!stub) return { ok: true }
  if (stub.type === 'reject') throw new Error(`stub-reject:${label}`)
  if (stub.type === 'null') return null
  return stub.value
}
async function parallel(fns) { return Promise.all(fns.map(f => f())) }
function phase(name) { calls.push(`phase:${name}`) }
function log(_msg) {}
async function pipeline(items, mapFn) { return Promise.all(items.map(mapFn)) }

;(async () => {
  try {
    // Constructing the AsyncFunction is where a SyntaxError in the workflow source surfaces
    // (e.g. a stray closing paren) — keep it inside the try so a file that doesn't even parse
    // reports as a normal { ok: false } result instead of crashing the harness process.
    const fn = new AsyncFunction('args', 'agent', 'parallel', 'phase', 'log', 'pipeline', source)
    const result = await fn(scenario.args, agent, parallel, phase, log, pipeline)
    process.stdout.write(JSON.stringify({ ok: true, result, calls }))
  } catch (e) {
    process.stdout.write(JSON.stringify({ ok: false, error: String((e && e.message) || e), calls }))
  }
})()
HARNESS_EOF

# run_case <desc> <workflow-js-file> <scenario-json-file> <expect: ok|throws>
run_case() {
  local desc="$1" wf="$2" scenario="$3" expect="$4"
  local out
  out="$(node "$TMP/harness.mjs" "$wf" "$scenario" 2>"$TMP/stderr.$$")"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    fail "$desc — harness itself crashed (rc=$rc): $(cat "$TMP/stderr.$$" 2>/dev/null | tail -3)"
    rm -f "$TMP/stderr.$$"
    return
  fi
  rm -f "$TMP/stderr.$$"
  local got_ok
  got_ok="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["ok"])' 2>/dev/null)"
  if [[ "$expect" == "ok" && "$got_ok" == "True" ]]; then
    pass "$desc — workflow reached its final return (reconciliation) despite the rejected fallback"
  elif [[ "$expect" == "throws" && "$got_ok" == "False" ]]; then
    local err
    err="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["error"])' 2>/dev/null)"
    pass "$desc — negative control confirmed red: workflow aborted ($err)"
  else
    fail "$desc — expected '$expect', got: $out"
  fi
}

# ── Case 1: leadv2-diverge.js — judge-opus-fallback AND judge-fallback both reject ──────────────
cat > "$TMP/scenario-diverge.json" <<'JSON_EOF'
{
  "args": { "taskId": "selftest-diverge", "problem": "test problem", "n": 2 },
  "stubs": {
    "think-model-resolve": { "type": "resolve", "value": { "think_model": "fable" } },
    "gen:0": { "type": "resolve", "value": { "idea": "i0", "approach": "a0", "key_risk": "r0" } },
    "gen:1": { "type": "resolve", "value": { "idea": "i1", "approach": "a1", "key_risk": "r1" } },
    "judge": { "type": "null" },
    "judge-opus-fallback": { "type": "reject" },
    "judge-fallback": { "type": "reject" },
    "ledger-flush": { "type": "resolve", "value": "flushed:0" }
  }
}
JSON_EOF

run_case "leadv2-diverge.js (fixed, R9)" \
  "$PLUGIN_ROOT/workflows/leadv2-diverge.js" "$TMP/scenario-diverge.json" ok

# Negative control: the committed HEAD source (pre-R9 fix) run through the IDENTICAL scenario.
git -C "$REPO_ROOT" show HEAD:plugins/leadv2/workflows/leadv2-diverge.js > "$TMP/diverge-mutant.js" 2>/dev/null \
  || cp "$PLUGIN_ROOT/workflows/leadv2-diverge.js" "$TMP/diverge-mutant.js"
if grep -q "try {" "$TMP/diverge-mutant.js" && grep -A2 "label: 'judge-opus-fallback'" "$TMP/diverge-mutant.js" | grep -q "catch"; then
  fail "leadv2-diverge.js negative control — HEAD copy already carries the guard (fetched the fixed version, not the defect); re-anchor the control to a pre-fix ref"
else
  run_case "leadv2-diverge.js (HEAD/pre-fix mutant)" \
    "$TMP/diverge-mutant.js" "$TMP/scenario-diverge.json" throws
fi

# ── Case 2: leadv2-po-feedback-loop.js — audit-opus-fallback rejects ────────────────────────────
cat > "$TMP/scenario-pofeedback.json" <<'JSON_EOF'
{
  "args": { "taskId": "selftest-po", "featureName": "f", "preprodUrl": "http://x", "maxRounds": 0, "glmInWorkflows": false },
  "stubs": {
    "think-model-resolve": { "type": "resolve", "value": { "think_model": "fable" } },
    "audit": { "type": "null" },
    "audit-opus-fallback": { "type": "reject" },
    "critic-traps": { "type": "resolve", "value": { "traps": [] } },
    "verify": { "type": "resolve", "value": { "checks": [] } },
    "ledger-flush": { "type": "resolve", "value": "flushed:0" }
  }
}
JSON_EOF

run_case "leadv2-po-feedback-loop.js (fixed, R9)" \
  "$PLUGIN_ROOT/workflows/leadv2-po-feedback-loop.js" "$TMP/scenario-pofeedback.json" ok

git -C "$REPO_ROOT" show HEAD:plugins/leadv2/workflows/leadv2-po-feedback-loop.js > "$TMP/pofeedback-mutant.js" 2>/dev/null \
  || cp "$PLUGIN_ROOT/workflows/leadv2-po-feedback-loop.js" "$TMP/pofeedback-mutant.js"
if grep -q "\.then(r =>" "$TMP/pofeedback-mutant.js"; then
  run_case "leadv2-po-feedback-loop.js (HEAD/pre-fix mutant)" \
    "$TMP/pofeedback-mutant.js" "$TMP/scenario-pofeedback.json" throws
else
  fail "leadv2-po-feedback-loop.js negative control — HEAD copy no longer has the unguarded .then() chain (fetched the fixed version, not the defect); re-anchor the control to a pre-fix ref"
fi

# ── Case 3: leadv2-audit.js (mode=personas) — Fix-phase sonnet fallback rejects ─────────────────
cat > "$TMP/scenario-audit.json" <<'JSON_EOF'
{
  "args": { "mode": "personas", "repoDir": ".", "maxJudge": 8, "fix": true, "glmInWorkflows": false },
  "stubs": {
    "collect": { "type": "resolve", "value": { "rows": [ { "persona_id": "p1", "invariant": "inv1", "status": "breach" } ] } },
    "judge:p1:inv1": { "type": "resolve", "value": { "real": true, "root_cause": "rc", "evidence": "ev", "fix_hint": "fh" } },
    "fix:p1:inv1": { "type": "reject" },
    "reprobe": { "type": "resolve", "value": { "rows": [] } },
    "ledger-flush": { "type": "resolve", "value": "flushed:0" }
  }
}
JSON_EOF

run_case "leadv2-audit.js (fixed, R9)" \
  "$PLUGIN_ROOT/workflows/leadv2-audit.js" "$TMP/scenario-audit.json" ok

git -C "$REPO_ROOT" show HEAD:plugins/leadv2/workflows/leadv2-audit.js > "$TMP/audit-mutant.js" 2>/dev/null \
  || cp "$PLUGIN_ROOT/workflows/leadv2-audit.js" "$TMP/audit-mutant.js"
if grep -q "return agent(missionText, { label, phase: 'Fix', model: 'sonnet', effort: 'medium' })" "$TMP/audit-mutant.js"; then
  run_case "leadv2-audit.js (HEAD/pre-fix mutant)" \
    "$TMP/audit-mutant.js" "$TMP/scenario-audit.json" throws
else
  fail "leadv2-audit.js negative control — HEAD copy no longer has the bare unguarded fallback return (fetched the fixed version, not the defect); re-anchor the control to a pre-fix ref"
fi

log "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
