verdict: APPROVE
next_action: review_round_2

# DISPATCHER-BRANCH-RESIDUE-01 — full report

Worked in worktree `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCHER-BRANCH-RESIDUE-01`
on branch `worktree-DISPATCHER-BRANCH-RESIDUE-01`. No cd to the main checkout. Landed one commit
(`8cc54df8`), on top of the lane's existing base (`0a7d6a31 merge main into DISPATCHER-BRANCH-RESIDUE-01`).

## Method

For each branch, `git diff main...worktree-<id> -- <in-scope files>` was read in full (not just
line-count proxy from the mission table) by parallel Explore subagents, each asked to classify
every distinct behavioral hunk as SUPERSEDED (cite main's line), LAND (describe the gap), or
OBSOLETE (name the replacement mechanism). I independently re-verified the one LAND candidate by
reading its diff and grepping main for the entity names before writing any code (MD-05/§6.5 of the
subagent protocol).

## Verdict table

| branch | added/overlap (mission's proxy) | verdict | reason |
|---|---|---|---|
| 83c44855 | 155/127 (81%) | SUPERSEDED | Every hunk (quota-lockout raw-text plumbing, `_arm_status_probe`/`_quota_shaped`/`_wait_arm_early_verdict`, `record-quota-lockout` subcommand, `_pc_or_dash`/tenant routing-yaml search/`PC_TRIED`) is present in main verbatim, often with the same commit-tag comments (`dispatch-8e2a32be`), and main has iterated further (extra `PC_TRIED` checks, dual `_pc_maybe_quota_advance` call sites). |
| PREPASS-PROVIDER-FALLBACK-01-R5 | 220/174 (79%) | SUPERSEDED | Main (today's HEAD) already has `resolve_v2_dispatch`/`_v2_fail`, `_architect_failure_class`, `_architect_fallback_design`, `DISPATCH_SLOT_REG_ID` release logic, and extends it further (`ARCHITECT_FALLBACK_RUNNER_PID` signal-safe teardown, `lane_deregister`) beyond what R5 has. |
| PREPASS-PROVIDER-FALLBACK-01-R6 | 220/174 (79%) | SUPERSEDED, and **R5 supersedes R6** | Byte-identical diff to R5 on the target file (same tree hash, same second). R6's later "park uncommitted work" commit swept in debug/scratch residue (`.ppf-debug.sh`, three ~6400-line scratch copies) that R5 never has — R6 is the dirtier duplicate. Net: both discard; if traceability is wanted keep R5's history only. |
| f7f1c2c8 | 44/33 (75%) | SUPERSEDED | Report-only-gate plumbing (`LANE_DELIVERABLE`, `_mission_deliverable`, `--lane-deliverable` flag), `readings=` emit, and the report-lane gate body in product-close.sh are all present in main under the same marker names (REPORT-ONLY-GATE-01, GLM-FIRST-RECOVERY-01) — landed via `35657f5d feat(dispatch): gate report-only lanes on deliverables`, independently reimplemented, verbatim marker text. |
| d784b987 | 8/6 (75%) | SUPERSEDED | Evidence-contract prefix in `_spawn_worker_body` + `_LEADV2_EVIDENCE_CONTRACT_MISSION` const — byte-identical in main (`leadv2-dispatch-code.sh:5347-5351`, `leadv2-helpers.sh:63-64`, same CLAIM-EVIDENCE-GATE-01 fix). |
| PLUGIN-RELIABILITY-01 | 11/10 (90%) | SUPERSEDED | `prepass_parked` emit, `router_v2_reorder_failed` decision emits, and `_pc_process_alive`/`_pc_reap_worker` pid-file liveness are all in main, and main's versions are supersets (extra `no_dispatchable_arms` case, `worker_launched=0` field, more reap call sites). |
| PHASE-BOOTSTRAP-ADMIT-02 | 24/9 (37%) | OBSOLETE | The `_pp_bootstrap` phases.d-scan + `phase_precondition_bootstrap_admit` mechanism this branch edits was deliberately replaced: main's `_phase_precondition_guard` no longer does a caller-side bootstrap probe at all (comment cites `PHASE-GATE-IS-INVERTED-01`); `_verify_artifact` now accepts lead-authored evidence directly instead. The worktree's scan-based heuristic is exactly the caller-attested pattern main's history (`faee3fc5`) says was measured as inverted/buggy and removed. Landing it would reintroduce that bug. |
| 100a892d | 11/3 (27%) | **LAND** | Stale-script-tree provenance self-check in `cmd_resolve()` — `grep -n "stale_script_tree\|LEADV2_ALLOW_STALE_SCRIPT_TREE"` on main returned nothing before this change. Genuinely new: refuses (exit 4) a dispatch invoked from a non-`plugins/leadv2/scripts`-suffix tree when a canonical tree is discoverable at `PROJECT_ROOT/plugins/leadv2/scripts` (the exact shape of the 4c9ddb05 incident: a whole dispatch silently ran out of a stale copy, producing `status: no_reviewer` and rc=127 phase records). `LEADV2_ALLOW_STALE_SCRIPT_TREE=1` downgrades to a warn. PROJECT_ROOT is resolved via the existing git/pinned resolver already in the file (not `../` hops), so it doesn't violate the repo's own root-resolution doctrine. Landed. |
| 5e57c5ff | 21/5 (23%) | SUPERSEDED | All 4 hunks (readings= emit, `LANE_DELIVERABLE_DECL` REPORT-ONLY-GATE-01 pipeline, report-lane purity checks, `render_gate_findings` shared renderer) present verbatim in main. |
| 049e0e9e | 0/0 | SUPERSEDED | Touches only `leadv2-dispatch-product-close.sh` (224 lines, REVIEW-GATE-INFRA-01): `pc_precheck_writes`/undiffable-write-set bounce, dirty-lane partitioning, `pc_persist_review_body` stable-copy recovery — all present verbatim in main (lines 1734-1843, 2449-2499, 3151-3290). |

Net: **1 of 10 branches landed** (100a892d's tripwire only — not the rest of that branch's diff,
which also touched `leadv2-review-run.sh`; that hunk (`resolver_rc`/`resolver_stderr` capture) is
separately SUPERSEDED in main under a different shape (`emit decision "review_pool_resolver ... rc=..."`
at `leadv2-review-run.sh:185`), verified by grep before excluding it).

`tests/run-all.sh` EXTRA_SUITE_MAP: none of the 10 branches' surviving (LAND) hunk touched
`tests/run-all.sh`, so there was no map row to convert. The new suite self-registers via
`# run-all-triggers:` from the start (see below) — no conversion needed.

## What was landed

`plugins/leadv2/scripts/leadv2-dispatch-code.sh`, in `cmd_resolve()` right after the signature
validation block: a provenance guard that refuses dispatch (exit 4) when `SCRIPT_DIR` is not a
`plugins/leadv2/scripts` suffix while a canonical tree is discoverable at
`PROJECT_ROOT/plugins/leadv2/scripts`, journals `dispatch_refused reason=stale_script_tree`, and
prints a remedy (`ln -sf ... `) to stderr. `LEADV2_ALLOW_STALE_SCRIPT_TREE=1` downgrades to
`dispatch_stale_script_tree_warn` instead of refusing. Suffix-only match (never an absolute
prefix) so both a plugin-cache copy and a `.claude/worktrees/<id>/plugins/leadv2/scripts` copy
still pass.

## Test — tests/test-stale-script-tree.sh (new)

Hermetic (scratch git repo, poison provider bins, `--no-spawn`). Covers: T3 stale-tree refuses
(exit 4, stderr text, remedy, journal line), T4 escape-hatch downgrades to warn, T5 legitimate
trees (canonical + worktree-copy) pass.

### Green (function-body change in place)
```
PASS: T3a: stale-tree dispatch exits 4
PASS: T3b: refusal names the stale tree on stderr
PASS: T3c: remedy lands on stderr
PASS: T3d: journal carries dispatch_refused reason=stale_script_tree
PASS: T4a: escape hatch does not refuse (rc=3)
PASS: T4b: escape hatch emits the downgrade warn
PASS: T5(canonical): passes provenance check (rc=3)
PASS: T5(worktree-copy): passes provenance check (rc=3)
=== 8 passed, 0 failed ===
EXIT=0
```

### Negative control (flipped `!=` to `==` INSIDE the guard's `if` condition, function body —
not a top-level line insert, so only this behavior reddens, nothing else)
```
FAIL: T3a: stale-tree exit -- expected rc=4, got 3 -- [leadv2-dispatch-code] dispatch_classified task=acaa5dbf class=product reason=conservative_default kind=code
[leadv2-dispatch-code] phase_precondition_refused task=acaa5dbf class=Standard reason=unexpected_rc value=127
[leadv2-dispatch-code] ERROR: phase precondition: unexpected exit 127: bash: .../stale-tree/scripts/leadv2-phase-record.sh: No such file or directory
FAIL: T3b: refusal text -- stderr lacks the refuse line
FAIL: T3c: remedy -- no remedy line
FAIL: T3d: journal line -- capture lacks dispatch_refused: ...
PASS: T4a: escape hatch does not refuse (rc=3)
FAIL: T4b: downgrade warn -- no dispatch_stale_script_tree_warn line
FAIL: T5(canonical) -- refused (rc=4) -- legitimate tree must pass the suffix check
FAIL: T5(worktree-copy) -- refused (rc=4) -- legitimate tree must pass the suffix check
=== 1 passed, 7 failed ===
EXIT=1
```
Reverted (`diff` against the pre-edit backup showed 0 differences after revert); re-ran green
(8/8) before committing.

## CI selection proof (LEADV2_RUN_ALL_SELECT_ONLY=1 tests/run-all.sh --scope changed)

Present direction (change committed, in `main...HEAD` diff range):
```
[SELECT] .../plugins/leadv2/scripts/tests/test-stale-script-tree.sh
```
grep for the line: rc=0 (found).

Absent direction (net-zero diff over the range — file reverted then re-applied via revert-commit,
same effect as "never touched" for `--scope changed`'s `main...HEAD` union, since stash is
deny-floor-blocked in this repo): no `[SELECT]` line for the suite. grep rc=1 (not found).

Both directions proven without a bare `git stash` (blocked by `leadv2-deny-floor` hook in this
tree) — used a pair of ordinary commits (revert + revert-of-revert) instead, then squashed the
three checkpoint commits into the single landed commit via `git reset --soft` + one clean commit,
per "land it as ONE coherent change, not replayed history."

## Self-check (falsification set)

```
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh
OK
$ bash -n plugins/leadv2/scripts/tests/test-stale-script-tree.sh
OK
```
No Python files changed (no `py_compile` needed).

Changed-scope suite run (the new suite itself, the only suite this change's scope selects):
```
=== 8 passed, 0 failed ===
EXIT=0
```

## Dispatcher still dispatches

Real `--no-spawn` invocation from this worktree (a legitimate canonical-suffix tree — the tripwire
correctly does NOT fire):
```
[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/Projects/leadv2 cwd=.../worktrees/DISPATCHER-BRANCH-RESIDUE-01) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=839052dd status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/Projects/leadv2 cwd_root=.../worktrees/DISPATCHER-BRANCH-RESIDUE-01
[leadv2-dispatch-code] lane_plan_missing task=839052dd reason=source_absent source=.../docs/handoff/839052dd/context.yaml
[leadv2-dispatch-code] task_class=Light route=dispatch source=derived task=839052dd
[leadv2-dispatch-code] brain_decision task=839052dd class=Light class_source=computed phases=classify,build,test,review,close reason=no_explicit_class
[leadv2-dispatch-code] dispatch_classified task=839052dd class=product reason=conservative_default kind=code
RC=0
```
Reaches a real classification/routing decision (`brain_decision`, `dispatch_classified`), no
`stale_script_tree` refusal (correct — this worktree IS a `plugins/leadv2/scripts` suffix tree).

## Deliberately left alone

- `leadv2-review-run.sh` hunk from worktree-100a892d's diff (resolver_rc/stderr capture) — not
  landed; SUPERSEDED under a different shape already in main (verified by grep, not assumed).
- All 9 other branches / worktrees — read in full, judged SUPERSEDED or OBSOLETE, not landed, not
  deleted (deleting worktrees/branches is destructive and out of this lane's constraints; founder
  can prune `worktree-83c44855`, `worktree-PREPASS-PROVIDER-FALLBACK-01-R5`,
  `worktree-PREPASS-PROVIDER-FALLBACK-01-R6`, `worktree-f7f1c2c8`, `worktree-d784b987`,
  `worktree-PLUGIN-RELIABILITY-01`, `worktree-PHASE-BOOTSTRAP-ADMIT-02`, `worktree-5e57c5ff`,
  `worktree-049e0e9e` once this verdict is accepted).
- `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` — untouched per constraint (separate live
  lane owns it this session).
- `tests/known-red-suites.txt` / `tests/known-failures.txt` — untouched (neither grew nor needed
  to shrink; the new suite isn't in either file).
- Did not run a full `tests/run-all.sh` in this live checkout (per the mission's warning about the
  five live control-plane symlinks getting repointed into a temp fixture dir) — only the new
  suite directly and `--scope changed` in `LEADV2_RUN_ALL_SELECT_ONLY=1` mode.

## Commit

`8cc54df8 feat(dispatch): refuse dispatch from a stale script-tree copy (PLUGIN-REVIEW-ARMS-01 §3.2)`
on `worktree-DISPATCHER-BRANCH-RESIDUE-01`, on top of `0a7d6a31`. Working tree clean. Not pushed.

DELIVERABLE_COMPLETE
