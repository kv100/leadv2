REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=2 medium=6 low=5

FINDING: severity=High file=plugins/leadv2/scripts/lib/leadv2-status-cache.sh line=174 dimension=design desc=Cache library is wired into ZERO consumers — the diff touches only lib+instrument+test+run-all, so the fix changes no production behavior and the churn it claims to fix persists
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-spawn-rate.sh line=125 dimension=correctness desc=Live ps sampling is non-functional on macOS: `etimes` keyword not supported and `comm=` shows `bash` not script names, so the acceptance instrument's ps half always reports zero observations

## High findings

**H1 — Cache is dead code as delivered.** The brief (docs/handoff/STATUS-CHURN-01/brief.md item 1) requires `broad-status`, `status-collector`, `lanes-snapshot`, `lane-liveness`, `lane-status-line-tail` to "all read through it", and LANE_WRITES lists all five. The diff modifies none of them. Census over the whole tree:
```
$ grep -rn "leadv2-status-cache" plugins/leadv2/scripts --include="*.sh" -l | grep -v tests | grep -v status-cache.sh
plugins/leadv2/scripts/leadv2-spawn-rate.sh     # comment reference only
```
No consumer sources the lib or calls `lv2_status_snapshot_get` outside the test. The header's "THE FIX: ONE snapshot file per project control-plane" is false as shipped: every consumer still runs its own scan, the journal stays empty in production, and brief items 1 (wiring), 2 (per-consumer debounce) and 5 (before/after evidence — the handoff dir contains only `brief.md` + the diff, no report.md) are unmet.

**H2 — The acceptance instrument's ps half cannot work on the target platform.** Two live probes on this machine (Darwin 25.5.0):
```
$ ps -Ao comm=,etimes= 2>&1 | head -3
ps: etimes: keyword not found          # ← ps rejects the invocation outright

$ /tmp/leadv2-probe-comm.sh & ; ps -o comm= -p $!   # direct shebang exec of a leadv2-named script
bash                                    # ← comm= is the interpreter, not the script name

$ ps -Ao command= | grep -cE 'leadv2-(broad-status|status-collector|lanes-snapshot|lane-liveness|pulse-beat)'
29                                      # ← command= is the field that matches
```
`leadv2-spawn-rate.sh:125` pipes `ps -Ao comm=,etimes=` through `2>/dev/null`, so both defects are silent: the loop appends nothing and the report always prints "(no leadv2-* processes observed in this sampling window)". Combined with H1 (journal half also empty in production), the instrument the brief designates as the source of before/after acceptance numbers produces no data at all. The fix is `ps -Ao command=,etime=` (parse etime, or use lstart) — but even then it measures poll observations, not starts, which the script itself acknowledges.

## Medium findings

**M1 — Documented journal kind `miss` is never emitted** (census shape: header-contract vs code). `leadv2-status-cache.sh` header (diff lines 202, 197–198) documents `"kind":"hit|miss|recompute"` and "`miss` is journaled only for genuine give-ups"; the embedded Python journals only `hit` (lines 351, 389) and `recompute` (367, 427) — the genuine give-up path journals `"recompute"` with the prior age. `spawn-rate.sh` renders a `miss` column that is structurally always 0. Same shape: header line ~200 promises "Every call appends exactly one line", but a compute failure (exception) exits without any journal line.

**M2 — Failed compute poisons the cache.** `do_compute` (line 320) never checks `result.returncode`: a compute_cmd that fails with empty stdout is cached as a valid snapshot `{"computed_at":…,"producer":…}` and served as `hit` for the full TTL — every consumer sees empty status for TTL seconds. `timeout=30` raises uncaught `TimeoutExpired` → traceback, rc=1, no journal line.

**M3 — No post-lock freshness recheck** (census: 2 sites — the NB-lock winner, diff lines 364–368, and the alarm-fallback winner, lines 421–428). Both check age *before* acquiring the lock and recompute unconditionally after. A caller descheduled between its stale read and its flock attempt can acquire the lock after another producer already refreshed and recompute again. Standard pattern (re-read `computed_at` once inside the lock) is missing; this is also a direct false-red source for test (b)'s exact `==1` assertion under the load this ticket targets (load avg 244 per brief).

**M4 — Timing-based suite is flaky by construction** (tests-can-fail lens; suite passes now: `7 passed, 0 failed, rc=0`). (a) warm→run gap exceeding TTL 3s (scheduling on a loaded box) → false "expected 0 recomputes"; (b) exact `HITS_B==4`/`RECOMPUTES_B==1` breaks if any waiter exceeds the 2s poll window; (c) flags `age_s > 5.0` where the recompute line records the *replaced* snapshot's age (~3.4s after the 3.3s sleep) — a 1.7s scheduling delay pushes it past 5.0 and false-fails a correct library.

**M5 — Mutation control writes into the live source tree.** `BROKEN_LIB=plugins/leadv2/scripts/lib/.leadv2-status-cache-broken-test.sh` (test line 602). A SIGKILL/timeout between write and trap leaves a mutated library copy in the repo; this repo's own history shows dirty-tree auto-commits (`f4d0e17 "worker exited dirty"`), and parallel run-all suites would collide on the fixed path.

**M6 — Acceptance evidence absent.** Brief item 5 requires before/after spawn-rate tables over the same 15-min window in report.md; the handoff dir has no report.md, and per H2 the instrument could not have produced the ps half anyway.

## Low findings

- **L1** `spawn-rate.sh:53` — unknown args silently swallowed (`*) shift ;;`); non-numeric `--window-min` breaks the `$(( ))` arithmetic; PROJECT_ROOT fallback is `$PWD`-sensitive (known cwd gotcha).
- **L2** `spawn-rate.sh:104` — "calls/min" divides by the nominal window, not the observed journal span; with a cold journal the first minute overstates rates.
- **L4** `spawn-rate.sh:125` — the ps grep list (7 names incl. `pulse-beat`, `lane-detail`) doesn't match the lib header's 5 consumers; census inconsistency, moot while sampling is broken.
- **L5** `test-status-churn.sh` line 4/printf — "(a) … exactly one recompute line" but the assertion is `RECOMPUTES_A -eq 0`; comment and assertion disagree (the brief's own wording is similarly off).
- **L6** `leadv2-status-cache.sh:417` — SIGALRM could fire between flock success and `signal.alarm(0)` inside the `finally`; uncaught `_Timeout` → rc=1. Astronomically narrow.

## Claims-without-evidence census

| Claim | Verdict |
|---|---|
| lib header: "Measured 2026-09-01 (load avg 244) … ×10/×8/×4/×6", "66–92% of a core" | Backed by in-repo brief.md (numbers match verbatim) — OK |
| lib header: state-path "identical across every worktree of the same repo" | Verified against `leadv2-state-path.sh` (git-common-dir resolution) — OK |
| lib: journal/snapshot path shape under `LEADV2_STATE_ROOT` | Verified live: probe wrote `/tmp/sc-probe/state/status-snapshot-journal.jsonl` + `status-snapshot.json` with expected JSON — OK |
| spawn-rate: implicit claim that `ps -Ao comm=,etimes=` observes leadv2 scripts | **Disproven by probe (H2)** — `ps: etimes: keyword not found` + `comm=`=`bash` |
| "Bash 3.2 compatible" (both files) | Suite ran green under the system bash on this box — verified for the paths the tests exercise; UNVERIFIED for the `--window-min`/`--sample-secs` arg paths the tests never hit |

## Positive verification (falsification lens)

The suite is genuinely falsifiable, not a happy-path rubber stamp: I ran it (`7 passed, 0 failed`), and the mutation control actually fires — the flock-removed library produced 5 recomputes with raw journal lines pasted in the output. Lock semantics, atomic `os.replace`, waiter-poll, journal path resolution, and end-to-end lib behaviour were all probed live and behave as coded.

The two High findings are architectural, not nitpicks: the library and its tests are solid in isolation, but nothing in production calls the library, and the one instrument meant to prove the fix works cannot observe the system it instruments on this platform.

---

FINISH CONTRACT: no stash was created (nothing to pop). I made no repo edits — this was a review-only pass with all probes in `/tmp` (cleaned up: `/tmp/sc-probe`, `/tmp/leadv2-probe-comm.sh` removed). NOT-COMMITTED — no changes to commit; the review above is the deliverable. Files changed: none. Test results: `test-status-churn.sh` 7 passed / 0 failed (run by me, LEADV2_SUITE_LOCK_DISABLE=1).
