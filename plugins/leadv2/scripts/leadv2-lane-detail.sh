#!/usr/bin/env bash
# leadv2-lane-detail.sh — per-lane ownership/worker/disk facts for the
# founder status table (SUPERVISOR-STATUS-TABLE-IN-PLUGIN-01).
#
# Deterministic, no LLM. Consumed as the "lane_detail" collector section by
# leadv2-status-collector.sh; the broad-status.sh table renderer joins this
# against the "lanes" section (leadv2-supervise.sh --json) per task_id.
#
# HARD RULE 1: ownership ("owns") is read ONLY from architect-prepass.md /
# fanout-lane mission.txt — never from a lane's *.stream.jsonl. Grepped by
# the task's acceptance evidence; keep it true.
# HARD RULE 2: liveness (verdict/age/reason) is taken VERBATIM from
# leadv2-lane-liveness.sh --all --json. This script never re-derives
# alive/dead and never infers liveness from a live PID.
#
# Usage: leadv2-lane-detail.sh --project-root <dir> [--json]
#
# Rollback: this section is additive-only (leadv2-status-collector.sh
# STATUS-COLLECTOR-01 section isolation) — a broken lane-detail.sh degrades
# the "lane_detail" section to {"ok": false, ...} without losing "lanes" or
# "repo_facts".

set -uo pipefail
trap 'exit 0' ERR   # a probe script's contract: never crash the timer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
    --json) shift ;;  # only output mode this script has; accepted for symmetry with lane-liveness.sh
    -h|--help)
      echo "Usage: leadv2-lane-detail.sh --project-root <dir> [--json]"
      exit 0 ;;
    *) shift ;;
  esac
done
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

# R1 (architect prepass, CRITICAL): resolve liveness via SCRIPT_DIR so a
# drifted .claude/scripts/ copy (known drift, see UNLANDED-FIXES-IN-USER-
# SCRIPTS-COPIES-01 sibling class) is visible in the artifact's
# liveness_source_path field instead of silently wrong.
LIVENESS_SH="${LEADV2_LANE_LIVENESS_BIN:-$SCRIPT_DIR/leadv2-lane-liveness.sh}"
LIVENESS_JSON="$(LEADV2_PROJECT_ROOT="$PROJECT_ROOT" PROJECT_ROOT="$PROJECT_ROOT" \
  bash "$LIVENESS_SH" --project-root "$PROJECT_ROOT" --all --json 2>/dev/null)" || LIVENESS_JSON=''
[[ -n "$LIVENESS_JSON" ]] || LIVENESS_JSON='{"lanes":[]}'

python3 - "$PROJECT_ROOT" "$LIVENESS_SH" "$LIVENESS_JSON" "${LEADV2_LANE_SILENT_MAX_S:-900}" <<'PY'
import glob, json, os, re, subprocess, sys, time

root, liveness_source_path, liveness_raw, silent_max_s = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    silent_max = int(silent_max_s)
except ValueError:
    silent_max = 900

try:
    liveness = json.loads(liveness_raw)
except Exception:
    liveness = {"lanes": []}
lane_rows = {
    str(r.get("lane")): r
    for r in (liveness.get("lanes") or [])
    if isinstance(r, dict) and r.get("lane")
}

active_yaml = os.path.join(root, "docs", "leadv2", "active.yaml")
sessions = []
try:
    import yaml
    with open(active_yaml, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh) or {}
    sessions = doc.get("sessions") or []
except Exception:
    sessions = []
session_by_task = {
    str(s.get("task_id")): s for s in sessions if isinstance(s, dict) and s.get("task_id")
}

# ── dispatch binding: docs/leadv2/tasks/dispatch-*/journal.md carries
#    "dispatch_task_bound task=<disp> founder_task=<tid>" lines. Multiple
#    dispatch dirs can bind the same founder task across retries -- the
#    journal with the latest mtime wins (R1's "newest wins").
dispatch_for_task = {}
tasks_root = os.path.join(root, "docs", "leadv2", "tasks")
journal_paths = sorted(
    glob.glob(os.path.join(tasks_root, "dispatch-*", "journal.md")),
    key=lambda p: (os.path.getmtime(p) if os.path.isfile(p) else 0),
)
for jpath in journal_paths:
    disp = os.path.basename(os.path.dirname(jpath))[len("dispatch-"):]
    try:
        with open(jpath, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if "dispatch_task_bound" not in line:
                    continue
                parts = {}
                for tok in line.strip().split():
                    if "=" in tok:
                        k, _, v = tok.partition("=")
                        parts[k] = v
                ftid = parts.get("founder_task")
                if ftid:
                    dispatch_for_task[ftid] = disp  # ascending mtime iteration -> last write wins
    except OSError:
        continue


def read_owns(task_id, dispatch_id):
    # HARD RULE 1: never read *.stream.jsonl here.
    if dispatch_id:
        prepass = os.path.join(root, "docs", "handoff", f"dispatch-{dispatch_id}", "architect-prepass.md")
        if os.path.isfile(prepass):
            try:
                heading, summary = None, None
                with open(prepass, encoding="utf-8", errors="replace") as fh:
                    for line in fh:
                        line = line.rstrip("\n")
                        if heading is None:
                            if line.startswith("# "):
                                heading = line[2:].strip()
                            continue
                        if line.strip():
                            summary = line.strip()
                            break
                if heading:
                    text = heading if not summary else f"{heading} — {summary}"
                    return text[:220], "prepass"
            except OSError:
                pass
    # D2 rung 2 (BROAD-STATUS-RENDERER-01): dispatch lanes write
    # lane-mission.md into their handoff dir — the fanout-era mission.txt
    # fallback below was the ONLY rung and never exists for them, which is
    # why every row rendered "—". First # / ## heading, else the first
    # non-empty line; YAML front-matter (--- fence) and "MISSION:"-prefixed
    # boilerplate are skipped. owns_source stays "mission" so the renderer
    # labels it — visibly not passed off as a prepass.
    if dispatch_id:
        mission_md = os.path.join(root, "docs", "handoff", f"dispatch-{dispatch_id}", "lane-mission.md")
        if os.path.isfile(mission_md):
            try:
                first_heading, first_line, in_frontmatter = None, None, False
                with open(mission_md, encoding="utf-8", errors="replace") as fh:
                    for i, line in enumerate(fh):
                        s = line.strip()
                        if i == 0 and s == "---":
                            in_frontmatter = True   # front-matter fence opens
                            continue
                        if in_frontmatter:
                            if s == "---":
                                in_frontmatter = False
                            continue
                        if not s or s.startswith("MISSION:"):
                            continue
                        if s.startswith("# ") or s.startswith("## "):
                            if first_heading is None:
                                first_heading = s.lstrip("#").strip()
                                break
                        if first_line is None:
                            first_line = s
                text = first_heading or first_line
                if text:
                    return text[:220], "mission"
            except OSError:
                pass
    mission = os.path.join(root, "docs", "handoff", f"fanout-lane-{task_id}", "mission.txt")
    if os.path.isfile(mission):
        try:
            with open(mission, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    line = line.strip()
                    if line:
                        return line[:220], "mission"
        except OSError:
            pass
    return None, "none"


def read_worker(task_id):
    s = session_by_task.get(task_id) or {}
    provider = s.get("provider")
    model = s.get("lead_model")
    effort = s.get("lead_effort")
    if provider or model:
        label = provider or "?"
        if model:
            label += f"/{model}"
            if effort:
                label += f"/{effort}"
        return label
    # fallback: a fanout launch log line "task=<tid> ... provider=<p> model=<m>/<e>"
    for cand in sorted(
        glob.glob(os.path.join(root, "docs", "leadv2", "fanout*.log")),
        key=lambda p: os.path.getmtime(p) if os.path.isfile(p) else 0,
        reverse=True,
    ):
        try:
            with open(cand, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if f"task={task_id} " not in line:
                        continue
                    if "provider=" not in line or "model=" not in line:
                        continue
                    try:
                        provider = line.split("provider=", 1)[1].split()[0]
                        model = line.split("model=", 1)[1].split()[0]
                        return f"{provider}/{model}"
                    except IndexError:
                        continue
        except OSError:
            continue
    return "unknown"


def stat_stream(log_path):
    if not log_path:
        return None, None
    candidate = log_path if os.path.isabs(log_path) else os.path.join(root, log_path)
    try:
        st = os.stat(candidate)
        return st.st_size, max(0, int(time.time()) - int(st.st_mtime))
    except OSError:
        return None, None


def _worktree_facts(task_id):
    # Primary disk source, unchanged: the worktree recorded in active.yaml.
    s = session_by_task.get(task_id) or {}
    worktree = s.get("worktree")
    if not worktree or not os.path.isdir(worktree):
        return None
    try:
        shortstat = subprocess.run(
            ["git", "-C", worktree, "diff", "--shortstat"],
            capture_output=True, text=True, timeout=10,
        )
        names = subprocess.run(
            ["git", "-C", worktree, "diff", "--name-only"],
            capture_output=True, text=True, timeout=10,
        )
        untracked = subprocess.run(
            ["git", "-C", worktree, "ls-files", "--others", "--exclude-standard"],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    changed = [l for l in names.stdout.splitlines() if l.strip()]
    untracked_files = [l for l in untracked.stdout.splitlines() if l.strip()]
    shortstat_line = shortstat.stdout.strip()
    if not changed and not untracked_files and not shortstat_line:
        return None
    return {
        "worktree": worktree,
        "files_changed": len(changed),
        "untracked_count": len(untracked_files),
        "shortstat": shortstat_line or None,
    }


# Hard cap for the handoff scan (R2): this runs under a status timer with a
# 761 KB stream + hundreds of tmp files possible in one dir.
_HANDOFF_SCAN_CAP = 200


def _handoff_facts(dispatch_id):
    # Second, separately labelled disk source (D3, BROAD-STATUS-RENDERER-01):
    # a lane that produced prepass/mission/review-gate/stream artifacts but
    # has no active.yaml worktree row (pruned/tombstoned session, or a
    # handoff-only lane) reported NOTHING on disk. A handoff artifact is not
    # a code diff — the two halves are reported side by side, never merged.
    if not dispatch_id:
        return None
    hdir = os.path.join(root, "docs", "handoff", f"dispatch-{dispatch_id}")
    try:
        with os.scandir(hdir) as it:
            entries = []
            for entry in it:
                if len(entries) >= _HANDOFF_SCAN_CAP:
                    return {"dir": hdir, "file_count": f"{_HANDOFF_SCAN_CAP}+",
                            "bytes": None, "top": [], "capped": True}
                name = entry.name
                if name.startswith(".") or ".tmp" in name:
                    continue
                try:
                    st = entry.stat(follow_symlinks=False)
                except OSError:
                    continue
                if entry.is_dir(follow_symlinks=False):
                    continue  # dirs excluded from file_count; non-recursive
                entries.append((name, st.st_size))
    except OSError:
        return None
    if not entries:
        return None
    entries.sort(key=lambda e: -e[1])
    return {
        "dir": hdir,
        "file_count": len(entries),
        "bytes": sum(size for _, size in entries),
        "top": [name for name, _ in entries[:3]],
        "capped": False,
    }


def disk_facts(task_id, dispatch_id):
    worktree = _worktree_facts(task_id)
    handoff = _handoff_facts(dispatch_id)
    if not worktree and not handoff:
        return None
    source = "worktree+handoff" if (worktree and handoff) else ("worktree" if worktree else "handoff")
    return {"worktree": worktree, "handoff": handoff, "source": source}


out_lanes = []
# D1 (BROAD-STATUS-RENDERER-01): a lane whose own task_id already IS
# "dispatch-<hex>" carries its dispatch id in its name — resolve that
# identity BEFORE the journal-binding map, which only maps FOUNDER task ids
# and therefore misses every dispatch lane (the source of the renderer's
# false "(dispatch id unknown)"). Anchored, lowercase-hex only (R5): an
# unrelated task id shaped like a hex dispatch must not match. This is an
# identity, not an inference; dispatch_id_source records which rule fired.
DISPATCH_RE = re.compile(r"^dispatch-([0-9a-f]{6,40})$")
for task_id, lane in sorted(lane_rows.items()):
    m = DISPATCH_RE.match(task_id)
    if m:
        dispatch_id, dispatch_id_source = m.group(1), "self"
    else:
        dispatch_id = dispatch_for_task.get(task_id)
        dispatch_id_source = "journal_binding" if dispatch_id else None
    owns, owns_source = read_owns(task_id, dispatch_id)
    worker = read_worker(task_id)
    stream_bytes, stream_age_s = stat_stream(lane.get("log_path"))
    writing_now = stream_age_s is not None and stream_age_s <= silent_max
    verdict = str(lane.get("verdict") or "")
    terminal_reason = f"{verdict}: {lane.get('reason') or '?'}" if verdict.startswith("dead:") else None
    disk = disk_facts(task_id, dispatch_id)

    out_lanes.append({
        "task_id": task_id,
        "dispatch_id": dispatch_id,
        "dispatch_id_source": dispatch_id_source,
        "owns": owns,
        "owns_source": owns_source,
        "worker": worker,
        "stream_bytes": stream_bytes,
        "stream_mtime_age_s": stream_age_s,
        "writing_now": writing_now,
        "verdict": verdict or None,
        "terminal_reason": terminal_reason,
        "disk": disk,
        "liveness_source_path": liveness_source_path,
    })

print(json.dumps({"ok": True, "lanes": out_lanes}))
PY
