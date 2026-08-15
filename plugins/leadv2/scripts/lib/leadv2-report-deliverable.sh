#!/usr/bin/env bash
# lib/leadv2-report-deliverable.sh — REPORT-ONLY-GATE-01 shared lib.
#
# A lane may declare its deliverable is a FILE (a report), not a diff:
#   LANE_DELIVERABLE: report:<repo-relative path>
# This lib is the single mechanism for that declaration: parse (both
# leadv2-dispatch-code.sh and leadv2-dispatch-product-close.sh), locate,
# substantiveness, harvest (product-close only). Sourced guarded everywhere
# (missing lib => no-op stub => today's diff-gate behaviour, never a broken gate).
#
# Deliberately `set -uo pipefail`, never `-e` -- a sourced `-e` leaks into and
# silently overrides the caller's own deliberate no--e policy (SILENT-DEATH-01,
# see leadv2-dispatch-code.sh / leadv2-refusal-classify.sh's matching comments).
set -uo pipefail

# lv2_deliverable_parse <decl> -> prints "report\x1f<path>" on stdout, rc 0, for a
# well-formed report declaration; rc 1 (nothing printed) for any other kind or a
# path that cannot name a repo-relative file. Only `report:` is a known kind
# (REPORT-ONLY-GATE-01 non-goal: no other kinds) — an unparsable declaration must
# never silently convert a code lane into a report lane.
lv2_deliverable_parse() { # <decl>
  local decl="${1:-}" path
  [[ "${decl}" == report:* ]] || return 1
  path="${decl#report:}"
  # trim surrounding whitespace
  path="${path#"${path%%[![:space:]]*}"}"
  path="${path%"${path##*[![:space:]]}"}"
  path="${path#./}"
  # reject empty / absolute / traversal / interior-empty-segment paths
  [[ -n "${path}" && "${path}" != /* && "${path}" != "." && "${path}" != "/" ]] || return 1
  [[ "${path}" == ".." || "${path}" == ../* || "${path}" == */.. || "${path}" == */../* ]] && return 1
  case "/${path}/" in *//*) return 1 ;; esac
  printf 'report\x1f%s' "${path}"
}

# lv2_report_locate <diff_root> <root> <rel> -> prints the first EXISTING absolute
# path for <rel>, preferring the lane worktree (diff_root) over the main checkout
# (root); rc 1 if neither exists. The report's canonical home is the lane worktree
# (worker --cwd is LEADV2_LANE_WORK_ROOT), but a worker that ran in the main
# checkout leaves it ROOT-side -- both are legitimate finds.
lv2_report_locate() { # <diff_root> <root> <rel>
  local diff_root="$1" root="$2" rel="$3" cand
  for cand in "${diff_root}/${rel}" "${root}/${rel}"; do
    [[ -f "${cand}" ]] && { printf '%s' "${cand}"; return 0; }
  done
  return 1
}

# lv2_report_substantive <abs> -> rc 0 iff the report clears BOTH floors:
#   >= LEADV2_REPORT_MIN_BYTES  (default 600)  non-whitespace BYTES
#   >= LEADV2_REPORT_MIN_LINES  (default 12)   non-blank LINES
# Deliberately dumb — no LLM, no keyword sniff. "Non-trivial" must be a fact a
# human can re-check by eye (mission REPORT-ONLY-GATE-01 hard constraint).
lv2_report_substantive() { # <abs>
  local abs="$1"
  local min_bytes="${LEADV2_REPORT_MIN_BYTES:-600}"
  local min_lines="${LEADV2_REPORT_MIN_LINES:-12}"
  local bytes lines
  [[ "${min_bytes}" =~ ^[0-9]+$ ]] || min_bytes=600
  [[ "${min_lines}" =~ ^[0-9]+$ ]] || min_lines=12
  [[ -f "${abs}" ]] || return 1
  bytes="$(tr -d '[:space:]' < "${abs}" | wc -c | tr -d '[:space:]')"
  lines="$(grep -c '[^[:space:]]' "${abs}" 2>/dev/null || true)"
  [[ "${bytes}" =~ ^[0-9]+$ ]] || bytes=0
  [[ "${lines}" =~ ^[0-9]+$ ]] || lines=0
  (( bytes >= min_bytes && lines >= min_lines ))
}

# lv2_report_harvest <abs> <handoff_dir> -> copies the report to
# <handoff_dir>/report.md (ROOT-side docs/handoff/dispatch-<TASK>/, which survives
# lane-worktree sweep) and prints the destination. Atomic idiom: write a
# same-directory tmp then mv -f (the :2056 rename idiom), so a concurrent reader
# never sees a partial report.md. Copy-onto-itself (report already ROOT-side) is
# a guarded no-op.
lv2_report_harvest() { # <abs> <handoff_dir>
  local abs="$1" handoff_dir="$2" dest tmp
  dest="${handoff_dir}/report.md"
  mkdir -p "${handoff_dir}" 2>/dev/null || return 1
  if [[ "${abs}" -ef "${dest}" ]]; then
    printf '%s' "${dest}"
    return 0
  fi
  tmp="$(mktemp "${handoff_dir}/report.md.tmp.XXXXXX")" || return 1
  if ! cp "${abs}" "${tmp}" 2>/dev/null; then
    rm -f "${tmp}" 2>/dev/null
    return 1
  fi
  if ! mv -f "${tmp}" "${dest}" 2>/dev/null; then
    rm -f "${tmp}" 2>/dev/null
    return 1
  fi
  printf '%s' "${dest}"
}
