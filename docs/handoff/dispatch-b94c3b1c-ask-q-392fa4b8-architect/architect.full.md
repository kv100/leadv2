# Architect decision — FABLE-THINK-TIER-01 round 2, scope expansion ask

DECISION_OPTION: a
RATIONALE: The 2 routing-guard advisory lines are live steering text that contradicts the shipped think-tier resolver (active regression, same class as dispatch-6280f73a), all 6 files are git-tracked text with lane-commit revert as rollback, and leaving a reviewer HIGH open guarantees a round-3 cycle costing more than the edits.

## Verified site inventory (probed on live tree, base 71ae2b3)

| Site | Evidence | Class |
|---|---|---|
| plugins/leadv2/hooks/leadv2-routing-guard.sh:470,476 | `printf 'Or use Agent(%s, model=opus) for high-stakes plan/review.'` / `'Use Agent(%s, model=opus) for plan/review -- NOT sonnet.'` | **Load-bearing advisory** — runtime output steering plan/review spawns to opus, contradicting the resolver |
| skills/leadv2-review/ref/manual-dispatch-cases.md (x2) | 2 `opus` grep hits | Reference examples of think-role dispatch |
| skills/leadv2-review/ref/architect-escape-mission.md | 1 hit | Think-role mission template |
| skills/leadv2-diverge/PHASES.md:56 | `model=<opus if Heavy/Strategic else sonnet>` | Generic tier guidance, NOT a think-role literal |
| skills/leadv2-recovery/EXAMPLES.md:7,24 | `Spawn architect(opus)`, `model: opus` | Teaching example, adjacent to think-role |
| skills/leadv2-token-discipline/EXAMPLES.md:5,13,16 | Generic Opus-fleet discipline prose | NOT think-role literals — do not touch |

Note: the mission's `hooks/leadv2-routing-guard.sh` path is plugin-relative; the real path is `plugins/leadv2/hooks/leadv2-routing-guard.sh`. No `hooks/` dir exists at repo root.

## Why a over b

1. **Two sites are active, not stale.** The routing-guard printfs fire at runtime and recommend exactly the pattern this lane exists to replace (hardcoded opus for think roles). Documenting the gap (b) leaves a live contradiction between the guard's advice and the resolver — the same failure shape the dispatch-6280f73a ruling called an active regression, not a gap.
2. **Reversibility is real.** All 6 files are git-tracked; rollback = revert of the lane commit. No schema change, and no hook-cache behavior change is required for the edit to be *correct in canonical*.
3. **Round economics.** A reviewer HIGH left open either blocks close or forces round 3. Six bounded text edits now is cheaper than a third review cycle.

## Binding constraints for the implementing developer (so the expansion stays safe)

- Touch ONLY literals that name a think-role dispatch (plan / review / architect-escape / critic-on-think). The diverge PHASES.md and token-discipline EXAMPLES hits are generic Opus-discipline prose — replace only if they read as think-role directives; otherwise leave verbatim and note "reviewed, not think-role" in the lane journal.
- Hook file edit is canonical-source only: per HOOK-CACHE-01, it does not go live until the plugin cache is refreshed and sessions restart. LEAD_ACTION (not lane work): propagate `plugins/leadv2/hooks/leadv2-routing-guard.sh` into the plugin cache after merge.
- Add all 6 files to LANE_WRITES for this round only; do not reformat or refactor the markdown.

## Risks

- Scope fuzziness ("which literals count") → mitigated by the think-role-only rule above and journal annotation for skipped hits.
- Hook edit appears to do nothing live → pre-declared above; prevents a false "fix verified" claim at verify.

## Out of scope

- Any change to the resolver itself, model-capability.yaml, or executable routing scripts (already in LANE_WRITES from round 1).
- Rewriting skill-doc teaching prose beyond the literal substitutions.

DELIVERABLE_COMPLETE
