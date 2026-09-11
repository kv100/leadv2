# architect — one review path: the census must reach exactly one owner

TASK_ID: dispatch-75d151fe-architect
Worktree: `.claude/worktrees/9ce00c9d` @ `599275c`, branch `worktree-9ce00c9d`.
Design only. No implementation performed.

---

## 1. Verdict: (B) primary, with a genuine (A) deletion of the JS

The mission framed A and B as exclusive. The evidence says they answer **two different
questions** and the honest answer uses one of each:

| Owner | Retired? | Evidence | Action |
|---|---|---|---|
| `plugins/leadv2/workflows/leadv2-review.js` | **Yes — but not unreachable today.** It is orphaned from the lane, yet still resolvable by name (`meta.name: 'leadv2-review'`, `leadv2-review.js:2`) as a Workflow, i.e. a live *lead-side* second review path. | Zero script/hook call sites (grep §2). `skills/leadv2-review/SKILL.md:102-103` and `WORKFLOW-PATH.md:33-34` **already state it is deleted** — the docs are lying because the file exists. | **Delete (A)** — and migrate, not delete, the three suites' coverage. |
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` (`run_reviewer_arm()`, L1629) | **No.** It is the *only* owner reachable at `LEADV2_REVIEW_ENGINE=0`, which is the mandated production value. | `leadv2-dispatch-product-close.sh:1549` — `if [[ "${LEADV2_REVIEW_ENGINE:-0}" == "1" ]]` calls the engine; the `else` body is today's live review. Deleting it at flag=0 would silently promote the engine to the live path — the mission's own disqualifier. | **Keep (B)** — the *test* is asserting the wrong invariant and gets rewritten. |

So: a **static file census can never legitimately read 1 while the flag is 0**. That part of
`test-review-single-owner-census.sh` is wrong and must be replaced by a *reachability* census
parameterised by the flag. Simultaneously, the JS is a real third owner on a real (lead-invoked)
path and must go — otherwise even the reachability census reads 2 at flag=0.

This is **not** splitting the difference: the rewritten census still fails on every way a second
owner can appear (see §4 falsifiability), and one whole owner file is genuinely deleted.

### Evidence gathered

- `md5 -q` on all three copies of `leadv2-review.js` → `83ac930c352e288cbe7795a9f69ba473` for
  canonical, `~/.claude/workflows/`, and `~/.claude/plugins/cache/leadv2-local/leadv2/0.1.0/workflows/`.
  **Byte-identical confirmed** (the mission's precondition for deleting "both copies"; there are
  in fact three).
- Live (non-test, non-doc) references to `leadv2-review.js`: **zero call sites**. Only comments
  (`leadv2-review-run.sh:399,417` — "ported from"; `leadv2-route-bandit.sh:546`) and docs.
- Engine `leadv2-review-run.sh` fan-out: `run_reviewer_arm()` L241 with arms `codex` / `glm` /
  `kimi` / `sonnet|opus`, plus always-on `_engine_hack_detect_job` (L405) and
  `_engine_verify_job` (L418) on a distinct arm. No bare `claude -p` — all Claude arms go through
  `claude-subsession.sh` (L291, L412, L423).

---

## 2. Coverage migration — the three asserting suites

None of the three is deleted. Each is retargeted at real behaviour.

### 2a. `test-codex-doc-pointer.sh` — retarget + one engine change

Asserts that the Codex adversarial dispatcher prompt names 5 doc surfaces
(`docs/systems-map/TRUTH-TABLE.md`, `docs/BOARD.md`, …) plus a `docs/specs/*.md … possibly stale`
caveat.

**The engine's Codex prompt does not carry the pointer today** — `grep` for `TRUTH-TABLE` /
`BOARD.md` / `ENGINE-REFERENCE` in `leadv2-review-run.sh` and `codex-task.sh` returns nothing. So
retargeting the test alone would turn it red. Required implementation order:

1. Port the doc-pointer block (5 surfaces + staleness caveat) into the engine's codex `--focus`
   string at `leadv2-review-run.sh:247-249`. Additive prompt text only; no control-flow change.
2. Repoint `CANONICAL` at `scripts/leadv2-review-run.sh`.
3. **Drop R3 and R4.** R3 reconstructs a pre-fix state via `git archive HEAD -- …leadv2-review.js`
   — meaningless once the file is gone. R4 asserts 3-copy byte-identity of a file that will not
   exist. Replace R4 with the equivalent invariant that *does* survive: `leadv2-review-run.sh` has
   exactly one copy under `plugins/leadv2/scripts/` and no shadow copy in `~/.claude/` — this is
   the same anti-drift property R4 protected, expressed against the surviving owner.

**Note this is a live-path prompt change.** Per `leadv2-review-run.sh:26-27` the lead/interactive
skill path calls the engine unconditionally, independent of the lane flag. Adding a doc pointer to
the Codex focus string is additive and low-risk, but it is not inert — state it in the handoff.

### 2b. `test-leadv2-review-routing.sh` — rewrite as an engine degradation suite

Current assertions load the JS with a stubbed `agent()` and check labels `codex-adversarial`,
`critic-structural-cross-check`, `critic-full-fallback`, plus prompt-breadth strings
(`do NOT repeat a full line-by-line review`, `cross-module API/data-contract drift`,
`FULL adversarial code review`).

**The engine has no analogue for the narrow-vs-full critic promotion.** Its degradation model is
different: `classify_arm_failure()` (L302) + `next_ok_arm_after()` (L337) rotate to the next OK arm
in the pool; there is no "promote the critic's breadth" concept.

Migration, honestly stated:

| Original assertion | Migrated to |
|---|---|
| normal round dispatches Codex | Engine: `codex` is the `--base-arm` (`resolve_review_pool_call`, L106) and is the first fan-out arm. Assert against the engine. |
| Codex unavailable → do **not** dispatch Codex; run a fallback reviewer instead | Engine: `classify_arm_failure` → `next_ok_arm_after` yields a **distinct** non-codex arm, and the pool degradation is logged. |
| mid-run Codex failure is logged | Engine emits `review_pool_resolve` / arm-failure lines to its stderr logger (L61). Assert the human-visible line. |
| critic prompt breadth (narrow vs full) | **No engine analogue. Coverage delta — recorded, not silently dropped.** Do NOT invent a breadth-promotion feature in the engine to satisfy a test; that is scope creep on the live lead path. Record the delta as a one-line `KNOWN COVERAGE DELTA` comment at the top of the rewritten suite and in `phases.md`. |

Overlap with `test-review-engine-fanout-multiprovider` / `-pool-degrades` is acceptable; the new
suite must still add the *codex-is-base-arm-and-is-skipped-when-unavailable* assertion, which is
this suite's distinct contribution.

### 2c. `test-leadv2-phase8-learn-counter.sh` T7 — retarget `JS_FILE`

T7 extracts `ROOT_RESOLVE_CMD` (the `git-common-dir … || pwd` one-liner) from the JS via a backtick
regex and executes it across main / worktree / unrelated cwds. The same idiom lives in
`leadv2-plan.js`, `leadv2-intake-enrich.js`, `leadv2-learn.js`, `leadv2-causal-critique.js`.

Retarget `JS_FILE` (L34) to `../../workflows/leadv2-plan.js`. **Implementation must verify the
regex still matches** (`_extract_js_resolve_snippet` anchors on a backtick-delimited literal
containing `git-common-dir … || pwd`); if `leadv2-plan.js` stores it differently, fall to
`leadv2-learn.js`, and only if no JS consumer matches may T7 be retired — with the justification
that T6 already exercises the identical one-liner in `leadv2-phase8-close.sh`. Retiring T7 is the
last resort, not the first move.

### 2d. `test-statusline-readable.sh` — dead variable

L28 sets `REAL_REVIEW="${REAL_PLUGIN_DIR}/scripts/leadv2-review.js"` — a path that has never
existed (the file is under `workflows/`, not `scripts/`) and the variable is **never read**.
Delete the line. Zero coverage impact; it exists only to stop a future grep from re-flagging it.

---

## 3. The rewritten census — design

`test-review-single-owner-census.sh` becomes a **reachability census parameterised by
`LEADV2_REVIEW_ENGINE`**, not a file count.

**Invariant asserted:** *for each value of `LEADV2_REVIEW_ENGINE` (0 and 1), exactly one review
orchestration owner is reachable, and every owner file found on disk is accounted for by exactly
one of those two buckets.*

Structure:

1. **Discover** — same grep as today (`^run_reviewer_arm\(\)` | `const reviewers = [` |
   `parallel(reviewers)`) over `plugins/leadv2/scripts` and `plugins/leadv2/workflows`, excluding
   `/tests/`, `.err`, `.md`. This is the *unclassified* owner set.
2. **Classify** against an explicit, documented table:

   | Owner file | Reachable when | Gate proof the test re-verifies |
   |---|---|---|
   | `scripts/leadv2-dispatch-product-close.sh` | `LEADV2_REVIEW_ENGINE=0` | the file contains a branch `[[ "${LEADV2_REVIEW_ENGINE:-0}" == "1" ]]` whose **then**-side invokes `leadv2-review-run.sh` and whose **else**-side is the inline body |
   | `scripts/leadv2-review-run.sh` | `LEADV2_REVIEW_ENGINE=1` (lane) **and** unconditionally on the lead/skill path | product-close's then-branch resolves `_ENGINE_BIN` to it (L1556) |

3. **Assert three things**, all independently able to fail:
   - `flag=0` bucket has exactly 1 member, and it is `leadv2-dispatch-product-close.sh`;
   - `flag=1` bucket has exactly 1 member, and it is `leadv2-review-run.sh`;
   - **the discovered set minus the two buckets is empty** — any owner file not in the table is an
     immediate FAIL with its path printed.

The third clause is what keeps this falsifiable: the table is an allowlist keyed by *path*, so a
new owner file, a resurrected `leadv2-review.js`, or a second `run_reviewer_arm()` in any script
lands in "unclassified" and goes red. It is not "assert the count is ≥1".

4. **Print the census verbatim** before asserting — `owners found:` followed by each path and its
   bucket — so the mission's before/after requirement is satisfied from the test's own output.

The test must **not** execute the lane or the engine. It is a static reachability census; the
"reachable" claim is proved by re-verifying the gate expression's shape, not by running it.

---

## 4. Falsifiability demo (mandatory — the mission requires the RED)

The implementation must demonstrate red, not merely claim it. Prescribed negative control:

1. Create a throwaway owner: a file under `plugins/leadv2/scripts/` (e.g.
   `leadv2-review-shadow.sh.NEGCTL`, named so `run-all.sh` never collects it) containing a
   `run_reviewer_arm() {` definition at column 0.
2. Run the census → it must print the shadow path under `unclassified` and FAIL.
3. Delete the throwaway; re-run → PASS.
4. Capture both outputs verbatim in the handoff.

Second control (cheaper, proves the bucket arithmetic, not just the allowlist): temporarily
neutralise product-close's `LEADV2_REVIEW_ENGINE` gate line **in a `git archive` scratch copy —
never in the worktree** and confirm the flag=0 bucket assertion fails. Optional; the first control
is required.

---

## 5. Files affected

| File | Change |
|---|---|
| `plugins/leadv2/scripts/tests/test-review-single-owner-census.sh` | rewrite per §3 |
| `plugins/leadv2/workflows/leadv2-review.js` | **delete** |
| `plugins/leadv2/scripts/leadv2-review-run.sh` | add doc-pointer text to the codex `--focus` (L247-249) — additive only |
| `plugins/leadv2/scripts/tests/test-codex-doc-pointer.sh` | retarget to the engine; drop R3/R4, add the single-copy invariant |
| `plugins/leadv2/scripts/tests/test-leadv2-review-routing.sh` | rewrite as an engine degradation suite + KNOWN COVERAGE DELTA note |
| `plugins/leadv2/scripts/tests/test-leadv2-phase8-learn-counter.sh` | T7 `JS_FILE` → `leadv2-plan.js` (verify regex) |
| `plugins/leadv2/scripts/tests/test-statusline-readable.sh` | drop dead `REAL_REVIEW` line |
| `plugins/leadv2/docs/phases.md` | replace the "deletion DEFERRED / both copies still exist" paragraph (L302-313) with what is now true |
| `plugins/leadv2/skills/leadv2-review/ref/workflow-review-reference.md` | L4 still names `~/.claude/workflows/leadv2-review.js` as "the maintained script" — repoint at `leadv2-review-run.sh` |
| `plugins/leadv2/scripts/leadv2-route-bandit.sh` | L546 comment names `leadv2-review.js` — cosmetic, update while touching |

**Out-of-repo deletions (not in LANE_WRITES, must still be done and reported):**
`~/.claude/workflows/leadv2-review.js` and
`~/.claude/plugins/cache/leadv2-local/leadv2/0.1.0/workflows/leadv2-review.js`. Both confirmed
byte-identical to canonical. Per the global shared-trees rule the cache is a real copy, not a
symlink, so removing canonical alone leaves the workflow name resolvable from the cache — deleting
canonical without the cache would leave the second review path alive and make the whole task a
no-op on the running system.

---

## 6. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | Deleting `leadv2-review.js` from the plugin cache changes what a *running* session can invoke by name. | It is already documented as deleted (`SKILL.md:102`), the lane never calls it, and `leadv2-review-run.sh` is the documented replacement. Report the cache deletion explicitly; a session restart is the standard remedy per the hooks/cache rule. |
| R2 | Doc-pointer port into the engine's codex prompt is a **live** lead-path change (engine is called unconditionally by the skill). | Additive string only, inside `--focus`. Re-run `test-review-engine-fanout-multiprovider` and `-verify-coverage` to prove the arm still dispatches. |
| R3 | The rewritten routing suite may silently become a duplicate of `-pool-degrades`. | Require the codex-is-base-arm assertion, which `-pool-degrades` does not make. State the coverage delta in-file. |
| R4 | Allowlist-by-path could be "fixed" later by appending a path instead of removing an owner. | The table carries a comment: *adding a row is a design decision, not a test fix.* The gate-shape re-verification means a row cannot be added for a file that has no flag gate. |
| R5 | T7's regex may not match `leadv2-plan.js`. | §2c gives an ordered fallback chain ending in an explicitly-justified retirement, never a silent delete. |
| R6 | Baseline drift — a suite already red at `599275c` gets attributed to this lane. | Take the `bash tests/run-all.sh --scope all` baseline **first, in this worktree, before any edit**, save it, and diff result sets. Non-negotiable ordering. |
| R7 | Review-pool consumer fix (`717b16f`) regression. | This design moves **no** review logic out of product-close — the inline body and `_pc_write_unreviewed` (L229-233) are untouched. The three pool suites are unaffected by construction; still run them. Author exclusion (`test-review-pool-never-empty.sh` T7) likewise untouched. |
| R8 | Concurrent access: another lane editing `plugins/leadv2/scripts/` in the shared tree. | Re-diff every file immediately before `git add` (global rule). Never `git reset --hard` / `clean` / `stash`. |

## 7. Constraint checklist

1. **Env var naming** — only `LEADV2_REVIEW_ENGINE`, `LEADV2_REVIEW_RUN_BIN`, `LEADV2_REVIEW_FANOUT`
   are touched; all `LEADV2_*`. No new env var introduced. No `LEAD_V2_*` drift found.
2. **File paths** — every path in §5 verified present on disk at `599275c` except the negative-control
   file (`(to-create)`, throwaway).
3. **`claude -p`** — none introduced. All Claude arms route through `claude-subsession.sh`
   (`leadv2-review-run.sh:291,412,423`), consistent with the mission's "no bare `claude -p`".
4. **Concurrent access** — §R8. The engine writes `review-gate.md` via `.tmp`+`mv`; the lane's EXIT
   trap is absent-only (documented `leadv2-review-run.sh:4-9`). Unchanged by this design.
5. **Config contradiction** — `LEADV2_REVIEW_ENGINE` semantics ("gates whether the LANE calls the
   engine"; the lead/skill path is ungated) are consistent across `leadv2-review-run.sh:24-27`,
   `leadv2-workflow-bypass-guard.sh:42-43`, `SKILL.md:99` and `WORKFLOW-PATH.md:6`. The census's
   two-bucket model encodes exactly this. **No contradiction.** Flag stays `0`.

## 8. Non-goals

- Flipping `LEADV2_REVIEW_ENGINE` to `1` anywhere (gated on `SD-ONEPATH-CODEX-LIVE-PROOF-01` + 3-repo soak).
- Removing or refactoring product-close's inline `run_reviewer_arm()` body or its `_pc_write_unreviewed` path.
- Adding narrow/full critic-breadth promotion to the engine to satisfy the old routing test.
- Changing the engine's fan-out, verifier, hack-detect, or pool-resolution logic beyond the doc-pointer string.
- Touching `~/Projects/leadv2` main working tree, or creating any real copy of a plugin file inside a consuming repo.
- De-duplicating `.claude/scripts/tests/` (separate open thread).

---

acceptance:
- surface: rendered_line
  observable: "Running the single-owner census prints an owners block listing exactly two accounted-for files — leadv2-dispatch-product-close.sh under the flag-0 bucket and leadv2-review-run.sh under the flag-1 bucket, nothing under unclassified — followed by a final line reading `review single-owner census: PASS=3 FAIL=0`."
  authored_at: 2026-08-07T01:32:42Z
- surface: rendered_line
  observable: "With a throwaway file defining run_reviewer_arm() placed under plugins/leadv2/scripts/, the same census output lists that file's path under `unclassified` and ends with a FAIL line naming it; after the file is removed the output returns to PASS=3 FAIL=0."
  authored_at: 2026-08-07T01:32:42Z
- surface: file_artifact
  observable: "leadv2-review.js is absent from plugins/leadv2/workflows/, from ~/.claude/workflows/, and from the leadv2 plugin cache; the leadv2-review skill's SKILL.md statement that the file is deleted is now true."
  authored_at: 2026-08-07T01:32:42Z
- surface: rendered_line
  observable: "The full-sweep run of all suites shows the same set of failing suite names as the baseline sweep taken at 599275c before any edit — no suite name appears in the after-set that was passing in the before-set — and the nine named suites all report FAIL=0."
  authored_at: 2026-08-07T01:32:42Z

LANE_WRITES: plugins/leadv2/scripts/tests/test-review-single-owner-census.sh, plugins/leadv2/scripts/tests/test-codex-doc-pointer.sh, plugins/leadv2/scripts/tests/test-leadv2-review-routing.sh, plugins/leadv2/scripts/tests/test-leadv2-phase8-learn-counter.sh, plugins/leadv2/scripts/tests/test-statusline-readable.sh, plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/leadv2-route-bandit.sh, plugins/leadv2/workflows/leadv2-review.js, plugins/leadv2/docs/phases.md, plugins/leadv2/skills/leadv2-review/ref/workflow-review-reference.md

DELIVERABLE_COMPLETE
