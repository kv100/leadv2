# REVIEW-GATE-IS-MUTE-01 — report

Premise confirmed at step 0, before any edit, and it is worse than the row said.
The gate does not merely stay quiet about what it could not check — **it asserts
the opposite.**

All work was done in a pinned scratch tree at `27f3bd83`, never in the live
checkout: wave B1's merge is still open there and `leadv2-review-run.sh` is one
of the files it touches.

---

## Step 0 — a live refusal, and what it actually printed

Real engine, real fixture repo, two arms launched. One returned a clean
`REVIEW_VERDICT: PASS`. The other returned a substantial body — well over the
review floor — with no parsable verdict anywhere in it. The gate wrote:

```
arms: codex,glm
fanout: 2/2 degraded=false launched=2 pool_ok=2 source=pool reason=none
status: pass
reviewer: codex
```

and the decision line:

```
review_gate task=MUTE status=pass diff=bcbc12a6 arms=codex,glm
```

Read what that says. `arms: codex,glm` — as though both contributed.
`degraded=false`, `reason=none` — an explicit claim that nothing was missing.
And **not one word** about glm, whose opinion the gate never established. A lane
merges on one reviewer while its own record says it had two.

This is not the phase gate's disease (naming the missing set in installments)
and not the arbiter's (collapsing unknown into the forbidding answer). It is the
third variant, and the worst-shaped of the three: **unknown collapsed into the
permissive answer, then stated as a positive fact.** `degraded=false` is not a
gap in the output. It is an active lie about a check that never happened.

### What was already fixed, and by whom

Worth saying plainly, because the row asked whether neighbours had closed it:
the **all-arms-unreadable** half was already correct. `REVIEW-ARM-FAILCLOSED-02`
made a fan-out where no arm produces a verdict exit 6 with
`status: blocked`, a named `reason:` and a per-arm `arm_rc:` line. That half
needed nothing from me and I did not touch its policy.

The hole was **partial** unknowledge. One readable arm carried the whole gate
and every unreadable arm beside it vanished at one of three bare `continue`
statements — provider error, body below the floor, unparsable verdict — none of
which recorded anything.

---

## The fix

One production file, `plugins/leadv2/scripts/leadv2-review-run.sh`, +53/−6.

1. **Each skip records why.** The three `continue` points in the verdict loop now
   append `arm=reason` to `_REVIEW_UNREADABLE`: `provider_error_rc<N>`,
   `below_floor`, `unparsable_verdict`.
2. **An unreadable arm degrades the gate.** `degraded` counted arms that
   *launched*; an arm that ran and could not be read is exactly as absent from
   the verdict as one that never started, so a non-empty list forces
   `degraded=true` and adds `arms_unreadable` to the reason.
3. **Every outcome carries an `unreadable:` line — `none` included.** A reader
   must be able to tell "every arm was read" from "we never said". Silence is not
   a value. Both terminal gates print it, both decision lines carry
   `unreadable=`, and the already-correct blocked path now uses the same
   vocabulary.

**What I deliberately did not do.** I did not make an unreadable arm *block*.
That is a policy change with a far larger blast radius than making the state
visible, and it belongs to whoever owns the merge bar, not to this row. The
suite pins that restraint explicitly (case 3): a readable PASS still passes,
rc=0. Naming the third state is the precondition for ever deciding it; deciding
it silently inside a visibility fix would be its own version of this bug.

---

## Two live runs, before and after

The same suite against the same pinned engine, once without the fix and once
with it (`live-runs.log`):

```
BEFORE  pass=1 fail=5
  FAIL 1: no unreadable line — degraded=false launched=2 ... reason=none
  FAIL 2: fanout: 2/2 degraded=false ... reason=none
  PASS 3: a readable PASS still passes
  FAIL 4: review_gate task=MUTE status=pass diff=bcbc12a6 arms=codex,glm
  FAIL 5: gate=[] — no unreadable line even when everything WAS readable
  FAIL 6: rc=6 gate=[status: blocked|reason: empty_response|arm_rc: codex=0,glm=0|]

AFTER   pass=6 fail=0
  unreadable: glm=unparsable_verdict
  fanout: 2/2 degraded=true ... reason=arms_unreadable
  status: pass, rc=0            (verdict unchanged — no silent policy change)
  review_gate ... status=pass ... unreadable=glm=unparsable_verdict
  unreadable: none              (on the fully-readable fan-out)
  rc=6 blocked, now naming the arms in the same vocabulary
```

Case 3 is green in **both** columns. That is the point of including it.

---

## The five requirements

**1. A real function under the claim.** All six cases run the real
`leadv2-review-run.sh` end to end against a real fixture repo. The fake is one
level lower: the reviewer processes. Nothing stubs `parse_review_verdict`,
`review_floor_ok`, the arm loop or the gate writer, and no case inspects a shell
variable — every assertion reads the `review-gate.md` the engine wrote or the
decision line it emitted.

One thing the suite had to learn the hard way, recorded because the next person
will hit it: the codex arm's body is its **stdout**, while the glm arm is invoked
as `<bin> run @mission --out <file>` and writes to the `--out` path. A stub that
only printed left an empty artifact, which the gate classified `below_floor` — a
*different* unreadable reason than the one those cases are about. The suite would
have been green on the wrong mechanism. Both stubs now honour the real calling
convention, and the mute body is deliberately over the 200-byte floor so it
reaches the parse step: a reviewer that answered at length and still said nothing
a gate can act on.

**2. Negative controls — run, by regex, inside a block body**, on a scratch copy
of the pinned tree:

| control | mutation | result |
|---|---|---|
| `REVIEW-GATE-CALLS-A-MUTE-ARM-HEALTHY` | `_rv_unreadable`'s body becomes `:` — nothing is ever recorded | **3 red** — 1, 2, 4. The mutant's output is the measured production output: `degraded=false ... reason=none`, `unreadable=none` |
| `REVIEW-GATE-KNOWS-AND-DOES-NOT-SAY` | `UNREADABLE_LINE` is emptied — the gate keeps the knowledge and prints none of it | **2 red** — 1, 5. Case 2 stays **green**, because `degraded` is still forced |

They are deliberately not interchangeable: the second is the arbiter's exact
shape one layer up — the fact is computed and never reaches the reader — and it
proves the gate *file* is asserted, not just the decision line.

**3. Catalog rows.** `review-gate-calls-a-mute-arm-healthy` and
`review-gate-knows-and-does-not-say`. Counted after the append: **21 entries,
all `expected: killed`.**

**4. CI selection, proven from the PRODUCTION file.** One comment appended to
`leadv2-review-run.sh`, reverted in the same command:

```
CONTROL — clean tree:              4 selected, no review suite
PROOF   — review-run dirty ONLY:  33 selected, including
          test-review-gate-names-the-unreadable.sh
          (+ 20 other review suites, most of which became selectable only
             through this session's other lane, SUITE-SELECTION-COVERS-140-OF-390-01)
```

**5. Suite state, before and after.**

| suite | before | after |
|---|---|---|
| `test-review-gate-shows-findings.sh` | 36 / 6 | **36 / 6** — same six, pre-existing, untouched |
| `test-review-body-persist.sh` | 13 / 0 | 13 / 0 |
| `test-review-gate-names-the-unreadable.sh` | did not exist | **6 / 0** |

The six reds in `test-review-gate-shows-findings.sh` were baselined against a
clean `git archive` of the pin before the patch and are byte-identical after it
(B2 ledger token, and five C1 assertions that expect exit 7 and get 6).

---

## Where this landed, and what is still waiting

Landed once wave B1's merge closed — it had been open for the whole lane, and
`git commit` refuses while a merge stands, so the work waited in the pinned tree
rather than being applied to a checkout somebody else was resolving.

| | |
|---|---|
| `9dd83975` | the fix + `test-review-gate-names-the-unreadable.sh` |
| `363035f4` | this report, the two controls, the live before/after |
| `7365e038` | the two catalog rows (committed with the other lane's catalog change) |

The patch was re-applied to canonical rather than copied from the pin, so its
anchors were re-checked against the post-merge file; the suite is 6/0 there.

Two things I looked at and left alone:

- **Whether an unreadable arm should block.** Named above, not taken.
- **`review_floor_ok`'s 200-byte default.** A reviewer that answers in 150 bytes
  is classified `below_floor` — indistinguishable, in the new vocabulary, from a
  truncated transport. It is now at least *named* rather than silent, which is
  what this row was for, but the two are different failures and someone should
  eventually split them.
