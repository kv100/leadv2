REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=1 medium=1 low=1
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-review-run.sh line=1065 dimension=correctness desc=hack-detect job now aliases the claude reviewer arm's claude-subsession artifacts (same role=critic + same task-id `dispatch-${TASK}-review`) and runs concurrently with it, clobbering shared per-role output files and cost records

# Review: /tmp/leadv2-bootstrap-routing-glm53.diff

## What the diff does
Bumps the GLM build/review model glm-5.2 → glm-5.3 in `leadv2-routing.yaml`, `glm-coder.sh`, `leadv2-session-route.sh`; adds an evidence doc + inline evidence pointers; adds `materialize_glm_review_body()` to unwrap Claude's JSON envelope before verdict parsing; fixes an `UnboundLocalError` in the glm-policy resolver for tenant YAMLs without `glm_policy:`; revives the dead hack-detect arm by re-pointing it from the nonexistent `hack-detect` role to `critic`; updates 4 test files to match.

## Findings

### High — role-alias artifact collision in the review engine (`leadv2-review-run.sh:1065`)
`_engine_hack_detect_job` now runs `claude-subsession.sh --role critic --task-id "dispatch-${TASK}-review"` — **identical role AND task-id** to the main claude reviewer arm (`leadv2-review-run.sh:444`). `claude-subsession.sh` keys its artifacts by ROLE only inside `HANDOFF_DIR=docs/handoff/<task-id>`:
- `claude-subsession.sh:550` — `STREAM_OUT="$HANDOFF_DIR/${ROLE}.stream.jsonl"` (truncating `>`)
- `claude-subsession.sh:1157-1160` — `${ROLE}.full.md` / `${ROLE}.summary.md` / legacy `${ROLE}.md`
- `claude-subsession.sh:1154` — `parse_and_record_cost "$STREAM_OUT"` reads the shared stream file

The two jobs run concurrently (`leadv2-review-run.sh:1286-1290`: arms backgrounded, then `( _engine_hack_detect_job ) &` under `SECURITY_REVIEW_ENABLED=1`). When the pool selects an anthropic reviewer (opus/sonnet/fable — exactly the D3-floor case when glm/codex are locked, per test T2) on a protected-path diff, the haiku hack-detect job and the reviewer both truncate and rewrite `critic.stream.jsonl` / `critic.full.md` / `critic.summary.md` in the same directory, and both parse costs from the same interleaved stream. The parsed gate verdict survives (each job's stdout goes to its own `HACKDETECT_OUT`/`review_out` pipe), but the reviewer's canonical deliverable and cost record — the evidence trail this engine treats as load-bearing — can be silently replaced by hack-detect output. This is **introduced** by the diff: pre-diff, `--role hack-detect` exited 1 at `claude-subsession.sh:181` (`role file not found in agents/ or roles/ $ROLE` — no such file exists in `.claude/agents/` or `.claude/roles/`), so the arm was dead and wrote nothing. Fix: give hack-detect a distinct task-id (e.g. `dispatch-${TASK}-review-hackdetect`) or a real dedicated role file.

### Medium — census miss: live session runner still pins glm-5.2 (`leadv2-glm-session-runner.sh:32`)
The model-bump shape was not enumerated exhaustively. `MODEL="${LEADV2_LEAD_MODEL:-glm-5.2}"` remains in a live (non-test) script. `MODEL` is never passed to `glm-coder` (used only in the provider receipt at line 130 and log at line 313), so on direct invocation the active.yaml provider receipt and logs record `glm-5.2` while glm-coder now actually runs glm-5.3 — untruthful telemetry. (On the fanout path `LEADV2_LEAD_MODEL` is set from routing, `leadv2-fanout.sh:1181`, so only the default path lies.) Full census of remaining `glm-5.2` references: this file, `config/model-capability.yaml:157`, and ~20 test fixtures (self-contained, fine). Quota accounting is safe: `leadv2-quota-status.sh:193,204` matches `model LIKE 'glm%'` (prefix, not exact).

### Low — stale capability sheet (`config/model-capability.yaml:157`)
`glm: underlying_model: glm-5.2`, asof 2026-07-31. No script consumes it (`grep -rln 'model-capability' plugins/leadv2/scripts` → empty), so it's advisory metadata now contradicting routing. Docs-only.

## Lens results

**Correctness** — the resolver fix is right and minimal: `block = ""` then the existing regex; reproduced pre-fix `UnboundLocalError: cannot access local variable 'block'` and post-fix clean dict `{'sonnet_exceptions': [], ..., 'codex_quota_gate': None, 'live_balance': None}` via direct exec of both variants. `materialize_glm_review_body` correctly handles glm-coder's envelope-with-merged-stderr (`glm-coder.sh:271` `--output-format json >"${out_file}" 2>&1`) by reverse-scanning for the last `is_error:false` line with non-empty string `result`, and fails closed (returns 1, `|| true`, leaving the JSON for the existing `review_body_lost` guard at `leadv2-review-run.sh:1369`). The High above is the one correctness defect.

**Tests-can-fail** — all four touched suites pass: `test-session-route.sh` PASS=8 FAIL=0; `test-leadv2-review-routing.sh` PASS=3 FAIL=0; `test-review-engine-v3-core.sh` PASS=5 FAIL=0; `test-review-pool-never-empty.sh` all PASS incl. T4b, exit 0. T4b genuinely falsifies (pre-fix crash reproduced above). The v3-core fixture's mission-head check (`head -n 1 == 'Run hack-detection on the diff at '*`) matches the real mission first line at `leadv2-review-run.sh:1061`. None of the tests, however, exercise the two concurrent critic sessions (the High finding) — the fixture only counts sequential role labels.

**Product-invariant/contract** — fail-closed review-gate contract preserved (materialize leaves malformed output to the body-lost guard). One-copy rule respected (edits in canonical plugin only). The hack-detect mission still emits `dimension=hack`, outside the reviewer contract's enum — pre-existing, not diff-touched.

**Census** — model-bump shape: 2 missed live instances (High/Medium/Low above); role-change shape: single site; evidence-pointer shape: 3 sites (routing.yaml:52, glm-coder.sh:3, session-route.sh:64) + 1 doc, all consistent.

**Claims-without-evidence** — every external-system claim in the diff carries inline evidence, and I reproduced the probe live against `https://api.z.ai/api/anthropic` (token sourced from `~/.claude/secrets/zai.env`, never echoed):
```json
{"is_error": false, "model": ["glm-5.3"], "result": "GLM-53-ALIVE"}
```
with stderr `[claude-code:unrecognized_model] {"model":"glm-5.3","query_source":"sdk"}` — exactly matching `docs/evidence/glm-5.3-probe.md`, including the envelope fields `terminal_reason`, `canonicalModel: "glm-5.3"`, `provider: "firstParty"` (verified present in a full envelope dump). The comment "glm-coder deliberately preserves that envelope" is confirmed at `glm-coder.sh:270-271`. No untagged evidence-free claims found.

## Finish contract
- Stash: none created by me (pre-existing `stash@{0}` from another session's worktree left untouched).
- Files changed by me: none — review-only, read-only probes.
- Tests: 4/4 touched suites pass (outputs quoted above); live GLM-5.3 endpoint probe passed.
- Commit: NOT-COMMITTED — no changes to commit; the diff under review is already applied in the working tree.
