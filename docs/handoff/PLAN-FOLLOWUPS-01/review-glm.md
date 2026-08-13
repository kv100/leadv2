⚠ claude.ai connectors are disabled because ANTHROPIC_API_KEY or another auth source is set and takes precedence over your claude.ai login · Unset it to load your organization's connectors
"glm-5.2" is not a model this version of Claude Code recognizes, so auto-compact will keep this session within 200k tokens (the context window it assumes). If the model accepts more, append [1m] to the model name for 1M, or set CLAUDE_CODE_MAX_CONTEXT_TOKENS to its real window; to make it recognized, map it in the modelOverrides setting or update Claude Code; CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1 restores the previous wait-for-the-API behavior.
Now I have the full picture. Let me compile the review.

---

REVIEW_VERDICT: PASS_WITH_NITS
REVIEW_FINDINGS: critical=0 high=0 medium=0 low=3

FINDING: severity=Low file=plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py line=530 dimension=correctness desc=Empty-rank-table regression: elif condition changed from `rank_table` (truthy=non-empty) to `not floor_ok`, so an empty rank_table (feature-not-adopted config) now overwrites refusal to pool_floor_table_degenerate instead of preserving all_review_arms_unavailable

## Detailed Review

### Scope
The diff implements 4 caveats from PLAN-FOLLOWUPS-01:
1. Architect arm refusal spill in `leadv2-plan-run.sh`
2. Dual-ordering YAML extraction in `extract_plan_yaml`
3. Non-dict acceptance rejection in `leadv2-context-merge.py`
4. `DISPATCHABLE_PLAN_ARMS` filtering in `leadv2-glm-policy-resolve.py`

Plus a new test file and registration in `run-core-offline.sh`.

### Caveat 1 — Architect refusal spill ✅
The while-loop correctly walks forward through `:ok:` arms when an arm returns `refused_*` or `arm_unavailable`, bounded at 4 total tries. The `case` glob `refused_*)` matches all three refusal types from `classify_arm_failure` (`refused_quota`, `refused_peak_hours`, `refused_channel_down`). The `_slot_rc` post-loop fallback correctly distinguishes provider_error (rc≠0) from empty_response (rc=0). Logic is sound.

### Caveat 2 — Dual-ordering YAML extraction ✅
Order A (marker→fence) and Order B (fence→marker) awk programs are correct. Traced both through sample inputs — they extract the right content and stop at the closing fence. The legacy marker-only fallback correctly guards on "no fences AND marker present" before extracting. The final `cat "$f"` fallback preserves the original behavior for raw-YAML stubs.

### Caveat 3 — Non-dict acceptance rejection ✅
The `TypeError` raise for non-dict `acceptance` is correct and the `main()` try/except converts it to `return 1`. The new `result["acceptance"] = {}` initialization when skeleton lacks a dict acceptance is a strict improvement over the old code (which would fall through to `elif` and clobber the entire acceptance key). `ENGINE_OWNED_ACCEPTANCE` keys (authored_at) are preserved.

### Caveat 4 — DISPATCHABLE_PLAN_ARMS floor filtering ✅
`_review_floor`'s new `dispatchable` parameter correctly filters the rank table before floor selection. The semantic change from `return None, False` to `return None, True` for the no-candidates case is safe: when `dispatchable=None`, this path is unreachable for tables with ≥2 entries (a dict with ≥2 keys always has ≥1 non-author candidate). The caller changes (`elif not floor_ok:` replacing `elif rank_table:`, and `if not ok` replacing `if rank_table`) correctly avoid misclassifying a valid-but-filtered-empty ladder as degenerate.

### Low findings (3)

**L1 — Empty rank_table regression** (`leadv2-glm-policy-resolve.py:530`): When `rank_table` is completely empty (no `review_rank` entries in the routing YAML — the "feature not adopted" case), `_review_floor` returns `(None, False)`. The old `elif rank_table:` was falsy for `{}` (correctly preserving `all_review_arms_unavailable`). The new `elif not floor_ok:` fires, overwriting to `pool_floor_table_degenerate`. Same issue in `_best_effort_floor_pool` (line 302 of diff). Impact is **diagnostic only** — I verified the plan engine's `case "${refusal}"` at `leadv2-plan-run.sh:539` only gates on `resolver_missing_failclosed|resolver_error_failclosed`, so both refusal strings fall through identically. The review engine (`leadv2-review-run.sh:447`) also doesn't branch on the refusal value. Fix: add `and rank_table` to the condition, or check `len(rank_table) >= 2` before the elif.

**L2 — `extract_plan_yaml` multi-read breaks pipe input** (`leadv2-plan-run.sh:371`): The function reads `$f` up to 4+ times across separate awk invocations. This works for regular files (each awk reopens from offset 0) but silently fails for pipes/stdin — the first awk drains the pipe, subsequent awks see EOF. Test 2e pipes through `/dev/stdin`, so it only works if the fixture emits Order A format (first awk succeeds, no re-read needed). Not a production issue (always called with file paths), but the test is fragile.

**L3 — Diagnostic: all-refused reported as provider_error** (`leadv2-plan-run.sh:148`): When all arms refuse and the loop exhausts, the post-loop check reports `reason=provider_error rc=75` based on the last arm's rc. A dedicated `reason=all_arms_refused` would be more informative, but the gate still blocks correctly.

### Test file
17 individual assertions covering all 4 caveats with hermetic sandboxes. Test 4d correctly verifies the filtered-to-empty case returns `all_review_arms_unavailable` (not `pool_floor_table_degenerate`) — this works because the *original* rank_table has ≥2 entries. Mutation-gated by design (each test must fail when its fix is reverted). No grep-on-source assertions — all tests exercise runtime behavior.

---

**NOT-COMMITTED** — review only, no files changed, no stash created.
