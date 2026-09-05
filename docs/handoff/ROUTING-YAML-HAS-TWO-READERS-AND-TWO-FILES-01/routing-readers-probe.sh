#!/usr/bin/env bash
# Every extraction shape any reader of leadv2-routing.yaml uses, run against all
# three files. Output is compared before/after the comment block is prepended:
# identical output == the block is genuinely additive.
set -uo pipefail
LIB=~/Projects/leadv2/plugins/leadv2/scripts/lib/leadv2-review-signals.sh
for F in ~/Projects/leadv2/plugins/leadv2/config/leadv2-routing.yaml \
         ~/Projects/leadv2/.claude/ref/leadv2-routing.yaml \
         ~/Projects/persona-engine/.claude/ref/leadv2-routing.yaml; do
  printf '### %s\n' "${F/#$HOME/~}"

  # 1. yaml.safe_load shape (router-v2 filter, resolve-L3, glm-policy-resolve,
  #    dispatch-code ladder, arbiter's own matrix read)
  python3 -c '
import sys, yaml, json
c = yaml.safe_load(open(sys.argv[1])) or {}
rv2 = c.get("router_v2") or {}
r   = c.get("router") or {}
print("  arms=%d ladder=%d cap_matrix=%d active_account=%s" % (
    len(rv2.get("arms") or []), len(r.get("dispatch_ladder") or []),
    len(rv2.get("capability_matrix") or {}), rv2.get("active_account")))
print("  glm_policy_present=%s phases=%d stop_rules=%s downgrade_chain=%s floor_rules=%s" % (
    bool((c.get("phases") or {}).get("glm_policy") or c.get("glm_policy")),
    len(c.get("phases") or {}), bool(c.get("stop_rules")),
    bool(c.get("downgrade_chain")), bool(c.get("floor_rules"))))
print("  sha_of_parsed=%s" % __import__("hashlib").sha256(
    json.dumps(c, sort_keys=True, default=str).encode()).hexdigest()[:16])
' "$F" 2>&1 | sed 's/^/ /'

  # 2. quota-read.py's line scanner for router_v2.active_account
  python3 -c '
import sys
in_rv2 = False
for raw in open(sys.argv[1]):
    if raw.strip() == "router_v2:":
        in_rv2 = True; continue
    if in_rv2:
        if raw and not raw[0].isspace() and raw.strip() and not raw.lstrip().startswith("#"):
            break
        if raw.strip().startswith("active_account:"):
            print("  quota-read scan ->", raw.strip().split(":",1)[1].strip().strip("\x27\"")); break
else:
    print("  quota-read scan -> (none)")
' "$F" 2>&1 | sed 's/^/ /'

  # 3. codex-task.sh's regex fallback for the quota thresholds
  python3 -c '
import sys, re
txt = open(sys.argv[1]).read()
for k in ("build_threshold_pct", "review_threshold_pct"):
    m = re.search(r"^\s*%s:\s*(\d+)" % k, txt, re.M)
    print("  codex-task regex %s -> %s" % (k, m.group(1) if m else "(none)"))
' "$F" 2>&1 | sed 's/^/ /'

  # 4. review-signals.sh's regex extractor for the protected patterns
  # shellcheck source=/dev/null
  ( source "$LIB" >/dev/null 2>&1
    printf '  review-signals patterns -> %s\n' \
      "$(_leadv2_review_signals_extract "$F" | tr '\n' ' ')" )
done
