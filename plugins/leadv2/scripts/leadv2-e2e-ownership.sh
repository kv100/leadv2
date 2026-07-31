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
# Any preparation failure (archive, scratch dir, overlay) folds every
# blocking suite into `undecidable` — fail-closed to the caller's pre-fix
# (kill) behaviour, never silently permissive.
set -uo pipefail

ROOT="${1:?usage: leadv2-e2e-ownership.sh <root> <task_sig8> <writes_csv> <log_file>}"
TASK="${2:?task sig8 required}"
WRITES_CSV="${3:-}"
LOG_FILE="${4:?log file required}"

_emit() { # <own_csv> <foreign_csv> <undecidable_csv> <owner_lane>
  printf 'own=%s\nforeign=%s\nundecidable=%s\nowner_lane=%s\n' "$1" "$2" "$3" "${4:-unknown}"
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
  suite_path="${SCRATCH}/tests/unit/${suite}"
  if [[ ! -f "${suite_path}" ]]; then
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

_emit "$(_join "${own[@]:-}")" "$(_join "${foreign[@]:-}")" "$(_join "${undecidable[@]:-}")" "${owner_lane}"
