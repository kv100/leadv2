#!/usr/bin/env bash
# tests/run-all.sh — canonical repo's e2e entrypoint (T-d, PRODUCT-READINESS-GATES-01
# follow-up, 2026-07-29). This is what leadv2-e2e-entrypoint.sh resolves to and what the
# product gates (leadv2-dispatch-product-close.sh, leadv2-phase8-e2e-gate.sh) execute.
#
# It does NOT author new suites — it drives the plugin's own curated offline regression
# runner (.claude/scripts/tests/run-core-offline.sh) plus, on `--scope changed`, any
# test-*.sh whose stem matches a changed file's stem under plugins/leadv2/scripts/.
#
# usage: tests/run-all.sh [--scope changed|all]
# exit 0: every selected suite passed
# exit 1: at least one suite failed
# exit 2: bad usage
set -uo pipefail

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
      echo "usage: tests/run-all.sh [--scope changed|all]" >&2
      exit 0 ;;
    *)
      echo "run-all: unknown argument: $1" >&2
      exit 2 ;;
  esac
done
case "${SCOPE}" in
  changed|all) ;;
  *) echo "run-all: --scope must be changed|all (got '${SCOPE}')" >&2; exit 2 ;;
esac

PASS=0
FAIL=0
KNOWN=0
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
  [[ -f "${ALLOWLIST}" ]] || return 1
  grep -qxF "$1" <(grep -vE '^[[:space:]]*(#|$)' "${ALLOWLIST}" | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//')
}
# Non-stem suite mappings live in EXTRA_SUITE_MAP below (string rows, one per
# line, "<stem>:<suite>"). The PHASE-DISCIPLINE-01 array form was migrated into
# it during the MON-PULSE-01 merge (2026-08-28) — one mechanism, not two.

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
EXTRA_SUITE_MAP=""

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
    done < <(find "${_dir}" -maxdepth 1 -type f -name 'test-*.sh' 2>/dev/null | sort)
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

if [[ "${SCOPE}" == "all" ]]; then
  while IFS= read -r f; do add_suite "$f"; done < <(
    find "${ROOT}/plugins/leadv2/scripts/tests" "${ROOT}/.claude/scripts/tests" "${ROOT}/plugins/leadv2/tests" "${ROOT}/tests" \
      -maxdepth 1 -type f -name 'test-*.sh' 2>/dev/null | sort
  )
else
  # Union uncommitted diff with the lane range NOT YET SEEN by a prior run of
  # this script (round-4, HOOK-OUTPUT-CAP-PLUGIN-01): a plain merge-base
  # anchor (round-3) unions in the WHOLE `<merge-base>..HEAD` range on every
  # invocation forever — every already-committed, already-tested commit on
  # the lane re-selects its suite on every future unrelated commit, growing
  # monotonically with lane length. Persist the last-checked SHA per git-dir
  # (worktree-scoped, so concurrent lanes never share the file) and diff from
  # THAT instead of the merge-base once it exists. First run on a lane (no
  # state file yet) still falls back to the merge-base, so a docs-only HEAD
  # with unrelated dirt still selects the lane's own suite (round-3's win).
  changed="$(git -C "${ROOT}" diff --name-only HEAD 2>/dev/null)"
  _base_ref=""
  for _cand in main origin/main; do
    if git -C "${ROOT}" rev-parse --verify "${_cand}" >/dev/null 2>&1; then
      _base_ref="${_cand}"
      break
    fi
  done
  _merge_base=""
  if [[ -n "${_base_ref}" ]]; then
    _merge_base="$(git -C "${ROOT}" merge-base HEAD "${_base_ref}" 2>/dev/null || true)"
  fi
  _git_dir="$(git -C "${ROOT}" rev-parse --git-dir 2>/dev/null || true)"
  _state_file=""
  if [[ -n "${_git_dir}" ]]; then
    case "${_git_dir}" in
      /*) : ;;
      *) _git_dir="${ROOT}/${_git_dir}" ;;
    esac
    _state_file="${_git_dir}/leadv2-run-all-last-checked-sha"
  fi
  _range_start=""
  if [[ -n "${_state_file}" && -f "${_state_file}" ]]; then
    _range_start="$(cat "${_state_file}" 2>/dev/null || true)"
    if [[ -n "${_range_start}" ]] && ! git -C "${ROOT}" rev-parse --verify "${_range_start}^{commit}" >/dev/null 2>&1; then
      _range_start=""
    fi
  fi
  if [[ -z "${_range_start}" ]]; then
    _range_start="${_merge_base}"
  fi
  if [[ -n "${_range_start}" ]]; then
    changed="${changed}
$(git -C "${ROOT}" diff --name-only "${_range_start}..HEAD" 2>/dev/null)"
  elif git -C "${ROOT}" rev-parse HEAD~1 >/dev/null 2>&1; then
    changed="${changed}
$(git -C "${ROOT}" diff --name-only HEAD~1..HEAD 2>/dev/null)"
  fi
  # Record this run's HEAD as "checked" so a future clean-HEAD run only sees
  # what's newly dirty, not the whole lane range again. Best-effort (a
  # write failure must never fail the test run) — tmp+mv keeps concurrent
  # invocations in the same worktree from reading a half-written file.
  if [[ -n "${_state_file}" ]]; then
    _head_sha="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "${_head_sha}" ]]; then
      printf '%s\n' "${_head_sha}" > "${_state_file}.tmp.$$" 2>/dev/null \
        && mv -f "${_state_file}.tmp.$$" "${_state_file}" 2>/dev/null
    fi
  fi
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
      elif [[ "${cf}" == "plugins/leadv2/config/leadv2-routing.yaml" ]]; then
        # PLUGIN-PAPERCUTS-01: a data-only routing change (arm cells, tiers)
        # must select the suites that grade routing, same shape as
        # freepool-arm.yaml above.
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
      elif [[ "${cf}" == plugins/leadv2/workflows/*.js ]]; then
        # FABLE-THINK-TIER-01 R6: the four THINK workflows (diverge/learn/
        # diagnose/po-feedback-loop) are js carriers — the R5 map rows were
        # dead because the loop continued before any non-.sh reached here.
        stem="$(basename "${cf}")"
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
  if [[ "${suite}" == "${ROOT}/${CORE_OFFLINE_REL}" || "${suite}" == "${ROOT}/.claude/scripts/tests/run-core-offline.sh" ]]; then
    # Capture the wrapper transcript so the [CORE-OFFLINE] FAILED: labels can
    # be classified below, then stream it verbatim — ci-gate.sh re-parses the
    # same lines from this output, so nothing may be swallowed.
    suite_log="$(mktemp "${TMPDIR:-/tmp}/run-all-core-offline.XXXXXX")"
    bash "${suite}" >"${suite_log}" 2>&1
    rc=$?
    cat "${suite_log}"
  else
    bash "${suite}"
    rc=$?
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
  if [[ -n "${suite_log}" ]]; then
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

if [[ ${KNOWN} -gt 0 ]]; then
  printf 'run-all: %d passed, %d failed, %d known-red (allow-listed, non-blocking), scope=%s\n' \
    "${PASS}" "${FAIL}" "${KNOWN}" "${SCOPE}"
else
  printf 'run-all: %d passed, %d failed, scope=%s\n' "${PASS}" "${FAIL}" "${SCOPE}"
fi
(( FAIL == 0 ))
