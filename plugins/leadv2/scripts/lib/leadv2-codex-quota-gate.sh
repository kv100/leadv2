#!/usr/bin/env bash
# lib/leadv2-codex-quota-gate.sh — shared spawn gate for codex.
#
# Provides codex_spawn_gate: a pre-launch check that consults (1) the bounded
# cooldown memory and (2) the circuit breaker before allowing a codex spawn.
# On refusal, prints the LEADV2_DISPATCH_REFUSED marker to stderr and returns 2
# (the existing router contract — callers map rc 2 → next candidate).
#
# Sourced by:
#   - leadv2-codex-session-runner.sh (before every `codex exec`)
#   - codex-task.sh (transitively — the circuit lib is sourced separately and
#     the circuit check is integrated into _codex_quota_gate additively).
#
# The threshold check (routing-yaml + live quota reader) is NOT in this lib;
# it lives in codex-task.sh's _codex_quota_gate where the reader functions are
# defined. This gate covers the two checks that must run on EVERY spawn path,
# including the session-runner which bypasses codex-task.sh entirely.

# Source dependencies (idempotent — safe to re-source).
_CODEX_QG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v arm_cooldown_state >/dev/null 2>&1 \
  || source "$_CODEX_QG_DIR/leadv2-arm-cooldown.sh" 2>/dev/null || true
command -v codex_circuit_state >/dev/null 2>&1 \
  || source "$_CODEX_QG_DIR/leadv2-codex-circuit.sh" 2>/dev/null || true

# codex_spawn_gate <sub> [launch args…]
#   Returns 0 (pass) or 2 (refuse). Prints refusal markers to stderr.
#   Honors CODEX_SKIP_QUOTA_GATE=1 (skips all checks).
codex_spawn_gate() {
  shift || true

  [[ "${CODEX_SKIP_QUOTA_GATE:-0}" == "1" ]] && return 0

  # check 1 — bounded cooldown memory. Once reprobe_at passes, the next
  # dispatch launches and provider evidence is authoritative again.
  local _cooldown _cooldown_until
  _cooldown="$(arm_cooldown_state codex 2>/dev/null || true)"
  case "$_cooldown" in
    cooling\ *)
      _cooldown_until="${_cooldown#cooling }"; _cooldown_until="${_cooldown_until%% *}"
      printf '[codex-task] CODEX_REFUSED_QUOTA reason=cooldown used=na threshold=na until=%s\n' "$_cooldown_until" >&2
      printf 'LEADV2_DISPATCH_REFUSED: quota_gate\n' >&2
      return 2
      ;;
  esac

  # check 2 — circuit breaker (fail-closed on corruption, fail-open on
  # infra-gap). A usage-limit refusal opens a circuit that stays open until
  # the retry-at timestamp (days for a weekly limit). "unknown" (marker file
  # exists but unparseable) ⇒ refuse. "closed" (no file, or path unresolvable)
  # ⇒ proceed.
  local _circuit
  _circuit="$(codex_circuit_state 2>/dev/null || printf 'unknown')"
  case "$_circuit" in
    open\ *)
      local _c_until="${_circuit#open }"; _c_until="${_c_until%% *}"
      printf '[codex-task] CODEX_REFUSED_QUOTA reason=circuit used=na threshold=na until=%s\n' "$_c_until" >&2
      printf 'LEADV2_DISPATCH_REFUSED: quota_gate\n' >&2
      return 2
      ;;
    unknown)
      printf '[codex-task] CODEX_REFUSED_QUOTA reason=circuit-unknown (control-plane unreachable) used=na threshold=na until=na\n' >&2
      printf 'LEADV2_DISPATCH_REFUSED: quota_gate\n' >&2
      return 2
      ;;
  esac

  return 0
}
