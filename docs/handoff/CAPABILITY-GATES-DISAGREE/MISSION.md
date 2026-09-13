# CAPABILITY-GATES-DISAGREE-AND-THE-JOURNAL-CANNOT-SEE-IT-01

## The number

**11 of 64 spawn attempts were refused with `arm_not_capable_for_kind` — 17%.**

```
$ ls /var/folders/.../T/leadv2-dispatch-spawn-*.stderr.log | wc -l      → 64
$ grep -l "arm_not_capable_for_kind" .../leadv2-dispatch-spawn-*.stderr.log | wc -l → 11
$ grep -h "refused:" .../leadv2-dispatch-spawn-*.stderr.log | sort | uniq -c
     11 refused: arm_not_capable_for_kind
```

Each one is a wasted arbiter selection and a silent re-roll down the ladder. One of them is
reproducible from today's own journal: the arbiter picked sonnet for `--kind plugin`
(`arm_resolved … reason=integration_critical_4subsystems`, `arbiter_pick=sonnet`), the launcher
refused it, and the lane ran on codex instead.

## Why a previous lane reported zero

Row `e6de9ea2a20a` measured this and returned:

```text
arm_not_capable_for_kind=0
kind_unmapped=0
paired-disagreement=0
```

Its number is correct **for the surface it read** — the event journal — and wrong for the question,
because the launcher writes this refusal to a per-spawn stderr file
(`$TMPDIR/leadv2-dispatch-spawn-<sig8>.stderr.log`) and nothing copies it into the journal. The
dispatcher even prints the path (`ERROR: spawn(<arm>) full launcher stderr preserved at …`), so the
fact is not hidden — it is merely unjoinable to every counting surface we have.

**That is the primary defect, and it is bigger than this one refusal:** a launcher refusal is
invisible to the journal, so no census, no replay and no dashboard can ever count one. Fix the
blindness first; the capability question is second.

## What to build

### 1. A launcher refusal becomes a journal event

Every `refused: <reason>` the launcher writes to its stderr file must also be emitted as a decision
event carrying the sig8, the arm, the reason, and the arm the ladder fell through to. Then this
class is countable by the same tools that count everything else.

- Do not parse the stderr file after the fact if the dispatcher can emit at the refusal site —
  a log-scraper is a second source of truth that will drift. If after-the-fact parsing is the only
  seam available, say why, and make the parse total (an unrecognised `refused:` line must still
  produce an event with `reason=unclassified`, never be dropped).
- Backfill is optional and must be clearly marked as backfill if you do it. Do not rewrite history
  silently.

### 2. Then count, then decide

With the events flowing, count the real rate over a window and report it. Only then answer the
design question:

- `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:1918` computes `_fit_order` from kind/size
  BEFORE the economic sort — the arbiter already has a notion of capability.
- The launcher has a second, different notion, and `e6de9ea2a20a` found that the launcher seam
  coerces a kind absent from the capability matrix to `code`.

So: do the two notions disagree because of the coercion, or for another reason? Name the mechanism
with the code path, then pick ONE:
- make the arbiter's `_fit` know what the launcher will refuse (preferred — one notion of capable), or
- keep two gates and justify why, with the measured cost of the re-rolls.

**Do not add a second capability matrix.** Both prior lanes independently reached that conclusion
and both were right about it.

### 3. The e2e rung timed out on the sibling lane

`dispatch_terminal task=4e2676a0 terminal=parked cause=e2e_timeout` — the decision-record lane
parked on an e2e timeout although its work was complete and green. Note whether the same rung will
time out for you, and if it does, report it rather than letting `parked` read as failure.

## Method — binding

- **A count is a claim about a surface.** Before reporting any frequency, say which surface you read
  and prove that surface is where the fact is written. This lane exists because that step was skipped.
- Every change gets a negative control: mutate inside the function body in a scratch worktree, show
  the suite goes red, restore. Strip comments when grepping.
- Re-check what looks obviously true, in both directions. Two lanes today reported a confident zero
  that was an artefact of the surface, and one reported a confident critical that was an artefact of
  reading only the diff.

## Acceptance

1. A launcher refusal produces a journal event — demonstrated on a real refusal, not a fixture.
2. The measured rate over a stated window, with the surface named.
3. A stated decision on the two gates, with its mechanism and code path.
4. Still green: `test-arbiter-decision-record-inputs.sh`, `test-reset-urgency.sh`,
   `test-leadv2-task-judge.sh`, `test-arbiter-prices-by-provider.sh`.
5. New suites registered so `tests/run-all.sh --scope changed` SELECTS them; commit first, then
   show the selection output.

## Off limits

- `reset_urgency`, `provider_cost`, the decision record's schema v2, the judge's arm default
  (haiku, set by measurement today) — all landed, none of them yours to revise.
- Any hardcoded arm exclusion.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
