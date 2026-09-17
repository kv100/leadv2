# INJECT-DEDUP-ANCHOR-KIND-STRING-MISMATCH-01

Standing rules for this lane: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them
first; they are not repeated here.

## One red suite

`plugins/leadv2/scripts/tests/test-inject-dedup.sh` — exit 1, pass=10 fail=4.

```
FAIL: G5 setup: expected hash-state file not found at
  .../T//leadv2-inject-dedup.oYwcVD/state/.inject-hash.inject-dedup-51563.thread-anchor
```

## The doubled slash is NOT the cause — this was measured

The prior census guessed the `//` in `/var/folders/...T//` was the defect. It is **cosmetic**.
It originates at `plugins/leadv2/scripts/leadv2-temp.sh:22`
(`mktemp -d "${TMPDIR:-/tmp}/${label}.XXXXXX"`, and macOS `TMPDIR` already ends in `/`), both
sides of the comparison derive from the same string, and macOS collapses `//` to a single
separator. Do not spend the lane on it.

## The observed cause

A **kind-string mismatch** in the anchor filename suffix:

- the hook writes only `.inject-hash.<key>.idle-anchor` and `.inject-hash.<key>.task-anchor`
  — `plugins/leadv2/hooks/leadv2-task-anchor.sh:811,1026`;
- the suite expects `.inject-hash.<key>.thread-anchor` — `test-inject-dedup.sh:97`.

Nothing ever writes `thread-anchor`, so the G5 setup assertion can never find its file.

## What to do — decide which side is wrong, do not assume

Re-run the suite and confirm the above. Then establish, from the code that *reads* these files,
which name is the correct one:

- If a third anchor kind `thread-anchor` is supposed to exist and the hook fails to write it,
  that is a **production defect** — fix the hook.
- If `thread-anchor` was renamed away and the suite was never updated, that is a **stale test** —
  fix the test to the real kind, and say plainly in the report that the production behaviour was
  already correct.

Name which of the two it is, with the reader's file:line as your evidence. "The test matched the
code afterwards" is not evidence of either.

## Off limits

- Never make the suite green by deleting an assertion, loosening a grep, or adding `|| true`.
- Do not "fix" the doubled slash in `leadv2-temp.sh` as part of this lane. If you think it is
  worth normalising, say so in the report and it will be filed as its own row — a cosmetic change
  riding along inside a behavioural fix hides which one moved the verdict.

## Control

One claim, one negative control, run, with both outputs pasted. Apply the mutation inside the
function body in the lane worktree — not in a scratch copy. Before running it, assert that the
text you are mutating is actually present, or the control can rot into a permanent green.

## Deliverable

`docs/handoff/INJECT-DEDUP-ANCHOR-KIND-STRING-MISMATCH-01/report.md` — before/after counts with
their boundary (counts, ceiling, platform, commit), the verdict on which side was wrong with the
reader's file:line, and the control with pasted output.
