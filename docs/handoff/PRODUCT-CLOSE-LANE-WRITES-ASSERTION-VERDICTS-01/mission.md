# PRODUCT-CLOSE-LANE-WRITES-ASSERTION-VERDICTS-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

**This lane covers two filed rows**, because both edit the same suite file and cannot be worked in
parallel without conflicting:

- `PRODUCT-CLOSE-LANE-WRITES-ASSERTION-VERDICTS-01` (`c79462050be4`) — cases C2-b, C3, H5, L11;
- `LANE-WRITES-C1-LAUNCHER-CWD-SUBJECT-TRACE-01` (`29a677e94a6c`) — cases C1 glm / codex / sonnet.

Report on them separately. If only one half is fixed, say so; the other row stays open with its
cause named, and the close will record a partial.

## Half one — C2-b, C3, H5, L11

`plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh`. These four cases fail inside the
**product-close** path, which answers with a generic selfcheck refusal instead of the asserted
lane-writes verdict. The suite asks "what is the lane-writes verdict?" and gets back "selfcheck
refused" — a different answer to a different question, which is why the assertion cannot match.

**Two hypotheses are already dead. Do not re-run them:**

- bare-`mktemp` / `TMPDIR` sensitivity — **tested and falsified**: the same eight failures survived
  an explicit fixture root;
- suite-local repair — falsified for the C1 half (below) and not promising here.

Prior evidence, read it before you start: `docs/handoff/LANE-WRITES-SCOPING-SUITE-RED-ON-MAIN-01/report.md`
on leadv2 main.

The question to answer first, by looking rather than reasoning: **does the product-close path reach
the lane-writes verdict at all, or does the selfcheck refusal short-circuit before it?** Those need
opposite fixes — one is an ordering bug in the production path, the other is a suite asserting
through a door that is legitimately shut. Name the verdict in one sentence before proposing
anything.

## Half two — C1 (glm, codex, sonnet)

The three C1 cases stay red after both suite-local repairs were tried and falsified (an explicit
`/tmp` fixture root, and a real red premise row). The blocker is diagnostic, not behavioural:
**every subject invocation is redirected to `/dev/null`**, so the launcher cwd-recorder path cannot
be traced at all.

Start by removing that redirect locally and **looking at what the launcher actually records**. This
is the same shape that made `test-claim-evidence-gate` an unconfirmed guess in a sibling lane: a
suite that discards its subject's output cannot tell a wrong answer from no answer. If the cause
turns out to differ per arm (glm vs codex vs sonnet), say so and treat them separately — do not
fold three causes into one to make the count tidier.

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
  A case that cannot be fixed honestly stays red and is named as still-red with its cause.
- Do not touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
  `plugins/leadv2/scripts/leadv2-active-registry.sh`, or
  `plugins/leadv2/scripts/leadv2-review-run.sh` — other lanes hold all three.
- Leaving a subject's output redirected to `/dev/null` after you are done is not acceptable even if
  the cases pass: it is the thing that made this row cost two rounds already.

## Controls

The two halves are independent claims, so **two** negative controls minimum, each RUN, both outputs
pasted. For each: mutate the thing you changed, inside the function body, **in the lane worktree**
(never a scratch copy — this family was measured to behave differently in a detached worktree at
the same commit), and confirm exactly the cases you fixed go red again. Assert the mutation target
string is present before running, so a control cannot rot into a permanent green.

## Deliverable

`docs/handoff/PRODUCT-CLOSE-LANE-WRITES-ASSERTION-VERDICTS-01/report.md` — per-half verdict with the
evidence that settled it, before/after case counts with their boundary (pass/fail, ceiling,
platform, commit), both controls with pasted output, and any case left red with its cause stated
precisely enough that nobody repeats the two falsified hypotheses a third time.
