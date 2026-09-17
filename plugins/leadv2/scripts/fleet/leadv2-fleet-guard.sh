#!/usr/bin/env bash
# leadv2-fleet-guard.sh — FLEET-RUNTIME-UNATTENDED-01
#
# Periodic maintenance, invoked by a systemd TIMER (never a `while true`
# inside a unit — that shape is exactly the retired supervisor-daemon
# pattern this task is forbidden from reviving). Each invocation does one
# pass and exits:
#   1. reap lane worktrees that reached a terminal
#   2. refuse (self-stop) a new lane below the disk floor
#   3. detect a stalled lane (worktree untouched N minutes) and record it
#
# No `claude` invocation anywhere in this file (mission off-limits, stated
# explicitly for guard and state reader).
#
# Reap scope decision: this script does NOT parse leadv2-active-registry.sh's
# internal schema (docs/leadv2/active.yaml / the live registry) — that file
# is owned by other lanes under concurrent edit this session and is
# off-limits to depend on here. Instead, leadv2-fleet-runner.sh (this same
# deliverable) writes a `.fleet-terminal` marker file into a lane worktree
# the moment its own lane command returns a terminal rc; this guard only
# reaps worktrees carrying that marker. This keeps the fleet runtime
# self-contained and decoupled from the registry's internal shape.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=leadv2-fleet-lib.sh
. "${SCRIPT_DIR}/leadv2-fleet-lib.sh"
STATE_BIN="${LEADV2_FLEET_STATE_BIN:-${SCRIPT_DIR}/leadv2-fleet-state.sh}"

REPO=""
NAME=""
FLOOR_KB="${FLEET_DISK_FLOOR_KB_DEFAULT}"
STALL_MINUTES="${LEADV2_FLEET_STALL_MINUTES:-60}"

usage() {
  cat <<'EOF'
usage: leadv2-fleet-guard.sh --repo <path> --name <instance> [--floor-kb N] [--stall-minutes N]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --floor-kb) FLOOR_KB="$2"; shift 2 ;;
    --stall-minutes) STALL_MINUTES="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "leadv2-fleet-guard.sh: unknown arg $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "${REPO}" && -n "${NAME}" ]] || { usage; exit 2; }

WORKTREE_ROOT="${REPO}/.claude/worktrees"
STALL_LOG="${FLEET_STATE_ROOT}/${NAME}.stalled.log"
mkdir -p "${FLEET_STATE_ROOT}"
reaped=0
stalled=0

# 1. Reap terminal-marked lane worktrees. `git worktree remove --force`
#    refuses on a locked/submodule-carrying tree; round-1 fell back to
#    `rm -rf` on refusal, which can destroy an in-flight lane's uncommitted
#    work and leaves a dangling `.git/worktrees` entry — the mission's own
#    "a half-merged lane is worse than a running one" rule. Round-2 fix
#    (H4): on refusal, record `reap_refused` and leave the tree untouched;
#    a human/next pass decides, this script never deletes on a refusal.
if [[ -d "${WORKTREE_ROOT}" ]]; then
  for wt in "${WORKTREE_ROOT}"/*/; do
    [[ -d "${wt}" ]] || continue
    if [[ -f "${wt}.fleet-terminal" ]]; then
      wt_trim="${wt%/}"
      if git -C "${REPO}" worktree remove --force "${wt_trim}" >/dev/null 2>&1; then
        reaped=$((reaped + 1))
        printf '[fleet-guard] reaped terminal worktree %s\n' "${wt_trim}"
      else
        printf '%s reap_refused worktree=%s\n' "$(fleet_now_iso)" "${wt_trim}" >> "${STALL_LOG}"
        printf '[fleet-guard] reap_refused: git worktree remove refused for %s (left in place, not force-deleted)\n' "${wt_trim}" >&2
      fi
    fi
  done
fi

# 2. Disk floor — self-stop with a named reason.
if ! floor_reason="$(fleet_disk_floor_ok "${REPO}" "${FLOOR_KB}")"; then
  "${STATE_BIN}" set-status --name "${NAME}" --status stopped --reason "disk_floor: ${floor_reason}" >/dev/null
  printf '[fleet-guard] self-stop disk_floor: %s\n' "${floor_reason}"
fi

# 3. Stalled-lane detection (round-2 fix M6): the worktree ROOT directory's
#    own mtime only — round 1 walked every file under every worktree with
#    `find -type f` each pass, which is O(files) on every timer tick for no
#    added precision the founder surface uses. A directory's mtime already
#    advances on any direct create/rename/delete under it; that is enough
#    signal for "untouched for N minutes".
if [[ -d "${WORKTREE_ROOT}" ]]; then
  now="$(fleet_now_epoch)"
  for wt in "${WORKTREE_ROOT}"/*/; do
    [[ -d "${wt}" ]] || continue
    wt_trim="${wt%/}"
    newest="$(fleet_mtime_epoch "${wt_trim}")"
    [[ -n "${newest}" && "${newest}" -gt 0 ]] || continue
    age_min=$(( (now - newest) / 60 ))
    if [[ "${age_min}" -ge "${STALL_MINUTES}" ]]; then
      stalled=$((stalled + 1))
      printf '%s stalled worktree=%s age_min=%s\n' "$(fleet_now_iso)" "${wt_trim}" "${age_min}" >> "${STALL_LOG}"
      printf '[fleet-guard] stalled lane recorded: %s (age_min=%s)\n' "${wt_trim}" "${age_min}"
    fi
  done
fi

"${STATE_BIN}" set-field --name "${NAME}" --field stalled --value "${stalled}" >/dev/null
printf '[fleet-guard] pass complete reaped=%s stalled=%s\n' "${reaped}" "${stalled}"
