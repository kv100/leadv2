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
# file in handoff_dir that looks like a WORKER's OWN claim (never descending
# into handoff_dir/red/ or handoff_dir/round*-red/, which hold the proofs,
# not the claims).
#
# round-3 (review finding): a brief/mission file (lane-mission.md, any
# *mission*.md, review-mission-*.md, context.yaml) can itself contain
# `## [Critical]`/`## [High]` headings -- quoting a PRIOR round's review
# findings verbatim, as every round-N mission in this repo does. Reading
# those back as the CURRENT worker's claimed fixes produced 4/4 false
# positives in production. Two filters, both required:
#   1. filename does not look like a brief (case-insensitive "mission").
#   2. the file ends with the protocol's own deliverable marker
#      (DELIVERABLE_COMPLETE) -- a brief is never terminated that way; only
#      a worker's own <role>.full.md / fix-round-N.md report is.
leadv2_red_proof_named_fixes() {
  local dir="$1" f base
  for f in "${dir}"/*.md; do
    [[ -f "${f}" ]] || continue
    base="$(basename "${f}")"
    case "${base}" in
      *[Mm][Ii][Ss][Ss][Ii][Oo][Nn]*) continue ;;
    esac
    grep -qF 'DELIVERABLE_COMPLETE' "${f}" 2>/dev/null || continue
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
  # round-3: this repo's real RED artifacts live under BOTH <dir>/red/ (single-round
  # tasks) and <dir>/roundN-red/ (per-round, once a task has been re-dispatched) -- e.g.
  # docs/handoff/DISPATCH-CLOSE-GATE-01/{red,round2-red}/. Checking only `red` matched 0
  # of 652 real dispatch dirs on disk.
  for reddir in "${dir}/red" "${dir}"/round*-red; do
    [[ -d "${reddir}" ]] || continue
    for f in "${reddir}"/*; do
      [[ -f "${f}" ]] || continue
      grep -qF -- "${name}" "${f}" 2>/dev/null || continue
      grep -qiE 'mutation' "${f}" 2>/dev/null || continue
      grep -qiE '\b[1-9][0-9]*[[:space:]]+(test[s]?[[:space:]]+)?(failed|failing)\b' "${f}" 2>/dev/null && return 0
    done
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
