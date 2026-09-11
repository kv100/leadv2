#!/usr/bin/env python3
"""Resolve a founder task id against a repo's markdown pipe-table backlog.

PREMISE-GATE-MARKDOWN-BACKLOG-01. Consulted by _premise_probe_gate in
leadv2-dispatch-code.sh only when the yaml resolver already returned
status=none. Never raises: any failure prints `none\t-\t<diag>` and exits 0.

stdout: exactly one line  <status>\t<row_id>\t<status_text_or_diag>
        status in {md_closed, md_open, md_ambiguous, none}
exit:   always 0
"""
import argparse
import os
import re
import subprocess
import sys
import unicodedata

DECL_REL = os.path.join(".claude", "leadv2-overrides", "markdown-backlog.yaml")


def _nfc(s):
    return unicodedata.normalize("NFC", s)


def _git_common_dir_parent(root):
    try:
        out = subprocess.run(
            ["git", "-C", root, "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, timeout=10,
        ).stdout.strip()
    except Exception:
        return ""
    parent = os.path.dirname(out) if out else ""
    return parent if parent and os.path.isdir(parent) else ""


def _resolve_roots(root):
    roots = [root]
    common = _git_common_dir_parent(root)
    if common and common not in roots:
        roots.append(common)
    return roots


def _strip_comment(raw_line):
    """Drop a trailing '# comment', but never one inside a quoted scalar --
    a status cell like id_column: "#" must survive comment stripping."""
    quote = None
    for i, ch in enumerate(raw_line):
        if quote:
            if ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
        elif ch == "#":
            return raw_line[:i].rstrip()
    return raw_line.rstrip()


def _load_yaml_flat(text):
    """Minimal fallback parser for the mission's flat declaration shape:
    `key: value` scalars and `- "item"` list entries under a `key:` line.
    Anything beyond that (flow collections, nesting, anchors) is refused by
    raising ValueError -- the caller turns that into decl_malformed."""
    data = {}
    cur_key = None
    for raw_line in text.splitlines():
        line = _strip_comment(raw_line)
        if not line.strip():
            continue
        stripped = line.strip()
        if stripped.startswith("- "):
            if cur_key is None:
                raise ValueError("list item with no preceding key")
            item = stripped[2:].strip()
            item = _unquote(item)
            if data.get(cur_key) is None:
                data[cur_key] = []
            elif not isinstance(data[cur_key], list):
                raise ValueError("mixed list/scalar for key %r" % cur_key)
            data[cur_key].append(item)
            continue
        if ":" not in line:
            raise ValueError("no ':' in line %r" % raw_line)
        key, _, val = line.partition(":")
        key = key.strip()
        val = val.strip()
        if not key:
            raise ValueError("empty key")
        if val == "":
            cur_key = key
            data[key] = None
            continue
        if val.startswith("[") or val.startswith("{"):
            raise ValueError("flow collection not supported by fallback parser")
        data[key] = _unquote(val)
        cur_key = key
    return data


def _unquote(s):
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        return s[1:-1]
    return s


def _load_declaration(path):
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    try:
        import yaml  # noqa: local import -- optional dependency, guarded
        try:
            data = yaml.safe_load(text)
        except Exception:
            raise ValueError("pyyaml parse failure")
    except ImportError:
        data = _load_yaml_flat(text)
    if not isinstance(data, dict):
        raise ValueError("declaration is not a mapping")
    return data


def _validate_declaration(data):
    for key in ("file", "id_column", "status_column"):
        val = data.get(key)
        if not isinstance(val, str) or not val.strip():
            return None, "decl_missing_key:%s" % key
    id_pattern = data.get("id_pattern")
    if not isinstance(id_pattern, str) or not id_pattern.strip():
        return None, "decl_missing_key:id_pattern"
    try:
        compiled = re.compile(id_pattern)
    except re.error:
        return None, "decl_bad_pattern"
    closed = data.get("closed_statuses")
    if not isinstance(closed, list) or not closed or not all(isinstance(c, str) for c in closed):
        return None, "decl_missing_key:closed_statuses"
    return {
        "file": data["file"],
        "id_column": data["id_column"],
        "status_column": data["status_column"],
        "id_pattern": compiled,
        "closed_statuses": {_nfc(c.strip()) for c in closed},
    }, None


def _split_row(line):
    cells = re.split(r"(?<!\\)\|", line)
    # Outer empties from the leading/trailing '|' of a pipe-table row.
    if cells and cells[0].strip() == "":
        cells = cells[1:]
    if cells and cells[-1].strip() == "":
        cells = cells[:-1]
    return [c.strip().replace("\\|", "|") for c in cells]


_SEP_RE = re.compile(r"^:?-{3,}:?$")


def _find_matches(decl, root, task_id):
    file_rel = decl["file"]
    file_abs = os.path.realpath(os.path.join(root, file_rel))
    root_abs = os.path.realpath(root)
    if os.path.commonpath([file_abs, root_abs]) != root_abs:
        return None, "decl_file_outside_root", file_abs
    if not os.path.isfile(file_abs):
        return None, "decl_file_missing", file_abs

    with open(file_abs, "r", encoding="utf-8", errors="strict") as fh:
        text = fh.read()
    text = _nfc(text)

    id_idx = None
    status_idx = None
    matches = []
    task_id_norm = _nfc(task_id.strip())

    for raw_line in text.splitlines():
        line = raw_line.rstrip("\r\n")
        if not line.lstrip().startswith("|"):
            continue
        cells = _split_row(line)
        if not cells:
            continue
        if decl["id_column"] in cells and decl["status_column"] in cells:
            id_idx = cells.index(decl["id_column"])
            status_idx = cells.index(decl["status_column"])
            continue
        if all(_SEP_RE.match(c) for c in cells if c):
            continue
        if id_idx is None:
            continue
        if id_idx >= len(cells):
            continue
        cell_id = cells[id_idx]
        if not decl["id_pattern"].fullmatch(cell_id):
            continue
        if _nfc(cell_id) != task_id_norm:  # nc-anchor: id-exact
            continue
        status_text = cells[status_idx] if status_idx < len(cells) else "-"
        status_text = status_text.replace("\t", " ")
        matches.append((cell_id, status_text))

    if id_idx is None:
        return None, "decl_columns_missing", file_abs
    return matches, None, file_abs


def resolve(root, task_id):
    """Returns (status, row_id, status_text_or_diag, file_path). file_path
    is '-' unless a declared file was actually located (needed only so the
    gate's refusal message can name the backlog file; not part of the
    match/no-match verdict itself)."""
    decl_path = os.path.join(root, DECL_REL)
    if not os.path.isfile(decl_path):
        return ("none", "-", "-", "-")

    try:
        raw = _load_declaration(decl_path)
    except Exception:
        return ("none", "-", "decl_malformed", "-")

    decl, diag = _validate_declaration(raw)
    if decl is None:
        return ("none", "-", diag, "-")

    matches, diag, file_abs = _find_matches(decl, root, task_id)
    if matches is None:
        return ("none", "-", diag, file_abs if diag == "decl_file_outside_root" else "-")

    if not matches:
        return ("none", "-", "-", "-")
    if len(matches) >= 2:
        return ("md_ambiguous", matches[0][0], matches[0][1], file_abs)

    row_id, status_text = matches[0]
    status_norm = _nfc(status_text.strip())
    closed = status_norm in decl["closed_statuses"]  # nc-anchor: closed-exact
    return ("md_closed" if closed else "md_open", row_id, status_text, file_abs)


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--task-id", required=True)
    args = parser.parse_args(argv)

    try:
        for root in _resolve_roots(args.root):
            decl_path = os.path.join(root, DECL_REL)
            if os.path.isfile(decl_path):
                status, row_id, text, file_path = resolve(root, args.task_id)
                break
        else:
            status, row_id, text, file_path = ("none", "-", "-", "-")
    except Exception:
        status, row_id, text, file_path = ("none", "-", "reader_exception", "-")

    sys.stdout.write("%s\t%s\t%s\t%s\n" % (status, row_id, text, file_path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
