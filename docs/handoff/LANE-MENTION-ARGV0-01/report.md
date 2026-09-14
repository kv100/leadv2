# LANE-MENTION-ARGV0-01 — the dispatcher mints the row it then refuses on

## What changed (1+2, per architect prepass)

Both changes from the prepass were implemented, as recommended:

**Change 1 (mandatory) — `plugins/leadv2/scripts/lib/leadv2-lane-state.sh`, `reconcile` sweep.**
The mention test previously judged only `argv[0]` against the single `non_workers` set. Since the
dispatcher runs as `bash /…/leadv2-dispatch-code.sh --worktree …`, `argv[0]` is `bash`, never the
script name, so the exclusion never fired and the sweep minted a `recovered_unowned` row for its
own command line. Fix: a derived `non_worker_scripts` set (script names, `.sh` suffix) is judged
over the **whole argv program set** (interpreter-agnostic — `bash`, `nohup bash`, `bash -x` all
still resolve to "the dispatcher/liveness script is present"), while tool names (`grep`, `ps`,
`tail`, `Monitor`) stay judged at `argv[0]` only, preserving the existing HEAD-case-2 semantics
(a tool shell whose *argv text* merely mentions `grep` must still count as a mention). The
ancestry check (`if pid in ancestors: continue`) was also moved to run **before** the mention
test, not just before adoption, so a self-run sweep (dispatcher's own lineage) cannot mint a row
for itself either — this covers the dispatcher-run sweep path in addition to the hook-run sweep
path (two independent producers, per prepass §0 point 2).

**Change 2 (recommended, included) — `plugins/leadv2/scripts/leadv2-lane-liveness.sh`, `registered_no_stream` rung.**
A `recovered` active.yaml row with no `pid` (the sweep's pid-less visibility row) no longer earns
`starting:` grace. Same reasoning as the existing `watcher_only` exclusion (FORK-STORM-KILLS-HOOKS-01):
the sweep re-stamps `started_at` every pass, so a recurring bystander mention could re-earn the
grace forever. This closes the residual hole Change 1 alone leaves open — any *other* future
pid-less producer (a stray `git -C <lane> status`, `lsof`, editor, etc.) still mints a visibility
row today, and without Change 2 that row could still refuse a dispatch for up to ~300s per pass,
indefinitely, exactly as measured live on V5-M1-L0. Blast radius is bounded: a `recovered_unowned`
row by construction never carries a pid, so it never carries hijack evidence — the pid-bearing
`lane_is_live` refusal path (adoption rows, `f853b0e3`'s self-pid branch) is untouched.

## Prepass census — no falsification found

Read both functions end to end against the census in the prepass (callers, both sweep call sites,
the ancestry/ppid seam, the TTL reaper, the liveness rung order). Everything matched: two sweep
callers (`leadv2-dispatch-code.sh:8684` pre-admission, `hooks/leadv2-stale-pid-sweep.sh:13`
SessionStart), `ancestry()`/`ppid()` already computed once per sweep pass, the `registered_no_stream`
rung pid-free by design with `watcher_only` as existing precedent for denying grace. No caller,
return-code consequence, or configuration state contradicted the census. Implemented as designed;
did not widen scope beyond it.

## Diff

```
 plugins/leadv2/scripts/leadv2-lane-liveness.sh     |   9 ++-
 plugins/leadv2/scripts/lib/leadv2-lane-state.sh    |  36 +++++--
 .../scripts/tests/test-lane-mention-argv0.sh       | 277 ++++++++++++++++++
 3 files changed, 314 insertions(+), 8 deletions(-)
```

## New suite: `plugins/leadv2/scripts/tests/test-lane-mention-argv0.sh`

Self-registers via the `plugins/leadv2/scripts/tests/test-*.sh` path convention (confirmed below,
no `EXTRA_SUITE_MAP` entry needed). 10 cases:

- **D-1a** — hook-run sweep: non-ancestor pid running `bash <abs>/leadv2-dispatch-code.sh --worktree <lane> …`. RED on unfixed lib (`ed30627c`), GREEN on fixed lib.
- **D-1b** — self-run sweep: same shape, pid = the test shell's own `$$` (a real ancestor of the reconcile's python3 process via the live `ps -o ppid=` fallback, no fixture needed). RED before, GREEN after — proves the ancestry-check reorder, not just the argv basis.
- **D-1c** — `nohup bash` and `bash -x` wrapper variants — still 0 rows (interpreter-agnostic).
- **D-2** — a genuine worker-marker process (`claude -p … --worktree <lane>`, cwd = lane) is still adopted with its pid (adoption path unaffected). The existing tool-shell mention (HEAD case 2, `/bin/zsh -c … grep …`) still mints a pid-less `recovered_unowned` row (tool argv0 basis unchanged).
- **D-2b** — liveness: a pid-less `recovered` row gets no `starting:` grace (falls straight through); a normal pid-less **registered, non-recovered** row keeps its grace — negative control proving Change 2 is scoped to `recovered` rows only.

Direction 3 (foreign live lane still refuses) is exercised by the untouched
`test-dispatch-reentry-self-race.sh` R-b case (still 6/6 green below) — a pid-bearing foreign row
is unaffected by either change, since Change 1 only touches the *mention* test (never reached once
`programs & worker_markers` puts a row on the adoption path) and Change 2 only touches *pid-less*
rows.

### D-1a — RED (unfixed `ed30627c` lib) / GREEN (fixed lib), verbatim

```
[TEST] PASS: D-1a-RED: unfixed lib mints 1 row(s) for the dispatcher's own command line (bash argv[0]) — reproduces the live defect
[TEST] PASS: D-1a-GREEN: fixed lib mints 0 rows for the same dispatcher command line
```

### D-1b — RED (unfixed) / GREEN (fixed), verbatim

```
[TEST] PASS: D-1b-RED: unfixed lib mints 1 row(s) for its own ancestor's dispatcher line (ancestry checked after the mention test)
[TEST] PASS: D-1b-GREEN: fixed lib mints 0 rows once ancestry is checked before the mention test
```

### Full new-suite run (fixed lib)

```
[TEST] PASS: D-1a-RED: unfixed lib mints 1 row(s) for the dispatcher's own command line (bash argv[0]) — reproduces the live defect
[TEST] PASS: D-1a-GREEN: fixed lib mints 0 rows for the same dispatcher command line
[TEST] PASS: D-1b-RED: unfixed lib mints 1 row(s) for its own ancestor's dispatcher line (ancestry checked after the mention test)
[TEST] PASS: D-1b-GREEN: fixed lib mints 0 rows once ancestry is checked before the mention test
[TEST] PASS: D-1c: 'nohup bash' wrapper mints 0 rows
[TEST] PASS: D-1c: 'bash -x' wrapper mints 0 rows
[TEST] PASS: D-2: genuine worker-marker process still adopted with its pid (argv0 fix does not touch worker_markers)
[TEST] PASS: D-2: tool-shell bystander (HEAD case 2) still mints a pid-less recovered_unowned row — tool argv0 basis untouched
[TEST] PASS: D-2b: pid-less recovered row gets NO starting: grace
[TEST] PASS: D-2b-control: a normal pid-less REGISTERED (non-recovered) row keeps its starting: grace
[TEST] test-lane-mention-argv0: 10 passed, 0 failed
```
rc=0

## Regression suites (must-stay-green per mission)

`test-dispatch-reentry-self-race.sh` — unchanged, still green:
```
[TEST] PASS: R-a: no lane_is_live refusal for this run's own row
[TEST] PASS: R-b: foreign live lane still refuses (rc=5)
[TEST] PASS: R-b: WORK_ROOT never pinned for the foreign row
[TEST] PASS: R-b: lane_is_live reason present for the foreign row
test-dispatch-reentry-self-race: 6 passed, 0 failed
```
rc=0

`test-leadv2-lane-state.sh` cases 1-5 — unchanged, still green:
```
[TEST] PASS: case1: live lead-owner row at repo root -> no recovered row for the lane
[TEST] PASS: case2: bystander not adopted; unowned pid-less recovered_unowned row registered
[TEST] PASS: case2b: unowned row not killed for being pidless on the next pass
[TEST] PASS: case3: genuine orphan with proven owner recovered with the right pid
[TEST] PASS: case4: unowned recovered row past LEADV2_RECOVERED_UNOWNED_TTL_SEC (900s, mirrors the registry pending window) is expired -> no longer pending -> cannot refuse a lane
[TEST] PASS: case5-RED: mutant (known-matching reverted) recovered 1 spurious row(s) — suite shows its own red: 1 != 0
[TEST] PASS: case5-GREEN: restored lib, case1 clean again (0 spurious rows)
[TEST] test-leadv2-lane-state: 7 passed, 0 failed
```
rc=0

## Self-registration check (DoD gate (c))

```
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh --scope changed | grep test-lane-mention-argv0
leadv2-lane-state.sh:plugins/leadv2/scripts/tests/test-lane-mention-argv0.sh
leadv2-lane-liveness.sh:plugins/leadv2/scripts/tests/test-lane-mention-argv0.sh
```
No `EXTRA_SUITE_MAP` entry needed — the file lives at
`plugins/leadv2/scripts/tests/test-*.sh`, one of the self-select path globs `run-all.sh` already
recognizes, and both edited stems (`leadv2-lane-state.sh`, `leadv2-lane-liveness.sh`) resolve to it.

## Changed-scope trigger set — full run, all green except two PRE-EXISTING reds

`LEADV2_RUN_ALL_LIST_TRIGGERS=1` names every suite the two edited stems (`leadv2-lane-state.sh`,
`leadv2-lane-liveness.sh`) trigger with an exact `<stem>.sh:` key. Ran all 14 (13 existing +
the new suite counted separately above):

| Suite | rc | Result |
|---|---|---|
| test-active-cache-liveness.sh | 0 | 2 passed, 0 failed |
| test-lane-adopt-writeset-refusal.sh | 0 | 10 passed, 0 failed |
| test-lane-alive-predicate.sh | 0 | pass=13 fail=0 skip=0 |
| test-lane-finished-state.sh | 1 | **PRE-EXISTING RED** — see below |
| test-lane-liveness-authoritative.sh | 1 | **PRE-EXISTING RED** — see below |
| test-lane-liveness-e0-contradiction.sh | 0 | 6 passed, 0 failed |
| test-lane-liveness-sentinel.sh | 0 | 16 passed, 0 failed |
| test-lane-verdict-pid-is-a-worker.sh | 0 | 2 passed, 0 failed |
| test-leadv2-lane-state.sh | 0 | 7 passed, 0 failed |
| test-liveness-tristate-01.sh | 0 | 14 passed, 0 failed |
| test-reap-funnel-death-proof.sh | 1 | **PRE-EXISTING RED** — see below |
| test-status-churn.sh | 0 | 13 passed, 0 failed |
| test-worktree-enforce-liveness.sh | 0 | 2 passed, 0 failed |
| tests/test-lane-state-self-resurrect.sh | 0 | 6 passed, 0 failed |
| test-dispatch-reentry-self-race.sh (explicit mission requirement) | 0 | 6 passed, 0 failed |

### Pre-existing reds — verified identical on unfixed base `ed30627c` (not this diff)

Verified by temporarily checking out `git show ed30627c:<path>` over both edited files (byte swap,
restored immediately after, `git diff --stat` confirmed the swap-back was exact), then re-running
each suite before touching anything else.

**`test-lane-liveness-authoritative.sh`** — same failure on `ed30627c` and on the fixed tree:
```
[TEST] FAIL: supervise emits log-only lane while registry is empty
```
(Unrelated code path — `leadv2-lanes-snapshot.sh` log-only union enumeration, not the
`registered_no_stream` rung this task touches.)

**`test-lane-finished-state.sh`** — same failures on `ed30627c` (ran to its own 60s test-level
timeout mid-suite, after producing the identical failure lines) and on the fixed tree:
```
Fixed tree:
[TEST] FAIL: Test 8: verdict=unknown:contradictory_rows (expected silent:* -- a live worker's lane must never read dead or finished)
[TEST] FAIL: Test 9: verdict=unknown:contradictory_rows (must be dead:* -- an alive-but-mismatched pid must never read alive)
[TEST] FAIL: Test 5a: pre-mutation baseline must be finished:* (got unknown:contradictory_rows) -- fixture broken, mutation gate aborted

Unfixed ed30627c (same run pattern, plus Test 7 before it):
[TEST] FAIL: Test 7: verdict=unknown:contradictory_rows (must be dead:*, never starting:* -- the stuck-starting incident)
[TEST] FAIL: Test 8: verdict=unknown:contradictory_rows (expected silent:* -- a live worker's lane must never read dead or finished)
[TEST] FAIL: Test 9: verdict=unknown:contradictory_rows (must be dead:* -- an alive-but-mismatched pid must never read alive)
[TEST] FAIL: Test 5a: pre-mutation baseline must be finished:* (got unknown:contradictory_rows) -- fixture broken, mutation gate aborted
```
Identical `unknown:contradictory_rows` signature both sides — an E0-contradiction-guard fixture
issue unrelated to the mention-test / starting-grace code this task touches.

**`test-reap-funnel-death-proof.sh`** — same single failure on both trees (only the SHA in the
fixture differs run-to-run, the failure *shape* is identical: `landedunscoped_unresolvedunknown`):
```
Fixed tree:   C12a: expected landed with sha 83eeac576fc579ae5def617b52d40627b007be58, got: landedunscoped_unresolvedunknown
Unfixed tree: C12a: expected landed with sha 9d900760a95ea5e6c1a8344d44b8d97efbb74793, got: landedunscoped_unresolvedunknown
```
28 passed / 1 failed on both trees.

## Self-check (bash -n / py_compile)

```
$ bash -n plugins/leadv2/scripts/leadv2-lane-liveness.sh && echo OK-liveness
OK-liveness
$ bash -n plugins/leadv2/scripts/lib/leadv2-lane-state.sh && echo OK-lanestate
OK-lanestate
$ bash -n plugins/leadv2/scripts/tests/test-lane-mention-argv0.sh && echo OK-newsuite
OK-newsuite
$ python3 -m py_compile <extracted heredoc body of leadv2-lane-liveness.sh> && echo OK-pycompile-liveness
OK-pycompile-liveness
$ python3 -m py_compile <extracted heredoc body of lib/leadv2-lane-state.sh> && echo OK-pycompile-lanestate
OK-pycompile-lanestate
```
(Both embedded Python bodies run inside a `python3 - … <<'PY' … PY` heredoc, not a hook
materialized-core `CORE=` blob — checked via `grep -n "CORE="` on both files, zero hits, so no
version pin to bump.)

## Left alone (out of scope, per prepass §8)

`_lv2_ws_pending` refusal semantics, the adoption predicate, `unowned_expired` TTL, the
`f853b0e3` self-pid branch, watcher reaping, status-surface rendering of `recovered_unowned`,
`hooks.json`. No drive-by refactors.

## LANE_WRITES

```
plugins/leadv2/scripts/lib/leadv2-lane-state.sh
plugins/leadv2/scripts/leadv2-lane-liveness.sh
plugins/leadv2/scripts/tests/test-lane-mention-argv0.sh
```
Matches the prepass's declared scope exactly; `git status --short` shows no other files touched.
