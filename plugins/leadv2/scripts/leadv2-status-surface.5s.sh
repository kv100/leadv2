#!/usr/bin/env bash
# leadv2-status-surface.5s.sh — SWIFTBAR-FAST-NAMES-01
#
# SwiftBar / xbar menu-bar widget for leadv2-status-surface.sh. The `.5s.sh`
# filename convention tells SwiftBar/xbar to refresh every 5 seconds — so the
# supervisor state is always on screen, in the menu bar, regardless of which
# terminal (if any) is open.
#
# SWIFTBAR-FAST-NAMES-01 (2026-08-04): the renderer's `--all` payload costs
# ~4 s wall (GLM live quota, codex lockout probe, ledger scans). A 5 s cadence
# is shorter than one refresh, so the widget NEVER calls the renderer on its
# render path. Instead:
#   - RENDER PATH (every 5 s tick): reads two cache files — all.payload (the
#     last good `--all` stdout) and labels.map (sig8→human-label). Its only
#     I/O is those two reads. It kicks a DETACHED refresher when the payload
#     is older than TTL; it never waits. Zero spinners, zero «обновляется…».
#   - REFRESHER (detached, ≤1 live at a time via a mkdir lock): runs
#     `bash $RENDERER --all`, promotes the result only on rc=0 + non-empty
#     (a failed refresh keeps the last good payload and grows its age — the
#     widget degrades to "stale" honestly instead of a false zero), then
#     rebuilds labels.map.
# Freshness is mtime(all.payload); a payload older than 600 s flips the title
# to `⚠️ кэш устарел` — a 10-minute-old value rendered as a confident 🛠/⚪ is
# the lying-green shape this surface exists to kill.
#
# Human lane names: the renderer's section 6 emits an 8-hex sig8 for any lane
# with no reservation row (e.g. this very architect lane). The refresher
# resolves every section-6 sig8 → a human label via resolve_lane_label()
# (ledger lane_label > active.yaml worktree match > mission heading > sig8)
# and stores it in labels.map. The render path maps the title token and each
# worker row through it; the raw sig8 survives only in a demoted `sig …` line.
#
# LEADV2_STATUS_SYNC=1 escape hatch: bypass the cache and call the renderer
# synchronously (the pre-FAST-NAMES behaviour). SwiftBar never sets it, so prod
# always runs the cached path; it exists so the fixture test suite (which drives
# the widget once per assertion and expects a synchronous title) keeps working
# unchanged, and so an operator can force a one-shot live render from a shell.
#
# COPY-REPLY SAFETY: a question's option row copies the reply command to the
# clipboard only — it NEVER invokes leadv2-reply-router.sh. A stray menu click
# cannot answer a founder question irreversibly. The copy is done by
# re-invoking THIS script as `--copy-reply <qid> <opt>` (a self-contained
# helper mode, no new file); SwiftBar params are space-free tokens so the
# command is never split.
#
# SOURCEABLE: resolve_lane_label() and its helpers are defined before the main
# guard so a test can `source` this file and call the resolver directly. The
# executable body is guarded by `BASH_SOURCE[0] = $0`.
#
# INSTALL (manual — by design, no auto-install into the plugin dir):
#   ln -s "<repo>/plugins/leadv2/scripts/leadv2-status-surface.5s.sh" \
#         "<SwiftBar Plugins>/leadv2-status-surface.5s.sh"
#   A symlink is required (not a copy): a copy drifts the moment the script is
#   updated — the same lying-stale disease this surface exists to kill.
#
# POSIX [ ] only; no double-bracket tests (eval-adjacent glob hazard), no
# ${var^^} (bash 3.2 on macOS has neither). printf '%s'-style only — never
# printf "$var" (question text / lane labels are LLM/prose-authored and may
# contain %/|).

set -uo pipefail

# ════════════════════════════════════════════════════════════════════════════
# SOURCEABLE HELPERS — sig8 → human-label resolution (off the render path)
# ════════════════════════════════════════════════════════════════════════════
# Mirror the renderer's path conventions so a sandboxed env (tests) and prod
# resolve against the same stores:
#   LEADV2_STATUS_LEDGER_DIR   default ~/.claude/cache/dispatch-ledger   (per-repo *.jsonl)
#   LEADV2_STATUS_ACTIVE_YAML  default discovered (leadv2-state + project roots)
#   LEADV2_STATUS_HANDOFF_DIR  default discovered over ~/Projects/*/docs/handoff

# _try_mission <handoff_root> <sig8> — first heading line of the lane's mission
_try_mission() {
  _tm_root="$1" _tm_sig="$2" _tm_out=""
  for _tm_p in "$_tm_root"/dispatch-"$_tm_sig"/mission.md \
               "$_tm_root"/dispatch-"$_tm_sig"/architect-prepass.md \
               "$_tm_root"/"$_tm_sig"*/mission.md; do
    [ -f "$_tm_p" ] || continue
    _tm_line="$(head -1 "$_tm_p" 2>/dev/null)"
    _tm_line="$(printf '%s' "$_tm_line" | sed 's/^#[[:space:]]*//')"  # strip leading '#'
    if [ -n "$_tm_line" ]; then _tm_out="$_tm_line"; break; fi
  done
  printf '%s' "$_tm_out"
}

# _mission_heading <sig8> — explicit handoff dir, else discover over project roots
_mission_heading() {
  _mh_sig="$1" _mh_out=""
  _mh_hd="${LEADV2_STATUS_HANDOFF_DIR:-}"
  if [ -n "$_mh_hd" ] && [ -d "$_mh_hd" ]; then
    _mh_out="$(_try_mission "$_mh_hd" "$_mh_sig")"
  fi
  if [ -z "$_mh_out" ]; then
    for _mh_root in "$HOME"/Projects/*/docs/handoff \
                    "$HOME"/Projects/*/.claude/worktrees/*/docs/handoff; do
      [ -d "$_mh_root" ] || continue
      _mh_out="$(_try_mission "$_mh_root" "$_mh_sig")"
      [ -n "$_mh_out" ] && break
    done
  fi
  printf '%s' "$_mh_out"
}

# _active_yaml_scan <sig8> — task_id of the session whose worktree carries the
# sig8. Pairs task_id/worktree fields in document order (flow + block style);
# python3 optional (absent → skip this fallback). Best-effort fallback #2 of 4.
_active_yaml_scan() {
  _as_sig="$1" _as_files=""
  _as_explicit="${LEADV2_STATUS_ACTIVE_YAML:-}"
  if [ -n "$_as_explicit" ] && [ -f "$_as_explicit" ]; then
    _as_files="$_as_explicit"
  fi
  if [ -z "$_as_files" ]; then
    for _as_f in "$HOME"/.claude/leadv2-state/*/active.yaml \
                 "$HOME"/Projects/*/docs/leadv2/active.yaml; do
      [ -f "$_as_f" ] && _as_files="${_as_files}${_as_files:+ }$_as_f"
    done
  fi
  [ -n "$_as_files" ] || { printf ''; return; }
  command -v python3 >/dev/null 2>&1 || { printf ''; return; }
  AS_FILES="$_as_files" AS_SIG="$_as_sig" python3 2>/dev/null <<'PYEOF'
import os, re
sig = os.environ.get("AS_SIG", "")
out = ""
for f in os.environ.get("AS_FILES", "").split():
    try:
        txt = open(f, encoding="utf-8", errors="replace").read()
    except Exception:
        continue
    if sig not in txt:
        continue
    tids = [a or b for a, b in re.findall(r'task_id:\s*"([^"]*)"|task_id:\s*([^\s,}]+)', txt)]
    wts  = [a or b for a, b in re.findall(r'worktree:\s*"([^"]*)"|worktree:\s*([^\s,}]+)', txt)]
    for i, w in enumerate(wts):
        if sig in w and i < len(tids) and tids[i]:
            out = tids[i]; break
    if out:
        break
print(out.strip()[:40])
PYEOF
}

# resolve_lane_label <sig8> — the resolver. Prints the label (no trailing NL).
# Chain: 1) ledger lane_label>task_id>founder_task_id  2) active.yaml worktree
# match  3) mission heading  4) miss → sig8. Result is '|' stripped and clipped
# to 40 chars (renderer rule 3: lane_label rendered verbatim, never tasks.yaml
# looked-up, clipped at 40).
resolve_lane_label() {
  [ -n "${1:-}" ] || { printf ''; return; }
  _rl_sig="$1"
  _rl_label=""

  # 1. reservation / terminal ledger — scan every repo's *.jsonl (section 6
  #    mixes repos). task_sig is full 64-hex; sig8 is its first 8 chars.
  _rl_ld="${LEADV2_STATUS_LEDGER_DIR:-$HOME/.claude/cache/dispatch-ledger}"
  if [ -d "$_rl_ld" ]; then
    _rl_row="$(grep -h "\"task_sig\":\"${_rl_sig}" "$_rl_ld"/*.jsonl 2>/dev/null | tail -1)"
    if [ -n "$_rl_row" ]; then
      _rl_label="$(printf '%s' "$_rl_row" | sed -n 's/.*"lane_label":"\([^"]*\)".*/\1/p')"
      [ -z "$_rl_label" ] && _rl_label="$(printf '%s' "$_rl_row" | sed -n 's/.*"task_id":"\([^"]*\)".*/\1/p')"
      [ -z "$_rl_label" ] && _rl_label="$(printf '%s' "$_rl_row" | sed -n 's/.*"founder_task_id":"\([^"]*\)".*/\1/p')"
    fi
  fi

  # 2. active.yaml — session whose worktree contains the sig8
  [ -z "$_rl_label" ] && _rl_label="$(_active_yaml_scan "$_rl_sig")"

  # 3. mission heading (dispatch-<sig8>/mission.md H1)
  [ -z "$_rl_label" ] && _rl_label="$(_mission_heading "$_rl_sig")"

  # 4. miss → sig8 (covers bbbbbbbb test junk)
  [ -z "$_rl_label" ] && _rl_label="$_rl_sig"

  _rl_label="$(printf '%s' "$_rl_label" | tr -d '|' | cut -c1-40)"
  printf '%s' "$_rl_label"
}

# _is_sig8 <token> — true iff exactly 8 lowercase hex chars. POSIX case glob.
_is_sig8() {
  case "$1" in
    [a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]) return 0 ;;
    *) return 1 ;;
  esac
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN — only when executed, not sourced
# ════════════════════════════════════════════════════════════════════════════
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then

# ── --copy-reply helper mode (checked FIRST) ────────────────────────────────
if [ "${1:-}" = "--copy-reply" ]; then
  _cr_qid="${2:-}"; _cr_opt="${3:-}"
  if [ -n "$_cr_qid" ] && [ -n "$_cr_opt" ]; then
    printf 'leadv2-reply-router.sh %s %s' "$_cr_qid" "$_cr_opt" | pbcopy 2>/dev/null || true
  fi
  exit 0
fi

# ── resolve own dir through a symlink ───────────────────────────────────────
_self="${BASH_SOURCE[0]:-$0}"
_resolve() {
  local p="$1" dir
  while [ -L "$p" ]; do
    dir="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in
      /*) ;;
      *)  p="${dir}/${p}" ;;
    esac
  done
  cd "$(dirname "$p")" 2>/dev/null && pwd -P
}
SCRIPT_DIR="$(_resolve "$_self")"
RENDERER="${LEADV2_STATUS_RENDERER:-${SCRIPT_DIR}/leadv2-status-surface.sh}"
# SELF_PATH derived from $_self, NOT hardcoded — the rename (.10s→.5s) and any
# future rename would otherwise silently break every copy-reply row (R2).
SELF_PATH="${SCRIPT_DIR}/$(basename "${_self}")"

# ── cache layout (~/.claude/cache/status-surface/) ─────────────────────────
CACHE_DIR="${LEADV2_STATUS_CACHE_DIR:-${HOME}/.claude/cache/status-surface}"
PAYLOAD="${CACHE_DIR}/all.payload"
LABELS="${CACHE_DIR}/labels.map"
LOCKDIR="${CACHE_DIR}/refresh.lock"
ERRFILE="${CACHE_DIR}/refresh.err"
TTL="${LEADV2_STATUS_CACHE_TTL:-8}"
[ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR" 2>/dev/null || true

CACHED=1
[ "${LEADV2_STATUS_SYNC:-0}" = "1" ] && CACHED=0
OUT_ALL=""
PAYLOAD_AGE=0
_AGE_SUFFIX=""
_TITLE_OVERRIDE=""

# ── age suffix / stale override (cached mode only) ─────────────────────────
_age_short() {  # <seconds> -> "12s" | "3m" | "2h"
  if [ "$1" -lt 60 ]; then printf '%ds' "$1"
  elif [ "$1" -lt 3600 ]; then printf '%dm' $(( $1 / 60 ))
  else printf '%dh' $(( $1 / 3600 )); fi
}
_compute_age_suffix() {
  _AGE_SUFFIX=""; _TITLE_OVERRIDE=""
  [ "$CACHED" -eq 1 ] || return
  if [ "$PAYLOAD_AGE" -ge 600 ]; then
    _TITLE_OVERRIDE="$(printf '⚠️ кэш устарел (%s)' "$(_age_short "$PAYLOAD_AGE")")"
    return
  fi
  [ "$PAYLOAD_AGE" -gt 6 ] && _AGE_SUFFIX="$(printf ' (%s)' "$(_age_short "$PAYLOAD_AGE")")"
}
_emit_title() {  # <title>
  if [ -n "$_TITLE_OVERRIDE" ]; then printf '%s\n' "$_TITLE_OVERRIDE"
  else printf '%s%s\n' "$1" "$_AGE_SUFFIX"; fi
}

# ── label lookup on the render path: labels.map grep, else resolver ─────────
_lookup_label() {  # <token> -> label (sig8 resolved, else verbatim)
  if _is_sig8 "$1"; then
    if [ -f "$LABELS" ]; then
      _ll="$(awk -F'\t' -v k="$1" '$1==k {print $2; exit}' "$LABELS" 2>/dev/null)"
      if [ -n "$_ll" ]; then printf '%s' "$_ll"; return; fi
    fi
    printf '%s' "$(resolve_lane_label "$1")"
  else
    printf '%s' "$1"
  fi
}

# ── refresher: detached, mkdir-guarded, promotes only rc=0 + non-empty ──────
_kick_refresh() {
  if ! mkdir "$LOCKDIR" 2>/dev/null; then
    _lk_age=$(( $(date +%s) - $(stat -f %m "$LOCKDIR" 2>/dev/null || echo 0) ))
    if [ "${_lk_age:-0}" -gt 90 ] 2>/dev/null; then
      rmdir "$LOCKDIR" 2>/dev/null && mkdir "$LOCKDIR" 2>/dev/null || return
    else
      return
    fi
  fi
  (
    _tmp="${PAYLOAD}.tmp.$$"
    bash "$RENDERER" --all >"$_tmp" 2>"$ERRFILE"
    _rc=$?
    if [ "$_rc" -eq 0 ] && [ -s "$_tmp" ]; then
      mv "$_tmp" "$PAYLOAD"
      _build_labels_map
    else
      printf 'rc=%s\n' "$_rc" > "$ERRFILE"
      rm -f "$_tmp"
    fi
    rmdir "$LOCKDIR" 2>/dev/null
  ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# ── labels.map build — runs ONLY inside the refresher, never on render path ─
# Resolve every section-6 sig8 (header field 4 + each detail line field 1).
# Tokens that already resolved to a human name (not 8-hex) are skipped.
_build_labels_map() {
  _bl_tmp="${LABELS}.tmp.$$"
  _bl_s6="$(cat "$PAYLOAD" 2>/dev/null | awk 'BEGIN{c=1} $0=="---"{c++; next} c==6{print}')"
  {
    printf '%s\n' "$_bl_s6" | sed -n '1p' | awk '{print $4}'
    printf '%s\n' "$_bl_s6" | sed -n '2,$p' | sed 's/^[[:space:]]*//' | awk 'NF{print $1}'
  } 2>/dev/null | sort -u | while IFS= read -r _bl_tok; do
    [ -n "$_bl_tok" ] || continue
    if _is_sig8 "$_bl_tok"; then
      printf '%s\t%s\n' "$_bl_tok" "$(resolve_lane_label "$_bl_tok")"
    fi
  done > "$_bl_tmp"
  mv "$_bl_tmp" "$LABELS" 2>/dev/null || rm -f "$_bl_tmp"
}

# ════════════════════════════════════════════════════════════════════════════
# RENDER PATH
# ════════════════════════════════════════════════════════════════════════════
if [ "$CACHED" -eq 0 ]; then
  # ── SYNC escape hatch: synchronous renderer call (tests / one-shot live) ──
  if [ ! -f "$RENDERER" ]; then
    printf '⚠️ leadv2 status\n'; printf -- '---\n'
    printf 'renderer missing (looked for: %s) | font=Menlo size=12\n' "$RENDERER"
    printf 'Refresh | refresh=true\n'; exit 0
  fi
  _ss_err="$(mktemp -t leadv2-ss-err)"
  OUT_ALL="$(bash "$RENDERER" --all 2>"$_ss_err")"
  _ss_rc=$?
  if [ "$_ss_rc" -ne 0 ] || [ -z "$OUT_ALL" ]; then
    _ss_msg="$(head -1 "$_ss_err" 2>/dev/null)"
    [ -z "$_ss_msg" ] && _ss_msg="renderer exited $_ss_rc with no output"
    _ss_msg="$(printf '%s' "$_ss_msg" | cut -c1-120)"
    printf '⚠️ renderer failed\n'; printf -- '---\n'
    printf 'rc=%s | %s | font=Menlo size=12\n' "$_ss_rc" "$_ss_msg"
    printf 'renderer: %s | font=Menlo size=12\n' "$RENDERER"
    printf -- '---\n'; printf 'Refresh | refresh=true\n'
    rm -f "$_ss_err"; exit 0
  fi
  rm -f "$_ss_err"
  PAYLOAD_AGE=0
else
  # ── CACHED path: read two files, never call the renderer ──────────────────
  if [ ! -f "$PAYLOAD" ]; then
    printf '⏳ leadv2 (нет кэша)\n'; printf -- '---\n'
    printf 'первый сбор… | font=Menlo size=12\n'
    printf 'Refresh | refresh=true\n'
    _kick_refresh
    exit 0
  fi
  OUT_ALL="$(cat "$PAYLOAD" 2>/dev/null)"
  PAYLOAD_AGE=$(( $(date +%s) - $(stat -f %m "$PAYLOAD" 2>/dev/null || echo 0) ))
  if [ "$PAYLOAD_AGE" -gt "$TTL" ] && [ ! -d "$LOCKDIR" ]; then
    _kick_refresh
  fi
fi

# ── section splitter (sections separated by '---'; 1=lanes 2=questions
#    3=limits 4=due 5=alarms 6=single-lead 7=repo-facts) ────────────────────
_sec() {
  printf '%s\n' "$OUT_ALL" | awk -v want="$1" 'BEGIN{c=1} $0=="---"{c++; next} {if(c==want) print}'
}
LANES_BLOCK="$(_sec 1)"
Q_BLOCK="$(_sec 2)"
LIM_BLOCK="$(_sec 3)"
DUE_BLOCK="$(_sec 4)"
ALM_BLOCK="$(_sec 5)"
SINGLE_LEAD_BLOCK="$(_sec 6)"
REPO_FACTS_BLOCK="$(_sec 7)"

# ── parse the lanes block (section 1) — supervisor on/off + live/dead ───────
hdr="$(printf '%s\n' "$LANES_BLOCK" | sed -n '1p')"
case "$hdr" in
  supervisor:*ON*) SUP_ON=1 ;;
  *)               SUP_ON=0 ;;
esac
lane_line="$(printf '%s\n' "$LANES_BLOCK" | sed -n '2p')"
LANES_BROKEN=0
case "$lane_line" in *⚠*) LANES_BROKEN=1 ;; esac
LIVE_N=0; DEAD_N=0; DONE_N=0; _hdr_parse_ok=1
LIVE_N="$(printf '%s' "$lane_line" | sed -n 's/.*[^0-9]\([0-9][0-9]*\) live.*/\1/p')"
DEAD_N="$(printf '%s' "$lane_line" | sed -n 's/.*[^0-9]\([0-9][0-9]*\) dead.*/\1/p')"
DONE_N="$(printf '%s' "$lane_line" | sed -n 's/.*[^0-9]\([0-9][0-9]*\) done.*/\1/p')"
case "$LIVE_N" in ''|*[!0-9]*) LIVE_N=0; _hdr_parse_ok=0 ;; esac
case "$DEAD_N" in ''|*[!0-9]*) DEAD_N=0; _hdr_parse_ok=0 ;; esac
case "$DONE_N" in ''|*[!0-9]*) DONE_N=0; _hdr_parse_ok=0 ;; esac
if [ "$_hdr_parse_ok" -eq 0 ] && [ "$LANES_BROKEN" -eq 0 ]; then LANES_BROKEN=1; fi

# ── parse the questions block (section 2) ───────────────────────────────────
Q_N=0
_q_hdr="$(printf '%s\n' "$Q_BLOCK" | sed -n '1p')"
Q_N="$(printf '%s' "$_q_hdr" | sed -n 's/^questions (\([0-9]*\)).*/\1/p')"
case "$Q_N" in ''|*[!0-9]*) Q_N=0 ;; esac

# mode from the renderer (never re-derived from SUP_ON)
_sl_hdr="$(printf '%s\n' "$SINGLE_LEAD_BLOCK" | sed -n '1p')"
case "$_sl_hdr" in mode=single-lead*) WIDGET_SINGLE_LEAD=1 ;; *) WIDGET_SINGLE_LEAD=0 ;; esac

_compute_age_suffix

# ════════════════════════════════════════════════════════════════════════════
# SINGLE-LEAD MODE — title (priority ⚠ > ❓ > 🔴 > 🛠 > ⚪) + dropdown
# ════════════════════════════════════════════════════════════════════════════
if [ "$WIDGET_SINGLE_LEAD" -eq 1 ]; then
  _sl_warning=0
  case "$_sl_hdr" in *"active ⚠"*) _sl_warning=1 ;; esac
  _rf_corrupt=0
  case "$REPO_FACTS_BLOCK" in *"⚠ snapshot corrupt"*) _rf_corrupt=1 ;; esac
  _rf_alarms="$(LEADV2_RF_BLOCK="$REPO_FACTS_BLOCK" python3 2>/dev/null <<'PYEOF'
import json, os
n = 0
for line in os.environ.get("LEADV2_RF_BLOCK", "").splitlines():
    key, sep, raw = line.partition(": ")
    if sep and key.endswith("_alarm"):
        try: value = json.loads(raw)
        except Exception: continue
        if value: n += 1
print(n)
PYEOF
)"
  case "$_rf_alarms" in ''|*[!0-9]*) _rf_alarms=0 ;; esac
  _sl_count=0; _sl_tid=""; _sl_arm=""; _sl_age=""
  case "$_sl_hdr" in
    "mode=single-lead active "*" "*" "*" "*)
      _sl_count="$(printf '%s' "$_sl_hdr" | awk '{print $3}')"
      _sl_tid="$(printf '%s' "$_sl_hdr" | awk '{print $4}')"
      _sl_arm="$(printf '%s' "$_sl_hdr" | awk '{print $5}')"
      _sl_age="$(printf '%s' "$_sl_hdr" | awk '{print $6}')"
      ;;
    "mode=single-lead active "*" "*" "*)
      _sl_count="$(printf '%s' "$_sl_hdr" | awk '{print $3}')"
      _sl_tid="$(printf '%s' "$_sl_hdr" | awk '{print $4}')"
      _sl_arm="$(printf '%s' "$_sl_hdr" | awk '{print $5}')"
      _sl_age="?"
      ;;
    "mode=single-lead active "*)
      _sl_count=0
      ;;
  esac
  case "$_sl_count" in ''|*[!0-9]*) _sl_count=0 ;; esac

  if [ "$_sl_warning" -eq 1 ] || [ "$_rf_corrupt" -eq 1 ]; then
    if [ "$_rf_corrupt" -eq 1 ]; then _title="⚠️ snapshot не прочитан"; else _title="⚠️ ledger не прочитан"; fi
  elif [ "$Q_N" -gt 0 ]; then
    _title="$(printf '❓%d' "$Q_N")"
  elif [ "$_rf_alarms" -gt 0 ]; then
    _title="$(printf '🔴 %d' "$_rf_alarms")"
  elif [ "$_sl_count" -eq 1 ]; then
    _title="$(printf '🛠 %s %s %s' "$(_lookup_label "$_sl_tid")" "$_sl_arm" "$_sl_age")"
  elif [ "$_sl_count" -gt 1 ]; then
    _title="$(printf '🛠 %d: %s %s %s' "$_sl_count" "$(_lookup_label "$_sl_tid")" "$_sl_arm" "$_sl_age")"
  else
    _title="⚪ idle"
  fi
  _emit_title "$_title"

  printf -- '---\n'
  # CACHED mode: reformat detail rows to "<label> · <arm> · <age>" and demote
  # the raw sig8 to a `sig …` line (the founder's ask). SYNC mode: keep the
  # renderer's verbatim line so the fixture suite's `active`/`closing` greps
  # stay byte-compatible.
  if [ "$CACHED" -eq 1 ]; then
    printf '%s\n' "$SINGLE_LEAD_BLOCK" | sed -n '2,$p' | while IFS= read -r _sline; do
      _s_trim="$(printf '%s' "$_sline" | sed 's/^[[:space:]]*//')"
      [ -n "$_s_trim" ] || continue
      _s_id="$(printf '%s' "$_s_trim" | awk '{print $1}')"
      _s_arm="$(printf '%s' "$_s_trim" | awk '{print $2}')"
      _s_age="$(printf '%s' "$_s_trim" | awk '{print $3}')"
      _s_label="$(_lookup_label "$_s_id")"
      printf '%s · %s · %s | font=Menlo size=12\n' "$_s_label" "$_s_arm" "$_s_age"
      if _is_sig8 "$_s_id"; then
        printf '  sig %s | font=Menlo size=12\n' "$_s_id"
      fi
    done
  else
    printf '%s\n' "$SINGLE_LEAD_BLOCK" | while IFS= read -r _sline; do
      printf '%s | font=Menlo size=12\n' "$_sline"
    done
  fi
  printf -- '---\n'
  if [ -n "$REPO_FACTS_BLOCK" ]; then
    printf '%s\n' "$REPO_FACTS_BLOCK" | while IFS= read -r ln; do printf '%s | font=Menlo size=12\n' "$ln"; done
    printf -- '---\n'
  fi
  if [ -n "$DUE_BLOCK" ]; then printf '%s | font=Menlo size=12\n' "$DUE_BLOCK"; printf -- '---\n'; fi
  if [ -n "$LIM_BLOCK" ]; then
    printf '%s\n' "$LIM_BLOCK" | while IFS= read -r ln; do printf '%s | font=Menlo size=12\n' "$ln"; done
    printf -- '---\n'
  fi
  if [ "$Q_N" -gt 0 ]; then
    printf '%s\n' "$Q_BLOCK" | while IFS= read -r qln; do printf '%s | font=Menlo size=12\n' "$(printf '%s' "$qln" | tr -d '|')"; done
    printf -- '---\n'
  fi
  if [ -n "$ALM_BLOCK" ]; then printf '%s | font=Menlo size=12\n' "$ALM_BLOCK"; printf -- '---\n'; fi
  printf 'Refresh | refresh=true\n'
  exit 0
fi

# ════════════════════════════════════════════════════════════════════════════
# LEGACY / SUPERVISOR MODE — title (priority ⚠ > ❓ > 🔴 > 🟢 > ⚪) + dropdown
# ════════════════════════════════════════════════════════════════════════════
_prefix=""
if [ "$SUP_ON" -eq 0 ] && [ "$Q_N" -eq 0 ]; then _prefix="⚪ sup OFF · "; fi
if [ "$LANES_BROKEN" -eq 1 ]; then
  _title="$(printf '%s⚠️ lanes не прочитаны' "$_prefix")"
  [ "$Q_N" -gt 0 ] && _title="${_title} · ❓${Q_N}"
elif [ "$Q_N" -gt 0 ]; then
  _title="$(printf '%s❓%d · 🟢 %d / 🔴 %d' "$_prefix" "$Q_N" "$LIVE_N" "$DEAD_N")"
elif [ "$DEAD_N" -gt 0 ]; then
  _title="$(printf '%s🔴 %d / 🟢 %d' "$_prefix" "$DEAD_N" "$LIVE_N")"
elif [ "$LIVE_N" -gt 0 ]; then
  _title="$(printf '%s🟢 %d / 🔴 %d' "$_prefix" "$LIVE_N" "$DEAD_N")"
elif [ "$DONE_N" -gt 0 ]; then
  _title="$(printf '%s✅ %d' "$_prefix" "$DONE_N")"
else
  _title="$(printf '%s🟢 %d / 🔴 %d' "$_prefix" "$LIVE_N" "$DEAD_N")"
fi
_emit_title "$_title"

printf -- '---\n'

# questions: header + one row per pending question, with copy-reply sub-rows
if [ "$Q_N" -gt 0 ]; then
  _qi=0
  printf '%s\n' "$Q_BLOCK" | while IFS= read -r qln; do
    _qi=$(( _qi + 1 ))
    if [ "$_qi" -eq 1 ]; then
      printf '%s | font=Menlo size=12\n' "$qln"; continue
    fi
    _qid="$(printf '%s' "$qln" | awk '{print $1}')"
    _disp="$(printf '%s' "$qln" | sed -e 's/ *\[.*\] *$//' | tr -d '|')"
    printf '%s | font=Menlo size=12\n' "$_disp"
    _opts="$(printf '%s' "$qln" | sed -n 's/.*\[\(.*\)\].*/\1/p')"
    if [ -n "$_opts" ]; then
      printf '%s\n' "$_opts" | tr '|' '\n' | while IFS= read -r _o; do
        [ -z "$_o" ] && continue
        printf '  %s — copy reply | terminal=false refresh=false bash=%s param1=--copy-reply param2=%s param3=%s\n' \
          "$_o" "$SELF_PATH" "$_qid" "$_o"
      done
    fi
  done
  printf -- '---\n'
fi

# lanes table (monospaced)
printf '%s\n' "$LANES_BLOCK" | while IFS= read -r ln; do printf '%s | font=Menlo size=12\n' "$ln"; done
printf -- '---\n'

if [ -n "$LIM_BLOCK" ]; then
  printf '%s\n' "$LIM_BLOCK" | while IFS= read -r ln; do printf '%s | font=Menlo size=12\n' "$ln"; done
  printf -- '---\n'
fi
if [ -n "$DUE_BLOCK" ]; then printf '%s | font=Menlo size=12\n' "$DUE_BLOCK"; printf -- '---\n'; fi
if [ -n "$ALM_BLOCK" ]; then printf '%s | font=Menlo size=12\n' "$ALM_BLOCK"; printf -- '---\n'; fi
printf 'Refresh | refresh=true\n'

fi  # end main guard
