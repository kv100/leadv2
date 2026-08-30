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

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
declare -a SUITES=()
declare -a FAILED_REL=()
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
  for existing in "${SUITES[@]:-}"; do
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

# MON-PULSE-01: EXTRA_SUITE_MAP — "<changed-stem>:<suite>" rows, one per line.
# A changed plugin script whose behavioural lock lives in a DIFFERENTLY-NAMED
# suite (the dispatch-code arming seam is proven by the pulse-watch suites,
# not by any test-dispatch-code.sh) is mapped here so --scope changed still
# runs its suite instead of silently dropping it.
EXTRA_SUITE_MAP="leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh
freepool-coder:plugins/leadv2/scripts/tests/test-freepool-model-selector.sh
leadv2-backlog-pump:plugins/leadv2/scripts/tests/test-backlog-pump.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-phase-precondition.sh
leadv2-gate1-prompt:plugins/leadv2/scripts/tests/test-gate1-discipline.sh
leadv2-phase-record:plugins/leadv2/scripts/tests/test-phase-record.sh
leadv2-phase-record:plugins/leadv2/scripts/tests/test-phase-precondition.sh
leadv2-admission-class:plugins/leadv2/scripts/tests/test-admission-class.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-route-arbiter-symlink-install.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-model-select-telemetry.sh
leadv2-lane-pulse-watch.sh:plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh
leadv2-single-lead-beat-loop.sh:plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh
leadv2-lane-pulse-watch.sh:plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-mission-writeset.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-red-proof-gate.sh
leadv2-mission-writeset:plugins/leadv2/scripts/tests/test-mission-writeset.sh
leadv2-red-proof:plugins/leadv2/scripts/tests/test-red-proof-gate.sh"

if [[ "${SCOPE}" == "all" ]]; then
  while IFS= read -r f; do add_suite "$f"; done < <(
    find "${ROOT}/plugins/leadv2/scripts/tests" "${ROOT}/.claude/scripts/tests" "${ROOT}/plugins/leadv2/tests" "${ROOT}/tests" \
      -maxdepth 1 -type f -name 'test-*.sh' 2>/dev/null | sort
  )
else
  # DISPATCH-CLOSE-GATE-01 round-3: a real dirty lane usually has docs-only working-tree
  # dirt (journals, bus offsets, active.yaml) SITTING ON TOP OF already-committed source
  # changes for this round. `git diff --name-only HEAD` alone only sees the former --
  # a non-empty docs-only diff short-circuited the old code before it ever looked at what
  # was actually committed on this branch, so the widened lib/*.sh glob and the new
  # EXTRA_SUITE_MAP rows were unreachable on the exact lane they exist for. Union both
  # signals: uncommitted dirt AND everything committed since this branch's merge-base with
  # the default branch, so neither shadows the other.
  changed_dirty="$(git -C "${ROOT}" diff --name-only HEAD 2>/dev/null)"
  changed_committed=""
  _rall_default="$(git -C "${ROOT}" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  _rall_default="${_rall_default#origin/}"
  [[ -z "${_rall_default}" ]] && _rall_default="main"
  _rall_base="$(git -C "${ROOT}" merge-base HEAD "${_rall_default}" 2>/dev/null || true)"
  _rall_head="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || true)"
  if [[ -n "${_rall_base}" && "${_rall_base}" != "${_rall_head}" ]]; then
    changed_committed="$(git -C "${ROOT}" diff --name-only "${_rall_base}" HEAD 2>/dev/null)"
  fi
  changed="$(printf '%s\n%s\n' "${changed_dirty}" "${changed_committed}" | sed '/^$/d' | sort -u)"
  if [[ -z "${changed}" ]] && git -C "${ROOT}" rev-parse HEAD~1 >/dev/null 2>&1; then
    changed="$(git -C "${ROOT}" diff --name-only HEAD~1..HEAD 2>/dev/null)"
  fi
  if [[ -n "${changed}" ]]; then
    while IFS= read -r cf; do
      # DISPATCH-CLOSE-GATE-01: widened to include lib/*.sh -- a bare `scripts/*.sh` glob
      # never matches a subdirectory, so a lib-only change (e.g. lib/leadv2-mission-
      # writeset.sh) previously never reached the stem/EXTRA_SUITE_MAP lookup below at all.
      case "${cf}" in
        plugins/leadv2/scripts/*.sh|plugins/leadv2/scripts/lib/*.sh) ;;
        *) continue ;;
      esac
      stem="$(basename "${cf}" .sh)"
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
      done <<< "${EXTRA_SUITE_MAP}"
    done <<< "${changed}"
  fi
fi

for suite in "${SUITES[@]}"; do
  printf '[RUN] %s\n' "${suite}"
  if bash "${suite}"; then
    printf '[PASS] %s\n' "${suite}"
    PASS=$((PASS + 1))
  else
    printf '[FAIL] %s\n' "${suite}"
    FAIL=$((FAIL + 1))
    # C4 (GATE-WRONG-ROOT-FALSE-DEAD-01): record repo-relative path for the
    # machine-readable failure block (consumed by leadv2-e2e-ownership.sh).
    rel="${suite#"${ROOT}/"}"
    [[ "${rel}" == "${suite}" ]] && rel="${suite}"   # outside ROOT → absolute
    FAILED_REL+=("${rel}")
  fi
done

# C4: emit the Failures (blocking) block that leadv2-e2e-ownership.sh already
# documents as the contract. Suite names are repo-relative to ROOT so the
# classifier can locate them in the scratch tree by direct path. Additive —
# existing [FAIL] lines and the run-all: summary are untouched.
if [[ ${FAIL} -gt 0 ]]; then
  printf '  Failures (blocking):\n'
  for rel in "${FAILED_REL[@]}"; do
    printf '    - %s\n' "${rel}"
  done
fi

printf 'run-all: %d passed, %d failed, scope=%s\n' "${PASS}" "${FAIL}" "${SCOPE}"
(( FAIL == 0 ))
