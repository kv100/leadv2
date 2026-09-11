# CONTROL-PLANE-REVIEW-01 / M4 — the dispatcher, and whether the four compose

READ FIRST: `docs/handoff/CONTROL-PLANE-REVIEW-01/seed-facts.md`. Facts S3, S5,
S6 are yours.

Repo: `leadv2`. **READ-ONLY review.** Your only write target is
`docs/handoff/CONTROL-PLANE-REVIEW-01/f4-composition.md`.

## Subject

`plugins/leadv2/scripts/leadv2-dispatch-code.sh` — specifically the seam where
it consumes the arbiter's decision, the balancer's profile pick, and the judge's
verdict. Plus `leadv2-active-registry.sh` where the dispatcher registers a lane.

## The founder's actual ask

"чтобы все они были умными и работали **вместе**". Three components can each be
correct in isolation and still compose into a wrong outcome. A standing lesson
from this repo, measured: *a guard verified in isolation is not verified in
composition* — the negative control was honest while the input was substituted,
and 265 lines went through.

So the question is not "is the dispatcher correct" but **does a decision survive
the handoff?**

With `file:line` for each:

1. **Arbiter → dispatcher.** The consult returns
   `arm=… model=… tier=… effort=… chain=…`. Which of those fields does the
   dispatcher actually USE, and which does it recompute or ignore? A field the
   arbiter sets and the dispatcher overrides is the finding. S3 gives you a real
   decision line to trace.

2. **Balancer → worker.** Does the profile the balancer picked reach the spawned
   worker's environment, or can the worker inherit a different account? Today's
   measured failure, worth checking against: four prepass runs died `rc=124`
   because the selector had chosen an exhausted credential while the other
   account was free, and `rc=124` was then reclassified to `timeout`, which the
   fallback allowlist excludes — so a quota failure wore a timeout's name and
   got no fallback. Confirm whether that path is now closed or still open.

3. **The blind registry.** S6: every `active.yaml` reported 0 lanes while a real
   codex lane had been alive 25 minutes. Find where the dispatcher writes the
   lane record and why the write does not land. Then say what breaks downstream:
   the lane cap, the write-set collision check, or both. Note `LEADV2_LANE_CAP`
   is read from `~/.claude/settings.json` — do not edit that file.

4. **Judge → deploy.** Does a no-go verdict actually stop the deploy step, or is
   the merge reachable without it? Check whether a hand `git merge` bypasses the
   close gate — a measured fact from this session is that the lead's own
   hand-merges produced no `dispatch_terminal` event at all.

5. **The composite failure.** Name ONE concrete sequence in which all four
   components behave exactly as written and the outcome is still wrong. One is
   enough; make it specific enough to reproduce.

## Rules

- Every finding: `file:line`, mechanism in one sentence, concrete failure
  scenario.
- Something you checked and found SOUND is a finding — say so with the line.
- `leadv2-active-registry.sh` is a LIBRARY, not a CLI: running
  `bash <script> list` exits 0 silently and proves nothing. Source it.
- Do not dispatch anything. Do not write to `~/.claude/leadv2-state/`.
- Do not `git stash`, `reset --hard`, `clean`, or `worktree prune` — standing
  prohibition in shared trees.
