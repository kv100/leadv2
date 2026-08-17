#!/usr/bin/env bash
# leadv2-supervise-loop.sh — SUPERVISE-V2-01 D-c (batch-2 item 1): one
# Monitor-attachable FOREGROUND loop around `leadv2-supervise.sh --json
# --since <cursor>`. The loop renders output to a log file; the supervising
# lead only Monitor()s that file and never re-invokes leadv2-supervise.sh
# in-band. This script owns the sleep/poll cadence — not the LLM (off_limits:
# "no sleep/poll loop owned by the LLM").
#
# Usage:
#   leadv2-supervise-loop.sh --ensure   # attach-or-start: if a live loop
#     already owns the PID+birth sentinel, print its log path and exit 0
#     WITHOUT starting a duplicate (re-entry/PostCompact safe). Otherwise this
#     process becomes the loop itself (blocks — spawn it backgrounded).
#   leadv2-supervise-loop.sh            # unconditionally becomes the loop
#     (no sentinel liveness check first) — prefer --ensure from callers.
#
# Cadence (D-c):
#   every LEADV2_SUPERVISE_EVENT_POLL_S (default 5s): `leadv2-supervise.sh
#     --json --since <cursor>` — new question/dead/stuck/closed/truth-breach
#     events are appended to the log as ONE typed URGENT line each,
#     immediately. Unchanged poll -> zero bytes appended (delta_mode default).
#   every LEADV2_SUPERVISE_PULSE_S (default 300s): one full non-delta call ->
#     exactly N status lines for N non-dead lanes, each <=180 bytes:
#       `task_id phase age waiting|stuck|ok cx=<receipt|-> glm=<receipt|->`
#     (dead lanes are excluded from the N-count per D-d; their liveness is
#     surfaced only via the DEAD urgent event + founder escalation, never as
#     a pulse row — the mission grammar's "dead" token documents the state
#     enum, it is not reachable inside a non-dead-lane pulse line).
#
# Env overrides (test sandboxing):
#   LEADV2_PROJECT_ROOT / CLAUDE_PROJECT_DIR / PROJECT_ROOT — repo root
#     (same fail-closed order as leadv2-supervise.sh; no script-dir fallback)
#   LEADV2_SUPERVISE_EVENT_POLL_S   — event poll interval seconds (default 5)
#   LEADV2_SUPERVISE_PULSE_S        — full pulse interval seconds (default 300)
#   LEADV2_SUPERVISE_BROAD_STATUS_S — founder broad-status cadence seconds
#     (default 1800; 0 disables as a one-step rollback)
#   LEADV2_SUPERVISE_LOOP_MAX_CYCLES — exit after N event-poll cycles (test
#     determinism; 0/unset = run forever)
#   LEADV2_SUPERVISE_LOOP_PULSE_ON_START=1 — force a pulse on the FIRST cycle
#     instead of waiting for the full PULSE_S window (test determinism)
#
# Exit codes: 0 = ensure found a live loop already running (EXISTING: adopt)
# OR a bare invocation found a live owner it must not displace (FOREIGN) OR
# the loop ran its bounded test cycles and exited cleanly. 1 = root_error.
#
# lean: cx=/glm= receipts are read directly from active.yaml's
# provider_receipts[] field (populated by a future provider-wrapper writer —
# batch-1 already reserves the field, empty by default) rather than a new
# column in leadv2-supervise.sh's JSON table — upgrade when a receipt writer
# lands and the table shape needs the same data server-side.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENSURE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ensure) ENSURE=1; shift ;;
    -h|--help)
      printf -- 'Usage: leadv2-supervise-loop.sh [--ensure]\n'
      exit 0
      ;;
    *)
      printf -- '[supervise-loop] unknown arg: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

# ── Fail-closed root resolution — identical order to leadv2-supervise.sh ───
PROJECT_ROOT=""
if [[ -n "${LEADV2_PROJECT_ROOT:-}" ]]; then
  PROJECT_ROOT="$LEADV2_PROJECT_ROOT"
elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  PROJECT_ROOT="$CLAUDE_PROJECT_DIR"
elif _lv2l_top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"; then
  PROJECT_ROOT="$_lv2l_top"
fi
if [[ -z "$PROJECT_ROOT" ]]; then
  printf -- '[supervise-loop] root_error: could not resolve project root — set LEADV2_PROJECT_ROOT or CLAUDE_PROJECT_DIR, or run from inside a git worktree (cwd=%s)\n' "$PWD" >&2
  exit 1
fi
export LEADV2_PROJECT_ROOT="$PROJECT_ROOT"

STATE_PATH_SH="${SCRIPT_DIR}/leadv2-state-path.sh"
SUPERVISE_SH="${SCRIPT_DIR}/leadv2-supervise.sh"

SENTINEL="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" .supervise-loop.json)"
LOG_FILE="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" supervise-loop.log)"
ACTIVE_YAML="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" active.yaml)"

EVENT_POLL_S="${LEADV2_SUPERVISE_EVENT_POLL_S:-5}"
PULSE_S="${LEADV2_SUPERVISE_PULSE_S:-300}"
BROAD_STATUS_S="${LEADV2_SUPERVISE_BROAD_STATUS_S:-1800}"
MAX_CYCLES="${LEADV2_SUPERVISE_LOOP_MAX_CYCLES:-0}"

# EFFICIENCY-TUNE-01 C: this different registry artifact keeps its own event,
# but shares the lane-silence knob so operators do not tune competing limits.
JOB_STALL_MIN="${LEADV2_LANE_SILENT_MAX_S:-900}"
JOB_REG_ROOT="/tmp/leadv2-job-registry"
JOB_REG_SEEN="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" job-registry-seen.json)"

_now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
# DO NOT "simplify" back to `tr -s ' '` alone. SESSION-CLOSE-FIXES-01 fix 1A:
# this is the root cause of the --ensure sibling-spawn. The bash writer here
# used `tr -s ' '` which squeezes interior whitespace runs but NEVER strips
# the leading/trailing space, producing `"Fri Jul 31 19:52:12 2026 " (trailing
# space)`. The python reader in the PYENSURE block normalised with
# `" ".join(b.split())` (which trims), giving `"Fri Jul 31 19:52:12 2026"`.
# The two NEVER compared equal, the corroboration branch never returned
# EXISTING, and EVERY --ensure fell through to "claim ownership + run" — i.e.
# every intervention added a sibling loop. The fix is byte-identical trimming
# on both sides (collapse interior runs AND strip both ends), matching python.
_pid_birth() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//' || true; }
_pid_alive() { kill -0 "$1" 2>/dev/null; }

# ── Alarm dedupe (SUPERVISOR-HARDENING-01 item 5) ──────────────────────────
# Transition-based: an alarm fires only on (key->value) change, so a
# persistent breach repeats once, not every poll. Source the shared lib; if it
# is unavailable, fall back to pass-through (every candidate fires) so an alarm
# is never silently lost to a missing lib.
if [[ -f "${SCRIPT_DIR}/lib/leadv2-alarm-dedupe.sh" ]]; then
  # shellcheck source=lib/leadv2-alarm-dedupe.sh
  source "${SCRIPT_DIR}/lib/leadv2-alarm-dedupe.sh"
fi
if ! command -v _leadv2_alarm_fire >/dev/null 2>&1; then
  _LEADV2_ALARM_DEDUPE_LOADED=0
  leadv2_alarm_filter()      { cat; }                 # pass-through fallback
  leadv2_alarm_filter_seen() { cat; }
  leadv2_alarm_sweep()       { :; }
else
  _LEADV2_ALARM_DEDUPE_LOADED=1
fi

# ── Item 2/3 shared paths (defined early: the --ensure block needs the
#    heartbeat path, and _install_beat_cron needs both) ────────────────────
# Heartbeat (item 2): written at the TOP of every cycle so a hang inside
# supervise.sh shows up as heartbeat staleness. Lives beside the ownership
# sentinel (same control-plane dir).
HEARTBEAT_FILE="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" .supervise-loop.heartbeat)"
WATCHDOG_SH="${SCRIPT_DIR}/leadv2-supervise-watchdog.sh"

# ── Item 3: cron-owned status beat ─────────────────────────────────────────
# Attaching supervision installs ONE idempotent crontab entry whose payload is
# the watchdog (item 2) — which both alarms on loop silence AND calls --ensure
# to self-heal. One entry covers failure classes 1 (silent loop) and 2 (dead
# loop, no beat). Idempotent by a marker tag; re-running --ensure never
# accumulates duplicates. Kill-switch LEADV2_SUPERVISE_BEAT_CRON=0 (tests +
# founder opt-out). CRONTAB_BIN is injectable so tests never touch the real
# crontab.
_install_beat_cron() {
  [[ "${LEADV2_SUPERVISE_BEAT_CRON:-1}" == "1" ]] || return 0
  [[ -x "$WATCHDOG_SH" ]] || return 0
  local crontab_bin="${CRONTAB_BIN:-crontab}"
  command -v "$crontab_bin" >/dev/null 2>&1 || {
    # Visible gap, not a silent one (PULSE-IS-A-PLUGIN-DUTY-01 §3): with no
    # cron there is no resurrection after a session death — only a manual
    # --ensure restarts the loop, and the founder should see that in the log.
    printf -- '%s [supervise-loop] beat-cron install skipped: %s unavailable — restart after a session death needs a manual --ensure\n' \
      "$(_now_iso)" "$crontab_bin" >>"$LOG_FILE" 2>/dev/null || true
    return 0
  }
  # Repo slug for the marker (basename of the main repo toplevel).
  local repo_slug
  repo_slug="$(basename "${PROJECT_ROOT}")"
  local marker="# LEADV2_SUPERVISE_BEAT ${repo_slug}"
  local cron_line="*/10 * * * * ${WATCHDOG_SH} --project-root ${PROJECT_ROOT} ${marker}"
  # Read-modify-write under a sibling lock (no unlocked crontab rewrite — two
  # concurrent --ensure could otherwise race). python3 fcntl, same convention
  # as the ownership sentinel below (no bash `flock` binary on macOS/BSD).
  python3 -c "
import sys, os, fcntl, subprocess
lock_path, crontab_bin, marker, line = sys.argv[1:5]
os.makedirs(os.path.dirname(lock_path) or '.', exist_ok=True)
lf = open(lock_path, 'a+')
fcntl.flock(lf, fcntl.LOCK_EX)
try:
    cur = subprocess.run([crontab_bin, '-l'], capture_output=True, text=True)
    rows = (cur.stdout or '').splitlines()
    rows = [r for r in rows if marker not in r]
    rows.append(line)
    new = '\n'.join(rows) + '\n'
    p = subprocess.run([crontab_bin, '-'], input=new, capture_output=True, text=True)
    sys.exit(0 if p.returncode == 0 else 0)  # never fail --ensure on a cron hiccup
finally:
    fcntl.flock(lf, fcntl.LOCK_UN)
    lf.close()
" "${HEARTBEAT_FILE}.crontab.lock" "$crontab_bin" "$marker" "$cron_line" 2>/dev/null || true
}

# ── --ensure: attach-or-start via PID+birth sentinel (no duplicate loop) ──
# R2-2 fix (codex-review-2.md finding 2): the old version did an UNLOCKED
# check-then-create — two concurrent `--ensure` calls could both observe a
# stale/dead sentinel, both fall through, and both write a sentinel claiming
# ownership (duplicate loop; whichever writes last "wins" and the other's
# process silently has no matching sentinel). The liveness check AND the
# ownership write below now happen inside ONE critical section held by a
# single `flock` on `${SENTINEL}.lock` (python3 fcntl, matching this
# project's portable-locking convention elsewhere in leadv2-supervise.sh —
# no bash `flock` binary, which is absent on macOS/BSD).
#
# SESSION-CLOSE-FIXES-01 fix 1B/1C: the adopt predicate now requires
# pid-alive AND birth-match AND a fresh heartbeat (LEADV2_SUPERVISE_ADOPT_MAX_AGE_S,
# default 600s = watchdog's 2×PULSE_S). A birth match alone used to be the gate
# but the birth strings never compared equal (fix 1A) so EXISTING never fired
# and every --ensure spawned a sibling. Now birth is normalised identically on
# both sides, and a stale/hung owner (birth matches but heartbeat aged out) is
# treated as NOT live → fall through and claim. The liveness check is computed
# UNCONDITIONALLY (not just under --ensure): a bare invocation that finds a
# live owner prints FOREIGN and exits 0 (single-owner invariant) instead of
# clobbering the live owner's sentinel with no check at all.
mkdir -p "$(dirname "$SENTINEL")" "$(dirname "$LOG_FILE")" "$(dirname "$HEARTBEAT_FILE")"
MY_PID=$$
MY_BIRTH="$(_pid_birth "$MY_PID")"

_ENSURE_OUT="$(python3 - "$SENTINEL" "${SENTINEL}.lock" "$ENSURE" "$MY_PID" "$MY_BIRTH" "$HEARTBEAT_FILE" <<'PYENSURE'
import sys, os, json, fcntl, tempfile, datetime, subprocess, time

sentinel_path, lock_path, ensure_flag, my_pid_s, my_birth, heartbeat_path = sys.argv[1:7]
ensure_flag = ensure_flag == "1"
my_pid = int(my_pid_s)

adopt_max_age = 600
try:
    adopt_max_age = int(os.environ.get("LEADV2_SUPERVISE_ADOPT_MAX_AGE_S", "600"))
except Exception:
    pass

def pid_alive(pid_val):
    try:
        os.kill(int(pid_val), 0)
        return True
    except (TypeError, ValueError, ProcessLookupError, PermissionError):
        return False

def pid_birth(pid_val):
    # MUST mirror bash _pid_birth byte-for-byte: collapse interior whitespace
    # runs AND strip both ends. (SESSION-CLOSE-FIXES-01 fix 1A — the trailing
    # space mismatch was the sibling-spawn root cause.) Never parse as a date.
    try:
        r = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid_val)],
                            capture_output=True, text=True, timeout=5)
        b = r.stdout.strip()
        return " ".join(b.split()) if b else ""
    except Exception:
        return ""

def heartbeat_fresh(hb_path):
    # A loop that just started has not written beat 1 yet — an ABSENT
    # heartbeat is adopt-safe (matches the watchdog: no heartbeat is not
    # "silent" unless a log exists). Treating absent as stale would
    # reintroduce the sibling spawn during the startup window. STALE-but-
    # present (aged past adopt_max_age) is NOT fresh → claim + run.
    if not hb_path or not os.path.isfile(hb_path):
        return True
    try:
        age = time.time() - os.path.getmtime(hb_path)
        return age < adopt_max_age
    except Exception:
        return True

def live_owner(d):
    spid = d.get("pid")
    sbirth = d.get("pid_birth")
    if spid is None or not pid_alive(spid):
        return None
    if not sbirth or pid_birth(spid) != sbirth:
        return None        # different process reusing the pid → not our owner
    if not heartbeat_fresh(heartbeat_path):
        return None        # same process, but stale/hung → not live
    return int(spid)

os.makedirs(os.path.dirname(lock_path) or ".", exist_ok=True)
lf = open(lock_path, "a+")
fcntl.flock(lf, fcntl.LOCK_EX)
try:
    owner_pid = None
    if os.path.isfile(sentinel_path):
        try:
            with open(sentinel_path, encoding="utf-8") as fh:
                d = json.load(fh) or {}
            owner_pid = live_owner(d)
        except Exception:
            owner_pid = None
    if owner_pid is not None:
        # A live owner exists. --ensure ADOPTS it (no sibling); a bare call
        # honours the single-owner invariant and declines to start (FOREIGN).
        if ensure_flag:
            print(f"EXISTING {owner_pid}")
        else:
            print(f"FOREIGN {owner_pid}")
        sys.exit(0)
    # No live owner — claim ownership atomically, still holding the lock, so no
    # other --ensure caller can race us here. Covers: no sentinel, dead pid,
    # pid reuse (birth mismatch), and stale/hung-but-same-pid owner.
    out = {
        "pid": my_pid,
        "pid_birth": my_birth,
        "started_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    dirn = os.path.dirname(sentinel_path)
    os.makedirs(dirn, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=dirn, suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(out, fh)
    os.replace(tmp, sentinel_path)
    print(f"NEW {my_pid}")
finally:
    fcntl.flock(lf, fcntl.LOCK_UN)
    lf.close()
PYENSURE
)"

_ENSURE_STATUS="$(printf -- '%s\n' "$_ENSURE_OUT" | awk '{print $1}')"
_ENSURE_PID="$(printf -- '%s\n' "$_ENSURE_OUT" | awk '{print $2}')"

if [[ "$_ENSURE_STATUS" == "EXISTING" ]]; then
  # Adopt: ensure the beat cron is present (idempotent) then exit 0 WITHOUT
  # starting a sibling. The adopt line goes to the log file — today it only
  # went to stdout, which cron discards, making the adoption invisible.
  _install_beat_cron
  printf -- '%s [supervise-loop] adopt existing loop pid=%s log=%s\n' \
    "$(_now_iso)" "$_ENSURE_PID" "$LOG_FILE" >>"$LOG_FILE"
  printf -- '[supervise-loop] already running pid=%s log=%s\n' "$_ENSURE_PID" "$LOG_FILE"
  exit 0
fi

if [[ "$_ENSURE_STATUS" == "FOREIGN" ]]; then
  # Bare invocation found a live owner — single-owner invariant: do NOT start.
  printf -- '%s [supervise-loop] another loop owns this repo (pid=%s) — not starting\n' \
    "$(_now_iso)" "$_ENSURE_PID" >>"$LOG_FILE"
  exit 0
fi

printf -- '%s [supervise-loop] started pid=%s log=%s event_poll=%ss pulse=%ss\n' \
  "$(_now_iso)" "$MY_PID" "$LOG_FILE" "$EVENT_POLL_S" "$PULSE_S" >>"$LOG_FILE"

# ── Heartbeat writer (HEARTBEAT_FILE / WATCHDOG_SH / _install_beat_cron are
#    defined above the --ensure block; this writer belongs to the loop body) ─
_write_heartbeat() {  # <cycle>
  local cycle="$1"
  python3 -c "
import sys, os, json, tempfile, datetime
path, pid, birth, cyc = sys.argv[1:5]
out = {'pid': int(pid), 'pid_birth': birth, 'cycle': cyc,
       'ts_iso': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}
d = os.path.dirname(path) or '.'
os.makedirs(d, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=d, suffix='.tmp')
with os.fdopen(fd, 'w', encoding='utf-8') as fh:
    json.dump(out, fh)
os.replace(tmp, path)
" "$HEARTBEAT_FILE" "$MY_PID" "$MY_BIRTH" "$cycle" 2>/dev/null || true
}

# Install the beat whenever a NEW loop actually starts (EXISTING already
# installed it in its own branch above before the early exit).
_install_beat_cron

# R2-2 fix: the EXIT trap used to unconditionally `rm -f` the sentinel — if
# another `--ensure` call raced in between (e.g. a PostCompact re-entry that
# started a second loop after this one's ownership check but before this
# one's write), that trap could delete the SECOND loop's live ownership
# record out from under it. Now the trap only removes the sentinel if it
# STILL contains this process's own pid+birth — i.e. this process is still
# the recorded owner — matching the same "never clobber a different owner"
# discipline leadv2-supervise.sh's active.yaml mutation uses.
_cleanup_sentinel() {
  python3 -c "
import json, sys, os
path, pid, birth = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, encoding='utf-8') as fh:
        d = json.load(fh) or {}
    if str(d.get('pid')) == pid and d.get('pid_birth') == birth:
        os.remove(path)
except Exception:
    pass
" "$SENTINEL" "$MY_PID" "$MY_BIRTH" 2>/dev/null || true
}
trap _cleanup_sentinel EXIT

PUMP_SH="${LEADV2_BACKLOG_PUMP_BIN:-${SCRIPT_DIR}/leadv2-backlog-pump.sh}"
BROAD_STATUS_SH="${SCRIPT_DIR}/leadv2-broad-status.sh"

# PULSE-IS-A-PLUGIN-DUTY-01 C1: a beat that cannot compose must still wake the
# lead — a missing status is visible, never inferred from silence. Fires once
# per occurrence (value carries the epoch), which at one beat per
# BROAD_STATUS_S window is the same cadence the beat itself would have.
_emit_broad_status_degraded() {  # <reason>
  local reason="${1:-unknown}"
  if command -v leadv2_alarm_transition >/dev/null 2>&1 \
      && ! leadv2_alarm_transition broad_status_ready "degraded:${reason}:$(date +%s)" 2>/dev/null; then
    return 0
  fi
  printf -- '%s [SUPERVISE-URGENT] BROAD_STATUS_READY at=%s path=docs/leadv2/founder-status.md rows=- dispatched=unavailable degraded=1 reason=%s\n' \
    "$(_now_iso)" "$reason" >>"$LOG_FILE"
}

# BACKLOG-PUMP-01: this loop already owns the sleep/poll cadence (off_limits:
# "no sleep/poll loop owned by the LLM") — the pump's refill trigger belongs
# here, not in the lead's turn. Gated by LEADV2_BACKLOG_PUMP so an explicit 0
# is a zero-cost no-op; the default is on and a single flip restores prior
# behaviour.
_run_pump_on_close() {
  local out_json="$1"
  [[ "${LEADV2_BACKLOG_PUMP:-1}" == "1" ]] || return 0
  [[ -x "$PUMP_SH" ]] || return 0
  local closed_ids
  closed_ids="$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
for tid in (d.get('closed_since_last') or []):
    print(tid)
" "$out_json" 2>/dev/null || true)"
  local tid
  while IFS= read -r tid; do
    [[ -z "$tid" ]] && continue
    bash "$PUMP_SH" reap "$tid" >>"$LOG_FILE" 2>&1 || true
  done <<<"$closed_ids"
  # Refill regardless of whether anything closed THIS cycle — capacity can
  # also free up from a manual close, or the pump can be freshly enabled
  # while lanes already sit idle (the exact founder complaint this exists
  # to fix): "capacity free + queue non-empty" must not depend on a fresh
  # event to notice.
  bash "$PUMP_SH" check >>"$LOG_FILE" 2>&1 || true
}

_render_events() {
  local out_json="$1"
  local alarm_rows
  # Non-alarm events (QUESTION/DEAD/STUCK/CLOSED/DEGRADED) are written to the
  # log directly — they are already delta-deduped by the `--since loop` call.
  # TRUTH_RED rows are printed to stdout as `<key>\t<value>\t<line>` and piped
  # through the transition dedupe below (item 5) so a persistent breach does
  # not repeat every poll. No SWEEP here — the authoritative truth-probe runs
  # on the pulse cadence (_render_pulse); sweeping at the 5s event cadence
  # would clear still-active breaches between probes.
  alarm_rows="$(python3 - "$out_json" "$LOG_FILE" <<'PYEV'
import json, sys, datetime

out_str, log_path = sys.argv[1], sys.argv[2]
try:
    d = json.loads(out_str)
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
events = []
alarm_keys = []  # (key, value) for truth_red — emitted via stdout for dedupe
for q in (d.get("requires_founder") or d.get("questions") or []):
    summary = (q.get("summary_for_lead") or q.get("question") or "")[:100]
    options = ",".join(str(o) for o in (q.get("options") or []))[:80]
    if q.get("escalated"):
        events.append(f"QUESTION_ESCALATED {q.get('task_id', '?')} qid={q.get('qid', '?')} age={q.get('age_seconds', '?')}s options={options} \"{summary}\"")
    else:
        events.append(f"QUESTION {q.get('task_id', '?')} qid={q.get('qid', '?')} options={options} \"{summary}\"")
for st in (d.get("dead") or []):
    reasons = "; ".join(st.get("reasons", []))[:100]
    events.append(f"DEAD {st.get('task_id', '?')} {reasons}")
for item in (d.get("degraded") or []):
    events.append(f"DEGRADED {item.get('task_id', '?')} architect_prepass={item.get('reason', '?')} dispatched_raw_mission")
for st in (d.get("stuck") or []):
    reasons = "; ".join(st.get("reasons", []))[:100]
    events.append(f"STUCK {st.get('task_id', '?')} {reasons}")
for tid in (d.get("closed_since_last") or []):
    events.append(f"CLOSED {tid}")

if events:
    with open(log_path, "a", encoding="utf-8") as fh:
        for e in events:
            line = f"{now} [SUPERVISE-URGENT] {e}"
            if len(line.encode("utf-8")) > 220:
                line = line[:217] + "..."
            fh.write(line + "\n")

# TRUTH_RED → dedupe candidates (stdout). value = severity (semantic, stable
# while the breach holds; NOT the summary/timestamp which would churn).
for b in (d.get("truth_breaches") or []):
    bid = str(b.get("id", "?"))
    sev = str(b.get("severity", "?"))
    summary = str(b.get("summary", ""))[:80]
    line = f"{now} [SUPERVISE-URGENT] TRUTH_RED {bid} {sev} {summary}"
    if len(line.encode("utf-8")) > 220:
        line = line[:217] + "..."
    sys.stdout.write(f"truth_red:{bid}\t{sev}\t{line}\n")
PYEV
)"
  [[ -z "$alarm_rows" ]] || printf '%s\n' "$alarm_rows" | leadv2_alarm_filter >>"$LOG_FILE"
}

_render_pulse() {
  local pulse_json="$1"
  # Pulse table → log directly. TRUTH_RED → stdout dedupe candidates. This is
  # the AUTHORITATIVE truth-probe cadence (truth_probe==checked only here), so
  # the wrapper sweeps the truth_red keyspace: a breach that disappears is
  # CLEARed so a later re-breach fires again (item 5 recovery edge, A5).
  # First stdout line `#PROBE <checked|unchecked>` tells the wrapper whether to
  # sweep (never sweep an unchecked probe — it would clear active breaches).
  local raw
  raw="$(python3 - "$pulse_json" "$ACTIVE_YAML" "$LOG_FILE" <<'PYPULSE'
import json, sys, os, datetime

pulse_str, active_yaml_path, log_path = sys.argv[1:4]
try:
    d = json.loads(pulse_str)
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)

probe_checked = (d.get("truth_probe") == "checked")
print(f"#PROBE {'checked' if probe_checked else 'unchecked'}")

table = d.get("table") or []
stuck_ids = {st.get("task_id") for st in (d.get("stuck") or [])}
dead_ids = {st.get("task_id") for st in (d.get("dead") or [])}
waiting_ids = {q.get("task_id") for q in (d.get("requires_founder") or d.get("questions") or [])}

receipts_by_task = {}
try:
    import yaml
    with open(active_yaml_path, encoding="utf-8") as fh:
        ay = yaml.safe_load(fh) or {}
    for s in (ay.get("sessions") or []):
        receipts_by_task[s.get("task_id")] = s.get("provider_receipts") or []
except Exception:
    pass

def receipt_proof(receipts, provider):
    for r in receipts:
        if not isinstance(r, dict) or r.get("provider") != provider:
            continue
        jid = r.get("job_id") or r.get("run_id")
        art = r.get("artifact_path")
        if jid and art:
            return f"{str(jid)[:8]}@{os.path.basename(str(art))}"
    return "-"

lines = []
for row in table:
    tid = row.get("task_id", "?")
    phase = row.get("phase", "?")
    age = row.get("minutes_in_phase", "?")
    if tid in waiting_ids:
        state = "waiting"
    elif tid in stuck_ids:
        state = "stuck"
    else:
        state = "ok"
    receipts = receipts_by_task.get(tid, [])
    cx = receipt_proof(receipts, "codex")
    glm = receipt_proof(receipts, "glm")
    line = f"{tid} {phase} {age}m {state} cx={cx} glm={glm}"
    if len(line.encode("utf-8")) > 180:
        line = line[:177] + "..."
    lines.append(line)

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
with open(log_path, "a", encoding="utf-8") as fh:
    fh.write(f"--- pulse {now} ({len(lines)} lane(s)) ---\n")
    for ln in lines:
        fh.write(ln + "\n")

# TRUTH_RED → dedupe candidates (stdout). value = severity (semantic, stable
# while the breach holds). Emitted only when the probe actually ran.
if probe_checked:
    for b in (d.get("truth_breaches") or []):
        bid = str(b.get("id", "?"))
        sev = str(b.get("severity", "?"))
        summary = str(b.get("summary", ""))[:80]
        line = f"{now} [SUPERVISE-URGENT] TRUTH_RED {bid} {sev} {summary}"
        if len(line.encode("utf-8")) > 220:
            line = line[:217] + "..."
        sys.stdout.write(f"truth_red:{bid}\t{sev}\t{line}\n")
PYPULSE
)"
  [[ -z "$raw" ]] && return 0
  local probe_status rest
  probe_status="$(printf '%s\n' "$raw" | sed -n '1p' | sed -n 's/^#PROBE //p')"
  rest="$(printf '%s\n' "$raw" | tail -n +2)"
  local cyc="${PULSE_CYCLE:-$(date +%s)}"
  if [[ "$probe_status" == "checked" ]]; then
    [[ -n "$rest" ]] && printf '%s\n' "$rest" | leadv2_alarm_filter_seen truth_red "$cyc" >>"$LOG_FILE"
    # ALWAYS sweep on a checked probe — a breach that disappeared must CLEAR so
    # a re-breach fires again (item 5 recovery edge, A5).
    leadv2_alarm_sweep truth_red "$cyc"
  else
    [[ -n "$rest" ]] && printf '%s\n' "$rest" | leadv2_alarm_filter >>"$LOG_FILE"
  fi
}

# EFFICIENCY-TUNE-01 C: scans /tmp/leadv2-job-registry/*/<job_id> entries
# (written by codex-task.sh / glm-coder.sh at spawn, cleared at their own
# completion point) for entries whose run_dir falls under this project.
# Presence + age >= JOB_STALL_MIN seconds -> URGENT stalled line; an entry seen last
# tick but gone now -> DONE line (best-effort progress.log tail).
# lean: codex --background dispatches clear their registry entry immediately
# after parsing jobId (codex-task.sh's own comment, not real job completion),
# and codex's registry line's run_dir field is the spawning cwd, not a
# per-job dir -- codex DONE/URGENT here only reflects synchronous/--wait
# invocations, with a generic "completed" DONE summary (no progress.log to
# tail); true background-job completion stays tracked via codex-guard.sh's
# jobId watch. glm-coder.sh's run_dir IS the real per-job dir and tails
# cleanly. upgrade when codex-task.sh's companion writes a per-job run_dir
# into the registry line instead of $PWD.
_render_job_registry() {
  local alarm_rows
  # DONE lines → log directly (progress, not noisy). JOB_STALLED → stdout dedupe
  # candidates (item 5) so a job stalled across many pulses alarms once; when it
  # completes (registry entry gone) the sweep CLEARs it so a re-stall re-fires.
  alarm_rows="$(python3 - "$JOB_REG_ROOT" "$JOB_REG_SEEN" "$PROJECT_ROOT" "$JOB_STALL_MIN" "$LOG_FILE" <<'PYJOBS'
import sys, os, json, glob, datetime, tempfile

reg_root, seen_path, project_root, stall_min_s, log_path = sys.argv[1:6]
stall_min = float(stall_min_s)
now = datetime.datetime.now(datetime.timezone.utc)

try:
    with open(seen_path, encoding="utf-8") as fh:
        seen = json.load(fh) or {}
except Exception:
    seen = {}

current = {}
for path in glob.glob(os.path.join(reg_root, "*", "*")):
    job_id = os.path.basename(path)
    try:
        with open(path, encoding="utf-8") as fh:
            line = fh.readline().rstrip("\n")
        run_dir, started_at, kind = line.split("\t", 2)
    except Exception:
        continue
    if not run_dir.startswith(project_root):
        continue
    try:
        mtime = datetime.datetime.fromtimestamp(os.path.getmtime(path), tz=datetime.timezone.utc)
    except Exception:
        mtime = now
    current[job_id] = {"run_dir": run_dir, "started_at": started_at, "kind": kind}
    age_s = (now - mtime).total_seconds()
    if age_s >= stall_min:
        now_s = now.strftime("%Y-%m-%dT%H:%M:%SZ")
        line_out = f"{now_s} [SUPERVISE-URGENT] JOB_STALLED {kind} job={job_id} age={int(age_s)}s"
        # → dedupe candidate (stdout). value = kind (stable while stalled).
        sys.stdout.write(f"job_stalled:{job_id}\t{kind}\t{line_out[:220]}\n")

for job_id, meta in seen.items():
    if job_id in current:
        continue
    run_dir = meta.get("run_dir", "")
    kind = meta.get("kind", "?")
    tail = ""
    try:
        with open(os.path.join(run_dir, "progress.log"), encoding="utf-8") as fh:
            lines = [ln.rstrip("\n") for ln in fh if ln.strip()]
        tail = lines[-1][:80] if lines else ""
    except Exception:
        tail = ""
    now_s = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    line_out = f"{now_s} [supervise-loop] DONE {kind} job={job_id} {tail or 'completed'}"
    with open(log_path, "a", encoding="utf-8") as fh:
        fh.write(line_out[:220] + "\n")

os.makedirs(os.path.dirname(seen_path) or ".", exist_ok=True)
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(seen_path) or ".", suffix=".tmp")
with os.fdopen(tmp_fd, "w", encoding="utf-8") as fh:
    json.dump(current, fh)
os.replace(tmp_path, seen_path)
PYJOBS
)"
  local cyc="${PULSE_CYCLE:-$(date +%s)}"
  [[ -z "$alarm_rows" ]] || printf '%s\n' "$alarm_rows" | leadv2_alarm_filter_seen job_stalled "$cyc" >>"$LOG_FILE"
  # ALWAYS sweep — a job that completed (registry entry gone) must CLEAR so a
  # later re-stall re-fires (item 5 recovery edge).
  leadv2_alarm_sweep job_stalled "$cyc"
}

# ── Item 6: dead-without-deliverable terminal check ────────────────────────
# Run on the PULSE tick (not the 5s poll — it costs a git log per lane). Fires
# one LANE_DEAD_NO_ARTIFACT <task_id> URGENT when ALL four hold:
#   1. lane process gone — lane-liveness verdict dead:* (NEVER a hand-rolled
#      PID check; that duplication is called out in the tail script's comments)
#   2. recorded result is success — dead:provider_{completed,done} (not a
#      crash/timeout shape like dead:silent_*/dead:wedged/failed/cancelled)
#   3. no deliverable file under docs/handoff/<TASK_ID>/ (build-report.md /
#      *-report.md)
#   4. no commit on its branch beyond the fork point (rev-list count == 0)
# Deduped via item 5, key lane_no_artifact:<task_id>, value = branch head sha
# (a lane that later commits transitions and stops alarming). Placed in the
# LOOP, not in leadv2-supervise.sh, so supervise.sh's JSON contract is intact.
_render_terminal_check() {
  local liveness_json alarm_rows
  liveness_json="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-lane-liveness.sh" --json --all --no-codex 2>/dev/null || true)"
  [[ -n "$liveness_json" ]] || return 0
  alarm_rows="$(PROJECT_ROOT="$PROJECT_ROOT" python3 - "$liveness_json" "$ACTIVE_YAML" "$PROJECT_ROOT" "$LOG_FILE" <<'PYTC'
import sys, os, json, subprocess, datetime

liveness_str, active_yaml_path, project_root, log_path = sys.argv[1:5]
try:
    liv = json.loads(liveness_str)
except Exception:
    sys.exit(0)
lanes = (liv or {}).get("lanes") or []
if not lanes:
    sys.exit(0)

# branch/worktree per task_id from active.yaml
meta_by_task = {}
try:
    import yaml
    with open(active_yaml_path, encoding="utf-8") as fh:
        ay = yaml.safe_load(fh) or {}
    for s in (ay.get("sessions") or []):
        tid = s.get("task_id")
        if tid:
            meta_by_task[tid] = {"branch": s.get("branch"), "worktree": s.get("worktree")}
except Exception:
    pass

SUCCESS_VERDICTS = ("dead:provider_completed", "dead:provider_done")

def deliverable_present(task_id):
    d = os.path.join(project_root, "docs", "handoff", task_id)
    if not os.path.isdir(d):
        return False
    for name in os.listdir(d):
        if name == "build-report.md" or name.endswith("-report.md") or name == "report.md":
            return True
    return False

def commits_beyond_fork(branch, worktree):
    # rev-list --count <base>..<branch>; base = merge-base with main. Returns
    # (ok, count). On any resolution failure ok=False (skip the alarm rather
    # than false-fire — a missing main must not invent a dead lane).
    if not branch or not worktree or not os.path.isdir(worktree):
        return False, 0
    git = ["git", "-C", worktree]
    try:
        base = subprocess.run(git + ["merge-base", branch, "main"],
                              capture_output=True, text=True, timeout=10)
        if base.returncode != 0 or not base.stdout.strip():
            return False, 0
        cnt = subprocess.run(git + ["rev-list", "--count", base.stdout.strip() + ".." + branch],
                             capture_output=True, text=True, timeout=10)
        if cnt.returncode != 0:
            return False, 0
        return True, int((cnt.stdout or "0").strip() or "0")
    except Exception:
        return False, 0

def head_sha(branch, worktree):
    if not branch or not worktree:
        return "?"
    try:
        r = subprocess.run(["git", "-C", worktree, "rev-parse", branch],
                           capture_output=True, text=True, timeout=10)
        return (r.stdout or "?").strip()[:12] if r.returncode == 0 else "?"
    except Exception:
        return "?"

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
for row in lanes:
    tid = row.get("lane") or row.get("task_id")
    verdict = str(row.get("verdict") or "")
    if not verdict.startswith("dead:"):
        continue
    if verdict not in SUCCESS_VERDICTS:
        continue  # crash/timeout/abandoned — not a "success" end
    if deliverable_present(tid):
        continue
    m = meta_by_task.get(tid) or {}
    ok, count = commits_beyond_fork(m.get("branch"), m.get("worktree"))
    if not ok:
        continue        # could not verify — never false-fire
    if count > 0:
        continue        # branch has commits → there IS an artifact
    sha = head_sha(m.get("branch"), m.get("worktree"))
    line = f"{now} [SUPERVISE-URGENT] LANE_DEAD_NO_ARTIFACT {tid} branch={m.get('branch','?')} sha={sha}"
    sys.stdout.write(f"lane_no_artifact:{tid}\t{sha}\t{line[:220]}\n")
PYTC
)"
  local cyc="${PULSE_CYCLE:-$(date +%s)}"
  [[ -z "$alarm_rows" ]] || printf '%s\n' "$alarm_rows" | leadv2_alarm_filter_seen lane_no_artifact "$cyc" >>"$LOG_FILE"
  # ALWAYS sweep — a lane that later commits / gains a deliverable must CLEAR
  # so a future dead-no-artifact re-fires (item 5 recovery edge).
  leadv2_alarm_sweep lane_no_artifact "$cyc"
}

LAST_PULSE_EPOCH=0
LAST_BROAD_STATUS_EPOCH=$(date +%s)
if [[ "${LEADV2_SUPERVISE_LOOP_PULSE_ON_START:-0}" == "1" ]]; then
  LAST_PULSE_EPOCH=0
  LAST_BROAD_STATUS_EPOCH=0
else
  LAST_PULSE_EPOCH=$(date +%s)
fi
CYCLE=0

while true; do
  CYCLE=$((CYCLE + 1))
  # Item 2 heartbeat: written FIRST, before the supervise.sh call, so a hang
  # inside that call shows up as heartbeat staleness (the watchdog's signal).
  _write_heartbeat "$CYCLE"
  RC=0
  OUT="$("$SUPERVISE_SH" --json --since loop 2>/dev/null)" || RC=$?
  if [[ "$RC" -ne 0 ]]; then
    printf -- '%s [supervise-loop] URGENT root_error rc=%s: %s\n' \
      "$(_now_iso)" "$RC" "$(printf -- '%s' "$OUT" | tr '\n' ' ' | cut -c1-180)" >>"$LOG_FILE"
  else
    _render_events "$OUT"
    _run_pump_on_close "$OUT"
  fi

  NOW_EPOCH=$(date +%s)
  if (( NOW_EPOCH - LAST_PULSE_EPOCH >= PULSE_S )); then
    RC=0
    PULSE_JSON="$("$SUPERVISE_SH" --json 2>/dev/null)" || RC=$?
    if [[ "$RC" -eq 0 ]]; then
      _render_pulse "$PULSE_JSON"
    fi
    _render_job_registry
    _render_terminal_check        # item 6 — pulse cadence only (git log per lane)
    LAST_PULSE_EPOCH=$NOW_EPOCH
  fi

  # The supervisor never reads or composes this status: the helper gathers
  # facts and makes one cheap model call, then writes a finished block here.
  # PULSE-IS-A-PLUGIN-DUTY-01: (C2) the backlog pump runs BEFORE the composer
  # and its dispatched count is exported into the beat, so "a pulse dispatches
  # before it reports" is a code-enforced, after-the-fact auditable order —
  # not an instruction. (C1) the composer emits one URGENT-tagged
  # BROAD_STATUS_READY line per beat (the delivery contract); a beat that
  # cannot compose still wakes via _emit_broad_status_degraded.
  if [[ "$BROAD_STATUS_S" =~ ^[0-9]+$ ]] && (( BROAD_STATUS_S > 0 )) \
      && (( NOW_EPOCH - LAST_BROAD_STATUS_EPOCH >= BROAD_STATUS_S )); then
    export LEADV2_BROAD_STATUS_DISPATCHED="unavailable"
    if [[ "${LEADV2_BACKLOG_PUMP:-1}" == "1" && -x "$PUMP_SH" ]]; then
      _BS_PUMP_OUT="$(bash "$PUMP_SH" check 2>&1)" || true
      [[ -z "$_BS_PUMP_OUT" ]] || printf '%s\n' "$_BS_PUMP_OUT" >>"$LOG_FILE"
      # Parse the pump's own "check complete:" summary; absent summary →
      # "unavailable", never 0 (a fabricated "ran and dispatched nothing").
      export LEADV2_BROAD_STATUS_DISPATCHED="$(printf '%s\n' "$_BS_PUMP_OUT" \
        | sed -n 's/.*check complete:.*dispatched=\([0-9][0-9]*\).*/\1/p' | tail -n1)"
      [[ -n "${LEADV2_BROAD_STATUS_DISPATCHED}" ]] || export LEADV2_BROAD_STATUS_DISPATCHED="unavailable"
    fi
    if [[ -x "$BROAD_STATUS_SH" ]]; then
      if bash "$BROAD_STATUS_SH" >>"$LOG_FILE" 2>&1; then
        :
      else
        printf -- '%s [BROAD_STATUS] failure: quality read unavailable\n' "$(_now_iso)" >>"$LOG_FILE"
        _emit_broad_status_degraded "composer_rc_nonzero"
      fi
    else
      printf -- '%s [BROAD_STATUS] failure: composer unavailable; quality read unavailable\n' "$(_now_iso)" >>"$LOG_FILE"
      _emit_broad_status_degraded "composer_missing"
    fi
    unset LEADV2_BROAD_STATUS_DISPATCHED
    LAST_BROAD_STATUS_EPOCH=$NOW_EPOCH
  fi

  if [[ "$MAX_CYCLES" -gt 0 && "$CYCLE" -ge "$MAX_CYCLES" ]]; then
    printf -- '%s [supervise-loop] max-cycles=%s reached — exiting (test mode)\n' "$(_now_iso)" "$MAX_CYCLES" >>"$LOG_FILE"
    exit 0
  fi

  sleep "$EVENT_POLL_S"
done
