#!/usr/bin/env bash
# plugins/leadv2/scripts/anti-silence-pulse.sh — ANTI-SILENCE-HEARTBEAT-01
# ONE-STATUS-MECHANISM-01 (founder order 2026-09-12: «надо 1 рабочий
# механизм»): this file in the plugin tree is THE canonical status
# mechanism — the single-lead beat / broad-status chain is deleted, repo
# copies of this script are symlinks to this one (same inode doctrine as
# every other plugin-owned script).
#
# A 30-minute pulse the lead cannot forget to arm. Not a hook (hooks cannot
# arm a Monitor — see docs/handoff/dispatch-4c26a8f5/context.yaml D1). This
# script is armed by the LEAD's own Bash(run_in_background=true) call
# (D2), watched by the lead's own Monitor on its stdout.
#
# Every ~30 minutes (or immediately in --once mode) prints ONE line to
# stdout AND appends it to the log:
#   [ПУЛЬС HH:MMZ] <task_id>=<age>m [STALL|ПРИЗРАК?]; ...   (board non-empty)
#   [ПУЛЬС HH:MMZ] линий нет                                (board empty)
#   [ПУЛЬС] сбор не удался: <reason>                        (collection error)
#
# PULSE-WORTH-READING (founder 2026-09-09: «стоит писать арм, сложность
# задачи... хоть короткое описание что за задача»): every rendered live row
# carries WHAT the lane is (a clipped mission-title clause, ground truth
# from the worker own transcript + the mission file in the worktree) and
# HOW it runs (arm/model and class from the lane journal route rows) — each
# field omitted when its source is absent, never guessed. The AGENT path
# additionally suppresses itself when there is genuinely nothing to say
# (no rendered rows AND no ghosts): it prints the single marker line
#   __ANTI_SILENCE_NOTHING__ [<project> HH:MMZ] живых линий нет, отправка подавлена
# and anti-silence-agent.sh skips the Telegram send for it (founder:
# «если ничего нет в работе то ничего и не надо писать»). The in-session
# board path KEEPS its «live=0 — тишина» line: its only consumer is the
# lead Monitor, which must hear the loop speak — a pulse that never speaks
# is the failure this repo already had.
#
# Age thresholds (D5 — deliberately looser than, and reported separately
# from, leadv2-lane-liveness.sh's own 15min SILENT_MAX):
#   <=30min  live
#   30-60min STALL
#   >60min   ПРИЗРАК? — excluded from the live count. SWEEPER-FALSE-LIFE
#            (2026-09-09): leadv2-lane-liveness.sh --all --json is not a
#            cross-check footnote anymore — a lane the probe calls alive IS
#            live evidence (a process for the lane), rendered as a • row.
#
# --once [--now=EPOCH]  deterministic single-beat mode for tests: skips the
#                        sleep loop and the PID-file write, computes exactly
#                        one beat using EPOCH (default: current time) as
#                        "now", prints it, appends to the log, exits 0.
#
# --sid=<session>       INTERNAL — written by the self re-exec below, never
#                        by a caller. In loop mode the process re-execs once
#                        so its argv carries the session key from the marker
#                        file name; the arming dedup then finds THIS session's
#                        live pulse by a strict argv match instead of by a
#                        pid file (PULSE-ARMS-WITHOUT-A-PIDFILE-AND-ACCUMULATES-01:
#                        measured 2026-09-06T12:15Z — 18 pulse processes, 5
#                        pid files, 13 invisible to both reaper passes; the
#                        lead's own session armed twice after the hook said
#                        "not armed" because the marker was gone while the
#                        pulse was alive). Marker files that carry no session
#                        key (the bare default name) keep the legacy
#                        pid-file-only path unchanged.
#
# Env overrides (all default to the real repo paths; used by
# tests/unit/test-anti-silence-pulse.sh to point at fixtures):
#   CLAUDE_PROJECT_DIR           session root; when absent, derived from script
#   ACTIVE_YAML                  docs/leadv2/active.yaml
#   TASKS_DIR                    docs/leadv2/tasks
#   PULSE_PID_FILE               docs/leadv2/anti-silence-pulse.pid
#   PULSE_LOG_FILE               docs/leadv2/anti-silence-pulse.log
#   LEADV2_LANE_LIVENESS_SCRIPT  .claude/scripts/leadv2-lane-liveness.sh
#   LEADV2_ANTI_SILENCE_INTERVAL_S  1800  (D7 — LEADV2_* prefix, this is
#                                          lead-tooling state, not a PE_* flag)
#   ANTI_SILENCE_GLM_RUNS_DIR     ~/.claude/cache/glm-runs (worker run dirs)
#   ANTI_SILENCE_GLM_SNAPSHOT     <glm-runs>/.anti-silence-pulse-journal-sizes.tsv
#                                 GLM-JOURNAL-GROWTH-IS-LIFE: persistent
#                                 journal.jsonl size baseline — a run whose
#                                 journal GREW since the previous tick is a
#                                 LIVE worker, never «живость не доказана».
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Hooks and the pulse must use the same session root.  Falling back to the
# repository containing this script keeps direct CLI use useful without making
# PROJECT_ROOT a competing source of truth.
CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
PROJECT_ROOT="$CLAUDE_PROJECT_DIR"

# Captured BEFORE the defaults below fill the variables: did the CALLER pin
# the board (ACTIVE_YAML / TASKS_DIR)? A pinned caller is a fixture world
# (tests) or a composition with its own board answer (the outside agent) —
# and the canonical state-store tier must not reach OUT of that world into
# the real machine state store (measured 2026-09-08: the guard suite pins a
# 2024 clock and a fixture TASKS_DIR, the canonical tier found a same-named
# REAL journal from the live store, and the beat rendered a clamped 0m age).
# Default-armed pulses (the lead arming from a checkout) keep the tier ON —
# that is the production fix; the agent forces it on explicitly as well.
_AS_BOARD_PINNED=0
if [[ -n "${ACTIVE_YAML:-}" || -n "${TASKS_DIR:-}" ]]; then
  _AS_BOARD_PINNED=1
fi
export _AS_BOARD_PINNED

ACTIVE_YAML="${ACTIVE_YAML:-${PROJECT_ROOT}/docs/leadv2/active.yaml}"
TASKS_DIR="${TASKS_DIR:-${PROJECT_ROOT}/docs/leadv2/tasks}"

# ANTI-SILENCE-MUST-LIVE-OUTSIDE-THE-SESSION-01 (content truth, 2026-09-08):
# when this pulse is armed from a WORKTREE (every dispatched session is),
# PROJECT_ROOT is the worktree and the repo-side board copies under it are
# the stale per-worktree git copies — measured 2026-09-08: every worktree
# copy of docs/leadv2/{active.yaml,tasks} trails the main checkout, so a
# beat composed from them reported `live=0: <lane>=нет-журнала` while the
# named lane had 3 commits and 492 insertions in its worktree at that exact
# moment. The main checkout's copies are strictly fresher, so when the
# caller did NOT pin the env explicitly (tests and the outside agent always
# pin them) the defaults are re-pointed at the MAIN checkout and its
# active.yaml is additionally read as a second board view. Explicit env
# always wins untouched — this block is dormant for every pinned caller.
if [[ -z "${ACTIVE_YAML:-}" || -z "${TASKS_DIR:-}" ]]; then
  # ONE-STATUS-MECHANISM-01: the main checkout to re-point at is the one of
  # the SESSION repo (CLAUDE_PROJECT_DIR), not of the tree this script
  # happens to live in — run from the plugin tree, SCRIPT_DIR git repo is
  # leadv2 and the repoint would read the leadv2 board for a persona-engine
  # session.
  _as_main_root="$(git -C "${PROJECT_ROOT}" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
  [[ -n "${_as_main_root}" ]] || _as_main_root="${PROJECT_ROOT}"
  if [[ -z "${TASKS_DIR:-}" && "${_as_main_root}" != "${PROJECT_ROOT}" ]]; then
    TASKS_DIR="${_as_main_root}/docs/leadv2/tasks"
  fi
  if [[ -z "${ACTIVE_YAML:-}" ]]; then
    ACTIVE_YAML="${PROJECT_ROOT}/docs/leadv2/active.yaml"
    if [[ "${_as_main_root}" != "${PROJECT_ROOT}" ]]; then
      ANTI_SILENCE_EXTRA_ACTIVE_YAML="${_as_main_root}/docs/leadv2/active.yaml"
      export ANTI_SILENCE_EXTRA_ACTIVE_YAML
    fi
  fi
fi
PULSE_PID_FILE="${PULSE_PID_FILE:-${PROJECT_ROOT}/docs/leadv2/anti-silence-pulse.pid}"
PULSE_LOG_FILE="${PULSE_LOG_FILE:-${PROJECT_ROOT}/docs/leadv2/anti-silence-pulse.log}"
# H1 (round 5): this heartbeat detects a WEDGED OR DEAD loop -- a live PID
# whose stamp has gone stale (older than one interval + slack) -- nothing
# more. It CANNOT detect a detached Monitor sitting on top of a healthy loop:
# _stamp_heartbeat is called by the loop itself right after _beat returns, so
# a perfectly healthy loop keeps stamping fresh even when nothing is watching
# its stdout. Only the receiving side (the lead, re-attaching its Monitor)
# can prove delivery; nothing inside this script can. This file is
# re-stamped with the current epoch at arm time and after every beat; the
# hooks alert on a live PID whose stamp has gone stale instead of trusting
# PID-aliveness alone -- that is the whole and only guarantee.
PULSE_HEARTBEAT_FILE="${PULSE_HEARTBEAT_FILE:-${PROJECT_ROOT}/docs/leadv2/anti-silence-pulse.heartbeat}"
LEADV2_LANE_LIVENESS_SCRIPT="${LEADV2_LANE_LIVENESS_SCRIPT:-${PROJECT_ROOT}/.claude/scripts/leadv2-lane-liveness.sh}"
# ONE-STATUS-MECHANISM-01: plugin-canonical home — run from the plugin tree
# the repo-side default does not exist, and the liveness probe lives one
# directory over, next to this script (same fallback shape as the
# journal-address lib below).
[[ -f "${LEADV2_LANE_LIVENESS_SCRIPT}" ]] || LEADV2_LANE_LIVENESS_SCRIPT="${SCRIPT_DIR}/leadv2-lane-liveness.sh"
# MONITORS-ARE-THE-SECOND-CONSUMER-OF-THE-ADDRESS-RESOLVER-01: the tiered
# journal-address algorithm below now IMPORTS this module instead of
# defining its own copy of it -- lib/leadv2-journal-address.py is the single
# source, shared with any other lane-journal consumer (leadv2-lane-watch.sh).
LEADV2_JOURNAL_ADDRESS_LIB="${LEADV2_JOURNAL_ADDRESS_LIB:-${PROJECT_ROOT}/.claude/leadv2/scripts/lib/leadv2-journal-address.py}"
[[ -f "${LEADV2_JOURNAL_ADDRESS_LIB}" ]] || LEADV2_JOURNAL_ADDRESS_LIB="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-journal-address.py"
# ANTI-SILENCE-MUST-LIVE-OUTSIDE-THE-SESSION-01: the CANONICAL journal
# address oracle. Lane journals are written by leadv2-journal.sh into
# ~/.claude/leadv2-state/<repo>/tasks/<id>/journal.md — a path NO repo-side
# glue can produce (the pre-fix resolver only ever looked at repo checkouts,
# which is exactly how the beat said нет-журнала for journals that existed).
# The collector asks the writer's own CLI for the address instead; overridable
# only so tests can point at fixtures, same seam shape as every other env here.
LEADV2_JOURNAL_CLI="${LEADV2_JOURNAL_CLI:-$(dirname "$(dirname "${LEADV2_JOURNAL_ADDRESS_LIB}")")/leadv2-journal.sh}"
INTERVAL_S="${LEADV2_ANTI_SILENCE_INTERVAL_S:-1800}"
HEARTBEAT_SLACK_S="${LEADV2_ANTI_SILENCE_HEARTBEAT_SLACK_S:-300}"

ONCE=0
NOW_OVERRIDE=""
ARM_SID_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) ONCE=1; shift ;;
    --now=*) NOW_OVERRIDE="${1#--now=}"; shift ;;
    --sid=*) ARM_SID_ARG="${1#--sid=}"; shift ;;
    *) printf '[anti-silence-pulse] unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# ── PULSE-ARMS-WITHOUT-A-PIDFILE-AND-ACCUMULATES-01 ─────────────────────
# Fix 2, step 1: put the session key INTO argv. The dedup below must find
# THIS session's live pulse even when every marker file is gone — a pid file
# is the thing that went missing (13 of 18 live pulses had none), and the
# environment is not visible in `ps` output on every platform we run on.
# argv is. So a loop-mode arm whose marker file name carries a session key
# re-execs itself once with --sid=<key>: same PID, same parent, same env —
# only the visible argv changes. A marker name without a session key (the
# bare default, and every pre-hook legacy shape) never re-execs and keeps
# the pid-file-only behaviour of old.
SCRIPT_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
_session_key_from_marker_name() {
  # Session key from the BASE pid-marker file NAME: anti-silence-pulse.<sid>
  # [.instance-key].pid — first dot-field after the prefix. Same derivation
  # the owner-belt lane (758ba844d) uses; kept as its own function so the
  # two lanes' hunks stay textually independent.
  local b
  b="$(basename "${PULSE_PID_FILE}")"
  b="${b%.pid}"
  b="${b#anti-silence-pulse.}"
  printf '%s' "${b%%.*}"
}
_ARM_SID="${ARM_SID_ARG:-$(_session_key_from_marker_name)}"
if [[ "$ONCE" -eq 0 && -z "$ARM_SID_ARG" ]] \
   && [[ "$_ARM_SID" =~ ^[0-9a-fA-F-]{8,}$ ]]; then
  exec "${BASH:-bash}" "$SCRIPT_PATH" "--sid=${_ARM_SID}"
fi

mkdir -p "$(dirname "$PULSE_LOG_FILE")" "$(dirname "$PULSE_PID_FILE")" "$(dirname "$PULSE_HEARTBEAT_FILE")"

# H3 (round 5): the interval is written HERE, alongside the stamp, so
# whoever reads the file later (this process, a takeover armer, or a hook
# in a different process) uses the interval the loop was actually armed
# with -- not whatever LEADV2_ANTI_SILENCE_INTERVAL_S happens to resolve to
# in the reader's own environment, which can silently differ from the
# armer's (two independent processes, two independent env resolutions).
# PULSE-ARMS-WITHOUT-A-PIDFILE-AND-ACCUMULATES-01, fix 1: the pid marker is
# MAINTAINED, not written once. A pulse can outlive its marker — the
# worktree gets swept, the file gets deleted, the directory gets recreated —
# and a marker written only at arm time leaves the process invisible to
# everything that reads markers (measured 2026-09-06T12:15Z: 5 pid files
# for 18 live pulses). Every beat re-asserts pid+birth when the marker no
# longer names THIS process, so marker-side invisibility cannot recur.
# Called from _stamp_heartbeat — the loop's existing per-beat marker hook —
# so the while-loop body below stays byte-identical to the merge baseline
# shared with the owner-belt lane (758ba844d, worktree-f0a4d555f761).
# --once mode is exempt: its contract is "no PID-file write" (see header),
# and this guard keeps that true.
_reassert_marker() {
  [[ "$ONCE" -eq 0 ]] || return 0
  local cur=""
  [[ -f "$PULSE_PID_FILE" ]] && cur="$(cat "$PULSE_PID_FILE" 2>/dev/null || true)"
  if [[ "$cur" != "$$" ]]; then
    printf '%s\n' "$$" >"$PULSE_PID_FILE" 2>/dev/null || true
    _write_birth
  fi
}

_stamp_heartbeat() {
  printf '%s %s\n' "$(date +%s)" "$INTERVAL_S" >"$PULSE_HEARTBEAT_FILE" 2>/dev/null || true
  _reassert_marker
}

_beat() {
  local now="$1"
  local line
  if ! line="$(
    ACTIVE_YAML="$ACTIVE_YAML" TASKS_DIR="$TASKS_DIR" NOW="$now" \
    LEADV2_LANE_LIVENESS_SCRIPT="$LEADV2_LANE_LIVENESS_SCRIPT" \
    PROJECT_ROOT="$PROJECT_ROOT" \
    LEADV2_JOURNAL_ADDRESS_LIB="$LEADV2_JOURNAL_ADDRESS_LIB" \
    LEADV2_JOURNAL_CLI="$LEADV2_JOURNAL_CLI" \
    _AS_BOARD_PINNED="${_AS_BOARD_PINNED}" \
    python3 - <<'PYEOF' 2>>"${PULSE_LOG_FILE}.stderr"
import datetime, importlib.util, json, os, re, subprocess

_ja_lib = os.environ.get("LEADV2_JOURNAL_ADDRESS_LIB", "")
_ja_spec = importlib.util.spec_from_file_location("_leadv2_journal_address", _ja_lib)
journal_address = importlib.util.module_from_spec(_ja_spec)
_ja_spec.loader.exec_module(journal_address)

active_yaml = os.environ["ACTIVE_YAML"]
tasks_dir = os.environ["TASKS_DIR"]
now = int(os.environ["NOW"])
liveness_script = os.environ.get("LEADV2_LANE_LIVENESS_SCRIPT", "")
project_root = os.environ.get("PROJECT_ROOT", "")

hhmm = datetime.datetime.utcfromtimestamp(now).strftime("%H:%M")
# One pulse per project (founder order 2026-09-08): the outside agent passes
# ANTI_SILENCE_BEAT_PREFIX so every delivered message names its project at a
# glance — the chosen per-project mechanism (a [<project>] prefix in the ONE
# General topic) instead of per-project forum topics, which would mutate the
# founder channel during the build. The in-session default stays ПУЛЬС.
beat_prefix = (os.environ.get("ANTI_SILENCE_BEAT_PREFIX") or "ПУЛЬС").strip() or "ПУЛЬС"
stamp = f"[{beat_prefix} {hhmm}Z]"

# ANTI-SILENCE-MUST-LIVE-OUTSIDE-THE-SESSION-01: two session sources.
# (1) ANTI_SILENCE_SESSIONS_JSON — the enumeration by the outside agent
#     (worktrees of the main checkout ∪ live journals in the state store).
#     JSON is deliberately parsed before `import yaml`: the launchd agent
#     runs on /usr/bin/python3 where PyYAML is absent (user-install only),
#     and this path must never depend on an optional module.
# (2) active.yaml (yaml) — the in-session board, unchanged, plus the
#     active.yaml of the main checkout as an extra view from a worktree.
# NOTE: no single quotes anywhere in this heredoc body, not even in prose —
# macOS /bin/bash 3.2 re-scans a quoted heredoc inside $( ) with
# quote-sensitivity, so a stray apostrophe in a comment unbalances the parse
# of the whole script (measured 2026-09-08: main parsed, this body did not,
# and the only difference was prose apostrophes).
sessions_json = (os.environ.get("ANTI_SILENCE_SESSIONS_JSON") or "").strip()
if sessions_json:
    try:
        sessions = json.loads(sessions_json)
    except Exception as exc:
        print(f"[ПУЛЬС] сбор не удался: ANTI_SILENCE_SESSIONS_JSON: {exc}")
        raise SystemExit(0)
    if not isinstance(sessions, list):
        print(f"[ПУЛЬС] сбор не удался: ANTI_SILENCE_SESSIONS_JSON is not a list: {type(sessions)}")
        raise SystemExit(0)
else:
    try:
        import yaml

        def _load_board(path):
            if not os.path.isfile(path):
                return []
            with open(path, encoding="utf-8") as f:
                doc = yaml.safe_load(f) or {}
            rows = doc.get("sessions") or []
            if not isinstance(rows, list):
                raise ValueError(f"active.yaml sessions is not a list: {type(rows)}")
            # TERMINAL-LANES-STILL-READ-AS-LIVE-01: a lane that recorded a
            # terminal outcome (nothing_to_merge, merged, completed, ...) is
            # finished. Its `phase` is frozen at whatever it was, so without
            # this the pulse announced closed lanes as live every half hour --
            # and a repeated false alarm is what makes a real dead lane
            # unnoticeable.
            return [s for s in rows
                    if isinstance(s, dict) and not str(s.get("terminal_status") or "").strip()]

        sessions = _load_board(active_yaml)
        extra_yaml = (os.environ.get("ANTI_SILENCE_EXTRA_ACTIVE_YAML") or "").strip()
        if extra_yaml:
            # Second board view (the active.yaml of the MAIN checkout when
            # this pulse runs from a worktree). Union by (task_id, worktree);
            # a parse failure of the EXTRA view degrades to the primary board
            # only — a failure of the primary file stays loud below.
            try:
                have = {(s.get("task_id"), s.get("worktree")) for s in sessions}
                for s in _load_board(extra_yaml):
                    if (s.get("task_id"), s.get("worktree")) not in have:
                        sessions.append(s)
            except Exception:
                pass
    except Exception as exc:
        print(f"[ПУЛЬС] сбор не удался: {exc}")
        raise SystemExit(0)

if not sessions and not sessions_json:
    # A project (or board) with no lanes at all still states it in one short
    # line — silence is the exact failure this beat exists to kill. The agent
    # path (sessions JSON, possibly an empty list) falls THROUGH to its own
    # renderer below: the state board may still name live lanes the journal
    # enumeration missed, and only the renderer may declare тишина there.
    print(f"{stamp} live=0 — тишина")
    raise SystemExit(0)

live_probe = None
if liveness_script and os.path.isfile(liveness_script):
    try:
        out = subprocess.run(
            [liveness_script, "--all", "--json"],
            capture_output=True, text=True, timeout=10,
        )
        live_probe = json.loads(out.stdout) if out.returncode == 0 else None
    except Exception:
        live_probe = None

def probe_says_alive(task_id):
    """Three-valued probe verdict. SWEEPER-FALSE-LIFE (2026-09-09) promoted
    it from a ghost-aggregate footnote to LIVE evidence: True (the probe says
    a process for this lane is alive) feeds lane_liveness_kind as strong
    «процесс» evidence and renders a • row, False (probe ran and does not
    call the lane alive — dead, silent, starting and child verdicts
    all agree with ghostness), or None (no probe at all — liveness then
    rests on the other worker evidence only). The old «probe считает
    живыми» ghost clause is gone because it is unreachable by construction:
    a True verdict promotes the lane out of the ghost branch before that
    clause could ever fire.
    H2 round 4 note kept: silent:<n> and child are real top-level verdicts
    leadv2-lane-liveness.sh emits; both map to False here, which is exactly
    the pre-round collapse their docstring warned about — deliberate now,
    because the per-row rendering that consumer distinguished them is gone
    (ADDENDUM-2 format: ghosts are one aggregate line, not forty rows)."""
    if live_probe is None:
        return None
    rows = live_probe.get("lanes", []) if isinstance(live_probe, dict) else []
    if not isinstance(rows, list):
        return None
    for row in rows:
        if isinstance(row, dict) and row.get("lane") == task_id:
            return row.get("verdict") in ("live", "alive")
    return False

def state_journal_path(task_id):
    """ANTI-SILENCE-MUST-LIVE-OUTSIDE-THE-SESSION-01: the canonical journal
    address, from leadv2-journal.sh `path` — the oracle the WRITER itself
    uses — never a path glued out of a repo checkout. The glued form is the
    exact defect
    this fixes: 2026-09-08T18:52Z the beat read live=0 / нет-журнала for
    lanes whose journals existed in ~/.claude/leadv2-state the whole time,
    because no repo-side join can name that directory. Empty string when the
    CLI is absent or refuses — the caller then falls through to the
    address-lib resolver, whose repo-side tiers remain unchanged."""
    cli = os.environ.get("LEADV2_JOURNAL_CLI", "")
    if not (cli and os.path.isfile(cli)):
        return ""
    try:
        out = subprocess.run(["bash", cli, "path", task_id],
                             capture_output=True, text=True, timeout=10)
    except Exception:
        return ""
    if out.returncode != 0:
        return ""
    for ln in out.stdout.splitlines():
        if ln.strip():
            return ln.strip()
    return ""


def lane_journal(task_id, dkey, worktree, row, now):
    """THE one place a lane journal address is decided (per-project agent,
    2026-09-08). Tiers, in order: (1) an explicit journal carried by the
    session row itself — the outside agent enumerates each project store
    through the resolver chain and hands the exact path it found, so a
    project with no local checkout (m3-market) is still addressed correctly
    without depending on the CLI cwd ladder; (2) the writer CLI canonical
    tier (state_journal_path above — the in-session oracle); (3) the shared
    address-lib tiers. NC1 of tests/unit/test-anti-silence-survives-a-dead-
    lead.sh mutates the FIRST statement of this body back to a repo-glued
    docs/leadv2/tasks join and the suite must go red: every tier dies at
    once, exactly like the 2026-09-08 defect."""
    explicit = (row or {}).get("journal")
    if isinstance(explicit, str) and explicit and os.path.isfile(explicit):
        return explicit
    if _state_tier_on:
        canonical = state_journal_path(task_id)
        if canonical and os.path.isfile(canonical):
            return canonical
    resolved = journal_address.resolve(tasks_dir, task_id, dkey, worktree, now,
                                       project_root=project_root)
    if resolved and os.path.isfile(resolved):
        return resolved
    return None


def _read_text_bounded(path, limit=262144):
    # PULSE-WORTH-READING: bounded reads for the per-row enrichment — the
    # fd/byte budget that killed the first launchd beat applies to these
    # new consumers too (they run ONLY for rendered rows, <= _MAX_LINES).
    try:
        with open(path, "rb") as f:
            return f.read(limit).decode("utf-8", "replace")
    except OSError:
        return ""


def lane_route_info(jtext):
    """Founder 2026-09-09 («стоит писать арм, сложность задачи»): the arm
    and model a lane RUNS on plus its class/complexity, from the lane own
    journal route rows (route_resolved / model_select_telemetry) — never a
    guess. LAST match wins (a re-dispatch re-stamps the route). Empty per
    field when the journal carries no route row; the renderer then omits
    the field instead of inventing one. class= is preferred over
    complexity= when both exist across rows."""
    arm = model = klass = ""
    if not jtext:
        return arm, model, klass
    for ln in jtext.splitlines():
        if ("route_resolved" not in ln) and ("model_select_telemetry" not in ln):
            continue
        m = re.search(r" arm=([A-Za-z0-9._-]+)", ln)
        if m:
            arm = m.group(1)
        m = re.search(r" model=([A-Za-z0-9._-]+)", ln)
        if m:
            model = m.group(1)
        m = re.search(r" class=([A-Za-z0-9._-]+)", ln)
        if m:
            klass = m.group(1)
        elif not klass:
            m = re.search(r" complexity=([A-Za-z0-9._-]+)", ln)
            if m:
                klass = m.group(1)
    return arm, model, klass


def lane_mission_title(worktree):
    """Founder 2026-09-09 («стоит давать хоть короткое описание что за
    задача»): ONE clause naming the task. Ground truth only — the worker
    own session transcript names its mission file, and the title is that
    file first heading line, read from the worktree copy. Nothing is
    matched by guesswork: no transcript, no mission file or no heading
    means NO description, never a fabricated or neighbour-lane one (a
    wrong description in the founder beat is defect 1 again)."""
    if not (isinstance(worktree, str) and worktree):
        return ""
    import glob as _g
    base = os.path.join(os.path.expanduser("~"), ".claude", "projects")
    rel = ""
    for d in _g.glob(os.path.join(base, "*" + os.path.basename(worktree))):
        if not os.path.isdir(d):
            continue
        jsonls = [p for p in _g.glob(os.path.join(d, "*.jsonl")) if os.path.isfile(p)]
        if not jsonls:
            continue
        newest = max(jsonls, key=lambda p: os.stat(p).st_mtime)
        m = re.search(r"docs/handoff/[A-Za-z0-9._/-]*missions/[A-Za-z0-9._-]+\.md",
                      _read_text_bounded(newest))
        if m:
            rel = m.group(0)
            break
    if not rel:
        return ""
    mpath = os.path.join(worktree, rel)
    if not os.path.isfile(mpath):
        return ""
    m = re.search(r"^# (.+)$", _read_text_bounded(mpath, 8192), re.M)
    if not m:
        return ""
    title = m.group(1).strip()
    if len(title) > 70:
        cut = title[:70].rsplit(" ", 1)[0]
        title = cut + "…"
    return title


def lane_head_fields(desc, arm, model, klass):
    """The mid-segment both render sites append after the lane name: the
    description clause, then the arm/model and class. With no sources the
    result is the empty string and the row renders BYTE-IDENTICAL to the
    pre-2026-09-09 shape — enrichment never changes what an evidence-less
    row says, it only adds what a real source proves."""
    segs = []
    if desc:
        segs.append(desc)
    route = "/".join(x for x in (arm, model) if x)
    bits = []
    if route:
        bits.append(route)
    if klass:
        bits.append("класс " + klass)
    if bits:
        segs.append(", ".join(bits))
    if not segs:
        return ""
    return " — " + " — ".join(segs)


_AS_NOTHING_MARKER = "__ANTI_SILENCE_NOTHING__"


def nothing_to_report(rendered_rows, ghost_count, stamped_count=0):
    """Founder 2026-09-09: «если ничего нет в работе то ничего и не надо
    писать» — a project that resolved fine and has nothing running sends
    NOTHING. True only for exactly that: no rendered rows, no ghosts and no
    stamped lanes (SWEEPER-FALSE-LIFE: a registry lane whose life could not
    be proven is the corpse-dressed-as-live shape the founder asked about —
    real news, never suppressed). Live lanes, ghosts (liveness unproven
    either way), probe disagreement and every error path above are real news
    and must still speak. The in-session board path deliberately does NOT
    call this — its only consumer is the lead Monitor, which must hear the
    loop speak."""
    return (rendered_rows == 0 and ghost_count == 0
            and stamped_count == 0)  # PULSE-WORTH-READING-SUPPRESS


def worktree_evidence(wt, now):
    """Corroborating liveness evidence straight from the worktree of a lane —
    the instrument the lead has used all day and which has never lied:
    freshest of (last commit committer time, mtime of any modified/untracked
    path from `git status --porcelain`). Returns (age_s, tag) or None; tags
    are kommit/pravki so the beat names WHICH evidence made the lane live."""
    if not (isinstance(wt, str) and wt and os.path.isdir(wt)):
        return None
    best = None
    try:
        out = subprocess.run(["git", "-C", wt, "log", "-1", "--format=%ct"],
                             capture_output=True, text=True, timeout=10)
        if out.returncode == 0 and out.stdout.strip().isdigit():
            age = now - int(out.stdout.strip())
            if best is None or age < best[0]:
                best = (age, "kommit")
    except Exception:
        pass
    try:
        out = subprocess.run(["git", "-C", wt, "status", "--porcelain"],
                             capture_output=True, text=True, timeout=10)
        if out.returncode == 0:
            for ln in out.stdout.splitlines():
                # chr(34) instead of a single-quoted double-quote char: this
                # heredoc body must stay free of apostrophes (see the note at
                # the top of the collector).
                p = ln[3:].strip().strip(chr(34))
                if " -> " in p:
                    p = p.split(" -> ")[-1].strip().strip(chr(34))
                if not p:
                    continue
                try:
                    # int(): st_mtime is a float, and a float age would render
                    # "5.0m" — every other age in the beat is an int.
                    mt = int(os.stat(os.path.join(wt, p)).st_mtime)
                except OSError:
                    continue
                age = now - mt
                if best is None or age < best[0]:
                    best = (age, "pravki")
    except Exception:
        pass
    return best


_EVIDENCE_TAG = {"kommit": "коммит", "pravki": "правки", "protsess": "процесс", "glm": "glm-поток"}

# SWEEPER-FALSE-LIFE (founder order 2026-09-09): journal mtime is NOT
# liveness. Two measured writers stamp journals of lanes whose WORKER is
# gone — the merged-worktree sweeper (`worktree_swept` notes; one beat after
# a sweep run, two corpse lanes rendered live with «активность не видна
# (0м, журнал)») and the dispatcher product_close loop (`waiting_worker`
# every poll cycle while IT waits, not while the worker runs). A journal
# touch is therefore a weak, NAMED signal: it may keep a row, never a live
# verdict, never a seat in live=N. Strong evidence is what only the lane own
# worker leaves: a process the probe can see, a fresh glm stream, or a fresh
# commit/edit inside its worktree.
_LIVE_WINDOW_S = 1800
_BOARD_DEAD_PHASES = ("recovered", "dead", "closed", "done", "cancelled", "parked")

def lane_liveness_kind(strong_age, strong_tag, jage, phase):
    """THE one place the live/not-live verdict is decided, shared by BOTH
    render sites (the sessions/agent path and the in-session board path —
    a change at only one of them looks fixed and is not; the lead was
    caught by exactly that). Returns ("live", age, tag) for strong worker
    evidence, ("board", jage, None) for a live phase on the state board,
    ("stamped", jage, "journal") for a journal touch inside the window, and
    (None, None, None) when nothing proves anything either way (the caller
    then applies its own ghost/no-evidence semantics, which do not change).
    NC declarations of tests/unit/test-liveness-is-not-a-file-mtime.sh
    mutate THIS body: returning live for the stamped branch, or returning
    None unconditionally, must each turn that suite red."""
    if strong_age is not None:
        return ("live", strong_age, strong_tag)
    if phase and not any(phase.startswith(p) for p in _BOARD_DEAD_PHASES):
        return ("board", jage, None)
    if jage is not None and jage <= _LIVE_WINDOW_S:
        return ("stamped", jage, "journal")
    return (None, None, None)

def journal_toucher_name(tail_line):
    """Name the last journal writer when the newest stamp is one of the known
    non-worker writers, so a fresh journal says WHAT proved nothing. Empty
    string for anything else (a worker own last line is also unknown-life —
    the row wording already says живость не доказана)."""
    if "worktree_swept" in tail_line:
        return " (штамп свипера: worktree_swept)"
    if "product_close" in tail_line and "waiting_worker" in tail_line:
        return " (штамп close-цикла: product_close waiting_worker)"
    return ""

def freshest_journal_last_line(paths):
    """The last non-empty line of the freshest journal of a lane — the newest
    single stamp. Bounded read (the fd/byte budget that killed the first
    launchd beat); runs ONLY for rendered stamped rows."""
    best_p, best_m = None, -1.0
    for p in paths or []:
        try:
            m = os.stat(p).st_mtime
        except OSError:
            continue
        if m > best_m:
            best_p, best_m = p, m
    if best_p is None:
        return ""
    for ln in reversed(_read_text_bounded(best_p).splitlines()):
        if ln.strip():
            return ln
    return ""

def stamped_row_text(disp, head, jage, toucher):
    """The render BOTH sites share for a journal-touch-only lane. The marker
    is ○, never •: live=N and the • rows stay one list (ADDENDUM 4 #1) while
    a corpse with a fresh stamp stays visible, named and uncounted."""
    age = f"{jage // 60}м" if jage is not None else "давность неизвестна"
    return f"○ {disp}{head} — живость не доказана: отметка в журнале {age} назад, процесса и коммитов нет{toucher}"

# Canonical state-store tier participation. ON for every production shape:
# a default-armed pulse (nothing pinned), the outside agent (sessions JSON
# is its enumeration, and it forces the flag), or an explicit opt-in. OFF
# only for a caller that pinned its own board WITHOUT opting in — the
# fixture-world shape, where consulting the real machine state store would
# import files the fixture never placed (see the _AS_BOARD_PINNED note in
# the shell prologue). The lib tiers below are never gated.
_state_tier_on = (
    bool(sessions_json)
    or os.environ.get("ANTI_SILENCE_STATE_JOURNAL_TIER", "") == "1"
    or os.environ.get("_AS_BOARD_PINNED", "") != "1"
)

# GLM-JOURNAL-GROWTH-IS-LIFE (founder order 2026-09-12, ONE-STATUS-
# MECHANISM-01): ~/.claude/cache/glm-runs/<handle>/journal.jsonl GROWING is
# the one liveness signal that does not lie — measured 2026-09-12: +334KB
# in 25s on a lane every other probe called dead (bd7f811eb05c streamed via
# glm while the board path rendered it «живость не доказана», because that
# path had no glm evidence at all). The run maps to its lane through
# meta.yaml repo: (the writer records the dispatch sig / founder name
# there). Finished runs (finished_at stamped, or result.md present) are
# FINISHED — never live. Journal mtime inside the live window bootstraps
# the first tick; every tick after that compares journal sizes against the
# persistent snapshot written at the end of the scan, so GROWTH — not
# freshness — is the verdict from tick two on. Fixture worlds keep the
# whole scanner off: same gate as the state-store tier (a pinned board
# must not reach into the real machine run dirs).
_GLM_ROOT = os.environ.get("ANTI_SILENCE_GLM_RUNS_DIR", "")
if not _GLM_ROOT:
    _GLM_ROOT = os.path.join(os.path.expanduser("~"), ".claude", "cache", "glm-runs")
_GLM_SNAPSHOT = os.environ.get("ANTI_SILENCE_GLM_SNAPSHOT", "")
if not _GLM_SNAPSHOT:
    _GLM_SNAPSHOT = os.path.join(_GLM_ROOT, ".anti-silence-pulse-journal-sizes.tsv")

def _meta_scalar(txt, key):
    # First matching column-0 `key:` line of a machine-written meta.yaml,
    # value stripped of spaces and quotes. Empty string when absent.
    for ln in (txt or "").splitlines():
        s = ln.strip()
        if s.startswith(key + ":"):
            return s.split(":", 1)[1].strip().strip(chr(34))
    return ""

def glm_stream_scan(now):
    """ONE scanner, module level, shared by BOTH render sites (the shared-
    verdict doctrine of lane_liveness_kind: a change at only one site looks
    fixed and is not). Returns a dict keyed by BOTH the lane sig (meta
    repo:) and the run handle; value is (journal_age_s, handle, grew).
    Unfinished runs only; growth means size > the previous snapshot."""
    if not (_state_tier_on or os.environ.get("ANTI_SILENCE_GLM_RUNS_DIR")):
        return {}
    prev = {}
    try:
        with open(_GLM_SNAPSHOT, encoding="utf-8") as f:
            for ln in f:
                parts = ln.rstrip(chr(10)).split(chr(9))
                if len(parts) == 2 and parts[1].isdigit():
                    prev[parts[0]] = int(parts[1])
    except OSError:
        prev = {}
    live = {}
    cur = {}
    try:
        names = os.listdir(_GLM_ROOT)
    except OSError:
        names = []
    for name in names:
        d = os.path.join(_GLM_ROOT, name)
        if not os.path.isdir(d):
            continue
        if os.path.exists(os.path.join(d, "result.md")):
            continue  # FINISHED: the round wrote its result
        jp = os.path.join(d, "journal.jsonl")
        if not os.path.isfile(jp):
            continue
        meta = _read_text_bounded(os.path.join(d, "meta.yaml"), 16384)
        if _meta_scalar(meta, "finished_at"):
            continue  # FINISHED: the writer stamped the end
        sig = _meta_scalar(meta, "repo")
        if not sig and name.count("-") >= 3:
            sig = "-".join(name.split("-")[2:-1])
        if not sig:
            continue
        try:
            age = max(0, now - int(os.stat(jp).st_mtime))
        except OSError:
            continue
        try:
            size = int(os.path.getsize(jp))
        except OSError:
            continue
        cur[name] = size
        grew = name in prev and size > prev[name]
        if not (grew or age <= _LIVE_WINDOW_S):
            continue
        cand = (age, name, grew)
        old = live.get(sig)
        if old is None or cand[0] < old[0]:
            live[sig] = cand
            live[name] = cand
    try:
        with open(_GLM_SNAPSHOT, "w", encoding="utf-8") as f:
            for k in sorted(cur):
                f.write(k + chr(9) + str(cur[k]) + chr(10))
    except OSError:
        pass
    return live

_GLM_STREAMS = glm_stream_scan(now)

# ADDENDUM-2 format (founder 2026-09-08, after the live agent delivered a
# 45-entry database dump into General): the beat reports ONLY what is live,
# one line per lane, hard-capped; a lane that is not live gets no row at
# all (a скрыто=N count was an admission the wrong set was enumerated in
# the first place); ghosts appear ONCE as an aggregate, never one ПРИЗРАК?
# per row; every rendered name is a name a human gave the work (a raw
# dispatch- signature is stripped to its id); and each live line says what
# the lane is DOING through the two instruments that never lied all day:
# commits ahead of main with their insertions, plus uncommitted edits.
# _MAX_LINES, the char budget and the zero-dispatch-id rule are pinned by
# tests/unit/test-anti-silence-survives-a-dead-lead.sh; NC3 there mutates
# `shown` back to enumerating everything and the suite must go red.
_MAX_LINES = 8

def _plural_commits(n):
    if n % 10 == 1 and n % 100 != 11:
        return "коммит"
    if n % 10 in (2, 3, 4) and n % 100 not in (12, 13, 14):
        return "коммита"
    return "коммитов"

def display_name(task_id):
    # The names a human gave the work: a state-store dir can carry the
    # dispatch- prefix; the bare remainder is the id the founder can match
    # against the board. Nothing wider is recoverable from the store alone.
    if isinstance(task_id, str) and task_id.startswith("dispatch-"):
        return task_id[len("dispatch-"):]
    return task_id

def doing_stats(wt):
    """What the lane is DOING, straight from its worktree: commits ahead of
    main and the insertions they carry, plus uncommitted edits — «4 коммита,
    +377» tells the founder more than an age in minutes. Empty string when
    nothing is statable (no worktree, or git refuses); the renderer then
    falls back to the winning-evidence word. Runs ONLY for rendered live
    rows — fd-frugal by the same budget that killed the first launchd beat
    (256-fd soft limit, 270+ journals in the store)."""
    if not (isinstance(wt, str) and wt and os.path.isdir(wt)):
        return ""
    commits = 0
    ins = 0
    have_main = False
    try:
        rp = subprocess.run(["git", "-C", wt, "rev-parse", "--verify", "main"],
                            capture_output=True, text=True, timeout=10)
        have_main = rp.returncode == 0
    except Exception:
        pass
    if have_main:
        try:
            cl = subprocess.run(["git", "-C", wt, "rev-list", "--count", "main..HEAD"],
                                capture_output=True, text=True, timeout=10)
            if cl.returncode == 0 and cl.stdout.strip().isdigit():
                commits = int(cl.stdout.strip())
        except Exception:
            pass
        try:
            st = subprocess.run(["git", "-C", wt, "log", "--format=", "--shortstat",
                                 "main..HEAD"],
                                capture_output=True, text=True, timeout=10)
            if st.returncode == 0:
                for ln in st.stdout.splitlines():
                    m = re.search(r"(\d+) insertion", ln)
                    if m:
                        ins += int(m.group(1))
        except Exception:
            pass
    dirty = 0
    try:
        ps = subprocess.run(["git", "-C", wt, "status", "--porcelain"],
                            capture_output=True, text=True, timeout=10)
        if ps.returncode == 0:
            dirty = len([ln for ln in ps.stdout.splitlines() if ln.strip()])
    except Exception:
        pass
    bits = []
    if commits:
        bits.append(f"{commits} {_plural_commits(commits)}, +{ins}")
    if dirty:
        bits.append(f"правки: {dirty}")
    return ", ".join(bits)

# ADDENDUM 3 + ADDENDUM 4 (2026-09-08/09, live-board rounds): the DELIVERED
# beat (the agent path, sessions JSON) is composed by the contract below, not
# by the in-session board renderer further down. Every difference is a
# measured defect of the rounds before it:
#   • live=N is the number of rendered rows. A header that says live=0 above
#     three rows contradicts itself (ADDENDUM 4 #1); here the count and the
#     rows are built from ONE list, so they cannot disagree.
#   • every row is named by the id a human gave the work: founder_task= from
#     the lane journal, searched across EVERY state store (a lane dispatched
#     from the leadv2 plugin repo writes into the leadv2 store — ADDENDUM 4
#     #2) and through BOTH address shapes plus the founder-name dir
#     (67dddef9, dispatch-67dddef9 and A1-CODEX-TIERS-B are three addresses
#     of ONE lane — ADDENDUM 3 #2: they dedupe into one row by founder name).
#   • journal mtime is NOT liveness. A lane whose dispatch_terminal line is
#     the newest task= event is FINISHED — no row, not counted, not even a
#     ghost (ADDENDUM 3 #3: merged lanes read live for hours on journal
#     mtime alone). A lane nobody can prove anything about keeps its row and
#     says so honestly instead of being dropped (ADDENDUM 4 #3: A6 was in
#     phase=build and writing, and the beat dropped it).
#   • worker liveness comes from the worker run dir — the instrument that
#     never lied: a fresh glm-runs/<handle>/ without result.md is a
#     streaming worker; result.md marks the round finished; the handle is
#     read from the journal handle= lines.
#   • a lane on the state board (active.yaml of the store) with an active
#     phase gets its row even when no other evidence exists.
if sessions_json:
    import glob as _globmod

    _state_root = os.environ.get("ANTI_SILENCE_STATE_ROOT", "")
    if not _state_root:
        _state_root = os.path.join(os.path.expanduser("~"), ".claude", "leadv2-state")
    _glm_runs_root = os.environ.get("ANTI_SILENCE_GLM_RUNS_DIR", "")
    if not _glm_runs_root:
        _glm_runs_root = os.path.join(os.path.expanduser("~"), ".claude", "cache", "glm-runs")
    try:
        _horizon_s = int(os.environ.get("ANTI_SILENCE_LANE_HORIZON_S") or 21600)
    except ValueError:
        _horizon_s = 21600
    # _LIVE_WINDOW_S and _BOARD_DEAD_PHASES live at module level now — the
    # shared lane_liveness_kind needs them for BOTH render sites.
    _root_real = os.path.realpath(project_root) if project_root else None

    _jtext_cache = {}

    def _jtext(path):
        # One read per journal per beat, shared by every consumer below
        # (fd-frugal: the store holds 270+ journals and a gui agent gets a
        # 256-fd soft limit — measured 2026-09-08).
        if path not in _jtext_cache:
            try:
                with open(path, encoding="utf-8", errors="replace") as f:
                    _jtext_cache[path] = f.read()
            except OSError:
                _jtext_cache[path] = ""
        return _jtext_cache[path]

    # Store directory shapes under the state root. The canonical store is one
    # level deep (<root>/<project>/tasks); the resolver segregates throwaway
    # checkouts into <root>/.ephemeral/<slug>/tasks — two levels (measured in
    # this repo own fixture: a tmp-dir repo resolves its store there, and a
    # one-level glob silently addresses an empty store). NC5 of the dead-lead
    # suite narrows this tuple to one store and the suite must go red.
    _store_globs = ("*", "*/*")

    def _glob_lane_journals(ident):
        # Both address shapes of one id, across EVERY store under the state
        # root. Same fixture-world gate as the canonical tier: a pinned board
        # that did not opt in must not reach into the real machine store.
        if not _state_tier_on or not ident:
            return []
        bare = ident[len("dispatch-"):] if ident.startswith("dispatch-") else ident
        idents = []
        for c in (ident, bare, ("dispatch-" + bare) if bare else ""):
            if c and c not in idents:
                idents.append(c)
        out = []
        for c in idents:
            for shape in _store_globs:
                out += _globmod.glob(os.path.join(_state_root, shape, "tasks", c, "journal.md"))
        return out

    def _lane_journals(task_id, explicit):
        # The full journal set of one lane: the id shapes above, the explicit
        # journal the agent enumeration already found, plus ONE closure hop —
        # the sigs (task= hex) and founder names inside those journals name
        # the twin directories of the same lane, and only the union of all
        # addresses carries the terminal line and the founder id.
        ordered = []
        seen = set()
        for p in _glob_lane_journals(task_id):
            r = os.path.realpath(p)
            if r not in seen:
                seen.add(r)
                ordered.append(p)
        if isinstance(explicit, str) and explicit and os.path.isfile(explicit):
            r = os.path.realpath(explicit)
            if r not in seen:
                seen.add(r)
                ordered.append(explicit)
        hops = []
        for p in ordered:
            t = _jtext(p)
            hops += re.findall(r"task=([0-9a-f]{6,})", t)
            hops += re.findall(r"founder_task=([A-Za-z0-9._-]+)", t)
        for h in hops:
            for p in _glob_lane_journals(h):
                r = os.path.realpath(p)
                if r not in seen:
                    seen.add(r)
                    ordered.append(p)
        return ordered

    def lane_founder_name(journals):
        # The name a human gave the work (ADDENDUM 3 #1). The LAST
        # founder_task= line wins — a re-dispatch re-stamps the name.
        founder = ""
        for p in journals:
            mm = re.findall(r"founder_task=([A-Za-z0-9._-]+)", _jtext(p))
            if mm:
                founder = mm[-1]
        return founder

    _ts_re = re.compile(r"- (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)")

    def _lane_finished(journals):
        # True when a dispatch_terminal line is the newest task= event of the
        # lane. A resumed lane writes waiting_worker / dwr_resume AFTER the
        # old terminal line and must come back. The dedup echo counts as the
        # same terminal marker: measured on the live board 2026-09-09, the
        # zombie lane dispatch-bound000 carries ONLY dedup echoes (the real
        # terminal line never landed) and would otherwise render as a
        # fresh-journal row forever, because the dispatcher re-echoes it
        # every few hours.
        term_ts = ""
        act_ts = ""
        for p in journals:
            for ln in _jtext(p).splitlines():
                m = _ts_re.match(ln)
                if not m:
                    continue
                ts = m.group(1)
                if "dispatch_terminal" in ln:
                    if not term_ts or ts > term_ts:
                        term_ts = ts
                elif " task=" in ln:
                    if not act_ts or ts > act_ts:
                        act_ts = ts
        return bool(term_ts) and (not act_ts or term_ts >= act_ts)

    def _lane_handle(journals):
        handle = ""
        for p in journals:
            mm = re.findall(r"handle=([0-9]{6}-[0-9]{6}-[A-Za-z0-9._-]+)", _jtext(p))
            if mm:
                handle = mm[-1]
        return handle

    def _glm_age(handle, now):
        # The worker run dir: a fresh mtime is a streaming worker (within a
        # minute, measured all day 2026-09-08); result.md means the round is
        # over — a new round mints a NEW handle in the journal, so a stale
        # result.md can never mask it.
        if not handle:
            return None
        d = os.path.join(_glm_runs_root, handle)
        if not os.path.isdir(d) or os.path.exists(os.path.join(d, "result.md")):
            return None
        # max(0, …): a streaming worker can touch the dir between the beat
        # arming and this stat — a negative age rendered as «-1м» once
        # (measured live 2026-09-09, this lane own run dir).
        age = max(0, now - int(os.stat(d).st_mtime))
        return age if age <= _LIVE_WINDOW_S else None

    _board_path = os.environ.get("ANTI_SILENCE_STATE_ACTIVE_YAML", "")
    if _board_path and os.path.isfile(_board_path):
        # Flat stdlib parse of the state-store board (launchd runs on
        # /usr/bin/python3 where PyYAML is absent). Each session record opens
        # with a task_id: line; the fields the beat needs are scalars; the
        # file is machine-written in exactly this shape by the plugin. Dead
        # shapes (recovered_*, terminal_status) are not lanes and never
        # become sessions.
        try:
            with open(_board_path, encoding="utf-8", errors="replace") as f:
                _board_text = f.read()
        except OSError:
            _board_text = ""
        _pending = []
        cur = None
        for ln in _board_text.splitlines():
            s = ln.strip()
            # A new record is any COLUMN-0 list item. The board is
            # machine-written in two shapes (`- task_id: NAME` and
            # `- session_id: s-…` followed by an indented `task_id:`), and a
            # parser that opens only on `- task_id:` FOLDS the second shape
            # into the previous record — measured on the live board
            # 2026-09-09: the A6 record lost its leadv2 worktree to the
            # watcher record nested after it, and the dead
            # recovered_unowned ANTISILENCE-OUTSIDE record inherited
            # phase: build. Nested event items (`  - at:` under
            # lane_events) sit at column 2 and never open a record.
            if ln.startswith("- "):
                if cur:
                    _pending.append(cur)
                cur = {}
                if s.startswith("task_id:"):
                    cur["task_id"] = s.split(":", 1)[1].strip()
                continue
            if cur is None:
                continue
            if s.startswith("task_id:") and "task_id" not in cur:
                cur["task_id"] = s.split(":", 1)[1].strip()
                continue
            for k in ("phase", "worktree", "terminal_status"):
                if s.startswith(k + ":"):
                    cur[k] = s.split(":", 1)[1].strip()
        if cur:
            _pending.append(cur)
        for row in _pending:
            ph = (row.get("phase") or "").lower()
            if row.get("terminal_status"):
                continue
            if ph and any(ph.startswith(p) for p in _BOARD_DEAD_PHASES):
                continue
            if row.get("task_id"):
                sessions.append(row)

    _lanes = {}
    for sess in sessions:
        if not isinstance(sess, dict):
            continue
        task_id = sess.get("task_id") or "?"
        worktree = sess.get("worktree") if isinstance(sess.get("worktree"), str) else None
        if worktree and _root_real and os.path.realpath(worktree) == _root_real:
            # A watcher session whose worktree IS the main checkout is not
            # the lane code — its dirty files belong to whoever runs there.
            worktree = None
        # The tiered resolver (explicit column → writer CLI → address lib)
        # runs FIRST and its answer joins the glob set: the writer CLI
        # remains the canonical oracle for the store address, and it is what
        # reaches a store the caller pinned ANTI_SILENCE_STATE_ROOT away from.
        # Tier 1 of lane_journal already returns the row explicit journal, so
        # there is no second fallback here — the explicit path must not have
        # a redundant reader the address mutation cannot kill.
        tiered = lane_journal(task_id,
                              journal_address.dispatch_key_from_log_path(sess.get("log_path")),
                              worktree, sess, now)
        journals = _lane_journals(task_id, tiered)
        finished = _lane_finished(journals)
        founder = lane_founder_name(journals)
        handle = _lane_handle(journals)
        # PULSE-WORTH-READING: what the lane RUNS on, from the journals the
        # beat already read (cached text, no new fds) — never a guess.
        arm, model, klass = lane_route_info("\n".join(_jtext(p) for p in journals))
        jages = [max(0, now - int(os.stat(p).st_mtime)) for p in journals]
        jage = min(jages) if jages else None
        wt_ev = worktree_evidence(worktree, now) if worktree else None
        wt_age = wt_ev[0] if wt_ev else None
        wt_tag = wt_ev[1] if wt_ev else None
        glm_age = _glm_age(handle, now)
        # GLM-JOURNAL-GROWTH-IS-LIFE: the module scanner beats the dir-mtime
        # fallback — a journal that GREW since the previous tick is a live
        # worker even when the dir mtime fell outside the window.
        _gsv = _GLM_STREAMS.get(handle)
        if _gsv is None:
            _gsv = _GLM_STREAMS.get(
                task_id[len("dispatch-"):] if task_id.startswith("dispatch-") else task_id)
        if _gsv is not None:
            glm_age = _gsv[0] if glm_age is None else min(glm_age, _gsv[0])
        name = founder or (task_id[len("dispatch-"):] if task_id.startswith("dispatch-") else task_id)
        merge_key = name if name else task_id
        prev = _lanes.get(merge_key)
        if prev is None:
            _lanes[merge_key] = {
                "name": name, "task_id": task_id, "finished": finished,
                "jage": jage, "wt": worktree, "wt_age": wt_age, "wt_tag": wt_tag,
                "glm_age": glm_age, "phase": sess.get("phase") or "",
                "arm": arm, "model": model, "klass": klass,
                "journals": journals,
            }
        else:
            # Dedup AFTER resolution (ADDENDUM 3 #2): the signature and the
            # founder id are two addresses of one lane — they meet here, in
            # one row, counted once.
            prev["finished"] = prev["finished"] or finished
            prev["journals"] = (prev.get("journals") or []) + journals
            both = [x for x in (prev["jage"], jage) if x is not None]
            prev["jage"] = min(both) if both else None
            if wt_age is not None and (prev["wt_age"] is None or wt_age < prev["wt_age"]):
                prev["wt_age"], prev["wt_tag"], prev["wt"] = wt_age, wt_tag, worktree
            if glm_age is not None and (prev["glm_age"] is None or glm_age < prev["glm_age"]):
                prev["glm_age"] = glm_age
            if not prev["phase"]:
                prev["phase"] = sess.get("phase") or ""
            # Same fill-empties rule as the other dedup fields: a twin
            # address of the lane may carry the route rows the first one
            # lacked, but a found field is never overwritten by an absent one.
            if not prev["arm"]:
                prev["arm"] = arm
            if not prev["model"]:
                prev["model"] = model
            if not prev["klass"]:
                prev["klass"] = klass

    for key in list(_lanes):
        L = _lanes[key]
        # ADDENDUM 4 #2: a bare hex signature is not a name. When no journal
        # of the lane carries founder_task=, the row says so AND names the
        # stores that were searched — never a silent hex as if it were a name.
        if re.fullmatch(r"[0-9a-f]{6,}", L["name"] or ""):
            if _state_tier_on:
                _stores = sorted(os.path.basename(os.path.dirname(p)) for p in
                                 _globmod.glob(os.path.join(_state_root, "*", "tasks")))
                L["name_note"] = ("имя не найдено: " + L["name"] + " (искал в: "
                                  + (", ".join(_stores[:3]) if _stores else "пусто")
                                  + (", всего " + str(len(_stores)) if len(_stores) > 3 else "")
                                  + ")")
            else:
                L["name_note"] = "имя не найдено: " + L["name"] + " (хранилища не опрашивались)"
        else:
            L["name_note"] = ""

    rows = []
    stamped = []
    ghosts = []
    for key in sorted(_lanes):
        L = _lanes[key]
        if L["finished"]:
            continue
        # SWEEPER-FALSE-LIFE: strong evidence first, and only evidence the
        # lane own worker leaves — glm stream, process probe, fresh
        # commit/edit in the worktree. The journal mtime goes into the
        # shared classifier as the WEAK signal it is: it may keep a named
        # row (stamped below), never a live verdict, never live=N.
        strong_age = L["glm_age"]
        strong_tag = "glm"
        if strong_age is None and probe_says_alive(L["task_id"]) is True:
            strong_age, strong_tag = 0, "protsess"
        if strong_age is None and L["wt_age"] is not None and L["wt_age"] <= _LIVE_WINDOW_S:
            strong_age, strong_tag = L["wt_age"], L["wt_tag"]
        ph = (L["phase"] or "").lower()
        kind, klass_age, klass_tag = lane_liveness_kind(strong_age, strong_tag,
                                                        L["jage"], ph)
        if kind == "live":
            rows.append(("active", klass_age, klass_tag, L))
        elif kind == "board":
            rows.append(("board", klass_age, None, L))
        elif kind == "stamped":
            stamped.append(L)
        else:
            ev = [x for x in (L["jage"], L["wt_age"]) if x is not None]
            if ev and min(ev) <= _horizon_s:
                ghosts.append(L)
    rows.sort(key=lambda r: ({"active": 0, "board": 1}[r[0]],
                             r[1] if r[1] is not None else 10 ** 9))
    n_live = len(rows)
    # PULSE-WORTH-READING (founder 2026-09-09): resolved fine and nothing
    # running — no rendered rows, no ghosts AND no stamped lanes — means NO
    # message. Every other condition (live rows, stamped ○ rows, ghosts, the
    # error paths above) still speaks below; only this exact shape is muted.
    if nothing_to_report(n_live, len(ghosts), len(stamped)):
        print(f"{_AS_NOTHING_MARKER} {stamp} живых линий нет, отправка подавлена")
        raise SystemExit(0)
    lines = []
    header = f"{stamp} live={n_live}"
    if n_live == 0 and not stamped:
        # тишина only when there is truly nothing: a stamped lane is a
        # registry-listed lane whose life the beat could NOT prove — the
        # exact corpse-dressed-as-live shape SWEEPER-FALSE-LIFE exists to
        # surface, never to mute.
        header += " — тишина"
    shown = rows[:_MAX_LINES]
    if n_live > _MAX_LINES:
        header += f" (показаны первые {_MAX_LINES})"
    lines.append(header)
    for kind, age, tag, L in shown:
        disp = L["name_note"] or L["name"]
        # The PULSE-WORTH-READING head: description + arm/model + class,
        # computed once per RENDERED row (fd-frugal: never per session).
        head = lane_head_fields(lane_mission_title(L["wt"]),
                                L.get("arm", ""), L.get("model", ""),
                                L.get("klass", ""))
        if kind == "active" and tag == "glm":
            body = f"работает (glm, {age // 60}м)"
            doing = doing_stats(L["wt"])
            if doing:
                body += "; " + doing
            lines.append(f"• {disp}{head} — {body}")
        elif kind == "active":
            doing = doing_stats(L["wt"])
            body = doing or "в работе"
            ev = f", {_EVIDENCE_TAG.get(tag, tag)}" if tag else ""
            lines.append(f"• {disp}{head} — {body} ({age // 60}м{ev})")
        else:
            ag = f" ({age // 60}м)" if age is not None else " (давность неизвестна)"
            lines.append(f"• {disp}{head} — открыта, активность не видна{ag}")
    if n_live > _MAX_LINES:
        lines.append(f"… и ещё {n_live - _MAX_LINES} живых")
    if stamped:
        # SWEEPER-FALSE-LIFE: a journal-touch-only lane keeps a NAMED row the
        # founder can act on, but never a • bullet and never a live=N seat —
        # the toucher may be a sweeper or the dispatcher close-loop, and the
        # row says so when the newest stamp is one of the known writers.
        for L in stamped[:_MAX_LINES]:
            disp = L["name_note"] or L["name"]
            head = lane_head_fields(lane_mission_title(L["wt"]),
                                    L.get("arm", ""), L.get("model", ""),
                                    L.get("klass", ""))
            lines.append(stamped_row_text(
                disp, head, L["jage"],
                journal_toucher_name(freshest_journal_last_line(L.get("journals")))))
        if len(stamped) > _MAX_LINES:
            lines.append(f"… и ещё {len(stamped) - _MAX_LINES} линий, живость не доказана")
    if ghosts:
        # PULSE-WORTH-READING (founder 2026-09-09: «что за призраки?»): the
        # aggregate explains ITSELF in the founder own words — a ghost is a
        # lane the registry still lists whose liveness the pulse could not
        # confirm. No probe-disagreement clause anymore (SWEEPER-FALSE-LIFE):
        # a True probe verdict is strong «процесс» evidence and promotes the
        # lane to a • row above, so it can never reach this aggregate.
        g = f"призраки: {len(ghosts)} (числятся в реестре, живость не подтверждена)"
        lines.append(g)
    print("\n".join(lines))
    raise SystemExit(0)

# MONITORS-ARE-THE-SECOND-CONSUMER-OF-THE-ADDRESS-RESOLVER-01: the
# per-session resolution (own-root/foreign-root x task_id/dispatch-key,
# recency-bounded fallback) now lives ONCE in journal_address (imported
# above) — lane_journal is a thin caller, not a second copy of the
# algorithm. Liveness is decided ONCE in lane_liveness_kind (SWEEPER-
# FALSE-LIFE): strong worker evidence only for `live=N`; journal mtime
# renders a stamped ○ row and never counts; the winning evidence still
# names itself in the rendered line.
all_rows = []
_by_name = {}
_name_order = []
# PULSE-WORTH-READING: journal address per name, recorded during collection
# so the renderer can read route rows — but the READ happens only for rows
# that actually render (fd-frugal, same budget as the agent site).
_journal_by_name = {}
def _row_key(row):
    # Dedup order for one human lane seen through several board views
    # (worktree board + main-checkout board + state store): live beats
    # stamped beats ghost beats no-evidence, fresher beats staler, and among
    # equals the row WITH a worktree wins — it is the one that can say what
    # the lane is doing.
    name, task_id, age_s, ev_tag, wt, kind = row
    rank = {"live": 0, "stamped": 1, "ghost": 2, "noev": 3}.get(kind, 4)
    return (rank, age_s if age_s is not None else 10 ** 12, 0 if wt else 1)
for sess in sessions:
    if not isinstance(sess, dict):
        continue
    task_id = sess.get("task_id") or "?"
    dkey = journal_address.dispatch_key_from_log_path(sess.get("log_path"))
    worktree = sess.get("worktree") if isinstance(sess.get("worktree"), str) else None
    journal = lane_journal(task_id, dkey, worktree, sess, now)
    wt_ev = worktree_evidence(worktree, now) if worktree else None
    name = display_name(task_id)
    if journal is None and wt_ev is None:
        row = (name, task_id, None, None, None, "noev")
    else:
        # SWEEPER-FALSE-LIFE: same shared classifier as the agent site —
        # strong worker evidence (fresh commit/edit in the worktree, or a
        # process the probe sees) is the only thing that makes this row
        # live; a journal touch renders stamped (○, uncounted). Stale
        # evidence keeps the pre-existing ghost semantics unchanged.
        strong_age, strong_tag = None, None
        # GLM-JOURNAL-GROWTH-IS-LIFE: glm FIRST — the one signal that does
        # not lie. Before 2026-09-12 this board path had NO glm evidence at
        # all and rendered a streaming worker as «живость не доказана».
        # Fresh commit/edit and the process probe follow, exactly as before.
        _gsv = _GLM_STREAMS.get(
            task_id[len("dispatch-"):] if task_id.startswith("dispatch-") else task_id)
        if _gsv is not None:
            strong_age, strong_tag = _gsv[0], "glm"
        if strong_age is None and wt_ev is not None and wt_ev[0] <= _LIVE_WINDOW_S:
            strong_age, strong_tag = wt_ev[0], wt_ev[1]
        if strong_age is None and probe_says_alive(task_id) is True:
            strong_age, strong_tag = 0, "protsess"
        jage = None
        if journal is not None:
            jage = max(0, now - int(os.stat(journal).st_mtime))
        kind, age_s, ev_tag = lane_liveness_kind(strong_age, strong_tag, jage, None)
        if kind is None:
            ev = []
            if jage is not None:
                ev.append(jage)
            if wt_ev is not None:
                ev.append(wt_ev[0])
            kind = "ghost"
            age_s = min(ev) if ev else None
            ev_tag = None
        row = (name, task_id, age_s, ev_tag, worktree, kind)
    prev = _by_name.get(name)
    if prev is None:
        _by_name[name] = row
        _name_order.append(name)
        if journal is not None:
            _journal_by_name[name] = journal
    elif _row_key(row) < _row_key(prev):
        _by_name[name] = row
        if journal is not None:
            _journal_by_name[name] = journal
for name in _name_order:
    all_rows.append(_by_name[name])

live_rows = [r for r in all_rows if r[5] == "live"]
stamped_rows = [r for r in all_rows if r[5] == "stamped"]
ghost_rows = [r for r in all_rows if r[5] == "ghost"]
ghost_count = len(ghost_rows)

lines = []
header = f"{stamp} live={len(live_rows)}"
if not live_rows and not stamped_rows:
    header += " — тишина"
lines.append(header)
shown = live_rows[:_MAX_LINES]
for name, task_id, age_s, ev_tag, wt, kind in shown:
    if kind == "ghost":
        lines.append(f"• {name} — старше {age_s // 60}м")
        continue
    if kind == "noev":
        lines.append(f"• {name} — нет журнала")
        continue
    # PULSE-WORTH-READING: the SAME head fields as the agent site, from the
    # same helpers — the two render sites stay in agreement (a change at
    # only one looks fixed and is not; the lead was already caught by
    # exactly that). Reads happen here, only for rendered rows.
    arm, model, klass = lane_route_info(
        _read_text_bounded(_journal_by_name.get(name) or ""))
    head = lane_head_fields(lane_mission_title(wt), arm, model, klass)
    doing = doing_stats(wt)
    ev = f", {_EVIDENCE_TAG.get(ev_tag, ev_tag)}" if ev_tag else ""
    if not doing:
        # SWEEPER-FALSE-LIFE: a live row always carries worker evidence
        # (ev_tag names it in the suffix), so the fallback says the activity
        # plainly once — never the tag twice («процесс (0м, процесс)»).
        doing = "в работе"
    lines.append(f"• {name}{head} — {doing} ({age_s // 60}м{ev})")
if len(live_rows) > _MAX_LINES:
    lines.append(f"… и ещё {len(live_rows) - _MAX_LINES} живых")
if stamped_rows:
    # SWEEPER-FALSE-LIFE: the SAME stamped render as the agent site (○,
    # named toucher, never a live=N seat) — the two sites stay in
    # agreement by construction, both calling stamped_row_text.
    for name, task_id, age_s, ev_tag, wt, kind in stamped_rows[:_MAX_LINES]:
        arm, model, klass = lane_route_info(
            _read_text_bounded(_journal_by_name.get(name) or ""))
        head = lane_head_fields(lane_mission_title(wt), arm, model, klass)
        jpath = _journal_by_name.get(name)
        lines.append(stamped_row_text(
            name, head, age_s,
            journal_toucher_name(freshest_journal_last_line([jpath] if jpath else []))))
    if len(stamped_rows) > _MAX_LINES:
        lines.append(f"… и ещё {len(stamped_rows) - _MAX_LINES} линий, живость не доказана")
if ghost_count:
    # Same founder-words ghost explanation as the agent site (see there; the
    # probe-disagreement suffix is gone for the same reason — a True verdict
    # promotes the lane to live before this aggregate).
    # NO suppression on this path: its only consumer is the lead Monitor,
    # which must hear the loop speak.
    lines.append(f"призраки: {ghost_count} (числятся в реестре, живость не подтверждена)")
print("\n".join(lines))
PYEOF
  )"; then
    line="[ПУЛЬС] сбор не удался: python3 collector exited non-zero"
  fi
  printf '%s\n' "$line"
  printf '%s\n' "$line" >>"$PULSE_LOG_FILE"
}

if [[ "$ONCE" -eq 1 ]]; then
  now="${NOW_OVERRIDE:-$(date +%s)}"
  _beat "$now"
  _stamp_heartbeat
  exit 0
fi

# H1 (round 8): an unverified takeover (below) does not kill the process it
# cannot identify, so that process -- if it really is still the pulse loop
# -- keeps running and keeps stamping whatever heartbeat file it was armed
# with. If the new loop kept using the SAME base file names, the zombie's
# fresh stamps would mask a wedged NEW loop: the detector goes quiet exactly
# when it should shout. Fix: an "instance key" pointer file, sibling to the
# base pid file, names which suffixed file set is CURRENT. A normal arm (no
# takeover) never writes the pointer and everyone uses the base names
# unchanged -- this is pure additive behaviour for the common case. Only an
# unverified takeover mints a new key and switches this process (and,
# symmetrically, both hooks -- see H1 there) onto the suffixed files, so a
# surviving zombie can only ever refresh a heartbeat file nobody is reading
# any more.
_BASE_PID_FILE="$PULSE_PID_FILE"
_BASE_HEARTBEAT_FILE="$PULSE_HEARTBEAT_FILE"
_BASE_LOG_FILE="$PULSE_LOG_FILE"
_POINTER_FILE="${PULSE_POINTER_FILE:-${_BASE_PID_FILE%.pid}.current}"
_resolve_current_files() {
  local key=""
  if [[ -f "$_POINTER_FILE" ]]; then
    key="$(cat "$_POINTER_FILE" 2>/dev/null || true)"
    key="${key//[^a-zA-Z0-9_]/}"
  fi
  if [[ -n "$key" ]]; then
    PULSE_PID_FILE="${_BASE_PID_FILE%.pid}.${key}.pid"
    PULSE_HEARTBEAT_FILE="${_BASE_HEARTBEAT_FILE%.heartbeat}.${key}.heartbeat"
    PULSE_LOG_FILE="${_BASE_LOG_FILE%.log}.${key}.log"
  else
    PULSE_PID_FILE="$_BASE_PID_FILE"
    PULSE_HEARTBEAT_FILE="$_BASE_HEARTBEAT_FILE"
    PULSE_LOG_FILE="$_BASE_LOG_FILE"
  fi
}

_pid_alive() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

# PULSE-ARMS-WITHOUT-A-PIDFILE-AND-ACCUMULATES-01, fix 2 step 2 + fix 3:
# enumerate live pulse processes from the PROCESS TABLE by a strict argv
# match — the last tokens of the command line must be exactly this script
# path, optionally followed by --sid=<key> — never a substring match.
# pgrep -f matches inside ANY argv token (an editor, a grep, a Monitor
# command line that merely mentions the script) and tripled the count the
# one time it was trusted (lead measured 7 real pulses reported as 20).
# $1 selects a session key; "" means "any session, still this exact script
# path". Direct-shebang shapes (script as argv[0], no interpreter token)
# are counted too, but only the --sid= shape can carry a session key, so
# pre-fix pulses (no marker in argv) are invisible to a keyed lookup by
# design — they age out via the owner belt, they are not re-signalled here.
# Self AND self's whole fork family are excluded: the scanner process is
# itself in the table by the time it scans (the re-exec above already
# stamped --sid= into its own argv), and every $(...) command substitution
# or pipeline segment it runs forks a transient twin with the IDENTICAL
# argv that lives exactly as long as the substitution — the twin's parent
# is the substitution subshell, not the scanner, so a bare ppid==$$ check
# misses it. Both were measured live on the first smoke runs: a heal aimed
# at the scanner's own pipeline-segment twin (which then verified-identity
# "killed" itself and bricked the arm), and a census of 2 with one real
# pulse. The table is captured once into a variable and matched in a
# single awk END block that drops self, self's children and self's
# grandchildren — the complete scan family, order-independent. A real
# pulse of the same session is armed by the session's shell, never by this
# scanner, so family exclusion cannot hide a genuine duplicate.
_ps_pulse_pids() {
  local want_sid="$1" tbl
  tbl="$(ps -axo pid=,ppid=,command= 2>/dev/null || true)"
  awk -v script="$SCRIPT_PATH" -v wsid="$want_sid" -v self="$$" '
    {
      p[NR] = $1; q[NR] = $2; a0[NR] = $3; a1[NR] = $4; a2[NR] = $5; n[NR] = NF
    }
    END {
      # Transitive closure of the descendants of self. One level is not enough:
      # the measured phantom was THREE deep ($( ) subshell -> pipeline
      # segment running this function -> its own $( ) capture subshell),
      # every one a fork carrying the script argv.
      fam[self] = 1
      changed = 1
      while (changed) {
        changed = 0
        for (i = 1; i <= NR; i++)
          if ((q[i] in fam) && !(p[i] in fam)) { fam[p[i]] = 1; changed = 1 }
      }
      for (i = 1; i <= NR; i++) {
        if (p[i] in fam) continue
        # Row shapes (columns: pid ppid argv...): shebang-direct = script at
        # $3/NF 3; interpreter-invoked no-sid = script at $4/NF 4; keyed =
        # script at $4/NF 5 with --sid= as the whole 5th token.
        if (a0[i] == script && n[i] == 3 && wsid == "") { print p[i]; continue }
        if (a1[i] == script && n[i] == 4 && wsid == "") { print p[i]; continue }
        if (a1[i] == script && n[i] == 5 && a2[i] ~ /^--sid=/) {
          if (wsid == "" || substr(a2[i], 7) == wsid) print p[i]
        }
      }
    }' <<<"$tbl"
}
_argv_count() {
  _ps_pulse_pids "$1" | wc -l | tr -d ' '
}

# H2 (round 5): mirrors the hooks' _heartbeat_fresh — a live PID whose
# heartbeat stamp is missing or older than one interval + slack is wedged
# or dead, not a second armer that should refuse forever.
#
# Rollout decision: a missing stamp is treated IDENTICALLY to a stale one
# (not fresh), never as "healthy" and never as "wedged forever". A process
# armed before this feature shipped has no stamp yet; that makes it
# eligible for exactly one takeover below, which immediately writes it a
# fresh stamp -- so the rollout gap is a one-time nag/takeover, not a
# starvation loop that keeps re-killing the same process every turn.
# H3 (round 5): read the interval the file's WRITER recorded, not this
# process's own env resolution -- a takeover armer may have a different
# LEADV2_ANTI_SILENCE_INTERVAL_S than the process that wrote the stamp.
# A single-field (stamp-only) file is the pre-H3 / rollout-gap format:
# fall back to this process's own env value, same as a missing file would.
_heartbeat_fresh() {
  [[ -f "$PULSE_HEARTBEAT_FILE" ]] || return 1
  local line stamp interval now age
  line="$(cat "$PULSE_HEARTBEAT_FILE" 2>/dev/null || true)"
  read -r stamp interval <<<"$line"
  [[ "$stamp" =~ ^[0-9]+$ ]] || return 1
  [[ "$interval" =~ ^[0-9]+$ ]] || interval="$INTERVAL_S"
  now="$(date +%s)"
  age=$(( now - stamp ))
  (( age >= 0 && age <= interval + HEARTBEAT_SLACK_S ))
}

_resolve_current_files

# mkdir is atomic on the platforms supported by this repository.  It makes
# check-and-write one critical section: a simultaneous second arm waits, sees
# the first process's live PID, and exits without becoming a second pulse.
_pid_lock="${PULSE_PID_FILE}.lock"
LOCK_WAIT_ATTEMPTS="${PULSE_LOCK_WAIT_ATTEMPTS:-100}"
_locked=0
_release_lock() {
  if [[ "$_locked" -eq 1 ]]; then
    rm -f "${_pid_lock}/owner.pid" 2>/dev/null || true
    rmdir "$_pid_lock" 2>/dev/null || true
    _locked=0
  fi
}
_cleanup() {
  if [[ -f "$PULSE_PID_FILE" ]] && [[ "$(cat "$PULSE_PID_FILE" 2>/dev/null || true)" == "$$" ]]; then
    rm -f "$PULSE_PID_FILE" "${PULSE_PID_FILE}.birth"
  fi
  _release_lock
}

# H1 (round 6): a takeover may only signal a process it has positively
# identified as this pulse. PIDs are recycled -- a stale-owner takeover that
# kills whatever number is in the pid file with no identity check will
# eventually kill an unrelated process on a long-lived machine. This mirrors
# the pid_birth / pid_identity pattern .claude/scripts/leadv2-lane-liveness.sh
# already uses for the same problem (recorded `ps -o lstart=` compared
# against a live observation): a well-formed recorded birth that a live `ps`
# observation CONTRADICTS is the only thing that blocks a takeover -- an
# absent or unobservable birth degrades to "unverified" and does not block
# it, so a pre-H1 pid file (no birth ever recorded) does not wedge the
# rollout-gap takeover this script already relies on.
_norm_ps_field() {
  local s
  s="$(printf '%s' "$1" | tr -s '[:space:]' ' ')"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}
_ps_lstart() {
  ps -o lstart= -p "$1" 2>/dev/null || true
}
_write_birth() {
  # Records THIS process's own ps lstart into the birth sidecar so a LATER
  # takeover can positively identify that the pid still in PULSE_PID_FILE is
  # still the same OS process it was when it armed -- not a different
  # process the kernel later recycled the pid to.
  _norm_ps_field "$(_ps_lstart "$$")" >"${PULSE_PID_FILE}.birth" 2>/dev/null || true
}
# Returns "verified" | "unverified" | "mismatch" -- never blocks on an
# absent or unobservable birth (degrade-to-unverified, same direction as
# leadv2-lane-liveness.sh's pid_state()); only a recorded birth that
# contradicts a live observation is a "mismatch".
_pid_identity() {
  local pid="$1" birth_file="${PULSE_PID_FILE}.birth" recorded observed
  [[ -f "$birth_file" ]] || { printf 'unverified'; return; }
  recorded="$(cat "$birth_file" 2>/dev/null || true)"
  [[ -n "$recorded" ]] || { printf 'unverified'; return; }
  observed="$(_norm_ps_field "$(_ps_lstart "$pid")")"
  [[ -n "$observed" ]] || { printf 'unverified'; return; }
  if [[ "$observed" == "$recorded" ]]; then
    printf 'verified'
  else
    printf 'mismatch'
  fi
}
_stale_lock() {
  local owner
  owner="$(cat "${_pid_lock}/owner.pid" 2>/dev/null || true)"
  if _pid_alive "$owner"; then
    return 1
  fi
  rm -f "${_pid_lock}/owner.pid" 2>/dev/null || true
  rmdir "$_pid_lock" 2>/dev/null
}

# A killed armer must not permanently block the next one.  Wait one bounded
# second before inspecting the owner: a genuine concurrent armer writes its
# owner marker inside this tiny critical section, while a dead owner can be
# safely reclaimed.
for ((_attempt = 1; _attempt <= LOCK_WAIT_ATTEMPTS + 1; _attempt++)); do
  if mkdir "$_pid_lock" 2>/dev/null; then
    _locked=1
    trap '_cleanup' EXIT
    trap '_cleanup; exit 129' HUP
    trap '_cleanup; exit 130' INT
    trap '_cleanup; exit 143' TERM
    printf '%s\n' "$$" >"${_pid_lock}/owner.pid"
    # Test-only seam: lets the unit test kill an armer while it owns the
    # lock.  Unset in every real invocation, so production has no delay.
    if [[ -n "${PULSE_TEST_ARM_HOLD_S:-}" ]]; then
      _hold_until=$((SECONDS + PULSE_TEST_ARM_HOLD_S))
      while (( SECONDS < _hold_until )); do :; done
    fi
    break
  fi
  if [[ "$_attempt" -eq "$LOCK_WAIT_ATTEMPTS" ]]; then
    _stale_lock || true
  fi
  sleep 0.01
done
if [[ "$_locked" -ne 1 ]]; then
  printf '[anti-silence-pulse] unable to acquire arm lock\n' >&2
  exit 1
fi

_existing_pid=""
if [[ -f "$PULSE_PID_FILE" ]]; then
  _existing_pid="$(cat "$PULSE_PID_FILE" 2>/dev/null || true)"
fi
if ! _pid_alive "$_existing_pid"; then
  # PULSE-ARMS-WITHOUT-A-PIDFILE-AND-ACCUMULATES-01, fix 2 step 2: the
  # marker is missing or names a dead pid, and the pid-file check alone
  # would sail straight past a LIVE same-session pulse — exactly how a live
  # session accumulated pulses on every "not armed" nag (the lead's own
  # session: hook said not-armed, lead armed a second, the first was alive;
  # growth 14 -> 16 -> 18 in ~1h at unchanged lane count). Recover the live
  # pid from the process table by strict argv match and HEAL the marker
  # (pid + birth from the live `ps` observation) so the hooks stop nagging
  # too — instead of arming a second pulse. Only marker names that carry a
  # session key participate: the bare default name cannot be keyed to a
  # session, so legacy arms keep the exact pre-fix behaviour.
  _argv_pid=""
  if [[ "$_ARM_SID" =~ ^[0-9a-fA-F-]{8,}$ ]]; then
    _argv_pid="$(_ps_pulse_pids "$_ARM_SID" | sort -n | head -n 1)"
  fi
  if [[ -n "$_argv_pid" ]]; then
    printf '[anti-silence-pulse] pid marker missing/dead but a live same-session pulse exists by strict argv (pid %s, ppid %s) — healing marker+birth, NOT arming a second\n' \
      "$_argv_pid" "$(ps -o ppid= -p "$_argv_pid" 2>/dev/null | tr -d ' ')" >>"$PULSE_LOG_FILE" 2>/dev/null || true
    printf '%s\n' "$_argv_pid" >"$PULSE_PID_FILE" 2>/dev/null || true
    _norm_ps_field "$(_ps_lstart "$_argv_pid")" >"${PULSE_PID_FILE}.birth" 2>/dev/null || true
    _existing_pid="$_argv_pid"
  fi
fi
if _pid_alive "$_existing_pid"; then
    if _heartbeat_fresh; then
      # Round-5 H2 contract (review round 1, 2026-09-06): a marker-PRESENT
      # healthy owner is refused SILENTLY — the hooks read the marker files
      # directly and never nag in this state, so no fresh Monitor is ever
      # left sitting on a dead stream that would need the line; the silence
      # is pinned by tests/unit/test-anti-silence-pulse.sh ("healthy owner
      # ... arm still refused, PID_FILE untouched", assert_eq "" on stdout).
      # The refusal is said OUT LOUD only when the NEW no-pidfile dedup is
      # what prevented the arm (_argv_pid healed a missing/dead marker onto
      # a live same-session pulse): THAT is the state the hook nags about —
      # the marker was gone, the lead re-armed, and a silent exit 0 would
      # leave the new Monitor with nothing to relay about why nothing beats
      # on the new stream while the old pulse is still alive on the old one.
      if [[ -n "${_argv_pid:-}" ]]; then
        printf '[anti-silence-pulse] already armed: pid %s (session %s) — not starting a second\n' \
          "$_existing_pid" "${_ARM_SID:-default}"
      fi
      exit 0
    fi
    # H2 (round 5): stale-owner takeover. A live PID with a stale or
    # missing heartbeat is wedged, dead-in-all-but-PID, or a rollout-gap
    # process -- refusing to arm forever would mean the nag fires
    # (correctly) and the remedy is permanently blocked (the bug this
    # fixes). Kill it and take over; log the takeover so it is auditable,
    # never silent.
    # H1 (round 6): but ONLY signal a process this takeover has positively
    # identified as the pulse. PIDs recycle -- an unverified kill on a bare
    # guess will eventually hit an unrelated process. "mismatch" (a
    # recorded birth that live `ps` contradicts) refuses outright.
    # C1 (round 7): "unverified" (no birth recorded -- pre-H1 pid file, or
    # `ps` itself unobservable) is NOT proof of identity either -- it is
    # simply the absence of evidence, exactly as capable of naming an
    # unrelated recycled pid as a "mismatch" is. Signalling on a guess is
    # the round-6 instruction this closes: "if identity cannot be
    # established, refuse the takeover and say so in the nag -- never
    # signal on a guess." So "unverified" now takes the marker files
    # (PULSE_PID_FILE/heartbeat/birth) WITHOUT sending any signal to
    # `_existing_pid` -- the new loop becomes the one the hooks observe as
    # live, while the old, unidentifiable process (if it is still this
    # pulse) is left running untouched. The nag line names it so a human
    # can decide whether a manual kill is warranted.
    _identity="$(_pid_identity "$_existing_pid")"
    if [[ "$_identity" == "mismatch" ]]; then
      # H2 (round 8): a mismatch is PROOF the recorded pid was recycled to
      # an unrelated process -- it is not, and never was, our pulse. That is
      # the opposite situation from "unverified" below: there is no chance
      # this pid is a live zombie of ours, so there is nothing to protect a
      # new instance key from, and nothing to signal. Refusing (exit 1)
      # here just bricks the pulse forever on a stale marker -- a safety
      # check permanently disabling the mechanism it protects is worse than
      # the risk it avoids. Discard the stale marker and arm fresh on the
      # SAME (resolved) file names; log the discard so it is auditable.
      printf '[anti-silence-pulse] stale marker DISCARDED: pid %s identity mismatch (recorded birth does not match live process, i.e. this pid was recycled to an unrelated process) -- not our pulse, not signalling it, discarding the marker and arming fresh\n' "$_existing_pid" >>"$PULSE_LOG_FILE"
      rm -f "$PULSE_PID_FILE" "${PULSE_PID_FILE}.birth" 2>/dev/null || true
    elif [[ "$_identity" == "unverified" ]]; then
      # H1 (round 8): identity cannot be established, so this may still be
      # our own live zombie loop -- do not kill it (C1, round 7), but do not
      # let it keep stamping the file this new loop is about to claim
      # either. Mint a fresh instance key and switch onto the suffixed
      # files before writing anything, so nothing the zombie writes to the
      # OLD files can be read as this loop's stamp.
      _new_key="t$(date +%s)_$$"
      # Both lines go to the BASE log file (before the resolve below switches
      # PULSE_LOG_FILE to the suffixed one) -- a human/hook tailing the
      # original path must see the whole takeover story in one place; the
      # new suffixed log then carries only this loop's own beats onward.
      printf '[anti-silence-pulse] takeover WITHOUT SIGNAL: pid %s identity unverified (no birth recorded or ps unobservable) -- NOT killing it, switching to a new instance key (%s) so its continued writes to the old files cannot mask this loop; if pid %s is still running and is not this pulse, it may need a manual kill\n' "$_existing_pid" "$_new_key" "$_existing_pid" >>"$PULSE_LOG_FILE"
      printf '[anti-silence-pulse] new instance armed under key %s (handed off from unverified pid %s)\n' "$_new_key" "$_existing_pid" >>"$PULSE_LOG_FILE"
      printf '%s\n' "$_new_key" >"$_POINTER_FILE"
      _resolve_current_files
    else
      # PULSE-ARMS-WITHOUT-A-PIDFILE-AND-ACCUMULATES-01, fix 3: capture the
      # count BEFORE any signal — `kill` returns 0 and says nothing about
      # whether the subject is still there (the lead killed a wrapper shell,
      # got rc=0, watched it vanish from ps — and the real bash pulse
      # survived to ppid=1; count 14 before, 14 after). The verdict below is
      # the strict-argv count before/after plus the target's observed
      # aliveness, never a return code.
      _tk_before="$(_argv_count "$_ARM_SID")"
      printf '[anti-silence-pulse] stale-owner takeover: pid %s heartbeat stale/missing, identity=%s, taking over arm\n' "$_existing_pid" "$_identity" >>"$PULSE_LOG_FILE"
      kill "$_existing_pid" 2>/dev/null || true
      for ((_wait_i = 0; _wait_i < 20; _wait_i++)); do
        _pid_alive "$_existing_pid" || break
        sleep 0.1
      done
      if _pid_alive "$_existing_pid"; then
        kill -9 "$_existing_pid" 2>/dev/null || true
      fi
      # Three-valued kill -0 trap: rc=0 alive, ESRCH dead, EPERM = alive but
      # owned by another user — so aliveness is derived a second way, from
      # the ps table, and both facts go into the log line.
      _tk_alive="no"
      if ps -o pid= -p "$_existing_pid" >/dev/null 2>&1; then _tk_alive="yes"; fi
      _tk_after="$(_argv_count "$_ARM_SID")"
      _tk_verdict="clean"
      if [[ "$_tk_alive" == "yes" ]]; then _tk_verdict="TARGET STILL ALIVE"; fi
      printf '[anti-silence-pulse] takeover verify: target pid %s alive=%s; other same-session pulses by strict argv before=%s after=%s — %s\n' \
        "$_existing_pid" "$_tk_alive" "$_tk_before" "$_tk_after" "$_tk_verdict" >>"$PULSE_LOG_FILE" 2>/dev/null || true
    fi
fi

printf '%s\n' "$$" >"$PULSE_PID_FILE"
_write_birth
# Stamp a heartbeat immediately at arm time (H3): the first real beat is up
# to INTERVAL_S away, and without this the detector would have to special-
# case "PID alive, heartbeat file doesn't exist yet" as a distinct grace
# state instead of just seeing a fresh stamp like any other live beat.
_stamp_heartbeat
_release_lock

# PULSE-ARMS-WITHOUT-A-PIDFILE-AND-ACCUMULATES-01, fix 3 (arm verdict): the
# arm's own success line carries a COUNT with its boundary, so a later reader
# (hook, reaper, lead) re-derives "exactly one pulse for this session" from
# the log instead of trusting rc=0. The count is of OTHER same-session
# pulses besides this armer — the healthy number is 0; anything else is
# accumulation in the act. A marker name without a session key cannot be
# counted per-session — that arm logs n/a rather than a number that would
# silently span every session on the machine.
if [[ "$_ARM_SID" =~ ^[0-9a-fA-F-]{8,}$ ]]; then
  printf '[anti-silence-pulse] armed pid=%s session=%s other same-session pulses by strict argv=%s\n' \
    "$$" "$_ARM_SID" "$(_argv_count "$_ARM_SID")" >>"$PULSE_LOG_FILE" 2>/dev/null || true
else
  printf '[anti-silence-pulse] armed pid=%s session=<no key in marker name> other same-session pulses by strict argv=n/a\n' \
    "$$" >>"$PULSE_LOG_FILE" 2>/dev/null || true
fi

while true; do
  sleep "$INTERVAL_S"
  now="$(date +%s)"
  _beat "$now"
  _stamp_heartbeat
done
