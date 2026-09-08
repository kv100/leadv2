#!/usr/bin/env bash
# leadv2-override-triage.sh — re-derive .claude/leadv2-overrides verdicts, compare to the table.
#
# Row C4 (ONE-PLUGIN-SOURCE-TRIAGE-THE-64-OVERRIDES-01). The yaml table
# (plugins/leadv2/config/override-triage.yaml) is a snapshot; this script
# re-derives each entry's verdict from the live trees so the table cannot rot
# silently: a RETIRE file that gains a reader must stop reading RETIRE, and a
# KEEP entry whose consumer vanished must be named.
#
# Usage:
#   leadv2-override-triage.sh [--yaml <path>] [--derive] [--roots <repo>=<path>[:...]]
# Env:
#   LEADV2_OVERRIDE_TRIAGE_YAML      same as --yaml
#   LEADV2_OVERRIDE_TRIAGE_ROOTS     same as --roots (repo=path pairs, ':'-separated)
#
# Roots default: leadv2 = this script's repo root; persona-engine = ~/Projects/persona-engine;
# m3-market = ~/MythicalGames/m3-market; respiro-ios = ~/Projects/respiro-ios.
# Exit: 0 clean · 1 disagreements · 2 usage/yaml error · 4 checked=0 (empty scan is a failure).
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LEADV2_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
YAML_PATH="${LEADV2_OVERRIDE_TRIAGE_YAML:-$LEADV2_ROOT/plugins/leadv2/config/override-triage.yaml}"
ROOTS="${LEADV2_OVERRIDE_TRIAGE_ROOTS:-}"
MODE="check"

usage() {
  sed -n '4,15p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yaml)   YAML_PATH="$2"; shift 2 ;;
    --derive) MODE="derive"; shift ;;
    --roots)  ROOTS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf '[override-triage] unknown arg: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! -f "$YAML_PATH" ]]; then
  printf '[override-triage] yaml not found: %s\n' "$YAML_PATH" >&2
  exit 2
fi

export LEADV2_OVERRIDE_TRIAGE_YAML_PATH="$YAML_PATH"
export LEADV2_OVERRIDE_TRIAGE_ROOTS="$ROOTS"
export LEADV2_OVERRIDE_TRIAGE_MODE="$MODE"
export LEADV2_OVERRIDE_TRIAGE_LEADV2_ROOT="$LEADV2_ROOT"
export LEADV2_OVERRIDE_TRIAGE_SELF="$SCRIPT_DIR/leadv2-override-triage.sh"

exec python3 - <<'PYEOF'
import os, sys
try:
    import yaml
except ImportError:
    print("[override-triage] python3 PyYAML is required", file=sys.stderr)
    sys.exit(2)

HOME = os.path.expanduser("~")
DEFAULT_ROOTS = {
    "leadv2": os.environ.get("LEADV2_OVERRIDE_TRIAGE_LEADV2_ROOT") or "",
    "persona-engine": HOME + "/Projects/persona-engine",
    "m3-market": HOME + "/MythicalGames/m3-market",
    "respiro-ios": HOME + "/Projects/respiro-ios",
}
for pair in filter(None, os.environ.get("LEADV2_OVERRIDE_TRIAGE_ROOTS", "").split(":")):
    if "=" not in pair:
        continue
    repo, path = pair.split("=", 1)
    DEFAULT_ROOTS[repo] = os.path.abspath(os.path.expanduser(path))

EXCLUDE_PARTS = {"docs", "__pycache__", "node_modules", ".git"}
CLAUDE_EXCLUDE = {
    # These are runtime/transcript/browser-artifact stores, not code surfaces.
    # In particular, m3-market's auth profiles contain hundreds of MB of browser
    # cache.  Scanning them made a four-repo check exceed a foreground gate while
    # adding no possible override consumer.
    "worktrees", "leadv2-overrides", "cache", "projects", "leadv2-tasks",
    "auth-profiles", "screenshots",
}
# Self-referential artefacts: this checker and the yaml table it checks both
# name every override path, so they must never count as readers.
SELF_FILES = {os.path.abspath(os.environ.get("LEADV2_OVERRIDE_TRIAGE_YAML_PATH", "")),
              os.path.abspath(os.environ.get("LEADV2_OVERRIDE_TRIAGE_SELF", ""))}
_domain_cache = {}

def scan_domain(repo, root):
    """Code surfaces a consumer of an override file can live in. No symlink
    following, no docs (mentions are not readers), no runtime caches, and not
    the overrides dir itself (intra-override consumers are recorded by hand in
    the table's evidence fields instead)."""
    key = (repo, root)
    if key in _domain_cache:
        return _domain_cache[key]
    out = []
    if repo == "leadv2":
        tops = ["plugins", "tests", ".claude"]
    else:
        tops = [d for d in [".claude", "scripts", "bin", ".circleci", ".github"]
                if os.path.isdir(os.path.join(root, d))]
    for top in tops:
        base = os.path.join(root, top)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            keep = []
            for d in dirnames:
                if d in EXCLUDE_PARTS or os.path.islink(os.path.join(dirpath, d)):
                    continue
                if top == ".claude" and dirpath == base and d in CLAUDE_EXCLUDE:
                    continue
                keep.append(d)
            dirnames[:] = keep
            for fn in filenames:
                p = os.path.join(dirpath, fn)
                if os.path.islink(p) or p in SELF_FILES:
                    continue
                try:
                    if os.path.getsize(p) > 2_000_000:
                        continue
                    # Ignore binary artefacts even when they happen to be small.
                    # A text reader can still be extensionless (for example an
                    # executable shell entry point), so do not filter by suffix.
                    with open(p, "rb") as probe:
                        if b"\\0" in probe.read(8192):
                            continue
                    with open(p, "r", errors="ignore") as f:
                        out.append((p, f.read()))
                except OSError:
                    pass
    _domain_cache[key] = out
    return out

def readers_for(entry, domains):
    """domains: list of (repo, files). live = path-qualified or dir-loader hit;
    backup = same but inside a *vendor-backup* tree (inert copy); loose = bare
    basename mention without a path-qualified one."""
    path = entry["path"]
    self_paths = {os.path.join(DEFAULT_ROOTS[r], ".claude", "leadv2-overrides", path)
                  for r in {d[0] for d in domains} if DEFAULT_ROOTS.get(r)}
    p1 = "leadv2-overrides/" + path
    d = os.path.dirname(path)
    p2 = ("leadv2-overrides/" + d) if d else None
    base = os.path.basename(path)
    live = backup = loose = 0
    first = None
    seen = set()
    for domrepo, files in domains:
        for p, text in files:
            if p in seen or p in self_paths:
                continue
            seen.add(p)
            is_backup = "vendor-backup" in p
            if p1 in text:
                kind = "path"
            elif p2 and p2 in text:
                kind = "dir-loader"
            elif base in text:
                kind = "basename"
            else:
                continue
            if is_backup:
                backup += 1
            elif kind in ("path", "dir-loader"):
                live += 1
                if first is None:
                    rp = os.path.relpath(p, DEFAULT_ROOTS[domrepo])
                    for i, line in enumerate(text.splitlines(), 1):
                        if p1 in line or (p2 and p2 in line):
                            first = "%s:%s:%d" % (domrepo, rp, i)
                            break
                    if first is None:
                        first = "%s:%s:?" % (domrepo, rp)
            else:
                loose += 1
    return live, backup, loose, first

def derive_verdict(entry, live, backup, loose):
    if live > 0:
        return "keep"
    if backup > 0 or loose > 0:
        return "unproven"
    if entry.get("retire_candidate") is True and str(entry.get("consumer", "")).strip() == "none" \
            and str(entry.get("absent_default", "")).strip() and str(entry.get("evidence", "")).strip():
        return "retire"
    return "unproven"

def verify_consumer(entry, domains_by_repo):
    """A KEEP row pins its consumer; if that file is gone or no longer references
    the override, the row has rotted even if the verdict still agrees."""
    consumer = str(entry.get("consumer", ""))
    if consumer in ("", "none") or ":" not in consumer:
        return None
    parts = consumer.split(":")
    crepo, crel = parts[0], parts[1]
    root = DEFAULT_ROOTS.get(crepo)
    if not root or not os.path.isfile(os.path.join(root, crel)):
        return "consumer-gone: %s (file not found under %s root)" % (consumer, crepo)
    cpath = os.path.join(root, crel)
    try:
        with open(cpath, "r", errors="ignore") as f:
            text = f.read()
    except OSError:
        return "consumer-gone: %s (unreadable)" % consumer
    p1 = "leadv2-overrides/" + entry["path"]
    d = os.path.dirname(entry["path"])
    p2 = ("leadv2-overrides/" + d) if d else None
    if p1 not in text and not (p2 and p2 in text) and os.path.basename(entry["path"]) not in text:
        return "consumer-gone: %s no longer references %s" % (crel, entry["path"])
    return None

def compare_entry(entry, derived, live, backup, loose, first, domains_by_repo):
    msgs = []
    entry_verdict = entry.get("verdict", "?")
    label = "%s/%s" % (entry["repo"], entry["path"])
    if derived == "missing":
        msgs.append("MISMATCH %s yaml=%s derived=missing reason=file-missing" % (label, entry_verdict))
        return msgs
    if entry_verdict != derived:
        if entry_verdict == "retire":
            reason = "retire-blocked"
            detail = "gained reader: %s" % (first or "backup/loose hit")
        elif entry_verdict == "keep":
            reason = "keep-broken"
            detail = "readers lost (live=%d backup=%d loose=%d)" % (live, backup, loose)
        else:
            reason = "verdict-drift"
            detail = "live=%d backup=%d loose=%d" % (live, backup, loose)
        msgs.append("MISMATCH %s yaml=%s derived=%s reason=%s detail=%s"
                    % (label, entry_verdict, derived, reason, detail))
    if entry_verdict == "keep":
        gone = verify_consumer(entry, domains_by_repo)
        if gone:
            msgs.append("MISMATCH %s yaml=keep reason=%s" % (label, gone))
    return msgs

def main():
    with open(os.environ["LEADV2_OVERRIDE_TRIAGE_YAML_PATH"]) as f:
        doc = yaml.safe_load(f)
    entries = doc.get("entries") or []
    mode = os.environ.get("LEADV2_OVERRIDE_TRIAGE_MODE", "check")
    checked = skipped = disagree = 0
    lines = []
    lv2_root = DEFAULT_ROOTS.get("leadv2") or ""
    for entry in entries:
        repo = entry.get("repo", "")
        root = DEFAULT_ROOTS.get(repo)
        if not root or not os.path.isdir(root):
            skipped += 1
            lines.append("SKIPPED %s/%s reason=root-missing(%s)" % (repo, entry.get("path", "?"), repo))
            continue
        domains = [("leadv2", scan_domain("leadv2", lv2_root))]
        if repo != "leadv2" and root != lv2_root:
            domains.append((repo, scan_domain(repo, root)))
        odir = os.path.join(root, ".claude", "leadv2-overrides", entry.get("path", ""))
        if not os.path.isfile(odir):
            derived = "missing"
            live = backup = loose = 0
            first = None
        else:
            live, backup, loose, first = readers_for(entry, domains)
            derived = derive_verdict(entry, live, backup, loose)
        checked += 1
        if mode == "derive":
            lines.append("DERIVE %s/%s live=%d backup=%d loose=%d first=%s"
                         % (repo, entry.get("path", "?"), live, backup, loose, first or "-"))
            continue
        msgs = compare_entry(entry, derived, live, backup, loose, first, domains)
        disagree += len(msgs)
        lines.extend(msgs)
    for m in lines:
        print(m)
    print("checked=%d skipped=%d disagree=%d" % (checked, skipped, disagree))
    if checked == 0:
        print("[override-triage] FAILURE: examined zero entries — an empty scan is a failure, not a pass",
              file=sys.stderr)
        sys.exit(4)
    sys.exit(1 if disagree else 0)

main()
PYEOF
