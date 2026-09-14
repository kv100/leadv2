#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01):
# run-all-triggers: leadv2-glm-policy-resolve.py leadv2-review-run.sh
#
# STRONGER-REVIEWER-01 (founder amendment, DO-THE-PHASES-AND-THE-CROSS-VENDOR-
# REVIEW-ACTUALLY-RUN-01, 2026-09-14): "same vendor is acceptable when the
# reviewer is a STRICTLY STRONGER model" -- not "never same vendor". Measured
# violations on 2026-09-14 (28-line review_gate sample carrying both author=
# and reviewer=): sonnet->fable x2, fable->opus x1, all same-vendor
# (anthropic) and all treated as capability-equal (sonnet/opus/fable all sit
# at capability: 4 in leadv2-routing.yaml's capability_matrix -- the field
# cannot express an ordering within that tie).
#
# This suite is the negative control the mission's "Method" section demands:
# force a same-vendor pairing and show the gate excluding it BY NAME (never a
# silent skip folded into a quota disposition), then a cross-vendor pairing
# passing untouched. Unit-level (imports the python module directly) so it
# stays fast and fully deterministic -- no dispatch pipeline, no live quota
# reads, no lockout files on disk.
#
# Ordering source, reused (never invented): leadv2-routing.yaml's
# dispatch_ladder `review_rank` (haiku=1 < sonnet=2 < opus=3 < fable=4) is the
# ONLY existing total order over the Anthropic arms -- it already resolves
# the exact tie the founder's three violations fell into. Codex vendor uses
# ~/.codex/models_cache.json `priority` (lower = stronger; probed 2026-09-14:
# astra=1, sol=4, terra=7, luna=8).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../lib/leadv2-glm-policy-resolve.py"

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '[TEST] FAIL: %s -- %s\n' "$1" "$2"; }

[[ -f "${LIB}" ]] || { printf '[TEST] FAIL: setup -- %s missing\n' "${LIB}"; exit 1; }

_probe() { # <author> <candidate> -> "True"/"False"
  python3 - "${LIB}" "$1" "$2" <<'PY'
import sys, importlib.util
lib_path, author, candidate = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("glm_policy_resolve", lib_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
ladder_providers = {
    "glm": "glm", "glm-flash": "glm", "kimi": "kimi", "codex": "codex",
    "sonnet": "anthropic", "freepool": "freepool", "haiku": "anthropic",
    "opus": "anthropic", "fable": "anthropic",
}
print(mod._same_vendor_not_stronger(author, candidate, ladder_providers))
PY
}

# ── Negative control, direction 1: same vendor, NOT stronger -> excluded ──
# The three real violations, re-checked against the review_rank ladder:
r1="$(_probe fable opus)"      # fable(4) authored, opus(3) reviewing: weaker
[[ "${r1}" == "True" ]] && pass "fable->opus: same vendor, opus weaker -> excluded (matches the one violation review_rank does NOT rescue)" \
  || fail "fable->opus should be excluded" "${r1}"

r2="$(_probe opus opus)"       # degenerate: candidate == author is a different
                                 # guard (arm==author) upstream, but the tie
                                 # itself (equal rank) must not read as "stronger"
[[ "${r2}" == "True" ]] && pass "opus->opus: equal rank never reads as stronger" \
  || fail "opus->opus (equal rank) should not be treated as stronger" "${r2}"

# ── Negative control, direction 2: same vendor, IS stronger -> allowed ──
# sonnet->fable and sonnet->opus were flagged as capability-tied violations;
# review_rank (an existing ordering, reused here, not invented) resolves both
# as the reviewer being genuinely stronger, so the amendment allows them.
r3="$(_probe sonnet fable)"
[[ "${r3}" == "False" ]] && pass "sonnet->fable: same vendor, fable stronger (rank4>2) -> allowed" \
  || fail "sonnet->fable should be allowed under the amendment" "${r3}"

r4="$(_probe sonnet opus)"
[[ "${r4}" == "False" ]] && pass "sonnet->opus: same vendor, opus stronger (rank3>2) -> allowed" \
  || fail "sonnet->opus should be allowed under the amendment" "${r4}"

r5="$(_probe haiku sonnet)"
[[ "${r5}" == "False" ]] && pass "haiku->sonnet: same vendor, sonnet stronger -> allowed" \
  || fail "haiku->sonnet should be allowed" "${r5}"

# ── Cross-vendor is always allowed, regardless of rank ──
r6="$(_probe sonnet glm)"
[[ "${r6}" == "False" ]] && pass "sonnet->glm: different vendor -> never excluded by this rule" \
  || fail "sonnet->glm (cross-vendor) should never be excluded" "${r6}"

r7="$(_probe fable codex)"
[[ "${r7}" == "False" ]] && pass "fable->codex: different vendor -> never excluded by this rule" \
  || fail "fable->codex (cross-vendor) should never be excluded" "${r7}"

# ── Codex vendor: astra/sol are orderable (models_cache priority); "codex"
#    the arm name is NOT (it resolves to terra or luna at dispatch time, which
#    this resolver cannot see) -- unresolvable must default to excluded, the
#    safe direction, never an implicit pass. ──
r8="$(_probe sol astra)"
[[ "${r8}" == "False" ]] && pass "sol->astra: same vendor, astra stronger (priority 1 beats 4) -> allowed" \
  || fail "sol->astra should be allowed" "${r8}"

r9="$(_probe astra sol)"
[[ "${r9}" == "True" ]] && pass "astra->sol: same vendor, sol weaker -> excluded" \
  || fail "astra->sol should be excluded" "${r9}"

r10="$(_probe sol codex)"
[[ "${r10}" == "True" ]] && pass "sol->codex: same vendor, 'codex' strength unresolvable -> excluded (safe default, never an implicit pass)" \
  || fail "sol->codex (unresolvable strength) should default to excluded" "${r10}"

# ── End-to-end: the pool loop names the exclusion, never folds it into a ──
# ── quota disposition (round-1 review checks for exactly this shape).    ──
pool_line="$(LEADV2_QUOTA_LOCKOUT_DIR="/nonexistent-$$" python3 "${LIB}" \
  --routing-yaml "${SCRIPT_DIR}/../../config/leadv2-routing.yaml" \
  --review-pool --author fable --quota-live /bin/true --kimi-bin /bin/false --job review 2>&1 \
  | sed -n 's/^pool=//p')"
if printf '%s' "${pool_line}" | grep -q 'opus:excluded:same_vendor_not_stronger'; then
  pass "pool entry names the exclusion: opus:excluded:same_vendor_not_stronger (author=fable)"
else
  fail "pool line missing the named exclusion" "${pool_line}"
fi

printf '\n================================================\n'
printf '  stronger-reviewer vendor gate: PASS=%s FAIL=%s\n' "${PASS}" "${FAIL}"
printf '================================================\n'
[[ "${FAIL}" -eq 0 ]] && exit 0 || exit 1
