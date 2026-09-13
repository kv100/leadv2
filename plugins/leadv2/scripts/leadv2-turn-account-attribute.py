#!/usr/bin/env python3
"""Attribute burn turn_events rows to the account that paid for them.

QUOTA-TELEMETRY-CANNOT-PRICE-AN-ARM-01: turn_events rows carry a session_id
but no account, so token spend could never be joined to the quota window it
burned — 201 intervals were discarded as idle while real spend was happening.
The account is DERIVABLE, not guessed: aggregator.py records each session's
jsonl_path, and the config dir holding the transcript is by construction the
account whose keychain service suffix is sha256_8(realpath(config_dir)) — the
SAME derivation leadv2-quota-read.py applies to a running session
(account_key_for_config_dir, imported from there: one definition, never
re-implemented here).

Retro-attribution of existing rows from this recorded fact is legitimate —
the jsonl_path is where the transcript physically lives, not a backfill
guess. Measured live 2026-09-13: 0 NULL jsonl_path in 17411 sessions, 0
orphan turn_events in 8902, exactly two prefixes, both mapping to the only
two account keys that have ever parsed percentages.

Schema: ADDITIVE ONLY. turn_events gains a nullable account_key via a
guarded ALTER TABLE. SCHEMA_VERSION in ~/.claude/burn/lib.py must stay 1 —
bumping it makes ensure_schema() DROP sessions+turn_events (lib.py:120-124),
destroying the only token history; that is lane risk R1 and a hard boundary.
A rebuild by lib.py drops the column; the next run of this script re-adds it
and re-derives — nothing is lost that the rebuild had not already lost.

rc contract (a caller must NEVER be aborted by this script):
  0  attributed ok (possibly 0 rows — the caller asserts on counts, not rc)
  2  DB unreadable / locked / busy — skip this cycle
  3  sessions or turn_events absent (fresh or rebuilt DB) — resumes next run

Usage: leadv2-turn-account-attribute.py [--db PATH] [--dry-run]
Output (stdout): attributed=<n> null=<m> total=<t>[ dry_run=1]
  attributed = rows this run gave a key (0 on a second run: idempotent)
  null       = rows left unattributable (no session row, or no /projects/
               root in jsonl_path) — NULL is "unknown", never a default key
"""
import importlib.util
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.realpath(__file__))

_spec = importlib.util.spec_from_file_location(
    "leadv2_quota_read", os.path.join(HERE, "leadv2-quota-read.py"))
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)  # main() is behind an if __name__ guard
account_key_for_config_dir = _mod.account_key_for_config_dir

DEFAULT_DB = os.path.expanduser(
    os.environ.get("LEADV2_BURN_DB", "~/.claude/burn/history.db"))


def main(argv):
    db = DEFAULT_DB
    dry = False
    args = argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--db" and i + 1 < len(args):
            db = args[i + 1]
            i += 2
        elif args[i] == "--dry-run":
            dry = True
            i += 1
        else:
            print("usage: leadv2-turn-account-attribute.py [--db PATH] [--dry-run]",
                  file=sys.stderr)
            return 3
    if not os.path.exists(db):
        print("attributed=0 null=0 total=0 db_absent=1", flush=True)
        return 3

    try:
        conn = sqlite3.connect(db, timeout=2)
        conn.execute("PRAGMA busy_timeout=2000")
    except sqlite3.Error as exc:
        print("attributed=0 null=0 total=0 error=%s" % exc, file=sys.stderr)
        return 2

    try:
        names = {r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")}
        if "turn_events" not in names or "sessions" not in names:
            print("attributed=0 null=0 total=0 schema_absent=1", flush=True)
            return 3

        cols = [r[1] for r in conn.execute("PRAGMA table_info(turn_events)")]
        has_col = "account_key" in cols
        if not has_col:
            if dry:
                print("would_alter=1", file=sys.stderr)
            else:
                # Guarded additive ALTER, NO SCHEMA_VERSION bump (R1).
                try:
                    conn.execute("ALTER TABLE turn_events ADD COLUMN account_key TEXT")
                    conn.commit()
                except sqlite3.OperationalError as exc:
                    print("attributed=0 null=0 total=0 alter_error=%s" % exc,
                          file=sys.stderr)
                    return 2

        # session_id -> derived key; a session whose jsonl_path carries no
        # /projects/ root (or no session row at all) stays unmapped — its
        # turn_events rows keep account_key NULL (D3: unknown, not a guess).
        key_by_session = {}
        for sid, path in conn.execute(
                "SELECT session_id, jsonl_path FROM sessions").fetchall():
            if not sid or not path:
                continue
            cut = path.find("/projects/")
            if cut <= 0:
                continue
            key_by_session[sid] = account_key_for_config_dir(path[:cut])

        total = conn.execute("SELECT COUNT(*) FROM turn_events").fetchone()[0]
        if has_col or not dry:
            todo = conn.execute(
                "SELECT id, session_id FROM turn_events "
                "WHERE account_key IS NULL").fetchall()
        else:
            # --dry-run over a DB that does not carry the column yet: every
            # row is pending (the ALTER was skipped on purpose).
            todo = conn.execute(
                "SELECT id, session_id FROM turn_events").fetchall()
        updates = [(key_by_session[sid], tid) for tid, sid in todo
                   if sid in key_by_session]
        attributed = len(updates)
        if updates and not dry:
            try:
                conn.executemany(
                    "UPDATE turn_events SET account_key=? WHERE id=?", updates)
                conn.commit()
            except sqlite3.OperationalError as exc:
                print("attributed=0 null=0 total=%d error=%s" % (total, exc),
                      file=sys.stderr)
                return 2
        if dry:
            # projected: rows that would stay NULL = all current NULLs minus
            # the ones we can map.
            null_after = len(todo) - attributed
        else:
            null_after = conn.execute(
                "SELECT COUNT(*) FROM turn_events WHERE account_key IS NULL"
            ).fetchone()[0]
        print("attributed=%d null=%d total=%d%s"
              % (attributed, null_after, total, " dry_run=1" if dry else ""),
              flush=True)
        return 0
    except sqlite3.Error as exc:
        print("attributed=0 null=0 total=0 error=%s" % exc, file=sys.stderr)
        return 2
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
