#!/usr/bin/env bash
# leadv2-lanes.sh — FOUNDER-LANE-VIEW-01: the founder's "what is running
# right now" view.  One line per LIVE lane, newest activity first.
#
# Liveness here is judged by PROCESS EXISTENCE, not by artifact mtime — the
# split from leadv2-lane-liveness.sh is deliberate: that script's verdict
# vocabulary is asserted by test-lane-liveness-authoritative.sh and consumed
# by the supervisor prune path, the statusline tail and the dispatch-ledger
# sweep, so its liveness rule must not move.  This script is a new read-only
# surface beside it; `--all` delegates verbatim to keep today's behaviour
# reachable (byte-for-byte).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Single source of truth for lane sub-agent role suffixes
# (STATUSLINE-COUNT-TRUTH-02 §1a) — never a second hardcoded suffix list.
if [[ -f "$SCRIPT_DIR/leadv2-lane-child-suffixes.sh" ]]; then
  # shellcheck source=leadv2-lane-child-suffixes.sh
  source "$SCRIPT_DIR/leadv2-lane-child-suffixes.sh"
fi
LEADV2_LANE_CHILD_SUFFIXES="${LEADV2_LANE_CHILD_SUFFIXES:-architect}"

usage() {
  cat >&2 <<'EOF'
Usage:
  leadv2-lanes.sh [--json] [--no-color] [--repo <path>]...
  leadv2-lanes.sh --all [<liveness-args>...]

  Live lanes only, one line each, newest activity first. Liveness is judged
  by process existence (a running lane with no log yet still prints).
  --all     today's leadv2-lane-liveness.sh --all output, verbatim.
  --json    machine-readable rows (see README).
  --repo    add a repo root to scan (repeatable; replaces the default set:
            $PWD, ~/Projects/persona-engine, ~/Projects/leadv2).
Env: LEADV2_LANE_VIEW_ROOTS (colon-separated roots),
     LEADV2_LANE_VIEW_MAX (row cap, default 40).
EOF
}

JSON=0
ALL=0
NO_COLOR="${LEADV2_NO_COLOR:-0}"
REPOS=()
REST=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON=1; shift ;;
    --all) ALL=1; shift; while [[ $# -gt 0 ]]; do REST+=("$1"); shift; done ;;
    --no-color) NO_COLOR=1; shift ;;
    --repo) REPOS+=("${2:-}"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf '[lanes] unknown arg: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

# --all: exec-delegate with the remaining args verbatim rather than
# re-implementing any flag, so the delegation cannot drift from the
# liveness script (its own flags like --project-root pass through).
if [[ "$ALL" -eq 1 ]]; then
  DELEG=(--all)
  [[ "$JSON" -eq 1 ]] && DELEG+=(--json)
  exec bash "$SCRIPT_DIR/leadv2-lane-liveness.sh" "${DELEG[@]}" ${REST[@]+"${REST[@]}"}
fi

# Root set: explicit --repo wins; else LEADV2_LANE_VIEW_ROOTS; else defaults.
if [[ ${#REPOS[@]} -gt 0 ]]; then
  ROOTS="$(IFS=:; printf '%s' "${REPOS[*]}")"
else
  ROOTS="${LEADV2_LANE_VIEW_ROOTS:-$PWD:$HOME/Projects/persona-engine:$HOME/Projects/leadv2}"
fi

if [[ "$NO_COLOR" -ne 1 && ! -t 1 ]]; then NO_COLOR=1; fi

# One ps snapshot (single subprocess, no network, no per-lane shell-out).
# LEADV2_LANE_VIEW_PS_FILE is a TEST-ONLY override: when set and the file
# exists, the snapshot is read from it instead of shelling out.
PS_FILE="${LEADV2_LANE_VIEW_PS_FILE:-}"
TMP_PS=""
if [[ -z "$PS_FILE" || ! -f "$PS_FILE" ]]; then
  TMP_PS="$(mktemp -t leadv2-lanes)"
  trap 'rm -f "$TMP_PS"' EXIT
  ps -Ao pid=,pgid=,etime=,command= > "$TMP_PS" 2>/dev/null || true
  PS_FILE="$TMP_PS"
fi

SELF_PID="$$"
SELF_PGID="$(ps -o pgid= -p "$SELF_PID" 2>/dev/null | tr -d ' ' || printf '0')"

python3 - "$PS_FILE" "$ROOTS" "$LEADV2_LANE_CHILD_SUFFIXES" "$JSON" \
  "${LEADV2_LANE_VIEW_MAX:-40}" "$NO_COLOR" "$SELF_PID" "$SELF_PGID" <<'PY'
import glob, json, os, re, sys, time

(ps_path, roots_raw, child_raw, json_raw, max_raw, color_raw,
 self_pid_raw, self_pgid_raw) = sys.argv[1:9]
json_mode = json_raw == "1"
color = color_raw != "1"
try:
    max_rows = max(1, int(max_raw))
except ValueError:
    max_rows = 40
SELF_PID = int(self_pid_raw)
SELF_PGID = int(self_pgid_raw or 0)

CHILD_SUFFIXES = [s.strip() for s in child_raw.split(",") if s.strip()]
FOLD_RE = re.compile(r'^(dispatch-[0-9a-f]{8})-(.+)$')

def fold(tid):
    # A lane id shaped dispatch-<sig8>-<suffix> where <suffix> is a registered
    # child role is a prepass INSIDE its parent lane — fold to the parent so
    # it never renders as its own row (STATUSLINE-COUNT-TRUTH-02 §1a).
    m = FOLD_RE.match(tid)
    if m and m.group(2) in CHILD_SUFFIXES:
        return m.group(1)
    return tid

# Full lane id as it may appear in argv (base or suffixed); hex boundary
# guards stop a 10-hex-char string from matching its first 8 chars.
LANE_RE = re.compile(r'(?<![0-9A-Za-z_-])(dispatch-[0-9a-f]{8}(?:-[A-Za-z0-9_-]+)?)(?![0-9A-Za-z_-])')
ROOT_RE = re.compile(r"(/[^'\"\s]+)/docs/handoff/(dispatch-[0-9a-f]{8}(?:-[A-Za-z0-9_-]+)?)")
PS_LINE_RE = re.compile(r'^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.*)$')

RUNNERS = ("leadv2-dispatch-code.sh", "leadv2-fanout", "claude-subsession.sh",
           "claude -p", "glm-coder.sh", "kimi-coder.sh", "codex-task.sh",
           "leadv2-dispatch-product-close.sh")
ARM_HINTS = (("glm-coder.sh", "glm"), ("kimi-coder.sh", "kimi"),
             ("codex-task.sh", "codex"), ("claude", "claude"))

def etime_s(text):
    # ps etime shape: [[DD-]HH:]MM:SS — parsed here, never shelled out to date.
    days = 0
    if "-" in text:
        day_part, text = text.split("-", 1)
        try:
            days = int(day_part)
        except ValueError:
            return 0
    parts = text.split(":")
    try:
        nums = [int(p) for p in parts]
    except ValueError:
        return 0
    while len(nums) < 3:
        nums.insert(0, 0)
    h, m, s = nums[-3:]
    return days * 86400 + h * 3600 + m * 60 + s

lanes = {}  # lane -> {"pids": set, "pgids": set, "cmds": [], "runtime_s": 0, "etime": "", "roots": set}

def lane_entry(lane):
    return lanes.setdefault(lane, {"pids": set(), "pgids": set(), "cmds": [],
                                   "runtime_s": 0, "etime": "", "roots": set()})

def add_proc(lane, pid, pgid, etime, cmd):
    e = lane_entry(lane)
    e["pids"].add(pid)
    e["pgids"].add(pgid)
    e["cmds"].append(cmd)
    secs = etime_s(etime)
    if secs > e["runtime_s"]:
        e["runtime_s"] = secs
        e["etime"] = etime

procs = []
try:
    with open(ps_path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = PS_LINE_RE.match(line)
            if not m:
                continue
            pid, pgid, etime, cmd = int(m.group(1)), int(m.group(2)), m.group(3), m.group(4)
            if pid == SELF_PID or pgid == SELF_PGID:
                continue  # never let the view count itself
            procs.append((pid, pgid, etime, cmd))
except OSError:
    procs = []

matched_pids = set()
matched_pgids = set()
for pid, pgid, etime, cmd in procs:
    full_ids = [m.group(1) for m in LANE_RE.finditer(cmd)]
    if not full_ids:
        continue
    matched_pids.add(pid)
    matched_pgids.add(pgid)
    is_runner = any(r in cmd for r in RUNNERS)
    for full in full_ids:
        # Runner allowlist OR a real docs/handoff/<lane> path — a command
        # that merely MENTIONS an id (grep, an editor) invents no lane.
        if not is_runner and ("docs/handoff/" + full) not in cmd:
            continue
        add_proc(fold(full), pid, pgid, etime, cmd)
        for m in ROOT_RE.finditer(cmd):
            lane_entry(fold(m.group(2)))["roots"].add(m.group(1))

# pgid closure: a worker whose own argv lost the lane id (a long `claude -p`
# prompt, a tee, a python child) is still counted via its process group.
for pid, pgid, etime, cmd in procs:
    if pid in matched_pids or pgid not in matched_pgids:
        continue
    for lane, e in lanes.items():
        if pgid in e["pgids"]:
            add_proc(lane, pid, pgid, etime, cmd)

ROOTS = []
for r in roots_raw.split(":"):
    r = os.path.expanduser(r.strip())
    if r and os.path.isdir(r) and r not in ROOTS:
        ROOTS.append(r)

def human_age(secs):
    if secs < 60:
        return "%ds" % secs
    if secs < 3600:
        return "%dm" % (secs // 60)
    if secs < 86400:
        return "%dh" % (secs // 3600)
    return "%dd" % (secs // 86400)

def read_head(path, lines=50):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return [next(fh, "") for _ in range(lines)]
    except OSError:
        return []

def first_heading(path):
    for line in read_head(path, 40):
        if line.startswith("# "):
            return line[2:].strip()
    return None

def infer_arm(cmds):
    joined = " ".join(cmds)
    for hint, arm in ARM_HINTS:
        if hint in joined:
            return arm
    return "?"

def enrich(lane, e):
    # A derived root only counts if it exists on disk; else attribute to the
    # first configured root that actually holds the lane dir.
    derived = sorted(r for r in e["roots"] if os.path.isdir(r))
    root = (derived or [r for r in ROOTS
                        if os.path.isdir(os.path.join(r, "docs", "handoff", lane))] or ["?"])[0]
    title, phase, art_name, art_age, art_mtime = None, None, None, None, None
    if root != "?":
        hdir = os.path.join(root, "docs", "handoff", lane)
        journal = os.path.join(root, "docs", "leadv2", "tasks", lane, "journal.md")
        # title: context.yaml -> first *mission*.md heading -> journal heading
        for line in read_head(os.path.join(hdir, "context.yaml"), 50):
            m = re.match(r"^title:\s*(.+)$", line)
            if m:
                title = m.group(1).strip().strip('"\'')
                break
        if not title:
            for miss in sorted(glob.glob(os.path.join(hdir, "*mission*.md"))):
                title = first_heading(miss)
                if title:
                    break
        if not title:
            title = first_heading(journal)
        # last artifact: newest-mtime regular file at depth 1, dotfiles skipped
        try:
            entries = [(os.stat(os.path.join(hdir, n)).st_mtime, n)
                       for n in os.listdir(hdir)
                       if not n.startswith(".") and os.path.isfile(os.path.join(hdir, n))]
        except OSError:
            entries = []
        if entries:
            art_mtime, art_name = max(entries)
            art_age = int(time.time() - art_mtime)
        # phase/gate: .close -> closed; review-gate verdict; journal phase=
        if os.path.exists(os.path.join(hdir, ".close")):
            phase = "closed"
        else:
            for line in read_head(os.path.join(hdir, "review-gate.md"), 20):
                m = re.search(r"(?:verdict=|VERDICT)[:\s=]*([A-Za-z0-9_]+)", line)
                if m:
                    phase = "gate:" + m.group(1)
                    break
        if phase is None:
            try:
                with open(journal, encoding="utf-8", errors="replace") as fh:
                    tail = fh.readlines()[-40:]
            except OSError:
                tail = []
            for line in reversed(tail):
                m = re.search(r"phase=([A-Za-z0-9_]+)", line)
                if m:
                    phase = m.group(1)
                    break
    return {"lane": lane, "root": root, "arm": infer_arm(e["cmds"]),
            "title": title or "—", "runtime_s": e["runtime_s"],
            "etime": e["etime"] or "0:00", "pids": sorted(e["pids"]),
            "pgids": sorted(e["pgids"]), "last_artifact": art_name,
            "last_artifact_age_s": art_age, "art_mtime": art_mtime,
            "phase": phase or "—"}

rows = [enrich(lane, e) for lane, e in lanes.items()]
# A real dispatch lane always has its handoff dir on disk under some root.
# A lane id that only appears in prose inside a worker's argv (a prompt that
# MENTIONS other lanes) resolves to no existing dir anywhere — drop it; it
# is argv noise, not a lane (founder-facing signal over junk rows).
rows = [r for r in rows if r["root"] != "?"]
# Newest activity first: artifact lanes by mtime desc, then artifactless
# lanes by longest runtime.
rows.sort(key=lambda r: (0, -(r["art_mtime"] or 0)) if r["art_mtime"] is not None
          else (1, -r["runtime_s"]))
rows = rows[:max_rows]

if json_mode:
    payload = [{"lane": r["lane"], "root": r["root"], "arm": r["arm"],
                "title": r["title"], "runtime_s": r["runtime_s"],
                "pids": r["pids"], "pgids": r["pgids"],
                "last_artifact": r["last_artifact"],
                "last_artifact_age_s": r["last_artifact_age_s"],
                "phase": r["phase"]} for r in rows]
    print(json.dumps({"lanes": payload, "count_live": len(payload)}, indent=2))
    sys.exit(0)

if not rows:
    print("no live lanes")
    sys.exit(0)

multi_root = len({r["root"] for r in rows}) > 1
B, R = ("\033[1m", "\033[0m") if color else ("", "")
for r in rows:
    cols = ["%s%s%s" % (B, r["lane"], R) if color else r["lane"]]
    if multi_root and r["root"] != "?":
        cols.append("@" + os.path.basename(r["root"].rstrip("/")))
    cols.append(r["arm"])
    cols.append(r["title"])
    cols.append("run " + r["etime"])
    if r["last_artifact"] is not None:
        cols.append("%s %s ago" % (r["last_artifact"], human_age(r["last_artifact_age_s"])))
    else:
        cols.append("—")
    cols.append(r["phase"])
    print(" · ".join(cols))
PY
