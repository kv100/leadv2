verdict: APPROVE
next_action: review_round_2

# STATUS-CHURN-01 fix-round 3 — developer report

Lane: `worktree-STATUS-CHURN-01`. Resumed pre-existing work (report.md and the
three script diffs already existed uncommitted on the lane at session start);
merged `main` (ea4a9091, docs-only commit, no conflicts), verified, and
committed as `a3e391df`.

## R3 findings — verdict per row (full evidence: `docs/handoff/STATUS-CHURN-01/report.md`)

| # | File:line | Verdict |
|---|---|---|
| H1 | status-collector.sh:129 set -e fallback unreachable | REFUTED (mechanism — subshell condition-context suppresses errexit) but hardening (`\|\| snap=""`) kept |
| H2 | status-collector.sh:132 non-deterministic git JSON shape | REAL → fixed: 5-key shape (computed_at/producer null off cache path) everywhere |
| H3 | status-cache.sh:4 header claims 5 consumers | REAL → fixed: header now names the one real consumer (status-collector git-facts), census command in report |
| H4 | status-cache.sh:39 header cites nonexistent reference shape | REAL → fixed: header now cites the real `{local_head,branch,unpushed}` shape |
| H5 | test-status-churn.sh:159 mutant written into shipped lib dir | REAL → fixed: mutant now under `mktemp -d`, cleaned by EXIT trap |
| H6 | test-status-churn.sh:133 test (c) sleep-dependent, asserts pre-recompute age | REAL → fixed: lib now journals served (post-recompute) age_s (~0) + separate `stale_age_s`; fixture fakes staleness via `computed_at` rewrite, no sleep |
| H7 | test-status-churn.sh:1 no production-wiring test | REAL → fixed: new suite cases (e) drives the real collector across cache-hit/miss/bypass/fallback, (f) drives `dispatched_lanes` |

## Fold-in: lane visibility

`leadv2-status-collector.sh` gained a `dispatched_lanes` section — union of
`active.yaml` registry rows (task_id/phase/pid/pid-liveness/worktree) and
`.claude/worktrees/*` dirs (worktree-only rows for unregistered dirs).
Resolution order: `LEADV2_SC_ACTIVE_YAML` (tests) → `$PROJECT_ROOT/docs/leadv2/active.yaml`
→ control-plane `active.yaml`. Live sample and full rationale in report.md.

## Self-check (paste, run from lane root)

`bash -n` all three changed files: all OK (see tool transcript).

`bash plugins/leadv2/scripts/tests/test-status-churn.sh`:
```
test (a): 5 concurrent consumers within TTL -> exactly one recompute
test (b): stale snapshot -> one recompute, rest read fresh computed_at
test (c): every served age_s stays within TTL+2s (stale fixture, no sleep)
mutation control: library with flock removed -> (a) recomputes >= 2
  (expected RED reproduced: mutation without the lock causes >=2 recomputes)
test (e): collector git section 5-key shape on cache/bypass/fallback
test (f): collector dispatched_lanes lists active.yaml + worktree lanes

13 passed, 0 failed
```

`bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-status-churn.sh`:
```
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=64
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

`bash tests/run-all.sh --scope changed` (lane root cwd):
```
run-all: 4 passed, 2 failed, scope=changed
Failures (blocking):
  - plugins/leadv2/scripts/tests/run-core-offline.sh
  - plugins/leadv2/scripts/tests/test-collector-sees-registered-lane.sh
```
test-status-churn.sh (this round's suite) passed inside this run too:
`13 passed, 0 failed`.

**Both failures verified pre-existing**, not caused by this diff: checked
out lane HEAD-before-this-round (`f6781dc2`) into an isolated
`git worktree add --detach /tmp/sc01-baseline f6781dc2` (removed after
check) and re-ran each in isolation —
- `test-collector-sees-registered-lane.sh` → `PASS=2 FAIL=2` on baseline,
  byte-identical failure text (foreign-lane board-rendering issue, unrelated
  code path).
- `run-core-offline.sh` → same lock-contention symptom
  (`rm: ...: Directory not empty`) reproduces on baseline; multiple other
  dispatch-* lanes were concurrently running core-offline shards against
  the same global lock path during this measurement window.

## Commit

`a3e391df` on `worktree-STATUS-CHURN-01`. Files: the 3 script/test files +
`docs/handoff/STATUS-CHURN-01/report.md`. Per LANE_WRITES constraint,
deliberately left uncommitted (lead-owned control-plane state, modified by
other concurrent sessions during this run, not touched by this diff):
`docs/LEAD_V2_STATE.md`, `docs/leadv2/*`, `docs/handoff/dispatch-nw*/phases.d/*`.

## Left alone

Nothing deliberately deferred beyond the two pre-existing failures documented
above (H1 kept as a hardening no-op per its REFUTED verdict, not a defer).

DELIVERABLE_COMPLETE
