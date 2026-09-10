#!/usr/bin/env bash
# leadv2-interactive-session-switch.sh — move a WALL-BOUND INTERACTIVE session
# onto a free account (lane 467462db0de5).  §3 (5ee952587fdf) covered
# dispatchable lanes; this is the interactive half the founder asked for on
# 2026-09-10 after an m3-market session sat on "Session limit reached ·
# Retrying in 50m · attempt 1/300" while a probe the same minute found two
# free accounts.
#
# Step-0 measured branch (BEFORE this code, per brief; artifacts in
# docs/handoff/w-interactive-session-switch/step0-keychain-run2.log +
# witness-burn.log): a live interactive claude does NOT re-read its keychain
# credential per request — a session started on account A, whose keychain
# entry was verifiably swapped to account B before a multi-minute turn,
# streamed that whole turn on A (B's windows stayed byte-flat at 0.0 while the
# same-size burn on B registers within 32s).  So an interactive session can
# NEVER be switched in place: switching is RESTART-WITH-RESUME.  This script
# is that restart, composed from the existing instruments — no second
# switcher:
#   * leadv2-interactive-limit-detect.sh decides "is this really a limit";
#   * leadv2-account-switch.sh is the ONLY switch: it picks the target, arms
#     the selector's own cooldown marker for the exhausted account, and
#     OBSERVES the next selection landing on the target (rc 5 otherwise);
#   * this script then transplants the session transcript into the target
#     slot's projects tree (byte-verified, never overwriting; when both slots
#     share one projects tree the transplant is already satisfied -- same
#     inode, said aloud, no copy) and emits the exact `claude --resume`
#     command that continues the conversation on the free account.
#
# Usage:
#   leadv2-interactive-session-switch.sh --transcript <session.jsonl>
#       [--config-dir <dir>] [--screen-text <string|@file>] [--handoff <dir>]
#       [--dry-run]
#
#   --transcript   path of the stuck session's <uuid>.jsonl (usually under
#                  <config-dir>/projects/<munged-cwd>/).
#   --config-dir   the stuck session's CLAUDE_CONFIG_DIR (default ~/.claude).
#   --screen-text  paste of what the operator sees; without it the account is
#                  probed live (see the detector's header for the
#                  limit-vs-network-error discriminator).
#   --handoff      dir for journals (or $LEADV2_HANDOFF_DIR).
#   --dry-run      decide everything, write nothing (no marker, no transplant).
#
# Exit codes:
#   0  switched + transcript transplanted + resume command emitted
#   3  REFUSED, loud -- not a limit (reason=not_limit | limit_unknown) or no
#      free account (reason=switch_refused, the account-switch refusal word
#      carried in detail=)
#   4  REFUSED, guard -- reason=current_not_in_registry, or an account-switch
#      guard refusal (registry_not_two_buckets / selector_refused) propagated
#   5  FAILED -- reason=switch_failed (switch_not_taken propagated) |
#      transcript_missing | transcript_not_session | transcript_no_cwd |
#      transplant_target_exists | transplant_failed
#
# Journal: <handoff>/interactive-switch.log — one line per decision, each
# refusal carrying its OWN reason word + detail= naming WHICH guard fired
# (the §3 round-2 lesson: two guards sharing one word is a defect).
#
# bash 3.2: indexed arrays only, no mapfile.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Test seam (the suite's LEADV2_TEST_*_BIN convention, tests/test-account-
# switch.sh:23): lets a fixture pin the limit verdict so the refusal-
# propagation case tests ITS guard without standing on a detector guard.
DETECTOR="${LEADV2_TEST_LIMIT_DETECT_BIN:-$SCRIPT_DIR/leadv2-interactive-limit-detect.sh}"
ACCOUNT_SWITCH="$SCRIPT_DIR/leadv2-account-switch.sh"
REGISTRY="${LEADV2_CLAUDE_PROFILES_FILE:-$HOME/.claude/state/leadv2/claude-profiles.tsv}"

usage() {
  printf 'usage: leadv2-interactive-session-switch.sh --transcript <f> [--config-dir <d>] [--screen-text <s|@f>] [--handoff <d>] [--dry-run]\n' >&2
  exit 3
}

TRANSCRIPT=""; CONFIG_DIR="$HOME/.claude"; SCREEN_TEXT=""; HANDOFF=""; DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --transcript)  [[ $# -ge 2 ]] || usage; TRANSCRIPT="$2"; shift 2 ;;
    --config-dir)  [[ $# -ge 2 ]] || usage; CONFIG_DIR="$2"; shift 2 ;;
    --screen-text) [[ $# -ge 2 ]] || usage; SCREEN_TEXT="$2"; shift 2 ;;
    --handoff)     [[ $# -ge 2 ]] || usage; HANDOFF="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=1; shift ;;
    *) usage ;;
  esac
done
[[ -n "$TRANSCRIPT" ]] || usage
[[ -z "$HANDOFF" && -n "${LEADV2_HANDOFF_DIR:-}" ]] && HANDOFF="$LEADV2_HANDOFF_DIR"
[[ -n "$HANDOFF" ]] || usage
[[ -r "$DETECTOR" && -r "$ACCOUNT_SWITCH" ]] || { echo "interactive-switch: FATAL detector/account-switch missing" >&2; exit 4; }
[[ -r "$REGISTRY" ]] || { echo "interactive-switch: FATAL registry unreadable: $REGISTRY" >&2; exit 4; }

JOURNAL="$HANDOFF/interactive-switch.log"
say()  { printf 'interactive-switch: %s\n' "$*"; }
journal() {
  mkdir -p "$HANDOFF" 2>/dev/null || true
  printf '%s [interactive-switch] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$JOURNAL" 2>/dev/null || true
}
refuse() { # <rc> <reason line for stdout> <journal line> -- loud, then stop
  say "$2"
  journal "$3"
  exit "$1"
}
ino_id() { # <file> -> dev:ino identity ('' when unstattable), BSD stat and GNU stat
  if [[ "$(uname -s)" == "Darwin" ]]; then stat -f '%d:%i' "$1" 2>/dev/null
  else stat -c '%d:%i' "$1" 2>/dev/null; fi
}

# ---------------------------------------------------------------------------
# Guard 1: the transcript must BE a session file (a <uuid>.jsonl with a
# parseable cwd) -- everything downstream keys off its stem and its project
# segment, and a resume command for a non-session file would be a lie.
if [[ ! -r "$TRANSCRIPT" ]]; then
  refuse 5 "REFUSED reason=transcript_missing -- $TRANSCRIPT is not a readable file" \
           "REFUSED reason=transcript_missing path=$TRANSCRIPT"
fi
SESSION_ID="$(basename "$TRANSCRIPT" .jsonl)"
if ! [[ "$SESSION_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  refuse 5 "REFUSED reason=transcript_not_session -- stem '$SESSION_ID' is not a session uuid; nothing to --resume" \
           "REFUSED reason=transcript_not_session stem=$SESSION_ID"
fi
PROJ_SEG="$(basename "$(dirname "$TRANSCRIPT")")"
# The last line of a COMPLETED session is a type=cost-state record that has no
# cwd structurally (2026-09-10 m3-market, live: 14255 of 19904 lines carried
# the real cwd, yet tail -n 1 saw none and the resume command said cd "-").
# Scan BACKWARDS in bounded chunks -- never loading the whole transcript --
# and let the first record carrying a non-empty string cwd win (a session does
# not change directory mid-run; if one ever did, its LAST value is the right
# one).  No cwd anywhere is a LOUD refusal, never a guessed directory: a quiet
# cd "-" sends the operator to the PREVIOUS directory, silently.
CWD="$(python3 -c '
import json, os, sys
path, chunk = sys.argv[1], 65536
with open(path, "rb") as f:
    f.seek(0, os.SEEK_END); pos = f.tell(); head = b""
    while pos > 0:
        step = min(chunk, pos); pos -= step
        f.seek(pos)
        lines = (f.read(step) + head).split(b"\n")
        head = lines[0]
        for ln in reversed(lines[1:]):
            s = ln.strip()
            if not s:
                continue
            try:
                d = json.loads(s)
            except Exception:
                continue
            if isinstance(d, dict):
                c = d.get("cwd")
                if isinstance(c, str) and c:
                    print(c); sys.exit(0)
    s = head.strip()
    try:
        d = json.loads(s) if s else None
    except Exception:
        d = None
    if isinstance(d, dict):
        c = d.get("cwd")
        if isinstance(c, str) and c:
            print(c); sys.exit(0)
sys.exit(1)
' "$TRANSCRIPT" 2>/dev/null || true)"
if [[ -z "$CWD" ]]; then
  refuse 5 "REFUSED reason=transcript_no_cwd -- no record in $SESSION_ID carries a cwd; a resume command with a guessed directory would be a quiet lie" \
           "REFUSED reason=transcript_no_cwd session=$SESSION_ID transcript=$TRANSCRIPT"
fi

# ---------------------------------------------------------------------------
# Guard 2: the detector.  Not a limit / cannot say -> LOUD refusal, the
# account is not touched (no marker, account-switch never invoked).  This is
# exactly the "ordinary network error" fixture: unknown is never a limit.
DET_ARGS=(--config-dir "$CONFIG_DIR" --journal "$JOURNAL")
[[ -n "$SCREEN_TEXT" ]] && DET_ARGS+=(--screen-text "$SCREEN_TEXT")
DET_OUT="$(bash "$DETECTOR" "${DET_ARGS[@]}" 2>&1)"; DET_RC=$?
say "detector: $DET_OUT"
case "$DET_RC" in
  0) ;;
  1) DET_WHY="$(printf '%s' "$DET_OUT" | sed -n 's/.*verdict=no_limit.*/detector_says_no_limit/p')"
     refuse 3 "REFUSED reason=not_limit -- the detector does not see an account wall ($DET_OUT); switching now would be yanking the account on a non-limit" \
              "REFUSED reason=not_limit detail=detector_no_limit detector=$DET_OUT" ;;
  2) DET_REASON="$(printf '%s' "$DET_OUT" | sed -n 's/.*reason=\([a-z_]*\).*/\1/p' | head -1)"
     refuse 3 "REFUSED reason=limit_unknown detail=${DET_REASON:-?} -- the probe cannot say this is a limit ($DET_OUT); an ordinary network error must never trigger a switch" \
              "REFUSED reason=limit_unknown detail=${DET_REASON:-unknown} detector=$DET_OUT" ;;
  *) refuse 4 "REFUSED reason=detector_fatal -- detector rc=$DET_RC ($DET_OUT)" \
              "REFUSED reason=detector_fatal detector_rc=$DET_RC" ;;
esac
CURRENT_LABEL="$(printf '%s' "$DET_OUT" | sed -n 's/.*label=\([a-z0-9][a-z0-9_-]*\).*/\1/p' | head -1)"

# ---------------------------------------------------------------------------
# Guard 3: the current session's slot must be a registry row — the switch
# keys off it (--from) and the transplant needs the target row's config dir.
if [[ -z "$CURRENT_LABEL" || "$CURRENT_LABEL" == "-" ]]; then
  refuse 4 "REFUSED reason=current_not_in_registry -- $CONFIG_DIR is not a registry row; there is no label to switch from" \
           "REFUSED reason=current_not_in_registry config_dir=$CONFIG_DIR"
fi

# ---------------------------------------------------------------------------
# Guard 4: the switch itself — leadv2-account-switch.sh, unmodified, with the
# detector's label.  Its refusal is propagated LOUD (its own reason word in
# detail=), and on any non-zero rc the transplant does NOT happen: resuming a
# session onto an account we failed to switch to would strand it.
SWITCH_ARGS=(--handoff "$HANDOFF" --from "$CURRENT_LABEL")
(( DRY_RUN )) && SWITCH_ARGS+=(--dry-run)
SW_OUT="$(bash "$ACCOUNT_SWITCH" "${SWITCH_ARGS[@]}" 2>&1)"; SW_RC=$?
printf '%s\n' "$SW_OUT" | sed 's/^/account-switch: /'
if (( SW_RC != 0 )); then
  SW_REASON="$(printf '%s' "$SW_OUT" | sed -n 's/.*reason=\([a-z_]*\).*/\1/p' | head -1)"
  if (( SW_RC == 5 )); then
    refuse 5 "FAILED reason=switch_failed detail=${SW_REASON:-?} switch_rc=$SW_RC -- the switch did not take; nothing was transplanted" \
             "FAILED reason=switch_failed detail=${SW_REASON:-unknown} switch_rc=$SW_RC"
  elif (( SW_RC == 4 )); then
    refuse 4 "REFUSED reason=switch_refused detail=${SW_REASON:-?} switch_rc=$SW_RC -- the account-switch guard refused; nothing was transplanted" \
             "REFUSED reason=switch_refused detail=${SW_REASON:-unknown} switch_rc=$SW_RC"
  else
    refuse 3 "REFUSED reason=switch_refused detail=${SW_REASON:-?} switch_rc=$SW_RC -- no free account; nothing was transplanted" \
             "REFUSED reason=switch_refused detail=${SW_REASON:-unknown} switch_rc=$SW_RC"
  fi
fi
if (( DRY_RUN )); then
  TARGET_LABEL="$(printf '%s' "$SW_OUT" | sed -n 's/.*would switch [^ ]* -> \([a-z0-9][a-z0-9_-]*\).*/\1/p' | head -1)"
else
  TARGET_LABEL="$(printf '%s' "$SW_OUT" | sed -n 's/.*OK switched from=[a-z0-9_-]* to=\([a-z0-9][a-z0-9_-]*\).*/\1/p' | head -1)"
fi
if [[ -z "$TARGET_LABEL" ]]; then
  refuse 5 "FAILED reason=switch_unparsed -- could not read the target label from the switch output" \
           "FAILED reason=switch_unparsed"
fi

TARGET_DIR=""
while IFS=$'\t' read -r _label _dir _cred _rest; do
  [[ -z "${_label//[$' \t\r']/}" ]] && continue
  case "$_label" in '#'*) continue ;; esac
  if [[ "$_label" == "$TARGET_LABEL" ]]; then TARGET_DIR="$_dir"; break; fi
done < "$REGISTRY"
if [[ -z "$TARGET_DIR" || ! -d "$TARGET_DIR" ]]; then
  refuse 4 "REFUSED reason=target_not_in_registry target=$TARGET_LABEL -- cannot resolve the target slot's config dir" \
           "REFUSED reason=target_not_in_registry target=$TARGET_LABEL"
fi

# ---------------------------------------------------------------------------
# Guard 5: transplant + resume.  The transcript is COPIED (never moved: the
# original session's history stays where it was), byte-verified, and an
# existing destination that is ANOTHER file is never overwritten (that would
# be destroying the target slot's own session with the same id).  One shape
# measured live 2026-09-10 (lane b7b09a41c2f7): the target slot's projects/
# is a symlink to the source slot's, so DEST IS the transcript -- one inode,
# the transplant is satisfied by construction, and refusing on bare existence
# made the happy path unreachable on this machine.  Inode identity (stat
# dev:ino), never path equality (the paths differ) and never content (hashing
# 70 MB to learn a file is itself): recognized, SAID aloud, then straight to
# the resume command.  A different file in the slot keeps the loud refusal.
DEST_DIR="$TARGET_DIR/projects/$PROJ_SEG"
DEST="$DEST_DIR/$SESSION_ID.jsonl"
if (( DRY_RUN )); then
  say "DRY-RUN would transplant $TRANSCRIPT -> $DEST and emit the resume command below; wrote nothing"
  say "DRY-RUN resume: cd \"$CWD\" && CLAUDE_CONFIG_DIR=\"$TARGET_DIR\" claude --resume $SESSION_ID"
  journal "DRY-RUN from=$CURRENT_LABEL to=$TARGET_LABEL would_transplant=$DEST session=$SESSION_ID"
  exit 0
fi
SAME_INODE=0
if [[ -e "$DEST" ]]; then
  SRC_INO="$(ino_id "$TRANSCRIPT")"; DST_INO="$(ino_id "$DEST")"
  if [[ -n "$SRC_INO" && "$SRC_INO" == "$DST_INO" ]]; then
    SAME_INODE=1
    say "OK transplant already in place: $DEST is the transcript itself (both slots share one projects tree)"
  else
    refuse 5 "FAILED reason=transplant_target_exists -- $DEST already exists; never overwriting a session in the target slot" \
             "FAILED reason=transplant_target_exists dest=$DEST"
  fi
fi
SRC_SHA="$(shasum -a 256 "$TRANSCRIPT" 2>/dev/null | cut -d' ' -f1)"
if (( SAME_INODE )); then
  DST_SHA="$SRC_SHA"   # the destination IS the transcript; nothing to copy or verify
else
  mkdir -p "$DEST_DIR" 2>/dev/null || true
  if ! cp "$TRANSCRIPT" "$DEST" 2>/dev/null; then
    refuse 5 "FAILED reason=transplant_failed -- copy $TRANSCRIPT -> $DEST did not succeed" \
             "FAILED reason=transplant_failed stage=copy dest=$DEST"
  fi
  DST_SHA="$(shasum -a 256 "$DEST" 2>/dev/null | cut -d' ' -f1)"
  if [[ -z "$SRC_SHA" || "$SRC_SHA" != "$DST_SHA" ]]; then
    rm -f "$DEST" 2>/dev/null || true
    refuse 5 "FAILED reason=transplant_failed -- byte-verify failed (src=${SRC_SHA:-none} dst=${DST_SHA:-none}); partial copy removed" \
             "FAILED reason=transplant_failed stage=verify src=${SRC_SHA:-none} dst=${DST_SHA:-none}"
  fi
fi

# ---------------------------------------------------------------------------
# The resume command: pinned to the TARGET slot (Step-0: the account is fixed
# at process start, so pinning the config dir IS pinning the account), in the
# session's own working directory so the project context matches.
if (( SAME_INODE )); then
  say "OK switched from=$CURRENT_LABEL to=$TARGET_LABEL; transplant already satisfied, same inode (sha256 ${DST_SHA:0:12})"
  journal "switched from=$CURRENT_LABEL to=$TARGET_LABEL transplant_same_inode dest=$DEST sha12=${DST_SHA:0:12} session=$SESSION_ID target_dir=$TARGET_DIR cwd=$CWD"
else
  say "OK switched from=$CURRENT_LABEL to=$TARGET_LABEL and transplanted session=$SESSION_ID (sha256 ${DST_SHA:0:12})"
  journal "switched from=$CURRENT_LABEL to=$TARGET_LABEL transplanted=$DEST sha12=${DST_SHA:0:12} session=$SESSION_ID target_dir=$TARGET_DIR cwd=$CWD"
fi
say "exit the stuck session, then continue it on the free account with:"
say "resume: cd \"$CWD\" && CLAUDE_CONFIG_DIR=\"$TARGET_DIR\" claude --resume $SESSION_ID"
exit 0
