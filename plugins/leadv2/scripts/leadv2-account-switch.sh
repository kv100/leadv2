#!/usr/bin/env bash
# leadv2-account-switch.sh — §3 "переключение аккаунта как работающая операция"
#
# ONE action: move work off an exhausted Claude account onto a free one.
# Nothing else.  It is not a report and not a design: it reuses the existing
# instruments instead of building second ones --
#   * leadv2-claude-profile-select.sh (+ lib/leadv2-claude-profile-pick.py
#     inside it) is the ONLY selector: every pick below is a real selector
#     run, pinned or balancing;
#   * leadv2-claude-account-check.sh is the TWO_BUCKETS guard -- switching
#     between two labels that serve one real account is a lie, refuse;
#   * leadv2-quota-read.py is the only liveness/free probe.  Free means its
#     live probe says so (binding window pct < 100); a stale keychain
#     expiresAt is NOT dead and a usage 401 is NOT dead -- the probe decides,
#     exactly like the selector's own D3 discipline.
#
# What "switch" means mechanically (Step-0 measured 2026-09-10, see
# docs/handoff/w-account-switch-impl/report.md): a running client re-reads
# its credential FILE per call, but its config dir / keychain service pin is
# process env and fixed for life -- and this operation never rewrites a live
# slot's credential (that is the 2026-08-28 collapse-incident class).  So the
# operation switches every FUTURE spawn of this lane: it arms the selector's
# own cooldown marker for the exhausted account (the only file the selector
# reads for steering, self-expiring at that account's next window reset) and
# then OBSERVES the next selection actually landing on the free account.
# A switch whose next selection did not move is reported as a FAILURE (rc 5),
# never as a success.
#
# Usage:
#   leadv2-account-switch.sh --handoff <dir> [--from <label>] [--dry-run]
#     --handoff   handoff dir holding claude-profile.log (or
#                 $LEADV2_HANDOFF_DIR); the current account is its LAST
#                 `selected=<label>` line.  The file is read, never written.
#     --from      override the current label (operator intent / tests).
#     --dry-run   decide + confirm, write nothing, change nothing.
#
# Env: everything the reused instruments already honour flows straight
# through (LEADV2_CLAUDE_PROFILES_FILE, LEADV2_CLAUDE_PROFILE_SECURITY_BIN,
# LEADV2_CLAUDE_PROFILE_PROBE, LEADV2_QUOTA_CACHE_DIR,
# LEADV2_CLAUDE_PROFILE_TIMEOUT, LEADV2_CLAUDE_ACCOUNT_ALARM_FILE).  This
# script adds NO second source of truth for accounts, quota, or identity.
#
# Journal: <handoff>/account-switch.log (a SEPARATE file -- claude-profile.log
# is read by leadv2-claude-profile-status.sh via `tail -1` expecting a
# `selected=` line, so this operation must never append after it; the
# selected= line format itself is untouched).
#
# Exit codes:
#   0  switched, and the observed next selection is the target account
#   3  REFUSED -- no free target (reason=no_free_alternative |
#      current_is_best_free | target_not_usable | target_not_free |
#      single_profile_no_alternative)
#   4  REFUSED -- guard (reason=no_current_account | registry_not_two_buckets |
#      selector_refused)
#   5  FAILED -- switch was attempted but NOT observed
#      (reason=switch_not_taken | survivor_changed); loud, never silent
#
# bash 3.2: no associative arrays, no mapfile, indexed arrays only.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELECTOR="$SCRIPT_DIR/leadv2-claude-profile-select.sh"
ACCOUNT_CHECK="$SCRIPT_DIR/leadv2-claude-account-check.sh"
PROBE_BIN="${LEADV2_CLAUDE_PROFILE_PROBE:-$SCRIPT_DIR/leadv2-quota-read.py}"
CACHE_BASE="${LEADV2_QUOTA_CACHE_DIR:-$HOME/.claude/state/leadv2/quota-cache}"
# Mirror of the selector's own cooldown default (leadv2-claude-profile-
# select.sh COOLDOWN_S): when the exhausted account's reset time cannot be
# read from a live probe, steer away for the selector's own default window
# instead of inventing a new constant.
COOLDOWN_S="${LEADV2_CLAUDE_PROFILE_COOLDOWN_S:-900}"

usage() {
  printf 'usage: leadv2-account-switch.sh --handoff <dir> [--from <label>] [--dry-run]\n' >&2
  exit 1
}

HANDOFF=""; FROM_LABEL=""; DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --handoff) [[ $# -ge 2 ]] || usage; HANDOFF="$2"; shift 2 ;;
    --from)    [[ $# -ge 2 ]] || usage; FROM_LABEL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) usage ;;
  esac
done
[[ -z "$HANDOFF" && -n "${LEADV2_HANDOFF_DIR:-}" ]] && HANDOFF="$LEADV2_HANDOFF_DIR"
[[ -n "$HANDOFF" ]] || usage
[[ -r "$SELECTOR" && -r "$ACCOUNT_CHECK" ]] || { echo "account-switch: FATAL selector/account-check missing" >&2; exit 4; }

PROFILE_LOG="$HANDOFF/claude-profile.log"
SWITCH_JOURNAL="$HANDOFF/account-switch.log"

say()  { printf 'account-switch: %s\n' "$*"; }
journal() {
  mkdir -p "$HANDOFF" 2>/dev/null || true
  printf '%s [account-switch] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$SWITCH_JOURNAL" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Current account: the LAST selected= line of the lane's claude-profile.log
# (read-only; its format is a pinned contract this script must not touch).
CURRENT_LABEL="$FROM_LABEL"
if [[ -z "$CURRENT_LABEL" ]]; then
  if [[ ! -r "$PROFILE_LOG" ]] \
     || ! CURRENT_LABEL="$(grep -a 'selected=' "$PROFILE_LOG" | tail -1 | sed -n 's/.*selected=\([a-z0-9][a-z0-9_-]*\).*/\1/p')" \
     || [[ -z "$CURRENT_LABEL" ]]; then
    say "REFUSED reason=no_current_account -- no selected= line in $PROFILE_LOG and no --from"
    journal "REFUSED reason=no_current_account"
    exit 4
  fi
fi

# ---------------------------------------------------------------------------
# Guard (reused instrument #1): the registry must really hold TWO distinct
# accounts before any switch is meaningful.  ONE_BUCKET / ORG_COLLAPSE /
# INDETERMINATE all refuse -- a "switch" between two labels on one account
# is exactly the silent no-op this lane exists to kill.
CHECK_OUT="$(bash "$ACCOUNT_CHECK" 2>&1)"; CHECK_RC=$?
if (( CHECK_RC != 0 )); then
  VERDICT="$(printf '%s\n' "$CHECK_OUT" | sed -n 's/^VERDICT: \([A-Z_]*\).*/\1/p' | tail -1)"
  say "REFUSED reason=registry_not_two_buckets verdict=${VERDICT:-unknown} -- refusing to switch inside a collapsed registry"
  journal "REFUSED reason=registry_not_two_buckets verdict=${VERDICT:-unknown}"
  exit 4
fi

# Selector wrapper: one code path for every run below, journal to the switch
# log only.  DEMOTE_DIR=off keeps the ranking a pure score comparison --
# demotion is a dispatch-time concern, not a switch concern.
run_selector() { # $1 = requested label or ""
  if [[ -n "$1" ]]; then
    env LEADV2_CLAUDE_MULTIPROFILE=1 \
        LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off \
        LEADV2_CLAUDE_PROFILE_JOURNAL="$SWITCH_JOURNAL" \
        LEADV2_CLAUDE_PROFILE_REQUESTED="$1" \
      bash "$SELECTOR" 2>>"$SWITCH_JOURNAL"
  else
    env LEADV2_CLAUDE_MULTIPROFILE=1 \
        LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off \
        LEADV2_CLAUDE_PROFILE_JOURNAL="$SWITCH_JOURNAL" \
      bash "$SELECTOR" 2>>"$SWITCH_JOURNAL"
  fi
}

re_sel='^profile=([a-z0-9][a-z0-9_-]{0,31})[[:space:]]config_dir=([^[:space:]]+)[[:space:]]score=([0-9]+)[[:space:]]source=(live|unknown)'

# Refusal-path helper (must be defined before the Run A decision block that
# calls it): resolve a label's credential source through the selector, then
# read that account's own reset time with the same live probe the selector
# uses -- the ONLY reset-time source, no second instrument.
probe_window_iso() { # <label> -- echo "label=<l> reset=<iso>" from a live probe
  local svc out
  svc="$(run_selector "$1" | sed -n 's/.*[[:space:]]cred=\([^[:space:]]*\).*/\1/p')"
  [[ -z "$svc" ]] && return 1
  if [[ "$svc" == keychain:* ]]; then
    out="$(env "LEADV2_QUOTA_CACHE_DIR=${CACHE_BASE}/identity-$1" \
        "LEADV2_ANTHROPIC_ACTIVE_SERVICE=${svc#keychain:}" \
      python3 "$PROBE_BIN" anthropic --no-cache 2>/dev/null)"
  else
    out="$(env "LEADV2_QUOTA_CACHE_DIR=${CACHE_BASE}/identity-$1" \
      python3 "$PROBE_BIN" anthropic --no-cache --credential-file "${svc#file:}" 2>/dev/null)"
  fi
  printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(1)
a = next((x for x in (d.get("accounts") or []) if isinstance(x, dict) and x.get("active")), None)
if not a:
    sys.exit(1)
r = a.get("five_hour_reset_iso") or a.get("seven_day_reset_iso")
if r:
    print("label=%s reset=%s" % (sys.argv[1], r))
' "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Run A -- the balancing selector decides the target.  Its pick IS the reuse
# of lib/leadv2-claude-profile-pick.py; no second chooser exists here.
SEL_A="$(run_selector "")"; SEL_A_RC=$?
if [[ "$SEL_A" =~ $re_sel ]]; then
  PICK_LABEL="${BASH_REMATCH[1]}"; PICK_SCORE="${BASH_REMATCH[3]}"; PICK_SOURCE="${BASH_REMATCH[4]}"
  PICK_WINDOWS="$(printf '%s' "$SEL_A" | sed -n 's/.*[[:space:]]windows=\([^[:space:]]*\).*/\1/p')"
else
  SEL_REASON="$(printf '%s' "$SEL_A" | sed -n 's/^profile=-[[:space:]]reason=\([^[:space:]]*\).*/\1/p')"
  if [[ -z "$SEL_REASON" && "$SEL_A_RC" == "0" ]]; then SEL_REASON="single_profile_no_alternative"; fi
  say "REFUSED reason=selector_refused selector_reason=${SEL_REASON:-unparsed} -- the selector did not name a usable account"
  journal "REFUSED reason=selector_refused selector_reason=${SEL_REASON:-unparsed}"
  exit 4
fi

if [[ "$PICK_LABEL" == "$CURRENT_LABEL" ]]; then
  # The balancer kept the current account.  Two named shapes, never a silent
  # "switched" onto the very same account:
  if [[ "$PICK_SOURCE" == "live" && "$PICK_SCORE" -lt 100 ]]; then
    say "REFUSED reason=current_is_best_free -- current=$CURRENT_LABEL is the freest account (score=$PICK_SCORE); windows: ${PICK_WINDOWS:-unknown}"
    journal "REFUSED reason=current_is_best_free score=$PICK_SCORE"
    exit 3
  fi
  # Current is exhausted (or unprobed) and STILL won => every alternative is
  # worse (cooling / unknown / exhausted).  Name the nearest reset, then stop.
  NEAREST=""
  _wn="$(printf '%s' "${PICK_WINDOWS:-}" | tr '|' '\n')"
  while IFS= read -r _wrow; do
    [[ -n "$_wrow" ]] || continue
    _wlb="${_wrow%%:*}"; _wpct="${_wrow##*=}"
    [[ -z "$_wlb" || "$_wlb" == "$_wrow" ]] && continue
    if [[ "$_wpct" == "100" || "$_wpct" == "-" ]]; then
      NEAREST="$(probe_window_iso "$_wlb" 2>/dev/null)"; [[ -n "$NEAREST" ]] && break
    fi
  done <<<"$_wn"
  say "REFUSED reason=no_free_alternative -- current=$CURRENT_LABEL exhausted and every other candidate is worse; windows: ${PICK_WINDOWS:-unknown}${NEAREST:+; nearest reset: $NEAREST}"
  journal "REFUSED reason=no_free_alternative windows=${PICK_WINDOWS:-unknown}${NEAREST:+ nearest_reset=$NEAREST}"
  exit 3
fi
TARGET_LABEL="$PICK_LABEL"

# ---------------------------------------------------------------------------
# Run B -- confirm the target the hard-pin way (NO-WAY-TO-PIN semantics,
# reused): the selector must probe THIS one account and confirm it usable.
# Free-ness comes from the live probe alone (source=live, score<100).
SEL_B="$(run_selector "$TARGET_LABEL")"; SEL_B_RC=$?
if [[ "$SEL_B" =~ $re_sel ]]; then
  TARGET_SOURCE="${BASH_REMATCH[4]}"; TARGET_SCORE="${BASH_REMATCH[3]}"
  TARGET_BINDING="$(printf '%s' "$SEL_B" | sed -n 's/.*[[:space:]]binding=\([^[:space:]]*\).*/\1/p')"
else
  say "REFUSED reason=target_not_usable target=$TARGET_LABEL selector_rc=$SEL_B_RC -- live probe could not confirm the target"
  journal "REFUSED reason=target_not_usable target=$TARGET_LABEL selector_rc=$SEL_B_RC"
  exit 3
fi
if [[ "$TARGET_SOURCE" != "live" || "$TARGET_SCORE" -ge 100 ]]; then
  say "REFUSED reason=target_not_free target=$TARGET_LABEL source=$TARGET_SOURCE score=$TARGET_SCORE -- free requires a live probe under 100"
  journal "REFUSED reason=target_not_free target=$TARGET_LABEL source=$TARGET_SOURCE score=$TARGET_SCORE"
  exit 3
fi

# ---------------------------------------------------------------------------
# Run C -- pinned probe of the CURRENT account: identity/config_dir/cred for
# the cooldown marker keying (same derivation as the selector's), and its
# live windows for the marker's expiry.
SEL_C="$(run_selector "$CURRENT_LABEL")"; SEL_C_RC=$?
if ! [[ "$SEL_C" =~ $re_sel ]]; then
  say "REFUSED reason=current_not_probeable current=$CURRENT_LABEL selector_rc=$SEL_C_RC -- cannot key the steering marker"
  journal "REFUSED reason=current_not_probeable current=$CURRENT_LABEL"
  exit 4
fi
CUR_IDENTITY="$(printf '%s' "$SEL_C" | sed -n 's/.*[[:space:]]identity=\([^[:space:]]*\).*/\1/p')"
CUR_DIR="${BASH_REMATCH[2]}"
CUR_CRED="$(printf '%s' "$SEL_C" | sed -n 's/.*[[:space:]]cred=\([^[:space:]]*\).*/\1/p')"

# The marker's id_key replicates the selector's bucket keying (its lines
# around the probe loop): identity when the email half resolved, config dir
# hash otherwise.  Drift here would write an invisible marker -- the suite
# pins the selector actually skipping the exhausted account, so a divergence
# reds the test, not production.
if [[ "${CUR_IDENTITY#*/}" == "na" || -z "$CUR_IDENTITY" ]]; then
  ID_KEY="$(printf '%s' "$CUR_DIR" | tr -c 'A-Za-z0-9_-' '_')"
else
  ID_KEY="$(printf '%s' "$CUR_IDENTITY" | tr -c 'A-Za-z0-9_-' '_')"
fi

# Live probe of the current account (the same invocation the selector makes):
# reset time for the marker, pct for the record.  UNVERIFIABLE reset (probe
# unknown / 429) falls back to the selector's own cooldown window.
probe_current() {
  if [[ "$CUR_CRED" == keychain:* ]]; then
    env "LEADV2_QUOTA_CACHE_DIR=${CACHE_BASE}/identity-${ID_KEY}" \
        "LEADV2_ANTHROPIC_ACTIVE_SERVICE=${CUR_CRED#keychain:}" \
      python3 "$PROBE_BIN" anthropic --no-cache 2>/dev/null
  else
    env "LEADV2_QUOTA_CACHE_DIR=${CACHE_BASE}/identity-${ID_KEY}" \
      python3 "$PROBE_BIN" anthropic --no-cache --credential-file "${CUR_CRED#file:}" 2>/dev/null
  fi
}

CUR_PROBE="$(probe_current)"
RESET_EPOCH="$(printf '%s' "$CUR_PROBE" | python3 -c '
import calendar, json, sys, time
try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
a = next((x for x in (d.get("accounts") or []) if isinstance(x, dict) and x.get("active")), None)
if not a:
    sys.exit(0)
for iso in (a.get("five_hour_reset_iso"), a.get("seven_day_reset_iso")):
    if not iso:
        continue
    try:
        print(calendar.timegm(time.strptime(iso[:19], "%Y-%m-%dT%H:%M:%S")))
    except Exception:
        continue
    sys.exit(0)
' 2>/dev/null | head -1)"
if [[ "$RESET_EPOCH" =~ ^[0-9]+$ ]] && (( RESET_EPOCH > $(date +%s) )); then
  COOLDOWN_UNTIL="$RESET_EPOCH"
  EXHAUSTED_UNTIL="reset"
else
  COOLDOWN_UNTIL=$(( $(date +%s) + COOLDOWN_S ))
  EXHAUSTED_UNTIL="probe_unknown_fallback_${COOLDOWN_S}s"
fi

if (( DRY_RUN )); then
  say "DRY-RUN would switch $CURRENT_LABEL -> $TARGET_LABEL (score=$TARGET_SCORE binding=$TARGET_BINDING) steering cooldown until epoch $COOLDOWN_UNTIL ($EXHAUSTED_UNTIL)"
  journal "DRY-RUN from=$CURRENT_LABEL to=$TARGET_LABEL cooldown_until=$COOLDOWN_UNTIL basis=$EXHAUSTED_UNTIL"
  exit 0
fi

# ---------------------------------------------------------------------------
# Survivors snapshot: what must OUTLIVE the switch is checked by reading, not
# by word.  claude-profile.log must stay byte-identical (this operation never
# writes it), and the handoff's stream/journal artifacts must not move.
survivor_snapshot() {
  { sha_one "$PROFILE_LOG"
    find "$HANDOFF" -maxdepth 1 -type f \( -name '*.stream.jsonl' -o -name '*journal*' -o -name 'mission*.md' \) 2>/dev/null | sort
  } 2>/dev/null
}
sha_one() { # <file> -- portable sha256 of a file, "-" when unreadable
  [[ -r "$1" ]] || { printf 'sha:- %s\n' "$1"; return 0; }
  ( shasum -a 256 "$1" 2>/dev/null || sha256sum "$1" 2>/dev/null ) | sed 's/  .*/ /' | sed "s|^|$(basename "$1") |"
}
BEFORE_SURVIVORS="$(survivor_snapshot)"

# ---------------------------------------------------------------------------
# PERFORM: arm the selector's own cooldown marker for the exhausted account.
# File names/formats are the selector's (probe-cooldown-until + .cred
# sidecar); until = that account's own window reset, so the steer expires the
# moment the account is free again and re-competition is automatic.
MARKER_DIR="${CACHE_BASE}/identity-${ID_KEY}"
MARKER_RC=0
mkdir -p "$MARKER_DIR" 2>/dev/null || MARKER_RC=1
printf '%s' "$COOLDOWN_UNTIL" > "${MARKER_DIR}/probe-cooldown-until" 2>/dev/null || MARKER_RC=1
# .cred sidecar: sha256[:12] of the RAW credential blob (never the blob),
# so the selector can later tell "same exhausted credential" from "operator
# re-logged in" (PROBE-COOLDOWN-OUTLIVES-ITS-CONDITION-01 semantics).
CRED_DIGEST="-"
case "$CUR_CRED" in
  keychain:*)
    if command -v "${LEADV2_CLAUDE_PROFILE_SECURITY_BIN:-security}" >/dev/null 2>&1; then
      CRED_DIGEST="$("${LEADV2_CLAUDE_PROFILE_SECURITY_BIN:-security}" find-generic-password -s "${CUR_CRED#keychain:}" -w 2>/dev/null \
        | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:12])' 2>/dev/null || echo -)"
    fi ;;
  file:*)
    CRED_DIGEST="$(cat "${CUR_CRED#file:}" 2>/dev/null \
      | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:12])' 2>/dev/null || echo -)" ;;
esac
[[ "$CRED_DIGEST" != "-" ]] && printf '%s' "$CRED_DIGEST" > "${MARKER_DIR}/probe-cooldown-until.cred" 2>/dev/null || true

# ---------------------------------------------------------------------------
# OBSERVE (the check the whole operation stands on): the NEXT balancing
# selection must land on the target.  This is a fresh selector run -- a real
# observation, not the command asserting itself.  A next pick that stayed on
# the old account is a FAILED switch (rc 5), loud.
SEL_E="$(run_selector "")"
OBSERVED_NEXT="$(printf '%s' "$SEL_E" | sed -n 's/^profile=\([a-z0-9][a-z0-9_-]*\)[[:space:]].*/\1/p')"
OBSERVED_SCORE="$(printf '%s' "$SEL_E" | sed -n 's/.*[[:space:]]score=\([0-9]*\).*/\1/p')"
if [[ "$OBSERVED_NEXT" != "$TARGET_LABEL" ]]; then
  say "FAILED reason=switch_not_taken observed_next_pick=${OBSERVED_NEXT:-none} expected=$TARGET_LABEL -- the next selection did NOT move to the new account"
  journal "FAILED reason=switch_not_taken observed=${OBSERVED_NEXT:-none} expected=$TARGET_LABEL marker_rc=$MARKER_RC"
  exit 5
fi
# The mirror shape of the same failure: the pick DID move, but the target
# stopped being free between confirmation and observation -- a switch onto
# an exhausted account is not a switch, it is a relay into the same wall.
if [[ ! "$OBSERVED_SCORE" =~ ^[0-9]+$ || "$OBSERVED_SCORE" -ge 100 ]]; then
  say "FAILED reason=switch_not_taken observed_next_pick=$OBSERVED_NEXT observed_score=${OBSERVED_SCORE:-?} -- the target stopped being free before the next selection"
  journal "FAILED reason=switch_not_taken observed=$OBSERVED_NEXT observed_score=${OBSERVED_SCORE:-?} detail=target_no_longer_free marker_rc=$MARKER_RC"
  exit 5
fi

# Survivors re-check: by reading the bytes back.
AFTER_SURVIVORS="$(survivor_snapshot)"
if [[ "$BEFORE_SURVIVORS" != "$AFTER_SURVIVORS" ]]; then
  say "FAILED reason=survivor_changed -- handoff artifacts did not survive the switch byte-identically"
  journal "FAILED reason=survivor_changed"
  exit 5
fi

# ---------------------------------------------------------------------------
# Live children: processes already running keep their account (env is fixed
# for their lifetime; their credential is never rewritten under them).  Count
# them, never print the service name.  Best-effort: `ps eww` may be denied.
STAYING=0; STAYING_PIDS=""
if [[ "$CUR_CRED" == keychain:* ]]; then
  _svc="${CUR_CRED#keychain:}"
  for _pid in $(ps -axo pid=,command= 2>/dev/null | grep -i 'claude' | awk '{print $1}'); do
    _envline="$(ps eww -o command= -p "$_pid" 2>/dev/null || true)"
    if [[ "$_envline" == *"LEADV2_ANTHROPIC_ACTIVE_SERVICE=${_svc}"* ]]; then
      STAYING=$((STAYING + 1)); STAYING_PIDS="${STAYING_PIDS:+$STAYING_PIDS,}$_pid"
    fi
  done
fi

say "OK switched from=$CURRENT_LABEL to=$TARGET_LABEL (score=$TARGET_SCORE binding=$TARGET_BINDING)"
say "observed_next_pick=$OBSERVED_NEXT observed_score=${OBSERVED_SCORE:-?} -- the NEXT selection runs on the new account"
say "steering: $CURRENT_LABEL cooling until epoch $COOLDOWN_UNTIL ($EXHAUSTED_UNTIL); auto-reverts at reset"
say "staying_children=$STAYING${STAYING_PIDS:+ pids=$STAYING_PIDS} -- running sessions keep the old account until they exit; new spawns use $TARGET_LABEL"
journal "switched from=$CURRENT_LABEL to=$TARGET_LABEL score=$TARGET_SCORE binding=$TARGET_BINDING cooldown_until=$COOLDOWN_UNTIL basis=$EXHAUSTED_UNTIL observed_next_pick=$OBSERVED_NEXT staying_children=$STAYING marker_rc=$MARKER_RC"
exit 0
