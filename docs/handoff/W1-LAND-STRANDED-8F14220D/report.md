# W1-LAND-STRANDED-8F14220D — landing and verification

The code was already on main when this recovery began: `2e34cd9d` carries the four-file
patch from rebased lane commit `093620ad`; current main is `29545513`.
Ancestry plus all five blob IDs independently confirm this in [lineage.log](evidence/lineage.log).
This commit completes the missing report/evidence. It does not repeat the code landing.
**Verification is partial: current main has two red target suites; no all-green claim.**

## Before/after evidence (pass/fail)

Fresh runs: before = historical main `50148393` in an isolated checkout; after = canonical
main `29545513` itself. Neither baseline uses the stranded lane's stale anchor.
Commands, timeouts and diagnostic setup: [commands.txt](evidence/commands.txt).

| Suite (`test-*.sh`) | main before | current main after |
|---|---:|---:|
| idle-lead-guard | 19/0 | 19/0 |
| injector-dedup | 10/0 | 10/0 |
| lane-diff-single-repo | 5/0 | 5/0 |
| phase-precondition | 81/1 | 80/2 |
| t14-worker-mcp | 21/1 | 21/1 |

Every green summary was cross-checked for a positive case count and absence of explicit
FAIL lines: [summary-audit.log](evidence/summary-audit.log). No previously green suite went red.
Both lane-diff runs also emitted TRIPWIRE warnings about changing `~/.claude` paths;
causal attribution is UNCERTAIN. Full before/after logs preserve those warnings.

## Conflict: test-idle-lead-guard.sh

Both sides replace case 10's obsolete registration requirement with an absence check.
Main adds the retirement rationale and visible assertion stderr; the lane adds checks for
promise-guard in Stop and lane-watch-v2 arm/disarm in SessionStart/SessionEnd, but suppresses
stderr. Kept main's rationale, diagnostic absence assertion and unsuppressed stderr, plus
all three lane assertions. Reproduced the cherry-pick conflict in scratch, then separately
rebased `d2971b7e` onto historical main and resolved both hunks; [conflict-hunks.diff](evidence/conflict-hunks.diff)
and [rebase.log](evidence/rebase.log) preserve the evidence. This matches the existing landing;
its only addition to that replay is the T14 effort pin ([diff](evidence/rebase-to-landed.diff)).

## What landed, and remaining red cases

Landed in `2e34cd9d`: idle registration assertions, lane-diff bytecode suppression,
phase-precondition bare-handle stub, T14 effort baseline plus `GLM_EFFORT=max` fixture pins.
Injector-dedup was already identical to `d2971b7e`; matching blobs and SHA-256 checks confirm it.
No target file is missing from main's effective result. Neither known-red file is committed
by this recovery. The initial dirty two-line deletion in known-red-suites is preserved,
unstaged; removing its phase-precondition entry would be unjustified by the current run.

Each current red case was also measured on current main with the five landing test edits
removed in scratch (all production files remain at `29545513`):

- Phase: `accepted waiver should not exit 4 (got 4)` — also fails without landing.
- Phase: `waived plan.yaml not written` — also fails without landing.
- T14: `bg spawn missing --mcp-config (value=none)` — also fails without landing.

[Without-landing phase log](evidence/current-without-phase-precondition.log): 78/4, also
including G3 and G7g. [Without-landing T14 log](evidence/current-without-t14-worker-mcp.log): 21/1.
On the same historical main runtime, rebased phase-precondition is **82/0**: its G3 fix works.
T14's controlled `GLM_EFFORT=low` comparison is **20/2 -> 21/1**: argv drift is fixed,
but the background case remains red. A scratch diagnostic retained the child log:
```
/tmp/w1-stranded-proof-20260906/rebase/plugins/leadv2/scripts/glm-coder.sh: line 1236: /dev/fd/63: Operation not permitted
```
This is [the child artifact](evidence/t14-child.log), not proof of T14 green outside this sandbox.
UNCERTAIN: unrestricted T14 result. Settling command from main in an unrestricted shell:
`GLM_EFFORT=low timeout -k 5s 120s bash plugins/leadv2/scripts/tests/test-t14-worker-mcp.sh`.

## Falsification set: raw output evidence

Raw red then green on the identical historical main runtime:
```
  FAIL: G3: dispatch should exit 0 (got 4)
[PHASE-PRECONDITION] pass=81 fail=1
[PHASE-PRECONDITION] pass=82 fail=0
```
Full [before](evidence/before-phase-precondition.log) and [rebased](evidence/rebased-phase-precondition.log) logs.
The current-main reds above remain unresolved; this historical green does not override them.

### bash -n evidence
```
bash -n plugins/leadv2/scripts/tests/test-idle-lead-guard.sh: rc=0
bash -n plugins/leadv2/scripts/tests/test-injector-dedup.sh: rc=0
bash -n plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh: rc=0
bash -n plugins/leadv2/scripts/tests/test-phase-precondition.sh: rc=0
bash -n plugins/leadv2/scripts/tests/test-t14-worker-mcp.sh: rc=0
```
No Python files changed; `python3 -m py_compile` is inapplicable.

### tests/run-all.sh --scope changed evidence
Command: `timeout -k 10s 900s bash tests/run-all.sh --scope changed`.
```
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/W1-LAND-STRANDED-8F14220D-01/plugins/leadv2/scripts/tests/run-core-offline.sh
process_rc=124
```
The gate timed out before an aggregate summary; **incomplete/red, not passed**.
[Wrapper output](evidence/changed-scope.log), [failure labels](evidence/changed-scope-failures.log),
and [serial partial output](evidence/core-serial-tail.log) retain the evidence; four shard logs are adjacent.
The run used the pinned lane with its initial dirty state. Broader failures are unclassified,
not asserted pre-existing. No allow-list entries were added; no model review was launched.
To settle the full gate, rerun that command in a clean unrestricted main checkout.

### Deterministic definition-of-done evidence
Before committing the report, the mechanical gate correctly refused it:
```
dod_fail check=report_missing_or_unheaded detail=not_committed
dod_pass check=paste_evidence
dod_pass check=suite_registration
dod_pass check=runtime_state
```
After committing the report ([artifact](evidence/dod-after.log)):
```
dod_pass check=report
dod_pass check=paste_evidence
dod_pass check=suite_registration
dod_pass check=runtime_state
```
