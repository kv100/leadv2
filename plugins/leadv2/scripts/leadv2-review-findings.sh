#!/usr/bin/env bash
# leadv2-review-findings.sh — REVIEW-GATE-SHOWS-FINDINGS-01: the ONE shared renderer
# that turns a reviewer report (review-<arm>.md) into the findings block appended to
# review-gate.md. Called by BOTH gate writers:
#   - leadv2-review-run.sh             (fail + pass exits)
#   - leadv2-dispatch-product-close.sh (fail + pass exits — the lane path that wrote
#     every real gate to date; a fix landing only in review-run.sh would change
#     nothing the founder sees)
#
# CONTRACT (design R3): rc is ALWAYS 0, output goes to stdout ONLY, and this file
# never writes review-gate.md. A renderer that can kill the gate mid-write is a worse
# bug than the one being fixed: callers invoke it inside the gate's `{ ... } > tmp`
# block with `|| true`, so a total failure degrades to today's exact gate, never to a
# missing one. Parse degradation is expressed in the emitted text
# (findings: unavailable + findings_reason:), never in the exit code.
#
# Dual-mode:
#   library:  source <this>; render_gate_findings "<report>" ["<json>"] ["<arm>"] ["<relpath>"]
#   CLI:      leadv2-review-findings.sh --report <review-<arm>.md> [--json <review-findings.json>]
#                                       [--arm <name>] [--report-path <repo-relative path to print>]
#
# Side effects when sourced: the _rgf_* function namespace, RGF_DO_NOT_MERGE (1 when
# the report-level do-not-merge advisory fired — callers append an additive
# `do_not_merge=1` token to their ledger line), and the LEADV2_GATE_* defaults.
#
# BSD/macOS constraints (design R5): grep -E / sed -E / awk only, no grep -P, no jq,
# bash-3.2-safe expansions, no in-place edits. Cyrillic do-not-merge phrases are
# matched as fixed strings in both cases because BSD grep -i is not reliable on
# non-ASCII.
set -uo pipefail

LEADV2_GATE_DESC_MAX="${LEADV2_GATE_DESC_MAX:-180}"
LEADV2_GATE_MEDIUM_MAX="${LEADV2_GATE_MEDIUM_MAX:-5}"
RGF_DO_NOT_MERGE=0

# do-not-merge phrase set (design §3, R4): imperative-only and narrow. It is
# ADVISORY — it never changes status: or any exit code (a PASS_WITH_NITS + do-not-
# merge report still writes status: pass; turning that into a blocking verdict is a
# decision change owned by its own lane).
_rgf_says_dnm_text() { # <text> -> rc 0 when a blocking phrase is present
  local t="$1" p
  if printf '%s\n' "$t" | grep -iEq 'do not merge|don.t merge|not merge as-is|must not land|should not be merged'; then
    return 0
  fi
  for p in 'не мержить' 'Не мержить' 'НЕ МЕРЖИТЬ' 'не мержим' 'Не мержим' 'нельзя мержить' 'Нельзя мержить'; do
    printf '%s\n' "$t" | grep -Fq -- "$p" && return 0
  done
  return 1
}

_rgf_says_dnm_file() { # <file>
  local f="$1"
  [[ -r "$f" ]] || return 1
  _rgf_says_dnm_text "$(cat "$f" 2>/dev/null)"
}

# Byte-boundary truncation: cut at max BYTES under LC_ALL=C, then trim any UTF-8
# sequence the cut split (continuation bytes are non-printable under C) so the gate
# never carries a broken character. Appends the … ellipsis only when truncating.
_rgf_trunc() { # <text> [max-bytes] -> stdout
  local LC_ALL=C s="$1" max="${2:-${LEADV2_GATE_DESC_MAX}}" c
  if (( ${#s} <= max )); then printf '%s' "$s"; return 0; fi
  s="${s:0:max}"
  while (( ${#s} > 0 )); do
    c="${s:$((${#s} - 1))}"
    [[ "$c" =~ ^[[:print:]]$ ]] && break
    s="${s:0:$((${#s} - 1))}"
  done
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s…' "$s"
}

# Anchor = first backticked token in the item that looks like a file path
# (optionally :line). Yields scripts/gate-cost-report.sh, scripts/vps-release-deploy.sh,
# client.sh, agent/safety/pre-execute.sh on the three real reports.
_rgf_anchor() { # <text> -> stdout ("" when none)
  local s="$1" tok m
  while IFS= read -r tok; do
    [[ -n "$tok" ]] || continue
    tok="${tok//\`/}"
    m="$(printf '%s' "$tok" | grep -oE '^[A-Za-z0-9_./-]+\.[A-Za-z0-9]+(:[0-9]+)?' | head -n1)"
    [[ -n "$m" ]] && { printf '%s' "$m"; return 0; }
  done < <(printf '%s\n' "$s" | grep -oE '\`[^\`]+\`')
  return 0
}

# Markdown item -> one rendered line. Marker shapes cover all three real reports:
# `1. **text**`, `2) text`, `**H1 — text**`, `- text`, `* text`.
_rgf_md_item() { # <raw-first-line> <severity> -> stdout "- [Sev] anchor — desc"
  local raw="$1" sev="$2" s anchor
  s="$(printf '%s' "$raw" | sed -E 's/^[[:space:]]*([0-9]+[.)][[:space:]]+|[-*][[:space:]]+|\*\*)//')"
  anchor="$(_rgf_anchor "$s")"
  s="${s//\*/}"; s="${s//\`/}"
  # strip a leading item label (H1 — / M1: / L2 - ) if present (em-dash matched as a
  # literal outside the ASCII class — bracket classes cannot hold multibyte chars)
  s="$(printf '%s' "$s" | sed -E 's/^[[:space:]]*[A-Z]?[0-9]{1,3}([[:space:]]*[):.-][[:space:]]*|[[:space:]]*—[[:space:]]*)//')"
  s="$(printf '%s' "$s" | tr -s '[:space:]' ' ')"
  s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"
  # drop the anchor when it prefixes the text (the **H1 — path: desc** shape)
  if [[ -n "${anchor}" && "${s}" == "${anchor}"* ]]; then
    s="${s#"${anchor}"}"
    s="${s#":"}"; s="${s#"${s%%[![:space:]]*}"}"
  fi
  local out="- [${sev}]"
  [[ -n "${anchor}" ]] && out="${out} ${anchor} —"
  printf '%s %s\n' "$out" "$(_rgf_trunc "$s")"
}

# Structured item (FINDING: line or review-findings.json record) -> rendered line.
# verifier_verdict rides through verbatim when the structured source supplied it
# (refuted findings still render — they are information; the verdict logic, which
# already ignores them, is untouched).
_rgf_struct_item() { # <sev> <file> <line> <desc> <verdict>
  local sev="$1" f="$2" ln="$3" desc="$4" v="${5:-}"
  # (bash-3.2: a same-line `local anchor="$f"` sees f as unbound — split declarations)
  local anchor="$f" out
  [[ -n "${ln}" && "${ln}" != "0" ]] && anchor="${f}:${ln}"
  out="- [${sev}] ${anchor} — $(_rgf_trunc "${desc}")"
  [[ -n "${v}" && "${v}" != "unverified" ]] && out="${out} (verified: ${v})"
  printf '%s\n' "$out"
}

# Markdown severity sections -> TSV "severity<TAB>raw-first-line".
# Section heading regex tolerates trailing text (`## Medium (3)`, `### Высокий`); a
# NON-severity heading closes the current section. Cyrillic matched as literal
# two-case alternatives because byte-oriented awk bracket expressions cannot span
# multibyte characters.
_rgf_markdown_items() { # <report> -> stdout TSV
  awk '
    function classify(h) {
      low = tolower(h)
      if (low ~ /^critical/ || h ~ /^Критич/ || h ~ /^критич/) return "Critical"
      if (low ~ /^high/ || h ~ /^Высок/ || h ~ /^высок/) return "High"
      if (low ~ /^medium/ || h ~ /^Средн/ || h ~ /^средн/) return "Medium"
      if (low ~ /^low/ || h ~ /^Низк/ || h ~ /^низк/) return "Low"
      return ""
    }
    /^#+[ \t]/ {
      head = $0; sub(/^#+[ \t]+/, "", head)
      sev = classify(head)
      next
    }
    sev == "" { next }
    /^[ \t]*[0-9]+[.)][ \t]/ || /^[ \t]*\*\*/ || /^[ \t]*[-*][ \t]/ { print sev sprintf("%c",31) $0 }
  ' "$1" 2>/dev/null
}

_rgf_sev_norm() { # <word> -> canonical severity or ""
  case "$1" in
    [Cc]ritical) printf 'Critical' ;;
    [Hh]igh)     printf 'High' ;;
    [Mm]edium)   printf 'Medium' ;;
    [Ll]ow)      printf 'Low' ;;
    *)           printf '' ;;
  esac
}

# ---------------------------------------------------------------------------
# render_gate_findings <report> [<json>] [<arm>] [<relpath>] -> findings block on
# stdout. rc ALWAYS 0. Block shape (appended AFTER the writer's existing head lines,
# which stay byte-identical and first, so head -1 / ^status: consumers are safe):
#   reviewer_says: do_not_merge     (only when the advisory fired)
#   findings_source: finding_lines | markdown_sections | none
#   findings:                       (followed by one "- [Sev] anchor — desc" per item)
#   findings: none                  (zero counts AND zero items — the one quiet case)
#   findings: unavailable           (+ findings_reason: parse_failed | report_missing)
#   omitted: medium=K low=N         (lows are NEVER rendered; design rule 4)
#   report: <relpath>               (pointer for the human, whenever a report exists)
# Every Critical and every High is rendered, always, uncapped (design rule 1).
# ---------------------------------------------------------------------------
render_gate_findings() {
  local report="${1:-}" json="${2:-}" arm="${3:-}" relpath="${4:-}"
  RGF_DO_NOT_MERGE=0
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/rgf.XXXXXX" 2>/dev/null)" || tmp="/tmp/rgf.$$"
  local src="none"

  if [[ -z "${report}" || ! -r "${report}" ]]; then
    printf 'findings_source: none\nfindings: unavailable\nfindings_reason: report_missing\n'
    [[ -n "${relpath}" ]] && printf 'report: %s\n' "${relpath}"
    rm -f "${tmp}" 2>/dev/null
    return 0
  fi

  if _rgf_says_dnm_file "${report}"; then RGF_DO_NOT_MERGE=1; fi

  # Expected counts from the report's own REVIEW_FINDINGS: line (contract order).
  local exp_c=0 exp_h=0 exp_m=0 exp_l=0 cnt
  cnt="$(sed -nE 's/^[[:space:]]*REVIEW_FINDINGS:.*critical=([0-9]+).*high=([0-9]+).*medium=([0-9]+).*low=([0-9]+).*/\1 \2 \3 \4/p' "${report}" | head -n1)"
  [[ -n "${cnt}" ]] && read -r exp_c exp_h exp_m exp_l <<<"${cnt}"

  # Priority 1 (design §2.1): structured records — non-empty review-findings.json
  # first (it is deduped and carries verifier_verdict), else FINDING: lines.
  if [[ -n "${json}" && -s "${json}" ]] && grep -q '"findings":\[{' "${json}" 2>/dev/null; then
    src="finding_lines"
    sed 's/},/}\n/g' "${json}" 2>/dev/null | grep -o '{"dimension".*' | while IFS= read -r obj; do
      _sev="$(_rgf_sev_norm "$(printf '%s' "$obj" | sed -nE 's/.*"severity":"([A-Za-z]+)".*/\1/p')")"
      [[ -n "${_sev}" ]] || continue
      _f="$(printf '%s' "$obj" | sed -nE 's/.*"file":"([^"]*)".*/\1/p')"
      _ln="$(printf '%s' "$obj" | sed -nE 's/.*"line":([0-9]+).*/\1/p')"
      _v="$(printf '%s' "$obj" | sed -nE 's/.*"verifier_verdict":"([a-z]+)".*/\1/p')"
      _d="$(printf '%s' "$obj" | sed -nE 's/.*"desc":"(.*)"\}/\1/p')"
      printf '%s\037%s\037%s\037%s\037%s\n' "${_sev}" "${_f}" "${_ln:-0}" "${_v}" "${_d}"
    done >> "${tmp}"
  elif grep -qE '^[[:space:]]*FINDING:' "${report}" 2>/dev/null; then
    src="finding_lines"
    grep -E '^[[:space:]]*FINDING:' "${report}" | while IFS= read -r _line; do
      _sev="$(_rgf_sev_norm "$(printf '%s' "$_line" | sed -nE 's/.*severity=([A-Za-z]+).*/\1/p')")"
      [[ -n "${_sev}" ]] || continue
      _f="$(printf '%s' "$_line" | sed -nE 's/.*file=([^ ]+).*/\1/p')"
      _ln="$(printf '%s' "$_line" | sed -nE 's/.*line=([0-9]+).*/\1/p')"
      _d="$(printf '%s' "$_line" | sed -nE 's/.*desc=(.*)$/\1/p')"
      printf '%s\037%s\037%s\037%s\037%s\n' "${_sev}" "${_f}" "${_ln:-0}" "" "${_d}"
    done >> "${tmp}"
  else
    # Priority 2: markdown severity sections.
    src="markdown_sections"
    _rgf_markdown_items "${report}" | while IFS=$'\037' read -r _sev _raw; do
      printf '%s\037%s\037\037\037\n' "${_sev}" "${_raw}"
    done >> "${tmp}"
  fi

  local -a out_lines=() med_lines=()
  local sev f1 f2 f3 rest line n_c=0 n_h=0 n_m=0 n_l=0 rendered_med=0 om_m=0 om_l=0
  while IFS=$'\037' read -r sev f1 f2 f3 rest; do
    [[ -n "${sev}" ]] || continue
    case "${sev}" in
      Critical|High)
        if [[ "${src}" == "markdown_sections" ]]; then
          line="$(_rgf_md_item "${f1}" "${sev}")"
        else
          line="$(_rgf_struct_item "${sev}" "${f1}" "${f2}" "${rest}" "${f3}")"
        fi
        out_lines+=("${line}")
        if [[ "${sev}" == "Critical" ]]; then n_c=$((n_c + 1)); else n_h=$((n_h + 1)); fi
        ;;
      Medium)
        n_m=$((n_m + 1))
        if [[ "${src}" == "markdown_sections" ]]; then
          line="$(_rgf_md_item "${f1}" "Medium")"
        else
          line="$(_rgf_struct_item "Medium" "${f1}" "${f2}" "${rest}" "${f3}")"
        fi
        # Blocking Medium (design rule 2): its own text matches the phrase set, or
        # the report-level flag is set (then every Medium renders, uncapped).
        if [[ "${RGF_DO_NOT_MERGE}" == "1" ]] || _rgf_says_dnm_text "${f1}"; then
          med_lines+=("${line}")
        elif (( rendered_med < LEADV2_GATE_MEDIUM_MAX )); then
          med_lines+=("${line}"); rendered_med=$((rendered_med + 1))
        else
          om_m=$((om_m + 1))
        fi
        ;;
      Low)
        n_l=$((n_l + 1))
        ;;
    esac
  done < "${tmp}"
  rm -f "${tmp}" 2>/dev/null

  # Anti-lying-green degrade (design §4): counts say Critical/High/Medium exist but
  # the extractor produced zero items for them.
  if (( exp_c + exp_h + exp_m > 0 )) && (( n_c + n_h + n_m == 0 )); then
    [[ "${RGF_DO_NOT_MERGE}" == "1" ]] && printf 'reviewer_says: do_not_merge\n'
    printf 'findings_source: none\nfindings: unavailable\nfindings_reason: parse_failed\n'
    [[ -n "${relpath}" ]] && printf 'report: %s\n' "${relpath}"
    return 0
  fi

  [[ "${RGF_DO_NOT_MERGE}" == "1" ]] && printf 'reviewer_says: do_not_merge\n'
  printf 'findings_source: %s\n' "${src}"
  if (( ${#out_lines[@]} + ${#med_lines[@]} == 0 )); then
    printf 'findings: none\n'
  else
    printf 'findings:\n'
    (( ${#out_lines[@]} > 0 )) && printf '%s\n' "${out_lines[@]}"
    (( ${#med_lines[@]} > 0 )) && printf '%s\n' "${med_lines[@]}"
  fi
  # Lows are never rendered. Prefer the report's own REVIEW_FINDINGS: count — the
  # extractor can overcount (a bold line after the last section, e.g. a finish-
  # contract footer, matches the **H1 item shape); fall back to extracted only when
  # the report carried no counts.
  (( exp_l == 0 )) && exp_l="${n_l}"
  local om=""
  (( om_m > 0 )) && om="medium=${om_m}"
  (( exp_l > 0 )) && om="${om:+${om} }low=${exp_l}"
  [[ -n "${om}" ]] && printf 'omitted: %s\n' "${om}"
  [[ -n "${relpath}" ]] && printf 'report: %s\n' "${relpath}"
  return 0
}

# ---------------------------------------------------------------------------
# CLI mode
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  _rgf_report=""; _rgf_json=""; _rgf_arm=""; _rgf_relpath=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --report)      _rgf_report="${2:-}";   shift 2 ;;
      --json)        _rgf_json="${2:-}";     shift 2 ;;
      --arm)         _rgf_arm="${2:-}";      shift 2 ;;
      --report-path) _rgf_relpath="${2:-}";  shift 2 ;;
      -h|--help)     sed -n '3,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *)             shift ;;
    esac
  done
  render_gate_findings "${_rgf_report}" "${_rgf_json}" "${_rgf_arm}" "${_rgf_relpath}"
  exit 0
fi
