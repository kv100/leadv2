#!/usr/bin/env bash
# leadv2-lanes-snapshot.sh — one call = one snapshot of all child /leadv2 sessions.
#
# Task LEAD-SUPERVISE-01. See docs/handoff/LEAD-ANCHOR-01/mission-supervise.md.
#
# Reads (no network, files only):
#   docs/leadv2/active.yaml                         — live session registry
#     (schema per ~/.claude/leadv2-shared/scripts/leadv2-active-registry.sh:
#      session_id, task_id, worktree, branch, started_at, phase, class, pid,
#      pid_birth, last_pulse_at, stale, note)
#   docs/handoff/<task_id>/questions-async/*-pending.yaml (+ sibling
#     *-answered.yaml) — the EXISTING async question store (leadv2-helpers.sh
#     leadv2_ask_async / leadv2-reply.sh). Worktree-local — only visible when
#     this script's PROJECT_ROOT is that same worktree.
#   <control-plane>/questions/<qid>.yaml (leadv2-state-path.sh questions) —
#     the LEAD-ANCHOR-01 cross-worktree question store, written by
#     scripts/leadv2-ask.sh, answered by scripts/leadv2-answer.sh. TRUE
#     control-plane (outside any worktree) — this is what makes fanned-out
#     sessions (each in their own `git worktree add` checkout) visible to the
#     supervising lead. This script does not write to either store — read-only.
#   docs/handoff/<task_id>/phase8-passed.flag        — close signal
#
# Writes:
#   docs/leadv2/.supervise-last.json                 — snapshot state (for
#     --since delta mode and for "closed since last snapshot" detection)
#   active.yaml — D-d (SUPERVISE-V2-01 item 4) ONLY: adopts a triple-proof
#     tmux orphan row, and tombstones+prunes a row corroborated dead across
#     two consecutive calls. Both writes are additive/subtractive only —
#     never rewrites a live row, never restarts/kills a process. Gated
#     observe_only (env or automatic D-e 2-cycle rollout window) skips both.
#   <control-plane>/tombstones.yaml — one entry per pruned dead row, written
#     BEFORE the prune under a separate lock.
#
# Usage:
#   leadv2-lanes-snapshot.sh [--json] [--since <ISO>] [--print]
#
# SESSION-HANDOFF-01: a full (non-delta) --json call also carries a bounded
# "resume" key — a live-composed <supervisor-handoff> restore block (role +
# founder rules, live lanes, focus/next-action, freshest open-threads tail,
# tasks.yaml P0/P1 top-10). Computed by scripts/leadv2-lanes-resume.sh
# from the same canonical on-disk sources this script already reads/
# reconciles — no new state file. `--print` execs straight into that
# composer (skipping every mutation path below: sentinel write, tmux
# adopt/prune, phase-backfill, truth-probe) as a lightweight fallback entry
# point for the leadv2-supervise skill.
#
# Exit codes: 0 = reconciled snapshot rendered (table may legitimately be
# empty). Non-zero = fail-closed (B1, SUPERVISE-V2-01): unresolvable project
# root, missing/malformed active.yaml, or an unwritable snapshot path all
# exit non-zero with a typed JSON error ({"error": "root_error"|"registry_
# error"|"state_write_error", "message": ...} in --json mode, `[supervise]
# <kind>: <message>` on stderr otherwise). Only a registry that PARSED
# CLEANLY may report `table: []` — a missing/malformed registry is never
# silently treated as "no sessions".
#
# lean: minutes-in-phase uses last_pulse_at (freshness) falling back to
# started_at (session age) — active.yaml has no per-phase-entry timestamp.
# upgrade when leadv2-active-registry.sh adds phase_started_at.
#
# LANE-OBSERVABILITY-02 change 3: --all-repos (default ON via
# LEADV2_LANES_ALL_REPOS=1) extends a FULL --json call's table with the OTHER
# repos' lanes, read strictly READ-ONLY (foreign active.yaml from the
# control-plane state dir + pid/log-mtime liveness — never lane-liveness.sh's
# state-path resolution, which links/mkdirs into the foreign repo's control
# plane, and never this script's own adopt/tombstone/prune writes, which stay
# own-repo-only). Every foreign row carries `repo: <slug>`; a failed foreign
# read yields one {"repo":..,"error":"repo_read_error",..} row instead of
# zeroing the table (LANE-DETAIL-BLIND-01: a sub-read failure is loud).
# Single-repo safety: when the projects TSV yields no FOREIGN repo (one repo
# total, enumeration unavailable, or the flag off), output is byte-identical
# to today. --no-all-repos restores today unconditionally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${LEADV2_TRACE:-0}" == "1" ]]; then . "${SCRIPT_DIR}/lib/leadv2-trace.sh"
else lv2_trace_begin() { :; }; lv2_trace_end() { :; }; lv2_trace_arm_exit() { :; }; fi

# ── B1 fail-closed arg parse (BEFORE root resolution — a root error must
# know whether to render as JSON or plain stderr) ──────────────────────────
JSON_MODE=0
SINCE=""
PRINT_MODE=0
ALL_REPOS="${LEADV2_LANES_ALL_REPOS:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)  JSON_MODE=1; shift ;;
    --since) SINCE="${2:-}"; shift 2 ;;
    --print) PRINT_MODE=1; shift ;;
    --all-repos)    ALL_REPOS=1; shift ;;
    --no-all-repos) ALL_REPOS=0; shift ;;
    -h|--help)
      printf -- 'Usage: leadv2-lanes-snapshot.sh [--json] [--since <ISO>] [--print] [--all-repos|--no-all-repos]\n'
      exit 0
      ;;
    *)
      printf -- '[lanes-snapshot] unknown arg: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

# ── B1 fail-closed root resolution (SUPERVISE-V2-01 D-b/item-2) ────────────
# Order: LEADV2_PROJECT_ROOT -> CLAUDE_PROJECT_DIR -> `git -C "$PWD" rev-parse
# --show-toplevel`. NEVER a script-dir fallback (that let a wrong/empty root
# silently resolve to this script's OWN parent dir and report a false-clean
# empty registry) and NEVER a bare ambient `$PROJECT_ROOT`/`$(pwd)` fallback
# (an unrelated/garbage PROJECT_ROOT env var must not be trusted silently).
PROJECT_ROOT=""
lv2_trace_arm_exit "lanes.snapshot" || true
if [[ -n "${LEADV2_PROJECT_ROOT:-}" ]]; then
  PROJECT_ROOT="$LEADV2_PROJECT_ROOT"
elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  PROJECT_ROOT="$CLAUDE_PROJECT_DIR"
elif _lv2_git_top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"; then
  PROJECT_ROOT="$_lv2_git_top"
fi

if [[ -z "$PROJECT_ROOT" ]]; then
  _lv2_err_msg="root_error: could not resolve project root — set LEADV2_PROJECT_ROOT or CLAUDE_PROJECT_DIR, or run from inside a git worktree (cwd=${PWD})"
  if [[ "$JSON_MODE" -eq 1 ]]; then
    printf -- '{"error":"root_error","message":%s}\n' "$(printf '%s' "$_lv2_err_msg" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')"
  else
    printf -- '[supervise] %s\n' "$_lv2_err_msg" >&2
  fi
  exit 1
fi

# SESSION-HANDOFF-01: --print is a lightweight fallback entry point for the
# leadv2-supervise skill — composes the SAME bounded <supervisor-handoff>
# resume block as the "resume" key below, via the shared composer script,
# but skips every mutation/reconciliation path in this script (sentinel
# write, tmux adoption/prune, phase-backfill, truth-probe). Read-only,
# fast, safe to call whenever the mandatory --json call is unavailable.
if [[ "$PRINT_MODE" -eq 1 ]]; then
  RESUME_SH="${SCRIPT_DIR}/leadv2-lanes-resume.sh"
  if [[ -x "$RESUME_SH" || -f "$RESUME_SH" ]]; then
    if [[ "$JSON_MODE" -eq 1 ]]; then
      exec bash "$RESUME_SH" --json --project-root "$PROJECT_ROOT"
    else
      exec bash "$RESUME_SH" --project-root "$PROJECT_ROOT"
    fi
  fi
  printf -- '<supervisor-handoff>\nHANDOFF DEGRADED — resume composer script missing at %s\n</supervisor-handoff>\n' "$RESUME_SH"
  exit 0
fi

# LEAD-CONTROL-PLANE-01: active.yaml lives in the control plane (outside any
# worktree) — resolved via leadv2-state-path.sh, never hardcoded here.
ACTIVE_YAML="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" active.yaml)"
HANDOFF_DIR="${PROJECT_ROOT}/docs/handoff"
SNAPSHOT="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" .supervise-last.json)"

# LEAD-ANCHOR-01: true control-plane questions dir — shared across every
# worktree of this repo, unlike HANDOFF_DIR above.
CP_QUESTIONS_DIR="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" questions)"
# SUPERVISOR-RETRO-01 §5: consume the `closed` bus event published by
# scripts/leadv2-phase8-assert.sh after all seven hard assertions pass — a
# second, shared signal alongside the worktree-local phase8-passed.flag.
LEADV2_DIR_RESOLVED="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" 2>/dev/null || true)"
BUS_JSONL="${LEADV2_DIR_RESOLVED:+${LEADV2_DIR_RESOLVED}/bus.jsonl}"
BUS_OFFSET_FILE="${LEADV2_DIR_RESOLVED:+${LEADV2_DIR_RESOLVED}/.bus-offsets/supervise-closed-consumer}"

# ── D-d tmux reconciliation + honest death (SUPERVISE-V2-01 item 4) ────────
# Gathered on EVERY call (delta and full) — corroborated death requires two
# CONSECUTIVE 5s event polls to see the same evidence, not just the 300s
# pulse. Portable: real tmux binary, no GNU-only flags; "|||" delimiter
# (never a raw tab) avoids shell tab-escaping ambiguity in -F format strings.
# LEADV2_SUPERVISE_TMUX_SOCKET lets tests point at an isolated `tmux -L`
# server without ever touching a real "leadv2" session.
TMUX_SESSION_NAME="${LEADV2_FANOUT_TMUX_SESSION:-leadv2}"
TMUX_SOCKET_ARGS=()
if [[ -n "${LEADV2_SUPERVISE_TMUX_SOCKET:-}" ]]; then
  TMUX_SOCKET_ARGS=(-L "$LEADV2_SUPERVISE_TMUX_SOCKET")
fi
TMUX_WINDOWS_TSV=""
TMUX_PANES_TSV=""
if command -v tmux >/dev/null 2>&1 && tmux "${TMUX_SOCKET_ARGS[@]}" has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
  TMUX_WINDOWS_TSV="$(tmux "${TMUX_SOCKET_ARGS[@]}" list-windows -t "$TMUX_SESSION_NAME" -F '#{window_name}' 2>/dev/null || true)"
  TMUX_PANES_TSV="$(tmux "${TMUX_SOCKET_ARGS[@]}" list-panes -t "$TMUX_SESSION_NAME" -F '#{window_name}|||#{pane_pid}' 2>/dev/null || true)"
fi
TASKS_YAML_PATH="${PROJECT_ROOT}/docs/tasks.yaml"
TOMBSTONES_FILE="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" tombstones.yaml)"
ACTIVE_LOCKFILE="${ACTIVE_YAML}.lock"
# D-e: first 2 full-call reconciliation cycles after rollout are ALWAYS
# observe-only for legacy rows (enforced cycle-counted in the python core
# below via the persisted snapshot, not just this env flag). This env flag
# additionally lets a caller force observe-only at ANY time (verification.md
# canary command uses it).
OBSERVE_ONLY="${LEADV2_SUPERVISE_OBSERVE_ONLY:-0}"
# LEADV2_SUPERVISE_PRUNE_V2=0 is the one-flag rollback to the exact prior
# prune-evidence implementation (PID-only death authority, absent PID alone
# is death evidence). Default-on: =1 or unset consumes the authoritative
# lane-liveness verdict instead.
SUPERVISE_PRUNE_V2="${LEADV2_SUPERVISE_PRUNE_V2:-1}"
# A pending founder decision must not blend into routine supervision forever.
# This is deliberately a supervisor surface (not a second queue): after this
# age it emits one fresh URGENT event, even if its original delivery happened
# while the supervising lead was mid-turn.
QUESTION_ESCALATE_S="${LEADV2_QUESTION_ESCALATE_S:-300}"
[[ "$QUESTION_ESCALATE_S" =~ ^[0-9]+$ ]] || QUESTION_ESCALATE_S=300

# SUPERVISOR-RETRO-01 item 3: run the phase reconciliation backfill from the
# supervisor heartbeat (this script IS the repeated /leadv2 heartbeat poll —
# founder-facing Monitor loops call it on a cadence). The Write|Edit hook
# handles the common case live; this reconciles any task whose phase drifted
# (missed hook invocation, hook timeout, task registered before the hook
# existed). Best-effort and non-fatal — this script's contract is "exit 0
# always" (a read-only status probe) — but errors are surfaced on stderr,
# never swallowed to /dev/null, so a broken backfill is visible in logs.
PHASE_BACKFILL_SH="${PROJECT_ROOT}/.claude/scripts/leadv2-phase-backfill.sh"
if [[ -f "$PHASE_BACKFILL_SH" ]]; then
  if ! BACKFILL_OUT="$(LEADV2_PROJECT_ROOT="$PROJECT_ROOT" bash "$PHASE_BACKFILL_SH" 2>&1)"; then
    printf -- '[supervise] WARN: phase-backfill reconciliation failed:\n%s\n' "$BACKFILL_OUT" >&2
  fi
fi

# Informational only: retain valid JSON for --json consumers, while the human
# snapshot gets one best-effort provider-split line.
if [[ "$JSON_MODE" -eq 0 && -z "$SINCE" ]]; then
  ROLLUP_SH="${SCRIPT_DIR}/leadv2-provider-rollup.sh"
  if [[ -x "$ROLLUP_SH" ]]; then
    "$ROLLUP_SH" || printf -- 'provider-rollup: unavailable\n'
  fi
fi

# ── F2 truth-probe generic hook contract (SUPERVISE-V2-01 item 3) ──────────
# Runs ONLY on a full (non-delta, SINCE empty) snapshot call — the loop's own
# 300s pulse cadence is what makes those calls, so this naturally runs "once
# per 300s pulse" without a separate timer here. If
# <repo>/.claude/leadv2-overrides/supervise-truth-probe.sh exists+executable,
# invoke it with a 10s PORTABLE timeout (python3 subprocess.run(timeout=...),
# never the GNU-only `timeout` binary) and require JSON stdout shaped
# {"breaches": [{id, severity, summary, evidence_cmd}, ...]}. ANY failure —
# missing hook, non-zero exit, timeout, malformed JSON — degrades to
# status:"unavailable" with breaches:[] (fail-open-to-EMPTY). This must NEVER
# be read as "no breaches confirmed clear" (fail-open-to-clear) — callers
# (the retired loop's URGENT renderer, gone 2026-08-17 SUPERVISOR-DELETE-01)
# key off `status`,
# not just an empty breaches list. The persona-engine probe INSTANCE is
# written elsewhere (GLM-FIRST-01, out of this task's scope) — this is only
# the generic contract + cache writer.
TRUTH_BREACHES_JSON='{"status":"skipped","breaches":[]}'
if [[ -z "$SINCE" ]]; then
  TRUTH_PROBE_SH="${PROJECT_ROOT}/.claude/leadv2-overrides/supervise-truth-probe.sh"
  if [[ -x "$TRUTH_PROBE_SH" ]]; then
    TRUTH_BREACHES_JSON="$(python3 - "$TRUTH_PROBE_SH" <<'PYPROBE'
# SUPERVISE-V2-01 fix: the probe script backgrounds 3 check functions (ssh/
# curl/python3 children) via `&`. `subprocess.run(capture_output=True,
# timeout=N)` pipes stdout/stderr; on timeout it SIGKILLs only the DIRECT
# child, never the process group. Any grandchild still alive at that instant
# (a straggler ssh/curl under network load) keeps the inherited PIPE write-end
# open, so CPython's communicate() blocks draining that pipe well past the
# declared timeout -- reproduced hanging 20s+ past a timeout=10 in isolation.
# Fix: start the probe in its own session (setsid) so `&`-backgrounded
# descendants share its process group (bash job control is off by default in
# non-interactive scripts), capture stdout to a plain temp FILE (never
# blocks -- no pipe backpressure), and on timeout SIGKILL the whole group via
# os.killpg before giving up. Timeout raised 10->12 to sit safely above the
# probe's own 9s internal watchdog + cleanup instead of nearly tying it.
import subprocess, sys, json, os, signal, tempfile

probe_path = sys.argv[1]
try:
    with tempfile.TemporaryFile() as outf:
        proc = subprocess.Popen(
            [probe_path],
            stdout=outf,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            rc = proc.wait(timeout=12)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                pass
            print(json.dumps({"status": "unavailable", "breaches": [], "reason": "timeout"}))
            sys.exit(0)
        outf.seek(0)
        out = outf.read().decode("utf-8", errors="replace")
        if rc != 0:
            print(json.dumps({"status": "unavailable", "breaches": [], "reason": f"exit {rc}"}))
        else:
            try:
                d = json.loads(out)
                breaches = d.get("breaches") if isinstance(d, dict) else None
                if not isinstance(breaches, list):
                    breaches = []
                print(json.dumps({"status": "checked", "breaches": breaches}))
            except Exception as e:
                print(json.dumps({"status": "unavailable", "breaches": [], "reason": f"malformed_json:{e.__class__.__name__}"}))
except Exception as e:
    print(json.dumps({"status": "unavailable", "breaches": [], "reason": e.__class__.__name__}))
PYPROBE
)"
  else
    TRUTH_BREACHES_JSON='{"status":"no_probe_configured","breaches":[]}'
  fi
  # Best-effort ONLY (per header comment above: "informational only, never
  # read as fail-open-to-clear"). An unwritable state dir must NOT kill this
  # script here — the real B1 fail-closed contract belongs to the snapshot
  # write in the python core below, which already emits a typed
  # state_write_error. Regression (test-supervise-failclosed.sh Test 5):
  # this block used to die under `set -e` on a failed redirect/mv before the
  # typed-error path ever ran, producing rc=1 with EMPTY stdout instead of
  # {"error":"state_write_error",...}. Every write attempt below is now
  # guarded so a permission failure degrades silently and falls through to
  # the real fail-closed check.
  TRUTH_BREACHES_FILE="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" truth-breaches-last.json)"
  mkdir -p "$(dirname "$TRUTH_BREACHES_FILE")" 2>/dev/null || true
  _TB_TMP="${TRUTH_BREACHES_FILE}.tmp.$$"
  python3 -c '
import json, sys, datetime
d = json.loads(sys.argv[1])
d["observed_at"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
print(json.dumps(d))
' "$TRUTH_BREACHES_JSON" > "$_TB_TMP" 2>/dev/null || printf -- '%s' "$TRUTH_BREACHES_JSON" > "$_TB_TMP" 2>/dev/null || true
  if [[ -f "$_TB_TMP" ]]; then
    mv "$_TB_TMP" "$TRUTH_BREACHES_FILE" 2>/dev/null || rm -f "$_TB_TMP" 2>/dev/null || true
  fi
fi

# One snapshot resolves the active-registry and handoff-log key union in one
# subprocess.  Codex provider jobs remain included for backward compatibility.
LANE_LIVENESS_JSON="$(LEADV2_PROJECT_ROOT="$PROJECT_ROOT" bash "${SCRIPT_DIR}/leadv2-lane-liveness.sh" --project-root "$PROJECT_ROOT" --all --json 2>/dev/null || printf '%s' '{"lanes":[],"jobs":[],"availability":"unavailable"}')"

# ── LANE-OBSERVABILITY-02 change 3: foreign-repo lane gather ────────────────
# Runs only on a FULL --json call with the flag on. Foreign repos come from
# leadv2-status-projects.sh's TSV (slug \t state_dir \t repo_root); own repo is
# whatever root -ef PROJECT_ROOT. Each foreign repo is read PURE-READ: its
# active.yaml straight from the TSV state_dir (NO leadv2-state-path.sh call —
# the resolver mkdirs/symlinks into the foreign repo's control plane by
# design, which a status probe must never trigger) plus pid/log-mtime liveness
# computed in-process. A failed/timeout read appends one repo_read_error row;
# the loop below ALWAYS continues to the next repo. When no foreign repo
# yields a row, both temp files are dropped and the main snapshot runs
# UNMODIFIED (byte-identical single-repo output).
_LV2_FOREIGN_ROWS_FILE=""
_LV2_MAIN_JSON_TMP=""
if [[ "$ALL_REPOS" == "1" && "$JSON_MODE" == "1" && -z "$SINCE" ]]; then
  _LV2_PROJECTS_SH="${SCRIPT_DIR}/leadv2-status-projects.sh"
  if [[ -f "${_LV2_PROJECTS_SH}" ]]; then
    _LV2_OWN_PHYS="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P || true)"
    _LV2_FOREIGN_ROWS_FILE="$(mktemp "${TMPDIR:-/tmp}/lv2-foreign-rows.XXXXXX")"
    : > "${_LV2_FOREIGN_ROWS_FILE}"
    while IFS=$'\t' read -r _lv2_slug _lv2_state_dir _lv2_repo_root; do
      [[ -n "${_lv2_slug}" && -n "${_lv2_repo_root}" && -d "${_lv2_repo_root}" ]] || continue
      _lv2_rroot_phys="$(cd "${_lv2_repo_root}" 2>/dev/null && pwd -P || true)"
      [[ -n "${_lv2_rroot_phys}" && "${_lv2_rroot_phys}" == "${_LV2_OWN_PHYS}" ]] && continue
      LEADV2_FOREIGN_STATE_DIR="${_lv2_state_dir}" \
      python3 - "${_lv2_slug}" "${_lv2_repo_root}" "${_lv2_state_dir}" "${_LV2_FOREIGN_ROWS_FILE}" <<'PYF' 2>/dev/null || true
import datetime, glob, json, os, sys, time

slug, repo_root, state_dir, out_path = sys.argv[1:5]

def now_utc():
    return datetime.datetime.now(datetime.timezone.utc)

def parse_iso(s):
    if not s:
        return None
    try:
        dt = datetime.datetime.fromisoformat(str(s).rstrip("Z"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        return dt
    except Exception:
        return None

def emit(row):
    with open(out_path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(row) + "\n")

# hard per-repo timeout: a foreign repo read that wedges (NFS hang, huge
# registry) yields ONE error row after 15s, never a wedged beat.
# LEADV2_FOREIGN_SCAN_DEADLINE_S is a test knob for that error path (0 with
# at least one session row -> immediate deadline exceeded).
try:
    _deadline_s = max(0, int(os.environ.get("LEADV2_FOREIGN_SCAN_DEADLINE_S", "15")))
except ValueError:
    _deadline_s = 15
_DEADLINE = time.monotonic() + _deadline_s

try:
    active_yaml = os.path.join(state_dir, "active.yaml")
    session_by_task = {}
    try:
        import yaml
        with open(active_yaml, encoding="utf-8") as fh:
            doc = yaml.safe_load(fh) or {}
        for s in (doc.get("sessions") or []):
            if isinstance(s, dict) and s.get("task_id"):
                session_by_task[str(s["task_id"])] = s
    except Exception:
        pass  # no registry is an empty lane set, not a repo_read_error

    lane_fresh_s = 120
    try:
        lane_fresh_s = max(0, int(os.environ.get("LEADV2_LANE_FRESH_S", "120")))
    except ValueError:
        pass

    now = now_utc()
    for tid, s in sorted(session_by_task.items()):
        if time.monotonic() > _DEADLINE:
            emit({"repo": slug, "error": "repo_read_error", "data": "foreign scan deadline exceeded"})
            break
        pid = s.get("pid")
        pid_alive = False
        if isinstance(pid, int):
            try:
                os.kill(pid, 0)
                pid_alive = True
            except (ProcessLookupError, PermissionError):
                pid_alive = False
        # stream freshness: newest mtime under the lane's log_path / worktree
        # docs/leadv2 stream surfaces — pure stat, pure read.
        age_s = None
        stream_bytes = None
        log_path = s.get("log_path")
        cands = []
        if log_path:
            p = log_path if os.path.isabs(log_path) else os.path.join(repo_root, log_path)
            cands.append(p)
        hdir = os.path.join(repo_root, "docs", "handoff", str(tid))
        if os.path.isdir(hdir):
            cands.extend(glob.glob(os.path.join(hdir, "*.stream.jsonl")))
            cands.extend(glob.glob(os.path.join(hdir, "*.out")))
        newest = None
        for p in cands:
            try:
                st = os.stat(p)
            except OSError:
                continue
            if newest is None or st.st_mtime > newest:
                newest = st.st_mtime
                stream_bytes = st.st_size
        if newest is not None:
            age_s = max(0, int(time.time() - newest))
        if pid_alive or (isinstance(age_s, (int, float)) and age_s <= lane_fresh_s):
            status = "active"
        elif isinstance(age_s, (int, float)) and age_s <= 86400:
            status = "stale"
        else:
            status = "dead"
        started = parse_iso(s.get("last_pulse_at")) or parse_iso(s.get("started_at"))
        minutes = max(0, int((now - started).total_seconds() // 60)) if started else "?"
        where = s.get("where") or ("headless" if s.get("daemon_mode") else "terminal")
        status_reason = (
            f"foreign repo {slug}; pid={'alive' if pid_alive else 'dead'}"
            + (f"; stream_age={age_s}s" if age_s is not None else "; no stream")
        )
        emit({
            "task_id": tid,
            "phase": s.get("phase") or "?",
            "minutes_in_phase": minutes,
            "status": status,
            "status_reason": status_reason,
            "waiting": False,
            "where": where,
            "protocol_version": s.get("protocol_version", 1),
            "repo": slug,
            "age_s": age_s,
            "stream_bytes": stream_bytes,
        })
except Exception as e:  # never zero the table on one bad repo
    emit({"repo": slug, "error": "repo_read_error",
          "data": f"{e.__class__.__name__}: {str(e)[:180]}"})
PYF
    done < <(bash "${_LV2_PROJECTS_SH}" 2>/dev/null || true)
    if [[ ! -s "${_LV2_FOREIGN_ROWS_FILE}" ]]; then
      rm -f "${_LV2_FOREIGN_ROWS_FILE}"
      _LV2_FOREIGN_ROWS_FILE=""
    else
      _LV2_MAIN_JSON_TMP="$(mktemp "${TMPDIR:-/tmp}/lv2-snapshot-main.XXXXXX")"
    fi
  fi
fi

_lv2_main_snapshot() {
python3 - "$ACTIVE_YAML" "$HANDOFF_DIR" "$SNAPSHOT" "$JSON_MODE" "$SINCE" "$CP_QUESTIONS_DIR" "${BUS_JSONL:-}" "${BUS_OFFSET_FILE:-}" "$TRUTH_BREACHES_JSON" "$TMUX_WINDOWS_TSV" "$TMUX_PANES_TSV" "$TASKS_YAML_PATH" "$ACTIVE_LOCKFILE" "$TOMBSTONES_FILE" "$OBSERVE_ONLY" "$SCRIPT_DIR" "$PROJECT_ROOT" "$LANE_LIVENESS_JSON" "$QUESTION_ESCALATE_S" "$SUPERVISE_PRUNE_V2" <<'PY'
import sys, os, json, glob, datetime, subprocess, time
from collections import deque

(active_yaml, handoff_dir, snapshot_path, json_mode, since, cp_questions_dir,
 bus_jsonl, bus_offset_file, truth_breaches_json, tmux_windows_tsv,
 tmux_panes_tsv, tasks_yaml_path, active_lockfile, tombstones_file,
 observe_only_env, script_dir, project_root, lane_liveness_json,
 question_escalate_s_raw, prune_v2_raw) = sys.argv[1:21]
json_mode = json_mode == "1"
delta_mode = bool(since)
prune_v2_mode = prune_v2_raw != "0"

try:
    _truth = json.loads(truth_breaches_json)
except Exception:
    _truth = {"status": "unavailable", "breaches": []}
truth_probe_status = _truth.get("status", "unavailable")
truth_probe_reason = _truth.get("reason")
truth_breaches = _truth.get("breaches") or []
try:
    codex_liveness = json.loads(lane_liveness_json)
except Exception:
    codex_liveness = {"jobs": [], "availability": "unavailable"}
# Authoritative per-lane verdict (log mtime + process evidence, never a bare
# PID check) — consumed by prune evidence below instead of re-deriving death
# from an absent provider PID alone.
lane_liveness_by_id = {str(row["lane"]): row for row in (codex_liveness.get("lanes") or [])
                       if isinstance(row, dict) and row.get("lane")}

warnings = []

CAP_ROWS = 20
try:
    QUESTION_ESCALATE_S = max(0, int(question_escalate_s_raw))
except (TypeError, ValueError):
    QUESTION_ESCALATE_S = 300

# STATUS-SURFACE-SHOWS-STALE-TRUTH-01: a dead lane silent longer than this
# is reaped from the printed table (never from the underlying store — this
# is a render-time filter, not a prune). 86400s (24h) = one full working
# day: a lane silent across a whole day with no process cannot be state
# anyone is still waiting on, while anything shorter risks hiding a lane
# that stalled overnight and is still being triaged. 0 disables reaping.
try:
    LEADV2_SUPERVISE_REAP_S = int(os.environ.get("LEADV2_SUPERVISE_REAP_S", "86400"))
except (TypeError, ValueError):
    LEADV2_SUPERVISE_REAP_S = 86400
try:
    LEADV2_SUPERVISE_TOMBSTONE_ROWS = max(0, int(os.environ.get("LEADV2_SUPERVISE_TOMBSTONE_ROWS", "5")))
except (TypeError, ValueError):
    LEADV2_SUPERVISE_TOMBSTONE_ROWS = 5
try:
    _LANE_ABANDON_MAX_S = int(os.environ.get("LEADV2_LANE_ABANDON_MAX_S", "3600"))
except (TypeError, ValueError):
    _LANE_ABANDON_MAX_S = 3600
# LANE-LIVENESS-THREE-STATES-02: same window/rationale as leadv2-lane-liveness.sh's
# `finished_window` -- both probes must agree on the same three-state answer for the
# same lane, so both read the SAME env var and the SAME default (1800s).
try:
    _LANE_FINISHED_WINDOW_S = max(0, int(os.environ.get("LEADV2_LANE_FINISHED_WINDOW_S", "1800")))
except (TypeError, ValueError):
    _LANE_FINISHED_WINDOW_S = 1800
if LEADV2_SUPERVISE_REAP_S and LEADV2_SUPERVISE_REAP_S < _LANE_ABANDON_MAX_S:
    # A lane cannot legitimately be reaped before leadv2-lane-liveness.sh
    # itself has had a chance to classify it dead — clamp up rather than
    # silently reap fresher rows than the liveness ladder intends.
    warnings.append(
        f"LEADV2_SUPERVISE_REAP_S={LEADV2_SUPERVISE_REAP_S} is below the lane-liveness "
        f"abandon threshold ({_LANE_ABANDON_MAX_S}s); clamped up to {_LANE_ABANDON_MAX_S}"
    )
    LEADV2_SUPERVISE_REAP_S = _LANE_ABANDON_MAX_S

def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def parse_iso(s):
    if not s:
        return None
    try:
        s2 = s.rstrip("Z")
        dt = datetime.datetime.fromisoformat(s2)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        return dt
    except Exception:
        return None

def pid_alive(pid_val):
    try:
        pid = int(pid_val)
        os.kill(pid, 0)
        return True
    except (TypeError, ValueError, ProcessLookupError, PermissionError):
        return False

def _commit_age_s(worktree):
    # LANE-LIVENESS-THREE-STATES-02: same externally-checkable evidence as
    # leadv2-lane-liveness.sh's commit_age_s -- the lane's OWN worktree HEAD
    # commit time, never a worker's self-reported success. Missing/foreign/
    # non-git/unborn-HEAD worktree -> None (cannot establish finished),
    # never a fabricated age.
    if not worktree or not os.path.isdir(worktree):
        return None
    try:
        r = subprocess.run(["git", "-C", worktree, "log", "-1", "--format=%ct"],
                           capture_output=True, text=True, timeout=3)
    except Exception:
        return None
    if r.returncode != 0:
        return None
    try:
        ctime = int(r.stdout.strip())
    except ValueError:
        return None
    return max(0, int(time.time()) - ctime)

def emit_fatal(kind, message):
    """B1 fail-closed: registry_error / state_write_error. Never a successful
    empty table — only a registry that PARSED CLEANLY may return table: []."""
    if json_mode:
        print(json.dumps({"error": kind, "message": message}, indent=2))
    else:
        print(f"[supervise] {kind}: {message}", file=sys.stderr)
    sys.exit(1)

# ── Load active.yaml — fail closed on missing/malformed registry ───────────
# Only a file that exists AND parses to a dict with a `sessions` list is a
# "successfully reconciled" registry (individual malformed rows are dropped
# with a warning, per-row — that's reconciliation, not a registry defect).
sessions = []
if not os.path.isfile(active_yaml):
    emit_fatal("registry_error", f"active.yaml not found at {active_yaml} (never initialized — run leadv2-active-registry.sh to create it)")
try:
    import yaml
    with open(active_yaml, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except Exception as e:
    emit_fatal("registry_error", f"active.yaml parse error ({e.__class__.__name__}: {e}) at {active_yaml}")

if not isinstance(data, dict):
    emit_fatal("registry_error", f"active.yaml root is not a mapping ({type(data).__name__}) at {active_yaml}")

raw_sessions = data.get("sessions")
if raw_sessions is None:
    raw_sessions = []
if not isinstance(raw_sessions, list):
    emit_fatal("registry_error", f"active.yaml: sessions is not a list ({type(raw_sessions).__name__}) at {active_yaml}")

for s in raw_sessions:
    if not isinstance(s, dict) or not s.get("task_id"):
        warnings.append("active.yaml: dropped malformed session entry")
        continue
    sessions.append(s)

current = {s["task_id"]: s for s in sessions}  # last-write-wins on dup task_id

# ── Load previous snapshot ──────────────────────────────────────────────────
prev = {}
# S3 (1b07a6fd0490, row 33659fede36e): capture whether the snapshot existed
# BEFORE we (maybe) create it via the snapshot write later. On a FRESH
# supervise session the snapshot is absent, prev_tasks is empty, so the
# has_flag diff loop below would read prev_flag=False for every task that
# already has a stale phase8-passed.flag on disk -> every such task reported
# CLOSED-just-now. cold_start suppresses that one-shot hallucination; the
# snapshot is still seeded with the current has_flag state so cycle 2+ diffs
# correctly. (G2 root cause.)
snapshot_existed = os.path.isfile(snapshot_path)
if snapshot_existed:
    try:
        with open(snapshot_path, encoding="utf-8") as fh:
            prev = json.load(fh) or {}
    except Exception:
        warnings.append(f"{snapshot_path} unreadable — starting fresh snapshot")
        prev = {}
prev_tasks = prev.get("tasks", {}) if isinstance(prev, dict) else {}
prev_reported = set(prev.get("reported_events", []) if isinstance(prev, dict) else [])

now = datetime.datetime.now(datetime.timezone.utc)

# ── D-d: tmux reconciliation, triple-proof adoption, corroborated death ────
# (SUPERVISE-V2-01 item 4). Runs every call (delta and full) so death
# corroboration can span two consecutive 5s event polls, per D-d spec.
def _ps_tree():
    try:
        r = subprocess.run(["ps", "-eo", "pid,ppid,comm"], capture_output=True, text=True, timeout=5)
    except Exception:
        return {}, {}
    children_, comms_ = {}, {}
    for line in r.stdout.splitlines()[1:]:
        parts = line.split(None, 2)
        if len(parts) < 3:
            continue
        try:
            pid_v, ppid_v = int(parts[0]), int(parts[1])
        except ValueError:
            continue
        comms_[pid_v] = parts[2].split("/")[-1].lower()
        children_.setdefault(ppid_v, []).append(pid_v)
    return children_, comms_

def _find_claude_descendant(pane_pid, children_, comms_):
    if pane_pid is None:
        return None
    seen, q = set(), deque([pane_pid])
    while q:
        p = q.popleft()
        if p in seen:
            continue
        seen.add(p)
        if "claude" in comms_.get(p, ""):
            return p
        for c in children_.get(p, []):
            q.append(c)
    return None

# BROAD-STATUS-RENDERER-01 D4: ONE pid-birth rule, ONE inode. The local
# _pid_birth_of/_norm_birth copies are gone; import the shared module from
# <script_dir>/lib. Import guard (R4): a drifted .claude/scripts/ copy
# without lib/ falls back to the byte-identical inline forms and records
# birth_norm_source="inline" so the artifact says which rule fired —
# degrade, never crash a status probe.
try:
    sys.path.insert(0, os.path.join(script_dir, "lib"))
    from leadv2_pid_birth import pid_birth_of as _pid_birth_of, norm_birth as _norm_birth
    birth_norm_source = "shared"
except Exception:
    def _pid_birth_of(pid_val):
        try:
            r = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid_val)], capture_output=True, text=True, timeout=5)
            b = r.stdout.strip()
            return " ".join(b.split()) if b else None
        except Exception:
            return None

    def _norm_birth(v):
        # LANE-LIVENESS-LIES-01 Change 1a semantics, inline fallback: normalise
        # the STORED value at read time too, so legacy active.yaml rows
        # persisted with the pre-fix trailing space compare equal.
        if not v:
            return v
        return " ".join(str(v).split())
    birth_norm_source = "inline"

tmux_windows = {w.strip() for w in tmux_windows_tsv.splitlines() if w.strip()}
tmux_panes = {}
for line in tmux_panes_tsv.splitlines():
    if "|||" not in line:
        continue
    wname, pane_pid_s = line.split("|||", 1)
    wname = wname.strip()
    try:
        tmux_panes[wname] = int(pane_pid_s.strip())
    except ValueError:
        continue

known_task_ids = set()
try:
    if os.path.isfile(tasks_yaml_path):
        with open(tasks_yaml_path, encoding="utf-8") as fh:
            _td = yaml.safe_load(fh)
        _items = []
        if isinstance(_td, list):
            _items = _td
        elif isinstance(_td, dict):
            for _k in ("tasks", "items", "queues"):
                if isinstance(_td.get(_k), list):
                    _items = _td[_k]
                    break
        for it in _items:
            if isinstance(it, dict) and it.get("id"):
                known_task_ids.add(str(it["id"]))
except Exception as e:
    warnings.append(f"tasks.yaml unreadable for tmux-adoption id check: {e.__class__.__name__}: {e}")
# mission D-d: "tid in tasks.yaml/active" — an already-live registry row also
# satisfies the id-membership leg of the triple proof.
known_task_ids |= set(current.keys())

children_map, comms_map = (_ps_tree() if (tmux_windows or current) else ({}, {}))

orphans = []
pending_adopts = []  # triple-proof-satisfied candidates this call
for wname in sorted(tmux_windows):
    if wname in current:
        continue  # matching live row already exists — nothing to adopt
    pane_pid = tmux_panes.get(wname)
    claude_pid = _find_claude_descendant(pane_pid, children_map, comms_map)
    if wname in known_task_ids and claude_pid is not None:
        pending_adopts.append({
            "task_id": wname, "window": wname, "pane_pid": pane_pid,
            "pid": claude_pid, "pid_birth": _pid_birth_of(claude_pid),
        })
    else:
        reason = "unknown_task_id" if wname not in known_task_ids else "no_live_claude_pid"
        orphans.append({"window": wname, "reason": reason})

# D-e: the first 2 FULL (non-delta) reconciliation cycles after rollout are
# ALWAYS observe-only for legacy protocol_version==1 rows — counted here
# (never in a delta call) so a burst of 5s polls can't fast-forward past it.
reconcile_cycle = int(prev.get("reconcile_cycle_count", 0)) if isinstance(prev, dict) else 0
if not delta_mode:
    reconcile_cycle += 1
force_observe_only = reconcile_cycle <= 2
observe_only = force_observe_only or (observe_only_env == "1")

SPAWN_GRACE_MIN = 5
prev_dead_candidates = (prev.get("dead_candidates") or {}) if isinstance(prev, dict) else {}
dead_candidates_next = {}
dead_now = []
pending_prunes = []

for tid, s in list(current.items()):
    started_at_dt = parse_iso(s.get("started_at"))
    if started_at_dt and (now - started_at_dt).total_seconds() < SPAWN_GRACE_MIN * 60:
        continue  # spawning grace — never a death candidate this young
    backend = s.get("backend") or ("tmux" if s.get("tmux_window") else ("headless" if s.get("daemon_mode") else "terminal"))

    # R2-3 fix (codex-review-2.md finding 3): death evidence is gathered
    # per-signal (window presence, PID liveness/birth) but for a tmux-backend
    # lane BOTH must be corroborated together — D-d spec is "death =
    # corroborated (window+PID birth, 2 polls)", not either signal alone. The
    # prior code treated ANY single reason as sufficient, so a tmux window
    # that transiently fails to list (tmux server hiccup, rename race) while
    # the underlying claude PID is provably still alive got pruned after two
    # polls — a live child killed by a false-positive, in direct violation of
    # D-d and the live-child off_limits constraint. Non-tmux backends
    # (headless/workflow — no window concept at all) are unaffected: PID
    # evidence alone remains sufficient for them, exactly as before.
    window_missing = False
    if backend == "tmux":
        win = s.get("tmux_window") or tid
        window_missing = win not in tmux_windows

    pid = s.get("pid")
    pid_issue = False
    pid_issue_reason = None
    if pid is None:
        if not prune_v2_mode:
            # LEADV2_SUPERVISE_PRUNE_V2=0 rollback: exact prior implementation
            # — an absent PID is treated as death evidence on its own.
            pid_issue = True
            pid_issue_reason = "pid dead"
        else:
            # BLOCKING fix (SUPERVISOR-AUDIT-01): dispatch-code/funnel rows
            # are pid:null BY DESIGN (Codex/GLM jobs have no local Claude
            # PID). An absent PID is never itself death evidence — consult
            # the authoritative lane-liveness verdict (log mtime + process
            # evidence) instead. No liveness row / alive / silent => not
            # death evidence yet; only an explicit "dead:*" verdict counts.
            liveness_verdict = str((lane_liveness_by_id.get(tid) or {}).get("verdict") or "")
            if liveness_verdict.startswith("dead:"):
                pid_issue = True
                pid_issue_reason = f"lane_liveness={liveness_verdict}"
    elif not pid_alive(pid):
        pid_issue = True
        pid_issue_reason = "pid dead"
    else:
        stored_birth = _norm_birth(s.get("pid_birth"))
        cur_birth = _pid_birth_of(pid)
        if stored_birth and cur_birth and stored_birth != cur_birth:
            pid_issue = True
            pid_issue_reason = "pid birth mismatch (reuse)"

    reasons = []
    if backend == "tmux":
        if window_missing and pid_issue:
            reasons = ["tmux window missing", pid_issue_reason]
        # else: window-missing alone or pid-issue alone on a tmux lane is
        # NOT corroborated evidence of death — no reasons, falls through to
        # `continue` below, same as fully-clean evidence.
    elif pid_issue:
        reasons = [pid_issue_reason]

    # LANE-LIVENESS-THREE-STATES-02: a dead/absent pid with a commit in the
    # lane's OWN worktree inside FINISHED_WINDOW_S is a completed round, not
    # death evidence -- externally checkable, independent of stream/log
    # freshness. Placed BEFORE the LANE-LIVENESS-LIES freshness veto below so
    # a finished lane that has since gone silent past the shorter
    # LANE_FRESH_S window still clears here (this is the exact three-
    # founder-escalation defect: the worker had already committed and
    # exited, and by the time the second poll corroborated it, the stream
    # was no longer within LANE_FRESH_S either).
    if reasons:
        _commit_age = _commit_age_s(s.get("worktree"))
        if _commit_age is not None and _commit_age <= _LANE_FINISHED_WINDOW_S:
            reasons = []

    # LANE-LIVENESS-LIES-01 Change 1b: a fresh stream/log mtime outranks the
    # pid heuristic before any escalation (memory
    # feedback_pulse_liveness_by_stream_mtime). Reuse lane_liveness_by_id
    # (leadv2-lane-liveness.sh --all --json, already computed above) as the
    # single authoritative freshness oracle instead of opening a second one.
    # Applies to BOTH legs (pid evidence and tmux-window evidence) -- a live
    # worker whose tmux window transiently fails to list is the same lie.
    # Absence of a liveness row must never be evidence of life: the veto
    # simply does not fire and `reasons` (if any) stands.
    # Gated by prune_v2_mode: LEADV2_SUPERVISE_PRUNE_V2=0 is the emergency
    # rollback that must reproduce the EXACT prior (pre-SUPERVISOR-AUDIT-01)
    # PID-only death authority verbatim (test-supervise-v2.sh Test 12b) --
    # this veto is a Change-1b safety addition layered on TOP of the normal
    # (v2) path, same precedent as the "absent PID alone" gate above.
    if prune_v2_mode and reasons:
        _lv_row = lane_liveness_by_id.get(tid) or {}
        _age_s = _lv_row.get("age_s")
        try:
            _lane_fresh_s = max(0, int(os.environ.get("LEADV2_LANE_FRESH_S", "120")))
        except (TypeError, ValueError):
            _lane_fresh_s = 120
        if isinstance(_age_s, (int, float)) and _age_s <= _lane_fresh_s:
            reasons = []

    if not reasons:
        continue  # evidence clears any prior candidate marker — not carried forward

    is_legacy = s.get("protocol_version", 1) == 1
    if tid in prev_dead_candidates:
        # corroborated on a second consecutive poll — ALWAYS computed, even
        # under observe_only (honesty: a candidate must be visible via
        # would_prune, never silently dropped just because the write is
        # gated). Only the actual write below is observe_only-gated.
        dead_now.append({"task_id": tid, "reasons": reasons, "legacy": is_legacy})
        dead_candidates_next[tid] = prev_dead_candidates[tid]
        pending_prunes.append({"task_id": tid, "reasons": reasons, "last_state": dict(s),
                                "gated": observe_only or (is_legacy and force_observe_only)})
    else:
        dead_candidates_next[tid] = now_iso()

apply_prunes = [p for p in pending_prunes if not p["gated"]]

# ── Apply mutations under the SAME lock leadv2-active-registry.sh uses ─────
# (extends active.yaml, never rewrites the registry's own lock primitive —
# this is a direct, independent flock on the identical lockfile path).
applied_adopts = []
tombstoned_ids = []  # R2-4: only these task_ids may ever be pruned from active.yaml
if (pending_adopts or apply_prunes) and not observe_only:
    import fcntl as _fcntl
    # B1 fail-closed (test-supervise-failclosed.sh Test 5 regression guard):
    # any OSError while writing active.yaml/tombstones under an unwritable
    # state dir must surface as the typed state_write_error contract, never
    # an unhandled traceback (untyped stdout + non-JSON crash).
    try:
      os.makedirs(os.path.dirname(active_lockfile), exist_ok=True)
      _lf = open(active_lockfile, "a+")
      try:
        _fcntl.flock(_lf, _fcntl.LOCK_EX)

        # R2-4 fix (codex-review-2.md finding 4): tombstone FIRST, prune
        # SECOND. The prior order wrote active.yaml with the dead rows
        # ALREADY REMOVED before the tombstone file was even opened — a
        # tombstone write failure (or a crash between the two writes) meant
        # a row was permanently pruned with no historical record at all,
        # violating "tombstone before prune". Now: a row is only removed
        # from active.yaml if its tombstone write DURABLY SUCCEEDED this
        # call; a tombstone failure keeps the row live in active.yaml (and
        # in `current`, below) and surfaces a warning — never a silent
        # permanent prune with no tombstone.
        if apply_prunes:
          _tlock = tombstones_file + ".lock"
          try:
            os.makedirs(os.path.dirname(tombstones_file), exist_ok=True)
            _tlf = open(_tlock, "a+")
            try:
                _fcntl.flock(_tlf, _fcntl.LOCK_EX)
                _existing = []
                if os.path.isfile(tombstones_file):
                    try:
                        with open(tombstones_file, encoding="utf-8") as fh:
                            _existing = yaml.safe_load(fh) or []
                        if not isinstance(_existing, list):
                            _existing = []
                    except Exception:
                        _existing = []
                for p in apply_prunes:
                    _existing.append({
                        "task_id": p["task_id"], "tombstoned_at": now_iso(),
                        "reasons": p["reasons"], "last_state": p["last_state"],
                        "log_path": p["last_state"].get("log_path"),
                    })
                _ttmp = tombstones_file + f".tmp.{os.getpid()}"
                with open(_ttmp, "w", encoding="utf-8") as fh:
                    yaml.dump(_existing, fh, default_flow_style=False, sort_keys=False)
                os.replace(_ttmp, tombstones_file)
                tombstoned_ids = [p["task_id"] for p in apply_prunes]
            finally:
                _fcntl.flock(_tlf, _fcntl.LOCK_UN)
                _tlf.close()
          except OSError as e:
            # Tombstone write failed — do NOT prune. Every intended-prune
            # row stays in active.yaml this cycle; loud warning, never a
            # swallowed failure (same loud-fail philosophy as the
            # control-plane question read above).
            warnings.append(
                f"tombstone write failed for {[p['task_id'] for p in apply_prunes]} "
                f"({e.__class__.__name__}: {e}) — row(s) KEPT, prune skipped this cycle"
            )
            tombstoned_ids = []

        with open(active_yaml, encoding="utf-8") as fh:
            _d = yaml.safe_load(fh) or {}
        _sess = _d.setdefault("sessions", [])
        _by_tid = {s.get("task_id"): s for s in _sess}
        for a in pending_adopts:
            if a["task_id"] in _by_tid:
                continue  # raced with another writer — never clobber
            _row = {
                "session_id": f"tmux-adopt-{a['task_id']}-{int(now.timestamp())}",
                "task_id": a["task_id"], "worktree": None, "branch": None,
                "started_at": now_iso(), "phase": "unknown", "class": "Standard",
                "pulse_log": None, "pid": a["pid"], "pid_birth": a["pid_birth"],
                "parent_session_id": None, "daemon_mode": False,
                "last_pulse_at": now_iso(), "stale": False,
                "note": f"adopted from tmux window {a['window']}",
                "protocol_version": 2, "backend": "tmux", "origin": "adopted",
                "phase_started_at": now_iso(), "updated_at": now_iso(),
                "tmux_window": a["window"], "tmux_pane": a.get("pane_pid"),
                "log_path": None, "provider_receipts": [],
            }
            _sess.append(_row)
            applied_adopts.append(a["task_id"])
        # Only tombstone-confirmed ids are removed — a tombstone-failed
        # prune candidate is left in place (see above).
        _prune_ids = set(tombstoned_ids)
        if _prune_ids:
            _d["sessions"] = [s for s in _sess if s.get("task_id") not in _prune_ids]
        _tmp = active_yaml + f".tmp.{os.getpid()}"
        with open(_tmp, "w", encoding="utf-8") as fh:
            yaml.dump(_d, fh, default_flow_style=False, sort_keys=False)
        os.replace(_tmp, active_yaml)
      finally:
        _fcntl.flock(_lf, _fcntl.LOCK_UN)
        _lf.close()

      # Best-effort founder escalation via the existing canonical question
      # channel — never a second question mechanism, never auto-restart.
      # Only for rows that were ACTUALLY tombstoned+pruned this call.
      if tombstoned_ids:
        _ask_sh = os.path.join(script_dir, "leadv2-ask.sh")
        if os.path.isfile(_ask_sh):
            for p in apply_prunes:
                if p["task_id"] not in tombstoned_ids:
                    continue
                try:
                    subprocess.run(
                        [_ask_sh, p["task_id"],
                         f"Task {p['task_id']} corroborated dead: {'; '.join(p['reasons'])}. Escalate.",
                         "--option", "inspect|inspect logs first",
                         "--option", "restart|restart the task",
                         "--option", "abandon|mark abandoned",
                         "--no-block"],
                        capture_output=True, text=True, timeout=10,
                    )
                except Exception as e:
                    warnings.append(f"dead-escalation ask failed for {p['task_id']}: {e.__class__.__name__}: {e}")
    except OSError as e:
        emit_fatal("state_write_error", f"could not write active.yaml/tombstones mutation: {e.__class__.__name__}: {e}")

# Reflect mutations in THIS call's in-memory view without re-reading the file.
for tid in applied_adopts:
    a = next(x for x in pending_adopts if x["task_id"] == tid)
    current[tid] = {
        "task_id": tid, "phase": "unknown", "started_at": now_iso(),
        "last_pulse_at": now_iso(), "pid": a["pid"], "stale": False,
        "protocol_version": 2, "backend": "tmux", "tmux_window": a["window"],
    }
# R2-4: only actually-tombstoned rows are removed from the in-memory view —
# a gated (observe_only) OR tombstone-failed candidate stays visible in
# `current`/table, never silently vanishes just because a prune was skipped.
for p in pending_prunes:
    if p["task_id"] in tombstoned_ids:
        current.pop(p["task_id"], None)
sessions = list(current.values())

# ── has_flag (closed) per known task_id ─────────────────────────────────────
def flag_path(tid):
    return os.path.join(handoff_dir, tid, "phase8-passed.flag")

known_ids = set(current) | set(prev_tasks)
# S3 (1b07a6fd0490): True only on a fresh supervise session where no prior
# snapshot file existed. Suppresses the one-shot false-CLOSED burst (G2);
# the snapshot is still seeded below with current has_flag so cycle 2+ works.
cold_start = not snapshot_existed
closed_now = []
new_snapshot_tasks = {}

for tid in known_ids:
    has_flag = os.path.isfile(flag_path(tid))
    prev_flag = bool(prev_tasks.get(tid, {}).get("has_flag", False))
    # S3 (1b07a6fd0490): on a cold start every pre-existing phase8-passed.flag
    # would read as newly-closed (prev_flag defaults False). Seed the snapshot
    # WITHOUT emitting closed_now; cycle 2 will diff against this seeding and
    # report genuine new closures only. (G2 root cause.)
    if has_flag and not prev_flag and not cold_start:
        closed_now.append(tid)
    if tid in current:
        entry = dict(current[tid])
        entry["has_flag"] = has_flag
        new_snapshot_tasks[tid] = entry
    elif not has_flag:
        # still unresolved, vanished from active.yaml without a close flag —
        # keep tracking one more cycle so we don't lose a genuine close event
        entry = dict(prev_tasks.get(tid, {}))
        entry["has_flag"] = has_flag
        new_snapshot_tasks[tid] = entry
    # else: has_flag True and no longer in current — already reported (now or
    # earlier); drop from snapshot, nothing more to watch.

# ── `closed` bus-event consumer (SUPERVISOR-RETRO-01 §5) ────────────────────
# Reads new lines since the last call (stateful offset file — no flock: this
# is a periodic read-only status probe, not a mutation path; worst case on a
# torn concurrent read is a `closed` line reported one cycle late, never
# lost, since the offset only advances past lines successfully parsed).
# lean: no flock on the offset file — upgrade when >1 supervisor process
# reads bus.jsonl concurrently (today: one supervising lead per repo).
bus_closed_ids = []
if bus_jsonl and os.path.isfile(bus_jsonl):
    start = 0
    if bus_offset_file and os.path.isfile(bus_offset_file):
        try:
            start = int(open(bus_offset_file, encoding="utf-8").read().strip() or "0")
        except Exception:
            start = 0
    try:
        with open(bus_jsonl, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except Exception:
        lines = []
    for line in lines[start:]:
        if not line.strip():
            continue
        try:
            ev = json.loads(line)
        except Exception:
            continue
        if ev.get("type") == "closed" and ev.get("task_id"):
            bus_closed_ids.append(ev["task_id"])
    if bus_offset_file:
        try:
            os.makedirs(os.path.dirname(bus_offset_file), exist_ok=True)
            tmp = bus_offset_file + f".tmp.{os.getpid()}"
            with open(tmp, "w", encoding="utf-8") as fh:
                fh.write(str(len(lines)))
            os.replace(tmp, bus_offset_file)
        except Exception as e:
            warnings.append(f"could not persist bus offset: {e}")

for tid in bus_closed_ids:
    if tid not in closed_now:
        closed_now.append(tid)
    # Ensure the snapshot reflects closed so the flag-diff loop above doesn't
    # re-report it next cycle once/if the flag file also becomes visible.
    entry = dict(new_snapshot_tasks.get(tid, prev_tasks.get(tid, {})))
    entry["has_flag"] = True
    entry["closed_via_bus"] = True
    new_snapshot_tasks[tid] = entry

# ── Control-plane questions (LEAD-ANCHOR-01) ────────────────────────────────
# Read via leadv2-ask.sh's <qid>.yaml schema: task_id, question, options[],
# asked_at, status, answer. TRUE control plane — visible from every worktree,
# unlike the per-task questions-async dir below.
cp_pending = []
abandon_answers = []
if cp_questions_dir and os.path.isdir(cp_questions_dir):
    for qf in sorted(glob.glob(os.path.join(cp_questions_dir, "*.yaml"))):
        qid = os.path.basename(qf)
        if qid.endswith(".yaml"):
            qid = qid[: -len(".yaml")]
        try:
            import yaml
            with open(qf, encoding="utf-8") as fh:
                qd = yaml.safe_load(fh) or {}
        except Exception as e:
            # M2 fix (SUPERVISE-V2-01 fix-1): a malformed/unreadable
            # control-plane question file used to vanish silently -- a
            # blocked child could disappear from requires_founder with no
            # warning. Loud-fail philosophy (same as the active.yaml/
            # snapshot warnings above): record it, never drop it quietly.
            warnings.append(f"control-plane question {qf} unreadable/malformed ({e.__class__.__name__}: {e}) — skipped")
            continue
        if not isinstance(qd, dict):
            continue
        # ABANDON-NO-OP-01: a dead-lane escalation is actionable.  The old
        # snapshot only rendered pending questions; an answered `abandon`
        # left the registration intact, so every later reconciliation asked
        # the same question again.  Consume only this exact, self-authored
        # escalation shape -- never let an unrelated question abandon a lane.
        answer = qd.get("answer") or {}
        selected = answer.get("selected") if isinstance(answer, dict) else answer
        tid = str(qd.get("task_id") or "")
        if (qd.get("status") == "answered" and selected == "abandon" and tid
                and str(qd.get("question") or "").startswith(f"Task {tid} corroborated dead:")):
            abandon_answers.append((tid, qf))
            continue
        if qd.get("status") != "pending":
            continue
        question_text = qd.get("question", "")
        raw_options = qd.get("options") or []
        opt_labels = [
            o.get("label", "") if isinstance(o, dict) else str(o)
            for o in raw_options
        ]
        cp_pending.append({
            "qid": qid,
            "task_id": qd.get("task_id", "?"),
            "question": question_text,
            "summary_for_lead": qd.get("summary_for_lead") or question_text[:60],
            "options": opt_labels,
            "asked_at": qd.get("asked_at"),
            # D-a dual-read tagging (SUPERVISE-V2-01 item 4): control-plane
            # store has no worktree-local sibling file — legacy_path is null.
            "store": "control-plane",
            "legacy_path": None,
        })

# Apply answered abandon decisions before rendering.  The question YAML is
# retained as the durable answer receipt; only the in-flight registration is
# removed.  The identical active-registry lock makes this race-safe with a
# live lane refresh, and a failed write leaves both row and answer visible.
# T13 slice2 fix-round (F2, review): this block used to delete the active.yaml
# row DIRECTLY, bypassing the file's own R2-4 contract (tombstone FIRST, prune
# SECOND -- see the dead-row prune above): an abandoned lane left no historical
# record at all. The deletion now goes through the same tombstone path -- an
# ABANDON entry is durably written to tombstones.yaml under its lock BEFORE the
# row is pruned, and only ids whose tombstone write succeeded are removed from
# active.yaml (a tombstone failure keeps the row live and surfaces a warning).
abandoned_ids = []
if abandon_answers and not observe_only:
    try:
        import fcntl as _ab_fcntl
        os.makedirs(os.path.dirname(active_lockfile), exist_ok=True)
        with open(active_lockfile, "a+") as _ab_lf:
            _ab_fcntl.flock(_ab_lf, _ab_fcntl.LOCK_EX)
            with open(active_yaml, encoding="utf-8") as _ab_fh:
                _ab_data = yaml.safe_load(_ab_fh) or {}
            _ab_sessions = _ab_data.get("sessions") or []
            _ab_ids = {tid for tid, _qf in abandon_answers}
            # Tombstone FIRST (R2-4 order, mirrored from the dead-row prune
            # writer above -- same lock file, same tmp+replace durability).
            _ab_tombstoned = []
            try:
                _ab_tlock = tombstones_file + ".lock"
                os.makedirs(os.path.dirname(tombstones_file), exist_ok=True)
                with open(_ab_tlock, "a+") as _ab_tlf:
                    _ab_fcntl.flock(_ab_tlf, _ab_fcntl.LOCK_EX)
                    _ab_existing = []
                    if os.path.isfile(tombstones_file):
                        try:
                            with open(tombstones_file, encoding="utf-8") as _ab_tf:
                                _ab_existing = yaml.safe_load(_ab_tf) or []
                            if not isinstance(_ab_existing, list):
                                _ab_existing = []
                        except Exception:
                            _ab_existing = []
                    for _ab_tid in sorted(_ab_ids):
                        _ab_last = next((s for s in _ab_sessions if s.get("task_id") == _ab_tid), {})
                        _ab_existing.append({
                            "task_id": _ab_tid, "tombstoned_at": now_iso(),
                            "reasons": ["abandon: answered dead-lane escalation"],
                            "last_state": dict(_ab_last),
                            "log_path": _ab_last.get("log_path"),
                            "abandon": True,
                        })
                    _ab_ttmp = tombstones_file + f".tmp.{os.getpid()}"
                    with open(_ab_ttmp, "w", encoding="utf-8") as _ab_tout:
                        yaml.dump(_ab_existing, _ab_tout, default_flow_style=False, sort_keys=False)
                    os.replace(_ab_ttmp, tombstones_file)
                    _ab_tombstoned = sorted(_ab_ids)
            except OSError as e:
                # Tombstone write failed — do NOT prune. Rows stay in
                # active.yaml this cycle; loud warning, never a silent
                # permanent delete with no tombstone (R2-4 contract).
                warnings.append(
                    f"abandon tombstone write failed for {sorted(_ab_ids)} "
                    f"({e.__class__.__name__}: {e}) — row(s) KEPT, abandon prune skipped"
                )
                _ab_tombstoned = []
            # Prune SECOND — only tombstone-confirmed ids.
            _ab_prune = set(_ab_tombstoned)
            _ab_data["sessions"] = [s for s in _ab_sessions if s.get("task_id") not in _ab_prune]
            _ab_tmp = active_yaml + f".abandon.{os.getpid()}"
            with open(_ab_tmp, "w", encoding="utf-8") as _ab_out:
                yaml.safe_dump(_ab_data, _ab_out, default_flow_style=False, sort_keys=False)
            os.replace(_ab_tmp, active_yaml)
            abandoned_ids = sorted(_ab_prune)
    except Exception as e:
        warnings.append(f"abandon deregistration failed: {e.__class__.__name__}: {e}")

for _ab_tid in abandoned_ids:
    current.pop(_ab_tid, None)
    new_snapshot_tasks.pop(_ab_tid, None)
    dead_candidates_next.pop(_ab_tid, None)
    dead_now[:] = [d for d in dead_now if d.get("task_id") != _ab_tid]
    pending_prunes[:] = [p for p in pending_prunes if p.get("task_id") != _ab_tid]

cp_by_task = {}
for q in cp_pending:
    cp_by_task.setdefault(q["task_id"], []).append(q)

# ── Legacy handoff questions (global scan) ──────────────────────────────────
# Out-of-pipeline lanes do not register in active.yaml, so scan every handoff
# task rather than only the task ids present in the live-session registry.
legacy_pending = []
for pf in sorted(glob.glob(os.path.join(handoff_dir, "*", "questions-async", "*-pending.yaml"))):
    qdir = os.path.dirname(pf)
    qid = os.path.basename(pf)[:-len("-pending.yaml")]
    answered = os.path.join(qdir, f"{qid}-answered.yaml")
    if os.path.isfile(answered):
        continue
    task_id = os.path.basename(os.path.dirname(qdir))
    question = ""
    options = []
    summary = ""
    qd = {}
    try:
        import yaml
        with open(pf, encoding="utf-8") as fh:
            qd = yaml.safe_load(fh) or {}
        question = qd.get("question", "")
        summary = qd.get("summary_for_lead", "")
        options = [o.get("label", "") for o in (qd.get("options") or []) if isinstance(o, dict)]
    except Exception:
        pass
    legacy_pending.append({"qid": qid, "task_id": task_id, "question": question,
                           "summary_for_lead": summary, "options": options,
                           "asked_at": qd.get("created_at"),
                           "store": "legacy-handoff", "legacy_path": pf})

legacy_by_task = {}
for q in legacy_pending:
    legacy_by_task.setdefault(q["task_id"], []).append(q)

# ── Table + waiting + stuck (registry ∪ handoff-log lanes) ─────────────────
_scored_table = []  # (status_rank, age_key, entry) — ranked before the cap below
waiting_items = []
stuck_items = []
reaped_count = 0

# The liveness helper has already filtered .close and tombstoned lanes.  Do
# not fall back to a local verdict: this table only maps its authoritative
# output into the supervisor's historic active/stale/dead vocabulary.
lane_rows = {str(row.get("lane")): row for row in (codex_liveness.get("lanes") or [])
             if isinstance(row, dict) and row.get("lane")}
for tid, lane in sorted(lane_rows.items()):
    s = current.get(tid, {})
    phase = s.get("phase") or "?"
    verdict = str(lane.get("verdict") or "dead:unresolved")
    if verdict == "alive":
        status = "active"
    elif verdict.startswith("silent:"):
        status = "stale"
    else:
        status = "dead"
    status_reason = f"{verdict}; source={lane.get('source') or '?'}"
    if lane.get("log_path"):
        status_reason += f"; log={lane['log_path']}"
    started_at = parse_iso(s.get("started_at"))
    minutes = max(0, int((now - started_at).total_seconds() // 60)) if started_at else None

    # waiting-for-answer: open questions-async pending files with no sibling answered
    open_qs = list(legacy_by_task.get(tid, []))
    open_qs.extend(cp_by_task.get(tid, []))
    is_waiting = bool(open_qs)
    waiting_items.extend(open_qs)

    is_flagged_closed = new_snapshot_tasks.get(tid, {}).get("has_flag", False)
    reasons = []
    if not is_flagged_closed and verdict.startswith("dead:"):
        reasons.append(status_reason)
    if reasons:
        stuck_items.append({"task_id": tid, "reasons": reasons})

    # LEAD-ANCHOR-01: "where" tells the founder which host to look at —
    # tmux window / terminal window / headless. Older active.yaml rows
    # (pre-dating this field) fall back on daemon_mode; a windowed-launch row
    # with neither field present defaults to "terminal" (the prior sole
    # windowed backend before tmux was added).
    where = s.get("where") or ("headless" if s.get("daemon_mode") else "terminal")

    # M3 fix (SUPERVISE-V2-01 fix-1): leadv2-active-registry.sh:register op
    # comment claims "reader-side infers protocol_version: 1 ... see
    # leadv2-supervise.sh" -- that inference did not actually exist anywhere
    # in this file. Implement it: a row registered before item 3 (D-d
    # registry-honesty fields) simply lacks the key -- absence means V1.
    protocol_version = s.get("protocol_version", 1)

    age_s = lane.get("age_s")
    pid_alive_flag = bool(lane.get("pid_alive"))
    # Reap = do not render, never delete. A live PID is never reaped no
    # matter how old its timestamp; an indeterminate age (None) is treated
    # as NOT reapable — unknown is not the same as old.
    if (status == "dead" and not pid_alive_flag and LEADV2_SUPERVISE_REAP_S
            and isinstance(age_s, (int, float)) and age_s > LEADV2_SUPERVISE_REAP_S):
        reaped_count += 1
        continue

    entry = {
        "task_id": tid, "phase": phase,
        "minutes_in_phase": minutes if minutes is not None else "?",
        "status": status,
        "status_reason": status_reason,
        "waiting": is_waiting, "where": where,
        "protocol_version": protocol_version,
    }
    # Rank active > stale > dead, freshest first within a group, so a fixed
    # row cap drops the least-informative rows rather than truncating an
    # alphabetically-sorted list that can bury today's live lanes behind
    # thousands of never-reaped dead ones (STATUS-SURFACE-SHOWS-STALE-TRUTH-01).
    status_rank = {"active": 0, "stale": 1, "dead": 2}.get(status, 3)
    age_key = age_s if isinstance(age_s, (int, float)) else -1
    _scored_table.append((status_rank, age_key, entry))

_scored_table.sort(key=lambda t: (t[0], t[1]))
table = [entry for _, _, entry in _scored_table]
capped_count = max(0, len(table) - CAP_ROWS)
table = table[:CAP_ROWS]

# Tombstones are durable terminal lanes, not bookkeeping to hide from the
# status count.  Keep the latest death per task as its own row even after the
# active registry has been pruned.
terminal_by_task = {}
try:
    with open(tombstones_file, encoding="utf-8") as fh:
        for item in (yaml.safe_load(fh) or []):
            if isinstance(item, dict) and item.get("task_id"):
                terminal_by_task[item["task_id"]] = item
except Exception:
    pass
# Newest tombstoned_at first, capped — the tombstone loop used to append
# EVERY row unbounded past CAP_ROWS, which is half of why a 21-day-old
# corpse could still show up (STATUS-SURFACE-SHOWS-STALE-TRUTH-01 C3).
_tombstone_items = sorted(
    terminal_by_task.items(),
    key=lambda kv: kv[1].get("tombstoned_at") or "",
    reverse=True,
)
tombstone_capped_count = max(0, len(_tombstone_items) - LEADV2_SUPERVISE_TOMBSTONE_ROWS)
for tid, item in _tombstone_items[:LEADV2_SUPERVISE_TOMBSTONE_ROWS]:
    state = item.get("last_state") or {}
    started = parse_iso(state.get("started_at"))
    mins = max(0, int((now - started).total_seconds() // 60)) if started else "?"
    reason = "; ".join(str(x) for x in (item.get("reasons") or [])) or "terminal lane recorded without a reason"
    table.append({"task_id": tid, "phase": state.get("phase") or "never-started",
                  "minutes_in_phase": mins, "status": "dead", "status_reason": reason,
                  "waiting": False, "where": state.get("where") or "terminal record",
                  "protocol_version": state.get("protocol_version", "terminal")})

_hidden_total = reaped_count + capped_count + tombstone_capped_count
hidden_lanes_summary = (
    f"{_hidden_total} older/dead lanes hidden (reap>{LEADV2_SUPERVISE_REAP_S}s, cap={CAP_ROWS}, "
    f"tombstone_cap={LEADV2_SUPERVISE_TOMBSTONE_ROWS})"
    if _hidden_total else None
)

# Codex app-server jobs are first-class lanes even when they have no active.yaml
# row. Their status/phase comes only from codex-task.sh, never codex-guard/ps.
for job in codex_liveness.get("jobs", []):
    status = job.get("verdict", "unknown")
    started = parse_iso(job.get("started_at"))
    mins = int((now - started).total_seconds() // 60) if started else "?"
    table.append({"task_id": f"codex:{job.get('id', '?')}", "phase": job.get("phase", "unknown"),
                  "minutes_in_phase": mins, "status": status,
                  "status_reason": f"authoritative {job.get('source', 'codex-task.sh status')}: status={job.get('status', 'unknown')}" + (f"; {job.get('reason')}" if job.get('reason') else ""),
                  "waiting": False, "where": "codex app-server", "protocol_version": "provider"})

# Dangling control-plane questions — task_id not (or not yet) in active.yaml
# (e.g. registry lag). Still surface them; never silently drop a pending
# founder question just because the session table hasn't caught up.
for q in cp_pending:
    if q["task_id"] not in current:
        waiting_items.append(q)

# Dangling legacy-handoff questions are equally founder-visible even when
# their worker lane was launched outside the active.yaml dispatch funnel.
for q in legacy_pending:
    if q["task_id"] not in current:
        waiting_items.append(q)

# A question can be delivered while the lead is busy.  Keep it queued in the
# same supervisor stream and emit one additional, visibly escalated event
# after a short bounded age; never manufacture an answer or discard it.
for q in waiting_items:
    asked = parse_iso(q.get("asked_at"))
    age_s = max(0, int((now - asked).total_seconds())) if asked else 0
    q["age_seconds"] = age_s
    q["escalated"] = bool(asked and age_s >= QUESTION_ESCALATE_S)

# Dispatch prepass degradation is operational news.  Journal it into the
# same event stream as questions so the supervisor sees a raw-mission launch
# instead of inferring that the quality gate succeeded.
degraded_items = []
tasks_dir = os.path.join(os.path.dirname(active_yaml), "tasks")
try:
    for name in (os.listdir(tasks_dir) if os.path.isdir(tasks_dir) else []):
        if not name.startswith("dispatch-"):
            continue
        journal = os.path.join(tasks_dir, name, "journal.md")
        if not os.path.isfile(journal):
            continue
        with open(journal, encoding="utf-8") as fh:
            lines = fh.readlines()
        for line in reversed(lines):
            if "architect_prepass" in line and "status=degraded" in line:
                reason = line.split("reason=", 1)[1].split()[0] if "reason=" in line else "no_design"
                degraded_items.append({"task_id": name, "reason": reason})
                break
except Exception as e:
    warnings.append(f"degraded dispatch scan unavailable: {e.__class__.__name__}")

# ── Delta / event-key bookkeeping ───────────────────────────────────────────
current_events = set()
for q in waiting_items:
    suffix = ":escalated" if q.get("escalated") else ""
    current_events.add(f"waiting:{q['task_id']}:{q['qid']}{suffix}")
for st in stuck_items:
    current_events.add(f"stuck:{st['task_id']}:{'|'.join(st['reasons'])}")
for tid in closed_now:
    current_events.add(f"closed:{tid}")
# R2-5 fix (codex-review-2.md finding 5): dead_now must participate in the
# SAME dedup discipline as waiting/stuck/closed. Previously the JSON `dead`
# key returned the raw dead_now list on EVERY call — including every 5s
# delta poll while the row remained corroborated-dead-but-not-yet-pruned
# (e.g. observe_only, or a tombstone failure per R2-4's keep-row path) —
# so the (now-retired) supervisor loop's _render_events appended a duplicate DEAD
# urgent line every single poll instead of once per liveness change,
# violating the pulse ceiling ("unchanged poll -> zero bytes appended").
for d in dead_now:
    current_events.add(f"dead:{d['task_id']}:{'|'.join(d['reasons'])}")
for item in degraded_items:
    current_events.add(f"degraded:{item['task_id']}:{item['reason']}")

new_events = current_events - prev_reported if delta_mode else current_events

# ── Persist snapshot — unwritable state is fatal (B1), not a warning ───────
# A snapshot write failure means the delta cursor / closed-event dedupe is
# silently broken for every future --since call; that must fail loud now,
# not degrade into repeated false "nothing changed" on a later poll.
try:
    os.makedirs(os.path.dirname(snapshot_path), exist_ok=True)
    tmp = snapshot_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({
            "rendered_at": now_iso(),
            "tasks": new_snapshot_tasks,
            "reported_events": sorted(current_events),
            # D-d bookkeeping (item 4): carried forward so death corroboration
            # spans two consecutive calls and the D-e 2-cycle observe-only
            # rollout window survives across invocations of this script.
            "dead_candidates": dead_candidates_next,
            "reconcile_cycle_count": reconcile_cycle,
        }, fh, indent=2)
    os.replace(tmp, snapshot_path)
except Exception as e:
    emit_fatal("state_write_error", f"could not write snapshot to {snapshot_path}: {e.__class__.__name__}: {e}")

# ── Filter output items to only the ones whose event_key is in new_events ──
def event_key_waiting(q):
    suffix = ":escalated" if q.get("escalated") else ""
    return f"waiting:{q['task_id']}:{q['qid']}{suffix}"

def event_key_stuck(st):
    return f"stuck:{st['task_id']}:{'|'.join(st['reasons'])}"

def event_key_dead(d):
    return f"dead:{d['task_id']}:{'|'.join(d['reasons'])}"

def event_key_degraded(item):
    return f"degraded:{item['task_id']}:{item['reason']}"

out_waiting = [q for q in waiting_items if event_key_waiting(q) in new_events] if delta_mode else waiting_items
out_stuck = [st for st in stuck_items if event_key_stuck(st) in new_events] if delta_mode else stuck_items
out_closed = [tid for tid in closed_now if f"closed:{tid}" in new_events] if delta_mode else closed_now
# R2-5: same filter pattern as waiting/stuck/closed — a full (non-delta)
# call always reports the complete live dead_now state; a delta call only
# reports a dead_now entry whose event_key is NEW since the last snapshot.
out_dead = [d for d in dead_now if event_key_dead(d) in new_events] if delta_mode else dead_now
out_degraded = [item for item in degraded_items if event_key_degraded(item) in new_events] if delta_mode else degraded_items

# ── SESSION-HANDOFF-01: bounded resume object (full calls only) ────────────
# Rides this mandatory first --json call the leadv2-supervise skill already
# makes — no new hook, no new state file. Computed only on a full (non-delta)
# call, same gating as truth_probe/orphans/adopted above; a delta poll never
# needs to re-render the whole restore block. Best-effort: any failure here
# degrades to a typed stub, never crashes the parent snapshot call (this
# script's contract is "exit 0 always" for a status probe).
resume_obj = {"status": "skipped_delta"} if delta_mode else {"status": "degraded", "degraded": ["resume composer unavailable"]}
if not delta_mode:
    resume_script = os.path.join(script_dir, "leadv2-lanes-resume.sh")
    if os.path.isfile(resume_script):
        try:
            _rr = subprocess.run(
                ["bash", resume_script, "--json", "--project-root", project_root],
                capture_output=True, text=True, timeout=8,
            )
            resume_obj = json.loads(_rr.stdout) if _rr.returncode == 0 and _rr.stdout.strip() else {
                "status": "degraded", "degraded": [f"resume composer exit {_rr.returncode}"]
            }
        except Exception as e:
            resume_obj = {"status": "degraded", "degraded": [f"resume composer error: {e.__class__.__name__}: {e}"]}

# ── Render ────────────────────────────────────────────────────────────────
if json_mode:
    result = {
        "warnings": warnings,
        "delta_mode": delta_mode,
        # BROAD-STATUS-RENDERER-01 D4: which pid-birth normaliser fired
        # ("shared" = lib/leadv2_pid_birth.py, "inline" = drifted-copy
        # fallback). Auditable, never silently one or the other.
        "birth_norm_source": birth_norm_source,
        "table": [] if (delta_mode and not new_events) else table,
        "requires_founder": out_waiting,
        # DEFECT-2 (LEAD-ANCHOR-01): explicit top-level aliases so the
        # Monitor loop / skill contract can key off "questions"/"waiting"
        # by name instead of reaching into requires_founder[].
        "questions": out_waiting,
        "waiting": bool(out_waiting),
        "stuck": out_stuck,
        "closed_since_last": out_closed,
        # F2 truth-probe contract (SUPERVISE-V2-01 item 3): only populated on
        # a full (non-delta) call — see the bash block above. delta_mode
        # calls always report status "skipped" with an empty list; consumers
        # must not read that as "clear".
        "truth_probe": truth_probe_status,
        "truth_probe_reason": truth_probe_reason,
        "truth_breaches": truth_breaches,
        # D-d (item 4): orphans are reported, NEVER silently adopted; dead
        # rows are corroborated-twice and already tombstoned+pruned above
        # (or reported only, if observe_only) — the loop's pulse renderer
        # excludes any task_id present here from the N-lane count.
        "orphans": orphans,
        "adopted": applied_adopts,
        # Honesty (CONTROL-TRUTH discipline): a triple-proof-eligible
        # candidate must never go INVISIBLE just because observe_only
        # skipped the write — that is exactly the "control renders, engine
        # never reads it" lying-green pattern. would_adopt/would_prune list
        # every candidate that passed proof but was not applied this call.
        "would_adopt": [a["task_id"] for a in pending_adopts if a["task_id"] not in applied_adopts],
        # Fixed observe_only visibility gap: report every GATED prune
        # (per-item p["gated"], not just the global observe_only flag) —
        # a legacy row individually gated by D-e's 2-cycle window while
        # global observe_only is false must still surface here, never be
        # silently dropped.
        "would_prune": [p["task_id"] for p in pending_prunes if p["gated"]],
        # R2-5 fix (codex-review-2.md finding 5): out_dead, not the raw
        # dead_now list — deduped through new_events exactly like
        # waiting/stuck/closed, so a delta call reports a DEAD event once
        # per liveness change, never once per 5s poll while the state is
        # unchanged (pulse-ceiling violation otherwise).
        "dead": out_dead,
        "degraded": out_degraded,
        "observe_only": observe_only,
        "reconcile_cycle": reconcile_cycle,
        # SESSION-HANDOFF-01: bounded <supervisor-handoff> restore block —
        # "skipped_delta" on a --since call (never recomputed), a typed
        # {"status":"degraded",...} stub if the composer failed/timed out,
        # never a fabricated block. See leadv2-lanes-resume.sh.
        "resume": resume_obj,
        # STATUS-SURFACE-SHOWS-STALE-TRUTH-01 C4: never let a capped/reaped
        # table read as "this is the whole store" — null when nothing hidden.
        "hidden_lanes_summary": hidden_lanes_summary,
    }
    print(json.dumps(result, indent=2))
    sys.exit(0)

for w in warnings:
    print(f"WARN: {w}", file=sys.stderr)

if delta_mode:
    if not new_events:
        # silence — no new event since last snapshot; not an error
        sys.exit(0)
    if out_waiting:
        print("=== TREBUET TEBYA (open questions) ===")
        for q in out_waiting:
            opts = ", ".join(q["options"]) if q["options"] else "?"
            print(f"  [{q['qid']}] {q['task_id']}: {q['question']} (options: {opts})")
    if out_stuck:
        print("=== ZASTRYALO ===")
        for st in out_stuck:
            print(f"  {st['task_id']}: {'; '.join(st['reasons'])}")
    if out_closed:
        print("=== ZAKRYTO ===")
        for tid in out_closed:
            print(f"  {tid}")
    sys.exit(0)

if not table and not codex_liveness.get("jobs"):
    print("net zhivykh sessiy (no live sessions)")
    sys.exit(0)

print(f"{'TASK-ID':<28} {'phase':<12} {'min':>4} {'status':<8} {'waiting?':<9} {'where'}")
for row in table:
    print(f"{row['task_id']:<28} {row['phase']:<12} {str(row['minutes_in_phase']):>4} "
          f"{row['status']:<8} {'yes' if row['waiting'] else 'no':<9} {row['where']}")
if hidden_lanes_summary:
    print(f"... {hidden_lanes_summary}")

if waiting_items:
    print("\n=== TREBUET TEBYA (open questions) ===")
    for q in waiting_items:
        opts = ", ".join(q["options"]) if q["options"] else "?"
        print(f"  [{q['qid']}] {q['task_id']}: {q['question']} (options: {opts})")

if stuck_items:
    print("\n=== ZASTRYALO ===")
    for st in stuck_items:
        print(f"  {st['task_id']}: {'; '.join(st['reasons'])}")

if closed_now:
    print("\n=== ZAKRYTO s proshlogo snimka ===")
    for tid in closed_now:
        print(f"  {tid}")
PY
}

# LANE-OBSERVABILITY-02 change 3: with foreign rows in hand, capture the main
# snapshot to a temp file and splice the foreign rows onto its table (append —
# own-repo ranking/cap untouched); otherwise run it exactly as before. A main-
# snapshot failure propagates unchanged (fail-closed contract above is the
# MAIN snapshot's own; the merge step never swallows it).
if [[ -n "${_LV2_MAIN_JSON_TMP}" ]]; then
  _lv2_main_snapshot > "${_LV2_MAIN_JSON_TMP}"
  python3 - "${_LV2_MAIN_JSON_TMP}" "${_LV2_FOREIGN_ROWS_FILE}" <<'PYM' || { rm -f "${_LV2_MAIN_JSON_TMP}"; exit 1; }
import json, sys

main_path, foreign_path = sys.argv[1], sys.argv[2]
with open(main_path, encoding="utf-8") as fh:
    doc = json.load(fh)
if not isinstance(doc, dict) or not isinstance(doc.get("table"), list):
    # a typed {"error": ...} doc — re-emit verbatim, never bury a fail-closed
    # verdict under a merge crash
    with open(main_path, encoding="utf-8") as fh:
        sys.stdout.write(fh.read())
    sys.exit(0)
with open(foreign_path, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if line:
            try:
                doc["table"].append(json.loads(line))
            except ValueError:
                continue
print(json.dumps(doc, indent=2))
PYM
  rm -f "${_LV2_MAIN_JSON_TMP}"
else
  _lv2_main_snapshot
fi
