#!/usr/bin/env bash
# leadv2-e2e-ownership.sh — GATE-FOREIGN-FAILURE-01
#
# Classifies each blocking failure from an already-run e2e gate log as OWN
# (the lane's own regression), FOREIGN (another lane's in-progress edit in
# the same shared working tree), or UNDECIDABLE (fail-closed to OWN by the
# caller). Reused by both e2e-gate callers (leadv2-dispatch-product-close.sh,
# leadv2-phase8-e2e-gate.sh) so there is exactly one classification mechanism.
#
# Mechanism: differential re-run against a lane-only tree. `git archive HEAD`
# gives a clean scratch checkout of the last COMMITTED state, then only the
# lane's own declared write set is overlaid from the real working tree on
# top of it. A blocking suite is the lane's own iff it still fails against
# that lane-only tree; if it only fails against the full (multi-lane-dirty)
# working tree, the regression belongs to whichever uncommitted edit the
# lane does not own.
#
# Deliberately NOT a reimplementation of tests/run-all.sh's
# map_changed_to_suites / EXTRA_SUITE_MAP (that would be a second, silently-
# driftable copy of repo-local mapping data). Suites are located by the
# existing tests/unit/<name> convention and re-executed directly.
#
# usage: leadv2-e2e-ownership.sh <root> <task_sig8> <writes_csv> <log_file>
# stdout (always, exit 0 — pure data contract, no journal writes of its own):
#   own=<csv>
#   foreign=<csv>
#   undecidable=<csv>
#   owner_lane=<sig8|unknown>
#   pre_existing=<csv>
#
# GATE-CHARGES-A-LANE-FOR-A-RED-IT-DID-NOT-CAUSE (HARNESS-COSTS-MORE-THAN-IT-
# CATCHES-01): ownership answers "does this suite fail with only YOUR files?"
# -- which is still yes for a suite that was ALREADY red before the lane
# branched. Every suite classified own is therefore re-run once more against
# the lane's own merge-base tree, with NO lane overlay at all. Fails there too
# -> the red predates the lane -> `pre_existing`, and it leaves `own`. Only a
# NEW red stays own. Fail-closed everywhere: no resolvable merge-base, no
# archive, suite absent at merge-base (the lane ADDED it), or the time budget
# spent -> the suite stays own and the lane still dies.
# Any preparation failure (archive, scratch dir, overlay) folds every
# blocking suite into `undecidable` — fail-closed to the caller's pre-fix
# (kill) behaviour, never silently permissive.
set -uo pipefail

ROOT="${1:?usage: leadv2-e2e-ownership.sh <root> <task_sig8> <writes_csv> <log_file>}"
TASK="${2:?task sig8 required}"
WRITES_CSV="${3:-}"
LOG_FILE="${4:?log file required}"

_emit() { # <own_csv> <foreign_csv> <undecidable_csv> <owner_lane> [pre_existing_csv]
  printf 'own=%s\nforeign=%s\nundecidable=%s\nowner_lane=%s\npre_existing=%s\n' \
    "$1" "$2" "$3" "${4:-unknown}" "${5:-}"
}
_join() { local IFS=,; echo "$*"; }

# ── parse the blocking-failure block out of the log (F) ─────────────────────
# tests/run-all.sh's exact summary shape:
#   "  Failures (blocking):"
#   "    - <suite-name>"   (one or more, until the next non-matching line)
mapfile -t F < <(awk '
  /^  Failures \(blocking\):$/ { infail=1; next }
  infail && /^    - / { sub(/^    - /, ""); print; next }
  { infail=0 }
' "${LOG_FILE}" 2>/dev/null)

if [[ ${#F[@]} -eq 0 ]]; then
  # rc != 0 but no parseable failure block (harness crash, pytest-not-installed,
  # a timeout before the summary printed) -- nothing to attribute, fail-closed.
  _emit "" "" "harness_unparsed" "unknown"
  exit 0
fi

if [[ -z "${WRITES_CSV}" ]]; then
  # Caller resolves the whole_tree_fallback branch itself when WRITES_CSV is
  # empty; if we're reached anyway, fail-closed to own so nothing regresses.
  _emit "$(_join "${F[@]}")" "" "" "unknown"
  exit 0
fi

IFS=',' read -r -a writes <<< "${WRITES_CSV}"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-e2e-own-${TASK}-$$.XXXX" 2>/dev/null)" || {
  _emit "$(_join "${F[@]}")" "" "" "unknown"
  exit 0
}
trap 'rm -rf "${SCRATCH}"' EXIT

if ! git -C "${ROOT}" archive HEAD 2>/dev/null | tar -x -C "${SCRATCH}" 2>/dev/null; then
  _emit "$(_join "${F[@]}")" "" "" "unknown"
  exit 0
fi

for w in "${writes[@]}"; do
  [[ -z "${w}" ]] && continue
  src="${ROOT}/${w}"
  [[ -f "${src}" ]] || continue
  dst="${SCRATCH}/${w}"
  mkdir -p "$(dirname "${dst}")" 2>/dev/null || continue
  cp "${src}" "${dst}" 2>/dev/null || true
done

own=()
foreign=()
undecidable=()
for suite in "${F[@]}"; do
  [[ -z "${suite}" ]] && continue
  # C5 (GATE-WRONG-ROOT-FALSE-DEAD-01): ordered suite location, first hit wins.
  # 1. ${SCRATCH}/${suite} — repo-relative path (what C4's run-all.sh emits,
  #    e.g. plugins/leadv2/scripts/tests/test-foo.sh or tests/unit/test-A.sh).
  # 2. ${SCRATCH}/tests/unit/${suite} — legacy basename convention (other repos,
  #    pre-C4 fixtures that emit basenames only).
  suite_path=""
  if [[ -f "${SCRATCH}/${suite}" ]]; then
    suite_path="${SCRATCH}/${suite}"
  elif [[ -f "${SCRATCH}/tests/unit/${suite}" ]]; then
    suite_path="${SCRATCH}/tests/unit/${suite}"
  fi
  if [[ -z "${suite_path}" ]]; then
    # Not a locatable tests/unit/<name> script (aggregate "pytest" name, a
    # "(missing)"/"(TIMEOUT)" suffixed entry, an E2E break-matrix suite,
    # etc.) -- cannot safely re-run in isolation. Fail-closed to own.
    undecidable+=("${suite}")
    continue
  fi
  if ( cd "${SCRATCH}" && timeout 120 env RUN_MODE=dry_run bash "${suite_path}" ) >/dev/null 2>&1; then
    foreign+=("${suite}")
  else
    own+=("${suite}")
  fi
done

# -- subtract the reds that predate the lane --------------------------------
_baseline_sha() { # <root> -> prints a merge-base sha, or nothing (exit 1)
  local root="$1" b mb
  for b in "${LEADV2_E2E_BASELINE_REF:-}" main origin/main master origin/master; do
    [[ -z "${b}" ]] && continue
    git -C "${root}" rev-parse --verify --quiet "${b}" >/dev/null 2>&1 || continue
    mb="$(git -C "${root}" merge-base HEAD "${b}" 2>/dev/null)" || continue
    [[ -n "${mb}" ]] || continue
    printf '%s\n' "${mb}"
    return 0
  done
  return 1
}

pre_existing=()
if [[ ${#own[@]} -gt 0 && "${LEADV2_E2E_BASELINE:-1}" != "0" ]]; then
  base_sha="$(_baseline_sha "${ROOT}" 2>/dev/null || true)"
  base_scratch=""
  if [[ -n "${base_sha}" ]]; then
    base_scratch="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-e2e-base-${TASK}-$$.XXXX" 2>/dev/null || true)"
    if [[ -n "${base_scratch}" ]]; then
      git -C "${ROOT}" archive "${base_sha}" 2>/dev/null | tar -x -C "${base_scratch}" 2>/dev/null \
        || base_scratch=""
    fi
  fi
  if [[ -n "${base_scratch}" ]]; then
    trap 'rm -rf "${SCRATCH}" "${base_scratch}"' EXIT
    budget="${LEADV2_E2E_BASELINE_BUDGET_S:-300}"
    started="$(date +%s 2>/dev/null || echo 0)"
    still_own=()
    for suite in "${own[@]}"; do
      [[ -z "${suite}" ]] && continue
      now="$(date +%s 2>/dev/null || echo 0)"
      if (( started > 0 && now - started >= budget )); then
        # Budget spent. Everything left is unmeasured, so it stays own.
        still_own+=("${suite}")   # unmeasured is not innocent
        continue
      fi
      base_path=""
      if [[ -f "${base_scratch}/${suite}" ]]; then
        base_path="${base_scratch}/${suite}"
      elif [[ -f "${base_scratch}/tests/unit/${suite}" ]]; then
        base_path="${base_scratch}/tests/unit/${suite}"
      fi
      if [[ -z "${base_path}" ]]; then
        # The suite does not exist at merge-base: the lane added it. A suite
        # that did not exist cannot have been red. Stays own.
        still_own+=("${suite}")   # absent at merge-base
        continue
      fi
      if ( cd "${base_scratch}" && timeout 120 env RUN_MODE=dry_run bash "${base_path}" ) >/dev/null 2>&1; then
        still_own+=("${suite}")        # green before the lane, red now -> NEW.
      else
        pre_existing+=("${suite}")     # red before the lane touched anything.
      fi
    done
    own=()
    [[ ${#still_own[@]} -gt 0 ]] && own=("${still_own[@]}")
  fi
fi

owner_lane="unknown"
if [[ ${#foreign[@]} -gt 0 ]]; then
  mapfile -t all_changed < <(
    { git -C "${ROOT}" diff --name-only HEAD -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null
      git -C "${ROOT}" ls-files --others --exclude-standard -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null; } | sort -u
  )
  foreign_files=()
  for f in "${all_changed[@]}"; do
    [[ -z "${f}" ]] && continue
    is_write=0
    for w in "${writes[@]}"; do [[ "${f}" == "${w}" ]] && { is_write=1; break; }; done
    (( is_write )) || foreign_files+=("${f}")
  done
  # Best-effort: whichever other lane's declared LANE_WRITES intersects the
  # foreign file set. No match (or no other prepass artifacts yet) -> unknown,
  # never a hard failure.
  if [[ ${#foreign_files[@]} -gt 0 ]]; then
    for prepass in "${ROOT}"/docs/handoff/dispatch-*/architect-prepass.md; do
      [[ -f "${prepass}" ]] || continue
      other_sig8="$(basename "$(dirname "${prepass}")")"
      other_sig8="${other_sig8#dispatch-}"
      [[ "${other_sig8}" == "${TASK}" ]] && continue
      other_line="$(grep -m1 -iE '^[[:space:]*_]*LANE_WRITES[*_]*:' "${prepass}" 2>/dev/null | sed -E 's/^[[:space:]*_]*LANE_WRITES[*_]*:[[:space:]]*//I')"
      [[ -z "${other_line}" ]] && continue
      IFS=',' read -r -a other_writes <<< "${other_line}"
      matched=0
      for fw in "${foreign_files[@]}"; do
        for ow in "${other_writes[@]}"; do
          ow="$(printf '%s' "${ow}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
          if [[ "${fw}" == "${ow}" ]]; then
            owner_lane="${other_sig8}"
            matched=1
            break
          fi
        done
        [[ ${matched} -eq 1 ]] && break
      done
      [[ ${matched} -eq 1 ]] && break
    done
  fi
fi

_emit "$(_join "${own[@]:-}")" "$(_join "${foreign[@]:-}")" "$(_join "${undecidable[@]:-}")" \
  "${owner_lane}" "$(_join "${pre_existing[@]:-}")"
