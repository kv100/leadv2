"""leadv2_lane_naming.py — ONE naming rule, ONE inode
(STATUS-FORMAT-IN-RENDERER-01).

The founder-status table's "Линия" (name) and "Что делает" (description)
columns come from ONE source: the lane's mission title. Never from
architect-prepass.md (that stays in the detail-block "owns" field) and
never from *.stream.jsonl. These are pure deterministic string transforms
of text the founder himself wrote in the mission — no LLM ever names a
lane, so a name cannot drift between beats on its own (freezing across
beats is the caller's job, in leadv2-broad-status.sh's .broad-status-prev.
json, not this module's).

Import contract: readers inside heredocs do

    sys.path.insert(0, os.path.join(script_dir, "lib"))
    from leadv2_lane_naming import mission_title, human_name, product_sentence

and MUST fall back to a no-op (return None) when the import fails (a
drifted .claude/scripts/ copy without lib/) — degrade, never crash a
status probe.
"""

import os
import re

# Any of these tokens in a candidate name/sentence marks it as raw
# artifact leakage (prepass/mission boilerplate), never a real name.
_REJECT_TOKENS = ("TASK_ID:", "ROLE:", "Verdict", "LANE_WRITES")

# A leading founder task-id token, e.g. "STATUS-FORMAT-IN-RENDERER-01 —".
_ID_TOKEN_RE = re.compile(r"^([A-Z][A-Z0-9-]*-\d+)\s*(?:[—:-]\s*)?(.*)$")

_TRAILING_PREPS = {
    "для", "на", "в", "по", "с", "к", "о", "из", "от", "при", "за",
    "for", "of", "on", "in", "to", "with", "and", "or", "the", "a",
}


def _strip_markdown(s):
    s = s.strip()
    s = re.sub(r"^#+\s*", "", s)
    s = s.replace("**", "").replace("`", "")
    s = re.sub(r"\s+", " ", s).strip()
    return s


def _rejects(s):
    return any(tok in s for tok in _REJECT_TOKENS)


def _read_first_heading(path):
    # Same skipping rules as leadv2-lane-detail.sh::read_owns rung 2: YAML
    # front-matter (--- fence) and "MISSION:"-prefixed boilerplate are
    # skipped; first `#`/`##` heading wins, else the first non-empty line.
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
    except OSError:
        return None
    in_frontmatter = False
    first_heading, first_line = None, None
    for i, line in enumerate(lines):
        s = line.strip()
        if i == 0 and s == "---":
            in_frontmatter = True
            continue
        if in_frontmatter:
            if s == "---":
                in_frontmatter = False
            continue
        if not s or s.startswith("MISSION:"):
            continue
        if s.startswith("# ") or s.startswith("## "):
            first_heading = s.lstrip("#").strip()
            break
        if first_line is None:
            first_line = s
    return first_heading or first_line


def _journal_dispatch_title(journal_path):
    # Rung 2: a dispatch-line title, if the journal happens to carry one
    # (e.g. "dispatch_classified task=... title=..."). Best-effort — most
    # journals don't carry a title token, in which case this rung is a
    # silent miss and rung 3 (tasks.yaml) decides.
    try:
        with open(journal_path, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
    except OSError:
        return None
    for line in reversed(lines):
        if "dispatch_classified" not in line and "dispatch_task_bound" not in line:
            continue
        if "title=" not in line:
            continue
        try:
            rest = line.split("title=", 1)[1]
            title = rest.split("\t")[0].strip() if "\t" in rest else rest.strip()
        except IndexError:
            continue
        if title:
            return title
    return None


def _tasks_yaml_intent(root, task_id, dispatch_id):
    tasks_yaml = os.path.join(root, "docs", "tasks.yaml")
    try:
        import yaml
        with open(tasks_yaml, encoding="utf-8") as fh:
            doc = yaml.safe_load(fh) or {}
    except Exception:
        return None
    items = doc.get("tasks") if isinstance(doc, dict) else None
    if not isinstance(items, list):
        return None
    for it in items:
        if not isinstance(it, dict):
            continue
        iid = str(it.get("id") or "")
        if iid and (iid == task_id or iid == dispatch_id or iid == f"dispatch-{dispatch_id}"):
            intent = it.get("intent")
            if intent:
                return str(intent)
    return None


def mission_title(root, dispatch_id):
    """Resolve a lane's mission title, never its prepass excerpt.

    -> (title | None, source) where source is "mission" | "journal" |
    "tasks" | "none". Never opens architect-prepass.md or *.stream.jsonl.
    """
    if not dispatch_id:
        return None, "none"
    dispatch_id = str(dispatch_id)
    task_id = dispatch_id if dispatch_id.startswith("dispatch-") else f"dispatch-{dispatch_id}"

    # rung 1: docs/handoff/dispatch-<id>/lane-mission.md
    mission_md = os.path.join(root, "docs", "handoff", task_id, "lane-mission.md")
    if os.path.isfile(mission_md):
        title = _read_first_heading(mission_md)
        if title and not _rejects(title):
            return title, "mission"

    # rung 2: docs/leadv2/tasks/<task_id>/journal.md dispatch-line title
    journal = os.path.join(root, "docs", "leadv2", "tasks", task_id, "journal.md")
    title = _journal_dispatch_title(journal)
    if title and not _rejects(title):
        return title, "journal"

    # rung 3: tasks.yaml intent by the id token
    intent = _tasks_yaml_intent(root, task_id, dispatch_id)
    if intent and not _rejects(intent):
        return intent, "tasks"

    return None, "none"


def split_task_id(title):
    """-> (id_token | None, rest). Strips a leading founder task-id token."""
    if not title:
        return None, title or ""
    m = _ID_TOKEN_RE.match(title.strip())
    if not m:
        return None, title.strip()
    return m.group(1), m.group(2).strip()


def human_name(title):
    """-> a short (<=5 words, <=42 chars) human name, or None if unnameable."""
    if not title:
        return None
    _id, rest = split_task_id(title)
    rest = _strip_markdown(rest)
    if not rest or _rejects(rest):
        return None
    cut = re.split(r"[—:,(]", rest, maxsplit=1)[0].strip()
    if not cut:
        return None
    words = cut.split()
    if len(words) > 5:
        words = words[:5]
    if words and words[-1].lower().strip(".,;") in _TRAILING_PREPS:
        words = words[:-1]
    cut = " ".join(words).strip()
    if len(cut) > 42:
        cut = cut[:42].rstrip()
    if not cut or _rejects(cut):
        return None
    if re.fullmatch(r"[A-Z][A-Z0-9-]*-\d+", cut):
        return None  # bare id, not a name
    return cut


def product_sentence(title):
    """-> one plain sentence (<=140 chars, no markdown), or None."""
    if not title:
        return None
    _id, rest = split_task_id(title)
    rest = _strip_markdown(rest)
    if not rest or _rejects(rest):
        return None
    m = re.search(r"[.!?](\s|$)", rest)
    sentence = rest[: m.start() + 1].strip() if m else rest
    if len(sentence) > 140:
        sentence = sentence[:140].rstrip()
    sentence = sentence.rstrip("—-: ").strip()
    if not sentence or _rejects(sentence):
        return None
    return sentence


def is_markdown_free(s):
    """Test-facing predicate: no markdown/table/newline artifacts."""
    if s is None:
        return True
    if not isinstance(s, str):
        return False
    return not any(tok in s for tok in ("**", "`", "#", "|", "\n"))
