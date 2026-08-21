#!/usr/bin/env bash
# tests/test-pulse-liveness-job-registry.sh — SD-PULSE-LIVENESS-BY-JOB-REGISTRY-01
# / PULSE-READABLE-01 cause fix (b).
#
# Incident: the 2026-08-21T08:09:49Z founder beat reported dispatch-21f644a1
# as `dead:silent_200431s_abandoned` in "Закрыто сегодня" while its codex job
# had been `status=running` since 08:05:43Z — the 200431s silence age came
# from a *.stream.jsonl last written by a PREVIOUS attempt two days earlier,
# not the live one. leadv2-lane-liveness.sh's v2_mode ladder let a stale
# stream mtime declare a lane dead:silent_*_abandoned even when the CURRENT
# attempt's job registry (codex-task.sh status --all, keyed by this lane's
# own codex-plan.json job_id) said the job was still queued/running.
#
# T1 (RED before the fix, GREEN after): stream mtime older than
# LEADV2_LANE_ABANDON_MAX_S + provider status "running" -> verdict must NOT
# start with "dead:" (never abandoned while the registry says running).
# T2: same shape with provider status "queued" -> same non-dead guarantee.
# T3 negative control: same stale stream, but codex-task.sh reports the job
# "completed" (dead in reality) -> verdict MUST be dead:* — this proves the
# fix does not just blanket-suppress every abandon-max dead verdict.
#
# Hermetic: runs against a throwaway COPY of scripts/ (never the real
# checkout — see TEST-DESTROYS-PRODUCTION-SCRIPT-01 containment pattern in
# test-lane-liveness-authoritative.sh), with an md5 tripwire on the real
# leadv2-lane-liveness.sh confirming this run never mutated it.
# Run: bash scripts/tests/test-pulse-liveness-job-registry.sh
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
tmp="$(lv2_mktemp_dir pulse-liveness-job-registry)"; trap 'rm -rf "$tmp"' EXIT

PLUGIN_DIR="$tmp/plugin"
mkdir -p "$PLUGIN_DIR"
cp -a "${REAL_PLUGIN_DIR}/scripts" "$PLUGIN_DIR/"
case "$PLUGIN_DIR" in
  "$tmp"/*) ;;
  *) printf '[TEST-SAFETY] ABORT: PLUGIN_DIR %s did not resolve under the scratch root %s\n' "$PLUGIN_DIR" "$tmp" >&2; exit 90 ;;
esac
case "$PLUGIN_DIR" in
  "$REAL_PLUGIN_DIR"|"$REAL_PLUGIN_DIR"/*)
    printf '[TEST-SAFETY] ABORT: PLUGIN_DIR %s resolves inside the real plugin tree %s -- refusing to run\n' "$PLUGIN_DIR" "$REAL_PLUGIN_DIR" >&2
    exit 90
    ;;
esac
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"

_lv2_md5() { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}'; }
REAL_HELPER="${REAL_PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
REAL_HELPER_MD5_BEFORE="$(_lv2_md5 "$REAL_HELPER")"
lv2_tripwire() {
  local after
  after="$(_lv2_md5 "$REAL_HELPER")"
  if [[ "$after" != "$REAL_HELPER_MD5_BEFORE" ]]; then
    printf '[TEST-SAFETY] FATAL: test mutated a production path %s\n  before=%s\n  after=%s\n' \
      "$REAL_HELPER" "$REAL_HELPER_MD5_BEFORE" "$after" >&2
    exit 91
  fi
  printf '[TEST-SAFETY] tripwire OK: %s unchanged (md5 %s before and after)\n' "$REAL_HELPER" "$after"
}
trap 'lv2_tripwire; rm -rf "$tmp"' EXIT

HELPER="${PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
repo="$tmp/repo"; state="$tmp/state"; mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff" "$tmp/bin" "$state"
(cd "$repo" && git init -q)
lv2_assert_scratch_repo "$repo"
printf 'sessions: []\n' > "$repo/docs/leadv2/active.yaml"

pass=0; fail_ct=0
check() {  # <output> <expect-regex> <label>
  if grep -q "$2" <<<"$1"; then
    printf '[TEST] PASS: %s\n' "$3"; pass=$((pass+1))
  else
    printf '[TEST] FAIL: %s\n%s\n' "$3" "$1"; fail_ct=$((fail_ct+1))
  fi
}
refute() {  # <output> <forbidden-regex> <label>
  if grep -q "$2" <<<"$1"; then
    printf '[TEST] FAIL: %s (forbidden pattern present)\n%s\n' "$3" "$1"; fail_ct=$((fail_ct+1))
  else
    printf '[TEST] PASS: %s\n' "$3"; pass=$((pass+1))
  fi
}

# One lane, one stale stream (older than abandon_max), one codex-plan.json
# binding it to job "job-21f644a1" -- shape matches the real incident.
mkdir -p "$repo/docs/handoff/dispatch-21f644a1"
printf '{"v":1}\n' > "$repo/docs/handoff/dispatch-21f644a1/developer.stream.jsonl"
python3 - "$repo/docs/handoff/dispatch-21f644a1/developer.stream.jsonl" <<'PY'
import os, sys, time
os.utime(sys.argv[1], (time.time() - 200431, time.time() - 200431))  # incident's own age
PY
printf '{"job_id":"job-21f644a1"}\n' > "$repo/docs/handoff/dispatch-21f644a1/codex-plan.json"

cat > "$tmp/bin/codex-task-running.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"workspaceRoot":"x","running":[{"id":"job-21f644a1","status":"running","phase":"executing","createdAt":"2026-08-21T08:05:43Z"}],"recent":[]}'
SH
chmod +x "$tmp/bin/codex-task-running.sh"

cat > "$tmp/bin/codex-task-queued.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"workspaceRoot":"x","running":[],"recent":[]}'
SH
# queued jobs surface via provider_jobs() same as running -- reuse "running"
# array with status queued for T2.
cat > "$tmp/bin/codex-task-queued.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"workspaceRoot":"x","running":[{"id":"job-21f644a1","status":"queued","phase":"queued","createdAt":"2026-08-21T08:05:43Z"}],"recent":[]}'
SH
chmod +x "$tmp/bin/codex-task-queued.sh"

cat > "$tmp/bin/codex-task-completed.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"workspaceRoot":"x","running":[],"recent":[{"id":"job-21f644a1","status":"completed","phase":"completed","createdAt":"2026-08-21T08:05:43Z"}]}'
SH
chmod +x "$tmp/bin/codex-task-completed.sh"

ABANDON=3600  # default; the stream is 200431s old, well past it

# ── T1: registry says running -> never dead ─────────────────────────────
running_out="$(LEADV2_LANE_ABANDON_MAX_S="$ABANDON" LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
  CODEX_TASK_SH="$tmp/bin/codex-task-running.sh" bash "$HELPER" --project-root "$repo" --lane dispatch-21f644a1 --json)"
refute "$running_out" '"verdict":"dead:' 'T1: stale stream + provider running -> verdict is never dead:*'
check "$running_out" '"verdict":"silent:' 'T1: stale stream + provider running -> verdict is silent: (visible, not abandoned)'
check "$running_out" 'abandoned_but_provider_running' 'T1: reason names the override explicitly'

# ── T2: registry says queued -> same guarantee ──────────────────────────
queued_out="$(LEADV2_LANE_ABANDON_MAX_S="$ABANDON" LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
  CODEX_TASK_SH="$tmp/bin/codex-task-queued.sh" bash "$HELPER" --project-root "$repo" --lane dispatch-21f644a1 --json)"
refute "$queued_out" '"verdict":"dead:' 'T2: stale stream + provider queued -> verdict is never dead:*'

# ── T3 negative control: registry says completed -> MUST still be dead ──
# proves the fix targets ONLY queued/running, not every abandon-max dead
# verdict (a test that cannot fail is worse than no test).
completed_out="$(LEADV2_LANE_ABANDON_MAX_S="$ABANDON" LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
  CODEX_TASK_SH="$tmp/bin/codex-task-completed.sh" bash "$HELPER" --project-root "$repo" --lane dispatch-21f644a1 --json)"
check "$completed_out" '"verdict":"dead:' 'T3 (negative control): stale stream + provider completed -> still dead:* (fix is not a blanket suppression)'

printf '\n[TEST] === %s passed, %s failed ===\n' "$pass" "$fail_ct"
[[ "$fail_ct" -eq 0 ]]
