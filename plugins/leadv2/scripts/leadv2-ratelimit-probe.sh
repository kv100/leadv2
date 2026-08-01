#!/usr/bin/env bash
# leadv2-ratelimit-probe.sh — SWIFTBAR-LIVE-01 real Anthropic rate-limit numbers.
#
# Deviation from the original one-shot-header-probe design (documented in
# developer.full.md): leadv2-quota-live.sh + leadv2-quota-read.py ALREADY
# implement a multi-account-aware, keychain-resolving, cached live Anthropic
# quota reader (5h% + 7-day% + reset times, per-account). Re-implementing a
# second independent token resolver + raw /v1/messages probe here would
# duplicate credential-handling logic and create a second place that can leak
# a token. This script is a thin adapter: it forces a fresh read through the
# EXISTING reader and writes the burn-DB kv row leadv2-limits-refresh.sh (and
# the renderer) expects, in a superset shape that keeps the two pre-existing
# consumers of the same kv key working:
#   - leadv2-quota-read.py _anthropic_kv() treats the value as an opaque
#     fallback blob (any shape is fine).
#   - leadv2-quota-status.sh reads `status` / `overageStatus` / `resetsAt` /
#     `captured_epoch` as a best-effort secondary signal (absent -> it already
#     degrades to "unmeasured", never crashes).
# This write ADDS fields, never removes/renames the ones above.
#
# Never prints/logs/persists a token anywhere -- the token itself never
# leaves leadv2-quota-read.py's process memory (see its own header).
#
# Usage: leadv2-ratelimit-probe.sh   (no args; always forces --no-cache)
# Env:
#   LEADV2_BURN_DB       default: ~/.claude/burn/history.db
#   LEADV2_QUOTA_LIVE_SH override path to leadv2-quota-live.sh (tests)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUOTA_LIVE="${LEADV2_QUOTA_LIVE_SH:-${SCRIPT_DIR}/leadv2-quota-live.sh}"
BURN_DB="${LEADV2_BURN_DB:-${HOME}/.claude/burn/history.db}"

NOW_EPOCH="${LEADV2_RATELIMIT_PROBE_NOW:-$(date +%s)}"

RAW_JSON=""
if [ -x "$QUOTA_LIVE" ]; then
  RAW_JSON="$(bash "$QUOTA_LIVE" --no-cache anthropic 2>/dev/null || true)"
fi

# Build the kv row entirely in python (safe json handling, no shell string
# interpolation of provider-supplied content).
KV_JSON="$(LEADV2_RP_RAW="$RAW_JSON" LEADV2_RP_EPOCH="$NOW_EPOCH" python3 <<'PYEOF'
import json, os, sys

raw = os.environ.get("LEADV2_RP_RAW", "")
epoch = int(os.environ.get("LEADV2_RP_EPOCH", "0") or "0")

def unauth(detail):
    return {
        "status": "unknown", "state": "unauthenticated", "detail": detail,
        "captured_epoch": epoch, "source": "ratelimit-probe",
    }

if not raw.strip():
    print(json.dumps(unauth("leadv2-quota-live.sh produced no output (missing or crashed)")))
    sys.exit(0)

try:
    d = json.loads(raw)
except Exception:
    print(json.dumps(unauth("leadv2-quota-live.sh output was not valid JSON")))
    sys.exit(0)

status = d.get("status", "unknown")
if status != "ok":
    err = d.get("error") or d.get("note") or "no active Anthropic account resolved"
    out = unauth(str(err)[:200])
    kv = d.get("rate_limit_info_captured")
    if kv:
        out["rate_limit_info_captured"] = kv
    print(json.dumps(out))
    sys.exit(0)

accounts = d.get("accounts") or []
active = next((a for a in accounts if a.get("active")), (accounts[0] if accounts else None))
if not active or active.get("status") != "ok":
    print(json.dumps(unauth("resolved account has no usable quota data")))
    sys.exit(0)

five = active.get("five_hour") or {}
week = active.get("seven_day") or {}
out = {
    "status": "ok",
    "state": "ok",
    "overageStatus": "normal",
    "resetsAt": week.get("reset_iso") or five.get("reset_iso"),
    "captured_epoch": epoch,
    "source": "ratelimit-probe",
    "account_label": active.get("account_label"),
    "five_hour_pct": five.get("pct"),
    "five_hour_reset_iso": five.get("reset_iso"),
    "seven_day_pct": week.get("pct"),
    "seven_day_reset_iso": week.get("reset_iso"),
    "binding_window": active.get("binding_window"),
}
print(json.dumps(out))
PYEOF
)"

if [ -z "$KV_JSON" ]; then
  KV_JSON="$(printf '{"status":"unknown","state":"unreachable","detail":"probe adapter produced no JSON","captured_epoch":%s,"source":"ratelimit-probe"}' "$NOW_EPOCH")"
fi

if command -v sqlite3 >/dev/null 2>&1; then
  mkdir -p "$(dirname "$BURN_DB")" 2>/dev/null || true
  LEADV2_RP_KV="$KV_JSON" python3 - "$BURN_DB" <<'PYEOF' || true
import os, sqlite3, sys

db_path = sys.argv[1]
kv = os.environ["LEADV2_RP_KV"]
conn = sqlite3.connect(db_path, timeout=5)
try:
    conn.execute("PRAGMA busy_timeout=3000")
    conn.execute("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT)")
    conn.execute("BEGIN IMMEDIATE")
    conn.execute("INSERT OR REPLACE INTO kv (key, value) VALUES ('rate_limit_anthropic', ?)", (kv,))
    conn.commit()
finally:
    conn.close()
PYEOF
fi

printf '%s\n' "$KV_JSON"
