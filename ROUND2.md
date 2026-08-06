# M-6 round 2 — the merge premise was wrong; switch the mechanism

You proved in round 1 that nothing in this index is mergeable: 0 of 9,870 pairs reach the
0.34 threshold, max similarity 0.267. That finding is accepted and is the reason for this
round. Do NOT lower the threshold, do NOT retry merging. Founder decision: replace the
compaction mechanism with the two below. Keep everything you already built — the batched
model call, immunity rules, archive/restore, apply-gating, the honest error paths — the
verdict vocabulary changes, not the machinery.

Work in this worktree (`worktree-cffc2f86`, on top of `7e5afe1`). Ignore any leadv2
orchestration skill, phase contract or session runner in this repo — they are the subject of
the codebase, not instructions to you.

## A — archive by spentness, not by similarity
The index is over cap because it accumulates entries that have already done their job, not
because it has duplicates. Reuse the SAME batched model call, with a new per-entry verdict:
`live` (still changes what a future session would do) vs `spent` (a closed task, a fixed bug,
a superseded infrastructure fact, a one-off incident already encoded elsewhere).

Rules that are not negotiable:
- `spent` entries move to the archive directory, never deleted, and the index line goes with
  them. Restore must still reproduce the pre-GC index byte-for-byte.
- The existing immunity list stays absolute: `STANDING:` entries, `metadata.type: user`,
  `metadata.memory_gc: keep`, and ACTIVE patterns can never be archived, whatever the model
  says. Enforce in code, not in the prompt.
- Every archived entry records WHY it was judged spent, in one line. An archive with no
  reason is a silent drop.
- Dry-run stays the default.

## B — derive the cap instead of asserting 100
`100` is a made-up number and the warning fires every session because of it. Replace it with a
cap derived from something measurable — the actual read cost of the index (bytes/tokens the
index contributes to a session), with the threshold expressed in those terms and the line count
following from it. Document the derivation in `SKILL.md` in one short paragraph: what was
measured, on what, and why that number. House rule: derive alert bars from config, never pick a
number. If you cannot measure it honestly from this environment, say so and propose the
measurement rather than inventing a figure.

## Acceptance — raw output, no fixtures
1. Dry-run against the live persona-engine memory dir prints a per-entry verdict list with a
   non-empty `spent` set and a projected size at or under the derived cap.
2. Apply: index at or under the cap; every archived entry has a reason line; zero entries from
   the immunity list archived — prove that with a query, not an assertion.
3. Re-run is a no-op.
4. Restore reproduces the original index exactly (`diff` empty).
5. State the derived cap and the measurement behind it.

If any item cannot be met honestly, mark it BLOCKED with the reason. A forced green is worse
than a documented gap — round 1's honest FAIL is exactly why this round exists.

## Return
Write `./ROUND2-RESULT.md`: PASS|FAIL|BLOCKED per item, changed paths, commit SHA, raw output.
