# The dispatcher manufactures the very row it then refuses on

`f853b0e3` narrowed the self-race guard and its suite passes both directions — but the live
path still refuses. Measured twice today on a real re-dispatch (`V5-M1-L0-FIX`, sig
`ea519b21`), 08:47Z and 09:52Z:

```
premise_probe task=ea519b21 verdict=skipped reason=resume_lane
lane_liveness verdict=live task=ea519b21 signal=none probe_id=V5-M1-L0 raw=starting:73 age=73
lane_placement_refused task=ea519b21 reason=lane_is_live probe_id=V5-M1-L0 verdict=starting:73 age=73
```

`f853b0e3` cannot fire here: it keys on `pid_source == lead_durable` plus pid identity, and
the offending row **has no pid at all**. Read it from `active.yaml` at the time of refusal:

```yaml
- task_id: V5-M1-L0
  session_id: recovered
  lead_session_id: recovered
  phase: recovered_unowned
  started_at: '2026-09-14T09:51:03Z'     # == the moment the refusing run started
  recovered: true
  lane_events:
  - event: recovered_unowned_no_pid
```

## Root cause — two facts, both in `lib/leadv2-lane-state.sh`

**1. The mention test reads the interpreter, not the program.** In the recovery sweep
(~line 468-492) a live process makes a worktree "mentioned" — which creates the pid-less
visibility row — when its argv contains the worktree as a whole token and
`argv0 = basename(argv[0])` is not in `non_workers`. `non_workers` explicitly lists
`leadv2-dispatch-code.sh`, and the comment states the intent plainly: *"grep/tail/ps/dispatch
never make a lane"*.

But the dispatcher is invoked as `bash /…/leadv2-dispatch-code.sh --worktree /…/V5-M1-L0 …`
— that is the documented form and the one `nohup` uses — so `argv[0]` is **`bash`**, and the
exclusion never applies. The dispatcher's own command line is what conjures the row.

Note the asymmetry inside the same function: *adoption* is tested with
`programs & non_workers`, i.e. the whole argv program set, which does catch the script name.
Only the *mention* test was written against `argv[0]` alone. That asymmetry is the defect.

**2. A pid-less row earns `starting:` grace and is re-stamped on every attempt.** The
`registered_no_stream` rung in `leadv2-lane-liveness.sh` (~line 1196-1216) is pid-free by
design: `registered and age <= starting_max` → `starting:<age>` → live. The sweep writes
`started_at: now()` each time it recreates the row, so age is always ~0 and the refusal can
never age out. The creation site's own comment claims the opposite — *"it does not claim an
owner, and it ages out … so it cannot block dispatch"* — and that guarantee is false.

There is a precedent for the shape of the cure in the rung itself: `watcher_only` rows were
already denied `starting` grace under FORK-STORM-KILLS-HOOKS-01, for exactly this reason
("a row whose started_at every retry's idempotent re-registration refreshes would re-earn it
forever").

## What to change

Fix **1** — it is the generator. Make the mention test use the same program-set basis the
adoption test already uses, so a command that merely runs the dispatcher (under any
interpreter) cannot mint a lane row.

Decide for yourself whether to also fix **2**, and say which you chose and why. An argument
for doing both: 1 stops this producer, 2 makes any future pid-less producer non-blocking.
An argument against doing 2 here: it widens the blast radius of a guard that exists to stop
lane hijacking. Either answer is acceptable; an unexamined one is not.

**Do not weaken the guard.** A lane genuinely held by another session — a row with a live
pid — must still refuse with `lane_is_live`.

## Acceptance — a real suite, all three directions

1. **The dispatcher does not mint its own row.** A process whose argv is
   `bash <abs>/leadv2-dispatch-code.sh --worktree <lane-worktree> …` does NOT cause the
   sweep to create a `recovered_unowned` row for that worktree. This must fail before your
   change and pass after — show both.
2. **A real worker still does.** A process running under a `worker_markers` program
   (`claude`, `codex`, `glm-coder.sh`, …) that names the worktree still produces a row.
3. **Foreign live lane still refuses.** A row with a live pid belonging to a different task
   sig still produces `reason=lane_is_live` and a non-zero exit. This is the negative
   control and is not optional.

Direction 1 is the one that matters: state explicitly that you ran it against the
**unfixed** code and saw it fail. A suite that only ever saw the fixed code proves nothing
here — that is precisely how `f853b0e3` came to be believed.

Also required: `bash -n` on every shell file touched, plus the repo's own suite selection
for the changed files staying green, and the existing
`plugins/leadv2/scripts/tests/test-dispatch-reentry-self-race.sh` still passing (6 passed,
0 failed) — `f853b0e3` is correct for the shape it covers and must not regress.

## Report
`docs/handoff/LANE-MENTION-ARGV0-01/report.md`: the diff, which of 1 / 1+2 you did and why,
and the acceptance output verbatim for all three directions including the before/after pair
for direction 1.
