#!/usr/bin/env bash
# ONE-PATH-EVERYWHERE-01 T6 (static, no execution): reachability census parameterised by
# LEADV2_REVIEW_ENGINE, per dispatch-75d151fe-architect §3.
#
# A plain file-count census cannot be right: at LEADV2_REVIEW_ENGINE=0 (the mandated
# production default everywhere) leadv2-review-run.sh is genuinely NOT the reviewer that
# runs -- leadv2-dispatch-product-close.sh's inline run_reviewer_arm() is, and that inline
# body is REQUIRED to stay byte-for-byte (see leadv2-dispatch-product-close.sh:1542-1548).
# So the invariant this test proves is:
#
#   for each value of LEADV2_REVIEW_ENGINE (0 and 1), exactly one review-orchestration
#   owner is reachable, and every owner file discovered on disk is accounted for by
#   exactly one of those two buckets.
#
# Bucket table (allowlist BY PATH -- adding a row is a design decision, not a test fix):
#   flag=0  scripts/leadv2-dispatch-product-close.sh   (inline run_reviewer_arm(), gated else-branch)
#   flag=1  scripts/leadv2-review-run.sh                (engine; product-close's then-branch execs it)
#
# The test does NOT execute the lane or the engine. "Reachable" is proved by
# re-verifying the SHAPE of the gate expression in product-close (the same branch that
# picks the engine at flag=1 and the inline body at flag=0), not by running either path.
#
# Anything discovered that is not one of the two allowlisted paths -- a resurrected
# workflows/leadv2-review.js, a second run_reviewer_arm() anywhere else, a new fan-out
# file -- is UNCLASSIFIED and fails the census immediately, with its path printed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGINS_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LEADV2_SCRIPTS="$PLUGINS_ROOT/leadv2/scripts"
LEADV2_WORKFLOWS="$PLUGINS_ROOT/leadv2/workflows"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$SCRIPT_DIR/test-review-single-owner-census.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

# Allowlist-by-path. FLAG0_OWNER is reachable when LEADV2_REVIEW_ENGINE=0 (default,
# everywhere). FLAG1_OWNER is reachable when LEADV2_REVIEW_ENGINE=1 (lane) and
# unconditionally on the lead/skill path.
FLAG0_OWNER="$LEADV2_SCRIPTS/leadv2-dispatch-product-close.sh"
FLAG1_OWNER="$LEADV2_SCRIPTS/leadv2-review-run.sh"

# 1. Discover -- same fan-out grep as before, excluding tests/docs/err logs.
owners="$(grep -rlE -- '^run_reviewer_arm\(\)|const[[:space:]]+reviewers[[:space:]]*=[[:space:]]*\[|parallel\(reviewers\)' \
  "$LEADV2_SCRIPTS" "$LEADV2_WORKFLOWS" 2>/dev/null \
  | grep -vE '/tests/|\.err$|\.md$' \
  | sort -u)"

log "owners found:"
if [[ -n "$owners" ]]; then
  while IFS= read -r o; do
    case "$o" in
      "$FLAG0_OWNER") log "  $o  [bucket: flag=0]" ;;
      "$FLAG1_OWNER") log "  $o  [bucket: flag=1]" ;;
      *)              log "  $o  [bucket: UNCLASSIFIED]" ;;
    esac
  done <<< "$owners"
else
  log "  (none)"
fi

# 2. Classify -- split discovered set into the two allowlisted buckets plus unclassified.
flag0_members=""
flag1_members=""
unclassified=""
if [[ -n "$owners" ]]; then
  while IFS= read -r o; do
    case "$o" in
      "$FLAG0_OWNER") flag0_members="${flag0_members}${o}\n" ;;
      "$FLAG1_OWNER") flag1_members="${flag1_members}${o}\n" ;;
      *) unclassified="${unclassified}${o}\n" ;;
    esac
  done <<< "$owners"
fi

flag0_count="$(printf '%b' "$flag0_members" | grep -c . || true)"
flag1_count="$(printf '%b' "$flag1_members" | grep -c . || true)"
unclassified_count="$(printf '%b' "$unclassified" | grep -c . || true)"

# 3a. flag=0 bucket must have exactly one member (leadv2-dispatch-product-close.sh), AND
# its gate expression must still have the shape the bucket depends on: a branch on
# LEADV2_REVIEW_ENGINE whose then-side execs leadv2-review-run.sh and whose else-side is
# the inline body (i.e. product-close itself, unconditionally reachable, is the flag=0
# fallback owner). Static re-verification of the gate SHAPE only -- no execution.
if [[ "$flag0_count" -eq 1 ]] \
   && grep -qE '\[\[[[:space:]]*"\$\{LEADV2_REVIEW_ENGINE:-0\}"[[:space:]]*==[[:space:]]*"1"[[:space:]]*\]\]' "$FLAG0_OWNER" 2>/dev/null \
   && grep -qE 'leadv2-review-run\.sh' "$FLAG0_OWNER" 2>/dev/null; then
  pass "flag=0 bucket has exactly one owner (leadv2-dispatch-product-close.sh) with gate expression routing flag=1 to leadv2-review-run.sh"
else
  fail "flag=0 bucket invariant broken: count=$flag0_count, gate-expression-shape-found=$(grep -qE '\[\[[[:space:]]*"\$\{LEADV2_REVIEW_ENGINE:-0\}"[[:space:]]*==[[:space:]]*"1"[[:space:]]*\]\]' "$FLAG0_OWNER" 2>/dev/null && echo yes || echo no)"
fi

# 3b. flag=1 bucket must have exactly one member: leadv2-review-run.sh.
if [[ "$flag1_count" -eq 1 ]]; then
  pass "flag=1 bucket has exactly one owner: leadv2-review-run.sh"
else
  fail "flag=1 bucket expected exactly 1 (leadv2-review-run.sh), found $flag1_count"
fi

# 3c. discovered set minus the two buckets must be empty -- fail-on-unclassified.
if [[ "$unclassified_count" -eq 0 ]]; then
  pass "no unclassified review-orchestration owners"
else
  fail "unclassified owner file(s) found (not in allowlist): $(printf '%b' "$unclassified" | tr '\n' ',')"
fi

log ""
log "================================================"
log "  review single-owner census: PASS=$PASS FAIL=$FAIL"
log "================================================"
[[ "$FAIL" -eq 0 ]]
