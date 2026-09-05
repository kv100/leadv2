#!/usr/bin/env bash
# WRITESET-CAROUSEL-01 — the same real dispatch admission, run against the REAL
# live registry, once with leadv2-active-registry.sh as it stood before this
# lane (cd1a4d2e^) and once as it stands now.
#
# Nothing is written to the live registry: its active.yaml is COPIED into a
# scratch state root and the candidate registers there. Everything else is real
# — the real leadv2_active_register, the real rows, the real pids.
#
# Usage: bash docs/handoff/WRITESET-CAROUSEL-01/live-runs.sh [<candidate write set>]
set -uo pipefail
cd "$HOME/Projects/leadv2" || exit 1
LIVE="$HOME/.claude/leadv2-state/leadv2/active.yaml"
PREV_SHA="cd1a4d2e^"
WS="${1:-plugins/leadv2/scripts/leadv2-active-registry.sh}"

printf 'live registry: %s\n' "$LIVE"
printf 'candidate write set: %s\n' "$WS"
python3 -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
rows = d.get("sessions") or []
nopid = [r for r in rows if r.get("pid") in (None,"","null","None") and not r.get("writes")]
print("  rows=%d  pid-less AND undeclared=%d" % (len(rows), len(nopid)))
' "$LIVE"

run_against() {
  local label="$1" sha="$2" d out rc
  d="$(mktemp -d)"
  mkdir -p "$d/scripts" "$d/root/docs/leadv2"
  cp -R plugins/leadv2/scripts/. "$d/scripts/"
  if [[ -n "$sha" ]]; then
    git show "${sha}:plugins/leadv2/scripts/leadv2-active-registry.sh" \
      > "$d/scripts/leadv2-active-registry.sh" || { printf 'git show failed\n'; return 1; }
  fi
  cp "$LIVE" "$d/root/docs/leadv2/active.yaml"
  out="$(WS="$WS" LEADV2_PROJECT_ROOT="$d/root" LEADV2_STATE_ROOT="$d/root" \
         LEADV2_WRITESET_PENDING_WINDOW_SEC=900 LEADV2_WRITESET_ENFORCE=warn \
         LEADV2_BURN_GOVERNOR=0 \
         bash -c 'source "$0"; leadv2_active_register "WRITESET-CAROUSEL-01" Standard "$1" wt-carousel false "" "" "$WS"' \
         "$d/scripts/leadv2-active-registry.sh" "$d/root" 2>&1 >/dev/null)"; rc=$?
  printf '\n== %s\n  rc=%d\n' "$label" "$rc"
  printf '%s\n' "$out" | grep -v 'LEADV2_WRITESET_UNKNOWN' | sed 's/^/  /'
  printf '  (+%s LEADV2_WRITESET_UNKNOWN lines elided — legacy rows outside the window)\n' \
    "$(printf '%s\n' "$out" | grep -c 'LEADV2_WRITESET_UNKNOWN')"
  case "$rc" in
    0) printf '  VERDICT: ADMITTED\n' ;;
    5) printf '  VERDICT: REFUSED (conflict code)\n' ;;
    *) printf '  VERDICT: rc=%d\n' "$rc" ;;
  esac
  rm -rf "$d"
}

run_against "BEFORE — registry at ${PREV_SHA}" "$PREV_SHA"
run_against "AFTER  — registry at HEAD" ""
