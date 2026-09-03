# REVIEW-RUN-LOSES-VERDICTS-01 — a real FAIL verdict is discarded, and a quota cooldown is reported as a provider error

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REVIEW-RUN-LOSES-VERDICTS-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh,plugins/leadv2/scripts/tests/test-review-body-recovery.sh,tests/run-all.sh,docs/handoff/REVIEW-RUN-LOSES-VERDICTS-01/

Main is `95ed6f310` in `~/Projects/leadv2`. Branch from it.

Both defects were found live by the session running V5-M0-SKELETON-01, with probe evidence, not
by reading code. Its two `blocked: provider_error` review runs were neither a provider outage
nor a transport failure.

## [Critical] a completed codex review is thrown away as `review_body_lost`

Codex exited `rc=0` and did real work, twice. What landed was `review-codex.md` at **202
bytes** of housekeeping lines ("Thread ready", "Turn started") with zero findings, so the
wrapper declared `review_arm_retry reason=review_body_lost` and spilled to another arm.

The verdict was never lost. It was sitting in codex's own store the whole time:

```
codex-task.sh result review-mtgzwfxe-silbka
  -> FAIL, 4 high
```

Four substantive findings about gate integrity — `tee` without `pipefail` masking a non-zero
rc; the timeout killing only the background bash while `mypy`/`pytest` children survive the
worktree teardown; the dirty-tree guard not seeing untracked files. All four would have
vanished silently. The V5 lead had to extract them by hand into `review-codex-recovered.md`.

**Fix:** before declaring `review_body_lost` and spilling to another arm, the wrapper must
read the verdict from `codex-task.sh result <job-id>`. A body that is only housekeeping lines
is a capture failure in our wrapper, not an absent review — and the store is the authority.

Only after the store also yields nothing may the run be called body-lost, and that outcome must
name which retrieval attempts were made.

## [Critical] an intentional cooldown is not a provider error

The glm arm exited `rc=2` from its **own quota gate**:

```
ARM_COOLDOWN arm=glm reason=peak_hours
"GLM-5.2 costs 3× during 06:00-10:00 UTC"
```

Quota at the time was 5h=1%, weekly=1%. That is a deliberate, healthy refusal. `review-run`
reported it as `provider_error` and **blocked the review gate** — so a cost-saving cooldown
reads to the lead as an outage, and a lane stalls on a non-problem.

**Fix:** a cooldown/refusal is a distinct outcome from a provider error. It must spill to the
next arm without blocking the gate, and the log line must say the arm declined on cooldown,
naming the reason. Do not special-case the string `peak_hours` or the arm name `glm` — the
founder has a standing rule against hardcoding an arm into or out of routing; key on the
refusal being a declared cooldown outcome.

## Acceptance

Build `test-review-body-recovery.sh` against fixtures — never a real codex job, never a real
review — covering:

1. arm exits 0 but writes a housekeeping-only body, and the store HAS a verdict ⇒ the verdict
   is recovered, findings preserved, no retry, no `body_lost`;
2. arm exits 0, body is housekeeping-only, and the store has nothing ⇒ `body_lost` is declared
   AND the log names both retrieval attempts;
3. an arm refusing on a declared cooldown ⇒ outcome is a cooldown spill, the gate is NOT
   blocked, and it is distinguishable in the log from a provider error;
4. a genuine provider error ⇒ still blocks, exactly as today;
5. no arm name or reason string is matched as a literal in the decision path.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production function body, RED, revert, GREEN, clean `git diff --stat`.
  A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- The suite must leave every repo path and every real state root byte-identical, on the failure
  path too.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A recoverable verdict is never discarded, a cooldown never blocks the gate, and a mutation that
restores either behaviour turns the suite red with the exit code following.
