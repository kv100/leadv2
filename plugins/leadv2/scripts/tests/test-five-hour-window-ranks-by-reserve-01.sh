#!/usr/bin/env bash
# run-all-triggers: leadv2-claude-profile-pick.py
# FIVE-HOUR-WINDOW-NEVER-ENTERS-THE-ACCOUNT-CHOICE-01 acceptance suite
# (founder order 2026-09-16: the near-reset burn rule was ordered for the
# WEEKLY quota only; the five-hour window is compared as a RESERVE).
#
# The picker is a pure module (stdin only), so the suite drives it directly.
# Negative controls (run by leadv2-mutation-control.sh):
#   1. in score_payload, drop the five-hour reserve branch -> cases 1 and 2
#      must go red (the founder's case returns to binding_window ranking).
#   2. in score_payload, swap the reserve order key to (fh_reserve, ...) ->
#      cases 1 and 2 must go red with profile=personal.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PICK="${SCRIPT_DIR}/../lib/leadv2-claude-profile-pick.py"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

mkrec() { # <label> <config_dir> <json>
  printf '%s\t%s\tfile:stub\t%s\tunknown/na\t0\t0\t-\t-\n' \
    "$1" "$2" "$(printf '%s' "$3" | base64 | tr -d '\n')"
}

acct() { # <fh_pct> <fh_remaining> <fh_usable> <fh_reset> <sd_pct> <sd_remaining> <sd_usable> <sd_reset> <binding>
  printf '{"provider":"anthropic","status":"ok","accounts":[{"status":"ok","active":true,"account_label":"stub","five_hour_pct":%s,"seven_day_pct":%s,"five_hour":{"pct":%s,"reset_iso":"%s","remaining_pct":%s,"hours_to_reset":2.0,"usable_now":%s},"seven_day":{"pct":%s,"reset_iso":"%s","remaining_pct":%s,"hours_to_reset":60.0,"usable_now":%s},"binding_window":"%s"}],"active_account":"stub","fetched_at":"2026-09-16T12:00:00Z"}' \
    "$1" "$5" "$1" "$4" "$2" "$3" "$5" "$8" "$6" "$7" "$9"
}

pick() { # records on stdin -> picker output line
  python3 "$PICK"
}

# Case 1 — the founder's case, measured by the lead 2026-09-16:
#   personal 5h=20% left, weekly=79% left (usable 1.317), binding=seven_day
#   work     5h=95% left, weekly=96% left (usable 0.627), binding=seven_day
# Old code ranked seven_day rates (1.317 > 0.627) and picked personal; the
# five-hour numbers were never compared.  The five-hour reserve must gate.
OUT="$( { mkrec personal /d/p "$(acct 80 20 10.0 2026-09-16T14:00:00Z 21 79 1.317 2026-09-19T04:00:00Z seven_day)"
          mkrec work     /d/w "$(acct 5  95 31.667 2026-09-16T15:00:00Z 4 96 0.627 2026-09-23T04:00:00Z seven_day)"; } | pick )"
if [[ "$OUT" == profile=work\ config_dir=/d/w\ * ]]; then
  pass "case 1 (founder's case): work wins on five-hour reserve"
else
  fail "case 1: expected profile=work, got: $OUT"
fi
if [[ "$OUT" == *'reason=five_hour_reserve'* ]]; then
  pass "case 1: reason names the reserve gate"
else
  fail "case 1: reason=five_hour_reserve missing: $OUT"
fi

# Case 2 — cross-window ranking (second defect, same root): personal binds
# five_hour at 2% left (usable rate 0.50), work binds seven_day (0.627).  The
# old code ranked 0.50 against 0.627 -- a five-hour rate against a weekly
# rate.  No account may be ranked against another on a different window.
OUT="$( { mkrec personal /d/p "$(acct 98 2 0.5 2026-09-16T16:00:00Z 21 79 1.317 2026-09-19T04:00:00Z five_hour)"
          mkrec work     /d/w "$(acct 5  95 31.667 2026-09-16T15:00:00Z 4 96 0.627 2026-09-23T04:00:00Z seven_day)"; } | pick )"
if [[ "$OUT" == profile=work\ config_dir=/d/w\ * ]]; then
  pass "case 2 (cross-window): work wins; no rate-vs-reserve cross comparison"
else
  fail "case 2: expected profile=work, got: $OUT"
fi

# Case 3 — passing control: both accounts carry the SAME five-hour reserve
# (50% left), so the weekly rate decides.  Under today's (pre-fix) code both
# bind seven_day and the higher usable_now (work, 1.2 > 0.5) wins; the fix
# must keep that answer via the weekly tiebreak.  A green run without this
# case cannot be distinguished from a picker that stopped asserting.
OUT="$( { mkrec personal /d/p "$(acct 50 50 25.0 2026-09-16T14:00:00Z 40 60 0.5 2026-09-19T04:00:00Z seven_day)"
          mkrec work     /d/w "$(acct 50 50 25.0 2026-09-16T14:00:00Z 10 90 1.2 2026-09-21T04:00:00Z seven_day)"; } | pick )"
if [[ "$OUT" == profile=work\ config_dir=/d/w\ * ]]; then
  pass "control: equal five-hour reserves -> weekly rate still decides (work)"
else
  fail "control: expected profile=work, got: $OUT"
fi

# Case 4 — the five-hour reserve is the ONLY quantity that differs when it
# differs: personal weekly usable is HIGHER (1.317 > 0.627) but its reserve
# is 10% vs work's 60% -- reserve must win, weekly rate must not override it.
OUT="$( { mkrec personal /d/p "$(acct 90 10 5.0 2026-09-16T14:00:00Z 21 79 1.317 2026-09-19T04:00:00Z seven_day)"
          mkrec work     /d/w "$(acct 40 60 30.0 2026-09-16T15:00:00Z 4 96 0.627 2026-09-23T04:00:00Z seven_day)"; } | pick )"
if [[ "$OUT" == profile=work\ config_dir=/d/w\ * ]]; then
  pass "case 4: reserve outranks a higher weekly rate"
else
  fail "case 4: expected profile=work, got: $OUT"
fi

printf 'pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
