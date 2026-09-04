verdict: REVISE
next_action: review_round_2

# dispatch-0322009e — LANE-STATE-LEAK-01 fix round, developer full report

## 0. Census correction (PREPASS-MECHANISM-CLOSURE-01) — the design's root-cause narrative for leg (d) does not hold

The scoped design's §0 claims leg (d) fails because leg (a) (the writer) and leg (d) (the
reader) resolved `.arm-exceptions-<day>` under two different control-plane roots (leg (d) set
`LEADV2_STATE_ROOT=${TMP_ROOT}/state-d`, leg (a) never set it).

I verified this claim experimentally and it is **false as the cause of the observed failure**,
though the pairing mismatch it describes is real and worth fixing regardless:

- Manually resolving both the writer path (`PROJECT_ROOT=${ROOT} leadv2-state-path.sh
  .arm-exceptions-<day>`, no `LEADV2_STATE_ROOT`) and the reader path (`_lv2_state_resolve` inside
  `leadv2-broad-status.sh`, same `PROJECT_ROOT`) showed they resolved to the **same path**, and that
  path contained real content (`count=1`, `last_reason=glm_refused_quota_gate`, `sig8=...`) even
  before I touched the test.
- I checked out the merge-base (`aed1f2b`) into `/tmp/wt-base` and ran
  `test-glm-deferred-ladder.sh` unmodified: **leg (d) was already FAIL there**, with the exact same
  message (`expected sonnet-fallback line missing from rendered artifact`), before any of this
  round's state-path changes existed. At that commit the renderer read `.arm-exceptions-<day>` via
  a **raw** `os.path.join(root, "docs", "leadv2", ...)` path — which, in this test's no-git sandbox,
  resolves to exactly the same path the writer used. So the two sides already agreed at the
  merge-base, and the test was red anyway.
- The actual cause: `leadv2-broad-status.sh` folds the three provider-health lines
  (sonnet-fallback / codex-credits / glm-deferred) into `queue_md` (`:669-681`), and `queue_md` is
  **unconditionally** collapsed out of the compact `founder-status.md` — `_queue_line_count` is
  always > 0 (queue_md always has at least a label + placeholder line), so `hidden_bits` is always
  populated (`:779-784`) and the compact `BLOCK` written to `FOUNDER_STATUS_PATH` never contains
  `queue_md` at all (`:855-877`; the code's own comment at `:850` says so explicitly: "full lane
  detail, full queue ... still lands in founder-status-full.md"). This is a **pre-existing,
  deliberate design decision (PULSE-READABLE-01)**, byte-identical between `aed1f2b` and `HEAD` —
  `diff` of the two versions of `leadv2-broad-status.sh` shows zero difference in this logic.
- The test's own assertion (`test-glm-deferred-ladder.sh:282`, unchanged in this round's diff
  against `aed1f2b`) reads `${ROOT}/docs/leadv2/founder-status.md` — the compact file — which by the
  above was **never** going to contain the line, independent of any state-root pairing.

**What I did about it:** implemented the design's Option A pairing fix anyway (removing the two
`LEADV2_STATE_ROOT` overrides in legs (d)/(neg), adding a writer/reader pre-assert) because it's a
real, harmless hardening — matches the writer's actual resolution and gives a named failure if a
future edit re-splits the two sides. But it does not, by itself, turn the test green. The actual
fix was retargeting the leg's assertions from `founder-status.md` to `founder-status-full.md`,
which is where the design's own code comments say this content belongs. See the diff in
`test-glm-deferred-ladder.sh` for both changes.

I did not widen scope beyond this: no change to which file compact vs full status writes to, no
change to the PULSE-READABLE-01 collapse behavior itself — only the test's target file and the
pairing hygiene.

## 1. `test-glm-deferred-ladder.sh` — now green, cause in one sentence

Leg (d)/(neg) asserted against `founder-status.md` (compact), but provider-health lines are
unconditionally excluded from that file by design; retargeting the assertions to
`founder-status-full.md` (plus the writer/reader state-root pairing fix) makes the suite green.

```
PASS: (a) park row written before sonnet fallback worker spawn (ordering holds)
PASS: (a) poison fence held
PASS: (b) glm-deferred --list prints the parked sig8
PASS: (b) glm-deferred --list prints 'no deferred glm tasks' when empty
PASS: (c) two credit-empty computations within 24h emit exactly ONE journal line
PASS: (c) a third computation after the stamp ages past 24h emits a second journal line
PASS: (d) rendered founder-status-full.md contains sonnet-фолбэков сегодня: 1 (glm_refused_quota_gate) -- real reason variant, not hardcoded 'glm quota'
PASS: (d) a day with no fallback renders no sonnet-fallback line
PASS: (e) shared-cache double refusal: count=2, both distinct sig8s recorded
PASS: (e) park queue holds a row for both distinct sig8s
PASS: (e) run 2's park row carries reason=glm_refused_quota_precheck (benched, never attempted)
PASS: (e2) a repeat bump for an already-present sig8 is a no-op (count stays 1)
PASS: (g) a parked row whose sig8 already landed is reaped, not retried
PASS: (h) a parked row with no usable mission is skipped and stays in the queue (H3)
PASS: (i) a failed retry dispatch leaves the row pending
PASS: (f) real retry-all: new dispatch observed (marker file), 'retried as=', old sig8 reaped from --list
PASS: poison fence held across the suite
================================================
  glm-deferred-ladder suite: FAIL=0
================================================
```

Also added a §3 input-boundary guard to `leadv2-broad-status.sh`: a malformed/failed
`date -u +%Y%m%d` used to leave `_TODAY_UTC` empty, resolving `.arm-exceptions-` (a name no
writer ever writes) and silently rendering 0 fallbacks with no warning — asymmetric with the
writer's own 8-digit guard in `leadv2-dispatch-code.sh`. Now it retries once, then skips the
arm-exceptions read entirely (with a stderr WARN) rather than resolving a truncated name.

## 2. Three suites — real falsification, verified red-then-green by actually breaking the thing they guard

All three previously had no falsification marker at all. I added genuine mutants (copies of
production code with the guarded defect reintroduced), ran the suite's own assertion against
the mutant AND the real code, and print `RED-then-GREEN: <name> (pre_rc=1 -> post_rc=0)` only
when the mutant demonstrably fails and the real code demonstrably passes — matching the exact
regex `leadv2-builder-selfcheck.sh` greps for (`RED-then-GREEN: .*\(pre_rc=1 -> post_rc=0\)`).

- **`test-state-path-worktree-identity.sh`**: mutant forces `COMMON_DIR=""` (git-common-dir lookup
  neutered), which sends the resolver down its "not inside a git repo" branch unconditionally,
  pinning `STATE_ROOT` at `${LINK_ROOT}/docs/leadv2` — the raw, per-worktree path this whole task
  exists to kill. Against a real linked worktree (main repo vs worktree are different directories),
  main/worktree resolution diverges (`pre_rc=1`); the real resolver agrees (`post_rc=0`).
  ```
  PASS: falsification: mutant (raw per-worktree path) diverges, real resolver agrees
  RED-then-GREEN: worktree-identity (pre_rc=1 -> post_rc=0)
  ALL PASS
  ```
- **`test-state-path-migration.sh`**: mutant replaces the MERGE(file) collision branch (target
  already exists) with an unconditional `shutil.move(local, target)` — clobber instead of
  line-union. Re-running the exact two-worktree merge scenario S4 already exercises: wt-a's line
  lands first, wt-b's collision then overwrites the target outright, losing wt-a's line
  (`pre_rc=1`); the real resolver unions both (`post_rc=0`).
  ```
  PASS: falsification: clobber mutant loses wt-a's line, real resolver unions both
  RED-then-GREEN: state-path-migration (pre_rc=1 -> post_rc=0)
  ALL PASS
  ```
- **`test-state-path-no-raw-paths.sh`**: parameterised the scanner into `scan_root()` (was
  hard-coded to `PLUGIN_ROOT`), then built a mutant corpus — a **copy** of `scripts/` + `hooks/` —
  with one line appended to a file not on any allow-list (`X="${PROJECT_ROOT}/docs/leadv2/active.yaml"`).
  Scanning the mutant corpus catches it (`pre_rc=1`); scanning the real tree is clean (`post_rc=0`).
  ```
  PASS: falsification: mutant corpus (un-allow-listed raw path) is caught, real tree is clean
  RED-then-GREEN: state-path-no-raw-paths (pre_rc=1 -> post_rc=0)
  ALL PASS
  ```

All mutants are copies, never in-place mutations of the real tree; each mutant lives under its
own `mktemp -d` and is cleaned up via `trap ... EXIT` (or explicit `rm -rf` for the corpus, since
that suite's original file had no cleanup trap and I didn't want to change that behavior for the
non-falsification path).

## 3. `run-core-offline.sh` and the three named suites

`bash plugins/leadv2/scripts/tests/run-core-offline.sh`:

```
[CORE-OFFLINE] FAILED: broad-status relay scoping
[CORE-OFFLINE] FAILED: fanout classifier/runner guard
[LANE-TRUTH-BATCH-01] pass=11 fail=5
[CORE-OFFLINE] FAILED: lane truth batch (log_path + quarantine convergence)
[CORE-OFFLINE] suites passed=57 failed=3 missing=0
```

All three failures are **pre-existing and unrelated to this round's changes** — I did not touch
`leadv2-fanout.sh`, the lane-truth-batch files, `leadv2-single-lead-beat.sh`, or
`test-broad-status-relay-scope.sh` at all. Evidence:

- `test-broad-status-relay-scope.sh` and `test-fanout-classify-guard.sh` and
  `test-lane-truth-batch-01.sh` all PASS cleanly when run against the merge-base `aed1f2b`
  (checked out to `/tmp/wt-base2`).
- Re-running `test-broad-status-relay-scope.sh` at current `HEAD` with `leadv2-broad-status.sh`
  swapped back to its pre-my-edit `HEAD` version (i.e. isolating my one production-code change)
  still fails identically (7 passed, 18 failed) — so my `_TODAY_UTC` guard is not the cause either.
  This is a regression that predates my session, introduced somewhere else in this lane's own
  round-1 commits (not in the `LANE_WRITES` scope I was given).

I did not attempt to fix these — they're outside the scoped `LANE_WRITES` list and outside the
design's non-goals boundary ("no production change ... except the `_TODAY_UTC` validation").
Flagging for lead/architect: this lane is NOT actually clean on `run-core-offline.sh`, independent
of anything in this round.

`test-broad-status-lanes-blind.sh`, named in the original mission's "Done means" list, **does not
exist anywhere in this tree** (`ls plugins/leadv2/scripts/tests/` has no match, `grep -r
lanes-blind` across scripts/tests/docs is empty). I did not fabricate a run for it.

The other two named suites both pass cleanly:

```
$ bash plugins/leadv2/scripts/tests/test-broad-status-renderer-truth.sh
...
[TEST] === 22 passed, 0 failed ===

$ bash plugins/leadv2/scripts/tests/test-pulse-empty-board.sh
...
[TEST] === 10 passed, 0 failed ===
```

## 4. `git diff --stat`

```
$ git diff --stat aed1f2b..HEAD
 .gitignore                                                        |   5 +
 plugins/leadv2/hooks/leadv2-single-lead-beat.sh                   |  17 +-
 plugins/leadv2/scripts/leadv2-broad-status.sh                     |  77 ++++++-
 plugins/leadv2/scripts/leadv2-dispatch-code.sh                    |  85 ++++++-
 plugins/leadv2/scripts/leadv2-state-path.sh                       | 282 +++++++++++++++++++--
 plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh          |  55 ++++-
 plugins/leadv2/scripts/tests/test-state-path-migration.sh         | 194 +++++++++++++++
 plugins/leadv2/scripts/tests/test-state-path-no-raw-paths.sh      | 198 +++++++++++++++
 plugins/leadv2/scripts/tests/test-state-path-worktree-identity.sh | 135 +++++++++++
 9 files changed, 981 insertions(+), 67 deletions(-)
```

This session's own commit (`a726c16`, on top of the prior lane HEAD):

```
$ git show --stat HEAD
 plugins/leadv2/scripts/leadv2-broad-status.sh                     |  17 +++-
 plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh          |  39 +++++--
 plugins/leadv2/scripts/tests/test-state-path-migration.sh         |  83 +++++++++
 plugins/leadv2/scripts/tests/test-state-path-no-raw-paths.sh      |  95 +++++++++---
 plugins/leadv2/scripts/tests/test-state-path-worktree-identity.sh |  34 +++++
 5 files changed, 236 insertions(+), 32 deletions(-)
```

## Self-check falsification (mission boilerplate)

`bash -n` on every file I touched — all OK (bash 3.2 syntax, `/bin/bash -n` not separately run
since no new bash-4-only constructs were introduced; no Python files were touched this session,
so no `py_compile`):

```
OK-3.2-syntax: plugins/leadv2/scripts/leadv2-broad-status.sh
OK-3.2-syntax: plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh
OK-3.2-syntax: plugins/leadv2/scripts/tests/test-state-path-migration.sh
OK-3.2-syntax: plugins/leadv2/scripts/tests/test-state-path-no-raw-paths.sh
OK-3.2-syntax: plugins/leadv2/scripts/tests/test-state-path-worktree-identity.sh
```

Red-then-green shown per-suite above (§1, §2) — each of the four changed test suites was run
before my fix (red, captured earlier in this session) and after (green, pasted above).

## What I deliberately left alone

- The pre-existing `run-core-offline.sh` regressions in relay-scope / fanout / lane-truth-batch —
  out of scope, unrelated to `LANE_WRITES`, reported above.
- `test-broad-status-lanes-blind.sh` — does not exist; not fabricated.
- All non-goals from the design §6 (durable half, other production files, pre-existing
  no-raw-paths allow-list entries, `~/.claude/leadv2-shared/` drift, Option B hermeticity, rebase
  onto `main`).
- The unrelated `docs/handoff/dispatch-nw5sig005|nw9sig009|nwcm0012/phases.d/*.yaml` and
  `plugins/leadv2/scripts/tests/zzdebug-glm.sh` changes visible in `git status` — not mine, not
  touched, not committed (this is a shared worktree; another process appears to be writing those
  concurrently).

## Verdict

REVISE, not APPROVE: the design's stated root cause for the one red test was wrong (§0), and
`run-core-offline.sh` is not actually clean on this lane (3 pre-existing failures, §3) even
though none of them are caused by this round's work. Both are facts the architect/lead should see
before this closes, not silent green.

DELIVERABLE_COMPLETE
