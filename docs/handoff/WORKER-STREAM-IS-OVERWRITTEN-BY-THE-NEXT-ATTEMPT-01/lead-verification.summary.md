---
verdict: APPROVE
next_action: continue
---

# WORKER-STREAM-IS-OVERWRITTEN-BY-THE-NEXT-ATTEMPT-01 — lead verification

Verified by the lead by running it, not by reading the worker's report. 2026-09-04.
`next_action: continue` = the branch is ready to merge, and merging is the other lead's call.

## Verdict: the branch is green and the defect is closed. Not merged.

The lane was **parked by the e2e gate**, not by its own work:

```
e2e_gate task=ab933592 status=ran verdict=timeout rc=124 timeout_s=900
dispatch_terminal task=ab933592 terminal=parked cause=e2e_timeout
```

The fix, the suite, the five controls and the report were all written before the gate killed it.
This is `E2E-GATE-RUNS-THE-WHOLE-REPO-AND-CANNOT-FINISH-01` costing a lane a clean close.

## Ten consecutive runs — the worker reported one, the lead ran ten

```
run1  rc=0   run2  rc=0   run3  rc=0   run4  rc=0   run5  rc=0
run6  rc=0   run7  rc=0   run8  rc=0   run9  rc=0   run10 rc=0
```
Final restored run: `test-stream-attempt-isolation: 22 passed, 0 failed`.

## The lead's own control, on the branch the worker's controls did NOT reach

The worker's control #2 mutated the repoint call and reddened on
`A2: flat newest-pointer is a symlink` — the consequence of no symlink existing at all. That proves
the pointer is *created*; it says nothing about **where it points**, which is the whole purpose of
repointing on every attempt.

Single-site mutation, inside the body, at `claude-subsession.sh:457` — repoint only when no pointer
exists yet, so attempt #2 leaves the pointer at attempt #1:

```
  tmp_link="${link_name}.repoint.$$"; [[ -L "${link_name}" ]] && return 0
```

Result, by the strict criterion (every earlier assertion green, the named one the only red):

```
mutated_rc=1
red count: 1
[TEST] FAIL: A1: pointer resolves to attempt #2 (newest), not #1
        (got: …/attempts/1788499831-15656/developer.stream.jsonl)
21 passed, 1 failed
RESTORED ok   restored_rc=0   22 passed, 0 failed
```

Exactly one red, and it is the named branch. **The pointer-target branch is defended.**

## Round 1 of this verification was INVALID and is retracted

The first attempt inserted the guard with `perl -0pi -e 's/…/$1  [[ -L "$link_name" ]] && …/'`.
Perl interpolated `$link_name` as its own undefined variable, so the inserted line read
`[[ -L "" ]] && return 0` and never fired. `shasum` showed the file changed; the suite stayed green;
that reads exactly like "the branch is undefended".

**"The mutant differs" is necessary and not sufficient.** A mutation can differ byte-for-byte and be
inert. The fix is to read the mutated line back and confirm it says what it was meant to say — which
round 2 does, and which is now part of the acceptance for every control.

## Control-by-control: does each redden on the assertion its name claims?

| # | mutation | red line | on its named branch? |
|---|---|---|---|
| 1 | `_lv2_attempt_id` → constant | `A1: setup self-check — fake claude ran twice (2 attempt dirs, got 1)` | yes — one dir instead of two is the direct consequence |
| 2 | repoint no-op | `A2: flat newest-pointer is a symlink` | partly — proves creation, not target; **the lead's control above covers the target** |
| 3 | `MARKER_FILE` → flat | `A3: TWO pending-cost markers coexist (attempt#1 not overwritten)` | yes |
| 4 | budget-check `attempts/` walk disabled | `B1: fallback sums ALL attempts exactly (spent: 160)` | yes |
| 5 | flat `STREAM_OUT`, no repoint (mandatory e2e) | `A2: exactly one attempt dir exists (got 0)` | **no — reddens on the dir count, earlier than its name** |

**4 of 5 redden on the assertion their name claims** (counting #2 as covered only because the lead
added the missing target control).

## `A1: two attempts' streams DIFFER` is not independently falsifiable — and that is not a defect

Control #5's name claims both attempts' streams exist **and differ**. No product mutation can redden
the differ-assertion without reddening an earlier one first: if the attempt directories are distinct,
the two streams differ by construction (the fake `claude` embeds its own pid and timestamp); if they
are not distinct, the dir-count or file-exists assertion fails first. The assertion is implied by its
predecessors rather than undefended. Reported here so a later reader does not mistake "no control
flips it" for "the branch is naked".

## One defect shipped inside the cure

`_lv2_repoint_newest_pointer` (`claude-subsession.sh:463-464`) warns to stderr on its failure path
and then `return 0`. The warning is real — unlike the three instances in
`STATE-LAYER-CANNOT-SAY-IT-FAILED-01`, this path does say something out loud — but the caller still
cannot act on it. Recorded, not fixed here; it belongs to that census.
