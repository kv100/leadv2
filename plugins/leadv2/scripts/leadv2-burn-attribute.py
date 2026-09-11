#!/usr/bin/env python3
"""Attribute dispatched Claude burn sessions without changing history.db.

The burn database intentionally has no account column.  This reader joins its
session_id to dispatch handoffs that contain both a SESSION_ID= record and a
claude-profile.log selected=personal|work decision.  Anything else is unknown:
interactive leads and incomplete handoffs are deliberately never guessed.
"""
from __future__ import annotations

import argparse
import os
import re
import sqlite3
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable
from urllib.parse import quote

ACCOUNT_VALUES = {"personal", "work"}
SESSION_RE = re.compile(r"\bSESSION_ID=([A-Za-z0-9][A-Za-z0-9_.-]*)")
SELECTED_RE = re.compile(r"\bselected=(personal|work)\b")
ARM_RE = re.compile(r"\b(?:arm|provider|worker_arm|selected_arm)=([A-Za-z0-9_-]+)\b", re.I)


def parse_time(value: str) -> datetime:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid ISO-8601 timestamp: {value}") from exc


def default_roots() -> list[Path]:
    """Return all disk handoff roots, not a guessed account source."""
    roots: list[Path] = []
    env_roots = os.environ.get("LEADV2_BURN_HANDOFF_ROOTS", "")
    roots.extend(Path(item).expanduser() for item in env_roots.split(os.pathsep) if item)
    projects = Path.home() / "Projects"
    project_checkouts: list[Path] = []
    if projects.is_dir():
        # One root per checkout repository.  Do not recursively walk every
        # historical worktree: each is a duplicate of its parent repo's
        # handoff ledger and a recursive census both overcounts and is too
        # slow to be useful for the requested window.
        project_checkouts = [child for child in projects.iterdir() if child.is_dir()]
        roots.extend(child / "docs" / "handoff" for child in project_checkouts)
    cwd_root = Path.cwd() / "docs" / "handoff"
    # A lane worktree is beneath its checkout's Projects/<repo> directory;
    # its handoff history must not double the canonical checkout's ledger.
    if cwd_root.is_dir() and not any(checkout in cwd_root.parents for checkout in project_checkouts):
        roots.append(cwd_root)
    return unique_existing(roots)


def unique_existing(roots: Iterable[Path]) -> list[Path]:
    out: list[Path] = []
    seen: set[Path] = set()
    for root in roots:
        try:
            resolved = root.expanduser().resolve()
        except OSError:
            continue
        if resolved.is_dir() and resolved not in seen:
            seen.add(resolved)
            out.append(resolved)
    return sorted(out)


def file_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def classify_arm(text: str) -> str:
    values = {value.lower() for value in ARM_RE.findall(text)}
    if values & {"claude", "sonnet", "opus", "haiku"}:
        return "claude"
    for arm in ("codex", "glm", "kimi"):
        if arm in values:
            return arm
    return "unknown"


def scan_handoffs(roots: Iterable[Path]) -> tuple[dict[str, str], Counter[str], Counter[str]]:
    """Return session evidence, join defects, and arm census for no-profile dirs."""
    evidence: dict[str, set[str]] = defaultdict(set)
    join = Counter()
    missing_profile_arms = Counter()
    dirs: set[Path] = set()
    for root in roots:
        dirs.update(path for path in root.glob("dispatch-*") if path.is_dir())
    join["dispatch_dirs"] = len(dirs)
    for directory in sorted(dirs):
        profile = file_text(directory / "claude-profile.log")
        selected = SELECTED_RE.findall(profile)
        account = selected[-1] if selected else None
        aggregate = "\n".join(file_text(p) for p in directory.rglob("*") if p.is_file())
        session_ids = set(SESSION_RE.findall(aggregate))
        if account:
            join["selected_profiles"] += 1
        else:
            join["without_selected_profile"] += 1
            missing_profile_arms[classify_arm(aggregate)] += 1
        if account and not session_ids:
            join["profile_without_session"] += 1
        if session_ids and not account:
            join["session_without_profile"] += len(session_ids)
        if account:
            for session_id in session_ids:
                evidence[session_id].add(account)
    resolved: dict[str, str] = {}
    for session_id, accounts in evidence.items():
        if len(accounts) == 1:
            resolved[session_id] = next(iter(accounts))
        else:
            resolved[session_id] = "unknown"
            join["conflicting_session_evidence"] += 1
    return resolved, join, missing_profile_arms


def open_read_only(path: Path) -> sqlite3.Connection:
    # This marker is mutation-controlled by nc-burn-attribute.sh.  Do not
    # simplify it: URI mode=ro is the non-negotiable no-write boundary.
    uri = f"file:{quote(str(path.resolve()))}?mode=ro"
    return sqlite3.connect(uri, uri=True)


def query_sessions(db: Path, since: datetime, until: datetime) -> list[sqlite3.Row]:
    conn = open_read_only(db)
    conn.row_factory = sqlite3.Row
    try:
        columns = {row[1] for row in conn.execute("PRAGMA table_info(sessions)")}
        required = {"session_id", "project_name", "last_asst_ts", "turns", "cc_total", "cr_total", "last_model"}
        missing = sorted(required - columns)
        if missing:
            raise RuntimeError(f"history.db sessions schema missing: {', '.join(missing)}")
        rows = list(conn.execute("SELECT session_id, project_name, last_asst_ts, turns, cc_total, cr_total, last_model FROM sessions"))
    finally:
        conn.close()
    selected = []
    for row in rows:
        value = row["last_asst_ts"]
        if not value:
            continue
        try:
            timestamp = parse_time(value)
        except argparse.ArgumentTypeError:
            continue
        if since <= timestamp < until:
            selected.append(row)
    return selected


def metric(rows: list[sqlite3.Row]) -> tuple[int, int, int, int]:
    return (len(rows), sum(int(r["turns"] or 0) for r in rows), sum(int(r["cc_total"] or 0) for r in rows), sum(int(r["cr_total"] or 0) for r in rows))


def emit(rows: list[sqlite3.Row], attribution: dict[str, str], join: Counter[str], arms: Counter[str], since: datetime, until: datetime) -> None:
    grouped: dict[str, list[sqlite3.Row]] = defaultdict(list)
    for row in rows:
        grouped[attribution.get(row["session_id"], "unknown")].append(row)
    print("# Leadv2 read-only dispatched-burn attribution")
    print(f"WINDOW since={since.isoformat().replace('+00:00', 'Z')} until={until.isoformat().replace('+00:00', 'Z')}")
    print("WINDOW_POSITION five_hour=unknown weekly=unknown reason=history_db_has_no_window_reset_or_account_fields")
    for account in ("personal", "work", "unknown"):
        sessions, turns, cc, cr = metric(grouped[account])
        suffix = " reason=unmatched_dispatch_or_no_selected_profile" if account == "unknown" else ""
        print(f"ACCOUNT {account} sessions={sessions} turns={turns} cc_total={cc} cr_total={cr}{suffix}")
        for project in sorted({str(row["project_name"] or "unknown") for row in grouped[account]}):
            subset = [row for row in grouped[account] if str(row["project_name"] or "unknown") == project]
            sessions, turns, cc, cr = metric(subset)
            print(f"PROJECT account={account} project_name={project} sessions={sessions} turns={turns} cc_total={cc} cr_total={cr}")
        for model in sorted({str(row["last_model"] or "unknown") for row in grouped[account]}):
            subset = [row for row in grouped[account] if str(row["last_model"] or "unknown") == model]
            sessions, turns, cc, cr = metric(subset)
            print(f"MODEL account={account} last_model={model} sessions={sessions} turns={turns} cc_total={cc} cr_total={cr}")
    print("JOIN " + " ".join(f"{key}={join[key]}" for key in ("dispatch_dirs", "selected_profiles", "without_selected_profile", "profile_without_session", "session_without_profile", "conflicting_session_evidence")))
    print("MISSING_PROFILE_ARM_CENSUS " + " ".join(f"{arm}={arms[arm]}" for arm in ("claude", "codex", "glm", "kimi", "unknown")))


def main() -> int:
    now = datetime.now(timezone.utc)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=Path.home() / ".claude/burn/history.db")
    parser.add_argument("--handoff-root", type=Path, action="append", default=[])
    parser.add_argument("--since", type=parse_time, default=now - timedelta(days=7))
    parser.add_argument("--until", type=parse_time, default=now)
    args = parser.parse_args()
    if args.until <= args.since:
        parser.error("--until must be later than --since")
    roots = unique_existing(args.handoff_root) if args.handoff_root else default_roots()
    attribution, join, arms = scan_handoffs(roots)
    rows = query_sessions(args.db.expanduser(), args.since, args.until)
    emit(rows, attribution, join, arms, args.since, args.until)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, sqlite3.Error) as exc:
        print(f"leadv2-burn-attribute: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
