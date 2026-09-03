#!/usr/bin/env bash
# Evidence artifact for FREEPOOL-MUST-ACTUALLY-GET-WORK-01.  Each invocation
# streams one focused suite directly, so the suite's synthetic-worker cleanup
# cannot swallow a later mutation control in this process group.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
case "${1:-}" in
  protection-and-floor)
    bash "${ROOT}/plugins/leadv2/scripts/tests/test-freepool-gets-work.sh"
    rc=$?
    ;;
  turn-cap-checkpoint)
    bash "${ROOT}/plugins/leadv2/scripts/tests/test-freepool-turncap-checkpoint.sh"
    rc=$?
    ;;
  *)
    echo 'usage: leadv2-mutation-control.sh protection-and-floor|turn-cap-checkpoint' >&2
    exit 2
    ;;
esac
printf 'ARTIFACT=%s EXIT=%s\n' "$1" "${rc}"
exit "${rc}"
