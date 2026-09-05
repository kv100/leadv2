#!/usr/bin/env bash
# DISPATCH-EXITS-ZERO-ON-UNREADABLE-MISSION-01 — the actionable line must be the LAST
# line of stderr, and the positional mission form must stay intact.
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: leadv2-dispatch-code
#
# WHAT THE ROW CLAIMED AND WHAT IS TRUE. The row says `--mission-file` makes the
# dispatcher print its help and exit ZERO. Measured 2026-09-05: it exits 1 — the
# `--*` branch calls usage(), and usage() ends in `exit 1`. Case (a) pins that, so
# the claim can never be re-filed from memory. What genuinely misleads is placement:
# the one actionable line was printed FIRST and then buried under ~90 lines of help
# on the same stream, so a reader who tails the output — or pipes it, where the
# pipeline's status is the filter's 0 and not this 1 — sees only help and reads the
# run as a successful no-op.
#
# WHAT THIS SUITE DOES NOT COVER, said rather than implied: that a correct dispatch
# actually reaches arm resolution. Running one has real side effects (worktrees,
# ledger rows, a spawned worker), so the positional path is pinned at the two
# refusals that happen BEFORE any of that — which is enough to prove `@file` and an
# inline mission are still routed to the mission resolver rather than to the
# unknown-flag branch.
#
# DECLARED NEGATIVE CONTROL (tests/mutations/catalog.yaml): usage()'s trailing
# `[[ -n "${1:-}" ]] && log_err "$1"` is deleted, re-burying the reason. Kills (a).
set -uo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
DISPATCH="${ROOT}/scripts/leadv2-dispatch-code.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

run(){ # <args...> -> sets RC, ERR_LAST, ERR_ALL
  local err; err="$(mktemp)"
  bash "$DISPATCH" "$@" >/dev/null 2>"$err"; RC=$?
  ERR_ALL="$(cat "$err")"; ERR_LAST="$(printf '%s\n' "$ERR_ALL" | grep -v '^[[:space:]]*$' | tail -1)"
  rm -f "$err"
}

# (a) the defect: an unrecognised flag must be refused nonzero AND its reason must be
# the last thing on the stream, not the first thing under a wall of help.
run --mission-file /tmp/does-not-exist-either.md
if [[ "$RC" -ne 0 && "$ERR_LAST" == *"unknown arg: --mission-file"* && "$ERR_LAST" == *"nothing was dispatched"* ]]; then
  ok "an unknown flag exits nonzero and its reason is the LAST line of stderr"
else
  bad "a: rc=$RC last='$ERR_LAST'"
fi

# (b) the help itself must still be printed — the fix is placement, not suppression.
if [[ "$ERR_ALL" == *"Usage:"* ]]; then
  ok "the full usage block is still printed above the reason"
else
  bad "b: usage block missing from stderr"
fi

# (c) PAIRED NEGATIVE. The positional @file form must still be routed to the mission
# resolver. An unreadable @file refuses with its OWN message, never 'unknown arg'.
run @/tmp/no-such-mission-file-here.md
if [[ "$RC" -ne 0 && "$ERR_ALL" == *"cannot read mission file"* && "$ERR_ALL" != *"unknown arg"* ]]; then
  ok "@file is still a mission, not an unknown flag"
else
  bad "c: rc=$RC all='$(printf '%s' "$ERR_ALL" | tr '\n' ' ' | cut -c1-200)'"
fi

# (d) PAIRED NEGATIVE. An inline positional mission is still collected as text and
# refused for being empty — again its own message, not 'unknown arg'.
run "   "
if [[ "$RC" -ne 0 && "$ERR_ALL" == *"mission"* && "$ERR_ALL" != *"unknown arg"* ]]; then
  ok "an inline positional mission is still collected as text"
else
  bad "d: rc=$RC all='$(printf '%s' "$ERR_ALL" | tr '\n' ' ' | cut -c1-200)'"
fi

printf '[DISPATCH-USAGE-NAMES-THE-FAULT-LAST] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
