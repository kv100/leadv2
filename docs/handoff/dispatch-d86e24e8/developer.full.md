verdict: APPROVE
next_action: review_round_2

# developer.full.md — dispatch-d86e24e8 / LANE-MENTION-ARGV0-01

Full analysis, diff rationale, and all test evidence live in
`docs/handoff/LANE-MENTION-ARGV0-01/report.md` (this task's canonical report, per the mission's
own "Report" section). This file is the required protocol pointer plus a condensed restatement.

## Verdict on the census (PREPASS-MECHANISM-CLOSURE-01)

Read both target functions end to end (`lib/leadv2-lane-state.sh` reconcile sweep,
`leadv2-lane-liveness.sh` `registered_no_stream` rung) against the architect prepass's §1
caller/callee table and §3 census before writing any code. No falsification: both sweep call
sites, the ancestry/ppid seam, the TTL reaper comment, and the liveness rung order matched the
census exactly. Implemented the design as scoped — Change 1 (mandatory, argv-basis split +
ancestry-first) and Change 2 (recommended, included: pid-less `recovered` rows lose `starting:`
grace).

## What changed

1. `plugins/leadv2/scripts/lib/leadv2-lane-state.sh` — the mention test in the `reconcile` sweep
   now judges tool names (`grep`/`ps`/`tail`/`Monitor`) at `argv[0]` only (unchanged) but script
   names (`leadv2-dispatch-code.sh`/`leadv2-lane-liveness.sh`) over the whole argv program set
   (new — interpreter-agnostic). The ancestry check moved before the mention test so a self-run
   sweep can't mint a row for its own lineage either.
2. `plugins/leadv2/scripts/leadv2-lane-liveness.sh` — a `recovered` row with no `pid` gets no
   `starting:` grace (falls straight to the dead determination), same precedent as the existing
   `watcher_only` exclusion.
3. `plugins/leadv2/scripts/tests/test-lane-mention-argv0.sh` (new) — 10 cases: D-1a/D-1b
   RED-before/GREEN-after against the real unfixed `ed30627c` lib (not a mutant), D-1c wrapper
   variants, D-2 adoption/mention regression checks, D-2b liveness grace + negative control.

## Acceptance evidence (verbatim in report.md)

- Direction 1 (dispatcher doesn't mint its own row): D-1a + D-1b, both RED on `ed30627c`, GREEN
  on the fix.
- Direction 2 (real worker still adopts): D-2, PASS.
- Direction 3 (foreign live lane still refuses): `test-dispatch-reentry-self-race.sh` R-b,
  unchanged, still 6/6 green.
- `bash -n` all 3 files, `python3 -m py_compile` on both embedded python heredoc bodies: all OK.
- Full 14-suite changed-scope trigger run (`LEADV2_RUN_ALL_LIST_TRIGGERS=1`): 11 clean green, 3
  pre-existing reds (`test-lane-finished-state.sh`, `test-lane-liveness-authoritative.sh`,
  `test-reap-funnel-death-proof.sh`) verified byte-identical failure signatures on the unfixed
  `ed30627c` checkout of the same two files — not this diff's regression.

## Left alone

`_lv2_ws_pending`, adoption predicate, `unowned_expired` TTL, `f853b0e3`'s self-pid branch,
watcher reaping, status-surface rendering, `hooks.json` — all per prepass §8, out of scope.

## Committed

Lane branch, 1 commit, LANE_WRITES-scoped diff (3 files, matches prepass exactly).

DELIVERABLE_COMPLETE
