#!/usr/bin/env bash
# leadv2-code-intel-rate.sh — CODE-INTEL-IS-INSTALLED-AND-UNUSED-01
#
# Tallies the code_intel_preamble decision line (leadv2-dispatch-code.sh,
# emitted once per worker spawn) across every task journal in THIS repo, by
# arm and by mode (attached | fail_open | arm_unwired). Read-only reporting,
# never a gate — exit 0 regardless of what the counts say.
#
# Why this exists: 2026-09-03 the founder asked how often code-intel is used
# and whether it saves anything. The answer required grepping ~800 journal
# files by hand (docs/handoff/CODE-INTEL-IS-INSTALLED-AND-UNUSED-01/brief.md
# item 5) because nothing surfaced the attach rate anywhere. This script is
# that surface, so the question never again requires an ad-hoc audit.
#
# Journal path convention: leadv2-journal.sh writes to
# ${PROJECT_ROOT}/docs/leadv2/tasks/<task-id>/journal.md — this script reads
# that same convention directly (grep), never re-implementing journal parsing.
#
# Usage:
#   leadv2-code-intel-rate.sh              # table, all-time
#   leadv2-code-intel-rate.sh --since 2026-09-01   # only journal lines with a
#                                                     timestamp >= this date
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# LEADV2_CODE_INTEL_RATE_ROOT: test-only override (test-code-intel-rate.sh)
# so the suite can point this at a scratch tasks/ tree instead of the real
# repo's 800+ journals.
PROJECT_ROOT="${LEADV2_CODE_INTEL_RATE_ROOT:-}"
if [[ -z "${PROJECT_ROOT}" ]]; then
  PROJECT_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null)"
  [[ -n "${PROJECT_ROOT}" ]] || PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

SINCE=""
if [[ "${1:-}" == "--since" ]]; then
  SINCE="${2:?--since requires YYYY-MM-DD}"
fi

TASKS_DIR="${PROJECT_ROOT}/docs/leadv2/tasks"
if [[ ! -d "${TASKS_DIR}" ]]; then
  echo "[code-intel-rate] no ${TASKS_DIR} — nothing to report" >&2
  exit 0
fi

TMP="$(mktemp "${TMPDIR:-/tmp}/code-intel-rate.XXXXXX")"
trap 'rm -f "${TMP}"' EXIT

# find + grep, never a shell glob over 800+ dirs (ARG_MAX safety).
find "${TASKS_DIR}" -maxdepth 2 -name "journal.md" -print0 2>/dev/null \
  | xargs -0 grep -h "code_intel_preamble arm=" 2>/dev/null > "${TMP}" || true

if [[ -n "${SINCE}" ]]; then
  awk -v since="${SINCE}" '{
    ts = $2; gsub(/[][]/, "", ts);
    if (substr(ts,1,10) >= since) print
  }' "${TMP}" > "${TMP}.filtered" && mv "${TMP}.filtered" "${TMP}"
fi

TOTAL=$(wc -l < "${TMP}" | tr -d ' ')
if [[ "${TOTAL}" -eq 0 ]]; then
  echo "code-intel attach rate: 0 decisions recorded${SINCE:+ since ${SINCE}}"
  exit 0
fi

echo "code-intel attach rate — ${TOTAL} decision(s)${SINCE:+ since ${SINCE}}, by arm:"
echo

grep -oE "arm=[a-z0-9_-]+ task=[a-z0-9_-]+ mode=[a-z_]+( reason=[a-z_]+)?" "${TMP}" \
  | awk '
    {
      arm=""; mode="other";
      for (i=1;i<=NF;i++) {
        if ($i ~ /^arm=/) { split($i,a,"="); arm=a[2] }
      }
      if ($0 ~ /mode=attached/) mode="attached";
      else if ($0 ~ /reason=fail_open/) mode="fail_open";
      else if ($0 ~ /reason=arm_unwired/) mode="arm_unwired";
      key = arm "\t" mode;
      count[key]++;
    }
    END {
      for (k in count) print count[k], k
    }
  ' | sort -k3,3 -k1,1nr | awk 'BEGIN{printf "%-12s %-14s %s\n","ARM","MODE","COUNT"}
    {printf "%-12s %-14s %s\n",$2,$3,$1}'

echo
ATTACHED=$(grep -c "mode=attached" "${TMP}" || true)
WIRED_ARM_TOTAL=$(grep -cE "mode=attached|reason=fail_open" "${TMP}" || true)
if [[ "${WIRED_ARM_TOTAL}" -gt 0 ]]; then
  PCT=$(awk -v a="${ATTACHED}" -v t="${WIRED_ARM_TOTAL}" 'BEGIN{printf "%.0f", (a/t)*100}')
  echo "attach rate among MCP-capable arms (excludes codex arm_unwired): ${ATTACHED}/${WIRED_ARM_TOTAL} = ${PCT}%"
else
  echo "attach rate among MCP-capable arms: no data"
fi
