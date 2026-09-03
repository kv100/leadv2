# CLAIM-EVIDENCE-GATE-01 — architect prepass (RESUME of lane d784b987)

Lane worktree: `.claude/worktrees/d784b987`, branch `worktree-d784b987`, HEAD `559cf15`.
This is a **resume**: ~85% of the code work already exists uncommitted in that worktree.
The design below is therefore *finish-and-verify*, not build-from-zero.

## 1. Inventory of what already exists (verified in the worktree)

| File | State | Verdict |
|---|---|---|
| `plugins/leadv2/scripts/claude-subsession.sh` | +7 lines inside `SHARED_PROTOCOL_BOILERPLATE` (`EVIDENCE CONTRACT` bullet + `UNVERIFIED:` bullet) | **KEEP** — this is the live preamble source (proof below) |
| `plugins/leadv2/skills/leadv2-subagent-protocol/SKILL.md` | new `## 11. Evidence contract for external-system claims` | **KEEP** — long-form backing; matches contract §1 verbatim in substance |
| `plugins/leadv2/scripts/leadv2-review-run.sh` | `FOUR lenses` → `FIVE lenses`, adds `5. claims-without-evidence` + a `Claims-without-evidence rule:` printf | **KEEP** — placement is inside the `else` (round-1 exhaustive) branch of `_review_build_contract` only; no logic changed |
| `plugins/leadv2/scripts/tests/run-core-offline.sh` | +1 `SUITE_DEFS` entry for the new suite | **KEEP** |
| `plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh` | untracked, 201 lines, cases C1–C6 | **KEEP, needs execution evidence** |

### Live-reader proof (contract §1 "prove the reader")
- `plugins/leadv2/scripts/claude-subsession.sh:234` — `SHARED_PROTOCOL_BOILERPLATE=` is defined.
- `plugins/leadv2/scripts/claude-subsession.sh:303` — `${SHARED_PROTOCOL_BOILERPLATE}` is interpolated into `prefix_content`, which becomes the stable prefix of the `claude -p` system prompt for every subsession.
- `grep -rln "MANDATORY — /leadv2 subagent protocol" plugins/` returns exactly **one** file: `claude-subsession.sh`. There is no second injector to keep in sync. (`leadv2-mission-lint.sh` matches only the weaker string "subagent protocol"; it lints, it does not inject.)
- `SKILL.md` is *referenced by path* from the preamble (`- See full protocol: .claude/skills/...`), so it is documentation, not the live source. Editing SKILL.md alone would NOT have satisfied §1 — the `claude-subsession.sh` edit is the load-bearing one.

### `claude-subsession.sh` — keep or revert?
**KEEP.** It is not incidental churn: it is the only path that puts the contract in front of a running subagent. Reverting it would leave the requirement documented and unenforced.

## 2. Data flow (numbered)

1. Lead dispatches a subagent → `claude-subsession.sh` builds `prefix_content` = role body + `SHARED_PROTOCOL_BOILERPLATE` + skill body (`:297-308`).
2. The two new bullets ride the **stable prefix**, so every subagent in every role sees the evidence contract before its mission text.
3. Subagent writes `<ROLE>.full.md`. External-system claims either carry a probe artifact or the literal token `UNVERIFIED:`.
4. Build closes → `leadv2-review-run.sh` runs. `_review_build_contract` (`:701-711`) branches: `verify_only` → unchanged; else (round 1) → renders the **five-lens** exhaustive mission including the `claims-without-evidence` rule.
5. Reviewer classifies: untagged evidence-free claim that drives a decision → BLOCKING; tagged → MEDIUM ceiling. This flows into the existing findings/verdict machinery untouched.

No new env vars, no new state files, no new runtime code paths. Pure prompt-text change on two surfaces + one test suite.

## 3. Interface contracts

| Surface | Contract | Enforced by |
|---|---|---|
| Subagent preamble | contains literal `EVIDENCE CONTRACT` and literal `UNVERIFIED:` | test case C1 (red-first) |
| Round-1 review mission (rendered) | contains `FIVE lenses` and `claims-without-evidence` | test cases C2 (source) + C6 (rendered artifact) |
| Round 2+ review mission | must NOT contain `claims-without-evidence` | test case C3 |
| Both new text blocks | no `"` and no `` ` `` (codex `--focus` is one shell word) | test case C4 |
| Both edited scripts | `bash -n` clean under bash 5 and `/bin/bash` (3.2) | test case C5 |

## 4. Remaining work — ordered

1. **Run the new suite standalone** and capture raw output:
   `bash plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh`
   Required: `FAIL=0`, `GREEN_PRE_FIX=0`, `COULD_NOT_RUN=0`, exit 0. Any `GREEN-PRE-FIX` line means the case does not actually discriminate pre/post fix — fix the probe, do not relax the assertion.
2. **Prove the red floor is real** — the raw red evidence is the per-case `pre_rc` in the `RED-then-GREEN: <name> (pre_rc=1 -> post_rc=0)` lines. Baseline ref resolves to `merge-base origin/main HEAD` = `559cf15` (lane HEAD), which lacks both strings; the hardcoded `559cf15` fallback only arms after this lane merges. Both are correct as written — no change needed.
3. **Hermeticity audit of the new suite before the full run.** Confirmed clean by inspection: C6 builds `--root` and handoff under two `mktemp -d` trees, stubs resolver/architect/codex/dispatch, and `rm -rf`s both. `leadv2-review-run.sh` writes nothing outside `${ROOT}`/`${HANDOFF}` (grep for `bus-emit|leadv2-bus|ledger|task-journal|phases.d` in that script returns nothing). Re-verify empirically: `git status --short` before and after the standalone run must be identical.
4. **Full runner, both directions:**
   `bash plugins/leadv2/scripts/tests/run-core-offline.sh` and
   `LEADV2_CORE_OFFLINE_REVERSE=1 bash plugins/leadv2/scripts/tests/run-core-offline.sh`.
5. **Lint:** `bash -n` + `shellcheck` on `claude-subsession.sh`, `leadv2-review-run.sh`, `run-core-offline.sh`, `test-claim-evidence-gate.sh`.
6. **Revert the fixture churn** before staging: `git checkout -- docs/handoff/dispatch-c1sig001 docs/handoff/dispatch-c2sig001 docs/handoff/dispatch-nw5sig005 docs/handoff/dispatch-nw9sig009 docs/handoff/dispatch-nwcm0012` (only the `phases.d/*.yaml` paths).
7. **Commit path-scoped** — `git add` exactly the five deliverable paths, never `-A`, never `docs/leadv2/*`.

## 5. Risks and mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | `git commit -a` / `git add -A` sweeps in the live-state churn (`docs/leadv2/bus.jsonl`, `active.yaml`, `*.lock`, `questions`, `open-threads.md`) and the `dispatch-*sig*/phases.d` fixtures, corrupting shared lane state | **CRITICAL** | Stage by explicit path only (step 7). Do **not** `git checkout --` the `docs/leadv2/*` files either — they are live bus/lock state, reverting them can clobber a running lane. Leave untouched, unstaged. |
| R2 | The `phases.d/*.yaml` churn recurs on the next full runner pass, so a later `git status` looks dirty again and someone re-stages it | HIGH | Root cause is **pre-existing and out of scope**: `test-lane-phase-render.sh`, `test-phase-precondition.sh`, `test-phase-record.sh` write real tracked `dispatch-*sig*` fixtures via `leadv2-phase-record.sh`. Log it as a follow-up thread; do not fix it in this lane. Re-run step 6 immediately before `git add`. |
| R3 | Adding 7 lines to `SHARED_PROTOCOL_BOILERPLATE` changes the stable-prefix checksum (`:310`), invalidating the prompt cache for every subsession once | LOW | One-time cost, self-healing on the next spawn. No action; note it in the commit body so the burn spike is not misread as a regression. |
| R4 | `verify_only` (round 2+) accidentally inherits the lens, breaking REVIEW-ROUND1-EXHAUSTIVE-01 | MEDIUM | Already guarded by C3. Verify C3 actually PASSes rather than silently matching an empty `verify_only_block` — if `sed` extracts nothing the `-n` guard fails the case, which is correct; confirm the PASS line appears in output. |
| R5 | A double-quote or backtick sneaks into the lens text and breaks `codex --focus` flattening | MEDIUM | Already guarded by C4 (scoped to added lines only, per its own comment). |
| R6 | The new suite's C6 shells out to the real review engine; if a future refactor makes that engine reach the network, the "offline" runner stops being offline | LOW | All four external bins are stubbed via `LEADV2_*_BIN` env. Keep it that way; do not add a case that omits a stub. |
| R7 | SKILL.md wording drifts from the preamble wording over time | LOW | Accept. C1 asserts the preamble only; SKILL.md is documentation. Do not add a cross-file text-equality test — it would fail on every legitimate reword. |

## 6. Non-goals (explicit — implementing agent must ignore)

- No machine enforcement of the evidence contract (no linter, no gate script, no regex scan of `.full.md`). This lane ships **text contracts only**.
- No new env var, no `LEADV2_*` flag, no config surface.
- No change to `leadv2-dispatch-product-close.sh` (**off_limits**).
- No fix for the pre-existing `phases.d` fixture-mutation defect in the three phase suites (R2) — revert the churn, file the thread, move on.
- No change to the `verify_only` branch of `_review_build_contract`.
- No edit to any `docs/handoff/**` or `docs/leadv2/**` file as a deliverable.
- No backport of the contract into per-repo `.claude/` trees (canonical plugin is the single source; the repos symlink).

## 7. Mandatory constraint checklist

1. **Env var naming** — no new env vars introduced. Existing ones referenced by the suite (`LEADV2_TEST_BASELINE_REF`, `LEADV2_GLM_POLICY_RESOLVER`, `LEADV2_DISPATCH_*_BIN`, `LEADV2_REVIEW_FANOUT`, `LEADV2_CORE_OFFLINE_REVERSE`) all carry the `LEADV2_` prefix. PASS.
2. **File paths** — all five write-set paths verified present in the worktree (four tracked-modified, `test-claim-evidence-gate.sh` untracked-present). PASS.
3. **`claude -p` commands** — none introduced by this lane. `claude-subsession.sh`'s own invocation is untouched (only the boilerplate string constant changed). PASS/N-A.
4. **Concurrent access** — the suite runs inside `mktemp -d` roots; no two steps read+write a shared file. The only shared-file hazard is R1 (`docs/leadv2/*` live state), mitigated by path-scoped staging. PASS.
5. **Config contradiction check** — no env-var semantics changed. PASS.

## acceptance:

```yaml
acceptance:
  - surface: rendered_line
    observable: "A reviewer opening the round-1 review mission file for a fresh task sees a numbered list that reads 'Review this diff through FIVE lenses' with '5. claims-without-evidence' as the last entry, followed by a paragraph beginning 'Claims-without-evidence rule:'."
    authored_at: 2026-08-19T15:54:08Z
  - surface: rendered_line
    observable: "A subagent spawned into any /leadv2 role reads, in its own opening instructions above the mission, a bullet headed 'EVIDENCE CONTRACT' and a following bullet telling it to prefix unproven external-system claims with UNVERIFIED:."
    authored_at: 2026-08-19T15:54:08Z
  - surface: rendered_line
    observable: "A reviewer opening a round-2 (verification-only) review mission sees no mention of claims-without-evidence anywhere in it."
    authored_at: 2026-08-19T15:54:08Z
  - surface: log_line
    observable: "The offline test runner's summary line for the claim-evidence suite reads zero failures, zero green-pre-fix and zero could-not-run, and each new case prints as red against the pre-fix baseline before turning green — visible in both the forward and reverse runner passes."
    authored_at: 2026-08-19T15:54:08Z
  - surface: file_artifact
    observable: "A commit on the lane branch whose changed-file list contains only the two plugin scripts, the skill document, the runner registration and the new test suite — and no handoff or leadv2 state files."
    authored_at: 2026-08-19T15:54:08Z
```

LANE_WRITES: plugins/leadv2/scripts/claude-subsession.sh, plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/skills/leadv2-subagent-protocol/SKILL.md, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh

DELIVERABLE_COMPLETE
