#!/usr/bin/env bash
# test-codex-tier-model-table.sh — A1-CODEX-TIERS-A2 (part A + registry entries).
#
# The defect this suite pins shut: codex-task.sh mapped ALL THREE tiers to
# gpt-6-astra (only the effort differed) while its own header documented
# sol/terra/luna — gpt-5.6-sol, gpt-5.6-luna and gpt-5.6-terra were
# unreachable through any tier, and an absent model silently resolved to
# astra. Asserts, against a stubbed companion (never the real Codex CLI):
#   1. each tier resolves to ITS OWN model (sol/terra/luna) in the resolution
#      line AND the argv actually forwarded to the companion;
#   2. an absent model falls back to a NAMED model with a fallback journal
#      line on stderr (never a silent astra); the top-tier ledger line
#      carries the resolved model too;
#   3. an unreadable models_cache never fails the run (terminal astra +
#      journal line saying so);
#   4. effort stays per tier while the model falls back (same fallback model,
#      two tiers, two efforts — model and effort must not fold together);
#   5. leadv2-launch-registry.py carries one entry per launchable (model,
#      tier) pair with per-TASK-CLASS effort, refuses an unregistered pair,
#      and resolves sol/luna/terra end-to-end from three copy-pasteable
#      capability_matrix rows (the part-B proof: config change, not redesign).
#
# Negative controls (E2E-KILLRATE-01) are embedded as mutated COPIES of
# codex-task.sh — each mutation lands INSIDE _resolve_tier_model_effort's
# body, never at top level — and the suite requires its own assertions to go
# red on them: (m1) re-collapsed tiers must break the resolved-model check
# for at least two different tiers; (m2) a silent no-journal astra fallback
# must break the missing-journal-line check. Mutants are written as siblings
# of the real script (its lib/ sourcing is BASH_SOURCE-relative) and removed
# by the EXIT trap.
#
# run-all-triggers: codex-task leadv2-launch-registry
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CODEX_TASK_SH="${SCRIPTS_DIR}/codex-task.sh"
REGISTRY_PY="${SCRIPTS_DIR}/lib/leadv2-launch-registry.py"

PASS=0
FAIL=0
pass() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

BASE="$(mktemp -d "${TMPDIR:-/tmp}/codex-tmt.XXXXXX")"
cleanup() {
  rm -rf "$BASE"
  rm -f "${SCRIPTS_DIR}/.codex-task-mutant-m1-tmp.sh" "${SCRIPTS_DIR}/.codex-task-mutant-m2-tmp.sh"
  return 0
}
trap cleanup EXIT

[[ -f "$CODEX_TASK_SH" ]] || { echo "FATAL: $CODEX_TASK_SH missing"; exit 2; }
[[ -f "$REGISTRY_PY" ]]  || { echo "FATAL: $REGISTRY_PY missing"; exit 2; }

# ── shared stubs (same shape as test-codex-quota-guardrails.sh) ─────────────
STUBBIN="$BASE/stubbin"
mkdir -p "$STUBBIN"
cat > "$STUBBIN/node" <<'EOF'
#!/usr/bin/env bash
echo "ARGV: $*" >> "${CODEX_ARGV_LOG:-/dev/null}"
exit 0
EOF
chmod +x "$STUBBIN/node"

ISOLATED_HOME="$BASE/home"
mkdir -p "$ISOLATED_HOME/.claude/plugins/cache/openai-codex/codex/1.0.4/scripts"
printf 'process.exit(0);\n' > "$ISOLATED_HOME/.claude/plugins/cache/openai-codex/codex/1.0.4/scripts/codex-companion.mjs"

# ── fixture models_cache.json variants ──────────────────────────────────────
mkcache() { local slugs="$1" out="$2"; : > "$out"
  for s in $slugs; do printf '{"slug":"%s"}\n' "$s" >> "$out"; done
  jq -s '{models:.}' "$out" > "${out}.j" && mv "${out}.j" "$out"; }
CACHE_FULL="$BASE/cache-full.json"        # every tier's primary present
mkcache "gpt-6-astra gpt-5.6-sol gpt-5.6-terra gpt-5.6-luna gpt-5.5" "$CACHE_FULL"
CACHE_NO_SOL="$BASE/cache-no-sol.json"    # top falls back to terra (journaled)
mkcache "gpt-6-astra gpt-5.6-terra gpt-5.6-luna gpt-5.5" "$CACHE_NO_SOL"
CACHE_ASTRA_ONLY="$BASE/cache-astra-only.json"  # standard+volume fall back to astra
mkcache "gpt-6-astra gpt-5.5" "$CACHE_ASTRA_ONLY"
CACHE_MISSING="$BASE/does-not-exist.json" # unreadable -> terminal astra, never fail

TIER_LOG="$BASE/tier-log.jsonl"

# run_tier <script> <cache> <tier> <with_reason:0|1> — runs one stubbed
# dispatch; stderr -> $ERR, forwarded argv -> $ARGV.
run_tier() {
  local script="$1" cache="$2" tier="$3" with_reason="$4"
  ERR="$BASE/err.$$"; ARGV="$BASE/argv.$$"; rm -f "$ERR" "$ARGV"
  local reason=()
  [[ "$with_reason" == "1" ]] && reason=(--reason "A1-CODEX-TIERS-A2 suite self-test")
  HOME="$ISOLATED_HOME" PATH="$STUBBIN:$PATH" CODEX_SKIP_QUOTA_GATE=1 \
    CODEX_ARGV_LOG="$ARGV" CODEX_MODELS_CACHE="$cache" \
    LEADV2_CODEX_TIER_LOG="$TIER_LOG" \
    bash "$script" task "tmt-probe" --tier "$tier" "${reason[@]}" \
    --cwd "$BASE" >"$BASE/out.$$" 2>"$ERR" || true
}

# ════════════════════════════════════════════════════════════════════════════
# Group 1 — each tier resolves to its OWN model (resolution line + argv)
# ════════════════════════════════════════════════════════════════════════════
check_primary() { # <tier> <model> <effort>
  local tier="$1" model="$2" effort="$3" with_reason=0
  [[ "$tier" == "top" ]] && with_reason=1
  run_tier "$CODEX_TASK_SH" "$CACHE_FULL" "$tier" "$with_reason"
  if grep -q "tier=$tier -> model=$model effort=$effort (sub=task)" "$ERR"; then
    pass "g1: tier=$tier resolves $model/$effort in its own resolution line"
  else
    fail "g1: tier=$tier resolution line missing '$model/$effort': $(grep -h 'tier=' "$ERR" | tail -1)"
  fi
  if grep -q -- "--model $model" "$ARGV" && grep -q -- "--effort $effort" "$ARGV"; then
    pass "g1: tier=$tier forwards --model $model --effort $effort to the companion"
  else
    fail "g1: tier=$tier argv does not pin $model/$effort: $(tail -1 "$ARGV" 2>/dev/null)"
  fi
}
check_primary top      gpt-5.6-sol   high
check_primary standard gpt-5.6-terra medium
check_primary volume   gpt-5.6-luna  low

# ════════════════════════════════════════════════════════════════════════════
# Group 2 — absent model => NAMED fallback, journaled (never a silent astra)
# ════════════════════════════════════════════════════════════════════════════
run_tier "$CODEX_TASK_SH" "$CACHE_NO_SOL" top 1
if grep -q "tier=top fallback: gpt-5.6-sol absent from .* -> gpt-5.6-terra" "$ERR"; then
  pass "g2: sol absent => journal names sol and the terra fallback"
else
  fail "g2: sol-absent journal line missing: $(grep -h fallback "$ERR" | tail -1)"
fi
if grep -q "tier=top -> model=gpt-5.6-terra effort=high (sub=task)" "$ERR"; then
  pass "g2: top-without-sol resolves terra/high"
else
  fail "g2: top-without-sol resolution wrong: $(grep -h 'tier=' "$ERR" | tail -1)"
fi
if grep -q '"model":"gpt-5.6-sol"' "$TIER_LOG"; then
  pass "g2: top-tier ledger records the resolved model gpt-5.6-sol"
else
  fail "g2: tier ledger missing gpt-5.6-sol: $(tail -1 "$TIER_LOG" 2>/dev/null)"
fi

run_tier "$CODEX_TASK_SH" "$CACHE_ASTRA_ONLY" standard 0
if grep -q "tier=standard fallback: gpt-5.6-terra absent from .* -> gpt-6-astra" "$ERR" \
   && grep -q "tier=standard -> model=gpt-6-astra effort=medium (sub=task)" "$ERR"; then
  pass "g2: terra absent => journaled astra fallback for standard"
else
  fail "g2: standard astra-fallback path wrong: $(grep -h 'tier=\|fallback' "$ERR" | tail -2)"
fi
run_tier "$CODEX_TASK_SH" "$CACHE_ASTRA_ONLY" volume 0
if grep -q "tier=volume fallback: gpt-5.6-luna absent from .* -> gpt-6-astra" "$ERR" \
   && grep -q "tier=volume -> model=gpt-6-astra effort=low (sub=task)" "$ERR"; then
  pass "g2: luna absent => journaled astra fallback for volume"
else
  fail "g2: volume astra-fallback path wrong: $(grep -h 'tier=\|fallback' "$ERR" | tail -2)"
fi

# ════════════════════════════════════════════════════════════════════════════
# Group 3 — unreadable cache NEVER fails the dispatch (terminal astra + journal)
# ════════════════════════════════════════════════════════════════════════════
run_tier "$CODEX_TASK_SH" "$CACHE_MISSING" standard 0
if grep -q "tier=standard fallback: models_cache unreadable at .* -> gpt-6-astra (presence unverified)" "$ERR" \
   && grep -q "tier=standard -> model=gpt-6-astra effort=medium (sub=task)" "$ERR" \
   && grep -q -- "--model gpt-6-astra" "$ARGV"; then
  pass "g3: unreadable cache => astra/medium + journal line, dispatch proceeds"
else
  fail "g3: unreadable-cache path wrong: $(grep -h 'tier=\|fallback' "$ERR" | tail -2)"
fi

# ════════════════════════════════════════════════════════════════════════════
# Group 4 — effort is per TIER, distinguishable from the model choice
# ════════════════════════════════════════════════════════════════════════════
# Same resolved model (terra) via two different tiers must carry two different
# efforts: top-without-sol => terra/HIGH, standard => terra/MEDIUM.
run_tier "$CODEX_TASK_SH" "$CACHE_NO_SOL" top 1
TMT_TOP_TERRA="$(grep -o 'tier=top -> model=gpt-5.6-terra effort=[a-z]*' "$ERR" | tail -1)"
run_tier "$CODEX_TASK_SH" "$CACHE_FULL" standard 0
TMT_STD_TERRA="$(grep -o 'tier=standard -> model=gpt-5.6-terra effort=[a-z]*' "$ERR" | tail -1)"
if [[ "$TMT_TOP_TERRA" == *effort=high* && "$TMT_STD_TERRA" == *effort=medium* ]]; then
  pass "g4: same model (terra), two tiers, two efforts (high vs medium) — not folded"
else
  fail "g4: effort folded into model: top='$TMT_TOP_TERRA' standard='$TMT_STD_TERRA'"
fi

# ════════════════════════════════════════════════════════════════════════════
# Group 5 — launch registry: (model, tier) entries, per-class effort, refusal
# ════════════════════════════════════════════════════════════════════════════
PY_OUT="$(REGISTRY_PATH="$REGISTRY_PY" python3 - "$REGISTRY_PY" <<'EOF'
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("lr", sys.argv[1])
lr = importlib.util.module_from_spec(spec); spec.loader.exec_module(lr)
checks = {}
checks["pairs"] = sorted("%s@%s" % p for p in lr.CODEX_MODEL_TIERS) == sorted([
    "gpt-5.6-sol@top", "gpt-5.6-terra@top", "gpt-5.6-terra@standard",
    "gpt-5.6-luna@volume", "gpt-6-astra@top", "gpt-6-astra@standard", "gpt-6-astra@volume"])
checks["effort_varies_by_class"] = (
    lr.codex_effort_for("gpt-5.6-terra", "top", "trivial") == "medium"
    and lr.codex_effort_for("gpt-5.6-terra", "top", "heavy") == "xhigh"
    and lr.codex_effort_for("gpt-5.6-luna", "volume", "heavy") == "medium"
    and lr.codex_effort_for("gpt-5.6-luna", "volume", "standard") == "low")
checks["unregistered_pair_none"] = lr.codex_effort_for("gpt-5.5", "top", None) is None
argv_task, sup_task = lr._argv_codex("developer", "gpt-5.6-sol", "top", "high", "code")
checks["task_wire_pins_model_effort"] = (
    argv_task == ["--tier", "top", "--model", "gpt-5.6-sol", "--effort", "high"] and sup_task is True)
argv_rev, sup_rev = lr._argv_codex("developer", "gpt-6-astra", "standard", "medium", "review")
checks["review_shape_frozen"] = argv_rev == ["--tier", "standard"] and sup_rev is False
argv_legacy, sup_legacy = lr._argv_codex("developer", "gpt-6-astra", "top", "high")
checks["legacy_4arg_shape"] = (
    argv_legacy == ["--tier", "top", "--reason", "registry-resolved-top-tier"] and sup_legacy is False)
print(json.dumps(checks))
EOF
)" || PY_OUT="{}"
for k in pairs effort_varies_by_class unregistered_pair_none task_wire_pins_model_effort \
          review_shape_frozen legacy_4arg_shape; do
  if [[ "$(printf '%s' "$PY_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$k'))")" == "True" ]]; then
    pass "g5: registry $k"
  else
    fail "g5: registry $k -- $PY_OUT"
  fi
done

# Part-B proof: the three capability_matrix rows from the lane report, pasted
# into a fixture routing.yaml, make lookup() resolve sol/terra/luna with no
# registry edit (config change, not redesign).
FIXTURE_YAML="$BASE/routing-fixture.yaml"
cat > "$FIXTURE_YAML" <<'EOF'
router_v2:
  capability_matrix:
    - { arm: codex, provider: codex, model: gpt-5.6-luna, tier: volume, cost: 3, kinds: [code, docs, review, plan, audit, fanout-class-funnel, backlog-pump], sizes: [standard], tags: [mechanical], review: true, protected: true, capability: 3 }
    - { arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, cost: 4, kinds: [code, docs, review, plan, audit, fanout-class-funnel, backlog-pump], sizes: [standard, heavy], tags: [review, adversarial], review: true, protected: true, capability: 4 }
    - { arm: codex, provider: codex, model: gpt-5.6-sol, tier: top, cost: 7, kinds: [code, review, plan, audit, fanout-class-funnel, backlog-pump], sizes: [heavy], tags: [adversarial, exhaustive], review: true, protected: true, capability: 4 }
EOF
partb() { # <label> <task_class> <expected substring of argv>
  local out
  out="$(LEADV2_ROUTE_ARBITER_ROUTING_YAML="$FIXTURE_YAML" python3 "$REGISTRY_PY" \
    --kind code --role developer --arm codex --task-class "$1" --json 2>&1)" || true
  if [[ "$out" == *"$2"* && "$out" == *'"ok": true'* ]]; then
    pass "g5: part-B rows: code/$1 -> $2"
  else
    fail "g5: part-B rows: code/$1 expected '$2' got: $out"
  fi
}
partb standard '"--model", "gpt-5.6-luna", "--effort", "low"'
partb heavy    '"--model", "gpt-5.6-terra", "--effort", "high"'

# Unregistered matrix pair must REFUSE (narrowing): gpt-5.5 is on the account
# but is no tier's model in codex-task.sh's table.
BAD_YAML="$BASE/routing-bad.yaml"
printf 'router_v2:\n  capability_matrix:\n    - { arm: codex, provider: codex, model: gpt-5.5, tier: standard, cost: 4, kinds: [code], sizes: [standard], review: true, protected: true, capability: 4 }\n' > "$BAD_YAML"
BAD_OUT="$(LEADV2_ROUTE_ARBITER_ROUTING_YAML="$BAD_YAML" python3 "$REGISTRY_PY" \
  --kind code --role developer --arm codex --task-class standard --json 2>&1)" || true
if [[ "$BAD_OUT" == *'"reason": "codex_model_tier_not_registered"'* ]]; then
  pass "g5: unregistered (model,tier) pair refuses instead of substituting"
else
  fail "g5: unregistered pair not refused: $BAD_OUT"
fi

# A1-CODEX-TIERS-A3: check() must accept EVERY registered codex model, not
# first-row-wins -- under the old scalar canonical, part B's three-model
# matrix would make check("codex", "gpt-5.6-sol") refuse (first codex row is
# luna/volume), vetoing exactly the models part A made launchable.
CHK_OUT="$(LEADV2_ROUTE_ARBITER_ROUTING_YAML="$FIXTURE_YAML" python3 - "$REGISTRY_PY" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("lr", sys.argv[1])
lr = importlib.util.module_from_spec(spec); spec.loader.exec_module(lr)
for m in ("gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"):
    assert lr.check("codex", m) == "ok", (m, lr.check("codex", m))
assert lr.check("codex", "gpt-5.5") == "refuse"
assert lr.check("fable", "sonnet") == "refuse"
assert lr.check("haiku", "haiku") == "ok"
print("fixture-ok")
PYEOF
)" && pass "g5: check() accepts every registered codex model (3-model fixture)"   || fail "g5: multi-model check() broken on fixture: $CHK_OUT"
LIVE_CHK="$(python3 "$REGISTRY_PY" --check --arm codex --model gpt-6-astra 2>&1)"
if [[ "$LIVE_CHK" == "ok" ]]; then
  pass "g5: check() codex/gpt-6-astra ok on live all-astra matrix (no widening)"
else
  fail "g5: live-matrix check wrong: $LIVE_CHK"
fi

# ════════════════════════════════════════════════════════════════════════════
# Group 6 — embedded negative controls (E2E-KILLRATE-01)
# ════════════════════════════════════════════════════════════════════════════
# m1: re-collapse every tier onto gpt-6-astra INSIDE _resolve_tier_model_effort
# (the three chain assignments are in its body); the Group-1 model checks must
# go red for at least two different tiers.
M1="${SCRIPTS_DIR}/.codex-task-mutant-m1-tmp.sh"
cp "$CODEX_TASK_SH" "$M1"
M1_CNT="$(grep -c '_chain=(gpt-5.6-' "$M1" || true)"
if [[ "$M1_CNT" -eq 3 ]]; then
  sed -i '' \
    -e 's/_chain=(gpt-5.6-sol gpt-5.6-terra gpt-6-astra)/_chain=(gpt-6-astra)/' \
    -e 's/_chain=(gpt-5.6-terra gpt-6-astra)/_chain=(gpt-6-astra)/' \
    -e 's/_chain=(gpt-5.6-luna gpt-6-astra)/_chain=(gpt-6-astra)/' "$M1"
  M1_RED=0
  for t in top standard volume; do
    wr=0; [[ "$t" == "top" ]] && wr=1
    run_tier "$M1" "$CACHE_FULL" "$t" "$wr"
    if ! grep -q "tier=$t -> model=gpt-5.6-" "$ERR" || grep -q "tier=$t -> model=gpt-6-astra" "$ERR"; then
      M1_RED=$((M1_RED + 1))
    fi
  done
  if [[ "$M1_RED" -ge 2 ]]; then
    pass "m1: re-collapsed table caught on $M1_RED/3 tiers (need >=2)"
  else
    fail "m1: re-collapse NOT caught (red on $M1_RED/3 tiers) — Group-1 assertions are decorative"
  fi
else
  fail "m1: control_not_applied — chain anchor count is $M1_CNT, expected 3"
fi
rm -f "$M1"

# m2: absent model resolves SILENTLY to astra (journal line deleted inside the
# resolver body); the Group-2 journal-line check must go red.
M2="${SCRIPTS_DIR}/.codex-task-mutant-m2-tmp.sh"
cp "$CODEX_TASK_SH" "$M2"
M2_ANCHOR='echo "[codex-task] tier=$_tier fallback: $_missing absent from $_mc -> $_chosen" >&2'
if [[ "$(grep -cF "$M2_ANCHOR" "$M2")" -eq 1 ]]; then
  python3 - "$M2" <<'EOF'
import sys
path = sys.argv[1]
src = open(path).read()
anchor = 'echo "[codex-task] tier=$_tier fallback: $_missing absent from $_mc -> $_chosen" >&2'
assert src.count(anchor) == 1, "anchor drifted"
open(path, "w").write(src.replace(
    anchor, '_chosen="gpt-6-astra"  # MUTATED-NEGATIVE-CONTROL: silent astra, no journal'))
EOF
  run_tier "$M2" "$CACHE_NO_SOL" top 1
  if ! grep -q "gpt-5.6-sol absent" "$ERR"; then
    pass "m2: silent (unjournalled) fallback caught by the missing journal line"
  else
    fail "m2: silent fallback NOT caught — journal assertion is decorative"
  fi
else
  fail "m2: control_not_applied — journal-line anchor not found exactly once"
fi
rm -f "$M2"

# ── verdict ─────────────────────────────────────────────────────────────────
printf '\n== test-codex-tier-model-table: PASS=%d FAIL=%d ==\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
