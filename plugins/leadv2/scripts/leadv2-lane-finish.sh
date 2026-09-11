#!/usr/bin/env bash
# leadv2-lane-finish.sh — W-LEAD-LAST-MILE-01
#
# ONE command for the lead's per-lane close ritual, so the lead decides and
# the procedure runs itself. Measured 2026-09-10: three back-to-back lanes
# dispatched 01:19 / 02:09 / 03:43 — serialised entirely by ~40 minutes of
# manual lead mechanics per lane (suite run, mutation inside the real file,
# restore + porcelain proof, merged-tree, merge with trailers). This wrapper
# is that chain; the lead's only decision stays "land or not".
#
# Chain (first red step aborts with a non-zero code and a line naming it):
#   1. suite        run the lane's suite in THIS checkout (must be green)
#   2. mutation     leadv2-mutation-control.sh --live — the SAME mutation on
#                   the REAL file (a mutation of a scratch copy proves
#                   nothing for the lead), suite must redden, file restored,
#                   porcelain byte-identical (incl. empty-when-clean)
#   3. cleanliness  re-prove `git status --porcelain` is byte-identical to
#                   the pre-chain snapshot of THIS checkout
#   4. land         leadv2-land.sh <lane> — hygiene, merge-safety gate +
#                   the merged-tree instrument (refuses if the merge would
#                   delete/change main files outside the lane write set),
#                   then merge (--no-ff with Landed-lane:/Landed-branch:
#                   trailers when asked) and push. land is THE single
#                   landing runner; this wrapper never merges by itself.
#
# Usage:
#   leadv2-lane-finish.sh <lane-branch> <suite> <file> <sed-or-patch> \
#       [--task-dir <dir>] [--write-set <spec>] [--dry-run] [--no-ff]
#
#   <lane-branch>   lane branch as leadv2-land.sh takes it (the branch, not
#                   the checkout; land resolves the primary checkout itself)
#   <suite>         repo-relative (to THIS checkout) path to the lane suite
#   <file>          repo-relative path to the file the lead mutation targets
#   <sed-or-patch>  sed expression or patch file, as mutation-control takes
#   --task-dir      artifact dir for mutation-control/ (default:
#                   docs/handoff/<task-id>)
#   --write-set     LEADV2_LAND_WRITE_SET for land's merged-tree check
#                   (csv/colon list or file of paths)
#   --dry-run       forwarded to land (steps 1-3 still run for real)
#   --no-ff         forwarded to land (merge commit with Landed-* trailers)
#
# Honest limit (brief §4): the primary checkout carries ~124 dirty entries
# that do not intersect any lane's write set. If land refuses with
# reason=main_dirty on dirt that does NOT intersect the write set, that is
# SHOWN as its own KNOWN-DEFECT line here — never silently bypassed — and
# belongs in its own row, not patched in this wrapper.
#
# Exit codes: 0 = chain green (landed, or dry-run ok); 1 = refused at a
# named step; 2 = usage.
#
# Bash 3.2 compatible: no associative arrays, no ${x^^}, no readarray.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  printf 'Usage: %s <lane-branch> <suite> <file> <sed-or-patch> [--task-dir <dir>] [--write-set <spec>] [--dry-run] [--no-ff]\n' \
    "$(basename "$0")" >&2
}

LANE=""; SUITE=""; TARGET=""; MUTATION=""
TASK_DIR=""; WRITE_SET=""
DRY_RUN=0; NO_FF=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir)  [[ $# -ge 2 ]] || { usage; exit 2; }; TASK_DIR="$2"; shift 2 ;;
    --write-set) [[ $# -ge 2 ]] || { usage; exit 2; }; WRITE_SET="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    --no-ff)     NO_FF=1; shift ;;
    -*)          usage; exit 2 ;;
    *)
      if [[ -z "${LANE}" ]]; then LANE="$1"
      elif [[ -z "${SUITE}" ]]; then SUITE="$1"
      elif [[ -z "${TARGET}" ]]; then TARGET="$1"
      elif [[ -z "${MUTATION}" ]]; then MUTATION="$1"
      else usage; exit 2; fi
      shift ;;
  esac
done
[[ -n "${LANE}" && -n "${SUITE}" && -n "${TARGET}" && -n "${MUTATION}" ]] || { usage; exit 2; }

# THIS checkout is the lane worktree the wrapper was invoked from (suite +
# mutation run here); land.sh finds the primary checkout on its own.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TASK="${LEADV2_LAND_TASK_ID:-${LANE#worktree-}}"
[[ -n "${TASK_DIR}" ]] || TASK_DIR="${ROOT}/docs/handoff/${TASK}"

SUITE_ABS="${SUITE}"; case "${SUITE_ABS}" in /*) ;; *) SUITE_ABS="${ROOT}/${SUITE_ABS}" ;; esac
[[ -f "${SUITE_ABS}" ]] || { printf 'leadv2-lane-finish: not a file: suite=%s\n' "${SUITE_ABS}" >&2; exit 2; }
# Pin the cwd to the lane checkout: mutation-control resolves ITS ROOT from
# the cwd it inherits, and relative suite/mutation paths resolve here too.
cd "${ROOT}" || { printf 'leadv2-lane-finish: cannot cd to %s\n' "${ROOT}" >&2; exit 2; }

_refuse() { # <step> <detail>
  printf 'leadv2-lane-finish: REFUSED step=%s: %s\n' "$1" "$2" >&2
  exit 1
}

_ws_entry_matches_path() { # <write-set-entry> <path> -> rc 0 = entry covers path
  [[ "$2" == "$1" || "$2" == "$1"/* ]]
}

_ws_spec_contains_path() { # <write-set-spec> <path> -> rc 0 = path is covered
  local spec="$1" p="$2" item
  if [[ -f "${spec}" ]]; then
    while IFS= read -r item; do
      item="${item%%#*}"
      item="${item#"${item%%[![:space:]]*}"}"
      item="${item%"${item##*[![:space:]]}"}"
      [[ -n "${item}" ]] || continue
      _ws_entry_matches_path "${item}" "${p}" && return 0
    done < "${spec}"
  else
    local IFS=',:'
    for item in ${spec}; do
      [[ -n "${item}" ]] || continue
      _ws_entry_matches_path "${item}" "${p}" && return 0
    done
  fi
  return 1
}

LOG="$(mktemp "${TMPDIR:-/tmp}/leadv2-finish.XXXXXX")"
trap 'rm -f "${LOG}"' EXIT

# ── snapshot BEFORE anything: step 3 proves the chain left no residue ───────
# The task dir is the chain's one DECLARED write (the mutation artifact), so
# its entries are filtered from BOTH sides: cleanliness means nothing changed
# except the declared artifact location.
_task_rel() { # prints task-dir relative to ROOT
  local t="${TASK_DIR}"
  case "${t}" in "${ROOT}/"*) t="${t#${ROOT}/}" ;; esac
  printf '%s' "${t}"
}
_porc_filtered() { # porcelain minus the task-dir entries
  local tr; tr="$(_task_rel)"
  # -uall: list untracked FILES, not collapsed dirs — otherwise a brand-new
  # docs/ tree shows as a single `?? docs/` line no task-dir filter can match.
  git -C "${ROOT}" status --porcelain -uall 2>/dev/null | LC_ALL=C sort \
    | grep -vE "^(.. |\?\? )${tr}(/.*)?$" || true
}
PORCELAIN_BEFORE="$(_porc_filtered)"

# ── step 1: the lane's suite, green ─────────────────────────────────────────
( cd "$(dirname "${SUITE_ABS}")" && bash "${SUITE_ABS}" ) > "${LOG}" 2>&1
rc=$?
[[ ${rc} -eq 0 ]] || _refuse "suite" "suite rc=${rc}: ${SUITE}
$(tail -15 "${LOG}")"
printf 'leadv2-lane-finish: STEP suite ok (%s)\n' "${SUITE}" >&2

# ── step 2: lead mutation on the REAL file, red proof, restore ─────────────
bash "${SCRIPT_DIR}/leadv2-mutation-control.sh" --live "${SUITE}" "${TARGET}" "${MUTATION}" "${TASK_DIR}" > "${LOG}" 2>&1
rc=$?
if [[ ${rc} -ne 0 ]]; then
  tail -15 "${LOG}" >&2
  _refuse "mutation" "mutation-control --live rc=${rc} (mutant_survived = the negative control was NOT proven; restore still guaranteed by its trap)"
fi
printf 'leadv2-lane-finish: STEP mutation ok (live, red proven, file restored, porcelain identical)\n' >&2

# ── step 3: cleanliness of THIS checkout ────────────────────────────────────
PORCELAIN_NOW="$(_porc_filtered)"
if [[ "${PORCELAIN_NOW}" != "${PORCELAIN_BEFORE}" ]]; then
  diff <(printf '%s\n' "${PORCELAIN_BEFORE}") <(printf '%s\n' "${PORCELAIN_NOW}") | head -20 >&2
  _refuse "cleanliness" "git status --porcelain differs from the pre-chain snapshot (see diff above)"
fi
printf 'leadv2-lane-finish: STEP cleanliness ok (porcelain identical to pre-chain; empty-when-clean: %s)\n' \
  "$([[ -z "${PORCELAIN_NOW}" ]] && printf yes || printf no)" >&2

# ── step 4: land (hygiene -> safety gate + merged-tree -> merge -> push) ────
[[ -n "${WRITE_SET}" ]] && export LEADV2_LAND_WRITE_SET="${WRITE_SET}"
export LEADV2_LAND_TASK_ID="${TASK}"
LAND_ARGS=("${LANE}")
[[ ${DRY_RUN} -eq 1 ]] && LAND_ARGS+=("--dry-run")
[[ ${NO_FF} -eq 1 ]] && LAND_ARGS+=("--no-ff")
bash "${SCRIPT_DIR}/leadv2-land.sh" "${LAND_ARGS[@]}" > "${LOG}" 2>&1
rc=$?
if [[ ${rc} -ne 0 ]]; then
  cat "${LOG}" >&2
  # Brief §4 honest limit: a main_dirty refusal on dirt that does NOT
  # intersect the lane write set is its own known defect — name it, do not
  # bypass it, do not fix it here.
  if grep -q 'reason=main_dirty' "${LOG}"; then
    _finish_dirty_paths="$(sed -n '/outside the state list:/,$p' "${LOG}" | grep -vE 'leadv2-land:|^$' | head -50)"
    _finish_overlap=""
    if [[ -n "${WRITE_SET}" && -n "${_finish_dirty_paths}" ]]; then
      while IFS= read -r _dp; do
        [[ -n "${_dp}" ]] || continue
        if _ws_spec_contains_path "${WRITE_SET}" "${_dp}"; then _finish_overlap=1; break; fi
      done <<< "${_finish_dirty_paths}"
    fi
    if [[ -z "${_finish_overlap}" ]]; then
      printf 'leadv2-lane-finish: KNOWN-DEFECT (file a separate row; deliberately NOT fixed or bypassed here): land refused reason=main_dirty on dirty paths that do NOT intersect the lane write set — the 124-entry class measured 2026-09-10 (brief §4)\n' >&2
    fi
  fi
  _refuse "land" "leadv2-land.sh rc=${rc} (see its output above; hygiene / merge-safety / merged-tree / merge / push)"
fi
printf 'leadv2-lane-finish: STEP land ok (%s)\n' "${LAND_ARGS[*]}" >&2

printf 'leadv2-lane-finish: CHAIN GREEN — lane=%s suite=%s mutation=%s\n' "${LANE}" "${SUITE}" "${TARGET}" >&2
exit 0
