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
#
# Registry format (TSV, blank lines and #-comments ignored):
#   label<TAB>config_dir<TAB>credential_source(optional)
#   credential_source: keychain:<service> | file:<abs path>
#   absent -> file:<config_dir>/.credentials.json
#   label: ^[a-z0-9][a-z0-9_-]{0,31}$ ('@'/'.', i.e. emails, are a hard reject)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${LEADV2_CLAUDE_PROFILES_FILE:-$HOME/.claude/state/leadv2/claude-profiles.tsv}"
PROBE="${LEADV2_CLAUDE_PROFILE_PROBE:-$SCRIPT_DIR/leadv2-quota-read.py}"
PICK="$SCRIPT_DIR/lib/leadv2-claude-profile-pick.py"
CACHE_BASE="${LEADV2_QUOTA_CACHE_DIR:-$HOME/.claude/state/leadv2/quota-cache}"

warn() { printf '[claude-profile-select] %s\n' "$*" >&2; }
single_profile() { printf 'profile=- reason=single_profile\n'; exit 0; }

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
  LABELS+=("$label"); DIRS+=("$config_dir"); SOURCES+=("$cred")
done < "$REGISTRY"

# <2 valid entries => multi-profile is inert; caller keeps its inherited
# CLAUDE_CONFIG_DIR (single-profile fallback preserved).
n=${#LABELS[@]}
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
  label="${LABELS[$i]}"; dir="${DIRS[$i]}"; cred="${SOURCES[$i]}"
  i=$((i + 1))
  remaining=$(( deadline - $(date +%s) ))
  if (( remaining < 1 )); then
    warn "WARN: profile probe budget exhausted; unprobed entries score unknown"
    printf '%s\t%s\t%s\t-\n' "$label" "$dir" "$cred" >> "$recs"
    continue
  fi
  out="$(mktemp "${TMPDIR:-/tmp}/claude-profile-probe.XXXXXX")"
  if [[ -z "$out" ]]; then
    printf '%s\t%s\t%s\t-\n' "$label" "$dir" "$cred" >> "$recs"
    continue
  fi
  err="${out}.err"
  # Portable bounded subprocess (leadv2-provider-quota-gate.sh pattern).
  if [[ "$cred" == keychain:* ]]; then
    env "LEADV2_QUOTA_CACHE_DIR=${CACHE_BASE}/profile-${label}" \
        "LEADV2_ANTHROPIC_ACTIVE_SERVICE=${cred#keychain:}" \
        python3 "$PROBE" anthropic --no-cache >"$out" 2>"$err" &
  else
    env "LEADV2_QUOTA_CACHE_DIR=${CACHE_BASE}/profile-${label}" \
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
    printf '%s\t%s\t%s\t-\n' "$label" "$dir" "$cred" >> "$recs"
    continue
  fi
  completed=$((completed + 1))
  b64="$(printf '%s' "$json" | base64 | tr -d '\n')"
  printf '%s\t%s\t%s\t%s\n' "$label" "$dir" "$cred" "$b64" >> "$recs"
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
