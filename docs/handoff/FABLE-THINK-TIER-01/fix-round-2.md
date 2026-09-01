# FABLE-THINK-TIER-01 — fix round 2

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FABLE-THINK-TIER-01`
LANE_WRITES: plugins/leadv2/config/model-capability.yaml,plugins/leadv2/docs/model-effort-matrix.md,plugins/leadv2/scripts/lib/leadv2-think-model.sh,plugins/leadv2/scripts/*.sh,plugins/leadv2/workflows/*.js,plugins/leadv2/skills/**/SKILL.md,plugins/leadv2/scripts/tests/test-fable-think-tier.sh,docs/handoff/FABLE-THINK-TIER-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last `bccafe5`); run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Review verdict on round 1 (reviewer glm, `review-findings.json`)
status=fail high=2:
- **[High] `docs/model-effort-matrix.md:107`** — the new global invariant "no think-role spawn site
  may hardcode an `opus` literal — call the resolver" is FALSE in-tree: the reviewer's census found
  ≥8 untouched think-role sites still spawning with a literal `opus`, while the grep-gate in the
  suite covers only the 4 workflows you changed.
- **[High] `config/model-capability.yaml:38`** — external-system claims (Fable 5.1 GA, 1M context,
  same Claude Max bucket as Opus) drive code (`glm-policy-resolve.py` bucket mapping, `context_k:
  1000`) with no inline evidence tag. The bucket-mapping path is claim-driven.

## Do
1. Run your OWN census first and paste it in report.md: `grep -rnE "model[=: ]+['\"]?opus" plugins/leadv2/{scripts,workflows,skills,hooks}` plus
   `subagent_type.*(architect|critic|judge)` spawn sites. Classify each hit: think-role (must go
   through the resolver) / build-role (opus literal allowed only if the matrix says so) / prose.
   Migrate EVERY think-role site to the resolver. Then make the suite's grep-gate cover the whole
   tree (the census command itself, expecting zero think-role literals), not four files.
2. Evidence tags: every claim in `model-capability.yaml` notes and in the matrix that drives a code
   path gets `evidence:` — the verbatim source line. Fable 5.1 model id `claude-fable-5-1` and
   Opus 5 `claude-opus-5` come from the Claude Code environment banner (quote it). The Max-bucket
   claim: PROVE it with `python3 plugins/leadv2/scripts/leadv2-quota-read.py anthropic --no-cache`
   before and after one tiny `claude -p --model claude-fable-5-1 'say ok'` on the personal profile
   — if the same bucket moves, tag `evidence: quota-read delta 2026-09-01`; if it does NOT move or
   Fable is refused on this plan, the mapping is WRONG: give Fable its own bucket entry and make
   `context_k` / `cost_class` say `unverified` rather than a number you did not measure. Paste both
   quota reads.
3. Mutation negative control, RUN and paste red: re-insert one `model: opus` literal at a think-role
   site → the tree-wide grep-gate red. Revert.
4. Append "## Round 2 evidence" (census, quota reads, suite green, control red) to report.md; commit
   in the lane. An uncommitted exit is a failed round.
