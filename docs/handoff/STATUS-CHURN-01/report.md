# STATUS-CHURN-01 — fix-round 3 report

Branch: `worktree-STATUS-CHURN-01` (main merged first: f6781dc2, conflict in
`tests/run-all.sh` resolved by keeping both sides' suite mappings).
R2 review under review: committed-tree diff 6626410d, verdict FAIL high=7.

## R3 findings

| # | File:line | Finding | Verdict | Evidence |
|---|---|---|---|---|
| H1 | `leadv2-status-collector.sh:129` | `set -e` in the section subshell aborts on a non-zero cache helper; `_sc_git_compute_raw` fallback at :133 unreachable | **REFUTED** (mechanism), fix kept as hardening | `_sc_run_section` runs `if ( set -euo pipefail; "$@" ); then` — the subshell is the *tested command*, and bash suppresses errexit inside a condition context even when `set -e` is re-set inside (POSIX; confirmed on bash 5.3.9). Probes: (1) committed HEAD collector run with a failing cache helper (`LEADV2_STATE_ROOT` = regular file → `lv2_status_snapshot_get_scoped` returns 1) → git section `{'branch': 'main', 'local_head': 'f38b4a0', 'unpushed': None}, 'ok': True` — that IS the raw fallback's 3-key output, i.e. the fallback executed. (2) Minimal repro: `if ( set -euo pipefail; s="$(f)"; echo SURVIVED ); then …` prints SURVIVED + then-branch. The `|| snap=""` is retained so the contract no longer depends on this subtlety. |
| H2 | `leadv2-status-collector.sh:132` | git section JSON shape non-deterministic: 5 keys on cache path vs 3 on bypass/fallback | **REAL → fixed** | Same HEAD probe as H1: fallback emitted 3 keys while the cache path emits 5 (`computed_at`, `producer` added by the lib). Fix: `_sc_git_compute_raw` now emits `computed_at: null, producer: null` — every path carries the same 5 keys; the cache lib overwrites both on write. Covered by suite test (e) e3/e4 (bypass and fallback assert the exact 5-key set with nulls). |
| H3 | `lib/leadv2-status-cache.sh:4` | header documents a five-consumer shared-snapshot fix the diff does not implement | **REAL → fixed** | Census command: `grep -rn "lv2_status_snapshot_get" plugins/leadv2/scripts --include='*.sh' \| grep -v tests/ \| grep -v status-cache.sh` → exactly one hit: `leadv2-status-collector.sh:141` (the git-facts call). Header rewritten: names the ONE production consumer (status-collector git section, scope `git-facts`), states explicitly that the other consumers were NOT wired. |
| H4 | `lib/leadv2-status-cache.sh:39` | header points at a "reference shape" that does not exist | **REAL → fixed** | `git show HEAD:plugins/.../leadv2-status-collector.sh \| sed -n '61,70p'` → the compute step emits `{local_head, branch, unpushed}` (now + the two explicit nulls). Header now names that exact shape. |
| H5 | `tests/test-status-churn.sh:159` | mutation control writes an executable into the shipped plugin lib dir under a fixed name | **REAL → fixed** | `git show HEAD:.../test-status-churn.sh \| grep -n BROKEN_LIB=` → `BROKEN_LIB="${SCRIPT_DIR}/../lib/.leadv2-status-cache-broken-test.sh"` (canonical). Fix: mutant now lives in `mktemp -d` (`<mut>/lib/leadv2-status-cache.sh` + symlink to the real `leadv2-state-path.sh` at `<mut>/` so the lib's relative path resolution still works), cleaned by the EXIT trap. |
| H6 | `tests/test-status-churn.sh:133` | test (c) asserts the unbounded PRE-recompute staleness; passes only via a 3.3s sleep | **REAL → fixed** | HEAD test: `sleep 3.3` at :129 + a bound check over every journal row, while the HEAD lib journaled `recompute` with the PRE-recompute age (`journal("recompute", 0.0 if age is None else round(age, 3))`). Fix (both sides): the lib now journals `age_s` = age of the snapshot SERVED (recomputes ≈ 0) with the pre-recompute staleness moved to a separate `stale_age_s` field — safe because `leadv2-spawn-rate.sh` counts `kind`/`producer` only (`grep -n 'age_s\|kind' leadv2-spawn-rate.sh` → only `d.get("kind")`); the test fixture injects staleness by rewriting `computed_at` (`make_stale … 3600`, no sleep) and additionally asserts a recompute actually happened so the bound check cannot pass vacuously. |
| H7 | `tests/test-status-churn.sh:1` | no test exercises the production wiring — suite never invokes leadv2-status-collector.sh | **REAL → fixed** | `git show HEAD:.../test-status-churn.sh \| grep -c 'status-collector'` → 0. New suite test (e) drives the real collector in a temp git repo across all four paths (cache-miss, cache-hit, bypass, cache-helper-failure fallback) asserting the 5-key shape on each, and test (f) drives the new `dispatched_lanes` section. Each step writes its own `snap-<tag>.json` + keeps its stderr log so a failed write can never alias a previous step's snapshot. |

## Fold-in: founder-status blind to lanes

`leadv2-status-collector.sh` gained a `dispatched_lanes` section — a cheap,
file-only union of the `active.yaml` registry (per-row task_id, phase, pid,
pid liveness via `os.kill(pid,0)`, worktree + existence, started/updated) and
the `.claude/worktrees/*` dirs (a worktree with no registry row still shows,
`source: "worktree-only"`), so a dead/slow heavyweight lanes-snapshot can no
longer make live disk lanes invisible to the beat. Resolution order:
`LEADV2_SC_ACTIVE_YAML` (tests) → `$PROJECT_ROOT/docs/leadv2/active.yaml` →
control-plane `active.yaml` via `leadv2-state-path.sh`.

Live sample (this worktree, `collected_at=2026-09-02T03:43:21Z`, full run of
the real collector against the real control plane; before this round the
beat's only always-rendered lane-ish source was the dispatch-ledger tail —
codex-task rows):

```
dispatched_lanes ok= True
count= 13
{"phase": "recovered", "pid": "34197", "pid_alive": true, "source": "registry", "started_at": "2026-09-01T22:03:58Z", "task_id": "PROMISE-GUARD-TURN-IT-ON-01",  "updated_at": "2026-09-01T22:03:58Z", "worktree": ".../worktrees/PROMISE-GUARD-TURN-IT-ON-01",  "worktree_exists": true}
{"phase": "recovered", "pid": "62839", "pid_alive": true, "source": "registry", "started_at": "2026-09-01T22:22:05Z", "task_id": "0e7cd03d",                    "updated_at": "2026-09-01T22:22:05Z", "worktree": ".../worktrees/0e7cd03d",                    "worktree_exists": true}
{"phase": "recovered", "pid": "56861", "pid_alive": true, "source": "registry", "started_at": "2026-09-01T22:54:39Z", "task_id": "RESUME-LANE-ACCEPTS-PATH-01", "updated_at": "2026-09-01T22:54:39Z", "worktree": ".../worktrees/RESUME-LANE-ACCEPTS-PATH-01", "worktree_exists": true}
{"phase": "recovered", "pid": "49635", "pid_alive": true, "source": "registry", "started_at": "2026-09-01T23:13:52Z", "task_id": "BEAT-LOOP-ORPHANS-01",        "updated_at": "2026-09-01T23:13:52Z", "worktree": ".../worktrees/BEAT-LOOP-ORPHANS-01",        "worktree_exists": true}
{"phase": "recovered", "pid": "1360",  "pid_alive": true, "source": "registry", "started_at": "2026-09-01T23:45:55Z", "task_id": "MERGE-QUEUE-DEAD-HEAD-01",    "updated_at": "2026-09-01T23:45:55Z", "worktree": ".../worktrees/MERGE-QUEUE-DEAD-HEAD-01",    "worktree_exists": true}
{"phase": "recovered", "pid": "6860",  "pid_alive": true, "source": "registry", "started_at": "2026-09-02T00:29:03Z", "task_id": "LEADV2-HOOK-CACHE-DEPLOY-01", "updated_at": "2026-09-02T00:29:03Z", "worktree": ".../worktrees/LEADV2-HOOK-CACHE-DEPLOY-01", "worktree_exists": true}
{"phase": "recovered", "pid": "2291",  "pid_alive": true, "source": "registry", "started_at": "2026-09-02T02:38:19Z", "task_id": "GLM-ARM-THROUGHPUT-01",      "updated_at": "2026-09-02T02:38:19Z", "worktree": ".../worktrees/GLM-ARM-THROUGHPUT-01",      "worktree_exists": true}
{"phase": "recovered", "pid": "90885", "pid_alive": true, "source": "registry", "started_at": "2026-09-02T03:27:40Z", "task_id": "CACHE-TRUTH-01",             "updated_at": "2026-09-02T03:27:40Z", "worktree": ".../worktrees/CACHE-TRUTH-01",             "worktree_exists": true}
{"phase": "e2e",       "pid": "1",     "pid_alive": true, "source": "registry", "started_at": "2026-09-02T03:28:47Z", "task_id": "GUARD-CENSUS-IS-WRONG-01",   "updated_at": "2026-09-02T03:38:09Z", "worktree": ".../worktrees/BRAIN-CLASS-LIVE-01",       "worktree_exists": true}
git: {"branch": "worktree-STATUS-CHURN-01", "computed_at": 1788320514.5780559, "local_head": "f6781dc2", "producer": "status-collector", "unpushed": 7}
```

(9 live registry rows shown; the remaining 4 of the 13 are dead/stale
registry rows. 0 worktree-only rows — every worktree dir currently has a
registry row.)

## Files changed

- `plugins/leadv2/scripts/leadv2-status-collector.sh` — fallback hardening
  (`|| snap=""`), one 5-key git shape on every path, new
  `dispatched_lanes` section.
- `plugins/leadv2/scripts/lib/leadv2-status-cache.sh` — header rewritten to
  the one consumer that exists + the real shape; `recompute` journal rows
  now report the served age (~0) with the pre-recompute staleness in
  `stale_age_s`.
- `plugins/leadv2/scripts/tests/test-status-churn.sh` — (c) sleep-free and
  post-recompute-bound, mutation mutant in `mktemp -d`, new (e) production
  wiring and (f) dispatched_lanes suite cases.
- `tests/run-all.sh` — merge-conflict resolution only (kept both sides'
  suite mappings).

## Verification

- `bash -n` on all three changed shell files: OK.
- Suite: `bash plugins/leadv2/scripts/tests/test-status-churn.sh` →
  **13 passed, 0 failed**, 3 consecutive runs.
- Falsifiability: `leadv2-suite-falsifiable.sh …/test-status-churn.sh` →
  `verdict: falsifiable — a failure injection turned the suite red (rc=1)`
  (probe `assertion_tools_broken`: rc=1).
- Changed-scope runner: `bash tests/run-all.sh --scope changed` (lane root
  cwd) → `run-all: 4 passed, 2 failed, scope=changed`. Both failures
  pre-exist on baseline `f6781dc2` (this branch's HEAD before this round's
  uncommitted diff), verified by running each in a detached `git worktree
  add --detach /tmp/sc01-baseline f6781dc2`:
  - `test-collector-sees-registered-lane.sh` → `PASS=2 FAIL=2` on baseline,
    byte-identical failure output to the worktree run (foreign-lane board
    rendering, unrelated to the git/cache/lanes-dispatch code touched this
    round).
  - `run-core-offline.sh` → reproduces the same `rm: ...: Directory not
    empty` / lock-contention symptom on baseline; multiple other lanes were
    concurrently running core-offline shards against the same
    `/tmp/leadv2-core-offline-*` lock/tmp paths during this measurement
    (see the other active dispatch-* sessions in this run's environment) —
    environmental contention, not a regression from this diff.
  - `test-status-churn.sh` (this round's own suite) passed inside the
    `run-all` run too: `13 passed, 0 failed`.
