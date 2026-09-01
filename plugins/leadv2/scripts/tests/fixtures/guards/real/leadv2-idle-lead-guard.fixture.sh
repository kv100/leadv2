#!/usr/bin/env bash
# Real-guard fixture: leadv2-idle-lead-guard.sh (Stop), the guard that sat
# out a whole night of queued work because lane-liveness hung and it failed
# open silently (the GUARDS-MUST-PROVE-THEY-FIRE-01 motivation).
#
# Probe artifact 2026-09-01: with a queued task + stub lane-liveness answering
# {"availability":"authoritative","count_live":0} + an empty questions dir,
# the guard prints {"decision":"block",...} — its fire path IS reachable when
# its probes answer. STATE_DIR/HOME stay in the sandbox; the stub liveness
# replaces the real leadv2-lane-liveness.sh via LEADV2_IDLE_GUARD_LIVENESS_SH.
# GV_FIX_CWD points at a sandbox "project" so the guard's docs/leadv2 root
# check passes without touching the real repo.
GV_FIX_GUARD="leadv2-idle-lead-guard.sh"
GV_FIX_PRE='mkdir -p "$LEADV2_SANDBOX/proj/docs/leadv2" "$LEADV2_SANDBOX/qdir" "$LEADV2_SANDBOX/state"
# The guard silently exits 0 unless $PROJECT_ROOT/docs/tasks.yaml exists,
# even when LEADV2_IDLE_GUARD_TASKS_FILE points elsewhere (probe 2026-09-01).
printf "%s\n" "[]" > "$LEADV2_SANDBOX/proj/docs/tasks.yaml"
printf "%s" "IyEvdXNyL2Jpbi9lbnYgYmFzaApwcmludGYgJ3siYXZhaWxhYmlsaXR5IjoiYXV0aG9yaXRhdGl2ZSIsImNvdW50X2xpdmUiOjB9XG4nCg==" | base64 -D > "$LEADV2_SANDBOX/liveness-stub.sh"
chmod +x "$LEADV2_SANDBOX/liveness-stub.sh"
printf "%s\n" "- id: FX-1" "  status: queued" "  lane: fx" "  title: fixture queued row" > "$LEADV2_SANDBOX/tasks.yaml"'
GV_FIX_STDIN='{"session_id":"fx-idle","stop_hook_active":false,"cwd":"$LEADV2_SANDBOX/proj"}'
GV_FIX_CWD='$LEADV2_SANDBOX/proj'
GV_FIX_ENV="LEADV2_IDLE_GUARD_TASKS_FILE=\$LEADV2_SANDBOX/tasks.yaml LEADV2_IDLE_GUARD_QUESTIONS_DIR=\$LEADV2_SANDBOX/qdir LEADV2_IDLE_GUARD_LIVENESS_SH=\$LEADV2_SANDBOX/liveness-stub.sh LEADV2_IDLE_GUARD_STATE_DIR=\$LEADV2_SANDBOX/state LEADV2_IDLE_GUARD_GOAL_FILE=\$LEADV2_SANDBOX/no-goal.yaml"
GV_FIX_EXPECT="block"
