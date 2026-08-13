LABEL=critic-dispatch-PLUGIN-RELIABILITY-01-review-1786562178 SESSION_ID=065fe096-c5dd-46c2-aecf-91af9c7b4dd7
--- body from: docs/handoff/dispatch-PLUGIN-RELIABILITY-01-review/critic.full.md ---
REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=2 medium=2 low=0

FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=1494 dimension=correctness desc=_pc_reap_worker called with "${HANDLE}" as run_dir instead of the actual run directory, so pgid/lock_dir reaping is a silent no-op on worker-timeout
FINDING: severity=High file=plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh line=684 dimension=correctness desc=D3/D5 tests are pure grep-on-source (the exact "lying-green" pattern round 1 was faulted for) and no test exercises the two reap call sites, so the run_dir bug passes 21/21 green

# Review: PLUGIN-RELIABILITY-01 round-2 fix (docs/handoff/PR01-review/build-r2.diff)

## Method
Applied the diff to a scratch clone (`git apply --check` clean), ran `bash -n` on all
four touched files (all OK), ran the new `test-plugin-reliability-01.sh` (21/21 pass —
confirms the author's claim), then hand-reproduced the two reap call sites outside the
test harness to check whether the collected-pid logic they depend on actually runs
against a real run-dir layout.

## HIGH — `_pc_reap_worker` invoked with the wrong first argument at both timeout sites

`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, two call sites (post-patch
line numbers ~1494 and ~1516, both new in this diff):

```
_pc_reap_worker "${HANDLE}" "$(_pc_meta_value "${_PC_RUNS_ROOT:-${RUNS_ROOT:-${ROOT}}}/${AUTHOR}-runs/${HANDLE}/meta.yaml" pid 2>/dev/null)"
```

`_pc_reap_worker` is documented and implemented as `<run_dir> [meta_pid]`. Every other
call/definition in this file resolves `run_dir` via `_pc_run_dir_for "${AUTHOR}"
"${HANDLE}"` (line 513) or the equivalent inline glm/kimi-aware construction inside
`pc_worker_alive` (lines 756-760, which honors `GLM_RUNS_DIR`/`KIMI_RUNS_DIR`
overrides). These two new call sites instead pass the bare `"${HANDLE}"` string —
e.g. `"a1b2c3d4"` — as `run_dir`.

Inside `_pc_reap_worker`, `run_dir` is used to build `${run_dir}/pgid` and
`dirname "${run_dir}"` + `.lockref` to locate the lock dir. With `run_dir="a1b2c3d4"`,
neither `a1b2c3d4/pgid` nor `a1b2c3d4/.lockref` exist relative to whatever the script's
cwd happens to be, so sources 2-4 (child pgid, lock-dir pid, lock-dir pgid) silently
find nothing. I reproduced this directly (see command below): the identical function
body collects the live supervisor pid when given the correct run_dir, and collects
`<none>` when given the bare handle.

```
-- correct call (as pc_worker_alive does, via real run_dir) --
reap collected pids: 65740 (run_dir='/tmp/simruns/glm-runs/HANDLE123')
-- buggy call (as the two timeout call sites do: pass bare HANDLE) --
reap collected pids: <none> (run_dir='HANDLE123')
```

The only pid that can still be reaped at these two sites is the `meta_pid` passed as
`$2` — and per this diff's own root-cause writeup (`_pc_process_alive` doc comment,
lines ~191-203 of the diff): *"The pid in meta.yaml may be stale (the glm-coder.sh
start process that wrote status=complete, while its `__supervise` parent still holds
the GLM lock)"* — i.e. exactly the case this fix exists to handle is the case these
two call sites cannot catch, because the supervisor pid only lives in
`lock_dir/pid`/`run_dir/pgid`, which this call never locates.

Net effect: on `worker_timeout` (the two `pc_await_worker_exit` failure branches this
diff instruments), the new reap call degrades to a near-no-op for the straggler
`__supervise` process — the same class of stuck-lock incident D1 was written to close
survives specifically on the timeout path, silently.

**Fix:** use `_pc_run_dir_for "${AUTHOR}" "${HANDLE}"` for `run_dir` at both sites
(as line 576 already does), e.g.:
```
_pc_reap_worker "$(_pc_run_dir_for "${AUTHOR}" "${HANDLE}")" "$(_pc_meta_value "$(_pc_run_dir_for "${AUTHOR}" "${HANDLE}")/meta.yaml" pid 2>/dev/null)"
```
This also removes the duplicated, GLM_RUNS_DIR/KIMI_RUNS_DIR-unaware path
reconstruction (`"${AUTHOR}-runs"` doesn't honor the env-var overrides that
`_pc_run_dir_for` and `pc_worker_alive` both respect) and the dead
`${RUNS_ROOT:-${ROOT}}` fallback chain (`RUNS_ROOT` is never assigned anywhere in
this file; `_PC_RUNS_ROOT` is always set at line 498, so that fallback never fires —
harmless but vestigial).

## HIGH — new tests reintroduce the exact anti-pattern round 1 was faulted for, and none cover the broken call sites

`plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh`. The file header and
`docs/handoff/PLUGIN-RELIABILITY-01/summary.md` both assert: *"Round 2: tests are
BEHAVIORAL... No grep-on-source tests (the lying-green disease)."* That claim is not
accurate for the whole suite:

- `test_d3_no_block` (line ~684): `grep -q '\-\-no-block' "$src" && ! grep -q
  'prepass.*--timeout 1800' "$src"` — asserts a string is present in source. It never
  invokes `cmd_resolve`, never calls `leadv2-ask.sh --no-block` and times how long it
  takes, never checks that the dispatcher actually returns before 1800s. The original
  Critical 3 bug (synchronous 30-minute block) is exactly the kind of thing a grep can't
  catch — a `--no-block` string could be present while still being passed to the wrong
  invocation, or a stray blocking call could exist elsewhere.
- `test_d5_reorder_signal` (line ~757): same pattern, `grep -q
  'router_v2_reorder_failed' "$src"`.
- `test_d2_fallback_frontmatter`'s "source accepts agents_worktree_fallback" check
  (line ~609) is also a source grep, layered on top of the (better) reimplementation
  test below it.

Separately, and more importantly: **none of the 21 assertions exercise the two actual
call sites** identified in the High finding above (`pc_await_worker_exit` timeout
branches in the main script body). `test_d1_reap_worker` only calls
`_pc_reap_worker "$run_dir" ...` directly with a correctly-constructed `run_dir` it
built itself in the test — it never sources or invokes the surrounding script logic
that computes the arguments at the real call sites. That is precisely how a
wrong-argument bug like the one above survives a 21/21-green suite: the unit under
test is correct in isolation, the call site is not, and nothing exercises the call
site.

**Fix:** Convert D3 to a real behavioral test — stub/mock `leadv2-ask.sh` (or run the
real one against a scratch questions dir) and time-bound the call, asserting
`cmd_resolve`'s prepass-park branch returns well under a few seconds. Convert D5 to
assert the emitted journal line via a fake `emit`/log capture instead of grepping
source. Add a call-site-level test for D1: extract or invoke the actual
`pc_await_worker_exit` failure branch (or the two lines verbatim from the diff) with a
fake `run_dir` built from `HANDLE`/`AUTHOR` fixtures, and assert the collected pid set
matches what `_pc_run_dir_for` would produce — this is exactly the test that would
have caught the High finding above.

## MEDIUM — D2 "full integration" test never resolves a real `git worktree` common-dir

`test_d2_fallback_frontmatter`, "Full integration" block (lines ~616-663). It creates
`fake_main` as a plain `git init`'d repo and `fake_worktree` as an *unrelated* plain
directory (never `git worktree add`'d off `fake_main`), so
`git -C "$fake_worktree" rev-parse --git-common-dir` fails (not a git repo at all) and
`_common_dir` comes back empty. The test then falls into its own manually-written
`if [[ -z "$_common_dir" ]]; then _main_checkout="${fake_main}"` branch — a
hand-authored substitute for the git resolution, not an exercise of it. The actual
production code path in `claude-subsession.sh` (lines 109-113 of the diff:
`git -C "$PROJECT_ROOT" rev-parse --git-common-dir` → `cd "$_common_dir/.." && pwd`)
is never invoked by this test at all; a bug specific to that traversal (e.g. relative
vs absolute `--git-common-dir` output, a trailing `/.git` vs `/.git/worktrees/<name>`
difference) would not be caught.

**Fix:** use `git worktree add "$fake_worktree" -b test-wt` off a real `fake_main`
repo with a commit, then source/invoke the actual `git -C ... rev-parse
--git-common-dir` line from `claude-subsession.sh` (or run the real script with
`PROJECT_ROOT` pointed at the worktree) instead of reimplementing the fallback
decision in the test.

## MEDIUM — `_pc_process_alive`/`_pc_reap_worker` pid-file trust has no staleness bound

`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, both new functions
(~204-284). All liveness/kill decisions trust `kill -0 <pid>` against whatever pid is
recorded in `meta.yaml`/`pgid`/`lock_dir/pid`, with no comparison against process
start time or command name. On a long-lived host, if the recorded pid has exited and
the OS has recycled that pid number for an unrelated process by the time
`_pc_process_alive`/`_pc_reap_worker` runs, both `_pc_process_alive` (false "alive",
causing another poll cycle to keep waiting) and `_pc_reap_worker` (SIGTERM/SIGKILL of
an unrelated process) misfire. This is a pre-existing class of risk with any raw
pid-file check (not newly introduced by this diff — the round-1 code had the same
trust model, minus the self-match bug), so I am not blocking on it, but the round-2
summary frames this as "NEVER uses pgrep... self/parent always excluded" as if the
liveness check is now airtight; it removes one specific failure mode (self-match) but
does not address pid-reuse. Given `_pc_reap_worker` now sends real `SIGTERM`→`SIGKILL`
based on this data, worth a one-line acknowledgment in the summary rather than an
implied "solved," and worth revisiting if reuse is ever observed in practice (e.g. via
`/proc/<pid>/stat` start-time comparison recorded at meta.yaml-write time, if the
target OS is Linux; macOS lacks an equivalent cheap primitive, which may be why it
wasn't done here).

## What I checked and found clean
- `git apply --check` on the diff: clean.
- `bash -n` on all four touched scripts post-patch: all OK.
- Ran `test-plugin-reliability-01.sh` post-patch: 21/21 pass, matches the author's
  claimed `passed=21 failed=0`.
- `claude-subsession.sh` D2 fix itself (the `ROLE_SOURCE` comparison and the
  git-common-dir fallback construction) is correct as written; my Medium finding is
  about the test's fidelity to it, not the fix.
- D3's actual `leadv2-ask.sh --no-block` flag exists and is implemented as
  fire-and-forget (verified in `leadv2-ask.sh`); the wiring in `cmd_resolve` looks
  correct, my finding is about missing behavioral proof, not a code defect there.
- D4 grace-guard logic (meta-existence + 30s mtime check) is correctly ordered
  relative to the existing revived/running/registry checks — no fallthrough gaps
  found.
- D5 journal line placement (`router_v2_reorder_failed`) is reachable and uses
  variables (`_qg_rc`, `_qg_eligible`) that are populated earlier in the same block.
- No new Supabase/RLS surface (this is a bash-only plugin change) — N/A for this repo.
- No `except Exception`/type-safety dimensions apply (bash, not Python/TS).

## Verdict
FAIL — 2 High findings. Both are fixable with small, mechanical changes (swap
`"${HANDLE}"` for `_pc_run_dir_for "${AUTHOR}" "${HANDLE}"` at the two reap call
sites; strengthen D3/D5 to real behavioral assertions and add a call-site-level test).
The 2 Medium findings should be addressed or explicitly justified in the commit
message per the review bar but do not block on their own.

DELIVERABLE_COMPLETE
