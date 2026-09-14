#!/usr/bin/env bash
# GLM-MAY-REVIEW-AND-ITS-CEILING-IS-95-NOT-80-01 regression proof.
# run-all-triggers: leadv2-glm-policy-resolve.py leadv2-route-arbiter leadv2-routing.yaml
#
# Hermetic, foreground proof for the founder's two independent rules:
# ordinary glm may review a different arm's diff, but never its own; glm-flash
# and freepool are permanent review exclusions; and the arbiter admits glm from
# 80 through 94 but caps it at 95.  Quota is a fixture emitted by live.sh, never
# a provider/network call.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "${HERE}/.." && pwd)"
PLUGIN="$(cd "${SCRIPTS}/.." && pwd)"
RESOLVER="${SCRIPTS}/lib/leadv2-glm-policy-resolve.py"
ARBITER="${SCRIPTS}/lib/leadv2-route-arbiter.sh"
ROUTING="${PLUGIN}/config/leadv2-routing.yaml"

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s -- %s\n' "$1" "${2:-}"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/glm-review-95.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT INT TERM

if python3 -m py_compile "${RESOLVER}"; then pass "py_compile resolver"; else fail "py_compile resolver"; fi
if bash -n "${ARBITER}"; then pass "bash -n arbiter"; else fail "bash -n arbiter"; fi
if ! grep -q 'DEFAULT_.*THRESHOLD_PCT' "${ARBITER}"; then
  pass "arbiter reads routing.yaml ceilings, not resolver DEFAULT_* fallbacks"
else
  fail "arbiter must not import resolver DEFAULT_* fallbacks"
fi

# Configure an order that deliberately puts the permanently banned arms before
# codex.  This proves the resolver enforces the exclusions rather than merely
# relying on their absence from the shipped default order.
pool_probe() { # <author>
  python3 - "${RESOLVER}" "$1" <<'PY'
import importlib.util, sys
path, author = sys.argv[1:]
spec = importlib.util.spec_from_file_location("resolver", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
policy = {"codex_quota_gate": {
    "review_arm_order": ["glm", "glm-flash", "freepool", "codex"],
    "review_arm_exclusions": list(mod.DEFAULT_REVIEW_EXCLUSIONS),
    "glm_review_threshold_pct": 98.0,
    "review_threshold_pct": 98.0,
}}
providers = {"glm": "glm", "glm-flash": "glm", "freepool": "freepool", "codex": "codex"}
r = mod.resolve_review_pool(policy, author, pcts={"glm": 85.0, "codex": 10.0},
                            kimi_bin="/bin/false", ladder_providers=providers)
print("reviewer=" + r["reviewer"])
print("pool=" + ",".join(r["pool"]))
print("refusal=" + r["refusal"])
PY
}

foreign_out="$(pool_probe codex)"
if grep -qx 'reviewer=glm' <<<"${foreign_out}" \
   && grep -q 'glm:ok:85' <<<"${foreign_out}" \
   && grep -q 'glm-flash:excluded:review_arm_exclusion' <<<"${foreign_out}" \
   && grep -q 'freepool:excluded:review_arm_exclusion' <<<"${foreign_out}"; then
  pass "foreign author resolves glm; flash/freepool name their exclusions — ${foreign_out//$'\n'/ }"
else
  fail "foreign author should select ordinary glm" "${foreign_out//$'\n'/ }"
fi

self_out="$(pool_probe glm)"
if ! grep -qx 'reviewer=glm' <<<"${self_out}" \
   && grep -q 'glm:author:' <<<"${self_out}" \
   && grep -qx 'reviewer=codex' <<<"${self_out}"; then
  pass "self-review refused by name (glm:author), codex selected — ${self_out//$'\n'/ }"
else
  fail "self author must not select glm" "${self_out//$'\n'/ }"
fi

cat > "${TMP}/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat > "${TMP}/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${TMP}/live.sh" "${TMP}/free.sh"

quota() { # <glm pct>
  python3 - "$1" <<'PY'
import json, sys
g = int(sys.argv[1])
print(json.dumps({
  "glm": {"status":"ok", "five_hour":{"pct":g}, "weekly":{"pct":g}},
  "codex": {"status":"ok", "binding_window":"primary", "windows":[{"kind":"primary","used_percent":20}]},
  "anthropic": {"status":"ok", "accounts":[{"active":True,"five_hour_pct":20,"seven_day_pct":20}]},
}))
PY
}

arbiter_probe() { # <glm pct>
  rm -f "${TMP}/state"
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="${ROUTING}" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="${TMP}/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="${TMP}/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="${TMP}/state" \
  LEADV2_ARBITER_SPEND_FORECAST=0 \
  ROUTE_TEST_QUOTA="$(quota "$1")" \
  bash -c 'source "$0"; route_arbiter worker "$1"' "${ARBITER}" \
    '{"kind":"code","size":"standard","requested_arm":"glm"}'
}

for pct in 80 94; do
  arb_out="$(arbiter_probe "${pct}")"
  if [[ "${arb_out}" == *'arm=glm '* && "${arb_out}" == *"util_glm=${pct}"* ]]; then
    pass "worker util=${pct} admits glm — ${arb_out}"
  else
    fail "worker util=${pct} must admit glm" "${arb_out}"
  fi
done

cap_out="$(arbiter_probe 95)"
if [[ "${cap_out}" == *'arm=refuse '* && "${cap_out}" == *'requested_arm_capped'* \
      && "${cap_out}" == *'glm:capped'* && "${cap_out}" == *'util_glm=95'* ]]; then
  pass "worker util=95 caps glm — ${cap_out}"
else
  fail "worker util=95 must cap glm" "${cap_out}"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
