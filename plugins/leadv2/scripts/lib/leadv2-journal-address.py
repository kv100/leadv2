#!/usr/bin/env python3
"""lib/leadv2-journal-address.py — canonical lane-journal address resolver.

MONITORS-ARE-THE-SECOND-CONSUMER-OF-THE-ADDRESS-RESOLVER-01: this is the
single source. Extracted verbatim (algorithm unchanged) from the tiered
resolution scripts/anti-silence-pulse.sh's `_beat` collector grew for
LIVE-LANES-RUN-WITHOUT-A-JOURNAL-01 (persona-engine commit 9aa5dbf55) --
that fix made the pulse the FIRST consumer of this address scheme but left
it duplicated inline inside a Python heredoc, unreachable by anything else.
leadv2-lane-watch.sh (repo-root mode) is the second, and it never adopted
either half: its glob only ever matched `dispatch-*/journal.md`, silently
missing every founder-task-id-named journal dir (46 of 67 on persona-engine
main at time of writing -- the MAJORITY, not an edge case) and carrying none
of the foreign-root / recency-bounded-fallback tiers this module has.

Two operations, both read-only:

  list --root ROOT
    Enumerate every journal.md under ROOT/docs/leadv2/tasks/*/journal.md --
    BOTH naming schemes (task-id dirs and dispatch-<sig8> dirs), one path
    per line. This is what a watcher arming itself over "everything active
    under this root" needs; the narrow dispatch-only glob it replaces is
    exactly the bug.

  resolve --root ROOT --task-id TID [--dispatch-key KEY] [--worktree WT] [--now EPOCH]
    Same five-tier resolution the pulse performs per session: own-root by
    task_id, own-root by dispatch key, foreign-root (worktree) by task_id,
    foreign-root by dispatch key, then -- only if none of those exist --
    the worktree's own tasks dir, recency-bounded to the last hour (a stale
    checkout of docs/leadv2/tasks/ ships hundreds of historical journal.md
    files; unbounded "freshest file wins" picks one of those instead of
    reporting no-journal for a genuinely dead lane). Prints the resolved
    path (empty if none) and exits 0 if found, 1 if not.
"""
import argparse
import os
import re
import sys
import time


def dispatch_key_from_log_path(log_path):
    if not isinstance(log_path, str):
        return None
    m = re.search(r"dispatch-[0-9a-f]{6,}", log_path)
    return m.group(0) if m else None


def journal_candidates(tasks_dir, task_id, dispatch_key=None, worktree=None, project_root=None):
    """Ordered candidate journal.md paths, own-root first (unchanged
    pre-fix behaviour for the common case), then the foreign-root pair --
    only using fields the caller explicitly names, never a glob or a grep
    of file bodies (EXACT-ATTRIBUTION invariant, shared with
    leadv2-lane-address.sh's header)."""
    seen = set()
    out = []

    def _add(p):
        if p and p not in seen:
            seen.add(p)
            out.append(p)

    _add(os.path.join(tasks_dir, task_id, "journal.md"))
    if dispatch_key:
        _add(os.path.join(tasks_dir, dispatch_key, "journal.md"))

    tasks_dir_rel = None
    if project_root:
        rel = os.path.relpath(tasks_dir, project_root)
        if not rel.startswith(".."):
            tasks_dir_rel = rel

    if worktree and tasks_dir_rel is not None:
        foreign_root = os.path.normpath(worktree)
        if project_root and foreign_root != os.path.normpath(project_root):
            _add(os.path.join(foreign_root, tasks_dir_rel, task_id, "journal.md"))
            if dispatch_key:
                _add(os.path.join(foreign_root, tasks_dir_rel, dispatch_key, "journal.md"))
    return out


def recent_glob_fallback(tasks_dir, project_root, worktree, now, max_age_s=3600):
    """Last resort, used ONLY when no exact candidate exists on disk: the
    worktree's own tasks dir, entries kept only if modified within
    max_age_s. Bounded recency, not bare glob-and-trust -- see module
    docstring for why the bound matters."""
    if not worktree or not project_root:
        return []
    rel = os.path.relpath(tasks_dir, project_root)
    if rel.startswith(".."):
        return []
    foreign_root = os.path.normpath(worktree)
    foreign_tasks_dir = os.path.join(foreign_root, rel)
    try:
        entries = os.listdir(foreign_tasks_dir)
    except OSError:
        return []
    out = []
    for name in entries:
        jp = os.path.join(foreign_tasks_dir, name, "journal.md")
        try:
            mt = os.stat(jp).st_mtime
        except OSError:
            continue
        if now - mt <= max_age_s:
            out.append(jp)
    return out


def freshest_journal(paths):
    best_path, best_mtime = None, -1.0
    for p in paths:
        try:
            mt = os.stat(p).st_mtime
        except OSError:
            continue
        if mt > best_mtime:
            best_path, best_mtime = p, mt
    return best_path


def list_journals(tasks_dir):
    """Every journal.md directly under tasks_dir/*/journal.md, both naming
    schemes (task-id dirs and dispatch-<sig8> dirs alike -- this function
    does not care which). One path per line, sorted for determinism."""
    out = []
    try:
        entries = os.listdir(tasks_dir)
    except OSError:
        return out
    for name in entries:
        jp = os.path.join(tasks_dir, name, "journal.md")
        if os.path.isfile(jp):
            out.append(jp)
    out.sort()
    return out


def resolve(tasks_dir, task_id, dispatch_key=None, worktree=None, now=None, project_root=None):
    """tasks_dir is the caller's OWN docs/leadv2/tasks (may be a fixture,
    not necessarily project_root/docs/leadv2/tasks -- kept independently
    configurable, matching the pre-extraction pulse behaviour). project_root
    defaults to tasks_dir's own root (tasks_dir/../..) when not given, used
    only for the foreign-root relpath comparison against `worktree`."""
    if project_root is None:
        project_root = os.path.normpath(os.path.join(tasks_dir, "..", ".."))
    now = int(now) if now is not None else int(time.time())
    exact = [p for p in journal_candidates(tasks_dir, task_id, dispatch_key, worktree, project_root)
             if os.path.isfile(p)]
    if exact:
        return freshest_journal(exact)
    return freshest_journal(recent_glob_fallback(tasks_dir, project_root, worktree, now))


def _tasks_dir_from_args(args):
    if args.tasks_dir:
        return args.tasks_dir
    return os.path.join(args.root, "docs", "leadv2", "tasks")


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_list = sub.add_parser("list")
    p_list.add_argument("--root", default=None, help="repo root; tasks dir = ROOT/docs/leadv2/tasks")
    p_list.add_argument("--tasks-dir", default=None, help="explicit tasks dir, overrides --root's default")

    p_res = sub.add_parser("resolve")
    p_res.add_argument("--root", default=None, help="repo root; tasks dir = ROOT/docs/leadv2/tasks")
    p_res.add_argument("--tasks-dir", default=None, help="explicit tasks dir, overrides --root's default")
    p_res.add_argument("--task-id", required=True)
    p_res.add_argument("--dispatch-key", default=None)
    p_res.add_argument("--worktree", default=None)
    p_res.add_argument("--now", type=int, default=None)

    args = ap.parse_args(argv)
    if not args.tasks_dir and not args.root:
        ap.error("one of --root or --tasks-dir is required")
    tasks_dir = _tasks_dir_from_args(args)

    if args.cmd == "list":
        for p in list_journals(tasks_dir):
            print(p)
        return 0

    if args.cmd == "resolve":
        journal = resolve(tasks_dir, args.task_id, args.dispatch_key, args.worktree, args.now,
                           project_root=args.root)
        if journal:
            print(journal)
            return 0
        return 1

    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
