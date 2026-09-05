All probes done. Compiling the review.

---

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=1 medium=4 low=4

FINDING: severity=High file=docs/handoff/WORKER-MCP-ALL-ARMS-01/report.md line=247 dimension=design desc=Deliverable asserts a full `tests/run-all.sh --scope changed` run ("full run, 2026-09-02, state-file reset beforehand") but the evidence block is the literal unfilled token `RUNALL_PLACEHOLDER` — an untagged, evidence-free verification claim driving the round's done-ness.

## Evidence basis (what I verified live)

- **Suite green, independently re-run**: `bash plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh` → `TOTAL: PASS=49 FAIL=0`, rc=0. All negative controls (freepool run, freepool bg, kimi bg wiring, tee -a, dispatch gate, mission-fold) pass.
- **Codex external claims verified live**: `ls ~/.claude/plugins/cache/openai-codex/codex/` → 1.0.3, 1.0.4; `grep -c mcp …/1.0.4/scripts/codex-companion.mjs` → 0; `wc -l` → 1027; `spawn(` at :643 with the fixed `task-worker` argv exactly as the toml comment states. These claims are properly evidenced.
- **H1 fix on disk**: kimi-coder.sh:1135 `tee -a`; freepool twins already append (:1283, :1285).
- **Gate root == launcher root**: dispatch:5180 passes `"${WORK_ROOT}"`; every arm launch (:5214, :5268, :5327, :5490) uses `--cwd "${WORK_ROOT}"`. Sonnet branch semantics match claude-subsession.sh:543 (`LEADV2_SUBSESSION_SLIM_MCP` default 0, opt-in).

## Findings

**High**

1. **H-1 (claims-without-evidence)** — `report.md:247`: `RUNALL_PLACEHOLDER`. The report's §4 "Falsifiable gate + changed-scope" claims the changed-scope run-all was executed in full, then pastes a placeholder where its output belongs. The falsifiable-gate block above it IS filled, which makes the missing block look completed at a glance. Census of the same shape: Round 2's "`tests/run-all.sh --scope changed`: (selected-suite line appended below after run completes.)" (report.md:130-131) is a second unfilled evidence slot — historical, superseded, but same defect shape in the same file.

**Medium**

2. **M-1 (design/census — triple-copied wrapper)** — `worker_mcp_journal()` + `worker_mcp_resolve()` are byte-identical copies in freepool-coder.sh:127-169 and kimi-coder.sh:151-193 (verified by `diff`: freepool==kimi exactly; glm-coder.sh:288-330 differs only in comment lines). This diff *added* two new copies while its own header comment claims "same resolver … — never a second implementation". `resolve_role_mcp_config` is shared, but the ~40-line wrapper pair now lives in three places; exactly the silent-drift shape the 2026-07-29 founder decision bans for copies. The wrappers belonged in `lib/leadv2-worker-mcp.sh`.
3. **M-2 (correctness — gate prediction can drift by role)** — `lib/leadv2-worker-mcp.sh` (`worker_mcp_preamble_for_arm`, role read ~:199) uses ambient `LEADV2_WORKER_ROLE:-developer`, but the glm launch line (dispatch:5214) *forces* `LEADV2_WORKER_ROLE=developer` into the launcher env. If the dispatcher process carries a different ambient role, the gate predicts a different role's server set than the child attaches — a hole in the code-comment's absolute claim "the prediction is therefore deterministic … cannot drift" (lib:178). Edge-case env, but it is precisely the drift dimension the gate exists to close; kimi/freepool/codex paths are consistent.
4. **M-3 (documentation — report contradicts shipped code, no Round 4 section)** — report.md Round 3 §2 (~lines 190-196) states rc=3 → "one-line `code-intel MCP unavailable … use grep/Read instead of mcp__* tools.` note", but the R4 code returns *empty* on rc=3 and the suite carries an explicit regression case asserting that note can never return. The report has Round 1/2/3 sections only — the R4 reversal (silence-not-note, R4 finding 1) and the new WMB behavioural case + negative control (f) are documented only in code/test comments, not in the deliverable.
5. **M-4 (claims — stale counts)** — report.md:260 claims `PASS=47 FAIL=0`; live run today: `PASS=49 FAIL=0`. The two R4 cases were added after the count was written and the number was never updated.

**Low**

6. **L-1** — dispatch `_spawn_worker_body` (~:5181): `case "${_ci_rc}"` maps any rc other than 0/3 (e.g. `cat` failing mid-print → 1) to `mode=none reason=arm_unwired`, misattributing a transient failure to "arm unwired".
7. **L-2 (tests-can-fail)** — the disabled-path assertions grep only `--mcp-config`. A regression appending `--strict-mcp-config` *without* `--mcp-config` (which strips the child to zero MCP servers — the most damaging failure mode) passes both the `LEADV2_WORKER_MCP=0` case and the default cases. Today both flags sit behind one `if`, so it's contrived, but the dangerous flag is the unchecked one.
8. **L-3 (census — mapping coverage)** — the six new run-all.sh keys are all `.sh` files; a change to `worker-code-intel-preamble.md` or `config/codex-mcp-servers.toml` alone triggers no suite, so the preamble's ≤25-line/routing-content invariants are only re-checked incidentally.
9. **L-4 (observability asymmetry)** — the `run` path calls `worker_mcp_resolve "${cwd_dir}" "" "${mcp_out_dir}"` in both arms (freepool-coder.sh:468, kimi-coder.sh:360): journal arg empty → `worker_mcp_attached/skipped` goes to stderr with no durable record; only the bg path journals. Machine-greppable attach records are bg-only.

**Verdict rationale**: the code itself is solid — suite independently green, external claims probe-verified, H1/H2 fixes real and regression-guarded. But the deliverable's headline verification claim (changed-scope run-all) is a literal placeholder, which is BLOCKING under the evidence contract; plus the report's Round 3/R4 inconsistency means the document misdescribes the shipped behavior.

---

FINISH CONTRACT: no stash created; no files changed (review-only pass — findings above). **NOT-COMMITTED** (nothing to commit; the diff under review belongs to the author's lane). Test artifact: `/tmp/wmaa-review-suite.log` (49/49 PASS, rc=0).
