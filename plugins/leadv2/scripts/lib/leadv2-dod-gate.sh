#!/usr/bin/env bash
# lib/leadv2-dod-gate.sh — WORKER-DOD-GATE-01
#
# Deterministic bash definition-of-done gate. Runs BEFORE any model review,
# on the PRODUCTION review path, and refuses a round on a missing mechanical
# DoD item at zero model spend — see docs/handoff/WORKER-DOD-GATE-01/brief.md
# for the founder motivation (2026-09-02 review-round audit: 15 of 19 High
# findings that night were mechanical, checkable predicates, not design
# disagreements).
#
# lv2_dod_gate_run <repo_root> <task_dir> <diff_file> <out_md>
#   exit 0 = pass (hard checks a-d)
#   exit 1 = fail (one or more dod_fail lines)
#   exit 2 = undetermined (a hard check's own input was unreadable/missing —
#            never a false pass, never a false fail)
#   exit 3 = usage error
# Check (e) is report-only and NEVER affects the exit code — see §4/CHALLENGE-14
# in architect-v2.md.
#
# Bash 3.2 compatible (no associative arrays, no mapfile). Under 5s per run:
# bash + grep + git only, no model call (off_limits, brief's own rule).
set -uo pipefail

# Runtime-state path list (check d). Hardcoded per architect-v2 §11: this is
# the extension point for lib/leadv2-land.sh (LAND-PATH-IS-BROKEN-01), which
# is confirmed absent today — do not create it here.
_DOD_RUNTIME_STATE_REGEX='^(docs/leadv2/|docs/LEAD_V2_STATE\.md$|docs/handoff/dispatch-nw)'

# External-claim shape for check (e) — brief's own list, a living regex.
_DOD_CLAIM_REGEX='docs say|macOS|Claude Code|Z\.AI|endpoint|rate limit|version'

_dod_sha256() { # <file> -> stdout hash, empty on failure
  [[ -f "$1" ]] || return 0
  shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
}

# All b/-side paths named in a unified diff (added, modified, or the new
# side of a rename) — mirrors leadv2-review-run.sh:592-599's diff_hash
# sourcing and its falsifiability gate's own `sed -n 's|^+++ b/||p'` idiom.
_dod_diff_paths() { # <diff_file> -> stdout, one path per line
  [[ -f "$1" ]] || return 0
  sed -n 's|^+++ b/||p' "$1" 2>/dev/null | grep -v '^/dev/null$'
}

# Suite paths touched by the diff. Broader than the falsifiability gate's own
# conventional-dir-only regex (leadv2-review-run.sh:1318) on purpose: that
# regex pre-filters to the 4 self-selecting directories, which made check
# (c)'s own self_select case below unreachable-false when reused verbatim —
# every path that survived the filter was, by construction, already in one
# of those directories, so the "needs an EXTRA_SUITE_MAP row" branch could
# never fire. Matching any `test-*.sh` regardless of directory keeps every
# conventional-dir suite path AND surfaces the real failure mode this check
# exists for: a test file dropped outside a self-selecting directory.
_dod_diff_suite_paths() { # <diff_file> -> stdout, one path per line
  _dod_diff_paths "$1" | grep -E '(^|/)test-[^/]+\.sh$' | sort -u
}

# Task dir relative to root, for git-committed-content checks (portable to
# fixture roots used by the test suite, not just the real repo layout).
_dod_task_rel() { # <root> <task_dir> -> stdout relpath (no trailing slash)
  local root="$1" task_dir="$2"
  case "${task_dir}" in
    "${root}"/*) printf '%s' "${task_dir#${root}/}" ;;
    *) printf '%s' "${task_dir}" ;;
  esac
}

# ---------------------------------------------------------------------------
# check (a) — report.md exists, is committed at HEAD, and carries the round
# heading the brief asked for. Conditional: skipped entirely (never failed)
# when brief.md never mentions "report.md" (CHALLENGE-04 fix — the original
# unconditional heading regex refused 37/37 real reports).
# Returns: 0 pass, 1 fail (dod_fail line on stdout), 3 skip (not required).
# ---------------------------------------------------------------------------
_dod_check_a() {
  local root="$1" task_dir="$2"
  local brief="${task_dir}/brief.md" report="${task_dir}/report.md"
  if [[ ! -f "${brief}" ]] || ! grep -qi 'report\.md' "${brief}" 2>/dev/null; then
    printf 'dod_skip check=report_not_required\n'
    return 3
  fi
  if [[ ! -f "${report}" ]]; then
    printf 'dod_fail check=report_missing_or_unheaded detail=missing_file\n'
    return 1
  fi
  local rel
  rel="$(_dod_task_rel "${root}" "${task_dir}")"
  if ! git -C "${root}" show "HEAD:${rel}/report.md" >/dev/null 2>&1; then
    printf 'dod_fail check=report_missing_or_unheaded detail=not_committed\n'
    return 1
  fi
  if ! grep -qiE '^#{2,3}[[:space:]].*evidence' "${report}" 2>/dev/null; then
    printf 'dod_fail check=report_missing_or_unheaded detail=no_evidence_heading\n'
    return 1
  fi
  printf 'dod_pass check=report\n'
  return 0
}

# ---------------------------------------------------------------------------
# check (b) — every brief "paste" line has a matching fenced block in
# report.md under a heading that names it (token-overlap heuristic,
# threshold tunable — CHALLENGE-16). Mutation-control paste-lines additionally
# require a grounded artifact file whose diff_hash matches THIS round's diff
# (CHALLENGE-07: never a prose-sentinel grep).
# Returns: 0 pass, 1 fail, 2 undetermined (diff_file missing while a
# mutation-control line is present and needs diff_hash binding), 3 skip (no
# paste lines in brief.md at all).
# ---------------------------------------------------------------------------
_DOD_PASTE_OVERLAP_PCT="${LEADV2_DOD_PASTE_OVERLAP_PCT:-50}"

_dod_stopwords=' the and run paste this into output result with from that your then also for are was were has have will use used using each once every line lines'

_dod_tokens() { # <text> -> stdout space-joined lowercase tokens len>=4, stopwords dropped
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' ' ' | tr -s ' ' '\n' \
    | while IFS= read -r w; do
        [[ ${#w} -ge 4 ]] || continue
        case " ${_dod_stopwords} " in *" ${w} "*) continue ;; esac
        printf '%s\n' "${w}"
      done
}

# Does <heading_and_block_text> contain >=threshold% of <line_tokens>?
_dod_overlap_hits() { # <line_tokens_file> <hay_text>
  local tokf="$1" hay total=0 hit=0 w
  hay="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r w; do
    [[ -n "${w}" ]] || continue
    total=$((total + 1))
    case "${hay}" in *"${w}"*) hit=$((hit + 1)) ;; esac
  done < "${tokf}"
  [[ ${total} -eq 0 ]] && { printf '0 0\n'; return 0; }
  printf '%s %s\n' "${hit}" "${total}"
}

# Filename-shaped tokens in <text> (e.g. "test-worker-dod-gate.sh",
# "leadv2-mutation-control.sh") — the strongest match signal for "match by
# the suite/control name in the line" (brief item 1b). Excludes report.md
# itself: that names the artifact being written INTO, never the control
# being pasted, and including it would let a generic "write report.md and
# paste X" line match any section that merely mentions report.md.
_dod_filename_tokens() { # <text> -> stdout, one filename-shaped token per line
  _dod_tokens "$1" | grep -E '\.[a-z]{1,4}$' | grep -vxF 'report.md'
}

# heading<TAB>has_fence(0|1)<TAB>body — one row per heading section in report.md
#
# Body lines are joined with a space, never a real newline: the caller reads
# one \x01-joined record per line (`while IFS=$'\x01' read -r heading
# has_fence body`), and `read` always stops at LF regardless of IFS. A body
# that embeds literal "\n" (the pre-fix behaviour) silently splits ONE
# section into many malformed reads — heading empty after the first physical
# line, so every line past the first is dropped from the match, a false
# refusal for any multi-line report section (i.e. nearly every real one).
_dod_report_sections() { # <report_md> -> stdout rows, \x01-joined (heading, has_fence, body b64)
  [[ -f "$1" ]] || return 0
  awk '
    BEGIN { heading = ""; body = ""; fence = 0 }
    /^#{1,6}[[:space:]]/ {
      if (heading != "") { printf "%s\x01%s\x01%s\n", heading, fence, body }
      heading = $0; body = ""; fence = 0; next
    }
    { body = body $0 " "; if ($0 ~ /^```/) fence = 1 }
    END { if (heading != "") printf "%s\x01%s\x01%s\n", heading, fence, body }
  ' "$1"
}

_dod_check_b() {
  local root="$1" task_dir="$2" diff_file="$3"
  local brief="${task_dir}/brief.md" report="${task_dir}/report.md"
  [[ -f "${brief}" ]] || { printf 'dod_skip check=paste_not_required reason=no_brief\n'; return 3; }

  local paste_lines
  paste_lines="$(grep -nEi '[Pp]aste' "${brief}" 2>/dev/null || true)"
  [[ -n "${paste_lines}" ]] || { printf 'dod_skip check=paste_not_required\n'; return 3; }

  local sections_file
  sections_file="$(mktemp 2>/dev/null || echo "${task_dir}/.dod_sections.tmp")"
  _dod_report_sections "${report}" > "${sections_file}"

  local overall_rc=0 undetermined=0
  local diff_hash=""
  [[ -f "${diff_file}" ]] && diff_hash="$(_dod_sha256 "${diff_file}")"

  local lineno linetext tokf fnametokf
  tokf="$(mktemp 2>/dev/null || echo "${task_dir}/.dod_tok.tmp")"
  fnametokf="$(mktemp 2>/dev/null || echo "${task_dir}/.dod_fnametok.tmp")"
  while IFS= read -r pl; do
    [[ -n "${pl}" ]] || continue
    lineno="${pl%%:*}"; linetext="${pl#*:}"
    _dod_tokens "${linetext}" > "${tokf}"
    _dod_filename_tokens "${linetext}" > "${fnametokf}"
    [[ -s "${tokf}" ]] || continue

    local matched=0
    while IFS=$'\x01' read -r heading has_fence body; do
      [[ -n "${heading}" ]] || continue
      [[ "${has_fence}" == "1" ]] || continue
      local hay="${heading} ${body}"
      local hay_lc
      hay_lc="$(printf '%s' "${hay}" | tr '[:upper:]' '[:lower:]')"
      if [[ -s "${fnametokf}" ]]; then
        # Strong signal: match by the named suite/control/file, per the
        # brief's own instruction — any one of the line's filename-shaped
        # tokens appearing in this section is sufficient.
        local fw
        while IFS= read -r fw; do
          [[ -n "${fw}" ]] || continue
          case "${hay_lc}" in *"${fw}"*) matched=1 ;; esac
          [[ ${matched} -eq 1 ]] && break
        done < "${fnametokf}"
      else
        # No filename in the paste-line: fall back to generic word overlap.
        local res hit total
        res="$(_dod_overlap_hits "${tokf}" "${hay}")"
        hit="${res%% *}"; total="${res##* }"
        [[ ${total} -eq 0 ]] && continue
        if [[ $((hit * 100 / total)) -ge ${_DOD_PASTE_OVERLAP_PCT} ]]; then
          matched=1
        fi
      fi
      [[ ${matched} -eq 1 ]] && break
    done < "${sections_file}"

    if [[ ${matched} -eq 0 ]]; then
      printf 'dod_fail check=paste_evidence_missing brief_line=%s\n' "${lineno}"
      overall_rc=1
    fi

    # Sub-check: mutation-control lines need a grounded artifact.
    case "${linetext}" in
      *[Mm]utation*)
        if [[ -z "${diff_file}" || ! -f "${diff_file}" ]]; then
          printf 'dod_skip check=mutation_control_undetermined brief_line=%s reason=no_diff_file\n' "${lineno}"
          undetermined=1
        else
          local mc_dir="${task_dir}/mutation-control" found=0 f
          if [[ -d "${mc_dir}" ]]; then
            for f in "${mc_dir}"/*.txt; do
              [[ -f "${f}" ]] || continue
              if grep -q "^diff_hash=${diff_hash}$" "${f}" 2>/dev/null; then
                found=1
                break
              fi
            done
          fi
          if [[ ${found} -eq 0 ]]; then
            printf 'dod_fail check=mutation_control_not_via_runner brief_line=%s\n' "${lineno}"
            overall_rc=1
          fi
        fi
        ;;
    esac
  done <<< "${paste_lines}"

  rm -f "${sections_file}" "${tokf}" "${fnametokf}" 2>/dev/null || true

  if [[ ${overall_rc} -eq 1 ]]; then
    return 1
  elif [[ ${undetermined} -eq 1 ]]; then
    return 2
  fi
  printf 'dod_pass check=paste_evidence\n'
  return 0
}

# ---------------------------------------------------------------------------
# check (c) — every new/touched suite path in the diff is registered in
# tests/run-all.sh, resolved IN-PROCESS (no shell-out, no --dry-run state
# write — CHALLENGE-06/08). A suite already living under one of the
# self-selecting conventional dirs (tests/, plugins/leadv2/scripts/tests/,
# .claude/scripts/tests/, plugins/leadv2/tests/) with test-*.sh naming is
# registered by construction (run-all.sh's own "changed test suite selects
# itself" rule); anything else must appear as an EXTRA_SUITE_MAP value.
# Returns: 0 pass, 1 fail, 2 undetermined (diff_file unreadable), 3 skip (no
# tests/run-all.sh in this repo).
# ---------------------------------------------------------------------------
_dod_extra_suite_map_values() { # <root> -> stdout, one RHS path per line
  local run_all="${1}/tests/run-all.sh"
  [[ -f "${run_all}" ]] || return 0
  sed -n '/^EXTRA_SUITE_MAP="/,/"$/p' "${run_all}" \
    | sed -e '1s/^EXTRA_SUITE_MAP="//' -e '$s/"$//' \
    | while IFS= read -r row; do
        [[ -n "${row}" ]] || continue
        printf '%s\n' "${row#*:}"
      done
}

_dod_check_c() {
  local root="$1" task_dir="$2" diff_file="$3"
  local run_all="${root}/tests/run-all.sh"
  if [[ ! -f "${run_all}" ]]; then
    printf 'dod_skip check=suite_registration reason=no_run_all\n'
    return 3
  fi
  if [[ -z "${diff_file}" || ! -f "${diff_file}" ]]; then
    printf 'dod_skip check=suite_registration_undetermined reason=no_diff_file\n'
    return 2
  fi

  local suite_paths
  suite_paths="$(_dod_diff_suite_paths "${diff_file}")"
  [[ -n "${suite_paths}" ]] || { printf 'dod_pass check=suite_registration\n'; return 0; }

  local extra_values
  extra_values="$(_dod_extra_suite_map_values "${root}")"

  local rc=0 sp
  while IFS= read -r sp; do
    [[ -n "${sp}" ]] || continue
    local self_select=0
    case "${sp}" in
      tests/test-*.sh|plugins/leadv2/scripts/tests/test-*.sh|.claude/scripts/tests/test-*.sh|plugins/leadv2/tests/test-*.sh)
        self_select=1 ;;
    esac
    if [[ ${self_select} -eq 1 ]]; then
      continue
    fi
    if printf '%s\n' "${extra_values}" | grep -qxF "${sp}"; then
      continue
    fi
    printf 'dod_fail check=suite_unregistered suite=%s\n' "${sp}"
    rc=1
  done <<< "${suite_paths}"

  if [[ ${rc} -eq 1 ]]; then
    return 1
  fi
  printf 'dod_pass check=suite_registration\n'
  return 0
}

# ---------------------------------------------------------------------------
# check (d) — no runtime-state path in the diff. Reads DIFF_FILE exclusively
# (CHALLENGE-12: never `git diff main HEAD`, which is not reliably the
# round's base ref).
# Returns: 0 pass, 1 fail, 2 undetermined (diff_file unreadable).
# ---------------------------------------------------------------------------
_dod_check_d() {
  local diff_file="$1"
  if [[ -z "${diff_file}" || ! -f "${diff_file}" ]]; then
    printf 'dod_skip check=runtime_state_undetermined reason=no_diff_file\n'
    return 2
  fi
  local paths hit=""
  paths="$(_dod_diff_paths "${diff_file}")"
  local p csv=""
  while IFS= read -r p; do
    [[ -n "${p}" ]] || continue
    if [[ "${p}" =~ ${_DOD_RUNTIME_STATE_REGEX} ]]; then
      csv="${csv:+${csv},}${p}"
    fi
  done <<< "${paths}"
  if [[ -n "${csv}" ]]; then
    printf 'dod_fail check=runtime_state_in_diff paths=%s\n' "${csv}"
    return 1
  fi
  printf 'dod_pass check=runtime_state\n'
  return 0
}

# ---------------------------------------------------------------------------
# check (e) — SOFT, report-only. Never affects the gate's exit code
# (CHALLENGE-14: the critic measured ~19% false-refusal as a blocking check).
# ---------------------------------------------------------------------------
_dod_check_e() {
  local task_dir="$1"
  local report="${task_dir}/report.md"
  [[ -f "${report}" ]] || return 0
  local total_lines n=0
  total_lines="$(wc -l < "${report}" 2>/dev/null | tr -d ' ')"
  while IFS= read -r n; do
    [[ -n "${n}" ]] || continue
    local lo=$((n - 2)); local hi=$((n + 2))
    [[ ${lo} -lt 1 ]] && lo=1
    [[ -n "${total_lines}" && ${hi} -gt ${total_lines} ]] && hi="${total_lines}"
    local window
    window="$(sed -n "${lo},${hi}p" "${report}" 2>/dev/null)"
    if ! printf '%s' "${window}" | grep -qE 'evidence:|UNVERIFIED'; then
      printf 'dod_note check=unverified_claim line=%s\n' "${n}"
    fi
  done < <(grep -nE "${_DOD_CLAIM_REGEX}" "${report}" 2>/dev/null | sed -n 's/^\([0-9]*\):.*/\1/p')
  return 0
}

# ---------------------------------------------------------------------------
lv2_dod_gate_run() {
  if [[ $# -ne 4 ]]; then
    printf 'Usage: lv2_dod_gate_run <repo_root> <task_dir> <diff_file> <out_md>\n' >&2
    return 3
  fi
  local root="$1" task_dir="$2" diff_file="$3" out_md="$4"
  local tmp_out
  tmp_out="$(mktemp 2>/dev/null || echo "${out_md}.tmp")"

  local overall_fail=0 overall_undetermined=0
  local a_out b_out c_out d_out e_out
  a_out="$(_dod_check_a "${root}" "${task_dir}")"; local a_rc=$?
  b_out="$(_dod_check_b "${root}" "${task_dir}" "${diff_file}")"; local b_rc=$?
  c_out="$(_dod_check_c "${root}" "${task_dir}" "${diff_file}")"; local c_rc=$?
  d_out="$(_dod_check_d "${diff_file}")"; local d_rc=$?
  e_out="$(_dod_check_e "${task_dir}")"

  for rc in "${a_rc}" "${b_rc}" "${c_rc}" "${d_rc}"; do
    [[ "${rc}" == "1" ]] && overall_fail=1
    [[ "${rc}" == "2" ]] && overall_undetermined=1
  done

  {
    printf '# dod-gate report — %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
    printf '%s\n' "${a_out}"
    printf '%s\n' "${b_out}"
    printf '%s\n' "${c_out}"
    printf '%s\n' "${d_out}"
    [[ -n "${e_out}" ]] && printf '%s\n' "${e_out}"
  } > "${tmp_out}"
  mv -f "${tmp_out}" "${out_md}" 2>/dev/null || cp -f "${tmp_out}" "${out_md}" 2>/dev/null || true

  cat "${out_md}" 2>/dev/null

  if [[ ${overall_fail} -eq 1 ]]; then
    return 1
  elif [[ ${overall_undetermined} -eq 1 ]]; then
    return 2
  fi
  return 0
}

# Allow standalone invocation: bash lib/leadv2-dod-gate.sh <root> <task_dir> <diff_file> <out_md>
# but stay sourceable for the test suite (BASH_SOURCE[0] != $0 when sourced).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  lv2_dod_gate_run "$@"
  exit $?
fi
