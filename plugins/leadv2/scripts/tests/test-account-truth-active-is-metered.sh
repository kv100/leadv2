#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-quota-read.py leadv2-quota-read leadv2-ratelimit-probe.sh leadv2-ratelimit-probe leadv2-turn-account-attribute.py leadv2-turn-account-attribute leadv2-cost-actuals.sh leadv2-cost-actuals leadv2-dispatch-code.sh leadv2-dispatch-code leadv2-drain-weights.py leadv2-drain-weights
# tests/test-account-truth-active-is-metered.sh — ACCOUNT-TRUTH-ACTIVE-IS-NOT-THE-METERED-ONE-01
#
# Guards the account-truth half of dispatch-1786402f: resolve_active_account()
# must pick the account the session ACTUALLY runs under (derived from
# CLAUDE_CONFIG_DIR via sha256_8(realpath(dir)), matched against keychain
# entry_suffixes) instead of the bare "default" service that has 124/124
# unauthenticated snapshots and has never metered — and the probe must persist
# the unmetered third state instead of silently collapsing it to
# "unauthenticated" with a null pct.
#
# Binding decisions under test (D-numbers from the scoped design):
#   D2  no login, no `ccswitch --switch`, no credential write (assertion 8)
#   D4  SCHEMA_VERSION stays 1 — no version bump anywhere new (assertion 5)
#   D6  remaining_pct polarity preserved: consumed 91.0 stores 91.0 (assertion 6)
#   D8  401+team/max persists state='unmetered', pct NULL — never a silent
#       null-equivalent 0 (assertion 7)
#
# Fixture style: test-leadv2-ratelimit-probe.sh (fake leadv2-quota-live.sh via
# LEADV2_QUOTA_LIVE_SH, from-scratch sqlite DB, pinned epochs). The resolver
# assertions import account_key_for_config_dir/resolve_active_account straight
# from leadv2-quota-read.py (importlib; main() is behind __main__).
#
# Portable: the two live key anchors (eb6c5b97/5a3c2328) are asserted only on
# the machine whose $HOME they were measured on; everywhere else the same
# checks run against the locally derived key, so the CONTRACT is tested on
# every runner. Exit 0 = pass.

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# LEADV2_QUOTA_READ_PY / LEADV2_RATELIMIT_PROBE_SH: mutation-control injection
# points (nc-account-truth-active-is-metered.sh) — the whole suite runs against
# a scratch mutated copy, never an in-place edit.
QR_PY="${LEADV2_QUOTA_READ_PY:-${SCRIPTS_ROOT}/leadv2-quota-read.py}"
PROBE_SH="${LEADV2_RATELIMIT_PROBE_SH:-${SCRIPTS_ROOT}/leadv2-ratelimit-probe.sh}"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS+1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir "acct-truth")"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# 1. syntax
# ---------------------------------------------------------------------------
for f in "$QR_PY" "${SCRIPTS_ROOT}/leadv2-turn-account-attribute.py" "${SCRIPTS_ROOT}/leadv2-drain-weights.py"; do
  if python3 -m py_compile "$f" 2>/dev/null; then pass "1 py_compile $(basename "$f")"; else fail "1 py_compile $(basename "$f")"; fi
done
if bash -n "$PROBE_SH"; then pass "1 bash -n leadv2-ratelimit-probe.sh"; else fail "1 bash -n leadv2-ratelimit-probe.sh"; fi
if bash -n "${SCRIPTS_ROOT}/lib/leadv2-cost-actuals.sh"; then pass "1 bash -n lib/leadv2-cost-actuals.sh"; else fail "1 bash -n lib/leadv2-cost-actuals.sh"; fi
nc_dispatch=0
while IFS= read -r f; do
  if bash -n "$f"; then :; else fail "1 bash -n $(basename "$f")"; nc_dispatch=1; fi
done < <(ls "${SCRIPTS_ROOT}"/leadv2-dispatch-*.sh 2>/dev/null)
(( nc_dispatch == 0 )) && pass "1 bash -n leadv2-dispatch-*.sh"

# ---------------------------------------------------------------------------
# 2+3. derivation: normalization contract + live anchors
# ---------------------------------------------------------------------------
# Portable contract: tilde expansion, trailing-slash and /./ equality, raw
# strings are NOT hashed, empty is "".
PORTABLE_OK=1
python3 - "$QR_PY" "$TMP" <<'PY' || PORTABLE_OK=0
import hashlib, importlib.util, os, sys
spec = importlib.util.spec_from_file_location("qr", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
k = m.account_key_for_config_dir
d = os.path.join(sys.argv[2], "cfgdir")
os.makedirs(d, exist_ok=True)
def raw(s): return hashlib.sha256(s.encode()).hexdigest()[:8]
assert k(d) == k(d + "/") == k(d + "/./"), "normalization variants disagree"
assert k(d) == raw(os.path.realpath(d).rstrip("/")), "not sha256_8(realpath)"
assert k(d) != raw(d), "raw string hashed (tilde/relative forms would fork keys)"
assert k("") == "" and k("   ") == "", "empty must be empty, not a hash of ''"
assert k("~/.claude") == raw(os.path.realpath(os.path.expanduser("~/.claude")).rstrip("/")), \
    "tilde default does not land on the expanded-path key"
PY
if [[ "$PORTABLE_OK" == "1" ]]; then
  pass "2 derivation: tilde/realpath/trailing-slash equality + raw-string rejection"
else
  fail "2 derivation: normalization contract broken"
fi

# Live anchors (measured 2026-09-13 against rate_limit_history: the only two
# keys that have ever parsed a percentage). Only meaningful on this $HOME —
# elsewhere the portable contract above is the assertion.
if [[ "$(python3 -c 'import os,sys; print(os.path.realpath(os.path.expanduser("~/.claude")))')" == "/Users/kostiantyn.vlasenko/.claude" ]]; then
  ANCHOR_OK=1
  python3 - "$QR_PY" <<'PY' || ANCHOR_OK=0
import importlib.util, sys
spec = importlib.util.spec_from_file_location("qr", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
k = m.account_key_for_config_dir
assert k("~/.claude") == "eb6c5b97", "personal anchor drifted: %r" % k("~/.claude")
assert k("~/.claude-work") == "5a3c2328", "work anchor drifted: %r" % k("~/.claude-work")
PY
  if [[ "$ANCHOR_OK" == "1" ]]; then pass "3 anchors: ~/.claude=eb6c5b97 ~/.claude-work=5a3c2328"
  else fail "3 anchors: live key derivation drifted"; fi
else
  log "SKIP 3 anchors: foreign \$HOME (portable contract already asserted)"
fi

# ---------------------------------------------------------------------------
# 4. resolution ladder: stored-active flag loses to CLAUDE_CONFIG_DIR
# ---------------------------------------------------------------------------
LADDER_OK=1
CFG="$TMP/session-cfg"; mkdir -p "$CFG"
GONE="$TMP/gone-cfg"   # entry exists, dir does not
OTHER="$TMP/other-cfg" # dir exists, entry does not
CFG_KEY="$(python3 -c 'import hashlib,os,sys; print(hashlib.sha256(os.path.realpath(sys.argv[1]).rstrip("/").encode()).hexdigest()[:8])' "$CFG")"
HOME_KEY="$(python3 -c 'import hashlib,os; print(hashlib.sha256(os.path.realpath(os.path.expanduser("~/.claude")).rstrip("/").encode()).hexdigest()[:8])')"
CFG_ENV="$CFG" CFG_KEY="$CFG_KEY" GONE="$GONE" \
GONE_KEY="$(python3 -c 'import hashlib,os,sys; print(hashlib.sha256(os.path.realpath(sys.argv[1]).rstrip("/").encode()).hexdigest()[:8])' "$GONE")" \
OTHER="$OTHER" HOME_KEY="$HOME_KEY" QR_PY="$QR_PY" python3 <<'PY' || LADDER_OK=0
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("qr", os.environ["QR_PY"])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
resolve = m.resolve_active_account

def accounts():
    # The negative-control fixture shape from the design: the BARE service
    # arrives carrying a stored active=True from an older resolution, while
    # the config dir says the suffixed entry is the metered one.
    return [
        {"service": "Claude Code-credentials", "entry_suffix": "default",
         "account_label": "max_20x", "active": True},
        {"service": "Claude Code-credentials-%s" % os.environ["CFG_KEY"],
         "entry_suffix": os.environ["CFG_KEY"], "account_label": "cfg_acct", "active": False},
        {"service": "Claude Code-credentials-%s" % os.environ["HOME_KEY"],
         "entry_suffix": os.environ["HOME_KEY"], "account_label": "home_acct", "active": False},
    ]

def active_label(accts):
    return next(a["account_label"] for a in accts if a.get("active"))

# 4a. config dir beats the stale stored flag (the lane's headline defect)
os.environ["CLAUDE_CONFIG_DIR"] = os.environ["CFG_ENV"]
os.environ.pop("LEADV2_ANTHROPIC_ACTIVE_SERVICE", None)
os.environ.pop("CLAUDE_CODE_CREDENTIALS_SERVICE", None)
os.environ.pop("LEADV2_ANTHROPIC_FORCE_UNRESOLVED", None)
accts = accounts()
res = resolve(accts, "max_20x")
assert res == "config_dir", res
assert active_label(accts) == "cfg_acct", "stored active flag survived: %s" % active_label(accts)
assert sum(1 for a in accts if a["active"]) == 1, "mark-exactly-one violated"

# 4b. explicit operator env still outranks the derivation (rung 1)
os.environ["LEADV2_ANTHROPIC_ACTIVE_SERVICE"] = "Claude Code-credentials"
accts = accounts()
res = resolve(accts, "max_20x")
assert res == "session_credential" and active_label(accts) == "max_20x", (res, active_label(accts))

# 4c. absent CLAUDE_CONFIG_DIR derives the ~/.claude default (auditable)
os.environ.pop("LEADV2_ANTHROPIC_ACTIVE_SERVICE")
os.environ.pop("CLAUDE_CONFIG_DIR")
accts = accounts()
res = resolve(accts, "max_20x")
assert res == "config_dir_default" and active_label(accts) == "home_acct", (res, active_label(accts))

# 4d. matched entry but nonexistent dir: config_dir_missing, still selected
os.environ["CLAUDE_CONFIG_DIR"] = os.path.expandvars("$GONE")
accts = [
        {"service": "Claude Code-credentials", "entry_suffix": "default",
         "account_label": "max_20x", "active": False},
        {"service": "x", "entry_suffix": os.environ["GONE_KEY"],
         "account_label": "gone_acct", "active": False}]
res = resolve(accts, "max_20x")
assert res == "config_dir_missing" and active_label(accts) == "gone_acct", res

# 4e. unmatched derivation falls through to the bare service — the rung never
# invents an account
os.environ["CLAUDE_CONFIG_DIR"] = os.environ["OTHER"]
accts = accounts()
res = resolve(accts, "max_20x")
assert res == "session_credential" and active_label(accts) == "max_20x", res
PY
if [[ "$LADDER_OK" == "1" ]]; then
  pass "4 ladder: config_dir beats stored flag; env rung wins; default/missing/unmatched auditable"
else
  fail "4 ladder: resolution ladder regression"
fi

# ---------------------------------------------------------------------------
# 5. SCHEMA_VERSION stays 1; nothing new writes it (D4/R1)
# ---------------------------------------------------------------------------
BURN_LIB="${LEADV2_BURN_LIB:-$HOME/.claude/burn/lib.py}"
if [[ -f "$BURN_LIB" ]]; then
  if grep -Eq '^[[:space:]]*SCHEMA_VERSION[[:space:]]*=[[:space:]]*1[[:space:]]*$' "$BURN_LIB"; then
    pass "5 lib.py SCHEMA_VERSION still 1"
  else
    fail "5 lib.py SCHEMA_VERSION is not 1 (bump would DROP sessions+turn_events)"
  fi
else
  log "SKIP 5 lib.py absent on this runner — asserting no-writes half only"
fi
if ! grep -Eq 'SCHEMA_VERSION[[:space:]]*=' "${SCRIPTS_ROOT}/leadv2-turn-account-attribute.py" "${SCRIPTS_ROOT}/leadv2-drain-weights.py"; then
  pass "5 new files assign no SCHEMA_VERSION"
else
  fail "5 a new file writes SCHEMA_VERSION (guarded additive ALTER is the only legal path)"
fi

# ---------------------------------------------------------------------------
# probe fixture: fake live reader + from-scratch DB (probe creates the table)
# ---------------------------------------------------------------------------
FAKE_LIVE="$TMP/quota-live-fake.sh"
NEXT_JSON="$TMP/next-accounts.json"
cat > "$FAKE_LIVE" <<EOF
#!/usr/bin/env bash
cat "$NEXT_JSON"
EOF
chmod +x "$FAKE_LIVE"
DB="$TMP/acct.db"
sqlite3 "$DB" "CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT);"
run_probe() {
  LEADV2_QUOTA_LIVE_SH="$FAKE_LIVE" LEADV2_BURN_DB="$DB" \
  LEADV2_RATELIMIT_PROBE_NOW="1893456000" bash "$PROBE_SH"
}

# ---------------------------------------------------------------------------
# 6. polarity: consumed 91.0 is stored as 91.0 (D6)
# ---------------------------------------------------------------------------
cat > "$NEXT_JSON" <<'JSON'
{"provider":"anthropic","status":"ok","accounts":[
{"entry_suffix":"eb6c5b97","service":"Claude Code-credentials-eb6c5b97","account_label":"max_20x","active":true,"status":"ok","five_hour":{"pct":91.0,"reset_iso":"2026-09-13T22:00:00+00:00"},"seven_day":{"pct":42.0,"reset_iso":"2026-09-16T00:00:00+00:00"},"binding_window":"five_hour"}
],"active_account":"max_20x"}
JSON
run_probe >/dev/null 2>&1
pct="$(sqlite3 "$DB" "SELECT five_hour_pct FROM rate_limit_history WHERE account_key='eb6c5b97';")"
wk="$(sqlite3 "$DB" "SELECT seven_day_pct FROM rate_limit_history WHERE account_key='eb6c5b97';")"
if [[ "$pct" == "91.0" && "$wk" == "42.0" ]]; then
  pass "6 polarity: consumed 91.0/42.0 stored verbatim (not 9.0/58.0)"
else
  fail "6 polarity: stored five_hour_pct='$pct' seven_day_pct='$wk' (expected 91.0/42.0)"
fi

# ---------------------------------------------------------------------------
# 7. 401+team persists unmetered; unknown-without-state stays unauthenticated
# ---------------------------------------------------------------------------
rm -f "$DB"; sqlite3 "$DB" "CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT);"
cat > "$NEXT_JSON" <<'JSON'
{"provider":"anthropic","status":"ok","accounts":[
{"entry_suffix":"5a3c2328","service":"Claude Code-credentials-5a3c2328","account_label":"max_5x","active":true,"status":"unknown","account_state":"unmetered","subscription_type":"team","error":"http 401"},
{"entry_suffix":"deadbeef","service":"Claude Code-credentials-deadbeef","account_label":"stale","active":false,"status":"unknown","error":"http 401"}
],"active_account":"max_5x"}
JSON
run_probe >/dev/null 2>&1
u_state="$(sqlite3 "$DB" "SELECT state FROM rate_limit_history WHERE account_key='5a3c2328';")"
u_pct="$(sqlite3 "$DB" "SELECT five_hour_pct FROM rate_limit_history WHERE account_key='5a3c2328';")"
d_state="$(sqlite3 "$DB" "SELECT state FROM rate_limit_history WHERE account_key='deadbeef';")"
if [[ "$u_state" == "unmetered" && "$u_pct" == "" && "$d_state" == "unauthenticated" ]]; then
  pass "7 unmetered: 401+team persists state='unmetered' pct NULL; bare unknown stays unauthenticated"
else
  fail "7 unmetered: team state='$u_state' pct='$u_pct' unknown state='$d_state'"
fi

# ---------------------------------------------------------------------------
# 8. no credential writes anywhere in the changed set (D2)
# ---------------------------------------------------------------------------
GREPTargets=("$QR_PY" "$PROBE_SH" "${SCRIPTS_ROOT}/leadv2-turn-account-attribute.py"
             "${SCRIPTS_ROOT}/leadv2-drain-weights.py" "${SCRIPTS_ROOT}/lib/leadv2-cost-actuals.sh")
hits="$(grep -nE 'ccswitch|security (add|delete)-generic-password|osascript' "${GREPTargets[@]}" 2>/dev/null || true)"
if [[ -z "$hits" ]]; then
  pass "8 no ccswitch / keychain-write / osascript in the changed set"
else
  fail "8 credential-write pattern present: $(printf '%s' "$hits" | head -2 | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
printf -- '\n'
printf -- 'pass=%d fail=%d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf -- '%s\n' "${ERRORS[@]}" >&2
  exit 1
fi
exit 0
