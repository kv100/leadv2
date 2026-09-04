#!/usr/bin/env bash
# SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01 — suites self-register their
# changed-scope triggers next to themselves; tests/run-all.sh discovers them
# by walking the four suite directories (scan_suite_triggers), so adding a
# suite edits only that suite's own file — never the run-all.sh map block.
# The ~220-row EXTRA_SUITE_MAP literal was migrated into these declarations.
#
# This suite pins the mechanism three ways:
#   1. real-tree invariants: every '# run-all-triggers:' declaration in the
#      four suite directories parses (charset + non-empty), and EVERY row of
#      the pre-migration map snapshot below still resolves to the same suite
#      — proven by enumeration, not inspection (no row silently dropped);
#   2. integration (scratch repo + the real run-all.sh): a marker-declared
#      suite is selected when its mapped stem is dirtied — under both bash
#      AND zsh, failing on any disagreement — and is NOT selected for an
#      unmapped stem (attribution);
#   3. loud failure: a malformed declaration (invalid char, empty list)
#      exits 2 with bad_trigger_decl — never a silently unselected suite.
# run-all-triggers: run-all.sh
set -uo pipefail

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=$((FAIL + 1)); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_ALL="$ROOT/tests/run-all.sh"
[[ -f "$RUN_ALL" ]] || { echo "FAIL: run-all not found at $RUN_ALL"; exit 1; }

# tokenize a declaration body the same way run-all.sh does (commas are
# whitespace; runs of whitespace are one separator)
tokens_of() { # <decl-body> -> one token per line on stdout
  printf '%s' "$1" | tr ',' ' ' | tr -s '[:space:]' '\n'
}

# --- part 1a: every real declaration parses ----------------------------------
decl_files=0; decl_lines=0; bad=0
for dir in "$ROOT/plugins/leadv2/scripts/tests" "$ROOT/.claude/scripts/tests" \
           "$ROOT/plugins/leadv2/tests" "$ROOT/tests"; do
  [[ -d "$dir" ]] || continue
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    hits="$(grep -n '^# run-all-triggers:' "$f" 2>/dev/null || true)"
    [[ -n "$hits" ]] || continue
    decl_files=$((decl_files + 1))
    while IFS= read -r hit; do
      [[ -n "$hit" ]] || continue
      decl_lines=$((decl_lines + 1))
      lineno="${hit%%:*}"
      body="${hit#*:}"
      body="${body#'# run-all-triggers:'}"
      n=0; badtok=""
      while IFS= read -r tok; do
        [[ -n "$tok" ]] || continue
        case "$tok" in
          *[!A-Za-z0-9._-]*) badtok="$tok" ;;
          *) n=$((n + 1)) ;;
        esac
        [[ -n "$badtok" ]] && break
      done <<< "$(tokens_of "$body")"
      if [[ -n "$badtok" ]]; then
        fail "malformed declaration (invalid trigger '$badtok'): ${f#"${ROOT}/"}:$lineno"
        bad=$((bad + 1))
      elif [[ $n -eq 0 ]]; then
        fail "malformed declaration (no triggers): ${f#"${ROOT}/"}:$lineno"
        bad=$((bad + 1))
      fi
    done <<< "$hits"
  done < <(find "$dir" -maxdepth 1 -type f -name 'test-*.sh' 2>/dev/null | sort)
done
if [[ $bad -eq 0 ]]; then
  pass "all real declarations parse ($decl_files files, $decl_lines declaration lines)"
fi

# --- part 1b: enumeration — every pre-migration map row still resolves -------
# Snapshot of tests/run-all.sh EXTRA_SUITE_MAP at anchor 5bd9e11d (2026-09-04,
# immediately before the SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01 migration).
# Format: one "<stem>:<suite-relpath>" row per line, byte-identical to the
# rows the literal map carried. Each row must still resolve: the suite file
# exists and declares the stem, or the row survives as an EXTRA_SUITE_MAP
# fallback row in run-all.sh (a trigger cannot be written into a file that
# does not exist — those rows must stay in the map).
rows_resolved=0; rows_missing=0
while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  key="${row%%:*}"
  suite="${row#*:}"
  if [[ ! -f "$ROOT/$suite" ]]; then
    fail "snapshot row suite file missing: $row"
    rows_missing=$((rows_missing + 1))
    continue
  fi
  ok=0
  decls="$(grep -h '^# run-all-triggers:' "$ROOT/$suite" 2>/dev/null || true)"
  if [[ -n "$decls" ]]; then
    while IFS= read -r decl; do
      [[ -n "$decl" ]] || continue
      while IFS= read -r tok; do
        [[ -n "$tok" ]] || continue
        [[ "$tok" == "$key" ]] && { ok=1; break; }
      done <<< "$(tokens_of "${decl#'# run-all-triggers:'}")"
      [[ $ok -eq 1 ]] && break
    done <<< "$decls"
  fi
  if [[ $ok -eq 0 ]]; then
    # supported fallback: the row may live in EXTRA_SUITE_MAP instead
    if grep -qF "$row" "$RUN_ALL"; then
      ok=1
    fi
  fi
  if [[ $ok -eq 1 ]]; then
    rows_resolved=$((rows_resolved + 1))
  else
    fail "snapshot row NO LONGER RESOLVES (dropped row — suite CI silently stops running it): $row"
    rows_missing=$((rows_missing + 1))
  fi
done <<'WAVE_OLD_ROWS_EOF'
glm-coder.sh:plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh
glm-coder.sh:plugins/leadv2/scripts/tests/test-glm-flash-handle.sh
glm-coder.sh:plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-glm-flash-handle.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh
leadv2-phase8-assert.sh:plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh
leadv2-hook-session-kind.sh:plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh
leadv2-single-lead-beat-loop.sh:plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh
leadv2-lane-pulse-watch.sh:plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh
leadv2-tasks-lib.sh:plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-plugin-papercuts.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh
leadv2-active-registry.sh:plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh
claude-subsession.sh:plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh
freepool-coder:plugins/leadv2/scripts/tests/test-freepool-model-selector.sh
leadv2-backlog-pump:plugins/leadv2/scripts/tests/test-backlog-pump.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-phase-precondition.sh
leadv2-gate1-prompt:plugins/leadv2/scripts/tests/test-gate1-discipline.sh
leadv2-phase-record:plugins/leadv2/scripts/tests/test-phase-record.sh
leadv2-phase-record:plugins/leadv2/scripts/tests/test-phase-precondition.sh
leadv2-phase-record:plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh
leadv2-phase-record:plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh
leadv2-admission-class:plugins/leadv2/scripts/tests/test-admission-class.sh
leadv2-admission-class:plugins/leadv2/scripts/tests/test-admission-safety-pin.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-admission-safety-pin.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-brain-class-live.sh
leadv2-brain-record:plugins/leadv2/scripts/tests/test-brain-class-live.sh
leadv2-admission-class:plugins/leadv2/scripts/tests/test-brain-class-live.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-route-arbiter-symlink-install.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-quota-reset-arbiter.sh
codex-task.sh:plugins/leadv2/scripts/tests/test-codex-longrun.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-freepool-gets-work.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-freepool-gets-work.sh
freepool-coder:plugins/leadv2/scripts/tests/test-freepool-turncap-checkpoint.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-model-select-telemetry.sh
leadv2-lane-pulse-watch.sh:plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh
leadv2-single-lead-beat-loop.sh:plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh
leadv2-single-lead-beat-loop.sh:plugins/leadv2/scripts/tests/test-plugin-papercuts.sh
leadv2-pulse-beat.sh:plugins/leadv2/scripts/tests/test-plugin-papercuts.sh
leadv2-routing.yaml:plugins/leadv2/scripts/tests/test-plugin-papercuts.sh
codex-task.sh:plugins/leadv2/scripts/tests/test-plugin-papercuts.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh
leadv2-lane-pulse-watch.sh:plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-broad-status-renderer-truth.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-broad-status-duty.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-pulse-readable-rendering.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-pulse-empty-board.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-single-lead-beat.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-lib-source-guarded.sh
leadv2-sleep.sh:plugins/leadv2/scripts/tests/test-no-orphan-sleep.sh
leadv2-hook-fork-budget.sh:plugins/leadv2/scripts/tests/test-hook-fork-budget.sh
hooks.json:plugins/leadv2/scripts/tests/test-hook-fork-budget.sh
leadv2-promise-guard.sh:plugins/leadv2/scripts/tests/test-promise-action-binding.sh
leadv2-promise-guard.sh:plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh
leadv2-promise-guard.sh:plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh
leadv2-promise-guard.sh:plugins/leadv2/scripts/tests/test-promise-guard-unknown-kind.sh
leadv2-promise-guard.sh:plugins/leadv2/tests/test-promise-guard.sh
leadv2-guard-census.sh:plugins/leadv2/scripts/tests/test-guard-census.sh
leadv2-guard-verdict.sh:plugins/leadv2/scripts/tests/test-guard-census.sh
leadv2-bash-pre-dispatch.sh:plugins/leadv2/scripts/tests/test-bash-pre-dispatch-verdict.sh
leadv2-guard-census.sh:plugins/leadv2/scripts/tests/test-bash-pre-dispatch-verdict.sh
leadv2-guard-verdict.sh:plugins/leadv2/scripts/tests/test-bash-pre-dispatch-verdict.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh
leadv2-worker-output-gate:plugins/leadv2/scripts/tests/test-worker-output-gate.sh
freepool-coder:plugins/leadv2/scripts/tests/test-worker-output-gate.sh
leadv2-repo-install.sh:plugins/leadv2/scripts/tests/test-adoption-gate-passable.sh
leadv2-freepool-model-select:plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh
freepool-arm.yaml:plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh
freepool-arm.yaml:plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh
freepool-arm.yaml:plugins/leadv2/scripts/tests/test-freepool-gets-work.sh
freepool-coder:plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-status-repo-scoped.sh
leadv2-status-collector.sh:plugins/leadv2/scripts/tests/test-collector-sees-registered-lane.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-mission-writeset.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-red-proof-gate.sh
leadv2-mission-writeset:plugins/leadv2/scripts/tests/test-mission-writeset.sh
leadv2-think-model.sh:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-router.sh:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-glm-policy-resolve.py:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-cache-warm.sh:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
model-capability.yaml:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-review-run.sh:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-session-route.sh:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-route-bandit.sh:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-ask.sh:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-fanout.sh:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-fanout-classify.sh:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-repo-install.sh:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-main-model.yaml:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-phase-record.sh:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-llm-judge.sh:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-diverge.js:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-learn.js:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-diagnose.js:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-po-feedback-loop.js:plugins/leadv2/scripts/tests/test-fable-think-tier.sh
leadv2-diverge.js:plugins/leadv2/scripts/tests/test-workflow-fallback-guard.sh
leadv2-po-feedback-loop.js:plugins/leadv2/scripts/tests/test-workflow-fallback-guard.sh
leadv2-audit.js:plugins/leadv2/scripts/tests/test-workflow-fallback-guard.sh
leadv2-red-proof:plugins/leadv2/scripts/tests/test-red-proof-gate.sh
leadv2-one-copy-drift.sh:plugins/leadv2/scripts/tests/test-hook-output-cap.sh
leadv2-truth-card-inject.sh:plugins/leadv2/scripts/tests/test-hook-output-cap.sh
leadv2-dispatch-ledger:plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
leadv2-dispatch-ledger.sh:plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
leadv2-dispatch-ledger.sh:plugins/leadv2/scripts/tests/test-close-chain.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-lane-containment.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-plan-in-lane.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-lane-placement-pin.sh
leadv2-lane-guard:plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
leadv2-lane-guard:plugins/leadv2/scripts/tests/test-lane-containment.sh
leadv2-lane-guard:plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh
leadv2-lane-guard:plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh
leadv2-lane-guard:plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh
leadv2-lane-guard:plugins/leadv2/scripts/tests/test-t13-slice1.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-class-floor-survives-resume.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh
leadv2-dispatch-ledger.sh:plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh
leadv2-admission-class.sh:plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh
test-consumer-symlink-farm.sh:plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh
leadv2-status-surface.sh:plugins/leadv2/scripts/tests/test-status-surface.sh
leadv2-lane-status-line.sh:plugins/leadv2/scripts/tests/test-statusline-readable.sh
leadv2-lane-status-line-tail.sh:plugins/leadv2/scripts/tests/test-statusline-readable.sh
leadv2-worker-output-gate:plugins/leadv2/scripts/tests/test-worker-gate-no-origin.sh
gitignore:plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh
gitignore:plugins/leadv2/scripts/tests/test-handoff-docs-not-leaked.sh
leadv2-lane-worktree:plugins/leadv2/scripts/tests/test-lane-worktree-base-pick.sh
leadv2-review-run.sh:plugins/leadv2/scripts/tests/test-review-body-recovery.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-arm-admission.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-arm-admission.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-arm-admission.sh
leadv2-control-prover.sh:plugins/leadv2/scripts/tests/test-control-prover.sh
leadv2-control-prover:plugins/leadv2/scripts/tests/test-control-prover.sh
leadv2-review-run.sh:plugins/leadv2/scripts/tests/test-control-prover.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-effort-routing.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-effort-routing.sh
codex-task.sh:plugins/leadv2/scripts/tests/test-codex-broker-staleness.sh
codex-guard.sh:plugins/leadv2/scripts/tests/test-codex-broker-staleness.sh
leadv2-notify-lead:plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
leadv2-inbox:plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
leadv2-ask:plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
ask-lead:plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
leadv2-broad-status:plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-complexity-routing.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-complexity-routing.sh
leadv2-router-v2:plugins/leadv2/scripts/tests/test-complexity-routing.sh
leadv2-lane-liveness.sh:plugins/leadv2/scripts/tests/test-lane-finished-state.sh
leadv2-lane-liveness.sh:plugins/leadv2/scripts/tests/test-fork-storm-watcher-liveness.sh
leadv2-dispatch-ledger.sh:plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh
leadv2-lane-liveness.sh:plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh
leadv2-lane-pulse-watch.sh:plugins/leadv2/scripts/tests/test-fork-storm-watcher-liveness.sh
leadv2-lanes-snapshot.sh:plugins/leadv2/scripts/tests/test-lane-finished-state.sh
leadv2-review-run.sh:plugins/leadv2/scripts/tests/test-suite-falsifiable.sh
leadv2-suite-falsifiable:plugins/leadv2/scripts/tests/test-suite-falsifiable.sh
run-core-offline.sh:plugins/leadv2/scripts/tests/test-suite-lock-scope.sh
leadv2-lane-watch-v2.sh:plugins/leadv2/scripts/tests/test-lane-watch-v2.sh
leadv2-lane-watch-v2:plugins/leadv2/scripts/tests/test-lane-watch-v2.sh
freepool-coder:plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh
kimi-coder:plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh
codex-task.sh:plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh
leadv2-codex-planner.sh:plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh
leadv2-worker-mcp.sh:plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh
leadv2-status-cache.sh:plugins/leadv2/scripts/tests/test-status-churn.sh
leadv2-spawn-rate.sh:plugins/leadv2/scripts/tests/test-status-churn.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-status-churn.sh
leadv2-status-collector.sh:plugins/leadv2/scripts/tests/test-status-churn.sh
leadv2-lanes-snapshot.sh:plugins/leadv2/scripts/tests/test-status-churn.sh
leadv2-lane-liveness.sh:plugins/leadv2/scripts/tests/test-status-churn.sh
leadv2-lane-status-line-tail.sh:plugins/leadv2/scripts/tests/test-status-churn.sh
leadv2-cache-truth.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
glm-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
freepool-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
kimi-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
claude-subsession.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
leadv2-plugin-cache-sync.sh:plugins/leadv2/scripts/tests/test-plugin-cache-sync.sh
leadv2-merge-queue.sh:plugins/leadv2/scripts/tests/test-merge-queue-dead-head.sh
leadv2-worker-epilogue.sh:plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh
leadv2-worker-epilogue.sh:plugins/leadv2/scripts/tests/test-freepool-turncap-checkpoint.sh
glm-coder.sh:plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh
run-all.sh:tests/test-run-all-carrier-map.sh
glm-coder.sh:plugins/leadv2/scripts/tests/test-lane-outcome.sh
leadv2-dod-gate.sh:plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
leadv2-mutation-control.sh:plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
leadv2-review-run.sh:plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
leadv2-worker-epilogue.sh:plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
leadv2-helpers.sh:plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
leadv2-lane-outcome.sh:plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
leadv2-phase8-e2e-gate.sh:plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
leadv2-repo-install.sh:plugins/leadv2/scripts/tests/test-repo-install-tracked-settings.sh
leadv2-quota-window-history.sh:plugins/leadv2/scripts/tests/test-leadv2-ratelimit-probe.sh
leadv2-lane-state.sh:plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh
leadv2-lane-heartbeat.sh:plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh
leadv2-watch-lifecycle.sh:plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh
leadv2-lane-salvage.sh:plugins/leadv2/scripts/tests/test-lane-salvage.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-leadv2-merge-safety-gate.sh
leadv2-deploy-merge.sh:plugins/leadv2/scripts/tests/test-leadv2-merge-safety-gate.sh
WAVE_OLD_ROWS_EOF
if [[ $rows_missing -eq 0 ]]; then
  pass "enumeration: all $rows_resolved pre-migration map rows still resolve to their suite"
fi

# --- part 2: scratch-repo integration against the real run-all.sh ------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SCRATCH="$TMP/repo"
git init -q "$SCRATCH" 2>/dev/null
mkdir -p "$SCRATCH/tests" "$SCRATCH/plugins/leadv2/scripts" \
         "$SCRATCH/plugins/leadv2/scripts/tests" "$SCRATCH/plugins/leadv2/config" \
         "$SCRATCH/plugins/leadv2/scripts/lib" "$SCRATCH/plugins/leadv2/workflows"
cp "$RUN_ALL" "$SCRATCH/tests/run-all.sh"
# Two mapped stub suites whose names deliberately do NOT match their stems'
# convention candidates (test-selfreg-*.sh does not exist), so selection is
# attributable to the self-declaration alone, never to the stem convention.
printf '#!/usr/bin/env bash\n# run-all-triggers: selfreg-filename.sh\nexit 0\n' \
  > "$SCRATCH/plugins/leadv2/scripts/tests/test-sr-filename-lock.sh"
printf '#!/usr/bin/env bash\n# run-all-triggers: selfreg-bare\nexit 0\n' \
  > "$SCRATCH/plugins/leadv2/scripts/tests/test-sr-bare-lock.sh"
# tracked sources (committed, then dirtied, to appear in the changed set)
printf '#!/usr/bin/env bash\n# mapped source (filename-form trigger)\n' > "$SCRATCH/plugins/leadv2/scripts/selfreg-filename.sh"
printf '#!/usr/bin/env bash\n# mapped source (bare-form trigger)\n' > "$SCRATCH/plugins/leadv2/scripts/selfreg-bare.sh"
printf '#!/usr/bin/env bash\n# unmapped control source\n' > "$SCRATCH/plugins/leadv2/scripts/selfreg-unmapped.sh"
git -C "$SCRATCH" add -A
git -C "$SCRATCH" -c user.email=t@t -c user.name=t commit -qm base

run_sel() { # <shell> -> [SELECT] lines on stdout, run-all rc as return code
  local _out _rc
  _out="$( cd "$SCRATCH" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
      LEADV2_RUN_ALL_SELECT_ONLY=1 \
      "$1" tests/run-all.sh --scope changed 2>&1 )"
  _rc=$?
  printf '%s' "$_out"
  return "$_rc"
}

# --- case A: filename-form trigger (key == stem.sh) ---------------------------
printf '# dirty\n' >> "$SCRATCH/plugins/leadv2/scripts/selfreg-filename.sh"
out="$(run_sel bash)"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s' "$out" | grep -q '\[SELECT\].*test-sr-filename-lock\.sh'; then
  pass "filename-form trigger: dirty selfreg-filename.sh selects test-sr-filename-lock.sh"
else
  fail "filename-form trigger NOT selected (rc=$rc); output:
$out"
fi
if printf '%s' "$out" | grep -q '\[SELECT\].*test-sr-bare-lock\.sh'; then
  fail "cross-selection: filename-form dirt also selected the bare-form suite (not attributable)"
else
  pass "attribution: filename-form dirt selects only its own suite"
fi
git -C "$SCRATCH" checkout -q -- plugins/leadv2/scripts/selfreg-filename.sh

# --- case B: bare-form trigger (key == stem) ----------------------------------
printf '# dirty\n' >> "$SCRATCH/plugins/leadv2/scripts/selfreg-bare.sh"
out="$(run_sel bash)"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s' "$out" | grep -q '\[SELECT\].*test-sr-bare-lock\.sh'; then
  pass "bare-form trigger: dirty selfreg-bare.sh selects test-sr-bare-lock.sh"
else
  fail "bare-form trigger NOT selected (rc=$rc); output:
$out"
fi
git -C "$SCRATCH" checkout -q -- plugins/leadv2/scripts/selfreg-bare.sh

# --- case C (negative control): unmapped stem selects neither -----------------
printf '# dirty\n' >> "$SCRATCH/plugins/leadv2/scripts/selfreg-unmapped.sh"
out="$(run_sel bash)"; rc=$?
if printf '%s' "$out" | grep -qE '\[SELECT\].*test-sr-(filename|bare)-lock\.sh'; then
  fail "negative control FAILED: unmapped stem selected a self-registered suite; output:
$out"
else
  pass "negative control: unmapped stem selects no self-registered suite"
fi
git -C "$SCRATCH" checkout -q -- plugins/leadv2/scripts/selfreg-unmapped.sh

# --- case D: bash/zsh agreement on selection (failing on disagreement) --------
printf '# dirty\n' >> "$SCRATCH/plugins/leadv2/scripts/selfreg-filename.sh"
printf '# dirty\n' >> "$SCRATCH/plugins/leadv2/scripts/selfreg-bare.sh"
out_b="$(run_sel bash)"; rc_b=$?
out_z="$(run_sel zsh)"; rc_z=$?
sel_b="$(printf '%s\n' "$out_b" | grep '^\[SELECT\]' | sort)"
sel_z="$(printf '%s\n' "$out_z" | grep '^\[SELECT\]' | sort)"
if [[ $rc_b -ne 0 || $rc_z -ne 0 ]]; then
  fail "bash/zsh agreement leg: non-zero rc (bash=$rc_b zsh=$rc_z); bash output:
$out_b
zsh output:
$out_z"
elif [[ -z "$sel_b" ]]; then
  fail "bash/zsh agreement leg: no [SELECT] lines captured; output:
$out_b"
elif [[ "$sel_b" != "$sel_z" ]]; then
  fail "bash/zsh DISAGREEMENT on selection:
bash:
$sel_b
zsh:
$sel_z"
else
  pass "bash/zsh agreement: identical selection sets ($(printf '%s\n' "$sel_b" | grep -c . ) lines)"
fi
git -C "$SCRATCH" checkout -q -- plugins/leadv2/scripts/selfreg-filename.sh plugins/leadv2/scripts/selfreg-bare.sh

# --- case E: list seam exposes discovered rows (ROOT-relative) ----------------
out="$( cd "$SCRATCH" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    env LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh --scope changed 2>&1 )"; rc=$?
if [[ $rc -eq 0 ]] \
   && printf '%s\n' "$out" | grep -qxF 'selfreg-bare:plugins/leadv2/scripts/tests/test-sr-bare-lock.sh' \
   && printf '%s\n' "$out" | grep -qxF 'selfreg-filename.sh:plugins/leadv2/scripts/tests/test-sr-filename-lock.sh'; then
  pass "list seam: LEADV2_RUN_ALL_LIST_TRIGGERS=1 prints discovered ROOT-relative rows"
else
  fail "list seam missing expected rows (rc=$rc); output:
$out"
fi

# --- case F: malformed declaration is a loud error, not a silent skip ---------
# F1: invalid character in a trigger (space is a SEPARATOR in the grammar, so
# the invalid-char probe must use a character that can never tokenize away)
printf '#!/usr/bin/env bash\n# run-all-triggers: selfreg/stem\nexit 0\n' \
  > "$SCRATCH/plugins/leadv2/scripts/tests/test-sr-bad.sh"
out="$(run_sel bash)"; rc=$?
if [[ $rc -eq 2 ]] && printf '%s' "$out" | grep -q 'bad_trigger_decl'; then
  pass "malformed declaration (invalid char 'selfreg/stem') -> exit 2 + bad_trigger_decl"
else
  fail "invalid-char declaration did not fail loudly (rc=$rc, expected 2); output:
$out"
fi
rm -f "$SCRATCH/plugins/leadv2/scripts/tests/test-sr-bad.sh"
# F2: declaration with no triggers at all
printf '#!/usr/bin/env bash\n# run-all-triggers:\nexit 0\n' \
  > "$SCRATCH/plugins/leadv2/scripts/tests/test-sr-empty.sh"
out="$(run_sel bash)"; rc=$?
if [[ $rc -eq 2 ]] && printf '%s' "$out" | grep -q 'declaration with no triggers'; then
  pass "malformed declaration (empty list) -> exit 2"
else
  fail "empty declaration did not fail loudly (rc=$rc, expected 2); output:
$out"
fi
rm -f "$SCRATCH/plugins/leadv2/scripts/tests/test-sr-empty.sh"
# restore check: with the malformed stubs gone the run is clean again
out="$(run_sel bash)"; rc=$?
if [[ $rc -eq 0 ]]; then
  pass "restore check: after removing malformed stubs run-all exits 0 again"
else
  fail "restore check: run-all still failing after malformed stubs removed (rc=$rc); output:
$out"
fi

# ── every scan root that holds a declared suite must appear in the map ───────
# SCAN-ROOT-CAN-BE-DROPPED-SILENTLY-01 (lead negative control, 2026-09-04).
# scan_suite_triggers() walks four roots. Removing one of them from that list
# is a parse-clean, behaviour-changing edit that this suite did not notice:
# dropping "${ROOT}/tests" took the discovered map from 2 rows pointing into
# tests/ to 0 — and the suite stayed 11/0. The suites that prove this whole
# feature (test-run-all-self-registration.sh, test-run-all-carrier-map.sh)
# live in exactly that root, so the silent failure mode is "CI stops selecting
# the tests that guard self-registration" with nothing red to say so.
#
# The assertion is deliberately derived, not hardcoded: for each root that
# exists AND contains at least one suite carrying a declaration, the map must
# carry at least one row pointing into that root. A new root needs no edit
# here; a dropped root reddens immediately.
MAP_OUT="$( env LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash "$RUN_ALL" 2>/dev/null )"
root_miss=""
root_checked=0
for _r in "plugins/leadv2/scripts/tests" ".claude/scripts/tests" "plugins/leadv2/tests" "tests"; do
  [[ -d "$ROOT/$_r" ]] || continue
  grep -lE '^# run-all-triggers:' "$ROOT/$_r"/test-*.sh >/dev/null 2>&1 || continue
  root_checked=$((root_checked + 1))
  if ! printf '%s\n' "$MAP_OUT" | grep -qE "^[^:]+:${_r}/"; then
    root_miss="${root_miss} ${_r}"
  fi
done
if [[ $root_checked -eq 0 ]]; then
  fail "scan roots: no root carries a declaration — discovery cannot be exercised at all"
elif [[ -z "$root_miss" ]]; then
  pass "scan roots: all $root_checked declaring root(s) contribute rows to the discovered map"
else
  fail "scan roots: declaring root(s) missing from the map:${root_miss} — scan_suite_triggers stopped walking a directory that holds declared suites"
fi

printf 'test-run-all-self-registration: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
