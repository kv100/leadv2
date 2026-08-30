#!/usr/bin/env bash
# leadv2-mission-writeset.sh — DISPATCH-CLOSE-GATE-01 Mechanism 1.
#
# Sourced (never executed) by leadv2-dispatch-code.sh. Owns the check that
# refuses a dispatch BEFORE it spawns when the mission demands a path that
# the lane's LANE_WRITES does not cover. Measured cost this mechanism exists
# for: two full re-dispatch rounds in one afternoon (2026-08-30) where a
# worker correctly stopped rather than write out of scope, and the round had
# to be thrown away and re-dispatched with a corrected write set.
#
# Bash 3.2 safe: no associative arrays, no ${x^^}, no mapfile.

# leadv2_writeset_extract_required — stdin: mission text -> stdout: one
# required path per line, de-duplicated, order-preserved.
#
# Sources scanned:
#   1. Backticked path-like tokens inside a "## Done means" section (any
#      heading depth), EXCLUDING any backtick preceded on the same line by a
#      citation verb (see/read/refer/per/cited/described/shown/documented) —
#      those are evidence to consult, not a path the worker must produce.
#   2. Any line anywhere in the mission matching "leave the logs in <path>"
#      or "write ... to <path>" / "save ... to <path>".
# Deliberately NOT scanned: prose outside Done-means that merely names a
# path (a report to read, a file cited as context) — under-detecting there
# is the documented tradeoff (a missed refusal costs one review round; a
# false refusal blocks a good dispatch outright).
leadv2_writeset_extract_required() {
  local _mtext
  _mtext="$(cat)"
  # python3 - <<'heredoc' would consume stdin AS the script source, leaving nothing for
  # the script's own stdin read -- the mission text is passed as argv[1] instead.
  python3 - "${_mtext}" <<'PY'
import re, sys

text = sys.argv[1]
lines = text.splitlines()

required = []
citation_re = re.compile(
    r'\b(see|read|reading|refer|reference|referenced|per|cited|citing|described|shown|documented)\b',
    re.I,
)
path_re = re.compile(r'`([A-Za-z0-9_.\-]*/[A-Za-z0-9_./\-\*]*)`')

in_section = False
for line in lines:
    if re.match(r'^\s*#{1,6}\s*Done means\b', line, re.I):
        in_section = True
        continue
    if in_section and re.match(r'^\s*#{1,6}\s', line):
        in_section = False
        continue
    if in_section:
        for m in path_re.finditer(line):
            prefix = line[:m.start()]
            if citation_re.search(prefix):
                continue
            required.append(m.group(1))

instr_re = re.compile(
    r'(?:leave the logs in|writ(?:e|ing)\s+.*?\s+to|sav(?:e|ing)\s+.*?\s+to)\s+'
    r'`?([A-Za-z0-9_.\-]*/[A-Za-z0-9_./\-\*]*)`?',
    re.I,
)
for line in lines:
    for m in instr_re.finditer(line):
        required.append(m.group(1))

seen = []
for p in required:
    p = p.rstrip('.,;:')
    if p and p not in seen:
        seen.append(p)
for p in seen:
    print(p)
PY
}

# leadv2_writeset_missing <lane_writes_csv> ; stdin: mission text -> stdout:
# required paths NOT covered by lane_writes_csv, one per line. Always rc 0
# (report, don't fail) — the caller decides whether "any output" is a refusal.
#
# Coverage rules for a declared entry <decl> against a required <path>:
#   - exact string match
#   - <decl> is a directory prefix of <path> (decl/, or decl followed by /)
#   - <decl> contains '*' and glob-matches <path>
leadv2_writeset_missing() {
  local writes_csv="$1"
  local mission_text
  mission_text="$(cat)"
  local required
  required="$(printf '%s\n' "${mission_text}" | leadv2_writeset_extract_required)"
  [[ -n "${required}" ]] || return 0

  if [[ -z "${writes_csv}" ]]; then
    writes_csv="$(printf '%s\n' "${mission_text}" \
      | grep -m1 -iE '^[[:space:]*_]*LANE_WRITES[*_]*:' \
      | sed -E 's/^[[:space:]*_]*LANE_WRITES[*_]*:[[:space:]]*//I')"
  fi

  local -a decls=()
  local IFS_SAVE="${IFS}"
  IFS=','
  read -ra decls <<< "${writes_csv}"
  IFS="${IFS_SAVE}"

  local path decl hit
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    hit=0
    for decl in "${decls[@]}"; do
      decl="$(printf '%s' "${decl}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -n "${decl}" ]] || continue
      if [[ "${path}" == "${decl}" ]]; then hit=1; break; fi
      case "${decl}" in
        */) case "${path}" in "${decl}"*) hit=1 ;; esac ;;
        *)  case "${path}" in "${decl}"/*) hit=1 ;; esac ;;
      esac
      [[ ${hit} -eq 1 ]] && break
      case "${decl}" in
        *'*'*) case "${path}" in ${decl}) hit=1 ;; esac ;;
      esac
      [[ ${hit} -eq 1 ]] && break
    done
    [[ ${hit} -eq 0 ]] && printf '%s\n' "${path}"
  done <<< "${required}"
  return 0
}

# leadv2_writeset_suggest_line <lane_writes_csv> ; stdin: missing paths (one
# per line) -> stdout: a ready-to-paste corrected "LANE_WRITES:" line.
leadv2_writeset_suggest_line() {
  local writes_csv="$1" combined="${1}" m
  while IFS= read -r m; do
    [[ -n "${m}" ]] || continue
    if [[ -n "${combined}" ]]; then combined="${combined},${m}"; else combined="${m}"; fi
  done
  printf 'LANE_WRITES: %s\n' "${combined}"
}
