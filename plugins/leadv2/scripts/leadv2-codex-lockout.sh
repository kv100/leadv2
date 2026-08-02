#!/usr/bin/env bash
# leadv2-codex-lockout.sh — compatibility front-end for bounded codex cooldown.
#
# Reads the SAME lockout memory codex-task.sh's launch gate (_codex_quota_gate,
# codex-task.sh:98,271-286) consults before spawning, and prints the same
# verdict in a form leadv2-limits-refresh.sh can render. This file duplicates
# the gate's parse/compare logic rather than sourcing codex-task.sh (off
# limits this lane) — the duplication is bonded by
# tests/test-codex-lockout-agreement.sh, which drives both this helper and
# the real codex-task.sh gate against the same fixtures and asserts they
# never disagree.
#
# Usage: leadv2-codex-lockout.sh
# Stdout (always exactly one line, exit always 0 — fail-open, matches the
# gate's own fail-open contract):
#   locked <until-iso>   -- a future-dated lockout is in force
#   clear                -- no file, no matching line, or the lockout expired
#
# Env:
#   LEADV2_STATUS_CODEX_LOCKOUT  override path to codex-lockout.state
#                                 (default ~/.claude/cache/codex-lockout.state;
#                                 same knob codex-task.sh's own file uses --
#                                 resurrected here, see leadv2-limits-refresh.sh
#                                 header for the "unused" note this replaces)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/leadv2-arm-cooldown.sh
source "${SCRIPT_DIR}/lib/leadv2-arm-cooldown.sh"

state="$(arm_cooldown_state codex)"
case "$state" in
  # arm_cooldown_state prints "cooling <reprobe_iso> <reason>"; only the
  # reprobe time belongs on this line. The awk that used to stand here piped
  # printf's OUTPUT rather than its argument, so `{print $1}` kept the literal
  # word "locked" and dropped the timestamp entirely -- the surface said locked
  # but could never say until when, which is the one thing the founder needs to
  # read off it. Take the first field of the stripped state instead.
  cooling\ *) _rest="${state#cooling }"; printf 'locked %s\n' "${_rest%% *}" ;;
  *) printf 'clear\n' ;;
esac
exit 0
