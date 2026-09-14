#!/usr/bin/env bash
# tests/test-quota-read-codex-refresh-race.sh — CODEX-QUOTA-READER-401-WHILE-CODEX-WORKS-01
#
# leadv2-quota-read.py's read_codex() shares ~/.codex/auth.json with the
# interactive codex CLI. refresh_token rotation is single-use: if the CLI
# rotates it between our disk read and our POST landing, the OAuth server
# sees an already-consumed refresh_token and answers 401/403 -- even though
# the CLI's own refresh just succeeded and the account is perfectly alive.
# Measured live 2026-09-14: leadv2-quota-live.sh reported codex status=unknown
# error="refresh http 401" at 08:26Z with a fresh fetched_at, while
# codex-login.log shows a login exchange at 08:38Z and a same-night dispatch
# job completed fine on gpt-5.6-terra -- the credential was never dead, only
# the read path's single refresh attempt lost a rotation race.
#
# Before this fix, a 401/403 on the refresh POST gave up immediately
# (status=unknown, needs_login=True) with no re-read of the (by then
# rotated) auth.json. This suite hermetically drives read_codex() (no real
# CODEX_HOME, no real network: _codex_auth_path/_codex_access_from_disk/
# http_json are monkeypatched, same technique as
# test-quota-read-anthropic-liveness.sh) and proves:
#   T1: a refresh POST that 401s because a concurrent writer (the real CLI)
#       already rotated the refresh_token still ends in status=ok -- the
#       retry re-reads auth.json from disk and picks up the winning token.
#   T2 (negative control): a refresh POST that 401s TWICE (a genuinely dead
#       credential, no concurrent winner) still lands on status=unknown with
#       needs_login=True, and the retry is bounded at exactly one extra
#       attempt (2 POSTs total, never a loop).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
READER="${LEADV2_TEST_QUOTA_READ_PY:-${SCRIPTS_ROOT}/leadv2-quota-read.py}"

if [[ ! -f "${READER}" ]]; then
  echo "FAIL: reader not found at ${READER}" >&2
  exit 1
fi

# run-all-triggers: leadv2-quota-read leadv2-quota-live

python3 - "${READER}" <<'PY'
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import urllib.error

reader_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("quota_reader_codex_race", reader_path)
quota_reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(quota_reader)

failures = []


def check(label, cond, detail=""):
    if cond:
        print("[TEST] PASS: %s" % label)
    else:
        failures.append(label)
        print("[TEST] FAIL: %s -- %s" % (label, detail))


orig_auth_path = quota_reader._codex_auth_path
orig_access_from_disk = quota_reader._codex_access_from_disk
orig_http = quota_reader.http_json


def restore():
    quota_reader._codex_auth_path = orig_auth_path
    quota_reader._codex_access_from_disk = orig_access_from_disk
    quota_reader.http_json = orig_http


tmpdir = tempfile.mkdtemp(prefix="codex-race-test-")
auth_path = os.path.join(tmpdir, "auth.json")

USAGE_OK = {
    "plan_type": "prolite",
    "rate_limit": {"primary_window": {"used_percent": 18,
                                       "limit_window_seconds": 604800,
                                       "reset_at": 9999999999}},
    "credits": {"has_credits": True, "balance": 0},
}


def write_auth(refresh_token, access_token="acc-old"):
    with open(auth_path, "w") as f:
        json.dump({"tokens": {"access_token": access_token,
                               "refresh_token": refresh_token,
                               "account_id": "acct-1"}}, f)


# --- T1: refresh 401s once (a concurrent CLI won the rotation race), the ---
# --- retry re-reads the now-rotated auth.json and succeeds -----------------
write_auth("RT_OLD")
quota_reader._codex_auth_path = lambda: auth_path
quota_reader._codex_access_from_disk = lambda: (None, None)  # force the refresh branch

t1_refresh_calls = {"n": 0}


def fake_http_t1(url, headers=None, method="GET", data=None, timeout=15):
    if url == "https://auth.openai.com/oauth/token":
        t1_refresh_calls["n"] += 1
        body = json.loads(data.decode())
        if t1_refresh_calls["n"] == 1:
            check("T1: first refresh POST used the pre-race refresh_token",
                  body.get("refresh_token") == "RT_OLD", "body=%r" % body)
            # The concurrent CLI process rotates the token server-side and
            # writes the winning tokens to the shared auth.json.
            write_auth("RT_NEW", access_token="acc-new")
            raise urllib.error.HTTPError(url, 401, "invalid_grant", {}, None)
        check("T1: retry POST used the rotated refresh_token (re-read from disk)",
              body.get("refresh_token") == "RT_NEW", "body=%r" % body)
        return 200, json.dumps({"access_token": "acc-new2", "refresh_token": "RT_NEWER"})
    if url == "https://chatgpt.com/backend-api/wham/usage":
        return 200, json.dumps(USAGE_OK)
    raise AssertionError("unexpected url %r" % url)


quota_reader.http_json = fake_http_t1
result = quota_reader.read_codex()
check("T1: a lost rotation race still ends in status=ok",
      result.get("status") == "ok", "result=%r" % result)
check("T1: exactly one retry happened (2 refresh POSTs total)",
      t1_refresh_calls["n"] == 2, "n=%d" % t1_refresh_calls["n"])
restore()

# --- T2 (negative control): both refresh attempts genuinely 401 -- no ------
# --- concurrent winner exists, the credential really is dead ---------------
write_auth("RT_DEAD")
quota_reader._codex_auth_path = lambda: auth_path
quota_reader._codex_access_from_disk = lambda: (None, None)

t2_refresh_calls = {"n": 0}


def fake_http_t2(url, headers=None, method="GET", data=None, timeout=15):
    if url == "https://auth.openai.com/oauth/token":
        t2_refresh_calls["n"] += 1
        raise urllib.error.HTTPError(url, 401, "invalid_grant", {}, None)
    raise AssertionError("unexpected url %r during a dead-credential probe" % url)


quota_reader.http_json = fake_http_t2
result = quota_reader.read_codex()
check("T2: a genuinely dead credential still lands on status=unknown (never fabricated ok)",
      result.get("status") == "unknown", "result=%r" % result)
check("T2: needs_login is surfaced", result.get("needs_login") is True,
      "result=%r" % result)
check("T2: the retry is bounded at exactly one extra attempt (2 POSTs, never a loop)",
      t2_refresh_calls["n"] == 2, "n=%d" % t2_refresh_calls["n"])
check("T2: error message names the http code",
      "401" in str(result.get("error", "")), "error=%r" % result.get("error"))
restore()

shutil.rmtree(tmpdir, ignore_errors=True)

if failures:
    print("[TEST] Results: FAIL=%d (%s)" % (len(failures), ", ".join(failures)))
    sys.exit(1)
print("[TEST] Results: all codex-refresh-race checks green")
sys.exit(0)
PY
