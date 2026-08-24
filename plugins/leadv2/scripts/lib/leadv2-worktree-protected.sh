#!/usr/bin/env bash
# lib/leadv2-worktree-protected.sh — SWEEPER-LANE-SAFETY-01 lane-protection gate.
#
# WHY THIS EXISTS (founder, 2026-08-24, «свипер починить на уровне плагина»):
# two same-day incidents. Lane b413968c was gutted to a lone docs/ dir by the
# merged-sweep hook's discard-then-remove ordering; lane 43ae4318 was deleted
# outright (worktree remove --force + branch -D) by --sweep-dead before its
# worker had committed anything. "Merged and clean" is NOT sufficient evidence
# a worktree is garbage: a lane worktree legitimately sits at base (ahead=0)
# both before its first commit and between fix rounds. This lib is the ONE
# inode both unattended sweepers consult (hooks/leadv2-merged-worktree-sweep.sh
# and leadv2-worktree-cleanup.sh --sweep-dead / --sweep-merged); _MW_ORCH_RE is
# this repo's cautionary tale about keeping one rule in two hand-edited files.
#
# Contract (design SWEEPER-LANE-SAFETY-01 §2). Sourceable; no side effects on
# source. Prime once per sweep pass, probe once per worktree:
#
#   lv2_wt_protect_prime <repo_root>
#       Reads active.yaml and the dispatch terminal ledger ONCE per pass (a
#       large registry or ledger is read once per sweep, never once per
#       worktree). Any failure — python3 absent, state-path resolver failed,
#       active.yaml missing/unreadable/malformed — puts the gate in a
#       fail-closed error state and EVERY later probe returns rc 5. A missing
#       registry is indistinguishable from a broken one; both protect.
#   lv2_worktree_protected <repo_root> <worktree_path>
#       rc 0  not protected — caller proceeds to its existing merged/dirty/
#             liveness gates
#       rc 1  active_yaml — lane id present in sessions[].task_id (bare or
#             dispatch-<id> form) or sessions[].worktree resolves to this
#             path, ANY state
#       rc 2  arm_open — docs/handoff/[dispatch-]<id>/arm-registered exists
#             (main repo or the worktree itself) and NO true terminal
#             (landed|dead) row for the id in the dispatch ledger
#       rc 3  live_pid — a registered pid for the id is alive
#       rc 4  young — worktree gitdir mtime younger than the age threshold
#             (default 48h; 0 disables ONLY this probe). The threshold accepts
#             LEADV2_SWEEP_MIN_AGE_S (seconds, preferred when numeric) or
#             LEADV2_SWEEP_MIN_AGE_H (hours, otherwise); both default to 48h.
#             The gitdir is creation-stamped by `git worktree add`; the mutable
#             worktree-directory mtime is a fallback only. This probe is the
#             ONLY protection during the window between `git worktree add` and
#             the active.yaml/arm-registered registration writes.
#       rc 5  read-error — fail closed: any probe that could not read its
#             input protects. On a broken control plane nothing is ever
#             removed.
#     Also sets LV2_WT_PROTECT_REASON for logging.
#
# Concurrency: active.yaml and the ledger are read once, read-only, WITHOUT
# taking the writers' locks (leadv2-portable-lock.sh / dispatch-ledger's own
# flock). A SessionStart gate blocking on a lane's write lock would be a worse
# failure than a stale directory; a torn read lands in rc 5, never rc 0.

LV2_WT_PROTECT_REASON=""
LV2_WT_PROTECT_ERR=""
LV2_WT_PROTECT_SESSIONS=""   # TSV lines: task_id \t worktree \t pid \t pid_alive(0|1)
LV2_WT_PROTECT_TERMINALS=""  # newline-separated ids with a TRUE terminal row
LV2_WT_PROTECT_MIN_AGE_S=$((48 * 3600))

# One pass over both control-plane files. Prints:
#   S \t task_id \t worktree \t pid \t pid_alive(0|1)   per active.yaml session
#   T \t <id>                                        per id with a TRUE terminal
# A missing ledger is not an error (no terminal row => an arm-registered lane
# counts as open — the correct direction); an unopenable active.yaml, a
# malformed YAML, or a missing yaml module exits 3 => caller fails closed.
_LV2_WT_PROTECT_PY='
import json, os, sys

active_path, ledger_path = sys.argv[1], sys.argv[2]
try:
    import yaml
except ImportError:
    sys.exit(3)

try:
    with open(active_path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
except OSError:
    sys.exit(3)
if not isinstance(data, dict):
    sys.exit(3)

for s in data.get("sessions") or []:
    if not isinstance(s, dict) or not s.get("task_id"):
        continue
    pid = s.get("pid")
    alive = 0
    if pid not in (None, "", "null", "None"):
        try:
            os.kill(int(pid), 0)
            alive = 1
        except (TypeError, ValueError, OSError):
            alive = 0
    print("S\t%s\t%s\t%s\t%d" % (s.get("task_id"), s.get("worktree") or "", pid or "", alive))

if ledger_path and os.path.isfile(ledger_path):
    try:
        fh = open(ledger_path, encoding="utf-8")
    except OSError:
        sys.exit(3)
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except ValueError:
                continue  # a non-JSON line is skipped, never kills the pass
            if not isinstance(row, dict):
                continue
            if str(row.get("terminal") or "") in ("landed", "dead"):
                for key in ("task_sig", "founder_task_id"):
                    val = str(row.get(key) or "")
                    if val:
                        print("T\t%s" % val)
'

lv2_wt_protect_prime() {
  local repo_root="$1" state_bin active_path ledger_path out v
  LV2_WT_PROTECT_ERR=""
  LV2_WT_PROTECT_SESSIONS=""
  LV2_WT_PROTECT_TERMINALS=""

  # LEADV2_SWEEP_MIN_AGE_S wins when it is numeric; otherwise accept the
  # established LEADV2_SWEEP_MIN_AGE_H value. Both empty/unset values default
  # to 48 hours. A malformed value emits ONE warning and never aborts a pass.
  if [[ -n "${LEADV2_SWEEP_MIN_AGE_S:-}" ]]; then
    v="$LEADV2_SWEEP_MIN_AGE_S"
    if [[ "$v" =~ ^[0-9]+$ ]] && (( v < 2147483648 )); then
      LV2_WT_PROTECT_MIN_AGE_S="$v"
    else
      printf '[leadv2-worktree-protected] LEADV2_SWEEP_MIN_AGE_S="%s" malformed — using LEADV2_SWEEP_MIN_AGE_H/default\n' "$v" >&2
      v="${LEADV2_SWEEP_MIN_AGE_H:-48}"
      if [[ "$v" =~ ^[0-9]+$ ]] && (( v < 2147483648 )); then
        LV2_WT_PROTECT_MIN_AGE_S=$((v * 3600))
      else
        LV2_WT_PROTECT_MIN_AGE_S=$((48 * 3600))
      fi
    fi
  else
    v="${LEADV2_SWEEP_MIN_AGE_H:-48}"
    if [[ "$v" =~ ^[0-9]+$ ]] && (( v < 2147483648 )); then
      LV2_WT_PROTECT_MIN_AGE_S=$((v * 3600))
    else
      LV2_WT_PROTECT_MIN_AGE_S=$((48 * 3600))
      printf '[leadv2-worktree-protected] LEADV2_SWEEP_MIN_AGE_H="%s" malformed — using default 48\n' "$v" >&2
    fi
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    LV2_WT_PROTECT_ERR="python3-absent"
    return 0
  fi

  state_bin="${BASH_SOURCE[0]:-$0}"; state_bin="${state_bin%/*}/../leadv2-state-path.sh"
  if [[ ! -f "$state_bin" ]]; then
    LV2_WT_PROTECT_ERR="state-path-resolver-absent"
    return 0
  fi

  active_path="$(PROJECT_ROOT="$repo_root" bash "$state_bin" --no-link active.yaml 2>/dev/null)" \
    || { LV2_WT_PROTECT_ERR="state-path-resolver-failed"; return 0; }
  if [[ -z "$active_path" || ! -f "$active_path" ]]; then
    LV2_WT_PROTECT_ERR="active-yaml-missing"
    return 0
  fi
  ledger_path="$(PROJECT_ROOT="$repo_root" bash "$state_bin" --no-link dispatch-ledger.jsonl 2>/dev/null)" \
    || ledger_path=""

  out="$(python3 -c "$_LV2_WT_PROTECT_PY" "$active_path" "$ledger_path" 2>/dev/null)" \
    || { LV2_WT_PROTECT_ERR="control-plane-unreadable"; return 0; }

  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      S$'\t'*) LV2_WT_PROTECT_SESSIONS+="${line#S$'\t'}"$'\n' ;;
      T$'\t'*) LV2_WT_PROTECT_TERMINALS+="${line#T$'\t'}"$'\n' ;;
    esac
  done <<< "$out"
  return 0
}

# 0 iff a session row is registered for this lane id / path. Probe A's key set.
_lv2_wt_session_row() { # <id> <wt-path>
  local id="$1" wt="$2" tid wpath pid alive wreal treal
  while IFS=$'\t' read -r tid wpath pid alive; do
    [[ -n "$tid" ]] || continue
    if [[ "$tid" == "$id" || "$tid" == "dispatch-$id" ]]; then
      return 0
    fi
    if [[ -n "$wpath" ]]; then
      if [[ "$wpath" == "$wt" ]]; then return 0; fi
      # Physical compare: git reports /private/var where we passed /var.
      wreal="$(realpath "$wpath" 2>/dev/null || printf '%s' "$wpath")"
      treal="$(realpath "$wt" 2>/dev/null || printf '%s' "$wt")"
      if [[ "$wreal" == "$treal" ]]; then return 0; fi
    fi
  done <<< "$LV2_WT_PROTECT_SESSIONS"
  return 1
}

# 0 iff a live pid is registered for this lane id. Probe C's key set (same as
# A's — a pid row implies a session row, so in practice rc 3 only refines rc 1;
# both are kept because the rc contract is the sweeper-facing interface).
_lv2_wt_pid_alive() { # <id>
  local id="$1" tid wpath pid alive
  while IFS=$'\t' read -r tid wpath pid alive; do
    [[ -n "$tid" ]] || continue
    if [[ "$tid" == "$id" || "$tid" == "dispatch-$id" ]] && [[ "$alive" == "1" ]]; then
      return 0
    fi
  done <<< "$LV2_WT_PROTECT_SESSIONS"
  return 1
}

# 0 iff a TRUE terminal (landed|dead — same two-word set as
# leadv2-dispatch-ledger.sh's dispatch_terminal_exists) is recorded for any
# id form: the bare id, dispatch-<id>, or the id with its dispatch- prefix
# stripped (the ledger keys rows by sig8; worktree basenames are the sig8 or
# the full task id depending on which regime created the lane).
_lv2_wt_terminal_recorded() { # <id>
  local id="$1" cand
  for cand in "$id" "dispatch-$id" "${id#dispatch-}"; do
    [[ -n "$cand" ]] || continue
    if printf '%s\n' "$LV2_WT_PROTECT_TERMINALS" | grep -Fxq -- "$cand"; then
      return 0
    fi
  done
  return 1
}

# Probe B. rc 0 = arm open (protect); rc 1 = no open arm; rc 2 = unreadable.
# PRESENCE is the signal — dispatch-code.sh writes arm-registered as a marker;
# its content is never parsed to decide protection. Checked in the main repo
# AND in the worktree itself (a lane mid-round has its own handoff tree).
_lv2_wt_arm_open() { # <repo-root> <wt-path> <id>
  local repo_root="$1" wt="$2" id="$3" base hd
  for base in "$repo_root" "$wt"; do
    for hd in "$base/docs/handoff/$id" "$base/docs/handoff/dispatch-$id"; do
      [[ -e "$hd/arm-registered" ]] || continue
      if [[ ! -r "$hd/arm-registered" ]]; then return 2; fi
      if ! _lv2_wt_terminal_recorded "$id"; then return 0; fi
    done
  done
  return 1
}

lv2_worktree_protected() { # <repo-root> <wt-path> -> rc 0-5
  local repo_root="$1" wt="$2" id mtime now arm_rc git_dir age_source
  LV2_WT_PROTECT_REASON=""
  if [[ -n "$LV2_WT_PROTECT_ERR" ]]; then
    LV2_WT_PROTECT_REASON="read-error:${LV2_WT_PROTECT_ERR}"
    return 5
  fi

  id="$(basename "$wt")"

  if _lv2_wt_session_row "$id" "$wt"; then
    LV2_WT_PROTECT_REASON="active_yaml"
    return 1
  fi

  _lv2_wt_arm_open "$repo_root" "$wt" "$id"; arm_rc=$?
  if [[ "$arm_rc" == "0" ]]; then
    LV2_WT_PROTECT_REASON="arm_open"
    return 2
  fi
  if [[ "$arm_rc" == "2" ]]; then
    LV2_WT_PROTECT_REASON="read-error:arm-registered-unreadable"
    return 5
  fi

  if _lv2_wt_pid_alive "$id"; then
    LV2_WT_PROTECT_REASON="live_pid"
    return 3
  fi

  if (( LV2_WT_PROTECT_MIN_AGE_S > 0 )); then
    git_dir="$(git -C "$wt" rev-parse --git-dir 2>/dev/null || printf '%s' '')"
    age_source="${git_dir:+$git_dir/gitdir}"
    if [[ -n "$age_source" && ! -f "$age_source" ]]; then age_source=""; fi
    if [[ -n "$age_source" ]]; then
      mtime="$(stat -f %m "$age_source" 2>/dev/null || stat -c %Y "$age_source" 2>/dev/null || printf '%s' '')"
    else
      mtime=""
    fi
    if [[ ! "$mtime" =~ ^[0-9]+$ ]]; then
      mtime="$(stat -f %m "$wt" 2>/dev/null || stat -c %Y "$wt" 2>/dev/null || printf '%s' '')"
    fi
    if [[ ! "$mtime" =~ ^[0-9]+$ ]]; then
      LV2_WT_PROTECT_REASON="read-error:worktree-stat-failed"
      return 5
    fi
    now="$(date +%s)"
    if (( now - mtime < LV2_WT_PROTECT_MIN_AGE_S )); then
      LV2_WT_PROTECT_REASON="young"
      return 4
    fi
  fi

  LV2_WT_PROTECT_REASON="not-protected"
  return 0
}
