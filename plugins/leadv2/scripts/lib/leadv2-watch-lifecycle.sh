#!/usr/bin/env bash
# lib/leadv2-watch-lifecycle.sh — WATCHER-LIFECYCLE-LEAK-01 shared watcher
# lifecycle: race-safe singleton claim, owner-bound self-reap, reap-on-close,
# and the one-line-per-event instrumentation log.
#
# Sourced (never executed) by leadv2-single-lead-beat-loop.sh,
# leadv2-lane-pulse-watch.sh and leadv2-dispatch-ledger.sh (reap-on-close).
#
# Root cause this lib kills (ticket 2026-09-01, ~/Desktop/leadv2-laptop-load-
# ticket-for-dima-2026-09-01.md follow-up #1): 17 DUPLICATE beat loops were
# measured live from ONE worktree, re-spawned every few minutes, plus
# lane-pulse watchers persisting at PPID 1 after their owner was gone. The
# pre-existing pidfile guards were CHECK-THEN-WRITE with no cmdline
# validation: two dispatches racing through the guard's slow prelude
# (state-path resolution) both saw no pidfile and both armed; the pidfile
# loser was then invisible forever — no later arm could refuse against it —
# and ran to its full lifetime cap (86400s for the beat loop).
#
# Contract:
#   wl_singleton_claim <pidfile> [needle]
#       rc 0 — this caller may run (fresh claim, stale/foreign pidfile
#              replaced, or pidfile dir unwritable -> fail-open spawn, the
#              pre-fix behavior, per the mission's fail-open constraint);
#       rc 3 — a LIVE process whose command line contains <needle> already
#              holds <pidfile>: caller logs dedup_refused and exits 0.
#              <needle> defaults to the CALLING script's basename
#              (BASH_SOURCE[1]) so a renamed/copied script still self-matches
#              its own cmdline — a bare `kill -0` also matched RECYCLED pids
#              (wrong process -> false no-op, silent starvation) and never
#              matched the loser of a write race.
#       The claim is a stateless noclobber-create + post-settle verify (see
#       the function comment): in any interleaving exactly the process named
#       by the surviving pidfile runs — the losers all observe a live twin —
#       closing the TOCTOU that produced the 17 duplicates.
#   wl_owner_gone — rc 0 iff LEADV2_WATCHER_OWNER_PID is set, numeric and
#       dead. The seam for ops/tests that arm a watcher with a concrete
#       owner process; unset (production default) answers "no" and changes
#       nothing. The watchers' DURABLE owners are their own board signals
#       (live-lane count / terminal-or-timeout) — a dispatcher pid is NOT a
#       valid owner (it exits seconds after arming; see the call sites).
#   wl_reap <pidfile> <needle> <tag> <owner> — best-effort, idempotent
#       TERM-then-KILL of the watcher holding <pidfile>. Dead pid ->
#       no-op (+pidfile cleanup); live but foreign cmdline (pid reuse) ->
#       left alone. Logs event=reaped.
#   wl_event <tag> <owner> <pid> <event> — ONE line
#       `ts|tag|owner|pid|event` appended to $LEADV2_WATCH_LIFECYCLE_LOG,
#       soft-fail (an unwritable log dir never kills a watcher). Events:
#       spawn | dedup_refused | self_reap | reaped.
#
# Negative-control seam: LEADV2_WATCH_SINGLETON=0 reverts wl_singleton_claim
# to the pre-fix blind pidfile write (always rc 0, no liveness check) — the
# declared red path for test-watch-lifecycle.sh L7.
#
# Bash 3.2 safe (no assoc arrays, no ${var,,}). No set -e assumptions:
# every function is called in a condition or behind an explicit case.

# wl_event <tag> <owner> <pid> <event> — one instrumentation line, soft-fail
wl_event() {  # <tag> <owner> <pid> <event>
  local f="${LEADV2_WATCH_LIFECYCLE_LOG:-}"
  [[ -n "$f" ]] || return 0
  mkdir -p "$(dirname "$f")" 2>/dev/null || true
  printf '%s|%s|%s|%s|%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "$4" \
    >> "$f" 2>/dev/null || true
  return 0
}

# wl_cmdline_match <pid> <needle> — rc0 iff pid is live AND its command line
# contains needle (basename match survives ps path prefixes; the needle is
# short enough that no ps truncation can cut it out of a `bash <script>` argv)
wl_cmdline_match() {  # <pid> <needle>
  local cmd
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$1" 2>/dev/null || return 1
  cmd="$(ps -p "$1" -o command= 2>/dev/null || true)"
  [[ -n "$cmd" && "$cmd" == *"$2"* ]]
}

# wl_pidfile_live <pidfile> <needle> — rc0 iff pidfile's pid is a live needle process
wl_pidfile_live() {  # <pidfile> <needle>
  local p
  [[ -f "$1" ]] || return 1
  p="$(cat "$1" 2>/dev/null | tr -d '[:space:]')"
  wl_cmdline_match "$p" "$2"
}

# wl_singleton_claim <pidfile> [needle] — rc0 may run / rc3 live duplicate.
# Stateless two-step primitive (no lock files to orphan):
#   1. pidfile present -> a live cmdline-matching holder REFUSES (rc3); a
#      dead or recycled-foreign pid is removed;
#   2. exclusive create (set -C noclobber) of the pidfile with OUR pid —
#      create fails if a concurrent claimer wrote it first, so the loop
#      re-reads.
# A stale-replacer can still delete a JUST-created claim between another
# claimer's step-1 read and its rm, so a WON create is not final: after a
# settle longer than any claimer's read->rm->create span (ms), the FINAL
# pidfile content decides — our pid -> rc0, a live twin -> rc3. In any
# interleaving exactly the process named by the surviving pidfile runs; the
# losers all see a live twin and refuse.
wl_singleton_claim() {  # <pidfile> [needle]
  local pf="$1" needle="${2:-$(basename "${BASH_SOURCE[1]:-${0}}")}"
  local i held
  # negative-control seam: pre-WATCHER-LIFECYCLE-LEAK-01 blind write
  if [[ "${LEADV2_WATCH_SINGLETON:-1}" != "1" ]]; then
    mkdir -p "$(dirname "$pf")" 2>/dev/null || true
    printf '%s\n' "$$" > "${pf}.tmp.$$" 2>/dev/null \
      && mv -f "${pf}.tmp.$$" "$pf" 2>/dev/null || true
    return 0
  fi
  for ((i = 0; i < 10; i++)); do
    if [[ -f "$pf" ]]; then
      if wl_pidfile_live "$pf" "$needle"; then return 3; fi
      rm -f "$pf" 2>/dev/null || true   # stale (dead) or foreign (recycled pid)
    fi
    mkdir -p "$(dirname "$pf")" 2>/dev/null || true
    if ( set -C; printf '%s\n' "$$" > "$pf" ) 2>/dev/null; then
      sleep 0.2   # settle: outlast any concurrent claimer's rm->create span
      held="$(cat "$pf" 2>/dev/null | tr -d '[:space:]')"
      if [[ "$held" == "$$" ]]; then return 0; fi
      if wl_pidfile_live "$pf" "$needle"; then return 3; fi
      continue   # neither us nor a live twin (replaced again?) — loop retries
    fi
    sleep 0.1     # create raced a concurrent (re)placer — re-read next pass
  done
  # unwritable dir / pathological contention: honor a readable live pidfile,
  # else fail OPEN (spawn) — never refuse a healthy board's beat over
  # lifecycle bookkeeping
  wl_pidfile_live "$pf" "$needle" && return 3
  return 0
}

# wl_owner_gone — rc0 iff LEADV2_WATCHER_OWNER_PID is set and dead
wl_owner_gone() {
  local p="${LEADV2_WATCHER_OWNER_PID:-}"
  [[ "$p" =~ ^[0-9]+$ ]] || return 1
  ! kill -0 "$p" 2>/dev/null
}

# wl_reap <pidfile> <needle> <tag> <owner> — best-effort idempotent reap
wl_reap() {  # <pidfile> <needle> <tag> <owner>
  local pf="$1" needle="$2" tag="$3" owner="$4" p i
  [[ -f "$pf" ]] || return 0
  p="$(cat "$pf" 2>/dev/null | tr -d '[:space:]')"
  if ! wl_cmdline_match "$p" "$needle"; then
    # dead -> clear the stale pidfile; live-but-foreign (pid reuse) -> untouched
    kill -0 "$p" 2>/dev/null || rm -f "$pf" 2>/dev/null || true
    return 0
  fi
  kill -TERM "$p" 2>/dev/null || true
  for ((i = 0; i < 20; i++)); do
    kill -0 "$p" 2>/dev/null || break
    sleep 0.1
  done
  kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null || true
  wl_event "$tag" "$owner" "$p" "reaped"
  return 0
}
