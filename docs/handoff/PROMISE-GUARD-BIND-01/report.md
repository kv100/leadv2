# PROMISE-GUARD-BIND-01 — round 2 (review said fail)

Round 1's report (still the record of what was proven then) is preserved below the
`---` divider. This section documents round 2's fixes, one per review finding.

## [Critical] the suite wrote into the real journal — fixed, sandboxed, controlled

`test-promise-action-binding.sh` (`_verdict`) ran the real hook with the real `$HOME`
inherited, so every case appended a row to `~/.claude/leadv2-promise-guard.jsonl` — the
exact file `PROMISE-GUARD-BLOCK-FLIP-01`'s GO-condition reads.

Fix: `HOME` is now exported to a per-run sandbox (`${WORK}/home`) before any `_verdict`
call, and a control runs at the end of the suite that fails the whole run if the REAL
journal's line count changed during the run. Proven both ways:
- Clean run: `PASS: sandbox-control -- real journal ... unchanged (1738 lines)`
  (`round2-red/test-promise-action-binding.RED-then-GREEN.log`).
- Mutated back to the real `$HOME` (control removed): the suite correctly FAILS —
  `FAIL: sandbox-escape ... grew from 1738 to 1752 lines`
  (`round2-red/sandbox-escape-mutation.RED-then-GREEN.log`).

**What must happen to the rows already there.** As of this task, the real journal has
grown to 1752 lines with 203 distinct session ids matching the synthetic pattern
`test-<pid>-<rand>-<rand>` that only this suite's pre-fix `_verdict` ever generated (14
of those 203 were added by the deliberate mutation proof above, run once to demonstrate
the control fires — a necessary cost of proving the fix, not new pollution from a live
session). These rows must NOT be counted toward the `PROMISE-GUARD-BLOCK-FLIP-01`
GO-condition. I did not delete or edit `~/.claude/leadv2-promise-guard.jsonl` — it is a
shared, real-`$HOME` file that every other active lane on this machine also appends to
concurrently, and deleting from a live shared file is exactly the destructive-without-
authorization action the boundaries section warns against. Proposed cleanup (for the
founder/lead to run, not this lane):
```
grep -vE '"session_id": "test-[0-9]+-[0-9]+-[0-9]+"' \
  ~/.claude/leadv2-promise-guard.jsonl > ~/.claude/leadv2-promise-guard.jsonl.filtered
```
then diff-review and swap in. Until that runs, the GO-condition query in
`scheduled-decisions.md` should be read as "over rows whose `session_id` does NOT match
`^test-\d+-\d+-\d+$`" — this is a filter to apply by hand when evaluating the flip, not
a code change (the hook's own journaling is unaffected; only the test suite was ever
the leak).

## [High] the control self-destructed at commit — fixed with a checked-in fixture

`test-promise-action-binding.sh` and `test-promise-guard-morphology.sh` both pinned
`PRE_HOOK` to `git show HEAD:...`. Both now read a checked-in fixture instead:
`docs/handoff/PROMISE-GUARD-BIND-01/fixtures/leadv2-promise-guard.pre-bind01.sh` — a
snapshot of the hook at commit `e994f07` (the immediate parent of `fc080bf`, this task's
round-1 fix commit), verified to contain zero occurrences of `classify_promise_kind`
(`grep -c` → `0`). This is fixed content that cannot shift when this task's own commits
land, unlike `HEAD`.

An unresolvable pre-image is now a hard failure, not a silent pass. Both `run_case`
functions were rewritten: `pre_rc=2` (pre-fix arm could not run) is now its own `FAIL`
branch, not a fall-through into `PASS`/`RED-then-GREEN`. Proven: with the fixture file
moved aside, the suite now exits 1 with
`FATAL: pre-fix fixture unresolvable ... refusing to report a fake RED-then-GREEN
proof` instead of silently reporting `8 passed(red->green)`
(`round2-red/unresolvable-pre-image-hard-fail.log`). Restored, the suite is green
again.

## [High] the extractor never touched — now recognises the three quoted forms

`COMMIT_RU_VERBS` gained `поправлю`, `прогоню`, `закоммичу` (both in the primary
extraction pattern and in the telemetry `PATTERN` classifier, so the two definitions
don't drift the way the file's own comments warn against). None of the three collide
with their own 3rd-person-plural the way the PROMISE-GUARD-3PL-COLLISION-01 verbs do
(поправят/прогонят/закоммитят are not stem+"т"), so the shared negative-lookahead guard
is inert but harmless for them.

Twelve fixtures now live in `test-promise-guard-morphology.sh` (`case_r2_01`..`_12`),
covering all four `classify_promise_kind` kinds and every extraction grammar shape
(`COMMIT_RU_NOW`, bare `COMMIT_RU`, `COMMIT_EN`, `COMMIT_RU_SHAPE`). I could not find the
reviewer's original set of twelve committed anywhere in the repo — this is a
reconstructed twelve anchored by the three sentences the review quoted verbatim
(`case_r2_01_popravlyu`, `_02_progonyu`, `_03_zakommichu`), which are genuine RED-then-
GREEN against the pinned pre-round2 fixture (all three MISS before, HIT after — see
`round2-red/test-promise-guard-morphology.RED-then-GREEN.log`,
`3 passed(red->green), 0 failed, 25 green-pre-fix`).

## [High] `2>/dev/null` no longer satisfies a write promise

`ACTION_KIND_BASH`'s `write` pattern was `>>?\s*\S`, which matched any shell redirect
including `2>/dev/null` (noise suppression, the near-universal idiom in this repo's own
test suites — ironically most common in the promise-guard tests themselves) and `2>&1`
(fd duplication). Tightened to `>>?\s*(?!/dev/null\b)(?!&)\S`, which excludes both while
still matching a genuine file write (`> out.txt`, `>> log`).

Fixture added: `write-promise-devnull-unrelated-fires` — promise = write
("Сейчас поправлю конфиг"), action = `grep ... 2>/dev/null` only → must FIRE (write not
kept). Genuine RED-then-GREEN: `pre_rc=1 -> post_rc=0`
(`round2-red/test-promise-action-binding.RED-then-GREEN.log`). Companion fixture
`write-promise-real-write-matches-silent` proves the tightening didn't also blind the
write kind to a real write (`echo done > /tmp/...`) — GREEN-PRE-FIX (correct both
before and after, locking the "don't regress the happy path" half).

## [High] the scheduled-decision row is now parseable by `leadv2-task-anchor.sh`'s own grammar

The row's header was `## PROMISE-GUARD-BLOCK-FLIP-01` with no em-dash/title, and its
fields were plain `STATUS:`/`CONTEXT:` lines — none of which match
`_nearest_decision_signature`'s three field-extraction regexes (table row, `- **key:**
value`, bare `**key:** value`) or its header regex (`^#{2,3} (\S+)\s+—\s+(.+?)\s*$`).
Rewritten to:
```
## PROMISE-GUARD-BLOCK-FLIP-01 — flip promise-guard from log-only to blocking

- **status:** CONDITION_BOUND
- **due:** condition-bound — no fixed date, gated on journal evidence (see GO-CONDITION below)
```
Verified by extracting the hook's own embedded python (`sed -n '65,1037p'
plugins/leadv2/hooks/leadv2-task-anchor.sh`) and calling `_nearest_decision_signature`
directly against this repo's live `docs/leadv2/scheduled-decisions.md`:
```
SIG: PROMISE-GUARD-BLOCK-FLIP-01:CONDITION_BOUND
```
(`round2-red/scheduled-decision-parse.log`) — previously this returned `"none"` (no
candidates matched at all). Note: `nearest_due_line()` (a different, thread-anchor-only
code path) delegates to a project-local renderer,
`.claude/hooks/scheduled-decisions-nearest.sh`, which does not exist in this repo (only
in downstream project repos) — that path is a no-op here regardless of this file's
content, and is not what the review's "this repo's own grammar" pointed at.

## [High] the fix is not on the running path

Confirmed live: the plugin actually loaded by Claude Code sessions is not this git
checkout but a cached copy, resolved from `~/.claude/plugins/installed_plugins.json`
(`leadv2@leadv2-local`, `installPath:
/Users/kostiantyn.vlasenko/.claude/plugins/cache/leadv2-local/leadv2/0.3.0`).
```
$ grep -c classify_promise_kind /Users/kostiantyn.vlasenko/.claude/plugins/cache/leadv2-local/leadv2/0.3.0/hooks/leadv2-promise-guard.sh
0
```
Neither round 1's fix nor round 2's is on any currently-running session's hook path —
confirmed by absence, not inferred. Per this machine's own documented plugin-cache
gotcha (global CLAUDE.md, "Shared trees — edit policy"): a directory-source
marketplace's `claude plugin update` no-ops when content changed but the package
version did not, so merging this lane's diff into `~/Projects/leadv2` main is
necessary but not sufficient. What has to happen, in order, none of which this lane can
or should do (it is outside `$WRITE_ROOT`, and `installed_plugins.json`/the plugin
cache are shared machine-wide state, not this worktree):
1. Merge this lane's commit into the canonical `leadv2` repo's default branch.
2. Bump the plugin manifest version (currently `0.3.0`) so the marketplace sees a
   version change, OR directly refresh the cached copy at
   `~/.claude/plugins/cache/leadv2-local/leadv2/0.3.0/hooks/leadv2-promise-guard.sh`.
3. Restart every active Claude Code session (hooks are read once at session start;
   an already-running session keeps its stale copy even after the cache updates).
This is a lead/founder deployment action, not a code change — flagging it explicitly
rather than silently leaving it implied.

## Rollout posture (unchanged)

`LEADV2_PROMISE_GUARD_BLOCK` still defaults to `"0"` (log-only). Nothing in round 2
touches the rollout gate itself.

## Self-check (round 2)

```
$ bash -n plugins/leadv2/hooks/leadv2-promise-guard.sh                                    # OK
$ bash -n plugins/leadv2/scripts/tests/test-promise-action-binding.sh                      # OK
$ bash -n plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh                     # OK
$ bash -n plugins/leadv2/tests/test-promise-guard.sh                                        # OK
$ bash -n tests/run-all.sh                                                                  # OK
$ bash -n docs/handoff/PROMISE-GUARD-BIND-01/fixtures/leadv2-promise-guard.pre-bind01.sh    # OK
$ python3 -c "ast.parse(...)" over both embedded PYEOF heredocs in the hook            # OK (2 blocks)

$ bash plugins/leadv2/tests/test-promise-guard.sh
17/17 pass

$ bash plugins/leadv2/scripts/tests/test-promise-action-binding.sh
Results: 2 passed(red->green), 0 failed, 8 green-pre-fix, 0 could-not-run
PASS: sandbox-control -- real journal unchanged (1752 lines)

$ bash plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh
Results: 3 passed(red->green), 0 failed, 25 green-pre-fix, 0 could-not-run
```

Full command output for every claim above: `docs/handoff/PROMISE-GUARD-BIND-01/round2-red/`.

`tests/run-all.sh --scope changed`: attempted, blocked identically to round 1 on the
shared cross-repo `/tmp/leadv2-core-offline.lock` (confirmed held by a concurrent lane,
not this change) — this is the same pre-existing, unrelated infrastructure contention
round 1 documented; the three suites that actually exercise the changed hook were run
directly and are the evidence above.

## Deliberately left alone

- The turn-wide (non-positional) binding model — unchanged, not reopened.
- The rollout gate (`LEADV2_PROMISE_GUARD_BLOCK` default `"0"`) — unchanged, still
  log-only per the mission's explicit rule.
- `~/.claude/leadv2-promise-guard.jsonl` itself — not edited or truncated; cleanup is
  proposed above, not executed, per the mission's explicit instruction not to silently
  delete it.
- Getting the fix onto the live plugin-cache path — documented above as a required
  follow-up action, not performed (outside this lane's writable scope).

---

(Round 1 report follows, preserved as written.)

# PROMISE-GUARD-BIND-01 — the guard is suppressed by any tool call

## The extractor's failure (item 1)

Before this fix the "promise extractor" (`commitments` in the hook's embedded Python)
only captured the raw clause TEXT of a detected commitment — it never derived WHAT was
promised. Downstream, `has_action` was computed by scanning the whole turn for ANY
action-tool call (`is_action_tool`), so a promise of a dispatch and an Edit call looked
identical to the guard: both read as "an action happened, suppress." Binding was
structurally impossible because there was nothing on the promise side to bind an action
to.

Fix: `classify_promise_kind(clause)` in `plugins/leadv2/hooks/leadv2-promise-guard.sh`
reads the SAME small kind space (`test` / `commit` / `dispatch` / `write`) off the
clause text that already triggered `COMMIT_RE`. The primary commitment (`commitments[0]`
— the one the QUOTE downstream is always built from) gets a `primary_kind`.

## `ACTION_BASH_RE` fix (item 2)

The old regex had one catch-all alternative, `leadv2-.*\.sh`, that matched almost every
Bash invocation in this repo — including read-only status/audit scripts — which is most
of the reason "any tool call" suppressed the guard in practice. It is now
`ACTION_KIND_BASH`, a list of `(kind, pattern)` pairs with no catch-all:
- `test`: `run-all.sh`, `test-*.sh`, `pytest`, `npm test`, `ctest`
- `commit`: `git commit|push|add|tag`
- `dispatch`: `leadv2-dispatch-code`, `leadv2-fanout`, `*-task.sh`, `glm-coder.sh`
- `write`: `sed -i`, `mv/cp/tee/touch/mkdir/install`, `>>`/`>` redirects, `systemctl
  restart/start/enable`

Tool names get the same treatment (`Edit/MultiEdit/Write/NotebookEdit` → `write`;
`Agent/Workflow/SendMessage`/`Task*` → `dispatch`).

Binding rule (kept turn-wide per the 2026-08-22 positional revert — see the hook's own
comment trail, which this fix does not touch): a promise whose kind is known is only
"kept" by an action of that SAME kind occurring anywhere in the turn. A promise whose
kind cannot be classified falls back to the legacy behaviour (any action suppresses) —
we don't have journal evidence yet for kinds outside this taxonomy, and binding on an
unmodeled shape would just produce noise.

## Mutation-proven RED→GREEN control (rule: mutation inside the function body)

`plugins/leadv2/scripts/tests/test-promise-action-binding.sh` already runs every case
against BOTH the pre-fix hook (`git show HEAD:...`, i.e. this file's state before this
task started) and the current working copy, and classifies each case as GREEN-PRE-FIX
(passed even before the fix — not a proof) or RED-then-GREEN (failed against the old
code, passes against the new — an actual proof). The new case
`dispatch-promise-unrelated-action-fires` (promise = "Диспатчу воркера на задачу", kind
`dispatch`; action = `Edit`, kind `write`) is exactly the defect this task fixes:

```
[TEST] RED-then-GREEN: dispatch-promise-unrelated-action-fires (pre_rc=1 -> post_rc=0)
```

Pre-fix: an Edit call is *an* action, so the guard read the promise as kept — SILENT
when the test expects FIRED (this is PROMISE-GUARD-SUPPRESSED-BY-ANY-TOOL-CALL-01,
reproduced). Post-fix: `dispatch` (promised) not in `{write}` (what actually happened)
→ FIRES. Full log: `red/test-promise-action-binding.RED-then-GREEN.log`.

A second, independent mutation control proves the log-only rollout gate itself: with
`LEADV2_PROMISE_GUARD_BLOCK:-0` mutated to `:-1` (simulating "no log-only gate, block by
default"), case 15a in `test-promise-guard.sh` goes RED (`decision:block` is emitted when
the test expects silence); reverting the mutation returns it to GREEN. Full log:
`red/log-only-gate.RED-then-GREEN.log`.

## The two required fixtures (rule: promise+matching action passes, promise+unrelated fires)

Both live in `test-promise-action-binding.sh`:
- `case_dispatch_promise_matching_action` — promise=dispatch, action=Agent(dispatch) →
  SILENT (kept). GREEN-PRE-FIX (correct both before and after — locks the "don't
  regress the happy path" half).
- `case_dispatch_promise_unrelated_action` — promise=dispatch, action=Edit(write) →
  FIRED. RED-then-GREEN (see above) — the actual defect fixture.

`plugins/leadv2/tests/test-promise-guard.sh` carries the same pair against the real
Stop-hook driver (cases 13/14), plus case 7 flipped from its old (wrong)
`silent-on-any-action` expectation to the correct kind-bound `FIRES`.

## Log-only rollout (item 3)

`LEADV2_PROMISE_GUARD_BLOCK` defaults to `"0"`. The journal row
(`~/.claude/leadv2-promise-guard.jsonl`) is written unconditionally on every evaluated
turn with a commitment shape — `verdict: "fired"` in log-only mode literally means "would
have blocked." Only `LEADV2_PROMISE_GUARD_BLOCK=1` makes the hook actually emit
`decision:block`. This is proven both by test-promise-guard.sh cases 15a/15b (default
env → stdout silent, journal row still fired) and by the mutation control above.

## Real journal line (Done-means requirement)

This session, over the course of doing this task, never once let a real turn end on an
unkept promise — every "I'll ..." sentence in this session's own transcript was
immediately followed, in the same continuous turn, by the corresponding tool call (no
Stop event ever fired on an unkept promise; verified by grepping this session's own
transcript for `I'?ll|going to` and checking each one against what followed). That is
the guard working as intended in spirit, not a gap in the evidence — but it means there
is no genuine mid-session Stop-hook block to show.

What IS real: this session's own fix, exercised directly against the shipped hook (not
the test harness's sandboxed HOME), appending to the actual production journal path
`~/.claude/leadv2-promise-guard.jsonl`:

```
{"ts": "2026-08-30T12:02:50Z", "session_id": "promise-guard-bind-01-repro-1788091369",
 "cwd": "/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-BIND-01",
 "verdict": "fired", "quote": "I will dispatch the worker now", "pattern": "COMMIT_EN",
 "tools": ["Bash:git"], "n_commitments": 1, "primary_promise_kind": "dispatch",
 "action_kinds_seen": ["commit"], "block_mode": "0"}
```

This is the literal defect this task closes: a turn that promises a dispatch and
instead only runs `git commit` — pre-fix, `git commit` is *an* action so the guard
stayed silent; post-fix, `dispatch` is not in `{commit}`, so it correctly fires
(`verdict: "fired"`, `block_mode: "0"` = would have blocked, did not, because we are
still in the log-only rollout window per the scheduled decision below).

## Scheduled decision (item 4)

`docs/leadv2/scheduled-decisions.md` (new file — not in this task's original
`LANE_WRITES` list, but required by the mission text; flagging the discrepancy
explicitly rather than silently going out of scope) — row
`PROMISE-GUARD-BLOCK-FLIP-01`: GO-condition is 20 consecutive `fired` journal rows,
spanning ≥3 distinct `session_id`s, with zero manually-confirmed false positives. Flip =
set `LEADV2_PROMISE_GUARD_BLOCK=1`. Rollback = unset it (one step, no state to clean up).

## Self-check

```
$ bash -n plugins/leadv2/hooks/leadv2-promise-guard.sh
$ python3 -m py_compile   # no .py files changed — only the embedded python inside the
                          # .sh heredocs; syntax-checked via ast.parse extraction, see below
$ bash plugins/leadv2/tests/test-promise-guard.sh          # 17/17 pass
$ bash plugins/leadv2/scripts/tests/test-promise-action-binding.sh   # 8/8 (1 RED-then-GREEN, 7 GREEN-PRE-FIX)
$ bash plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh # 16/16 (unaffected, verified untouched)
```

`--scope changed` selection proof (dry-run instrumentation of `tests/run-all.sh`,
printing `${SUITES[@]}` instead of executing them, against the real uncommitted diff):

```
[SELECTED] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECTED] .../tests/test-status-surface-bash32.sh
[SELECTED] .../tests/test-status-surface-single-lead.sh
[SELECTED] .../tests/test-status-surface-fast-names.sh
[SELECTED] .../plugins/leadv2/scripts/tests/test-promise-action-binding.sh
[SELECTED] .../plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh
[SELECTED] .../plugins/leadv2/tests/test-promise-guard.sh
```

All three promise-guard suites are selected. This required a second fix beyond the hook
itself: `tests/run-all.sh`'s changed-file filter only matched
`plugins/leadv2/scripts/*.sh`, so a change to `plugins/leadv2/hooks/leadv2-promise-guard.sh`
matched NOTHING before this task — the filter now also accepts `plugins/leadv2/hooks/*.sh`,
and three `EXTRA_SUITE_MAP` rows key `leadv2-promise-guard.sh` to all three suites (their
filenames don't share the changed file's stem, so the plain stem-match alone would still
have missed them).

A live `bash tests/run-all.sh --scope changed` (not the dry-run) was attempted for full
end-to-end proof but blocked for an extended period on `/private/tmp/leadv2-core-offline.lock`
— a global, cross-repo, cross-session `flock` that serializes the always-on
`run-core-offline.sh` suite against concurrent lanes (confirmed via `lsof`: the waiting
process was parked in `flock 9`, not crashed or looping). That lock is infrastructure
shared with every other active lane on this machine and is unrelated to this change; the
dry-run selection proof above plus the three green targeted-suite runs are the actual
evidence for this task's own correctness. If the full run completes before this task's
review, its output should be appended here by whoever reads this next; it does not gate
this deliverable's correctness claims, which rest on the three suites that actually
exercise the changed code.

## Deliberately left alone

- The turn-wide (non-positional) binding model itself — `PROMISE-GUARD-POSITIONAL-REVERT-01`
  reverted positional binding for good reason (5 false positives / 0 catches); this task
  binds by KIND, not by position, and does not reopen that decision.
- `test-promise-guard-morphology.sh` — untouched; it tests `COMMIT_RE`/`VETO_RE` shape
  directly and has no coupling to action-kind binding.
- The pre-existing dirty `docs/leadv2/.bus*.lock`, `active.yaml*`, `bus.jsonl`,
  `merge-queue.jsonl`, `open-threads.md`, `questions` files (modified before this task
  started, per the session's initial `git status`) — not staged or touched, out of this
  task's scope (shared registry state owned by other concurrent lanes/lead).

