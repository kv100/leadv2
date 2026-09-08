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

# --- E2E-GATE-RUNS-ALL-94-SUITES...-01: --scope contract ---------------------
# tests/run-all.sh (and persona-engine's) implement `--scope changed|all`; the
# phase-8 gate appends `--scope changed` to whatever leadv2-e2e-entrypoint.sh
# resolves. Until 2026-09-07 this runner parsed NO arguments at all, so the
# flag was silently discarded and every gate run executed all 94 suites
# (measured: lane d2823c51e670, a 4-file diff, parked e2e_timeout rc=124 after
# 900 s). Three rules bind the implementation below, in priority order:
#   1. Fail OPEN when coverage is unknown (no base ref, git failure, an
#      unmapped file): run EVERYTHING and say why. Narrow cf03dd6a's original
#      rule only for a known empty relevant diff: run nothing and explicitly
#      report verdict=nothing_to_run. This proves no suites passed; rejecting
#      a lane that produced nothing is a separate review/close responsibility.
#   2. Say what it narrowed to, and why: suite count AND reason, every run.
#      A gate whose only output in 900 s is one line is undiagnosable -- that
#      is how this defect survived.
#   3. An unknown argument is a loud error (exit 2), never a silent no-op.
#      Silent arg-dropping is what let the gate claim a narrowed run for weeks.
# The changed-file -> suite mapping reuses run-all's own mechanism (`#
# run-all-triggers:` self-registration + EXTRA_SUITE_MAP rows, both literal
# forms), so a suite registers its triggers in exactly ONE place no matter
# which runner executes it. No argument at all keeps today's behaviour: the
# full set, byte-for-byte.
CORE_OFFLINE_SCOPE=""
# The parser below SHIFTS the positional params away, so the original argv is
# saved FIRST: the flock re-exec further down must forward it verbatim — the
# locked child is the process that actually runs the suites, and re-parsing
# there is idempotent.
CORE_OFFLINE_ORIG_ARGS=("$@")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      if [[ $# -lt 2 ]]; then
        printf -- 'run-core-offline: --scope requires a value (changed|all)\n' >&2
        exit 2
      fi
      CORE_OFFLINE_SCOPE="$2"; shift 2 ;;
    --scope=*)
      CORE_OFFLINE_SCOPE="${1#--scope=}"; shift ;;
    -h|--help)
      printf -- 'usage: run-core-offline.sh [--scope changed|all]\n' \
        '  (no arguments: the full curated set — the pre-scope behaviour)\n' >&2
      exit 0 ;;
    *)
      printf -- 'run-core-offline: unknown argument: %s\n' "$1" >&2
      exit 2 ;;
  esac
done
case "$CORE_OFFLINE_SCOPE" in
  ''|all|changed) ;;
  *)
    printf -- 'run-core-offline: --scope must be changed|all (got %s)\n' "$CORE_OFFLINE_SCOPE" >&2
    exit 2 ;;
esac

if [ -n "${LEADV2_CORE_OFFLINE_PROBE:-}" ]; then
  printf -- '[CORE-OFFLINE] probe LOGICAL_DIR=%s REPO_ROOT=%s PLUGIN_ROOT=%s TEST_DIR=%s\n' \
    "$LOGICAL_DIR" "$REPO_ROOT" "$PLUGIN_ROOT" "$TEST_DIR"
  exit 0
fi

# --- SUITE-SPEED-01 item 1 / SUITE-LOCK-IS-MACHINE-WIDE-01: cross-run lock --
# Two concurrent run-core-offline.sh invocations inside the SAME working tree
# share /tmp fixtures and, more importantly, that one repo working tree — the
# hermeticity post-condition below diffs `git status -- docs/leadv2` around
# every suite, and a second run mutating that SAME tree mid-diff manufactures
# a false HERMETIC-VIOLATION/FAIL that has nothing to do with the suite under
# test. An exclusive flock serializes runs instead.
#
# The lock protects exactly one thing: REPO_ROOT's own docs/leadv2 working
# tree. It does NOT protect any resource shared across worktrees, so it must
# be scoped to REPO_ROOT, never to a single machine-wide path. A hardcoded
# /tmp/leadv2-core-offline.lock (pre-SUITE-LOCK-IS-MACHINE-WIDE-01) made every
# concurrent lane on the box -- each in its OWN worktree, each diffing its OWN
# docs/leadv2 -- queue behind one runner regardless of worktree: N lanes did
# not run concurrently, one ran and N-1 blocked until their own dispatch
# timeout killed them with no diagnosis. Measured 2026-08-31: 45 lanes hit
# this "waiting for lock" line before this fix; do not restore the shared
# literal path (that is the regression this comment exists to prevent).
#
# LEADV2_SUITE_LOCK_DISABLE=1 is the kill-switch (debugging, or a caller that
# has already serialized externally). LEADV2_SUITE_LOCK_WAIT_S bounds the
# wait (default below) -- a run that cannot acquire within budget fails
# loudly instead of hanging until an external watchdog kills it with no
# reason recorded anywhere (that silent-kill is what six lanes looked like
# on 2026-08-31 before this default existed).
LEADV2_SUITE_LOCK_DISABLE="${LEADV2_SUITE_LOCK_DISABLE:-0}"
LEADV2_SUITE_LOCK_WAIT_S="${LEADV2_SUITE_LOCK_WAIT_S:-600}"

# TESTS-POLLUTE-REAL-JOURNAL-01 §1: mark this whole subtree as a test so the
# shared-state writers (leadv2-event.sh, lib/leadv2-freepool-gate.sh record)
# refuse unredirected writes to the real journal / freepool arm-state file —
# the fast path for lib/leadv2-test-context.sh's own detection (its ancestor
# walk already catches a suite invoked directly with nothing exported).
export LEADV2_TEST_CONTEXT="${LEADV2_TEST_CONTEXT:-1}"
# bash-3.2-safe slug: no external hashing tool needed for the default case,
# and no `${var//pat/rep}` surprises across worktree paths that only differ
# by non-alnum characters (still enough entropy to keep worktrees distinct —
# collisions would require two DIFFERENT worktree paths reducing to the same
# alnum skeleton, which none of this plugin's lane paths do:
# .claude/worktrees/<LANE-NAME>).
_core_offline_lock_slug() {
  local s="$1"
  s="${s//[^A-Za-z0-9]/-}"
  printf '%s' "$s"
}
LEADV2_SUITE_LOCK_FILE="${LEADV2_SUITE_LOCK_FILE:-/tmp/leadv2-core-offline-$(_core_offline_lock_slug "$REPO_ROOT").lock}"
# --- SUITE-LOCK-ORPHAN-FD-04: the lock fd must NOT survive into a child -----
# `exec 9<>"$LOCK"` (the old approach) leaves fd 9 open across every `fork`
# AND every `exec` this process performs, so any child that outlives this run
# -- a background worker reparented to launchd after the run is killed --
# keeps the flock held forever (measured 2026-08-31: 47 such orphans, some
# holding the lock for 15+ minutes with ppid=1). Bash has no builtin to mark
# a manually-opened fd close-on-exec, so instead of holding fd 9 in THIS
# process we hand the whole rest of this script to `flock ... -o <lockfile>
# <command>`: flock's own `-o/--close` closes ITS internal lock fd before
# exec'ing <command>, so <command> (the re-exec'd copy of this very script,
# marked via _LV2_CORE_OFFLINE_LOCK_HELD=1) and everything IT ever forks
# never has the fd at all -- there is nothing left for an orphan to inherit.
# The lock is then held solely by the `flock` process; killing that process
# (however it dies) releases the lock immediately and unconditionally, which
# is exactly the "process whose exit is guaranteed to release it" property
# fd-inheritance cannot give us. Verified live on this machine: a run whose
# child was left running as an orphan (ppid=1) held no fd on the lock file
# (`lsof <lockfile>` empty) and a fresh run acquired immediately.
#
# `-E 99` picks an exit code no suite-body outcome can ever produce (bodies
# exit 0/1/2 -- see EOF) so "flock could not acquire" is unambiguous against
# "the wrapped run legitimately exited with that code".
#
# Pure introspection (lists the shard partition, resolves the scope, runs
# nothing) never needs to serialize against a concurrent real run — skip the
# lock entirely for it.
if [[ "$LEADV2_SUITE_LOCK_DISABLE" != "1" && -z "${LEADV2_SUITE_SHARDS_DUMP:-}" \
  && -z "${LEADV2_CORE_OFFLINE_SCOPE_DUMP:-}" \
  && "${_LV2_CORE_OFFLINE_LOCK_HELD:-0}" != "1" ]]; then
  # CORE_OFFLINE_ORIG_ARGS (saved before the parser shifted $@ away) is
  # forwarded on both re-execs below: the locked child is the process that
  # actually runs the suites, so dropping the arguments here would silently
  # un-scope every real (lock-taking) invocation — the exact silent-arg-
  # dropping this file's --scope contract exists to end.
  if flock -x -n -E 99 -o "$LEADV2_SUITE_LOCK_FILE" \
    env _LV2_CORE_OFFLINE_LOCK_HELD=1 bash "${BASH_SOURCE[0]}" ${CORE_OFFLINE_ORIG_ARGS[@]+"${CORE_OFFLINE_ORIG_ARGS[@]}"}; then
    exit 0
  else
    _lock_rc=$?
  fi
  if [[ "$_lock_rc" != 99 ]]; then
    exit "$_lock_rc"
  fi
  _lock_holder="$(cat "$LEADV2_SUITE_LOCK_FILE" 2>/dev/null || true)"
  printf -- '[CORE-OFFLINE] waiting for lock file=%s holder=%s (held by a concurrent run)\n' \
    "$LEADV2_SUITE_LOCK_FILE" "${_lock_holder:-<unknown>}" >&2
  if flock -x -w "$LEADV2_SUITE_LOCK_WAIT_S" -E 99 -o "$LEADV2_SUITE_LOCK_FILE" \
    env _LV2_CORE_OFFLINE_LOCK_HELD=1 bash "${BASH_SOURCE[0]}" ${CORE_OFFLINE_ORIG_ARGS[@]+"${CORE_OFFLINE_ORIG_ARGS[@]}"}; then
    exit 0
  else
    _lock_rc2=$?
  fi
  if [[ "$_lock_rc2" == 99 ]]; then
    _lock_holder="$(cat "$LEADV2_SUITE_LOCK_FILE" 2>/dev/null || true)"
    printf -- '[CORE-OFFLINE] FATAL lock_timeout file=%s wait_s=%s holder=%s\n' \
      "$LEADV2_SUITE_LOCK_FILE" "$LEADV2_SUITE_LOCK_WAIT_S" "${_lock_holder:-<unknown>}" >&2
    exit 2
  fi
  exit "$_lock_rc2"
fi

if [[ "${_LV2_CORE_OFFLINE_LOCK_HELD:-0}" == "1" ]]; then
  # We now hold the lock (immediately or after waiting) -- stamp holder info
  # for the NEXT contender to read and report. This is a plain overwrite of
  # the file's CONTENT on a fresh fd, unrelated to the fd `flock` itself
  # holds the lock on -- it does not touch that lock.
  printf 'pid=%s host=%s since=%s\n' "$$" "$(hostname 2>/dev/null || printf unknown)" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$LEADV2_SUITE_LOCK_FILE" 2>/dev/null || true
fi

if [ -n "${LEADV2_SUITE_LOCK_PROBE:-}" ]; then
  printf -- '[CORE-OFFLINE] lock-probe acquired file=%s\n' "$LEADV2_SUITE_LOCK_FILE"
  exit 0
fi

# Test-only hook (SUITE-LOCK-ORPHAN-FD-04): simulate the incident shape --
# this run forks a long-lived child, then dies before ever reaching real
# suite execution (mirrors a lane killed right after a worker spawn). Never
# set by a real caller; test-suite-lock-scope.sh uses it to prove the
# orphaned child does not keep holding the lock.
if [ -n "${LEADV2_SUITE_LOCK_ORPHAN_TEST_SLEEP_S:-}" ]; then
  sleep "$LEADV2_SUITE_LOCK_ORPHAN_TEST_SLEEP_S" &
  printf -- '[CORE-OFFLINE] orphan-test child spawned pid=%s\n' "$!"
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
  "plugin sync contracts write gate"
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
    # TWELVE-LINUX-ONLY-SUITES-01: the only validation seam is
    # `claude plugin validate`, which needs the claude CLI -- not installed on
    # ubuntu-latest CI runners. SKIP cleanly with a stated reason (the
    # test-status-surface-bash32.sh pattern), never a hollow pass: the suite
    # still runs (and validates) anywhere the CLI exists, e.g. macOS.
    printf -- '[CORE-OFFLINE] SKIP: claude plugin manifest/components -- claude CLI unavailable on this platform; validation cannot run\n' >&2
    return 0
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
#
# E2E-GATE-BROKE-TODAY-01 round 2 moved 4 of the original 11 |||SERIAL markers
# into the parallel pool; a lead pass on 2026-09-04 re-derived the remaining 7 by
# BEHAVIOUR and moved 4 more, leaving 3.
#
# Method (and the reason the earlier justifications did not survive): each of the
# 7 was run ALONE in an isolated worktree under /private/tmp -- never /tmp, whose
# macOS symlink trips run-all.sh's root_escape guard and aborts the run before
# selection -- with `git status -- docs/leadv2` taken before and after. The probe
# was shown able to report DIRTY on a synthetic write before any "clean" from it
# was believed.
#
#   green + clean, moved to the pool: test-no-work-terminal, test-lanes-snapshot,
#     test-stop-gate, test-codex-session-runner (its rc=1 is its own defect,
#     tracked separately -- a broken suite is not a placement reason).
#   dirty, still SERIAL: test-routing-enforcement-p1, test-lane-truth-batch-01,
#     test-burn-governor. All three dirty the SAME path,
#     docs/leadv2/open-threads.md, and none of them writes it directly.
#
# The round-2 reasons cited membership in _CORE_OFFLINE_OWNED_SUITES. That list
# is read in exactly one place (run_check ~296) and sets the SEVERITY of a
# hermeticity violation -- owned means FAIL rather than WARN -- never placement.
# It says what happens IF a suite dirties the tree; it does not say that one does.
# A borrowed justification: the citation is real, the document is real, and the
# proposition it was needed for is not in it. The real reason is a conjunction --
# "dirties the shared tree AND its violations are fatal" -- and the list only ever
# supplied the second half.
#
SUITE_DEFS=(
  "all plugin shell syntax|||syntax_all"
  "portable temp helper stress|||bash $TEST_DIR/test-leadv2-temp-stress.sh"
  "Claude plugin manifest/components|||validate_plugin"
  "provider/model router|||bash $TEST_DIR/test-session-route.sh"
  # serial (measured 2026-09-04, run alone in an isolated worktree): dirties
  # docs/leadv2/open-threads.md, which in every checkout is a symlink into the
  # shared live control plane. The write is not the suite's own: the
  # UserPromptSubmit hook capture_ask (leadv2-task-anchor.sh:589) appends and
  # then os.replace()s the path, which destroys the symlink. Until that hook
  # writes through the link, a concurrent neighbour is misattributed this dirt.
  # PROMPT-CAPTURE-HOOK-DESTROYS-THE-SHARED-JOURNAL-01 removes this reason.
  "dispatch refusal fallback chain|||bash $TEST_DIR/test-routing-enforcement-p1.sh|||SERIAL"
  # parallel (measured 2026-09-04, run alone in an isolated worktree at
  # /private/tmp): rc=0, docs/leadv2 clean. The round-2 reason cited
  # _CORE_OFFLINE_OWNED_SUITES, but that list sets the SEVERITY of a
  # hermeticity violation (run_check ~296: owned = FAIL, otherwise WARN),
  # never placement -- it does not assert that a suite dirties anything.
  "product-close waits for worker exit|||bash $TEST_DIR/test-no-work-terminal.sh|||SERIAL"
  "product-close resumes a died-with-work lane once|||bash $TEST_DIR/test-dwr-resume.sh"
  "parked worker contract and one-shot resume (WORKER-PARKED-ON-BG-01)|||bash $TEST_DIR/test-parked-worker-resume.sh"
  "red-first pinned-baseline resolver (RED-FIRST-SELF-INVALIDATES-01)|||bash $TEST_DIR/test-red-first-baseline.sh"
  "shared-sink test guard (TESTS-POLLUTE-REAL-JOURNAL-01)|||bash $TEST_DIR/test-shared-sink-test-guard.sh"
  "product-close scopes a single-repo lane worktree|||bash $TEST_DIR/test-lane-diff-single-repo.sh"
  # serial: on _CORE_OFFLINE_OWNED_SUITES -- writes real REPO_ROOT/docs/leadv2
  # state; concurrent with another owned suite's write, run_check's hermetic
  # git-status diff misattributes one suite's dirt to the other.
  "Codex full-cycle runner|||bash $TEST_DIR/test-codex-session-runner.sh|||SERIAL"
  "Codex terminal lead intake|||bash $TEST_DIR/test-codex-lead-intake.sh"
  "Codex child-session recursion boundary|||bash $TEST_DIR/test-codex-child-session-boundary.sh"
  "autonomous session spawner|||bash $TEST_DIR/test-session-spawner.sh"
  "hook token + mode isolation|||bash $TEST_DIR/test-hook-token-mode-isolation.sh"
  "per-turn injection dedup (HOOK-INJECT-DEDUP-01)|||bash $TEST_DIR/test-inject-dedup.sh"
  "cross-injector dedup, active-task path (T15)|||bash $TEST_DIR/test-injector-dedup.sh"
  "main model/live quota|||bash $TEST_DIR/test-main-model-check.sh"
  "active registry fail-closed|||bash $TEST_DIR/test-active-registry-failclosed.sh"
  "lane write-set admission block (LANE-WRITESET-REGISTRY-01)|||bash $TEST_DIR/test-writeset-admission-block.sh"
  # parallel (round 2): not on _CORE_OFFLINE_OWNED_SUITES; every fixture is
  # LEADV2_STATE_ROOT-sandboxed, no shared lock/port.
  "lane worktrees survive the sweepers (SWEEPER-LANE-SAFETY-01)|||bash $TEST_DIR/test-worktree-lane-safety.sh"
  "active registry phase updates|||bash $TEST_DIR/test-active-registry-update-phase.sh"
  # parallel (round 2): not on _CORE_OFFLINE_OWNED_SUITES; LEADV2_PROJECT_ROOT/
  # LEADV2_STATE_ROOT sandboxed per-test, no shared lock/port.
  "fanout classifier/runner guard|||bash $TEST_DIR/test-fanout-classify-guard.sh"
  # parallel (measured 2026-09-04, run alone in an isolated worktree at
  # /private/tmp): rc=0, docs/leadv2 clean. The round-2 reason cited
  # _CORE_OFFLINE_OWNED_SUITES, but that list sets the SEVERITY of a
  # hermeticity violation (run_check ~296: owned = FAIL, otherwise WARN),
  # never placement -- it does not assert that a suite dirties anything.
  "lanes snapshot reconciliation|||bash $TEST_DIR/test-lanes-snapshot.sh|||SERIAL"
  "T13 slice2 (arbiter bench-fallback + abandon dedup)|||bash $TEST_DIR/test-t13-slice2.sh"
  "Phase-8 task schema|||bash $TEST_DIR/test-leadv2-phase8-assert-a2-schema.sh"
  "Phase-8 merge/completion proof|||bash $PLUGIN_ROOT/tests/test-deploy-merge-blocker-gate.sh"
  "subsession model downgrade|||bash $TEST_DIR/test-leadv2-model-arg-rebuild.sh"
  "subsession context diet (WORKER-CONTEXT-DIET-01)|||bash $TEST_DIR/test-subsession-context-diet.sh"
  "T14 worker MCP (glm spawn role config)|||bash $TEST_DIR/test-t14-worker-mcp.sh"
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
  # serial (measured 2026-09-04, run alone in an isolated worktree): dirties
  # docs/leadv2/open-threads.md, which in every checkout is a symlink into the
  # shared live control plane. The write is not the suite's own: the
  # UserPromptSubmit hook capture_ask (leadv2-task-anchor.sh:589) appends and
  # then os.replace()s the path, which destroys the symlink. Until that hook
  # writes through the link, a concurrent neighbour is misattributed this dirt.
  # PROMPT-CAPTURE-HOOK-DESTROYS-THE-SHARED-JOURNAL-01 removes this reason.
  "lane truth batch (log_path + quarantine convergence)|||bash $TEST_DIR/test-lane-truth-batch-01.sh|||SERIAL"
  "founder lane view|||bash $TEST_DIR/test-leadv2-lanes.sh"
  "plugin reliability (process liveness + role fallback + prepass/reorder signals)|||bash $TEST_DIR/test-plugin-reliability-01.sh"
  "plugin reliability-02 (zombie-reaper: run_dir arg + group signaling + ordering + TASK)|||bash $TEST_DIR/test-plugin-reliability-02.sh"
  "plan-followups-01|||bash $TEST_DIR/test-plan-followups-01.sh"
  "e2e gate arch-01 (lane-tree testing)|||bash $TEST_DIR/test-e2e-gate-arch-01.sh"
  "e2e gate ignores pre-existing red|||bash $TEST_DIR/test-e2e-gate-ignores-pre-existing-red.sh"
  "mutation runner measures only declared files|||bash $TEST_DIR/test-mutation-runner-measures-only-declared-files.sh"
  "judge-shaped agent notice|||bash $TEST_DIR/test-judge-shaped-agent-guard.sh"
  "journal honours the pinned root|||bash $TEST_DIR/test-journal-honours-the-pinned-root.sh"
  "guard says when it could not check|||bash $TEST_DIR/test-guard-says-when-it-could-not-check.sh"
  "dod gate suite registration (both map forms + run-all selection)|||bash $TEST_DIR/test-dod-gate-suite-registration.sh"
  "worker ends turn on a wait (contract + detector + salvage)|||bash $TEST_DIR/test-worker-ended-on-wait.sh"
  # parallel (round 2): not on _CORE_OFFLINE_OWNED_SUITES; every case uses its
  # own mktemp -d sandbox (incl. a sandboxed HOME), no shared lock/port.
  # serial WITH A DEATH DATE, not a return to the old placement (measured
  # 2026-09-04): round 2 moved this to the pool for want of a justification. The
  # justification exists and was found by measurement -- alone on main it dirties
  # docs/leadv2/open-threads.md, and `git status --porcelain -- docs/leadv2`, the
  # exact command run_check compares, DOES report that path (` T docs/leadv2/
  # open-threads.md`, reproduced by replacing the symlink with a real file). Four
  # _CORE_OFFLINE_OWNED_SUITES members share the pool at FAIL severity, so a
  # concurrent run reddens an innocent suite non-deterministically. The write is
  # not this suite's: suite -> dispatch -> session -> prompt -> UserPromptSubmit
  # hook -> journal rewrite. Remove this marker when
  # PROMPT-CAPTURE-HOOK-DESTROYS-THE-SHARED-JOURNAL-01 lands, not before.
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
  # serial: kept per round-1 finding. Not on _CORE_OFFLINE_OWNED_SUITES and
  # not proven to touch real docs/leadv2 or a real un-sandboxed HOME path
  # (run_check already gives sharded suites a private HOME/TMPDIR, which
  # would neutralize the ~/.claude/burn/history.db race its own header
  # comment warns about) -- round-2 could not independently reconfirm the
  # hazard, but also could not fully disprove it (uses real `git worktree`
  # machinery via leadv2-lane-worktree.sh). Left serial: an unconfirmed
  # disproof is not grounds to risk a flaky-red incident.
  "stop-gate autocommit on worker exit (V3-STOP-GATE-01)|||bash $TEST_DIR/test-stop-gate.sh|||SERIAL"
  "core-offline cross-run exclusive lock (SUITE-SPEED-01)|||bash $TEST_DIR/test-core-offline-lock-01.sh"
  "core-offline shard partition (SUITE-SPEED-01)|||bash $TEST_DIR/test-core-offline-shards-01.sh"
  # parallel (round 3): pure introspection -- asserts SUITE_DEFS shard
  # placement via LEADV2_SUITE_SHARDS_DUMP=1 (one runner parse, executes no
  # suites). Locks both halves of the E2E-GATE-BROKE-TODAY-01 round-2
  # decision: the 4 parallelized suites stay out of the serial tail, the 7
  # justified ones stay in it.
  "core-offline shard pool placement lock (E2E-GATE-BROKE-TODAY-01)|||bash $TEST_DIR/test-core-offline-shard-scope-01.sh"
  "core-offline per-suite TMPDIR isolation (SUITE-SPEED-01)|||bash $TEST_DIR/test-core-offline-tmpdir-01.sh"
  # The scope=changed contract itself (E2E-GATE-RUNS-ALL-94-SUITES-...-01):
  # selection, fail-open fallbacks, loud narrowing, arg errors, negative
  # controls M1/M2 via leadv2-mutation-control.sh.
  "core-offline scope=changed selection (E2E-GATE-RUNS-ALL-94-SUITES-01)|||bash $TEST_DIR/test-core-offline-scope-changed.sh"
  "silent-arm commits-ahead + live-worker guard (GATE-FALSE-SILENT-01)|||bash $TEST_DIR/test-silent-arm-commits-ahead.sh"
  "plugin sync .claude/scripts link classification|||bash $TEST_DIR/test-plugin-sync-claude-scripts.sh"
  "plugin sync contracts write gate|||bash $TEST_DIR/test-plugin-sync-contracts-gate.sh"
  "lane trace instrument (Mission B: writer/concurrency/off-path/reader)|||bash $TEST_DIR/test-leadv2-trace.sh"
  # serial (measured 2026-09-04, run alone in an isolated worktree): dirties
  # docs/leadv2/open-threads.md, which in every checkout is a symlink into the
  # shared live control plane. The write is not the suite's own: the
  # UserPromptSubmit hook capture_ask (leadv2-task-anchor.sh:589) appends and
  # then os.replace()s the path, which destroys the symlink. Until that hook
  # writes through the link, a concurrent neighbour is misattributed this dirt.
  # PROMPT-CAPTURE-HOOK-DESTROYS-THE-SHARED-JOURNAL-01 removes this reason.
  "burn governor (BURN-GOVERNOR-01: 24h burn gate)|||bash $TEST_DIR/test-burn-governor.sh|||SERIAL"
  "provider quota gate (QUOTA-GATE-PARITY-01)|||bash $TEST_DIR/test-provider-quota-gate.sh"
  "Claude multi-profile selector (CLAUDE-MULTIPROFILE-QUOTA-02)|||bash $TEST_DIR/test-claude-profile-select.sh"
  "Claude account collapse check (TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01)|||bash $TEST_DIR/test-claude-account-check.sh"
  "codex-dead review reroute (QUOTA-GATE-PARITY-01)|||bash $TEST_DIR/test-codex-dead-reroute.sh"
  "worker_reason on no_work/dead terminals (LANE-OBSERVABILITY-02)|||bash $TEST_DIR/test-worker-reason-terminal.sh"
  # parallel (round 2): not on _CORE_OFFLINE_OWNED_SUITES; single mktemp -d
  # SANDBOX root for all state, no shared lock/port.
  "prepass resume invalidation (LANE-OBSERVABILITY-02)|||bash $TEST_DIR/test-prepass-resume-invalidate.sh"
  "poll-based lane watcher (LANE-OBSERVABILITY-02)|||bash $TEST_DIR/test-lane-watch-poll.sh"
  "broad-status foreign-repo lanes (LANE-OBSERVABILITY-02)|||bash $TEST_DIR/test-broad-status-foreign-lanes.sh"
  "freepool model selector + gate stale-window TTL (FREEPOOL-MODEL-SELECTOR-01)|||bash $TEST_DIR/test-freepool-model-selector.sh"
  "lane verdict three states (D2-UNBLIND-AND-THIRD-STATE-M0M1-01: deliverable=finished_unlanded, registry unreadable=unknown)|||bash $TEST_DIR/test-lane-verdict-three-states.sh"
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

# --- scope=changed selection (E2E-GATE-RUNS-ALL-94-SUITES-...-01) -----------
# Reuses tests/run-all.sh's own file->suite mechanism so a suite registers its
# triggers in exactly one place no matter which runner executes it:
#   * `# run-all-triggers: <stem> ...` self-registration, discovered by the
#     same four-directory walk, the same token rule ([A-Za-z0-9._-]+), and the
#     same FATAL on a malformed declaration (an authoring error is never a
#     silently unselected suite);
#   * EXTRA_SUITE_MAP rows, both literal forms (leadv2's scalar string and
#     persona-engine's declare -A), extracted with the same sed shapes
#     lib/leadv2-dod-gate.sh's _dod_extra_suite_map_values() uses in
#     production.
# Selection narrows the SUITE_DEFS list above; the phase-8 gate's `--scope
# changed` then exercises the lane's own suites instead of all 94.
SCOPE_FILE_SEL=()
_scope_sel_add() { # <abs suite path> — dedup append to SCOPE_FILE_SEL
  local p="$1" e
  for e in ${SCOPE_FILE_SEL[@]+"${SCOPE_FILE_SEL[@]}"}; do
    [[ "$e" == "$p" ]] && return 0
  done
  SCOPE_FILE_SEL+=("$p")
}

_scope_resolve_suite_token() { # <repo-relative path | basename> -> abs path, rc1 if unresolvable
  local v="$1" d
  case "$v" in
    /*) [[ -f "$v" ]] && { printf '%s' "$v"; return 0; }; return 1 ;;
    */*) [[ -f "$REPO_ROOT/$v" ]] && { printf '%s' "$REPO_ROOT/$v"; return 0; }; return 1 ;;
  esac
  for d in "$REPO_ROOT/plugins/leadv2/scripts/tests" "$REPO_ROOT/.claude/scripts/tests" \
           "$REPO_ROOT/plugins/leadv2/tests" "$REPO_ROOT/tests"; do
    [[ -f "$d/$v" ]] && { printf '%s' "$d/$v"; return 0; }
  done
  return 1
}

# Fills SCOPE_MAP_ROWS ("key<TAB>value") from trigger declarations + EXTRA rows.
# A malformed declaration sets SCOPE_TRIGGER_ERRORS (FATAL at use, mirroring
# run-all's scan_suite_triggers); a malformed EXTRA row key is skipped — the
# unmapped rule below is the safety net that turns it into a full-set run,
# never a silent zero-suite run.
_scope_load_map_rows() {
  SCOPE_MAP_ROWS=()
  SCOPE_TRIGGER_ERRORS=""
  local dir file line spec tok n run_all row key val
  for dir in "$REPO_ROOT/plugins/leadv2/scripts/tests" \
             "$REPO_ROOT/.claude/scripts/tests" \
             "$REPO_ROOT/plugins/leadv2/tests" \
             "$REPO_ROOT/tests"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        spec="${line#'# run-all-triggers:'}"
        n=0
        while IFS= read -r tok; do
          [[ -n "$tok" ]] || continue
          case "$tok" in
            *[!A-Za-z0-9._-]*)
              SCOPE_TRIGGER_ERRORS="${SCOPE_TRIGGER_ERRORS}${file}: invalid trigger '${tok}' (allowed [A-Za-z0-9._-])
" ;;
            *)
              n=$((n + 1))
              SCOPE_MAP_ROWS+=("${tok}"$'\t'"${file}") ;;
          esac
        done <<< "$(printf '%s' "$spec" | tr ',' ' ' | tr -s '[:space:]' '\n')"
        if [[ "$n" -eq 0 ]]; then
          SCOPE_TRIGGER_ERRORS="${SCOPE_TRIGGER_ERRORS}${file}: declaration with no triggers
"
        fi
      done <<< "$(grep -h '^# run-all-triggers:' "$file" 2>/dev/null || true)"
    done < <(find "$dir" -maxdepth 1 -type f -name 'test-*.sh' 2>/dev/null | sort)
  done
  run_all="$REPO_ROOT/tests/run-all.sh"
  [[ -f "$run_all" ]] || return 0
  # FORM 1 — scalar rows "stem:suite-path" (the leadv2 shape).
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    case "$row" in *:*) ;; *) continue ;; esac
    key="${row%%:*}"
    val="${row#*:}"
    [[ -n "$val" ]] || continue
    case "$key" in *[!A-Za-z0-9._-]*) continue ;; esac
    SCOPE_MAP_ROWS+=("${key}"$'\t'"${val}")
  done <<< "$(sed -n '/^EXTRA_SUITE_MAP="/,/"$/p' "$run_all" \
    | sed -e '1s/^EXTRA_SUITE_MAP="//' -e '$s/"$//')"
  # FORM 2 — declare -A rows ["stem"]="suite [suite...]" (the persona-engine
  # shape); values are suite basenames there, resolved by
  # _scope_resolve_suite_token below.
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    key="${row%%$'\t'*}"
    val="${row#*$'\t'}"
    case "$key" in *[!A-Za-z0-9._-]*) continue ;; esac
    while IFS= read -r tok; do
      [[ -n "$tok" ]] || continue
      SCOPE_MAP_ROWS+=("${key}"$'\t'"${tok}")
    done <<< "$(printf '%s' "$val" | tr -s '[:space:]' '\n')"
  done <<< "$(sed -n '/^declare -A EXTRA_SUITE_MAP=(/,/^)/p' "$run_all" \
    | sed -n 's/^[[:space:]]*\[\([^]]*\)\]="\([^"]*\)".*/\1'"$(_scope_tab)"'\2/p')"
}
_scope_tab() { printf '\t'; }

_scope_sel_map_rows_for_stem() { # <stem> — add every map row keyed stem|stem.sh
  local stem="$1" row key val resolved
  for row in ${SCOPE_MAP_ROWS[@]+"${SCOPE_MAP_ROWS[@]}"}; do
    key="${row%%$'\t'*}"
    [[ "$key" == "$stem" || "$key" == "$stem".sh ]] || continue
    val="${row#*$'\t'}"
    resolved="$(_scope_resolve_suite_token "$val" || true)"
    [[ -n "$resolved" ]] && _scope_sel_add "$resolved"
  done
}

# One changed file -> suite files, by run-all's rules: a changed test file
# selects itself; synthetic stems for files the generic allowlist never
# reaches; then `test-<stem>.sh` candidates plus map rows. rc0 = the file is
# mapped (>=1 suite selected), rc1 = unmapped.
_scope_changed_file_select() { # <repo-relative changed file>
  local cf="$1" stem="" via_hooks=0 cand
  case "$cf" in
    plugins/leadv2/scripts/tests/test-*.sh|.claude/scripts/tests/test-*.sh|plugins/leadv2/tests/test-*.sh|tests/test-*.sh)
      [[ -f "$REPO_ROOT/$cf" ]] && _scope_sel_add "$REPO_ROOT/$cf" ;;
  esac
  if [[ "$cf" == "plugins/leadv2/hooks/hooks.json" ]]; then
    stem="hooks.json"; via_hooks=1
  elif [[ "$cf" == plugins/leadv2/hooks/*.sh ]]; then
    stem="$(basename "$cf" .sh)"; via_hooks=1
  elif [[ "$cf" == "plugins/leadv2/config/freepool-arm.yaml" ]]; then
    stem="freepool-arm.yaml"
  elif [[ "$cf" == "plugins/leadv2/config/leadv2-routing.yaml" ]]; then
    stem="leadv2-routing.yaml"
  elif [[ "$cf" == "plugins/leadv2/config/model-capability.yaml" ]]; then
    stem="model-capability.yaml"
  elif [[ "$cf" == "plugins/leadv2/ref/leadv2-main-model.yaml" ]]; then
    stem="leadv2-main-model.yaml"
  elif [[ "$cf" == "plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py" ]]; then
    stem="leadv2-glm-policy-resolve.py"
  elif [[ "$cf" == plugins/leadv2/workflows/*.js ]]; then
    stem="$(basename "$cf")"
  elif [[ "$cf" == ".claude/leadv2-overrides/status-collector-facts.sh" ]]; then
    stem="status-collector-facts"
  elif [[ "$cf" == ".gitignore" ]]; then
    stem="gitignore"
  elif [[ "$cf" == "tests/run-all.sh" ]]; then
    stem="run-all.sh"
  elif [[ "$cf" == "tests/known-red-suites.txt" ]]; then
    # B2-GATE-BUDGET-4: the allow-list is a legit lane write target; without
    # this case every allow-list edit was structurally unmappable -> full-set
    # fallback (95 suites) for a one-line comment change (measured on this
    # very lane before the fix). Suites self-declare the
    # `known-red-suites(.txt)` triggers (see
    # plugins/leadv2/tests/test-gate-reaches-a-verdict-inside-budget.sh).
    stem="known-red-suites.txt"
  else
    case "$cf" in
      plugins/leadv2/scripts/*.sh|plugins/leadv2/scripts/lib/*.sh|plugins/leadv2/scripts/*.py|plugins/leadv2/hooks/*.sh) ;;
      *)
        [[ ${#SCOPE_FILE_SEL[@]} -gt 0 ]] && return 0
        return 1 ;;
    esac
    stem="$(basename "$cf")"
    stem="${stem%.*}"
  fi
  if [[ "$via_hooks" == "1" ]]; then
    for cand in "$REPO_ROOT/plugins/leadv2/scripts/tests/test-${stem}.sh" \
                "$REPO_ROOT/tests/test-${stem}.sh"; do
      [[ -f "$cand" ]] && _scope_sel_add "$cand"
    done
  else
    for cand in "$REPO_ROOT/plugins/leadv2/scripts/tests/test-${stem}.sh" \
                "$REPO_ROOT/.claude/scripts/tests/test-${stem}.sh" \
                "$REPO_ROOT/plugins/leadv2/tests/test-${stem}.sh" \
                "$REPO_ROOT/tests/test-${stem}.sh"; do
      [[ -f "$cand" ]] && _scope_sel_add "$cand"
    done
  fi
  _scope_sel_map_rows_for_stem "$stem"
  [[ ${#SCOPE_FILE_SEL[@]} -gt 0 ]]
}

# The scope-resolution body. On success: SCOPE_SELECTED_DEFS holds the narrowed
# defs and SCOPE_FALLBACK_REASON is empty; on failure: the full set stays and
# SCOPE_FALLBACK_REASON says why. NO last-checked stamp on purpose: run-all
# can persist its last-checked SHA because its always-on set re-runs
# regardless; this runner's narrowed set IS the whole gate, so a stamp would
# shrink a second gate run's diff to only-new commits and green it on partial
# coverage — the lying-green shape, paid for with an optimization.
#
# DECLARED NEGATIVE CONTROLS (E2E-KILLRATE-01), applied by leadv2-mutation-
# control.sh to the two `scope-mut-*` marker lines INSIDE this body — the two
# shapes a scope gate takes when it lies green:
#   M1 scope-mut-1: an unresolvable base returns an EMPTY selection as success
#      -> the suite goes red on the executed-suite count being 0.
#   M2 scope-mut-2: the changed-file list is ignored, everything is selected
#      -> --scope parsed, full set run anyway; red on the count for a narrow
#      diff (today's bug wearing the new flag).
_core_offline_scope_changed_select() {
  local tok base_ref="" merge_base="" range_start="" changed="" f="" g="" line=""
  local -a rel_changed=() selected_files=() uniq_files=()
  SCOPE_FALLBACK_REASON=""
  SCOPE_SELECTION_REASON="-"
  SCOPE_BASE_DESC="unresolvable"
  SCOPE_CHANGED_COUNT=0
  SCOPE_UNMAPPED_COUNT=0
  SCOPE_SELECTED_DEFS=()
  if ! git -C "$REPO_ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
    SCOPE_FALLBACK_REASON="git_error (rev-parse HEAD failed in $REPO_ROOT)"
    return 1
  fi
  for tok in main origin/main; do
    if git -C "$REPO_ROOT" rev-parse --verify "$tok" >/dev/null 2>&1; then
      base_ref="$tok"
      break
    fi
  done
  if [[ -n "$base_ref" ]]; then
    merge_base="$(git -C "$REPO_ROOT" merge-base HEAD "$base_ref" 2>/dev/null || true)"
    if [[ -n "$merge_base" ]]; then
      range_start="$merge_base"
      SCOPE_BASE_DESC="${base_ref}@${merge_base:0:10}"
    fi
  fi
  if [[ -z "$range_start" ]] && git -C "$REPO_ROOT" rev-parse --verify 'HEAD~1' >/dev/null 2>&1; then
    range_start='HEAD~1'
    SCOPE_BASE_DESC="HEAD~1@$(git -C "$REPO_ROOT" rev-parse --short 'HEAD~1' 2>/dev/null || printf 'HEAD~1')"
  fi
  if [[ -z "$range_start" ]]; then
    # scope-mut-1: no-base fallthrough — fail OPEN to the full set, never an empty run
    SCOPE_FALLBACK_REASON="no_base_ref (no main/origin/main merge-base, no HEAD~1)"
    return 1
  fi
  # Changed set: uncommitted + committed range + untracked, minus the phase-8
  # gate's own non-executable excludes (docs/leadv2, docs/handoff, *.md,
  # docs/* — the gate skips such diffs as no_executable_change, so they must
  # neither force nor dodge a full run here).
  changed="$({
    git -C "$REPO_ROOT" diff --name-only HEAD -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null || true
    git -C "$REPO_ROOT" diff --name-only "$range_start" HEAD -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null || true
    git -C "$REPO_ROOT" ls-files --others --exclude-standard -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null || true
  } | sort -u)"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    # GATE-BUDGET-...-01 / lane-liveness-artifacts: a leading-anchor `docs/*`
    # only matches housekeeping at the repo root. A mis-rooted caller (see
    # leadv2-lane-liveness.sh PLUGINS-DOCS-LANE-SHARE-01) can leave runtime
    # debris nested at plugins/docs/leadv2/.lane-liveness-share/... — same
    # housekeeping, one level deeper. Match `docs/` as a full path segment at
    # ANY depth, plus the .lane-liveness-share artifact dir by name, so a
    # nested copy neither forces nor dodges a full run either. Deliberately
    # NOT a bare `*docs*` — that would also swallow a real source file under
    # some future plugins/docs-tool/, and the whole value of the unmapped-file
    # safety net below is that it refuses to guess.
    case "$f" in
      *.md|docs/*|*/docs/*|.lane-liveness-share/*|*/.lane-liveness-share/*) continue ;;
    esac
    rel_changed+=("$f")
  done <<< "${changed:-}"
  SCOPE_CHANGED_COUNT=${#rel_changed[@]}
  if [[ "$SCOPE_CHANGED_COUNT" -eq 0 ]]; then
    SCOPE_SELECTION_REASON="no_relevant_changed_files"
    return 0 # scope-empty-control: known empty diff, no coverage to prove
  fi
  _scope_load_map_rows
  if [[ -n "$SCOPE_TRIGGER_ERRORS" ]]; then
    printf '%s' "$SCOPE_TRIGGER_ERRORS" >&2
    printf -- 'run-core-offline: FATAL bad_trigger_decl — a malformed # run-all-triggers: declaration is an error, never a silently unselected suite; fix the suite file(s) listed above\n' >&2
    exit 2
  fi
  for f in ${rel_changed[@]+"${rel_changed[@]}"}; do
    SCOPE_FILE_SEL=()
    if _scope_changed_file_select "$f" && [[ ${#SCOPE_FILE_SEL[@]} -gt 0 ]]; then
      selected_files+=("${SCOPE_FILE_SEL[@]}")
    else
      SCOPE_UNMAPPED_COUNT=$((SCOPE_UNMAPPED_COUNT + 1))
    fi
  done
  for f in ${selected_files[@]+"${selected_files[@]}"}; do
    local dup=0
    for g in ${uniq_files[@]+"${uniq_files[@]}"}; do
      [[ "$g" == "$f" ]] && { dup=1; break; }
    done
    [[ "$dup" == "0" ]] && uniq_files+=("$f")
  done
  if [[ ${#uniq_files[@]} -eq 0 || "$SCOPE_UNMAPPED_COUNT" -gt 0 ]]; then
    SCOPE_FALLBACK_REASON="unmapped_files (${SCOPE_UNMAPPED_COUNT} of ${SCOPE_CHANGED_COUNT} changed files selected no suite) — cannot prove the diff is covered"
    return 1 # scope-unmapped-control: unknown coverage must run the full set
  fi
  # scope-mut-2: selection applied below this line
  local entry name rest cmd_str base matched_syntax=0
  local -a new_defs=() consumed=()
  # Always-on under a narrowed scope: whole-plugin shell syntax (the entry
  # whose command is the syntax_all function), the one curated invariant that
  # syntax-checks EVERY changed .sh file even when its mapped suite does not;
  # costs seconds. Only when the curated set actually has one (a
  # LEADV2_SUITE_DEFS_OVERRIDE list may not).
  for entry in ${SUITE_DEFS[@]+"${SUITE_DEFS[@]}"}; do
    rest="${entry#*|||}"
    if [[ "${rest%%|||*}" == "syntax_all" ]]; then
      new_defs+=("$entry")
      matched_syntax=1
      break
    fi
  done
  for entry in ${SUITE_DEFS[@]+"${SUITE_DEFS[@]}"}; do
    name="${entry%%|||*}"
    rest="${entry#*|||}"
    cmd_str="${rest%%|||*}"
    base=""
    case "$cmd_str" in */*) base="${cmd_str##*/}" ;; esac
    [[ -n "$base" ]] || continue
    for f in ${uniq_files[@]+"${uniq_files[@]}"}; do
      if [[ "${f##*/}" == "$base" ]]; then
        new_defs+=("$entry")
        consumed+=("$f")
        break
      fi
    done
  done
  for f in ${uniq_files[@]+"${uniq_files[@]}"}; do
    local seen=0
    for g in ${consumed[@]+"${consumed[@]}"}; do
      [[ "$g" == "$f" ]] && { seen=1; break; }
    done
    if [[ "$seen" == "0" ]]; then
      new_defs+=("${f#"$REPO_ROOT"/} (scope-selected ad-hoc)|||bash $f")
    fi
  done
  SCOPE_SELECTED_DEFS=(${new_defs[@]+"${new_defs[@]}"})
  return 0
}

if [[ "$CORE_OFFLINE_SCOPE" == "changed" ]]; then
  _scope_total=${#SUITE_DEFS[@]}
  if _core_offline_scope_changed_select; then
    SUITE_DEFS=(${SCOPE_SELECTED_DEFS[@]+"${SCOPE_SELECTED_DEFS[@]}"})
    printf -- '[CORE-OFFLINE] scope=changed running %d of %d suites (base=%s, %d changed files, %d unmapped)\n' \
      "${#SUITE_DEFS[@]}" "$_scope_total" "$SCOPE_BASE_DESC" "$SCOPE_CHANGED_COUNT" "$SCOPE_UNMAPPED_COUNT"
    _scope_reason="$SCOPE_SELECTION_REASON"
    _scope_verdict="selected"
    if [[ "$_scope_reason" == no_relevant_changed_files ]]; then
      _scope_verdict="nothing_to_run"
    fi
  else
    printf -- '[CORE-OFFLINE] scope=changed running %d of %d suites (base=%s, %d changed files, %d unmapped -> full-set fallback: %s)\n' \
      "${#SUITE_DEFS[@]}" "$_scope_total" "$SCOPE_BASE_DESC" "$SCOPE_CHANGED_COUNT" "$SCOPE_UNMAPPED_COUNT" "$SCOPE_FALLBACK_REASON"
    _scope_reason="$SCOPE_FALLBACK_REASON"
    _scope_verdict="full_set_fallback"
  fi
  printf -- '[CORE-OFFLINE] SCOPE_RESULT selected=%d total=%d base=%s changed=%d unmapped=%d verdict=%s reason=%s\n' \
    "${#SUITE_DEFS[@]}" "$_scope_total" "$SCOPE_BASE_DESC" "$SCOPE_CHANGED_COUNT" "$SCOPE_UNMAPPED_COUNT" "$_scope_verdict" "$_scope_reason"
  if [[ -n "${LEADV2_CORE_OFFLINE_SCOPE_DUMP:-}" ]]; then
    for _e in ${SUITE_DEFS[@]+"${SUITE_DEFS[@]}"}; do
      printf -- '[CORE-OFFLINE] SCOPE_SELECTED %s\n' "${_e%%|||*}"
    done
    exit 0
  fi
  if [[ "$_scope_verdict" == nothing_to_run ]]; then
    printf -- '[CORE-OFFLINE] suites passed=0 failed=0 missing=0 verdict=nothing_to_run reason=no_relevant_changed_files repo=%s\n' "$REPO_ROOT"
    exit 0
  fi
  unset _scope_total _scope_reason _scope_verdict _e
fi

# --- B2-GATE-BUDGET-4: budget-mode known-red skip ----------------------------
# tests/run-all.sh forwards LEADV2_CORE_OFFLINE_SKIP_KNOWN_RED=1 in its
# BUDGET scopes (--scope changed / changed-since, i.e. the close gate and PR
# CI) together with the allow-list path. Under that request, allow-listed
# labels (`core:<label>` rows of $LEADV2_CORE_OFFLINE_KNOWN_RED_FILE) are
# SKIPPED here with one [CORE-OFFLINE] KNOWN-RED-SKIP: <name> line per
# dropped suite (run-all relays them as [KNOWN-RED-SKIP]); their failure
# classification was already non-blocking downstream, what they cost inside
# a 900s close-gate budget is TIME (measured 2026-09-09:
# lane-truth-batch-01 = 151s red inside this runner). Allow-listed suites
# are never dropped from runs entirely: without the request (bare
# invocation, --scope all — the nightly full sweep) every suite executes
# exactly as before, and a label that PASSES such a full run is surfaced by
# run-all as [KNOWN-RED-GONE-GREEN] — the seam that keeps the allow-list
# shrinking instead of becoming permanent.
# DECLARED NEGATIVE CONTROL (E2E-KILLRATE-01, this lane's third), applied by
# leadv2-mutation-control.sh to the marker line INSIDE the function body
# (never top level — a top-level insert reddens every suite for the wrong
# reason):
#   M3 skip-mut-1: drop the budget-scope gate (skip whenever the env is
#      present, even in a bare / --scope all run) ->
#      test-core-offline-known-red-skip.sh case 2 goes red: a bare
#      invocation still must execute allow-listed suites — that is the
#      "still executed somewhere" half of the contract.
KNOWN_RED_SKIPPED=0
_core_offline_skip_requested() { # rc0 iff the budget-mode skip was requested
  # The wrapper enforces the "still executed somewhere" contract itself:
  # only a --scope changed run may skip. An env leak into a bare or --scope
  # all invocation (the nightly full sweep — the ONE place allow-listed
  # suites still execute) must not silently skip them.
  [[ "$CORE_OFFLINE_SCOPE" == "changed" ]] || return 1 # skip-mut-1 marker: budget scope gates the skip
  [[ "${LEADV2_CORE_OFFLINE_SKIP_KNOWN_RED:-}" == "1" \
     && -n "${LEADV2_CORE_OFFLINE_KNOWN_RED_FILE:-}" \
     && -f "${LEADV2_CORE_OFFLINE_KNOWN_RED_FILE}" ]]
}
if _core_offline_skip_requested; then
  _kr_list="$(grep -vE '^[[:space:]]*(#|$)' "${LEADV2_CORE_OFFLINE_KNOWN_RED_FILE}" 2>/dev/null \
    | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//')"
  _kr_kept=()
  for _kr_entry in ${SUITE_DEFS[@]+"${SUITE_DEFS[@]}"}; do
    _kr_name="${_kr_entry%%|||*}"
    if printf '%s\n' "${_kr_list}" | grep -qxF "core:${_kr_name}"; then
      printf -- '[CORE-OFFLINE] KNOWN-RED-SKIP: %s\n' "$_kr_name" >&2
      KNOWN_RED_SKIPPED=$((KNOWN_RED_SKIPPED + 1))
    else
      _kr_kept+=("${_kr_entry}")
    fi
  done
  SUITE_DEFS=(${_kr_kept[@]+"${_kr_kept[@]}"})
  printf -- '[CORE-OFFLINE] known-red skipped=%d (budget mode: still executed by --scope all / bare runs)\n' "$KNOWN_RED_SKIPPED" >&2
  if [[ ${#SUITE_DEFS[@]} -eq 0 ]]; then
    printf -- '[CORE-OFFLINE] suites passed=0 failed=0 missing=0 known_red_skipped=%d verdict=nothing_to_run reason=known_red_skip_emptied_selection repo=%s\n' \
      "$KNOWN_RED_SKIPPED" "$REPO_ROOT"
    exit 0
  fi
fi
unset _kr_list _kr_kept _kr_entry _kr_name 2>/dev/null || true

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
    for _entry in ${SUITE_DEFS[@]+"${SUITE_DEFS[@]}"}; do
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

printf -- '\n[CORE-OFFLINE] suites passed=%d failed=%d missing=%d known_red_skipped=%d repo=%s\n' "$PASS" "$FAIL" "$MISSING" "$KNOWN_RED_SKIPPED" "$REPO_ROOT"
(( FAIL == 0 && MISSING == 0 ))
