#!/usr/bin/env bash
# pre-compact-task-freeze.sh — PreCompact hook (LEAD-COMPACT-SURVIVAL-01).
#
# Problem this fixes: /compact is a generative rewrite. Nothing pins the open
# task-id list through it. Evidence:
# docs/handoff/LEAD-ANCHOR-01/long-session-analysis.md — 27 compacts across two
# sessions; at the LAST compact of each, 136/139 and 191/191 task-ids mentioned
# before the compact never resurfaced after it. That's forgetting, not closing.
#
# Fix: before compact, freeze everything that must survive into
# <leadv2_dir>/.compact-freeze.md AND print it to stdout — PreCompact stdout
# is fed into the compact summarizer's context, so the task list physically
# survives the rewrite instead of depending on a prompt-text reminder.
#
# Source of truth: FILE ONLY.
#   - docs/tasks.yaml            (file mirror of Supabase work_items; status
#                                  open/in_progress == anything not in a
#                                  closed-status set — see CLOSED_STATUSES)
#   - <leadv2_dir>/open-threads.md          (open state only, post
#                                             OPEN-THREADS-HYGIENE-01 — see
#                                             scripts/leadv2-thread-prune.sh;
#                                             capped, not necessarily verbatim)
#   - <leadv2_dir>/scheduled-decisions.md   (DUE/OVERDUE rows only)
#   - <leadv2_dir>/tasks/*/journal.md       (tail of the most recently
#                                             touched journal, best-effort)
#   - plugin docs/single-lead-pulse.md      (pointed to, never embedded — a
#                                             real file survives a compact by
#                                             existing on disk, not by being
#                                             re-injected into chat context)
# NO network, NO Supabase call — after a compact nobody goes to the network,
# that is the entire premise of this hook.
#
# Cap: 80 lines by default (COMPACT-FREEZE-DIET-01, founder order 2026-07-30 —
# the 120-line/12-row/40-line ceilings let a 07-18 SESSION MODE block, a
# 372-task list and 183 ledger rows all ride into every compact). Gated by
# LEADV2_FREEZE_DIET (default "1"): open task ids trim to top-5, open threads
# filter to "leading ISO date within last 7 days OR undated in the file's last
# 40 lines" (cap 30 lines), scheduled decisions parse `## SD-` + `- Due:` into
# one clean `SD-id — status — why` row per OVERDUE/DUE-TODAY item (cap 15,
# CLOSED/COLLAPSED and future-dated rows excluded). LEADV2_FREEZE_DIET=0
# restores the pre-diet behavior verbatim (CAP 120, task cap 10, old
# role_and_tail()/due_rows() logic) for rollback. On overflow the journal tail
# is trimmed first (down to zero); the open task-id list is NEVER truncated —
# it is the one thing this hook exists to protect.
#
# Fail-open: ANY error -> exit 0, empty stdout. A broken hook must never
# block a compact.
#
# COMPACT-DEDUP-02: run-once guard. When PreCompact fires this script more
# than once for the SAME compact event (observed live: this script is
# registered both directly in a user settings.json AND via at least one
# plugin-installed hooks.json copy), every registration independently prints
# the ~11KB freeze block -> it lands TWICE in the compact summarizer's
# context. The freeze computation + .compact-freeze.md write below always
# run unconditionally (that file is the load-bearing artifact the PostCompact
# reground hook reads); only the final STDOUT emission is gated by a
# session-keyed, TTL-reclaimed lock near the bottom of this file. See that
# block for the mechanism.
#
# stdlib-only (bash + python3, +PyYAML if present — degrades to a regex
# line-parser without it), zero network, target <400ms.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/leadv2-temp.sh"
trap 'exit 0' ERR

# ── capture the hook's real stdin (JSON payload) before any heredoc can ─────
# consume it (heredocs piped into `python3 -` would otherwise steal stdin).
TMPFILE="$(lv2_mktemp_file "pe-compact-freeze" "json")" || exit 0
trap 'rm -f "${TMPFILE:-}"' EXIT
trap 'rm -f "${TMPFILE:-}"; exit 0' ERR
python3 -c "import sys; open('$TMPFILE','w').write(sys.stdin.read())" 2>/dev/null || exit 0

OUT="$(python3 - "$TMPFILE" <<'PYEOF' 2>/dev/null
import sys, os, re, json, subprocess, glob, datetime

CAP_LEGACY = 120
CAP_DIET = 80
CLOSED_STATUSES = {
    "done", "closed", "resolved", "complete", "completed",
    "cancelled", "canceled",
}


def git_toplevel(path):
    try:
        r = subprocess.run(
            ["git", "-C", path, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=2,
        )
        top = r.stdout.strip()
        return os.path.realpath(top) if r.returncode == 0 and top else path
    except Exception:
        return path


def resolve_leadv2_dir(root):
    sp = os.path.join(root, ".claude", "leadv2-overrides", "state-paths.yaml")
    try:
        with open(sp, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"^\s*leadv2_dir\s*:\s*(.+?)\s*$", line)
                if m:
                    val = m.group(1).strip().strip("'\"")
                    if val and val not in ("null", "~"):
                        return val
    except Exception:
        pass
    return "docs/leadv2"


def parse_tasks_yaml(path):
    """Return [(id, status, intent), ...] for tasks NOT in CLOSED_STATUSES.
    Tries PyYAML first (correctly handles folded multi-line intent scalars);
    falls back to a stdlib-only regex line-parser if PyYAML is unavailable
    or the file fails to parse.
    """
    try:
        import yaml
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
        out = []
        for t in (data.get("tasks") or []):
            tid = str(t.get("id", "")).strip()
            status = str(t.get("status", "")).strip()
            intent = str(t.get("intent", "")).strip()
            priority = str(t.get("priority", "")).strip()
            if tid and status.lower() not in CLOSED_STATUSES:
                out.append((tid, status, intent, priority))
        return out
    except Exception:
        pass
    out = []
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        for entry in re.split(r"\n(?=- id:\s)", text):
            m_id = re.search(r"^- id:\s*(\S+)", entry)
            m_status = re.search(r"\n\s*status:\s*(\S+)", entry)
            if not m_id or not m_status:
                continue
            m_intent = re.search(r"\n\s*intent:\s*'?(.+)", entry)
            m_priority = re.search(r"\n\s*priority:\s*'?([Pp]\d)", entry)
            tid = m_id.group(1).strip()
            status = m_status.group(1).strip()
            intent = (m_intent.group(1).strip() if m_intent else "")[:120]
            priority = (m_priority.group(1).strip().upper() if m_priority else "")
            if status.lower() not in CLOSED_STATUSES:
                out.append((tid, status, intent, priority))
    except Exception:
        pass
    return out


def read_file(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().splitlines()
    except Exception:
        return []


def due_rows(path):
    """Legacy (LEADV2_FREEZE_DIET=0) path — COMPACT-LEDGER-BLOAT-01: keep only
    the newest N raw lines containing an ALL-CAPS DUE/OVERDUE token, clipped to
    max_chars. Superseded by due_rows_diet() under the default diet mode; kept
    verbatim for rollback."""
    max_rows = int(os.environ.get("LEADV2_FREEZE_SD_ROWS", "12"))
    max_chars = int(os.environ.get("LEADV2_FREEZE_SD_CHARS", "220"))
    rows = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if re.search(r"\b(DUE|OVERDUE)\b", line):
                    rows.append(line.rstrip("\n"))
    except Exception:
        pass
    dropped = len(rows) - max_rows
    if dropped > 0:
        rows = rows[-max_rows:]
    clipped = []
    for r in rows:
        r = re.sub(r"\s+", " ", r).strip()
        if len(r) > max_chars:
            r = r[:max_chars].rstrip() + " …"
        clipped.append(r)
    if dropped > 0:
        clipped.insert(0, f"(… {dropped} older ledger rows omitted; full text in docs/leadv2/scheduled-decisions.md)")
    return clipped


def _strip_md(s):
    return re.sub(r"\*+", "", s).strip()


def due_rows_diet(path, today, max_rows=15, max_chars=200):
    """COMPACT-FREEZE-DIET-01: structured ledger parse. Splits
    scheduled-decisions.md into `## SD-...` blocks, drops CLOSED/COLLAPSED
    rows, and classifies each remaining row as OVERDUE / DUE TODAY / (skip)
    by parsing its `- Due:` bullet (ISO-date prefix compared to `today`);
    rows with no `- Due:` bullet fall back to the legacy inline header
    keywords (STILL DUE / DUE TODAY / OVERDUE). Condition-bound rows (a
    `- Due:` bullet with no parseable ISO date, e.g. "on next codex plugin
    update") are intentionally excluded here — they belong to the daily
    scan tier (scheduled-decisions-run.sh), not the compact freeze. Emits
    one clean `SD-id — status — why` line per row; never dumps raw body."""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except Exception:
        return []

    blocks = re.split(r"\n(?=##\s*SD-)", text)
    rows = []
    for block in blocks:
        m_head = re.match(r"##\s*(SD-[A-Za-z0-9_-]+)\s*(.*)", block)
        if not m_head:
            continue
        sd_id = m_head.group(1)
        header_rest = m_head.group(2)
        if re.search(r"\bCLOSED\b|\bCOLLAPSED\b", header_rest, re.I):
            continue

        lines = block.splitlines()
        due_text = None
        why_text = None
        for line in lines[1:]:
            if due_text is None:
                m_due = re.match(r"^-\s*\*{0,2}[Dd]ue:?\*{0,2}\s*(.+)$", line)
                if m_due:
                    due_text = _strip_md(m_due.group(1))
                    continue
            if why_text is None:
                m_why = re.match(r"^-\s*\*{0,2}[Ww]hy:?\*{0,2}\s*(.+)$", line)
                if m_why:
                    why_text = _strip_md(m_why.group(1))

        status = None
        if due_text is not None:
            m_iso = re.match(r"(\d{4}-\d{2}-\d{2})", due_text)
            if m_iso:
                try:
                    due_date = datetime.date.fromisoformat(m_iso.group(1))
                except Exception:
                    due_date = None
                if due_date is not None:
                    if due_date < today:
                        status = "OVERDUE"
                    elif due_date == today:
                        status = "DUE TODAY"
                    # future-dated -> not yet due, skip
            # non-ISO due text (condition-bound) -> skip (daily-scan tier owns it)
        else:
            if re.search(r"\bOVERDUE\b", header_rest, re.I):
                status = "OVERDUE"
            elif re.search(r"STILL DUE\b|DUE TODAY\b", header_rest, re.I):
                status = "DUE TODAY"

        if status is None:
            continue

        why = why_text if why_text else _strip_md(header_rest.lstrip("— -").strip())
        why = re.sub(r"\s+", " ", why).strip()
        row = f"{sd_id} — {status} — {why}"
        if len(row) > max_chars:
            row = row[:max_chars].rstrip() + " …"
        rows.append(row)

    dropped = len(rows) - max_rows
    if dropped > 0:
        rows = rows[-max_rows:]
        rows.insert(0, f"(… {dropped} older OVERDUE/DUE-TODAY rows omitted; full ledger in docs/leadv2/scheduled-decisions.md)")
    return rows


# OT-SESSION-SCOPE-01: optional advisory [s:<sid8>] session tag between the
# timestamp and the em-dash. group(1)=ts  group(2)=sid8 or None  group(3)=text.
# Both hooks carry this helper verbatim (separate processes, no shared module);
# keep the text identical so a diff between them makes drift visible.
_ENTRY_RE = re.compile(r"^- \[ \] (\S+)(?: \[s:([A-Za-z0-9._-]{1,8})\])? — (.*)$")


def _filter_by_session(lines, session_id):
    """OT-SESSION-SCOPE-01: keep untagged lines + lines tagged for THIS session.
    Returns (kept, hidden_count). Unknown session -> behave exactly as before
    (every line kept). Non-entry lines are never dropped."""
    mine = re.sub(r"[^A-Za-z0-9._-]", "", str(session_id or ""))[:8]
    if not mine:
        return lines, 0
    kept, hidden = [], 0
    for line in lines:
        m = _ENTRY_RE.match(line)
        if m and m.group(2) and m.group(2) != mine:
            hidden += 1
            continue
        kept.append(line)
    return kept, hidden


def _leading_date(line):
    stripped = re.sub(r"^[\s\-#*\[\]]*", "", line)
    m = re.match(r"(\d{4}-\d{2}-\d{2})", stripped)
    if not m:
        return None
    try:
        return datetime.date.fromisoformat(m.group(1))
    except Exception:
        return None


def filter_threads_diet(lines, today, tail_n=40, cap=30):
    """COMPACT-FREEZE-DIET-01: keep a line only if (a) it carries a leading
    ISO date within the last 7 days, or (b) it is undated AND within the
    file's last `tail_n` lines. This is what stops a stale, undated block
    (e.g. the 2026-07-18 SESSION MODE head) from surviving — it has no
    leading date and, in a multi-hundred-line file, sits well outside the
    tail window. Hard-caps the result to `cap` lines (keeps the newest)."""
    cutoff = today - datetime.timedelta(days=7)
    tail_start = max(0, len(lines) - tail_n)
    kept = []
    for i, line in enumerate(lines):
        d = _leading_date(line)
        if d is not None:
            if d >= cutoff:
                kept.append(line)
        elif i >= tail_start:
            kept.append(line)
    dropped = len(kept) - cap
    if dropped > 0:
        kept = kept[-cap:]
        kept.insert(0, f"… {dropped} older/undated lines dropped (full history in docs/leadv2/open-threads.md) …")
    return kept


def latest_journal_tail(root, leadv2_dir, n=15):
    pattern = os.path.join(root, leadv2_dir, "tasks", "*", "journal.md")
    try:
        files = glob.glob(pattern)
        if not files:
            return None, []
        latest = max(files, key=lambda p: os.path.getmtime(p))
        task_id = os.path.basename(os.path.dirname(latest))
        with open(latest, encoding="utf-8") as f:
            lines = [l.rstrip("\n") for l in f if l.strip()]
        return task_id, lines[-n:]
    except Exception:
        return None, []


def role_and_tail(lines, tail_n=40):
    """COMPACT-DEDUP-01 FU2: open-threads.md was embedded VERBATIM (broke the
    120-line CAP -- 643 ln / 105KB observed live). Bound it instead to the two
    things with actual resume value, per the SESSION-HANDOFF-01 design panel's
    Carry table (role sacrosanct, tail truncates first):
      - ROLE block: open-threads.md's own head (WHO YOU ARE + founder
        standing rules) -- structurally the span up to the 3rd "# N."
        heading (keeps sections 1+2, drops volatile section 3+). Falls back
        to the first 28 lines if the file has fewer than 3 numbered headings.
      - FRESHEST tail: last `tail_n` lines -- open-threads.md is an
        append-only log, so the tail is always the newest entries.
    Short files (role + tail would overlap) are returned whole -- nothing to
    save by truncating. Returns (role_lines, tail_lines, dropped_count).
    """
    heading_idxs = [i for i, l in enumerate(lines) if re.match(r"^#\s*\d+\.", l)]
    role_end = heading_idxs[2] if len(heading_idxs) >= 3 else min(28, len(lines))
    tail_start = max(role_end, len(lines) - tail_n)
    if tail_start <= role_end:
        return lines, [], 0
    return lines[:role_end], lines[tail_start:], tail_start - role_end


def main():
    with open(sys.argv[1], encoding="utf-8") as f:
        try:
            payload = json.load(f)
        except Exception:
            payload = {}
    cwd = payload.get("cwd") or os.getcwd()
    root = git_toplevel(os.path.realpath(cwd))
    leadv2_dir = resolve_leadv2_dir(root)
    leadv2_abs = os.path.join(root, leadv2_dir)
    if not os.path.isdir(leadv2_abs):
        return  # other repo without a leadv2 tree — silent no-op

    # OT-SESSION-SCOPE-01: scope the open-threads view to THIS session.
    session_id = payload.get("session_id")

    tasks_yaml = os.path.join(root, "docs", "tasks.yaml")
    open_tasks = parse_tasks_yaml(tasks_yaml) if os.path.isfile(tasks_yaml) else []

    # COMPACT-FREEZE-DIET-01 (founder order 2026-07-30): default ON, =0 restores
    # the pre-diet 120-line/cap-10/role_and_tail/due_rows behavior verbatim.
    diet = os.environ.get("LEADV2_FREEZE_DIET", "1") != "0"
    CAP = CAP_DIET if diet else CAP_LEGACY
    now_utc = datetime.datetime.now(datetime.timezone.utc)
    today = now_utc.date()

    ts = now_utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    header = [f"# compact-freeze @ {ts}", f"open_task_count: {len(open_tasks)}"]

    # Cap the dumped task list to the top-N by priority (P0<P1<P2<P3<unranked).
    # The FULL backlog always stays in docs/tasks.yaml; this only bounds the
    # per-compact context injection (LEADV2_FREEZE_TASK_CAP overrides; default
    # 5 under diet mode, 10 under legacy).
    default_task_cap = "5" if diet else "10"
    task_dump_cap = int(os.environ.get("LEADV2_FREEZE_TASK_CAP", default_task_cap))
    def _prank(pr):
        m = re.match(r"[Pp](\d)", pr or "")
        return int(m.group(1)) if m else 9
    ranked = sorted(enumerate(open_tasks), key=lambda x: (_prank(x[1][3]), x[0]))
    shown = [t for _, t in ranked[:task_dump_cap]]
    hidden = len(open_tasks) - len(shown)
    task_lines = [
        f"## OPEN TASK IDS (docs/tasks.yaml \u2014 top {task_dump_cap} by priority; full list in file)"
    ]
    for tid, status, intent, priority in shown:
        snippet = re.sub(r"\s+", " ", intent).strip()[:70]
        pfx = (priority + " ") if priority else ""
        task_lines.append(f"- {tid} [{status}] {pfx}{snippet}")
    if not open_tasks:
        task_lines.append("(none found / docs/tasks.yaml missing or empty)")
    elif hidden > 0:
        task_lines.append(
            f"- \u2026 +{hidden} more open tasks hidden (P0->P3->unranked sort; see docs/tasks.yaml)"
        )

    # OPEN-THREADS-HYGIENE-01: open-threads.md is now open STATE only (a
    # question awaiting an answer / a promised action not yet taken / a live
    # background job), self-pruned via leadv2-thread-prune.sh \u2014 it no longer
    # carries a hand-written, ever-growing role/status head block, so there
    # is nothing "stable" left to split out with role_and_tail(). Freeze the
    # (now-bounded) file as-is; role_and_tail's short-file path already
    # returns it whole when there's nothing worth truncating. The supervisor
    # role definition itself lives outside this file entirely (it's a real,
    # rarely-edited file \u2014 it survives a compact by existing on disk, not by
    # being re-injected into chat context every time) and is only pointed to
    # here, never embedded.
    ot_lines = read_file(os.path.join(leadv2_abs, "open-threads.md"))
    # OT-SESSION-SCOPE-01: drop other sessions' tagged asks BEFORE diet/legacy
    # capping so both paths inherit the scoped set. No session_id -> unchanged.
    ot_lines, ot_hidden = _filter_by_session(ot_lines, session_id)
    ot_section = []
    if ot_lines:
        threads_tail_n = int(os.environ.get("LEADV2_FREEZE_THREADS_TAIL", "40"))
        ot_section = [
            "## OPEN THREADS (docs/leadv2/open-threads.md; capped, not verbatim)",
            "single-lead role definition (stable, not frozen here): "
            + os.environ.get("CLAUDE_PLUGIN_ROOT", "${CLAUDE_PLUGIN_ROOT}")
            + "/docs/single-lead-pulse.md",
        ]
        if ot_hidden:
            ot_section.append(
                f"({ot_hidden} thread(s) from other sessions hidden)"
            )
        if diet:
            threads_cap = int(os.environ.get("LEADV2_FREEZE_THREADS_CAP", "30"))
            ot_section += filter_threads_diet(ot_lines, today, tail_n=threads_tail_n, cap=threads_cap)
        else:
            role_lines, tail_lines, dropped = role_and_tail(ot_lines, tail_n=threads_tail_n)
            ot_section += role_lines
            if dropped:
                ot_section.append(
                    f"\u2026 {dropped} stale middle lines dropped (full history in docs/leadv2/open-threads.md) \u2026"
                )
            ot_section += tail_lines

    if diet:
        sd_max_rows = int(os.environ.get("LEADV2_FREEZE_SD_ROWS", "15"))
        sd_max_chars = int(os.environ.get("LEADV2_FREEZE_SD_CHARS", "200"))
        sd_rows = due_rows_diet(
            os.path.join(leadv2_abs, "scheduled-decisions.md"), today,
            max_rows=sd_max_rows, max_chars=sd_max_chars,
        )
    else:
        sd_rows = due_rows(os.path.join(leadv2_abs, "scheduled-decisions.md"))
    sd_section = ["## SCHEDULED DECISIONS — DUE/OVERDUE"] + sd_rows if sd_rows else []

    journal_task_id, journal_lines_full = latest_journal_tail(root, leadv2_dir)

    fixed_lines = header + task_lines + ot_section + sd_section
    # NEVER cut fixed_lines (task-id list is the one inviolable section).
    # Overflow is absorbed entirely by shrinking (or dropping) the journal tail.
    budget = CAP - len(fixed_lines) - 1  # -1 reserves the journal heading line
    journal_section = []
    if journal_lines_full and budget > 0:
        take = min(budget, len(journal_lines_full))
        journal_section = [f"## ACTIVE JOURNAL TAIL ({journal_task_id})"] + journal_lines_full[-take:]

    out_text = "\n".join(fixed_lines + journal_section) + "\n"

    try:
        with open(os.path.join(leadv2_abs, ".compact-freeze.md"), "w", encoding="utf-8") as f:
            f.write(out_text)
    except Exception:
        pass  # write is best-effort; stdout below still carries the freeze

    print(out_text, end="")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
PYEOF
)" || exit 0

# ── COMPACT-DEDUP-02: run-once guard — gates STDOUT emission only ──────────
# The freeze block was already computed and written to .compact-freeze.md
# above, unconditionally, regardless of what happens next. This guard only
# decides whether THIS invocation is the one whose stdout actually reaches
# PreCompact (and therefore the compact summarizer). Keyed by session_id
# (from the captured payload) so two DIFFERENT sessions compacting at the
# same time never suppress each other; a short TTL reclaims a lock left
# behind by a crashed prior run so a genuinely fresh compact is never
# silently swallowed. Any failure in this block fails OPEN (EMIT=1) — a rare
# double-print is far cheaper than losing the freeze entirely.
set +e
EMIT=1
LOCK_TTL_S=60
LOCK_ROOT="${TMPDIR:-/tmp}/leadv2-precompact-freeze-locks"
mkdir -p "$LOCK_ROOT" 2>/dev/null
SESSION_KEY="$(python3 -c "
import json, sys
try:
    with open(sys.argv[1], encoding='utf-8') as f:
        d = json.load(f)
    print(str(d.get('session_id') or '').strip())
except Exception:
    print('')
" "$TMPFILE" 2>/dev/null)"
SESSION_KEY="$(printf '%s' "${SESSION_KEY:-}" | tr -c 'A-Za-z0-9_-' '_')"
[[ -z "$SESSION_KEY" ]] && SESSION_KEY="nosession"
LOCK_DIR="$LOCK_ROOT/${SESSION_KEY}.lock"

if mkdir "$LOCK_DIR" 2>/dev/null; then
  date +%s >"$LOCK_DIR/ts" 2>/dev/null
  EMIT=1
else
  LOCK_TS="$(cat "$LOCK_DIR/ts" 2>/dev/null)"
  [[ "$LOCK_TS" =~ ^[0-9]+$ ]] || LOCK_TS=0
  NOW="$(date +%s)"
  AGE=$(( NOW - LOCK_TS ))
  if [[ "$AGE" -gt "$LOCK_TTL_S" ]]; then
    # Stale lock from a crashed / long-finished prior compact — reclaim.
    rm -rf "$LOCK_DIR" 2>/dev/null
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      date +%s >"$LOCK_DIR/ts" 2>/dev/null
      EMIT=1
    else
      EMIT=1  # reclaim race — fail open
    fi
  else
    EMIT=0  # duplicate registration firing within the same compact — suppress
  fi
fi
set -e

[[ -n "$OUT" && "$EMIT" == "1" ]] && printf -- '%s\n' "$OUT"
exit 0
