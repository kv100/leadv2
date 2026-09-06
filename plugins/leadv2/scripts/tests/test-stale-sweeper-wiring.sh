#!/usr/bin/env bash
# run-all-triggers: leadv2-stale-sweeper leadv2-stale-pid-sweep
# test-stale-sweeper-wiring.sh — STALE-SWEEPER-WIRING-01 coverage.
#
# Defect: leadv2-stale-sweeper.sh is the sole writer of the `stale` flag
# (the flag fanout's selection filter discounts) and it was wired NOWHERE —
# hooks.json registered 71 hooks, none invoked it, so the live registry
# accumulated 40 rows with zero stale against hard_limit 3 and every fanout
# launch was refused "hard_limit reached".
#
# Coverage:
#   1. WIRING — the registered SessionStart hook
#      (hooks/leadv2-stale-pid-sweep.sh) actually REACHES the sweep: a
#      provably-dead row comes out of the hook run marked `stale`. Three
#      legs: (a) MUTANT — the invocation block stripped from a mirror copy
#      of the hook must leave the row UNMARKED (the pre-fix colour,
#      reproduced, proving the wiring assertion is load-bearing);
#      (b) FAITHFUL MIRROR — an unstripped copy in the same layout must
#      mark it (proves the red in (a) is the missing invocation, not the
#      mirror layout); (c) REAL HOOK — the registered file itself must mark
#      it, and the live-pid / pid-less rows must survive.
#   2. SAFETY — paired negative control on the sweeper's eligibility floor
#      (predicate identical to _row_dead in leadv2-active-registry.sh): a
#      row with a LIVE pid and a row with NO pid must both survive a direct
#      sweep while a provably-dead row in the same file is marked — the
#      dead row proves the sweep ran rather than silently no-op'ing. Run
#      under both agents-JSON paths (stubbed `claude` returning a live
#      agents list, and returning nothing = pid-only fallback).
#
# Sandbox: LEADV2_STATE_ROOT redirects the control plane into the sandbox;
# the fixture repo is a throwaway git repo; a stub `claude` on PATH makes
# the agents-JSON evidence deterministic and fast.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SH="${SCRIPT_DIR}/../../hooks/leadv2-stale-pid-sweep.sh"
SWEEPER_SH="${SCRIPT_DIR}/../leadv2-stale-sweeper.sh"
STATE_PATH="${SCRIPT_DIR}/../leadv2-state-path.sh"

PASS=0; FAIL=0
ok()   { printf '  PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

SB="$(mktemp -d /tmp/stale-sweeper-wiring.XXXXXX)"
cleanup() { rm -rf "$SB"; }
trap cleanup EXIT

# ── fixture repo (never the real one) ────────────────────────────────────────
TARGET="${SB}/target"
mkdir -p "${TARGET}/docs/leadv2"
( cd "${TARGET}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )

export LEADV2_STATE_ROOT="${SB}/state"
export LEADV2_PROJECT_ROOT="${TARGET}"
export CLAUDE_PROJECT_DIR="${TARGET}"
unset LEADV2_LEADV2_DIR 2>/dev/null || true
unset LEADV2_STATE_PATH_BIN 2>/dev/null || true
mkdir -p "${LEADV2_STATE_ROOT}"
ACTIVE="$(PROJECT_ROOT="${TARGET}" LEADV2_STATE_ROOT="${LEADV2_STATE_ROOT}" \
  bash "${STATE_PATH}" active.yaml)"
mkdir -p "$(dirname "${ACTIVE}")"

# ── stub claude (deterministic agents-JSON evidence, no real CLI call) ──────
mkdir -p "${SB}/bin-agents" "${SB}/bin-empty"
printf '#!/usr/bin/env bash\nprintf %%s "[{\\"id\\":\\"someone-else-sess\\"}]"\n' > "${SB}/bin-agents/claude"
printf '#!/usr/bin/env bash\nexit 0\n' > "${SB}/bin-empty/claude"
chmod +x "${SB}/bin-agents/claude" "${SB}/bin-empty/claude"

# ── fixture pids ─────────────────────────────────────────────────────────────
# Provably dead: pid 1 — os.kill(1,0) raises EPERM, so _pid_alive returns
# False and the row is dead per the _row_dead predicate (same convention as
# test-stale-row-starting-grace.sh row M-01). A spawned-then-reaped pid is
# NOT usable here: in low-pid namespaces the number is recycled to a live
# process within seconds and the row flips back to alive mid-test.
# Live: the suite's own pid ($$) — a parent, guaranteed alive for every
# child sweeper/hook run, and never a candidate for the harness's
# background-sleep reaper.
DEAD_PID=1
LIVE_PID=$$

TS_OLD="$(python3 -c \
  "import datetime; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(hours=3)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"

write_registry() {
  cat > "$ACTIVE" <<YAML
meta:
  hard_limit: 3
  heavy_max: 2
  light_max: 3
  standard_max: 2
sessions:
- task_id: ssw-dead-row
  session_id: ssw-dead-sess
  pid: ${DEAD_PID}
  last_pulse_at: '${TS_OLD}'
  phase: build
  class: Standard
- task_id: ssw-live-row
  session_id: ssw-live-sess
  pid: ${LIVE_PID}
  last_pulse_at: '${TS_OLD}'
  phase: build
  class: Standard
- task_id: ssw-nopid-row
  session_id: ssw-nopid-sess
  pid: null
  last_pulse_at: '${TS_OLD}'
  phase: build
  class: Standard
YAML
}

row_state() { # <task_id> -> prints "stale" | "fresh" | "absent"
  python3 - "$ACTIVE" "$1" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding="utf-8") as fh:
    d = yaml.safe_load(fh) or {}
for s in d.get("sessions") or []:
    if s.get("task_id") == sys.argv[2]:
        print("stale" if s.get("stale") else "fresh")
        sys.exit(0)
print("absent")
PY
}

sweep_lines() { # tee the sweeper's own verdict lines out of a log
  grep -E '^\[sweeper\] (marked stale|[0-9]+ stale session|all sessions current)' "$1" 2>/dev/null \
    | sed 's/^/    /' || true
}

echo "== Part 1: safety floor (direct sweep, both agents-JSON paths) =="

for MODE in agents empty; do
  BIN="${SB}/bin-${MODE}"
  write_registry
  LOG="${SB}/sweep-${MODE}.log"
  # cwd = sandbox repo: every worktree enumeration (GC, orphan detection,
  # lane_reconcile) must see the one-worktree sandbox, never the real repo.
  ( cd "${TARGET}" && PATH="${BIN}:${PATH}" LEADV2_PROJECT_ROOT="${TARGET}" \
    bash "${SWEEPER_SH}" --non-interactive >"$LOG" 2>&1 ) || true
  echo "  [sweeper] lines (mode=${MODE}):"
  sweep_lines "$LOG"
  [[ "$(row_state ssw-dead-row)"   == "stale" ]] \
    && ok   "mode=${MODE}: dead-pid row marked stale (sweep ran)" \
    || bad  "mode=${MODE}: dead-pid row NOT marked — sweep never fired"
  [[ "$(row_state ssw-live-row)"   == "fresh" ]] \
    && ok   "mode=${MODE}: LIVE-pid row present and survived" \
    || bad  "mode=${MODE}: LIVE-pid row lost or marked (state=$(row_state ssw-live-row))"
  [[ "$(row_state ssw-nopid-row)"  == "fresh" ]] \
    && ok   "mode=${MODE}: pid-less row present and survived" \
    || bad  "mode=${MODE}: pid-less row lost or marked (state=$(row_state ssw-nopid-row))"
done

echo "== Part 2: wiring — registered hook must REACH the sweep =="

# Mirror layout: <dir>/hooks/<hook>.sh + <dir>/scripts -> real scripts dir,
# so a copy of the hook resolves ../scripts exactly like the installed file.
make_mirror() { # <dir>
  mkdir -p "${1}/hooks"
  ln -sfn "${SCRIPT_DIR}/.." "${1}/scripts"
}
MUTANT="${SB}/mutant"; FAITHFUL="${SB}/faithful"
make_mirror "$MUTANT"; make_mirror "$FAITHFUL"
cp "$HOOK_SH" "${FAITHFUL}/hooks/leadv2-stale-pid-sweep.sh"
# Named mutation: strip the sweeper invocation block from the hook.
sed -e '/^SWEEPER=/,/^# end STALE-SWEEPER-WIRING-01$/d' "$HOOK_SH" > "${MUTANT}/hooks/leadv2-stale-pid-sweep.sh"
bash -n "${MUTANT}/hooks/leadv2-stale-pid-sweep.sh" \
  || { bad "mutant hook is not valid bash"; }
if grep -q 'bash "$SWEEPER" --non-interactive' "${MUTANT}/hooks/leadv2-stale-pid-sweep.sh"; then
  bad "mutation did not strip the invocation (mutant still sweeps)"
else
  ok "mutation applied: invocation absent from mutant"
fi

run_hook() { # <hook-path> <logfile>
  write_registry
  # LEADV2_SSWEEP_NO_DETACH: the hook's stage-2 nohup full sweep is not under
  # test here and would outlive the sandbox; the mark-only stage is what the
  # wiring assertions read.
  ( cd "${TARGET}" && PATH="${SB}/bin-agents:${PATH}" CLAUDE_PROJECT_DIR="${TARGET}" \
    LEADV2_PROJECT_ROOT="${TARGET}" LEADV2_STATE_ROOT="${SB}/state" \
    LEADV2_SSWEEP_NO_DETACH=1 \
    bash "$1" >"$2" 2>&1 ) || true
}

# (a) mutant — the pre-fix colour: no invocation, row stays unmarked
run_hook "${MUTANT}/hooks/leadv2-stale-pid-sweep.sh" "${SB}/hook-mutant.log"
[[ "$(row_state ssw-dead-row)" == "fresh" ]] \
  && ok   "mutant hook (invocation stripped): dead row NOT marked — pre-fix colour reproduced" \
  || bad  "mutant hook still swept the row — mutation is not load-bearing"

# (b) faithful mirror — same layout, unstripped: must mark (isolates the cause)
run_hook "${FAITHFUL}/hooks/leadv2-stale-pid-sweep.sh" "${SB}/hook-faithful.log"
echo "  [sweeper] lines (faithful mirror):"
sweep_lines "${SB}/hook-faithful.log"
[[ "$(row_state ssw-dead-row)" == "stale" ]] \
  && ok   "faithful mirror hook: dead row marked — mirror layout reaches the sweeper" \
  || bad  "faithful mirror failed to sweep — mirror layout is broken, mutation leg proves nothing"

# (c) the real, registered hook file
run_hook "$HOOK_SH" "${SB}/hook-real.log"
echo "  [sweeper] lines (real hook):"
sweep_lines "${SB}/hook-real.log"
[[ "$(row_state ssw-dead-row)" == "stale" ]] \
  && ok   "registered hook: dead row marked — the sweep IS reached at SessionStart" \
  || bad  "registered hook did not reach the sweep (state=$(row_state ssw-dead-row))"
[[ "$(row_state ssw-live-row)" == "fresh" ]] \
  && ok   "registered hook: LIVE-pid row survived" \
  || bad  "registered hook harmed the LIVE-pid row"
[[ "$(row_state ssw-nopid-row)" == "fresh" ]] \
  && ok   "registered hook: pid-less row survived" \
  || bad  "registered hook harmed the pid-less row"

echo "test-stale-sweeper-wiring: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
