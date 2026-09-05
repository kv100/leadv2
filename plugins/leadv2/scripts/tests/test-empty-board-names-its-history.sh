#!/usr/bin/env bash
# PULSE-BEATS-IN-IDLE-REPOS-01 — what the empty-board alarm undertakes to assert.
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: leadv2-broad-status
#
# MEASURED BEFORE ANY FIX, because the row asked for that. In an idle repo the beat is
# nearly free: one founder-status.md of 483 bytes, untracked, rewritten in place. So the
# beating is not the defect and was not touched. The WORDING is: platform/ carried
# "⚠ ДОСКА ПУСТА — ничего не выполняется, 4315 мин" -- a three-day outage alarm for a
# repo where no work was ever assigned. An idle repo and a stalled repo produced the
# same sentence, and the counter escalated in both.
#
# The fix invents no threshold and suppresses no alarm: headline and counter are
# untouched, and the two facts that separate the cases are appended when they exist --
# when this repo last had a lane, and how many it has ever had.
#
# WHAT IS REAL HERE: the production _board_empty_history_note is lifted out of
# leadv2-broad-status.sh and run. Only the repo tree is synthetic.
#
# DECLARED NEGATIVE CONTROL (tests/mutations/catalog.yaml): the guard line inside the
# function body becomes an unconditional `return 0`, so the alarm goes back to a bare
# minute counter. Kills (a) and (d); leaves (b) and (c) green -- the separator between
# "the alarm gained a fact" and "the alarm was changed or silenced".
set -uo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
SRC="${ROOT}/scripts/leadv2-broad-status.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

[[ -f "$SRC" ]] || { printf 'FAIL: %s not found\n[EMPTY-BOARD-HISTORY] pass=0 fail=1\n' "$SRC"; exit 1; }

# lift the REAL function body out of the production script
python3 - "$SRC" "$T/fn.sh" <<'PY'
import io, sys
s = io.open(sys.argv[1], encoding='utf-8').read()
k = '_board_empty_history_note() {'
i = s.index(k)
j = s.index('\n}\n', i) + 3
io.open(sys.argv[2], 'w', encoding='utf-8').write(s[i:j])
PY
[[ -s "$T/fn.sh" ]] || { printf 'FAIL: could not lift the function\n[EMPTY-BOARD-HISTORY] pass=0 fail=1\n'; exit 1; }

note(){ ( PROJECT_ROOT="$1"; . "$T/fn.sh"; _board_empty_history_note ); }

# (a) a repo that HAS had lanes: the alarm can name when, so the reader can tell an
# idle repo from a stalled one without a threshold being invented for them.
mkdir -p "$T/hasrepo/docs/handoff/dispatch-aaaa1111" \
         "$T/hasrepo/docs/handoff/dispatch-bbbb2222" \
         "$T/hasrepo/docs/handoff/dispatch-cccc3333"
got_a="$(note "$T/hasrepo")"
today="$(date '+%Y-%m-%d')"
if [[ "$got_a" == *"последняя линия здесь: ${today}"* && "$got_a" == *"линий за всё время: 3"* ]]; then
  ok "a repo with lanes gets both facts: when the last one was, and how many there ever were"
else
  bad "a: got '$got_a'"
fi

# (d) the count is read, not asserted -- a different number of lanes must say so.
mkdir -p "$T/onerepo/docs/handoff/dispatch-dddd4444"
got_d="$(note "$T/onerepo")"
if [[ "$got_d" == *"линий за всё время: 1"* ]]; then
  ok "the count reflects the tree, it is not a constant"
else
  bad "d: got '$got_d'"
fi

# (b) PAIRED NEGATIVE: no history to state -> the note is EMPTY, so the headline
# degrades to exactly today's text. The alarm must not be suppressed, and a fact must
# never be fabricated for a repo that has none.
mkdir -p "$T/norepo/docs"
got_b="$(note "$T/norepo")"
if [[ -z "$got_b" ]]; then
  ok "a repo with no lane history states nothing, so the alarm keeps its exact wording"
else
  bad "b: expected an empty note, got '$got_b'"
fi

# (c) PAIRED NEGATIVE TWO: a missing root must not crash the beat. A status composer
# that dies on a fact it could not gather is worse than one that omits the fact.
got_c="$(note "$T/does-not-exist-at-all" 2>&1)"; rc_c=$?
if [[ "$rc_c" -eq 0 && -z "$got_c" ]]; then
  ok "a missing root yields an empty note and a zero status, never a broken beat"
else
  bad "c: rc=$rc_c out='$got_c'"
fi

printf '[EMPTY-BOARD-HISTORY] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
