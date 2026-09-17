# WRITESET-GATE-BLOCKS-THE-BOARD-ON-A-FOREIGN-LANES-UNDECLARED-WRITE-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

## The defect, observed

`plugins/leadv2/scripts/leadv2-active-registry.sh:548-570`, inside the write-set admission gate:

```python
if other_raw is None:
    if _lv2_ws_pending(other) and _lv2_ws_live_worker(other):
        print(f"[registry] writeset conflict: other={other.get('task_id')} "
              f"reason=pending_resolution writes_reason={other.get('writes_reason') or 'undeclared'}",
              file=sys.stderr)
        sys.exit(5)
```

`other_raw is None` means **that row recorded no write set at all**. The refusal fires *before any
path comparison happens*. So one row with an unrecorded write set refuses **every** new dispatch
board-wide, no matter how disjoint the incoming lane's paths are.

Measured 2026-09-16/17: lane `f11c97a14f88` was refused three times with
`dispatch_refused reason=writeset_pending blocked_by=<other> blocked_writes_reason=undeclared
age_s=3076 window_s=900`, while its own declared set was clean and disjoint from the blocker's.
Five of six live rows in `active.yaml` carried `writes: None` at the time.

The 900s window itself is fine — `_lv2_ws_pending` (`:472-490`) enforces it correctly. The bug is
the *scope* of the refusal, not its timing.

## What is in scope and what is not

Two distinct defects share this seam. **This lane owns only the second.**

1. *The writer* does not persist `--writes` into the registry row — filed separately as
   `DISPATCHER-DOES-NOT-PERSIST-WRITES-INTO-THE-REGISTRY-ROW-01` (`e0a3caf252c8`). Do not fix it
   here; it lives in `leadv2-dispatch-code.sh`, which another lane holds.
2. *The gate* treats "write set unknown" as "conflicts with everything". That is this row.

Fixing (1) would hide (2) rather than remove it: as soon as any row fails to record its set for any
reason — a crash between registration and the write, an older row format, a foreign tool — the board
seizes again. The gate must be safe under an unknown set without being useless.

## The design question you must answer, not assume

An unknown write set genuinely *might* overlap. So "just allow it" is wrong, and "refuse everyone"
is what we have. State in the report which of these you chose and why, and name what you rejected:

- refuse only lanes whose declared set intersects the blocker's **working-tree dirt** (the paths it
  is observably touching right now), rather than its undeclared intent;
- refuse only within a much shorter window, and downgrade to a warning after it;
- attribute the unknown row a set derived from its worktree diff at gate time.

Whatever you pick, this property must hold and must be the thing your first control proves:
**a lane whose declared set is disjoint from everything observable is admitted.** And this one must
also hold: **a lane whose declared set genuinely overlaps a live holder is still refused.** A gate
that stops refusing is not a fix.

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
- Do not touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — another lane holds it.
- Do not remove the 900s window or `_lv2_ws_live_worker`. A dead holder must keep being ignored.

## Controls

Two independent claims, two negative controls, each RUN, both outputs pasted:

1. disjoint lane admitted → revert your change and confirm the refusal returns;
2. overlapping lane still refused → mutate the overlap check inside the function body and confirm
   the suite goes red.

Apply each mutation **inside the function body in the lane worktree**, never a scratch copy — this
family was measured to behave differently in a detached worktree at the same commit. Assert the
mutation target string is present before running, so a control cannot rot into a permanent green.

## Deliverable

`docs/handoff/WRITESET-GATE-BLOCKS-THE-BOARD-ON-A-FOREIGN-LANES-UNDECLARED-WRITE-01/report.md` —
the chosen semantics with the rejected alternatives named, both controls with pasted output, the
suite that now guards `leadv2-active-registry.sh` by name, and how CI selects it on a change to that
file. If no such suite exists, write one; a fix to the board's admission gate that nothing guards is
how this defect returns.
