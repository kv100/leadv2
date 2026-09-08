#!/usr/bin/env bash
# tests/test-claude-account-states.sh — ARMS-CANNOT-LAUNCH-THEMSELVES-01 P5.
#
# Two independent fixes in leadv2-quota-read.py, both exercised hermetically
# (no real keychain read, no real network call, no real registry file
# touched -- every input is synthetic and supplied via env/tmp files so this
# suite is deterministic on any machine):
#
#  1. `_keychain_services()` used to admit EVERY "Claude Code-credentials*"
#     entry the keychain enumerates, including stale entries nobody
#     registered (measured live: a `default` entry and one dir-hash-suffixed
#     entry dilute the claude price this way). It must now intersect the
#     enumeration against `~/.claude/state/leadv2/claude-profiles.tsv`
#     (env override LEADV2_CLAUDE_PROFILES_FILE) plus the unsuffixed prefix
#     itself (the ambient session credential) -- and fail OPEN
#     (unfiltered) when that registry is missing/unreadable/empty, never
#     fail closed to zero accounts.
#
#  2. `classify_account_state(subscription_type, http_code)` distinguishes
#     "credential dead" (stays `unknown`, keeps the existing
#     UNKNOWN_PROBE_PENALTY) from TEAM-ACCOUNT-QUOTA-WINDOW-UNPARSED-01's
#     named class: a team-tier account whose token/org DOES resolve but
#     whose /api/oauth/usage call 401s anyway -- that must become the new
#     explicit `unmetered` state, priced conservatively (never a measured
#     usage number, never the unknown penalty).
#
# Negative controls (E2E-KILLRATE-01), both mutated INSIDE function bodies:
#  - _keychain_services: the registry-intersection line is defeated so a
#    non-registry (stale) service is re-admitted -- the probe test must fail.
#  - classify_account_state: the team+401 branch is collapsed back into
#    `unknown` -- the pricing test must fail.
# Each control runs the SAME assertion used by the real positive test
# against a mutated copy of the module and requires it to disagree.
#
# Usage: bash plugins/leadv2/tests/test-claude-account-states.sh
# run-all-triggers: leadv2-quota-read

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
QUOTA_READ="${PLUGIN_DIR}/scripts/leadv2-quota-read.py"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "FAIL: $1"; FAIL=$(( FAIL + 1 )); }

[[ -f "$QUOTA_READ" ]] || { echo "FATAL: leadv2-quota-read.py not found at $QUOTA_READ"; exit 2; }

TMPD="$(mktemp -d)"
cleanup() { rm -rf "$TMPD" 2>/dev/null || true; }
trap cleanup EXIT

# Synthetic `security dump-keychain` output: three services share the
# "Claude Code-credentials" prefix -- the unsuffixed one (ambient session
# credential, always admitted), one registered slot (aaa111), and one STALE
# entry nobody registered (zzz999, the exact shape of the live dilution bug).
FAKE_DUMP='"svce"<blob>="Claude Code-credentials"
"svce"<blob>="Claude Code-credentials-aaa111"
"svce"<blob>="Claude Code-credentials-zzz999"
"svce"<blob>="unrelated-other-app"'

# Hermetic registry: only aaa111 is a real registered slot.
REGISTRY_TSV="${TMPD}/claude-profiles.tsv"
cat > "$REGISTRY_TSV" <<'EOF'
work	/tmp/fake-work-dir	keychain:Claude Code-credentials-aaa111
EOF

# run_keychain_probe <module_path> -> prints the sorted service set
# _keychain_services() resolves, with `security` monkeypatched to the
# synthetic dump above (never a real keychain read) and the registry pinned
# to the hermetic file above (never the real machine's registry).
run_keychain_probe() {
  local module_path="$1"
  FAKE_DUMP="$FAKE_DUMP" LEADV2_CLAUDE_PROFILES_FILE="$REGISTRY_TSV" \
    python3 -c '
import importlib.util, json, os, subprocess, sys

spec = importlib.util.spec_from_file_location("qr_under_test", sys.argv[1])
qr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qr)

class _FakeCompleted:
    pass

def _fake_check_output(cmd, **kwargs):
    if cmd[:2] == ["security", "dump-keychain"]:
        return os.environ["FAKE_DUMP"].encode()
    raise AssertionError("unexpected subprocess call in hermetic test: %r" % (cmd,))

subprocess.check_output = _fake_check_output
print(json.dumps(sorted(qr._keychain_services())))
' "$module_path"
}

# ── Part A: registry-filtered keychain probe excludes the stale entry ─────
probe_json="$(run_keychain_probe "$QUOTA_READ")"
EXPECTED='["Claude Code-credentials", "Claude Code-credentials-aaa111"]'
GOT="$probe_json" python3 -c '
import json, os, sys
got = json.loads(os.environ["GOT"])
expected = ["Claude Code-credentials", "Claude Code-credentials-aaa111"]
sys.exit(0 if got == expected else 1)
'
if [[ $? -eq 0 ]]; then
  pass "_keychain_services() admits the ambient prefix + registered slot, excludes the stale zzz999 entry"
else
  fail "_keychain_services() probe mismatch: expected ${EXPECTED}, got ${probe_json}"
fi

# ── Part A2: missing/unreadable registry fails OPEN (unfiltered) ──────────
open_json="$(FAKE_DUMP="$FAKE_DUMP" LEADV2_CLAUDE_PROFILES_FILE="${TMPD}/does-not-exist.tsv" python3 -c '
import importlib.util, json, os, subprocess, sys
spec = importlib.util.spec_from_file_location("qr_under_test", sys.argv[1])
qr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qr)
def _fake_check_output(cmd, **kwargs):
    return os.environ["FAKE_DUMP"].encode()
subprocess.check_output = _fake_check_output
print(json.dumps(sorted(qr._keychain_services())))
' "$QUOTA_READ")"
GOT="$open_json" python3 -c '
import json, os, sys
got = set(json.loads(os.environ["GOT"]))
# fail-open: ALL four dump entries matching the prefix pass through
# unfiltered (unrelated-other-app never matched the prefix to begin with).
sys.exit(0 if got == {"Claude Code-credentials", "Claude Code-credentials-aaa111", "Claude Code-credentials-zzz999"} else 1)
'
if [[ $? -eq 0 ]]; then
  pass "missing registry file fails OPEN (unfiltered enumeration), never drops every account to zero"
else
  fail "missing-registry fail-open probe mismatch, got: ${open_json}"
fi

# ── Part B: account-state classifier (CLI verb, no live probe needed) ─────
assert_classify() {
  local label="$1" sub="$2" code="$3" expected_state="$4"
  local out state
  out="$(python3 "$QUOTA_READ" classify-account "$sub" "$code" 2>&1)"
  state="$(STATE_JSON="$out" python3 -c 'import json, os; print(json.loads(os.environ["STATE_JSON"])["account_state"])' 2>/dev/null)"
  if [[ "$state" == "$expected_state" ]]; then
    pass "$label"
  else
    fail "$label -- expected account_state=${expected_state}, got: ${out}"
  fi
}

assert_classify "team+401 -> unmetered (TEAM-ACCOUNT-QUOTA-WINDOW-UNPARSED-01, priced conservatively)" \
  team 401 unmetered
assert_classify "pro+401 -> unknown (an ordinary dead credential, keeps today's penalty)" \
  pro 401 unknown
assert_classify "team+200 -> ok" \
  team 200 ok
assert_classify "team+429 -> unknown (rate-limited, never priced as unmetered)" \
  team 429 unknown
assert_classify "-(unresolved subscription)+401 -> unknown" \
  - 401 unknown

# unmetered must price conservatively, never invent a measured usage number,
# and never carry the unknown-probe penalty.
pricing_out="$(python3 "$QUOTA_READ" classify-account team 401 2>&1)"
PRICING_JSON="$pricing_out" python3 -c '
import json, os, sys
d = json.loads(os.environ["PRICING_JSON"])
p = d.get("pricing") or {}
sys.exit(0 if p.get("penalty") == 0 and p.get("priced_from") != "unknown_probe_penalty" else 1)
'
if [[ $? -eq 0 ]]; then
  pass "unmetered pricing carries no unknown-probe penalty and is not measured (conservative, configured-allowance basis)"
else
  fail "unmetered pricing shape wrong: ${pricing_out}"
fi

# ── Negative control #2 (E2E-KILLRATE-01): defeat the registry filter
# INSIDE _keychain_services' body and prove the Part-A probe assertion
# above actually catches the stale re-admission. ─────────────────────────
MUTANT_QR="${PLUGIN_DIR}/scripts/.leadv2-quota-read-mutant-tmp.py"
cp "$QUOTA_READ" "$MUTANT_QR"
cleanup_mutants() { rm -f "$MUTANT_QR" "$MUTANT_CLASSIFY" 2>/dev/null || true; }
trap 'cleanup_mutants; cleanup' EXIT

python3 -c '
import sys
src = open(sys.argv[1]).read()
target = "allowed = allowed | {prefix}"
mutated = "allowed = services  # MUTATED-NEGATIVE-CONTROL: defeats the registry filter entirely"
if src.count(target) != 1:
    sys.stderr.write("mutation anchor not found exactly once (found %d)\n" % src.count(target))
    sys.exit(1)
open(sys.argv[1], "w").write(src.replace(target, mutated, 1))
' "$MUTANT_QR"
if [[ $? -ne 0 ]]; then
  fail "negative control #2 setup: could not locate the registry-intersection line to mutate"
else
  mutant_probe="$(run_keychain_probe "$MUTANT_QR")"
  GOT="$mutant_probe" python3 -c '
import json, os, sys
got = json.loads(os.environ["GOT"])
expected = ["Claude Code-credentials", "Claude Code-credentials-aaa111"]
# The mutant must DISAGREE with the correctly-filtered set (it re-admits the
# stale zzz999 entry) -- if it still matches, the mutation had no effect.
sys.exit(0 if got != expected else 1)
'
  if [[ $? -eq 0 ]]; then
    pass "negative control: mutated _keychain_services (filter defeated) is caught -- stale zzz999 re-admitted, real probe assertion would fail"
  else
    fail "NEGATIVE CONTROL FAILED: mutated _keychain_services still excluded the stale entry -- the probe test does not detect a defeated filter"
  fi
fi

# ── Negative control #3: collapse unmetered back into unknown INSIDE
# classify_account_state's body, prove the Part-B pricing assertion catches
# it. ──────────────────────────────────────────────────────────────────────
MUTANT_CLASSIFY="${PLUGIN_DIR}/scripts/.leadv2-quota-read-classify-mutant-tmp.py"
cp "$QUOTA_READ" "$MUTANT_CLASSIFY"
python3 -c '
import sys
src = open(sys.argv[1]).read()
target = "    if subscription_type == \"team\" and http_code == 401:\n        return ACCOUNT_STATE_UNMETERED\n"
mutated = "    if False:  # MUTATED-NEGATIVE-CONTROL: collapses unmetered back into unknown\n        return ACCOUNT_STATE_UNMETERED\n"
if src.count(target) != 1:
    sys.stderr.write("mutation anchor not found exactly once (found %d)\n" % src.count(target))
    sys.exit(1)
open(sys.argv[1], "w").write(src.replace(target, mutated, 1))
' "$MUTANT_CLASSIFY"
if [[ $? -ne 0 ]]; then
  fail "negative control #3 setup: could not locate classify_account_state's team+401 branch to mutate"
else
  mutant_state="$(python3 "$MUTANT_CLASSIFY" classify-account team 401 2>&1)"
  STATE_JSON="$mutant_state" python3 -c '
import json, os, sys
state = json.loads(os.environ["STATE_JSON"])["account_state"]
# The mutant must report "unknown" (collapsed), not "unmetered" -- if it
# still reports unmetered, the mutation had no effect.
sys.exit(0 if state != "unmetered" else 1)
'
  if [[ $? -eq 0 ]]; then
    pass "negative control: mutated classify_account_state (team+401 collapsed) is caught -- reports unknown, real pricing assertion would fail"
  else
    fail "NEGATIVE CONTROL FAILED: mutated classify_account_state still reported unmetered -- the pricing test does not detect the collapse"
  fi
fi

echo "----"
echo "PASS=${PASS} FAIL=${FAIL}"
[[ "$FAIL" -eq 0 ]]
