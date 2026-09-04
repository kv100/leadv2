#!/usr/bin/env bash
# test-core-offline-shard-scope-01.sh — E2E-GATE-BROKE-TODAY-01 round 3
#
# State lock on run-core-offline.sh SUITE_DEFS shard placement (the round-2
# change). Round 2 moved 4 of the 11 |||SERIAL markers into the parallel shard
# pool; 7 markers stayed SERIAL, each with a recorded one-line justification.
# 2026-09-04: those 7 were re-derived by BEHAVIOUR rather than by list
# membership -- each run alone in an isolated worktree under /private/tmp, with
# git status on docs/leadv2 before and after. Four came back green AND clean
# (no-work-terminal, codex-session-runner, lanes-snapshot, stop-gate) and moved
# to the pool; three dirty docs/leadv2/open-threads.md and stayed SERIAL. The
# round-2 reasons cited _CORE_OFFLINE_OWNED_SUITES, but that list sets the
# SEVERITY of a hermeticity violation (run_check ~296: owned = FAIL, else WARN),
# never placement -- a borrowed justification: the citation is real, the
# document is real, and the proposition it needed is not in it.
# This suite pins BOTH halves of that decision so neither direction can drift
# silently:
#   - the 4 round-2 suites MUST be assigned to a parallel shard;
#   - the 7 justified suites MUST stay in the serial tail.
#
# The assertion input is the runner's own introspection dump
# (LEADV2_SUITE_SHARDS_DUMP=1: "shard=N idx=M name=..." / "serial idx=M
# name=..."), parsed into (name -> pool) pairs — placement STATE, never
# runner output text. The dump mode executes no suites, so this guard costs
# one runner parse, not a suite run.
#
# Registration: runs inside the gate via run-core-offline.sh SUITE_DEFS. For
# tests/run-all.sh --scope changed, wire the row
#   run-core-offline.sh:plugins/leadv2/scripts/tests/test-core-offline-shard-scope-01.sh
# into EXTRA_SUITE_MAP (NOT applied by this lane — tests/run-all.sh is a
# shared file; see docs/handoff/dispatch-3dd21396/developer.full.md).

set -euo pipefail

# SUITE-TEMPLATE-IS-ZSH-BLIND-01: fourth suite this shift blinded the same way.
# BASH_SOURCE does not exist under zsh, so this aborted before a single case ran
# (measured 1x5) while reading like a verdict about the runner.
_src="${BASH_SOURCE[0]:-}"
if [[ -z "$_src" && -f "${0:-}" ]]; then _src="$0"; fi
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
TEST_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _dir
RUNNER="$TEST_DIR/run-core-offline.sh"

pass=0
fail=0

# Pin the shard count: the dump only renders the serial section when
# shards > 1, and the placement contract is defined for the sharded path.
dump="$(LEADV2_SUITE_SHARDS=4 LEADV2_SUITE_SHARDS_DUMP=1 bash "$RUNNER")"

# Parse every dump line into "name<TAB>pool". Anything unparseable is kept
# visible as its own row so a format change cannot silently pass the guard.
assign="$(printf '%s\n' "$dump" | awk '
  /^shard=[0-9]+ idx=[0-9]+ name=/ { sub(/^shard=[0-9]+ idx=[0-9]+ name=/, ""); print $0 "\tparallel"; next }
  /^serial idx=[0-9]+ name=/       { sub(/^serial idx=[0-9]+ name=/, ""); print $0 "\tserial"; next }
  { print "<unparseable:" $0 ">\tunparseable" }
' | LC_ALL=C sort)"

pool_of() { # <suite name> -> parallel | serial | <absent>
  printf '%s\n' "$assign" | awk -F'\t' -v n="$1" '$1 == n { print $2; found=1 } END { if (!found) print "<absent>" }'
}

expect_pool() { # <suite name> <expected pool> <label>
  local got
  got="$(pool_of "$1")"
  if [[ "$got" == "$2" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[SHARD-SCOPE-01]   FAILED: $3: expected pool=$2 got=$got"
  fi
}

# --- the 4 round-2 parallelized suites (each isolated via mktemp /
# LEADV2_STATE_ROOT / LEADV2_PROJECT_ROOT, absent from
# _CORE_OFFLINE_OWNED_SUITES, so run_check's per-suite private $HOME already
# separates them — no serial placement needed) ---
expect_pool "lane worktrees survive the sweepers (SWEEPER-LANE-SAFETY-01)" parallel "test-worktree-lane-safety"
expect_pool "fanout classifier/runner guard" parallel "test-fanout-classify-guard"
expect_pool "report-only gate (REPORT-ONLY-GATE-01: report lane deliverable)" serial "test-report-only-gate"
expect_pool "prepass resume invalidation (LANE-OBSERVABILITY-02)" parallel "test-prepass-resume-invalidate"

# --- the 7 justified SERIAL suites (first 5 are on _CORE_OFFLINE_OWNED_SUITES:
# fixtures write real REPO_ROOT/docs/leadv2 state, which the hermetic
# git-status check would misattribute between concurrent suites; last 2 kept
# per round-1 findings that round 2 could not disprove) ---
expect_pool "dispatch refusal fallback chain" serial "test-routing-enforcement-p1"
expect_pool "product-close waits for worker exit" serial "test-no-work-terminal"
expect_pool "Codex full-cycle runner" serial "test-codex-session-runner"
expect_pool "lanes snapshot reconciliation" serial "test-lanes-snapshot"
expect_pool "lane truth batch (log_path + quarantine convergence)" serial "test-lane-truth-batch-01"
expect_pool "stop-gate autocommit on worker exit (V3-STOP-GATE-01)" serial "test-stop-gate"
expect_pool "burn governor (BURN-GOVERNOR-01: 24h burn gate)" serial "test-burn-governor"

# A dump line the parser did not recognize means the runner's dump format
# changed under this guard — fail loudly rather than assert against a stale
# parse.
if printf '%s\n' "$assign" | grep -q '^<unparseable:'; then
  fail=$((fail + 1))
  echo "[SHARD-SCOPE-01]   FAILED: unparseable dump lines:"
  printf '%s\n' "$assign" | grep '^<unparseable:' | head -3
else
  pass=$((pass + 1))
fi

echo "[SHARD-SCOPE-01] pass=$pass fail=$fail"
(( fail == 0 ))
