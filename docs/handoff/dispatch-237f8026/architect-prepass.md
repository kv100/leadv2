# ONE-PATH-EVERYWHERE-01 — architect prepass (scoped implementation design)

TASK_ID: dispatch-237f8026-architect · ROLE: architect · repo: `~/Projects/leadv2` (plugin source)

---

## 0. BLOCKING PREMISE — the binding design doc does not exist on disk

The mission's first instruction is **"Read `docs/handoff/one-review-path-2026-08-06/design.md` in
full before writing anything… it is the approved design"**, and it treats §3.1/§3.3/§3.4/§4/§5 and
the FOUNDER CONSTRAINTS section as binding.

Evidence:

```
$ ls docs/handoff/ | grep -i one-review     → (no output)
$ find . -name design.md -path "*one-review*"  → (no output)
$ ls docs/handoff | grep -i 2026-08-06         → (no output)
```

**The file is absent from the repo.** No `one-review-path-*` directory exists anywhere under
`docs/handoff/`. Consequently every `§N` reference in the mission is unresolvable, including the
deletion *order* mandated by §3.3 and the test list in §5.

Decision taken for this prepass: **do not block with nothing delivered.** The mission body itself
restates enough of §3.1/§3.2/§3.3 to design against, so this document is built from the mission
text plus the live code. Three places where the mission text alone is genuinely ambiguous are
raised as `D1`–`D3` below and must be answered before the corresponding line of code is written.

`decisions[] source: architect(self-check)` →
**D0 (CRITICAL): `docs/handoff/one-review-path-2026-08-06/design.md` is missing. Either the lead
supplies it before Step 1, or the lead confirms in writing that the mission body supersedes it.
Do not let an implementer infer §3.3's deletion order from prose.**

---

## 1. Layers affected

| Layer | File | Change |
|---|---|---|
| engine (new) | `plugins/leadv2/scripts/leadv2-review-run.sh` | **create** — canonical review container |
| engine lib (new) | `plugins/leadv2/scripts/lib/leadv2-review-pool.sh` | **create** — pool resolution, lifted verbatim |
| lane | `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | body `1447‑1667` → one engine call; `resolve_review_pool_call()` (`230‑280`) moves to the lib |
| lead / interactive | `plugins/leadv2/skills/leadv2-review/SKILL.md`, `WORKFLOW-PATH.md` | rewrite to call the engine over Bash |
| hook | `plugins/leadv2/hooks/leadv2-workflow-bypass-guard.sh` | predicate + matcher change |
| hook | `plugins/leadv2/hooks/leadv2-workflow-sentinel-touch.sh` | drop the `review` arm, **keep `plan`** |
| hook config | `plugins/leadv2/hooks/hooks.json` | add a `PreToolUse(Bash)` matcher for the guard |
| dead code | `plugins/leadv2/workflows/leadv2-review.js` + `~/.claude/workflows/leadv2-review.js` | delete both |
| dead env | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` `2061‑2068`, `3242` | delete `LEADV2_DISPATCH_REVIEWER_ARMS` |
| tests | `plugins/leadv2/scripts/tests/test-review-engine-*.sh`, `test-bypass-guard-lane-review.sh` | **create** |

Unchanged and explicitly preserved: `lib/leadv2-glm-policy-resolve.py`,
`lib/leadv2-review-signals.sh`, author-exclusion, quota bands (GLM 90, Codex 90/95, Claude 95).

---

## 2. Step 0 — the Codex-capability gate (design spec, not run here)

The prepass does not run Step 0; it specifies what counts as evidence so the implementer cannot
substitute an assertion for a probe.

| Probe | How | Evidence that counts |
|---|---|---|
| plain bash script invocable | from a live `leadv2-codex-session-runner.sh` session, run `bash plugins/leadv2/scripts/leadv2-review-run.sh --selftest` | the script's own stdout marker captured in the session transcript |
| Agent tool present | ask the session to list its tools; attempt one spawn | tool-list output + the spawn's success/refusal text |
| Workflow tool present | same | same |
| in-session MCP | attempt one `search_graph` | returned rows or the exact error |
| cwd | `pwd` inside the session | literal path |
| write scope under `docs/handoff/<task>/` | `touch docs/handoff/<task>/.codex-probe` then `ls -l` | the `ls -l` line, or the sandbox denial text |

All six land in `docs/handoff/one-review-path-2026-08-06/codex-capability.md`. **If row 1 fails →
return BLOCKED and write nothing else.** The whole design assumes the script is the container; a
failed row 1 invalidates it and the founder must hear that before code exists, not after.

---

## 3. The engine — `leadv2-review-run.sh`

### 3.1 Interface contract

```
leadv2-review-run.sh \
  --task <TASK> --root <ROOT> --handoff <HANDOFF_DIR> \
  --diff <diff_file> --author <arm> \
  [--founder-task-id <id>] [--fanout <N>] [--writes-csv <csv>] [--selftest]
```

| Field | Value |
|---|---|
| stdout | one-line-per-arm progress; never the verdict contract |
| writes | `<HANDOFF>/review-gate.md`, `<HANDOFF>/review-findings.json`, `<HANDOFF>/review-<arm>.md`/`.err`, `<HANDOFF>/review-mission.md` |
| exit 0 | PASS / PASS_WITH_NITS / dedup |
| exit 6 | blocked (`provider_error`, `empty_response`, `no_verdict_marker`, `review_body_lost`) |
| exit 7 | verdict FAIL |
| exit 9 | unreviewed (`all_arms_unavailable`) |

**Exit codes are a hard contract** — they are exactly today's lane codes, because the lane maps
each to `_dl_note` + `_stamp_review_terminal` and the supervisor reads those. The engine must not
invent a new code.

`emit` is injected, not assumed: the engine defines its own `emit()` writing through
`${LEADV2_JOURNAL_BIN}` and degrading to a no-op when unset, so it works identically inside the
lane (journal live) and from an interactive lead (journal may be absent).

### 3.2 Data flow (numbered)

1. Resolve pool → `leadv2_review_resolve_pool()` from the new lib: signals from
   `leadv2-review-signals.sh` (fail-closed), then `leadv2-glm-policy-resolve.py --job review
   --base-arm codex --review-pool --author <AUTHOR>`. Emits `review_signals`. **Verbatim lift** —
   no behavioural edit, no hardcoded arm added or removed.
2. Assert `reviewer != AUTHOR` (defence-in-depth, kept from `1469`).
3. Compute `diff_hash`; check the review ledger; dedup → exit 0.
4. **Fan-out**: `N = min(${LEADV2_REVIEW_FANOUT:-3}, count(:ok: arms in pool))`. Take the first N
   `:ok:` arms in the resolver's own order. `N==0` → `status: unreviewed / all_arms_unavailable`,
   exit 9. `N>=1` always proceeds — **degradation, never fail-closed** (this is the m3-market /
   Codex-disabled case).
5. Run each arm through `run_reviewer_arm()` (moved verbatim, incl. the codex/glm/kimi/subsession
   branches, the omp second channel, and `materialize_subsession_body`). Arms run sequentially in
   v1; see R3 for why parallel is deferred.
6. Per-arm post-guard: the `review_body_lost` check (`1624‑1638`) runs **per arm**. A lost body
   disqualifies that arm from the fan-out; it blocks the whole gate only when it is the last
   surviving arm.
7. **Hack-detect pass**, always on, one cheap arm (lowest-cost `:ok:` arm ≠ AUTHOR), separate
   prompt, findings tagged `source: hack-detect`.
8. **Refutation**: each finding is verified by an arm chosen round-robin from
   `pool \ {raising_arm, AUTHOR}`. If that set is empty the finding is emitted with
   `verified: unverified` — it still counts toward the verdict, it is simply not corroborated.
9. **Synthesis**: dedup findings by `(severity, file, normalized-title)`; verdict = FAIL if any
   surviving `critical`/`high` is not `REFUTED`; else PASS_WITH_NITS if any finding; else PASS.
10. Write `review-gate.md` then `review-findings.json`, then `record-review` in the ledger, then
    exit with the mapped code.

### 3.3 `review-gate.md` — existing contract + additive lines

```
status: pass|fail|blocked|unreviewed
reviewer: <primary arm>            # existing
diff: <hash8>                      # existing
critical: N / high: N / medium: N / low: N   # existing, fail path
reason: <named reason>             # existing, blocked/unreviewed paths
arms: codex,glm,opus               # ADDITIVE
verified: 4/6                      # ADDITIVE (findings corroborated / total)
review_verdict: FAIL               # ADDITIVE — see D2
```

Parsers today read `status:` — additive lines are backward-compatible.

### 3.4 `review-findings.json` — new artifact

```json
{
  "schema": 1,
  "task": "237f8026",
  "diff_hash": "…",
  "author": "sonnet",
  "pool": "codex:ok:,glm:ok:,opus:ok:",
  "arms": [{"arm":"codex","rc":0,"verdict":"FAIL","source":"stream","bytes":4211}],
  "findings": [{
    "id": "f1", "severity": "critical", "title": "…", "file": "…", "line": 12,
    "raised_by": "codex", "verified_by": "glm",
    "verification": "CONFIRMED|REFUTED|unverified", "rationale": "…",
    "source": "review|hack-detect"
  }],
  "counts": {"critical":1,"high":0,"medium":2,"low":0},
  "verdict": "FAIL"
}
```

Invariant enforced in code and asserted by test: **`verified_by != raised_by`** and
`verified_by != author`, for every finding whose `verification != "unverified"`.

---

## 4. Step 2 — converging the two entry points

### 4.1 Lane

`leadv2-dispatch-product-close.sh:1447‑1667` collapses to:

```
if [[ "${REVIEW_ON}" != 1 ]]; then … exit 0; fi
_PC_REVIEW_ENTERED=1
bash "${SCRIPT_DIR}/leadv2-review-run.sh" --task "${TASK}" --root "${ROOT}" \
     --handoff "${HANDOFF}" --diff "${diff_file}" --author "${AUTHOR}" \
     --writes-csv "${WRITES_CSV}" --founder-task-id "${FOUNDER_TASK_ID}"
_rev_rc=$?
case ${_rev_rc} in
  0) _dl_note landed review_verdict_pass …; _stamp_review_terminal pass ;;
  6) _dl_note dead …;                        _stamp_review_terminal blocked ;;
  7) …                                        _stamp_review_terminal fail ;;
  9) …                                        _stamp_review_terminal unreviewed ;;
esac
```

Preserved exactly as the mission requires: the lane's process model, the `_pc_exit_handler` EXIT
trap, `_stamp_review_terminal`, and the `review_crashed` fallback. The trap is already guarded by
`! -f "${HANDOFF}/review-gate.md"` (line 154), so an engine-written gate is never clobbered — this
was verified, not assumed.

Gated by `LEADV2_REVIEW_ENGINE`: `!= 1` → the current inline body runs unchanged. **Both paths
coexist in the tree for this task**; the inline body is deleted only in the follow-up that flips
the flag on. This is what makes the rollout reversible per repo.

### 4.2 Lead / interactive

`skills/leadv2-review/SKILL.md` + `WORKFLOW-PATH.md` are rewritten so the review phase is a single
Bash call to the engine with `--author` = the build arm. Every instruction to call
`Workflow(name=leadv2-review)` or to spawn a `critic` Agent is removed. `WORKFLOW-PATH.md` is
either deleted or reduced to a tombstone pointing at the engine — **D1**.

### 4.3 Bypass guard

- Predicate: **was** `-f docs/handoff/<task>/.workflow-called-<phase>`; **becomes** `review-gate.md
  exists AND a verdict parses out of it`. Only the `review` phase changes; `plan` keeps the
  sentinel until §3.4 is done, so `leadv2-workflow-sentinel-touch.sh` keeps its `plan` branch and
  loses only `review`.
- Matcher: currently `PreToolUse(Agent)` filtered on `subagent_type ∈ {architect,critic,
  security-auditor}`. Add a `PreToolUse(Bash)` matcher in `hooks.json` that denies *ad-hoc*
  reviewer launches (`claude-subsession.sh --role critic`, `codex-task.sh adversarial-review`)
  while explicitly allow-listing `leadv2-review-run.sh` and the dispatch scripts — those **are**
  the one path. Fail-open on any parse error, as today.
- Kill-switch `LEADV2_WORKFLOW_GUARD=0` and the supervisor-session bypass stay.

---

## 5. Step 3 — deletions

Order (mission-stated; §3.3's exact order is unverifiable — see D0):

1. `plugins/leadv2/workflows/leadv2-review.js`
2. `~/.claude/workflows/leadv2-review.js` — **outside the repo**, not in LANE_WRITES, a manual
   `rm` the implementer must perform and evidence with `ls`. Deleting only one leaves the other
   live; both must go in the same step.
3. The sentinel branch in `leadv2-workflow-bypass-guard.sh` (review only).
4. The `.workflow-called-review` sentinel write in `leadv2-workflow-sentinel-touch.sh`.
5. `LEADV2_DISPATCH_REVIEWER_ARMS` — `leadv2-dispatch-code.sh:2061‑2068` and the dead-comment at
   `3242`. It is already documented in-tree as vestigial.

Before 1–2: grep for registration of the workflow name (plugin manifest / skills index). The
`leadv2:leadv2-review` skill is advertised in the session skill list; if its registration survives
the file deletion, invoking it becomes a hard error instead of a redirect.

---

## 6. Risks

| # | Risk | Mitigation |
|---|---|---|
| **C1** | **Fan-out collision on the shared handoff dir.** Every `opus`/`sonnet` arm calls `claude-subsession.sh --task-id "dispatch-${TASK}-review"`, and `resolve_review_artifact`/`materialize_subsession_body` read `docs/handoff/dispatch-<task>-review/critic.full.md`. Two Claude-family arms in one fan-out overwrite each other's deliverable and the freshness gate (`-nt REVIEW_STAMP`) passes for both — arm B's body is silently attributed to arm A. | Key the subsession per arm: `--task-id "dispatch-${TASK}-review-${arm}"`, and make artifact resolution take the arm as a parameter. **Non-optional; a test must assert two Claude arms produce two distinct artifact paths.** |
| **C2** | Author-exclusion regression when the pool is lifted into a lib. | The lib must ship with the `reviewer == AUTHOR` assertion inline; test: author=codex ⇒ codex absent from every arm slot and every `verified_by`. |
| R3 | Parallel arms multiply the C1 surface, the ledger race, and quota burn. | v1 runs arms **sequentially**. Parallelism is a follow-up with its own review. |
| R4 | Dedup ledger now sees N arms per diff hash. | `record-review` is called **once**, after synthesis, with the primary arm — not per arm. |
| R5 | Both the inline lane body and the engine exist while the flag is 0; they will drift. | Flag-flip follow-up deletes the inline body. Record it in `docs/leadv2/open-threads.md` the same turn. |
| R6 | m3-market has Codex disabled → resolver returns a pool without codex. | Step 3.2/4 degrade path; explicit test. Never `exit 9` while ≥1 `:ok:` arm exists. |
| R7 | Interactive lead runs the engine with no journal → `emit` undefined. | `emit()` degrades to no-op when `LEADV2_JOURNAL_BIN` is unset. |
| R8 | `claude -p` flag hygiene. | The engine never calls `claude -p` directly; it goes through `claude-subsession.sh`, which supplies `--output-format stream-json` (337), `--max-turns` (343), `--permission-mode acceptEdits` (344). Note `acceptEdits`, **not** `bypassPermissions` — flagged, not changed; changing it is out of scope. |
| R9 | Guard widened to Bash could deny the engine itself → total review deadlock. | Allow-list `leadv2-review-run.sh` first, deny second; test both directions. |

### Self-check (mandatory checklist)

1. **Env naming** — `LEADV2_REVIEW_ENGINE`, `LEADV2_REVIEW_FANOUT` follow the `LEADV2_*`
   convention; no `LEAD_V2_*` drift. ✔
2. **Paths** — every path in §1 verified on disk; the four new files are marked create. The one
   exception is `docs/handoff/one-review-path-2026-08-06/design.md`, which the mission asserts
   exists and does not → **D0**.
3. **`claude -p` flags** — see R8.
4. **Concurrent access** — `review-gate.md` (engine vs EXIT trap: safe, `! -f` guard);
   `docs/handoff/dispatch-<task>-review/critic.full.md` (arm vs arm: **unsafe → C1**);
   the review ledger (**R4**).
5. **Config contradiction** — `LEADV2_DISPATCH_REVIEWER_ARMS` is being deleted, not re-used;
   `LEADV2_REVIEW_FAMILY_GATE` lives only in the workflow being deleted and dies with it.

---

## 7. Tests — each must FAIL against pre-fix code

| Test | Fails today because |
|---|---|
| `test-bypass-guard-lane-review.sh` | the guard only knows the `.workflow-called-review` sentinel; a lane review is invisible to it |
| `test-review-engine-fanout-multiprovider.sh` | no engine exists; asserts ≥2 distinct provider families across arms, not three Claudes |
| `test-review-engine-verifier-not-raiser.sh` | no refutation pass exists; asserts `verified_by != raised_by` for every finding |
| `test-review-engine-pool-degrade.sh` | asserts that with Codex unavailable the engine still reviews (exit ≠ 9) with a smaller `arms:` list |
| `test-review-engine-contract.sh` | asserts `review-gate.md` keeps its existing keys **and** gains `arms:`/`verified:`, and that `review-findings.json` validates |
| `test-review-engine-artifact-isolation.sh` | **C1** — two Claude-family arms must write two distinct artifact paths |

Harness: same convention as the 129 existing `plugins/leadv2/scripts/tests/*.sh`. Full suite runs
and its real output is reported — counts, not a claim.

---

## 8. Open decisions (answer before the corresponding code)

- **D0 (CRITICAL)** — the binding design doc is missing. Supply it, or confirm the mission body
  supersedes it.
- **D1** — `WORKFLOW-PATH.md`: delete, or keep as a tombstone redirecting to the engine?
- **D2** — the mission asks the guard to parse `REVIEW_VERDICT:` out of `review-gate.md`, but that
  file's contract is `status:`/`critical:` — `REVIEW_VERDICT:` lives in the raw reviewer output.
  Proposed: the engine additively writes `review_verdict: <V>` and the guard accepts either that
  line or a terminal `status:` value. Confirm.
- **D3** — widening the guard to Bash: confirm the intent is *deny ad-hoc reviewer launches,
  allow-list the dispatch/engine scripts* (this design's reading), not *deny the dispatch scripts*.

---

## 9. Out of scope — the implementing agent must not touch

- Plan (§3.4) and Diagnose consolidation, in any form.
- Enabling `LEADV2_REVIEW_ENGINE` anywhere. It stays `0` in every repo at the end of this task.
- Rollout to persona-engine / respiro-ios / m3-market.
- Deleting the inline lane body (follow-up, after the flag flips).
- The `.claude/scripts/tests/` duplicate-tree cleanup (separate open thread).
- Changing quota bands, the GLM policy resolver, `leadv2-review-signals.sh`, or the
  `claude-subsession.sh` permission mode.
- Any real copy of a plugin-owned file inside a consuming project.
- `git reset --hard`, `git clean`, `git stash`.

---

acceptance:
  - surface: file_artifact
    observable: "`docs/handoff/one-review-path-2026-08-06/codex-capability.md` opens with six answered rows — bash-script invocable, Agent tool, Workflow tool, in-session MCP, working directory, handoff write scope — each followed by the verbatim session output it was read from."
    authored_at: 2026-08-06T00:00:00Z
  - surface: file_artifact
    observable: "After a lane review with the engine on, `docs/handoff/dispatch-<task>/review-gate.md` shows its usual `status:` and `reviewer:` lines plus two new lines naming the arms that ran and how many findings were corroborated, e.g. `arms: codex,glm,opus` and `verified: 4/6`."
    authored_at: 2026-08-06T00:00:00Z
  - surface: file_artifact
    observable: "`docs/handoff/dispatch-<task>/review-findings.json` lists each finding with the arm that raised it and a different arm that checked it — no finding shows the same arm in both places, and none shows the author."
    authored_at: 2026-08-06T00:00:00Z
  - surface: log_line
    observable: "In a repo where Codex is disabled, the review journal line for the task reports a smaller arm list and a normal verdict rather than `status=unreviewed reason=all_arms_unavailable`."
    authored_at: 2026-08-06T00:00:00Z
  - surface: file_artifact
    observable: "`git status` after Step 3 shows both `plugins/leadv2/workflows/leadv2-review.js` and `~/.claude/workflows/leadv2-review.js` gone, and a grep for `LEADV2_DISPATCH_REVIEWER_ARMS` and `.workflow-called-review` across the plugin returns nothing."
    authored_at: 2026-08-06T00:00:00Z
  - surface: rendered_line
    observable: "The full test-suite run prints its own pass/fail totals in the terminal, with the six new review-engine tests named and passing, and the same six shown failing when run against the pre-change commit."
    authored_at: 2026-08-06T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/lib/leadv2-review-pool.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/skills/leadv2-review/SKILL.md, plugins/leadv2/skills/leadv2-review/WORKFLOW-PATH.md, plugins/leadv2/hooks/leadv2-workflow-bypass-guard.sh, plugins/leadv2/hooks/leadv2-workflow-sentinel-touch.sh, plugins/leadv2/hooks/hooks.json, plugins/leadv2/workflows/leadv2-review.js, plugins/leadv2/scripts/tests/test-review-engine-*.sh, plugins/leadv2/scripts/tests/test-bypass-guard-lane-review.sh

DELIVERABLE_COMPLETE
