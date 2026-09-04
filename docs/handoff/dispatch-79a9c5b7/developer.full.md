verdict: APPROVE
next_action: review_round_2

# CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01 — developer report

## Starting point

This lane already had uncommitted work from a killed prior worker, rescued verbatim by the
lead as commit `74c13cd6`. I read it (`git show HEAD`), judged it (not trusted blindly), ran it,
and found the arbiter logic itself sound and well-argued. I kept it with no functional edits.
I found and fixed one real defect: the rescue commit had incidentally bundled off-limits
runtime-state file diffs into the lane's history. That is fixed in a follow-up commit
(`30e021de`), described below.

## What the previous worker built (kept as-is)

`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` — `route_arbiter()`:

1. **Source of truth (brief item 1).** `leadv2-quota-read.py:113-142`
   (`normalize_window` / `with_window_truth`) already computes `hours_to_reset` and embeds it
   into the same JSON `leadv2-quota-live.sh json` returns for glm/codex/anthropic — confirmed by
   reading the function body directly (line-cited in a comment in the arbiter, and independently
   verified: `normalize_window(used_pct, reset_iso)` returns
   `{'remaining_pct': None, 'hours_to_reset': None, 'usable_now': None}` on a missing/malformed
   `reset_iso`, never a zero). No new fetcher was written — `window_period_hours()` /
   `window_reset()` in the arbiter only *read* that existing field. kimi carries no reset because
   `config/leadv2-routing.yaml` marks it `dispatch: false` — it is not a live build arm, confirmed
   by grep, no fetcher needed for it either.
   Missing-reset default: degrades to the window's own full period (5h for `five_hour`, 168h for
   `weekly`/`seven_day`, else `DEFAULT_PERIOD_HOURS=168.0`) — always outside the 10% wait
   threshold, so an unknown reset can never fabricate an imminent wait. Never a silent zero.

2. **Journal line (brief item 2).** The winning arm's line now carries
   `remaining=<pct> reset_in=<h>h reset_basis=<live|default_full_period>` plus, when any
   provider was waited on instead of switched, `wait_applied=<providers>`. Refusal lines
   (`reason=all_arms_capped`) also carry `reset_<provider>=` for every provider via `ufmt()`, so a
   refused round is diagnosable from the journal too, not just a win.

3. **Wait vs switch rule (brief item 3).** `WAIT_FRACTION_OF_PERIOD=0.10` — wait if
   `hours_to_reset <= period_hours * 0.10`, else switch. This is not picked free-hand: it
   reproduces both founder examples exactly against the two live period shapes (5h burst window,
   168h weekly window):
   - 20 min left on a 5h window: 0.1×5h = 30min; 20min ≤ 30min → WAIT (founder's example).
   - 4 days left on a 7-day window: 0.1×168h = 16.8h; 96h > 16.8h → SWITCH (founder's example).
   An over-ceiling provider whose binding window is near reset is NOT excluded from `capped()` —
   it stays in the running and is only picked again if still cheapest; a far-reset over-ceiling
   provider is capped exactly as before (unchanged behaviour, verified by test case (b)).

## What I verified end-to-end

- `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` — `bash -n` clean.
- `plugins/leadv2/scripts/leadv2-quota-read.py` — `python3 -m py_compile` clean.
- `plugins/leadv2/scripts/tests/test-quota-reset-arbiter.sh` — `bash -n` clean, and it is the
  test suite (not something I wrote from scratch — I re-ran and read it in full to confirm its
  assertions are real, not vacuous).

Suite content (7 cases): (a) near-reset over-ceiling glm waited on; (b) far-reset over-ceiling
glm switches away as before; (c) journal line carries `remaining=`/`reset_in=` for the winner;
(d) refusal path still names `reset_<provider>=` per provider; (e) negative control; (e2) revert;
(f) reader-level default for a missing/malformed reset is `None`, never zero.

### Negative control location

The mutation (`sed 's/WAIT_FRACTION_OF_PERIOD=0.10/WAIT_FRACTION_OF_PERIOD=0.0/'`) targets a line
inside `route_arbiter()`, which spans lines 18-367 of the arbiter file (verified: `grep -n
"^route_arbiter\|^}"` shows the function opening at 18 and its closing brace at 367; the mutated
assignment sits well inside that range, inside the python heredoc the function emits). It is
applied to a **private temp copy** (`$TMP/mutated-route-arbiter.sh`), never the tracked file, so a
mid-test crash cannot leave the repo dirty for a concurrent lane.

### macOS run

```
$ bash plugins/leadv2/scripts/tests/test-quota-reset-arbiter.sh
PASS: (a) near-reset over-ceiling glm is waited on, not switched away
PASS: (b) far-reset over-ceiling glm switches away as before
PASS: (c) journal line carries remaining= and reset_in= for the winning arm
PASS: (d) refusal path still names each provider reset_<provider>=
PASS: (e RED) threshold=0 mutation flips case (a) to switch -- control is load-bearing
PASS: (e2 GREEN) revert to the real file: green again
PASS: (f) reader-level normalize_window degrades a missing/malformed reset to unknown, never zero
SUMMARY: pass=7 fail=0
MACOS_EXIT=0
```

### Linux container run

`docker run --rm -v "$(pwd)":/repo -w /repo bash:5.2 ...` (Alpine, GNU bash 5.2.37,
aarch64-unknown-linux-musl). First attempt failed with rc=2 and zero output — root-caused (not a
script bug): the arbiter's python3 block does `import yaml` inside the sourced heredoc, and the
bare Alpine `python3` apk package ships no PyYAML, so the script's own documented fail-open
contract (`# non-zero means caller must fail open`, line 3) fired silently. This is an
environment gap in the vanilla `bash:5.2` image, not a regression — installing `py3-yaml`
resolved it (probe: `apk add --no-cache python3 py3-yaml`; `python3 -c "import yaml;
print(yaml.__version__)"` → `6.0.2`, rc=0).

```
$ apk add --no-cache python3 py3-yaml >/tmp/apk.log 2>&1
$ bash /repo/plugins/leadv2/scripts/tests/test-quota-reset-arbiter.sh
PASS: (a) near-reset over-ceiling glm is waited on, not switched away
PASS: (b) far-reset over-ceiling glm switches away as before
PASS: (c) journal line carries remaining= and reset_in= for the winning arm
PASS: (d) refusal path still names each provider reset_<provider>=
PASS: (e RED) threshold=0 mutation flips case (a) to switch -- control is load-bearing
PASS: (e2 GREEN) revert to the real file: green again
PASS: (f) reader-level normalize_window degrades a missing/malformed reset to unknown, never zero
SUMMARY: pass=7 fail=0
LINUX_EXIT=0
```

## Suite registration + --scope changed proof

`tests/run-all.sh` `EXTRA_SUITE_MAP` (already edited by the prior worker) carries:

```
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-quota-reset-arbiter.sh
```

Proof that `--scope changed` actually selects it (the checkpoint state file at
`.git/worktrees/<lane>/leadv2-run-all-last-checked-sha` had already been consumed past HEAD by an
earlier full run I killed for being slow — reset it to `git merge-base main HEAD` to re-verify a
non-empty range, per the documented convention that this state file is consumed per run):

```
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-route-arbiter-symlink-install.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-quota-reset-arbiter.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-freepool-gets-work.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-arm-admission.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-effort-routing.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-complexity-routing.sh
[SELECT] .../tests/test-run-all-carrier-map.sh
run-all: 13 selected, scope=changed, select_only=1
```

`test-quota-reset-arbiter.sh` is selected (both via its own `test-*.sh` self-select convention
and via the `leadv2-route-arbiter` stem mapping). I did not run the full `run-all.sh` suite
end-to-end (it took >120s and was auto-backgrounded; unrelated suites are not this task's scope
and the select-only proof above is the actual claim item 5 asks for — suite *selection*, not a
full-repo green run).

## Defect found and fixed: off-limits runtime-state churn in the rescue commit

`git diff --stat main...HEAD` (three-dot, merge-base-relative — the mission explicitly warns that
two-dot diffs against a moving `main` show other lanes' unrelated commits) showed the rescue
commit `74c13cd6` had also touched, beside the real arbiter work:

- `docs/LEAD_V2_STATE.md` (a stale `Last updated` / active-task row)
- `docs/leadv2/{.bus-offsets,.bus.lock,.merge.lock,active.yaml,active.yaml.lock,bus.jsonl,
  merge-queue.jsonl,open-threads.md,questions}` — all symlinks whose targets were stale
  `/var/folders/.../core-offline-run.<X>/...` paths left over from a prior test run
- a new, unrelated `docs/leadv2/.compact-freeze.md`

These are exactly the paths the DoD gate (item d) and the lane's off-limits list forbid touching.
Root cause: they were dirty in the shared worktree at the moment the lead ran the rescue commit
and got swept in incidentally along with the real diff — not anything I or the previous worker
wrote intentionally.

Fix (commit `30e021de`): `git checkout main -- <those paths>` to restore them to main's content,
and removed the stray `.compact-freeze.md`. Verified after the fix:

```
$ git diff --stat "$(git merge-base main HEAD)"
 .../SUBSCRIPTION-MIX-DECISION-01/assessment-glm.md | 227 +++++++++++++++++++++
 plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 103 ++++++++--
 .../scripts/tests/test-quota-reset-arbiter.sh      | 164 +++++++++++++++
 tests/run-all.sh                                   |   6 +
 4 files changed, 488 insertions(+), 12 deletions(-)
$ git diff --diff-filter=D --name-only main...HEAD
(empty — no deletions)
```

The one remaining non-task file, `docs/handoff/SUBSCRIPTION-MIX-DECISION-01/assessment-glm.md`,
is not a runtime-state path and not something I added: it shows as "added" only because this
lane's merge-base (`8b630a30`) predates it landing independently on `main`'s current tip via
another lane, with identical content. It is a merge no-op, not a conflict, and outside this
lane's off-limits list, so I left it alone.

## What I kept vs rewrote

- **Kept unchanged:** the entire arbiter diff (`window_period_hours`, `window_reset`, `util()`
  restructuring to carry `hours_to_reset`/`period_hours`/`reset_basis` per provider,
  `near_reset_wait()`, the `capped()` wait exemption, the journal `_quota`/`_wait` fields) and the
  full `test-quota-reset-arbiter.sh` suite (7 cases) and the `run-all.sh` `EXTRA_SUITE_MAP` row —
  all from the previous worker, verified correct by running them, not assumed correct.
- **Rewrote:** nothing functional. Added one follow-up commit solely to strip the off-limits
  runtime-state file churn described above.

## Off-limits respected

Did not touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
`plugins/leadv2/scripts/leadv2-ratelimit-probe.sh`, or the `rate_limit_anthropic` write path.
Did not add anything to `tests/known-red-suites.txt`. Did not weaken any assertion. No credential
value was ever printed or logged (fixtures use forged pct/reset numbers, no account tokens).

DELIVERABLE_COMPLETE
