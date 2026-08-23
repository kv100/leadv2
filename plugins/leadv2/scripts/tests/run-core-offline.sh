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

# --- SUITE-SPEED-01 item 1: cross-run exclusive lock ------------------------
# Two concurrent run-core-offline.sh invocations (e.g. two lanes racing on the
# same machine) share /tmp fixtures and, more importantly, the same real repo
# working tree — the hermeticity post-condition below diffs `git status --
# docs/leadv2` around every suite, and a second run mutating that tree mid-diff
# manufactures a false HERMETIC-VIOLATION/FAIL that has nothing to do with the
# suite under test. An exclusive flock on a well-known file serializes runs
# instead. LEADV2_SUITE_LOCK_DISABLE=1 is the kill-switch (debugging, or a
# caller that has already serialized externally). Default wait is unbounded
# (matches "the lane should finish, not race") — set LEADV2_SUITE_LOCK_WAIT_S
# for a bounded wait (used by tests, and by any caller that prefers a fast
# failure to a long block).
LEADV2_SUITE_LOCK_DISABLE="${LEADV2_SUITE_LOCK_DISABLE:-0}"
LEADV2_SUITE_LOCK_FILE="${LEADV2_SUITE_LOCK_FILE:-/tmp/leadv2-core-offline.lock}"
# Pure introspection (lists the shard partition, runs nothing) never needs to
# serialize against a concurrent real run — skip the lock entirely for it.
if [[ "$LEADV2_SUITE_LOCK_DISABLE" != "1" && -z "${LEADV2_SUITE_SHARDS_DUMP:-}" ]]; then
  exec 9>"$LEADV2_SUITE_LOCK_FILE"
  if ! flock -n 9; then
    printf -- '[CORE-OFFLINE] waiting for lock file=%s (held by a concurrent run)\n' \
      "$LEADV2_SUITE_LOCK_FILE" >&2
    if [[ -n "${LEADV2_SUITE_LOCK_WAIT_S:-}" ]]; then
      if ! flock -w "$LEADV2_SUITE_LOCK_WAIT_S" 9; then
        printf -- '[CORE-OFFLINE] FATAL lock_timeout file=%s wait_s=%s\n' \
          "$LEADV2_SUITE_LOCK_FILE" "$LEADV2_SUITE_LOCK_WAIT_S" >&2
        exit 2
      fi
    else
      flock 9
    fi
  fi
fi

if [ -n "${LEADV2_SUITE_LOCK_PROBE:-}" ]; then
  printf -- '[CORE-OFFLINE] lock-probe acquired file=%s\n' "$LEADV2_SUITE_LOCK_FILE"
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

# Changing HOME changes Python's user-site lookup.  Retain the interpreter's
# already-selected user base while sandboxing ~/.claude, so offline suites can
# still import the dependencies installed for this interpreter (for example
# PyYAML) without inheriting live Claude state.
_CORE_OFFLINE_PYTHONUSERBASE="${PYTHONUSERBASE:-}"
if [[ -z "$_CORE_OFFLINE_PYTHONUSERBASE" ]] && command -v python3 >/dev/null 2>&1; then
  _CORE_OFFLINE_PYTHONUSERBASE="$(python3 -c 'import site; print(site.USER_BASE)' 2>/dev/null || true)"
fi

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
  "lanes snapshot reconciliation"
  "plugin sync .claude/scripts link classification"
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
  local suite_failed=0 suite_home=""
  # Shards execute independent suites concurrently.  TMPDIR alone cannot
  # isolate suites that use the conventional ~/.claude/cache state surface,
  # so give every sharded suite an otherwise-empty HOME rooted in its
  # already-private fixture directory.  Keep serial mode byte-for-byte and
  # environment-compatible with the pre-sharding runner.
  if [[ "${LEADV2_SUITE_SHARDS:-1}" -gt 1 ]]; then
    local suite_tmp
    suite_tmp="$(mktemp -d "$RUN_TMP/suite.XXXXXX")"
    suite_home="$suite_tmp/home"
    mkdir -p "$suite_home/.claude/cache"
  fi
  if [[ "${LEADV2_CORE_OFFLINE_NO_SCRUB:-0}" == "1" || "$1" != "bash" ]]; then
    # Function-based checks (syntax_all, validate_plugin) run in-process and
    # cannot be wrapped by `env` (a bash function is invisible to a new exec).
    cmd=("$@")
  else
    if [[ -n "$suite_home" ]]; then
      cmd=(env "${_CORE_OFFLINE_SCRUB_ARGS[@]}" "TMPDIR=$suite_tmp" "HOME=$suite_home" \
        "PYTHONUSERBASE=$_CORE_OFFLINE_PYTHONUSERBASE" "$@")
    else
      local suite_tmp
      suite_tmp="$(mktemp -d "$RUN_TMP/suite.XXXXXX")"
      cmd=(env "${_CORE_OFFLINE_SCRUB_ARGS[@]}" "TMPDIR=$suite_tmp" "$@")
    fi
  fi

  local cmd_rc=0
  if [[ -n "$suite_home" ]]; then
    HOME="$suite_home" PYTHONUSERBASE="$_CORE_OFFLINE_PYTHONUSERBASE" "${cmd[@]}" || cmd_rc=$?
  else
    "${cmd[@]}" || cmd_rc=$?
  fi
  if [[ "$cmd_rc" -eq 0 ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    suite_failed=1
    printf -- '[CORE-OFFLINE] FAILED: %s\n' "$name" >&2
  fi

  if [[ "${LEADV2_CORE_OFFLINE_HERMETIC_GATE}" == "1" ]]; then
    local _docs_after
    _docs_after="$(git -C "$REPO_ROOT" status --porcelain -- docs/leadv2 2>/dev/null || true)"
    if [[ "$_docs_after" != "$_docs_before" ]]; then
      if _core_offline_suite_is_owned "$name"; then
        FAIL=$((FAIL + 1))
        # A hermeticity failure is a suite failure too.  In shard mode logs
        # are replayed after workers exit, so retain the canonical FAILED
        # marker even when the command itself passed.
        if [[ "$suite_failed" -eq 0 ]]; then
          printf -- '[CORE-OFFLINE] FAILED: %s\n' "$name" >&2
        fi
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
# Record format: "name|||cmd...|||SERIAL".  SERIAL is optional and only changes
# sharded runs: marked suites run as a serial tail after every parallel shard
# has completed, while the outer flock is still held.  This protects suites
# whose dispatch fixtures intentionally write repository state.  In shards=1
# mode the marker is deliberately inert, preserving the original execution
# path and output.
# Commands are space-split (every path in this list is space-free, matching the
# assumption the rest of this plugin already makes).
SUITE_DEFS=(
  "all plugin shell syntax|||syntax_all"
  "portable temp helper stress|||bash $TEST_DIR/test-leadv2-temp-stress.sh"
  "Claude plugin manifest/components|||validate_plugin"
  "provider/model router|||bash $TEST_DIR/test-session-route.sh"
  "dispatch refusal fallback chain|||bash $TEST_DIR/test-routing-enforcement-p1.sh|||SERIAL"
  "product-close waits for worker exit|||bash $TEST_DIR/test-no-work-terminal.sh|||SERIAL"
  "product-close resumes a died-with-work lane once|||bash $TEST_DIR/test-dwr-resume.sh"
  "parked worker contract and one-shot resume (WORKER-PARKED-ON-BG-01)|||bash $TEST_DIR/test-parked-worker-resume.sh"
  "red-first pinned-baseline resolver (RED-FIRST-SELF-INVALIDATES-01)|||bash $TEST_DIR/test-red-first-baseline.sh"
  "product-close scopes a single-repo lane worktree|||bash $TEST_DIR/test-lane-diff-single-repo.sh"
  "Codex full-cycle runner|||bash $TEST_DIR/test-codex-session-runner.sh|||SERIAL"
  "Codex terminal lead intake|||bash $TEST_DIR/test-codex-lead-intake.sh"
  "Codex child-session recursion boundary|||bash $TEST_DIR/test-codex-child-session-boundary.sh"
  "autonomous session spawner|||bash $TEST_DIR/test-session-spawner.sh"
  "hook token + mode isolation|||bash $TEST_DIR/test-hook-token-mode-isolation.sh"
  "per-turn injection dedup (HOOK-INJECT-DEDUP-01)|||bash $TEST_DIR/test-inject-dedup.sh"
  "main model/live quota|||bash $TEST_DIR/test-main-model-check.sh"
  "active registry fail-closed|||bash $TEST_DIR/test-active-registry-failclosed.sh"
  "active registry phase updates|||bash $TEST_DIR/test-active-registry-update-phase.sh"
  "fanout classifier/runner guard|||bash $TEST_DIR/test-fanout-classify-guard.sh|||SERIAL"
  "lanes snapshot reconciliation|||bash $TEST_DIR/test-lanes-snapshot.sh|||SERIAL"
  "Phase-8 task schema|||bash $TEST_DIR/test-leadv2-phase8-assert-a2-schema.sh"
  "Phase-8 merge/completion proof|||bash $PLUGIN_ROOT/tests/test-deploy-merge-blocker-gate.sh"
  "subsession model downgrade|||bash $TEST_DIR/test-leadv2-model-arg-rebuild.sh"
  "subsession context diet (WORKER-CONTEXT-DIET-01)|||bash $TEST_DIR/test-subsession-context-diet.sh"
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
  "lane truth batch (log_path + quarantine convergence)|||bash $TEST_DIR/test-lane-truth-batch-01.sh|||SERIAL"
  "founder lane view|||bash $TEST_DIR/test-leadv2-lanes.sh"
  "plugin reliability (process liveness + role fallback + prepass/reorder signals)|||bash $TEST_DIR/test-plugin-reliability-01.sh"
  "plugin reliability-02 (zombie-reaper: run_dir arg + group signaling + ordering + TASK)|||bash $TEST_DIR/test-plugin-reliability-02.sh"
  "plan-followups-01|||bash $TEST_DIR/test-plan-followups-01.sh"
  "e2e gate arch-01 (lane-tree testing)|||bash $TEST_DIR/test-e2e-gate-arch-01.sh"
  "report-only gate (REPORT-ONLY-GATE-01: report lane deliverable)|||bash $TEST_DIR/test-report-only-gate.sh|||SERIAL"
  "builder selfcheck gate (recursion/depth guard, baseline attribution)|||bash $TEST_DIR/test-builder-selfcheck-gate.sh"
  "review round exhaustive/verify-only (REVIEW-ROUND1-EXHAUSTIVE-01)|||bash $TEST_DIR/test-review-round-exhaustive.sh"
  "review round cap (REVIEW-ROUNDCAP-01)|||bash $TEST_DIR/test-review-roundcap.sh"
  "claim-evidence gate (CLAIM-EVIDENCE-GATE-01 preamble + round-1 lens)|||bash $TEST_DIR/test-claim-evidence-gate.sh"
  "broad-status relay scoping|||bash $TEST_DIR/test-broad-status-relay-scope.sh"
  "deferred-GLM ladder (V3-GLM-LADDER-01)|||bash $TEST_DIR/test-glm-deferred-ladder.sh"
  "pump junk stays out of lane worktrees (V3-ENV-GUARDS-01)|||bash $TEST_DIR/test-pump-junk-in-lane.sh"
  "codex instant-complete dead-arm spill (V3-ENV-GUARDS-01)|||bash $TEST_DIR/test-codex-instant-complete.sh"
  "worker env asserts (V3-ENV-GUARDS-01)|||bash $TEST_DIR/test-worker-env-asserts.sh"
  "stop-gate autocommit on worker exit (V3-STOP-GATE-01)|||bash $TEST_DIR/test-stop-gate.sh|||SERIAL"
  "core-offline cross-run exclusive lock (SUITE-SPEED-01)|||bash $TEST_DIR/test-core-offline-lock-01.sh"
  "core-offline shard partition (SUITE-SPEED-01)|||bash $TEST_DIR/test-core-offline-shards-01.sh"
  "core-offline per-suite TMPDIR isolation (SUITE-SPEED-01)|||bash $TEST_DIR/test-core-offline-tmpdir-01.sh"
  "silent-arm commits-ahead + live-worker guard (GATE-FALSE-SILENT-01)|||bash $TEST_DIR/test-silent-arm-commits-ahead.sh"
  "plugin sync .claude/scripts link classification|||bash $TEST_DIR/test-plugin-sync-claude-scripts.sh"
  "lane trace instrument (Mission B: writer/concurrency/off-path/reader)|||bash $TEST_DIR/test-leadv2-trace.sh"
  "burn governor (BURN-GOVERNOR-01: 24h burn gate)|||bash $TEST_DIR/test-burn-governor.sh|||SERIAL"
)

# Runner-mechanics test hook (SUITE-SPEED-01): a caller may substitute the
# whole SUITE_DEFS list with a newline-separated "name|||cmd" list of its own,
# so tests can exercise run_check's isolation/locking/sharding machinery
# against tiny fake suites instead of the real (slow) 57. Never used outside
# tests — production callers never set this.
if [[ -n "${LEADV2_SUITE_DEFS_OVERRIDE:-}" ]]; then
  SUITE_DEFS=()
  while IFS= read -r _override_line; do
    [[ -n "$_override_line" ]] || continue
    SUITE_DEFS+=("$_override_line")
  done <<< "$LEADV2_SUITE_DEFS_OVERRIDE"
fi

_core_offline_run_entry() {
  local entry="$1" name rest cmd_str
  name="${entry%%|||*}"
  rest="${entry#*|||}"
  cmd_str="${rest%%|||*}"
  # shellcheck disable=SC2086
  # Intentional word-splitting; every path here is space-free (the same
  # assumption the rest of this plugin already makes).
  run_check "$name" $cmd_str
}

_core_offline_entry_is_serial() {
  local entry="$1" rest marker
  [[ "$entry" == *'|||'*'|||'* ]] || return 1
  rest="${entry#*|||}"
  marker="${rest#*|||}"
  [[ "$marker" == "SERIAL" ]]
}

# --- SUITE-SPEED-01 item 3: sharding -----------------------------------------
# Suite indices are partitioned round-robin (idx % shards == shard_id) so the
# partition is a pure function of SUITE_DEFS order — deterministic regardless
# of how many shards run, and trivial to unit-test without executing suites
# (LEADV2_SUITE_SHARDS_DUMP=1 below).
#
# shards<=1 keeps the exact pre-sharding code path (no subshell, no result
# line, no reordering) so serial output stays byte-for-byte identical to
# before this change — that is the "shards=1 == today" parity requirement.
_core_offline_default_shards() {
  local n
  n="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  if ! [[ "$n" =~ ^[0-9]+$ ]]; then
    n="$(sysctl -n hw.ncpu 2>/dev/null || true)"
  fi
  [[ "$n" =~ ^[0-9]+$ ]] || n=1
  (( n > 4 )) && n=4
  (( n < 1 )) && n=1
  printf '%d' "$n"
}
LEADV2_SUITE_SHARDS="${LEADV2_SUITE_SHARDS:-$(_core_offline_default_shards)}"
if ! [[ "$LEADV2_SUITE_SHARDS" =~ ^[0-9]+$ ]] || [[ "$LEADV2_SUITE_SHARDS" -lt 1 ]]; then
  LEADV2_SUITE_SHARDS=1
fi

if [[ -n "${LEADV2_SUITE_SHARDS_DUMP:-}" ]]; then
  for (( _s = 0; _s < LEADV2_SUITE_SHARDS; _s++ )); do
    for (( _i = 0; _i < ${#SUITE_DEFS[@]}; _i++ )); do
      if (( _i % LEADV2_SUITE_SHARDS == _s )) \
        && { [[ "$LEADV2_SUITE_SHARDS" -le 1 ]] || ! _core_offline_entry_is_serial "${SUITE_DEFS[_i]}"; }; then
        printf -- 'shard=%d idx=%d name=%s\n' "$_s" "$_i" "${SUITE_DEFS[_i]%%|||*}"
      fi
    done
  done
  if [[ "$LEADV2_SUITE_SHARDS" -gt 1 ]]; then
    for (( _i = 0; _i < ${#SUITE_DEFS[@]}; _i++ )); do
      if _core_offline_entry_is_serial "${SUITE_DEFS[_i]}"; then
        printf -- 'serial idx=%d name=%s\n' "$_i" "${SUITE_DEFS[_i]%%|||*}"
      fi
    done
  fi
  exit 0
fi

_core_offline_run_shard() {
  local total="$1" idx="$2" n=0
  local -a order
  if [[ "${LEADV2_CORE_OFFLINE_REVERSE:-0}" == "1" ]]; then
    for (( _i = ${#SUITE_DEFS[@]} - 1; _i >= 0; _i-- )); do order+=("$_i"); done
  else
    for (( _i = 0; _i < ${#SUITE_DEFS[@]}; _i++ )); do order+=("$_i"); done
  fi
  for _i in "${order[@]}"; do
    if (( _i % total == idx )) && ! _core_offline_entry_is_serial "${SUITE_DEFS[_i]}"; then
      _core_offline_run_entry "${SUITE_DEFS[_i]}"
    fi
    n=$((n + 1))
  done
}

if [[ "$LEADV2_SUITE_SHARDS" -le 1 ]]; then
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
else
  printf -- '[CORE-OFFLINE] running %d suites across %d shards\n' \
    "${#SUITE_DEFS[@]}" "$LEADV2_SUITE_SHARDS"
  SHARD_LOGS=()
  for (( _s = 0; _s < LEADV2_SUITE_SHARDS; _s++ )); do
    shard_log="$RUN_TMP/shard-$_s.log"
    SHARD_LOGS+=("$shard_log")
    (
      PASS=0
      FAIL=0
      MISSING=0
      _core_offline_run_shard "$LEADV2_SUITE_SHARDS" "$_s"
      printf -- '[CORE-OFFLINE] SHARD_RESULT idx=%d pass=%d fail=%d missing=%d\n' \
        "$_s" "$PASS" "$FAIL" "$MISSING"
    ) >"$shard_log" 2>&1 &
  done
  wait
  for _log in "${SHARD_LOGS[@]}"; do
    cat "$_log"
  done
  serial_log="$RUN_TMP/serial-tail.log"
  (
    PASS=0
    FAIL=0
    MISSING=0
    for (( _i = 0; _i < ${#SUITE_DEFS[@]}; _i++ )); do
      if _core_offline_entry_is_serial "${SUITE_DEFS[_i]}"; then
        _core_offline_run_entry "${SUITE_DEFS[_i]}"
      fi
    done
    printf -- '[CORE-OFFLINE] SHARD_RESULT idx=serial pass=%d fail=%d missing=%d\n' \
      "$PASS" "$FAIL" "$MISSING"
  ) >"$serial_log" 2>&1
  cat "$serial_log"
  SHARD_LOGS+=("$serial_log")
  while IFS= read -r _line; do
    _p="$(printf '%s' "$_line" | sed -n 's/.*pass=\([0-9]*\).*/\1/p')"
    _f="$(printf '%s' "$_line" | sed -n 's/.*fail=\([0-9]*\).*/\1/p')"
    _m="$(printf '%s' "$_line" | sed -n 's/.*missing=\([0-9]*\).*/\1/p')"
    PASS=$((PASS + _p))
    FAIL=$((FAIL + _f))
    MISSING=$((MISSING + _m))
  done < <(grep -h 'SHARD_RESULT' "${SHARD_LOGS[@]}")
fi

printf -- '\n[CORE-OFFLINE] suites passed=%d failed=%d missing=%d repo=%s\n' "$PASS" "$FAIL" "$MISSING" "$REPO_ROOT"
(( FAIL == 0 && MISSING == 0 ))
