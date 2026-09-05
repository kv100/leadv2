REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=1 medium=3 low=5

FINDING: severity=High file=docs/handoff/GLM-5.3-ROUTING-FINAL/review.diff line=12 dimension=correctness desc=Corrupt patch artifact: `git apply --check` fails ("error: corrupt patch at line 12", rc=128) — hunk headers' line counts don't match bodies (e.g. policy-resolve hunk says +4 lines, body has 2; routing.yaml hunk1 claims 8/9 lines, body has 6), so the reviewed diff omits 2 of the 4 added comment lines that ARE in commit feb253b and cannot be applied by any downstream consumer.

## What the diff is

Model bump glm-5.2→glm-5.3 across routing/session/glm-coder, capability-nulling with UNVERIFIED tags, a JSON-envelope materializer for the GLM review arm, a hack-detect→critic role swap, a `block=""` NameError fix in the policy resolver, plus test updates. The change is already committed as `feb253b` and present in the tree; review.diff is its (corrupted) handoff representation.

## Verified correct (with artifacts)

- **Live endpoint claim** — re-ran the probe from the evidence file: `ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic ... claude -p --model sonnet` → `{"is_error":false,...,"modelUsage":{"glm-5.3":{"canonicalModel":"glm-5.3","provider":"firstParty",...}},"terminal_reason":"completed","result":"GLM-53-ALIVE"}`. Every field quoted in `docs/evidence/glm-5.3-probe.md` matches the live response; the evidence artifact is genuine, not fabricated.
- **`block = ""` fix is real** — `leadv2-glm-policy-resolve.py:172` runs `re.search(..., block)` unconditionally after the `if m:` guard, so a tenant yaml without `glm_policy:` previously raised NameError. Unit probe of the tenant path now returns a dict, no traceback; T4b covers it; `call_resolver` does accept the tenant yaml as arg 4.
- **hack-detect→critic swap justified** — `.claude/agents/` contains only architect/critic/developer/security-auditor (no `hack-detect.md`); `.claude/roles/` doesn't exist; the usage string at `claude-subsession.sh:49` lists 6 valid roles not including hack-detect — the old invocation hit the "role file not found" path. Mission text unchanged (drives semantics); artifact namespaces are distinct (`dispatch-${TASK}-review` vs `dispatch-${TASK}-review-hackdetect` at review-run.sh:444/1067/1086; SESSION_LABEL keys on ROLE+TASK_ID); no `review-*` glob sweeps `review-hackdetect.md` (only `review-gate.round*`/`review-findings.round*` at :613).
- **materializer is genuinely needed** — glm-coder's run path writes Claude's JSON envelope (`--output-format json`, glm-coder.sh:270); the verdict parser expects plain text.
- **model-capability nulls are safe** — no script consumers of `model-capability.yaml` (grep over scripts/ + lib/), documentation-only.
- **Tests, run by me**: test-session-route.sh PASS=8 FAIL=0 · test-review-engine-v3-core.sh PASS=5 FAIL=0 · test-leadv2-review-routing.sh PASS=3 FAIL=0 · test-review-pool-never-empty.sh all-PASS (incl. T4b/T5/T6/T7), no fails.

## Findings

**High**
1. Corrupt review.diff (above). A reviewer approving this artifact approves a patch that doesn't apply and differs from the shipped commit.

**Medium**
2. **Census — model bump missed user-facing docs**: `plugins/leadv2/commands/leadv2.md:37` still documents "GLM-5.2 / Kimi … glm-5.2 / kimi" (the `/leadv2` command surface) and `plugins/leadv2/docs/model-effort-matrix.md:105` still says glm-5.2.
3. **materialize fail-open edge** (`leadv2-review-run.sh` materialize_glm_review_body + call site): if glm exits 0 but every line is `is_error:true`/empty result, `|| true` leaves the raw JSON envelope in `review_out`; a grep-based verdict extractor can then match `REVIEW_VERDICT:` inside escaped JSON of a failed envelope. Failing the arm (or truncating) would be safer than silent retention.
4. **Stale parallel worktree**: `.claude/worktrees/3f9ac0d4/` carries full pre-bump copies (routing.yaml, glm-coder.sh, session-route.sh, session-runner all glm-5.2). Re-landing that branch silently reverts the bump — the exact one-copy-drift shape the session-start hook is already flagging.

**Low**
5. `test-t-core-filter-arms-parity.py:129` REAL_PROD_ARMS fixture still `glm-5.2` while its docstring claims it mirrors `router_v2.arms from leadv2-routing.yaml` — fixture's "REAL" claim is now false (filters don't key on model string, tests pass).
6. `test-leadv2-review-routing.sh` fake architect.sh: `[[ "$role" == "hack-detect" ]] && exit 0` is now dead code (role is never hack-detect post-swap).
7. T4b pass criterion asserts only non-empty pool + no Traceback, not reviewer/pool values — weak but acceptable for a crash-regression test.
8. Evidence probe omits the `contextWindow:200000` datum the live response carried; capability yaml keeps `context_k: null`/UNVERIFIED despite the probe itself producing a data point (also `$0.05/probe` cost unrecorded).
9. Remaining glm-5.2 test fixtures are self-contained synthetic data, not production-coupled (enumerated for census): test-glm-deferred-ladder.sh:68, test-router-v2-retired-arm.sh:130, test-glm-coder-529.sh:62/73/82/122, test-deadhand.sh:72/82/94/107/121/138, test-quota-glm-filter.sh:49, test-quota-weekly-total.sh:50, test-status-surface{,-close-phase,-handle-identity}.sh meta.yaml fixtures, test-routing-enforcement-p1.sh:465.

**Claims-without-evidence sweep**: all five "Live acceptance evidence" pointers resolve to a real file; live re-probe confirms it. The review-run comment "claude-subsession keys stream/cost files by task id plus role" is backed by `SESSION_LABEL="${ROLE}-${TASK_ID}-…"` (claude-subsession.sh:192). The test comment "Match the real glm-coder transport" is backed by glm-coder.sh:270. The capability note is properly UNVERIFIED-tagged. No untagged evidence-free external-system claims drive a decision.

---

**Finish contract**: no stash created. NOT-COMMITTED — read-only review; the only tree writes were `/tmp` (live probe ran from /tmp, shell cwd side-effect only). Files changed by me: none. Test results above are from my own runs this session.
