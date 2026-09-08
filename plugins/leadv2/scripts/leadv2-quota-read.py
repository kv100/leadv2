#!/usr/bin/env python3
"""
leadv2-quota-read.py — Live quota reads for the three provider buckets.
Credential-safe: tokens are held in process memory ONLY. They are never printed,
logged, or written to any cache file. Cache files store ONLY the normalized,
non-secret result (percentages, reset times, plan type).

Usage:
    leadv2-quota-read.py glm|codex|anthropic [--no-cache] [--cache-dir DIR]
    leadv2-quota-read.py anthropic --no-cache --credential-file <path>

Each provider is INDEPENDENT — one failing never blanks another. Any read error
fails OPEN: the bucket reports {"status":"unknown", ...} and exit code 0, so a
caller (the GLM gate) never crashes on a quota blip. unknown is never 0%.

Buckets:
  glm        z.ai token quota. Disambiguates 5h vs weekly by nextResetTime
             distance (position-independent). Bearer $ZAI_AUTH_TOKEN.
  codex      ChatGPT/Codex usage. Refreshes the OAuth token first (rotation
             rotates the refresh_token -> written back to auth.json), then reads
             chatgpt.com/backend-api/wham/usage. used_percent verbatim.
  anthropic  Anthropic Max/Team usage via /api/oauth/usage using whatever
             in-process access token each keychain entry holds. Scans every
             Claude Code-credentials* keychain entry; reports each account
             that has a token to try. 429 -> unknown. No token bytes at all ->
             unknown (nothing to try). A stale claudeAiOauth.expiresAt is NOT
             treated as death -- the live call itself is the liveness test
             (D3, TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01); a genuinely
             dead token still comes back 401/403 -> unknown.

Env overrides:
  LEADV2_QUOTA_TTL_GLM (60)  LEADV2_QUOTA_TTL_CODEX (120)  LEADV2_QUOTA_TTL_ANTHROPIC (300)
  LEADV2_QUOTA_CACHE_DIR (~/.claude/state/leadv2/quota-cache)
  LEADV2_BURN_DB (~/.claude/burn/history.db)  -- Anthropic rate_limit_info kv secondary signal
  LEADV2_ANTHROPIC_ACTIVE_SERVICE -- credential service used by this session
  LEADV2_ANTHROPIC_FORCE_UNRESOLVED=1 -- test the configured-pin fallback
  LEADV2_ROUTING_CONFIG -- router config containing router_v2.active_account
  CODEX_HOME (~/.codex)  ZAI_AUTH_TOKEN  LEADV2_ZAI_ENV (~/.claude/secrets/zai.env)
"""
import datetime, json, os, subprocess, sys, tempfile, time, urllib.request, urllib.error

UTC = datetime.timezone.utc


def iso_now():
    return datetime.datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def iso_from_ms(ms):
    try:
        return datetime.datetime.fromtimestamp((ms or 0) / 1000, UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        return None


def iso_from_epoch(s):
    try:
        return datetime.datetime.fromtimestamp(int(s or 0), UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        return None


CACHE_DIR = os.environ.get("LEADV2_QUOTA_CACHE_DIR",
                           os.path.expanduser("~/.claude/state/leadv2/quota-cache"))
TTL = {"glm": int(os.environ.get("LEADV2_QUOTA_TTL_GLM", "60")),
       "codex": int(os.environ.get("LEADV2_QUOTA_TTL_CODEX", "120")),
       "anthropic": int(os.environ.get("LEADV2_QUOTA_TTL_ANTHROPIC", "300"))}


def cache_get(provider):
    p = os.path.join(CACHE_DIR, provider + ".json")
    try:
        if time.time() - os.path.getmtime(p) < TTL[provider]:
            with open(p) as f:
                return json.load(f)
    except Exception:
        pass
    return None


def cache_put(provider, obj):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=provider + ".", dir=CACHE_DIR)
        with os.fdopen(fd, "w") as f:
            json.dump(obj, f)
        os.replace(tmp, os.path.join(CACHE_DIR, provider + ".json"))
    except Exception:
        pass


def http_json(url, headers=None, method="GET", data=None, timeout=15):
    req = urllib.request.Request(url, headers=headers or {}, method=method, data=data)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.getcode(), r.read().decode()


def unknown(provider, error, **extra):
    d = {"provider": provider, "status": "unknown", "error": error,
         "usable_now": None, "binding_window": None, "fetched_at": iso_now()}
    d.update(extra)
    return d


def _parse_iso(value):
    """Return an aware UTC datetime for a provider reset timestamp, or None."""
    if not value or not isinstance(value, str):
        return None
    try:
        return datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(UTC)
    except (TypeError, ValueError):
        return None


def normalize_window(used_pct, reset_iso, now=None):
    """Add router-v2 quota truth without changing a provider's source fields.

    Provider quota APIs report usage; the selector needs how much usable capacity
    remains per hour.  A missing or malformed value remains unknown, never zero.
    """
    try:
        used = float(used_pct)
    except (TypeError, ValueError):
        used = None
    reset = _parse_iso(reset_iso)
    if used is None or reset is None:
        return {"remaining_pct": None, "hours_to_reset": None, "usable_now": None}
    current = now or datetime.datetime.now(UTC)
    if current.tzinfo is None:
        current = current.replace(tzinfo=UTC)
    hours = (reset - current).total_seconds() / 3600.0
    remaining = max(0.0, min(100.0, 100.0 - used))
    return {"remaining_pct": remaining,
            "hours_to_reset": hours,
            "usable_now": remaining / max(hours, 1.0)}


def with_window_truth(window, used_key, now=None):
    """Return a copy of a provider window enriched with normalized quota truth."""
    if not isinstance(window, dict):
        return None
    out = dict(window)
    out.update(normalize_window(out.get(used_key), out.get("reset_iso"), now=now))
    return out


def binding_window(windows):
    """Name the lowest known usable-now window; unknown is deliberately not zero."""
    known = [(name, value.get("usable_now")) for name, value in windows.items()
             if isinstance(value, dict) and value.get("usable_now") is not None]
    return min(known, key=lambda item: item[1])[0] if known else None


# ── GLM ─────────────────────────────────────────────────────────────────────
def read_glm():
    tok = os.environ.get("ZAI_AUTH_TOKEN")
    if not tok:
        envf = os.environ.get("LEADV2_ZAI_ENV", os.path.expanduser("~/.claude/secrets/zai.env"))
        try:
            with open(envf) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("ZAI_AUTH_TOKEN") and "=" in line:
                        tok = line.split("=", 1)[1].strip().strip('"').strip("'")
                        break
        except Exception:
            pass
    if not tok:
        return unknown("glm", "ZAI_AUTH_TOKEN not set / not readable")
    try:
        glm_url = os.environ.get("LEADV2_ZAI_QUOTA_URL",
                                 "https://api.z.ai/api/monitor/usage/quota/limit")
        _, body = http_json(glm_url, headers={"Authorization": "Bearer " + tok})
        doc = json.loads(body)
        limits = (doc.get("data") or {}).get("limits") or []
    except urllib.error.HTTPError as e:
        return unknown("glm", "http %d" % e.code)
    except Exception as e:
        return unknown("glm", "fetch/parse: %s" % e)

    now_ms = int(time.time() * 1000)
    token_limits = [l for l in limits if l.get("type") == "TOKENS_LIMIT"]
    five_hour, weekly, search = None, None, None
    # Disambiguate by nextResetTime DISTANCE (position-independent, reorder-safe).
    for l in token_limits:
        hrs = ((l.get("nextResetTime") or 0) - now_ms) / 3_600_000.0
        if hrs < 36 and five_hour is None:
            five_hour = l
        elif hrs >= 36 and weekly is None:
            weekly = l
        else:
            if five_hour is None:
                five_hour = l
            elif weekly is None:
                weekly = l
    for l in limits:
        if l.get("type") == "TIME_LIMIT":
            search = l

    def win(l):
        if not l:
            return None
        return with_window_truth({"pct": l.get("percentage"),
                "reset_epoch_ms": l.get("nextResetTime"),
                "reset_iso": iso_from_ms(l.get("nextResetTime")),
                "unit": l.get("unit"), "number": l.get("number")}, "pct")

    five_hour_window, weekly_window = win(five_hour), win(weekly)
    out = {"provider": "glm", "status": "ok",
           "level": (doc.get("data") or {}).get("level"), "fetched_at": iso_now(),
           "five_hour": five_hour_window, "weekly": weekly_window,
           "binding_window": binding_window({"five_hour": five_hour_window, "weekly": weekly_window})}
    if search:
        out["search_credits"] = {"percentage": search.get("percentage"),
                                 "usage": search.get("usage"),
                                 "remaining": search.get("remaining"),
                                 "reset_iso": iso_from_ms(search.get("nextResetTime"))}
    if not (five_hour and weekly):
        # 0 or 1 usable windows means we cannot assess quota (bad token returns
        # 200 with empty limits). Fail honestly to unknown — never report ok/null.
        return unknown("glm",
                       "could not resolve both quota windows (got %d TOKENS_LIMIT); "
                       "token rejected or unexpected payload" % len(token_limits),
                       level=(doc.get("data") or {}).get("level"))
    return out


# ── Codex ───────────────────────────────────────────────────────────────────
def read_codex():
    aj = os.path.join(os.environ.get("CODEX_HOME", os.path.expanduser("~/.codex")), "auth.json")
    try:
        d = json.load(open(aj))
        rtok = d["tokens"]["refresh_token"]
    except Exception as e:
        return unknown("codex", "auth.json unreadable: %s" % e, needs_login=True)

    body = json.dumps({"grant_type": "refresh_token",
                       "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
                       "refresh_token": rtok,
                       "scope": "openid profile email offline_access"}).encode()
    try:
        _, rbody = http_json("https://auth.openai.com/oauth/token", method="POST", data=body,
                             headers={"Content-Type": "application/json",
                                      "User-Agent": "codex_cli_rs/0.0.0 (leadv2-quota)"})
        tok = json.loads(rbody)
    except urllib.error.HTTPError as e:
        return unknown("codex", "refresh http %d" % e.code, needs_login=True)
    except Exception as e:
        return unknown("codex", "refresh: %s" % e, needs_login=True)

    access = tok.get("access_token")
    new_refresh = tok.get("refresh_token") or rtok
    if not access:
        return unknown("codex", "no access_token in refresh response", needs_login=True)

    # Rotation invalidated the old refresh_token — write the new one back so the
    # CLI's refresh chain survives. chmod 600. Token never printed/logged.
    wrote_back = False
    try:
        d["tokens"]["access_token"] = access
        d["tokens"]["refresh_token"] = new_refresh
        if tok.get("id_token"):
            d["tokens"]["id_token"] = tok["id_token"]
        d["last_refresh"] = iso_now()
        td = os.path.dirname(aj) or "."
        fd, tmp = tempfile.mkstemp(prefix=".auth.json.", dir=td)
        with os.fdopen(fd, "w") as f:
            json.dump(d, f, indent=2)
        os.chmod(tmp, 0o600)
        os.replace(tmp, aj)
        wrote_back = True
    except Exception:
        pass  # token still held in memory for the single usage call below

    try:
        _, ubody = http_json("https://chatgpt.com/backend-api/wham/usage",
                             headers={"Authorization": "Bearer " + access,
                                      "User-Agent": "codex_cli_rs/0.0.0 (leadv2-quota)"})
        u = json.loads(ubody)
    except urllib.error.HTTPError as e:
        return unknown("codex", "usage http %d" % e.code, refreshed=True, wrote_back=wrote_back)
    except Exception as e:
        return unknown("codex", "usage: %s" % e, refreshed=True, wrote_back=wrote_back)

    rl = u.get("rate_limit") or {}
    pw = rl.get("primary_window") or {}
    sw = rl.get("secondary_window")
    windows = []
    if pw:
        windows.append(with_window_truth({"kind": "primary", "used_percent": pw.get("used_percent"),
                        "limit_window_seconds": pw.get("limit_window_seconds"),
                        "reset_epoch": pw.get("reset_at"),
                        "reset_iso": iso_from_epoch(pw.get("reset_at")),
                        "limit_reached": rl.get("limit_reached")}, "used_percent"))
    if sw:
        windows.append(with_window_truth({"kind": "secondary", "used_percent": sw.get("used_percent"),
                        "limit_window_seconds": sw.get("limit_window_seconds"),
                        "reset_epoch": sw.get("reset_at"),
                        "reset_iso": iso_from_epoch(sw.get("reset_at"))}, "used_percent"))
    cr = u.get("credits") or {}
    return {"provider": "codex", "status": "ok", "plan_type": u.get("plan_type"),
            "fetched_at": iso_now(), "refreshed": True, "wrote_back": wrote_back,
            "limit_reached": rl.get("limit_reached"), "allowed": rl.get("allowed"),
            "windows": windows,
            "binding_window": binding_window({w["kind"]: w for w in windows}),
            "credits": {"has_credits": cr.get("has_credits"), "balance": cr.get("balance")}}


def _registry_keychain_services(registry_path=None):
    """Keychain service names actually named in the Claude multi-profile
    registry (claude-profiles.tsv).

    ARMS-CANNOT-LAUNCH-THEMSELVES-01 P5: an entry never named in the registry
    is not our account and must not enter util('claude') at all -- not as
    unknown, not as anything. Two stale keychain entries exist today
    (`default`, and one dir-hash suffix) that dilute the claude price this
    way; excluding them here is the fix, and it is reversible (nothing is
    deleted from the keychain -- see module note below).

    Registry format matches leadv2-claude-account-check.sh /
    leadv2-claude-profile-select.sh: TSV
    `label<TAB>config_dir<TAB>credential_source(optional)<TAB>expect(optional)`,
    blank lines and #-comments ignored. Only a `keychain:<service>` credential
    source contributes a service name -- a `file:` source has no keychain
    service to admit. Returns an EMPTY set (never raises) when the registry
    is missing/unreadable/empty -- the caller fails OPEN on that (today's
    unfiltered behaviour), never fails closed by excluding every account.
    """
    path = registry_path or os.environ.get(
        "LEADV2_CLAUDE_PROFILES_FILE",
        os.path.expanduser("~/.claude/state/leadv2/claude-profiles.tsv"))
    services = set()
    try:
        with open(path) as fh:
            for raw in fh:
                line = raw.rstrip("\n")
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) < 2:
                    continue
                cred = parts[2] if len(parts) > 2 else ""
                if cred.startswith("keychain:"):
                    services.add(cred[len("keychain:"):])
    except OSError:
        pass
    return services


# ── Anthropic ───────────────────────────────────────────────────────────────
def _keychain_services(prefix="Claude Code-credentials"):
    services = set()
    try:
        out = subprocess.check_output(["security", "dump-keychain"], stderr=subprocess.DEVNULL).decode()
        for line in out.splitlines():
            s = line.strip()
            if s.startswith('"svce"<blob>="'):
                sv = s.split('="', 1)[1].rstrip('"')
                if sv.startswith(prefix):
                    services.add(sv)
    except Exception:
        pass
    if not services:
        return {prefix}
    allowed = _registry_keychain_services()
    if not allowed:
        # Registry missing/unreadable/empty: fail OPEN, unfiltered -- same as
        # today's behaviour before this filter existed. A misconfigured or
        # not-yet-populated LEADV2_CLAUDE_PROFILES_FILE must never silently
        # drop every account to zero.
        return services
    # The unsuffixed service is the credential store Claude Code itself uses
    # for the CURRENT running session (resolve_active_account's
    # session_credential path depends on seeing it) -- always admitted
    # regardless of the registry, which only enumerates the multi-profile
    # SLOTS (personal/work), not the ambient session credential.
    allowed = allowed | {prefix}
    filtered = services & allowed
    return filtered or {prefix}


# CLAUDE-ACCOUNT-STATE-01 (ARMS-CANNOT-LAUNCH-THEMSELVES-01 P5): the live
# probe conflated two different facts into one `status=unknown` value --
# a genuinely dead credential, and a genuinely alive account whose usage
# ENDPOINT simply does not serve that account class. Live probe evidence,
# 2026-09-07T18:21Z: keychain entry dir-hash 5a3c2328 (registry label
# `work`, subscriptionType `team`) -> http 401 on /api/oauth/usage, while
# leadv2-claude-account-check.sh confirms the SAME slot's token/account/org
# resolve fine (`slot=work dir_hash=5a3c2328 ... sub=team
# tier=default_claude_max_5x`) -- TEAM-ACCOUNT-QUOTA-WINDOW-UNPARSED-01's own
# named class. Conflating that with a truly dead credential means it eats
# UNKNOWN_PROBE_PENALTY forever even though the account is USABLE; pricing
# it as free headroom instead would be worse (no usage number exists to
# price from). Both are wrong -- hence a third state.
ACCOUNT_STATE_OK = "ok"
ACCOUNT_STATE_UNMETERED = "unmetered"
ACCOUNT_STATE_UNKNOWN = "unknown"

# The state a caller who cannot invent a real usage number should price an
# unmetered account at -- conservative (well under any live-measured
# account's typical remaining headroom), never a measured value. Exposed as
# DATA for a caller (the arbiter, part B) to consult; this module does not
# wire it into any pricing decision itself.
CLAUDE_ACCOUNT_STATE_PRICING = {
    ACCOUNT_STATE_OK:        {"penalty": 0,  "priced_from": "measured"},
    ACCOUNT_STATE_UNMETERED: {"penalty": 0,  "priced_from": "configured_allowance_conservative"},
    ACCOUNT_STATE_UNKNOWN:   {"penalty": 50, "priced_from": "unknown_probe_penalty"},
}


def classify_account_state(subscription_type, http_code):
    """(subscription_type, http_code) -> "ok" | "unmetered" | "unknown".

    http_code is the /api/oauth/usage response code for an account whose
    credential DID resolve an access token (read_anthropic only reaches this
    classification once `accessToken` was present -- a token-less entry never
    gets here at all, which is the "credential dead" case: it is excluded
    upstream, not classified `unknown` by this function).

    `unmetered` fires for the classes this has been MEASURED on: token-
    resolved accounts whose usage endpoint answers 401 anyway. team (measured
    2026-09-07, registry label `work`, tier default_claude_max_5x, token and
    org resolving fine) and max (measured 2026-09-04: the active max_20x
    entry read http 401 while a DIFFERENT entry of the SAME account returned
    a freshly-probed pct -- lib/leadv2-route-arbiter.sh:319-333 records it;
    and 2026-09-08 the live probe answered 401 on every max entry -- the D1
    mission input whose consumer half merged as fe491bff). This membership is
    a list of measured classes, NOT a distinguishing test: no signal at
    classification time separates a dead credential from an unmetered
    account. The probed token is a STORED one (the DPoP refresh is not wired,
    see the no-accounts branch below), so a 401 here measures only "this
    token cannot read usage data", never "this credential cannot launch" --
    a launch is the only test, and a failed launch is already parked by the
    arbiter's failure-memory/lockout machinery. pro+401 stays `unknown` as
    the guarded boundary (tests/test-unmetered-account-not-penalised.sh):
    never measured live, and widening past it is the founder's ruling, not
    this function's.
    """
    if http_code == 200:
        return ACCOUNT_STATE_OK
    if http_code == 401 and subscription_type in ("team", "max"):
        return ACCOUNT_STATE_UNMETERED
    return ACCOUNT_STATE_UNKNOWN


def _read_keychain(service):
    try:
        raw = subprocess.check_output(["security", "find-generic-password", "-s", service, "-w"],
                                      stderr=subprocess.STDOUT).decode()
        return json.loads(raw)
    except Exception:
        return None


def _read_credential_file(path):
    """CLAUDE-MULTIPROFILE-QUOTA-02: read a keychain-format blob from a file.

    A profile whose credential source is `file:` carries the same JSON blob a
    keychain entry holds (claudeAiOauth et al), just on disk.  Read-only; the
    blob is held in process memory exactly like a keychain secret — never
    printed, logged, or written to any cache file.
    """
    try:
        with open(path) as fh:
            return json.load(fh)
    except Exception:
        return None


def _anthropic_kv():
    """Last captured rate_limit_info from history.db kv (secondary signal)."""
    db = os.environ.get("LEADV2_BURN_DB", os.path.expanduser("~/.claude/burn/history.db"))
    if not os.path.exists(db):
        return None
    try:
        out = subprocess.check_output(
            ["sqlite3", db,
             "SELECT value FROM kv WHERE key='rate_limit_anthropic' ORDER BY rowid DESC LIMIT 1;"],
            stderr=subprocess.DEVNULL).decode().strip()
        return json.loads(out) if out else None
    except Exception:
        return None


def configured_active_account():
    """Read only the small scalar needed before the v2 router exists.

    PyYAML is intentionally not a runtime dependency of this credential reader;
    the config syntax here is the top-level scalar in router_v2.
    """
    config = os.environ.get("LEADV2_ROUTING_CONFIG",
                            os.path.join(os.path.dirname(__file__), "..", "config",
                                         "leadv2-routing.yaml"))
    try:
        in_router_v2 = False
        with open(config) as fh:
            for raw in fh:
                if raw.strip() == "router_v2:":
                    in_router_v2 = True
                    continue
                if in_router_v2:
                    if raw and not raw[0].isspace() and raw.strip() and not raw.lstrip().startswith("#"):
                        break
                    stripped = raw.strip()
                    if stripped.startswith("active_account:"):
                        return stripped.split(":", 1)[1].strip().strip("'\"") or "max_20x"
    except OSError:
        pass
    return "max_20x"


def account_label(service, suffix, subscription_type, tier, active_pin):
    """Produce a stable, human-readable account label without exposing IDs."""
    # The unsuffixed service is the credential store Claude Code itself uses.
    # Its configuration pin makes the expected active account explicit.
    if service == "Claude Code-credentials":
        return active_pin
    candidates = " ".join(str(v or "") for v in (suffix, subscription_type, tier)).lower()
    compact = candidates.replace("-", "_").replace(" ", "_")
    if "max_20" in compact or "20x" in compact:
        return "max_20x"
    if "max_5" in compact or "5x" in compact or "team" in compact:
        return "max_5x"
    return str(suffix or "unknown")


def resolve_active_account(accounts, active_pin):
    """Mark exactly one account as active and expose how it was resolved.

    A running session can provide its credential service explicitly.  In normal
    Claude Code operation the unsuffixed credential service is that session's
    service.  If neither is available, the config pin is used visibly rather
    than silently guessing from the most-used account.
    """
    forced = os.environ.get("LEADV2_ANTHROPIC_FORCE_UNRESOLVED") == "1"
    requested = os.environ.get("LEADV2_ANTHROPIC_ACTIVE_SERVICE") or \
        os.environ.get("CLAUDE_CODE_CREDENTIALS_SERVICE")
    if not forced:
        if requested:
            selected = next((a for a in accounts if a.get("service") == requested), None)
            if selected:
                selected["active"] = True
                return "session_credential"
        selected = next((a for a in accounts if a.get("service") == "Claude Code-credentials"), None)
        if selected:
            selected["active"] = True
            return "session_credential"

    selected = next((a for a in accounts if a.get("account_label") == active_pin), None)
    if selected is None:
        # A pin selects an account label, not a quota value.  If an old keychain
        # entry has no recognizable label, retain fail-open behavior while making
        # the unresolved provenance explicit for downstream journalling.
        selected = accounts[0] if accounts else None
    if selected:
        selected["active"] = True
    return "pinned_unresolved"


def read_anthropic(credential_file=None):
    accounts = []
    active_pin = configured_active_account()
    # CLAUDE-MULTIPROFILE-QUOTA-02: --credential-file swaps the keychain
    # enumeration for one on-disk blob (single-entry accounts list).  The
    # default path (no flag) is unchanged.
    active_service = os.environ.get("LEADV2_ANTHROPIC_ACTIVE_SERVICE", "").strip()
    if credential_file:
        blob = _read_credential_file(credential_file)
        sources = [("file:%s" % credential_file, blob)] if isinstance(blob, dict) else []
    elif active_service:
        # A multi-profile registry explicitly selects this keychain service.
        # Do not enumerate by the default service-name prefix in that mode.
        sources = [(active_service, _read_keychain(active_service))]
    else:
        sources = [(sv, _read_keychain(sv)) for sv in sorted(_keychain_services())]
    for sv, blob in sources:
        if not isinstance(blob, dict):
            continue
        o = blob.get("claudeAiOauth") or {}
        at = o.get("accessToken")
        if not at:
            continue  # no token bytes at all -- nothing to try
        # TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01 D3: claudeAiOauth.expiresAt
        # used to gate this loop (`ea and ea > now_ms`) before ever attempting
        # the call below.  Measured live 2026-09-03: expiresAt was in the past
        # on every one of six registered keychain entries, including the one
        # actively serving a running session -- the CLI refreshes the access
        # token in-process without ever rewriting expiresAt back to Keychain,
        # so the field is not a liveness signal here.  The usage call below IS
        # the liveness test; a token that is truly dead comes back 401/403 and
        # lands in the existing status=unknown branch, same as any other probe
        # failure (429, parse error, ...) -- one bad field never excludes an
        # account that could still return a working read.
        code, body, err = None, "", None
        try:
            code, body = http_json("https://api.anthropic.com/api/oauth/usage",
                                   headers={"Authorization": "Bearer " + at,
                                            "User-Agent": "claude-code/1.0 (leadv2-quota)"})
        except urllib.error.HTTPError as e:
            code = e.code
            if code != 429:
                try:
                    body = e.read().decode()
                except Exception:
                    body = ""
        except Exception as e:
            err = str(e)

        if credential_file:
            suffix = "file"
        elif sv == "Claude Code-credentials":
            suffix = "default"
        else:
            suffix = sv.rsplit("-", 1)[-1]
        acct = {"entry_suffix": suffix, "service": sv,
                "subscription_type": o.get("subscriptionType"),
                "tier": o.get("rateLimitTier"), "http": code,
                "account_label": account_label(sv, suffix, o.get("subscriptionType"),
                                               o.get("rateLimitTier"), active_pin),
                "active": False}
        if code == 200:
            try:
                u = json.loads(body)
                fh = u.get("five_hour") or {}
                sd = u.get("seven_day") or {}
                fh_window = with_window_truth({"pct": fh.get("utilization"),
                                               "reset_iso": fh.get("resets_at")}, "pct")
                sd_window = with_window_truth({"pct": sd.get("utilization"),
                                               "reset_iso": sd.get("resets_at")}, "pct")
                acct.update({"status": "ok",
                             "account_state": ACCOUNT_STATE_OK,
                             "five_hour_pct": fh.get("utilization"),
                             "five_hour_reset_iso": fh.get("resets_at"),
                             "seven_day_pct": sd.get("utilization"),
                             "seven_day_reset_iso": sd.get("resets_at"),
                             "five_hour": fh_window,
                             "seven_day": sd_window,
                             "binding_window": binding_window({"five_hour": fh_window,
                                                               "seven_day": sd_window}),
                             "limits": u.get("limits")})
            except Exception as ex:
                acct.update({"status": "unknown", "account_state": ACCOUNT_STATE_UNKNOWN,
                             "error": "parse: %s" % ex})
        elif code == 429:
            acct.update({"status": "unknown", "account_state": ACCOUNT_STATE_UNKNOWN,
                         "error": "429 rate_limited (reported as unknown, NEVER 0)"})
        else:
            # ARMS-CANNOT-LAUNCH-THEMSELVES-01 P5: `status` is left untouched
            # (still "unknown") for full backward compat -- only the ADDITIVE
            # `account_state` field distinguishes team-401-unmetered from a
            # genuinely dead credential. No existing consumer of `status`
            # changes behaviour from this edit; only a consumer that reads
            # the new field opts in (part B's arbiter wiring).
            acct.update({"status": "unknown",
                         "account_state": classify_account_state(o.get("subscriptionType"), code),
                         "error": err or ("http %s" % code)})
        accounts.append(acct)

    if not accounts:
        out = unknown("anthropic",
                      "no fresh in-process access token in any Claude Code-credentials* keychain entry; "
                      "DPoP refresh (platform.claude.com/v1/oauth/token) is not wired — start or recently "
                      "use a Claude session to refresh in-process, then re-run", accounts=[], needs_session=True)
        kv = _anthropic_kv()
        if kv:
            out["rate_limit_info_captured"] = kv
            out["note"] = ("reporting the last rate_limit_info captured into history.db kv "
                           "(rate_limit_anthropic) as a fallback signal")
        return out
    resolution = resolve_active_account(accounts, active_pin)
    active = next((a for a in accounts if a.get("active")), None)
    return {"provider": "anthropic", "status": "ok", "accounts": accounts,
            "active_account": active.get("account_label") if active else active_pin,
            "account_resolution": resolution,
            # This is intentionally pipe-friendly for the router's future journal event.
            "account_resolution_journal": "account=%s" % resolution,
            "binding_window": active.get("binding_window") if active else None,
            "fetched_at": iso_now()}


READERS = {"glm": read_glm, "codex": read_codex, "anthropic": read_anthropic}


def normalize_payload(obj):
    """Upgrade a cached pre-v2 payload in memory before a consumer sees it."""
    if not isinstance(obj, dict):
        return obj
    if obj.get("status") != "ok":
        obj.setdefault("usable_now", None)
        obj.setdefault("binding_window", None)
        return obj
    provider = obj.get("provider")
    if provider == "glm":
        for name in ("five_hour", "weekly"):
            obj[name] = with_window_truth(obj.get(name), "pct")
        obj["binding_window"] = binding_window({name: obj.get(name)
                                                 for name in ("five_hour", "weekly")})
    elif provider == "codex":
        windows = []
        for window in obj.get("windows") or []:
            enriched = with_window_truth(window, "used_percent")
            if enriched:
                windows.append(enriched)
        obj["windows"] = windows
        obj["binding_window"] = binding_window({w.get("kind", "unknown"): w for w in windows})
    elif provider == "anthropic":
        accounts = obj.get("accounts") or []
        pin = configured_active_account()
        for account in accounts:
            account["account_label"] = account.get("account_label") or account_label(
                account.get("service"), account.get("entry_suffix"), account.get("subscription_type"),
                account.get("tier"), pin)
            account["five_hour"] = with_window_truth(
                account.get("five_hour") or {"pct": account.get("five_hour_pct"),
                                               "reset_iso": account.get("five_hour_reset_iso")}, "pct")
            account["seven_day"] = with_window_truth(
                account.get("seven_day") or {"pct": account.get("seven_day_pct"),
                                               "reset_iso": account.get("seven_day_reset_iso")}, "pct")
            account["binding_window"] = binding_window({"five_hour": account["five_hour"],
                                                        "seven_day": account["seven_day"]})
        if len([a for a in accounts if a.get("active")]) != 1:
            for account in accounts:
                account["active"] = False
            obj["account_resolution"] = resolve_active_account(accounts, pin)
        obj.setdefault("account_resolution", "session_credential")
        obj["account_resolution_journal"] = "account=%s" % obj["account_resolution"]
        active = next((a for a in accounts if a.get("active")), None)
        obj["active_account"] = active.get("account_label") if active else pin
        obj["binding_window"] = active.get("binding_window") if active else None
    return obj


def main():
    args = sys.argv[1:]
    # ARMS-CANNOT-LAUNCH-THEMSELVES-01 P5: standalone classifier verb, handled
    # BEFORE the READERS dispatch below -- it names no provider bucket, it is
    # a pure function over two CLI-supplied values, useful to a caller (or a
    # test) that wants classify_account_state() without a live probe.
    if args and args[0] == "classify-account":
        rest = args[1:]
        if len(rest) != 2:
            sys.stderr.write("usage: leadv2-quota-read.py classify-account "
                             "<subscription_type|-> <http_code>\n")
            sys.exit(2)
        sub_raw, code_raw = rest
        sub = None if sub_raw == "-" else sub_raw
        try:
            code = int(code_raw)
        except ValueError:
            sys.stderr.write("http_code must be an integer\n")
            sys.exit(2)
        state = classify_account_state(sub, code)
        print(json.dumps({"account_state": state,
                          "pricing": CLAUDE_ACCOUNT_STATE_PRICING[state]}))
        return
    if not args or args[0] not in READERS:
        sys.stderr.write("usage: leadv2-quota-read.py glm|codex|anthropic [--no-cache] "
                         "[--credential-file <path> (anthropic only)] | classify-account "
                         "<subscription_type|-> <http_code>\n")
        sys.exit(2)
    provider = args[0]
    # CLAUDE-MULTIPROFILE-QUOTA-02: additive flag; absent = byte-identical to
    # the previous behaviour, so no existing caller changes.
    credential_file = None
    if "--credential-file" in args:
        if provider != "anthropic":
            sys.stderr.write("--credential-file applies to anthropic only\n")
            sys.exit(2)
        i = args.index("--credential-file")
        if i + 1 >= len(args):
            sys.stderr.write("--credential-file requires a path\n")
            sys.exit(2)
        credential_file = args[i + 1]
    if "--no-cache" not in args:
        cached = cache_get(provider)
        if cached is not None:
            cached = normalize_payload(cached)
            cache_put(provider, cached)
            print(json.dumps(cached))
            return
    obj = normalize_payload(READERS[provider](credential_file)
                            if provider == "anthropic" else READERS[provider]())
    obj.setdefault("provider", provider)
    obj.setdefault("fetched_at", iso_now())
    cache_put(provider, obj)
    print(json.dumps(obj))


if __name__ == "__main__":
    main()
