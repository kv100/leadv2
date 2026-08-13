# PLUGIN-RACING-RESERVE-01 — deliverable

## Verdict

**The original failure was in the test, not in the dedup.** `atomic_dispatch_reserve_spawn_confirm`
was never proven broken because none of the five failing p1 assertions ever reached it: every
mission in `test-routing-enforcement-p1.sh` classified as `product/conservative_default` (no
`kind`, no fast-path mission prefix), so each call hit the PREPASS-RETRY-THEN-PARK-01 (2026-07-29)
architect prepass, retried twice against an impossible-in-offline-suite real `claude -p`
subsession, and parked with `exit 3` before `dispatch_reserve` was ever invoked. The racing
assertion specifically parked at the `_lane_writes_guard` check inside the
`LEADV2_DISPATCH_ARCHITECT_GATE=0` kill-switch branch (H6/LANDING-BLOCKER-R2), since the test
declares no `--writes` and no lane worktree exists.

`test-dispatch-duplicate-caller-race.sh` (a distinct, already-passing suite that drives the same
`leadv2-dispatch-code.sh` for real, using a `docs-only` mission prefix to clear the prepass)
already proves the dedup holds under a genuine two-process race. Nothing in this task touched
`leadv2-dispatch-code.sh`'s dedup/reservation logic.

## Fix applied — `test-routing-enforcement-p1.sh`

Prefixed every mission string passed to `${DISPATCH_BIN}` with `plugin-only ` (matching
`classify_product_work()`'s fast-path regex), keeping the two byte-identical duplicate pairs
(`one mission only once` x2, `racing reservation` x2) prefixed identically so their dedup
signature (`compute_sig`) still matches.

**Discovered live, not by reading (R2 materialized for real):** once classification was fixed,
the quota-refusal assertion reached the real free-arm chain (glm -> kimi -> codex -> sonnet) for
the first time -- and the unfaked `LEADV2_DISPATCH_KIMI_BIN` defaulted to the **real**
`kimi-coder.sh`, which launched a live, token-spending `moonshotai/kimi-k3-free` background
session (`~/.claude/cache/kimi-runs/260801-180551-persona-engine-41a4`, `pid=56731`,
`status: running`, cwd = this checkout) against a nonsense mission-text prompt. It was found live
(via `ps`/the run-dir's `meta.yaml`) and killed (`kill -TERM` on its process group) within
~3 minutes of starting; `meta.yaml` showed `turns: 0`, so no model turn had completed and no
edit was made by it (confirmed: the only uncommitted changes present in the tree at kill time
were `leadv2-state-path.sh` (17:55, before the kimi run started at 18:05:52) and
`leadv2-status-surface.sh`/`.10s.sh` (18:07-18:08, but coherently labeled `SWIFTBAR-LIVE-01`
work matching a concurrently-running sibling lane's dispatch process observed in `ps` -- not
plausible output from a 0-turn kimi run against an unrelated 20-word prompt). No revert was
needed or performed; those files are another lane's legitimate in-flight work and reverting them
would itself have been the destructive-git mistake this task is warned against.

Added `make_refusing_kimi()` (mirrors `make_refusing_glm`'s pattern: emits
`LEADV2_DISPATCH_REFUSED:` + kimi's documented rc=77 launch-probe-failure contract,
KIMI-CHANNEL-01) and wired `LEADV2_DISPATCH_KIMI_BIN` into the quota-refusal, peak-hours-refusal,
and launcher-crash scenarios so the chain proceeds deterministically to the already-faked
codex/sonnet arms instead of ever touching a real launcher again.

Result: all 8 assertions in this suite now PASS, including `racing reserves admit exactly one
dispatch`.

## Fix applied — `test-session-route.sh`

Root cause was one level deeper than "stale GLM-FIRST-01 expectations": the suite's own header
promises "all provider and quota probes are stubbed... never calls a real model or consumes
subscription quota," but it never stubbed `LEADV2_GLM_QUOTA_GATE`, so `leadv2-session-route.sh`
shelled out to the **real** `leadv2-glm-quota-gate.sh` on every case. Every failure was driven by
whatever the real subscription's live quota happened to be that run -- not a fixed,
re-baseline-able expectation.

- Added `GLM_GATE_OK_STUB` / `GLM_GATE_REFUSE_STUB` fakes and made `route()` default to
  `LEADV2_GLM_QUOTA_GATE=$GLM_GATE_OK_STUB` and `LEADV2_KIMI_ENABLED=0` (kimi's own probe is
  likewise a live external call the suite's header already claims not to make).
- **"routine Standard -> Codex Terra" / "Light -> Codex Luna"** (pure preference assertions,
  superseded by GLM-FIRST-01): renamed to state GLM-first outcomes; now assert
  `provider=glm model=glm-5.2`.
- **"Codex quota threshold -> Claude fallback" / "missing Codex CLI -> Claude fallback"**
  (fallback-correctness assertions): kept the original expected outcome (`provider=claude
  model=sonnet`) but now construct the scenario with GLM *and* kimi genuinely unavailable
  (`LEADV2_GLM_QUOTA_GATE=$GLM_GATE_REFUSE_STUB`, `LEADV2_KIMI_ENABLED=0`) so the
  codex-quota/codex-missing fallback branch is actually the one being exercised, not bypassed
  by GLM winning auto-routing before the router ever reaches the codex check. Confirmed against
  `leadv2-session-route.sh`'s live auto-mode order (glm -> kimi -> codex -> claude): with GLM/kimi
  off, `codex_used_percent=90 reached policy threshold 85%` and `codex binary unavailable` both
  correctly fall through to `provider=claude`.

Result: all 8 assertions PASS; the suite is now genuinely offline (no live quota-gate or kimi
probe calls remain).

## Fix applied — `test-codex-session-runner.sh`

Two distinct findings, reported separately per the brief:

- **Stall cap -- stale expectation, fixed.** `STALL_MAX` was raised 2 -> 6 on 2026-07-24; `rc=4`
  already matched, only the hardcoded `calls -eq 2` was stale. Changed the assertion to read the
  runner's live default straight from `leadv2-session-runner.sh` source
  (`sed -n 's/^STALL_MAX="\${LEADV2_RUNNER_STALL_MAX:-\([0-9]*\)}".*/\1/p'`) rather than
  re-hardcoding a second magic number, so the next tuning pass can't silently re-break this again.
  Now PASSes with `STALL_MAX=6`.
- **Recursion -- real defect, left red, NOT touched.** `rc=5 calls=1` (fire on its own terms) is
  never observed; what happens is `rc=4 calls=6` -- the runner burns the full stall budget and
  only then prints `CODEX-LEAD RECURSION suspected` via the *stall* path, confirming the standing
  open item "codex-recursion still dead": the recursion detector is not an independent early-exit,
  it's a label printed by the stall cap. Fixing this means changing
  `leadv2-codex-session-runner.sh` control flow -- explicitly out of scope and off-limits for this
  task. The assertion was left as originally written (`rc=5 calls=1`); it still FAILs, honestly,
  and was not re-baselined to the observed `rc=4 calls=6`.

## Baseline protocol (Section 3) -- followed exactly

- One tree: `~/Projects/leadv2` canonical checkout, no worktree.
- Sequential: two full `run-core-offline.sh` runs, one before any edit, one after all edits,
  never overlapping (confirmed no `run-core-offline.sh` process ran concurrently with either;
  unrelated dispatch processes from a different active lane, `SWIFTBAR-R4`, were running
  concurrently in the shared tree during the BEFORE run but that lane does not touch
  `~/.claude/cache/dispatch-ledger` via `run-core-offline.sh` itself).
- Raw logs recorded in full at `docs/handoff/PLUGIN-RACING-RESERVE-01/before-run.log` (558 lines)
  and `after-run.log` (367 lines).

### Failing-suite SET diff (never count)

BEFORE: `passed=17 failed=4 missing=0`
```
Codex full-cycle runner
dispatch refusal fallback chain
hook token + mode isolation
provider/model router
```

AFTER: `passed=19 failed=2 missing=0`
```
Codex full-cycle runner
hook token + mode isolation
```

`diff before-failed.txt after-failed.txt`:
```
2d1
< dispatch refusal fallback chain
4d2
< provider/model router
```

No suite name appears in AFTER that was absent from BEFORE. `dispatch refusal fallback chain`
(the `run-core-offline.sh` label for `test-routing-enforcement-p1.sh` -- note: the acceptance
criteria's prose calls this "routing enforcement (P1)"; the actual suite label in
`run-core-offline.sh` is `dispatch refusal fallback chain`, same file, verified by
`grep -n 'run_check "dispatch refusal fallback chain"' run-core-offline.sh`) and
`provider/model router` are the two suites this task fixed. `Codex full-cycle runner` remains
failing -- expected, it's the recursion-detector defect, explicitly out of scope. `hook token +
mode isolation` remains failing on both sides -- pre-existing, unrelated to this task, not in
LANE_WRITES, not touched.

## Acceptance check

- `racing reserves admit exactly one dispatch`: PASS (verified standalone and inside the full
  suite run).
- The four sibling assertions (quota refusal advances chain, peak-hours refusal advances chain,
  launcher crash remains failure, duplicate dispatch refusal): all PASS.
- No `architect_prepass ... status=parked` line appears in the post-fix p1 suite output.
- Both raw run-core-offline.sh outputs recorded verbatim; SET diff computed and shown above.
- `hook token + mode isolation` is a pre-existing, out-of-LANE_WRITES-scope failure and is
  unchanged before/after -- not touched per the "no suite name absent from the before-run's set"
  acceptance line (it was present before and remains present after; nothing new was introduced).

## Off-limits / risk register -- final status

- `leadv2-dispatch-code.sh`, `leadv2-codex-session-runner.sh`, `leadv2-status-surface*.sh`,
  `glm-coder.sh`, `kimi-coder.sh`, `leadv2-lane-outcome.sh`: untouched.
- No `LEADV2_SKIP_DRIFT_GUARD=1`, no destructive git (no reset --hard / clean / stash).
- R2 (real launcher side effects on first-reachability) materialized for real during this task --
  see the kimi-run incident above -- and was mitigated by adding `make_refusing_kimi()` /
  `GLM_GATE_REFUSE_STUB` fakes rather than by weakening any assertion.

DELIVERABLE_COMPLETE
