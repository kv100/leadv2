#!/usr/bin/env bash
# tests/test-launch-registry-answers-for-every-arm.sh — A3-LAUNCH-REGISTRY-2.
#
# The contradiction this suite grades (measured by the lead 2026-09-08): the
# registry answered `ok:false reason=adapter_argv_not_registered` for glm in
# BOTH code/worker and review/reviewer while the dispatcher launched glm all
# day (journal: CODEX-ALWAYS-UP, RECON-5H-WINDOW author=glm; B2 route_resolved
# role=reviewer arm=glm). glm reaches its worker through glm-coder.sh, a path
# this registry never owned, and the launchability seam (_arm_launchable_arms)
# OR-ed a hardcoded legacy set over the refusal — two truths, at most one of
# them right.
#
# The fix: the registry DECLARES its scope. glm/glm-flash (provider glm) and
# freepool (provider freepool) still refuse — their adapter argv genuinely is
# not registered here, and the reason string is a cross-lane contract pinned
# verbatim by tests/test-launch-registry-argv.sh — but the refusal now carries
# adapter_scope="external" plus the real adapter script. Launchability is then
# derivable from the registry's OWN answer, with no shell-side arm-name
# duplication (Part 3 proves the derivation equals the seam's set exactly).
#
# Negative controls (E2E-KILLRATE-01; both mutations INSIDE lookup()'s body,
# never a top-level swap, and both mutants must go RED):
#   1. symptom mutant: the external-scope branch is stripped, restoring the
#      pre-A3 unqualified refusal -> the scope assertion AND the one-answer
#      theorem fail against the mutant.
#   2. guard mutant: the builder-miss refusal flips to ok:true (a registry
#      that approves everything / registers green answers nothing executes)
#      -> the invented-provider guard and the glm scope assertion fail.
#      Approving-everything is worse than the bug.
#
# Pinned NON-defect (confirmed deliberate, so it cannot drift silently):
# opus/haiku + kind=code answer not_a_build_arm because they are absent from
# DISPATCHABLE_BUILD_ARMS (lib/leadv2-glm-policy-resolve.py) AND their
# capability_matrix rows carry no `code` kind (config/leadv2-routing.yaml).
#
# Usage: bash plugins/leadv2/tests/test-launch-registry-answers-for-every-arm.sh
# run-all-triggers: leadv2-launch-registry leadv2-glm-policy-resolve.py leadv2-routing.yaml

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REGISTRY="${PLUGIN_DIR}/scripts/lib/leadv2-launch-registry.py"
ROUTING_YAML="${PLUGIN_DIR}/config/leadv2-routing.yaml"
# Mutants live INSIDE scripts/lib (not TMPD) so their _HERE-relative default
# routing.yaml resolution reaches the real capability_matrix — same reason as
# tests/test-launch-registry-argv.sh's mutant. Distinct suffixes so this suite
# and that one can run concurrently without clobbering each other's copies.
MUTANT_A="${PLUGIN_DIR}/scripts/lib/.leadv2-launch-registry-mutant-a-tmp.py"
MUTANT_B="${PLUGIN_DIR}/scripts/lib/.leadv2-launch-registry-mutant-b-tmp.py"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "FAIL: $1"; FAIL=$(( FAIL + 1 )); }

[[ -f "$REGISTRY" ]] || { echo "FATAL: registry not found at $REGISTRY"; exit 2; }
[[ -f "$ROUTING_YAML" ]] || { echo "FATAL: routing yaml not found at $ROUTING_YAML"; exit 2; }

TMPD="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPD" 2>/dev/null || true
  rm -f "$MUTANT_A" "$MUTANT_B" 2>/dev/null || true
}
trap cleanup EXIT

# verdict <registry> <expect-py-expr> <lookup args...> -> rc 0 when the
# registry's --json answer satisfies the expression (d = parsed answer). The
# registry's own exit code is IGNORED on purpose: a refusal CLI-exits 1 while
# still printing valid JSON — the answer VALUE is what is graded here.
verdict() {
  local reg="$1" expect="$2"; shift 2
  local out
  out="$(python3 "$reg" "$@" --json 2>&1)" || true
  LOOK_JSON="$out" CHECK="$expect" python3 -c '
import json, os, sys
try:
    d = json.loads(os.environ["LOOK_JSON"])
except Exception as ex:
    sys.stderr.write("PARSE_FAIL: %s | raw=%r\n" % (ex, os.environ["LOOK_JSON"]))
    sys.exit(1)
if not eval(os.environ["CHECK"]):
    sys.stderr.write("CHECK_FALSE: %r\n" % (d,))
    sys.exit(1)
' 2>"${TMPD}/verdict_err"
}

# assert_green <label> <expect> <args...>: the REAL registry must satisfy it.
assert_green() {
  local label="$1" expect="$2"; shift 2
  if verdict "$REGISTRY" "$expect" "$@"; then
    pass "$label"
  else
    fail "$label -- $(cat "${TMPD}/verdict_err")"
  fi
}

# assert_mutant_red <mutant> <label> <expect> <args...>: the MUTATED registry
# must FAIL the same check — the mutation is caught, never waved through.
assert_mutant_red() {
  local mutant="$1" label="$2" expect="$3"; shift 3
  if verdict "$mutant" "$expect" "$@"; then
    fail "NEGATIVE CONTROL FAILED: $label (mutant still satisfied the assertion)"
  else
    pass "negative control: $label"
  fi
}

# ── Part 1: the answer VALUE for every arm (the mission's rows) ────────────
EXTERNAL_GLM='d.get("ok") is False and d.get("reason") == "adapter_argv_not_registered" and d.get("adapter_scope") == "external" and d.get("external_adapter") == "glm-coder.sh"'

assert_green "glm+code/worker: refused AND scoped -- glm-coder.sh owns it, not 'cannot launch'" \
  "$EXTERNAL_GLM" \
  --kind code --role worker --arm glm --task-class standard

assert_green "glm+review/reviewer: same honest scope (B2's cheapest_capable reviewer)" \
  "$EXTERNAL_GLM" \
  --kind review --role reviewer --arm glm --task-class standard

assert_green "glm-flash+code: external via the glm provider's adapter" \
  "$EXTERNAL_GLM" \
  --kind code --role worker --arm glm-flash --task-class standard

assert_green "freepool+code: external, freepool-coder.sh" \
  'd.get("ok") is False and d.get("reason") == "adapter_argv_not_registered" and d.get("adapter_scope") == "external" and d.get("external_adapter") == "freepool-coder.sh"' \
  --kind code --role worker --arm freepool --task-class standard

# Confirmed deliberate (see header) — pinned so a future change to the build
# set or the matrix cannot silently make opus/haiku code arms.
for _a in opus haiku; do
  assert_green "${_a}+code -> not_a_build_arm is DELIBERATE (absent from DISPATCHABLE_BUILD_ARMS; matrix row carries no code kind)" \
    'd.get("ok") is False and d.get("reason") == "not_a_build_arm"' \
    --kind code --role worker --arm "$_a" --task-class standard
done

# Sanity: declaring scope widened nothing — the registry's OWN arms are green.
assert_green "sonnet+code still ok:true as itself" \
  'd.get("ok") is True and d.get("model") == "sonnet"' \
  --kind code --role worker --arm sonnet --task-class standard

assert_green "codex+review still ok:true as itself" \
  'd.get("ok") is True' \
  --kind review --role reviewer --arm codex --task-class standard

# ── Part 2: the guard — an arm with NO real launch path still answers no ───
# Fixture matrix: arm glm (so the build-arms gate passes) on a provider
# nothing launches — the "matrix row nobody wired" case. This must stay a
# BARE refusal: the scope marker may never leak to a provider without a live
# dispatcher-driven adapter.
cat > "${TMPD}/fixture-routing.yaml" <<'YEOF'
router_v2:
  capability_matrix:
    - { arm: glm, provider: madeup-provider, model: probe-1, tier: standard, cost: 1, kinds: [code], sizes: [standard], review: false, protected: false, capability: 1 }
YEOF

export LEADV2_ROUTE_ARBITER_ROUTING_YAML="${TMPD}/fixture-routing.yaml"
assert_green "guard: unregistered provider (madeup-provider on a build arm) is a BARE refusal — no adapter_scope" \
  'd.get("ok") is False and d.get("reason") == "adapter_argv_not_registered" and "adapter_scope" not in d' \
  --kind code --role worker --arm glm --task-class standard

assert_green "guard: an arm absent from the matrix entirely is refused" \
  'd.get("ok") is False' \
  --kind docs --role worker --arm no-such-arm --task-class standard
unset LEADV2_ROUTE_ARBITER_ROUTING_YAML

# ── Part 3: the one-answer theorem ──────────────────────────────────────────
# For every arm in the real capability_matrix, kind in {code, review}: the
# dispatcher's seam set (replicated EXACTLY, including its hardcoded legacy
# {glm,glm-flash,freepool}) must equal the set derived from the registry's
# answers ALONE (ok:true or adapter_scope=="external"). Green means "can this
# arm launch" has ONE answer and every caller can get it from the registry.
cat > "${TMPD}/one_answer.py" <<'PYA3'
import importlib.util, sys

reg = sys.argv[1]
spec = importlib.util.spec_from_file_location("launch_registry", reg)
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)

bad = []
facts = []
for kind in ("code", "review"):
    rows = r.load_capability_matrix()
    arms = sorted({row["arm"] for row in rows})
    build_arms, _plan_arms = r._dispatchable_arm_sets()
    # EXACT replica of the launchability seam's inline python (the predicate
    # inside _arm_launchable_arms), hardcoded legacy set included:
    seam = [arm for arm in arms if
            r.lookup(kind, "developer", arm, "standard").get("ok") or
            (arm in (build_arms & {"glm", "glm-flash", "freepool"}) and
             any(row.get("arm") == arm and kind in row.get("kinds", [])
                 for row in rows))]
    # The same set derived from the REGISTRY'S OWN ANSWERS — no hardcoded
    # arm names anywhere:
    derived = [arm for arm in arms if
               r.lookup(kind, "developer", arm, "standard").get("ok") or
               r.lookup(kind, "developer", arm, "standard").get("adapter_scope") == "external"]
    facts.append("kind=%s seam=%s" % (kind, ",".join(seam)))
    if seam != derived:
        bad.append("kind=%s seam_only=%s derived_only=%s" %
                   (kind, sorted(set(seam) - set(derived)),
                    sorted(set(derived) - set(seam))))
    if "glm" not in seam:
        bad.append("kind=%s: the replicated seam stopped including glm — glm "
                   "launches all day; the replica drifted from the source" % kind)
print(" | ".join(facts))
if bad:
    print("MISMATCH " + "; ".join(bad))
    sys.exit(1)
print("ONE_ANSWER seam==derived for code and review")
PYA3

if python3 "${TMPD}/one_answer.py" "$REGISTRY" >"${TMPD}/one_answer_out" 2>&1; then
  pass "one-answer theorem: the seam's launchable set (code+review) is fully derivable from the registry's answers ($(tail -1 "${TMPD}/one_answer_out"))"
else
  fail "one-answer theorem BROKEN: $(cat "${TMPD}/one_answer_out")"
fi

# ── Part 4: negative controls (E2E-KILLRATE-01) ────────────────────────────
# mutate <path> <needle-file> <replacement-file>: each needle must occur
# EXACTLY once in the copy — a drifted anchor is a FAIL, never a silent
# no-op mutation (which would make the control read as a pass for the wrong
# reason).
mutate() {
  local mpath="$1" needle_f="$2" repl_f="$3"
  python3 -c '
import sys
path, nf, rf = sys.argv[1:4]
src = open(path).read()
needle = open(nf).read()
repl = open(rf).read()
n = src.count(needle)
if n != 1:
    sys.stderr.write("mutation anchor found %d times (expected 1) -- registry source shape changed, fix this test\n" % n)
    sys.exit(1)
open(path, "w").write(src.replace(needle, repl, 1))
' "$mpath" "$needle_f" "$repl_f"
}

# Mutant A (the symptom): strip the external-scope branch inside lookup()'s
# body -> glm answers the pre-A3 unqualified refusal again.
cat > "${TMPD}/needle_a" <<'NA'
        if provider in _EXTERNAL_ADAPTERS:
            refusal["adapter_scope"] = "external"
            refusal["external_adapter"] = _EXTERNAL_ADAPTERS[provider]
        return refusal
NA
cat > "${TMPD}/repl_a" <<'RA'
        return refusal  # MUTATED-NEGATIVE-CONTROL-A: pre-A3 unqualified refusal
RA
cp "$REGISTRY" "$MUTANT_A"
if mutate "$MUTANT_A" "${TMPD}/needle_a" "${TMPD}/repl_a"; then
  assert_mutant_red "$MUTANT_A" \
    "mutant A caught: glm+code scope assertion fails on the old unqualified refusal" \
    "$EXTERNAL_GLM" \
    --kind code --role worker --arm glm --task-class standard
  if python3 "${TMPD}/one_answer.py" "$MUTANT_A" >/dev/null 2>&1; then
    fail "NEGATIVE CONTROL FAILED: one-answer theorem still held with the scope branch stripped (glm reads unlaunchable again)"
  else
    pass "negative control: one-answer theorem goes red when the scope branch is stripped"
  fi
else
  fail "mutant A setup: $(cat "${TMPD}/verdict_err" 2>/dev/null); mutation anchor drifted"
fi

# Mutant B (the guard's evil twin): flip lookup()'s refusal to approve
# everything — a registry that answers ok:true where no executable argv
# exists (the lying-green disease in registry form). Two edits, both inside
# lookup()'s body.
cat > "${TMPD}/needle_b1" <<'NB1'
        refusal = {"ok": False, "reason": "adapter_argv_not_registered", "arm": arm,
                   "provider": provider, "kind": kind}
NB1
cat > "${TMPD}/repl_b1" <<'RB1'
        refusal = {"ok": True, "reason": "adapter_argv_not_registered", "arm": arm,  # MUTATED-NEGATIVE-CONTROL-B: approve-everything
                   "provider": provider, "kind": kind}
RB1
cat > "${TMPD}/needle_b2" <<'NB2'
        if provider in _EXTERNAL_ADAPTERS:
            refusal["adapter_scope"] = "external"
NB2
cat > "${TMPD}/repl_b2" <<'RB2'
        if provider in _EXTERNAL_ADAPTERS:
            refusal["ok"] = True  # MUTATED-NEGATIVE-CONTROL-B: green answer nothing executes
RB2
cp "$REGISTRY" "$MUTANT_B"
if mutate "$MUTANT_B" "${TMPD}/needle_b1" "${TMPD}/repl_b1" \
   && mutate "$MUTANT_B" "${TMPD}/needle_b2" "${TMPD}/repl_b2"; then
  assert_mutant_red "$MUTANT_B" \
    "mutant B caught: glm+code must not answer ok:true (a scope refusal is not a launch)" \
    "$EXTERNAL_GLM" \
    --kind code --role worker --arm glm --task-class standard
  export LEADV2_ROUTE_ARBITER_ROUTING_YAML="${TMPD}/fixture-routing.yaml"
  assert_mutant_red "$MUTANT_B" \
    "mutant B caught: unregistered provider probe must stay refused (approve-everything is worse than the bug)" \
    'd.get("ok") is False and d.get("reason") == "adapter_argv_not_registered" and "adapter_scope" not in d' \
    --kind code --role worker --arm glm --task-class standard
  unset LEADV2_ROUTE_ARBITER_ROUTING_YAML
else
  fail "mutant B setup: mutation anchor drifted (registry source shape changed, fix this test)"
fi

echo "----"
echo "PASS=${PASS} FAIL=${FAIL}"
[[ "$FAIL" -eq 0 ]]
