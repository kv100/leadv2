LABEL=critic-dispatch-PLAN-FOLLOWUPS-01-review-1786617022 SESSION_ID=4e52488c-420e-444c-b2ff-ef167dcdb91d
--- body from: docs/handoff/dispatch-PLAN-FOLLOWUPS-01-review/critic.full.md ---
# critic — PLAN-FOLLOWUPS-01 build-attempt-3.diff (independent review)

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=3 medium=2 low=2

FINDING: severity=High file=plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py line=545 dimension=correctness desc=`elif not floor_ok` reclassifies an EMPTY rank_table (feature-not-adopted) as pool_floor_table_degenerate instead of all_review_arms_unavailable — verified behavior change vs HEAD
FINDING: severity=High file=plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py line=785 dimension=correctness desc=_best_effort_floor_pool has the identical regression: `if not ok` replaces `if rank_table`, so an empty rank_table returns the hard degenerate error instead of the unavailable fallback
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-plan-run.sh line=371 dimension=correctness desc=extract_plan_yaml order-A pass is disabled by ANY ``` fence appearing before PLAN_YAML:, so a marker→fence output with a prose code block falls through to `cat <whole file>` — HEAD handled this correctly

---

## High

### H1 — empty rank_table now hard-errors (`resolve_review_pool`)
`plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:545` (new numbering)

The diff replaces

```python
elif rank_table:
    # ... ordinary "feature not adopted" case (empty rank_table, handled by the
    # `elif` falling through and keeping all_review_arms_unavailable below).
    refusal = "pool_floor_table_degenerate"
```

with `elif not floor_ok:`. `_review_floor` returns `ok=False` for `len(rank_table) < 2`, which **includes the empty table**. So a routing ladder whose entries carry no `review_rank` (the documented not-adopted case, and exactly what the deleted comment protected) now yields the config-bug refusal.

Empirical A/B on HEAD vs the patched module, same inputs (`review_arm_order=[codex]`, `author=codex`, `rank_table={}`):

```
old {'reviewer': '', 'pool': ['codex:author:'], 'refusal': 'all_review_arms_unavailable'}
new {'reviewer': '', 'pool': ['codex:author:'], 'refusal': 'pool_floor_table_degenerate'}
```

Caveat 4 asked for a *dispatchable-filter* carve-out; it did not ask to fold the empty-table case into the degenerate branch. The docstring the author added even states ok is False "iff the original rank table has fewer than 2 entries" — which is precisely why `not floor_ok` is the wrong predicate here.

**Required fix:** keep both conditions distinct:
```python
elif rank_table and not floor_ok:
    refusal = "pool_floor_table_degenerate"
```
(the filtered-empty case already returns `(None, True)`, so it falls through to `all_review_arms_unavailable` as intended).

### H2 — same regression on the best-effort path
`plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:785`

```python
return "", [], "pool_floor_table_degenerate" if not ok else "all_review_arms_unavailable"
```
replaces `... if rank_table else ...`. Identical failure: a ladder with zero `review_rank` keys produces `ok=False` → degenerate. This path is the last-resort pool builder (called at lines 871/888 after a resolver failure), so it is exactly where a spurious hard error is most damaging — the review gate ends with a hard refusal instead of a graceful unavailable-pool degrade.

**Required fix:** `"pool_floor_table_degenerate" if (rank_table and not ok) else "all_review_arms_unavailable"`.

### H3 — extract_plan_yaml regresses on order A with any preceding fence
`plugins/leadv2/scripts/leadv2-plan-run.sh:371`

Pass A guards the marker rule with `!fence_before_marker`, where `fence_before_marker` is set by **any** line matching `^```` before the marker. That is not an order discriminator: order-B detection requires "the marker is *inside* the first fenced region", not "a fence appeared earlier in the file".

Repro (function copied verbatim from the diff):

```
Here is how I ran it:
```bash
echo hi
```
PLAN_YAML:
```yaml
decisions:
  - Decision A
```
```
→ output is the **entire file verbatim** (prose + fence markers), i.e. the `cat "$f"` fallback: pass A is disabled by the bash fence, pass B finds no marker inside the first fence, the legacy pass is skipped because fences exist. Downstream YAML parse fails → plan gate blocks.

HEAD's awk handled this input correctly (it ignored fences before the marker), so this is a **regression introduced by the caveat-2 fix**, and it is the realistic LLM-output shape (an arm narrating with a code block before emitting the plan).

**Required fix:** discriminate by whether the marker line falls inside a fenced region, e.g. track fence parity and mark `marker_in_fence` when `/^PLAN_YAML:/` is seen with parity odd; use pass B only when `marker_in_fence`, and let pass A skip fences before the marker as HEAD did. Add a test case: preamble fence + order A must still extract the YAML (none of 2a–2e cover it).

## Medium

### M1 — exhausted refusal chain is journaled as `provider_error`
`plugins/leadv2/scripts/leadv2-plan-run.sh:648`

After the spill loop gives up (4 tries or pool exhausted) with every arm `refused_*`, the tail block only inspects `_slot_rc` and emits
`status=blocked reason=provider_error rc=…`. The refusals were already emitted individually, but the terminal gate reason — the one an operator or the supervisor reads from `plan-gate.md` — misattributes a quota/peak-hours refusal to a provider crash, and `write_gate "blocked" "provider_error"` bakes that into the artifact. **Fix:** carry the last `_cls` and emit `reason=all_arms_refused` (or `reason=${_cls}`) when the loop terminated on a `refused_*` classification.

### M2 — the two regressed branches ship with no test
`plugins/leadv2/scripts/tests/test-plan-followups-01.sh:415` (Caveat 4d)

4d exercises a ladder where **every** entry has a `review_rank` (glm/haiku), so it only covers the filtered-empty case. There is no case with an empty `rank_table` (ladder without `review_rank`), which is the branch H1/H2 break. Per the review bar, a changed logic branch with no coverage is a blocking gap here because the change is a silent classification flip. **Fix:** add 4f — ladder with no `review_rank` keys, `--job plan --plan-pool`, assert `refusal=all_review_arms_unavailable`; plus a direct `_best_effort_floor_pool` case with the same ladder.

## Low

### L1 — `author_rank` computed after the dispatchable filter
`leadv2-glm-policy-resolve.py:264` (post-diff)

The filter is applied *before* `author_rank = rank_table.get(author, -inf)`. If the author is itself non-dispatchable for the plan job (e.g. `author=haiku`), its rank vanishes and `author_rank` becomes `-inf`, so the floor picks the *lowest*-ranked dispatchable arm rather than escalating one step above the author. Escalation semantics should use the author's rank from the unfiltered table: capture `author_rank` before filtering.

### L2 — `acceptance:` with an empty value now aborts the whole merge
`plugins/leadv2/scripts/lib/leadv2-context-merge.py:41`

`acceptance:` written bare in arm YAML parses to `None`, which is a very common LLM emission, and now raises `TypeError` → `main` returns 1 for the whole merge. Caveat 3 wanted non-mapping values rejected rather than silently clobbering `authored_at`, and `None` cannot clobber anything meaningful — treating `None` as "arm has no opinion" (skip, let `check_required` report it) would preserve the intent while avoiding a hard stop on a benign shape. Advisory; the current behavior is defensible if intentional.

## Not findings (checked, clean)
- Spill loop termination: `_tried_arch` cap of 4 plus `next_ok_arm_after` returning empty both bound the loop; no unbounded walk.
- `job` is a real parameter of `resolve_review_pool` (default `"review"`), so `job == "plan"` does not NameError; `--plan-pool` is the flag the CLI actually receives.
- `_review_floor`'s degenerate check runs on the *original* table before filtering — correct per its own contract.
- Multiple re-reads of `$f` in `extract_plan_yaml` are safe: all five production callers pass real file paths, not pipes.

## Type/lint evidence
No mypy/tsc surface — the diff touches bash and two dependency-free Python 3 scripts. Byte-compile of the patched resolver used for the A/B above succeeded (`importlib` load, no syntax/name errors). The bash changes were exercised by executing the patched `extract_plan_yaml` directly (see H3 repro).

DELIVERABLE_COMPLETE
