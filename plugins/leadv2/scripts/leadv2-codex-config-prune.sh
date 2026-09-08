#!/usr/bin/env bash
# Prune dead project tables, or register one canonical worktree path.
# Usage: ... [--dry-run] [--config FILE] | --trust PATH [--config FILE]
# Python 3.11+ is required. The editor preserves retained bytes and comments.
# Both operations share an advisory lock and replace the config atomically.
# Worktree deletion does not remove trust: run this command periodically.
set -euo pipefail
python3 - "$@" <<'PY'
import argparse
import datetime
import errno
import fcntl
import json
import os
from pathlib import Path
import stat
import tempfile
import time
import tomllib


def scan_line(line, quote, depth=0):
    """Find comments and carry multiline TOML string state across lines."""
    i = 0
    while i < len(line):
        if quote:
            if quote.startswith('"') and line[i] == '\\':
                i += 2
            elif line.startswith(quote, i):
                i += len(quote)
                # Four/five quote endings include one/two literal quotes.
                if len(quote) == 3:
                    while i < len(line) and line[i] == quote[0]:
                        i += 1
                quote = None
            else:
                i += 1
        elif line[i] == '#':
            return quote, i, depth
        elif line[i] in "\"'":
            quote = line[i] * (3 if line.startswith(line[i] * 3, i) else 1)
            i += len(quote)
        else:
            if line[i] in '[{':
                depth += 1
            elif line[i] in ']}':
                depth -= 1
            i += 1
    return quote, None, depth


def sections(text):
    """Use TOML's parser for header keys; keep source slices for lossless edits."""
    result = []
    current = {'keys': (), 'lines': []}
    quote = None
    depth = 0
    for line in text.splitlines(keepends=True):
        starts_header = quote is None and depth == 0 and line.lstrip().startswith('[')
        quote, comment, depth = scan_line(line, quote, depth)
        if starts_header:
            header = line[:comment].strip() if comment is not None else line.strip()
            node = tomllib.loads(header)
            keys = []
            while isinstance(node, dict) and len(node) == 1:
                key, node = next(iter(node.items()))
                keys.append(key)
                if isinstance(node, list):
                    node = node[0]
            result.append(current)
            current = {'keys': tuple(keys), 'lines': []}
        current['lines'].append(line)
    result.append(current)
    return result


def comments_only(lines):
    kept = []
    quote = None
    for line in lines:
        quote, comment, _ = scan_line(line, quote)
        if comment is not None:
            # Full-line comments and whitespace remain byte-identical; an inline
            # comment on a removed setting becomes a standalone comment.
            kept.append(line if not line[:comment].strip() else line[comment:])
        elif not line.strip() and quote is None:
            kept.append(line)
    return ''.join(kept)


def path_exists(path):
    try:
        os.stat(path)
        return True
    except OSError as exc:
        if exc.errno in (errno.ENOENT, errno.ENOTDIR):
            return False
        raise  # Permission/I/O failures are not evidence of a dead path.


def prune(text, data):
    projects = data.get('projects', {})
    if not isinstance(projects, dict):
        raise ValueError('projects is not a table')
    parts = sections(text)
    explicit = {p['keys'][1] for p in parts
                if len(p['keys']) >= 2 and p['keys'][0] == 'projects'}
    if set(projects) - explicit:
        raise ValueError('inline/dotted project definitions unsupported; config left untouched')
    removed = set()
    live = {}
    dead = duplicates = conflicts = 0
    for path, policy in projects.items():
        if not os.path.isabs(path):
            raise ValueError('non-absolute project path; config left untouched')
        exists = path_exists(path)
        if not exists:
            removed.add(path)
            dead += 1
        else:
            real = os.path.realpath(path)
            live.setdefault(real, []).append(path)
    for real, paths in live.items():
        # Prefer the physical spelling. Never discard a differing live policy.
        winner = real if real in paths else paths[0]
        for path in paths:
            if path != winner:
                if projects[path] == projects[winner]:
                    removed.add(path)
                    duplicates += 1
                else:
                    conflicts += 1
    output = ''.join(comments_only(p['lines'])
                     if len(p['keys']) >= 2 and p['keys'][0] == 'projects'
                     and p['keys'][1] in removed else ''.join(p['lines'])
                     for p in parts)
    return output, {'before': len(projects), 'removed': len(removed),
                    'dead': dead, 'duplicates': duplicates,
                    'retained_conflicts': conflicts, 'remaining': len(projects) - len(removed)}


def trust(text, data, path):
    if not os.path.isabs(path) or not path_exists(path):
        raise ValueError('trust requires an existing absolute path')
    real = os.path.realpath(path)
    projects = data.get('projects', {})
    for existing in projects:
        if os.path.realpath(existing) == real:
            return text, {'added': 0, 'path': real}
    stanza = ('\n[projects.' + json.dumps(real, ensure_ascii=False) + ']\n'
              'trust_level = "trusted"\napproval_policy = "never"\n'
              'sandbox_mode = "danger-full-access"\nnetwork_access = "enabled"\n')
    tomllib.loads(stanza)
    return text + stanza, {'added': 1, 'path': real}


def replace_config(config, original, output, mode):
    fd, name = tempfile.mkstemp(prefix=config.name + '.tmp-', dir=config.parent)
    try:
        with os.fdopen(fd, 'wb') as handle:
            os.fchmod(handle.fileno(), mode)
            handle.write(output)
            handle.flush()
            os.fsync(handle.fileno())
        if config.read_bytes() != original:
            raise ValueError('config changed concurrently; retry without overwriting')
        os.replace(name, config)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', default=str(Path(os.environ.get('CODEX_HOME',
                        str(Path.home() / '.codex'))) / 'config.toml'))
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--trust', metavar='PATH')
    args = parser.parse_args()
    config = Path(args.config).resolve(strict=True)
    # A stable sidecar locks across atomic replacements, unlike the config inode.
    # Dry runs are read-only snapshots and do not create lock/backup files.
    lock = None
    try:
        if not args.dry_run:
            lock = os.open(str(config) + '.leadv2.lock', os.O_CREAT | os.O_RDWR, 0o600)
            deadline = time.monotonic() + 10
            while True:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() >= deadline:
                        raise ValueError('config lock timeout after 10 seconds')
                    time.sleep(0.05)
        original = config.read_bytes()
        text = original.decode('utf-8')
        data = tomllib.loads(text)
        output, report = trust(text, data, args.trust) if args.trust else prune(text, data)
        if not args.trust:
            tomllib.loads(output)  # Validate the result of section removal.
        backup = None
        if output != text and not args.dry_run:
            mode = stat.S_IMODE(config.stat().st_mode)
            if not args.trust:
                stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
                backup = str(config) + '.bak-' + stamp
                fd = os.open(backup, os.O_CREAT | os.O_EXCL | os.O_WRONLY, mode)
                with os.fdopen(fd, 'wb') as handle:
                    handle.write(original)
                    handle.flush()
                    os.fsync(handle.fileno())
            replace_config(config, original, output.encode('utf-8'), mode)
        report.update(dry_run=args.dry_run, backup=backup)
        print(json.dumps(report, sort_keys=True))
    finally:
        if lock is not None:
            os.close(lock)


try:
    main()
except (OSError, ValueError) as exc:
    raise SystemExit('codex-config: ' + str(exc))
PY
