#!/usr/bin/env bash
# Acceptance for FIVE-HOUR-WINDOW-NEVER-ENTERS-THE-ACCOUNT-CHOICE-01 (row 7ea4fed65451).
#
# Replaces the lead's first probe, which was WRONG: it built the account payload
# without `five_hour.remaining_pct`, the very field a correct fix reads. That probe
# could never go green, no matter how right the fix was. This one uses the shape
# leadv2-quota-read.py's normalize_window() actually emits
# (remaining_pct / hours_to_reset / usable_now per window).
#
# Case: personal has 20% of its five-hour bucket left, work has 95%. Both weekly
# windows are healthy. The account with the five-hour RESERVE must win — the
# five-hour window decides who can absorb work now, and must not be invisible
# behind a weekly rate. Founder order 2026-09-16.
#
# Negative control included: flip which account holds the reserve and the answer
# must flip too, or the probe is just asserting a constant.
#
# Resolves the picker from THIS file, so a lane worktree grades its own tree.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LV2="$(cd "$HERE/../../.." && pwd)"
PICK="$LV2/plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py"
[ -f "$PICK" ] || { echo "no picker at $PICK"; exit 2; }

python3 - "$PICK" <<'PY'
import base64, json, subprocess, sys
PICK = sys.argv[1]

def rec(label, fh_left, fh_hrs, wk_left, wk_hrs):
    u = lambda p, h: p / max(h, 1.0)
    acct = {"active": True, "status": "ok",
            "binding_window": ("five_hour" if u(fh_left, fh_hrs) < u(wk_left, wk_hrs) else "seven_day"),
            "five_hour":  {"remaining_pct": fh_left, "hours_to_reset": fh_hrs, "usable_now": u(fh_left, fh_hrs)},
            "five_hour_pct": 100.0 - fh_left,
            "seven_day":  {"remaining_pct": wk_left, "hours_to_reset": wk_hrs, "usable_now": u(wk_left, wk_hrs)},
            "seven_day_pct": 100.0 - wk_left}
    blob = base64.b64encode(json.dumps({"status": "ok", "accounts": [acct]}).encode()).decode()
    return "\t".join([label, "/tmp/cfg-" + label, "-", blob, "sub/na", "0", "0", "-", "-"])

def pick(a, b):
    out = subprocess.run([sys.executable, PICK], input=rec(*a) + "\n" + rec(*b) + "\n",
                         capture_output=True, text=True).stdout
    return out.split("profile=", 1)[1].split(" ", 1)[0] if "profile=" in out else "?"

fails = 0
# main case: work holds the five-hour reserve
got = pick(("personal", 20, 3, 79, 60), ("work", 95, 3, 96, 153))
print("case: personal 5h=20%% left | work 5h=95%% left -> expect work, got %s" % got)
if got != "work":
    fails += 1

# negative control: give personal the reserve instead; the answer must flip
got2 = pick(("personal", 95, 3, 79, 60), ("work", 20, 3, 96, 153))
print("control (reserve flipped)                      -> expect personal, got %s" % got2)
if got2 != "personal":
    fails += 1

print("pass=%d fail=%d" % (2 - fails, fails))
sys.exit(1 if fails else 0)
PY
