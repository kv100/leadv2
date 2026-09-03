#!/usr/bin/env bash
# Generic, fail-open quota admission gate.  Only a known numeric reading at or
# above a known numeric ceiling returns 1; telemetry and configuration faults
# deliberately allow the launch.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CEILINGS="${LEADV2_QUOTA_CEILINGS:-${SCRIPT_DIR}/../config/leadv2-quota-ceilings.sh}"
LIVE="${LEADV2_QUOTA_LIVE:-${SCRIPT_DIR}/leadv2-quota-live.sh}"
provider="${1:-}"; purpose="${2:-}"
warn() { printf '[provider-quota-gate] %s\n' "$*" >&2; }
usage() { warn "usage: $0 <glm|codex|claude> <build|review>"; }

case "$provider" in glm|codex|claude) ;; *) usage; exit 3;; esac
case "$purpose" in build|review) ;; *) usage; exit 3;; esac
if [[ "${LEADV2_PROVIDER_QUOTA_GATE:-1}" == 0 ]]; then warn 'WARN: gate disabled'; exit 0; fi
if [[ ! -r "$CEILINGS" ]]; then warn "FAIL-OPEN: ceilings file missing (${CEILINGS})"; exit 0; fi
# Do not use -e: a malformed sourced file must not brick dispatch.
source "$CEILINGS" 2>/dev/null || { warn 'FAIL-OPEN: ceilings file malformed'; exit 0; }
if ! declare -F leadv2_quota_ceiling >/dev/null 2>&1; then warn 'FAIL-OPEN: ceilings lookup unavailable'; exit 0; fi
ceil="$(leadv2_quota_ceiling "$provider" "$purpose" 2>/dev/null)" || { usage; exit 3; }
if ! [[ "$ceil" =~ ^[0-9]+$ ]]; then warn "FAIL-OPEN: malformed ceiling ${ceil:-empty}"; exit 0; fi
if (( ceil > 100 )); then warn "WARN: ceiling $ceil > 100, gate is inert"; fi
if [[ ! -x "$LIVE" && ! -f "$LIVE" ]]; then warn 'FAIL-OPEN: quota-live helper missing'; exit 0; fi

# Portable bounded subprocess: quota-live can touch a remote provider on cache miss.
out="$(mktemp "${TMPDIR:-/tmp}/provider-quota.XXXXXX")" || { warn 'FAIL-OPEN: temp unavailable'; exit 0; }
err="${out}.err"; timeout_s="${LEADV2_QUOTA_READ_TIMEOUT:-8}"
# QUOTA-GATE-PARITY-01 F4: the configured timeout is untrusted operator input.
# Accept a positive integer only; clamp to 1..60 so a typo can neither disable
# the poll loop (0/-5/"") nor stall every spawn behind the gate (86400).
if ! [[ "$timeout_s" =~ ^[0-9]+$ ]]; then
  warn "WARN: LEADV2_QUOTA_READ_TIMEOUT='${timeout_s}' is not a positive integer; using default 8s"
  timeout_s=8
fi
if (( timeout_s < 1 )); then warn "WARN: LEADV2_QUOTA_READ_TIMEOUT=${timeout_s} clamped to 1s"; timeout_s=1; fi
if (( timeout_s > 60 )); then warn "WARN: LEADV2_QUOTA_READ_TIMEOUT=${timeout_s} clamped to 60s"; timeout_s=60; fi
bash "$LIVE" "$([[ "$provider" == claude ]] && printf anthropic || printf '%s' "$provider")" >"$out" 2>"$err" &
pid=$!; elapsed=0
while kill -0 "$pid" 2>/dev/null && (( elapsed < timeout_s * 10 )); do sleep 0.1; elapsed=$((elapsed + 1)); done
if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; rc=124; else wait "$pid"; rc=$?; fi
json="$(cat "$out" 2>/dev/null)"; rm -f "$out" "$err"
if (( rc != 0 )) || [[ -z "$json" ]]; then warn "FAIL-OPEN: quota-live exited $rc"; exit 0; fi

# Stale cache is unknown, never a refusal.  A missing cache is allowed because
# quota-live may have obtained a fresh value without persisting it (test fakes).
cache_dir="${LEADV2_QUOTA_CACHE_DIR:-${HOME}/.claude/state/leadv2/quota-cache}"
cache_name="$provider"; [[ "$provider" == claude ]] && cache_name=anthropic
cache_file="${cache_dir}/${cache_name}.json"
ttl=120; [[ "$provider" == glm ]] && ttl="${LEADV2_QUOTA_TTL_GLM:-60}"; [[ "$provider" == codex ]] && ttl="${LEADV2_QUOTA_TTL_CODEX:-120}"; [[ "$provider" == claude ]] && ttl="${LEADV2_QUOTA_TTL_ANTHROPIC:-300}"
if [[ -f "$cache_file" ]] && [[ "$ttl" =~ ^[0-9]+$ ]]; then
  mtime="$(python3 -c 'import os,sys; print(int(os.path.getmtime(sys.argv[1])))' "$cache_file" 2>/dev/null || true)"
  now="$(date +%s)"
  if [[ "$mtime" =~ ^[0-9]+$ ]] && (( now - mtime > ttl * 2 )); then warn "FAIL-OPEN: ${provider} quota-cache stale (age=$((now-mtime))s ttl=${ttl}s)"; exit 0; fi
fi

parsed="$(printf '%s' "$json" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print("MALFORMED"); raise SystemExit
if not isinstance(d,dict) or d.get("status") != "ok": print("UNKNOWN"); raise SystemExit
p=sys.argv[1]
def num(x):
 try: return int(round(float(x)))
 except: return None
if p == "glm":
 vals=[num((d.get(k) or {}).get("pct")) for k in ("five_hour","weekly")]; vals=[x for x in vals if x is not None]
elif p == "codex":
 # Evidence (QUOTA-GATE-PARITY-01 §5): limit_reached is fetched verbatim from
 # the provider rate_limit.limit_reached field and is NOT derived from
 # used_percent (captured 2026-08-24T13:54Z from
 # ~/.claude/state/leadv2/quota-cache/codex.json, fetcher leadv2-quota-read.py:273-291:
 # status=ok, limit_reached=false, binding_window=primary, used_percent=4).
 # UNVERIFIED: a true limit_reached has never been observed alongside its
 # used_percent, so 100 below is a saturating block sentinel, not a measured
 # percentage. Safe in the refusal direction only, which is why the shell
 # short-circuits on source=limit_reached before the ceiling comparison.
 ws=d.get("windows") or []; bind=d.get("binding_window"); w=next((x for x in ws if x.get("kind")==bind), None)
 if isinstance(w,dict) and w.get("limit_reached") is True: print("100 limit_reached"); raise SystemExit
 if d.get("limit_reached") is True: print("100 limit_reached"); raise SystemExit
 vals=[num((w or {}).get("used_percent"))] if w else [num(x.get("used_percent")) for x in ws if isinstance(x,dict)]
 vals=[x for x in vals if x is not None]
else:
 ac=d.get("accounts") or []; active=next((x for x in ac if isinstance(x,dict) and x.get("active")), ac[0] if ac else None)
 vals=[num((active or {}).get(k)) for k in ("seven_day_pct","five_hour_pct")]; vals=[x for x in vals if x is not None]
if not vals: print("UNKNOWN")
else: print("%s pct" % max(vals))
' "$provider" 2>/dev/null)"
case "$parsed" in MALFORMED) warn "FAIL-OPEN: malformed ${provider} JSON"; exit 0;; UNKNOWN|"") warn "FAIL-OPEN: ${provider} quota read is unknown"; exit 0;; esac
pct="${parsed%% *}"; source="${parsed#* }"
# QUOTA-GATE-PARITY-01 §4a: a standalone block signal must not be routed
# through a numeric comparison it can lose -- with a >100 (inert) ceiling the
# synthesized pct=100 would be admitted. Refuse before comparing to the ceiling.
if [[ "$source" == "limit_reached" ]]; then
  warn 'LEADV2_DISPATCH_REFUSED: quota_gate'
  warn "REROUTE — ${provider} limit_reached=true (block sentinel pct=${pct}, supersedes ceiling=${ceil}) (${purpose}) source=${source}"
  exit 1
fi
if (( pct >= ceil )); then
  warn 'LEADV2_DISPATCH_REFUSED: quota_gate'
  warn "REROUTE — ${provider} ${pct}% >= ${ceil}% (${purpose}) source=${source}"
  exit 1
fi
printf '[provider-quota-gate] OK — %s %s%% < %s%%\n' "$provider" "$pct" "$ceil"
