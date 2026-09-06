#!/usr/bin/env bash
# test-guard-says-when-it-could-not-check.sh
# GUARDS-SELF-DISABLE-ON-THE-EMPTY-WRITE-SET-01 — pass two
#
# Subject: the REAL _foreign_check from leadv2-reply-router.sh, lifted out of the
# script and driven directly. Nothing in it is stubbed — the same python/yaml
# read, the same age arithmetic. Faked one level lower: the question yaml.
#
# The finding this pins (measured 2026-09-06, second-pass census): NOT ONE of
# 8270 q-*.yaml rows on this machine carries an owner_session, so the branch
# commented "old row (pre-OWNERSHIP)" is the entire population — the foreign
# question protection has never engaged, and returned success without a word.
# The fix does not turn it into a refusal (that would block every answer); it
# makes "could not check" distinguishable from "checked and it is yours".
#
# DECLARED NEGATIVE CONTROLS (apply INSIDE _foreign_check's body; each must turn
# this suite RED):
#   M1  delete the UNAVAILABLE printf in the empty-owner branch => case (a)
#       fails: the guard is silent again.
#   M2  make the empty-owner branch `return 6` instead of 0 => case (b) fails:
#       every answer on the machine would be refused. Naming a gap is not
#       licence to close it with a wall.
# Case (c) -- a real young foreign question is still REFUSED -- must stay green
# under BOTH: the protection itself is untouched by this work.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER="${LEADV2_REPLY_ROUTER_SH:-${SCRIPT_DIR}/../leadv2-reply-router.sh}"
[[ -f "${ROUTER}" ]] || { echo "FATAL: router not found: ${ROUTER}" >&2; exit 2; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/guard-says.XXXXXX")" || exit 2
trap 'rm -rf "${WORK}"' EXIT

# Lift the real function body out of the script (no sourcing: the script runs a
# CLI on load). Same extraction the other suites in this repo use.
python3 - "${ROUTER}" "${WORK}/fn.sh" <<'PY'
import io, sys
src = io.open(sys.argv[1], encoding='utf-8').read()
i = src.index('_foreign_check() {')
j = src.index('\n}\n', i) + 3
io.open(sys.argv[2], 'w', encoding='utf-8').write(src[i:j])
PY
[[ -s "${WORK}/fn.sh" ]] || { echo "FATAL: could not lift _foreign_check" >&2; exit 2; }
# shellcheck disable=SC1090
. "${WORK}/fn.sh"

mkq() { # <file> <owner_session|-> <asked_at|->
  { printf 'qid: q-fixture\n'
    [[ "$2" != "-" ]] && printf 'owner_session: %s\n' "$2"
    # QUOTED, exactly as leadv2-ask.sh writes it (PyYAML quotes a string that
    # would otherwise re-resolve as a timestamp). An unquoted fixture parses
    # back as a datetime, strptime throws, and the age reads as unverifiable --
    # a third "blind path" that exists only in the fixture. Checked against a
    # live row: docs/leadv2/questions/q-*.yaml carries asked_at: '...Z'.
    [[ "$3" != "-" ]] && printf "asked_at: '%s'\n" "$3"
    printf 'question: fixture\n'; } > "$1"
}
NOW="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

run() { # <qfile> <caller_session> -> sets RC, OUT(stderr)
  # Consumed by the lifted function, not by this file (shellcheck cannot see
  # across the extraction).
  # shellcheck disable=SC2034
  QID="q-fixture"
  # shellcheck disable=SC2034
  FORCE_FOREIGN=0
  OUT="$(CLAUDE_SESSION_ID="$2" _foreign_check "$1" 2>&1 >/dev/null)"; RC=$?
  return 0
}

echo "== the population: a row with no owner at all"
mkq "${WORK}/none.yaml" - "${NOW}"
run "${WORK}/none.yaml" "sess-caller"
if [[ "${RC}" == "0" ]] && grep -q 'UNAVAILABLE.*no_owner_session' <<< "${OUT}"; then
  ok "(a) empty owner: still allowed, and it SAYS nothing was verified"
elif [[ "${RC}" == "0" ]]; then
  bad "(a) allowed silently — 'could not check' still reads as 'checked' (stderr='${OUT:0:70}')"
else
  bad "(a) rc=${RC}: the empty-owner row was refused, not merely unverified"
fi

# (b) NEG-CTL: it must still ALLOW. A guard that answers a gap with a wall would
#     refuse every answer on this machine, since 8270 of 8270 rows look like this.
if [[ "${RC}" == "0" ]]; then
  ok "(b) NEG-CTL: naming the gap did not turn the guard into a wall (rc=0)"
else
  bad "(b) NEG-CTL: rc=${RC} — the fix would block every answer on the machine"
fi

echo "== the protection itself, where it has input"
mkq "${WORK}/foreign.yaml" "sess-owner" "${NOW}"
run "${WORK}/foreign.yaml" "sess-other"
if [[ "${RC}" == "6" ]]; then
  ok "(c) NEG-CTL: a young FOREIGN question is still refused (rc=6)"
else
  bad "(c) NEG-CTL: foreign question no longer refused (rc=${RC}) — the protection was damaged"
fi

mkq "${WORK}/own.yaml" "sess-me" "${NOW}"
run "${WORK}/own.yaml" "sess-me"
if [[ "${RC}" == "0" ]] && [[ -z "${OUT}" ]]; then
  ok "(d) own question: allowed, and NOT warned about (the notice is for the blind path only)"
else
  bad "(d) rc=${RC} stderr='${OUT:0:70}' — the guard became noisy on a path it can check"
fi

echo "== the second blind branch: an age it cannot parse"
mkq "${WORK}/noage.yaml" "sess-owner" -
run "${WORK}/noage.yaml" "sess-other"
if [[ "${RC}" == "0" ]] && grep -q 'UNAVAILABLE.*unparseable_asked_at' <<< "${OUT}"; then
  ok "(e) unparseable age: allowed, and says the age was not verified"
else
  bad "(e) rc=${RC} stderr='${OUT:0:70}'"
fi

echo
echo "passed=${PASS} failed=${FAIL}"
[[ ${FAIL} -eq 0 ]]
