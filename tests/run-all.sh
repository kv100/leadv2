#!/usr/bin/env bash
# tests/run-all.sh — canonical repo's e2e entrypoint (T-d, PRODUCT-READINESS-GATES-01
# follow-up, 2026-07-29). This is what leadv2-e2e-entrypoint.sh resolves to and what the
# product gates (leadv2-dispatch-product-close.sh, leadv2-phase8-e2e-gate.sh) execute.
#
# It does NOT author new suites — it drives the plugin's own curated offline regression
# runner (.claude/scripts/tests/run-core-offline.sh) plus, on `--scope changed` or
# `--scope changed-since`, any test-*.sh whose stem matches a changed file's stem under
# plugins/leadv2/scripts/ (see scope_changed_anchor below for the two range semantics).
#
# usage: tests/run-all.sh [--scope changed|changed-since|all]
# exit 0: every selected suite passed
# exit 1: at least one suite failed
# exit 2: bad usage
set -uo pipefail

# TESTS-POLLUTE-REAL-JOURNAL-01 §1: mark this whole subtree as a test so the
# shared-state writers (leadv2-event.sh, lib/leadv2-freepool-gate.sh record)
# refuse unredirected writes to the real journal / arm-state file. Fast path
# for the writers' own detection (lib/leadv2-test-context.sh) — the ancestor
# walk there already catches a directly-invoked suite that sets nothing.
export LEADV2_TEST_CONTEXT="${LEADV2_TEST_CONTEXT:-1}"

# zsh-tolerant boot (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01): zsh has no
# BASH_SOURCE; under `zsh tests/run-all.sh` $0 is the script path, same as a
# direct bash execution — fall through without tripping set -u.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"

# C2 (GATE-WRONG-ROOT-FALSE-DEAD-01): root-escape guard. If ROOT does not
# resolve to a git toplevel, every downstream path derivation (PLUGIN_ROOT,
# REPO_ROOT in run-core-offline.sh, etc.) walks to a parent — the exact
# defect that produced repo=/Users/.../Projects. Fail hard, never silently.
_git_toplevel="$(git -C "${ROOT}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ "${_git_toplevel}" != "${ROOT}" ]]; then
  echo "run-all: FATAL root_escape expected=${ROOT} resolved=${_git_toplevel:-<not-a-repo>}" >&2
  exit 2
fi

SCOPE="changed"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      SCOPE="${2:-}"; shift 2 ;;
    --scope=*)
      SCOPE="${1#--scope=}"; shift ;;
    -h|--help)
      echo "usage: tests/run-all.sh [--scope changed|changed-since|all]" >&2
      exit 0 ;;
    *)
      echo "run-all: unknown argument: $1" >&2
      exit 2 ;;
  esac
done
case "${SCOPE}" in
  changed|changed-since|all) ;;
  *) echo "run-all: --scope must be changed|changed-since|all (got '${SCOPE}')" >&2; exit 2 ;;
esac

PASS=0
FAIL=0
KNOWN=0
KNOWN_RED_SKIPPED=0
GONE_GREEN=0
declare -a SUITES=()
declare -a FAILED_REL=()

# CI-RUNS-THE-SUITES-01 round 3: the known-red allow-list must reach THIS
# decision. Before this change a nested known-red failure inside
# run-core-offline.sh surfaced only as the wrapper's repo-relative path in
# the "Failures (blocking)" block — the block leadv2-e2e-ownership.sh parses,
# where every entry is blocking for a lane. The wrapper was never in
# tests/known-red-suites.txt (putting it there would allow-list all 83 of its
# nested suites at once), so no `core:` entry could ever unblock a lane;
# measured 2026-09-02: PULSE-HOOK-IS-A-FORKED-COPY-01 and
# CI-RUNS-THE-SUITES-01 both died at that wall. The wrapper already emits
# granular `[CORE-OFFLINE] FAILED: <label>` lines, so capture its transcript
# and classify HERE (one classification point, shared by ci-gate.sh and this
# lane-facing exit code):
#   every failing nested suite allow-listed   -> wrapper printed [KNOWN-RED],
#                                                NOT in Failures (blocking),
#                                                run-all exits 0;
#   >=1 failing nested suite NOT on the list  -> wrapper blocking as before
#                                                (named [NOT-KNOWN-RED]);
#   wrapper failure with ZERO parsed FAILED   -> blocking, fail-closed
#                                                (lock timeout, harness
#                                                crash, MISSING suites).
ALLOWLIST="${ROOT}/tests/known-red-suites.txt"
CORE_OFFLINE_REL="plugins/leadv2/scripts/tests/run-core-offline.sh"

is_known_red() { # <id>
  # known-red-mut-1 marker: the allow-list decision every classification consumes
  [[ -f "${ALLOWLIST}" ]] || return 1
  grep -qxF "$1" <(grep -vE '^[[:space:]]*(#|$)' "${ALLOWLIST}" | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//')
}

# ── B2-GATE-BUDGET-4: per-suite ceiling + known-red out of the close budget ──
# Re-measured on this lane 2026-09-09: one synchronous status-surface wrapper
# call costs ~48s under load, the bash32 suite makes several of them (~321s
# total, green), and test-lane-truth-batch-01 alone is ~355s (red, allow-
# listed). A gate selection containing them cannot finish inside the 900s
# close-gate budget, so the gate's only possible terminal was rc=124 /
# verdict=timeout — which is not a verdict. Two mechanisms here, both
# fail-toward-verdict:
#   1. per-suite ceiling: a suite that would eat the whole budget is killed
#      and NAMED — "[SUITE-TIMEOUT] X exceeded Ns" is a verdict a gate can
#      act on; rc=124-for-everything is not.
#   2. known-red nested suites leave the BUDGET path only (--scope changed /
#      changed-since): run-all asks run-core-offline.sh to skip allow-listed
#      labels (LEADV2_CORE_OFFLINE_SKIP_KNOWN_RED=1 + the allow-list path;
#      the wrapper relays [CORE-OFFLINE] KNOWN-RED-SKIP: lines, re-emitted
#      below as [KNOWN-RED-SKIP]). They are NOT dropped from runs entirely:
#      --scope all (the nightly full sweep) and a bare wrapper invocation
#      still execute every allow-listed suite, and a label that PASSES a
#      full-set run is surfaced as [KNOWN-RED-GONE-GREEN] — the allow-list
#      may only shrink, and this is the seam that keeps it shrinking.
#
# DECLARED NEGATIVE CONTROLS (E2E-KILLRATE-01), applied by
# leadv2-mutation-control.sh to the marker lines INSIDE the function bodies
# below (never at top level — a top-level insert reddens every suite for the
# wrong reason and reads as a pass):
#   M1 ceiling-mut-1: disable the ceiling (always 0) ->
#      plugins/leadv2/tests/test-gate-reaches-a-verdict-inside-budget.sh
#      case 1 goes red: the hanging stub suite is never killed, no
#      [SUITE-TIMEOUT] line, run-all exits 0 instead of 1.
#   M2 known-red-mut-1: is_known_red accepts everything -> case 2 goes red:
#      a NOT-allow-listed failing nested suite no longer blocks the run —
#      the always-green-gate defect, reintroduced.
_suite_ceiling_s() { # -> seconds one suite may run; 0 disables the ceiling
  local v="${LEADV2_RUN_ALL_SUITE_TIMEOUT_S:-600}"
  case "${v}" in ''|*[!0-9]*) v=600 ;; esac
  printf '%s' "${v}" # ceiling-mut-1 marker: the effective ceiling, after validation
}
# Standalone portable timeout with timeout(1) semantics (124 on kill): prefer
# gtimeout/timeout when present, else the process-group sleep+kill watcher
# leadv2-builder-selfcheck.sh uses. Deliberately NOT sourced from the plugin
# tree: run-all must run standalone in scratch fixture repos
# (test-known-red-allowlist-nested-match.sh copies only this file).
_run_all_timeout_run() { # <timeout_s> <logfile> -- <cmd...> -> rc (124 on kill)
  local timeout_s="$1" logfile="$2"; shift 2
  [[ "${1:-}" == "--" ]] && shift
  local rc=0
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${timeout_s}" "$@" > "${logfile}" 2>&1; rc=$?
  elif command -v timeout >/dev/null 2>&1; then
    timeout "${timeout_s}" "$@" > "${logfile}" 2>&1; rc=$?
  else
    local pid watcher
    set -m
    { "$@" >"${logfile}" 2>&1 & } 2>/dev/null
    pid=$!
    set +m
    ( sleep "${timeout_s}"
      kill -0 "${pid}" 2>/dev/null || exit 0
      kill -TERM -"${pid}" 2>/dev/null || kill -TERM "${pid}" 2>/dev/null || true
      sleep 2
      kill -KILL -"${pid}" 2>/dev/null || kill -KILL "${pid}" 2>/dev/null || true
    ) >/dev/null 2>&1 </dev/null &
    watcher=$!
    wait "${pid}" 2>/dev/null; rc=$?
    kill -TERM "${watcher}" 2>/dev/null || true
    wait "${watcher}" 2>/dev/null || true
    (( rc > 128 )) && rc=124
  fi
  return "${rc}"
}
# Budget modes only: changed (close gate / PR CI) and changed-since
# (incremental CI) hand the wrapper the known-red skip. --scope all (the
# nightly full sweep) executes every allow-listed suite — that is where
# red->green transitions surface via [KNOWN-RED-GONE-GREEN].
core_offline_budget_skip_env() { # -> rc0 iff the wrapper should skip known-red suites
  [[ "${SCOPE}" != "all" ]]
}
# Non-stem suite mappings live in EXTRA_SUITE_MAP below (string rows, one per
# line, "<stem>:<suite>"). The PHASE-DISCIPLINE-01 array form was migrated into
# it during the MON-PULSE-01 merge (2026-08-28) — one mechanism, not two.

# E2E-GATE-RUNS-ALL-94-SUITES-BECAUSE-run-all-SWALLOWS-SCOPE-01: the core
# runner (run-core-offline.sh) has had its own --scope contract since it
# added scope-aware selection, but nothing upstream of it ever forwarded
# one -- it was always invoked bare, so a `--scope changed` gate run always
# executed run-core-offline.sh's full unscoped suite set (95 of 95) instead
# of the narrow set it was told to run. Isolated in its own function, not
# inlined at the call site, so a negative-control mutant can target exactly
# this decision point without reddening every other suite invocation in the
# run loop for the wrong reason.
#
# DECLARED NEGATIVE CONTROLS (E2E-KILLRATE-01), applied by
# leadv2-mutation-control.sh to the two `scope-mut-*` marker lines INSIDE
# this function's body:
#   M1 scope-mut-1: drop the forwarded scope again (always return "") ->
#      test-run-all-forwards-scope.sh goes red on the --scope changed case:
#      the fake core-offline stub sees argv `--scope ` instead of
#      `--scope changed`, reintroducing the exact original defect.
#   M2 scope-mut-2: hardcode "changed" regardless of what run-all itself was
#      given -> the suite goes red on the --scope all case: a gate that can
#      no longer be asked for a full run is a new lying-green surface.
# A top-level insert is NOT a valid control for this suite: it reddens every
# suite invocation in the run loop for the wrong reason.
core_offline_scope_arg() { # -> the --scope value to hand to run-core-offline.sh
  # scope-mut-1: forward the value run-all itself was given
  # scope-mut-2: never a value other than what run-all itself was given
  # B6-SCOPE-CHANGED: changed-since is run-all's OWN incremental mode — the
  # nested runner deliberately has no incremental stamp (its narrowed set IS
  # the whole gate; skipping already-tested commits there would green on
  # partial coverage, see the comment above its _core_offline_scope_changed_
  # select). run-core-offline accepts only changed|all, so it always gets the
  # branch-anchored 'changed' selection.
  if [[ "${SCOPE}" == "changed-since" ]]; then
    printf '%s' "changed"
  else
    printf '%s' "${SCOPE}"
  fi
}

add_suite() { # <path>
  local p="$1" real
  real="$(cd "$(dirname "$p")" 2>/dev/null && pwd)/$(basename "$p")" || return 0
  [[ -f "$real" ]] || return 0
  # C2 (GATE-WRONG-ROOT-FALSE-DEAD-01): containment check. A resolved suite
  # path outside ROOT is a D2-class escape (symlink following, wrong-depth
  # anchor) — skip it loudly rather than running tests from a foreign tree.
  case "${real}" in
    "${ROOT}/"*) ;;
    "${ROOT}")   ;;
    *) echo "run-all: SKIP out_of_tree ${real}" >&2; return 0 ;;
  esac
  local existing
  for existing in ${SUITES[@]+"${SUITES[@]}"}; do
    [[ "$existing" == "$real" ]] && return 0
  done
  SUITES+=("$real")
}

# C3 (GATE-WRONG-ROOT-FALSE-DEAD-01): Always-on: the plugin's own curated
# offline regression set. Plugin-preferred — the canonical 111-file set at
# plugins/leadv2/scripts/tests/ has the correct ../../.. path arithmetic
# (D2) and is never a stale fork (D3). Repos without plugins/leadv2/
# (persona-engine, m3-market) fall through to .claude/ verbatim — zero
# behavioural delta outside this repo (case (g) guard).
if [[ -f "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh" ]]; then
  add_suite "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh"
else
  add_suite "${ROOT}/.claude/scripts/tests/run-core-offline.sh"
fi

# Always-on: SwiftBar runs the status-surface scripts under macOS /bin/bash 3.2
# (PATH-resolved, not Homebrew bash 5) — a stem-based --scope=changed match on
# the renderer/wrapper filenames is not enough, since a change to an unrelated
# script must not silently drop this guard from a run. See SWIFTBAR-BASH32-01.
add_suite "${ROOT}/tests/test-status-surface-bash32.sh"
# SWIFTBAR-FAST-NAMES-01: the widget's async-cache + label-resolver contract —
# always-on for the same reason as bash32 (the wrapper filename stem no longer
# matches the test stems after the .10s -> .5s rename, so a changed-scope match
# is not reliable).
add_suite "${ROOT}/tests/test-status-surface-single-lead.sh"
add_suite "${ROOT}/tests/test-status-surface-fast-names.sh"

# MON-PULSE-01 (superseded 2026-09-04, SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01):
# this used to be a ~220-row literal map of "<changed-stem>:<suite>" rows, and
# every lane adding a suite had to edit that one block in this one file — with
# three sessions working, the block was a queue. The rows were migrated to
# per-suite self-registration: each suite declares its own selection triggers
# in its own file with a header line
#   # run-all-triggers: <stem> [<stem>...]
# and scan_suite_triggers() below discovers them by walking the four suite
# directories, so adding a suite edits only that suite's own file — never
# this one. A trigger matches a changed file's stem (basename minus
# extension) or its full filename — the same key rule the map always applied
# (key == stem or key == stem.sh). This variable remains a SUPPORTED
# FALLBACK: rows added here still work, and a row whose target suite file
# does not exist on disk MUST live here, because a self-declaration can only
# be written into a file that exists.
# POOL-IS-COMPUTED-AFTER-THE-ARM-IS-CHOSEN-01: the two new routing suites
# must be selected by every production stem they grade. The suites also
# self-declare the same triggers via their own '# run-all-triggers:' headers;
# these rows are the belt-and-braces copy the mission asked for (a row whose
# target exists on disk is also how a rename can never silently deselect).
EXTRA_SUITE_MAP="leadv2-dispatch-code:plugins/leadv2/tests/test-arm-pool-reachability.sh
leadv2-route-arbiter:plugins/leadv2/tests/test-arm-pool-reachability.sh
leadv2-routing.yaml:plugins/leadv2/tests/test-arm-pool-reachability.sh
leadv2-glm-policy-resolve:plugins/leadv2/tests/test-arm-pool-reachability.sh
leadv2-glm-policy-resolve.py:plugins/leadv2/tests/test-arm-pool-reachability.sh
leadv2-phase-record:plugins/leadv2/scripts/tests/test-phase-record-class.sh
leadv2-dispatch-code:plugins/leadv2/tests/test-exclusion-stages.sh
leadv2-route-arbiter:plugins/leadv2/tests/test-exclusion-stages.sh
leadv2-routing.yaml:plugins/leadv2/tests/test-exclusion-stages.sh
"

# --- self-registration discovery (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01) ----
# A declaration line is exactly "# run-all-triggers:" followed by a
# whitespace/comma-separated list of triggers; each trigger matches
# [A-Za-z0-9._-]+. A declaration that cannot be parsed (empty list, invalid
# character) is a FATAL error naming the file — the suite is never silently
# unselected. Runs on EVERY invocation so a typo goes red at authoring time,
# not at review time.
DISCOVERED_SUITE_MAP=""
TRIGGER_ERRORS=""

parse_suite_triggers() { # <suite-relpath> <declaration lines>
  local _rel="$1" _line _pfx _spec _toks _tok _n
  _pfx='# run-all-triggers:'
  while IFS= read -r _line; do
    [[ -n "${_line}" ]] || continue
    _spec="${_line#"${_pfx}"}"
    _n=0
    _toks="$(printf '%s' "${_spec}" | tr ',' ' ' | tr -s '[:space:]' '\n')"
    while IFS= read -r _tok; do
      [[ -n "${_tok}" ]] || continue
      case "${_tok}" in
        *[!A-Za-z0-9._-]*)
          TRIGGER_ERRORS="${TRIGGER_ERRORS}${_rel}: invalid trigger '${_tok}' (allowed [A-Za-z0-9._-])
" ;;
        *)
          _n=$((_n + 1))
          DISCOVERED_SUITE_MAP="${DISCOVERED_SUITE_MAP}${_tok}:${_rel}
" ;;
      esac
    done <<< "${_toks}"
    if [[ ${_n} -eq 0 ]]; then
      TRIGGER_ERRORS="${TRIGGER_ERRORS}${_rel}: declaration with no triggers
"
    fi
  done <<< "$2"
}

scan_suite_triggers() {
  local _dir _file _hits
  for _dir in "${ROOT}/plugins/leadv2/scripts/tests" \
              "${ROOT}/.claude/scripts/tests" \
              "${ROOT}/plugins/leadv2/tests" \
              "${ROOT}/tests"; do
    [[ -d "${_dir}" ]] || continue
    while IFS= read -r _file; do
      [[ -n "${_file}" ]] || continue
      _hits="$(grep -h '^# run-all-triggers:' "${_file}" 2>/dev/null || true)"
      [[ -n "${_hits}" ]] || continue
      parse_suite_triggers "${_file#"${ROOT}/"}" "${_hits}"
    # C5 (GATE-DISCOVERS-246-UNTRACKED-SUITES-01): a suite runs only if
    # something tracked admits it. Count mode leaves a proportional, visible
    # refusal signal without emitting one line per untracked file on every run.
    done < <(bash "${ROOT}/plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh" --root "${ROOT}" --dir "${_dir}" --skip-report=count)
  done
  if [[ -n "${TRIGGER_ERRORS}" ]]; then
    printf '%s' "${TRIGGER_ERRORS}" >&2
    echo "run-all: FATAL bad_trigger_decl — a malformed '# run-all-triggers:' declaration is an error, never a silently unselected suite; fix the suite file(s) listed above" >&2
    exit 2
  fi
}

scan_suite_triggers
ALL_SUITE_MAP="${EXTRA_SUITE_MAP}${DISCOVERED_SUITE_MAP}"

# Human/CI seam: print the discovered stem->suite rows and exit (no suites run).
if [[ "${LEADV2_RUN_ALL_LIST_TRIGGERS:-0}" == "1" ]]; then
  printf '%s' "${DISCOVERED_SUITE_MAP}"
  exit 0
fi

# ── changed-scope range resolution (B6-SCOPE-CHANGED) ──────────────────────
# SCOPE-CHANGED-IS-STATEFUL-AND-A-SECOND-RUN-LIES-01 +
# SCOPE-CHANGED-DEGRADES-TO-THE-LAST-COMMIT-01: --scope changed used to pick
# its diff range from the per-git-dir checkpoint written by the PREVIOUS run
# (so the same question twice gave different answers — a correctly registered
# suite could look unregistered on the second run), and with no checkpoint
# and no resolvable main/origin/main it silently degraded to HEAD~1..HEAD —
# the last commit only, a plausible wrong answer on any multi-commit branch.
# Both lies are fixed by resolving the range through ONE function with two
# named semantics the caller chooses explicitly:
#   changed       -> "what does this branch change": <merge-base>..HEAD plus
#                    the uncommitted diff. STATELESS — the checkpoint is
#                    neither read nor written, so the same question twice is
#                    the same answer, residue or no residue.
#   changed-since -> "what changed since the last changed-since run": the
#                    checkpoint anchor when one exists, merge-base fallback
#                    on the first run, HEAD recorded after. The old default
#                    (round-4, HOOK-OUTPUT-CAP-PLUGIN-01: a plain merge-base
#                    anchor re-selects every already-tested lane commit on
#                    every future unrelated commit), kept — not deleted —
#                    behind an explicit flag because repeated incremental
#                    gate runs on one lane are its legitimate use.
# run-core-offline.sh deliberately has NO incremental mode (see the comment
# above its _core_offline_scope_changed_select): its narrowed set IS the
# whole gate, so skipping already-tested commits there would green on
# partial coverage.
#
# DECLARED NEGATIVE CONTROLS (E2E-KILLRATE-01), applied by
# leadv2-mutation-control.sh to the marker lines INSIDE scope_changed_
# anchor's body:
#   M1 scope-changed-mut-1: make the checkpoint visible under --scope changed
#      again (lie (a) reintroduced) -> test-scope-changed-is-deterministic.sh
#      case 1 goes RED: the second --scope changed run selects fewer suites
#      than the first, selected-set equality fails.
#   M2 scope-changed-mut-2: degrade an unresolvable base back to HEAD~1..HEAD
#      (lie (b) reintroduced) -> case 2 goes RED: rc=0 with a selected set
#      instead of rc=2 + the named no_base_ref refusal.
# A top-level insert is NOT a valid control for this suite: it reddens every
# suite invocation for the wrong reason and reads as a pass.
scope_changed_anchor() { # -> prints <range-start>; rc 1 + named reason on refusal
  local _base_ref="" _merge_base="" _anchor=""
  for _cand in main origin/main; do
    if git -C "${ROOT}" rev-parse --verify "${_cand}" >/dev/null 2>&1; then
      _base_ref="${_cand}"
      break
    fi
  done
  if [[ -n "${_base_ref}" ]]; then
    _merge_base="$(git -C "${ROOT}" merge-base HEAD "${_base_ref}" 2>/dev/null || true)"
  fi
  _anchor="${_merge_base}"
  # scope-changed-mut-1: the checkpoint is deliberately visible ONLY to
  # --scope changed-since. Under --scope changed this guard stays closed —
  # that closed guard IS the fix for the second-run lie: residue from an
  # earlier run must not change the answer.
  if [[ "${SCOPE}" == "changed-since" ]]; then   # scope-changed-mut-1 anchor
    local _git_dir _state_file _saved=""
    _git_dir="$(git -C "${ROOT}" rev-parse --git-dir 2>/dev/null || true)"
    _state_file=""
    if [[ -n "${_git_dir}" ]]; then
      case "${_git_dir}" in
        /*) : ;;
        *) _git_dir="${ROOT}/${_git_dir}" ;;
      esac
      _state_file="${_git_dir}/leadv2-run-all-last-checked-sha"
    fi
    if [[ -n "${_state_file}" && -f "${_state_file}" ]]; then
      _saved="$(cat "${_state_file}" 2>/dev/null || true)"
      if [[ -n "${_saved}" ]] && ! git -C "${ROOT}" rev-parse --verify "${_saved}^{commit}" >/dev/null 2>&1; then
        _saved=""
      fi
    fi
    if [[ -n "${_saved}" ]]; then
      _anchor="${_saved}"
    fi
  fi
  if [[ -z "${_anchor}" ]]; then
    # scope-changed-mut-2: a selection answer without a resolvable base would
    # be plausible and wrong — the old code fell through to HEAD~1..HEAD here.
    echo "run-all: FATAL no_base_ref (--scope ${SCOPE}: neither 'main' nor 'origin/main' gives a merge-base against HEAD, and no valid checkpoint applies) — refusing rather than silently degrading to HEAD~1..HEAD; a selection made from the last commit alone is plausible and wrong (SCOPE-CHANGED-DEGRADES-TO-THE-LAST-COMMIT-01). Fix the base ref or ask --scope all." >&2
    return 1  # scope-changed-refusal
  fi
  printf '%s\n' "${_anchor}"
}

# Best-effort checkpoint advance — ONLY under --scope changed-since. A write
# failure must never fail the test run; tmp+mv keeps concurrent invocations
# in the same worktree from reading a half-written file. --scope changed
# never writes it: its answer must not leave residue that moves a later
# run's goalposts (the other half of the same row).
scope_changed_checkpoint_record() {
  [[ "${SCOPE}" == "changed-since" ]] || return 0
  local _git_dir _state_file _head_sha
  _git_dir="$(git -C "${ROOT}" rev-parse --git-dir 2>/dev/null || true)"
  [[ -n "${_git_dir}" ]] || return 0
  case "${_git_dir}" in
    /*) : ;;
    *) _git_dir="${ROOT}/${_git_dir}" ;;
  esac
  _state_file="${_git_dir}/leadv2-run-all-last-checked-sha"
  _head_sha="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "${_head_sha}" ]] || return 0
  printf '%s\n' "${_head_sha}" > "${_state_file}.tmp.$$" 2>/dev/null \
    && mv -f "${_state_file}.tmp.$$" "${_state_file}" 2>/dev/null
}

if [[ "${SCOPE}" == "all" ]]; then
  # C5 (GATE-DISCOVERS-246-UNTRACKED-SUITES-01): never consume a suite
  # list whose git admission cannot be proved. Names + summary are intentional
  # here: a full sweep must make every refusal loud.
  _c5_list="$(mktemp "${TMPDIR:-/tmp}/run-all-discovery.XXXXXX")" || exit 2
  if ! bash "${ROOT}/plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh" --root "${ROOT}" > "${_c5_list}"; then
    rm -f "${_c5_list}"
    exit 2
  fi
  while IFS= read -r f; do add_suite "$f"; done < "${_c5_list}"
  rm -f "${_c5_list}"
else
  # Union the uncommitted diff with the range scope_changed_anchor resolved.
  # B6-SCOPE-CHANGED: deterministic merge-base anchor for --scope changed,
  # checkpoint anchor for --scope changed-since, and a named refusal (exit 2)
  # — never a quiet HEAD~1..HEAD — when no anchor resolves.
  changed="$(git -C "${ROOT}" diff --name-only HEAD 2>/dev/null)"
  if ! _range_start="$(scope_changed_anchor)"; then
    exit 2   # the named refusal reason is already on stderr
  fi
  scope_changed_checkpoint_record
  changed="${changed}
$(git -C "${ROOT}" diff --name-only "${_range_start}..HEAD" 2>/dev/null)"
  if [[ -n "${changed}" ]]; then
    while IFS= read -r cf; do
      # A changed test suite must select itself even when its matching
      # production file did not change in this run.
      case "${cf}" in
        plugins/leadv2/scripts/tests/test-*.sh|.claude/scripts/tests/test-*.sh|plugins/leadv2/tests/test-*.sh|tests/test-*.sh)
          add_suite "${ROOT}/${cf}"
          ;;
      esac
      # FORK-STORM-KILLS-HOOKS-01: the hook table (hooks.json) and hook
      # scripts (plugins/leadv2/hooks/*.sh) are continued by the
      # [[ scripts || lib ]] guard below, so they never reached the
      # stem-comparison loop and a hooks.json-only change ran zero suites.
      # Synthetic stem, freepool-arm.yaml precedent: map row + convention
      # candidate here, then continue.
      case "${cf}" in
        plugins/leadv2/hooks/hooks.json) stem="hooks.json" ;;
        plugins/leadv2/hooks/*.sh) stem="$(basename "${cf}" .sh)" ;;
        *) stem="" ;;
      esac
      if [[ -n "${stem}" ]]; then
        for cand in "${ROOT}/plugins/leadv2/scripts/tests/test-${stem}.sh" \
                    "${ROOT}/tests/test-${stem}.sh"; do
          add_suite "${cand}"
        done
        while IFS= read -r row; do
          [[ -n "$row" ]] || continue
          key="${row%%:*}"
          [[ "$key" == "${stem}" || "$key" == "${stem}.sh" ]] || continue
          add_suite "${ROOT}/${row#*:}"
        done <<< "${ALL_SUITE_MAP}"
        continue
      fi
      # PROMISE-GUARD-BIND-01: hooks/*.sh changes (e.g. leadv2-promise-guard.sh)
      # never matched this filter, so a hook fix ran zero suites under
      # --scope changed -- the EXTRA_SUITE_MAP below only fires once a
      # changed file reaches the stem-comparison loop.
      # FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01: a data-only change to the arm
      # ranking must select the suites that grade it, so freepool-arm.yaml
      # maps to its own stem.
      # DISPATCH-CLOSE-GATE-01: scripts/lib/*.sh added -- a bare scripts/*.sh glob
      # never matches a subdirectory, so a lib-only change never reached this loop.
      # PLUGIN-PAPERCUTS-01 repair: this block was a bad merge — an unterminated
      # `$(basename "${cf}" .sh)` and a stray `continue"` left the two stem
      # halves interleaved inside unbalanced quotes. Rewritten as ONE if/elif
      # chain with the same documented behaviours: config yaml special stems,
      # the scripts/lib/hooks allowlist, and the synthetic .gitignore stem.
      if [[ "${cf}" == "plugins/leadv2/config/freepool-arm.yaml" ]]; then
        # FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01: data-only arm-ranking change must
        # select the suites that grade it.
        stem="freepool-arm.yaml"
      elif [[ "${cf}" == "plugins/leadv2/config/leadv2-routing.yaml" ]] \
          || [[ "${cf}" == ".claude/ref/leadv2-routing.yaml" ]]; then
        # PLUGIN-PAPERCUTS-01: a data-only routing change (arm cells, tiers)
        # must select the suites that grade routing, same shape as
        # freepool-arm.yaml above.
        # PLUGIN-REPO-CARRIES-A-SHADOW-ROUTING-CONFIG-01: the tenant DELTA at
        # .claude/ref/ is a production routing config now (merged over the
        # canonical by lib/leadv2-routing-config.sh); it shares the canonical
        # stem so a delta edit selects the suites that grade routing.
        stem="leadv2-routing.yaml"
      elif [[ "${cf}" == "plugins/leadv2/config/model-capability.yaml" ]]; then
        # FABLE-THINK-TIER-01 R6: a data-only capability change must select
        # the think-tier contract suite (same shape as freepool-arm.yaml).
        stem="model-capability.yaml"
      elif [[ "${cf}" == "plugins/leadv2/ref/leadv2-main-model.yaml" ]]; then
        # LEAD-IS-OPUS-THINK-IS-FABLE-01: a data-only main-model default
        # change must select the think-tier split contract suite (same shape
        # as model-capability.yaml above) — ref/*.yaml is not under
        # plugins/leadv2/scripts/, so the generic scripts/*.sh|*.py allowlist
        # below never reaches it and the file would otherwise select zero
        # suites under --scope changed.
        stem="leadv2-main-model.yaml"
      elif [[ "${cf}" == "plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py" ]]; then
        # FABLE-THINK-TIER-01 R6: the policy resolver is a py carrier of the
        # think-tier contract — the scripts/*.sh allowlist below never saw it.
        stem="leadv2-glm-policy-resolve.py"
      elif [[ "${cf}" == "plugins/leadv2/scripts/lib/leadv2-routing-merge.py" ]]; then
        # PLUGIN-REPO-CARRIES-A-SHADOW-ROUTING-CONFIG-01: the routing merge
        # engine — lib/*.py reaches no allowlist below, and a merge-semantics
        # change must select its suite, same shape as the row above.
        stem="leadv2-routing-merge.py"
      elif [[ "${cf}" == plugins/leadv2/workflows/*.js ]]; then
        # FABLE-THINK-TIER-01 R6: the four THINK workflows (diverge/learn/
        # diagnose/po-feedback-loop) are js carriers — the R5 map rows were
        # dead because the loop continued before any non-.sh reached here.
        stem="$(basename "${cf}")"
      elif [[ "${cf}" == ".claude/leadv2-overrides/status-collector-facts.sh" ]]; then
        # CODE-INTEL-IS-INSTALLED-AND-UNUSED-01 item 5: the repo_facts hook
        # lives under .claude/leadv2-overrides/, not plugins/leadv2/scripts/,
        # so the generic scripts/*.sh allowlist below never reaches it and a
        # hook-only change would otherwise select zero suites under
        # --scope changed (same shape as .gitignore below).
        stem="status-collector-facts"
      elif [[ "${cf}" == ".gitignore" ]]; then
        # HANDOFF-ARTIFACTS-GITIGNORED-01: .gitignore isn't a plugins/leadv2
        # script, so it needs its own synthetic stem to reach EXTRA_SUITE_MAP
        # below — the blanket-vs-allowlist rule it carries has no test-*.sh
        # of its own name to match by convention.
        stem="gitignore"
      elif [[ "${cf}" == "tests/run-all.sh" ]]; then
        # FABLE-THINK-TIER-01 R7: the carrier map row for run-all.sh must be
        # reachable so the test suite for the carrier map can be selected.
        stem="run-all.sh"
      else
        case "${cf}" in
          plugins/leadv2/scripts/*.sh|plugins/leadv2/scripts/lib/*.sh|plugins/leadv2/scripts/*.py|plugins/leadv2/hooks/*.sh) ;;
          *) continue ;;
        esac
        # GATE-PROVES-ITS-OWN-CONTROL-01: lib/*.sh is a real production call
        # path (leadv2-control-prover.sh lives there) — a stem-scan that only
        # sees plugins/leadv2/scripts/*.sh never reaches it, so lib/ is scanned
        # too, not just the top-level scripts.
        # NUDGE-TAX-01: scripts/*.py joins the allowlist (leadv2-loop-detect.py
        # is the loop guard's real brain — a change there used to select ZERO
        # suites under --scope changed). Stem strips the real extension.
        stem="$(basename "${cf}")"
        stem="${stem%.*}"
      fi
      for cand in "${ROOT}/plugins/leadv2/scripts/tests/test-${stem}.sh" \
                  "${ROOT}/.claude/scripts/tests/test-${stem}.sh" \
                  "${ROOT}/plugins/leadv2/tests/test-${stem}.sh" \
                  "${ROOT}/tests/test-${stem}.sh"; do
        add_suite "${cand}"
      done
      # MON-PULSE-01: extra suites mapped to this changed stem (key may be the
      # bare stem or the full filename — both accepted; PHASE-DISCIPLINE-01
      # rows migrated into the same string map at the 2026-08-28 merge)
      while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        key="${row%%:*}"
        [[ "$key" == "${stem}" || "$key" == "${stem}.sh" ]] || continue
        add_suite "${ROOT}/${row#*:}"
      done <<< "${ALL_SUITE_MAP}"
    done <<< "${changed}"
  fi
fi

# Selection proof is intentionally non-executing: it lets a lane demonstrate
# that --scope changed will hand its suites to CI without starting the always-
# on core runner on a shared machine. Normal CI never sets this seam.
if [[ "${LEADV2_RUN_ALL_SELECT_ONLY:-0}" == "1" ]]; then
  for suite in ${SUITES[@]+"${SUITES[@]}"}; do printf '[SELECT] %s\n' "${suite}"; done
  printf 'run-all: %s selected, scope=%s, select_only=1\n' "${#SUITES[@]}" "${SCOPE}"
  exit 0
fi

for suite in ${SUITES[@]+"${SUITES[@]}"}; do
  printf '[RUN] %s\n' "${suite}"
  suite_log=""
  _ra_ceiling="$(_suite_ceiling_s)"
  if [[ "${suite}" == "${ROOT}/${CORE_OFFLINE_REL}" || "${suite}" == "${ROOT}/.claude/scripts/tests/run-core-offline.sh" ]]; then
    # Capture the wrapper transcript so the [CORE-OFFLINE] FAILED: labels can
    # be classified below, then stream it verbatim — ci-gate.sh re-parses the
    # same lines from this output, so nothing may be swallowed.
    # E2E-GATE-RUNS-ALL-94-SUITES-BECAUSE-run-all-SWALLOWS-SCOPE-01: forward
    # the scope this script itself was given. run-core-offline.sh has had its
    # own --scope contract since it added scope-aware selection, but nothing
    # upstream of it ever passed one through — it was always invoked bare, so
    # it always ran its full unscoped suite set regardless of --scope changed.
    core_scope_arg="$(core_offline_scope_arg)"
    printf 'run-all: delegating scope=%s to %s\n' "${core_scope_arg}" "${suite#"${ROOT}/"}"
    suite_log="$(mktemp "${TMPDIR:-/tmp}/run-all-core-offline.XXXXXX")"
    # The wrapper is a CONTAINER of suites, not a suite: under --scope all it
    # is DESIGNED to run long (the nightly full sweep, CI budget 120 min) and
    # it is the one place allow-listed suites still execute — ceilinging it
    # there would kill the gone-green surface. Budget scopes only.
    if core_offline_budget_skip_env; then
      _ra_wrapper_ceiling="$(_suite_ceiling_s)"
    else
      _ra_wrapper_ceiling=0
    fi
    _ra_ceiling="${_ra_wrapper_ceiling}"
    # B2-GATE-BUDGET-4: budget modes (changed/changed-since) additionally ask
    # the wrapper to skip allow-listed known-red nested suites — their
    # classification was already non-blocking (round 3), what they cost is
    # TIME inside the 900s close-gate budget. `env` (not a shell prefix on a
    # function call — that would leak the var past the call in bash) scopes
    # the request to this one invocation.
    if core_offline_budget_skip_env && [[ -f "${ALLOWLIST}" ]]; then
      _run_all_timeout_run "${_ra_ceiling}" "${suite_log}" -- \
        env LEADV2_CORE_OFFLINE_SKIP_KNOWN_RED=1 \
            LEADV2_CORE_OFFLINE_KNOWN_RED_FILE="${ALLOWLIST}" \
            bash "${suite}" --scope "${core_scope_arg}"
    else
      _run_all_timeout_run "${_ra_ceiling}" "${suite_log}" -- \
        bash "${suite}" --scope "${core_scope_arg}"
    fi
    rc=$?
    cat "${suite_log}"
    # Relay the wrapper's budget-mode skips loudly — attributable silence,
    # never a quiet drop. (Only budget-mode runs emit these; a wrapper too
    # old to honor the env prints none and nothing changes for it.)
    while IFS= read -r _ra_sk; do
      [[ -n "${_ra_sk}" ]] || continue
      printf '[KNOWN-RED-SKIP] core:%s — skipped in budget mode (scope=%s); still executed by --scope all (nightly full sweep)\n' "${_ra_sk}" "${SCOPE}"
      KNOWN_RED_SKIPPED=$((KNOWN_RED_SKIPPED + 1))
    done < <(grep -E '^\[CORE-OFFLINE\] KNOWN-RED-SKIP: ' "${suite_log}" 2>/dev/null | sed -E 's/^\[CORE-OFFLINE\] KNOWN-RED-SKIP: //')
    # B2-GATE-BUDGET-4 red->green surfacing: in a FULL-set run (--scope all,
    # or a narrowed run that failed open to the full set) every allow-listed
    # label had its chance to run — one absent from FAILED/MISSING/SKIP
    # lines PASSED. Say so, so the allow-list cannot become permanent (it may
    # only shrink). Full-set is decided from what run-all ITSELF asked for
    # plus the wrapper's own verdict line — never from the mere absence of a
    # SCOPE_RESULT line (a truncated or foreign transcript under
    # --scope changed is not evidence of a full run), and never without the
    # suites-passed summary (a FATAL — lock timeout, harness crash — never
    # ran the suites and must not mint a false gone-green).
    # The "own" lines are POSITIONAL, not any-match: the wrapper prints its
    # SCOPE_RESULT BEFORE running suites, so its own is the FIRST one in the
    # transcript; a nested suite inside the run can only print later. The
    # wrapper prints its summary after everything, so its own is the LAST
    # suites-passed line AND must follow the last SCOPE_RESULT (a nested
    # test's transcript containing verdict=full_set_fallback + its own
    # suites-passed line once minted 14 false gone-greens from a 13-of-95
    # narrowed run — measured on this lane's own gate run 2026-09-09).
    _ra_own_scope="$(grep -E '^\[CORE-OFFLINE\] SCOPE_RESULT ' "${suite_log}" 2>/dev/null | head -1)"
    _ra_last_sr_ln="$(grep -nE '^\[CORE-OFFLINE\] SCOPE_RESULT ' "${suite_log}" 2>/dev/null | tail -1 | cut -d: -f1)"
    _ra_last_sum_ln="$(grep -nE '^\[CORE-OFFLINE\] suites passed=' "${suite_log}" 2>/dev/null | tail -1 | cut -d: -f1)"
    if [[ -n "${_ra_last_sum_ln}" \
          && ( -z "${_ra_last_sr_ln}" || "${_ra_last_sum_ln}" -gt "${_ra_last_sr_ln}" ) ]] \
       && { [[ "${core_scope_arg}" == "all" ]] \
            || grep -q 'verdict=full_set_fallback' <<<"${_ra_own_scope}"; }; then
      while IFS= read -r _ra_gg; do
        [[ -n "${_ra_gg}" ]] || continue
        if ! grep -qF -- "[CORE-OFFLINE] FAILED: ${_ra_gg}" "${suite_log}" 2>/dev/null \
           && ! grep -qF -- "[CORE-OFFLINE] MISSING: ${_ra_gg}" "${suite_log}" 2>/dev/null \
           && ! grep -qF -- "[CORE-OFFLINE] SKIP: ${_ra_gg}" "${suite_log}" 2>/dev/null \
           && ! grep -qF -- "[CORE-OFFLINE] KNOWN-RED-SKIP: ${_ra_gg}" "${suite_log}" 2>/dev/null; then
          printf '[KNOWN-RED-GONE-GREEN] core:%s — passed a full-set run; remove the entry from tests/known-red-suites.txt (the list may only shrink)\n' "${_ra_gg}"
          GONE_GREEN=$((GONE_GREEN + 1))
        fi
      done < <(grep -vE '^[[:space:]]*(#|$)' "${ALLOWLIST}" 2>/dev/null | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' | sed -n 's/^core://p')
    fi
  else
    if [[ "${_ra_ceiling}" -gt 0 ]]; then
      suite_log="$(mktemp "${TMPDIR:-/tmp}/run-all-suite.XXXXXX")"
      _run_all_timeout_run "${_ra_ceiling}" "${suite_log}" -- bash "${suite}"
      rc=$?
      cat "${suite_log}"
    else
      bash "${suite}"
      rc=$?
    fi
  fi
  # B2-GATE-BUDGET-4: rc=124 from the ceiling is a NAMED, per-suite verdict —
  # printed before classification so a killed wrapper can never be laundered
  # into [KNOWN-RED] by the partial transcript it managed to emit first.
  if [[ ${rc} -eq 124 ]]; then
    _ra_rel="${suite#"${ROOT}/"}"
    [[ "${_ra_rel}" == "${suite}" ]] && _ra_rel="${suite}"
    printf '[SUITE-TIMEOUT] %s exceeded %ss ceiling (killed by run-all; counted as a blocking failure with a named cause)\n' "${_ra_rel}" "${_ra_ceiling}"
  fi
  if [[ ${rc} -eq 0 ]]; then
    printf '[PASS] %s\n' "${suite}"
    PASS=$((PASS + 1))
    [[ -n "${suite_log}" ]] && rm -f "${suite_log}"
    continue
  fi
  # C4 (GATE-WRONG-ROOT-FALSE-DEAD-01): record repo-relative path for the
  # machine-readable failure block (consumed by leadv2-e2e-ownership.sh).
  rel="${suite#"${ROOT}/"}"
  [[ "${rel}" == "${suite}" ]] && rel="${suite}"   # outside ROOT → absolute
  classified=0
  # rc=124 (ceiling kill) is exempt from classification on purpose: a killed
  # wrapper's partial transcript cannot prove the un-run remainder was all
  # allow-listed — the old "zero parsed FAILED -> blocking fail-closed" rule
  # extended to "killed -> blocking, named" (B2-GATE-BUDGET-4).
  if [[ -n "${suite_log}" && ${rc} -ne 124 ]]; then
    declare -a KNOWN_NAMES=() UNEXPECTED_NAMES=()
    while IFS= read -r name; do
      [[ -n "${name}" ]] || continue
      if is_known_red "core:${name}"; then
        KNOWN_NAMES+=("${name}")
      else
        UNEXPECTED_NAMES+=("${name}")
      fi
    done < <(grep -E '^\[CORE-OFFLINE\] FAILED: ' "${suite_log}" | sed -E 's/^\[CORE-OFFLINE\] FAILED: //')
    if [[ ${#KNOWN_NAMES[@]} -gt 0 && ${#UNEXPECTED_NAMES[@]} -eq 0 ]]; then
      printf '[KNOWN-RED] %s (every failing nested suite is allow-listed)\n' "${rel}"
      for n in "${KNOWN_NAMES[@]}"; do
        printf '    - core:%s\n' "${n}"
      done
      KNOWN=$((KNOWN + 1))
      classified=1
    else
      for n in "${UNEXPECTED_NAMES[@]:-}"; do
        [[ -n "${n}" ]] || continue
        printf '[NOT-KNOWN-RED] core:%s — failing nested suite is NOT on %s\n' "${n}" "tests/known-red-suites.txt"
      done
    fi
    rm -f "${suite_log}"
  fi
  if [[ ${classified} -eq 1 ]]; then
    continue
  fi
  printf '[FAIL] %s\n' "${suite}"
  FAIL=$((FAIL + 1))
  FAILED_REL+=("${rel}")
done

# C4: emit the Failures (blocking) block that leadv2-e2e-ownership.sh already
# documents as the contract. Suite names are repo-relative to ROOT so the
# classifier can locate them in the scratch tree by direct path. Known-red
# (allow-listed) wrapper failures are deliberately NOT in this block — that is
# the whole point of round 3; they are reported on their own [KNOWN-RED] lines
# and in the summary count below, so the silence is attributable.
if [[ ${FAIL} -gt 0 ]]; then
  printf '  Failures (blocking):\n'
  for rel in "${FAILED_REL[@]:-}"; do
    printf '    - %s\n' "${rel}"
  done
fi

if [[ ${KNOWN} -gt 0 || ${KNOWN_RED_SKIPPED} -gt 0 || ${GONE_GREEN} -gt 0 ]]; then
  printf 'run-all: %d passed, %d failed, %d known-red (allow-listed, non-blocking), %d known-red-skipped (budget mode, still run by --scope all), %d gone-green (remove from allow-list), scope=%s\n' \
    "${PASS}" "${FAIL}" "${KNOWN}" "${KNOWN_RED_SKIPPED}" "${GONE_GREEN}" "${SCOPE}"
else
  printf 'run-all: %d passed, %d failed, scope=%s\n' "${PASS}" "${FAIL}" "${SCOPE}"
fi
(( FAIL == 0 ))
