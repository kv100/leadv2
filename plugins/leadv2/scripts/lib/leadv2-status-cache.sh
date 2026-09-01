#!/usr/bin/env bash
# scripts/lib/leadv2-status-cache.sh — STATUS-CHURN-01 shared status-snapshot cache.
#
# THE BUG this fixes: every status consumer (leadv2-broad-status.sh,
# leadv2-status-collector.sh, leadv2-lanes-snapshot.sh, leadv2-lane-liveness.sh,
# leadv2-lane-status-line-tail.sh) ran its OWN independent Python scan of
# active.yaml + every *-runs/ dir, spawned at its own cadence by a different
# consumer (statusline, beat loop, pulse watch, backlog pump, lead hooks).
# Measured 2026-09-01 (load avg 244): leadv2-broad-status.sh x10,
# leadv2-status-collector.sh x8, leadv2-lanes-snapshot.sh x4,
# leadv2-lane-liveness.sh x6 in ONE `ps` instant -- the CPU spikes are these
# short-lived scans (66-92% of a core each), not the sleeping loops.
#
# THE FIX: ONE snapshot file per project control-plane
# (`<control-plane>/status-snapshot.json`), atomic tmp+mv, stamped with
# `computed_at`. A consumer asks for a snapshot no older than
# LEADV2_STATUS_SNAPSHOT_TTL_S (default 10, floor 3): if fresh, it reads the
# file immediately (`hit`); if stale, exactly ONE producer wins a
# non-blocking flock and recomputes (`recompute`) while the rest poll for up
# to 2s and then read the freshly-written file (`hit`, `age_s` measured from
# the NEW computed_at). If nobody has finished within that 2s window (lock
# holder wedged/dead), the caller does one more short blocking-lock attempt
# and recomputes itself rather than ever silently serving data older than
# TTL+2s (`miss` is journaled only for genuine give-ups, and even then the
# caller recomputes rather than trusting stale content past the bound).
#
# Every call appends exactly one line to
# `<control-plane>/status-snapshot-journal.jsonl`:
#   {"ts":<epoch>,"event":"status_snapshot","kind":"hit|miss|recompute","producer":"<name>","age_s":<n>}
# `leadv2-spawn-rate.sh` reads this journal to compute the ticket's
# before/after acceptance numbers.
#
# WHAT THIS DOES NOT DO: it does not change what any status surface
# DISPLAYS. It only caches the raw COMPUTE step behind a `compute_cmd` that
# each consumer supplies; the consumer's own rendering/formatting logic is
# untouched. A consumer that needs bespoke fields writes its own
# `compute_cmd` that emits whatever JSON shape it wants under the shared
# snapshot file (last writer's shape wins the file until the next recompute)
# -- see leadv2-status-collector.sh's compute step for the reference shape
# (active.yaml raw text + a directory listing of every `*-runs` dir with
# mtimes), which is the superset the other four consumers were duplicating.
#
# Usage (source, then call):
#   source ".../lib/leadv2-status-cache.sh"
#   snap_path="$(lv2_status_snapshot_get "<producer-name>" "<compute_cmd> [args...]")"
#   # $snap_path is the absolute path to a fresh-enough JSON file; read it.
#
# compute_cmd MUST print a JSON object (or object-producing text) to stdout;
# non-JSON stdout is wrapped as {"raw": "<stdout>"}. computed_at/producer are
# added by this library, not by compute_cmd.
#
# Bash 3.2 compatible: no associative arrays, no readarray, no ${x^^}.

LV2_STATUS_CACHE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LV2_STATUS_CACHE_STATE_PATH_SH="${LV2_STATUS_CACHE_LIB_DIR}/../leadv2-state-path.sh"

# lv2_status_snapshot_ttl — resolve effective TTL (seconds), floor 3.
lv2_status_snapshot_ttl() {
  local ttl="${LEADV2_STATUS_SNAPSHOT_TTL_S:-10}"
  # integer-only guard (bash 3.2 has no [[ =~ ]] portability issue here, but
  # keep it simple and defensive against non-numeric env pollution)
  case "$ttl" in
    ''|*[!0-9]*) ttl=10 ;;
  esac
  if [[ "$ttl" -lt 3 ]]; then
    ttl=3
  fi
  echo "$ttl"
}

# lv2_status_snapshot_path — absolute path to the shared snapshot file for
# the CURRENT project's control plane (resolved via leadv2-state-path.sh, so
# it is identical across every worktree of the same repo).
lv2_status_snapshot_path() {
  PROJECT_ROOT="${PROJECT_ROOT:-${LEADV2_PROJECT_ROOT:-}}" "${LV2_STATUS_CACHE_STATE_PATH_SH}" --no-link status-snapshot.json 2>/dev/null
}

# lv2_status_snapshot_journal_path — journal file, same control plane.
lv2_status_snapshot_journal_path() {
  PROJECT_ROOT="${PROJECT_ROOT:-${LEADV2_PROJECT_ROOT:-}}" "${LV2_STATUS_CACHE_STATE_PATH_SH}" --no-link status-snapshot-journal.jsonl 2>/dev/null
}

# lv2_status_snapshot_get <producer_name> <compute_cmd...>
#   Prints the absolute path of a fresh-enough snapshot file to stdout.
#   Returns 0 on success. compute_cmd is only invoked when this call is the
#   one that wins the recompute race (or the pathological wedged-lock
#   fallback).
lv2_status_snapshot_get() {
  local producer="$1"
  shift
  local snapshot_path journal_path ttl
  snapshot_path="$(lv2_status_snapshot_path)"
  journal_path="$(lv2_status_snapshot_journal_path)"
  ttl="$(lv2_status_snapshot_ttl)"
  if [[ -z "$snapshot_path" ]]; then
    return 1
  fi
  mkdir -p "$(dirname "$snapshot_path")" 2>/dev/null || true

  LV2SC_SNAPSHOT_PATH="$snapshot_path" \
  LV2SC_JOURNAL_PATH="$journal_path" \
  LV2SC_TTL="$ttl" \
  LV2SC_PRODUCER="$producer" \
  python3 - "$@" <<'PY'
import fcntl
import json
import os
import signal
import subprocess
import sys
import tempfile
import time

snapshot_path = os.environ["LV2SC_SNAPSHOT_PATH"]
journal_path = os.environ["LV2SC_JOURNAL_PATH"]
ttl = float(os.environ["LV2SC_TTL"])
producer = os.environ["LV2SC_PRODUCER"]
compute_cmd = sys.argv[1:]
lock_path = snapshot_path + ".lock"


def read_computed_at(path):
    try:
        with open(path) as f:
            data = json.load(f)
        return data.get("computed_at")
    except Exception:
        return None


def journal(kind, age_s):
    try:
        line = json.dumps({
            "ts": time.time(),
            "event": "status_snapshot",
            "kind": kind,
            "producer": producer,
            "age_s": age_s,
        })
        with open(journal_path, "a") as jf:
            jf.write(line + "\n")
    except Exception:
        pass


def do_compute():
    result = subprocess.run(compute_cmd, capture_output=True, text=True, timeout=30)
    stdout = result.stdout or ""
    try:
        data = json.loads(stdout) if stdout.strip() else {}
        if not isinstance(data, dict):
            data = {"raw": data}
    except Exception:
        data = {"raw": stdout}
    data["computed_at"] = time.time()
    data["producer"] = producer
    fd, tmp_path = tempfile.mkstemp(
        prefix=".status-snapshot.tmp.", dir=os.path.dirname(snapshot_path) or "."
    )
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f)
        os.replace(tmp_path, snapshot_path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass
        raise
    return data["computed_at"]


now = time.time()
computed_at = read_computed_at(snapshot_path)
age = (now - computed_at) if computed_at is not None else None

if age is not None and age <= ttl:
    journal("hit", round(age, 3))
    print(snapshot_path)
    sys.exit(0)

# Stale or missing -- try to become the single recomputer (non-blocking).
lock_f = open(lock_path, "a+")
got_lock = False
try:
    fcntl.flock(lock_f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    got_lock = True
except (BlockingIOError, OSError):
    got_lock = False

if got_lock:
    try:
        do_compute()
        journal("recompute", 0.0 if age is None else round(age, 3))
        print(snapshot_path)
    finally:
        try:
            fcntl.flock(lock_f.fileno(), fcntl.LOCK_UN)
        except Exception:
            pass
        lock_f.close()
    sys.exit(0)

# Someone else holds the lock and is (presumably) recomputing right now.
# Poll for up to 2s for a NEW computed_at to land, and never report a
# snapshot older than ttl+2s as a hit.
lock_f.close()
deadline = now + 2.0
prior = computed_at
while time.time() < deadline:
    time.sleep(0.05)
    c = read_computed_at(snapshot_path)
    if c is not None and c != prior:
        fresh_age = time.time() - c
        if fresh_age <= ttl + 2.0:
            journal("hit", round(fresh_age, 3))
            print(snapshot_path)
            sys.exit(0)

# Gave up waiting (lock holder wedged/dead, or it simply took >2s). Never
# hand back data whose age could exceed ttl+2s -- make one bounded blocking
# attempt to grab the lock ourselves and recompute; if even that fails,
# recompute unlocked (a rare duplicate compute is a lesser incident than a
# consumer silently trusting stale-past-bound data).


class _Timeout(Exception):
    pass


def _alarm(signum, frame):
    raise _Timeout()


old_handler = signal.signal(signal.SIGALRM, _alarm)
signal.alarm(1)
lock_f2 = open(lock_path, "a+")
locked_here = False
try:
    fcntl.flock(lock_f2.fileno(), fcntl.LOCK_EX)
    locked_here = True
except _Timeout:
    locked_here = False
finally:
    signal.alarm(0)
    signal.signal(signal.SIGALRM, old_handler)

try:
    stale_age = None
    c = read_computed_at(snapshot_path)
    if c is not None:
        stale_age = round(time.time() - c, 3)
    do_compute()
    journal("recompute", -1.0 if stale_age is None else stale_age)
    print(snapshot_path)
finally:
    if locked_here:
        try:
            fcntl.flock(lock_f2.fileno(), fcntl.LOCK_UN)
        except Exception:
            pass
    lock_f2.close()
PY
}
