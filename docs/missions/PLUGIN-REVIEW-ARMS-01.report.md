# PLUGIN-REVIEW-ARMS-01 — report

**Task:** dispatch-100a892d · **Lane worktree:** `.claude/worktrees/100a892d` · **Date:** 2026-08-15
**Design:** architect prepass `docs/handoff/dispatch-100a892d/architect-prepass.md` (scoped design authoritative)

## 0. What the mission said vs what was true

The mission's stated cause ("no `routing.yaml` in this repo") was wrong. The shipped code already
self-heals a missing tenant yaml (P3 fallback + resolver-side fallback since `717b16f`), and running
the shipped resolver against a deliberately nonexistent routing yaml returns a real author-excluding
pool. The real, single root cause of the `4c9ddb05` empty pool: **that dispatch ran from a stale
real-copy `.claude/scripts/` tree** (pre-2026-07-30 writers, no `leadv2-review-run.sh`, Aug-1
resolver, no `leadv2-phase-record.sh` → rc=127). All three reported symptoms were that one cause.

## 1. What was built (design §4, in order)

| # | Step | Where | Status |
|---|---|---|---|
| 1 | Tenant routing yaml | `.claude/ref/leadv2-routing.yaml` (new, committed) | done — protected paths = dispatch/gate/hook surface (`plugins/leadv2/scripts/*`, `hooks/*`, `config/*`, `.claude/settings.json`); arm mix deliberately unchanged vs shipped default; `docs/**` and skills markdown deliberately NOT protected |
| 2 | `.claude/config` → `../plugins/leadv2/config` symlink (note: the design's `../../` target was one hop too many; `../` is the correct relative target) | committed | done |
| 3 | `.claude/scripts/` dispatch-path symlinks (6 files: dispatch-code, dispatch-product-close, phase-record, review-run + lib/policy-resolve, lib/review-signals) | worktree-local (see §4 caveat) | done locally; **cannot be committed** — `.claude/scripts/` is gitignored by founder policy ("plugin sync writes canonical scripts here — not source, not committed"). The durable guard is step 4 |
| 4 | Dispatcher provenance refusal: a dispatch whose `SCRIPT_DIR` is not a `plugins/leadv2/scripts` tree while one is discoverable next to the project **exits 4** with `dispatch_refused reason=stale_script_tree` in the journal and a `remedy: ln -sf …` on stderr. `LEADV2_ALLOW_STALE_SCRIPT_TREE=1` downgrades to a warn. Suffix match only, so worktree copies and the plugin cache pass (R3/R4) | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (committed) | done |
| 5 | Review engine loud-failure: resolver stderr+rc captured (was `2>/dev/null`) and re-emitted; the unreviewed `review-gate.md` now carries the full 8-field diagnostic shape — `status/reason/author/pool/tried/refusal/resolver_rc/resolver_stderr/merge_blocked` — field-identical to the lane writer `_pc_write_unreviewed` | `plugins/leadv2/scripts/leadv2-review-run.sh` (committed) | done |
| 6 | Regression suite | `plugins/leadv2/scripts/tests/test-plugin-review-arms.sh` (committed) | done — **28/28 PASS**, mutation-gated (see §3) |
| 7 | Throwaway lane dispatch → evidence | `dispatch-f2ab4a0d` | done — see §2 |

## 2. Live evidence — throwaway lane `dispatch-f2ab4a0d`

Dispatched from the lane worktree's plugin tree (`plugins/leadv2/scripts/leadv2-dispatch-code.sh`),
architect-prepass kill-switched (throwaway), **e2e + review gates left ON**.

Journal `docs/leadv2/tasks/dispatch-f2ab4a0d/journal.md`:

- `phase_precondition_warn … class=Standard missing=plan,gate1,build,test,review,live_verify,close mode=warn`
  — **no** `reason=unexpected_rc value=127` (grep count 0): phase-record now resolves and returns a
  real rc=3 with a genuine missing list. Per design R6 this is the **second finding, load-bearing,
  not noise**: no phase has ever been recorded for plugin work. Left in warn mode (enforce is
  out of scope).
- `grep -c routing_config_degraded` → **0**; `route_resolved … reason=glm_default` (a real rule,
  not `no_routing_yaml`).

Reviewer pool (resolver, author=`glm`, protected-path signals, against
`.claude/ref/leadv2-routing.yaml`):

```
reviewer=opus
pool=codex:unknown:,glm:author:,kimi:excluded:safety,opus:ok:16,sonnet:ok:16
```

The author (`glm`) is **present in the pool but tagged `:author:` and never selected** — the quoted
pool line above is the proof the mission asked for. `kimi` stays `excluded:safety`. The reverse
direction holds too (`--author opus` → `opus:author:`, reviewer=`glm`) — verified in test T2 against
this exact yaml (R7 closed: claimed → proven).

<!-- VERDICT-EVIDENCE: filled after the close gate seats the reviewer -->

## 3. Tests

`plugins/leadv2/scripts/tests/test-plugin-review-arms.sh` — 28 assertions:

- T1 tenant yaml present/parses; protected-path patterns steer review-signals for a bash+markdown
  repo (plugin paths protected; `docs/**` not).
- T2 author-exclusion both directions against the **tenant** yaml; kimi stays safety-excluded.
- T3 stale-tree dispatch → exit 4 + stderr refuse/remedy + journal `dispatch_refused
  reason=stale_script_tree`.
- T4 `LEADV2_ALLOW_STALE_SCRIPT_TREE=1` → warn, no refuse.
- T5 plugin tree and worktree-style tree both pass the check (suffix match, R3).
- T6 engine unreviewed artifact carries refusal/resolver_rc/resolver_stderr/merge_blocked when the
  resolver crashes (rc=1, stderr "boom") — acceptance criterion 3.
- T7 engine and lane writers emit the identical 9-token field set (R8).
- T8 no `value=127` from a plugin-tree dispatch (R6 pin).

**Mutation gating** (honest): removing the `exit 4` → T3a FAIL (rc=0); removing the stderr capture
→ T6e FAIL (`resolver_stderr: -`). Restored → 28/28 both times.

Core offline e2e gate (`run-core-offline.sh --scope changed`, same command the close gate runs):
see `/tmp/pra01-core-offline.log` and §5.

## 4. Caveats / follow-ups for the lead

1. **Main checkout still carries the stale `.claude/scripts/` copies** (gitignored, so no commit can
   remove them). This lane is pinned to its worktree and did not touch them. The refusal now makes
   the NEXT dispatch from that tree fail loudly instead of silently; to actually convert (run once
   in `~/Projects/leadv2`):
   ```
   ln -sfn ../plugins/leadv2/config .claude/config
   for f in leadv2-dispatch-code.sh leadv2-dispatch-product-close.sh leadv2-phase-record.sh leadv2-review-run.sh; do
     ln -sfn "../../plugins/leadv2/scripts/$f" ".claude/scripts/$f"; done
   for f in leadv2-glm-policy-resolve.py leadv2-review-signals.sh; do
     ln -sfn "../../../plugins/leadv2/scripts/lib/$f" ".claude/scripts/lib/$f"; done
   ```
   Full de-duplication of the other ~213 files remains the existing open thread
   (GATE-WRONG-ROOT-FALSE-DEAD-01), unchanged and out of scope here.
2. `LEADV2_REVIEW_ENGINE` still defaults to 0 (ONE-PATH-EVERYWHERE-01 rollout), so today's live
   unreviewed artifacts come from the lane writer; the engine's widened shape is future-proofing the
   default path (that default flip is not this lane's).
3. Phase recording for plugin work (R6 finding) is a follow-up finding, deliberately not built here.

## 5. Acceptance checklist

| Acceptance | Status |
|---|---|
| Throwaway lane's `review-gate.md`: status ≠ no_reviewer, reviewer ≠ author, `REVIEW_VERDICT:` present | <!-- ACC1 --> |
| Throwaway journal: no `routing_config_degraded`, no `value=127` | **PASS** (grep counts 0 / 0) |
| Unreviewed shape carries refusal, resolver_rc, resolver_stderr, `merge_blocked: true` | **PASS** (test T6, live artifact reproduced in suite output) |
| This report states author-present-but-tagged-author and quotes the pool line | **PASS** (§2) |
