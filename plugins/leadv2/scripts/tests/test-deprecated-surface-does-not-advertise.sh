#!/usr/bin/env bash
# CAPABILITY-TRUTH-AUDIT-01 — a dead surface must not advertise itself as live.
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: leadv2-po-queue
#
# THE ONE OVER-CLAIM THE AUDIT FOUND. Across 142 files with an argument surface, 259
# advertised flags resolved to 253 reachable, 1 undetermined (argv forwarded onward) and
# 4 that do not exist -- all four in this script. Every subcommand here exits 2 with a
# deprecation notice, yet `usage()` -- which is what a bare invocation prints -- still
# sold claim/release/peek/validate as working, with their flags. The first thing a
# caller saw was a false claim; the second was the refusal.
#
# The fix is to the CLAIM, never to the behaviour: the refusals must stay exactly as
# they are. Cases (b) and (c) are the paired negative -- a truthful help text must not
# become either a silencing or a re-enabling.
#
# DECLARED NEGATIVE CONTROL (tests/mutations/catalog.yaml): the `REFUSED` markers and
# the DEPRECATED banner are dropped from the usage heredoc, restoring a help text that
# advertises four subcommands the script will not run. Kills (a); leaves (b) and (c)
# green, which is the separator between "the claim was corrected" and "the surface was
# changed".
set -uo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
PQ="${ROOT}/scripts/leadv2-po-queue.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

[[ -f "$PQ" ]] || { printf 'FAIL: %s not found\n[DEPRECATED-SURFACE] pass=0 fail=1\n' "$PQ"; exit 1; }

# (a) a bare invocation prints the help, and the help must not claim a live surface.
help_out="$(bash "$PQ" 2>&1 >/dev/null)"; help_rc=$?
if [[ "$help_out" == *"DEPRECATED"* ]] \
   && [[ "$help_out" == *"leadv2-queue-claim.sh"* ]] \
   && [[ "$(printf '%s' "$help_out" | grep -c 'REFUSED')" -ge 4 ]]; then
  ok "the help text names itself deprecated, points at the replacement, and marks every subcommand refused"
else
  bad "a: rc=$help_rc help did not declare itself dead: $(printf '%s' "$help_out" | tr '\n' ' ' | cut -c1-150)"
fi

# (b) PAIRED NEGATIVE ONE: the behaviour is untouched -- every advertised subcommand
# still refuses, with the status callers branch on and the replacement named. A help
# rewrite that quietly re-enabled any of them would be far worse than the false claim.
still_refusing=1
for sub in claim release peek validate bogus; do
  out="$(bash "$PQ" "$sub" --task-id x 2>&1 >/dev/null)"; rc=$?
  [[ "$rc" -eq 2 && "$out" == *"DEPRECATED"* && "$out" == *"leadv2-queue-release.sh"* ]] || still_refusing=0
done
(( still_refusing )) && ok "every subcommand still refuses with rc=2 and names its replacement" \
                     || bad "b: a subcommand stopped refusing or stopped naming the replacement"

# (c) PAIRED NEGATIVE TWO: the flags are still ADDRESSABLE in the text. The point of the
# fix is that an old caller can find what it was reaching for; erasing the names would
# make the script silent about a surface people still have in their scripts.
if [[ "$help_out" == *"--task-id"* && "$help_out" == *"--prefer"* && "$help_out" == *"--item"* ]]; then
  ok "the old flag names are still printed, so an old caller can recognise its own call"
else
  bad "c: the help erased the flag names instead of marking them dead"
fi

printf '[DEPRECATED-SURFACE] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
