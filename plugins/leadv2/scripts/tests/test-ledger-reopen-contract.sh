#!/usr/bin/env bash
# LEDGER-HAS-NO-REOPEN-01 — what "reopen" means here, stated and pinned.
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: leadv2-dispatch-ledger
#
# DECLARED BEFORE ANY FIX, because the row asked for that first. The ledger is
# append-only JSONL keyed by sig8, written concurrently by several sessions, and its
# readers take the LAST row for a sig. So "return the old row to open" is not something
# it can mean. What it can mean splits in two, and half of it is ALREADY TRUE:
#
#   refused | parked | no_work   already reopenable with no subcommand at all — the
#       write-once gate does not block them, dispatch_terminal_exists() reports the sig8
#       UNFINISHED, and the next attempt writes its own row.
#   landed | dead | dead_with_unlanded_work | pass_unlanded   write-once BY DESIGN. A
#       reopen that flipped one would destroy the very property the row's own paired
#       negative demands — a confirmed close must not become reopenable by accident.
#       Correcting one is a NEW dispatch, i.e. a new sig8 with its own rows.
#
# So no reopen was built. What was missing is that the CLI answered the request with a
# bare usage dump, leaving "there is no reopen" indistinguishable from "you typed it
# wrong". Cases (c)/(d) below are the pair the row demands, and they test the LEDGER's
# behaviour, not the wording.
#
# DECLARED NEGATIVE CONTROL (tests/mutations/catalog.yaml): in
# dispatch_ledger_write_terminal's write-once gate, `landed` is dropped from the
# blocklist arm. Kills (d) — a confirmed close becomes overwritable — and leaves (c)
# green, which is what separates "reopen exists for retryable words" from "the ledger
# stopped asserting anything".
set -uo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
LEDGER="${ROOT}/scripts/leadv2-dispatch-ledger.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

export LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$T/terminal.jsonl"
export LEADV2_DISPATCH_CACHE_DIR="$T/cache"
mkdir -p "$T/cache"
: > "$LEADV2_DISPATCH_TERMINAL_LEDGER_FILE"
led(){ bash "$LEDGER" "$@"; }
rows(){ grep -c . "$LEADV2_DISPATCH_TERMINAL_LEDGER_FILE" 2>/dev/null || printf '0'; }

# (a) the request must be answered, not dumped on. rc is unchanged (2, same as a usage
# error) so nothing branching on the status moves; the stream is what changes.
out="$(led reopen deadbeef 2>&1 >/dev/null)"; rc=$?
if [[ "$rc" -eq 2 && "$out" == *"ALREADY reopenable"* && "$out" == *"write-once by design"* ]]; then
  ok "reopen answers with the contract and keeps rc=2"
else
  bad "a: rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)"
fi

# (b) a real subcommand must still behave — the new case must not have swallowed the
# dispatcher's own routing.
led exists deadbeef >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "an unseen sig8 is still reported unfinished by exists" || bad "b: exists on an unseen sig8 did not return 1"

# (c) HALF ONE OF THE PAIR: a retryable close is ALREADY reopen — no subcommand needed.
led write-terminal aaaa1111 TASK-A refused writeset_pending >/dev/null 2>&1
before="$(rows)"
led exists aaaa1111 >/dev/null 2>&1; ex_rc=$?
led write-terminal aaaa1111 TASK-A landed ok >/dev/null 2>&1; second_rc=$?
after="$(rows)"
if [[ "$ex_rc" -eq 1 && "$second_rc" -eq 0 && "$after" -gt "$before" ]]; then
  ok "a refused close is already reopenable: exists says unfinished and a later terminal lands"
else
  bad "c: exists_rc=$ex_rc second_write_rc=$second_rc rows ${before}->${after}"
fi

# (d) HALF TWO, THE ONE THE ROW DEMANDS: a confirmed close must NOT become reopenable.
# Same shape as (c) but starting from a true terminal — the write must be refused and
# the file must not grow.
led write-terminal bbbb2222 TASK-B landed ok >/dev/null 2>&1
before2="$(rows)"
led write-terminal bbbb2222 TASK-B dead crashed >/dev/null 2>&1
after2="$(rows)"
led exists bbbb2222 >/dev/null 2>&1; ex2_rc=$?
last2="$(led cause bbbb2222 2>/dev/null; led state bbbb2222 2>/dev/null)"
# The write-once gate is a DEDUP, not an error: it declines to append and reports 0, and
# the first version of this case asserted a non-zero status and went red against a ledger
# that was behaving correctly. What must be true is about the LEDGER, not the exit code --
# the file does not grow, the sig8 still reads finished, and the recorded word is still
# the landed one, never the `dead` that tried to overwrite it.
if [[ "$after2" -eq "$before2" && "$ex2_rc" -eq 0 && "$last2" != *"crashed"* ]]; then
  ok "a landed close stays closed: the overwrite appends nothing and the word does not change"
else
  bad "d: rows ${before2}->${after2} exists_rc=$ex2_rc last='$(printf '%s' "$last2" | tr '\n' ' ' | cut -c1-90)'"
fi

printf '[LEDGER-REOPEN-CONTRACT] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
