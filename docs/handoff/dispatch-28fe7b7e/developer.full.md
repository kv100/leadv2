verdict: APPROVE
next_action: review_round_2

# IDLE-LEAD-GUARD-01 fix round 2 — implementation report

Result: **PASS**. Base rebase: `git fetch origin && git rebase origin/main` — no-op,
worktree was already at `origin/main`. Resulting SHA: `c4a6dda70b63ebc05294a2dd563262b62012711b`
(unchanged from round 1's base).

## Changed paths (matches LANE_WRITES exactly)

- `plugins/leadv2/hooks/leadv2-idle-lead-guard.sh` — F1, F2, F4, F5.1
- `plugins/leadv2/hooks/leadv2-idle-guard-arm.sh` *(new)* — F5.2
- `plugins/leadv2/hooks/hooks.json` — registered the SessionStart entry
- `plugins/leadv2/scripts/tests/test-idle-lead-guard.sh` — F3, 6 new cases (11-16)

No file outside this set was touched. Out-of-scope items named in the design
(`leadv2-state-path.sh`, `leadv2-lane-liveness.sh`, `leadv2-tasks-lib.sh`,
`leadv2-idle-notification-filter.sh`, other hooks, docs/leadv2 or docs/handoff
content besides this task's own, the plugin cache under `~/.claude/plugins/`)
were left alone.

## F1 — counter that cannot persist must not block

Added `persist_count()` (write + read-back verification, returns 1 on any
mismatch/failure) and rewrote `allow_stop()` into a helper that takes an
optional stderr reason, resets the counter best-effort, and exits 0 with no
stdout. The block call site now does:

```
new_count=$(( count + 1 ))
if ! persist_count "$new_count"; then
  allow_stop "IDLE-LEAD-GUARD: counter not persistable at ${COUNTER_FILE} — cap cannot count, allowing stop."
fi
```

Verified live: `chmod 555` on the state dir, 10 consecutive hook invocations
with 1 queued row + 0 live lanes → every call empty stdout (test case 11).

## F2 — unresolvable question dir must allow

Rewrote lines 90-117 to track `QDIR_RESOLVED` separately from "dir exists".
Unresolved (script absent/failed/timeout) → `allow_stop` with a stderr line
naming the cause. Resolved-but-absent → proceeds (no question store exists,
not evidence of uncertainty — this is the design's one deliberate non-allow
branch on uncertainty, and case 13 pins it). The pending-question python scan
now returns `"yes <id>"` / `"no"` instead of `"yes"`/`"no"`, so the id
threads into the `allow_stop` reason: `founder question pending (${qid})`.

Verified live: absent `leadv2-state-path.sh` sibling + a real pending
question + no `QUESTIONS_DIR` override → empty stdout, stderr contains
`questions dir unresolvable` (case 12). Resolvable QDIR + pending question →
empty stdout, stderr contains `question pending` and the id `q001` (case 13).

## F4 — stop_hook_active + counter TTL

- stdin parser now emits a third line (`stop_hook_active` as `true`/`false`),
  captured into `STOP_HOOK_ACTIVE`, appended to every stderr diagnostic
  (`allow_stop` reasons, the cap-reached line, and a new block-path stderr
  line) as `[stop_hook_active=<true|false>]`. Never read for control flow —
  R7 comment amended to say exactly that.
- `LEADV2_IDLE_GUARD_COUNTER_TTL_S` (default 3600): counter file mtime older
  than the TTL → treated as `count=0`. Age-read failure → treated as fresh
  (keeps counting toward the cap, the conservative direction per the design).
- Reaper: `leadv2-idle-guard-arm.sh` deletes `leadv2-idle-guard-*.count`
  files older than 24h at every SessionStart, best-effort.

## F5.1 — goal/done-state terminator

New optional `docs/leadv2/session-goal.yaml` (override:
`LEADV2_IDLE_GUARD_GOAL_FILE`, used by tests). Three predicate keys only —
`tasks_absent`, `tasks_status`, `file_exists` — ANDed, no shell/command
field. Evaluated as condition (d), inserted after the pending-question check
and before condition (a); the `TASKS_FILE` resolution block was moved up
ahead of it so both (d) and (a) share one resolution. Unparseable file or an
unknown predicate key → treated as satisfied (allow), per the design's
"never widen the block surface" rule.

As stated in the design: this implements the *terminator* half only. An
unreached goal does **not** extend the loop past an empty queue —
implementing that would make `{"decision":"block"}` reachable with zero
queued rows, the exact wedged-session failure this round exists to prevent.

Verified live:
- `file_exists` pointing at a file that exists + queued row + 0 live →
  `goal reached ("...")`, empty stdout (case 16, also manually against a
  freshly built fixture).
- `tasks_status` unsatisfied + queued row + 0 live → still blocks (case 15).

**Deviation from the design's own case-15 fixture, made explicitly and
documented in the test file's comment:** the design specifies
`tasks_status: {task-aaa: queued}` as the "unsatisfiable" goal for case 15.
Under the exact-match `tasks_status` semantics the design itself defines in
§5.1 (`{ IDLE-LEAD-GUARD-01: done } # exact status match`), that predicate is
*trivially satisfied* — the fixture's `task-aaa` genuinely has status
`queued` — which is the opposite of what the case is supposed to prove
("goal present, not reached, still blocks"). I implemented `tasks_status`
literally per the design's own contract and changed the case-15 fixture
value to `{task-aaa: done}` (genuinely unsatisfied, since the task is queued
not done). This is a fixture correction, not a semantics change — the
predicate-evaluation code matches the design exactly.

## F5.2 — SessionStart arming

`plugins/leadv2/hooks/leadv2-idle-guard-arm.sh` (new), registered as the last
entry in `hooks.SessionStart[0].hooks[]`, after `leadv2-one-copy-drift.sh`.
Does, in order: kill-switch check, stdin parse, the same project gate as the
Stop hook, remove this session's counter file (fresh cap budget), reap
24h-stale counter files (glob anchored to `leadv2-idle-guard-*.count`, never
bare `*`), and — if `docs/leadv2/session-goal.yaml` exists and parses to a
named goal — emit an `additionalContext` SessionStart payload naming the
goal and the release conditions. Verified live with a hand-built fixture
(payload piped in, checked JSON output and rc=0).

**BLOCKED, partially, exactly as the design anticipates and requires
stating plainly:** the arming state (steps 1-4) is fully automatic. Igniting
the *first turn* of a hand-opened interactive session is not achievable from
any hook — `Stop` only fires after an assistant turn exists, and no hook
event produces an unprompted one; `SessionStart` can only inject context
consumed once a turn happens. On the path that actually matters — sessions
opened by dispatch (`claude -p "<mission>"`) — the dispatch prompt itself is
turn 1, so the loop is self-sustaining with no human keystroke. An
out-of-session driver for the hand-opened case is out of scope per the
design (§8).

## F3 — tests

Added `setup_hook_copy_without_statepath()` (copies the hook into an
isolated `hooks/` dir whose sibling `scripts/` has no
`leadv2-state-path.sh`) and gave `run_hook()` an optional 3rd arg (hook path
override, default `$HOOK_SH`) so cases 1-11, 13-16 are unaffected. Extended
`cleanup()` to `chmod 755` `$FIXTURE_STATE` and `chmod -R u+w "$TMPROOT"`
before `rm -rf`, so case 11's `chmod 555` doesn't leak a temp dir.

New cases 11-16 (see design for full spec): unwritable state dir → allows on
all 10 calls; unresolvable questions dir with a real pending question →
allows, stderr names the cause; resolvable QDIR + pending question → allows,
stderr names the id; writable state dir still caps at 8/8 (regression
guard); unsatisfied goal doesn't suppress a legitimate block; satisfied
`file_exists` goal allows with `goal reached` in stderr.

### Test run 1 — against unmodified hook at c4a6dda

(Hook file swapped in-place for this run only, then restored — diff-verified
byte-identical afterward.)

```
[TEST] PASS: case 1: queued+0live blocks with reason naming task id
[TEST] PASS: case 2: queued+1live allows stop (empty stdout)
[TEST] PASS: case 3: no queued work allows stop
[TEST] PASS: case 4: pending question allows stop
[TEST] PASS: case 5: 8 blocks then 9th allows with cap warning
[TEST] PASS: case 6: kill switch allows stop silently
[TEST] PASS: case 7a: malformed stdin allows stop
[TEST] PASS: case 7b: deleted tasks.yaml allows stop
[TEST] PASS: case 7c: absent liveness probe allows stop
[TEST] PASS: case 7d: unavailable liveness allows stop
[TEST] PASS: case 8: no docs/leadv2/ allows stop
[TEST] PASS: case 9: counter resets on allow, re-blocks from 1
[TEST] PASS: case 10: hooks.json has idle-lead-guard last after promise-guard
[TEST] FAIL: case 11: expected empty stdout on every call, got: call2=NONEMPTY({"decision": "block", "reason": "IDLE-LEAD-GUARD: 1 queued row(s), 0 live lanes, no pending question. Next: dispatch task-aaa (Implement feature A). Cap: 1/8. Kill: LEADV2_IDLE_GUARD=0."}) call5=NONEMPTY(...) call10=NONEMPTY(...)
[TEST] FAIL: case 12: expected empty stdout + 'questions dir unresolvable' stderr, got: out={"decision": "block", ...} err=
[TEST] FAIL: case 13: expected empty stdout + 'question pending (q001)' stderr, got: out= err=
[TEST] PASS: case 14: writable state dir still reaches cap at 8/8
[TEST] PASS: case 15: unsatisfied goal does not suppress a legitimate block
[TEST] FAIL: case 16: expected empty stdout + 'goal reached' stderr, got: out={"decision": "block", ...} err=

[TEST] idle-lead-guard: PASS=15 FAIL=4
```

(Case 13 FAILs at c4a6dda not because it blocks — the old hook's
pending-question check already allows correctly when QDIR resolves — but
because the old code emits no stderr reason at all, so the new
id-in-stderr assertion has nothing to match. Case 16 FAILs because
`session-goal.yaml` support doesn't exist at c4a6dda, so the goal is never
consulted and the guard blocks on the queued row instead.)

### Test run 2 — after the fix

```
[TEST] PASS: case 1: queued+0live blocks with reason naming task id
[TEST] PASS: case 2: queued+1live allows stop (empty stdout)
[TEST] PASS: case 3: no queued work allows stop
[TEST] PASS: case 4: pending question allows stop
[TEST] PASS: case 5: 8 blocks then 9th allows with cap warning
[TEST] PASS: case 6: kill switch allows stop silently
[TEST] PASS: case 7a: malformed stdin allows stop
[TEST] PASS: case 7b: deleted tasks.yaml allows stop
[TEST] PASS: case 7c: absent liveness probe allows stop
[TEST] PASS: case 7d: unavailable liveness allows stop
[TEST] PASS: case 8: no docs/leadv2/ allows stop
[TEST] PASS: case 9: counter resets on allow, re-blocks from 1
[TEST] PASS: case 10: hooks.json has idle-lead-guard last after promise-guard
[TEST] PASS: case 11: unwritable state dir allows stop on all 10 calls (call2=empty call5=empty call10=empty )
[TEST] PASS: case 12: unresolvable questions dir allows stop, stderr names it
[TEST] PASS: case 13: pending question allows stop, stderr names id
[TEST] PASS: case 14: writable state dir still reaches cap at 8/8
[TEST] PASS: case 15: unsatisfied goal does not suppress a legitimate block
[TEST] PASS: case 16: satisfied file_exists goal allows stop

[TEST] idle-lead-guard: PASS=19 FAIL=0
```

## Other verification

- `/bin/bash -n` clean on all three shell files (bash 3.2 compatibility —
  no associative arrays, no `${x^^}`, no `readarray` used anywhere in the
  diff).
- `python3 -c "json.load(...)"` on `hooks.json` — valid.
- `git status --short` confirms exactly the four expected paths changed
  (three modified, one new — `leadv2-idle-guard-arm.sh`).
- Manually piped SessionStart payloads through `leadv2-idle-guard-arm.sh`
  against hand-built fixtures (goal present/absent, satisfied/unsatisfied)
  and confirmed both the `additionalContext` JSON shape and rc=0.

## Left alone / explicitly out of scope

Everything listed in the design's §8, plus: no commit/push (per this repo's
standing rule — work stays in the worktree for lead review); no change to
`leadv2-state-path.sh`, `leadv2-lane-liveness.sh`, `leadv2-tasks-lib.sh`, or
any other hook; no docs/leadv2 or docs/handoff content besides this task's
deliverable and the throwaway fixtures under `/tmp` used for manual
verification.

DELIVERABLE_COMPLETE
