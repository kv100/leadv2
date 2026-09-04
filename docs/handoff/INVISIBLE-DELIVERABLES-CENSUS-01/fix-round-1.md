# INVISIBLE-DELIVERABLES-CENSUS-01 — round 2: C6 passes for free, and the branch it names is undefended

LANE_WRITES: plugins/leadv2/scripts/tests/test-lane-report-address.sh, plugins/leadv2/scripts/lib/leadv2-lane-address.sh, docs/handoff/INVISIBLE-DELIVERABLES-CENSUS-01/

Round 1 is good work and almost all of it stands. Verified by me, not taken from your report:

- suite `test-lane-report-address.sh` — **20 passed, 0 failed, ten consecutive runs**;
- the mandatory control bites: disabling the main-root dispatch-dir scan
  (`lane_address_scan_handoff_root … "main" "$handoff"`) reddens C1 with
  `FAIL C1 rc=1 out=searched:` — the founder-id case fails with an empty searched list, exactly as
  designed. `MUTATION-CONTROL ok`;
- scope is clean: resolver lib, CLI, suite, and the one adopting consumer.

Keep all of it. One gap remains and it is the one this whole lane is about.

## The gap — measured

`plugins/leadv2/scripts/lib/leadv2-lane-address.sh:259-263`:

```
    lane_address_list_deliverables "$dir" ""
    if [[ -n "$LA_UNREADABLE" ]]; then
      LA_RESULT="unknown"
      LA_REASON="$dir exists but listdir failed"
      return 2
    fi
```

Flip that one `unknown` to `none` and **the suite stays green**:

```
sed 's|      LA_RESULT="unknown"|      LA_RESULT="none"|'   ->  MUTATION-CONTROL mutant_survived
```

Flip **every** `unknown` site at once and the suite does go red — but on **C5**, the
"unattributable dirs present" case:

```
sed 's|LA_RESULT="unknown"|LA_RESULT="none"|g'  ->  MUTATION-CONTROL ok, red_line = FAIL C5
```

So C5 defends its own site, and the site at :261 is defended by nothing. Meanwhile the suite carries
`C6 report dir unreadable (chmod 000) -> unknown, not none` — a case named for exactly this branch,
which passes whether or not the branch is correct.

The likely mechanism, which you must confirm rather than assume: `chmod 000` on a directory does not
deny the **owner** a listdir on macOS, so `LA_UNREADABLE` is never set, the fixture never reaches
:261, and C6 asserts on a path that behaves like the ordinary miss. If that is right, C6 is not a
weak assertion — it is an assertion about a condition the fixture never creates.

This matters more here than anywhere else in the lane. "The directory is there but I could not read
it" is the exact case the census exists to keep separate from "there is nothing here". A resolver
that reports `none` when it could not look is the whole disease, shipped inside its own cure.

## Your task

1. Make C6 create the condition it names. If `chmod 000` cannot deny the owner, use something that
   can: an unreadable **parent** directory, a path component replaced by a non-directory, an
   `LA_UNREADABLE`-forcing injection point in the lib, or a fixture that runs the listdir under a
   restricted environment. Pick what you can defend and say why in a comment.
2. Assert the full triple at that branch: `result: unknown`, a reason naming the directory, and
   **exit status 2** — not merely "not none".
3. If, after measurement, the branch turns out to be unreachable in practice, say so with the
   evidence and delete it rather than leaving a dead arm that reads as a guarantee. Deleting it is an
   acceptable outcome; leaving it undefended is not.

## Prove it

- **The single-site control must flip**: `sed 's|      LA_RESULT="unknown"|      LA_RESULT="none"|'`
  (that exact six-space anchor, the :261 site alone) must go from `mutant_survived` to
  `baseline_rc=0` / `mutated_rc=1`, with the literal red line. That flip is this round's deliverable.
- The global control must still bite, and its red line must now name **C6** or both cases, not C5
  alone.
- Suite green, **ten consecutive runs**, all ten count lines pasted.
- A mutant that reddens the suite by crashing it is not a control; a stack trace instead of a failed
  assertion means the anchor is wrong.

## Constraints

- Do not weaken C1-C5 or C7-C12, and do not touch the resolver's behaviour beyond what point 1 or 3
  requires.
- Do not touch `tests/run-all.sh` (its three `EXTRA_SUITE_MAP` rows are the lead's to land),
  `tests/known-red-suites.txt`, `main`, or `docs/leadv2/`.
- Never `reset --hard`, `clean`, `stash`, or `worktree prune` — the tree is shared and other lanes
  are live.
- Commit incrementally, not at the end: the e2e gate times out at 900s and kills workers on the
  threshold between finished and committed. Your round-1 report survived only because an auto-commit
  caught it.
- If any instruction here rests on a false premise, stop and say so with the measurement.
- Do not merge to main. Leave the branch green with a report.

## Report

The two control results with their pairs and red lines, the ten count lines, and the commit shas.
Nothing else.
