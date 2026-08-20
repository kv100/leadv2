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

# --- CRITICAL-1 round-2: env scrub + per-suite TMPDIR --------------------
# Suites share three real surfaces across a single run_check invocation: (1)
# the runner's own inherited environment (any LEADV2_*/CLAUDE_*/DRY_RUN/GIT_*
# exported by the operator's shell is visible to every suite below), (2) the
# real $HOME state tree (~/.claude/cache/*), and (3) the real repo working
# tree (docs/leadv2/**). This is the only mechanism that explains "passes
# twice standalone, fails inside the full runner" without any suite writing
# to another. Scrub (1) here; (2)/(3) are covered per-suite by their own
# LEADV2_*_DIR/_FILE overrides (drift-guard, codex-session-runner,
# routing-enforcement-p1) and by the hermeticity post-condition below.
#
# Denylist, not `env -i`: an allowlist-only environment would red suites that
# legitimately depend on inherited PATH/python site paths, and this lane must
# not manufacture new reds. LEADV2_CORE_OFFLINE_NO_SCRUB=1 disables the scrub
# entirely, so a future debugger can reproduce leaky behaviour on purpose.
_CORE_OFFLINE_SCRUB_ARGS=()
_core_offline_build_scrub_args() {
  local v
  for v in DRY_RUN GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE PROJECT_ROOT; do
    _CORE_OFFLINE_SCRUB_ARGS+=(-u "$v")
  done
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    case "$v" in
      LEADV2_*|CLAUDE_*|GIT_CONFIG*) _CORE_OFFLINE_SCRUB_ARGS+=(-u "$v") ;;
    esac
  done < <(compgen -e 2>/dev/null || true)
}
_core_offline_build_scrub_args

RUN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/core-offline-run.XXXXXX")"
trap 'rm -rf "$RUN_TMP"' EXIT

# --- MEDIUM-1 round-2: hermeticity post-condition -------------------------
# A lane must not manufacture reds in suites it did not touch: FAIL only for
# suites this lane owns; WARN + verbatim report for everything else.
# Untracked residue under docs/leadv2 pre-dates this lane and is out of scope
# (only tracked modifications are compared).
LEADV2_CORE_OFFLINE_HERMETIC_GATE="${LEADV2_CORE_OFFLINE_HERMETIC_GATE:-1}"
_CORE_OFFLINE_OWNED_SUITES=(
  "plugin sync quarantine/dry-run safety"
  "foreground-dispatch guard hook"
  "dispatch refusal fallback chain"
  "lane truth batch (log_path + quarantine convergence)"
  "Codex full-cycle runner"
  "product-close waits for worker exit"
  "supervisor reconciliation"
)
_core_offline_suite_is_owned() {
  local name="$1" o
  for o in "${_CORE_OFFLINE_OWNED_SUITES[@]}"; do
    [[ "$name" == "$o" ]] && return 0
  done
  return 1
}

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

  local _docs_before=""
  if [[ "${LEADV2_CORE_OFFLINE_HERMETIC_GATE}" == "1" ]]; then
    _docs_before="$(git -C "$REPO_ROOT" status --porcelain -- docs/leadv2 2>/dev/null || true)"
  fi

  local -a cmd
  if [[ "${LEADV2_CORE_OFFLINE_NO_SCRUB:-0}" == "1" || "$1" != "bash" ]]; then
    # Function-based checks (syntax_all, validate_plugin) run in-process and
    # cannot be wrapped by `env` (a bash function is invisible to a new exec).
    cmd=("$@")
  else
    local suite_tmp
    suite_tmp="$(mktemp -d "$RUN_TMP/suite.XXXXXX")"
    cmd=(env "${_CORE_OFFLINE_SCRUB_ARGS[@]}" "TMPDIR=$suite_tmp" "$@")
  fi

  if "${cmd[@]}"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf -- '[CORE-OFFLINE] FAILED: %s\n' "$name" >&2
  fi

  if [[ "${LEADV2_CORE_OFFLINE_HERMETIC_GATE}" == "1" ]]; then
    local _docs_after
    _docs_after="$(git -C "$REPO_ROOT" status --porcelain -- docs/leadv2 2>/dev/null || true)"
    if [[ "$_docs_after" != "$_docs_before" ]]; then
      if _core_offline_suite_is_owned "$name"; then
        FAIL=$((FAIL + 1))
        printf -- '[CORE-OFFLINE] HERMETIC-VIOLATION (FAIL, lane-owned): %s dirtied docs/leadv2:\n%s\n' \
          "$name" "$_docs_after" >&2
      else
        printf -- '[CORE-OFFLINE] HERMETIC-VIOLATION (WARN, follow-up): %s dirtied docs/leadv2:\n%s\n' \
          "$name" "$_docs_after" >&2
      fi
    fi
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

# --- CRITICAL-1 round-2: ordering falsification ---------------------------
# Suites are a data list (not a flat sequence of calls) so LEADV2_CORE_OFFLINE_REVERSE=1
# can walk them back-to-front. If 50/0 holds forward, reverse, and forward-again,
# order-dependence is disproven by construction rather than by two identical runs.
# Record format: "name|||cmd..." — cmd is space-split (every path in this list is
# space-free, matching the assumption the rest of this plugin already makes).
SUITE_DEFS=(
  "all plugin shell syntax|||syntax_all"
  "portable temp helper stress|||bash $TEST_DIR/test-leadv2-temp-stress.sh"
  "Claude plugin manifest/components|||validate_plugin"
  "provider/model router|||bash $TEST_DIR/test-session-route.sh"
  "dispatch refusal fallback chain|||bash $TEST_DIR/test-routing-enforcement-p1.sh"
  "product-close waits for worker exit|||bash $TEST_DIR/test-no-work-terminal.sh"
  "product-close resumes a died-with-work lane once|||bash $TEST_DIR/test-dwr-resume.sh"
  "product-close scopes a single-repo lane worktree|||bash $TEST_DIR/test-lane-diff-single-repo.sh"
  "Codex full-cycle runner|||bash $TEST_DIR/test-codex-session-runner.sh"
  "Codex terminal lead intake|||bash $TEST_DIR/test-codex-lead-intake.sh"
  "Codex child-session recursion boundary|||bash $TEST_DIR/test-codex-child-session-boundary.sh"
  "autonomous session spawner|||bash $TEST_DIR/test-session-spawner.sh"
  "hook token + mode isolation|||bash $TEST_DIR/test-hook-token-mode-isolation.sh"
  "main model/live quota|||bash $TEST_DIR/test-main-model-check.sh"
  "active registry fail-closed|||bash $TEST_DIR/test-active-registry-failclosed.sh"
  "active registry phase updates|||bash $TEST_DIR/test-active-registry-update-phase.sh"
  "fanout classifier/runner guard|||bash $TEST_DIR/test-fanout-classify-guard.sh"
  "supervisor fail-closed|||bash $TEST_DIR/test-supervise-failclosed.sh"
  "supervisor reconciliation|||bash $TEST_DIR/test-supervise-v2.sh"
  "supervisor/lead PID isolation|||bash $PLUGIN_ROOT/tests/test-supervise-fanout-guard.sh"
  "Phase-8 task schema|||bash $TEST_DIR/test-leadv2-phase8-assert-a2-schema.sh"
  "Phase-8 merge/completion proof|||bash $PLUGIN_ROOT/tests/test-deploy-merge-blocker-gate.sh"
  "subsession model downgrade|||bash $TEST_DIR/test-leadv2-model-arg-rebuild.sh"
  "plugin sync quarantine/dry-run safety|||bash $TEST_DIR/test-drift-guard-quarantine-perimeter.sh"
  "skill lint|||bash $TEST_DIR/test-leadv2-skill-lint.sh"
  "skill proof gate unit tests|||bash $TEST_DIR/test-skill-proof-gate.sh"
  "status surface single-lead + census|||bash $REPO_ROOT/tests/test-status-surface-single-lead.sh"
  "reply router dual-store resolution|||bash $TEST_DIR/test-reply-router-01.sh"
  "question delivery ownership|||bash $TEST_DIR/test-question-delivery-ownership-01.sh"
  "landed-at-spawn (no terminal=landed at spawn; target repo keying)|||bash $TEST_DIR/test-landed-at-spawn.sh"
  "lane placement pin (--resume-lane/--worktree)|||bash $TEST_DIR/test-lane-placement-pin.sh"
  "Codex quota guardrails (effort/circuit/hook)|||bash $TEST_DIR/test-codex-quota-guardrails.sh"
  "e2e gate lane root + suite family|||bash $TEST_DIR/test-e2e-gate-lane-root.sh"
  "review body persist (opus/sonnet materialisation + body_lost guard)|||bash $TEST_DIR/test-review-body-persist.sh"
  "review codex base (committed lane never diffs HEAD↔HEAD)|||bash $TEST_DIR/test-review-codex-base.sh"
  "quota stand-down duration (record-quota-lockout --hours)|||bash $TEST_DIR/test-quota-standdown-duration.sh"
  "core-offline root arithmetic (git-derived REPO_ROOT)|||bash $TEST_DIR/test-core-offline-root-arith.sh"
  "dispatch arm vocabulary (kimi retirement)|||bash $TEST_DIR/test-dispatch-arm-vocabulary.sh"
  "foreground-dispatch guard hook|||bash $TEST_DIR/test-fg-dispatch-guard.sh"
  "idle-lead guard hook|||bash $TEST_DIR/test-idle-lead-guard.sh"
  "phase record round-trip|||bash $TEST_DIR/test-phase-record.sh"
  "phase precondition guard matrix|||bash $TEST_DIR/test-phase-precondition.sh"
  "lane phase render|||bash $TEST_DIR/test-lane-phase-render.sh"
  "lane truth batch (log_path + quarantine convergence)|||bash $TEST_DIR/test-lane-truth-batch-01.sh"
  "founder lane view|||bash $TEST_DIR/test-leadv2-lanes.sh"
  "plugin reliability (process liveness + role fallback + prepass/reorder signals)|||bash $TEST_DIR/test-plugin-reliability-01.sh"
  "plugin reliability-02 (zombie-reaper: run_dir arg + group signaling + ordering + TASK)|||bash $TEST_DIR/test-plugin-reliability-02.sh"
  "plan-followups-01|||bash $TEST_DIR/test-plan-followups-01.sh"
  "e2e gate arch-01 (lane-tree testing)|||bash $TEST_DIR/test-e2e-gate-arch-01.sh"
  "report-only gate (REPORT-ONLY-GATE-01: report lane deliverable)|||bash $TEST_DIR/test-report-only-gate.sh"
  "review round exhaustive/verify-only (REVIEW-ROUND1-EXHAUSTIVE-01)|||bash $TEST_DIR/test-review-round-exhaustive.sh"
  "claim-evidence gate (CLAIM-EVIDENCE-GATE-01 preamble + round-1 lens)|||bash $TEST_DIR/test-claim-evidence-gate.sh"
  "broad-status relay scoping|||bash $TEST_DIR/test-broad-status-relay-scope.sh"
  "deferred-GLM ladder (V3-GLM-LADDER-01)|||bash $TEST_DIR/test-glm-deferred-ladder.sh"
)

_core_offline_run_entry() {
  local entry="$1" name cmd_str
  name="${entry%%|||*}"
  cmd_str="${entry#*|||}"
  # shellcheck disable=SC2086
  # Intentional word-splitting; every path here is space-free (the same
  # assumption the rest of this plugin already makes).
  run_check "$name" $cmd_str
}

if [[ "${LEADV2_CORE_OFFLINE_REVERSE:-0}" == "1" ]]; then
  printf -- '[CORE-OFFLINE] LEADV2_CORE_OFFLINE_REVERSE=1: running suite list back-to-front\n'
  for (( _i = ${#SUITE_DEFS[@]} - 1; _i >= 0; _i-- )); do
    _core_offline_run_entry "${SUITE_DEFS[_i]}"
  done
else
  for _entry in "${SUITE_DEFS[@]}"; do
    _core_offline_run_entry "$_entry"
  done
fi

printf -- '\n[CORE-OFFLINE] suites passed=%d failed=%d missing=%d repo=%s\n' "$PASS" "$FAIL" "$MISSING" "$REPO_ROOT"
(( FAIL == 0 && MISSING == 0 ))
