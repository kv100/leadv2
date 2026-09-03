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
  LEADV2_RP_KV="$KV_JSON" LEADV2_RP_RAW="$RAW_JSON" LEADV2_RP_EPOCH="$NOW_EPOCH" python3 - "$BURN_DB" <<'PYEOF' || true
import datetime, json, os, sqlite3, sys

HISTORY_COLS = [
    "captured_epoch", "account_key", "account_label", "is_active", "state", "status",
    "overage_status", "five_hour_pct", "five_hour_reset_iso", "five_hour_reset_epoch",
    "seven_day_pct", "seven_day_reset_iso", "seven_day_reset_epoch", "binding_window", "source",
]

# QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01 D3/D4: history is a per-account
# append-only log, keyed on account_key (a stable keychain-entry discriminator,
# NEVER the tier-derived account_label -- see leadv2-quota-read.py
# account_label()). kv above stays byte-identical: this block only ADDS a
# side-write into rate_limit_history, in the SAME transaction/connection.
RETAIN_DAYS = int(os.environ.get("LEADV2_RATELIMIT_HISTORY_RETAIN_DAYS", "180") or "180")
HEARTBEAT_S = int(os.environ.get("LEADV2_RATELIMIT_HISTORY_HEARTBEAT_S", "900") or "900")


def _iso_to_epoch(iso):
    # Precomputed here because the hot path is bash on macOS: `date -d` is
    # GNU-only (see repo CLAUDE.md). Malformed/absent -> None, never 0/now.
    if not iso or not isinstance(iso, str):
        return None
    try:
        return int(datetime.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp())
    except Exception:
        return None


def _accounts_from_raw(raw):
    try:
        d = json.loads(raw)
    except Exception:
        return []
    if d.get("status") != "ok":
        return []
    return d.get("accounts") or []


def _account_row(acct, epoch):
    suffix = acct.get("entry_suffix") or ""
    service = acct.get("service") or ""
    account_key = suffix or service or "unknown"
    status = acct.get("status")
    five = acct.get("five_hour") or {}
    week = acct.get("seven_day") or {}
    five_iso = five.get("reset_iso")
    week_iso = week.get("reset_iso")
    return {
        "captured_epoch": epoch,
        "account_key": account_key,
        "account_label": acct.get("account_label"),
        "is_active": 1 if acct.get("active") else 0,
        "state": "ok" if status == "ok" else "unauthenticated",
        "status": status,
        "overage_status": "normal" if status == "ok" else None,
        "five_hour_pct": five.get("pct"),
        "five_hour_reset_iso": five_iso,
        "five_hour_reset_epoch": _iso_to_epoch(five_iso),
        "seven_day_pct": week.get("pct"),
        "seven_day_reset_iso": week_iso,
        "seven_day_reset_epoch": _iso_to_epoch(week_iso),
        "binding_window": acct.get("binding_window"),
        "source": "ratelimit-probe",
    }


def _should_append(prev, row):
    if prev is None:
        return True
    if row["captured_epoch"] - prev["captured_epoch"] >= HEARTBEAT_S:
        return True
    for field in ("state", "binding_window", "account_label", "five_hour_pct", "seven_day_pct"):
        if prev.get(field) != row.get(field):
            return True
    return False


def _insert_row(conn, row):
    placeholders = ",".join(["?"] * len(HISTORY_COLS))
    conn.execute(
        "INSERT INTO rate_limit_history (%s) VALUES (%s)" % (",".join(HISTORY_COLS), placeholders),
        tuple(row[c] for c in HISTORY_COLS),
    )


def _prune_history(conn, retain_days):
    cutoff = epoch - retain_days * 86400
    conn.execute("DELETE FROM rate_limit_history WHERE captured_epoch < ?", (cutoff,))


def _append_history(conn, row, retain_days):
    key = row['account_key']
    prow = conn.execute(
        "SELECT %s FROM rate_limit_history WHERE account_key=? "
        "ORDER BY captured_epoch DESC, id DESC LIMIT 1" % ",".join(HISTORY_COLS),
        (key,),
    ).fetchone()
    prev = dict(zip(HISTORY_COLS, prow)) if prow is not None else None
    should = _should_append(prev, row)
    if should:
        _insert_row(conn, row)
    _prune_history(conn, retain_days)


def _seed_from_kv(conn, epoch):
    # D7: seed the ONE pre-existing kv row into history, before the kv upsert
    # below overwrites it -- else we would just copy the row we're about to
    # write. Idempotent: only fires while rate_limit_history is empty.
    if conn.execute("SELECT 1 FROM rate_limit_history LIMIT 1").fetchone() is not None:
        return
    kv_row = conn.execute("SELECT value FROM kv WHERE key='rate_limit_anthropic'").fetchone()
    if kv_row is None:
        return
    try:
        blob = json.loads(kv_row[0])
    except Exception:
        return
    if blob.get("status") != "ok" or not isinstance(blob.get("captured_epoch"), int):
        return
    five_iso = blob.get("five_hour_reset_iso")
    week_iso = blob.get("seven_day_reset_iso")
    seed_row = {
        "captured_epoch": blob["captured_epoch"],
        "account_key": "unknown",
        "account_label": blob.get("account_label"),
        "is_active": 1,
        "state": "ok",
        "status": blob.get("status"),
        "overage_status": blob.get("overageStatus"),
        "five_hour_pct": blob.get("five_hour_pct"),
        "five_hour_reset_iso": five_iso,
        "five_hour_reset_epoch": _iso_to_epoch(five_iso),
        "seven_day_pct": blob.get("seven_day_pct"),
        "seven_day_reset_iso": week_iso,
        "seven_day_reset_epoch": _iso_to_epoch(week_iso),
        "binding_window": blob.get("binding_window"),
        "source": "seed:kv",
    }
    _insert_row(conn, seed_row)


db_path = sys.argv[1]
kv = os.environ["LEADV2_RP_KV"]
raw = os.environ.get("LEADV2_RP_RAW", "")
epoch = int(os.environ.get("LEADV2_RP_EPOCH", "0") or "0")
accounts = _accounts_from_raw(raw)
per_account_rows = [_account_row(a, epoch) for a in accounts]

conn = sqlite3.connect(db_path, timeout=5)
try:
    conn.execute("PRAGMA busy_timeout=3000")
    conn.execute("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT)")
    conn.execute(
        "CREATE TABLE IF NOT EXISTS rate_limit_history ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "captured_epoch INTEGER NOT NULL,"
        "account_key TEXT NOT NULL,"
        "account_label TEXT,"
        "is_active INTEGER NOT NULL DEFAULT 0,"
        "state TEXT,"
        "status TEXT,"
        "overage_status TEXT,"
        "five_hour_pct REAL,"
        "five_hour_reset_iso TEXT,"
        "five_hour_reset_epoch INTEGER,"
        "seven_day_pct REAL,"
        "seven_day_reset_iso TEXT,"
        "seven_day_reset_epoch INTEGER,"
        "binding_window TEXT,"
        "source TEXT)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS rate_limit_history_acct "
        "ON rate_limit_history(account_key, captured_epoch DESC)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS rate_limit_history_epoch "
        "ON rate_limit_history(captured_epoch)"
    )
    conn.execute("BEGIN IMMEDIATE")
    _seed_from_kv(conn, epoch)
    conn.execute("INSERT OR REPLACE INTO kv (key, value) VALUES ('rate_limit_anthropic', ?)", (kv,))
    for row in per_account_rows:
        _append_history(conn, row, RETAIN_DAYS)
    conn.commit()
finally:
    conn.close()
PYEOF
fi

printf '%s\n' "$KV_JSON"
