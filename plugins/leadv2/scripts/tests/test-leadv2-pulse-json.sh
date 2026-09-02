#!/usr/bin/env bash
# test-leadv2-pulse-json.sh — PULSE-HOOK-IS-A-FORKED-COPY-01.
#
# Locks the LAST RESORT task_id resolver in hooks/leadv2-pulse-json.sh:
#   1. a registry holding ONLY dead rows (dead_at / deregistered) resolves to
#      NO task id — the pulse lands in _unknown/, never in a dead lane dir;
#   2. a dead row followed by a live row → the live row is chosen;
#   3. a row dead by `event: deregistered` alone (no dead_at) is skipped too;
#   4. no registry at all → _unknown (pre-existing contract, kept);
#   5. NEGATIVE CONTROL: a mutant copy of the hook with the dead-row skip
#      removed (the old exit-on-first-match resolver) must go RED on case 1 —
#      proves the suite actually grades the fix, not the harness.
# The registry is reached through leadv2-state-path.sh with LEADV2_STATE_ROOT
# sandboxed (the same knob production honour); the repo-local docs/leadv2
# symlink path is deliberately absent from the fixture so case 2 proves the
# control plane is read, not the fallback.
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
HOOK="${ROOT}/plugins/leadv2/hooks/leadv2-pulse-json.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

[ -f "$HOOK" ] || { echo "FAIL: hook missing: $HOOK"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pulse-json.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

# fire <proj> <registry-content-file-or-empty> <out-var> — runs one hook shot
# in a fresh project (docs/handoff only) and echoes the resolved task_id.
setup_proj() {
  local proj="$1" reg="$2"
  mkdir -p "$proj/docs/handoff" "$proj/docs/leadv2"
  rm -f "$proj/docs/leadv2/active.yaml"   # fallback path must NOT exist
  rm -rf "${LEADV2_STATE_ROOT:?}"
  if [[ -n "$reg" ]]; then
    mkdir -p "$LEADV2_STATE_ROOT"
    cp "$reg" "$LEADV2_STATE_ROOT/active.yaml"
  fi
}
fire() {
  local proj="$1"
  ( cd "$proj" && \
    CLAUDE_PROJECT_DIR="$proj" LEADV2_STATE_ROOT="$TMP/state" \
    LEADV2_TASK_ID= LEADV2_PULSE_TASK_ID= LEADV2_PHASE= \
    bash "$HOOK" <<< '{"tool_name":"Bash","session_id":"sess-pj-01"}' >/dev/null 2>&1 )
  # echo resolved tid from wherever pulse.json landed (or NONE)
  local f tid
  f="$(find "$proj/docs/handoff" -name pulse.json -maxdepth 2 2>/dev/null | head -1)"
  if [[ -n "$f" ]]; then
    tid="$(sed -n 's/.*"task_id":"\([^"]*\)".*/\1/p' "$f")"
    printf '%s' "${tid:-NONE}"
  else
    printf '%s' "NO-PULSE"
  fi
}

DEAD_ONLY="$TMP/reg-dead-only.yaml"
cat > "$DEAD_ONLY" <<'EOF'
meta:
  schema_version: 2
sessions:
- task_id: PULSE-DEAD-ROW-A
  session_id: deadarm-a
  worktree: /tmp/nope-a
  dead_at: '2026-09-02T11:51:32Z'
  history:
  - event: reconciled_dead
- task_id: PULSE-DEAD-ROW-B
  session_id: deadarm-b
  worktree: /tmp/nope-b
  dead_at: '2026-09-02T13:25:13Z'
  history:
  - event: reconciled_dead
EOF

DEAD_THEN_LIVE="$TMP/reg-dead-then-live.yaml"
cat > "$DEAD_THEN_LIVE" <<'EOF'
meta:
  schema_version: 2
sessions:
- task_id: PULSE-DEAD-FIRST
  session_id: deadarm-first
  worktree: /tmp/nope-first
  dead_at: '2026-09-02T13:25:13Z'
  history:
  - event: reconciled_dead
- task_id: PULSE-LIVE-SECOND
  session_id: liveweight
  worktree: /tmp/live
  pid: 424242
EOF

DEREG_ONLY="$TMP/reg-dereg-only.yaml"
cat > "$DEREG_ONLY" <<'EOF'
meta:
  schema_version: 2
sessions:
- task_id: PULSE-DEREG-ROW
  session_id: gone-arm
  worktree: /tmp/nope-dereg
  history:
  - event: deregistered
- task_id: PULSE-LIVE-AFTER-DEREG
  session_id: liveweight2
  worktree: /tmp/live2
  pid: 424243
EOF

# ── case 1: dead-only registry → no task id (lands in _unknown) ────────────
P1="$TMP/proj1"; LEADV2_STATE_ROOT="$TMP/state" setup_proj "$P1" "$DEAD_ONLY"
R1="$(fire "$P1")"
if [[ "$R1" == "_unknown" ]]; then
  ok "1: dead-only registry → tid=_unknown (got '$R1')"
else
  bad "1: dead-only registry → want _unknown, got '$R1'"
fi
[[ -e "$P1/docs/handoff/PULSE-DEAD-ROW-A" || -e "$P1/docs/handoff/PULSE-DEAD-ROW-B" ]] \
  && bad "1: pulse materialised in a DEAD lane dir" \
  || ok "1: no dead lane dir created"

# ── case 2: dead row then live row → live chosen ───────────────────────────
P2="$TMP/proj2"; LEADV2_STATE_ROOT="$TMP/state" setup_proj "$P2" "$DEAD_THEN_LIVE"
R2="$(fire "$P2")"
if [[ "$R2" == "PULSE-LIVE-SECOND" ]]; then
  ok "2: dead-first registry → live row chosen (got '$R2')"
else
  bad "2: dead-first registry → want PULSE-LIVE-SECOND, got '$R2'"
fi

# ── case 3: deregistered event alone (no dead_at) also skipped ─────────────
P3="$TMP/proj3"; LEADV2_STATE_ROOT="$TMP/state" setup_proj "$P3" "$DEREG_ONLY"
R3="$(fire "$P3")"
if [[ "$R3" == "PULSE-LIVE-AFTER-DEREG" ]]; then
  ok "3: deregistered-event row skipped (got '$R3')"
else
  bad "3: deregistered-event row → want PULSE-LIVE-AFTER-DEREG, got '$R3'"
fi

# ── case 4: no registry at all → _unknown (kept contract) ──────────────────
P4="$TMP/proj4"; LEADV2_STATE_ROOT="$TMP/state" setup_proj "$P4" ""
R4="$(fire "$P4")"
if [[ "$R4" == "_unknown" ]]; then
  ok "4: missing registry → tid=_unknown (got '$R4')"
else
  bad "4: missing registry → want _unknown, got '$R4'"
fi

# ── case 5: NEGATIVE CONTROL — mutant (dead-skip removed) goes red on 1 ────
MUTANT="$TMP/leadv2-pulse-json.mutant.sh"
sed 's/ && !dead//g' "$HOOK" > "$MUTANT" || bad "5: could not build mutant"
if ! grep -q 'pending != "" )' "$MUTANT" && grep -q 'pending != ""' "$MUTANT"; then
  : # mutation landed inside the resolver block
fi
if bash -n "$MUTANT"; then
  LEADV2_STATE_ROOT="$TMP/state"
  PM="$TMP/projM"; mkdir -p "$PM/docs/handoff"
  rm -f "$PM/docs/leadv2/active.yaml"; rm -rf "${LEADV2_STATE_ROOT:?}"
  mkdir -p "$LEADV2_STATE_ROOT"; cp "$DEAD_ONLY" "$LEADV2_STATE_ROOT/active.yaml"
  RM="$( ( cd "$PM" && \
    CLAUDE_PROJECT_DIR="$PM" LEADV2_STATE_ROOT="$TMP/state" \
    LEADV2_TASK_ID= LEADV2_PULSE_TASK_ID= LEADV2_PHASE= \
    bash "$MUTANT" <<< '{"tool_name":"Bash","session_id":"sess-pj-01"}' >/dev/null 2>&1 ) ; \
    find "$PM/docs/handoff" -name pulse.json -maxdepth 2 | head -1 )"
  case "$RM" in
    *PULSE-DEAD-ROW-*) ok "5: mutant picked the dead row (red as required: $RM)" ;;
    *) bad "5: mutant did NOT reproduce the bug (pulse at '${RM:-none}') — suite is blind" ;;
  esac
else
  bad "5: mutant fails bash -n — sed broke the hook"
fi

echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
