#!/usr/bin/env bash
# leadv2-journal-fixture-purge.sh — TESTS-POLLUTE-REAL-JOURNAL-01 §2
# Surgical removal of fixture-origin rows from a real leadv2 event journal
# (~/.claude/cache/leadv2-events/<repo>.jsonl).
#
# NEVER a wholesale truncate: a row is removed iff its `task` (the dispatch
# sig8) has NO row in the same repo's dispatch ledger
# (~/.claude/cache/dispatch-ledger/<repo>.jsonl). That ledger is the funnel's
# own record of every real dispatch: it predates the journal (ledger since
# 2026-08-16, journal since 2026-08-20) and every real dispatch writes it,
# while suites stub the ledger binary (LEADV2_DISPATCH_LEDGER_BIN=/bin/true)
# but historically left the event emitter live — which is exactly the shape
# being cleaned: journal rows under a task that never existed. Rows with no
# task field, unparseable lines, and blank lines are always kept — anything
# this tool cannot positively classify as fixture-origin stays.
#
# Ground truth missing => refuse (exit 4): guessing is the failure mode §2
# exists to prevent. Dry-run is the default; --apply rewrites the file under
# the journal's own append lock (same <file>.lock the emitter takes), so a
# purge can never race a live writer mid-append.
#
# usage: leadv2-journal-fixture-purge.sh --journal <path> --ledger <path> [--apply]
# exit 0 clean/dry-run ok · 2 usage · 3 journal missing · 4 ledger missing
# (no ground truth) · 5 lock timeout
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=leadv2-portable-lock.sh
source "${SCRIPT_DIR}/leadv2-portable-lock.sh"

JOURNAL="" LEDGER="" APPLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --journal) JOURNAL="${2:-}"; shift 2 ;;
    --ledger)  LEDGER="${2:-}";  shift 2 ;;
    --apply)   APPLY=1; shift ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ -n "${JOURNAL}" && -n "${LEDGER}" ]] || {
  printf 'usage: leadv2-journal-fixture-purge.sh --journal <path> --ledger <path> [--apply]\n' >&2
  exit 2
}
[[ -f "${JOURNAL}" ]] || { printf 'journal not found: %s\n' "${JOURNAL}" >&2; exit 3; }
# No ledger, no ground truth: refuse rather than guess what is a fixture.
[[ -f "${LEDGER}" ]] || {
  printf 'ledger not found: %s — without ground truth fixture rows cannot be distinguished from real ones; refusing\n' "${LEDGER}" >&2
  exit 4
}

lockf="${JOURNAL}.lock"
exec 9>>"${lockf}"
if ! lv2_lock_wait "${lockf}" 30; then
  printf 'could not lock %s within 30s (live writer holding it) — refusing to race\n' "${lockf}" >&2
  exit 5
fi

python3 - "${JOURNAL}" "${LEDGER}" "${APPLY}" <<'PYEOF'
import json, os, sys, collections

journal, ledger, apply = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

sig8s = set()
with open(ledger) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            sig8s.add(json.loads(line).get("task_sig", "")[:8])
        except Exception:
            continue

keep, remove = [], []
task_rows = collections.Counter()
term_details = collections.Counter()
with open(journal) as f:
    for line in f:
        s = line.strip()
        if not s:
            keep.append(line)  # preserve layout bytes we cannot classify
            continue
        try:
            row = json.loads(s)
        except Exception:
            keep.append(line)  # unparseable: never delete what we can't classify
            continue
        t = row.get("task")
        if not t or t in sig8s:
            keep.append(line)
            continue
        remove.append(line)
        task_rows[t] += 1
        if row.get("kind") == "worker_terminal":
            term_details[row.get("detail", "")] += 1

print(f"ledger sig8 ground-truth entries: {len(sig8s)}")
print(f"journal rows total: {len(keep) + len(remove)}")
print(f"fixture-origin rows (task absent from ledger): {len(remove)}")
print(f"kept rows (ledger-backed, taskless, or unclassifiable): {len(keep)}")
print(f"distinct fixture task ids: {len(task_rows)}")
for d, n in term_details.most_common(8):
    print(f"  fixture worker_terminal detail: {n:6d}  {d}")
for t, n in task_rows.most_common(5):
    print(f"  fixture task sample: {t} ({n} rows)")

if not apply:
    print("dry-run: journal NOT modified (pass --apply to remove the rows above)")
    sys.exit(0)

tmp = journal + ".purge.tmp"
with open(tmp, "w") as f:
    f.writelines(keep)
os.chmod(tmp, os.stat(journal).st_mode & 0o7777)
os.replace(tmp, journal)
print(f"APPLIED: removed {len(remove)} fixture rows, kept {len(keep)}")
PYEOF
