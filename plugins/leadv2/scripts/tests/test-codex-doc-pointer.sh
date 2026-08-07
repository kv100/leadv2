#!/usr/bin/env bash
# test-codex-doc-pointer.sh — RETIRE-CODEX-BUNDLE-01 / ONE-PATH-EVERYWHERE-01 retarget
# (dispatch-4fb7381a, per dispatch-75d151fe-architect §2a).
#
# R1/R2: the codex-adversarial dispatch inside leadv2-review-run.sh's run_reviewer_arm()
# `codex` arm carries a doc pointer naming the maintained authoritative surfaces, and the
# staleness caveat on docs/specs/*.md. This is the sole-owner engine's analogue of what
# workflows/leadv2-review.js used to carry (that file is now deleted -- see
# dispatch-75d151fe-architect §1/§5; leadv2-review-run.sh is the one reachable owner at
# LEADV2_REVIEW_ENGINE=1, and is unconditionally on the lead/skill path).
#
# R3/R4 DROPPED (architect §2a): R3 reconstructed a pre-fix state of leadv2-review.js via
# git archive -- meaningless once that file no longer exists. R4 asserted 3-copy
# byte-identity of a file that no longer exists. Replaced below with the equivalent
# anti-drift invariant expressed against the surviving owner: leadv2-review-run.sh has
# exactly one copy under plugins/leadv2/scripts/ and no shadow copy resurfaces under
# ~/.claude/ (the same "missed-copy" defect class R4 protected against).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
CANONICAL="$REPO_ROOT/plugins/leadv2/scripts/leadv2-review-run.sh"

SURFACES=(
  '.claude/CLAUDE.md'
  'docs/reference/ENGINE-REFERENCE.md'
  'docs/systems-map/CONTROL-TRUTH.md'
  'docs/systems-map/TRUTH-TABLE.md'
  'docs/BOARD.md'
)

pass=0
fail=0

check() {
  local desc="$1" cond="$2"
  if [[ "$cond" == "0" ]]; then
    echo "PASS: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc"
    fail=$((fail + 1))
  fi
}

# --- R1/R2: live (working-tree) engine carries all 5 surfaces + staleness caveat, inside
# the codex arm's --focus string.
for surface in "${SURFACES[@]}"; do
  if grep -qF "$surface" "$CANONICAL"; then
    check "engine names $surface" 0
  else
    check "engine names $surface" 1
  fi
done

if grep -q 'docs/specs/\*\.md.*possibly stale' "$CANONICAL"; then
  check "engine carries the docs/specs staleness caveat" 0
else
  check "engine carries the docs/specs staleness caveat" 1
fi

# --- anti-drift (replaces R4): exactly one copy of leadv2-review-run.sh under
# plugins/leadv2/scripts/, and no shadow copy under ~/.claude/ (workflows/ or the plugin
# cache) that would silently diverge from canonical.
copy_count="$(find "$REPO_ROOT/plugins/leadv2/scripts" -name 'leadv2-review-run.sh' | grep -c . || true)"
if [[ "$copy_count" -eq 1 ]]; then
  check "exactly one copy of leadv2-review-run.sh under plugins/leadv2/scripts/" 0
else
  check "exactly one copy of leadv2-review-run.sh under plugins/leadv2/scripts/ (found $copy_count)" 1
fi

shadow_count="$(find "$HOME/.claude" -name 'leadv2-review-run.sh' -not -path '*/plugins/cache/*' 2>/dev/null | grep -c . || true)"
if [[ "$shadow_count" -eq 0 ]]; then
  check "no shadow copy of leadv2-review-run.sh under ~/.claude/ (outside plugin cache)" 0
else
  check "no shadow copy of leadv2-review-run.sh under ~/.claude/ (outside plugin cache, found $shadow_count)" 1
fi

echo "---"
echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
