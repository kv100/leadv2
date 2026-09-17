#!/usr/bin/env bash
# Faithful reconstruction of run-core-offline.sh's per-suite env (:249-290):
# denylist scrub (DRY_RUN, GIT_*, PROJECT_ROOT + every LEADV2_*/CLAUDE_*/GIT_CONFIG*
# exported var), private TMPDIR, sandboxed empty HOME, retained PYTHONUSERBASE.
# Usage: harness-env-run.sh <suite-path>
set -uo pipefail
SUITE="$1"; [[ -n "$SUITE" && -r "$SUITE" ]] || { echo "usage: $0 <suite-path>" >&2; exit 91; }

SCRUB_ARGS=()
for v in DRY_RUN GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE PROJECT_ROOT; do
  SCRUB_ARGS+=(-u "$v")
done
while IFS= read -r v; do
  [[ -n "$v" ]] || continue
  case "$v" in
    LEADV2_*|CLAUDE_*|GIT_CONFIG*) SCRUB_ARGS+=(-u "$v") ;;
  esac
done < <(compgen -e 2>/dev/null || true)

PB="${PYTHONUSERBASE:-}"
if [[ -z "$PB" ]] && command -v python3 >/dev/null 2>&1; then
  PB="$(python3 -c 'import site; print(site.USER_BASE)' 2>/dev/null || true)"
fi

RUN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/harness-env-run.XXXXXX")"
trap 'rm -rf "$RUN_TMP"' EXIT
mkdir -p "$RUN_TMP/tmp" "$RUN_TMP/home"

exec env "${SCRUB_ARGS[@]}" "TMPDIR=$RUN_TMP/tmp" "HOME=$RUN_TMP/home" "PYTHONUSERBASE=$PB" \
  bash "$SUITE" "${@:2}"
