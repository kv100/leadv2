#!/usr/bin/env bash
# /tmp helper (NOT shipped) — drives the EXACT cache-sync body
# leadv2-plugin-sync.sh runs for one subdir, in a sandboxed subprocess, so the
# quarantine-then-reconcile test exercises the real _direction_safety_excludes
# + rsync reconcile path end-to-end without touching the live trees.
# Args: $1 plugin_sync_path  $2 canonical_scripts_root  $3 src/  $4 dst
#       $5 mode: --dry-run | --write (REQUIRED)
set -uo pipefail
plugin_sync="$1"; scripts_root="$2"; src="$3"; dst="$4"; mode="${5:-}"
case "$mode" in
  --dry-run|--write) ;;
  *)
    printf -- 'usage: pe_run_cache_sync.sh <plugin_sync> <scripts_root> <src> <dst> --dry-run|--write\n' >&2
    exit 3
    ;;
esac
set --   # clear positional params: plugin-sync.sh's sourced top-level arg
         # parser would otherwise see these and exit 2 ("Unknown arg") before
         # the cache loop ever runs (same fix as the _vs_call test harness).
# Source only the function-definitions portion (before the top-level body at
# "changed_summary=()"), exactly like the existing _vs_call test harness.
cutoff_line="$(grep -n "^changed_summary=()" "${plugin_sync}" | head -1 | cut -d: -f1)"
cutoff_line="$((cutoff_line - 1))"
# shellcheck disable=SC1090
source <(sed -n "1,${cutoff_line}p" "${plugin_sync}")
# Sourced via process-substitution -> SCRIPT_DIR resolves to a transient fd
# path, so _DIRECTION_SAFETY_CHECK would not find the checker. Point it at the
# real (stateless) canonical checker explicitly. PLUGIN_GIT_ROOT/CANONICAL_ROOT
# already resolved correctly at source time from LEADV2_CANONICAL_ROOT.
_DIRECTION_SAFETY_CHECK="${scripts_root}/leadv2-direction-safety-check.py"
# The sourced portion's own top-level body (leadv2-plugin-sync.sh:91) sets its
# own default DRY_RUN=true unconditionally as it executes during `source`
# above, clobbering anything set beforehand. Set DRY_RUN from the required
# mode argument AFTER sourcing (and before the _direction_safety_excludes
# call below) so this fixture's own choice always wins.
case "$mode" in
  --dry-run) DRY_RUN=true ;;
  --write) DRY_RUN=false ;;
esac
_unsafe_excludes=()
while IFS= read -r _u; do
  [[ -z "${_u}" ]] && continue
  _unsafe_excludes+=(--exclude="${_u}")
done < <(_direction_safety_excludes "warn" "cache/scripts" "scripts" "${src}" "${dst}")
if [[ "${DRY_RUN}" != "true" ]]; then
  rsync --checksum --recursive --delete "${_unsafe_excludes[@]}" "${src}" "${dst}"
fi
