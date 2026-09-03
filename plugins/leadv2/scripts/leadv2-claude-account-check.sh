#!/usr/bin/env bash
# leadv2-claude-account-check.sh — TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01 §3
#
# On-demand confirmation that the Claude multi-profile registry's slots are
# TWO DISTINCT real accounts, not one account silently collapsed into two
# labels (the 2026-08-28 / 2026-08-31 incident: an interactive `claude
# /login` run while CLAUDE_CONFIG_DIR pointed at the wrong slot rewrote that
# slot's .claude.json + suffixed keychain record onto the other account).
#
# No args, no flags, no env required:
#   bash plugins/leadv2/scripts/leadv2-claude-account-check.sh
#
# Compares REAL account identity only -- never registry labels (a label is
# operator-chosen display text and is exactly what silently drifted in the
# incident). Per slot: oauthAccount.accountUuid (last 6), organizationUuid
# (last 6), the rate-limit tier (userRateLimitTier, falling back to
# organizationRateLimitTier -- this is what shows 20x vs 5x after 09-15),
# subscriptionType from the credential, and sha256(raw credential blob)[:12]
# as a digest PROVING the two slots hold physically different credentials.
# Never prints/logs a credential value, access token, or refresh token --
# labels, uuid tails, tier strings, and digests only.
#
# Env (mirrors the selector's registry conventions):
#   LEADV2_CLAUDE_PROFILES_FILE          registry path (hermetic tests)
#   LEADV2_CLAUDE_PROFILE_SECURITY_BIN   override for `security` (hermetic
#                                        tests / Linux container: absent bin
#                                        -> keychain-less fallback, never
#                                        exit 2 for that reason alone)
#
# Exit codes:
#   0  TWO_BUCKETS     -- distinct accountUuids (or unresolvable-but-distinct
#                         config dirs when a Linux container has no keychain)
#   1  ONE_BUCKET      -- two slots resolve to the SAME accountUuid
#   2  INDETERMINATE   -- a slot's .claude.json is unreadable (identity
#                         cannot be established at all for that slot)
#   3  ORG_COLLAPSE    -- two slots hold DISTINCT accountUuids but the SAME
#                         organizationUuid (fix-round-1 finding: rate limiting
#                         applies at the org level -- see organizationRateLimitTier
#                         fallback below -- so two seats in one org is the same
#                         failure class one level up from ONE_BUCKET). Never
#                         fires when organizationUuid is unresolved ("-") for
#                         either slot -- unresolved is unknown, never collapse,
#                         same fail-open discipline as the email half (T20d).
#
# Linux container, no keychain: guarded by `command -v "$SECURITY_BIN"`.
# With no keychain the credential source falls back to
# file:<dir>/.credentials.json; if that is absent too, sub/cred print `-`
# and creds reads unavailable(no-keychain) -- accountUuid (from .claude.json,
# present on Linux) remains the sufficient discriminator, so this alone can
# never force exit 2.
#
# bash 3.2: parallel indexed arrays only, no associative arrays, no mapfile,
# no ${var^^} -- mirrors the selector's existing registry-parse loop.
set -uo pipefail

REGISTRY="${LEADV2_CLAUDE_PROFILES_FILE:-$HOME/.claude/state/leadv2/claude-profiles.tsv}"
SECURITY_BIN="${LEADV2_CLAUDE_PROFILE_SECURITY_BIN:-security}"

read_cred_json() {
  case "$1" in
    keychain:*)
      command -v "$SECURITY_BIN" >/dev/null 2>&1 || return 1
      "$SECURITY_BIN" find-generic-password -s "${1#keychain:}" -w 2>/dev/null
      ;;
    file:*) cat "${1#file:}" 2>/dev/null ;;
    *) return 1 ;;
  esac
}

# derive <config_dir> <credential_source>
#  -> "<sub|->\t<account_uuid|->\t<org_uuid|->\t<tier|->\t<digest12|->\t<cj_ok>"
derive() {
  read_cred_json "$2" | CJ_PATH="${1}/.claude.json" python3 -c '
import hashlib, json, os, sys
def _load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None
cj = _load(os.environ.get("CJ_PATH", ""))
raw = sys.stdin.buffer.read()
try:
    cred = json.loads(raw) if raw else None
except Exception:
    cred = None
oa = (cj or {}).get("oauthAccount") or {}
co = (cred or {}).get("claudeAiOauth") or {}
sub = co.get("subscriptionType") or "-"
acct = oa.get("accountUuid") or ""
org = oa.get("organizationUuid") or ""
tier = oa.get("userRateLimitTier") or oa.get("organizationRateLimitTier") or "-"
digest = hashlib.sha256(raw).hexdigest()[:12] if raw else "-"
print("%s\t%s\t%s\t%s\t%s\t%d" % (sub, acct or "-", org or "-", tier, digest, 1 if cj else 0))
' 2>/dev/null
}

[[ -r "$REGISTRY" ]] || { printf 'VERDICT: INDETERMINATE reason=registry_unreadable\n' >&2; exit 2; }

LABELS=(); DIR_HASHES=(); SUBS=(); ACCOUNTS=(); ORGS=(); TIERS=(); DIGESTS=(); CJ_OKS=(); NO_KEYCHAIN=0
re_label='^[a-z0-9][a-z0-9_-]{0,31}$'
lineno=0
while IFS=$'\t' read -r label config_dir cred expect || [[ -n "${label:-}" ]]; do
  lineno=$((lineno + 1))
  [[ -z "${label//[$' \t\r']/}" ]] && continue
  case "$label" in '#'*) continue ;; esac
  [[ "$label" =~ $re_label ]] || continue
  [[ -n "$config_dir" && -d "$config_dir" && -r "$config_dir" ]] || continue
  [[ -z "$cred" ]] && cred="file:${config_dir}/.credentials.json"
  case "$cred" in keychain:?* ) ;; file:/* ) ;; * ) continue ;; esac
  if [[ "$cred" == keychain:* ]] && ! command -v "$SECURITY_BIN" >/dev/null 2>&1; then
    NO_KEYCHAIN=1
  fi
  line="$(derive "$config_dir" "$cred")"
  IFS=$'\t' read -r sub acct org tier digest cj_ok <<<"$line"
  dir_hash="$(printf '%s' "$config_dir" | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.read().encode()).hexdigest()[:8])')"
  LABELS+=("$label"); DIR_HASHES+=("$dir_hash"); SUBS+=("${sub:--}")
  ACCOUNTS+=("${acct:--}"); ORGS+=("${org:--}"); TIERS+=("${tier:--}")
  DIGESTS+=("${digest:--}"); CJ_OKS+=("${cj_ok:-0}")
done < "$REGISTRY"

n=${#LABELS[@]}
i=0
while (( i < n )); do
  if [[ "${CJ_OKS[$i]}" != "1" ]]; then
    printf 'VERDICT: INDETERMINATE reason=claude_json_unreadable slot=%s\n' "${LABELS[$i]}" >&2
    exit 2
  fi
  i=$((i + 1))
done

i=0
while (( i < n )); do
  acct_tail="-"
  [[ "${ACCOUNTS[$i]}" != "-" ]] && acct_tail="..${ACCOUNTS[$i]: -6}"
  org_tail="-"
  [[ "${ORGS[$i]}" != "-" ]] && org_tail="..${ORGS[$i]: -6}"
  cred_field="${DIGESTS[$i]}"
  (( NO_KEYCHAIN )) && [[ "${cred_field}" == "-" ]] && cred_field="unavailable(no-keychain)"
  printf 'slot=%s dir_hash=%s account=%s org=%s sub=%s tier=%s cred=%s\n' \
    "${LABELS[$i]}" "${DIR_HASHES[$i]}" "$acct_tail" "$org_tail" "${SUBS[$i]}" "${TIERS[$i]}" "$cred_field"
  i=$((i + 1))
done

# verdict(): the ONLY collapse/no-collapse decision point (NC2 target).
# Compares raw accountUuids pairwise -- the real-account discriminator,
# present in .claude.json on every platform including a keychain-less Linux
# container (§ header). A missing keychain never enters this comparison, so
# it can never by itself flip the verdict.
verdict() {
  local _v_i=0 _v_j
  while (( _v_i < n )); do
    _v_j=$(( _v_i + 1 ))
    while (( _v_j < n )); do
      if [[ "${ACCOUNTS[$_v_i]}" != "-" && "${ACCOUNTS[$_v_i]}" == "${ACCOUNTS[$_v_j]}" ]]; then
        acct_tail="..${ACCOUNTS[$_v_i]: -6}"
        printf 'VERDICT: ONE_BUCKET collapsed=[%s,%s] account=%s\n' "${LABELS[$_v_i]}" "${LABELS[$_v_j]}" "$acct_tail"
        return 1
      fi
      _v_j=$(( _v_j + 1 ))
    done
    _v_i=$(( _v_i + 1 ))
  done
  # Org-level collapse (fix-round-1, NC3 target): reached only once every
  # pairwise accountUuid comparison above came back distinct or unresolved --
  # so this loop asks a DIFFERENT question: do two distinct accounts sit
  # inside the SAME organizationUuid? Rate limiting for an org applies at the
  # org level (organizationRateLimitTier fallback above), so that is one
  # shared quota bucket wearing two account labels -- the failure class this
  # lane exists to catch, one level up from ONE_BUCKET. Skips the "-"
  # placeholder exactly like the account loop above: an unresolved org is
  # unknown, never a collapse (fail-open, mirrors T20d's discipline for the
  # email half) -- this is the sole reason ORG_COLLAPSE gets its own verdict
  # word instead of overloading ONE_BUCKET: the remedy for "same account" and
  # "different accounts, same org" differs, and the operator must be able to
  # tell them apart without reading code.
  _v_i=0
  while (( _v_i < n )); do
    _v_j=$(( _v_i + 1 ))
    while (( _v_j < n )); do
      if [[ "${ORGS[$_v_i]}" != "-" && "${ORGS[$_v_i]}" == "${ORGS[$_v_j]}" ]]; then
        org_tail="..${ORGS[$_v_i]: -6}"
        printf 'VERDICT: ORG_COLLAPSE collapsed=[%s,%s] org=%s\n' "${LABELS[$_v_i]}" "${LABELS[$_v_j]}" "$org_tail"
        return 3
      fi
      _v_j=$(( _v_j + 1 ))
    done
    _v_i=$(( _v_i + 1 ))
  done
  local distinct_accounts distinct_creds creds_out
  distinct_accounts="$(printf '%s\n' "${ACCOUNTS[@]}" | grep -v '^-$' | sort -u | wc -l | tr -d ' ')"
  if (( NO_KEYCHAIN )); then
    creds_out="unavailable(no-keychain)"
  else
    distinct_creds="$(printf '%s\n' "${DIGESTS[@]}" | grep -v '^-$' | sort -u | wc -l | tr -d ' ')"
    creds_out="$distinct_creds"
  fi
  printf 'VERDICT: TWO_BUCKETS accounts=%s creds=%s\n' "${distinct_accounts:-0}" "$creds_out"
  return 0
}

verdict
exit $?
