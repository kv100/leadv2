#!/usr/bin/env python3
"""
leadv2-quota-daemon.py — W1-QUOTA-DAEMON-01 part B: always-live quota daemon
(founder proposal 2026-09-09, PRE-WAVES-PLAN §1 item 1.5).

One process logs in once and serves remaining quota for every source at any
second, with no interactive login per request.

FEEDS, never replaces (standing rule, founder 2026-09-09): every number still
comes from leadv2-quota-read.py — the single source of provider truth (codex
OAuth refresh rotation + write-back, anthropic keychain enumeration, GLM
window disambiguation all live there). The existing scorer is EXTENDED, not
rewritten: leadv2-claude-profile-select.sh probes each profile by invoking
leadv2-quota-read.py, whose payloads lib/leadv2-claude-profile-pick.py scores
on each account's BINDING window (usable_now = remaining_pct / hours_to_reset,
five_hour vs seven_day never collapsed into max()). Neither file changes here;
instead leadv2-quota-read.py consults this daemon's snapshot before doing its
own live call, so those per-profile probes become instant snapshot reads with
zero per-dispatch logins. The daemon also publishes per-model (GLM) and
per-tier (Codex) granularity — part A rides along because it lives in the
same reader.

Honest limit, recorded up front (not discovered later): this daemon does NOT
fix the lead's own window. The lead is an interactive session and cannot
switch accounts mid-flight; that is PRE-WAVES-PLAN §3, separate work. This
daemon covers measurement and routing of DISPATCHED arms.

Codex rotation safety: the daemon polls the usage endpoint on its cadence but
NEVER refreshes on that cadence — leadv2-quota-read.py reuses the on-disk
access token for LEADV2_QUOTA_CODEX_ACCESS_REUSE_S (default 45 min) and only
rotates when it is stale, so a 45 s poll cadence still rotates ~once an hour,
and it re-reads auth.json before every rotation so a concurrent codex CLI
refresh is never clobbered.

Fail-open semantics (unchanged from the reader): a failing source keeps its
last real payload and its age keeps growing — a number is never fabricated,
unknown is never reported as 0%, and staleness is always visible.

Usage:
    leadv2-quota-daemon.py start [--foreground]   # idempotent singleton
    leadv2-quota-daemon.py stop                   # socket shutdown + cleanup
    leadv2-quota-daemon.py status
    leadv2-quota-daemon.py query [--max-age 60] [--json] [--source NAME]

State dir (env LEADV2_QUOTA_DAEMON_DIR,
default ~/.claude/state/leadv2/quota-daemon):
    snapshot.json  atomically replaced after every source refresh; the DATA
                   plane every reader (leadv2-quota-read.py consult, tests)
                   consumes — no socket needed
    daemon.pid / daemon.sock / daemon.log

Env:
    LEADV2_QUOTA_READ                     reader to poll (tests fake it)
    LEADV2_QUOTA_DAEMON_INTERVAL_GLM/CODEX/ANTHROPIC   poll cadence s
                                           (default 45/45/55 — all under the
                                           60 s freshness the acceptance names)
    LEADV2_QUOTA_DAEMON_QUERY_TIMEOUT_S   bounded auto-start wait (default 20)
    LEADV2_CLAUDE_PROFILES_FILE           multi-profile registry (file:/keychain:
                                           sources become their own polled keys)
    LEADV2_QUOTA_DAEMON=0                 disables the reader-side consult
"""
import datetime
import json
import os
import signal
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time

UTC = datetime.timezone.utc
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_READER = os.path.join(SCRIPT_DIR, "leadv2-quota-read.py")
STATE_DIR = os.environ.get(
    "LEADV2_QUOTA_DAEMON_DIR",
    os.path.expanduser("~/.claude/state/leadv2/quota-daemon"))
SNAPSHOT = os.path.join(STATE_DIR, "snapshot.json")
PIDFILE = os.path.join(STATE_DIR, "daemon.pid")
SOCKPATH = os.path.join(STATE_DIR, "daemon.sock")
LOGFILE = os.path.join(STATE_DIR, "daemon.log")
READER = os.environ.get("LEADV2_QUOTA_READ", DEFAULT_READER)

INTERVALS = {
    "glm": int(os.environ.get("LEADV2_QUOTA_DAEMON_INTERVAL_GLM", "45")),
    "codex": int(os.environ.get("LEADV2_QUOTA_DAEMON_INTERVAL_CODEX", "45")),
    "anthropic": int(os.environ.get("LEADV2_QUOTA_DAEMON_INTERVAL_ANTHROPIC", "55")),
}
QUERY_TIMEOUT_S = float(os.environ.get("LEADV2_QUOTA_DAEMON_QUERY_TIMEOUT_S", "20"))
POLL_TIMEOUT_S = 30.0
LOG_MAX_BYTES = 1_000_000

# sources: {"key": {"provider": p, "interval": s, "extra_env": {...},
#                   "args": [...]}}
STATE = {"sources": {}, "updated_at": {}, "last_error": {},
         "started_at": time.time()}
LOCK = threading.Lock()
SHUTDOWN = threading.Event()


def iso_now():
    return datetime.datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def log(line):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        if os.path.exists(LOGFILE) and os.path.getsize(LOGFILE) > LOG_MAX_BYTES:
            with open(LOGFILE) as f:
                tail = f.read()[-200_000:]
            with open(LOGFILE, "w") as f:
                f.write(tail)
        with open(LOGFILE, "a") as f:
            f.write("%s %s\n" % (iso_now(), line))
    except Exception:
        pass


# ── source set ───────────────────────────────────────────────────────────────
def registry_profiles():
    """[(credential_source, value)] from the multi-profile registry.

    Same file and format as quota-read.py's _registry_keychain_services
    (~/.claude/state/leadv2/claude-profiles.tsv, TSV with an optional third
    column `keychain:<service>` / `file:<path>`). Unreadable -> [] (the
    default anthropic enumeration poll still runs; only per-profile keys are
    absent).
    """
    path = os.environ.get(
        "LEADV2_CLAUDE_PROFILES_FILE",
        os.path.expanduser("~/.claude/state/leadv2/claude-profiles.tsv"))
    out = []
    try:
        with open(path) as fh:
            for raw in fh:
                line = raw.rstrip("\n")
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) < 3:
                    continue
                cred = parts[2].strip()
                if cred.startswith("keychain:") and len(cred) > len("keychain:"):
                    out.append(("keychain", cred[len("keychain:"):]))
                elif cred.startswith("file:") and len(cred) > len("file:"):
                    out.append(("file", cred[len("file:"):]))
    except OSError:
        pass
    return out


def discover_sources():
    """The full polled key set, rediscovered so registry edits propagate."""
    sources = {
        "glm": {"provider": "glm", "interval": INTERVALS["glm"],
                "extra_env": {}, "args": []},
        "codex": {"provider": "codex", "interval": INTERVALS["codex"],
                  "extra_env": {}, "args": []},
        # Default enumeration (registry-filtered keychain scan) — what
        # quota-live.sh's `anthropic` bucket and the arbiter read.
        "anthropic": {"provider": "anthropic", "interval": INTERVALS["anthropic"],
                      "extra_env": {}, "args": []},
    }
    # Per-profile keys — the exact shape leadv2-claude-profile-select.sh
    # probes (one service via LEADV2_ANTHROPIC_ACTIVE_SERVICE, or one
    # credential file via --credential-file), so a consult returns precisely
    # what a direct probe would have.
    for kind, value in registry_profiles():
        if kind == "keychain":
            key = "anthropic:service:" + value
            sources[key] = {"provider": "anthropic",
                            "interval": INTERVALS["anthropic"],
                            "extra_env": {"LEADV2_ANTHROPIC_ACTIVE_SERVICE": value},
                            "args": []}
        else:
            key = "anthropic:file:" + value
            sources[key] = {"provider": "anthropic",
                            "interval": INTERVALS["anthropic"],
                            "extra_env": {},
                            "args": ["--credential-file", value]}
    return sources


# ── snapshot (data plane) ────────────────────────────────────────────────────
def write_snapshot():
    with LOCK:
        snap = {"daemon": {"pid": os.getpid(), "started_at": STATE["started_at"],
                           "version": 1},
                "sources": dict(STATE["sources"]),
                "updated_at": dict(STATE["updated_at"]),
                "last_error": dict(STATE["last_error"]),
                "written_at": iso_now()}
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix="snapshot.", dir=STATE_DIR)
        with os.fdopen(fd, "w") as f:
            json.dump(snap, f)
        os.replace(tmp, SNAPSHOT)
    except Exception as e:
        log("snapshot write failed: %s" % e)


def read_snapshot():
    try:
        with open(SNAPSHOT) as f:
            return json.load(f)
    except Exception:
        return None


# ── PRICE-THE-ARM-PER-PROVIDER-01 (dispatch-f8880421) ────────────────────────
# Anthropic already self-logs every poll to rate_limit_history
# (~/.claude/burn/history.db, a DIFFERENT writer). glm and codex have no
# equivalent: this daemon's snapshot.json is a single current-value file, not
# a history, so leadv2-drain-weights.py --provider {glm,codex} has nothing to
# fit against without one. provider_quota_history is that table -- append-only,
# one row per (provider, window) per poll, storing USED percent (never
# remaining_pct: this table answers "how much got spent", the same question
# ecost()/provider_cost() ask, not "how much is left").
_BURN_DB = os.path.expanduser(os.environ.get("LEADV2_BURN_DB", "~/.claude/burn/history.db"))


def _iso_to_epoch(iso):
    try:
        return datetime.datetime.fromisoformat(str(iso).replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def _ensure_quota_history_table(conn):
    conn.execute(
        "CREATE TABLE IF NOT EXISTS provider_quota_history ("
        "captured_epoch REAL NOT NULL, provider TEXT NOT NULL, window TEXT NOT NULL, "
        "used_pct REAL, reset_epoch REAL, source TEXT NOT NULL)")


def _quota_history_rows(provider, payload):
    now = time.time()
    rows = []
    if provider == "glm":
        for name in ("five_hour", "weekly"):
            w = payload.get(name) or {}
            if isinstance(w, dict) and w.get("pct") is not None:
                rows.append((now, "glm", name, w.get("pct"),
                             _iso_to_epoch(w.get("reset_iso")), "leadv2-quota-daemon"))
    elif provider == "codex":
        for w in payload.get("windows") or []:
            if isinstance(w, dict) and w.get("used_percent") is not None:
                rows.append((now, "codex", w.get("kind") or "unknown", w.get("used_percent"),
                             _iso_to_epoch(w.get("reset_iso")), "leadv2-quota-daemon"))
    return rows


def append_quota_history(provider, payload):
    """Best-effort: a history-append failure must never affect quota serving
    (same fail-open discipline as poll_source itself)."""
    if provider not in ("glm", "codex"):
        return
    rows = _quota_history_rows(provider, payload)
    if not rows:
        return
    try:
        os.makedirs(os.path.dirname(_BURN_DB), exist_ok=True)
        conn = sqlite3.connect(_BURN_DB, timeout=5)
        try:
            conn.execute("PRAGMA busy_timeout=3000")
            _ensure_quota_history_table(conn)
            conn.executemany(
                "INSERT INTO provider_quota_history "
                "(captured_epoch, provider, window, used_pct, reset_epoch, source) "
                "VALUES (?,?,?,?,?,?)", rows)
            conn.commit()
        finally:
            conn.close()
    except Exception as e:
        log("provider_quota_history append failed (%s): %s" % (provider, str(e)[:150]))


def poll_source(key, spec):
    env = dict(os.environ)
    # Anti-recursion: the reader must not consult this daemon's own snapshot.
    env["LEADV2_QUOTA_DAEMON"] = "0"
    env.update(spec["extra_env"])
    cmd = [sys.executable, READER, spec["provider"], "--no-cache"] + spec["args"]
    try:
        out = subprocess.check_output(cmd, env=env, timeout=POLL_TIMEOUT_S)
        payload = json.loads(out.decode())
    except Exception as e:
        with LOCK:
            STATE["last_error"][key] = str(e)[:200]
        log("poll %s ERROR %s" % (key, str(e)[:120]))
        return  # keep the previous payload; its age keeps growing, honestly
    with LOCK:
        STATE["sources"][key] = payload
        STATE["updated_at"][key] = time.time()
        STATE["last_error"].pop(key, None)
    log("poll %s ok status=%s" % (key, payload.get("status", "?")))
    append_quota_history(spec["provider"], payload)
    write_snapshot()


def poller_loop(key, spec):
    # First poll immediately so a freshly started daemon serves real numbers
    # within seconds, then keep the cadence.
    while not SHUTDOWN.is_set():
        poll_source(key, spec)
        SHUTDOWN.wait(spec["interval"])
    # Registry edits (new/removed profile slots) must propagate without a
    # daemon restart: the anthropic poller rescans the source set between
    # cycles. Keys are immutable per slot, so a removed profile simply stops
    # refreshing and its age grows.


def anthropic_supervisor():
    """Rescan-aware loop for the anthropic family (default + per-profile keys).

    glm/codex keys are static; anthropic keys depend on the multi-profile
    registry, which can change while the daemon lives. Every cycle the
    discovered set is re-pulled: new slots get a poller thread, and this
    supervisor owns only the default `anthropic` key.
    """
    spawned = set()
    while not SHUTDOWN.is_set():
        discovered = discover_sources()
        for key, spec in discovered.items():
            if key == "anthropic" or key in spawned:
                continue
            t = threading.Thread(target=poller_loop, args=(key, spec), daemon=True)
            t.start()
            spawned.add(key)
            log("registered profile source %s" % key)
        poll_source("anthropic", discovered["anthropic"])
        SHUTDOWN.wait(INTERVALS["anthropic"])
    # Stale keys from removed registry slots: left in place, their age grows;
    # consults (freshness-checked) simply stop hitting them.


def start_pollers():
    for key in ("glm", "codex"):
        spec = discover_sources()[key]
        threading.Thread(target=poller_loop, args=(key, spec), daemon=True).start()
    threading.Thread(target=anthropic_supervisor, daemon=True).start()


# ── socket (control plane) ──────────────────────────────────────────────────
def socket_request(req):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(3.0)
        s.connect(SOCKPATH)
        s.sendall(json.dumps(req).encode() + b"\n")
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        s.close()
        return json.loads(buf.decode().strip() or "{}")
    except Exception:
        return None


def serve():
    try:
        if os.path.exists(SOCKPATH):
            os.unlink(SOCKPATH)
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(SOCKPATH)
        srv.listen(16)
        srv.settimeout(1.0)
    except Exception as e:
        log("socket bind failed: %s" % e)
        return
    while not SHUTDOWN.is_set():
        try:
            conn, _ = srv.accept()
        except socket.timeout:
            continue
        except OSError:
            break
        try:
            conn.settimeout(5.0)
            buf = b""
            while b"\n" not in buf:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                buf += chunk
            req = json.loads(buf.decode().strip() or "{}")
            op = req.get("op")
            if op == "shutdown":
                conn.sendall((json.dumps(
                    {"ok": True, "shutting_down": True, "pid": os.getpid()}) + "\n").encode())
                conn.close()
                SHUTDOWN.set()
                break
            elif op == "status":
                with LOCK:
                    status = {"pid": os.getpid(),
                              "started_at": STATE["started_at"],
                              "uptime_s": round(time.time() - STATE["started_at"], 1),
                              "sources": sorted(STATE["sources"]),
                              "updated_at": dict(STATE["updated_at"]),
                              "last_error": dict(STATE["last_error"])}
                conn.sendall((json.dumps(status) + "\n").encode())
            elif op == "query":
                with LOCK:
                    payload = {"daemon": {"pid": os.getpid()},
                               "sources": dict(STATE["sources"]),
                               "updated_at": dict(STATE["updated_at"]),
                               "last_error": dict(STATE["last_error"]),
                               "served_at": iso_now()}
                conn.sendall((json.dumps(payload) + "\n").encode())
            else:
                conn.sendall(b'{"error": "unknown op"}\n')
        except Exception as e:
            try:
                conn.sendall((json.dumps({"error": str(e)}) + "\n").encode())
            except Exception:
                pass
        finally:
            try:
                conn.close()
            except Exception:
                pass
    try:
        os.unlink(SOCKPATH)
    except OSError:
        pass


def cleanup_pidfile():
    try:
        os.unlink(PIDFILE)
    except OSError:
        pass


# ── CLI verbs ───────────────────────────────────────────────────────────────
def daemon_alive():
    resp = socket_request({"op": "status"})
    if isinstance(resp, dict) and resp.get("pid"):
        return resp
    return None


def cmd_start(foreground=False):
    alive = daemon_alive()
    if alive:
        print("leadv2-quota-daemon already running (pid %s)" % alive["pid"])
        return 0
    os.makedirs(STATE_DIR, exist_ok=True)
    if foreground:
        with open(PIDFILE, "w") as f:
            f.write(str(os.getpid()))
        signal.signal(signal.SIGTERM, lambda *_: SHUTDOWN.set())
        signal.signal(signal.SIGINT, lambda *_: SHUTDOWN.set())
        log("daemon starting (pid %d, reader %s)" % (os.getpid(), READER))
        start_pollers()
        try:
            serve()
        finally:
            cleanup_pidfile()
            log("daemon stopped")
        return 0
    logf = open(LOGFILE, "a")
    subprocess.Popen([sys.executable, os.path.abspath(__file__), "start", "--foreground"],
                     stdout=logf, stderr=logf, stdin=subprocess.DEVNULL,
                     start_new_session=True)
    deadline = time.time() + QUERY_TIMEOUT_S
    while time.time() < deadline:
        alive = daemon_alive()
        if alive:
            print("leadv2-quota-daemon started (pid %s)" % alive["pid"])
            return 0
        time.sleep(0.25)
    print("leadv2-quota-daemon did not come up within %.0fs (see %s)"
          % (QUERY_TIMEOUT_S, LOGFILE), file=sys.stderr)
    return 4


def cmd_stop():
    resp = socket_request({"op": "shutdown"})
    if resp is None:
        cleanup_pidfile()
        print("leadv2-quota-daemon not running (cleaned pidfile/socket if any)")
        return 0
    pid = resp.get("pid")
    deadline = time.time() + 10
    while time.time() < deadline:
        if daemon_alive() is None:
            break
        time.sleep(0.2)
    if daemon_alive() is not None and pid:
        try:
            os.kill(int(pid), signal.SIGTERM)
        except Exception:
            pass
    print("leadv2-quota-daemon stopped (was pid %s)" % pid)
    return 0


def cmd_status():
    alive = daemon_alive()
    if not alive:
        print("leadv2-quota-daemon: not running")
        return 1
    now = time.time()
    print("leadv2-quota-daemon: pid %s, uptime %.0fs" % (alive["pid"], alive["uptime_s"]))
    for key in sorted(alive.get("updated_at", {})):
        age = now - alive["updated_at"][key]
        err = alive.get("last_error", {}).get(key)
        print("  %-60s age %6.1fs%s" % (key, age, (" ERROR " + err) if err else ""))
    return 0


def _age(payload, key):
    ts = (payload.get("updated_at") or {}).get(key)
    return (time.time() - ts) if isinstance(ts, (int, float)) else None


def _windows_summary(provider, payload):
    """[(window_name, remaining_pct, hours_to_reset)] for one provider payload."""
    rows = []
    if provider == "glm":
        for name in ("five_hour", "weekly"):
            w = payload.get(name) or {}
            if w:
                rows.append((name, w.get("remaining_pct"), w.get("hours_to_reset")))
    elif provider == "codex":
        for w in payload.get("windows") or []:
            rows.append((w.get("kind"), w.get("remaining_pct"), w.get("hours_to_reset")))
    elif provider == "anthropic":
        for a in payload.get("accounts") or []:
            for name, w in (("five_hour", a.get("five_hour") or {}),
                            ("seven_day", a.get("seven_day") or {})):
                if w:
                    rows.append(("%s/%s" % (a.get("account_label", "?"), name),
                                 w.get("remaining_pct"), w.get("hours_to_reset")))
    return rows


def cmd_query(max_age, as_json, source):
    payload = socket_request({"op": "query"})
    if payload is None:
        payload = read_snapshot()
        if payload and payload.get("daemon", {}).get("pid"):
            payload["from_file"] = True
    if payload is None or not payload.get("sources"):
        # Auto-start so a single command always answers (the acceptance's
        # "one command"), then wait bounded for the first fresh cycle.
        rc = cmd_start()
        if rc != 0:
            return rc
        deadline = time.time() + QUERY_TIMEOUT_S
        while time.time() < deadline:
            payload = socket_request({"op": "query"})
            if payload and payload.get("sources"):
                break
            time.sleep(0.5)
    if not payload or not payload.get("sources"):
        print("leadv2-quota-daemon: no snapshot available", file=sys.stderr)
        return 4
    stale = []
    now = time.time()
    keys = [source] if source else sorted(payload["sources"])
    for key in keys:
        src = payload["sources"].get(key)
        if src is None:
            continue
        age = _age(payload, key)
        if age is not None and age > max_age:
            stale.append(key)
    if as_json:
        payload["max_age_s"] = max_age
        payload["stale"] = stale
        print(json.dumps(payload, indent=2))
        return 3 if stale else 0
    for key in keys:
        src = payload["sources"].get(key)
        if src is None:
            print("%-42s MISSING" % key)
            continue
        age = _age(payload, key)
        age_s = ("%.1fs" % age) if age is not None else "?"
        err = (payload.get("last_error") or {}).get(key)
        if err:
            print("%-42s status=%s age=%s ERROR %s"
                  % (key, src.get("status", "?"), age_s, err[:80]))
        for name, remaining, hours in _windows_summary(
                src.get("provider", key.split(":")[0]), src):
            print("%-42s %-28s remaining=%s%% resets_in=%sh (age %s)"
                  % (key, name,
                     "?" if remaining is None else "%.1f" % remaining,
                     "?" if hours is None else "%.2f" % hours, age_s))
        if key == "glm" and src.get("models"):
            for model, mentry in sorted(src["models"].items()):
                att = (mentry.get("attributed") or {})
                a5 = (att.get("five_hour") or {})
                aw = (att.get("weekly") or {})
                print("%-42s model %-14s attributed 5h=%s%% weekly=%s%% (share %s%%)"
                      % (key, model,
                         "?" if a5.get("utilization_pct") is None else a5.get("utilization_pct"),
                         "?" if aw.get("utilization_pct") is None else aw.get("utilization_pct"),
                         "?" if a5.get("share_pct") is None else a5.get("share_pct")))
        if key == "codex" and src.get("tiers"):
            tiers = src["tiers"]
            print("%-42s tiers %s share one account window (shape=%s)"
                  % (key, "/".join(sorted(tiers)),
                     next(iter(tiers.values()), {}).get("window_shape", "?")))
    if stale:
        print("STALE beyond %ss: %s" % (max_age, ", ".join(stale)), file=sys.stderr)
        return 3
    return 0


def main():
    args = sys.argv[1:]
    if not args or args[0] not in ("start", "stop", "status", "query"):
        sys.stderr.write("usage: leadv2-quota-daemon.py "
                         "start [--foreground] | stop | status | "
                         "query [--max-age N] [--json] [--source NAME]\n")
        sys.exit(2)
    verb = args[0]
    if verb == "start":
        sys.exit(cmd_start(foreground="--foreground" in args))
    if verb == "stop":
        sys.exit(cmd_stop())
    if verb == "status":
        sys.exit(cmd_status())
    max_age, as_json, source = 60.0, False, None
    rest = args[1:]
    i = 0
    while i < len(rest):
        if rest[i] == "--max-age" and i + 1 < len(rest):
            max_age = float(rest[i + 1]); i += 2
        elif rest[i] == "--json":
            as_json = True; i += 1
        elif rest[i] == "--source" and i + 1 < len(rest):
            source = rest[i + 1]; i += 2
        else:
            sys.stderr.write("unknown query arg: %s\n" % rest[i]); sys.exit(2)
    sys.exit(cmd_query(max_age, as_json, source))


if __name__ == "__main__":
    main()
