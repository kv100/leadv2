#!/usr/bin/env bash
# lib/leadv2-codex-quota-gate.sh — shared spawn gate for codex.
#
# Provides codex_spawn_gate: a pre-launch check that consults (1) the bounded
# cooldown memory and (2) the circuit breaker before allowing a codex spawn.
# On refusal, prints the LEADV2_DISPATCH_REFUSED marker to stderr and returns 2
# (the existing router contract — callers map rc 2 → next candidate).
#
# CODEX-REFUSAL-MARKER-CARRIES-ITS-CAUSE-01: the marker carries its cause so
# the dispatcher never ledgers a non-quota refusal as a quota lockout:
#   quota_gate          — a genuine usage-limit refusal (live threshold over
#                         ceiling, or a cooldown whose recorded reason is
#                         quota-shaped: the provider itself refused)
#   transport_cooldown  — a cooldown whose recorded reason is a dead runtime
#                         (worker_died / queued_stall / transport_gone…): our
#                         side broke, the provider's quota did not
#   quota_circuit_open  — the circuit breaker is open (usage-limit origin,
#                         with its own until; the lockout must inherit it)
#   circuit_unknown     — circuit marker present but unparseable (control
#                         plane unreachable ⇒ fail-closed, no expiry known)
#   gate_broken         — the gate's own dependency is missing/non-executable
# All tokens match the router's single-word extraction grammar
# ([A-Za-z0-9._-]+), and `quota_gate` keeps its meaning for every existing
# reader that greps it.
#
# Sourced by:
#   - leadv2-codex-session-runner.sh (before every `codex exec`)
#   - codex-task.sh (transitively — the circuit lib is sourced separately and
#     the circuit check is integrated into _codex_quota_gate additively).
#
# The generic threshold check here is shared by both spawn paths.  codex-task's
# legacy yaml check remains stricter where configured.

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
  local _sub="${1:-exec}" _purpose _gate_rc
  shift || true

  [[ "${CODEX_SKIP_QUOTA_GATE:-0}" == "1" ]] && return 0

  # check 1 — bounded cooldown memory. Once reprobe_at passes, the next
  # dispatch launches and provider evidence is authoritative again.
  local _cooldown _cooldown_until _cooldown_reason _refusal_cause
  _cooldown="$(arm_cooldown_state codex 2>/dev/null || true)"
  case "$_cooldown" in
    cooling\ *)
      _cooldown_until="${_cooldown#cooling }"; _cooldown_until="${_cooldown_until%% *}"
      # The cooling verdict's 3rd field is the RECORDED reason (frozen grammar:
      # `cooling <reprobe_iso> <reason>`). It says who broke: the provider
      # (quota*) or our runtime (everything else).
      _cooldown_reason="${_cooldown##* }"
      case "$_cooldown_reason" in
        quota*) _refusal_cause="quota_gate" ;;
        *)      _refusal_cause="transport_cooldown" ;;
      esac
      printf '[codex-task] CODEX_REFUSED_QUOTA reason=cooldown used=na threshold=na until=%s\n' "$_cooldown_until" >&2
      printf 'LEADV2_DISPATCH_REFUSED: %s\n' "$_refusal_cause" >&2
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
      # Quota-origin (opened by a usage-limit refusal) but the circuit breaker
      # owns the expiry — the lockout side must inherit `until`, never re-default.
      printf 'LEADV2_DISPATCH_REFUSED: quota_circuit_open\n' >&2
      return 2
      ;;
    unknown)
      printf '[codex-task] CODEX_REFUSED_QUOTA reason=circuit-unknown (control-plane unreachable) used=na threshold=na until=na\n' >&2
      # No expiry is knowable here — inventing one (a default-duration quota
      # lockout) is exactly the defect this marker vocabulary exists to stop.
      printf 'LEADV2_DISPATCH_REFUSED: circuit_unknown\n' >&2
      return 2
      ;;
  esac

  case "$_sub" in review|adversarial-review|review-bg) _purpose=review ;; *) _purpose=build ;; esac
  # check 3 — the generic gate runs as a CHILD PROCESS, not a sourced function,
  # so it inherits the environment. Hermetic contract (QUOTA-GATE-PARITY-01 F2):
  # LEADV2_QUOTA_LIVE (fixture emitter), LEADV2_QUOTA_CACHE_DIR (scratch dir)
  # and LEADV2_QUOTA_CEILINGS (fixture ceilings file) are all read by the child
  # from the inherited env -- exporting them makes this check hermetic with no
  # dedicated bypass flag. Tests MUST set them; unset, check 3 reads the host's
  # real ~/.claude/state/leadv2/quota-cache/ and flakes on host quota state.
  # NOTE: the child is exec'd DIRECTLY (not `bash $gate`), so its executable
  # bit is load-bearing — mode 644 gives rc 126, which the caller below treats
  # as pass, silently disabling this check (tests/a4c guards it).
  local _provider_gate="$(cd "${_CODEX_QG_DIR}/.." && pwd)/leadv2-provider-quota-gate.sh"
  if [[ ! -x "$_provider_gate" ]]; then
    printf '[codex-task] CODEX_REFUSED_QUOTA reason=gate_broken dependency=%s\n' "$_provider_gate" >&2
    printf 'LEADV2_DISPATCH_REFUSED: gate_broken\n' >&2
    return 2
  fi
  "$_provider_gate" codex "$_purpose"
  _gate_rc=$?
  if [[ "$_gate_rc" -eq 1 ]]; then
    printf '[codex-task] CODEX_REFUSED_QUOTA reason=threshold used=live threshold=ceiling until=na\n' >&2
    # The ONE unambiguous quota refusal: the live ceiling check said no.
    printf 'LEADV2_DISPATCH_REFUSED: quota_gate\n' >&2
    return 2
  fi
  if [[ "$_gate_rc" -ne 0 && "$_gate_rc" -ne 1 ]]; then
    printf '[codex-task] CODEX_REFUSED_QUOTA reason=gate_broken dependency=%s rc=%s\n' "$_provider_gate" "$_gate_rc" >&2
    printf 'LEADV2_DISPATCH_REFUSED: gate_broken\n' >&2
    return 2
  fi

  return 0
}
