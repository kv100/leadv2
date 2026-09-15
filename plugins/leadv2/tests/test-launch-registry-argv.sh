#!/usr/bin/env bash
# tests/test-launch-registry-argv.sh — ARMS-CANNOT-LAUNCH-THEMSELVES-01 P1.
#
# leadv2-launch-registry.py is the standalone registry that answers "what
# argv actually launches (kind, role, arm, task_class) as ITSELF" -- the
# piece the founder's gate exists to satisfy: launching sonnet's own arbiter
# arm must never silently emit `--model sonnet` for a `fable`-resolved task
# (leadv2-dispatch-code.sh:6251's bug, fixed on a separate blocked-file lane
# this suite cannot touch or verify directly).
#
# This suite asserts on the ARGV TOKENS the registry emits, never on the
# arm name appearing anywhere in stdout -- a test that only greps for
# "arm=fable" in a JSON blob would pass even if the argv itself still said
# "--model sonnet" (the exact shape of the bug this registry exists to
# catch), so every assertion below parses the JSON and compares the argv
# list element-by-element.
#
# Negative control (E2E-KILLRATE-01): a mutated COPY of the registry with
# `_argv_claude`'s function BODY changed to hardcode "sonnet" as the model
# token regardless of what it was asked to build (never a top-level literal
# swap) must make the exact-argv assertion fail. This suite proves that by
# running the same assertion against the mutant and requiring it to
# disagree with the real registry's known-correct argv.
#
# Usage: bash plugins/leadv2/tests/test-launch-registry-argv.sh
# run-all-triggers: leadv2-launch-registry

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REGISTRY="${PLUGIN_DIR}/scripts/lib/leadv2-launch-registry.py"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "FAIL: $1"; FAIL=$(( FAIL + 1 )); }

[[ -f "$REGISTRY" ]] || { echo "FATAL: registry not found at $REGISTRY"; exit 2; }

TMPD="$(mktemp -d)"
cleanup() { rm -rf "$TMPD" 2>/dev/null || true; }
trap cleanup EXIT

# assert_argv <label> <expected_argv_json_array> <lookup_argv...>
#   lookup_argv are the --kind/--role/--arm/--task-class values passed
#   straight through to the registry's --json CLI.
assert_argv() {
  local label="$1" expected_json="$2"; shift 2
  local out
  out="$(python3 "$REGISTRY" "$@" --json 2>&1)"
  EXPECTED_JSON="$expected_json" ACTUAL_JSON="$out" python3 -c '
import json, os, sys
expected = json.loads(os.environ["EXPECTED_JSON"])
try:
    actual = json.loads(os.environ["ACTUAL_JSON"])
except Exception as ex:
    print("PARSE_FAIL: %s | raw=%r" % (ex, os.environ["ACTUAL_JSON"]))
    sys.exit(1)
if not actual.get("ok"):
    print("NOT_OK: %r" % actual)
    sys.exit(1)
if actual.get("argv") != expected:
    print("ARGV_MISMATCH: expected=%r actual=%r" % (expected, actual.get("argv")))
    sys.exit(1)
sys.exit(0)
' >"${TMPD}/assert_out" 2>&1
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    pass "$label"
  else
    fail "$label -- $(cat "${TMPD}/assert_out")"
  fi
}

# assert_refused <label> <expected_reason> <lookup_argv...>
assert_refused() {
  local label="$1" expected_reason="$2"; shift 2
  local out
  out="$(python3 "$REGISTRY" "$@" --json 2>&1)"
  EXPECTED_REASON="$expected_reason" ACTUAL_JSON="$out" python3 -c '
import json, os, sys
try:
    actual = json.loads(os.environ["ACTUAL_JSON"])
except Exception as ex:
    print("PARSE_FAIL: %s" % ex); sys.exit(1)
if actual.get("ok") is not False:
    print("EXPECTED_REFUSAL_GOT_OK: %r" % actual); sys.exit(1)
if actual.get("reason") != os.environ["EXPECTED_REASON"]:
    print("REASON_MISMATCH: expected=%s actual=%s" % (os.environ["EXPECTED_REASON"], actual.get("reason")))
    sys.exit(1)
sys.exit(0)
' >"${TMPD}/assert_out" 2>&1
  if [[ $? -eq 0 ]]; then
    pass "$label"
  else
    fail "$label -- $(cat "${TMPD}/assert_out")"
  fi
}

# ── Part A: real registry, exact argv tokens (the founder's gate) ─────────
assert_argv "fable+plan -> --model fable (never sonnet)" \
  '["--role", "developer", "--model", "fable", "--effort", "high"]' \
  --kind plan --role developer --arm fable --task-class strategic

assert_argv "sonnet+code standard -> --model sonnet, medium effort" \
  '["--role", "developer", "--model", "sonnet", "--effort", "medium"]' \
  --kind product --role developer --arm sonnet --task-class standard

assert_argv "haiku+recon -> --model haiku, low effort" \
  '["--role", "developer", "--model", "haiku", "--effort", "low"]' \
  --kind recon --role developer --arm haiku --task-class light

assert_argv "codex+review heavy -> cheapest heavy-capable tier (standard), no --reason" \
  '["--tier", "standard"]' \
  --kind review --role developer --arm codex --task-class heavy

# ── Part B: check() -- launch-capability verdicts ─────────────────────────
verdict="$(python3 "$REGISTRY" --check --arm fable --model sonnet 2>&1)"
[[ "$verdict" == "refuse" ]] && pass "check(fable, sonnet) -> refuse" \
  || fail "check(fable, sonnet) expected 'refuse', got: $verdict"

verdict="$(python3 "$REGISTRY" --check --arm fable --model fable 2>&1)"
[[ "$verdict" == "ok" ]] && pass "check(fable, fable) -> ok" \
  || fail "check(fable, fable) expected 'ok', got: $verdict"

verdict="$(python3 "$REGISTRY" --check --arm glm --model glm-5.3 2>&1)"
[[ "$verdict" == "not_applicable" ]] && pass "check(glm, *) -> not_applicable (glm family out of scope, documented)" \
  || fail "check(glm, glm-5.3) expected 'not_applicable', got: $verdict"

# ── Part C: refusal reasons (never a silently substituted arm) ────────────
assert_refused "fable+code -> not_a_build_arm (fable is a plan-only arm)" \
  "not_a_build_arm" \
  --kind product --role developer --arm fable --task-class standard

assert_refused "glm+code -> adapter_argv_not_registered (glm family intentionally out of scope)" \
  "adapter_argv_not_registered" \
  --kind product --role developer --arm glm --task-class standard

# ── Part D: pool_default is DATA (opus excluded from the default pool) ────
out="$(python3 "$REGISTRY" --kind plan --role developer --arm opus --task-class strategic --json 2>&1)"
POOL_JSON="$out" python3 -c '
import json, os, sys
d = json.loads(os.environ["POOL_JSON"])
sys.exit(0 if d.get("pool_default") is False else 1)
' && pass "opus lookup carries pool_default:false (data only -- admission wiring is part B)" \
  || fail "opus lookup did not carry pool_default:false: $out"

out="$(python3 "$REGISTRY" --kind plan --role developer --arm fable --task-class strategic --json 2>&1)"
POOL_JSON="$out" python3 -c '
import json, os, sys
d = json.loads(os.environ["POOL_JSON"])
sys.exit(0 if d.get("pool_default") is True else 1)
' && pass "fable lookup carries pool_default:true (no override recorded)" \
  || fail "fable lookup pool_default unexpectedly not true: $out"

# ── Part E: codex --tier top requires --reason (adapter fact, not a gap) ──
# Exercised directly against the real module's _argv_codex -- top only wins
# the auction when it is the sole size-capable candidate, which does not
# occur naturally in the shipped capability_matrix (every top-tier row is
# strictly more expensive than a same-size-capable lower tier), so this
# checks the real function body directly rather than fabricating a routing
# scenario that cannot happen with the shipped matrix.
out="$(REGISTRY_PATH="$REGISTRY" python3 -c '
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("lr", os.environ["REGISTRY_PATH"])
lr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lr)
argv, supported = lr._argv_codex("developer", "gpt-6-astra", "top", "high")
print(argv, supported)
' 2>&1)"
if [[ "$out" == "['--tier', 'top', '--reason', 'registry-resolved-top-tier'] False" ]]; then
  pass "_argv_codex(tier=top) appends the required --reason, effort_supported=False"
else
  fail "_argv_codex(tier=top) shape changed: $out"
fi

# ── Negative control (E2E-KILLRATE-01): mutate lookup INSIDE the function
# body (never a top-level swap) so a fable request emits sonnet's model
# token, and prove the exact-argv assertion used above actually catches it.
# Written INSIDE scripts/lib/ (not TMPD) so the mutant's own _HERE-relative
# routing.yaml path resolution stays correct -- it must reach the real
# capability_matrix to produce a comparable argv, only the model token
# differs. Removed by the trap below regardless of pass/fail.
MUTANT="${PLUGIN_DIR}/scripts/lib/.leadv2-launch-registry-mutant-tmp.py"
cp "$REGISTRY" "$MUTANT"
cleanup_mutant() { rm -f "$MUTANT" 2>/dev/null || true; }
trap 'cleanup_mutant; cleanup' EXIT
# _argv_claude's body: `argv = ["--role", role, "--model", model]` -- force
# the literal "sonnet" regardless of the `model` argument it was given. This
# reproduces exactly the class of bug the registry exists to prevent
# (leadv2-dispatch-code.sh:6251's hardcoded --model sonnet), inside the
# function body that builds the argv, not at module top level.
python3 -c '
import re, sys
src = open(sys.argv[1]).read()
needle = "\"argv = [\\\"--role\\\", role, \\\"--model\\\", model]\""
target = "argv = [\"--role\", role, \"--model\", model]"
mutated = "argv = [\"--role\", role, \"--model\", \"sonnet\"]  # MUTATED-NEGATIVE-CONTROL"
if src.count(target) != 1:
    sys.stderr.write("mutation anchor not found exactly once (found %d) -- registry source shape changed, fix this test\n" % src.count(target))
    sys.exit(1)
open(sys.argv[1], "w").write(src.replace(target, mutated, 1))
' "$MUTANT"
if [[ $? -ne 0 ]]; then
  fail "negative control setup: could not locate _argv_claude's argv-building line to mutate"
else
  mutant_out="$(python3 "$MUTANT" --kind plan --role developer --arm fable --task-class strategic --json 2>&1)"
  EXPECTED_JSON='["--role", "developer", "--model", "fable", "--effort", "high"]' MUTANT_JSON="$mutant_out" python3 -c '
import json, os, sys
expected = json.loads(os.environ["EXPECTED_JSON"])
actual = json.loads(os.environ["MUTANT_JSON"])
# The mutant must DISAGREE with the known-correct fable argv -- if it still
# matches, the mutation had no effect (or the assertion is not actually
# checking the argv tokens) and the negative control itself has failed.
sys.exit(0 if actual.get("argv") != expected else 1)
'
  if [[ $? -eq 0 ]]; then
    pass "negative control: mutated _argv_claude (hardcoded sonnet) is caught by the exact-argv assertion, not by an arm=fable string match"
  else
    fail "NEGATIVE CONTROL FAILED: mutated registry still produced the correct fable argv -- the argv-token assertion did not detect the injected --model sonnet bug"
  fi
fi

echo "----"
echo "PASS=${PASS} FAIL=${FAIL}"
[[ "$FAIL" -eq 0 ]]
