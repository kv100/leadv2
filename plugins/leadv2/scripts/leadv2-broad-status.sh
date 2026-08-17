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
# ready-line (the beat branch in leadv2-supervise-loop.sh is the only caller,
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
COLLECTOR_SH="${LEADV2_STATUS_COLLECTOR_BIN:-$SCRIPT_DIR/leadv2-status-collector.sh}"
TASKS_LIB_SH="${LEADV2_TASKS_LIB_BIN:-$SCRIPT_DIR/leadv2-tasks-lib.sh}"
CLAUDE_BIN="${LEADV2_BROAD_STATUS_CLAUDE_BIN:-claude}"

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
# twice; lib absent → pass-through emit (R2) — this script runs once per
# BROAD_STATUS_S window, not per poll, so pass-through is still one line per
# beat.
ALARM_LIB="${LEADV2_ALARM_DEDUPE_BIN:-${SCRIPT_DIR}/lib/leadv2-alarm-dedupe.sh}"
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

# ── failed-beat artifact policy (PULSE-IS-A-PLUGIN-DUTY-01 fix r1) ──────────
# A failed beat must never leave the PREVIOUS beat's healthy table in place
# while claiming freshness: the ready-line points at founder-status.md, so
# the artifact itself has to carry the failure. Replace it with an explicit
# degraded block (same envelope, same content contract: one lane table + 2
# prose lines, same atomic tmp+mv write as the happy path) and only then
# signal READY degraded. If even that write fails, refuse READY entirely:
# BROAD_STATUS_FAILED carries no path= token, so nothing points the founder
# at the stale file, while the URGENT substring still wakes them (C1).
_write_degraded_status() {  # <reason> -> rc 0 if the artifact was replaced
  local reason="$1" block
  block="$(
    printf '%s [BROAD_STATUS] dispatched=%s degraded=1\n' "$BEAT_AT" "$DISPATCHED"
    printf '| Линия | Что делает | Состояние |\n'
    printf '|---|---|---|\n'
    printf '| (статус не собран) | — | %s |\n\n' "$reason"
    printf 'СТАТУС НЕ СОБРАН на beat %s: %s.\n' "$BEAT_AT" "$reason"
    printf 'Таблица линий за этот beat недоступна — это НЕ значит, что линий нет.\n'
    printf '[BROAD_STATUS_END]\n'
  )"
  printf '%s\n' "$block" >>"$LOG_FILE"
  printf '%s\n' "$block" >"$FOUNDER_STATUS_PATH.tmp" 2>/dev/null \
    && mv "$FOUNDER_STATUS_PATH.tmp" "$FOUNDER_STATUS_PATH" 2>/dev/null
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
RENDER_JSON="$(python3 - "$SNAPSHOT_PATH" "$PREV_PATH" "$PROJECT_ROOT" "$TASKS_LIB_SH" "$RENDER_TMPDIR" "$SCRIPT_DIR" <<'PY'
import datetime, json, os, re, sys

snapshot_path, prev_path, root, tasks_lib_sh, tmpdir, script_dir = sys.argv[1:7]

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
lanes_data = lanes_section.get("data", {}) if isinstance(lanes_section.get("data"), dict) else {}
table_rows = lanes_data.get("table") or []
questions = lanes_data.get("questions") or lanes_data.get("requires_founder") or []
degraded = lanes_data.get("degraded") or []

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


rows_out = []
detail_lines = []
closed_items = []
current_lane_digest = {}
for row in table_rows:
    tid = str(row.get("task_id") or "?")
    d = detail_by_task.get(tid)

    # id_display: dispatch id when the dispatch binding is known, else the
    # raw founder task_id with an explicit marker (never silently pass one
    # off as the other). BROAD-STATUS-RENDERER-01 D1: a task id that IS
    # "dispatch-<hex>" carries its own dispatch id — same identity rule as
    # leadv2-lane-detail.sh, applied here too because tombstone rows (no
    # lane_detail row at all) were still rendered "(dispatch id unknown)"
    # while the id sat in their own name. This id is a fallback for col-1
    # ONLY (below) and always the source of the diagnostic detail line.
    dispatch_id = d.get("dispatch_id") if d else None
    if dispatch_id:
        id_display = f"dispatch-{dispatch_id}"
    elif re.match(r"^dispatch-[0-9a-f]{6,40}$", tid):
        id_display = tid
    else:
        id_display = f"{tid} (dispatch id unknown)"

    # STATUS-FORMAT-IN-RENDERER-01: Линия / Что делает come ONLY from the
    # mission title, never from the prepass excerpt (that stays in "owns"
    # for the detail block). Name is frozen on first resolution in
    # .broad-status-prev.json so it cannot drift between beats (R2).
    prev_row_name = (prev_lanes.get(tid) or {}).get("name") if isinstance(prev_lanes.get(tid), dict) else None
    mission_title = d.get("mission_title") if d else None
    linia_name = prev_row_name or human_name(mission_title)
    # Only the NAME is frozen (§2.2) — the one-sentence description is
    # re-derived fresh from the mission title every beat.
    chto = product_sentence(mission_title) or "—"
    linia = linia_name if linia_name else f"{id_display} (имя неизвестно)"

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
    is_dead = bool(verdict) and str(verdict).startswith("dead:")
    prev_row = prev_lanes.get(tid)
    delta_note = None
    if d is not None:
        current_lane_digest[tid] = {"stream_bytes": stream_bytes, "disk_key": disk_key(disk)}
        if isinstance(prev_row, dict) and prev_row is not None and not is_dead:
            same_bytes = prev_row.get("stream_bytes") == stream_bytes
            same_disk = prev_row.get("disk_key") == disk_key(disk)
            if same_bytes and same_disk:
                mins = int((d.get("stream_mtime_age_s") or 0) / 60)
                delta_note = f"молчит {mins} мин (без изменений с прошлого статуса)"
    if linia_name:
        # freeze-on-first-resolution: only write a name once resolved; an
        # un-nameable lane keeps retrying fresh resolution every beat.
        current_lane_digest.setdefault(tid, {"stream_bytes": stream_bytes, "disk_key": disk_key(disk)})
        current_lane_digest[tid]["name"] = linia_name

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
    else:
        # tombstoned / pruned from active.yaml — no lane_detail row.
        sostoyanie = row.get("status_reason") or str(row.get("status") or "неизвестно")

    na_diske = fmt_disk(disk) if d else "пока ничего"

    if is_dead:
        closed_items.append({"name": linia, "cause": sostoyanie})
        continue

    rows_out.append(
        "| " + " | ".join(md_escape(x) for x in (linia, chto, sostoyanie)) + " |"
    )
    detail_lines.append(f"{id_display} — {kto} — {na_diske}")

# Change 2b: a failed lane_detail section must be visible ABOVE the table,
# not inferred from every row silently reading "неизвестно".
table_prefix = []
if not detail_ok:
    table_prefix.append(
        f"детали линий недоступны (lane_detail: {detail_fail_reason}) — "
        "колонки «Линия» и «Что делает» могут остаться неизвестны\n"
    )

table_md = "\n".join(table_prefix + [
    "| Линия | Что делает | Состояние |",
    "|---|---|---|",
] + (rows_out if rows_out else ["| (живых линий нет) | — | — |"]))

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
queue_md = "Очередь — по влиянию на 60/6:\n\n" + (
    "\n\n".join(queue_sections) if queue_sections else "(очередь пуста)"
)

tail_facts = {
    "queued_top5": queued_items,
    "landed_today": landed_items,
    "repo_facts": repo_facts,
    "questions_pending": questions,
    "degraded_dispatch": degraded,
    "lanes_summary": [
        {"task_id": r.get("task_id"), "status": r.get("status")} for r in table_rows
    ],
}

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
    }, fh)
print(out_path)
PY
)"
RC=$?
if [[ $RC -ne 0 || -z "$RENDER_JSON" || ! -f "$RENDER_JSON" ]]; then
  printf '%s [BROAD_STATUS] render failure: table unavailable\n' "$(_now_iso)" >>"$LOG_FILE"
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
DETAIL_MD="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['detail_md'])" "$RENDER_JSON")"
CLOSED_PARAGRAPH="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['closed_paragraph'])" "$RENDER_JSON")"
QUEUE_MD="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['queue_md'])" "$RENDER_JSON")"
ROWS_N="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['rows'])" "$RENDER_JSON")"
TAIL_FACTS_JSON="$(python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1]))['tail_facts'], ensure_ascii=False))" "$RENDER_JSON")"

# STATUS-FORMAT-IN-RENDERER-01 §3.3: the table, the queue bucketing and the
# «Закрыто сегодня» paragraph are ALL deterministic python above — Haiku's
# job narrows to exactly two prose lines that require judgment over numbers
# it must not invent: the delta line and the blockers line.
PROMPT="$(python3 - "$TAIL_FACTS_JSON" <<'PY'
import json, sys
facts = json.loads(sys.argv[1])
print('''Ты пишешь РОВНО ДВЕ строки простого русского текста, без Markdown, без JSON. Ничего больше не выводи.\n\nСтрока 1 (дельта): сегодняшний объём публикаций против цели и позиция в рабочем окне — бери числа ТОЛЬКО из facts.repo_facts; используй ИМЕННО поле hit_rate_today (не hit_rate — это all-time и НЕ про сегодня); если hit_rate_today равен null или отсутствует — напиши буквально «нет данных за сегодня».\n\nСтрока 2 (блокеры): если facts.questions_pending непустой — дословный текст вопроса(ов) плюс твоя рекомендация; если facts.degraded_dispatch непустой — явно назови, что prepass не сработал; если оба пусты — напиши буквально «вопросов нет».\n\nНикогда не изобретай числа, хэши или сравнения, которых нет в фактах. Стоимость — только как использование лимитов 5-часового и недельного окна, никогда деньги.\n\nФакты:\n''' + json.dumps(facts, ensure_ascii=False))
PY
)"

RAW="$("$CLAUDE_BIN" -p "$PROMPT" --model haiku --max-turns 1 --permission-mode bypassPermissions --output-format json 2>/dev/null)" || RAW=""
TAIL="$(python3 - "$RAW" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[1])
    text = d.get('result') if isinstance(d, dict) else None
    if isinstance(text, str) and text.strip():
        print(text.strip())
except Exception:
    pass
PY
)"

if [[ -z "$TAIL" ]]; then
  TAIL=$'дельта недоступна в этом beat (Haiku-читалка не ответила)\nвопросов нет (не проверено — читалка недоступна)'
fi

BLOCK="$(
  printf '%s [BROAD_STATUS] dispatched=%s\n' "$BEAT_AT" "$DISPATCHED"
  printf '%s\n\n%s\n\n' "$TABLE_MD" "$DETAIL_MD"
  printf '%s\n\n' "$QUEUE_MD"
  printf 'Закрыто сегодня: %s\n\n' "$CLOSED_PARAGRAPH"
  printf '%s\n' "$TAIL"
  printf '[BROAD_STATUS_END]\n'
)"

printf '%s\n' "$BLOCK" >>"$LOG_FILE"
printf '%s\n' "$BLOCK" >"$FOUNDER_STATUS_PATH.tmp" && mv "$FOUNDER_STATUS_PATH.tmp" "$FOUNDER_STATUS_PATH"

# C1 delivery: the ONE wake per beat, after both durable writes succeeded.
_emit_ready_line "$ROWS_N"
