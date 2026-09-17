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

## ROUND 2 — read this before anything else

Round 1 (lane `c5db1e4e`, 2026-09-17) was **killed by review** with `critical=1 high=2`, and the
findings were correct and measured. Do not repeat that attempt. The full review is at
`docs/handoff/dispatch-c5db1e4e-review/critic.full.md`; the three that bind you:

- **C1 (measured, not argued).** The reviewer exported the plugin at `0c033894` into two scratch
  trees, applied the diff to one, and ran the five suites that pin the `pending_resolution`
  contract: **5/5 green on base, 5/5 red with the diff** —
  `test-writeset-pending-overlap`, `test-writeset-refusal-names-blocker`,
  `test-lane-adopt-writeset-refusal`, `test-writeset-admission-block`, `test-writeset-carousel`.
  Every failure is one shape: a live write-less incumbent whose worktree has no dirt is now admitted
  `rc=0` where the suites pin `rc=5`. Worse, in `refusal-names-blocker` case 3 the dispatch-side
  refusal degrades to `reason=writeset_conflict` because the parser at
  `leadv2-dispatch-code.sh:4513` finds no `writeset conflict: other=` line — so the two refusal
  kinds that suite exists to *distinguish* become indistinguishable. **Whatever you change, those
  five suites are part of the contract: either they stay green, or they are updated in the same diff
  to pin the new contract deliberately, with the reasoning stated.**

- **H1 — and this one invalidates the option the original mission suggested.** "Refuse only on
  overlap with the incumbent's working-tree dirt" **reopens the TOCTOU that the unconditional
  refusal exists to close**. Dirt measures what the incumbent has *already touched*, which during
  the guarded window is by construction **nothing**: a row mid architect-prepass has a fresh
  checkout, so dirt is `[]`, the candidate registers `rc=0` under the default
  `LEADV2_WRITESET_ENFORCE=warn` (`:545`), and moments later the incumbent's prepass calls
  `set_writes` with an overlapping set. `set_writes` "makes no liveness/collision judgement itself"
  (its own comment, `:1050-1056`) — so you end with two live lanes holding intersecting declared
  sets and no refusal on either side. **Dirt alone is not admissible evidence.** If you use it, the
  other side of the window must close too: `set_writes` (or its dispatch-code call site) has to run
  the same intersection against every non-stale, non-dead row and exit 5 when a late-declared set
  collides — second declarer loses — with a test that registers A (pending, live pid, no writes),
  registers B with `x/a`, then `set_writes A x/a` and asserts `rc=5`.

- **H2.** When the pending row's recorded `worktree` is the **shared main checkout**, the lead's own
  dirt is attributed to the incumbent, producing false refusals on unrelated paths. This is not
  hypothetical: it is exactly the 2026-09-16 incident where a foreign live session's pulse artifacts
  in a shared tree serialised the board.

## The design question you must answer, not assume

An unknown write set genuinely *might* overlap. So "just allow it" is wrong, and "refuse everyone"
is what we have. State in the report which of these you chose and why, and name what you rejected:

- refuse only within a much shorter window, and downgrade to a warning after it;
- attribute the unknown row a set derived from its worktree diff at gate time — subject to H2:
  a row whose worktree *is* the shared checkout must not inherit that tree's dirt;
- dirt-overlap **plus** a symmetric late-declaration check in `set_writes`, per H1. If you take this
  one, the `set_writes` half is not optional and is not a follow-up row.

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

**A third check, non-negotiable after round 1:** before you report, run all five contract suites
(`test-writeset-pending-overlap`, `test-writeset-refusal-names-blocker`,
`test-lane-adopt-writeset-refusal`, `test-writeset-admission-block`, `test-writeset-carousel`)
against your diff and paste the rc of each. Round 1 broke all five and shipped no test of its own;
a diff that does that again is refused on sight.

## Deliverable

`docs/handoff/WRITESET-GATE-BLOCKS-THE-BOARD-ON-A-FOREIGN-LANES-UNDECLARED-WRITE-01/report.md` —
the chosen semantics with the rejected alternatives named, both controls with pasted output, the
suite that now guards `leadv2-active-registry.sh` by name, and how CI selects it on a change to that
file. If no such suite exists, write one; a fix to the board's admission gate that nothing guards is
how this defect returns.
