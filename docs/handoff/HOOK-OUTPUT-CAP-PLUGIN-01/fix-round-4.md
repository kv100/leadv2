# HOOK-OUTPUT-CAP-PLUGIN-01 — round 4: the range fix works but grows without bound

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/HOOK-OUTPUT-CAP-PLUGIN-01`

LANE_WRITES: plugins/leadv2/hooks/leadv2-one-copy-drift.sh,plugins/leadv2/hooks/leadv2-truth-card-inject.sh,plugins/leadv2/scripts/tests/test-hook-output-cap.sh,tests/run-all.sh,docs/handoff/HOOK-OUTPUT-CAP-PLUGIN-01/

Full report: `docs/handoff/HOOK-OUTPUT-CAP-PLUGIN-01/review-r3.md`. HEAD is `bd63187`.

**The byte win and the loudness fix are done and confirmed three times over — do not touch them.**
Drift hook 45,705 B → 277 B, truth-card 7,758 B → ~243 B, caps on the real harness path,
`hooks.json` untouched, crash-shaped checker failures no longer swallowed with a mutation-proven
control, bash 3.2.57 clean. Round 3's merge-base anchor also genuinely fixed the original
selection failure: with a docs-only HEAD and unrelated dirt, `test-hook-output-cap.sh` IS now
selected. That half is right.

## [High] the merge-base range re-selects settled suites forever

Reproduced live: on a **clean HEAD** with a single unrelated dirty file (`leadv2-lane-shape.sh`),
selection was `test-leadv2-lane-shape.sh` **plus** `test-hook-output-cap.sh`. The range
`5d1a5d7..bd63187` — six files of this lane's own already-committed, already-tested work — is
unioned into "changed" on every subsequent run regardless of what is newly dirty.

It is not literally `--scope all`, but it grows monotonically with lane length: every already-tested
suite re-runs on every future unrelated commit for the branch's whole life. On this five-commit lane
it looks harmless; on a thirty-commit lane it is a different tool.

`tests/run-all.sh` is shared by every lane in this repo, so this lands on everyone.

Pick one and say which:

- diff only the commits new since the last CI run on this branch (persist the last-checked SHA), or
- intersect the committed range with the actual working-tree `git diff --name-only HEAD` instead of
  always unioning it.

Then prove BOTH properties in one run, because they pull against each other:

1. a docs-only HEAD with unrelated dirt still selects `test-hook-output-cap.sh` (round 3's win must
   survive), and
2. a clean HEAD with one unrelated dirty file selects **only** that file's own suite.

Both pasted, from a scratch clone. And a control: mutate the bounding logic out and show property 2
breaks.

## [Low] `/tmp/leadv2-core-offline.lock` may never expire

Real `--scope changed` runs hang past two minutes in scratch clones, blocked on that lock held by a
concurrent run; `run-core-offline.sh` is queued unconditionally before the scope branch. A
permanently orphaned lock makes `--scope changed` hang forever in CI. Verify the lock self-expires;
if it does not, say so in `report.md` with the file:line — do not fix it here, it is outside this
write set.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN. A zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image.
- Do not reorder, add or remove entries in `hooks.json`; it is not in LANE_WRITES.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- Write `fix-round-4` artifacts into the lane and commit them with `git add -f <file>`; do not edit
  `.gitignore`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Done means

Both selection properties proven in one pasted run from a scratch clone, a control that breaks
property 2 when the bounding logic is reverted, and a `report.md` line on whether the offline lock
self-expires.
