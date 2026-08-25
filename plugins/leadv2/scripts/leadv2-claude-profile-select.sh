#!/usr/bin/env bash
# leadv2-claude-profile-select.sh — CLAUDE-MULTIPROFILE-QUOTA-02
#
# Opt-in Anthropic multi-profile selector for Claude lanes.  Reads a
# user-level registry (LEADV2_CLAUDE_PROFILES_FILE, default
# ~/.claude/state/leadv2/claude-profiles.tsv — NEVER committed to any repo),
# probes each profile's quota independently, and prints exactly ONE stdout
# line naming the profile with the lowest worst-window utilisation:
#
#   profile=<label> config_dir=<path> score=<n> source=live|unknown \
#   reason=<reason> candidates=<n>
#
# config_dir appears on stdout ONLY — it is consumed by the caller
# (claude-subsession.sh) and is never journalled, logged, or sent to handoff.
# Every other surface (stderr warnings, handoff log) is LABEL-ONLY: registry
# lines are never echoed, so a path, service name, or email-shaped label
# cannot leak through a warning.
#
# Fail-open, always: opt-out/unset, missing registry, <2 valid entries, a
# malformed registry, or a probe budget that every probe consumed end in
# `profile=- reason=single_profile` (or silence) + exit 0 — the caller then
# leaves CLAUDE_CONFIG_DIR untouched and the lane runs exactly as before.
#
# Env:
#   LEADV2_CLAUDE_MULTIPROFILE=1   opt-in gate (anything else = inert)
#   LEADV2_CLAUDE_PROFILES_FILE    registry path (user-level, out of the repo)
#   LEADV2_CLAUDE_PROFILE_PROBE    probe override (hermetic tests)
#   LEADV2_CLAUDE_PROFILE_TIMEOUT  TOTAL probe budget, s (default 12, 1..60)
#   LEADV2_QUOTA_CACHE_DIR         base for per-profile cache dirs
#   LEADV2_CLAUDE_PROFILE_SECURITY_BIN  override for `security` (hermetic tests
#                                        inject a fixture reader here; the
#                                        stub must accept `find-generic-password
#                                        -s <service> -w` and print JSON)
#
# Registry format (TSV, blank lines and #-comments ignored):
#   label<TAB>config_dir<TAB>credential_source(optional)
#   credential_source: keychain:<service> | file:<abs path>
#   absent -> file:<config_dir>/.credentials.json
#   label: ^[a-z0-9][a-z0-9_-]{0,31}$ ('@'/'.', i.e. emails, are a hard reject)
#
# T12 (CLAUDE-PROFILE-SELECT-FINISH-01 follow-up): the registry LABEL is
# display-only and operator-chosen -- it can drift from what the credential
# actually is (a relabeled/re-logged-in slot can silently start serving a
# different account/subscriptionType).  So at selection time this script
# reads each credential's OWN JSON (never the label) and derives an
# `identity=<subscriptionType>/<email-or-na>` that is what actually gets
# scored, cached, and reported -- the label never drives quota bucketing.
# A credential whose `claudeAiOauth.expiresAt` is in the past is flagged
# `WARN token_expired` and excluded from candidate scoring; if that leaves
# zero live candidates, the selector refuses outright (reason=all_expired)
# rather than silently picking a dead credential.  Only parsed metadata
# (subscriptionType/email/expiresAt) ever leaves this function -- the raw
# credential JSON (which carries accessToken/refreshToken) is never printed,
# logged, or journalled.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${LEADV2_CLAUDE_PROFILES_FILE:-$HOME/.claude/state/leadv2/claude-profiles.tsv}"
PROBE="${LEADV2_CLAUDE_PROFILE_PROBE:-$SCRIPT_DIR/leadv2-quota-read.py}"
PICK="$SCRIPT_DIR/lib/leadv2-claude-profile-pick.py"
CACHE_BASE="${LEADV2_QUOTA_CACHE_DIR:-$HOME/.claude/state/leadv2/quota-cache}"
SECURITY_BIN="${LEADV2_CLAUDE_PROFILE_SECURITY_BIN:-security}"

warn() { printf '[claude-profile-select] %s\n' "$*" >&2; }
single_profile() { printf 'profile=- reason=single_profile\n'; exit 0; }
refuse_all_expired() { printf 'profile=- reason=all_expired\n'; exit 0; }

# read_cred_json <credential_source> -> raw credential JSON on stdout, empty
# on any failure. keychain: goes through $SECURITY_BIN (overridable for
# hermetic tests); file: is a plain read. Never logs, never echoes on error.
read_cred_json() {
  case "$1" in
    keychain:*) "$SECURITY_BIN" find-generic-password -s "${1#keychain:}" -w 2>/dev/null ;;
    file:*)     cat "${1#file:}" 2>/dev/null ;;
    *)          return 1 ;;
  esac
}

# derive_identity <credential_source> -> "<subscription_type>\t<email>\t<expires_at_ms|>"
# Parses ONLY claudeAiOauth.{subscriptionType,email/emailAddress,expiresAt};
# never emits accessToken/refreshToken. Any parse failure -> "unknown\tna\t".
derive_identity() {
  read_cred_json "$1" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    o = d.get("claudeAiOauth") or {}
    st = o.get("subscriptionType") or "unknown"
    email = o.get("email") or o.get("emailAddress") or "na"
    ea = o.get("expiresAt")
    ea = ea if isinstance(ea, (int, float)) else ""
    print("%s\t%s\t%s" % (st, email, ea))
except Exception:
    print("unknown\tna\t")
' 2>/dev/null
}

# Opt-in gate: unset or != 1 => print nothing, exit 0 (lane unchanged).
[[ "${LEADV2_CLAUDE_MULTIPROFILE:-}" == "1" ]] || exit 0

# TOTAL probe-budget clamp (QUOTA-GATE-PARITY-01 F4 pattern: the configured
# timeout is untrusted operator input; accept a positive integer only and
# clamp 1..60 so a typo can neither zero the budget nor stall every spawn).
timeout_s="${LEADV2_CLAUDE_PROFILE_TIMEOUT:-12}"
if ! [[ "$timeout_s" =~ ^[0-9]+$ ]]; then
  warn "WARN: LEADV2_CLAUDE_PROFILE_TIMEOUT is not a positive integer; using default 12s"
  timeout_s=12
fi
if (( timeout_s < 1 )); then warn "WARN: LEADV2_CLAUDE_PROFILE_TIMEOUT clamped to 1s"; timeout_s=1; fi
if (( timeout_s > 60 )); then warn "WARN: LEADV2_CLAUDE_PROFILE_TIMEOUT clamped to 60s"; timeout_s=60; fi

# --- registry parse ---------------------------------------------------------
# bash-3.2 safe: no associative arrays; duplicate labels are resolved by
# first-wins so the selection stays a pure function of file order.
LABELS=()
DIRS=()
SOURCES=()
IDENTITIES=()
expired_count=0
re_label='^[a-z0-9][a-z0-9_-]{0,31}$'
[[ -r "$REGISTRY" ]] || single_profile
lineno=0
while IFS=$'\t' read -r label config_dir cred || [[ -n "${label:-}" ]]; do
  lineno=$((lineno + 1))
  [[ -z "${label//[$' \t\r']/}" ]] && continue
  case "$label" in '#'*) continue ;; esac
  if ! [[ "$label" =~ $re_label ]]; then
    warn "WARN: registry line ${lineno} skipped: label charset/length invalid (allowed [a-z0-9][a-z0-9_-]{0,31})"
    continue
  fi
  if [[ -z "$config_dir" ]]; then
    warn "WARN: registry line ${lineno} skipped: missing config_dir"
    continue
  fi
  case "$config_dir" in
    /*) ;;
    *) warn "WARN: registry line ${lineno} skipped: config_dir not absolute"; continue ;;
  esac
  if [[ ! -d "$config_dir" || ! -r "$config_dir" ]]; then
    warn "WARN: registry line ${lineno} skipped: config_dir missing or unreadable"
    continue
  fi
  if [[ -z "$cred" ]]; then cred="file:${config_dir}/.credentials.json"; fi
  # lean: both registry columns are validated here, but cross-account identity
  # verification is deferred: the probe payload has no identity comparable to
  # what config_dir resolves to, so the operator owns that pairing.
  case "$cred" in
    keychain:?*)
      ;;
    file:/*)
      ;;
    *)
      warn "WARN: registry line ${lineno} skipped: credential_source must be keychain:<service> or file:<abs path>"
      continue
      ;;
  esac
  dup=0
  for _seen in ${LABELS[@]+"${LABELS[@]}"}; do
    [[ "$_seen" == "$label" ]] && dup=1
  done
  if (( dup )); then
    warn "WARN: registry line ${lineno} skipped: duplicate label (first wins)"
    continue
  fi
  # Identity is derived from the credential's OWN JSON, never the label --
  # a re-logged-in slot can silently start serving a different account.
  id_line="$(derive_identity "$cred")"
  IFS=$'\t' read -r id_sub id_email id_exp <<<"$id_line"
  id_sub="${id_sub:-unknown}"; id_email="${id_email:-na}"
  identity="${id_sub}/${id_email}"
  if [[ -n "$id_exp" ]] && [[ "$id_exp" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    now_ms=$(( $(date +%s) * 1000 ))
    id_exp_i="${id_exp%%.*}"
    if (( id_exp_i <= now_ms )); then
      warn "WARN: registry line ${lineno} skipped: token_expired label=${label} identity=${identity}"
      expired_count=$((expired_count + 1))
      continue
    fi
  fi
  LABELS+=("$label"); DIRS+=("$config_dir"); SOURCES+=("$cred"); IDENTITIES+=("$identity")
done < "$REGISTRY"

# <2 valid entries => multi-profile is inert; caller keeps its inherited
# CLAUDE_CONFIG_DIR (single-profile fallback preserved). But if every entry
# that would otherwise have been a candidate was excluded specifically for
# being expired, that is not "just run single-profile" -- it means the one
# live credential this lane would have picked is dead, so refuse by name
# instead of silently falling back onto a possibly-also-dead inherited one.
n=${#LABELS[@]}
if (( n == 0 )) && (( ${expired_count:-0} > 0 )); then
  refuse_all_expired
fi
(( n >= 2 )) || single_profile
[[ -r "$PROBE" ]] || single_profile
[[ -r "$PICK" ]] || single_profile

# --- independent probes, bounded by one TOTAL budget -------------------------
# Each profile is probed in its own subprocess with its own cache dir and (for
# keychain sources) its own service pin, so one profile's hang, crash, or
# cache corruption can never affect another.  A probe that never completed
# (killed by the budget) is recorded as '-' — distinct from a probe that
# completed and reported unknown, because "no profile completed at all" is the
# single_profile fail-open of T8, while "completed but unknown" is the
# all_unknown pick of T6.
recs="$(mktemp "${TMPDIR:-/tmp}/claude-profile-recs.XXXXXX")" || single_profile
deadline=$(( $(date +%s) + timeout_s ))
completed=0
i=0
while (( i < n )); do
  label="${LABELS[$i]}"; dir="${DIRS[$i]}"; cred="${SOURCES[$i]}"; identity="${IDENTITIES[$i]}"
  i=$((i + 1))
  # Quota bucket keying is by IDENTITY, not by the operator-chosen label --
  # two labels resolving to the same real account must share one quota
  # bucket, and a relabeled slot must never inherit a stale bucket's cache.
  id_key="$(printf '%s' "$identity" | tr -c 'A-Za-z0-9_-' '_')"
  remaining=$(( deadline - $(date +%s) ))
  if (( remaining < 1 )); then
    warn "WARN: profile probe budget exhausted; unprobed entries score unknown"
    printf '%s\t%s\t%s\t-\t%s\n' "$label" "$dir" "$cred" "$identity" >> "$recs"
    continue
  fi
  out="$(mktemp "${TMPDIR:-/tmp}/claude-profile-probe.XXXXXX")"
  if [[ -z "$out" ]]; then
    printf '%s\t%s\t%s\t-\t%s\n' "$label" "$dir" "$cred" "$identity" >> "$recs"
    continue
  fi
  err="${out}.err"
  # Portable bounded subprocess (leadv2-provider-quota-gate.sh pattern).
  # LEADV2_CLAUDE_PROFILE_LABEL is passed through for fixture/observability
  # use only (a hermetic test probe stub may key its canned response off it);
  # the real quota-read.py probe does not read it and scoring never uses it —
  # the cache dir below is the only thing that determines the quota bucket.
  if [[ "$cred" == keychain:* ]]; then
    env "LEADV2_QUOTA_CACHE_DIR=${CACHE_BASE}/identity-${id_key}" \
        "LEADV2_ANTHROPIC_ACTIVE_SERVICE=${cred#keychain:}" \
        "LEADV2_CLAUDE_PROFILE_LABEL=${label}" \
        python3 "$PROBE" anthropic --no-cache >"$out" 2>"$err" &
  else
    env "LEADV2_QUOTA_CACHE_DIR=${CACHE_BASE}/identity-${id_key}" \
        "LEADV2_CLAUDE_PROFILE_LABEL=${label}" \
        python3 "$PROBE" anthropic --no-cache --credential-file "${cred#file:}" \
        >"$out" 2>"$err" &
  fi
  pid=$!; elapsed=0
  while kill -0 "$pid" 2>/dev/null && (( elapsed < remaining * 10 )); do sleep 0.1; elapsed=$((elapsed + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; rc=124
  else
    wait "$pid" 2>/dev/null; rc=$?
  fi
  json="$(cat "$out" 2>/dev/null)"; rm -f "$out" "$err"
  if [[ "$rc" -ne 0 || -z "$json" ]]; then
    printf '%s\t%s\t%s\t-\t%s\n' "$label" "$dir" "$cred" "$identity" >> "$recs"
    continue
  fi
  completed=$((completed + 1))
  b64="$(printf '%s' "$json" | base64 | tr -d '\n')"
  printf '%s\t%s\t%s\t%s\t%s\n' "$label" "$dir" "$cred" "$b64" "$identity" >> "$recs"
done

# Every probe hung/crashed => no signal at all => single_profile (T8), not a
# blind all_unknown pick that would still pin a config_dir on zero evidence.
if (( completed == 0 )); then
  rm -f "$recs"
  single_profile
fi
result="$(python3 "$PICK" < "$recs" 2>/dev/null)" || result=""
rm -f "$recs"
if [[ -z "$result" ]]; then single_profile; fi
printf '%s\n' "$result"
exit 0
