#!/usr/bin/env bash
# FABLE-THINK-TIER-01 R6 — runtime proof that tests/run-all.sh --scope changed
# selects the think-tier contract suite when a NON-.sh carrier changes.
#
# R5 defect: the changed-file loop `continue`d on anything that was not
# plugins/leadv2/scripts/*.sh, scripts/lib/*.sh or hooks/*.sh, so the six R5
# carrier rows (leadv2-glm-policy-resolve.py, model-capability.yaml,
# leadv2-diverge.js, leadv2-learn.js, leadv2-diagnose.js,
# leadv2-po-feedback-loop.js) were dead map entries — no such stem was ever
# produced and the contract suite never re-ran on them.
#
# Method: build a scratch git repo with the run-all layout, copy the REAL
# run-all.sh in, dirty exactly one carrier, and assert the [RUN] line for the
# mapped suite appears. A negative control dirties an unmapped file and
# asserts the suite is NOT selected (so the positive is attributable to the
# carrier map, not to some always-on path).
set -uo pipefail

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=$((FAIL + 1)); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_ALL="${LEADV2_TEST_RUN_ALL:-$ROOT/tests/run-all.sh}"
[[ -f "$RUN_ALL" ]] || { echo "FAIL: run-all not found at $RUN_ALL"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

SCRATCH="$TMP/repo"
git init -q "$SCRATCH" 2>/dev/null
mkdir -p "$SCRATCH/tests" \
         "$SCRATCH/plugins/leadv2/config" \
         "$SCRATCH/plugins/leadv2/scripts/lib" \
         "$SCRATCH/plugins/leadv2/scripts/tests" \
         "$SCRATCH/plugins/leadv2/workflows"
cp "$RUN_ALL" "$SCRATCH/tests/run-all.sh"
# the mapped target suite: a cheap stub that passes
printf '#!/usr/bin/env bash\nexit 0\n' > "$SCRATCH/plugins/leadv2/scripts/tests/test-fable-think-tier.sh"
chmod +x "$SCRATCH/plugins/leadv2/scripts/tests/test-fable-think-tier.sh"
# R7: run-all.sh's OWN carrier-map row (tests/test-run-all-carrier-map.sh) —
# a cheap stub that passes
printf '#!/usr/bin/env bash\nexit 0\n' > "$SCRATCH/tests/test-run-all-carrier-map.sh"
chmod +x "$SCRATCH/tests/test-run-all-carrier-map.sh"
# tracked carriers (must be committed, then dirtied, to appear in diff HEAD)
printf 'fable:\n  model_id: claude-fable-5-1\n' > "$SCRATCH/plugins/leadv2/config/model-capability.yaml"
printf '# resolver carrier\n' > "$SCRATCH/plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py"
printf '// diverge carrier\n' > "$SCRATCH/plugins/leadv2/workflows/leadv2-diverge.js"
# an unmapped control file
printf '#!/usr/bin/env bash\n# unmapped control\n' > "$SCRATCH/plugins/leadv2/scripts/leadv2-unmapped-control.sh"
git -C "$SCRATCH" add -A
git -C "$SCRATCH" -c user.email=t@t -c user.name=t commit -qm base

# run with a clean env: no LEADV2_* leakage, bash 3.2-compatible invocation
run_selection() { # no args; prints run-all stdout+stderr
  ( cd "$SCRATCH" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
      bash tests/run-all.sh --scope changed 2>&1 )
}

# --- case 1: model-capability.yaml alone -------------------------------------
printf '  unavailable: false\n' >> "$SCRATCH/plugins/leadv2/config/model-capability.yaml"
out="$(run_selection)"
if printf '%s' "$out" | grep -q '\[RUN\].*test-fable-think-tier\.sh'; then
  pass "dirty model-capability.yaml alone selects test-fable-think-tier.sh"
else
  fail "dirty model-capability.yaml alone did NOT select the suite; output:
$out"
fi
git -C "$SCRATCH" checkout -q -- plugins/leadv2/config/model-capability.yaml

# --- case 2: leadv2-glm-policy-resolve.py alone -------------------------------
printf '# dirty\n' >> "$SCRATCH/plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py"
out="$(run_selection)"
if printf '%s' "$out" | grep -q '\[RUN\].*test-fable-think-tier\.sh'; then
  pass "dirty leadv2-glm-policy-resolve.py alone selects test-fable-think-tier.sh"
else
  fail "dirty leadv2-glm-policy-resolve.py alone did NOT select the suite; output:
$out"
fi
git -C "$SCRATCH" checkout -q -- plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py

# --- case 3: leadv2-diverge.js alone ------------------------------------------
printf '// dirty\n' >> "$SCRATCH/plugins/leadv2/workflows/leadv2-diverge.js"
out="$(run_selection)"
if printf '%s' "$out" | grep -q '\[RUN\].*test-fable-think-tier\.sh'; then
  pass "dirty leadv2-diverge.js alone selects test-fable-think-tier.sh"
else
  fail "dirty leadv2-diverge.js alone did NOT select the suite; output:
$out"
fi
git -C "$SCRATCH" checkout -q -- plugins/leadv2/workflows/leadv2-diverge.js

# --- case 3b: run-all.sh itself (R7) ------------------------------------------
# R7 defect: tests/run-all.sh carried a carrier-map row pointing back at its
# own suite (tests/test-run-all-carrier-map.sh), but the changed-file loop's
# else-branch case statement only allowlisted plugins/leadv2/scripts/*.sh,
# scripts/lib/*.sh and hooks/*.sh — anything else, including tests/run-all.sh
# itself, hit `*) continue ;;` before a stem was ever assigned. The map row
# was permanently dead: no diff to run-all.sh could ever select it.
printf '# dirty\n' >> "$SCRATCH/tests/run-all.sh"
out="$(run_selection)"
if printf '%s' "$out" | grep -q '\[RUN\].*test-run-all-carrier-map\.sh'; then
  pass "dirty tests/run-all.sh alone selects tests/test-run-all-carrier-map.sh"
else
  fail "dirty tests/run-all.sh alone did NOT select its own carrier-map suite (dead map row); output:
$out"
fi
git -C "$SCRATCH" checkout -q -- tests/run-all.sh

# --- case 4 (negative control): an unmapped scripts/*.sh must NOT select it ---
printf '# dirty\n' >> "$SCRATCH/plugins/leadv2/scripts/leadv2-unmapped-control.sh"
out="$(run_selection)"
if printf '%s' "$out" | grep -q '\[RUN\].*test-fable-think-tier\.sh'; then
  fail "negative control: unmapped leadv2-unmapped-control.sh DID select the suite (selection is not carrier-attributable); output:
$out"
else
  pass "negative control: unmapped scripts/*.sh change selects no think-tier suite"
fi

printf 'test-run-all-carrier-map: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
