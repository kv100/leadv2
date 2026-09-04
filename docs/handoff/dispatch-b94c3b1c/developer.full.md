verdict: REVISE
next_action: review_round_2

# FABLE-THINK-TIER-01 — developer round 8 (fix round)

Judge-r7 (`docs/handoff/FABLE-THINK-TIER-01/judge-r7.md` on the lane) returned `VERDICT: FIX-ROUND`
with 2 of 4 items resolved (2: carrier map, 3: PyYAML-less fail-closed — mutation-proven, untouched
this round). Two items were still open: item 1 (kill switch dead on the JS channel, with a vacuous
dispatch-side negative control) and item 4 (`report.md` never updated in R7).

## Starting state

The lane's previous R8 attempt ended its turn on a background wait at 92 turns without writing a
report, but its code work was already committed as `fe5bef0f` ("wip: R8 partial"). I merged `main`
first (`9b2533a5`, clean auto-merge — pulled in `leadv2-brain-record.sh` and unrelated handoff docs,
left untouched), then read and verified that WIP rather than re-doing it.

## Item 1 — kill switch on the JS channel — verified REFUTED (already fixed in fe5bef0f)

Root cause (judge-r7 §1a): the four THINK workflows (`leadv2-diverge.js`, `leadv2-diagnose.js`,
`leadv2-learn.js`, `leadv2-po-feedback-loop.js`) read `process.env.LEADV2_THINK_MODEL` as an
outright override, populated at **install time** into `.claude/settings.json`. A workflow launched
directly from the lead's own session (no `leadv2-dispatch-code.sh` in the path) never re-resolved
it, so flipping `model-capability.yaml`'s `fable.unavailable` to `true` changed nothing until the
next install.

Fix already in `fe5bef0f`: each of the four workflows now re-resolves through
`leadv2-router.sh think-model` at RUN time via a sentinel-bracketed block
(`// FABLE-THINK-TIER-01 R8 think-model-resolve:start` ... `:end`). Confirmed via the
`workflow-authoring` skill this round that the Workflow-tool JS sandbox has "No filesystem or
Node.js API access" — `agent()` is the only execution primitive available, which is why the fix
shells out via a spawned subagent rather than `child_process` directly (not available in-sandbox).
`a.model` (explicit caller override) still wins outright and skips the resolver entirely.

**Child-side runtime probe, re-run fresh this round (the brief's own acceptance test):**
```
$ T=$(mktemp -d); printf 'fable:\n  unavailable: true\n' > "$T/cap.yaml"
$ LEADV2_THINK_MODEL=fable LEADV2_MODEL_CAPABILITY_YAML="$T/cap.yaml" \
    bash plugins/leadv2/scripts/leadv2-router.sh think-model
opus
$ # real sentinel block extracted from leadv2-diverge.js, evaluated with node
$ # (agent() mocked to shell to the REAL router, same substitution the suite uses)
CHILD THINK_MODEL=opus
```
Router `opus`, child `opus` — matches all four workflows via the suite's new cases 1f/1g/1h
(`PASS=55 FAIL=0`, see report.md for the full paste).

**Spelling-independent negative control (judge-r7 §1c), re-proven fresh in a mktemp FULL copy**
(`plugins/` incl. `scripts/lib/`, plus `tests/`), unmutated baseline shown green first:
```
$ M=$(mktemp -d); cp -R plugins "$M"/; cp -R tests "$M"/
$ LEADV2_SUITE_LOCK_DISABLE=1 bash "$M/plugins/leadv2/scripts/tests/test-fable-think-tier.sh" | grep -E "^FAIL|PASS="
PASS=55 FAIL=0
$ # mutate: wrap the resolver call with the single-bracket `if [ -z "${LEADV2_THINK_MODEL:-}" ]; then ... fi`
$ #         (the exact respelling R7's grep-only defence missed)
$ LEADV2_SUITE_LOCK_DISABLE=1 bash "$M/plugins/leadv2/scripts/tests/test-fable-think-tier.sh" | grep -E "^FAIL|PASS="
FAIL: dispatch export path DEAD/LEAKY: spawned child LEADV2_THINK_MODEL='fable' (expected 'opus' ...)
PASS=54 FAIL=1
```
`fe5bef0f` widened the suite's extraction window (`blk_end` now anchors on the `LEADV2_TRACE`
sourcing line instead of the export line) so case 1e's runtime region swallows any enclosing
conditional around the resolver call, in any spelling. This is now spelling-independent, closing
judge-r7's exact finding.

No further code changes were needed for item 1 — I verified the committed fix rather than
re-implementing it. `git diff main..HEAD` for the four workflow .js files and the two shell files
matches exactly the diff already present in `fe5bef0f`; I made no additional code edits.

## Item 4 — `report.md` findings sections — fixed this round

`report.md` had not been touched since R6 (`grep -c '## R7 findings'` was 0 before this round,
matching judge-r7's finding). Wrote:
- `## R7 findings` — REAL/REFUTED table transcribed from `judge-r7.md`, one row per item.
- `## R8 findings` — item 1's fresh probes (above), item 4's own closure note, the falsifiable
  gate verdict, `bash -n` self-check, and the real `run-all --scope changed` tail.

### `run-all --scope changed` tail

Hit the same stale-lock issue judge-r7 warned about: the lane's own core-offline lock
(`/tmp/leadv2-core-offline--...-FABLE-THINK-TIER-01.lock`) was held by `pid=73299`, confirmed dead
(`kill -0 73299` → no such process). Cleared it, then ran with `timeout 1800` — machine load average
was ~27-37 (many concurrent lanes' test suites running simultaneously), which is why a first
`timeout 900` attempt hit `RC=124` mid-shard even with the lock cleared (genuinely slow, not
hung).

```
[RUN]  .../plugins/leadv2/scripts/tests/test-fable-think-tier.sh
PASS=55 FAIL=0
[PASS] .../plugins/leadv2/scripts/tests/test-fable-think-tier.sh
  Failures (blocking):
    - plugins/leadv2/scripts/tests/run-core-offline.sh
    - tests/test-status-surface-bash32.sh
run-all: 3 passed, 2 failed, scope=changed
RC=1
```

This lane's own suite is green (`PASS=55 FAIL=0`, `[PASS]` in the top-level listing). The 2 failing
top-level suites are pre-existing and unrelated to this round's diff: `run-core-offline.sh`'s
internal failures are dispatch-mission-chain cases, `reason=shared_tree` refusals, park-queue
signature cases, `shellcheck: leadv2-review-run.sh`, and golden-fixture cases — none reference
`think`, `fable`, `router`, or `THINK_MODEL`. `test-status-surface-bash32.sh`'s single failure is a
numeric-count mismatch (`min=31 full=30`) in the SwiftBar renderer, also unrelated. Left untouched
per CLAUDE.md ("never weaken a fixture to get green... an environment-sensitive failure is a
finding, not a test bug") and consistent with this repo's own memory record of pre-existing
`run-all` reds measured across other lanes.

## Falsifiable gate (leadv2-suite-falsifiable.sh, cwd = lane root)

```
$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-fable-think-tier.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=69
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

## Self-check falsification set

```
$ bash -n plugins/leadv2/scripts/leadv2-router.sh plugins/leadv2/scripts/lib/leadv2-think-model.sh \
    plugins/leadv2/scripts/tests/test-fable-think-tier.sh plugins/leadv2/scripts/leadv2-dispatch-code.sh
OK (all four, no red baseline to show — no python files touched)
```
No `.py` files were touched this round (or in the wip R8 commit I verified). The changed-scope
runner's tail is above (`run-all: 3 passed, 2 failed, scope=changed`; this lane's own suite green).

## Concurrency hazard encountered

Mid-session, `git status` showed uncommitted, unattributed edits to `plugins/leadv2/workflows/
leadv2-audit.js`, `leadv2-diverge.js`, `leadv2-po-feedback-loop.js`, and `tests/run-all.sh`, tagged
`FABLE-THINK-TIER-01 R9` in their diff comments — a concurrent session (the task-anchor's own active
list shows `FABLE-THINK-TIER-01: phase=build` running elsewhere) is already mid-flight on further
work in this SAME worktree. Per the lane-hazard playbook (pathspec-commit only your own files, never
a blanket `git add -A`), I committed **only** `docs/handoff/FABLE-THINK-TIER-01/report.md`
(`c8041393`) and left every other dirty path — including all of `docs/leadv2/`, `LEAD_V2_STATE.md`,
the `phases.d/` files, and the other session's R9 workflow edits — completely untouched. Nothing I
did depended on or altered that concurrent work; my report.md diff is purely additive (137 insertions,
0 deletions, `git diff` confirmed clean immediately before staging).

## Commits this round

- `9b2533a5` — merge `origin/main` into `worktree-FABLE-THINK-TIER-01` (clean, ff-able content).
- `c8041393` — `docs/handoff/FABLE-THINK-TIER-01/report.md` only: `## R7 findings` + `## R8 findings`
  sections, fresh probes, real run-all tail.

## What I deliberately left alone

- The R8 code fix itself (`fe5bef0f`) — verified, not re-implemented; already correct and
  suite-green.
- Items 2 and 3 (carrier map, PyYAML fail-closed) — resolved and mutation-proven in R7, preserved
  verbatim as instructed.
- The 2 pre-existing failing suites surfaced by `run-all --scope changed` — out of this lane's
  scope, documented in report.md rather than silently patched.
- The concurrent session's uncommitted R9 edits to the workflow `.js` files — not mine to commit or
  revert.

DELIVERABLE_COMPLETE
