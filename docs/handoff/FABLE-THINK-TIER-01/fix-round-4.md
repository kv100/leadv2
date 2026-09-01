# FABLE-THINK-TIER-01 — fix round 4

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FABLE-THINK-TIER-01`
LANE_WRITES: plugins/leadv2/skills/leadv2-review/ref/architect-escape-mission.md,plugins/leadv2/scripts/tests/test-fable-think-tier.sh,plugins/leadv2/docs/model-effort-matrix.md,plugins/leadv2/docs/phases.md,plugins/leadv2/config/model-capability.yaml,plugins/leadv2/scripts/lib/leadv2-think-model.sh,plugins/leadv2/scripts/leadv2-ask.sh,plugins/leadv2/scripts/leadv2-session-route.sh,plugins/leadv2/scripts/leadv2-route-bandit.sh,plugins/leadv2/scripts/leadv2-repo-install.sh,docs/handoff/FABLE-THINK-TIER-01/
Continue from the existing commits on this branch (`git log main..HEAD`); run with
`LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST (`git merge main`). NEVER commit anything under
`docs/leadv2/` (control-plane state: bus, locks, active.yaml, merge-queue) — the suites retarget those
symlinks to /tmp while running; before every commit run `git checkout -- docs/leadv2` and commit with
explicit pathspecs from LANE_WRITES only. Commit at the end; an uncommitted exit is a failed round.

## Review verdict on round 3 (reviewer glm, `review-glm.md`) — FAIL, critical=1 high=5
- Critical (`docs/leadv2/active.yaml` + 7 state symlinks retargeted to /tmp in the diff): suite side-effect
  captured by the auto-commit. The lead restored them from main; the rule above prevents a repeat.
- High 1 — `test-fable-think-tier.sh:85`: census regex matches only lowercase `model`/`--model`; uppercase
  shell-var pins (`X_MODEL:-opus`, `CLAUDE_HEAVY_MODEL="opus"`) evade both census passes.
- High 2 — `leadv2-ask.sh:514`: `model="${LEADV2_ASK_ARCHITECT_MODEL:-opus}"` — architect-decide think
  spawn still defaults to opus.
- High 3 — `leadv2-session-route.sh:61` (consumed at :213): `CLAUDE_HEAVY_MODEL="opus"` pins a think tier.
- High 4 — `leadv2-route-bandit.sh:553`: `default_architect="opus"`, `default_critic="opus"`,
  `two_arms='["sonnet","opus"]'` — plan/review bandit can never pick Fable.
- High 5 — `leadv2-repo-install.sh:298`: installer writes `"LEADV2_MAIN_MODEL":"opus"` on every
  install/update, defeating "lead main model = fable" on fresh/refreshed repos.

## Do
1. Census: match pins by VALUE class regardless of the variable name or case — any assignment or default
   (`X=opus`, `X="claude-opus-5"`, `${X:-opus}`, `"model":"opus"`, `--model opus`, JSON/YAML keys) at a
   think-role site fails unless it comes from the resolver (`leadv2-think-model.sh`). Add the four shapes
   from Highs 2–5 as red fixtures; run, paste red; then green after step 2.
2. Route the four sites through the resolver: `leadv2-ask.sh:514`, `leadv2-session-route.sh:61/213`,
   `leadv2-route-bandit.sh:553` (architect/critic defaults + `two_arms` must include `fable`),
   `leadv2-repo-install.sh:298` (write the resolver's answer, or `fable`, never a literal `opus`). Keep
   Opus 5 as the resolver's fallback when Fable is unavailable (quota / model missing) — the fallback lives
   in ONE place, the resolver.
3. Re-run the tree-wide census on the merged tree: paste the header line and prove zero think-role opus
   pins outside the resolver (`grep -rn` census output in report.md). If a site is intentionally opus
   (non-think role), list it with a one-line reason.
4. Mutation negative controls, RUN and paste red: (a) re-insert `CLAUDE_HEAVY_MODEL="opus"` at
   `leadv2-session-route.sh:61` → census red; (b) revert `leadv2-repo-install.sh` line → red. Revert both.
5. `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-fable-think-tier.sh`
   → paste FALSIFIABLE; `tests/run-all.sh --scope changed` → paste the selected-suite line.
6. "## Round 4 evidence" in `docs/handoff/FABLE-THINK-TIER-01/report.md`; commit (pathspecs only).
