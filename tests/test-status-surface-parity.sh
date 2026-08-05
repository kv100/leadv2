#!/usr/bin/env bash
# tests/test-status-surface-parity.sh — PANEL-TWO-IMPLEMENTATIONS-MERGE-01
#
# Asserts both renderers (lanes-table and single-lead) produce the SAME
# classification for the same lane shape.  The lanes path never sets
# res_state/arm, so the reservation branches in classify() are unreachable
# there; this test verifies they are truly inert on the lanes path while
# active on the single-lead path.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
LANE_CLASS_PY="${ROOT}/plugins/leadv2/scripts/leadv2-lane-class.py"

python3 -c "import py_compile; py_compile.compile('${LANE_CLASS_PY}')" 2>/dev/null || {
  echo "FATAL: cannot compile ${LANE_CLASS_PY}" >&2; exit 1; }

LANE_CLASS_PY="$LANE_CLASS_PY" python3 <<'PYEOF'
import os, sys

exec(open(os.environ["LANE_CLASS_PY"]).read(), globals())

NOW = 1000000
TTL = 7200
PASS = 0
FAIL = 0

def run(label, lanes_facts, single_facts, expect_cls=None, expect_terminal=None,
        expect_unknown=None, expect_cause_prefix=None, check_parity=True):
    global PASS, FAIL
    lc_lanes = classify(lanes_facts)
    lc_single = classify(single_facts)
    problems = []
    if check_parity:
        if lc_lanes["cls"] != lc_single["cls"]:
            problems.append("cls diverges: lanes=%s single=%s" % (lc_lanes["cls"], lc_single["cls"]))
        if lc_lanes["terminal"] != lc_single["terminal"]:
            problems.append("terminal diverges: lanes=%s single=%s" % (lc_lanes["terminal"], lc_single["terminal"]))
    if expect_cls is not None and lc_single["cls"] != expect_cls:
        problems.append("single cls=%s expected=%s" % (lc_single["cls"], expect_cls))
    if expect_terminal is not None and lc_single["terminal"] != expect_terminal:
        problems.append("single terminal=%s expected=%s" % (lc_single["terminal"], expect_terminal))
    if expect_unknown is not None and lc_single.get("unknown", False) != expect_unknown:
        problems.append("single unknown=%s expected=%s" % (lc_single.get("unknown", False), expect_unknown))
    if expect_cause_prefix is not None and not lc_single["cause"].startswith(expect_cause_prefix):
        problems.append("single cause=%s expected prefix=%s" % (lc_single["cause"], expect_cause_prefix))
    if problems:
        print("  FAIL - %s: %s" % (label, "; ".join(problems)))
        FAIL += 1
    else:
        print("  ok   - %s" % label)
        PASS += 1

# ---- shapes ----

# 1. live worker WITH pid — both paths see pid_alive_session
base_live = dict(kind="lane", pid="100", pid_alive_session=True, now=NOW)
run("1 live worker with pid",
    dict(base_live),
    dict(base_live, arm="codex", res_state="confirmed", res_age_s=120, res_ttl=TTL),
    expect_cls="live")

# 2. live worker WITHOUT pid — reservation confirmed, in TTL, arm set.
base_nopid = dict(kind="worker", pid=None, pid_alive_session=False, now=NOW)
run("2 reservation confirmed no-pid",
    dict(base_nopid),
    dict(base_nopid, arm="codex", res_state="confirmed", res_age_s=120, res_ttl=TTL),
    expect_cls="live", check_parity=False)

# 3. terminal landed (exit_code=0 → done)
base_term = dict(kind="worker", pid=None, pid_alive_session=False,
                 ledger_state="landed", terminal_token="landed", exit_code=0, now=NOW)
run("3 terminal landed",
    dict(base_term),
    dict(base_term, arm="codex", res_state="confirmed", res_age_s=60, res_ttl=TTL),
    expect_cls="done", expect_terminal=True)

# 4. terminal dead
base_dead = dict(kind="worker", pid=None, pid_alive_session=False,
                 ledger_state="dead", terminal_token="dead", now=NOW)
run("4 terminal dead",
    dict(base_dead),
    dict(base_dead, arm="codex", res_state="confirmed", res_age_s=60, res_ttl=TTL),
    expect_cls="dead", expect_terminal=True)

# 5. terminal no_work — cause must contain no-work
base_nw = dict(kind="worker", pid=None, pid_alive_session=False,
               ledger_state="no_work", terminal_token="no_work", now=NOW)
run("5 terminal no_work",
    dict(base_nw),
    dict(base_nw, arm="codex", res_state="confirmed", res_age_s=60, res_ttl=TTL),
    expect_cls="dead", expect_terminal=True, expect_cause_prefix="no-work")

# 6. ledger-only queued, no arm — both paths produce queued
base_q = dict(kind="worker", pid=None, pid_alive_session=False,
              ledger_state="queued", now=NOW)
run("6 ledger queued no arm",
    dict(base_q),
    dict(base_q, arm="", res_state="", res_age_s=None, res_ttl=TTL),
    expect_cls="queued")

# 7. reserved, no arm — both paths produce queued
base_r = dict(kind="worker", pid=None, pid_alive_session=False,
              ledger_state="reserved", now=NOW)
run("7 reserved no arm",
    dict(base_r),
    dict(base_r, arm="", res_state="", res_age_s=None, res_ttl=TTL),
    expect_cls="queued")

# 8. unreadable repo ledger — no facts at all, unknown must be True
base_void = dict(kind="worker", pid=None, pid_alive_session=False, now=NOW)
run("8 unreadable repo (no facts)",
    dict(base_void),
    dict(base_void, arm="", res_state="", res_age_s=None, res_ttl=TTL),
    expect_unknown=True)

# 9. missing model/arm field on an otherwise live reservation row -> queued
base_noarm = dict(kind="worker", pid=None, pid_alive_session=False,
                  ledger_state="confirmed", now=NOW)
run("9 confirmed but no arm -> queued",
    dict(base_noarm),
    dict(base_noarm, arm="", res_state="confirmed", res_age_s=60, res_ttl=TTL),
    expect_cls="queued", check_parity=False)

# 10. name longer than column — clip_name must end in …, len == n
_clipped = clip_name("FEED-SCAN-USABLE-CANDIDATES-01", 20)
if _clipped.endswith("…") and len(_clipped) == 20:
    print("  ok   - 10 clip_name ends in … len==20 (%s)" % _clipped)
    PASS += 1
else:
    print("  FAIL - 10 clip_name wrong: %r len=%d" % (_clipped, len(_clipped)))
    FAIL += 1

# 11. reservation state 'aborted' — foreign, dead
base_abort = dict(kind="worker", pid=None, pid_alive_session=False, now=NOW)
run("11 reservation aborted -> foreign dead",
    dict(base_abort),
    dict(base_abort, arm="codex", res_state="aborted", res_age_s=60, res_ttl=TTL),
    expect_cls="dead", expect_cause_prefix="foreign(state=aborted)")

# 12. reservation past TTL — expired, dead
base_expired = dict(kind="worker", pid=None, pid_alive_session=False, now=NOW)
run("12 reservation past TTL -> expired dead",
    dict(base_expired),
    dict(base_expired, arm="codex", res_state="confirmed", res_age_s=99999, res_ttl=TTL),
    expect_cls="dead", expect_cause_prefix="expired(")

print("test-status-surface-parity: %d passed, %d failed" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
PYEOF
