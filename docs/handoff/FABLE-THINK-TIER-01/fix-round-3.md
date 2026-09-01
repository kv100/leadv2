# FABLE-THINK-TIER-01 — fix round 3

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FABLE-THINK-TIER-01`
LANE_WRITES: plugins/leadv2/skills/leadv2-review/ref/architect-escape-mission.md,plugins/leadv2/scripts/tests/test-fable-think-tier.sh,plugins/leadv2/docs/model-effort-matrix.md,plugins/leadv2/docs/phases.md,plugins/leadv2/config/model-capability.yaml,plugins/leadv2/scripts/lib/leadv2-think-model.sh,docs/handoff/FABLE-THINK-TIER-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last `35ca9f2`); run with
`LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST (`git merge main`) so the land is ff-able. Write
report.md ONLY under `docs/handoff/FABLE-THINK-TIER-01/` (round 2 left a stray `report.md` at the
worktree root — delete it). Commit after step 2 and at the end; an uncommitted exit is a failed round.

## Review verdict on round 2 (reviewer glm, `review-glm.md`) — FAIL, high=3
1. **`skills/leadv2-review/ref/architect-escape-mission.md:22`** — the executable template calls
   `leadv2-router.sh` directly, which is not on PATH, and the line continuation `\  # comment` is
   broken, so the whole command is invalid: the architect escape path does not run.
2. **`scripts/tests/test-fable-think-tier.sh:82`** — the census gate can be bypassed: a pin by full
   model id (`model: 'claude-opus-5'`) passes, and any pin whose line contains the word "fallback"
   passes. The reviewer proved both in-session. A gate that a rename defeats is not a gate.
3. **`docs/model-effort-matrix.md:85`** (and `docs/phases.md:145`) — "CLAUDE_CODE_SUBAGENT_MODEL_FORCE
   (CC 2.1.257+) overrides every explicit `model=` pin" is stated as fact with no probe, no doc
   link, no UNVERIFIED tag, and it drives config policy.

## Do
1. Fix the template: call the router via `${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-router.sh` (or the
   `.claude/scripts/lv2` shim, whichever every other skill uses — check and match), fix the
   continuation, and add a suite case that `bash -n` parses the extracted command AND that the
   referenced script path exists.
2. Harden the census gate: match think-role model pins by VALUE class, not by the literal `opus`
   — any `claude-opus-*`, `opus`, `opus[1m]` etc. at a think-role site fails unless it comes from
   the resolver; the word "fallback" on the line is not an exemption (only a resolver call is).
   Add the two bypass shapes the reviewer used as red cases; run them, paste red, then green.
3. PROVE or TAG the SUBAGENT_MODEL_FORCE claim: run one tiny `claude -p` subagent spawn with
   `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=claude-sonnet-5` and an explicit `model: opus` pin, read the
   model id from the resulting stream (`"model":` field). Paste the line. If it overrides → keep
   the statement with `evidence:`; if not → rewrite both docs to what was measured. Same for the
   Max-bucket claim from round 2 if it is still untagged.
4. Mutation negative controls, RUN and paste red: (a) re-insert `model: 'claude-opus-5'` at a
   think-role site → gate red; (b) break the template continuation again → parse case red.
5. "## Round 3 evidence" in `docs/handoff/FABLE-THINK-TIER-01/report.md`; commit.
