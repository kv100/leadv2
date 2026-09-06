#!/usr/bin/env bash
# CODEX-TRANSPORT-DIES-ROOT-CAUSE-01 — the broker's socket must outlive our session.
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: codex-task
#
# WHAT THIS PINS. The codex broker puts its session dir, and the unix socket inside it,
# in os.tmpdir(). Measured 2026-09-06 over 360 retained broker records: 14 point into
# /tmp/claude-503/cxc-*, a Claude Code SESSION scratch dir that dies with its session --
# taking a live broker's socket while the record survives. A record cannot survive an
# ordinary teardown (clearBrokerSession follows teardownBrokerSession), so record-without-
# directory is the fingerprint of an external removal, which is what the job sees as
# transport_gone_app_server_absent.
#
# Case (b) is the negative control the row demands: a broker directory created under the
# pinned root SURVIVES the destruction of the session scratch. Cases (c) and (d) are the
# other half -- a fix that bricks codex, or that reaps a live broker, would be worse than
# the fault it removes.
#
# WHAT IS REAL HERE: the production _codex_durable_tmpdir is lifted out of codex-task.sh
# and run. Only the directories are synthetic.
#
# DECLARED NEGATIVE CONTROL (tests/mutations/catalog.yaml): the `export TMPDIR=...` line
# inside the function body is dropped, restoring inheritance of the session scratch.
# Kills (a), (b) and (e); leaves (c) and (d) green. (e) dies with the export on purpose --
# the operator override IS implemented by that export, so it cannot outlive it; (c) and (d)
# are the halves that must survive any rewording, because they are what stops this fix from
# bricking codex or reaping a live broker.
set -uo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
SRC="${ROOT}/scripts/codex-task.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

[[ -f "$SRC" ]] || { printf 'FAIL: %s not found\n[CODEX-TMPDIR] pass=0 fail=1\n' "$SRC"; exit 1; }
python3 - "$SRC" "$T/fn.sh" <<'PY'
import io, sys
s = io.open(sys.argv[1], encoding='utf-8').read()
k = '_codex_durable_tmpdir() {'
i = s.index(k); j = s.index('\n}\n', i) + 3
io.open(sys.argv[2], 'w', encoding='utf-8').write(s[i:j])
PY
[[ -s "$T/fn.sh" ]] || { printf 'FAIL: could not lift the function\n[CODEX-TMPDIR] pass=0 fail=1\n'; exit 1; }

# run the real function in a subshell with a synthetic HOME and a session-scratch TMPDIR
run_fn(){ # <extra env assignments...> -> prints resulting TMPDIR
  ( export HOME="$T/home"; export TMPDIR="$T/scratch-session"
    mkdir -p "$HOME" "$TMPDIR"
    while [[ $# -gt 0 ]]; do export "$1"; shift; done
    # shellcheck disable=SC1090
    . "$T/fn.sh"; _codex_durable_tmpdir; printf '%s' "$TMPDIR" )
}

# (a) the pin happens, and the result is a usable directory -- an unusable TMPDIR would
# break mkdtemp and take down every codex job.
got="$(run_fn)"
if [[ "$got" == "$T/home/.claude/plugins/data/codex-openai-codex/tmp" && -d "$got" && -w "$got" ]]; then
  ok "TMPDIR is pinned to the plugin's durable data dir, and it exists and is writable"
else
  bad "a: got '$got' (exists=$([[ -d "$got" ]] && echo y || echo n))"
fi

# (b) THE NEGATIVE CONTROL: a broker dir under the pinned root survives the session
# scratch being destroyed. This is the whole claim of the fix.
mkdir -p "$T/scratch-session"
brk="$(mktemp -d "${got}/cxc-XXXXXX")"; : > "$brk/broker.sock"
rm -rf "$T/scratch-session"
if [[ -d "$brk" && -e "$brk/broker.sock" ]]; then
  ok "a broker dir under the pinned root survives destruction of the session scratch"
else
  bad "b: the broker dir did not survive: $brk"
fi

# (c) PAIRED NEGATIVE: if the durable dir cannot be made, TMPDIR is left as inherited.
# A fix that bricks codex is worse than the fault.
blocked="$T/home2/blocked"
mkdir -p "$T/home2"; : > "$blocked"      # a FILE where the dir would go
got_c="$( export HOME="$T/home2"; export TMPDIR="$T/scratch2"; mkdir -p "$TMPDIR"
          # shellcheck disable=SC1090
          . "$T/fn.sh"; LEADV2_CODEX_TMPDIR="$blocked/x" _codex_durable_tmpdir; printf '%s' "$TMPDIR" )"
if [[ "$got_c" == "$T/scratch2" ]]; then
  ok "an unusable durable dir leaves TMPDIR exactly as inherited"
else
  bad "c: TMPDIR was changed to '$got_c' despite an unusable target"
fi

# (d) PAIRED NEGATIVE TWO: the bounded prune must never touch a live broker. A fresh
# cxc-* and any non-cxc entry both survive; only something a week old goes.
# base of its own: the prune runs BEFORE the export, so it must still be exercised when
# the export is gone -- otherwise this case measures the fixture, not the prune.
pbase="$T/prune-base"; mkdir -p "$pbase"
fresh="$(mktemp -d "${pbase}/cxc-XXXXXX")"; other="${pbase}/keepme"; mkdir -p "$other"
old="${pbase}/cxc-ancient"; mkdir -p "$old"; touch -t 202501010000 "$old" 2>/dev/null
run_fn "LEADV2_CODEX_TMPDIR=$pbase" >/dev/null
if [[ -d "$fresh" && -d "$other" && ! -d "$old" ]]; then
  ok "the prune takes only week-old cxc-* dirs, never a fresh one and never anything else"
else
  bad "d: fresh=$([[ -d "$fresh" ]] && echo kept || echo GONE) other=$([[ -d "$other" ]] && echo kept || echo GONE) old=$([[ -d "$old" ]] && echo STILL || echo gone)"
fi

# (e) the operator keeps the wheel: an explicit override wins, and the kill switch works.
got_e="$(run_fn "LEADV2_CODEX_TMPDIR=$T/custom")"
got_off="$(run_fn "LEADV2_CODEX_DURABLE_TMPDIR=0")"
if [[ "$got_e" == "$T/custom" && "$got_off" == "$T/scratch-session" ]]; then
  ok "an explicit LEADV2_CODEX_TMPDIR wins, and =0 restores the inherited behaviour"
else
  bad "e: override='$got_e' killswitch='$got_off'"
fi

printf '[CODEX-TMPDIR] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
