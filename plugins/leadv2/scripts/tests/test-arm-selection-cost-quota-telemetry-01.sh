#!/usr/bin/env bash
# ARM-SELECTION-COST-QUOTA-TELEMETRY-01 — hermetic coverage for the 4 changes
# this lane made to scripts/lib/leadv2-route-arbiter.sh, per
# docs/reference/arm-selection-proposal-2026-09-16.md §4.2-4.4, §5:
#
#   A) §4.2 cost provenance — router_v2.cost entries may be a bare number
#      (legacy) or a dict {value,source,observed_at,sample_count,confidence};
#      provider.model.effort / provider.model / provider keys are tried in
#      that order (_price_key_candidates); cost_src names which one matched
#      and carries the metadata tokens when present.
#   B) §4.3 quota — a scoped-Claude arm's own weekly_scoped window no longer
#      pops the account's seven_day aggregate; both bind (worst-of-readable).
#   C) §4.4 rotation — the equal-ecost anti-stickiness alternative is
#      filtered to the WINNER's fit bucket; a worse-fit arm never becomes the
#      new pick just because it costs the same.
#   D) §5 telemetry — arm_excluded/price_ratio is untouched (byte-identical;
#      test-exclusion-stages.sh and test-arbiter-decision-record-inputs.sh
#      assert its exact string); a new, purely additive `loser_detail=`
#      token on the stdout decision line names WHY each loser lost:
#      insufficient_fit | cost_unknown | higher_expected_cost.
#
# Harness conventions (arb_record / write_yaml_skeleton / quota fragments)
# mirror plugins/leadv2/scripts/tests/test-arm-selection-decision-fixtures-01.sh
# so a reviewer who knows that suite can read this one at a glance. This
# suite asserts against the arbiter's stdout decision line and decisions.jsonl
# directly (no baseline directory) — it owns no yaml/report files outside its
# own name.
#
# changed-scope triggers, self-registered:
# run-all-triggers: leadv2-route-arbiter
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "${HERE}/.." && pwd)"
ARBITER="${SCRIPTS}/lib/leadv2-route-arbiter.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d /private/tmp/arm-sel-cqt.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
: >"${WORK}/empty-events.jsonl"

Q_GLM_OK='"glm":{"status":"ok","five_hour":{"pct":10,"hours_to_reset":4.5},"weekly":{"pct":20,"hours_to_reset":100.0}}'
Q_CODEX_OK='"codex":{"status":"ok","windows":[{"kind":"weekly","used_percent":20,"hours_to_reset":100.0}]}'
Q_ANT_OK='"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","account_label":"max_20x","five_hour":{"pct":10,"hours_to_reset":3.0},"seven_day":{"pct":10,"hours_to_reset":120.0}}]}'
Q_ANT_TIRED='"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","account_label":"max_20x","five_hour":{"pct":20,"hours_to_reset":2.0},"seven_day":{"pct":60,"hours_to_reset":120.0}}]}'
Q_CODEX_TIRED='"codex":{"status":"ok","windows":[{"kind":"weekly","used_percent":60,"hours_to_reset":100.0}]}'

write_yaml_skeleton() { # <file> <cost-block-lines...via stdin>
  cat >"$1" <<'YAML'
router_v2:
  quota_ceilings:
    glm:    { work_pct: 95, review_pct: 98 }
    codex:  { work_pct: 95, review_pct: 98 }
    claude: { work_pct: 95, review_pct: 95 }
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix:
    - {default: true, effort: medium}
  observed_cost: {min_rows: 3}
YAML
  cat >>"$1"
  cat >>"$1" <<'YAML'
  cost_unpriced_policy: matrix_median
  capability_fit:
    enabled: true
    prior: 3.0
    slack: 0.5
    cap_default: 3.0
    complexity_ordinal: {trivial: 1, simple: 2, standard: 3, complex: 4}
    source_confidence: {judge: 0.9, flag: 0.7, heuristic: 0.4, unknown: 0.0}
  complexity_penalty: []
  capability_matrix:
YAML
}

arb_record() { # <out-file> <label> <role> <descriptor-json> <routing-yaml>
               # <quota-json> <state-seed-json|-> [ENV=VAL ...]
  local out="$1" label="$2" role="$3" desc="$4" yamlf="$5" quota="$6" seed="$7"
  shift 7
  local t out_txt rc
  t="$(mktemp -d "${WORK}/inv.XXXXXX")"
  printf '%s\n' "$quota" >"${t}/quota.json"
  cat >"${t}/live.sh" <<'EOF'
#!/usr/bin/env bash
cat "${QUOTA_JSON:-/dev/null}"
EOF
  cat >"${t}/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${t}/live.sh" "${t}/free.sh"
  : >"${t}/ledger.jsonl"
  rm -f "${t}/state"
  if [ "$seed" != "-" ]; then printf '%s\n' "$seed" >"${t}/state"; fi
  out_txt="$(env -u LEADV2_ARBITER_CAPABILITY_FIT \
    LEADV2_QUOTA_LIVE="${t}/live.sh" \
    LEADV2_ROUTE_ARBITER_ROUTING_YAML="$yamlf" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="${t}/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="${t}/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="${t}/state" \
    LEADV2_ROUTE_ARBITER_DECISIONS_FILE="${t}/decisions.jsonl" \
    LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="${WORK}/empty-events.jsonl" \
    LEADV2_ROUTE_ARBITER_FAILURE_LEDGER="${t}/ledger.jsonl" \
    LEADV2_ROUTE_ARBITER_MODEL_CAPABILITY_YAML=/dev/null \
    QUOTA_JSON="${t}/quota.json" \
    LEADV2_ARBITER_SPEND_FORECAST=0 \
    "$@" bash "$ARBITER" "$role" "$desc" 2>"${t}/stderr")"; rc=$?
  printf '## %s rc=%s\n%s\n' "$label" "$rc" "$out_txt" >>"$out"
  DECISIONS_FILE="${t}/decisions.jsonl"
  LAST_RC=$rc
  LAST_STDOUT="$out_txt"
}

std_arms() {
  local d="$1"
  cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: glm, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: sonnet, provider: claude, model: sonnet, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
YAML
}

DESC='{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"cqt fixture"}'

OUT="${WORK}/out.txt"

# ── A: cost provenance (§4.2) ────────────────────────────────────────────
# A1: a dict-shaped cost entry carries source/observed_at/sample_count/
# confidence through to cost_src on the winner's decision line.
d="${WORK}/a1"; mkdir -p "$d"
write_yaml_skeleton "${d}/routing.yaml" <<'YAML'
  cost:
    glm: {value: 0.4, source: live_probe, observed_at: "2026-09-10T00:00:00Z", sample_count: 12, confidence: 0.9}
    glm-flash: 0.33
    codex: 5.0
    anthropic: 5.0
    freepool: 1.0
YAML
std_arms "$d"
arb_record "$OUT" a1-dict-cost-metadata worker "$DESC" "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_OK,$Q_ANT_OK}" -
if [[ "$LAST_STDOUT" == *"arm=glm "* ]] && [[ "$LAST_STDOUT" == *"cost_src=glm:measured cost_conf=0.9 cost_n=12 cost_at=2026-09-10T00:00:00Z cost_prov=live_probe"* ]]; then
  pass "A1: dict cost entry -> cost_src carries cost_conf/cost_n/cost_at/cost_prov"
else
  fail "A1: dict cost entry -> cost_src carries cost_conf/cost_n/cost_at/cost_prov -- $(printf '%s' "$LAST_STDOUT" | head -c 400)"
fi

# A2: a bare-number cost entry (legacy shape) still resolves and reads
# measured with NO metadata tokens -- proves the dict branch is additive,
# not a behavior change for the existing plain-number config shape.
d="${WORK}/a2"; mkdir -p "$d"
write_yaml_skeleton "${d}/routing.yaml" <<'YAML'
  cost:
    glm: 0.4
    glm-flash: 0.33
    codex: 5.0
    anthropic: 5.0
    freepool: 1.0
YAML
std_arms "$d"
arb_record "$OUT" a2-plain-number-cost worker "$DESC" "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_OK,$Q_ANT_OK}" -
if [[ "$LAST_STDOUT" == *"cost_src=glm:measured "* ]] && [[ "$LAST_STDOUT" != *"cost_conf="* ]]; then
  pass "A2: plain-number cost entry -> cost_src=glm:measured, no metadata tokens"
else
  fail "A2: plain-number cost entry -> cost_src=glm:measured, no metadata tokens -- $(printf '%s' "$LAST_STDOUT" | head -c 400)"
fi

# A3: an unpriced (null) arm falls back to the matrix median and cost_src
# names it :median, never disguised as :measured -- winner is codex here
# (glm capped out so codex's own cost_src is what prints).
d="${WORK}/a3"; mkdir -p "$d"
write_yaml_skeleton "${d}/routing.yaml" <<'YAML'
  cost:
    glm: 0.4
    glm-flash: 0.33
    codex: null
    anthropic: 5.0
    freepool: 1.0
YAML
cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
YAML
arb_record "$OUT" a3-null-cost-is-median worker "$DESC" "${d}/routing.yaml" "{$Q_CODEX_OK}" -
if [[ "$LAST_STDOUT" == *"arm=codex "* ]] && [[ "$LAST_STDOUT" == *"cost_src=codex:median"* ]]; then
  pass "A3: null-priced winner -> cost_src=codex:median (never :measured)"
else
  fail "A3: null-priced winner -> cost_src=codex:median -- $(printf '%s' "$LAST_STDOUT" | head -c 400)"
fi

# A4: provider.model key (the new, more-specific candidate) wins over the
# provider-level fallback when both are present -- and the separator is '.'
# (not ':'), because the stdlib YAML-subset loader's key regex
# ([A-Za-z0-9_.-]+) refuses a colon.
d="${WORK}/a4"; mkdir -p "$d"
write_yaml_skeleton "${d}/routing.yaml" <<'YAML'
  cost:
    glm: 0.4
    glm.glm-6-costly: 9.0
    glm-flash: 0.33
    codex: 5.0
    anthropic: 5.0
    freepool: 1.0
YAML
cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: pricey, provider: glm, model: glm-6-costly, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
YAML
arb_record "$OUT" a4-provider-model-key worker "$DESC" "${d}/routing.yaml" "{$Q_GLM_OK}" -
if [[ "$LAST_STDOUT" == *"arm=pricey "* ]] && [[ "$LAST_STDOUT" == *"cost_src=glm.glm-6-costly:measured"* ]]; then
  pass "A4: provider.model cost key matched ahead of the provider-level key"
else
  fail "A4: provider.model cost key matched ahead of the provider-level key -- $(printf '%s' "$LAST_STDOUT" | head -c 400)"
fi

# ── B: quota keep-both (§4.3) ────────────────────────────────────────────
# fable has its own weekly_scoped window AND participates in the account's
# general seven_day aggregate. B1: scoped window free, general weekly
# exhausted (97%) -- fable must now be EXCLUDED (capped) on the general
# window; before this fix the general window's seven_day reading was
# popped and fable was silently admitted. B2 (control): scoped window
# exhausted, general free -- fable stays capped either way (unaffected by
# this fix, proves the fix didn't just flip capped->admitted everywhere).
d="${WORK}/b1"; mkdir -p "$d"
write_yaml_skeleton "${d}/routing.yaml" <<'YAML'
  cost:
    glm: 5.0
    glm-flash: 0.33
    codex: 5.0
    anthropic: 0.4
    freepool: 1.0
YAML
cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: fable, provider: claude, model: fable, tier: high, kinds: [review], sizes: [standard], protected: true, capability: 6}
    - {arm: sonnet, provider: claude, model: sonnet, tier: standard, kinds: [review], sizes: [standard], protected: true, capability: 4}
YAML
Q_SCOPED_FREE_GENERAL_OUT='"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","account_label":"max_20x","five_hour":{"pct":10,"hours_to_reset":3.0},"seven_day":{"pct":97,"hours_to_reset":120.0},"weekly_scoped":{"Fable":{"pct":0,"hours_to_reset":120.0}}}]}'
arb_record "$OUT" b1-scoped-free-general-out worker \
  '{"kind":"review","size":"standard","complexity":"standard","complexity_source":"judge","task":"b1 general exhausted"}' \
  "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_OK,$Q_SCOPED_FREE_GENERAL_OUT}" -
if [[ "$LAST_STDOUT" == *'"fable": "capped"'* || "$LAST_STDOUT" == *'fable:'*'capped'* ]] && [[ "$LAST_STDOUT" != *"arm=fable "* ]]; then
  pass "B1: scoped free but general weekly 97% -> fable excluded (both windows bind)"
else
  fail "B1: scoped free but general weekly 97% -> fable excluded -- $(printf '%s' "$LAST_STDOUT" | head -c 500)"
fi

Q_SCOPED_OUT_GENERAL_FREE='"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","account_label":"max_20x","five_hour":{"pct":10,"hours_to_reset":3.0},"seven_day":{"pct":0,"hours_to_reset":120.0},"weekly_scoped":{"Fable":{"pct":98,"hours_to_reset":120.0}}}]}'
arb_record "$OUT" b2-scoped-out-general-free worker \
  '{"kind":"review","size":"standard","complexity":"standard","complexity_source":"judge","task":"b2 scoped exhausted"}' \
  "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_OK,$Q_SCOPED_OUT_GENERAL_FREE}" -
if [[ "$LAST_STDOUT" != *"arm=fable "* ]]; then
  pass "B2 (control): scoped exhausted, general free -> fable still excluded on its own window"
else
  fail "B2 (control): scoped exhausted, general free -> fable still excluded -- $(printf '%s' "$LAST_STDOUT" | head -c 500)"
fi

# ── C: rotation keeps fit bucket (§4.4) ──────────────────────────────────
# alpha/gamma: equal ecost (same provider, same cost key), buckets 0 and 1.
# Seeded last=alpha, no other bucket-0 arm exists. Old code: gamma is a
# valid equal-ecost alternative (!=last) and rotation swaps to a WORSE fit.
# Fixed code: gamma is filtered out (its fit bucket != winner's), so the
# pick stays alpha.
d="${WORK}/c1"; mkdir -p "$d"
write_yaml_skeleton "${d}/routing.yaml" <<'YAML'
  cost:
    glm: 1.0
    glm-flash: 0.33
    codex: 5.0
    anthropic: 5.0
    freepool: 1.0
YAML
cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: alpha, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: gamma, provider: glm, model: glm-5.3-mini, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 2}
YAML
arb_record "$OUT" c1-no-same-bucket-alternative worker "$DESC" "${d}/routing.yaml" "{$Q_GLM_OK}" '{"arm":"alpha"}'
if [[ "$LAST_STDOUT" == *"arm=alpha "* ]]; then
  pass "C1: equal ecost, no same-fit-bucket alternative -> rotation stays on alpha (does not demote to gamma)"
else
  fail "C1: rotation must not demote to a worse-fit arm -- $(printf '%s' "$LAST_STDOUT" | head -c 400)"
fi

# C2 (control): a same-bucket alternative (beta, also capability 4) DOES
# exist alongside gamma (capability 2) -- rotation still works normally and
# picks beta, never gamma.
d="${WORK}/c2"; mkdir -p "$d"
write_yaml_skeleton "${d}/routing.yaml" <<'YAML'
  cost:
    glm: 1.0
    glm-flash: 0.33
    codex: 5.0
    anthropic: 5.0
    freepool: 1.0
YAML
cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: alpha, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: beta, provider: glm, model: glm-5.3-b, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: gamma, provider: glm, model: glm-5.3-mini, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 2}
YAML
arb_record "$OUT" c2-same-bucket-alternative-exists worker "$DESC" "${d}/routing.yaml" "{$Q_GLM_OK}" '{"arm":"alpha"}'
if [[ "$LAST_STDOUT" == *"arm=beta "* ]]; then
  pass "C2 (control): rotation picks the same-fit-bucket alternative (beta), not gamma"
else
  fail "C2 (control): rotation should pick beta -- $(printf '%s' "$LAST_STDOUT" | head -c 400)"
fi

# ── D: loser_detail telemetry (§5) ───────────────────────────────────────
# 4 admitted arms, one winner (cheap, glm, bucket0), three losers each for a
# DIFFERENT reason: costlyfit (codex, bucket1 -> insufficient_fit even
# though its own price is cheap), unknownprice (glm, bucket0, no cost key
# resolves -> matrix-median fallback -> cost_unknown), pricey (glm, bucket0,
# a known HIGHER price via the glm.glm-6-costly key -> higher_expected_cost).
# cheap/unknownprice/pricey share ONE provider (glm) deliberately: ecost also
# folds in a per-provider headroom/reset-urgency weight, and putting the
# cost_unknown loser on a different provider (claude) let that weight alone
# flip the intended winner in an earlier draft of this fixture -- same
# provider means only the price term differs between them. arm_excluded/
# price_ratio must stay byte-identical for all three losers (the old
# contract); the new information rides on loser_detail= only.
d="${WORK}/d1"; mkdir -p "$d"
write_yaml_skeleton "${d}/routing.yaml" <<'YAML'
  cost:
    glm: null
    glm.glm-5.3: 0.4
    glm.glm-6-costly: 9.0
    glm-flash: 0.33
    codex: 0.1
    anthropic: 5.0
    freepool: 1.0
YAML
cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: cheap, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: pricey, provider: glm, model: glm-6-costly, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: unknownprice, provider: glm, model: glm-5.3-mystery, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: costlyfit, provider: codex, model: gpt-5.6-terra, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 2}
YAML
arb_record "$OUT" d1-loser-detail-reasons worker "$DESC" "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_OK}" -
d1_dec="$DECISIONS_FILE"
if [[ "$LAST_STDOUT" == *"arm=cheap "* ]]; then
  pass "D1: winner is cheap (glm, bucket0, lowest known price)"
else
  fail "D1: expected winner=cheap -- $(printf '%s' "$LAST_STDOUT" | head -c 400)"
fi
for pair in 'costlyfit:price_ratio' 'unknownprice:price_ratio' 'pricey:price_ratio'; do
  if [[ "$LAST_STDOUT" == *"$pair"* ]]; then
    pass "D1: arm_excluded carries ${pair} (byte-identical legacy contract)"
  else
    fail "D1: arm_excluded should carry ${pair} -- $(printf '%s' "$LAST_STDOUT" | head -c 600)"
  fi
done
if [[ "$LAST_STDOUT" == *"loser_detail="* ]]; then
  detail="$(printf '%s' "$LAST_STDOUT" | grep -o 'loser_detail=[^ ]*')"
  ok=1
  [[ "$detail" == *"costlyfit:insufficient_fit"* ]] || ok=0
  [[ "$detail" == *"unknownprice:cost_unknown"* ]] || ok=0
  [[ "$detail" == *"pricey:higher_expected_cost"* ]] || ok=0
  if [[ "$ok" == 1 ]]; then
    pass "D1: loser_detail names the 3 distinct reasons ($detail)"
  else
    fail "D1: loser_detail should carry all 3 distinct reasons -- got: $detail"
  fi
else
  fail "D1: decision line is missing loser_detail= entirely"
fi

# D2: single-loser chain -- loser_detail is present with exactly one entry,
# proving it isn't just a copy of arm_excluded's keys.
d="${WORK}/d2"; mkdir -p "$d"
write_yaml_skeleton "${d}/routing.yaml" <<'YAML'
  cost:
    glm: 0.4
    glm-flash: 0.33
    codex: 9.0
    anthropic: 5.0
    freepool: 1.0
YAML
cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: glm, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
YAML
arb_record "$OUT" d2-single-loser worker "$DESC" "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_OK}" -
if [[ "$LAST_STDOUT" == *"arm=glm "* ]] && [[ "$LAST_STDOUT" == *"loser_detail=codex:higher_expected_cost"* ]]; then
  pass "D2: single genuinely-costlier loser -> loser_detail=codex:higher_expected_cost"
else
  fail "D2: single loser detail mismatch -- $(printf '%s' "$LAST_STDOUT" | head -c 400)"
fi

# D3 (round-3 review findings 2+4): the DURABLE record must carry the same
# loser_detail the stdout line carries. stdout is ephemeral -- §5 telemetry
# exists to be analysed from decisions.jsonl afterwards; asserting stdout
# alone is a false-green once the record drops the field.
if [[ -s "$d1_dec" ]]; then
  rec="$(python3 - "$d1_dec" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
win = [r for r in rows if r.get('arm') == 'cheap']
if not win:
    print('NO_WIN_RECORD')
else:
    print('loser_detail=%s' % ','.join(win[-1].get('loser_detail') or []))
PY
)"
  case "$rec" in
    *costlyfit:insufficient_fit*)
      if [[ "$rec" == *pricey:higher_expected_cost* ]] && [[ "$rec" == *unknownprice:cost_unknown* ]]; then
        pass "D3: decisions.jsonl win record carries the same loser_detail (${rec})"
      else
        fail "D3: durable record loser_detail partial -- got: ${rec}"
      fi
      ;;
    *)
      fail "D3: durable record loser_detail wrong -- got: ${rec}"
      ;;
  esac
else
  fail "D3: decisions.jsonl missing or empty at ${d1_dec}"
fi

echo "SUMMARY pass=$PASS fail=$FAIL"
[[ "$FAIL" -eq 0 ]]
