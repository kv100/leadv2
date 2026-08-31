#!/usr/bin/env bash
# leadv2-broad-status.sh — compose the 30-minute founder status.
# SUPERVISOR-STATUS-TABLE-IN-PLUGIN-01: the table is rendered DETERMINISTICALLY
# (python3, no LLM) from the collector snapshot; Haiku composes ONLY the
# below-table prose from a curated, pre-formatted facts payload. This split
# exists because the founder's table format must carry exact ids/hashes/
# sizes verbatim — an LLM rendering the table itself will eventually drift
# the column set or hallucinate a number (R4 in the architect prepass).
# A Haiku outage (or --model haiku failing) still yields a real table with
# no prose tail, never the old "качество недоступно" whole-status failure.
#
# PULSE-IS-A-PLUGIN-DUTY-01 C1: delivery. The founder's watcher is
# `tail -F | grep --line-buffered URGENT` on the loop log, and the
# [BROAD_STATUS] block itself never contains that substring — before this
# file emitted a ready-line, every beat was composed, timestamped, written to
# two files, and woke nobody. See _emit_ready_line below.
#
# Rollback: LEADV2_SUPERVISE_BROAD_STATUS_S=0 disables the loop beat AND its
# ready-line (the beat branch in the now-retired supervisor loop was the only caller,
# so the kill-switch cannot half-work).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)}}"
if [[ -z "$PROJECT_ROOT" ]]; then
  printf '[broad-status] root_error: set LEADV2_PROJECT_ROOT or run inside a git worktree\n' >&2
  exit 1
fi
export LEADV2_PROJECT_ROOT="$PROJECT_ROOT"

STATE_PATH_SH="$SCRIPT_DIR/leadv2-state-path.sh"
LOG_FILE="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" supervise-loop.log)"
SNAPSHOT_PATH="${LEADV2_BROAD_STATUS_SNAPSHOT_PATH:-$PROJECT_ROOT/docs/leadv2/status-snapshot.json}"
PREV_PATH="${LEADV2_BROAD_STATUS_PREV_PATH:-$PROJECT_ROOT/docs/leadv2/.broad-status-prev.json}"
FOUNDER_STATUS_PATH="${LEADV2_FOUNDER_STATUS_PATH:-$PROJECT_ROOT/docs/leadv2/founder-status.md}"
# PULSE-READABLE-01: overridable the same way FOUNDER_STATUS_PATH is --
# a scratch/test run that pins the compact beat elsewhere must never be
# able to leak the full doc into a real checkout's docs/leadv2/ (this bit
# an ad-hoc real-state sample render during this feature's own
# development: only FOUNDER_STATUS_PATH was overridden, and the full doc
# still wrote into the live persona-engine repo because it was hardcoded
# off PROJECT_ROOT).
FOUNDER_STATUS_FULL_PATH="${LEADV2_FOUNDER_STATUS_FULL_PATH:-$PROJECT_ROOT/docs/leadv2/founder-status-full.md}"
# The collector below supplies the "lanes" section rendered by this board.
# It pins the all-repos policy itself (LEADV2_LANES_ALL_REPOS=1 at
# leadv2-status-collector.sh's snapshot call). That pin is NOT defensive
# hardening against a hypothetical -- it is a demonstrated, live root cause:
# ~/.claude/settings.json's global `env` block ships LEADV2_LANES_ALL_REPOS=0
# for every Claude Code session on this machine (verified 2026-08-30: `env |
# grep LANES_ALL_REPOS` inside a fresh worktree shell -> "=0", and running
# leadv2-lanes-snapshot.sh --json against a fixture with a live foreign-repo
# lane and an empty own repo under that ambient env returns table=[] --
# without the collector's inline override, a lane running in another repo
# is invisible on the board even when the render itself succeeds).
# A SECOND, independent incident shares this bug's title: the bash-3.2
# heredoc parse failure fixed in 67f8b8d, which empties/aborts the render
# outright ("render failed") rather than merely omitting foreign rows --
# guarded by the syntax test below. Both are real; they were observed at
# different beats of the same live incident (2026-08-30T16:53-17:00Z).
COLLECTOR_SH="${LEADV2_STATUS_COLLECTOR_BIN:-$SCRIPT_DIR/leadv2-status-collector.sh}"
TASKS_LIB_SH="${LEADV2_TASKS_LIB_BIN:-$SCRIPT_DIR/leadv2-tasks-lib.sh}"
CLAUDE_BIN="${LEADV2_BROAD_STATUS_CLAUDE_BIN:-claude}"
# Reconcile any own-repo lane rows stranded in ephemeral launcher state
# before the collector takes its one board snapshot.  The registry function
# filters by git common-dir, so this cannot import another repo's scratch row.
ACTIVE_REGISTRY_SH="${LEADV2_ACTIVE_REGISTRY_BIN:-$SCRIPT_DIR/leadv2-active-registry.sh}"
if [[ -f "${ACTIVE_REGISTRY_SH}" ]]; then
  LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" source "${ACTIVE_REGISTRY_SH}" 2>/dev/null || true
  if declare -F leadv2_active_consolidate_ephemeral_roots >/dev/null 2>&1; then
    LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" leadv2_active_consolidate_ephemeral_roots >/dev/null 2>&1 || true
  fi
fi
# ANTI-SILENCE-BEAT-ABORT-04: leadv2-active-registry.sh:45 declares its own
# standalone policy `set -euo pipefail`, and `source` executes that in THIS
# shell — `|| true` above only guards the source command's exit status, not
# the shell option it leaves behind. With errexit on, the first failed
# command substitution on the main path (the render below, fed a garbage
# snapshot) kills the script BEFORE its `RC=$?` / degraded-beat abort paths:
# a beat that fires and says nothing — no log line, no artifact, no ready
# line (proven 2026-08-31: collector-garbage repro exits 1 with zero writes;
# LEADV2_ACTIVE_REGISTRY_BIN=/nonexistent on the same repro exits 0 with the
# full degraded artifact). Re-assert THIS script's own policy from line 22.
set +e
# PULSE-EMPTY-BOARD-01: empty-since cursor (survives across beats — an
# empty board's duration is measured from the FIRST beat that found it
# empty, never re-derived per-render) and the render's own epoch stamp.
#
# FRESH-VS-STALE RULE for any reader (lead relay, hook, human): compare
# `date +%s` against the integer in FOUNDER_STATUS_EPOCH_PATH — NOT
# founder-status.md's line-1 stamp (that stamp is UTC ISO-8601 text, kept
# unchanged for the relay contract, and comparing its wall-clock zone
# against a local `ls -la` mtime is exactly what produced the incident this
# fix exists for: 14:12 local == 11:12:23Z, same instant, "stale" by eye).
# `now_epoch - epoch_in_file < BEAT_S` (BEAT_S = LEADV2_SINGLE_LEAD_BEAT_S,
# default 1800) is FRESH; otherwise STALE. Both numbers are epoch seconds,
# so the comparison is timezone-proof by construction.
EMPTY_SINCE_PATH="${LEADV2_BOARD_EMPTY_SINCE_PATH:-$PROJECT_ROOT/docs/leadv2/.board-empty-since}"
FOUNDER_STATUS_EPOCH_PATH="${LEADV2_FOUNDER_STATUS_EPOCH_PATH:-$PROJECT_ROOT/docs/leadv2/.founder-status-epoch}"
_stamp_epoch() {
  local now
  now="$(date +%s 2>/dev/null || echo 0)"
  printf -- '%s' "$now" > "${FOUNDER_STATUS_EPOCH_PATH}.tmp.$$" 2>/dev/null \
    && mv -f "${FOUNDER_STATUS_EPOCH_PATH}.tmp.$$" "$FOUNDER_STATUS_EPOCH_PATH" 2>/dev/null || true
}

# Beat identity (also the alarm-dedupe VALUE — semantic, never the rendered
# line). LEADV2_BROAD_STATUS_BEAT_AT pins it for tests so a re-run of the
# same beat is a true no-op, not a second wake.
BEAT_AT="${LEADV2_BROAD_STATUS_BEAT_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
# PULSE-IS-A-PLUGIN-DUTY-01 C2: stamped by the loop AFTER the backlog pump
# ran and BEFORE this composer — "dispatch before report" as a code-enforced
# order. "unavailable" when the pump could not run: never 0, which would
# fabricate the fact that the pump ran and dispatched nothing.
DISPATCHED="${LEADV2_BROAD_STATUS_DISPATCHED:-unavailable}"

mkdir -p "$(dirname "$LOG_FILE")"

# ── C1: ONE URGENT-tagged ready-line per beat ──────────────────────────────
# INVARIANT (R1): exactly ONE line per beat, and it is a POINTER to
# founder-status.md — never the payload, never per-lane. Do not "enrich" it:
# every extra line is a model wake paid on every remaining turn of the
# attached session. Transition-deduped (key broad_status_ready, value = beat
# identity) so a re-read or a double --ensure cannot fire the same beat
# twice; lib absent from BOTH the local scripts/lib and the canonical root
# (DISPATCH-CLOSE-GATE-01 round 7: a consumer symlink farm missing this lib
# must fail over to canonical before pass-through, never pass through on a
# bare [[ -f ]] miss) → pass-through emit (R2) — this script runs once per
# BROAD_STATUS_S window, not per poll, so pass-through is still one line per
# beat.
ALARM_LIB="${LEADV2_ALARM_DEDUPE_BIN:-${SCRIPT_DIR}/lib/leadv2-alarm-dedupe.sh}"
[[ -f "${ALARM_LIB}" ]] || ALARM_LIB="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-alarm-dedupe.sh"
# shellcheck source=lib/leadv2-alarm-dedupe.sh
[[ -f "$ALARM_LIB" ]] && source "$ALARM_LIB"
_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_emit_ready_line() {  # <rows|-> [degraded]
  local rows="${1:--}" degraded="${2:-}"
  local dedupe_value="$BEAT_AT${degraded:+ degraded}"
  if command -v leadv2_alarm_transition >/dev/null 2>&1 \
      && ! leadv2_alarm_transition broad_status_ready "$dedupe_value" 2>/dev/null; then
    return 0  # same beat already delivered — suppressed
  fi
  local rel_path="${FOUNDER_STATUS_PATH#"$PROJECT_ROOT"/}"
  printf '%s [SUPERVISE-URGENT] BROAD_STATUS_READY at=%s path=%s rows=%s dispatched=%s%s\n' \
    "$(_now_iso)" "$BEAT_AT" "$rel_path" "$rows" "$DISPATCHED" \
    "${degraded:+ degraded=1}" >>"$LOG_FILE"
}

# ── ANTI-SILENCE-ONE-MECHANISM-01: live lane facts, computed independently
# of the failed collector/renderer. A degraded beat that only says "not
# collected" still leaves the founder with zero facts — this reads
# active.yaml directly (read-only, no dependency on the failed step) so the
# fallback always names how many lanes are live, which, and their phase.
# Never throws past this function: any failure just yields a one-line
# "facts unavailable" string, which is still more than silence.
_live_lane_facts() {
  local yaml_file
  yaml_file="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" --no-link active.yaml 2>/dev/null || true)"
  [[ -z "$yaml_file" ]] && yaml_file="$PROJECT_ROOT/docs/leadv2/active.yaml"
  python3 - "$yaml_file" <<'PY' 2>/dev/null
import sys, os
path = sys.argv[1]
try:
    import yaml
except Exception:
    print("живые линии: недоступно (PyYAML отсутствует)")
    sys.exit(0)
if not os.path.exists(path):
    print("живые линии: 0 (active.yaml не найден)")
    sys.exit(0)
try:
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    sessions = data.get("sessions") or []
except Exception:
    print("живые линии: недоступно (active.yaml не читается)")
    sys.exit(0)
if not sessions:
    print("живые линии: 0")
    sys.exit(0)
rows = []
for s in sessions:
    if not isinstance(s, dict):
        continue
    tid = s.get("task_id") or "?"
    phase = s.get("phase") or "?"
    flag = "stale" if s.get("stale") else "live"
    rows.append(f"{tid}({phase},{flag})")
print(f"живые линии: {len(rows)} — " + ", ".join(rows) if rows else "живые линии: 0")
PY
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    printf 'живые линии: недоступно (ошибка чтения)\n'
  fi
}

# ── failed-beat artifact policy (PULSE-IS-A-PLUGIN-DUTY-01 fix r1) ──────────
# A failed beat must never leave the PREVIOUS beat's healthy table in place
# while claiming freshness: the ready-line points at founder-status.md, so
# the artifact itself has to carry the failure. Replace it with an explicit
# degraded block (same envelope, same content contract: one lane table + 2
# prose lines, same atomic tmp+mv write as the happy path) and only then
# signal READY degraded. If even that write fails, refuse READY entirely:
# BROAD_STATUS_FAILED carries no path= token, so nothing points the founder
# at the stale file, while the URGENT substring still wakes them (C1).
# ANTI-SILENCE-ONE-MECHANISM-01 [Critical]: a degraded beat must still SPEAK
# — never reduce the founder to a bare staleness notice. The lane-facts line
# below is computed AT BEAT TIME from active.yaml directly, independent of
# whatever the collector/renderer failed to do, so the fallback always
# carries real, current facts.
_write_degraded_status() {  # <reason> -> rc 0 if the artifact was replaced
  local reason="$1" block lane_facts
  lane_facts="$(_live_lane_facts)"
  [[ -z "$lane_facts" ]] && lane_facts="живые линии: недоступно"
  block="$(
    printf '%s [BROAD_STATUS] dispatched=%s degraded=1\n' "$BEAT_AT" "$DISPATCHED"
    printf '| Линия | Что делает | Состояние |\n'
    printf '|---|---|---|\n'
    printf '| (статус не собран) | — | %s |\n\n' "$reason"
    printf 'СТАТУС НЕ СОБРАН на beat %s: %s.\n' "$BEAT_AT" "$reason"
    printf 'Таблица линий за этот beat недоступна — это НЕ значит, что линий нет.\n'
    printf '%s\n' "$lane_facts"
    printf '[BROAD_STATUS_END]\n'
  )"
  printf '%s\n' "$block" >>"$LOG_FILE"
  printf '%s\n' "$block" >"$FOUNDER_STATUS_PATH.tmp" 2>/dev/null \
    && mv "$FOUNDER_STATUS_PATH.tmp" "$FOUNDER_STATUS_PATH" 2>/dev/null \
    && _stamp_epoch
}
_emit_fail_line() {  # <reason> — artifact NOT replaced: no READY, no path=
  local reason="$1"
  local dedupe_value="$BEAT_AT failed"
  if command -v leadv2_alarm_transition >/dev/null 2>&1 \
      && ! leadv2_alarm_transition broad_status_ready "$dedupe_value" 2>/dev/null; then
    return 0  # same beat already reported failed — suppressed
  fi
  printf '%s [SUPERVISE-URGENT] BROAD_STATUS_FAILED at=%s reason=%s stale_file_kept=1\n' \
    "$(_now_iso)" "$BEAT_AT" "$reason" >>"$LOG_FILE"
}

if ! bash "$COLLECTOR_SH" --project-root "$PROJECT_ROOT" --out "$SNAPSHOT_PATH" >/dev/null 2>&1; then
  printf '%s [BROAD_STATUS] collection failure: quality read unavailable\n' "$(_now_iso)" >>"$LOG_FILE"
  # A beat that fails must still wake the lead (C1) — with the artifact
  # REPLACED, so the relay can never publish the previous healthy table.
  if _write_degraded_status "сборщик статуса не ответил (collector failed)"; then
    _emit_ready_line "-" degraded
  else
    _emit_fail_line "collection failure + founder-status.md not writable"
  fi
  exit 0
fi

# ── queued+why: docs/tasks.yaml, read ONLY through leadv2-tasks-lib.sh
#    (format-sensitive, lock-arbitrated — never hand-parsed here). ─────────
QUEUED_TSV=""
if [[ -f "$TASKS_LIB_SH" ]]; then
  QUEUED_TSV="$(cd "$PROJECT_ROOT" && PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "'"$TASKS_LIB_SH"'"
    leadv2_tasks_top_n 5
  ' 2>/dev/null)" || QUEUED_TSV=""
fi

# ── landed+hashes today: git log in the MAIN checkout only. ───────────────
LANDED_LOG="$(cd "$PROJECT_ROOT" && git log --since=midnight --pretty=format:'%h%x09%s' -- . 2>/dev/null)" || LANDED_LOG=""

RENDER_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$RENDER_TMPDIR"' EXIT

export _BS_QUEUED_TSV="$QUEUED_TSV"
export _BS_LANDED_LOG="$LANDED_LOG"
# BASH-3.2-HEREDOC-QUOTE-PARITY-01: this heredoc used to be written directly
# inside the `RENDER_JSON="$( ... <<'PY' ... )"` command substitution. macOS's
# system /bin/bash (3.2.57, the mandatory compatibility target — see
# CLAUDE.md) has a heredoc-in-command-substitution lexer bug: even with a
# QUOTED delimiter (<<'PY'), it still scans the heredoc body for stray
# single/double quotes and unmatched parens to decide where the enclosing
# $( ... ) closes. A ~750-line python heredoc full of English prose comments
# (apostrophes: "lane_detail's", "worker's own", contractions) desyncs that
# scan and the WHOLE SCRIPT fails to parse — `bash -n` (and real execution)
# aborts with "unexpected EOF while looking for matching `)'" and the script
# never runs at all, silently, under any minimal-PATH launcher that resolves
# `env bash` to /bin/bash (SwiftBar is exactly this case per CLAUDE.md). Fix:
# write the heredoc to a file as a TOP-LEVEL statement (not nested inside a
# command substitution), then invoke python3 on that file inside the
# substitution — a plain command has nothing for the buggy scanner to
# misparse. Verified: `/bin/bash -n` on this file failed before this change
# and passes after, both on macOS system bash 3.2.57 and homebrew bash 5.3.9.
cat >"$RENDER_TMPDIR/render.py" <<'PY'
import datetime, json, os, re, subprocess, sys

snapshot_path, prev_path, root, tasks_lib_sh, tmpdir, script_dir, full_status_path_override, empty_since_path = sys.argv[1:9]

sys.path.insert(0, os.path.join(script_dir, "lib"))
try:
    from leadv2_lane_naming import human_name, product_sentence
except Exception:
    def human_name(title):
        return None

    def product_sentence(title):
        return None
queued_tsv = os.environ.get("_BS_QUEUED_TSV", "")
landed_log = os.environ.get("_BS_LANDED_LOG", "")

snapshot = json.load(open(snapshot_path, encoding="utf-8"))
sections = snapshot.get("sections", {})

lanes_section = sections.get("lanes", {}) or {}
lanes_raw_data = lanes_section.get("data")
lanes_data = lanes_raw_data if isinstance(lanes_raw_data, dict) else {}
table_rows = lanes_data.get("table") or []
# LANE-OBSERVABILITY-02 change 3: a foreign-repo row whose READ failed
# ({"repo":..,"error":"repo_read_error",..}) is NOT a lane — pull it out of
# the table before any lane accounting below and render it as a named degraded
# prefix line instead, so one unreadable repo can neither zero the board nor
# masquerade as a lane row.
foreign_error_rows = [r for r in table_rows if isinstance(r, dict) and r.get("error")]
table_rows = [r for r in table_rows if not (isinstance(r, dict) and r.get("error"))]
# fix-round-3 (L1): a non-dict element in the collector's "table" array
# (malformed collector output) survived the filter above -- isinstance(r,
# dict) is False for it, so `not (False and ...)` is True -- and reached
# `_row.get(...)` in the dedup loop below with no isinstance guard, an
# AttributeError that killed the whole beat. Degrade it out of the table
# instead of crashing; "not a lane" is exactly what a non-dict row is.
#
# fix-round-4 (R3-3): round-3's filter dropped the non-dict rows UNCOUNTED,
# so a malformed collector table (e.g. a JSON-encoding bug that emits a
# bare string or null in place of a row object) rendered as a plain empty
# table -- byte-identical to a genuinely empty board, which is exactly the
# LANE-DETAIL-BLIND-01 failure mode ("no lanes" vs "could not read the
# lanes" collapsing into one output) this task exists to prevent, one level
# down: a malformed ROW is unreadable, not absent. Count it and surface it
# the same way an unreadable foreign repo already is (table_prefix line +
# suppression of the false empty-board headline below).
malformed_row_count = sum(1 for r in table_rows if not isinstance(r, dict))
table_rows = [r for r in table_rows if isinstance(r, dict)]
questions = lanes_data.get("questions") or lanes_data.get("requires_founder") or []
degraded = lanes_data.get("degraded") or []
# LANE-DETAIL-BLIND-01: a failed/absent `lanes` COLLECTOR SECTION (the
# source of table_rows itself, not lane_detail's per-row facts below) must
# be LOUD too -- mirrors detail_ok. Before this, `_sc_run_section`'s
# per-section isolation let leadv2-lanes-snapshot.sh fail (missing script,
# root_error, invalid JSON) or be genuinely absent while the REST of the
# collector run succeeded; that failure collapsed silently into
# table_rows=[] and was then indistinguishable downstream from a real,
# empty board -- the composer confidently printed "ДОСКА ПУСТА" (zero
# lanes running) when the true fact was "the lanes collector did not
# answer". lanes_raw_data (captured BEFORE the dict coercion above) is the
# actual captured stderr/parse-error string _sc_run_section wrote, not a
# generic "unavailable" placeholder -- the founder gets the real reason.
lanes_ok = bool(lanes_section.get("ok"))
lanes_fail_reason = None if lanes_ok else (
    lanes_raw_data if isinstance(lanes_raw_data, str) else "unavailable"
)

detail_section = sections.get("lane_detail", {}) or {}
detail_data = detail_section.get("data", {}) if isinstance(detail_section.get("data"), dict) else {}
detail_by_task = {
    str(l.get("task_id")): l for l in (detail_data.get("lanes") or []) if isinstance(l, dict)
}
# LANE-LIVENESS-LIES-01 Change 2b: a failed/absent lane_detail section must
# be LOUD, not silently degrade every row into a plausible-looking table.
detail_ok = bool(detail_section.get("ok"))
detail_fail_reason = None if detail_ok else (
    detail_data if isinstance(detail_data, str) else "unavailable"
)


def read_journal_worker(task_id):
    # Change 2c: when lane_detail has no worker for a task (section down,
    # or read_worker() itself came back "unknown"), fall back to the
    # dispatch journal's own classification line before ever printing
    # "неизвестно" -- a rendering artifact must not be presented as a fact.
    path = os.path.join(root, "docs", "leadv2", "tasks", str(task_id), "journal.md")
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
    except OSError:
        return None
    for line in reversed(lines):
        if "dispatch_classified" not in line or "kind=" not in line:
            continue
        try:
            kind = line.split("kind=", 1)[1].split()[0].strip()
        except IndexError:
            continue
        if kind:
            return f"dispatch (kind={kind})"
    return None


def read_worker_reason(task_id):
    # LANE-OBSERVABILITY-02 change 3/1: a TERMINAL lane's row carries the
    # worker's own last words next to the verdict, read through the same
    # shared lib the terminal ledger path uses (arm="" -> auto-detect the
    # stream/rollout source). Read-only, timeout-bounded, empty on any miss —
    # a renderer must degrade to no worker_reason, never crash the beat.
    lib = os.path.join(script_dir, "lib", "leadv2-worker-reason.sh")
    if not os.path.isfile(lib):
        return None
    m = re.match(r"^dispatch-([0-9a-f]{6,40})$", str(task_id))
    if not m:
        return None
    sig = m.group(1)
    handoff = os.path.join(root, "docs", "handoff", f"dispatch-{sig}")
    if not os.path.isdir(handoff):
        return None
    try:
        r = subprocess.run(
            ["bash", lib, handoff, "", sig],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()[:120]
    except Exception:
        return None
    return None

repo_facts_section = sections.get("repo_facts", {}) or {}
repo_facts = repo_facts_section.get("data", {}) if isinstance(repo_facts_section.get("data"), dict) else {}

try:
    with open(prev_path, encoding="utf-8") as fh:
        prev = json.load(fh) or {}
except Exception:
    prev = {}
prev_lanes = prev.get("lanes", {}) if isinstance(prev.get("lanes"), dict) else {}


def _fmt_worktree_half(wt):
    # The old flat-disk rendering, unchanged, as the worktree half.
    if not wt:
        return None
    parts = []
    if wt.get("shortstat"):
        parts.append(wt["shortstat"])
    extra = []
    if wt.get("files_changed") is not None:
        extra.append(f"{wt['files_changed']} tracked")
    if wt.get("untracked_count"):
        extra.append(f"{wt['untracked_count']} untracked")
    if extra:
        parts.append("(" + ", ".join(extra) + ")")
    return " ".join(parts) if parts else None


def _fmt_handoff_half(ho):
    if not ho:
        return None
    count = ho.get("file_count")
    size = ho.get("bytes")
    size_s = f"{size/1024:.0f} KB" if isinstance(size, (int, float)) else "размер неизвестен"
    top = ", ".join(str(n) for n in (ho.get("top") or []))
    out = f"артефакты: {count} файл(ов), {size_s}"
    if top:
        out += f" ({top})"
    return out


def fmt_disk(disk):
    # D3 (BROAD-STATUS-RENDERER-01): disk may now be the nested shape
    # {"worktree":…, "handoff":…} from leadv2-lane-detail.sh, or the OLD
    # flat shape (a prev-beat artifact or an older lane-detail copy) — both
    # are accepted so a deploy never renders a false "пока ничего" (R1).
    if not disk:
        return "пока ничего"
    if ("worktree" in disk) or ("handoff" in disk):
        halves = [
            h for h in (_fmt_worktree_half(disk.get("worktree")),
                        _fmt_handoff_half(disk.get("handoff"))) if h
        ]
        return " · ".join(halves) if halves else "пока ничего"
    flat = _fmt_worktree_half(disk)
    return flat if flat else "пока ничего"


def disk_key(disk):
    # Change-detection key for the "молчит N мин (без изменений)" delta: must
    # fold the handoff half in (file_count, bytes) or a lane whose handoff
    # dir grows reads as unchanged. Old flat shape still accepted (R1).
    if not disk:
        return None
    if ("worktree" in disk) or ("handoff" in disk):
        wt = disk.get("worktree") or {}
        ho = disk.get("handoff") or {}
        return (
            (wt.get("shortstat"), wt.get("files_changed"), wt.get("untracked_count")),
            (ho.get("file_count"), ho.get("bytes")),
        )
    return (disk.get("shortstat"), disk.get("files_changed"), disk.get("untracked_count"))


def md_escape(s):
    return str(s).replace("|", "\\|").replace("\n", " ").strip() if s else s


# BROAD-STATUS-ROWS-01 fix A: a lane can occupy exactly one row. Two rows
# with the same task_id previously happened whenever the row-identity
# column (below) collapsed two DIFFERENT lanes to the same displayed
# string; identity is now the task_id itself, but this dedup stays as a
# second, independent guard against an upstream collector duplicate
# (e.g. the same lane appearing once from an own-repo read and once from
# a foreign-repo read) ever reaching the renderer as two rows.
#
# BROAD-STATUS-ROWS-02 fix-round-2 (High #1/#2): the key MUST be the
# identity actually rendered, not a fragment of it.
#   - (repo, task_id): a foreign lane sharing a bare task_id with an
#     own-repo lane renders as "<repo>/<id>" vs "<id>" -- two DIFFERENT
#     rows -- so repo must be part of the key or the foreign one is
#     silently deleted despite never colliding on screen.
#   - a row with no task_id at all previously fell back to the literal
#     string "?" for every such row, so a SECOND task_id-less row from a
#     different lane collapsed into the first with no degraded row left
#     behind -- the exact failure `:203-213` (empty vs unreadable) exists
#     to prevent. Each occurrence gets its own never-colliding key instead.
_seen_keys = set()
_deduped_table_rows = []
_dedup_dropped_count = 0
for _idx, _row in enumerate(table_rows):
    _tid_raw = _row.get("task_id")
    if _tid_raw:
        _key = (_row.get("repo"), str(_tid_raw))
    else:
        _key = ("__missing_task_id__", _idx)
    if _key in _seen_keys:
        # fix-round-3 (L2): a dedup drop used to be invisible in the
        # founder-facing accounting -- count it so it can be surfaced
        # alongside table_rows_hidden instead of silently vanishing.
        _dedup_dropped_count += 1
        continue
    _seen_keys.add(_key)
    _deduped_table_rows.append(_row)
table_rows = _deduped_table_rows

# fix-round-3 (NEW-7): a single list of (line, is_foreign) pairs instead of
# two parallel lists -- there is exactly one append site, but a future
# second one that forgot the sibling list would truncate the table via
# zip() with no error and no hidden-count, which is exactly the silent-loss
# class this file exists to prevent.
rows_out = []
detail_lines = []
closed_items = []
current_lane_digest = {}
for row in table_rows:
    tid = str(row.get("task_id") or "?")
    # fix-round-3 (NEW-1): detail_by_task is built from lane_detail, which is
    # OWN-REPO-ONLY (see comment above its construction). A foreign row that
    # happens to share a bare task_id with an own-repo lane must NOT join it
    # -- the foreign row would otherwise render the own lane's mission
    # title, worker and stream_bytes, i.e. report a dead foreign lane as
    # "writing now". repo is the discriminator the dedup key already uses.
    _repo_slug = row.get("repo")
    d = detail_by_task.get(tid) if not _repo_slug else None
    # fix-round-3 (NEW-5): the delta digest must be keyed the same way the
    # row identity is rendered/deduped -- (repo, task_id) -- or (a) a
    # foreign row never enters the digest at all (delta line contradicts
    # the table above it) and (b) an own+foreign pair sharing a bare
    # task_id collapse into one digest entry.
    _digest_key = f"{_repo_slug}::{tid}" if _repo_slug else tid

    # id_display: BROAD-STATUS-ROWS-02 task.context.yaml decision IDENTITY
    # -- task_id first, sig8/dispatch id only as the FALLBACK when task_id
    # is absent. fix-round-2 (High #3): the previous ordering preferred
    # dispatch_id whenever a lane_detail join existed, so a lane dispatched
    # as task_id=BROAD-STATUS-ROWS-02 rendered as "dispatch-9f3a1c22" and
    # the founder's own task id appeared in no column at all -- backwards
    # from the decision record. dispatch_id remains the fallback for a row
    # whose task_id could not be resolved at all (tid == "?").
    #
    # PULSE-READABLE-01 honesty invariant (kept, not reverted by the above):
    # a task_id whose own dispatch binding is genuinely unresolved (no
    # lane_detail dispatch_id, and the task_id itself is not already
    # "dispatch-<hex>") still carries the "(dispatch id unknown)" marker --
    # it says "we don't know the binding", which is orthogonal to WHICH
    # identity wins as primary. A row with a resolved dispatch_id, or whose
    # task_id already IS the dispatch id shape, needs no such disclaimer.
    #
    # fix-round-3 (NEW-8): a foreign row NEVER joins lane_detail (own-repo
    # only, see `d` above), so "(dispatch id unknown)" was 100% predictable
    # on every foreign row and carried no information -- it just doubled
    # column width. Suppressed for foreign rows only; own-repo rows keep the
    # disclaimer exactly as before.
    dispatch_id = d.get("dispatch_id") if d else None
    if tid and tid != "?":
        if dispatch_id or re.match(r"^dispatch-[0-9a-f]{6,40}$", tid) or _repo_slug:
            id_display = tid
        else:
            id_display = f"{tid} (dispatch id unknown)"
    elif dispatch_id:
        id_display = f"dispatch-{dispatch_id}"
    else:
        id_display = f"{tid} (dispatch id unknown)"

    # STATUS-FORMAT-IN-RENDERER-01: Линия / Что делает come ONLY from the
    # mission title, never from the prepass excerpt (that stays in "owns"
    # for the detail block). Name is frozen on first resolution in
    # .broad-status-prev.json so it cannot drift between beats (R2).
    prev_row_name = (prev_lanes.get(_digest_key) or {}).get("name") if isinstance(prev_lanes.get(_digest_key), dict) else None
    # PULSE-READABLE-01: leadv2-lane-detail.sh now emits a genuine
    # "mission_title" field (added alongside this fix) -- rung 2/3 of
    # read_owns() (lane-mission.md heading, then fanout mission.txt),
    # NEVER architect-prepass.md, independent of what "owns"/
    # "owns_source" resolved for the detail block. Before this fix the
    # field never existed in lane-detail.sh's JSON contract at all (git
    # show HEAD had zero occurrences of the string "mission_title" in
    # that file), so every beat rendered every lane's name/description
    # as unresolved -- id-fallback in col-1, "\u2014" in col-2.
    mission_title = d.get("mission_title") if d else None
    linia_name = prev_row_name or human_name(mission_title)
    # BROAD-STATUS-ROWS-01 fix A: "Линия" carries the lane IDENTITY
    # (id_display: dispatch id, or the raw task_id/sig8 when no dispatch
    # binding is known) — never a human-derived name. human_name() truncates
    # to <=5 words, so two lanes whose mission titles share a long common
    # prefix ("BROAD-STATUS-ROWS-01 — the status pulse..." /
    # "BROAD-STATUS-ROWS-02 — the status pulse...") previously collapsed to
    # the identical short name and rendered as indistinguishable duplicate
    # rows — one lane visually "ate" the other. task_id (via id_display) is
    # unique per lane by construction, so this alone makes two lanes
    # unable to render as one row ever again.
    linia = id_display
    # LANE-OBSERVABILITY-02 change 3: a lane from ANOTHER repo (the lanes
    # snapshot's foreign rows carry repo=<slug>; own-repo rows never do) is
    # prefixed with its slug so the founder can tell which repo a row belongs
    # to at a glance — single-repo output carries no repo field and is
    # byte-identical to before. (_repo_slug computed once, above.)
    if _repo_slug:
        linia = f"{_repo_slug}/{linia}"
    # The human-readable title (formerly rendered as "Линия") now lives
    # ONLY in "Что делает", alongside the fuller product-sentence
    # description — never duplicated into the identity column.
    chto = product_sentence(mission_title) or linia_name or "—"

    # Кто делает
    _worker = d.get("worker") if d else None
    if _worker and _worker != "unknown":
        kto = _worker
    else:
        # Change 2c: lane_detail has no usable worker (section down, or
        # read_worker() itself returned "unknown") -> fall back to the
        # dispatch journal's own classification before printing
        # "неизвестно", so that string is a true statement, not an artifact.
        kto = read_journal_worker(tid) or "неизвестно"

    # Состояние — HARD RULE 3: unchanged stream+disk since the previous beat
    # renders as "молчит N мин (без изменений с прошлого статуса)".
    stream_bytes = d.get("stream_bytes") if d else None
    disk = d.get("disk") if d else None
    verdict = (d.get("verdict") if d else None) or row.get("status")
    # PULSE-READABLE-01: verdict has TWO valid dead spellings depending on
    # source. lane_detail's own `d["verdict"]` is the raw lane-liveness
    # string ("dead:silent_123s_abandoned"), always colon-qualified. But when
    # `d` is missing (tombstoned/pruned lanes have no lane_detail row at
    # all — leadv2-lanes-snapshot.sh:1113-1122 appends them straight from
    # tombstones.yaml) the fallback is `row["status"]`, the COARSE bucket
    # ("active"/"stale"/"dead", no colon). The old `.startswith("dead:")`
    # check silently missed every tombstone-sourced dead row — that bucket
    # spelling flowed into the live table as "(имя неизвестно) | — | pid
    # birth mismatch (reuse)" junk (founder-rejected beat, 2026-08-21).
    is_dead = bool(verdict) and (str(verdict) == "dead" or str(verdict).startswith("dead:"))
    prev_row = prev_lanes.get(_digest_key)
    delta_note = None
    # fix-round-3 (NEW-5): a foreign row (d is None by construction) must
    # still enter the digest -- keyed on _digest_key -- so raised/closed
    # accounting sees it; only the "молчит N мин (без изменений)" delta
    # note stays own-repo-only (it needs `d` for stream_mtime_age_s, which
    # foreign rows never carry).
    if d is not None or _repo_slug:
        current_lane_digest[_digest_key] = {"stream_bytes": stream_bytes, "disk_key": disk_key(disk)}
        if d is not None and isinstance(prev_row, dict) and not is_dead:
            same_bytes = prev_row.get("stream_bytes") == stream_bytes
            same_disk = prev_row.get("disk_key") == disk_key(disk)
            if same_bytes and same_disk:
                mins = int((d.get("stream_mtime_age_s") or 0) / 60)
                delta_note = f"молчит {mins} мин (без изменений с прошлого статуса)"
    if linia_name:
        # freeze-on-first-resolution: only write a name once resolved; an
        # un-nameable lane keeps retrying fresh resolution every beat.
        current_lane_digest.setdefault(_digest_key, {"stream_bytes": stream_bytes, "disk_key": disk_key(disk)})
        current_lane_digest[_digest_key]["name"] = linia_name

    if delta_note:
        sostoyanie = delta_note
    elif d and d.get("terminal_reason"):
        sostoyanie = d["terminal_reason"]
    elif is_dead:
        sostoyanie = row.get("status_reason") or str(verdict)
    elif d and d.get("writing_now"):
        sostoyanie = "пишет сейчас" + (f" ({stream_bytes} байт в потоке)" if stream_bytes else "")
    elif d:
        age_min = int((d.get("stream_mtime_age_s") or 0) / 60)
        sostoyanie = f"тихо {age_min} мин"
    elif isinstance(row.get("age_s"), (int, float)):
        # LANE-OBSERVABILITY-02 change 3: foreign-repo rows have no
        # lane_detail join (lane_detail reads the own repo only), but the
        # foreign row itself carries the stream mtime age — show it rather
        # than a bare status_reason.
        sostoyanie = f"тихо {int(row['age_s'] // 60)} мин"
    else:
        # tombstoned / pruned from active.yaml — no lane_detail row.
        sostoyanie = row.get("status_reason") or str(row.get("status") or "неизвестно")

    na_diske = fmt_disk(disk) if d else "пока ничего"

    if is_dead:
        # LANE-OBSERVABILITY-02: a terminal lane's closed line carries the
        # worker's own last words when they can be recovered — the verdict
        # alone ("dead:silent") is exactly the silence this fix exists to
        # break. Empty extraction degrades to the verdict-only line.
        _wr = (d.get("worker_reason") if d else None) or read_worker_reason(tid)
        # fix-round-2 (Medium): "name" carries the row IDENTITY (linia,
        # unchanged) so the closed line stays keyed the same way as a live
        # row, but the human-readable mission name -- lost when :519 was
        # reworked to print identity-only -- goes back into the prose so
        # the founder is not left reading a bare id.
        closed_items.append({
            "name": linia,
            "cause": (f"{linia_name} — " if linia_name else "")
            + sostoyanie
            + (f" — worker: {_wr}" if _wr else ""),
        })
        continue

    rows_out.append((
        "| " + " | ".join(md_escape(x) for x in (linia, chto, sostoyanie)) + " |",
        bool(_repo_slug),
        _repo_slug or "",
    ))
    detail_lines.append(f"{id_display} — {kto} — {na_diske}")

# fix-round-5 (R3-3, remedy half): round-4 counted a malformed (non-dict)
# table row and named it in the table_prefix line above the table, but the
# table BODY still printed only the positive-looking placeholder
# "(живых линий нет)" beneath it -- a reader who counts rows in the table
# itself, not the prose above it, still sees zero rows and nothing telling
# them one is unreadable. Each malformed row now also gets its own NAMED
# row inside the table (wording deliberately distinct from the table_prefix
# line above so the two are independently verifiable), so the table's own
# row count reflects reality: N unreadable rows are N rows, not an absence.
for _mi in range(malformed_row_count):
    rows_out.append((
        f"| (строка {_mi + 1} повреждена) | формат не читается | НЕ ЧИТАЕТСЯ |",
        False,
        "",
    ))

# Change 2b: a failed lane_detail section must be visible ABOVE the table,
# not inferred from every row silently reading "неизвестно".
table_prefix = []
if not detail_ok:
    table_prefix.append(
        f"детали линий недоступны (lane_detail: {detail_fail_reason}) — "
        "колонки «Линия» и «Что делает» могут остаться неизвестны\n"
    )
# LANE-DETAIL-BLIND-01: same treatment for the `lanes` section itself --
# this is the section table_rows is BUILT FROM, so its failure means the
# table below is not "empty", it is "unknown". Distinct wording from the
# detail_ok note above on purpose: this is "I cannot see any lanes",
# detail_ok's note is "I can see lanes but not their names/owners" -- the
# founder must be able to tell the two facts apart at a glance.
if not lanes_ok:
    table_prefix.append(
        f"НЕ ВИЖУ ЛИНИИ — сборщик lanes не ответил ({lanes_fail_reason}) — "
        "таблица ниже НЕ является доказательством пустой доски\n"
    )
# LANE-OBSERVABILITY-02 change 3: a foreign repo whose read failed gets the
# SAME "не вижу" treatment as a failed own-repo section — a named, per-repo
# degraded line. It must never zero the table (the own-repo rows below stay)
# and never read as "that repo has no lanes".
for _fer in foreign_error_rows:
    table_prefix.append(
        f"НЕ ВИЖУ ЛИНИИ — репозиторий {_fer.get('repo', '?')} не прочитан "
        f"({_fer.get('data') or _fer.get('error')}) — его линии неизвестны, "
        "таблица ниже не про него\n"
    )
# fix-round-4 (R3-3): a malformed (non-dict) table row is unreadable, not
# absent -- see the L1 comment above. Named, counted degraded line, same
# treatment as an unreadable foreign repo.
if malformed_row_count:
    table_prefix.append(
        f"НЕ ЧИТАЮТСЯ {malformed_row_count} строк(и) таблицы (повреждённый формат "
        "от сборщика) — это НЕ означает, что этих линий нет, они unreadable\n"
    )

# MON-PULSE-01 fix-round 2 (H4): route the per-lane pulse to the founder.
# The lane watcher (leadv2-lane-pulse-watch.sh) appends one line per journal
# event to docs/leadv2/tasks/<tid>/pulse.md via leadv2-pulse.sh; before this
# block the watcher's stdout was discarded by the dispatcher (>/dev/null) and
# NO reader consumed the file — both founder-facing channels were bypassed
# and a terminal could be "pulsed" yet invisible. The beat composer is that
# reader now: the LAST pulse line of every board lane (alive or dead this
# beat) lands VERBATIM in founder-status.md — never re-worded, so the
# founder greps the exact event. Capped at 6 like the table (rule 2).
pulse_lines = []
for row in table_rows:
    _ptid = str(row.get("task_id") or "?")
    try:
        with open(os.path.join(root, "docs", "leadv2", "tasks", _ptid, "pulse.md"),
                  encoding="utf-8", errors="replace") as fh:
            _pl = [l for l in fh.read().splitlines() if l.strip()]
    except OSError:
        continue
    if _pl:
        pulse_lines.append(f"{_ptid}: {_pl[-1]}")
pulse_md = (
    "Пульс линий (последние события):\n"
    + "\n".join(f"- {l}" for l in pulse_lines[:6])
) if pulse_lines else None

# PULSE-READABLE-01 rule 2: max ~6 rows in the founder-facing table. The
# full (uncapped) row set still goes into founder-status-full.md below —
# capping here is a RENDER decision, never a data-loss decision.
#
# BROAD-STATUS-ROWS-02 fix-round-2 (Critical): a foreign-repo row must
# survive the cap. leadv2-lanes-snapshot.sh APPENDS foreign rows onto the
# END of an already own-repo-ranked-and-capped table, so a plain
# `[:TABLE_ROW_CAP]` slice systematically cuts every foreign lane once
# own-repo lanes alone fill the cap -- the cross-repo lane is then counted
# as "мусорных/лишних строк" below, which is a lie: it was never junk.
#
# fix-round-3 (NEW-2/NEW-3): round-2 exempted foreign rows from the cap
# entirely (no counter), which is not a reservation -- it is unbounded, and
# leadv2-lanes-snapshot.sh puts NO cap and NO status filter on foreign rows
# (active+stale both reach the table). At the other extreme, own-repo rows
# had NO floor -- `_own_row_budget = max(0, TABLE_ROW_CAP - foreign_count)`
# meant enough foreign lanes evicted every own-repo row and the founder was
# told his own live lanes were "мусорных/лишних строк", the exact lie this
# task exists to delete, now pointed at his own board.
#
# A reservation must be BOUNDED on both sides: foreign gets a capped slice
# of TABLE_ROW_CAP (never the whole board), own-repo keeps the remainder as
# a floor (never zero while own rows exist). Neither side may starve the
# other.
#
# fix-round-4 (R3-2): the reserve above is a FLOOR (a guaranteed minimum
# when both sides compete for the cap), never a CEILING. Round-3's version
# applied FOREIGN_ROW_RESERVE unconditionally, so "10 foreign + 0 own"
# rendered only 2 of 6 available slots and printed "8 строк не поместилось"
# while four table slots sat empty -- the reservation was defending a bug,
# not preventing one. The empty side must yield its unused share to the
# other: 0 own -> foreign gets the WHOLE cap; 0 foreign -> own already got
# the whole cap (unchanged). Only when BOTH sides have rows does the
# reserve/floor split kick in.
TABLE_ROW_CAP = 6
FOREIGN_ROW_RESERVE = max(1, TABLE_ROW_CAP // 3)
rows_out_full = rows_out
_foreign_row_count = sum(1 for _, _f, _r in rows_out_full if _f)
_own_row_count = len(rows_out_full) - _foreign_row_count
# fix-round-5 (N4-1): the floor/reserve split above only has anything to
# defend when the two sides are actually COMPETING for the cap. round-4's
# version special-cased only `_own_row_count == 0`, so the ordinary board
# (WIP is 1-3 own lanes per session -- see leadv2 task-lane cap policy) fell
# straight into the `else` branch and got capped to FOREIGN_ROW_RESERVE
# regardless of whether the total even exceeded TABLE_ROW_CAP: "2 own + 4
# foreign" (6 lanes, 6 slots) rendered only 4 rows and reported "2 чужих
# строк не поместилось" -- lanes that fit were told they didn't. Nothing
# competes for a slot that would otherwise sit empty, so when everyone fits
# under the cap, everyone renders; the reserve/floor split below only
# engages once the two sides are actually fighting for a scarce slot.
if _own_row_count + _foreign_row_count <= TABLE_ROW_CAP:
    _foreign_slots = _foreign_row_count
elif _own_row_count == 0:
    _foreign_slots = min(_foreign_row_count, TABLE_ROW_CAP)
elif _foreign_row_count == 0:
    _foreign_slots = 0
else:
    _foreign_slots = min(_foreign_row_count, FOREIGN_ROW_RESERVE)
_own_row_budget = TABLE_ROW_CAP - _foreign_slots

# fix-round-4 (Medium, alphabetical starvation): leadv2-lanes-snapshot.sh
# emits foreign rows in whatever order its own read happened to enumerate
# repos, which is effectively alphabetical -- so when foreign supply
# exceeds _foreign_slots, a repo late in that order was silently NEVER
# shown, beat after beat, while an earlier repo always filled every slot.
# Round-robin across repos BY INDEX (first-seen order per repo) so a
# bounded slot budget is shared across repos, not monopolized by whichever
# repo sorts first.
#
# fix-round-5 (R3-5, comment correction): this round-robin fixes the
# CROSS-REPO starvation above, but WITHIN a repo it still keeps whatever
# order rows_out_full received the rows in, and that order is NOT a
# liveness/recency ordering -- leadv2-lanes-snapshot.sh sorts a repo's own
# foreign rows via `sorted(session_by_task.items())` (task-id/session-key
# order), so a lane silent for hours can sort ahead of one actively writing
# right now within the same repo, and this block has no way to tell the
# two apart (foreign rows carry only `age_s`, not a writing_now flag -- see
# the `d` is None branch above `sostoyanie` is built from `age_s` alone).
# leadv2-lanes-snapshot.sh is out of this task's LANE_WRITES scope, so this
# comment records the limitation rather than silently claiming a liveness
# guarantee this block does not provide.
_repo_buckets = {}
_repo_order = []
for _idx, (_l, _f, _r) in enumerate(rows_out_full):
    if not _f:
        continue
    if _r not in _repo_buckets:
        _repo_buckets[_r] = []
        _repo_order.append(_r)
    _repo_buckets[_r].append(_idx)
_foreign_selected_idx = set()
while len(_foreign_selected_idx) < _foreign_slots:
    _advanced = False
    for _r in _repo_order:
        if _repo_buckets[_r]:
            _foreign_selected_idx.add(_repo_buckets[_r].pop(0))
            _advanced = True
            if len(_foreign_selected_idx) >= _foreign_slots:
                break
    if not _advanced:
        break

rows_out = []
_own_rows_kept = 0
_foreign_rows_kept = 0
for _idx, (_line, _is_foreign, _repo) in enumerate(rows_out_full):
    if _is_foreign:
        if _idx in _foreign_selected_idx:
            rows_out.append((_line, _is_foreign))
            _foreign_rows_kept += 1
    elif _own_rows_kept < _own_row_budget:
        rows_out.append((_line, _is_foreign))
        _own_rows_kept += 1
_own_rows_hidden = max(0, _own_row_count - _own_rows_kept)
_foreign_rows_hidden = max(0, _foreign_row_count - _foreign_rows_kept)
table_rows_hidden = _own_rows_hidden + _foreign_rows_hidden

# PULSE-EMPTY-BOARD-01 rule 1: zero live lanes is a LOUD event, not a table
# with no rows. `rows_out_full` is already alive-only (a dead row hits
# `continue` above and is never appended), so its length IS the live-lane
# count. empty_since_path persists the first-observed-empty epoch across
# beats so the duration is real elapsed time, not re-derived per render; a
# non-empty board clears it, so the NEXT time it goes empty the clock
# restarts from that moment, not from the earlier outage.
live_lane_count = len(rows_out_full)
empty_headline = None
try:
    if not lanes_ok:
        # LANE-DETAIL-BLIND-01: table_rows is forced to [] whenever the
        # lanes section failed (its `data` becomes a plain error string,
        # never a dict -- see lanes_data above), so live_lane_count==0 here
        # is NOT evidence of an empty board, it is evidence the collector
        # did not answer. "the board is empty" and "I cannot see the
        # board" are different facts (task requirement) -- printing
        # PULSE-EMPTY-BOARD-01's headline for both is exactly the false
        # verdict this fix exists to kill. Deliberately does NOT touch
        # empty_since_path: whether the board was actually empty during
        # this outage is unknown, so neither starting nor clearing that
        # clock from an unknown state would be honest -- it stays frozen
        # at whatever it already recorded until a beat can actually see.
        empty_headline = (
            "⚠ НЕ ВИЖУ ЛИНИИ — сборщик статуса линий не ответил "
            f"({lanes_fail_reason}); неизвестно, пуста ли доска на самом деле"
        )
    elif live_lane_count == 0:
        # fix-round-5 (R3-3): a malformed row can no longer make
        # live_lane_count==0 while malformed_row_count>0 -- each malformed
        # row is now appended into rows_out_full as its own named "НЕ
        # ЧИТАЕТСЯ" row (see the loop right after the main row-building
        # loop above), so live_lane_count already reflects it and this
        # branch is the genuinely-empty case only.
        now_epoch = int(__import__("time").time())
        since_epoch = None
        try:
            with open(empty_since_path, encoding="utf-8") as fh:
                _cand = fh.read().strip()
            if _cand.isdigit():
                since_epoch = int(_cand)
        except OSError:
            since_epoch = None
        if since_epoch is None:
            since_epoch = now_epoch
            _tmp = empty_since_path + ".tmp"
            with open(_tmp, "w", encoding="utf-8") as fh:
                fh.write(str(now_epoch))
            os.replace(_tmp, empty_since_path)
        empty_minutes = max(0, (now_epoch - since_epoch) // 60)
        empty_headline = f"⚠ ДОСКА ПУСТА — ничего не выполняется, {empty_minutes} мин"
    else:
        try:
            os.remove(empty_since_path)
        except OSError:
            pass
except Exception:
    empty_headline = None

# PULSE-READABLE-01: header text kept as "Что делает" — the exact
# STATUS-FORMAT-IN-RENDERER-01 3-column contract shape (T8/T15 and other
# suites assert this literal string); the founder's sample used "Что чинит"
# as prose, not a spec requirement, and renaming it would be a drive-by
# break of an unrelated decision record for zero readability gain.
_table_header = ["| Линия | Что делает | Состояние |", "|---|---|---|"]
_rows_out_lines = [l for l, _ in rows_out]
_rows_out_full_lines = [l for l, _f, _r in rows_out_full]
table_md = "\n".join(table_prefix + _table_header +
                      (_rows_out_lines if _rows_out_lines else ["| (живых линий нет) | — | — |"]))
full_table_md = "\n".join(table_prefix + _table_header +
                           (_rows_out_full_lines if _rows_out_full_lines else ["| (живых линий нет) | — | — |"]))

detail_md = "Детали линий: " + " · ".join(detail_lines) if detail_lines else "Детали линий: (нет активных линий)"

closed_parts = [f"{c['name']} ({c['cause']})" for c in closed_items]

# ── curated, pre-formatted tail facts — nothing numeric here may be
#    invented by the composer; it copies these strings verbatim (R4). ──────
queued_items = []
for line in queued_tsv.splitlines():
    parts = line.split("\t")
    if len(parts) < 4:
        continue
    _lane, priority, iid, title = parts[0], parts[1], parts[2], parts[3]
    if not title.strip() and os.path.isfile(tasks_lib_sh):
        try:
            import subprocess
            r = subprocess.run(
                ["bash", "-c", f'PROJECT_ROOT="{root}" bash -c \'source "{tasks_lib_sh}" && leadv2_tasks_by_id "{iid}"\''],
                capture_output=True, text=True, timeout=5,
            )
            if r.returncode == 0 and r.stdout.strip():
                import yaml
                doc = yaml.safe_load(r.stdout)
                if isinstance(doc, list) and doc:
                    title = (doc[0].get("intent") or "")[:160]
        except Exception:
            pass
    title_final = title[:160] or "(без описания)"
    # Deterministic echelon bucket (§3.3) — never LLM judgment, so it cannot
    # drift between beats. Best-effort against the fields top_n actually
    # emits (lane, priority): plugin/leadv2-named work -> Плагин; human-
    # needed lane -> Хозяйство; critical/high priority -> Первый эшелон;
    # everything else -> Второй эшелон.
    _lane_lower = (_lane or "").lower()
    _title_lower = title_final.lower()
    if "leadv2" in _title_lower or "plugin" in _title_lower or "плагин" in _title_lower:
        echelon = "Плагин"
    elif _lane_lower in ("human-needed", "housekeeping", "hygiene", "chore"):
        echelon = "Хозяйство"
    elif str(priority).strip().lower() in ("critical", "high"):
        echelon = "Первый эшелон (корни)"
    else:
        echelon = "Второй эшелон (после корней)"
    queued_items.append({"id": iid, "priority": priority, "title_or_intent": title_final, "echelon": echelon})

landed_items = []
for line in landed_log.splitlines():
    if "\t" not in line:
        continue
    h, subj = line.split("\t", 1)
    landed_items.append({"hash": h, "subject": subj})

closed_parts = closed_parts + [f"{li['hash']} {li['subject']}" for li in landed_items]
closed_paragraph = " · ".join(closed_parts) if closed_parts else "закрытых линий и коммитов сегодня нет"

ECHELON_ORDER = [
    "Первый эшелон (корни)", "Второй эшелон (после корней)", "Плагин", "Хозяйство",
]
queue_sections = []
for echelon in ECHELON_ORDER:
    items = [q for q in queued_items if q["echelon"] == echelon]
    if not items:
        continue
    lines = [f"{i}. {q['id']} — {q['title_or_intent']}" for i, q in enumerate(items, start=1)]
    queue_sections.append(f"**{echelon}**\n" + "\n".join(lines))
_queue_label_file = os.path.join(".claude", "leadv2-overrides", "queue-impact-label.txt")
_queue_label = "Очередь — по влиянию:"
try:
    with open(_queue_label_file, encoding="utf-8") as fh:
        _cand = fh.readline().strip()
    if _cand:
        _queue_label = _cand
except OSError:
    pass
queue_md = _queue_label + "\n\n" + (
    "\n\n".join(queue_sections) if queue_sections else "(очередь пуста)"
)

# V3-GLM-LADDER-01: sonnet-fallback counter, codex credit watchdog, deferred-GLM park --
# all three rendered DETERMINISTICALLY here (never through the Haiku two-line writer,
# see architect design D0) so a degraded reader can never hide a degraded provider.
# Every read is existence-guarded and a malformed file yields the zero/absent case,
# never an exception (R5) -- a renderer traceback degrades the whole beat.
sonnet_fallbacks_today = 0
sonnet_fallback_last_reason = ""
try:
    _today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d")
    _exc_path = os.path.join(root, "docs", "leadv2", f".arm-exceptions-{_today}")
    if os.path.isfile(_exc_path):
        with open(_exc_path, encoding="utf-8") as fh:
            for _line in fh:
                _line = _line.strip()
                if _line.startswith("count="):
                    try:
                        sonnet_fallbacks_today = int(_line[len("count="):])
                    except ValueError:
                        sonnet_fallbacks_today = 0
                elif _line.startswith("last_reason="):
                    sonnet_fallback_last_reason = _line[len("last_reason="):]
except OSError:
    pass

codex_credits_empty_since = None
try:
    _stamp_path = os.path.join(root, "docs", "leadv2", ".codex-credits-empty.stamp")
    if os.path.isfile(_stamp_path):
        with open(_stamp_path, encoding="utf-8") as fh:
            _first = fh.readline().strip()
        if _first.startswith("since="):
            codex_credits_empty_since = _first[len("since="):]
except OSError:
    pass

glm_deferred_count = 0
try:
    _deferred_path = os.path.join(root, "docs", "leadv2", "glm-deferred.jsonl")
    if os.path.isfile(_deferred_path):
        _retried = set()
        _rows = []
        with open(_deferred_path, encoding="utf-8") as fh:
            for _line in fh:
                _line = _line.strip()
                if not _line:
                    continue
                try:
                    _row = json.loads(_line)
                except Exception:
                    continue
                if "_truncated" in _row:
                    continue
                _rows.append(_row)
        for _row in _rows:
            if _row.get("retried_at"):
                _retried.add(_row.get("sig8"))
        # M4: dedup by sig8 (newest row wins) -- a task parked twice (e.g. once at the
        # quota-precheck bench, once at a live refusal) counts once, not twice.
        _pending_sig8s = {r.get("sig8") for r in _rows if r.get("sig8") not in _retried}
        glm_deferred_count = len(_pending_sig8s)
except OSError:
    pass

_provider_health_lines = []
if sonnet_fallbacks_today > 0:
    _provider_health_lines.append(
        f"sonnet-фолбэков сегодня: {sonnet_fallbacks_today} ({sonnet_fallback_last_reason or 'glm quota'})"
    )
if codex_credits_empty_since:
    _provider_health_lines.append(f"codex: кредиты на нуле с {codex_credits_empty_since}")
if glm_deferred_count > 0:
    _provider_health_lines.append(
        f"отложено на GLM: {glm_deferred_count} задач (dispatch glm-deferred --list)"
    )
if _provider_health_lines:
    queue_md = queue_md + "\n\n" + "\n".join(_provider_health_lines)

tail_facts = {
    "queued_top5": queued_items,
    "landed_today": landed_items,
    "repo_facts": repo_facts,
    "questions_pending": questions,
    "degraded_dispatch": degraded,
    "lanes_summary": [
        {"task_id": r.get("task_id"), "status": r.get("status")} for r in table_rows
    ],
    "provider_health": {
        "sonnet_fallbacks_today": sonnet_fallbacks_today,
        "sonnet_fallback_last_reason": sonnet_fallback_last_reason,
        "codex_credits_empty_since": codex_credits_empty_since,
        "glm_deferred_count": glm_deferred_count,
    },
}

# ── PULSE-READABLE-01 rule 4: delta since previous beat, not a ledger. ────
# current_lane_digest holds every ALIVE lane resolved this beat (a dead row
# is `continue`d above before it is ever written into the digest);
# prev_lanes is the identical structure from the last .broad-status-prev.
# json. Diffing the two id sets is the whole delta: a lane the founder was
# already told about (raised) never re-appears, and a lane that vanished
# (closed_items this beat, OR silently pruned/tombstoned since) counts as
# closed exactly once, never re-listed on every following beat.
raised_ids = [tid for tid in current_lane_digest if tid not in prev_lanes]
closed_ids = [tid for tid in prev_lanes if tid not in current_lane_digest]
delta_line = f"С прошлого удара: +{len(raised_ids)} линии подняты, {len(closed_ids)} закрыто."

# ── rule 1: product-truth line 1. Deliberately generic — this file is the
# SHARED plugin, never a persona-engine-only copy (CLAUDE.md "features must
# be tenant-generic"). It reads whatever the caller repo's own
# collect_repo_facts() hook (.claude/leadv2-overrides/status-collector-
# facts.sh) chose to publish under a small candidate-key contract, and
# degrades any missing metric to the literal "н/д" — never 0, which would
# fabricate a false empty day (memory feedback_flag_on_but_artifact_missing
# / "a zero is probably a broken query"). A repo wires this line by adding
# posts_today/posts_floor (same shape for comments_/replies_) and an
# optional working_window string to its own repo_facts; nothing here
# hardcodes one tenant's throughput floor.
def _metric(today_key, floor_key):
    today = repo_facts.get(today_key)
    floor = repo_facts.get(floor_key)
    if not isinstance(today, (int, float)):
        return "н/д"
    if isinstance(floor, (int, float)):
        return f"{int(today)}/{int(floor)}"
    return str(int(today))

_now_hhmm = datetime.datetime.now(datetime.timezone.utc).strftime("%H:%M")
_window = repo_facts.get("working_window") or repo_facts.get("ny_window")
_product_bits = [
    _now_hhmm,
    f"посты {_metric('posts_today', 'posts_floor')}",
    f"комменты {_metric('comments_today', 'comments_floor')}",
    f"реплаи {_metric('replies_today', 'replies_floor')}",
]
if _window:
    _product_bits.append(f"окно {_window}")
product_line = " · ".join(_product_bits)

# ── rule 5: one decisions line. ────────────────────────────────────────────
if questions:
    _q0 = questions[0] if isinstance(questions, list) and questions else None
    _qtext = None
    if isinstance(_q0, dict):
        _qtext = _q0.get("question") or _q0.get("summary_for_lead")
    elif isinstance(_q0, str):
        _qtext = _q0
    decisions_line = (
        f"Ждёт решения: {_qtext}" if _qtext
        else f"Ждёт решения: {len(questions)} вопрос(ов) — см. founder-status-full.md"
    )
else:
    decisions_line = "Решений не ждёт."

# ── rule 6: nothing cut is lost — full doc, single writer, atomic write. ──
full_md = "\n\n".join([
    full_table_md,
    detail_md,
    queue_md,
    f"Закрыто сегодня: {closed_paragraph}",
])
full_status_path = full_status_path_override
try:
    _full_tmp = full_status_path + ".tmp"
    with open(_full_tmp, "w", encoding="utf-8") as fh:
        fh.write(full_md + "\n")
    os.replace(_full_tmp, full_status_path)
    full_doc_ok = True
except OSError:
    full_doc_ok = False

# fix-round-3 (NEW-6): a row hidden by the cap (own or foreign) was never
# junk -- it's a live lane that didn't fit -- but the old wording
# ("мусорных/лишних строк") labeled it garbage regardless. Split the two:
# an actual duplicate the dedup pass dropped (a real redundant row) keeps
# the junk wording; a row that simply didn't fit under TABLE_ROW_CAP gets
# honest "не поместилось" phrasing instead.
hidden_bits = []
# fix-round-4 (Medium): _own_rows_hidden/_foreign_rows_hidden were computed
# above and then discarded into one combined number, which hides WHICH side
# is starved (a founder reading "4 строк не поместилось" cannot tell if
# that is his own work or a foreign lane). Report them separately.
if _own_rows_hidden:
    hidden_bits.append(f"{_own_rows_hidden} своих строк не поместилось")
if _foreign_rows_hidden:
    hidden_bits.append(f"{_foreign_rows_hidden} чужих строк не поместилось")
if _dedup_dropped_count:
    hidden_bits.append(f"{_dedup_dropped_count} дублирующих строк")
_queue_line_count = len(queue_md.splitlines())
if _queue_line_count:
    hidden_bits.append(f"{_queue_line_count} строк очереди")
hidden_note = (
    f"(скрыто: {', '.join(hidden_bits)} — docs/leadv2/founder-status-full.md)"
    if (hidden_bits and full_doc_ok)
    else "(полная версия недоступна для записи — docs/leadv2/founder-status-full.md)" if hidden_bits
    else None
)

# ── previous-beat snapshot: single writer (this script, called only from
#    the sentinel-owned supervise loop), atomic tmp+os.replace. ────────────
new_prev = {
    "beat_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "lanes": current_lane_digest,
}
tmp_prev = prev_path + ".tmp"
with open(tmp_prev, "w", encoding="utf-8") as fh:
    json.dump(new_prev, fh)
os.replace(tmp_prev, prev_path)

out_path = os.path.join(tmpdir, "render.json")
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump({
        "table_md": table_md,
        "detail_md": detail_md,
        "closed_paragraph": closed_paragraph,
        "queue_md": queue_md,
        "rows": len(table_rows),
        "tail_facts": tail_facts,
        "product_line": product_line,
        "delta_line": delta_line,
        "decisions_line": decisions_line,
        "pulse_md": pulse_md,
        "hidden_note": hidden_note,
        "empty_headline": empty_headline,
    }, fh)
print(out_path)
PY
RENDER_JSON="$(python3 "$RENDER_TMPDIR/render.py" "$SNAPSHOT_PATH" "$PREV_PATH" "$PROJECT_ROOT" "$TASKS_LIB_SH" "$RENDER_TMPDIR" "$SCRIPT_DIR" "$FOUNDER_STATUS_FULL_PATH" "$EMPTY_SINCE_PATH" </dev/null)"
RC=$?
if [[ $RC -ne 0 || -z "$RENDER_JSON" || ! -f "$RENDER_JSON" ]]; then
  printf '%s [BROAD_STATUS] render failure: table unavailable\n' "$BEAT_AT" >>"$LOG_FILE"
  # Same policy as the collector path: replace the artifact, then (and only
  # then) wake; refuse READY entirely if the replacement itself failed.
  if _write_degraded_status "рендер таблицы не выполнен (render failed)"; then
    _emit_ready_line "-" degraded
  else
    _emit_fail_line "render failure + founder-status.md not writable"
  fi
  exit 0
fi

TABLE_MD="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['table_md'])" "$RENDER_JSON")"
ROWS_N="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['rows'])" "$RENDER_JSON")"
PRODUCT_LINE="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['product_line'])" "$RENDER_JSON")"
DELTA_LINE="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['delta_line'])" "$RENDER_JSON")"
DECISIONS_LINE="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['decisions_line'])" "$RENDER_JSON")"
HIDDEN_NOTE="$(python3 -c "import json,sys; v=json.load(open(sys.argv[1])).get('hidden_note'); print(v or '')" "$RENDER_JSON")"
EMPTY_HEADLINE="$(python3 -c "import json,sys; v=json.load(open(sys.argv[1])).get('empty_headline'); print(v or '')" "$RENDER_JSON")"
PULSE_MD="$(python3 -c "import json,sys; v=json.load(open(sys.argv[1])).get('pulse_md'); print(v or '')" "$RENDER_JSON")"

# PULSE-EMPTY-BOARD-01 rule 4: a review verdict that landed since the last
# beat (leadv2-pulse-beat.sh's transition detector, exported by the caller)
# is folded onto the deterministic delta line — never invented here, and
# never dropped silently if the composer runs with the var unset (normal
# clock-driven beats never set it).
if [[ -n "${LEADV2_BROAD_STATUS_REVIEW_DELTA:-}" ]]; then
  DELTA_LINE="${DELTA_LINE} ${LEADV2_BROAD_STATUS_REVIEW_DELTA}"
fi

# PULSE-READABLE-01: the delta and decisions lines are now fully
# deterministic (rules 4/5 — set-diff against the previous beat's lane
# digest, first pending question verbatim), so the Haiku prose pass that
# used to write them is gone. That pass was also the beat's single
# highest-latency, single point of failure (a Haiku outage degraded the
# whole tail to a canned "недоступна" line) — removing it makes every beat
# both correct and un-skippable. Everything it used to narrate at length
# (full lane detail, full queue, full closed-paragraph) still lands in
# founder-status-full.md, written above by the python render step.
# PULSE-EMPTY-BOARD-01 rule 1: an empty board is a headline, not a table
# with no rows — it must be unmistakable in the first two lines. Line 1
# stays the machine-parseable dispatched= stamp (the relay contract's
# format), so the headline is line 2, ahead of everything else, when set.
# LEAD-WORKER-CHANNEL-01: drain the durable lead inbox on every beat, so an
# unread worker event reaches this status EVEN IF every SendMessage wake-up
# was lost -- that is the property that makes the mechanism real rather
# than another thing that only works when everything already works. Lead
# id resolved the same way leadv2-dispatch-code.sh computes
# _lead_session_id, since this beat runs under that same lead's session.
# Never fatal: an inbox drain failure degrades to no inbox section, not a
# failed beat.
_LWC_LEAD_ID="${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-${CLAUDE_SESSION_ID:-direct}}}"
INBOX_MD="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-inbox.sh" drain --lead "${_LWC_LEAD_ID}" 2>/dev/null || true)"

BLOCK="$(
  printf '%s [BROAD_STATUS] dispatched=%s\n' "$BEAT_AT" "$DISPATCHED"
  if [[ -n "$EMPTY_HEADLINE" ]]; then
    printf '%s\n\n' "$EMPTY_HEADLINE"
  fi
  printf '%s\n\n' "$PRODUCT_LINE"
  printf '%s\n\n' "$TABLE_MD"
  printf '%s\n' "$DELTA_LINE"
  # MON-PULSE-01 H4: the lane pulse section — the founder-facing route for
  # watcher events. Printed only when a board lane has a pulse.md.
  if [[ -n "$PULSE_MD" ]]; then
    printf '\n%s\n' "$PULSE_MD"
  fi
  if [[ -n "$INBOX_MD" ]]; then
    printf '\n**Unread lead-worker events:**\n%s\n' "$INBOX_MD"
  fi
  printf '%s\n' "$DECISIONS_LINE"
  if [[ -n "$HIDDEN_NOTE" ]]; then
    printf '%s\n' "$HIDDEN_NOTE"
  fi
  printf '[BROAD_STATUS_END]\n'
)"

printf '%s\n' "$BLOCK" >>"$LOG_FILE"
printf '%s\n' "$BLOCK" >"$FOUNDER_STATUS_PATH.tmp" && mv "$FOUNDER_STATUS_PATH.tmp" "$FOUNDER_STATUS_PATH" && _stamp_epoch

# C1 delivery: the ONE wake per beat, after both durable writes succeeded.
_emit_ready_line "$ROWS_N"
