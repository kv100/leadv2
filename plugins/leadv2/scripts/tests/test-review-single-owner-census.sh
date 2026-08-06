#!/usr/bin/env bash
# ONE-PATH-EVERYWHERE-01 T6 (static, no execution): grep-based census — exactly ONE
# file in the repo should own review orchestration (spawn `--role critic`,
# `adversarial-review`, or an `agentType: 'critic'` fan-out). Intended end-state is
# leadv2-review-run.sh as the sole owner after workflows/leadv2-review.js is deleted.
#
# KNOWN GAP (see deliverable): this test currently reports THREE owners, not one:
#   1. workflows/leadv2-review.js — NOT deleted this run. grep found live callers in
#      the existing test suite (test-codex-doc-pointer.sh, test-leadv2-review-routing.sh,
#      test-leadv2-phase8-learn-counter.sh) that assert its presence/content, which is
#      exactly the STOP condition the task spec named ("do not strand a caller").
#   2. leadv2-dispatch-product-close.sh — still defines its own run_reviewer_arm()
#      inside the LEADV2_REVIEW_ENGINE=0 fallback body. This is REQUIRED by the design's
#      own §5 resolution ("a mid-flight lane that spawns product-close after the edit
#      still runs today's inline body" — byte-for-byte inertness at flag=0), which
#      overrides the design's A3 mitigation ("delete the lane copy in the same commit")
#      for as long as the flag defaults to 0 everywhere. Deleting it now would violate
#      §5, not satisfy it.
# This test is expected to FAIL until both are resolved (workflows/leadv2-review.js
# migration/deletion, and the eventual LEADV2_REVIEW_ENGINE=1 flip that lets the lane's
# dead fallback body be removed). It still passes the "fails against a stash of
# leadv2-review-run.sh" bar: on main (no engine at all), the count is 1
# (workflows/leadv2-review.js only) and the assertion below ('== 1 AND is the engine')
# fails there too, for a different, equally correct reason.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGINS_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$SCRIPT_DIR/test-review-single-owner-census.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

# Narrower than a bare `--role critic` / `adversarial-review` string grep (those also
# match legitimate non-owner mentions: tool implementations, comments, callers that
# invoke the ONE owner). "Owns orchestration" = defines a reviewer FAN-OUT: the bash
# `run_reviewer_arm()` function definition, or JS `const reviewers = [` / `parallel(reviewers)`.
owners="$(grep -rlE -- '^run_reviewer_arm\(\)|const[[:space:]]+reviewers[[:space:]]*=[[:space:]]*\[|parallel\(reviewers\)' \
  "$PLUGINS_ROOT/leadv2/scripts" "$PLUGINS_ROOT/leadv2/workflows" 2>/dev/null \
  | grep -vE '/tests/|\.err$|\.md$' \
  | sort -u)"

owner_count="$(printf '%s\n' "$owners" | grep -c . || true)"
engine_is_owner=0
printf '%s\n' "$owners" | grep -q 'leadv2-review-run\.sh$' && engine_is_owner=1

log "owners found:"
printf '%s\n' "$owners" | sed 's/^/  /'

if [[ "$owner_count" -eq 1 && "$engine_is_owner" -eq 1 ]]; then
  pass "exactly one review-orchestration owner: leadv2-review-run.sh"
else
  fail "expected exactly one owner (leadv2-review-run.sh), found $owner_count: $(printf '%s' "$owners" | tr '\n' ',')"
fi

log ""
log "================================================"
log "  review single-owner census: PASS=$PASS FAIL=$FAIL"
log "================================================"
[[ "$FAIL" -eq 0 ]]
