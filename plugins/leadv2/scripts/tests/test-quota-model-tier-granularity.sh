#!/usr/bin/env bash
# tests/test-quota-model-tier-granularity.sh — W1-QUOTA-DAEMON-01 part A
#
# The quota reader published exactly three provider-aggregate utilization
# numbers (glm / codex / anthropic), so GLM's two models (glm-5.3 and
# glm-5.3-flash, different measured spend) shared ONE number and Codex's three
# tiers (volume/standard/top) shared one too. Live probes 2026-09-09 settled
# what the providers actually meter:
#   - z.ai: ONE pooled plan allowance; the quota endpoint ignores ?model= and
#     returns two account-level TOKENS_LIMIT windows (docs.z.ai/devpack/overview
#     confirms both models share the 5-hour + weekly limits). Per-model truth
#     is therefore an ATTRIBUTION of the pooled spend, measured from our own
#     burn turn_events (input+output) -- never a fabricated provider number.
#   - OpenAI: account-level metering with a single 168h window and NO 5h burst
#     window (CODEX-TIER-100-NO-BURST-WINDOW-01, founder 2026-09-06). Per-tier
#     keys carry the same REAL account window, named by its measured period.
#
# Hermetic (same technique as test-quota-read-anthropic-liveness.sh): http_json
# and the burn DB are monkeypatched/fixture'd, no network, no real keychain,
# LEADV2_QUOTA_DAEMON=0. Named tests:
#   T1 glm-models-distinct-attributed-utilization  <-- the mutation target:
#      collapsing the models back into one shared entry inside build_glm_models
#      MUST redden exactly this test (acceptance #4).
#   T2 glm-aggregate-key-backcompat                (acceptance #2, old key live)
#   T3 glm-model-keys-carry-real-window-periods
#   T4 codex-tiers-weekly-only-no-invented-five-hour (acceptance #3)
#   T5 codex-aggregate-backcompat
#   T6 codex-access-reuse-login-once               (part B rotation safety)
#   T7 glm-attribution-unavailable-fail-open
#   T8 normalize-payload-upgrades-nested-granularity
#   T9 quota-live-json-arbiter-contract            (bash: aggregate keys intact)
#
# run-all-triggers: leadv2-quota-read leadv2-quota-live

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
READER="${LEADV2_TEST_QUOTA_READ_PY:-${SCRIPTS_ROOT}/leadv2-quota-read.py}"
LIVE_BIN="${SCRIPTS_ROOT}/leadv2-quota-live.sh"

if [[ ! -f "${READER}" ]]; then
  echo "FAIL: reader not found at ${READER}" >&2
  exit 1
fi

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_TEST}"' EXIT

python3 - "${READER}" "${TMPDIR_TEST}" <<'PY'
import datetime
import importlib.util
import io
import json
import os
import sqlite3
import sys
import time
import urllib.error

reader_path, tmpdir = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("quota_reader_granularity", reader_path)
qr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qr)

failures = []


def check(label, cond, detail=""):
    if cond:
        print("[TEST] PASS: %s" % label)
    else:
        failures.append(label)
        print("[TEST] FAIL: %s -- %s" % (label, detail))


now = datetime.datetime.now(datetime.timezone.utc)
now_ms = int(time.time() * 1000)
now_epoch = int(time.time())

# Hermetic env: no daemon consult, fixture burn DB, a token so read_glm starts.
os.environ["LEADV2_QUOTA_DAEMON"] = "0"
os.environ["LEADV2_BURN_DB"] = os.path.join(tmpdir, "burn.db")
os.environ["ZAI_AUTH_TOKEN"] = "test-token"
os.environ.pop("LEADV2_QUOTA_GLM_MODELS", None)

# ── fixtures ────────────────────────────────────────────────────────────────
con = sqlite3.connect(os.environ["LEADV2_BURN_DB"])
con.execute("CREATE TABLE turn_events (id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "session_id TEXT, ts TEXT, cc INTEGER, cr INTEGER, input INTEGER, "
            "output INTEGER, model TEXT, tools_json TEXT)")


def ts(hours_ago):
    return (now - datetime.timedelta(hours=hours_ago)).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


# Inside BOTH the 5h and the weekly window: glm-5.3 burned 9000, flash 1000.
con.execute("INSERT INTO turn_events (ts, input, output, model) VALUES (?,?,?,?)",
            (ts(1.0), 6000, 3000, "glm-5.3"))
con.execute("INSERT INTO turn_events (ts, input, output, model) VALUES (?,?,?,?)",
            (ts(0.5), 700, 300, "glm-5.3-flash"))
# Outside even the weekly window -- must not leak into either attribution.
con.execute("INSERT INTO turn_events (ts, input, output, model) VALUES (?,?,?,?)",
            (ts(100.0), 9999, 9999, "glm-5.3"))
con.commit()
con.close()

glm_doc = {"code": 200, "msg": "ok", "success": True, "data": {"level": "max", "limits": [
    {"type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 40,
     "nextResetTime": now_ms + 2 * 3600_000},
    {"type": "TOKENS_LIMIT", "unit": 6, "number": 1, "percentage": 20,
     "nextResetTime": now_ms + 100 * 3600_000},
    {"type": "TIME_LIMIT", "unit": 5, "number": 1, "usage": 4000, "currentValue": 44,
     "remaining": 3956, "percentage": 1, "nextResetTime": now_ms + 30 * 24 * 3600_000,
     "usageDetails": [{"modelCode": "search-prime", "usage": 41}]},
]}}

codex_usage = {"user_id": "u", "plan_type": "prolite", "rate_limit": {
    "allowed": True, "limit_reached": False,
    "primary_window": {"used_percent": 38, "limit_window_seconds": 604800,
                       "reset_after_seconds": 468000, "reset_at": now_epoch + 130 * 3600},
    "secondary_window": None},
    "credits": {"has_credits": False, "balance": "0"}}


def fake_http_json(url, headers=None, method="GET", data=None, timeout=15):
    if "z.ai" in url:
        return 200, json.dumps(glm_doc)
    if "auth.openai.com" in url:
        return 200, json.dumps({"access_token": "new-access", "refresh_token": "new-refresh"})
    if "wham/usage" in url:
        return 200, json.dumps(codex_usage)
    raise AssertionError("unexpected url %s" % url)


qr.http_json = fake_http_json

# ── T1/T2/T3: GLM granularity ───────────────────────────────────────────────
out = qr.read_glm()
check("glm-status-ok", out.get("status") == "ok", json.dumps(out)[:200])

models = out.get("models") or {}
check("glm-models-both-keys-present",
      sorted(models) == ["glm-5.3", "glm-5.3-flash"], str(sorted(models)))

m53 = (models.get("glm-5.3") or {}).get("attributed") or {}
mfl = (models.get("glm-5.3-flash") or {}).get("attributed") or {}
u53 = (m53.get("five_hour") or {}).get("utilization_pct")
ufl = (mfl.get("five_hour") or {}).get("utilization_pct")
check("T1 glm-models-distinct-attributed-utilization",
      u53 is not None and ufl is not None and u53 != ufl and u53 == 36.0 and ufl == 4.0,
      "glm-5.3=%s glm-5.3-flash=%s (expected 36.0 / 4.0: shares 90/10 of pooled 40%%)"
      % (u53, ufl))
w53 = (m53.get("weekly") or {}).get("utilization_pct")
wfl = (mfl.get("weekly") or {}).get("utilization_pct")
check("glm-models-distinct-weekly-too",
      w53 == 18.0 and wfl == 2.0, "weekly attributed %s/%s" % (w53, wfl))
check("glm-attribution-basis-named",
      (m53.get("five_hour") or {}).get("basis") == "burn-db-turn-events",
      str(m53.get("five_hour")))

check("T2 glm-aggregate-key-backcompat",
      out.get("five_hour", {}).get("pct") == 40 and out.get("weekly", {}).get("pct") == 20
      and out.get("binding_window") in ("five_hour", "weekly")
      and out.get("level") == "max" and out.get("provider") == "glm"
      and out.get("five_hour", {}).get("remaining_pct") == 60.0,
      "aggregate fields drifted: %s" % json.dumps(out)[:300])

fh5 = (models.get("glm-5.3") or {}).get("five_hour") or {}
wky = (models.get("glm-5.3") or {}).get("weekly") or {}
check("T3 glm-model-keys-carry-real-window-periods",
      0 < fh5.get("hours_to_reset", 99) <= 5.0 and 0 < wky.get("hours_to_reset", 999) <= 168.0
      and fh5.get("pct") == 40 and wky.get("pct") == 20
      and fh5.get("remaining_pct") == 60.0,
      "5h reset=%s weekly reset=%s (expected ~2h / ~100h)"
      % (fh5.get("hours_to_reset"), wky.get("hours_to_reset")))

# ── T7: attribution fail-open (no burn data) ────────────────────────────────
os.environ["LEADV2_BURN_DB"] = os.path.join(tmpdir, "does-not-exist.db")
out2 = qr.read_glm()
att2 = ((out2.get("models") or {}).get("glm-5.3") or {}).get("attributed") or {}
check("T7 glm-attribution-unavailable-fail-open",
      out2.get("status") == "ok"
      and (att2.get("five_hour") or {}).get("utilization_pct") is None
      and (att2.get("five_hour") or {}).get("basis") == "burn-db-unavailable"
      and out2.get("five_hour", {}).get("pct") == 40,
      "aggregate must stay provider truth, attribution must stay null: %s" % att2)
os.environ["LEADV2_BURN_DB"] = os.path.join(tmpdir, "burn.db")

# ── T4/T5: Codex tiers ──────────────────────────────────────────────────────
codex_home = os.path.join(tmpdir, "codex-home")
os.makedirs(codex_home)
os.environ["CODEX_HOME"] = codex_home
auth_path = os.path.join(codex_home, "auth.json")


def write_auth(last_refresh_age_s):
    lr = (now - datetime.timedelta(seconds=last_refresh_age_s)).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(auth_path, "w") as f:
        json.dump({"tokens": {"access_token": "old-access", "refresh_token": "r0"},
                   "last_refresh": lr}, f)


calls = []


def counting_http(url, headers=None, method="GET", data=None, timeout=15):
    calls.append(url)
    return fake_http_json(url, headers, method, data, timeout)


qr.http_json = counting_http

write_auth(60)  # fresh access token -> reuse, no rotation
outc = qr.read_codex()
check("T6 codex-access-reuse-login-once",
      outc.get("status") == "ok" and outc.get("access_reused") is True
      and outc.get("refreshed") is False
      and not any("auth.openai.com" in u for u in calls)
      and sum("wham/usage" in u for u in calls) == 1,
      "calls=%s payload_flags(refreshed=%s access_reused=%s)"
      % (calls, outc.get("refreshed"), outc.get("access_reused")))

calls.clear()
write_auth(3 * 3600)  # stale -> exactly one rotation, written back
outc = qr.read_codex()
with open(auth_path) as f:
    rotated = json.load(f)
check("codex-rotation-writeback",
      outc.get("status") == "ok" and outc.get("refreshed") is True
      and sum("auth.openai.com" in u for u in calls) == 1
      and rotated["tokens"]["refresh_token"] == "new-refresh"
      and rotated["tokens"]["access_token"] == "new-access",
      "calls=%s rotated=%s" % (calls, rotated.get("tokens")))

write_auth(60)
outc = qr.read_codex()
tiers = outc.get("tiers") or {}
check("T4 codex-tiers-weekly-only-no-invented-five-hour",
      sorted(tiers) == ["standard", "top", "volume"]
      and all("five_hour" not in (t or {}).get("windows", {}) for t in tiers.values())
      and all((t or {}).get("window_shape") == "weekly" for t in tiers.values())
      and all("weekly" in (t or {}).get("windows", {}) for t in tiers.values())
      and all((t["windows"]["weekly"] or {}).get("limit_window_seconds") == 604800
              for t in tiers.values()),
      "tiers=%s" % json.dumps(tiers)[:300])
tier_models = {t: (tiers.get(t) or {}).get("model") for t in tiers}
check("codex-tier-identity-matches-routing-matrix",
      tier_models == {"volume": "gpt-5.6-luna", "standard": "gpt-5.6-terra",
                      "top": "gpt-5.6-sol"},
      str(tier_models))
check("T5 codex-aggregate-backcompat",
      outc.get("windows") and outc["windows"][0].get("kind") == "primary"
      and outc["windows"][0].get("used_percent") == 38
      and outc["windows"][0].get("remaining_pct") == 62.0
      and outc.get("binding_window") == "primary"
      and outc.get("plan_type") == "prolite",
      "aggregate fields drifted: %s" % json.dumps(outc)[:300])

# ── T8: normalize_payload upgrades nested granularity ──────────────────────
cached = json.loads(json.dumps(out))  # the GLM payload from T1
cached["five_hour"]["hours_to_reset"] = 999.0
cached["five_hour"]["usable_now"] = 0.0
(cached["models"]["glm-5.3"]["five_hour"])["hours_to_reset"] = 999.0
upgraded = qr.normalize_payload(cached)
check("T8 normalize-payload-upgrades-nested-granularity",
      0 < upgraded["five_hour"]["hours_to_reset"] <= 5.0
      and 0 < upgraded["models"]["glm-5.3"]["five_hour"]["hours_to_reset"] <= 5.0
      and upgraded.get("binding_window") in ("five_hour", "weekly"),
      "5h=%s model5h=%s"
      % (upgraded["five_hour"]["hours_to_reset"],
         upgraded["models"]["glm-5.3"]["five_hour"]["hours_to_reset"]))

cached_c = json.loads(json.dumps(outc))
cached_c["tiers"]["top"]["windows"]["weekly"]["hours_to_reset"] = 999.0
upgraded_c = qr.normalize_payload(cached_c)
check("normalize-payload-upgrades-codex-tiers",
      0 < upgraded_c["tiers"]["top"]["windows"]["weekly"]["hours_to_reset"] <= 168.0,
      "tier weekly hours_to_reset=%s"
      % upgraded_c["tiers"]["top"]["windows"]["weekly"]["hours_to_reset"])

print("[TEST] python part: %d failure(s)" % len(failures))
sys.exit(1 if failures else 0)
PY
rc_python=$?

# ── T9: quota-live.sh json keeps the arbiter contract (bash, fake reader) ───
FAKE_READER="${TMPDIR_TEST}/fake-reader.py"
cat > "${FAKE_READER}" <<'FAKE'
import json, sys
args = sys.argv[1:]
p = args[0] if args else ""
if p == "glm":
    doc = {"provider": "glm", "status": "ok",
           "five_hour": {"pct": 40, "remaining_pct": 60.0, "hours_to_reset": 2.0,
                          "usable_now": 30.0, "reset_iso": "2026-09-09T21:00:00Z"},
           "weekly": {"pct": 20, "remaining_pct": 80.0, "hours_to_reset": 100.0,
                      "usable_now": 0.8, "reset_iso": "2026-09-13T21:00:00Z"},
           "binding_window": "five_hour", "metering": "shared_pool",
           "models": {"glm-5.3": {"attributed": {"five_hour": {"utilization_pct": 36.0,
                       "share_pct": 90.0, "basis": "burn-db-turn-events"}}},
                      "glm-5.3-flash": {"attributed": {"five_hour": {"utilization_pct": 4.0,
                       "share_pct": 10.0, "basis": "burn-db-turn-events"}}}}}
elif p == "codex":
    doc = {"provider": "codex", "status": "ok", "plan_type": "prolite",
           "windows": [{"kind": "primary", "used_percent": 38, "remaining_pct": 62.0,
                        "hours_to_reset": 130.0, "usable_now": 0.48,
                        "limit_window_seconds": 604800}],
           "binding_window": "primary", "metering": "account_pool",
           "tiers": {"volume": {"model": "gpt-5.6-luna", "window_shape": "weekly",
                     "windows": {"weekly": {"limit_window_seconds": 604800,
                                 "remaining_pct": 62.0, "hours_to_reset": 130.0}}}}}
elif p == "anthropic":
    doc = {"provider": "anthropic", "status": "ok",
           "accounts": [{"account_label": "max-test", "active": True,
                         "five_hour": {"pct": 10, "remaining_pct": 90.0,
                                       "hours_to_reset": 3.0, "usable_now": 30.0},
                         "seven_day": {"pct": 40, "remaining_pct": 60.0,
                                       "hours_to_reset": 100.0, "usable_now": 0.6},
                         "binding_window": "five_hour"}],
           "active_account": "max-test", "binding_window": "five_hour"}
else:
    doc = {"provider": p, "status": "unknown", "error": "fake: unknown provider"}
print(json.dumps(doc))
FAKE

T9_FAIL=""
json_out="$(LEADV2_QUOTA_READ="${FAKE_READER}" LEADV2_QUOTA_DAEMON=0 "${LIVE_BIN}" json)" || T9_FAIL="json mode exited nonzero"
echo "--- ${LIVE_BIN##*/} json (fake reader) ---"
printf '%s\n' "${json_out}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
ok = all(p in d for p in ("glm", "codex", "anthropic"))
ok = ok and "models" in d["glm"] and "tiers" in d["codex"]
ok = ok and d["glm"]["five_hour"]["pct"] == 40 and d["codex"]["windows"][0]["kind"] == "primary"
print("[TEST] %s T9 quota-live-json-arbiter-contract -- aggregate keys glm/codex/anthropic intact, granularity rides through" % ("PASS:" if ok else "FAIL:"))
sys.exit(0 if ok else 1)
' || T9_FAIL="T9 failed"

report_out="$(LEADV2_QUOTA_READ="${FAKE_READER}" LEADV2_QUOTA_DAEMON=0 "${LIVE_BIN}" report 2>/dev/null)" || true
if ! grep -q "glm model glm-5.3" <<<"${report_out}" || ! grep -q "codex tiers" <<<"${report_out}"; then
  echo "[TEST] FAIL: report mode does not render granularity lines"
  echo "${report_out}" | head -20
  T9_FAIL="report granularity lines missing"
else
  echo "[TEST] PASS: report mode renders glm model attribution + codex tier lines"
fi

if [[ -n "${T9_FAIL}" ]]; then
  echo "SUITE FAIL: ${T9_FAIL}"
  exit 1
fi
if [[ ${rc_python} -ne 0 ]]; then
  echo "SUITE FAIL: python part"
  exit 1
fi
echo "SUITE OK: quota model/tier granularity"
exit 0
