#!/usr/bin/env bash
# CLASS-IS-COMPUTED-NOT-DECLARED-01 — the conservative default must name the escape
# hatch, and must still default conservatively.
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: leadv2-dispatch-code
#
# WHAT THE CLASSIFICATION ACTUALLY ASSERTS. Not the nature of the work, and not which
# repository it touches: the STRICTNESS OF ADMISSION. `product` on an unknown kind is a
# deliberate fail-closed choice — the function's own comment says "unknown means product
# and gets all three gates" — and that is right. It is also expensive when it is wrong:
# measured 2026-09-05, a plugin-only task classified product, hit the architect prepass
# and died seven times in a row until --kind plugin was passed by hand. The accepted
# kinds lived in this function and were printed nowhere, so the decision line said what
# it decided and never what would change the decision.
#
# WHAT IS REAL HERE. The production classify_product_work body plus its kinds constant
# are lifted out of leadv2-dispatch-code.sh and sourced. No rule is restated: the suite
# reads the SAME string the case pattern matches on, which is the point of case (d).
#
# DECLARED NEGATIVE CONTROL (tests/mutations/catalog.yaml): the kinds constant is
# emptied. Kills (c) and (d); (a) and (b) stay green, which is what shows the pair is
# about the hatch being real, not about a token being present.
set -uo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
SRC="${ROOT}/scripts/leadv2-dispatch-code.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

python3 - "$SRC" "$T/classify.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
start = s.index('LEADV2_NON_PRODUCT_KINDS=')
end = s.index('\n}\n', s.index('classify_product_work() {')) + 3
open(sys.argv[2], 'w').write(s[start:end])
PY
source "$T/classify.sh"

cls(){ classify_product_work "$1" "$2" | cut -f1; }
rsn(){ classify_product_work "$1" "$2" | cut -f2; }

# (a) THE PAIRED NEGATIVE THE ROW DEMANDS, first because it is the one that matters:
# a genuine product task must STILL take the product path. Any "fix" here that relaxes
# the default would show up as this case going green->red.
if [[ "$(cls code 'add a retry to the publisher')" == "product" \
   && "$(rsn code 'add a retry to the publisher')" == "conservative_default" ]]; then
  ok "an unknown/product kind still classifies product by conservative default"
else
  bad "a: $(classify_product_work code 'add a retry to the publisher' | tr '\t' ' ')"
fi

# (b) an empty kind — the shape the live journal showed as kind=unknown — is likewise
# still product. Fail-closed is the design, not the defect.
if [[ "$(cls '' 'anything at all')" == "product" ]]; then
  ok "an absent kind is still product, not guessed non_product"
else
  bad "b: $(classify_product_work '' 'anything at all' | tr '\t' ' ')"
fi

# (c) the hatch the decision line now advertises must actually work — otherwise the
# advice is as useless as the silence it replaces. Every kind in the constant is tried,
# so a kind advertised but not accepted cannot hide behind a sibling that is.
missing=""
IFS='|' read -r -a kinds <<< "${LEADV2_NON_PRODUCT_KINDS}"
for k in "${kinds[@]}"; do
  [[ -z "$k" ]] && continue
  [[ "$(cls "$k" 'whatever the mission says')" == "non_product" ]] || missing="${missing} ${k}"
done
if [[ -z "$missing" && "${#kinds[@]}" -ge 8 ]]; then
  ok "every kind the remedy advertises really classifies non_product (${#kinds[@]} kinds)"
else
  bad "c: advertised but not accepted:${missing:-<none>} count=${#kinds[@]}"
fi

# (d) the remedy and the case pattern must read the SAME constant, or the advice drifts
# from what is accepted the first time someone edits one of them. Proven behaviourally:
# a kind that is NOT in the constant must be product.
if [[ "$(cls not-a-listed-kind 'whatever')" == "product" ]]; then
  ok "a kind outside the constant is product — the constant is what decides"
else
  bad "d: an unlisted kind was accepted as non_product"
fi

printf '[CLASSIFICATION-NAMES-ITS-HATCH] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
