# SD-GLM-FLASH-ARM-DEAD-CHAIN-DECORATIVE-01

Defect 1 root cause: `glm-flash` did not die. All four preserved GLM runs completed with exit 0 after 80-188s. The 20s constant was `LEADV2_ARM_EARLY_VERDICT_S`; `glm-flash` was missing from the GLM status/liveness adapters, so product-close fell through `worker_liveness=unknown`, looked in the nonexistent `glm-flash-runs` path, and declared the still-running worker silent.

Defect 1 fix: treat `glm-flash` as the `glm-coder.sh`/`glm-runs` provider alias in early status, duplicate liveness, close waiting, run-dir, final-output, exit-76, and resume paths. No arm was removed from routing.

Defect 2 root cause: the silent branch called `_dl_note no_work` before `_pc_arm_advance`; the write-once terminal made the later spawn decorative. The old close owner's EXIT trap would also terminalize a successful handoff.

Defect 2 fix: advance first, hand off close ownership without a terminal, walk remaining launchers until one is live or all are exhausted, and write `no_work` only after exhaustion. The marker records `status=advanced` for idempotent re-entry.

`git diff --stat --` mission files (the dispatcher file also contains concurrent pre-existing edits):
```
 plugins/leadv2/scripts/leadv2-dispatch-code.sh     | 89 ++++++++++++++++------
 .../scripts/leadv2-dispatch-product-close.sh       | 52 +++++++++----
 2 files changed, 104 insertions(+), 37 deletions(-)
```
Untracked proof harness: `plugins/leadv2/scripts/tests/test-arm-advance-real.sh` (126 lines).

Forced-empty arm-1 proof, verbatim:
```
worker_spawned by=router model=glm-flash task=f3ea32c6 attempt=f3ea32c6-1787968367-99342 handle=armfix-glm-flash
worker_spawned by=router model=freepool task=f3ea32c6 attempt=f3ea32c6-1787968370-1876 handle=armfix-freepool
```
The harness also asserts no `dispatch_terminal` exists at the second spawn.

DELIVERABLE_COMPLETE


## F4 evidence (lead-supplied 2026-08-29 03:35Z, round 2 left this unaddressed)

The defect-1 root-cause claim is now backed by the preserved run dirs under
`~/.claude/cache/glm-runs/`, `meta.yaml` of each:

    260829-042322-cd7dad21-32e8   exit_code: 0   duration_s: 106
    260829-042325-d458df09-4e07   exit_code: 0   duration_s: 188
    260829-043252-95fdcfe2-5029   exit_code: 0   duration_s: 80
    260829-043355-baa812c9-5ebb   exit_code: 0   duration_s: 122

All four workers succeeded in 80-188s while the gate declared them silent at 20s.
