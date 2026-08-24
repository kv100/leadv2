#!/usr/bin/env bash
# Isolated structural/unit coverage for PREPASS-PROVIDER-FALLBACK-01-R8.
# This file never sources or executes the dispatcher, registry, or a launcher.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH_SH="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }
need() { grep -Fq -- "$2" "$DISPATCH_SH" && ok "$1" || bad "$1"; }
[[ -f "$DISPATCH_SH" ]] || { printf '[TEST] missing dispatcher\n' >&2; exit 1; }

# Structural checks only: no dispatcher, registry, model launcher, or git command runs.
need 'fallback creates disposable workspace' 'ws_base="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-afb.XXXXXX")"'
need 'fallback creates detached workspace' 'git -C "${PROJECT_ROOT}" worktree add --detach "${ws}" HEAD'
need 'codex receives isolated cwd' '--cwd "${ws}"'
need 'glm receives isolated cwd' 'bash "${GLM_BIN}" run "@${mfile}" --out "${glm_out}" --cwd "${ws}"'
need 'all normal fallback paths dispose workspace' '_afb_discard_workspace "${ws_base}"'
need 'workspace failure aborts without shared cwd' 'outcome=aborted reason=workspace_unavailable'
need 'cleanup trap owns no-spawn release' '_release_registered_lane "${DISPATCH_SLOT_REG_ID}" "${DISPATCH_SLOT_SIG8:-}" "exit_trap"'
need 'register captures ownership session' 'DISPATCH_SLOT_SESSION="$(LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" leadv2_active_register'
need 'owner check protects worker rows' 'if row.get("pid_role") == "worker":'
need 'owner check protects foreign session' 'row.get("session_id") != session'
need 'owner check protects foreign pid' 'str(row.get("pid")) != pid'
need 'worker handoff disarms cleanup' 'DISPATCH_SLOT_REG_ID=""'

# Fixture-backed provider/output classification.  These fixtures exercise only
# decision logic; no external system is consulted.
classify_fixture() {
  local text="$1" rc="$2"
  if [[ "$text" == *authentication_failed* || "$text" == *'OAuth session expired'* || "$text" == *'HTTP 401'* ]]; then printf 'authentication_failed\n'
  elif [[ "$text" == *'rate limit'* || "$text" == *'HTTP 429'* || "$text" == *'too many requests'* ]]; then printf 'rate_limited\n'
  elif [[ "$text" == *'usage limit'* || "$text" == *'quota exceeded'* ]]; then printf 'quota_exceeded\n'
  else printf 'failed_rc_%s\n' "$rc"; fi
}
accept_codex_fixture() { [[ "$1" == 0 && -n "$2" ]]; }
accept_glm_fixture() { [[ "$1" == 0 && -n "$2" ]]; }
release_fixture() { [[ "$1" == armed && "$2" == ours ]] && printf released || printf kept; }
[[ "$(classify_fixture 'authentication_failed; HTTP 429' 1)" == authentication_failed ]] && ok 'fixture auth precedence' || bad 'fixture auth precedence'
[[ "$(classify_fixture 'HTTP 429 too many requests' 1)" == rate_limited ]] && ok 'fixture rate classification' || bad 'fixture rate classification'
[[ "$(classify_fixture 'usage limit reached' 1)" == quota_exceeded ]] && ok 'fixture quota classification' || bad 'fixture quota classification'
[[ "$(classify_fixture 'opaque failure' 7)" == failed_rc_7 ]] && ok 'fixture opaque classification' || bad 'fixture opaque classification'
accept_codex_fixture 0 design && ok 'fixture codex stdout accepted' || bad 'fixture codex acceptance'
! accept_codex_fixture 0 '' && ok 'fixture codex empty stdout rejected' || bad 'fixture codex empty output'
accept_glm_fixture 0 design-file && ok 'fixture glm output accepted' || bad 'fixture glm acceptance'
! accept_glm_fixture 1 design-file && ok 'fixture glm nonzero rejected' || bad 'fixture glm rc'
[[ "$(release_fixture armed ours)" == released ]] && ok 'fixture armed cleanup releases owner' || bad 'fixture armed cleanup'
[[ "$(release_fixture disarmed ours)" == kept ]] && ok 'fixture disarmed cleanup keeps row' || bad 'fixture disarmed cleanup'
[[ "$(release_fixture armed foreign)" == kept ]] && ok 'fixture owner-safe cleanup keeps foreign row' || bad 'fixture owner safety'
printf '\n[SUITE] %s: %d passed, %d failed\n' "$([[ $FAIL -eq 0 ]] && printf PASS || printf FAIL)" "$PASS" "$FAIL"
exit "$([[ $FAIL -eq 0 ]] && printf 0 || printf 1)"
