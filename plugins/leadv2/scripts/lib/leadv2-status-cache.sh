#!/usr/bin/env bash
# scripts/lib/leadv2-status-cache.sh — STATUS-CHURN-01 scoped status-snapshot cache.
#
# THE COST this pays down (measured 2026-09-01, load avg 244): the status
# surfaces each spawn their own short-lived scans at their own cadence —
# leadv2-broad-status.sh x10, leadv2-status-collector.sh x8,
# leadv2-lanes-snapshot.sh x4, leadv2-lane-liveness.sh x6 in ONE `ps`
# instant -- and those scans (66-92% of a core each), not the sleeping
# loops, are the CPU spikes.
#
# WHAT THIS LIBRARY IS: a TTL/flock/journal cache around a compute step a
# consumer supplies. It has exactly ONE production consumer today —
# leadv2-status-collector.sh's git section (scope "git-facts"), whose
# compute_cmd re-invokes that collector with --git-facts-only so a cache
# miss pays the 3 git subprocesses the section needs instead of the whole
# collector. Census (grep lv2_status_snapshot_get across
# plugins/leadv2/scripts, 2026-09-02): that is the only call site. The other
# status consumers still do their own reads; wiring them onto this cache is
# future work, deliberately not claimed here (R3 H3/H4: headers must
# describe what the diff DOES).
#
# Mechanics: ONE snapshot file per scope under the project control-plane
# (`<control-plane>/status-snapshot[-<scope>].json`), atomic tmp+mv, stamped
# with `computed_at`. A consumer asks for a snapshot no older than
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
# `<control-plane>/status-snapshot[-<scope>]-journal.jsonl`:
#   {"ts":<epoch>,"event":"status_snapshot","kind":"hit|recompute","producer":"<name>","age_s":<n>}
# `age_s` is always the age of the snapshot the caller was SERVED: hits
# report the age of the file they read; recomputes report ~0 (the file they
# just wrote), with the pre-recompute staleness kept as a separate
# `stale_age_s` diagnostic field. `leadv2-spawn-rate.sh` counts kinds only
# (it reads kind/producer, never age_s), so the age_s semantics above are
# safe for it.
#
# Cached-file shape: whatever compute_cmd prints (a JSON object; non-JSON
# stdout is wrapped as {"raw": "<stdout>"}), with computed_at/producer
# OVERWRITTEN by this library at write time. The one live compute_cmd
# (git-facts) emits {local_head, branch, unpushed, computed_at: null,
# producer: null} — the two nulls keep ONE shape on every path, including
# the caller's own bypass/fallback which prints compute_cmd output as-is.
#
# Usage (source, then call):
#   source ".../lib/leadv2-status-cache.sh"
#   snap_path="$(lv2_status_snapshot_get "<producer-name>" "<compute_cmd> [args...]")"
#   # $snap_path is the absolute path to a fresh-enough JSON file; read it.
#
# compute_cmd MUST print a JSON object (or object-producing text) to stdout.
# computed_at/producer are set by this library, not by compute_cmd.
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

# lv2_status_snapshot_path [scope] — absolute path to the shared snapshot
# file for the CURRENT project's control plane (resolved via
# leadv2-state-path.sh, so it is identical across every worktree of the same
# repo). With no scope: the original single shared file (back-compat, still
# what test-status-churn.sh's multi-producer scenarios exercise). With a
# scope (e.g. "git", "registry", a sanitized foreign-repo slug): a SEPARATELY
# named file, so two DIFFERENT raw-probe shapes (e.g. status-collector's git
# facts vs. lanes-snapshot's foreign-registry copy) never clobber each other
# under one filename -- see lv2_status_snapshot_get_scoped below.
lv2_status_snapshot_path() {
  local scope="${1:-}"
  local name="status-snapshot.json"
  [[ -n "$scope" ]] && name="status-snapshot-${scope}.json"
  PROJECT_ROOT="${PROJECT_ROOT:-${LEADV2_PROJECT_ROOT:-}}" "${LV2_STATUS_CACHE_STATE_PATH_SH}" --no-link "$name" 2>/dev/null
}

# lv2_status_snapshot_journal_path [scope] — journal file, same control plane.
lv2_status_snapshot_journal_path() {
  local scope="${1:-}"
  local name="status-snapshot-journal.jsonl"
  [[ -n "$scope" ]] && name="status-snapshot-${scope}-journal.jsonl"
  PROJECT_ROOT="${PROJECT_ROOT:-${LEADV2_PROJECT_ROOT:-}}" "${LV2_STATUS_CACHE_STATE_PATH_SH}" --no-link "$name" 2>/dev/null
}

# lv2_status_snapshot_get <producer_name> <compute_cmd...>
#   Prints the absolute path of a fresh-enough snapshot file to stdout.
#   Returns 0 on success. compute_cmd is only invoked when this call is the
#   one that wins the recompute race (or the pathological wedged-lock
#   fallback). Unscoped — every caller shares ONE file (original behaviour).
lv2_status_snapshot_get() {
  lv2_status_snapshot_get_scoped "" "$@"
}

# lv2_status_snapshot_get_scoped <scope> <producer_name> <compute_cmd...>
#   Same contract as lv2_status_snapshot_get, but the snapshot/journal file
#   is namespaced by <scope> (empty scope == the original unscoped file).
#   STATUS-CHURN-01 round 2: separate scopes let different real consumers
#   (status-collector's git facts, the shared active.yaml registry copy read
#   by broad-status/lane-status-line-tail, lanes-snapshot's per-foreign-repo
#   registry copy) each get their OWN debounced file instead of colliding on
#   one shape, while still sharing the same TTL/lock/journal machinery.
lv2_status_snapshot_get_scoped() {
  local scope="$1"
  local producer="$2"
  shift 2
  local snapshot_path journal_path ttl
  snapshot_path="$(lv2_status_snapshot_path "$scope")"
  journal_path="$(lv2_status_snapshot_journal_path "$scope")"
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


def journal(kind, age_s, stale_age_s=None):
    try:
        rec = {
            "ts": time.time(),
            "event": "status_snapshot",
            "kind": kind,
            "producer": producer,
            "age_s": age_s,
        }
        if stale_age_s is not None:
            rec["stale_age_s"] = stale_age_s
        line = json.dumps(rec)
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
        # age_s is the age of the snapshot SERVED (the one just written, ~0);
        # the pre-recompute staleness rides along as stale_age_s (R3 H6).
        new_ts = do_compute()
        journal("recompute", round(time.time() - new_ts, 3),
                None if age is None else round(age, 3))
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
    new_ts = do_compute()
    journal("recompute", round(time.time() - new_ts, 3), stale_age)
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
