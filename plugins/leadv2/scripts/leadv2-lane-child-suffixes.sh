#!/usr/bin/env bash
# Single source of truth for lane sub-agent role suffixes that register their
# OWN docs/handoff/dispatch-<sig8>-<role>/ directory but are never their own
# lane or cap slot -- they are a prepass running INSIDE the parent
# dispatch-<sig8> lane (today: the architect prepass spawned by
# leadv2-dispatch-code.sh's architect_prepass()).
#
# Contract: any launcher that registers a sub-agent lane dir under
# dispatch-<sig8>-<role>/ MUST add <role> to this comma-separated list.
# leadv2-lane-liveness.sh reads it to fold those ids into their parent so
# they never render or count as a separate lane (STATUSLINE-COUNT-TRUTH-01).
# Drift is structurally impossible only because the registrar
# (leadv2-dispatch-code.sh) also builds its dir name from this same value --
# never edit one side without the other.
export LEADV2_LANE_CHILD_SUFFIXES="${LEADV2_LANE_CHILD_SUFFIXES:-architect}"
