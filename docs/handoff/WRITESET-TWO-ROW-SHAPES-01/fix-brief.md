# Fix brief — two row shapes per task carry different write-set truth

Consumes the F4 composition review
(`docs/handoff/CONTROL-PLANE-REVIEW-01/f4-composition.md`). **Do not re-derive** the
call chain below; it is measured with file:line. This brief exists so the fix is
ready to dispatch the moment a lane slot frees — see ledger row
`SD-DISPATCH-WRITESET-TWO-ROW-FIX-01`.

## Which board row this serves

No new row. The class is on the board four times already:
`f9fe3e2b2caf` WRITESET-PENDING-BLOCKS-WITHOUT-ANY-OVERLAP-01 (P0, names
`active-registry.sh:418` and the policy), `46902ae71c51` WRITESET-UNKNOWN-BEATS-DECLARED-01
(names the root cause: "the registry permits several rows per lane while every reader
is written as if there were one"), `81a511b3003c` DISPATCH-WRITES-FLAG-DOES-NOT-REACH-THE-LANE-REGISTRY-01,
`7c2f9e8d54cb` LANE_WRITES-HARVEST-DID-NOT-RUN. Dispatch **`f9fe3e2b2caf`** and carry
this brief; it is the most concrete and already P0.

## The composed failure — every component is individually correct

1. `leadv2-dispatch-code.sh:8874-8899` registers the task BEFORE prepass resolves its
   scope, with `writes_reason=prepass_pending`. Correct: there is no candidate set yet.
2. Prepass resolves the declaration and `leadv2-dispatch-code.sh:9060-9091` copies it into
   `lane_writes`, persisted by the second register at `:9125-9166`. Correct — but the
   correctness is local to **row A**.
3. `leadv2-session-runner.sh:191-205` calls `lane_adopt_pid`; `lib/leadv2-lane-state.sh:146-183`
   finds no reusable non-dead row and appends **row B** with no `writes`/`writes_reason`
   field at all. `lib/leadv2-lane-state.sh:415-417` then transitions row B.
4. An unrelated single-file lane arrives. `leadv2-active-registry.sh:545-563` sees row Bs
   missing scope, `_lv2_ws_pending` measures first-registration age at `:464-483`, and
   `_lv2_ws_live_worker` fails closed for a live non-interactive worker at `:425-462`.
   Correct in isolation: a live worker with unknown scope might write anywhere.
5. `leadv2-dispatch-code.sh:4257-4312` renders `dispatch_refused reason=writeset_pending`
   with `blocked_by`, `blocked_writes_reason=undeclared`, `window_s=900`. Correct.

**The defect is none of the five. It is that the system permits two same-task row shapes
with different write-set truth**, and the collision checker reads the shape that lost the
declaration.

## Smallest safe change (F4s, keep it small)

Refuse before the append at `lib/leadv2-lane-state.sh:178-183` when there is no reusable
same-task row AND no write set available, and stop swallowing that refusal at
`leadv2-session-runner.sh:203-205`. A runner whose original row is gone then gets a
non-zero adoption refusal instead of silently creating an unknown-scope live blocker.

## Do NOT do this (F4 is explicit)

Do **not** blanket-reject every empty registration at `leadv2-active-registry.sh:534-535`.
The dispatcher deliberately needs the `prepass_pending` state (`:8874-8899`), and report
lanes are legitimately write-less under the report-deliverable contract. Forbidding every
unknown row is a LARGER change: delay active registration until after prepass
(`:9125-9166`), or add a reservation state the collision checker does not treat as a live
undeclared owner. Do not start there.

## Second propagation gap, same class (fix or file, do not ignore)

`leadv2-fanout.sh:980-982` registers the headless lane without writes; the later stamp at
`:1313-1319` reads only the optional `tasks.yaml` contract from `:1351-1387` and suppresses
`set_writes` failure with `|| true`. A declaration living in a handoff brief with no matching
`tasks.yaml` row leaves the row write-less and nothing refuses the launch.

## Negative control the suite must carry

Both directions, per `f9fe3e2b2caf`: an orphan row with no writes must **NOT** block; a row
with a declared set must block only on a REAL path intersection. A suite that only proves
the refusal fires is the false-green shape we keep paying for.
