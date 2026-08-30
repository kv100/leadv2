#!/usr/bin/env bash
# leadv2-red-proof.sh — DISPATCH-CLOSE-GATE-01 Mechanism 2.
#
# Sourced (never executed) by leadv2-dispatch-code.sh. Cross-checks a
# worker's claimed fixes against RED artifacts on disk at close, and names
# any claim without one as `unproven` — it does NOT block the close (D3:
# the gate reports, it does not trap the lane). Measured cost this mechanism
# exists for: the single most repeated review finding across fourteen
# dispatch rounds on 2026-08-30 was "this assertion survives its own
# mutation" — a claim of fixed that no RED run ever backed.
#
# Scope note: only `## [Critical]` / `## [High]` headings are detected as
# named fixes. A "mutation table" is also in the mission's stated scope, but
# no concrete table format exists anywhere in this repo's worker reports to
# key off of; inventing one risks silently not catching what a report
# actually uses. Left undetected — see docs/handoff/DISPATCH-CLOSE-GATE-01/
# report.md.
#
# Bash 3.2 safe: no associative arrays, no ${x^^}, no mapfile.

# leadv2_red_proof_named_fixes <handoff_dir> -> stdout: fix names (one per
# line, NOT de-duplicated — caller dedupes), read from every top-level *.md
# file in handoff_dir (never descending into handoff_dir/red/, which holds
# the proofs, not the claims).
leadv2_red_proof_named_fixes() {
  local dir="$1" f
  for f in "${dir}"/*.md; do
    [[ -f "${f}" ]] || continue
    grep -oE '^##[[:space:]]*\[(Critical|High)\][[:space:]].+' "${f}" 2>/dev/null \
      | sed -E 's/^##[[:space:]]*\[(Critical|High)\][[:space:]]*//' \
      | sed -E 's/[[:space:]]+$//'
  done
}

# leadv2_red_proof_has_red <handoff_dir> <fix_name> -> rc 0 if a RED artifact
# under handoff_dir/red/ backs this fix, rc 1 otherwise.
#
# A backing artifact must, in the SAME file:
#   - name the fix (fixed-string substring match, so a fix name containing
#     regex metacharacters is matched literally)
#   - show evidence a mutation was applied (the word "mutation")
#   - show a NONZERO failure count ("N failed"/"N failing", N>=1) — a file
#     whose only count is "0 failed" does not satisfy this fix.
leadv2_red_proof_has_red() {
  local dir="$1" name="$2" reddir f
  reddir="${dir}/red"
  [[ -d "${reddir}" ]] || return 1
  for f in "${reddir}"/*; do
    [[ -f "${f}" ]] || continue
    grep -qF -- "${name}" "${f}" 2>/dev/null || continue
    grep -qiE 'mutation' "${f}" 2>/dev/null || continue
    grep -qiE '\b[1-9][0-9]*[[:space:]]+(test[s]?[[:space:]]+)?(failed|failing)\b' "${f}" 2>/dev/null && return 0
  done
  return 1
}

# leadv2_red_proof_unproven <handoff_dir> -> stdout: "unproven: <name>" for
# every distinct named fix without a backing RED artifact. Always rc 0
# (report, don't fail — D3).
leadv2_red_proof_unproven() {
  local dir="$1" name
  leadv2_red_proof_named_fixes "${dir}" | awk '!seen[$0]++' | while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    leadv2_red_proof_has_red "${dir}" "${name}" || printf 'unproven: %s\n' "${name}"
  done
  return 0
}
