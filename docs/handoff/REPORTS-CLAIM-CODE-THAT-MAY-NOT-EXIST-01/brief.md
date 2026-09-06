# REPORTS-CLAIM-CODE-THAT-MAY-NOT-EXIST-01 — adjudication lane

Repo: ~/Projects/leadv2 (SHARED TREE — never `git add -A`, never `reset --hard`, never `clean`,
never `stash`, never push to origin.) **Read-mostly.** The deliverable is a verdict per row plus, at
most, backlog rows. Do not fix what you find; a fix mixed into an audit makes the audit unreviewable.

**COMMIT AFTER EVERY STEP** — one commit per adjudicated row, so a death costs one row and not five.

## Why this lane exists

On 2026-09-04 a worker wrote a full "implemented" report for `CLASS-IS-COMPUTED`. The code was never
committed and does not exist. The report survived, the code did not, and the row has read as
delivered ever since. That is the single most expensive failure shape in this project: **a committed
report is not evidence that code landed.**

Five rows in `docs/WAVES.md` are marked `[отчёт-разобрать]` — a report exists and nobody has checked
it. Adjudicate all five.

## The five rows

1. `CLASS-IS-COMPUTED-NOT-DECLARED-01` — the known-bad one above. Start here; it calibrates you.
2. `D2-SINGLE-LIVENESS-VERDICT`
3. `MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01`
4. `W1-LAND-STRANDED-8F14220D`
5. `dispatch-6436a2e2`

## The method, and it is the whole point

For each row, the verdict must rest on the CODE, never on the report's own words.

1. Find the report. Extract every claim it makes in the form "X now does Y".
2. For each claim, **grep for one named symbol the change would have created** — a function name, a
   variable, a marker string. Matching the task id proves nothing: task ids appear in commit
   messages, briefs and journals of work that never landed.
3. Establish whether it is in `main`, on a branch only, or nowhere. Note that
   `git diff main..B` (two dots, tip vs tip) reveals work superseded by a sibling, while
   `main...B` (three dots, from merge-base) hides it and makes a landed branch look unlanded.
   Ancestry, patch-id (`git cherry`) and blob history all MISS a landing that was reworded on the
   way in — a main commit whose subject carries the lane id is a fourth signal worth checking.
4. Verdict, one of: **landed** (name the commit) / **on a branch, unlanded** (name the branch and
   whether it is mergeable) / **claimed but absent** (the 09-04 shape) / **superseded** (name what
   replaced it) / **moot** (the premise is no longer true — say why).

Anti-false-zero discipline, which cost this project seventeen wrong answers in one night:

- `rc=0` means nothing; `rc=$?` after a pipe reads the LAST stage's status.
- Never let `head` truncate a listing you are about to call complete. Capture to a file and grep it.
- Quote glob pathspecs. Unquoted, zsh expands `refs/heads/worktree-*` against the filesystem and a
  census silently reports zero branches.
- `git branch` prefixes a worktree-checked-out branch with `+`; stripping only spaces and `*` leaves
  the `+` and every subsequent lookup misses.
- **Derive every zero a second way before believing it.** A confident empty answer is the failure
  mode here, not a wrong answer.

## Deliverable

`docs/handoff/REPORTS-CLAIM-CODE-THAT-MAY-NOT-EXIST-01/report.md`, under 110 lines: a table of the
five rows with verdict, the evidence command for each, and the named symbol you grepped. Then, for
any row whose verdict is **claimed but absent** or **on a branch, unlanded**, a one-paragraph
statement of what remains to be done — enough for a follow-up lane to start from, no more.

File a backlog row for anything you find that is not one of the five. Do not chase it.
