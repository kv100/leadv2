#!/usr/bin/env bash
# Reproducible, no-model/no-network core regression suite for the leadv2
# plugin. Covers manifest loading, shell syntax, provider routing/runners,
# supervisor isolation, active registry, and Phase-8 completion guards.

set -euo pipefail

# --- root arithmetic (GATE-ROOT-ARITH-01) -------------------------------------
# LOGICAL_DIR: the entry path as written by the caller — symlink NOT resolved.
# It is the only thing that answers "which checkout was this invoked from?".
LOGICAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# REPO_ROOT: derived from git, never from ../.. hops. A symlink entry from
# persona-engine resolves to persona-engine's toplevel; a canonical entry (incl.
# any leadv2 worktree lane) resolves to that worktree's toplevel.
REPO_ROOT="$(git -C "$LOGICAL_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ] || [ ! -e "$REPO_ROOT/.git" ]; then
  printf -- '[CORE-OFFLINE] FATAL repo_root_unresolvable from=%s resolved=%s\n' \
    "$LOGICAL_DIR" "${REPO_ROOT:-<not-a-git-checkout>}" >&2
  exit 2
fi

# PHYS_TEST_DIR / PLUGIN_ROOT: physical location of THIS file. Plugin-internal
# siblings must resolve into the canonical plugin tree regardless of entry path.
# bash-3.2 safe: manual readlink chain, no `readlink -f` / `realpath`.
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
PHYS_TEST_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
PLUGIN_ROOT="$(cd -P "$PHYS_TEST_DIR/../.." && pwd)"
TEST_DIR="$PLUGIN_ROOT/scripts/tests"
unset _src _dir
# -----------------------------------------------------------------------------

if [ -n "${LEADV2_CORE_OFFLINE_PROBE:-}" ]; then
  printf -- '[CORE-OFFLINE] probe LOGICAL_DIR=%s REPO_ROOT=%s PLUGIN_ROOT=%s TEST_DIR=%s\n' \
    "$LOGICAL_DIR" "$REPO_ROOT" "$PLUGIN_ROOT" "$TEST_DIR"
  exit 0
fi
PASS=0
FAIL=0
MISSING=0

run_check() {
  local name="$1"
  shift
  printf -- '\n[CORE-OFFLINE] %s\n' "$name"
  # A missing suite file must not be indistinguishable from a failing
  # assertion (N-4): preflight `bash <path>` invocations before executing.
  if [[ "$1" == "bash" && "$2" == /* && ! -r "$2" ]]; then
    MISSING=$((MISSING + 1))
    printf -- '[CORE-OFFLINE] MISSING: %s — %s does not exist\n' "$name" "$2" >&2
    return
  fi
  if "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf -- '[CORE-OFFLINE] FAILED: %s\n' "$name" >&2
  fi
}

syntax_all() {
  local file
  while IFS= read -r file; do
    bash -n "$file"
  done < <(find "$PLUGIN_ROOT" -type f -name '*.sh' -print | sort)
}

validate_plugin() {
  if ! command -v claude >/dev/null 2>&1; then
    printf -- '[CORE-OFFLINE] claude CLI unavailable; manifest validation cannot run\n' >&2
    return 1
  fi
  claude plugin validate "$PLUGIN_ROOT"
}

run_check "all plugin shell syntax" syntax_all
run_check "portable temp helper stress" bash "$TEST_DIR/test-leadv2-temp-stress.sh"
run_check "Claude plugin manifest/components" validate_plugin
run_check "provider/model router" bash "$TEST_DIR/test-session-route.sh"
run_check "dispatch refusal fallback chain" bash "$TEST_DIR/test-routing-enforcement-p1.sh"
run_check "product-close waits for worker exit" bash "$TEST_DIR/test-no-work-terminal.sh"
run_check "product-close resumes a died-with-work lane once" bash "$TEST_DIR/test-dwr-resume.sh"
run_check "product-close scopes a single-repo lane worktree" bash "$TEST_DIR/test-lane-diff-single-repo.sh"
run_check "Codex full-cycle runner" bash "$TEST_DIR/test-codex-session-runner.sh"
run_check "Codex terminal lead intake" bash "$TEST_DIR/test-codex-lead-intake.sh"
run_check "Codex child-session recursion boundary" bash "$TEST_DIR/test-codex-child-session-boundary.sh"
run_check "autonomous session spawner" bash "$TEST_DIR/test-session-spawner.sh"
run_check "hook token + mode isolation" bash "$TEST_DIR/test-hook-token-mode-isolation.sh"
run_check "main model/live quota" bash "$TEST_DIR/test-main-model-check.sh"
run_check "active registry fail-closed" bash "$TEST_DIR/test-active-registry-failclosed.sh"
run_check "active registry phase updates" bash "$TEST_DIR/test-active-registry-update-phase.sh"
run_check "fanout classifier/runner guard" bash "$TEST_DIR/test-fanout-classify-guard.sh"
run_check "supervisor fail-closed" bash "$TEST_DIR/test-supervise-failclosed.sh"
run_check "supervisor reconciliation" bash "$TEST_DIR/test-supervise-v2.sh"
run_check "supervisor/lead PID isolation" bash "$PLUGIN_ROOT/tests/test-supervise-fanout-guard.sh"
run_check "Phase-8 task schema" bash "$TEST_DIR/test-leadv2-phase8-assert-a2-schema.sh"
run_check "Phase-8 merge/completion proof" bash "$PLUGIN_ROOT/tests/test-deploy-merge-blocker-gate.sh"
run_check "subsession model downgrade" bash "$TEST_DIR/test-leadv2-model-arg-rebuild.sh"
run_check "plugin sync quarantine/dry-run safety" bash "$TEST_DIR/test-drift-guard-quarantine-perimeter.sh"
run_check "skill lint" bash "$TEST_DIR/test-leadv2-skill-lint.sh"
run_check "skill proof gate unit tests" bash "$TEST_DIR/test-skill-proof-gate.sh"
run_check "status surface single-lead + census" bash "$REPO_ROOT/tests/test-status-surface-single-lead.sh"
run_check "reply router dual-store resolution" bash "$TEST_DIR/test-reply-router-01.sh"
run_check "question delivery ownership" bash "$TEST_DIR/test-question-delivery-ownership-01.sh"
run_check "landed-at-spawn (no terminal=landed at spawn; target repo keying)" bash "$TEST_DIR/test-landed-at-spawn.sh"
run_check "lane placement pin (--resume-lane/--worktree)" bash "$TEST_DIR/test-lane-placement-pin.sh"
run_check "Codex quota guardrails (effort/circuit/hook)" bash "$TEST_DIR/test-codex-quota-guardrails.sh"
run_check "e2e gate lane root + suite family" bash "$TEST_DIR/test-e2e-gate-lane-root.sh"
run_check "review body persist (opus/sonnet materialisation + body_lost guard)" bash "$TEST_DIR/test-review-body-persist.sh"
run_check "review codex base (committed lane never diffs HEAD↔HEAD)" bash "$TEST_DIR/test-review-codex-base.sh"
run_check "quota stand-down duration (record-quota-lockout --hours)" bash "$TEST_DIR/test-quota-standdown-duration.sh"
run_check "core-offline root arithmetic (git-derived REPO_ROOT)" bash "$TEST_DIR/test-core-offline-root-arith.sh"
run_check "dispatch arm vocabulary (kimi retirement)" bash "$TEST_DIR/test-dispatch-arm-vocabulary.sh"
run_check "foreground-dispatch guard hook" bash "$TEST_DIR/test-fg-dispatch-guard.sh"
run_check "idle-lead guard hook" bash "$TEST_DIR/test-idle-lead-guard.sh"
run_check "phase record round-trip" bash "$TEST_DIR/test-phase-record.sh"
run_check "phase precondition guard matrix" bash "$TEST_DIR/test-phase-precondition.sh"
run_check "lane phase render" bash "$TEST_DIR/test-lane-phase-render.sh"
run_check "lane truth batch (log_path + quarantine convergence)" bash "$TEST_DIR/test-lane-truth-batch-01.sh"
run_check "founder lane view" bash "$TEST_DIR/test-leadv2-lanes.sh"
run_check "plugin reliability (process liveness + role fallback + prepass/reorder signals)" bash "$TEST_DIR/test-plugin-reliability-01.sh"
run_check "plugin reliability-02 (zombie-reaper: run_dir arg + group signaling + ordering + TASK)" bash "$TEST_DIR/test-plugin-reliability-02.sh"
run_check "plan-followups-01" bash "$TEST_DIR/test-plan-followups-01.sh"
run_check "e2e gate arch-01 (lane-tree testing)" bash "$TEST_DIR/test-e2e-gate-arch-01.sh"
run_check "report-only gate (REPORT-ONLY-GATE-01: report lane deliverable)" bash "$TEST_DIR/test-report-only-gate.sh"
run_check "review round exhaustive/verify-only (REVIEW-ROUND1-EXHAUSTIVE-01)" bash "$TEST_DIR/test-review-round-exhaustive.sh"

printf -- '\n[CORE-OFFLINE] suites passed=%d failed=%d missing=%d repo=%s\n' "$PASS" "$FAIL" "$MISSING" "$REPO_ROOT"
(( FAIL == 0 && MISSING == 0 ))
