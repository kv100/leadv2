#!/usr/bin/env bash
# run-all-triggers: leadv2-claude-profile-select.sh leadv2-claude-profile-pick.py leadv2-quota-read.py claude-subsession.sh leadv2-account-switch.sh
# tests/test-balancer-ranks-by-usable-now.sh —
# BALANCER-RANKS-BY-THE-WRONG-NUMBER-AND-PRINTS-A-MISLEADING-ONE-01
# (CONTROL-PLANE-REVIEW-01 / f1-balancer.md findings 2, 3, 8).
#
# F2 (S1, the negative control): the balancer ranked (tier, raw
#   binding-window pct, registry order) and never read the window's
#   usable_now -- its S4 outcome agreed with availability only by
#   coincidence.  The S1 fixture is f1's own failure scenario:
#   56%-used/113h-to-reset vs 67%-used/20h-to-reset; the LOWER-consumed
#   profile is the WRONG pick (usable_now 0.389 vs 1.650).  RED before the
#   fix, GREEN after.
# F3 (S2): the line printed score=<raw consumed pct> -- a CONSUMED number
#   presented as a score, direction unreadable.  The line must name WHAT was
#   compared and in which direction: rank_by=usable_now_max (or the honest
#   fallback rank_by=consumed_pct_min), consumed_pct=<n>, usable_now=<u>,
#   and the bare score= token must be gone.
# F8 (S5): every disk-cache hit normalized and wrote the payload back,
#   resetting mtime without refreshing the API-derived fetched_at, so the
#   nominal 300s anthropic TTL extended indefinitely while the payload aged
#   (a ~34-minute-old payload was served).  TTL must be judged on the
#   payload's own fetched_at, and a hit must not rewrite the cache file.
# Protected invariants (f1 findings 4/7/9 stay SOUND -- re-proved here,
# never changed): an unreadable/429 account is NEVER a zero or free quota,
#   unknown still ranks below every live usable_now (S4), and the
#   demote/cooling tier still ranks ahead of the number (S3).
# Hermetic: the pick lib is a pure module driven on stdin; quota-read's
# cache path is driven in-process with READERS patched -- no network, no
# keychain, no daemon.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PICK_BIN="${LEADV2_TEST_PICK_BIN:-${SCRIPTS_ROOT}/lib/leadv2-claude-profile-pick.py}"
QR_BIN="${SCRIPTS_ROOT}/leadv2-quota-read.py"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1 -- ${2:-}"; }
check_grep() { # <haystack> <pattern> <label>
  if grep -qE -- "$2" <<<"$1"; then pass "$3"; else fail "$3" "no match for '$2' in: $1"; fi
}
check_nogrep() { # <haystack> <pattern> <label>
  if grep -qE -- "$2" <<<"$1"; then fail "$3" "unexpected match for '$2' in: $1"; else pass "$3"; fi
}

unset LEADV2_CLAUDE_MULTIPROFILE LEADV2_CLAUDE_PROFILES_FILE \
      LEADV2_CLAUDE_PROFILE_PROBE LEADV2_CLAUDE_PROFILE_TIMEOUT \
      LEADV2_QUOTA_CACHE_DIR LEADV2_ANTHROPIC_ACTIVE_SERVICE CLAUDE_CONFIG_DIR \
      LEADV2_CLAUDE_PROFILE_DEMOTE_DIR LEADV2_CLAUDE_PROFILE_DEFAULT_DIR \
      LEADV2_QUOTA_DAEMON LEADV2_QUOTA_TTL_ANTHROPIC

tmp="$(mktemp -d "${TMPDIR:-/tmp}/balancer-usable-now.XXXXXX")"

pick_run() { pick_out="$(printf '%b' "$1" | python3 "$PICK_BIN")"; }

# make_payload <seven_day_pct> <seven_day_reset_iso> <seven_day_hours>
# Single-account anthropic probe payload, fixed reference "now"
# (2026-09-11T12:00:00Z) so every derived number is deterministic.
# five_hour is healthy and never binding (10% used, 3h to reset ->
# usable 30.0); seven_day carries the scenario numbers and binds.
make_payload() {
  python3 - "$1" "$2" "$3" <<'PY'
import base64, json, sys
sd_pct, sd_reset, sd_hours = float(sys.argv[1]), sys.argv[2], float(sys.argv[3])
rem = 100.0 - sd_pct
acct = {"entry_suffix": "file", "service": "file:stub", "status": "ok",
        "active": True, "account_label": "stub",
        "five_hour_pct": 10, "five_hour_reset_iso": "2026-09-11T15:00:00Z",
        "seven_day_pct": sd_pct, "seven_day_reset_iso": sd_reset,
        "five_hour": {"pct": 10, "reset_iso": "2026-09-11T15:00:00Z",
                      "remaining_pct": 90.0, "hours_to_reset": 3.0,
                      "usable_now": 30.0},
        "seven_day": {"pct": sd_pct, "reset_iso": sd_reset,
                      "remaining_pct": rem, "hours_to_reset": sd_hours,
                      "usable_now": rem / sd_hours},
        "binding_window": "seven_day"}
print(base64.b64encode(json.dumps(
    {"provider": "anthropic", "status": "ok", "accounts": [acct],
     "active_account": "stub",
     "fetched_at": "2026-09-11T12:00:00Z"}).encode()).decode())
PY
}

# ============================================================================
echo "=== S1 (negative control, f1 #2): rank by usable_now, not raw consumed pct ==="
# slowburn: 56% used, 113h to reset -> usable_now 44/113 = 0.389
# fastreset: 67% used, 20h to reset -> usable_now 33/20 = 1.650
# The LOWER-consumed profile is the WRONG pick.
B_SLOW="$(make_payload 56 2026-09-16T05:00:00Z 113)"
B_FAST="$(make_payload 67 2026-09-12T08:00:00Z 20)"
pick_run "slowburn\t/d/slow\tfile:/d/slow/c\t$B_SLOW\tpro/na\t0\t0\nfastreset\t/d/fast\tfile:/d/fast/c\t$B_FAST\tpro/na\t0\t0\n"
check_grep "$pick_out" '^profile=fastreset ' 'S1a: higher usable_now (1.650) wins even though consumed pct is HIGHER (67 vs 56) -- f1 #2 failure scenario'
check_grep "$pick_out" 'rank_by=usable_now_max consumed_pct=67 usable_now=1\.650 ' 'S1b: line names WHAT was compared (usable_now) and the direction (max); the pct is labeled consumed_pct'
check_grep "$pick_out" 'binding=seven_day:consumed_pct=67,usable_now=1\.650 ' 'S1c: binding field labels both of its numbers'
check_grep "$pick_out" 'windows=slowburn:seven_day=56,usable_now=0\.389\|fastreset:seven_day=67,usable_now=1\.650$' 'S1d: every candidate entry carries its usable_now'

# ============================================================================
echo "=== S2 (f1 #3): the line is self-describing; no bare score= token ==="
B20="$(printf '{"provider":"anthropic","status":"ok","accounts":[{"status":"ok","five_hour_pct":20,"seven_day_pct":20,"active":true}]}' | base64 | tr -d '\n')"
B80="$(printf '{"provider":"anthropic","status":"ok","accounts":[{"status":"ok","five_hour_pct":80,"seven_day_pct":80,"active":true}]}' | base64 | tr -d '\n')"
pick_run "alpha\t/d/a\tfile:/d/a/c\t$B20\tid/a\t0\t0\nbeta\t/d/b\tfile:/d/b/c\t$B80\tid/b\t0\t0\n"
check_grep "$pick_out" '^profile=alpha .*rank_by=consumed_pct_min consumed_pct=20 usable_now=- source=live' 'S2a: pct-only legacy payload keeps the old ORDER and says which rule ordered it (rank_by=consumed_pct_min)'
check_nogrep "$pick_out" '[[:space:]]score=[0-9]' 'S2b: the misleading bare score= token (a consumed pct presented as a score) is gone'

# ============================================================================
echo "=== S3: demote/cooling tier still ranks AHEAD of the number ==="
pick_run "slowburn\t/d/slow\tfile:/d/slow/c\t$B_SLOW\tpro/na\t0\t0\nfastreset\t/d/fast\tfile:/d/fast/c\t$B_FAST\tpro/na\t0\t1\n"
check_grep "$pick_out" '^profile=slowburn .*demoted=fastreset$' 'S3a: the usable_now-best profile is demoted -> the other wins; tier overrides the number, never rewrites it'

# ============================================================================
echo "=== S4 (f1 #4 protected): unknown is never a zero or free quota ==="
B429="$(printf '{"provider":"anthropic","status":"ok","accounts":[{"status":"unknown","account_state":"unknown","error":"429 rate_limited (reported as unknown, NEVER 0)","active":true}]}' | base64 | tr -d '\n')"
pick_run "dead\t/d/d\tfile:/d/d/c\t$B429\tpro/na\t0\t0\nfastreset\t/d/fast\tfile:/d/fast/c\t$B_FAST\tpro/na\t0\t0\n"
check_grep "$pick_out" '^profile=fastreset ' 'S4a: a live usable_now account beats an unknown (429) one'
check_grep "$pick_out" 'windows=dead:-=-.fastreset:seven_day' 'S4b: the unknown candidate is listed with no window -- never a faked 0 pct'
pick_run "dead\t/d/d\tfile:/d/d/c\t$B429\tpro/na\t0\t0\n"
check_grep "$pick_out" '^profile=dead .*rank_by=none consumed_pct=- usable_now=- source=unknown reason=all_unknown ' 'S4c: an unknown pick prints NO number (consumed_pct=-), never a sentinel dressed up as a pct'

# ============================================================================
echo "=== S5 (f1 #8): cache TTL is judged on fetched_at, not on rewrite-reset mtime ==="
CACHE_DIR="$tmp/quota-cache"; mkdir -p "$CACHE_DIR"
cat > "$tmp/ttl_probe.py" <<'PY'
import importlib.util, io, json, os, sys, time

QR, CACHE = sys.argv[1], sys.argv[2]
os.environ["LEADV2_QUOTA_CACHE_DIR"] = CACHE
os.environ["LEADV2_QUOTA_DAEMON"] = "0"  # no daemon snapshot branch
spec = importlib.util.spec_from_file_location("qr_under_test", QR)
qr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qr)
now = time.time()

def put(obj, mtime=None):
    qr.cache_put("anthropic", obj)
    if mtime is not None:
        p = os.path.join(CACHE, "anthropic.json")
        os.utime(p, (mtime, mtime))

def run_main():
    buf, old = io.StringIO(), sys.stdout
    sys.stdout = buf
    sys.argv = ["leadv2-quota-read.py", "anthropic", "json"]
    qr.main()
    sys.stdout = old
    return json.loads(buf.getvalue())

results = []
# s5a: fetched_at 20 min old + FRESH mtime == exactly the state the old
# normalize-and-write-back produced; TTL (300s) must judge it stale.
put({"provider": "anthropic", "status": "ok",
     "fetched_at": qr.iso_from_epoch(now - 1200)}, mtime=now)
results.append(("s5a_stale_fetched_at_fresh_mtime_is_miss",
                qr.cache_get("anthropic") is None))
# s5b: fresh fetched_at + fresh mtime == hit
put({"provider": "anthropic", "status": "ok", "fetched_at": qr.iso_now()},
    mtime=now)
hit = qr.cache_get("anthropic")
results.append(("s5b_fresh_payload_is_hit",
                hit is not None and hit.get("status") == "ok"))
# s5c: legacy payload without fetched_at falls back to mtime
put({"provider": "anthropic", "status": "ok"}, mtime=now)
results.append(("s5c_legacy_no_fetched_at_mtime_fallback",
                qr.cache_get("anthropic") is not None))
# s5d: a HIT must not rewrite the cache file -- the write-back is what reset
# mtime and silently extended TTL while the payload aged.
qr.READERS["anthropic"] = lambda cf=None: {"provider": "anthropic",
                                           "status": "ok", "marker": "STUB_LIVE"}
put({"provider": "anthropic", "status": "ok", "five_hour_pct": 20,
     "fetched_at": qr.iso_now()}, mtime=now)
p = os.path.join(CACHE, "anthropic.json")
before = (os.stat(p).st_mtime_ns, open(p, "rb").read())
out = run_main()
after = (os.stat(p).st_mtime_ns, open(p, "rb").read())
results.append(("s5d_hit_does_not_rewrite_cache", before == after))
results.append(("s5d_hit_serves_cached_payload", out.get("marker") is None))
# s5e: stale-by-fetched_at cache (fresh mtime) must not be served at all --
# the caller that never asked for cache gets the LIVE read.
put({"provider": "anthropic", "status": "ok", "five_hour_pct": 99,
     "fetched_at": qr.iso_from_epoch(now - 1200)}, mtime=now)
out = run_main()
results.append(("s5e_stale_cache_serves_fresh_live_read",
                out.get("marker") == "STUB_LIVE"))

for name, ok in results:
    print("%s %s" % (name, "PASS" if ok else "FAIL"))
PY
python3 "$tmp/ttl_probe.py" "$QR_BIN" "$CACHE_DIR" > "$tmp/ttl.out" 2> "$tmp/ttl.err"
ttl_rc=$?
if [[ $ttl_rc -ne 0 ]]; then
  fail "S5: ttl probe crashed (rc=$ttl_rc)" "$(tail -3 "$tmp/ttl.err" 2>/dev/null)"
else
  while IFS=' ' read -r name verdict; do
    [[ -n "${name:-}" ]] || continue
    if [[ "$verdict" == "PASS" ]]; then pass "S5-$name"; else fail "S5-$name" "verdict=$verdict"; fi
  done < "$tmp/ttl.out"
fi

printf '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
