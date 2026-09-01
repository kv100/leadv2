# PROMISE-GUARD-TURN-IT-ON-01 — fix round 4 (judge verdict REVISE, confidence 0.8)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-TURN-IT-ON-01`
LANE_WRITES: plugins/leadv2/hooks/leadv2-promise-guard.sh,plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh,plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh,docs/handoff/PROMISE-GUARD-TURN-IT-ON-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last `5ac858f`); run with `LEADV2_SUITE_LOCK_DISABLE=1`.

Judge (Fable) verdict: `docs/handoff/PROMISE-GUARD-TURN-IT-ON-01/judge-verdict.md`. Round 3's goal is
met: all three suites FALSIFIABLE, mutation control red. One HIGH blocks the land:

- **HIGH `hooks/leadv2-promise-guard.sh:~362-366`** — the write-kind regex additions `чин\w*` and
  `обнов\w*` are unanchored substrings. The judge probed the hook's own regex with
  "Сейчас посмотрю, в чём причина" and it classified as a WRITE promise → with blocking now ON by
  default, a plain sentence about looking at a cause gets blocked. This is the false-positive shape the
  GO-condition in scheduled-decisions.md exists to prevent.

## Do
1. Anchor every verb stem added in this lane as a word start (`\bчин\w*`, `\bобнов\w*` or the
   equivalent the hook's regex engine supports — check whether it is `grep -E`, `grep -P` or bash
   `=~`, and use the anchoring that actually works there; prove it with the judge's probe sentence).
   Add negative cases to `test-promise-guard-morphology.sh`: "в чём причина", "обновление пришло",
   "починка была вчера" → SILENT; positive: "чиню конфиг", "сейчас обновлю yaml" → FIRED/blocked.
2. Fix the false claim in report.md ("leadv2-suite-falsifiable.sh does not exist in this repo" — it is on
   main, blob 4fccc4a; the lane branch is simply behind). Merge main into the lane (`git merge main`)
   so the runner is present, then re-run the three falsifiability checks and paste the verdict lines.
3. Mutation negative control, RUN and paste red: remove the `\b` anchor again → the new negative
   cases red. Revert.
4. Append "## Round 4 evidence" to report.md; commit.
