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
    r'\b(see|read|reading|refer|reference|referenced|per|cited|citing|described|shown|'
    # round-3 (fix-round-2.md false positive): a Done-means line can name a path as the
    # EXPECTED OUTPUT of a checker/test the worker runs, not a file the worker must
    # itself produce ("asserting X quotes `lib/leadv2-lane-guard.sh` as expected checker
    # output"). "quote(s|d)", "expected", "checker output" and "names it/names <path>" are
    # the repo's actual phrasing for that distinction.
    r'documented|quote[sd]?|expected|checker output|names? it|as an? example)\b',
    re.I,
)
path_re = re.compile(r'`([A-Za-z0-9_.\-]*/[A-Za-z0-9_./\-\*]*)`')

# C2 (DISPATCH-CLOSE-GATE-01 round 2): a bare backticked fragment like `red/` or
# `round4-red/` has one path segment and is never a real LANE_WRITES entry -- it false-
# positived on a real, already-corrected mission (fix-round-4.md). Require >=2 non-empty
# path segments before treating a backticked token as a required path.
# round-3: an absolute path (`/bin/bash`, `/etc/passwd`) also splits into >=2 segments but
# is never a repo-relative LANE_WRITES entry -- every real entry in this repo is relative.
def repo_rooted(path):
    if path.startswith('/'):
        return False
    return len([s for s in path.split('/') if s]) >= 2

def add_path(bucket, line, m):
    prefix = line[:m.start()]
    if citation_re.search(prefix):
        return
    p = m.group(1)
    if repo_rooted(p):
        bucket.append(p)

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
            add_path(required, line, m)

# C3 (DISPATCH-CLOSE-GATE-01 round 2): the Done-means/instruction scan never looked at a
# source file named as a required edit elsewhere in the body. Both real corrected specimens
# (fix-round-4.md, fix-round-5.md) name a retroactively-added required path under a
# "**Write set note (corrected):** ... omitted `<path>` ... from LANE_WRITES" paragraph --
# that is the repo's actual convention for this, not a generic "scope" keyword (which also
# matches noise like `--scope changed`, `/bin/bash`, unrelated backtick paths).
scope_re = re.compile(r'write set note', re.I)
for para in re.split(r'\n\s*\n', text):
    if not scope_re.search(para):
        continue
    for line in para.splitlines():
        for m in path_re.finditer(line):
            add_path(required, line, m)

# C3: every real mission in this repo writes "Leave the RED logs in", never the bare
# "leave the logs in" the old regex demanded -- the word RED (or any adjective) between
# "leave" and "logs" defeated it on the whole corpus.
instr_re = re.compile(
    r'(?:leave\s+(?:the\s+)?(?:\w+\s+)?logs?\s+in|writ(?:e|ing)\s+.*?\s+to|sav(?:e|ing)\s+.*?\s+to)\s+'
    r'`?([A-Za-z0-9_.\-]*/[A-Za-z0-9_./\-\*]*)`?',
    re.I,
)
for line in lines:
    for m in instr_re.finditer(line):
        p = m.group(1)
        if repo_rooted(p):
            required.append(p)

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
  # H2 (DISPATCH-CLOSE-GATE-01 round 2): a caller (suggest_line) that only has the
  # ORIGINAL possibly-empty arg has no way to know we fell back to the mission's own
  # LANE_WRITES: line -- it would paste a "corrected" line built from nothing but the
  # missing paths, destroying every other declared entry. Not `local`: the caller reads
  # this after we return.
  LEADV2_WRITESET_RESOLVED_CSV="${writes_csv}"

  local -a decls=()
  local IFS_SAVE="${IFS}"
  IFS=','
  read -ra decls <<< "${writes_csv}"
  IFS="${IFS_SAVE}"

  local path decl hit
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    hit=0
    # H1 (DISPATCH-CLOSE-GATE-01 round 2): "${decls[@]}" is an unbound-variable error under
    # bash 3.2's `set -u` when decls has zero elements (empty writes_csv, no LANE_WRITES:
    # line in the mission) -- the caller's command substitution swallowed the crash and the
    # gate failed OPEN, silently. ${decls[@]+"${decls[@]}"} expands to nothing instead of
    # erroring when the array is empty, so the loop body legitimately runs zero times and
    # every required path falls through to the "missing" print below -- fail CLOSED.
    for decl in ${decls[@]+"${decls[@]}"}; do
      decl="$(printf '%s' "${decl}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -n "${decl}" ]] || continue
      if [[ "${path}" == "${decl}" ]]; then hit=1; break; fi
      case "${decl}" in
        */) case "${path}" in "${decl}"*) hit=1 ;; esac ;;
        *)  case "${path}" in "${decl}"/*) hit=1 ;; esac ;;
      esac
      [[ ${hit} -eq 1 ]] && break
      # C3 (DISPATCH-CLOSE-GATE-01 round 2): a required path can also be a directory that
      # a declared entry lives UNDER (required=`docs/handoff/X/`, decl=`docs/handoff/X/
      # round4-red/`) -- the mirror of the prefix rule above, needed once extraction started
      # picking up ancestor directories named in a "Write set note" paragraph.
      case "${path}" in
        */) case "${decl}" in "${path}"*) hit=1 ;; esac ;;
      esac
      [[ ${hit} -eq 1 ]] && break
      # C3: a required path can also be the relative TAIL of a fully repo-rooted decl
      # (required=`lib/leadv2-lane-guard.sh` as named in body prose, decl=`plugins/leadv2/
      # scripts/lib/leadv2-lane-guard.sh` as declared) -- same file, shorter mention.
      case "${decl}" in
        *"/${path}") hit=1 ;;
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
# H2: if the caller's own csv arg is empty (leadv2_writeset_missing fell back to parsing
# the mission's own LANE_WRITES: line), fall back to that same resolved csv so the pasted
# line is existing+missing, never just missing.
leadv2_writeset_suggest_line() {
  local writes_csv="$1"
  [[ -z "${writes_csv}" ]] && writes_csv="${LEADV2_WRITESET_RESOLVED_CSV:-}"
  local combined="${writes_csv}" m
  while IFS= read -r m; do
    [[ -n "${m}" ]] || continue
    if [[ -n "${combined}" ]]; then combined="${combined},${m}"; else combined="${m}"; fi
  done
  printf 'LANE_WRITES: %s\n' "${combined}"
}
