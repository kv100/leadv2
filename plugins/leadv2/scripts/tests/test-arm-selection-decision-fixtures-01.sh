#!/usr/bin/env bash
# ARM-SELECTION-DECISION-FIXTURES-01 — the instrument, before any policy changes.
#
# Hermetic decision harness for the route arbiter: given a fixed task
# descriptor, a fixed fixture routing.yaml and a fixed quota state, it records
# the arbiter's decision (the stdout decision line + the normalized structured
# decision record) with no live provider calls, no live quota reads, no
# network, no spend. It freezes the BASELINE decisions for the decision-shaped
# acceptance cases of docs/reference/arm-selection-proposal-2026-09-16.md §6
# (cases 1-13; case 14 is a documentation task owned by the lead). The brief
# says "twelve"; §6 lists thirteen decision-shaped cases — all thirteen are
# frozen here, see docs/handoff/ARM-SELECTION-DECISION-FIXTURES-01/report.md.
#
# This lane changes NO policy: if these fixtures alter a single live routing
# decision they have failed. The two policy lanes that follow (one edits
# config/leadv2-routing.yaml, one edits scripts/lib/leadv2-route-arbiter.sh)
# re-run `--record` into a fresh dir and diff against the committed baseline
# to show exactly which decisions moved and why — proposal §7: freeze the
# baseline decisions FIRST, then show the changed outcomes with reasons.
#
# Modes:
#   bash test-arm-selection-decision-fixtures-01.sh               # acceptance (default)
#   bash test-arm-selection-decision-fixtures-01.sh --record DIR  # regenerate recordings into DIR
#   bash test-arm-selection-decision-fixtures-01.sh --verify DIR  # fresh recordings diffed vs DIR
#
# Determinism contract — the one thing that decides this lane: recordings are
# byte-identical across re-runs on an unchanged tree. Fields normalized away,
# and why (a harness that hid a real nondeterminism in the decision itself
# would make both following lanes lie):
#   - decision-record 'ts' / 'ts_epoch' — wall clock of the record write, not
#     an input to the decision logic. Everything else in the record is kept,
#     including arb_rev/matrix_rev (content hashes naming the exact arbiter
#     and fixture bytes that produced the decision).
#   - the rotation state file is removed before every invocation — the arbiter
#     writes each winner into it and a leftover would rotate the NEXT run's
#     equal-ecost pick — except case05, where a seeded state file IS the
#     fixture input under test.
# PYTHONHASHSEED is deliberately left randomized: if set-iteration order ever
# leaked into a decision, the twice-run diff must be the thing that catches it.
#
# Negative control (run in acceptance mode): regenerate case01 with the
# winning arm's capability dropped by two (4 -> 2) — a change that MUST move
# the decision — and assert the recording changes AND the winner moves; then
# re-record unmutated and assert byte-identical restoration.
#
# changed-scope triggers, self-registered:
# run-all-triggers: leadv2-route-arbiter
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "${HERE}/.." && pwd)"
ARBITER="${SCRIPTS}/lib/leadv2-route-arbiter.sh"
REPO="$(cd "${SCRIPTS}/../../.." && pwd)"
BASELINE_DIR="${REPO}/docs/handoff/ARM-SELECTION-DECISION-FIXTURES-01/baseline"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d /private/tmp/arm-sel-fixtures.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
: >"${WORK}/empty-events.jsonl"

# ── fixture quota fragments (windows read by util(): glm five_hour/weekly,
# codex windows[], anthropic accounts[].five_hour/seven_day/weekly_scoped) ──
Q_GLM_OK='"glm":{"status":"ok","five_hour":{"pct":10,"hours_to_reset":4.5},"weekly":{"pct":20,"hours_to_reset":100.0}}'
Q_GLM_TIRED='"glm":{"status":"ok","five_hour":{"pct":10,"hours_to_reset":4.5},"weekly":{"pct":60,"hours_to_reset":100.0}}'
Q_GLM_OUT='"glm":{"status":"ok","five_hour":{"pct":30,"hours_to_reset":3.0},"weekly":{"pct":97,"hours_to_reset":100.0}}'
Q_CODEX_OK='"codex":{"status":"ok","windows":[{"kind":"weekly","used_percent":20,"hours_to_reset":100.0}]}'
Q_CODEX_TIRED='"codex":{"status":"ok","windows":[{"kind":"weekly","used_percent":60,"hours_to_reset":100.0}]}'
Q_ANT_OK='"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","account_label":"max_20x","five_hour":{"pct":10,"hours_to_reset":3.0},"seven_day":{"pct":10,"hours_to_reset":120.0}}]}'
Q_ANT_TIRED='"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","account_label":"max_20x","five_hour":{"pct":20,"hours_to_reset":2.0},"seven_day":{"pct":60,"hours_to_reset":120.0}}]}'
Q_ANT_OUT='"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","account_label":"max_20x","five_hour":{"pct":20,"hours_to_reset":2.0},"seven_day":{"pct":96,"hours_to_reset":120.0}}]}'

# ── shared routing.yaml skeleton — mirrors the live config's router_v2 block
# (cost keying incl. nulls, capability_fit on, the retained +100 penalty rule,
# live ceilings). Per-scenario capability_matrix rows are appended by callers.
# Block style matches plugins/leadv2/config/leadv2-routing.yaml so the stdlib
# YAML-subset loader (parse-or-refuse) sees only shapes it already ships. ──
write_yaml_skeleton() { # <file>
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
  cost:
    glm-flash: 0.33
    glm: 1.0
    codex: null
    anthropic: null
    freepool: 1.0
  cost_unpriced_policy: matrix_median
  capability_fit:
    enabled: true
    prior: 3.0
    slack: 0.5
    cap_default: 3.0
    complexity_ordinal: {trivial: 1, simple: 2, standard: 3, complex: 4}
    source_confidence: {judge: 0.9, flag: 0.7, heuristic: 0.4, unknown: 0.0}
  complexity_penalty:
    - complexities: [complex]
      penalize_tags: [cheap, mechanical]
      penalty: 100
  capability_matrix:
YAML
}

# ── recording engine ─────────────────────────────────────────────────────────
# arb_record <out-file> <label> <role> <descriptor-json> <routing-yaml>
#            <quota-json> <state-seed-json|-> <events-journal> [ENV=VAL ...]
# Appends one invocation block: rc, the stdout decision line(s), and the
# decision record with ts/ts_epoch stripped. stderr is deliberately excluded:
# it carries machine advisories (e.g. the PyYAML-unavailable NOTE), not
# decision content — a recording must not depend on the host's python site
# packages.
arb_record() {
  local out="$1" label="$2" role="$3" desc="$4" yamlf="$5" quota="$6" seed="$7" journal="$8"
  shift 8
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
    LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$journal" \
    LEADV2_ROUTE_ARBITER_FAILURE_LEDGER="${t}/ledger.jsonl" \
    LEADV2_ROUTE_ARBITER_MODEL_CAPABILITY_YAML=/dev/null \
    QUOTA_JSON="${t}/quota.json" \
    LEADV2_ARBITER_SPEND_FORECAST=0 \
    "$@" bash "$ARBITER" "$role" "$desc" 2>/dev/null)"; rc=$?
  {
    printf '## invocation: %s\n' "$label"
    printf '# descriptor: %s\n' "$desc"
    printf 'rc=%s\n' "$rc"
    printf '%s\n' "$out_txt"
    printf -- '--- decision-record\n'
    if [ -s "${t}/decisions.jsonl" ]; then
      python3 - "${t}/decisions.jsonl" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    if not line.strip():
        continue
    rec = json.loads(line)
    rec.pop('ts', None)      # wall clock of the record write, not a decision input
    rec.pop('ts_epoch', None)
    print(json.dumps(rec))
PY
    else
      printf '(none)\n'
    fi
  } >>"$out"
}

# scenario_header <out-file> <case-id-slug> <purpose>
scenario_header() {
  printf '### scenario: %s\n# purpose: %s\n' "$2" "$3" >"$1"
}

# record_all <outdir> [case01-glm-cap-override]
record_all() {
  local outdir="$1" glm_cap="${2:-}"
  mkdir -p "$outdir"

  # ── case01 — proposal case 1: standard concrete implementation; Flash is
  # ADMITTED (in the candidate set) and competes on its measured 0.33 price.
  # Baseline fact: admitted but OUT-RANKED — fit bucket 1 vs glm's 0 at
  # req_eff 3 — and labelled price_ratio (loser label, not a refusal).
  local d="${WORK}/case01"; mkdir -p "$d"
  write_yaml_skeleton "${d}/routing.yaml"
  cat >>"${d}/routing.yaml" <<YAML
    - {arm: glm, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: ${glm_cap:-4}}
    - {arm: glm-flash, provider: glm, model: glm-5.3-flash, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 2, tags: [cheap, mechanical]}
    - {arm: sonnet, provider: claude, model: sonnet, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
YAML
  scenario_header "${outdir}/case01-flash-admitted-standard.txt" case01-flash-admitted-standard \
    'proposal case 1: standard implementation task — flash admitted, competes on 0.33 credit-weight price'
  arb_record "${outdir}/case01-flash-admitted-standard.txt" a worker \
    '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"case01 standard concrete implementation"}' \
    "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_TIRED,$Q_ANT_TIRED}" - "${WORK}/empty-events.jsonl"

  # ── case02 — proposal case 2: same task, glm provider (glm AND glm-flash
  # share its windows) exhausted at 97% weekly with a FAR reset: an eligible
  # alternative wins, no refusal loop, no forced quota bypass.
  d="${WORK}/case02"; mkdir -p "$d"
  write_yaml_skeleton "${d}/routing.yaml"
  cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: glm, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: glm-flash, provider: glm, model: glm-5.3-flash, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 2, tags: [cheap, mechanical]}
    - {arm: sonnet, provider: claude, model: sonnet, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
YAML
  scenario_header "${outdir}/case02-flash-exhausted-alternative.txt" case02-flash-exhausted-alternative \
    'proposal case 2: glm provider exhausted (97% weekly, far reset) — eligible alternative wins, no bypass'
  arb_record "${outdir}/case02-flash-exhausted-alternative.txt" a worker \
    '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"case02 same task, flash exhausted"}' \
    "${d}/routing.yaml" "{$Q_GLM_OUT,$Q_CODEX_TIRED,$Q_ANT_OK}" - "${WORK}/empty-events.jsonl"

  # ── case03 — proposal case 3: complex/high-risk heavy task with the safety
  # hard flag: a strong route can win; require_trusted keeps the unprotected
  # arm out (gate intact).
  d="${WORK}/case03"; mkdir -p "$d"
  write_yaml_skeleton "${d}/routing.yaml"
  cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: astra, provider: codex, model: gpt-6-astra, tier: astra, kinds: [code, review], sizes: [heavy], protected: true, capability: 6, tags: [adversarial, exhaustive, flagship]}
    - {arm: sol, provider: codex, model: gpt-5.6-sol, tier: top, kinds: [code, review], sizes: [heavy], protected: true, capability: 5, tags: [adversarial, exhaustive]}
    - {arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, kinds: [code], sizes: [standard, heavy], protected: true, capability: 4, tags: [review, adversarial]}
    - {arm: sonnet, provider: claude, model: sonnet, tier: standard, kinds: [code], sizes: [standard, heavy], protected: true, capability: 4}
    - {arm: glm, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard, heavy], protected: true, capability: 4}
    - {arm: scout, provider: glm, model: glm-5.3-flash, tier: standard, kinds: [code], sizes: [heavy], protected: false, capability: 2, tags: [cheap, mechanical]}
YAML
  scenario_header "${outdir}/case03-complex-risk-strong-route.txt" case03-complex-risk-strong-route \
    'proposal case 3: complex+heavy+safety — strong route wins, unprotected arm excluded untrusted'
  arb_record "${outdir}/case03-complex-risk-strong-route.txt" a worker \
    '{"kind":"code","size":"heavy","complexity":"complex","complexity_source":"judge","safety":true,"task":"case03 complex high-risk task"}' \
    "${d}/routing.yaml" "{$Q_GLM_TIRED,$Q_CODEX_OK,$Q_ANT_TIRED}" - "${WORK}/empty-events.jsonl"

  # ── case04 — proposal case 4: FIT_MODE on vs off on one fixture. On: the
  # legacy +100 is ABSENT (flash effective_cost stays 0.33-scaled). Off: the
  # retained complexity_penalty rule adds +100 — visible as flash
  # effective_cost ~100.33-scaled in the record.
  d="${WORK}/case04"; mkdir -p "$d"
  write_yaml_skeleton "${d}/routing.yaml"
  cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: glm, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: glm-flash, provider: glm, model: glm-5.3-flash, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 2, tags: [cheap, mechanical]}
    - {arm: sonnet, provider: claude, model: sonnet, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
YAML
  scenario_header "${outdir}/case04-fit-mode-on-off.txt" case04-fit-mode-on-off \
    'proposal case 4: same fixture twice — fit_mode=on (default, +100 absent) and env-off (+100 live)'
  arb_record "${outdir}/case04-fit-mode-on-off.txt" fit-on worker \
    '{"kind":"code","size":"standard","complexity":"complex","complexity_source":"judge","task":"case04 complex code"}' \
    "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_TIRED,$Q_ANT_TIRED}" - "${WORK}/empty-events.jsonl"
  arb_record "${outdir}/case04-fit-mode-on-off.txt" fit-off worker \
    '{"kind":"code","size":"standard","complexity":"complex","complexity_source":"judge","task":"case04 complex code"}' \
    "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_TIRED,$Q_ANT_TIRED}" - "${WORK}/empty-events.jsonl" \
    LEADV2_ARBITER_CAPABILITY_FIT=off

  # ── case05 — proposal case 5 + §4.4: equal ecost, different fit buckets,
  # seeded state file naming the BETTER-fit arm as last pick. Freezes what the
  # anti-stickiness rotation does today at equal effective cost.
  d="${WORK}/case05"; mkdir -p "$d"
  write_yaml_skeleton "${d}/routing.yaml"
  cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: alpha, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: beta, provider: glm, model: glm-5.3-flash, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 2}
YAML
  scenario_header "${outdir}/case05-rotation-keeps-fit.txt" case05-rotation-keeps-fit \
    'proposal case 5 / §4.4: equal ecost, buckets 0 vs 1, state file seeds the bucket-0 arm as last'
  arb_record "${outdir}/case05-rotation-keeps-fit.txt" a worker \
    '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"case05 equal-ecost rotation"}' \
    "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_TIRED,$Q_ANT_TIRED}" '{"arm":"alpha"}' "${WORK}/empty-events.jsonl"

  # ── case06 — proposal case 6: null prices stay VISIBLY unknown (median
  # fallback, cost_src names it); known cheap is labelled measured, never
  # confused with the fallback.
  d="${WORK}/case06"; mkdir -p "$d"
  write_yaml_skeleton "${d}/routing.yaml"
  cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: glm, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: glm-flash, provider: glm, model: glm-5.3-flash, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 2, tags: [cheap, mechanical]}
    - {arm: sonnet, provider: claude, model: sonnet, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
YAML
  scenario_header "${outdir}/case06-null-price-unknown.txt" case06-null-price-unknown \
    'proposal case 6: winner on a null price reads cost_src=<key>:median; winner on glm reads :measured'
  arb_record "${outdir}/case06-null-price-unknown.txt" median-fallback-wins worker \
    '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"case06 glm exhausted, unpriced arms remain"}' \
    "${d}/routing.yaml" "{$Q_GLM_OUT,$Q_CODEX_TIRED,$Q_ANT_OK}" - "${WORK}/empty-events.jsonl"
  arb_record "${outdir}/case06-null-price-unknown.txt" measured-wins worker \
    '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"case06 glm healthy, measured price decides"}' \
    "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_TIRED,$Q_ANT_TIRED}" - "${WORK}/empty-events.jsonl"

  # ── case07 — proposal case 7: observed-rounds adjustment applies exactly
  # once (ecost = base x mean rounds), only at min_rows; missing class fields
  # and malformed rows invent nothing; a sub-min_rows bucket stays matrix_only.
  d="${WORK}/case07"; mkdir -p "$d"
  write_yaml_skeleton "${d}/routing.yaml"
  cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: glm, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
YAML
  cat >"${d}/events.jsonl" <<'EOF'
{"kind":"cost_actual","task":"t1","arm":"glm","detail":"class=standard rounds=2"}
{"kind":"cost_actual","task":"t2","arm":"glm","detail":"class=standard rounds=2"}
{"kind":"cost_actual","task":"t3","arm":"glm","detail":"class=standard rounds=2"}
{"kind":"cost_actual","task":"t4","arm":"codex","detail":"class=standard rounds=1"}
{"kind":"cost_actual","task":"t5","arm":"codex","detail":"class=standard rounds=1"}
{"kind":"cost_actual","task":"t6","arm":"glm","detail":"rounds=1"}
not json at all
EOF
  scenario_header "${outdir}/case07-observed-rounds-once.txt" case07-observed-rounds-once \
    'proposal case 7: n=3 rounds history reprices glm x2.00 exactly once; codex sub-min_rows stays matrix_only'
  arb_record "${outdir}/case07-observed-rounds-once.txt" a worker \
    '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"case07 observed rounds"}' \
    "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_OK,$Q_ANT_OK}" - "${d}/events.jsonl"

  # ── case08 — proposal case 8: one provider (codex), three models across
  # tiers/capabilities; live effort rows so effort follows the task. Complex
  # work separates terra (bucket 0) from luna (bucket 1); the winner's model
  # token is the recorded identity.
  d="${WORK}/case08"; mkdir -p "$d"
  write_yaml_skeleton "${d}/routing.yaml"
  # replace the skeleton's effort_matrix with the live code rows (insert is
  # not possible mid-file, so this fixture writes its own full skeleton)
  cat >"${d}/routing.yaml" <<'YAML'
router_v2:
  quota_ceilings:
    glm:    { work_pct: 95, review_pct: 98 }
    codex:  { work_pct: 95, review_pct: 98 }
    claude: { work_pct: 95, review_pct: 95 }
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix:
    - {kinds: [code], complexity: [complex], effort: high}
    - {kinds: [code], effort: medium}
    - {default: true, effort: medium}
  observed_cost: {min_rows: 3}
  cost:
    glm-flash: 0.33
    glm: 1.0
    codex: null
    anthropic: null
    freepool: 1.0
  cost_unpriced_policy: matrix_median
  capability_fit:
    enabled: true
    prior: 3.0
    slack: 0.5
    cap_default: 3.0
    complexity_ordinal: {trivial: 1, simple: 2, standard: 3, complex: 4}
    source_confidence: {judge: 0.9, flag: 0.7, heuristic: 0.4, unknown: 0.0}
  complexity_penalty:
    - complexities: [complex]
      penalize_tags: [cheap, mechanical]
      penalty: 100
  capability_matrix:
    - {arm: codex, provider: codex, model: gpt-5.6-luna, tier: volume, kinds: [code], sizes: [standard], protected: true, capability: 3}
    - {arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, kinds: [code], sizes: [standard, heavy], protected: true, capability: 4}
    - {arm: sol, provider: codex, model: gpt-5.6-sol, tier: top, kinds: [code], sizes: [heavy], protected: true, capability: 5}
YAML
  scenario_header "${outdir}/case08-same-provider-models-effort.txt" case08-same-provider-models-effort \
    'proposal case 8: one codex provider, luna/terra/sol — fit separates models, effort follows the task'
  arb_record "${outdir}/case08-same-provider-models-effort.txt" complex-heavy worker \
    '{"kind":"code","size":"heavy","complexity":"complex","complexity_source":"judge","task":"case08 complex heavy"}' \
    "${d}/routing.yaml" "{$Q_GLM_TIRED,$Q_CODEX_OK,$Q_ANT_TIRED}" - "${WORK}/empty-events.jsonl"
  arb_record "${outdir}/case08-same-provider-models-effort.txt" simple-standard worker \
    '{"kind":"code","size":"standard","complexity":"simple","complexity_source":"judge","task":"case08 simple standard"}' \
    "${d}/routing.yaml" "{$Q_GLM_TIRED,$Q_CODEX_OK,$Q_ANT_TIRED}" - "${WORK}/empty-events.jsonl"

  # ── case09 — proposal case 9: opus identity at the arbiter seam. (a) an
  # explicit pin reaches pool_default:false opus and the line names the alias
  # model token; (b) a model no arm carries (a 4.8 request) is refused BY
  # NAME — no silent alias downgrade, and no 4.8 route exists to downgrade to.
  d="${WORK}/case09"; mkdir -p "$d"
  write_yaml_skeleton "${d}/routing.yaml"
  cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: sonnet, provider: claude, model: sonnet, tier: standard, kinds: [code, review, plan, audit], sizes: [standard], protected: true, capability: 4}
    - {arm: opus, provider: claude, model: opus, tier: high, kinds: [review, plan, audit, safety], sizes: [standard, heavy], protected: true, capability: 5, pool_default: false}
    - {arm: fable, provider: claude, model: fable, tier: high, kinds: [plan, audit, review], sizes: [standard, heavy], protected: true, capability: 6}
YAML
  scenario_header "${outdir}/case09-opus-identity.txt" case09-opus-identity \
    'proposal case 9: opus pin honoured with alias model token; unknown 4.8 model refused by name'
  arb_record "${outdir}/case09-opus-identity.txt" pin-opus worker \
    '{"kind":"review","size":"standard","complexity":"standard","complexity_source":"judge","requested_arm":"opus","task":"case09 opus pin"}' \
    "${d}/routing.yaml" "{$Q_GLM_TIRED,$Q_CODEX_TIRED,$Q_ANT_OK}" - "${WORK}/empty-events.jsonl"
  arb_record "${outdir}/case09-opus-identity.txt" request-48-refused worker \
    '{"kind":"review","size":"standard","complexity":"standard","complexity_source":"judge","requested_model":"claude-opus-4-8","task":"case09 explicit 4.8 request"}' \
    "${d}/routing.yaml" "{$Q_GLM_TIRED,$Q_CODEX_TIRED,$Q_ANT_OK}" - "${WORK}/empty-events.jsonl"

  # ── case10 — proposal case 10 (+ §2.5): Fable scoped weekly vs the general
  # seven_day window, three shapes: scoped-exhausted + general-free; scoped-free
  # + general-exhausted; scoped stale (hours_to_reset=0) — no fabricated
  # urgency/headroom. Scoped exhaustion must not block unscoped sonnet.
  d="${WORK}/case10"; mkdir -p "$d"
  write_yaml_skeleton "${d}/routing.yaml"
  cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: fable, provider: claude, model: fable, tier: high, kinds: [plan, audit, review], sizes: [standard, heavy], protected: true, capability: 6}
    - {arm: sonnet, provider: claude, model: sonnet, tier: standard, kinds: [code, review], sizes: [standard], protected: true, capability: 4}
YAML
  local q_scoped_out q_scoped_free q_scoped_stale
  q_scoped_out='"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","account_label":"max_20x","five_hour":{"pct":10,"hours_to_reset":3.0},"seven_day":{"pct":0,"hours_to_reset":120.0},"weekly_scoped":{"Fable":{"pct":98,"hours_to_reset":120.0}}}]}'
  q_scoped_free='"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","account_label":"max_20x","five_hour":{"pct":10,"hours_to_reset":3.0},"seven_day":{"pct":97,"hours_to_reset":120.0},"weekly_scoped":{"Fable":{"pct":0,"hours_to_reset":120.0}}}]}'
  q_scoped_stale='"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","account_label":"max_20x","five_hour":{"pct":10,"hours_to_reset":3.0},"seven_day":{"pct":10,"hours_to_reset":120.0},"weekly_scoped":{"Fable":{"pct":50,"hours_to_reset":0}}}]}'
  scenario_header "${outdir}/case10-fable-scoped-weekly.txt" case10-fable-scoped-weekly \
    'proposal case 10: scoped/general weekly overlap — scoped-out, scoped-free+general-out, stale scoped'
  arb_record "${outdir}/case10-fable-scoped-weekly.txt" scoped-out-general-free worker \
    '{"kind":"review","size":"standard","complexity":"standard","complexity_source":"judge","task":"case10 scoped exhausted"}' \
    "${d}/routing.yaml" "{$Q_GLM_TIRED,$Q_CODEX_TIRED,$q_scoped_out}" - "${WORK}/empty-events.jsonl"
  arb_record "${outdir}/case10-fable-scoped-weekly.txt" scoped-free-general-out worker \
    '{"kind":"review","size":"standard","complexity":"standard","complexity_source":"judge","task":"case10 general exhausted"}' \
    "${d}/routing.yaml" "{$Q_GLM_TIRED,$Q_CODEX_TIRED,$q_scoped_free}" - "${WORK}/empty-events.jsonl"
  arb_record "${outdir}/case10-fable-scoped-weekly.txt" scoped-stale worker \
    '{"kind":"review","size":"standard","complexity":"standard","complexity_source":"judge","task":"case10 stale scoped reading"}' \
    "${d}/routing.yaml" "{$Q_GLM_TIRED,$Q_CODEX_TIRED,$q_scoped_stale}" - "${WORK}/empty-events.jsonl"

  # ── case11 — proposal case 11 (the WEEKLY-ALLOCATES shape): codex has a
  # five-hour bucket about to reset AND a weekly window with less room; glm
  # has weekly room. Weekly preservation must decide; the expiring 5h bucket
  # is admission-only and must not buy preference.
  d="${WORK}/case11"; mkdir -p "$d"
  write_yaml_skeleton "${d}/routing.yaml"
  cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: glm, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
YAML
  local q11
  q11='{"glm":{"status":"ok","five_hour":{"pct":10,"hours_to_reset":4.5},"weekly":{"pct":40,"hours_to_reset":100.0}},"codex":{"status":"ok","binding_window":"weekly","windows":[{"kind":"five_hour","used_percent":15,"hours_to_reset":0.2},{"kind":"weekly","used_percent":45,"hours_to_reset":100.0}]},"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","five_hour":{"pct":10},"seven_day":{"pct":10}}]}}'
  scenario_header "${outdir}/case11-weekly-preservation.txt" case11-weekly-preservation \
    'proposal case 11: near-reset 5h bucket vs scarce weekly — weekly reserve decides'
  arb_record "${outdir}/case11-weekly-preservation.txt" a worker \
    '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","allowed_arms":["glm","codex"],"task":"case11 weekly preservation"}' \
    "${d}/routing.yaml" "$q11" - "${WORK}/empty-events.jsonl"

  # ── case12 — proposal case 12, quota half: the ACTIVE-flagged account
  # cannot answer (status unknown — the identity the session believes it is
  # using); a different ok account carries the real numbers. The decision must
  # price claude off the ok account's readings, never fabricated zeros. (The
  # profile-UUID launcher enforcement is downstream of this seam — report.md.)
  d="${WORK}/case12"; mkdir -p "$d"
  write_yaml_skeleton "${d}/routing.yaml"
  cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: glm, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: sonnet, provider: claude, model: sonnet, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
YAML
  local q12
  q12='{"glm":{"status":"ok","five_hour":{"pct":30,"hours_to_reset":3.0},"weekly":{"pct":97,"hours_to_reset":100.0}},"codex":{"status":"ok","windows":[{"kind":"weekly","used_percent":60,"hours_to_reset":100.0}]},"anthropic":{"status":"ok","accounts":[{"active":true,"status":"unknown","account_label":"profile-A-max20x","five_hour":{"pct":null},"seven_day":{"pct":null}},{"active":false,"status":"ok","account_label":"profile-B-max20x","five_hour":{"pct":20,"hours_to_reset":3.0},"seven_day":{"pct":30,"hours_to_reset":120.0}}]}}'
  scenario_header "${outdir}/case12-account-identity-mismatch.txt" case12-account-identity-mismatch \
    'proposal case 12: active-flagged account cannot answer — real numbers priced from the ok account'
  arb_record "${outdir}/case12-account-identity-mismatch.txt" a worker \
    '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"case12 account identity"}' \
    "${d}/routing.yaml" "$q12" - "${WORK}/empty-events.jsonl"

  # ── case13 — proposal case 13: direct (pinned) and fallback (auction)
  # dispatch face the same admissibility checks. (a) healthy pin honoured;
  # (b) same pin on a capped account is REFUSED (a pin never overrides the
  # budget); (c) the fallback auction on the same state picks the alternative.
  d="${WORK}/case13"; mkdir -p "$d"
  write_yaml_skeleton "${d}/routing.yaml"
  cat >>"${d}/routing.yaml" <<'YAML'
    - {arm: glm, provider: glm, model: glm-5.3, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: sonnet, provider: claude, model: sonnet, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
YAML
  scenario_header "${outdir}/case13-direct-fallback-same-checks.txt" case13-direct-fallback-same-checks \
    'proposal case 13: pin honoured when admissible, refused when capped, auction picks the alternative'
  arb_record "${outdir}/case13-direct-fallback-same-checks.txt" pin-healthy worker \
    '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","requested_arm":"sonnet","task":"case13 pin healthy"}' \
    "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_TIRED,$Q_ANT_OK}" - "${WORK}/empty-events.jsonl"
  arb_record "${outdir}/case13-direct-fallback-same-checks.txt" pin-capped worker \
    '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","requested_arm":"sonnet","task":"case13 pin capped"}' \
    "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_TIRED,$Q_ANT_OUT}" - "${WORK}/empty-events.jsonl"
  arb_record "${outdir}/case13-direct-fallback-same-checks.txt" fallback-auction worker \
    '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"case13 fallback, sonnet capped"}' \
    "${d}/routing.yaml" "{$Q_GLM_OK,$Q_CODEX_TIRED,$Q_ANT_OUT}" - "${WORK}/empty-events.jsonl"

  printf 'recorded %s scenario recordings into %s\n' "$(ls "$outdir" | wc -l | tr -d ' ')" "$outdir"
}

# pin <name> <haystack-file> <literal> — assert a literal appears in a recording.
pin() {
  if grep -qF -- "$3" "$2"; then pass "$1"; else fail "$1 (missing: $3)"; fi
}
pin_rc() { # <name> <recording> <invocation-label> <rc>
  if grep -qE "^rc=$4\$" <(sed -n "/^## invocation: $3\$/,/^## invocation/p" "$2" 2>/dev/null) 2>/dev/null; then
    pass "$1"
  else
    fail "$1 (invocation $3 did not record rc=$4)"
  fi
}

# ── baseline shape assertions: freeze the DECISION facts, not the whole line
# (byte-identity vs the committed baseline covers the rest). A policy lane
# that intentionally moves one of these updates the pin AND the baseline in
# the same commit, and its report says why. ──────────────────────────────────
assert_baseline_pins() { # <outdir>
  local o="$1"
  local f
  f="${o}/case01-flash-admitted-standard.txt"
  pin 'case01: glm wins the standard task' "$f" 'arm=glm '
  pin 'case01: flash admitted in the candidate set' "$f" '"arm": "glm-flash"'
  pin 'case01: flash lost the auction, not a refusal' "$f" '"glm-flash": "price_ratio"'
  pin 'case01: fit buckets recorded (glm 0, flash 1)' "$f" 'fit_bucket=glm:0,codex:0,sonnet:0,glm-flash:1'
  pin 'case01: decisive comparator recorded (fit overrode pure cost)' "$f" 'fit_pick=glm fit_differs=1'
  f="${o}/case02-flash-exhausted-alternative.txt"
  pin 'case02: eligible alternative wins (not a refusal)' "$f" 'arm=sonnet '
  pin 'case02: glm excluded capped' "$f" '"glm": "capped"'
  pin 'case02: glm-flash excluded capped with it' "$f" '"glm-flash": "capped"'
  f="${o}/case03-complex-risk-strong-route.txt"
  pin 'case03: strong route (astra) wins the complex task' "$f" 'arm=astra '
  pin 'case03: unprotected arm excluded untrusted (gate intact)' "$f" '"scout": "untrusted"'
  f="${o}/case04-fit-mode-on-off.txt"
  pin 'case04 fit-on: mode token on' "$f" 'fit_mode=on'
  pin 'case04 fit-on: policy token capability_fit' "$f" 'complexity_policy=capability_fit'
  if grep -q 'fit_mode=off' "$f" && grep -q 'complexity_policy=penalty' "$f"; then
    pass 'case04 fit-off: mode + legacy penalty token explicit'
  else
    fail 'case04 fit-off: fit_mode=off / complexity_policy=penalty missing'
  fi
  if python3 - "$f" <<'PY'
import json, sys
txt = open(sys.argv[1]).read()
blocks = txt.split('## invocation: ')[1:]
on = next(b for b in blocks if b.startswith('fit-on'))
off = next(b for b in blocks if b.startswith('fit-off'))
def flash_cost(b):
    rec = json.loads(b.split('--- decision-record', 1)[1].strip().splitlines()[0])
    return next(c['effective_cost'] for c in rec['candidate_set'] if c['arm'] == 'glm-flash')
c_on, c_off = flash_cost(on), flash_cost(off)
assert c_off - c_on == 100.0, (c_on, c_off)   # the +100 appears exactly in off-mode
PY
  then pass 'case04: +100 present exactly in fit-off (flash effective_cost off-on == 100)'
  else fail 'case04: legacy +100 not isolated between modes'
  fi
  f="${o}/case05-rotation-keeps-fit.txt"
  pin 'case05: both buckets recorded' "$f" 'fit_bucket=alpha:0,beta:1'
  # §4.4 fix (2026-09-16 round 1): rotation at equal ecost must keep the
  # winner's own fit bucket — alpha (bucket 0) seeded as `last` must still
  # win. Picking beta again is the §4.4 regression, no longer a finding.
  if grep -q '^arm=alpha ' "$f"; then
    pass 'case05: rotation kept the better fit (alpha)'
  elif grep -q '^arm=beta ' "$f"; then
    fail 'case05: rotation picked the WORSE-fit arm at equal ecost (§4.4 regression — round-1 fix no longer holding)'
  else
    fail 'case05: no winner line recorded'
  fi
  f="${o}/case06-null-price-unknown.txt"
  pin 'case06: median-fallback winner names its provenance' "$f" 'cost_src=anthropic:median'
  pin 'case06: measured winner names its provenance' "$f" 'cost_src=glm:measured'
  f="${o}/case07-observed-rounds-once.txt"
  pin 'case07: rounds history repriced glm, named on the line' "$f" 'cost_actuals=standard/glm:n=3,avg_rounds=2.00'
  if python3 - "$f" <<'PY'
import json, sys
txt = open(sys.argv[1]).read()
rec = json.loads(txt.split('--- decision-record', 1)[1].strip().splitlines()[0])
costs = {c['arm']: c['effective_cost'] for c in rec['candidate_set']}
assert abs(costs['glm'] - 2.0 * costs['codex']) < 1e-9, costs   # x2.00 applied exactly once
PY
  then pass 'case07: multiplier applied exactly once (glm == 2x codex)'
  else fail 'case07: observed-rounds multiplier wrong'
  fi
  f="${o}/case08-same-provider-models-effort.txt"
  pin 'case08 complex: terra model token wins' "$f" 'model=gpt-5.6-terra'
  pin 'case08 complex: effort high from the task row' "$f" 'effort=high'
  pin 'case08 simple: effort medium from the task row' "$f" 'effort=medium'
  f="${o}/case09-opus-identity.txt"
  pin 'case09: opus pin honoured with alias model token' "$f" 'arm=opus kind=review model=opus'
  pin 'case09: pin reason explicit' "$f" 'reason=explicit_requested_capable'
  pin 'case09: unknown 4.8 model refused by name' "$f" 'reason=requested_model_unknown'
  pin_rc 'case09: refusal rc=69' "$f" request-48-refused 69
  f="${o}/case10-fable-scoped-weekly.txt"
  pin 'case10 scoped-out: sonnet unaffected, wins' "$f" 'arm=sonnet '
  pin 'case10 scoped-out: fable excluded capped on its OWN window' "$f" '"fable": "capped"'
  # Founder ruling 2026-09-16 (round 2): keep BOTH windows — an exhausted
  # account weekly caps fable even with scoped headroom. Refusal here is the
  # RULE now; admission is the replace-shaped regression this pin catches.
  if grep -q '^arm=fable ' "$f"; then
    fail 'case10 scoped-free+general-out: fable admitted while the general weekly is 97% (replace-shaped regression — founder ruling 2026-09-16 keeps both windows)'
  else
    pass 'case10 scoped-free+general-out: fable refused on the general window (both windows bind)'
  fi
  # the stale check reads ONLY the scoped-stale invocation block: the other
  # invocations legitimately price claude/fable urgency, and a whole-file
  # grep would false-red on them. Re-anchored 2026-09-16 (round 2, founder
  # ruling keep-both): claude/fable urgency may now legitimately appear,
  # sourced [seven_day] — the aggregate stays readable for a scoped arm.
  # What must NEVER appear is urgency sourced from the EXPIRED scoped window
  # itself (hours_to_reset=0 contributes nothing), and the keep-both rule
  # means the live aggregate-sourced token should be present.
  local stale_block urg
  stale_block="$(sed -n '/^## invocation: scoped-stale$/,$p' "$f")"
  urg="$(printf '%s\n' "$stale_block" | sed -n 's/.*reset_urgency=\([^ ]*\).*/\1/p' | head -1)"
  if printf '%s' "$urg" | grep -q 'claude/fable:[0-9.]*\[weekly_scoped'; then
    fail 'case10 stale: fabricated urgency from an expired reading'
  elif printf '%s' "$urg" | grep -q 'claude/fable:[0-9.]*\[seven_day'; then
    pass 'case10 stale: no urgency from hours_to_reset=0; fable urgency sourced from the live aggregate [seven_day]'
  else
    fail 'case10 stale: expected fable urgency from the live [seven_day] window under keep-both (founder ruling 2026-09-16)'
  fi
  f="${o}/case11-weekly-preservation.txt"
  pin 'case11: weekly reserve decided (glm won)' "$f" 'arm=glm '
  f="${o}/case12-account-identity-mismatch.txt"
  pin 'case12: sonnet wins priced off the ok account' "$f" 'arm=sonnet '
  pin 'case12: util read from the ok account (30), not fabricated' "$f" 'util_claude=30'
  f="${o}/case13-direct-fallback-same-checks.txt"
  pin 'case13: healthy pin honoured' "$f" 'arm=sonnet kind=code model=sonnet'
  pin 'case13: capped pin refused honestly' "$f" 'reason=requested_arm_capped'
  pin_rc 'case13: pin refusal rc=70' "$f" pin-capped 70
  pin 'case13: fallback auction picked the alternative' "$f" 'arm=glm '
}

# ── modes ────────────────────────────────────────────────────────────────────
MODE=acceptance; ARG_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --record) MODE=record; ARG_DIR="${2:-}"; shift 2 ;;
    --verify) MODE=verify; ARG_DIR="${2:-}"; shift 2 ;;
    *) printf 'usage: %s [--record DIR | --verify DIR]\n' "$0" >&2; exit 64 ;;
  esac
done
if { [ "$MODE" = record ] || [ "$MODE" = verify ]; } && [ -z "$ARG_DIR" ]; then
  printf 'FATAL: --record/--verify need a directory argument\n' >&2; exit 64
fi

case "$MODE" in
  record)
    record_all "$ARG_DIR"
    printf 'RECORD: %s\n' "$ARG_DIR"
    ;;
  verify)
    record_all "${WORK}/fresh"
    if diff -r "${WORK}/fresh" "$ARG_DIR" >/dev/null 2>&1; then
      printf 'VERIFY: fresh recordings identical to %s\n' "$ARG_DIR"
    else
      printf 'VERIFY: recordings DIFFER from %s:\n' "$ARG_DIR"
      diff -r "${WORK}/fresh" "$ARG_DIR" | head -40
      exit 1
    fi
    ;;
  acceptance)
    [ -d "$BASELINE_DIR" ] || { printf 'FATAL: no committed baseline at %s — run with --record first\n' "$BASELINE_DIR" >&2; exit 2; }
    printf '== 1. record all scenarios twice ==\n'
    record_all "${WORK}/run1"
    record_all "${WORK}/run2"
    N_REC="$(ls "${WORK}/run1" | wc -l | tr -d ' ')"
    if [ "$N_REC" -eq 13 ]; then pass "scenarios recorded: ${N_REC} (proposal §6 cases 1-13; case 14 is documentation)"; else fail "expected 13 recordings, got ${N_REC}"; fi
    printf '== 2. twice-run determinism ==\n'
    if diff -r "${WORK}/run1" "${WORK}/run2" >"${WORK}/twice.diff" 2>&1; then
      pass 'twice-run diff empty (recordings deterministic)'
    else
      fail 'twice-run diff NOT empty:'
      head -40 "${WORK}/twice.diff"
    fi
    printf '== 3. baseline pins ==\n'
    assert_baseline_pins "${WORK}/run1"
    printf '== 4. committed baseline byte-identity ==\n'
    if diff -r "${WORK}/run1" "$BASELINE_DIR" >"${WORK}/base.diff" 2>&1; then
      pass "fresh recordings byte-identical to committed baseline (${BASELINE_DIR})"
    else
      fail "fresh recordings DIFFER from committed baseline (arbiter or fixtures changed — re-freeze with --record and review the diff):"
      head -40 "${WORK}/base.diff"
    fi
    printf '== 5. negative control: move it, then restore it ==\n'
    record_all "${WORK}/mut" 2
    if ! diff -q "${WORK}/mut/case01-flash-admitted-standard.txt" "$BASELINE_DIR/case01-flash-admitted-standard.txt" >/dev/null 2>&1; then
      pass 'mutation (case01 glm capability 4->2) changed the recording'
    else
      fail 'mutation produced a byte-identical recording — harness asserts a constant'
    fi
    MUT_ARM="$(grep -m1 -oE '^arm=[a-z-]+' "${WORK}/mut/case01-flash-admitted-standard.txt" || true)"
    BASE_ARM="$(grep -m1 -oE '^arm=[a-z-]+' "$BASELINE_DIR/case01-flash-admitted-standard.txt" || true)"
    if [ -n "$MUT_ARM" ] && [ "$MUT_ARM" != "$BASE_ARM" ]; then
      pass "mutation moved the decision (${BASE_ARM} -> ${MUT_ARM})"
    else
      fail "mutation did not move the winner (${BASE_ARM:-none} -> ${MUT_ARM:-none})"
    fi
    record_all "${WORK}/restore"
    if diff -q "${WORK}/restore/case01-flash-admitted-standard.txt" "$BASELINE_DIR/case01-flash-admitted-standard.txt" >/dev/null 2>&1; then
      pass 'reverting the mutation restored the baseline byte-for-byte'
    else
      fail 'reverting the mutation did NOT restore the baseline'
    fi
    ;;
esac

printf 'SUMMARY pass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
