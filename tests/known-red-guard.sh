#!/usr/bin/env bash
# tests/known-red-guard.sh — CI-RUNS-THE-SUITES-01, revised 2026-09-14 by
# THE-KNOWN-RED-REGISTRY-ROTTED-AND-EVERY-LANE-PAYS-01.
#
# tests/known-red-suites.txt (the allow-list of tolerated red suites) may
# always SHRINK for free. Until 2026-09-14 it could never grow at all ("may
# only shrink, no exceptions") — that sounded safe but had no legitimate
# channel for registering a suite that turns red AFTER the list's snapshot
# date, so genuinely new reds were simply never added. Thirteen-plus of them
# accumulated silently over twelve days (SD-MAIN-CORE-SUITE-RED-01) and every
# one blew the blast radius of run-core-offline.sh's all-or-nothing wrapper
# classification onto every lane, not just the lane that caused it.
#
# This guard now checks THREE things instead of one:
#   1. DATED GROWTH: an entry present in the working tree but not at
#      base-ref may only exist if its trailing comment carries a
#      `YYYY-MM-DD` date token — a reason with no date is not a reason.
#      (Shrinking — removing an entry — never needs sign-off.)
#   2. STALE core: ENTRIES: every `core:<label>` must match a live label in
#      plugins/leadv2/scripts/tests/run-core-offline.sh's SUITE_DEFS. A label
#      that matches nothing was renamed, removed, or typo'd — the list is
#      granting silent immunity to nothing, which is worse than no entry at
#      all (a genuinely new failure under that old label now reads as an
#      unrelated, unlisted red instead of surfacing as [KNOWN-RED-GONE-GREEN]
#      or a plain failure).
#   3. STALE path: ENTRIES: every `path:<rel>` must resolve to a real file.
#   4. GONE-GREEN (opt-in, needs a transcript): tests/run-all.sh already
#      detects a `core:` entry that passed a full-set run and prints it as
#      [KNOWN-RED-GONE-GREEN], but that is deliberately informational-only in
#      run-all.sh (does not affect its exit code — see
#      plugins/leadv2/tests/test-gate-reaches-a-verdict-inside-budget.sh
#      cases 6/7/10/11, which assert exactly that). This guard adds a SEPARATE,
#      additive hard-refusal layer: given a transcript (stdout captured from a
#      full-set `tests/run-all.sh --scope all` or a bare
#      `run-core-offline.sh` run) as a second argument, every
#      [KNOWN-RED-GONE-GREEN] line in it is a violation here. This is what
#      makes a stale "snapshot disagrees with the live result" entry a visible
#      refusal instead of silence — without changing run-all.sh's own
#      contract.
#
# usage: tests/known-red-guard.sh [base-ref] [transcript-file]
#   base-ref defaults to origin/main, falling back to main, falling back to
#   "no history to compare" (first-ever commit of the list passes trivially).
#   transcript-file is optional; omit it to skip check 4 (no transcript to
#   check means nothing to disagree with).
# exit 0: no violation of any of the checks above
# exit 1: at least one violation (undated growth, stale core:, stale path:,
#         or gone-green-in-transcript)
# exit 2: tests/known-red-suites.txt does not exist (FATAL, not a violation)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
LIST_REL="tests/known-red-suites.txt"
LIST_ABS="${ROOT}/${LIST_REL}"
CORE_OFFLINE_ABS="${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh"

BASE_REF="${1:-}"
TRANSCRIPT="${2:-}"
if [[ -z "${BASE_REF}" ]]; then
  for cand in origin/main main; do
    if git -C "${ROOT}" rev-parse --verify "${cand}" >/dev/null 2>&1; then
      BASE_REF="${cand}"
      break
    fi
  done
fi

if [[ ! -f "${LIST_ABS}" ]]; then
  echo "known-red-guard: FATAL ${LIST_REL} does not exist" >&2
  exit 2
fi

# Normalized entry id: the id token before any trailing "# reason" comment,
# with surrounding whitespace trimmed. Used for the base-vs-current diff so a
# comment-only edit (fixing a typo in the reason) is never mistaken for new
# growth.
normalized_ids() {
  grep -vE '^[[:space:]]*(#|$)' "$1" 2>/dev/null \
    | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//'
}

CURRENT_IDS="$(normalized_ids "${LIST_ABS}")"
CURRENT_COUNT="$(printf '%s\n' "${CURRENT_IDS}" | grep -c . || true)"
CURRENT_COUNT="${CURRENT_COUNT:-0}"

BASE_IDS=""
BASE_COUNT=""
if [[ -n "${BASE_REF}" ]] && git -C "${ROOT}" cat-file -e "${BASE_REF}:${LIST_REL}" 2>/dev/null; then
  BASE_IDS="$(git -C "${ROOT}" show "${BASE_REF}:${LIST_REL}" \
    | grep -vE '^[[:space:]]*(#|$)' \
    | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//')"
  BASE_COUNT="$(printf '%s\n' "${BASE_IDS}" | grep -c . || true)"
  BASE_COUNT="${BASE_COUNT:-0}"
fi

if [[ -z "${BASE_COUNT}" ]]; then
  echo "known-red-guard: no ${LIST_REL} found at base-ref=${BASE_REF:-<none>} — treating as first introduction, nothing to compare (current_count=${CURRENT_COUNT})"
  BASE_IDS=""
fi

echo "known-red-guard: base=${BASE_REF:-<none>} base_count=${BASE_COUNT:-0} current_count=${CURRENT_COUNT}"

VIOLATIONS=0

# ── check 1: every entry NEW relative to base-ref must carry a date token ──
while IFS= read -r line; do
  [[ -n "${line}" ]] || continue
  id="$(printf '%s' "${line}" | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//')"
  if [[ -n "${BASE_IDS}" ]] && grep -qxF "${id}" <<<"${BASE_IDS}"; then
    continue  # already present at base-ref — free, no date required
  fi
  if ! grep -qE '\b20[0-9]{2}-[0-9]{2}-[0-9]{2}\b' <<<"${line}"; then
    echo "known-red-guard: FAIL undated-growth — new entry has no YYYY-MM-DD date token in its reason comment:" >&2
    echo "  ${line}" >&2
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
done < <(grep -vE '^[[:space:]]*(#|$)' "${LIST_ABS}")

# ── checks 2 & 3: every entry must resolve against the LIVE tree ──────────
CURRENT_LABELS=""
if [[ -f "${CORE_OFFLINE_ABS}" ]]; then
  CURRENT_LABELS="$(grep -oE '^[[:space:]]*"[^"]+\|\|\|' "${CORE_OFFLINE_ABS}" \
    | sed -E 's/^[[:space:]]*"//; s/\|\|\|.*$//')"
fi

while IFS= read -r id; do
  [[ -n "${id}" ]] || continue
  case "${id}" in
    core:*)
      label="${id#core:}"
      if [[ -z "${CURRENT_LABELS}" ]] || ! grep -qxF "${label}" <<<"${CURRENT_LABELS}"; then
        echo "known-red-guard: FAIL stale-core — no current SUITE_DEFS label matches: ${id}" >&2
        echo "  (renamed, removed, or typo'd — remove or correct this entry in ${LIST_REL})" >&2
        VIOLATIONS=$((VIOLATIONS + 1))
      fi
      ;;
    path:*)
      rel="${id#path:}"
      if [[ ! -f "${ROOT}/${rel}" ]]; then
        echo "known-red-guard: FAIL stale-path — file does not exist: ${id}" >&2
        VIOLATIONS=$((VIOLATIONS + 1))
      fi
      ;;
    *)
      echo "known-red-guard: FAIL malformed — entry has neither core: nor path: prefix: ${id}" >&2
      VIOLATIONS=$((VIOLATIONS + 1))
      ;;
  esac
done <<<"${CURRENT_IDS}"

# ── check 4 (opt-in): a supplied transcript must carry no GONE-GREEN lines ──
if [[ -n "${TRANSCRIPT}" ]]; then
  if [[ ! -f "${TRANSCRIPT}" ]]; then
    echo "known-red-guard: FAIL transcript-missing — ${TRANSCRIPT} does not exist" >&2
    VIOLATIONS=$((VIOLATIONS + 1))
  else
    while IFS= read -r gg_line; do
      [[ -n "${gg_line}" ]] || continue
      echo "known-red-guard: FAIL gone-green — transcript shows a registered entry now passing:" >&2
      echo "  ${gg_line}" >&2
      VIOLATIONS=$((VIOLATIONS + 1))
    done < <(grep -oE '\[KNOWN-RED-GONE-GREEN\] core:.*$' "${TRANSCRIPT}" 2>/dev/null || true)
  fi
fi

if [[ "${VIOLATIONS}" -gt 0 ]]; then
  echo "known-red-guard: FAIL — ${VIOLATIONS} violation(s); see above." >&2
  exit 1
fi

echo "known-red-guard: OK (no undated growth, no stale entries$( [[ -n "${TRANSCRIPT}" ]] && printf ', no gone-green in transcript' ))"
