#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTER="${ROOT}/scripts/leadv2-router-v2.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/router-v2-headroom.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT

# Keep the L3 arm registry aligned with this two-arm fixture.  The production
# registry uses claude-sonnet, while the quota-gate reroute's documented chain
# uses sonnet, so relying on production routing.yaml would test neither path.
printf '%s\n' '{"router_v2":{"arms":[{"id":"codex","bucket":"codex","reserve_threshold":0},{"id":"sonnet","bucket":"anthropic","reserve_threshold":0}]}}' > "${tmp}/routing.json"
printf '%s\n' '{"eligible":["codex","sonnet"],"filtered":[]}' > "${tmp}/l1.json"
printf '%s\n' '{"work_kind":"build","duration_class":"long","complexity":"medium","estimate_id":"test"}' > "${tmp}/estimate.json"
printf '%s\n' '{"codex":1.0,"sonnet":1.0}' > "${tmp}/samples.json"
printf '%s\n' '[{"min_usable_now":8,"weight":1.0},{"min_usable_now":2,"weight":0.7},{"min_usable_now":0,"weight":0.4},{"min_usable_now":null,"weight":0.2}]' > "${tmp}/weights.json"

quota() { # codex usable, anthropic usable or null
  printf '{"codex":{"status":"ok","provider":"codex","binding_window":"five_hour","windows":[{"kind":"five_hour","usable_now":%s}]},"anthropic":{"status":"ok","provider":"anthropic","accounts":[{"active":true,"status":"ok","binding_window":"five_hour","five_hour":{"usable_now":%s}}]}}\n' "$1" "$2" > "${tmp}/quota.json"
}
resolve() {
  bash "${ROUTER}" resolve --routing-yaml "${tmp}/routing.json" \
    --l1-json "${tmp}/l1.json" --estimate-json "${tmp}/estimate.json" \
    --samples-json "${tmp}/samples.json" --headroom-weights-json "${tmp}/weights.json" \
    --quota-json "${tmp}/quota.json"
}

quota 3 18
out="$(resolve)"
grep -qx 'winner=sonnet' <<<"${out}"
grep -qx 'eligible=codex,sonnet' <<<"${out}"
grep -qx 'ordered=sonnet,codex' <<<"${out}"

quota 18 3
out="$(resolve)"
grep -qx 'winner=codex' <<<"${out}"
grep -qx 'ordered=codex,sonnet' <<<"${out}"

quota 18 null
out="$(resolve)"
grep -qx 'winner=codex' <<<"${out}"
grep -qx 'ordered=codex,sonnet' <<<"${out}"

quota 18 18
out="$(resolve)"
grep -qx 'winner=codex' <<<"${out}"
grep -qx 'ordered=codex,sonnet' <<<"${out}"
[[ "$(sed -n 's/^winner=//p' <<<"${out}")" == "$(sed -n 's/^ordered=\([^,]*\).*/\1/p' <<<"${out}")" ]]

# The quota-gate reroute uses the ordinary --chain resolve path, not L3.
# Feed that path a stubbed quota-live fixture: when Codex has more actual
# usable_now than Anthropic it must win even though the input chain is static.
cat > "${tmp}/quota-live-fixture.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"codex":{"status":"ok","provider":"codex","binding_window":"five_hour","credits":{"has_credits":false,"balance":0},"windows":[{"kind":"five_hour","usable_now":18}]},"anthropic":{"status":"ok","provider":"anthropic","accounts":[{"active":true,"status":"ok","binding_window":"five_hour","five_hour":{"usable_now":3}}]}}'
EOF
chmod +x "${tmp}/quota-live-fixture.sh"
out="$(LEADV2_QUOTA_LIVE="${tmp}/quota-live-fixture.sh" bash "${ROUTER}" resolve --chain codex,sonnet)"
grep -qx 'winner=codex' <<<"${out}"
grep -qx 'eligible=codex,sonnet' <<<"${out}"
grep -qx 'ordered=codex,sonnet' <<<"${out}"
grep -qx 'vector=.*"arm": "codex".*"score": 18.*' <<<"${out}"

printf 'PASS test-router-v2-headroom-order\n'
