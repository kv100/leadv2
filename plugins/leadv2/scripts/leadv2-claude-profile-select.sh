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
#   LEADV2_CLAUDE_PROFILE_JOURNAL   optional journal file: every WARN line is
#                                   appended there ISO-prefixed, best-effort
#                                   (the caller points it at the handoff
#                                   claude-profile.log, since it drops the
#                                   selector's stderr by contract)
#   LEADV2_CLAUDE_PROFILE_DEFAULT_DIR  override for the inherited/default
#                                   config dir whose token health is warned
#                                   about (hermetic tests; default
#                                   ${CLAUDE_CONFIG_DIR:-$HOME/.claude})
#
# Registry format (TSV, blank lines and #-comments ignored):
#   label<TAB>config_dir<TAB>credential_source(optional)<TAB>expect(optional)
#   credential_source: keychain:<service> | file:<abs path>
#   absent -> file:<config_dir>/.credentials.json
#   expect: the identity the operator believes the slot serves -- "<sub>" or
#           "<sub>/<email>".  When the credential-derived identity differs,
#           WARN label_mismatch fires (fail-open: bucketing still keys on the
#           DERIVED identity, never on the label or the expectation).
#   label: ^[a-z0-9][a-z0-9_-]{0,31}$ ('@'/'.', i.e. emails, are a hard reject)
#
# T12 (CLAUDE-PROFILE-SELECT-FINISH-01 + LEAD-FINAL-FIXES-01): the registry
# LABEL is display-only and operator-chosen -- it can drift from what the
# credential actually is (2026-08-26: label said team/max_5x, both slots
# were actually one personal max_20x account, so team usage landed in the
# personal bucket).  So at selection time this script reads each slot's OWN
# JSON (never the label) and derives an `identity=<subscriptionType>/<email>`
# that is what actually gets scored, cached, and reported -- the label never
# drives quota bucketing.  Identity sources (verified live 2026-08-27):
# email comes from <config_dir>/.claude.json oauthAccount.emailAddress (the
# account the slot is logged into; it carries NO subscriptionType), while
# subscriptionType/expiresAt come from the credential's claudeAiOauth
# (which carries NO email) -- the two are merged.
# Loud fail-open warns (journal + stderr; selection never blocked):
#   same_account      two slots resolve to ONE real account (the incident)
#   label_mismatch    derived identity differs from the `expect` column
#   identity_email_unresolved  no readable .claude.json -> email unverifiable
#   default_token_unrefreshable / default_token_absent  the inherited slot's
#                      credential is dead/missing (the lane runs on it
#                      whenever the selector fails open)
#
# CLAUDE-PROFILE-DEFAULT-TOKEN-EXPIRED-01 (corrected contract) -- two
# independent bugs previously made this warn fire ~207 times on healthy
# credentials:
#   (A) wrong record: the CLI does not write the legacy unsuffixed
#       "Claude Code-credentials" keychain service for a live default config
#       dir -- it writes "Claude Code-credentials-<sha256(config_dir)[:8]>"
#       (see keychain_service_for_dir()).  The unsuffixed service is a stale
#       fallback, checked LAST now, never first.
#   (B) wrong predicate: `claudeAiOauth.expiresAt` is the ACCESS-token expiry
#       (~8h rolling) -- it is legitimately in the past very often and is NOT
#       a liveness signal on its own.  The only proof a slot is dead is its
#       REFRESH window: `refreshToken` absent, or `refreshTokenExpiresAt`
#       (~3wk horizon) already past.  See credential_health().
# A slot is flagged `WARN token_unrefreshable` / `default_token_unrefreshable`
# and excluded from candidate scoring ONLY when credential_health() returns 1
# (unrefreshable); if that leaves zero live candidates, the selector refuses
# outright (reason=all_expired, stdout token unchanged for the caller) rather
# than silently picking a dead credential.  An expired access token with a
# still-live (or unrecorded) refresh window is normal steady state and is
# silent -- not even an info line.  Only parsed metadata
# (subscriptionType/email/expiresAt/refreshTokenExpiresAt/has_refresh) ever
# leaves derive_identity() -- the raw credential JSON (which carries
# accessToken/refreshToken) and the tokens themselves are never printed,
# logged, or journalled.
# M1 (fix-round 2026-08-27) bucket-key migration: a slot whose email half is
# unresolved (`<sub>/na`) now keys its quota cache on the config_dir instead
# of the shared `<sub>_na` identity -- old shared bucket dirs are abandoned
# (each slot's new dir-cache repopulates with one cold read; no migration).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${LEADV2_CLAUDE_PROFILES_FILE:-$HOME/.claude/state/leadv2/claude-profiles.tsv}"
PROBE="${LEADV2_CLAUDE_PROFILE_PROBE:-$SCRIPT_DIR/leadv2-quota-read.py}"
PICK="$SCRIPT_DIR/lib/leadv2-claude-profile-pick.py"
CACHE_BASE="${LEADV2_QUOTA_CACHE_DIR:-$HOME/.claude/state/leadv2/quota-cache}"
SECURITY_BIN="${LEADV2_CLAUDE_PROFILE_SECURITY_BIN:-security}"

warn() {
  printf '[claude-profile-select] %s\n' "$*" >&2
  if [[ -n "${LEADV2_CLAUDE_PROFILE_JOURNAL:-}" ]]; then
    printf '%s [claude-profile-select] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" \
      >> "$LEADV2_CLAUDE_PROFILE_JOURNAL" 2>/dev/null || true
  fi
}
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

# keychain_service_for_dir <config_dir> -> "Claude Code-credentials-<8hex>"
# <8hex> = sha256(config_dir)[:8], the live per-config-dir keychain service
# name the CLI actually writes (verified: sha256("$HOME/.claude")[:8] ==
# eb6c5b97, sha256("$HOME/.claude-work")[:8] == 5a3c2328 -- Defect A).
# Hashed via python3 (already a hard dependency of derive_identity) -- no
# shasum/sha256sum, bash-3.2 safe.
keychain_service_for_dir() {
  python3 -c 'import hashlib, sys; print("Claude Code-credentials-" + hashlib.sha256(sys.argv[1].encode()).hexdigest()[:8])' "$1"
}

# derive_identity <config_dir> <credential_source>
#   -> "<sub>\t<email>\t<expiresAt|->\t<refreshTokenExpiresAt|->\t<has_refresh:0|1>\t<cj_ok>\t<cred_ok>"
# Email from <config_dir>/.claude.json oauthAccount.emailAddress, sub/expiry/
# refresh fields from the credential's claudeAiOauth (see header: the sources
# are complementary live shapes). Tab is IFS-whitespace, so empty numeric
# fields use the '-' sentinel to survive `IFS=$'\t' read` collapsing.
# has_refresh is a BOOLEAN only -- the refreshToken value itself is never
# emitted, printed, or journalled.
derive_identity() {
  read_cred_json "$2" | CJ_PATH="${1}/.claude.json" python3 -c '
import json, os, sys
def _load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None
cj = _load(os.environ.get("CJ_PATH", ""))
try:
    cred = json.load(sys.stdin)
except Exception:
    cred = None
oa = (cj or {}).get("oauthAccount") or {}
co = (cred or {}).get("claudeAiOauth") or {}
sub = co.get("subscriptionType") or "unknown"
email = oa.get("emailAddress") or co.get("email") or co.get("emailAddress") or "na"
ea = co.get("expiresAt")
ea = ea if isinstance(ea, (int, float)) else "-"
rte = co.get("refreshTokenExpiresAt")
rte = rte if isinstance(rte, (int, float)) else "-"
has_refresh = 1 if co.get("refreshToken") else 0
print("%s\t%s\t%s\t%s\t%d\t%d\t%d" % (sub, email, ea, rte, has_refresh, 1 if cj else 0, 1 if cred else 0))
' 2>/dev/null
}

# credential_health <expiresAt|-> <refreshTokenExpiresAt|-> <has_refresh:0|1> <cred_ok:0|1>
#   -> return 0 = refreshable, 1 = unrefreshable, 2 = unreadable
# Honest predicate (Defect B fix): `expiresAt` (the access-token expiry, ~8h
# rolling) is NEVER consulted here -- it is legitimately in the past often
# and proves nothing about liveness.  The only proof a slot is dead is its
# REFRESH window: no refreshToken at all, or a refreshTokenExpiresAt that has
# already passed.  A record with a live refreshToken but no
# refreshTokenExpiresAt field is NOT provably dead -- absence of the expiry
# is not evidence of expiry, so it returns refreshable (0).
credential_health() {
  local exp="$1" rexp="$2" has_refresh="$3" cred_ok="$4"
  local now_ms
  now_ms=$(( $(date +%s) * 1000 ))
  if [[ "$cred_ok" != "1" ]]; then return 2; fi
  if [[ "$has_refresh" != "1" ]]; then return 1; fi
  if [[ "$rexp" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( ${rexp%%.*} <= now_ms )); then return 1; fi
  return 0
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

# --- default (inherited) slot health ----------------------------------------
# Whenever this selector fails open, the lane runs on the inherited config
# dir, so a dead default credential is worth shouting about even though it
# changes nothing here (availability > purity).  Resolution order (Defect A
# fix): on-disk credential first, then the LIVE per-config-dir suffixed
# keychain service, then the legacy unsuffixed service as a last resort only
# (frozen since 2026-08-25 -- never the first record consulted).  Both
# keychain attempts are guarded by `command -v "$SECURITY_BIN"` so a
# keychain-less host (e.g. a Linux container, where the on-disk credential
# normally resolves on the very first attempt) costs zero failed execs.
default_dir="${LEADV2_CLAUDE_PROFILE_DEFAULT_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
def_line="$(derive_identity "$default_dir" "file:${default_dir}/.credentials.json")"
IFS=$'\t' read -r d_sub d_email d_exp d_rexp d_has_refresh d_cj d_cred <<<"$def_line"
if [[ "$d_cred" != "1" ]] && command -v "$SECURITY_BIN" >/dev/null 2>&1; then
  def_line="$(derive_identity "$default_dir" "keychain:$(keychain_service_for_dir "$default_dir")")"
  IFS=$'\t' read -r d_sub d_email d_exp d_rexp d_has_refresh d_cj d_cred <<<"$def_line"
fi
if [[ "$d_cred" != "1" ]] && command -v "$SECURITY_BIN" >/dev/null 2>&1; then
  def_line="$(derive_identity "$default_dir" "keychain:Claude Code-credentials")"
  IFS=$'\t' read -r d_sub d_email d_exp d_rexp d_has_refresh d_cj d_cred <<<"$def_line"
fi
if [[ "$d_cred" != "1" ]]; then
  warn "WARN: default_token_absent (inherited slot has no readable credential) -- fail-open"
else
  credential_health "$d_exp" "$d_rexp" "$d_has_refresh" "$d_cred"
  if [[ $? -eq 1 ]]; then
    # Coupling note (2026-09-03, lead cross-lane with TWO-SLOTS-COLLAPSE-INTO-
    # ONE-ACCOUNT-01): a bare `claude /login` rewrites whichever config dir
    # CLAUDE_CONFIG_DIR happens to point at right now, not necessarily this
    # dead slot's dir -- that mistargeted re-login is the PLAUSIBLE (not
    # proven) precursor to the two same-account collapses that lane found.
    # The remedy string below embeds the dir so it cannot be copy-pasted
    # without it.
    warn "WARN: default_token_unrefreshable identity=${d_sub}/${d_email} dir=${default_dir} -- fail-open -- repair (this slot only): CLAUDE_CONFIG_DIR=${default_dir} claude /login -- never a bare 'claude /login', it can silently repair the WRONG config dir"
  fi
fi

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
while IFS=$'\t' read -r label config_dir cred expect || [[ -n "${label:-}" ]]; do
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
  # Identity is derived from the slot's OWN JSON (.claude.json for the email,
  # the credential for sub/expiry), never from the label -- a re-logged-in
  # slot can silently start serving a different account.
  id_line="$(derive_identity "$config_dir" "$cred")"
  IFS=$'\t' read -r id_sub id_email id_exp id_rexp id_has_refresh id_cj id_cred <<<"$id_line"
  id_sub="${id_sub:-unknown}"; id_email="${id_email:-na}"
  identity="${id_sub}/${id_email}"
  if [[ "$id_cj" != "1" ]]; then
    # Missing/unreadable .claude.json: the email half of the identity cannot
    # be verified.  Warn and carry on -- the sub half still buckets correctly.
    warn "WARN: registry line ${lineno}: identity_email_unresolved (no readable .claude.json) label=${label} identity=${identity} -- fail-open"
  fi
  if [[ -n "${expect:-}" && "$expect" != "$identity" ]]; then
    warn "WARN: label_mismatch label=${label} expected=${expect} identity=${identity} -- bucketing by identity (fail-open)"
  fi
  credential_health "$id_exp" "$id_rexp" "$id_has_refresh" "$id_cred"
  if [[ $? -eq 1 ]]; then
    warn "WARN: registry line ${lineno} skipped: token_unrefreshable label=${label} identity=${identity}"
    expired_count=$((expired_count + 1))
    continue
  fi
  LABELS+=("$label"); DIRS+=("$config_dir"); SOURCES+=("$cred"); IDENTITIES+=("$identity")
done < "$REGISTRY"

# --- same-account detection (the 2026-08-26 incident shape) ------------------
# Two labels resolving to ONE real account means the registry lies about
# having two slots.  Warn loudly; both stay candidates and already share one
# identity-keyed quota bucket, so usage is counted once either way.
n=${#LABELS[@]}
_sa_i=0
while (( _sa_i < n )); do
  _sa_j=$(( _sa_i + 1 ))
  while (( _sa_j < n )); do
    if [[ "${IDENTITIES[$_sa_i]}" == "${IDENTITIES[$_sa_j]}" \
          && "${IDENTITIES[$_sa_i]}" != "unknown/na" \
          && "${IDENTITIES[$_sa_i]#*/}" != "na" ]]; then
      warn "WARN: same_account label=${LABELS[$_sa_i]} label=${LABELS[$_sa_j]} identity=${IDENTITIES[$_sa_i]} -- one real account behind two slots"
    fi
    _sa_j=$(( _sa_j + 1 ))
  done
  _sa_i=$(( _sa_i + 1 ))
done

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
  # An UNRESOLVED identity must not collapse every distinct slot into one
  # shared bucket either: fall back to the physical config_dir so each slot
  # keeps its own bucket until identity is restorable.  Fix-round C1
  # (2026-08-27): the fallback keys on ANY unresolved email half (`<sub>/na`),
  # not just the literal `unknown/na` -- two slots with a resolvable
  # subscriptionType but an unreadable .claude.json both derive e.g. `pro/na`
  # and would otherwise merge into ONE `pro_na` bucket, the exact incident
  # class this task exists to kill.
  if [[ "${identity#*/}" == "na" ]]; then
    id_key="$(printf '%s' "$dir" | tr -c 'A-Za-z0-9_-' '_')"
  else
    id_key="$(printf '%s' "$identity" | tr -c 'A-Za-z0-9_-' '_')"
  fi
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
