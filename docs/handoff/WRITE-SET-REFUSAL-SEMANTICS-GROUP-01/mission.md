# WRITE-SET-REFUSAL-SEMANTICS-GROUP-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

**Three filed rows, one lane**, because all three edit `plugins/leadv2/scripts/leadv2-dispatch-code.sh`
and cannot run in parallel. Report on them separately; fixing two of three is a good outcome and is
recorded as one.

- `REPORT-ONLY-GATE-REFUSES-A-FILE-THAT-IS-IN-THE-DECLARED-WRITE-SET-01` (`0e6af6f54cdd`)
- `LANE-WRITE-SET-CANNOT-BE-WIDENED-AFTER-DISPATCH-01` (`fdb2af7017aa`)
- `DISPATCH-REFUSAL-D2-STILL-MISMATCHES-INSIDE-A-FOREIGN-ROOT-01` (`0c47591a2f27`)

The theme: **the write set is compared against reality three times, and each comparison is wrong in
a different way.** Read all three before changing anything; a fix to the comparison helps or breaks
all of them at once.

## Row one — a compliant lane is refused as unscoped

Live reproduction 2026-09-15. Lane `71f133b2` (row `bf0dd16f7c9e`) was dispatched with
`--writes docs/handoff/ROOT-PATH-RESOLUTION-ONE-DEFECT-OR-FOUR-01/report.md` plus
`plugins/leadv2/scripts/tests/probe-root-path-resolution-census.sh`, and `--lane-deliverable
report:<path>`. It committed `f6e64210` touching **exactly those two files and nothing else**. The
gate answered:

```
review_gate status=blocked reason=unscoped_lane_work kind=report terminal=refused
declared=docs/handoff/ROOT-PATH-RESOLUTION-ONE-DEFECT-OR-FOUR-01/report.md
```

Note the `declared=` field lists **one** file where two were declared. That is the thread to pull
first: the refusal may be honest about a set that was already truncated upstream, in which case the
bug is in how `--writes` is parsed or carried when `--lane-deliverable` is also present — not in the
comparison at all.

## Row two — the set cannot be widened once dispatched

`--writes` is fixed at dispatch, so a fix that turns out to need a file nobody anticipated either
escapes the declared set silently or cannot be written at all. Observed 2026-09-15 on lane
`18dfa6f6`: the correct fix required a new script `leadv2-ratelimit-refresh-if-stale.sh` that the
lead's write set did not name. The lane created it anyway — and it then became invisible to the
review diff (that consequence is its own row, `82460942d7df`, held by another lane; do not fix it
here).

This one needs a **design decision**, not a patch. Either an audited widening step that re-checks
the new paths for overlap against live claims, or an explicit refusal that tells the lane to stop
and ask. State which you chose, what you rejected, and why. A silent escape is the one option that
is off the table — it is what produced the false High in the sibling row.

## Row three — one path-spelling case survives inside a foreign root

`test-dispatch-refusal-truth.sh` reads 6/0 from leadv2 main and 6/0 from its own lane worktree after
the round-3 path-resolution fix, but **5/1 when run from an unrelated lane worktree**, failing the
same D2 untracked assertion. That run also emits:

> `WARN: foreign project root detected (env=persona-engine cwd=leadv2/.claude/worktrees/ce3da635)
> -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)`

So the surviving case is reachable only when the surrounding root differs from the env root. The
round-3 acceptance was "main plus one lane tree", which this case passes — which is exactly why the
parent row closed with it still broken. **Reproduce it from a third, unrelated worktree before
theorising**; a fix verified only on main and its own lane repeats the mistake that left it here.

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
- Do **not** touch `plugins/leadv2/scripts/leadv2-active-registry.sh` or
  `plugins/leadv2/scripts/leadv2-review-run.sh` — other lanes hold both.
- No existing refusal may become permissive for a real dispatch.

## Controls

Three independent claims → **three** negative controls, each RUN, all outputs pasted. For row three
the control must run **from a foreign worktree**, not from main: a control run where the case
already passes proves nothing, and that is precisely how this row survived its parent's acceptance.

Apply each mutation inside the function body **in the lane worktree**, never a scratch copy. Assert
the mutation target string is present before running.

## Deliverable

`docs/handoff/WRITE-SET-REFUSAL-SEMANTICS-GROUP-01/report.md` — per-row verdict with the evidence
that settled it, the design decision for row two with its rejected alternative, before/after counts
with their boundary (counts, ceiling, platform, commit, **and which tree the run happened in**),
three controls with pasted output, and any row left open with its cause.
