#!/usr/bin/env bash
# .claude/hooks/docs-truth-inject.sh — SessionStart wiring for DOCS-TRUTH-02.
#
# Runs scripts/docs-truth-gate.sh against docs/leadv2/open-threads-rules.md.
# On failure, surfaces a short, loud block naming the stale/banned line so the
# next lead cannot copy it unknowingly (the incident this gate exists to
# prevent). A SessionStart hook must never brick the session, so this ALWAYS
# exits 0 — the failure is surfaced via output, not via blocking.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GATE="${PROJECT_ROOT}/scripts/docs-truth-gate.sh"

if [[ ! -x "$GATE" ]]; then
  # Gate not present/executable yet — nothing to enforce, stay silent.
  exit 0
fi

OUTPUT="$(bash "$GATE" --quiet 2>&1)"
RC=$?

if [[ $RC -ne 0 ]]; then
  echo "=========================================================="
  echo "DOCS-TRUTH GATE FAILED — docs/leadv2/open-threads-rules.md"
  echo "=========================================================="
  echo "$OUTPUT" | head -8
  echo "Fix before trusting any line in that file this session."
  echo "=========================================================="
fi

exit 0
