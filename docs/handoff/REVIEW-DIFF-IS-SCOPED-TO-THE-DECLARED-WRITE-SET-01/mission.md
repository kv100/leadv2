# REVIEW-DIFF-IS-SCOPED-TO-THE-DECLARED-WRITE-SET-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

## The defect, observed

The diff handed to the reviewer is built from the lane's **declared `--writes`**, not from what the
lane actually committed. Any file the lane created outside that set is invisible in the diff, so the
reviewer reports it as missing — and is right to, given what it was shown.

Measured 2026-09-15 on lane `18dfa6f6`. Codex returned `REVIEW_VERDICT=FAIL` with one High:

> Default refresh executable is missing (`leadv2-quota-status.sh:149`) …
> `leadv2-ratelimit-refresh-if-stale.sh` does not exist in the repository

The file was tracked in `HEAD` and present in the index at that moment. **The reviewer judged
honestly what it was given; the diff lied by omission.**

A false High costs a full fix round, exactly like a false green costs a landing. This is not a
cosmetic reviewer complaint — it is the review gate producing a verdict about a repository state
that does not exist.

## Why the obvious fix is not obviously right

"Just diff the lane's commit range" removes this bug and reintroduces a different one that the
declared-set scoping exists to prevent: a lane that also picked up unrelated churn (a sibling
session's writes in a shared tree, generated artifacts, a rebase) hands the reviewer a diff full of
files the lane is not accountable for — and a path-filtered diff is what keeps review focused.

So state in the report which you chose and what you rejected. The property that must hold either
way, and that your first control must prove:

**A file the lane actually committed is visible to the reviewer even when it is outside the declared
write set — and when the two sets differ, the difference is named in the review input rather than
silently resolved.** A reviewer told "these three files were committed but not declared" can judge;
a reviewer shown nothing cannot.

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
- Subject is `plugins/leadv2/scripts/leadv2-review-run.sh` and whatever builds its diff input. Do
  **not** touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` or
  `plugins/leadv2/scripts/leadv2-active-registry.sh` — other lanes hold both.
- Do not change what the write-set admission gate does. Declaring a write set and reviewing a diff
  are two different jobs that happen to read the same field.

## Controls

Two independent claims, two negative controls, each RUN, both outputs pasted:

1. an undeclared-but-committed file reaches the reviewer → revert your change and confirm it
   disappears from the diff again;
2. the diff is still scoped — unrelated churn the lane did not commit does **not** appear. Mutate
   the scoping so everything leaks in, and confirm the suite goes red.

Apply each mutation inside the function body **in the lane worktree**, never a scratch copy. Assert
the mutation target string is present before running, so the control cannot rot into a permanent
green against text that no longer exists.

## Deliverable

`docs/handoff/REVIEW-DIFF-IS-SCOPED-TO-THE-DECLARED-WRITE-SET-01/report.md` — the chosen diff
source with the rejected alternative named, both controls with pasted output, the suite that now
guards `leadv2-review-run.sh` by name and how CI selects it on a change to that file, and a
re-run of the `18dfa6f6` shape showing the false High does not reproduce. If no suite guards this
file today, write one: a review gate that can invent a High about a file that exists is how this
returns.
