#!/usr/bin/env bash
# FABLE-IS-PRICED-FROM-A-WINDOW-IT-DOES-NOT-BURN-01 (row 0485ea90c9e0) --
# HISTORICAL NAME, kept only because CI suite-selection maps key on the
# path. Decision 0485 (2026-09-13) built the model-scoped weekly window end
# to end: publisher (leadv2-quota-read.py parses limits[] into
# weekly_scoped), arbiter (leadv2-route-arbiter.sh prices a scoped arm from
# its own window beside the shared session), resolver
# (leadv2-glm-policy-resolve.py prices fable by max(session, scoped)). Its
# ARBITER half let the scoped window REPLACE the account's seven_day
# aggregate for that arm.
#
# FOUNDER RULING 2026-09-16 (ARM-SELECTION-COST-QUOTA-TELEMETRY-01 round 2):
# keep BOTH windows -- Fable draws down the scoped meter AND the account
# weekly aggregate simultaneously. The worst readable window binds; an
# exhausted account weekly caps Fable even when its own scoped window is
# free (C1), and the mirror -- an exhausted scoped window caps it while the
# aggregate is healthy (C2) -- must hold too: one direction alone would let
# a replace-shaped bug back in unnoticed. C5 pins the same rule at pricing
# level, under the ceiling so cap logic cannot mask the number. The
# resolver half (R-cases) pins leadv2-glm-policy-resolve.py, which still
# implements 0485 substitution and was not part of this ruling's patch --
# see the lane report's follow-up. Every case names which direction it
# pins.
# run-all-triggers: leadv2-quota-read leadv2-route-arbiter leadv2-glm-policy-resolve.py
# NB token shapes: scripts/*.py stems strip their extension (leadv2-quota-read),
# lib/leadv2-glm-policy-resolve.py keeps it (run-all.sh special case, FABLE-
# THINK-TIER-01 R6) -- a dotted quota-read token here would be a dead row.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh"
QUOTA_READ="${SCRIPTS_DIR}/leadv2-quota-read.py"
POLICY="${SCRIPTS_DIR}/lib/leadv2-glm-policy-resolve.py"
TMP_BASE="${LEADV2_TEST_TMPDIR:-/tmp}"
TMP="$(mktemp -d "${TMP_BASE%/}/test-fable-window.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
export LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/events.jsonl"
# R-case isolation: resolve_review_pool's D4 lockout read must consult an
# EMPTY store, never the live ~/.claude/cache/dispatch-ledger a real machine
# may hold (a real claude lockout here would block fable/opus/sonnet for
# environment reasons this suite does not mean to test).
export LEADV2_QUOTA_LOCKOUT_DIR="$TMP/no-lockout"
# W1-ARBITER-SUITE-THREE-RED-01: green and red artifacts alike carry the
# sourced bytes' identity, so a mutation applied anywhere but these files is
# visible as a hash that did not move.
for _f in "$ARBITER" "$QUOTA_READ" "$POLICY"; do
  printf 'under_test=%s sha256=%s\n' "$_f" "$(shasum -a 256 "$_f" 2>/dev/null | awk '{print substr($1,1,16)}')"
done
PASS=0; FAIL=0
LAST_ASSERT="(none yet -- died before the first assertion)"
SUMMARY_PRINTED=0
_suite_abort_report() {
  local rc=$?
  [[ ${SUMMARY_PRINTED} -eq 1 ]] && return 0
  printf 'ABORT: suite exited rc=%s WITHOUT a summary after %s assertion(s); last completed: %s\n' \
    "${rc}" "$((PASS+FAIL))" "${LAST_ASSERT}" >&2
}
trap _suite_abort_report EXIT
pass(){ LAST_ASSERT="$1"; printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ LAST_ASSERT="$1"; printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"

# Fixture routing yaml: minimal matrix whose review-kind cells are exactly
# codex / sonnet / fable, so the winner assertions below have no fourth
# candidate. glm stays code-only, mirroring the real matrix's shape.
cat >"$TMP/routing.yaml" <<'YML'
router_v2:
  quota_ceilings: {glm: {work_pct: 80, review_pct: 90}, claude: {work_pct: 80, review_pct: 95}, codex: {work_pct: 90, review_pct: 95}}
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix: [{default: true, effort: medium}]
  capability_matrix:
    - {arm: glm, provider: glm, model: glm-5.3, cost: 1, protected: true, sizes: [standard], kinds: [code]}
    - {arm: codex, provider: codex, model: gpt-5.6-terra, cost: 4, protected: true, sizes: [standard], kinds: [code, review]}
    - {arm: sonnet, provider: claude, model: sonnet, cost: 5, protected: true, sizes: [standard, heavy], kinds: [code, review]}
    - {arm: fable, provider: claude, model: fable, cost: 8, tier: high, protected: true, sizes: [standard, heavy], kinds: [plan, audit, review], review: true}
YML

# qjson G C FH SD [SCOPED] -- the full three-bucket quota payload, with the
# anthropic account's weekly_scoped map built by the REAL publisher parser
# (importlib on $QUOTA_READ), not by this suite's own idea of the shape. The
# limits[] rows are endpoint-shaped (live probe 2026-09-12): kind, percent,
# resets_at, scope.model.display_name. Resets are computed from now so the
# windows always have future clocks.
qjson(){ python3 - "$QUOTA_READ" "$@" <<'PY'
import datetime, importlib.util, json, sys
spec = importlib.util.spec_from_file_location("qr", sys.argv[1])
qr = importlib.util.module_from_spec(spec); spec.loader.exec_module(qr)
g, c, fh, sd = (int(x) for x in sys.argv[2:6])
scoped = int(sys.argv[6]) if len(sys.argv) > 6 and sys.argv[6] != "-" else None
now = datetime.datetime.now(datetime.timezone.utc)
iso = lambda h: (now + datetime.timedelta(hours=h)).strftime("%Y-%m-%dT%H:%M:%SZ")
limits = [{"kind": "session", "percent": fh, "resets_at": iso(3)},
          {"kind": "weekly_all", "percent": sd, "resets_at": iso(120)}]
if scoped is not None:
    limits.append({"kind": "weekly_scoped", "group": "weekly", "percent": scoped,
                   "resets_at": iso(120), "scope": {"model": {"display_name": "Fable"}}})
acct = {"active": True, "status": "ok", "account_label": "max_20x",
        "five_hour_pct": fh, "seven_day_pct": sd,
        "weekly_scoped": qr.anthropic_scoped_windows(limits, now=now),
        "limits": limits}
print(json.dumps({"glm": {"status": "ok", "five_hour": {"pct": g}, "weekly": {"pct": g}},
                  "codex": {"status": "ok", "binding_window": "primary",
                            "windows": [{"kind": "primary", "used_percent": c}]},
                  "anthropic": {"status": "ok", "accounts": [acct]}}))
PY
}
run(){ LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/routing.yaml" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" ROUTE_TEST_QUOTA="$1" ROUTE_TEST_FREE_RC="${2:-0}" bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$3"; }
# arm_excluded= is ONE comma-joined token (arm:stage+stage,...), so stage
# assertions parse the value out first -- matching the literal substring
# 'arm_excluded=fable:capped' would only ever fire when fable sorts first.
exc_of(){ printf '%s\n' "$1" | sed -n 's/.*arm_excluded=\([^ ]*\).*/\1/p'; }

# ── publisher half: limits[] -> weekly_scoped map ────────────────────────────
v="$(python3 - "$QUOTA_READ" <<'PY'
import datetime, importlib.util, sys
spec = importlib.util.spec_from_file_location("qr", sys.argv[1])
qr = importlib.util.module_from_spec(spec); spec.loader.exec_module(qr)
now = datetime.datetime(2026, 9, 13, 0, 0, tzinfo=datetime.timezone.utc)
iso = lambda h: (now + datetime.timedelta(hours=h)).strftime("%Y-%m-%dT%H:%M:%SZ")
limits = [
    {"kind": "session", "percent": 7, "resets_at": iso(3)},
    {"kind": "weekly_all", "percent": 96, "resets_at": iso(120)},
    {"kind": "weekly_scoped", "group": "weekly", "percent": 2, "resets_at": iso(120),
     "scope": {"model": {"display_name": "Fable"}}},
    {"kind": "weekly_scoped", "group": "weekly", "percent": 55, "resets_at": iso(120),
     "scope": {"model": {"id": "fallback-id-arm"}}},
    {"kind": "weekly_scoped", "group": "weekly", "percent": 66, "resets_at": iso(120)},
]
w = qr.anthropic_scoped_windows(limits, now=now)
problems = []
# scope.model.id is the documented display_name fallback; the scopeless row
# (percent 66) is the only scoped row that must produce nothing.
if set(w.keys()) != {"fable", "fallback-id-arm"}:
    problems.append("keys=%s" % sorted(w.keys()))
else:
    fw = w["fable"]
    if fw.get("pct") != 2: problems.append("pct=%r" % fw.get("pct"))
    if fw.get("kind") != "weekly_scoped": problems.append("kind=%r" % fw.get("kind"))
    if fw.get("scope_model") != "Fable": problems.append("scope_model=%r" % fw.get("scope_model"))
    if fw.get("limit_window_seconds") != 604800: problems.append("period=%r" % fw.get("limit_window_seconds"))
    if not (fw.get("hours_to_reset") and 100 < fw["hours_to_reset"] < 140): problems.append("hours=%r" % fw.get("hours_to_reset"))
    if w.get("fallback-id-arm", {}).get("pct") != 55: problems.append("id-fallback pct=%r" % w.get("fallback-id-arm"))
    if fw.get("usable_now") is None: problems.append("usable_now missing")
print("ok" if not problems else "bad:" + ";".join(problems))
PY
)"
if [[ "$v" == ok ]]; then pass 'P1 publisher parses weekly_scoped rows (key/scope/period/truth) and ignores non-scoped+scopeless rows'; else fail "P1 publisher parse: $v"; fi

# P2: a PRE-scoped-parser cache (limits[] present, weekly_scoped absent) is
# upgraded in memory by normalize_payload -- consumers see the map regardless
# of cache age. This is the guarantee that makes the arbiter half work on
# payloads written before this change.
v="$(python3 - "$QUOTA_READ" <<'PY'
import datetime, importlib.util, json, sys
spec = importlib.util.spec_from_file_location("qr", sys.argv[1])
qr = importlib.util.module_from_spec(spec); spec.loader.exec_module(qr)
now = datetime.datetime.now(datetime.timezone.utc)
iso = lambda h: (now + datetime.timedelta(hours=h)).strftime("%Y-%m-%dT%H:%M:%SZ")
legacy = {"provider": "anthropic", "status": "ok",
          "accounts": [{"active": True, "status": "ok", "account_label": "max_20x",
                        "five_hour_pct": 7, "seven_day_pct": 96,
                        "limits": [{"kind": "weekly_scoped", "percent": 2, "resets_at": iso(120),
                                    "scope": {"model": {"display_name": "Fable"}}}]}]}
out = qr.normalize_payload(legacy)
fw = ((out.get("accounts") or [{}])[0].get("weekly_scoped") or {}).get("fable") or {}
print("ok" if fw.get("pct") == 2 else "bad: fable window=%r" % fw)
PY
)"
if [[ "$v" == ok ]]; then pass 'P2 normalize_payload upgrades a legacy cache (limits[] only) with the weekly_scoped map'; else fail "P2 cache upgrade: $v"; fi

# ── resolver half: live_anthropic_pct + resolve_review_pool ──────────────────
# R-live: the REAL live-read path against a stub quota-live bin whose payload
# carries the scoped map under the payload's own key casing ("Fable") -- the
# join is normalized name equality, not spelling. Same payload, three arms:
# fable max(7, 2)=7; opus (no scoped window) keeps the aggregate max(7,96)=96;
# arm=None keeps the aggregate too. This one line pins that the fix freed the
# SCOPED arm without exempting the account's other arms.
cat >"$TMP/anthropic-live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"status":"ok","accounts":[{"active":true,"status":"ok","account_label":"max_20x","five_hour_pct":7,"seven_day_pct":96,"weekly_scoped":{"Fable":{"pct":2}}}]}'
EOF
chmod +x "$TMP/anthropic-live.sh"
v="$(python3 - "$POLICY" "$TMP/anthropic-live.sh" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gpr", sys.argv[1])
gpr = importlib.util.module_from_spec(spec); spec.loader.exec_module(gpr)
f = gpr.live_anthropic_pct(sys.argv[2], "fable")
o = gpr.live_anthropic_pct(sys.argv[2], "opus")
n = gpr.live_anthropic_pct(sys.argv[2])
got = (f, o, n)
print("ok %r" % (got,) if got == (7, 96, 96) else "bad %r" % (got,))
PY
)"
if [[ "$v" == "ok"* ]]; then pass 'R-live live_anthropic_pct: fable=(session,scoped) opus/None=aggregate'; else fail "R-live readings: $v"; fi

# R1 (NOT penalised): aggregate 96 over the 95 review threshold, fable's own
# scoped reading 7 -> fable admitted, opus blocked on the aggregate it shares.
v="$(python3 - "$POLICY" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gpr", sys.argv[1])
gpr = importlib.util.module_from_spec(spec); spec.loader.exec_module(gpr)
gate = {"codex_quota_gate": {"review_arm_order": ["fable", "opus", "sonnet"],
                             "anthropic_review_threshold_pct": 95}}
r = gpr.resolve_review_pool(gate, "codex", pcts={"anthropic": 96, "anthropic:fable": 7}, job="review")
pool = ",".join(r["pool"])
ok = r["reviewer"] == "fable" and "fable:ok:7" in pool and "opus:blocked:96" in pool
print("ok %s | %s" % (r["reviewer"], pool) if ok else "bad %s | %s" % (r["reviewer"], pool))
PY
)"
if [[ "$v" == "ok"* ]]; then pass 'R1 pool: scoped reading 7 admits fable while aggregate 96 blocks opus'; else fail "R1 pool: $v"; fi

# R2 (withdrawn): scoped window exhausted (100) while the aggregate is cool
# (30) -> fable BLOCKED, review falls to sonnet. An exemption would pass R1
# and fail exactly here.
v="$(python3 - "$POLICY" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gpr", sys.argv[1])
gpr = importlib.util.module_from_spec(spec); spec.loader.exec_module(gpr)
gate = {"codex_quota_gate": {"review_arm_order": ["fable", "opus", "sonnet"],
                             "anthropic_review_threshold_pct": 95}}
r = gpr.resolve_review_pool(gate, "codex", pcts={"anthropic": 30, "anthropic:fable": 100}, job="review")
pool = ",".join(r["pool"])
# opus is the first ELIGIBLE arm after fable in the order -- the assertion is
# fable's withdrawal, not which eligible arm succeeds it.
ok = r["reviewer"] == "opus" and "fable:blocked:100" in pool and "opus:ok:30" in pool
print("ok %s | %s" % (r["reviewer"], pool) if ok else "bad %s | %s" % (r["reviewer"], pool))
PY
)"
if [[ "$v" == "ok"* ]]; then pass 'R2 pool: scoped exhausted (100) withdraws fable though aggregate is 30'; else fail "R2 pool: $v"; fi

# R3 (fallback preserved): payload carries NO scoped reading for fable -> the
# single aggregate "anthropic" key remains the conservative ceiling. The
# scoped key outranks the aggregate only when present.
v="$(python3 - "$POLICY" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gpr", sys.argv[1])
gpr = importlib.util.module_from_spec(spec); spec.loader.exec_module(gpr)
gate = {"codex_quota_gate": {"review_arm_order": ["fable", "opus", "sonnet"],
                             "anthropic_review_threshold_pct": 95}}
r = gpr.resolve_review_pool(gate, "codex", pcts={"anthropic": 96}, job="review")
pool = ",".join(r["pool"])
ok = "fable:blocked:96" in pool and r["reviewer"] != "fable"
print("ok %s | %s" % (r["reviewer"], pool) if ok else "bad %s | %s" % (r["reviewer"], pool))
PY
)"
if [[ "$v" == "ok"* ]]; then pass 'R3 pool: no scoped key -> aggregate still blocks fable (no exemption)'; else fail "R3 pool: $v"; fi

# ── arbiter half: both windows bind, worst wins (founder ruling 2026-09-16) ──
# C1 (account weekly binds): weekly_all=96 (over every claude ceiling) with
# the scoped Fable window at 2 and session at 7. fable must read
# util_claude_fable=96 -- the WORST of its three readable windows, priced by
# the account weekly it also draws down -- and be capped beside sonnet.
# This is the ruled flip of the old C1 (which asserted the scoped window
# alone freed fable here); a replace-shaped regression reads 7 and admits
# it.
rm -f "$TMP/state"
out="$(run "$(qjson 1 1 7 96 2)" 1 '{"kind":"review","size":"standard","protected":true}' || true)"
exc="$(exc_of "$out")"
# Assertions go through PATH grep, not bash [[ substring ]] compares: the
# suite-falsifiability gate (SUITE-THAT-CANNOT-FAIL-01) breaks grep/diff/cmp
# generically and demands the suite notice; a bash-native comparison never
# engages those shims, so it reads green with every assertion tool broken.
if printf '%s\n' "$out" | grep -qF 'util_claude=96 ' \
   && printf '%s\n' "$out" | grep -qF 'util_claude_fable=96 ' \
   && printf '%s\n' "$out" | grep -qF 'scoped_window_fable=weekly_scoped(fable)' \
   && printf '%s\n' ",${exc}," | grep -qF ',sonnet:capped,' \
   && printf '%s\n' ",${exc}," | grep -qF ',fable:capped,' \
   && printf '%s\n' "$out" | grep -qF 'arm=codex '; then
  pass 'C1 arbiter: weekly_all 96 + scoped 2 -> util_claude_fable=96 (worst binds), fable+sonnet capped, codex wins'
else fail "C1 arbiter output=$out"; fi

# C2 (mirror of the ruling): scoped exhausted (100), aggregate cool (30) ->
# fable priced 100, capped, and the review work goes to sonnet. A healthy
# aggregate must NOT keep a scoped-exhausted arm alive -- this is the mirror
# the founder ruling demands beside C1, so a replace-shaped bug cannot slip
# back in from either direction.
rm -f "$TMP/state"
out="$(run "$(qjson 1 99 10 30 100)" 1 '{"kind":"review","size":"standard","protected":true}' || true)"
exc="$(exc_of "$out")"
if printf '%s\n' "$out" | grep -qF 'util_claude_fable=100 ' \
   && printf '%s\n' ",${exc}," | grep -qF ',fable:capped,' \
   && printf '%s\n' "$out" | grep -qF 'arm=sonnet ' \
   && ! printf '%s\n' "$out" | grep -qF 'arm=fable '; then
  pass 'C2 arbiter: scoped exhausted (100) withdraws fable though weekly_all=30; sonnet wins'
else fail "C2 arbiter output=$out"; fi

# C3 (session still binds): session 99, weekly_all 20, scoped 2. fable must
# read util_claude_fable=99 -- max(session, scoped), NOT the scoped 2 alone --
# and be capped. A fix that freed fable from the shared session window would
# read 2 here; that is the exact regression this case exists to catch.
rm -f "$TMP/state"
out="$(run "$(qjson 1 1 99 20 2)" 1 '{"kind":"review","size":"standard","protected":true}' || true)"
exc="$(exc_of "$out")"
if printf '%s\n' "$out" | grep -qF 'util_claude_fable=99 ' \
   && printf '%s\n' ",${exc}," | grep -qF ',fable:capped,' \
   && printf '%s\n' "$out" | grep -qF 'arm=codex ' \
   && ! printf '%s\n' "$out" | grep -qF 'arm=fable '; then
  pass 'C3 arbiter: session 99 still binds the scoped arm (util_claude_fable=99, capped)'
else fail "C3 arbiter output=$out"; fi

# C4 (aggregate arms untouched): same payload as C1 but a CODE descriptor --
# only sonnet serves code among the claude arms. sonnet must still read the
# aggregate util_claude=96 and be capped; the scoped view exists ONLY for the
# scoped arm. Guards the substitution against leaking into arm=None pricing.
rm -f "$TMP/state"
out="$(run "$(qjson 1 1 7 96 2)" 1 '{"kind":"code","size":"standard","protected":true}' || true)"
exc="$(exc_of "$out")"
if printf '%s\n' "$out" | grep -qF 'util_claude=96 ' \
   && printf '%s\n' ",${exc}," | grep -qF ',sonnet:capped,' \
   && printf '%s\n' "$out" | grep -qF 'arm=glm '; then
  pass 'C4 arbiter: non-scoped claude arm still priced by the aggregate (96, capped)'
else fail "C4 arbiter output=$out"; fi

# C5 (worst binds, pricing level): both weeklies mid-range and under every
# ceiling, so cap logic cannot mask the number. The scoped arm's price must
# follow the WORST readable window whichever side it is on: aggregate 60 vs
# scoped 30 reads 60 (a replace-shaped bug reads 30), aggregate 30 vs scoped
# 60 reads 60. Session is 10 in both, well clear.
rm -f "$TMP/state"
out="$(run "$(qjson 1 1 10 60 30)" 1 '{"kind":"review","size":"standard","protected":true}' || true)"
exc="$(exc_of "$out")"
if printf '%s\n' "$out" | grep -qF 'util_claude_fable=60 ' \
   && printf '%s\n' "$out" | grep -qF 'util_claude=60 ' \
   && ! printf '%s\n' ",${exc}," | grep -qF ',fable:capped,'; then
  pass 'C5a arbiter: aggregate 60 > scoped 30 -> util_claude_fable=60 (the aggregate participates in the price)'
else fail "C5a arbiter output=$out"; fi
rm -f "$TMP/state"
out="$(run "$(qjson 1 1 10 30 60)" 1 '{"kind":"review","size":"standard","protected":true}' || true)"
exc="$(exc_of "$out")"
if printf '%s\n' "$out" | grep -qF 'util_claude_fable=60 ' \
   && printf '%s\n' "$out" | grep -qF 'util_claude=30 ' \
   && ! printf '%s\n' ",${exc}," | grep -qF ',fable:capped,'; then
  pass 'C5b arbiter: scoped 60 > aggregate 30 -> util_claude_fable=60 (the scoped window still binds the price)'
else fail "C5b arbiter output=$out"; fi

SUMMARY_PRINTED=1
printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
