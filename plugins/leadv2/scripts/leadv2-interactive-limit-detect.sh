#!/usr/bin/env bash
# leadv2-interactive-limit-detect.sh — interactive-session limit detector
# (lane 467462db0de5: "интерактивная сессия должна уметь уйти с исчерпанного
# аккаунта").
#
# ONE question, answered and nothing else: is THIS interactive session sitting
# on an exhausted-account wall — the real banner from the 2026-09-10 m3-market
# case, "Session limit reached · Retrying in 50m · attempt 1/300" — or is it
# something else?  The detector never switches anything: the only switcher is
# leadv2-account-switch.sh (composed by leadv2-interactive-session-switch.sh).
#
# Why two inputs.  The banner string is rendered on the TUI screen ONLY: it
# appears in no transcript and no log (grep for "Session limit
# reached|Retrying in" over the m3-market project transcripts AND over
# plugins/leadv2/{scripts,hooks} returns zero files), so when the operator can
# paste what they see, that text is a first-class input.  When they cannot,
# the session's OWN account is probed live through the selector's own probe —
# the session's status line can lie (the same case showed a cached 61% while
# the account was walled); the live probe is the third party that cannot.
#
# LIMIT vs ORDINARY NETWORK ERROR — the discriminator this detector exists
# for (yanking the account on every connection glitch is the named failure
# mode).  "Limit" is ONLY one of:
#   (a) screen text containing the literal banner phrase
#       "<session|usage> limit reached" (lowercased match; "Approaching …
#       usage limit" deliberately does NOT match — approaching is not
#       reached); or
#   (b) a live probe that PARSED and shows a quota window at/over its cap
#       (five_hour_pct or seven_day_pct >= 100).
# Everything else — transport failure, HTTP error, unparsed payload,
# connection-reset banners, 5xx text — is verdict=unknown or no_limit and can
# NEVER trigger a switch.
#
# Usage:
#   leadv2-interactive-limit-detect.sh [--screen-text <string|@file>]
#                                      [--config-dir <dir>] [--journal <file>]
#
#   (no --screen-text)         live-probe the session's account.
#   --screen-text <string>     match what the operator sees, verbatim.
#   --screen-text @<file>      read the text from <file>.
#   --config-dir <dir>         the session's CLAUDE_CONFIG_DIR (default
#                              $HOME/.claude); resolves the registry row
#                              (label + credential source) for the live probe
#                              and is reported as context on every verdict.
#   --journal <file>           append the verdict line there too.
#
# Env (the reused instruments' own knobs flow through unchanged):
#   LEADV2_CLAUDE_PROFILES_FILE, LEADV2_CLAUDE_PROFILE_PROBE,
#   LEADV2_CLAUDE_PROFILE_SECURITY_BIN, LEADV2_QUOTA_CACHE_DIR.
#
# Output: exactly one verdict line on stdout --
#   verdict=limit source=screen|live label=<l|-> pct=<n|-> [attempt=<k/n>]
#   verdict=no_limit source=screen|live label=<l|-> pct=<n|->
#   verdict=unknown reason=<probe_transport|probe_unparsed|probe_unknown|
#                          no_registry_row|screen_unreadable> label=<l|->
#
# Exit codes: 0 = limit · 1 = no_limit · 2 = unknown · 3 = usage/fatal.
# A live probe's two measured traps are honoured by construction: expiresAt is
# never consulted (probe_window parsing only), and a 401/failed probe is
# verdict=unknown — never "dead", never a limit.
#
# bash 3.2: indexed arrays only, no mapfile, no ${var^^}.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_BIN="${LEADV2_CLAUDE_PROFILE_PROBE:-$SCRIPT_DIR/leadv2-quota-read.py}"
REGISTRY="${LEADV2_CLAUDE_PROFILES_FILE:-$HOME/.claude/state/leadv2/claude-profiles.tsv}"
CACHE_BASE="${LEADV2_QUOTA_CACHE_DIR:-$HOME/.claude/state/leadv2/quota-cache}"

usage() {
  printf 'usage: leadv2-interactive-limit-detect.sh [--screen-text <s|@f>] [--config-dir <d>] [--journal <f>]\n' >&2
  exit 3
}

SCREEN_TEXT=""; CONFIG_DIR="$HOME/.claude"; JOURNAL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --screen-text) [[ $# -ge 2 ]] || usage; SCREEN_TEXT="$2"; shift 2 ;;
    --config-dir)  [[ $# -ge 2 ]] || usage; CONFIG_DIR="$2"; shift 2 ;;
    --journal)     [[ $# -ge 2 ]] || usage; JOURNAL="$2"; shift 2 ;;
    *) usage ;;
  esac
done

say() { printf 'limit-detect: %s\n' "$*"; }
emit() { # <verdict line> <rc> -- the single output contract
  printf '%s\n' "$1"
  if [[ -n "$JOURNAL" ]]; then
    mkdir -p "$(dirname "$JOURNAL")" 2>/dev/null || true
    printf '%s [limit-detect] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$JOURNAL" 2>/dev/null || true
  fi
  exit "$2"
}

# --- registry row for the session's config dir (label + credential source) --
LABEL="-"; CRED=""
if [[ -r "$REGISTRY" ]]; then
  while IFS=$'\t' read -r _label _dir _cred _rest; do
    [[ -z "${_label//[$' \t\r']/}" ]] && continue
    case "$_label" in '#'*) continue ;; esac
    if [[ "$_dir" == "$CONFIG_DIR" ]]; then LABEL="$_label"; CRED="$_cred"; break; fi
  done < "$REGISTRY"
fi

# ---------------------------------------------------------------------------
# Input 1: the operator's screen text.  The banner phrase is matched
# lowercased and literally — no invented formats, the string from the case.
if [[ -n "$SCREEN_TEXT" ]]; then
  RAW="$SCREEN_TEXT"
  if [[ "$RAW" == @* ]]; then
    RAW="$(cat "${RAW#@}" 2>/dev/null)" || RAW=""
    if [[ -z "$RAW" ]]; then
      emit "verdict=unknown reason=screen_unreadable label=$LABEL" 2
    fi
  fi
  LOW="$(printf '%s' "$RAW" | tr '[:upper:]' '[:lower:]')"
  if printf '%s' "$LOW" | grep -qE '(session|usage) limit reached'; then
    ATTEMPT=""
    _att="$(printf '%s' "$LOW" | sed -n 's/.*attempt \([0-9]*\/[0-9]*\).*/\1/p' | head -1)"
    [[ -n "$_att" ]] && ATTEMPT=" attempt=$_att"
    emit "verdict=limit source=screen label=$LABEL pct=-$ATTEMPT" 0
  fi
  # A recognised NON-limit banner (connection errors, 5xx text, "Approaching
  # … usage limit") is a clean no — not unknown: the text was read, it simply
  # is not a wall.
  emit "verdict=no_limit source=screen label=$LABEL pct=-" 1
fi

# ---------------------------------------------------------------------------
# Input 2 (default): the live probe of the session's own account — the same
# invocation shape leadv2-account-switch.sh uses, service-pinned the
# selector's way.  No second instrument.
if [[ -z "$CRED" ]]; then
  emit "verdict=unknown reason=no_registry_row label=- config_dir=$CONFIG_DIR" 2
fi
if [[ "$CRED" == keychain:* ]]; then
  PROBE_OUT="$(env "LEADV2_QUOTA_CACHE_DIR=${CACHE_BASE}/identity-detect" \
      "LEADV2_ANTHROPIC_ACTIVE_SERVICE=${CRED#keychain:}" \
    python3 "$PROBE_BIN" anthropic --no-cache 2>/dev/null)"; PROBE_RC=$?
else
  PROBE_OUT="$(env "LEADV2_QUOTA_CACHE_DIR=${CACHE_BASE}/identity-detect" \
    python3 "$PROBE_BIN" anthropic --no-cache --credential-file "${CRED#file:}" 2>/dev/null)"; PROBE_RC=$?
fi
if (( PROBE_RC != 0 )) || [[ -z "$PROBE_OUT" ]]; then
  emit "verdict=unknown reason=probe_transport label=$LABEL probe_rc=$PROBE_RC" 2
fi
PARSED="$(printf '%s' "$PROBE_OUT" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print("probe_unparsed"); raise SystemExit
accounts = d.get("accounts") or []
a = next((x for x in accounts if isinstance(x, dict) and x.get("active")), None)
if a is None or not (d.get("status") == "ok" and a.get("status") == "ok"):
    print("probe_unknown"); raise SystemExit
try:
    f = float(a.get("five_hour_pct")); s = float(a.get("seven_day_pct"))
except (TypeError, ValueError):
    print("probe_unparsed"); raise SystemExit
print("pct=%g limit=%s window=%s" % (max(f, s), "1" if max(f, s) >= 100 else "0",
      "five_hour" if f >= s else "seven_day"))
' 2>/dev/null)"
case "$PARSED" in
  pct=*) ;;
  probe_unparsed) emit "verdict=unknown reason=probe_unparsed label=$LABEL" 2 ;;
  probe_unknown)   emit "verdict=unknown reason=probe_unknown label=$LABEL" 2 ;;
  *)               emit "verdict=unknown reason=probe_unparsed label=$LABEL" 2 ;;
esac
PCT="${PARSED%% *}"; PCT="${PCT#pct=}"
WIN="$(printf '%s' "$PARSED" | sed -n 's/.*window=\([a-z_]*\).*/\1/p')"
IS_LIMIT="${PARSED#* limit=}"; IS_LIMIT="${IS_LIMIT%% *}"
if [[ "$IS_LIMIT" == "1" ]]; then
  emit "verdict=limit source=live label=$LABEL pct=$PCT window=$WIN" 0
fi
emit "verdict=no_limit source=live label=$LABEL pct=$PCT" 1
