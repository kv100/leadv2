#!/usr/bin/env bash
# LANE-WRITES-IS-EMPTY-98-PERCENT-01 — the BEFORE number, by ONE procedure.
#
# The instrument is the PRODUCTION harvester itself: `_prepass_writes` and
# `_prepass_file` are extracted verbatim from leadv2-dispatch-code.sh and run
# over every dispatch handoff directory. Nothing is re-implemented, so the count
# cannot drift from what the dispatcher actually sees.
#
# Four outcomes, not one "empty" -- they are different diseases:
#   A no_artifact      the architect prepass file does not exist / is empty
#   B no_line          artifact exists, carries no LANE_WRITES: line at all
#   C empty_value      the line is there and its value is blank after stripping
#   D all_rejected     entries were declared and ALL were dropped by the L12
#                      over-broad filter (`*`, `**`, `.`, `/`, or a bare existing
#                      top-level directory)
#   E kept             a non-empty CSV survives -- the only healthy outcome
# C and D are the dangerous ones: downstream they are byte-identical to A and B,
# so a declared-but-discarded scope reads as "no scope declared".
set -uo pipefail
ROOT="${1:-$HOME/Projects/leadv2}"
D="$ROOT/plugins/leadv2/scripts/leadv2-dispatch-code.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

{
  printf 'PROJECT_ROOT=%q\nWORK_ROOT=%q\n' "$ROOT" "$ROOT"
  sed -n '/^_prepass_file()/p' "$D"
  sed -n '/^_prepass_writes()/,/^}$/p' "$D"
} > "$T/harvest.sh"
# shellcheck source=/dev/null
source "$T/harvest.sh"

declare -i A=0 B=0 C=0 D_=0 E=0 TOT=0
: > "$T/d.txt"; : > "$T/c.txt"
for dir in "$ROOT"/docs/handoff/dispatch-*/; do
  sig="$(basename "$dir")"; sig="${sig#dispatch-}"
  TOT+=1
  f="$(_prepass_file "$sig")"
  if [[ ! -s "$f" ]]; then A+=1; continue; fi
  if ! line="$(grep -m1 -iE '^[[:space:]*_]*LANE_WRITES[*_]*:' "$f" 2>/dev/null)"; then B+=1; continue; fi
  val="$(printf '%s' "$line" | sed -E 's/^[[:space:]*_]*LANE_WRITES[*_]*:[[:space:]]*//I' \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  kept="$(_prepass_writes "$sig")"
  if [[ -z "$val" ]]; then C+=1; printf '%s\n' "$sig" >> "$T/c.txt"; continue; fi
  if [[ -z "$kept" ]]; then D_+=1; printf '%s | %s\n' "$sig" "$val" >> "$T/d.txt"; continue; fi
  E+=1
done

pct() { awk -v n="$1" -v t="$2" 'BEGIN{ if(t==0){print "n/a"} else {printf "%.1f%%", 100*n/t} }'; }
printf 'corpus: %d dispatch handoff dirs under %s\n\n' "$TOT" "${ROOT/#$HOME/~}"
printf '  A no_artifact   %5d  %s\n' "$A"  "$(pct "$A"  "$TOT")"
printf '  B no_line       %5d  %s\n' "$B"  "$(pct "$B"  "$TOT")"
printf '  C empty_value   %5d  %s\n' "$C"  "$(pct "$C"  "$TOT")"
printf '  D all_rejected  %5d  %s\n' "$D_" "$(pct "$D_" "$TOT")"
printf '  E kept          %5d  %s   <- the only healthy outcome\n' "$E" "$(pct "$E" "$TOT")"
printf '\n  effectively empty (A+B+C+D): %d  %s\n' "$((A+B+C+D_))" "$(pct "$((A+B+C+D_))" "$TOT")"
if [[ -s "$T/d.txt" ]]; then
  printf '\n  D sample (declared, then discarded as over-broad):\n'; head -8 "$T/d.txt" | sed 's/^/    /'
fi
if [[ -s "$T/c.txt" ]]; then
  printf '\n  C sample (line present, value blank): %s\n' "$(head -6 "$T/c.txt" | tr '\n' ' ')"
fi
