#!/usr/bin/env bash
# test-codex-doc-pointer.sh — RETIRE-CODEX-BUNDLE-01
#
# R1/R2: the codex-adversarial dispatcher prompt in leadv2-review.js carries a doc pointer
# naming the maintained authoritative surfaces, and the staleness caveat on docs/specs/*.md.
# This is the function that replaces codex-context-bundle.sh's role for the ONE reachable
# call site (leadv2-review.js:151, the haiku dispatcher agent) -- NOT a claim that Codex
# itself reads this text; codex-task.sh/codex-companion take no prompt-injection flag today.
#
# R4: all three live copies of leadv2-review.js (canonical, ~/.claude/workflows,
# plugin cache) are byte-identical after the edit -- catches the missed-copy defect that
# left ~/.claude/workflows/leadv2-review.js and the plugin cache as real (non-symlink)
# copies that a canonical-only edit would silently miss.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
CANONICAL="$REPO_ROOT/plugins/leadv2/workflows/leadv2-review.js"
LIVE_HOME="$HOME/.claude/workflows/leadv2-review.js"
LIVE_CACHE="$HOME/.claude/plugins/cache/leadv2-local/leadv2/0.1.0/workflows/leadv2-review.js"

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

# --- R3 (pre-req, informational): reconstruct the pre-fix prompt via git archive, never
# git stash/reset/clean (shared-tree rule -- other lanes hold uncommitted work in this repo).
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
git -C "$REPO_ROOT" archive HEAD -- plugins/leadv2/workflows/leadv2-review.js \
  | tar -x -C "$SCRATCH"
PRE_FIX="$SCRATCH/plugins/leadv2/workflows/leadv2-review.js"

if [[ -f "$PRE_FIX" ]] && grep -q 'ENGINE-REFERENCE.md' "$PRE_FIX"; then
  echo "UNEXPECTED: pre-fix HEAD already carries the pointer -- RED reconstruction invalid"
  fail=$((fail + 1))
else
  echo "RED confirmed: pre-fix HEAD (git archive) does not carry the doc pointer"
fi

# --- R1/R2: live (working-tree) canonical file carries all 5 surfaces + staleness caveat
for surface in "${SURFACES[@]}"; do
  if grep -qF "$surface" "$CANONICAL"; then
    check "canonical names $surface" 0
  else
    check "canonical names $surface" 1
  fi
done

if grep -q 'docs/specs/\*\.md.*possibly stale' "$CANONICAL"; then
  check "canonical carries the docs/specs staleness caveat" 0
else
  check "canonical carries the docs/specs staleness caveat" 1
fi

# --- R4: three live copies are byte-identical
if [[ ! -f "$LIVE_HOME" ]]; then
  check "R4: $LIVE_HOME exists" 1
elif [[ ! -f "$LIVE_CACHE" ]]; then
  check "R4: $LIVE_CACHE exists" 1
else
  h1="$(md5 -q "$CANONICAL" 2>/dev/null || md5sum "$CANONICAL" | awk '{print $1}')"
  h2="$(md5 -q "$LIVE_HOME" 2>/dev/null || md5sum "$LIVE_HOME" | awk '{print $1}')"
  h3="$(md5 -q "$LIVE_CACHE" 2>/dev/null || md5sum "$LIVE_CACHE" | awk '{print $1}')"
  if [[ "$h1" == "$h2" && "$h2" == "$h3" ]]; then
    check "R4: canonical == ~/.claude/workflows == plugin-cache ($h1)" 0
  else
    check "R4: canonical($h1) == home($h2) == cache($h3)" 1
  fi
fi

echo "---"
echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
