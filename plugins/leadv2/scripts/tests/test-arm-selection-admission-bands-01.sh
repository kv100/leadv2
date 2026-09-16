#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-routing.yaml leadv2-route-arbiter
#
# ARM-SELECTION-ADMISSION-BANDS-01 (founder order 2026-09-16, proposal §4.1
# docs/reference/arm-selection-proposal-2026-09-16.md): the admission/pool
# membership half of the founder's arm-selection proposal, applied to
# plugins/leadv2/config/leadv2-routing.yaml ONLY. This suite freezes the §6
# acceptance cases this lane owns, against the REAL routing yaml and the REAL
# arbiter (lib/leadv2-route-arbiter.sh is a sibling lane's file -- read, never
# edited here). Hermetic: quota/freepool-gate/events-journal/failure-ledger/
# state are all temp-file seams; no live provider is consulted.
#
# Sibling lane note: ARM-SELECTION-DECISION-FIXTURES-01 (pre-change decision
# freezer) had NOT landed when this suite was written (checked 2026-09-16:
# zero test-arm-selection-decision-fixtures* files in tests/). This suite is
# the minimal fixture the mission authorised in that case. When that lane
# lands, the pre-change baseline in this suite's report must be reconciled
# against it.
#
# Cases (proposal §6, the rows this lane owns):
#   C1  standard concrete implementation: flash admitted, CAN win vs glm on the
#       documented cheaper credit (router_v2.cost.glm-flash 0.33 vs glm 1.0,
#       GLM-EFFICIENCY-01); fit buckets + the decisive comparator shown.
#   C1a negative control: the fit ladder did NOT flatten -- a band-2 arm
#       (haiku, capability 2) is still demoted a bucket on standard work.
#   C1b negative control: cheap credit is not cheap delivery -- with >=3
#       observed repair rounds on (standard, glm-flash), flash LOSES and the
#       decision line names the re-pricing (observed_cost, founder 2026-09-12).
#       A change that makes flash win everything is a different bug.
#   C2a flash cooling (failure_memory, 2 attributed no_work rows on this sig8):
#       an eligible alternative wins; no loop, no forced quota bypass.
#   C2b glm provider exhausted (99% >= work_pct 95): BOTH glm arms leave, an
#       eligible alternative wins, decision is a pick (not arm=refuse).
#   C3  complex + heavy + safety: freepool still stripped (untrusted stage),
#       effort still forced high (protected task row), and a suitable strong
#       route wins once the cheap provider is out. Mandatory gates intact.
#   C4a FIT_MODE=on (live default): legacy +100 is ABSENT -- flash wins a
#       complex task it would have been banned from under the penalty.
#   C4b FIT_MODE=off (env flip): the retained complexity_penalty block still
#       fires on flash's [cheap, mechanical] tags; the winner is not flash and
#       the line says complexity_policy=penalty.
#   C9  opus route resolves to the real Opus 5 id claude-opus-5 (matrix row +
#       --pin-arm decision line); no 4.8 route exists anywhere in the config.
#   R   recon eligibility (proposal §4.1): flash and luna pin-selectable on
#       kind=recon (codex's recon cell resolves gpt-5.6-luna); negative control:
#       sonnet (no recon in kinds) still refused requested_arm_incapable.
#   P   preservation: every founder-approved flash declaration (kinds/sizes/
#       review/protected/ladder when:[all]/no untrusted) is still in place;
#       luna stays 3, haiku stays 2; the opus build exclusion (no `code` kind)
#       and the dead complexity_penalty block are byte-intact.
#
# Live-identity evidence for C9 (claude CLI alias probes) is NOT hermetic and
# lives in this lane's report, not here: docs/handoff/ARM-SELECTION-
# ADMISSION-BANDS-01/report.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROUTING="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"
ARBITER="${SCRIPTS_ROOT}/lib/leadv2-route-arbiter.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/arm-admission-bands.XXXXXX")"
trap '[[ "${BANDS_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"' EXIT

bash -n "$ARBITER" || { fail "bash syntax: arbiter"; exit 1; }
pass "bash syntax: arbiter (sibling lane's file, unmodified by this lane)"

cat > "$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat > "$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"

quota() { # <glm_pct> <codex_pct> <claude_pct>
  python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok','five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
# run_case <case-tag> <quota_glm> <quota_codex> <quota_claude> <fit_mode> <descriptor-json>
# Fresh state/journal/ledger per case: anti-stickiness and failure memory must
# not leak between cases (one inode per case, one decision per case).
run_case() {
  local tag="$1" g="$2" c="$3" a="$4" fit="$5" desc="$6"
  local d="$TMP/case-$tag"
  mkdir -p "$d"; : > "$d/events.jsonl"; : > "$d/ledger.jsonl"
  # per-case journal overrides (hooks run_case_case below may pre-write rows)
  if [[ -f "$TMP/pre-$tag-events.jsonl" ]]; then cp "$TMP/pre-$tag-events.jsonl" "$d/events.jsonl"; fi
  if [[ -f "$TMP/pre-$tag-ledger.jsonl" ]]; then cp "$TMP/pre-$tag-ledger.jsonl" "$d/ledger.jsonl"; fi
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$d/state.json" \
  LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$d/events.jsonl" \
  LEADV2_ROUTE_ARBITER_FAILURE_LEDGER="$d/ledger.jsonl" \
  LEADV2_ARBITER_CAPABILITY_FIT="$fit" \
  ROUTE_TEST_QUOTA="$(quota "$g" "$c" "$a")" \
  ROUTE_TEST_FREE_RC=0 \
  bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$desc" 2>&1
}
line_arm() { printf '%s\n' "$1" | grep -o 'arm=[^ ]*' | head -1; }

# ── P: founder declarations preserved (config-level, python-pinned) ──────────
python3 - "$ROUTING" <<'PY' || fail "(P) config preservation" "python asserts below"
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
rv, rt = d['router_v2'], d['router']
rows = {(r['arm'], r.get('model')): r for r in rv['capability_matrix']}
flash = rows[('glm-flash', 'glm-5.3-flash')]
errs = []
# GLM-FLASH-DOES-ANY-WORK-01 (founder 2026-09-10) declarations, untouched:
for k, want in [('protected', True), ('review', True), ('capability', 4)]:
    if flash.get(k) != want: errs.append('flash %s=%r want %r' % (k, flash.get(k), want))
if 'code' not in flash['kinds'] or 'safety' not in flash['kinds']:
    errs.append('flash kinds lost founder-approved entries: %r' % flash['kinds'])
if flash['sizes'] != ['standard', 'heavy', 'bulk']:
    errs.append('flash sizes changed: %r' % flash['sizes'])
lad = [e for e in rt['dispatch_ladder'] if e['id'] == 'glm-flash']
if len(lad) != 1 or lad[0].get('when') != ['all'] or 'untrusted' in lad[0]:
    errs.append('flash ladder entry changed: %r' % lad)
# ARM-SELECTION-ADMISSION-BANDS-01: luna 3, haiku 2 (no promotion on this lane)
if rows[('codex', 'gpt-5.6-luna')].get('capability') != 3: errs.append('luna capability != 3')
if rows[('haiku', 'haiku')].get('capability') != 2: errs.append('haiku capability != 2')
# Opus build exclusion kept (kinds carry no code); identity resolved to Opus 5
opus = rows[('opus', 'claude-opus-5')]
if 'code' in opus['kinds']: errs.append('opus kinds gained code (build exclusion removed)')
if rows[('glm', 'glm-5.3')].get('capability') != 4: errs.append('glm capability changed')
# The legacy +100 block is retained byte-for-byte as the FIT_MODE=off path
cp = rv.get('complexity_penalty') or []
if not any(r.get('penalize_tags') == ['cheap', 'mechanical'] and r.get('penalty') == 100 for r in cp):
    errs.append('complexity_penalty block no longer carries the cheap/mechanical +100 rule')
if rv.get('capability_fit', {}).get('enabled') is not True: errs.append('capability_fit.enabled no longer true')
if rv.get('cost', {}).get('glm-flash') != 0.33: errs.append('cost.glm-flash != 0.33 (economics is a sibling lane)')
if errs:
    sys.exit('; '.join(errs))
PY
if [[ $? -eq 0 ]]; then pass "(P) flash/luna/haiku/opus declarations + dead-penalty block preserved"; fi

# ── C1: standard task, healthy quota -- flash wins on cheaper credit ────────
OUT="$(run_case c1 20 20 20 on '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"bands-c1-standard-build"}')"
printf '%s\n' "$OUT" > "$TMP/c1.log"
if printf '%s\n' "$OUT" | grep -q 'arm=glm-flash '; then
  pass "(C1) flash wins a standard concrete implementation task"
else
  fail "(C1) flash does not win the standard task" "$(line_arm "$OUT"); log: $TMP/c1.log"
fi
# fit buckets: flash and glm BOTH bucket 0 -> the comparator is ecost, not fit
# (codex/terra interleaves the token at the same bucket; assert membership)
if printf '%s\n' "$OUT" | grep -q 'fit_bucket=[^ ]*glm-flash:0' && printf '%s\n' "$OUT" | grep -q 'fit_bucket=[^ ]*glm:0'; then
  pass "(C1) fit buckets shown: glm-flash:0 and glm:0 (req_eff 3.0, band 4)"
else
  fail "(C1) fit bucket token missing/mismatched" "log: $TMP/c1.log"
fi
# decisive comparator: glm survived every gate and lost on effective cost --
# the price_ratio LOSER label (arbiter :2099-2104), never a refusal count
if printf '%s\n' "$OUT" | grep -q 'arm_excluded=[^ ]*glm:price_ratio'; then
  pass "(C1) decisive comparator on the line: glm in pool, lost on ecost (price_ratio loser label)"
else
  fail "(C1) glm price_ratio loser label missing" "log: $TMP/c1.log"
fi
if printf '%s\n' "$OUT" | grep -q 'reason=cheapest_capable'; then
  pass "(C1) reason=cheapest_capable (fit did not have to rescue the pick)"
else
  fail "(C1) reason is not cheapest_capable" "log: $TMP/c1.log"
fi

# ── C1a negative control: band-2 arm still demoted a bucket on standard ─────
OUT="$(run_case c1a 20 20 20 on '{"kind":"docs","size":"standard","complexity":"standard","complexity_source":"judge","task":"bands-c1a-docs"}')"
printf '%s\n' "$OUT" > "$TMP/c1a.log"
if printf '%s\n' "$OUT" | grep -q 'fit_bucket=[^ ]*glm-flash:0' && printf '%s\n' "$OUT" | grep -q 'fit_bucket=[^ ]*haiku:1'; then
  pass "(C1a) capability still orders arms: haiku (band 2) sits a bucket below flash (band 4) on standard"
else
  fail "(C1a) band-2 arm not demoted -- the fit ladder flattened" "log: $TMP/c1a.log"
fi
if printf '%s\n' "$OUT" | grep -q 'arm=glm-flash '; then
  pass "(C1a) winner is flash, not the demoted band-2 arms"
else
  fail "(C1a) unexpected winner" "$(line_arm "$OUT"); log: $TMP/c1a.log"
fi

# ── C1b negative control: observed repair rounds re-price flash out ─────────
# 3 cost_actual rows (>= observed_cost.min_rows 3) at rounds=4 on
# (standard, glm-flash): ecost 0.33*4=1.32 > glm 1.0 -- cheap credit is not
# cheap delivery. codex capped so the tie-break is glm vs sonnet (name order).
cat > "$TMP/pre-c1b-events.jsonl" <<'EOF'
{"kind":"cost_actual","task":"bands-c1b-t1","arm":"glm-flash","detail":"rounds=4 class=standard arm=glm-flash"}
{"kind":"cost_actual","task":"bands-c1b-t2","arm":"glm-flash","detail":"rounds=4 class=standard arm=glm-flash"}
{"kind":"cost_actual","task":"bands-c1b-t3","arm":"glm-flash","detail":"rounds=4 class=standard arm=glm-flash"}
EOF
OUT="$(run_case c1b 20 99 20 on '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"bands-c1b-rounds-x"}')"
printf '%s\n' "$OUT" > "$TMP/c1b.log"
rm -f "$TMP/pre-c1b-events.jsonl"
if printf '%s\n' "$OUT" | grep -q 'arm=glm '; then
  pass "(C1b) flash LOSES when its observed repair cost (4 rounds x 0.33) exceeds glm"
else
  fail "(C1b) rounds re-pricing did not dethrone flash" "$(line_arm "$OUT"); log: $TMP/c1b.log"
fi
if printf '%s\n' "$OUT" | grep -q 'cost_actuals=[^ ]*standard/glm-flash:n=3,avg_rounds=4.00'; then
  pass "(C1b) decision line names the re-pricing source (observed_cost, n=3 avg 4.00)"
else
  fail "(C1b) cost_actuals token missing" "log: $TMP/c1b.log"
fi
if printf '%s\n' "$OUT" | grep -q 'arm_excluded=[^ ]*glm-flash:price_ratio'; then
  pass "(C1b) flash labelled price_ratio (in pool, lost on ecost) -- not banned"
else
  fail "(C1b) flash loser-label missing" "log: $TMP/c1b.log"
fi

# ── C2a: flash cooling (failure memory, 2 attributed no_work rows) ───────────
# Ledger attribution follows the events-journal spawn timeline (arbiter
# :1418-1421): worker_spawned(glm-flash) at T, terminal no_work at T+ --
# twice, on THIS sig8 -- retires flash for this task (threshold 2).
cat > "$TMP/pre-c2a-events.jsonl" <<'EOF'
{"kind":"worker_spawned","task":"bands-c2a-sig","arm":"glm-flash","ts":"2026-09-16T01:00:00Z"}
EOF
cat > "$TMP/pre-c2a-ledger.jsonl" <<'EOF'
{"task_sig":"bands-c2a-sig","ts":"2026-09-16T01:05:00Z","terminal":"no_work","cause":"arm_produced_nothing"}
{"task_sig":"bands-c2a-sig","ts":"2026-09-16T02:05:00Z","terminal":"no_work","cause":"arm_produced_nothing"}
EOF
OUT="$(run_case c2a 20 20 20 on '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"bands-c2a-sig"}')"
printf '%s\n' "$OUT" > "$TMP/c2a.log"
rm -f "$TMP/pre-c2a-events.jsonl" "$TMP/pre-c2a-ledger.jsonl"
if printf '%s\n' "$OUT" | grep -q 'failure_memory=ok'; then
  pass "(C2a) failure memory read the cooling rows (failure_memory=ok)"
else
  fail "(C2a) failure_memory token not ok" "log: $TMP/c2a.log"
fi
if printf '%s\n' "$OUT" | grep -q 'arm_excluded=[^ ]*glm-flash:failure_memory'; then
  pass "(C2a) flash dropped by failure_memory (cooling), named on the line"
else
  fail "(C2a) flash not dropped by failure_memory" "log: $TMP/c2a.log"
fi
if printf '%s\n' "$OUT" | grep -q '^arm=refuse'; then
  fail "(C2a) refused instead of picking an eligible alternative" "log: $TMP/c2a.log"
elif printf '%s\n' "$OUT" | grep -q 'arm=glm-flash '; then
  fail "(C2a) cooling flash still won" "log: $TMP/c2a.log"
else
  pass "(C2a) eligible alternative won ($(line_arm "$OUT")) -- one decision, no loop, no quota bypass"
fi

# ── C2b: glm provider exhausted (99 >= work_pct 95) -- both glm arms out ────
OUT="$(run_case c2b 99 20 20 on '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"bands-c2b-sig"}')"
printf '%s\n' "$OUT" > "$TMP/c2b.log"
if printf '%s\n' "$OUT" | grep -q 'arm_excluded=[^ ]*glm:capped' && printf '%s\n' "$OUT" | grep -q 'arm_excluded=[^ ]*glm-flash:capped'; then
  pass "(C2b) glm provider over ceiling: glm AND glm-flash both dropped as capped"
else
  fail "(C2b) capped exclusion missing for the glm arms" "log: $TMP/c2b.log"
fi
if printf '%s\n' "$OUT" | grep -q '^arm=refuse'; then
  fail "(C2b) refused (all_arms_capped?) with healthy codex/claude available" "log: $TMP/c2b.log"
elif printf '%s\n' "$OUT" | grep -qE '^arm=(glm|glm-flash) '; then
  fail "(C2b) an exhausted-provider arm still won" "log: $TMP/c2b.log"
else
  pass "(C2b) eligible alternative won ($(line_arm "$OUT")) reason=$(printf '%s\n' "$OUT" | grep -o 'reason=[^ ]*' | head -1))"
fi

# ── C3: complex + safety, cheap provider out -- strong route wins ───────────
# size=standard on purpose: at size=heavy freepool is size-excluded (filter 2)
# BEFORE the untrusted stage can fire, so the trust gate would be untestable;
# at standard freepool IS pool-eligible and require_trusted must strip it.
OUT="$(run_case c3 99 20 20 on '{"kind":"code","size":"standard","complexity":"complex","complexity_source":"judge","safety":true,"task":"bands-c3-sig"}')"
printf '%s\n' "$OUT" > "$TMP/c3.log"
if printf '%s\n' "$OUT" | grep -q 'arm_excluded=[^ ]*freepool:untrusted'; then
  pass "(C3) freepool still stripped on a safety path (untrusted stage intact)"
else
  fail "(C3) freepool untrusted strip missing" "log: $TMP/c3.log"
fi
if printf '%s\n' "$OUT" | grep -q 'effort=high'; then
  pass "(C3) protected/safety task still forces effort=high (effort_matrix row intact)"
else
  fail "(C3) effort not forced high" "log: $TMP/c3.log"
fi
if printf '%s\n' "$OUT" | grep -q '^arm=refuse'; then
  fail "(C3) refused with strong routes available" "log: $TMP/c3.log"
elif printf '%s\n' "$OUT" | grep -q 'req_eff=4.0'; then
  pass "(C3) complex requirement req_eff=4.0 on the line"
else
  fail "(C3) req_eff token unexpected" "log: $TMP/c3.log"
fi
# a suitable strong route = a capability>=4 protected arm (codex/terra|sol,
# astra, sonnet). Under band 4 the cheap provider would have won this build;
# with it capped the strong tier takes over -- that is the intended shape.
if printf '%s\n' "$OUT" | grep -qE '^arm=(codex|astra|sol|sonnet) '; then
  pass "(C3) a suitable strong route ($(line_arm "$OUT") $(printf '%s\n' "$OUT" | grep -o 'model=[^ ]*' | head -1)) wins the complex high-risk build"
else
  fail "(C3) winner is not a strong route" "$(line_arm "$OUT"); log: $TMP/c3.log"
fi

# ── C4a: FIT_MODE=on -- legacy +100 absent, flash wins complex ──────────────
OUT="$(run_case c4a 20 20 20 on '{"kind":"code","size":"standard","complexity":"complex","complexity_source":"judge","task":"bands-c4a-sig"}')"
printf '%s\n' "$OUT" > "$TMP/c4a.log"
if printf '%s\n' "$OUT" | grep -q 'arm=glm-flash ' && printf '%s\n' "$OUT" | grep -q 'complexity_policy=capability_fit' && printf '%s\n' "$OUT" | grep -q 'fit_mode=on'; then
  pass "(C4a) FIT_MODE=on: no +100 in the decision -- flash wins complex at fit_bucket 0 (winning bucket: $(printf '%s\n' "$OUT" | grep -o 'fit_bucket=glm-flash:[0-9]*' | head -1))"
else
  fail "(C4a) fit-on complex decision unexpected" "$(line_arm "$OUT"); log: $TMP/c4a.log"
fi

# ── C4b: FIT_MODE=off -- the retained penalty block still fires ─────────────
OUT="$(run_case c4b 20 20 20 off '{"kind":"code","size":"standard","complexity":"complex","complexity_source":"judge","task":"bands-c4b-sig"}')"
printf '%s\n' "$OUT" > "$TMP/c4b.log"
if printf '%s\n' "$OUT" | grep -q 'arm=glm-flash '; then
  fail "(C4b) FIT_MODE=off still lets flash win complex -- +100 rule dead in BOTH modes" "log: $TMP/c4b.log"
elif printf '%s\n' "$OUT" | grep -q 'complexity_policy=penalty'; then
  pass "(C4b) FIT_MODE=off: +100 fires on [cheap, mechanical]; winner $(line_arm "$OUT") -- off-mode behaviour explicit"
else
  fail "(C4b) off-mode penalty token missing" "$(line_arm "$OUT"); log: $TMP/c4b.log"
fi

# ── C9: opus resolves to the real Opus 5; no 4.8 route exists ───────────────
if grep -q 'arm: opus, provider: claude, model: claude-opus-5,' "$ROUTING"; then
  pass "(C9) opus matrix row pronounces the versioned id claude-opus-5"
else
  fail "(C9) opus matrix row does not carry model: claude-opus-5"
fi
# NOTE: grep for a MODEL FIELD carrying 4.8, not the bare number -- this
# suite's own config comment says "No opus-4.8 route exists" and a bare-text
# grep would match its own documentation (caught red on the first run).
if grep -qE 'model: [^ ]*(4\.8|4-8)' "$ROUTING"; then
  fail "(C9) a versioned 4.8 model route exists in the config without a recorded exception"
else
  pass "(C9) zero opus-4/4.8 model routes in the config -- nothing to record an exception for"
fi
OUT="$(run_case c9 20 20 20 on '{"kind":"review","size":"standard","complexity":"standard","complexity_source":"judge","requested_arm":"opus","task":"bands-c9-sig"}')"
printf '%s\n' "$OUT" > "$TMP/c9.log"
# decision-line shape is `arm=opus kind=review model=claude-opus-5 ...` -- the
# kind token sits between, so assert the two tokens independently
if printf '%s\n' "$OUT" | grep -q 'arm=opus ' && printf '%s\n' "$OUT" | grep -q 'model=claude-opus-5 '; then
  pass "(C9) --pin-arm opus decision line carries model=claude-opus-5 (the spawn string, dispatch-code _MS_MODEL)"
else
  fail "(C9) pinned opus did not resolve to claude-opus-5" "$(line_arm "$OUT"); log: $TMP/c9.log"
fi

# ── R: recon eligibility for flash and luna (proposal §4.1) ──────────────────
# Membership facts only (pin + negative control), not the auction winner: the
# default-auction winner depends on freepool gate health and quota stubs, but
# the ELIGIBILITY the lane granted must hold regardless.
OUT="$(run_case r 20 20 20 on '{"kind":"recon","size":"standard","complexity":"standard","complexity_source":"judge","requested_arm":"glm-flash","task":"bands-r-flash"}')"
printf '%s\n' "$OUT" > "$TMP/r-flash.log"
if printf '%s\n' "$OUT" | grep -q 'arm=glm-flash ' && printf '%s\n' "$OUT" | grep -q 'reason=explicit_requested_capable'; then
  pass "(R) flash is pin-selectable on kind=recon (was freepool/haiku-only before this lane)"
else
  fail "(R) flash not recon-eligible" "$(line_arm "$OUT"); log: $TMP/r-flash.log"
fi
OUT="$(run_case r2 20 20 20 on '{"kind":"recon","size":"standard","complexity":"standard","complexity_source":"judge","requested_arm":"codex","task":"bands-r-luna"}')"
printf '%s\n' "$OUT" > "$TMP/r-luna.log"
# the codex arm's recon cell is the LUNA row (terra/sol carry no recon)
if printf '%s\n' "$OUT" | grep -q 'arm=codex ' && printf '%s\n' "$OUT" | grep -q 'model=gpt-5.6-luna '; then
  pass "(R) luna is the codex recon cell (pin codex on recon resolves gpt-5.6-luna)"
else
  fail "(R) codex recon pin did not resolve luna" "$(line_arm "$OUT"); log: $TMP/r-luna.log"
fi
OUT="$(run_case r3 20 20 20 on '{"kind":"recon","size":"standard","complexity":"standard","complexity_source":"judge","requested_arm":"sonnet","task":"bands-r-neg"}')"
printf '%s\n' "$OUT" > "$TMP/r-neg.log"
if printf '%s\n' "$OUT" | grep -q 'reason=requested_arm_incapable'; then
  pass "(R) negative control: sonnet (no recon in kinds) still refused on recon -- kinds still gate"
else
  fail "(R) recon membership leaked past kinds" "$(line_arm "$OUT"); log: $TMP/r-neg.log"
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
