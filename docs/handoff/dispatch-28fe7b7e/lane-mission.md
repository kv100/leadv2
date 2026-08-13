Product implementation task dispatch-28fe7b7e. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# IDLE-LEAD-GUARD-01 fix round 2 — implementation design

Base: worktree `.claude/worktrees/02a2c572`, HEAD `c4a6dda`. Continue from those edits.
**First implementation step (not optional):** `git fetch origin && git rebase origin/main`,
record the resulting SHA in the report.

Governing rule for every branch decision below: **when in doubt, allow the stop.** No change in
this round may add a new path that can emit `{"decision":"block"}`, except the one already
present (queued rows + 0 live lanes + no pending question), which is now *narrowed*.

---

## 1. Layers affected

| Layer | File | Change |
|---|---|---|
| Stop hook | `plugins/leadv2/hooks/leadv2-idle-lead-guard.sh` | F1, F2, F4, F5.1 |
| SessionStart hook | `plugins/leadv2/hooks/leadv2-idle-guard-arm.sh` *(to-create)* | F5.2 |
| Hook registry | `plugins/leadv2/hooks/hooks.json` | register the SessionStart entry |
| Tests | `plugins/leadv2/scripts/tests/test-idle-lead-guard.sh` | F3 (4 new cases) |

Out of scope for the implementing agent: `leadv2-state-path.sh`, `leadv2-lane-liveness.sh`,
`leadv2-tasks-lib.sh`, `leadv2-idle-notification-filter.sh`, any other hook, any `docs/leadv2`
or `docs/handoff` content, the plugin cache copy under `~/.claude/plugins/`.

---

## 2. F1 — counter that cannot persist must not block

Current `:198` `printf … > "$COUNTER_FILE" 2>/dev/null || true` is the whole defect: the write
fails, the cap never advances, and the only protection against an infinite block loop is gone.

### Contract

| Symbol | Signature | Semantics |
|---|---|---|
| `persist_count` | `persist_count <int> -> rc` | rc 0 **only if** the value is durably readable back from `$COUNTER_FILE`. Any failure → rc 1. |
| `allow_stop` | `allow_stop [<stderr reason>] -> exit 0` | Best-effort reset to `0` (still `\|\| true` — reset failure is harmless), optional one-line stderr diagnostic, exit 0 with **no stdout**. |

```
persist_count() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  printf '%s' "$1" > "$COUNTER_FILE" 2>/dev/null || return 1
  [[ "$(cat "$COUNTER_FILE" 2>/dev/null || true)" == "$1" ]] || return 1
}
```

Read-back verification (not just write rc) is required: it also covers a full disk, a truncated
write, and a `$COUNTER_FILE` that exists but is an unreadable/foreign inode.

### Call-site change at the block point (`:196-198`)

```
new_count=$(( count + 1 ))
if ! persist_count "$new_count"; then
  allow_stop "IDLE-LEAD-GUARD: counter not persistable at ${COUNTER_FILE} — cap cannot count, allowing stop."
fi
```

Nothing else moves. The pre-probe cap check at `:77` stays where it is (cheap first), and its
own `printf '0' > … || true` stays best-effort — a failed *reset* only ever costs one extra
allowed stop, never a block.

**Risk:** a transiently-unwritable state dir now silently disables the guard entirely rather
than partially. Mitigation: the stderr line above names the exact path, so the cause is visible
in the transcript on the first occurrence rather than after eight.

---

## 3. F2 — unresolvable question dir must allow

Replace `:90-117` with resolution that tracks *whether resolution succeeded*, separate from
*whether a question is pending*.

```
QDIR=""; QDIR_RESOLVED=0
if [[ -n "$QUESTIONS_DIR_OVERRIDE" ]]; then
  QDIR="$QUESTIONS_DIR_OVERRIDE"; QDIR_RESOLVED=1
else
  SP="$(dirname "$0")/../scripts/leadv2-state-path.sh"
  if [[ -f "$SP" ]]; then
    QDIR="$(timeout 4 bash "$SP" questions 2>/dev/null || true)"
  fi
  [[ -n "$QDIR" ]] && QDIR_RESOLVED=1
fi

(( QDIR_RESOLVED == 1 )) || allow_stop \
  "IDLE-LEAD-GUARD: questions dir unresolvable (leadv2-state-path.sh missing or failed) — cannot prove no question is pending, allowing stop."
```

Truth table for condition (c) after the fix:

| resolution | dir on disk | pending file | outcome |
|---|---|---|---|
| failed (empty output / script absent / non-zero exit / timeout) | — | — | **ALLOW** (new) |
| ok | absent | — | proceed to (a)/(b) — no question store exists, so no question is pending |
| ok | present | none pending | proceed to (a)/(b) |
| ok | present | ≥1 `status: pending` | **ALLOW**, stderr names the question id |
| ok | present | YAML unparseable | **ALLOW** (existing `print("yes")` fail-open, unchanged) |

The "resolved but dir absent → proceed" row is the one place this design does *not* allow on
uncertainty, and it is deliberate: a successful resolution that points at a non-existent
directory is positive evidence that no question store exists, not an unknown. It is also the
steady state of every project that has never asked a question — treating it as "allow" would
make the guard a permanent no-op for the majority of repos.

`allow_stop` for the pending case must name the question so a human reading the transcript sees
*why* the turn was released:

```
allow_stop "IDLE-LEAD-GUARD: founder question pending (${qid}) — allowing stop."
```

The existing inline python already scans the dir; extend its output from `yes|no` to
`yes <first-id>` / `no`, where `<first-id>` is the basename of the first pending file. Any
exception in that python still prints `yes` (fail-open), and a missing id degrades to `?`.

---

## 4. F4 — `stop_hook_active` and counter TTL

**Comment at `:23`.** Make it true rather than delete it: the stdin parse block at `:36-44`
gains a third printed line, `r.get("stop_hook_active", False)`, captured into `STOP_HOOK_ACTIVE`
and emitted on the stderr diagnostic line at every `allow_stop`/block
(`… [stop_hook_active=<true|false>]`). It is never read for control flow — that invariant is
what R7 protects, and the comment is amended to say *emitted in the stderr diagnostic line,
never read for control flow*.

**Counter TTL.** Two additive changes:
- Read side (`:70-75`): if `$COUNTER_FILE` mtime is older than
  `LEADV2_IDLE_GUARD_COUNTER_TTL_S` (default `3600`), treat `count=0`. Age via
  `python3 -c 'import os,sys,time; print(int(time.time()-os.path.getmtime(sys.argv[1])))'`,
  any failure → treat as fresh (i.e. keep the count → the conservative direction here is to
  keep counting toward the cap, not to reset it).
- Reaper: the SessionStart hook (§5.2) deletes `${STATE_DIR}/leadv2-idle-guard-*.count` with
  mtime older than 24h. Best-effort, never fatal.

---

## 5. F5 — result-driven termination and self-arming

### 5.1 Goal / done-state — implemented as a **terminator only**

New optional file, repo-relative: **`docs/leadv2/session-goal.yaml`** *(to-create, written by
the dispatcher or the lead, never by this hook)*.

```yaml
goal: "close IDLE-LEAD-GUARD-01"
done_when:
  tasks_absent: [IDLE-LEAD-GUARD-01]        # none of these ids carry a blocking status
  tasks_status: { IDLE-LEAD-GUARD-01: done } # exact status match
  file_exists: docs/handoff/IDLE-LEAD-GUARD-01/result.md
armed_at: 2026-08-05T00:00:00Z
```

All three predicates are optional; present ones are ANDed. Only these three exist — no shell,
no command field. A shell predicate in a hook-read config file is an execution surface reachable
from any file write in the repo, and is rejected.

Evaluation point: a new condition **(d)**, inserted *after* the pending-question check and
*before* condition (a), i.e. after `QDIR` handling, using the same `TASKS_FILE` resolution
already needed for (a) — so the tasks resolution block moves up ahead of it.

| state of `session-goal.yaml` | effect |
|---|---|
| absent | no effect — guard stays purely queue-driven (today's behaviour) |
| present, `done_when` satisfied | **ALLOW**, stderr `IDLE-LEAD-GUARD: goal reached ("<goal>") — allowing stop.` |
| present, unsatisfied | no effect — fall through to (a)/(b) unchanged |
| present, unparseable / unknown predicate key | **ALLOW** (treated as satisfied) |

**Stated plainly, per the mission's instruction not to fake a condition:** the mission asks the
loop to "terminate on the outcome" rather than on an empty queue. Half of that is expressible
and is implemented above — a declared outcome now *ends* the loop even while rows remain queued
or when rows were merely closed without producing the result. The other half — making an
undeclared-but-unreached outcome *keep* the loop alive after the queue drains — is **not**
implemented, deliberately. It would make `{"decision":"block"}` reachable with zero queued rows,
i.e. a block condition that no amount of dispatching can clear, bounded only by the 8-block cap
that F1 just proved fragile. That is the exact wedged-session failure this round exists to
prevent. If the founder wants queue-independent blocking, it needs its own task, its own cap
semantics, and its own kill path — not a widening of this hook.

Consequence to state in the report: with an empty queue and an unreached goal, the session still
ends. `session-goal.yaml` shortens loops that would otherwise churn; it does not lengthen them.

### 5.2 SessionStart arming — `leadv2-idle-guard-arm.sh` *(to-create)*

Registered as the **last** entry in `hooks.SessionStart[0].hooks[]` in
`plugins/leadv2/hooks/hooks.json`, after `leadv2-one-copy-drift.sh`.

Behaviour (all steps best-effort, exit 0 unconditionally, honours `LEADV2_IDLE_GUARD=0`):
1. Parse `session_id` + `cwd` from stdin with the same fail-open parser as the Stop hook.
2. Project gate identical to the Stop hook (`docs/leadv2/` + `docs/tasks.yaml`), else exit 0.
3. Remove this session's `${STATE_DIR}/leadv2-idle-guard-${SESSION_ID}.count` — a fresh session
   starts with a fresh cap budget.
4. Reap `${STATE_DIR}/leadv2-idle-guard-*.count` older than 24h (F4).
5. If `docs/leadv2/session-goal.yaml` exists and parses, emit
   `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"IDLE-LEAD-GUARD armed. Session goal: <goal>. The turn will be held open while work is queued and no lane is live; it is released when the goal's done_when is satisfied, or at 8 consecutive blocks."}}`.
   Absent/unparseable → no stdout.

**BLOCKED, partially — state this in the report rather than claiming F5.2 is fully done.** The
arming state is fully automatic and needs no human. What a hook cannot do is *ignite* the loop:
a `Stop` hook fires only after an assistant turn exists, and no hook event in the Claude Code
hook API produces an unprompted assistant turn — `SessionStart` can only inject context that is
consumed by the first turn, whenever that turn happens. So:

- Sessions opened by dispatch (`claude -p "<mission>"`) get their first turn from the dispatch
  prompt itself → the loop is fully self-sustaining from turn 1, no human typing, F5's
  requirement met on the path that actually matters.
- A hand-opened interactive session still needs a first turn to exist before the Stop hook can
  fire. That first keystroke cannot be removed from inside the plugin. Removing it needs an
  out-of-session driver (a cron or supervisor that opens the session with a prompt), which is
  outside this write set and outside a hook.

---

## 6. F3 — tests that fail at `c4a6dda`

Four cases appended to `plugins/leadv2/scripts/tests/test-idle-lead-guard.sh`, using the
existing `setup_fixture` / `run_hook` harness.

| # | Fixture | Assertion | Fails at `c4a6dda` because |
|---|---|---|---|
| 11 | queued row, `count_live:0`, no pending q, **`chmod 555 "$FIXTURE_STATE"`** after setup | run the hook 10× consecutively; stdout is empty on **every** call, and specifically on calls 2, 5 and 10 | today every call emits `{"decision":"block"} … Cap: 1/8` |
| 12 | queued row, `count_live:0`, real `status: pending` question on disk, **`LEADV2_IDLE_GUARD_QUESTIONS_DIR` unset**, hook copied into a temp `hooks/` dir whose sibling `scripts/` has **no** `leadv2-state-path.sh` | stdout empty; stderr matches `questions dir unresolvable` | today the resolution silently no-ops and the hook blocks with `no pending question` in the reason |
| 13 | queued row, `count_live:0`, `QDIR` set and containing a pending question | stdout empty; stderr matches `question pending` and contains the question id | today this allows, but silently — the id/reason assertion is new |
| 14 | identical to existing case 5 but with the state dir explicitly **writable** | blocks on calls 1–8, allows on call 9, stderr matches `cap reached (8/8)` | regression guard: proves F1's fix did not disable the cap |

Case 12 requires a fixture shape the suite does not have yet: a temp hook root. Add a helper

```
setup_hook_copy_without_statepath() -> sets FIXTURE_HOOK_SH
# $TMPROOT/isolated/hooks/leadv2-idle-lead-guard.sh  (copy of $HOOK_SH)
# $TMPROOT/isolated/scripts/                          (empty — no leadv2-state-path.sh)
```
and let `run_hook` take an optional hook-path override (default `$HOOK_SH`) so cases 1–11, 13, 14
are unchanged.

Case 11 cleanup must `chmod 755` the state dir in the `cleanup` trap, or `rm -rf "$TMPROOT"`
fails and the suite leaks temp dirs. Add that to the existing `cleanup()`.

Two additional cases are cheap and worth including (goal terminator, §5.1):
- **15** — `session-goal.yaml` with `tasks_status: {task-aaa: queued}` unsatisfiable →
  behaviour identical to case 1 (still blocks). Proves the goal file cannot *suppress* a
  legitimate block by accident.
- **16** — `session-goal.yaml` with `file_exists:` pointing at a file that exists, plus a queued
  row and 0 live lanes → allows, stderr matches `goal reached`.

The report must show `bash plugins/leadv2/scripts/tests/test-idle-lead-guard.sh` run twice —
once with the hook checked out at `c4a6dda` (expect cases 11/12 FAIL, 13 likely FAIL on the
stderr assertion) and once after the fix (expect all PASS) — with raw output for both.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| F1 fix turns a transient write failure into a fully disabled guard | stderr line names `$COUNTER_FILE`; SessionStart hook `mkdir -p`s `$STATE_DIR` so the common cause (missing dir) self-heals |
| F2 "resolved but dir absent → proceed" is the one non-allow uncertainty branch | table in §3 documents it; case 13 pins the pending-present behaviour so a future refactor cannot silently flip it |
| `session-goal.yaml` is repo-writable and read by a hook | no shell/command predicate; only three declarative keys; unknown key → allow (never block) |
| New SessionStart hook runs on every session in every leadv2 repo | project gate identical to the Stop hook; all work is `rm`/`stat` on `$STATE_DIR`; exits 0 unconditionally |
| The 24h reaper globs `$STATE_DIR` (`$HOME/.claude` by default) | glob is anchored to the literal prefix `leadv2-idle-guard-` and suffix `.count`; never a bare `*` |
| Two Stop-hook invocations racing on one counter file (parallel turns in one session) | not possible — Stop is serialized per session; noted so a future multi-session `$STATE_DIR` change re-checks it |
| Test case 11's `chmod 555` leaks a temp dir on failure | `cleanup()` chmods back before `rm -rf` |

### Mandatory constraint checklist
1. **Env naming** — all new vars keep the existing `LEADV2_IDLE_GUARD_*` prefix
   (`LEADV2_IDLE_GUARD_COUNTER_TTL_S`, `LEADV2_IDLE_GUARD_GOAL_FILE` for the test override). No
   `LEAD_V2_*` drift.
2. **Paths** — `leadv2-idle-lead-guard.sh`, `hooks.json`, `test-idle-lead-guard.sh`,
   `leadv2-state-path.sh` verified present on disk in the worktree; `leadv2-idle-guard-arm.sh`
   and `docs/leadv2/session-goal.yaml` marked *(to-create)*.
3. **`claude -p`** — this design introduces none. N/A.
4. **Concurrent access** — `$COUNTER_FILE` is the only shared mutable file; Stop is serialized
   per session, SessionStart runs before any Stop of that session. No lock needed; recorded above.
5. **Config contradiction** — `LEADV2_IDLE_GUARD` / `LEADV2_IDLE_GUARD_STATE_DIR` semantics are
   reused unchanged by the new SessionStart hook; no other consumer of these names exists in the
   plugin.

---

## 8. Out of scope

- Fixing `leadv2-state-path.sh` itself (F2 only makes the *caller* fail safely).
- Any change to how lanes are dispatched, or to `leadv2-lane-liveness.sh`.
- A cron/out-of-session driver to ignite the first turn (§5.2 limitation).
- Making an unreached goal *extend* the loop past an empty queue (§5.1, deliberately excluded).
- Deleting or migrating existing `.count` files beyond the 24h reaper.
- The `.claude/scripts/tests/` legacy copy tree (separate open thread).

---

acceptance:
  - surface: log_line
    observable: "With the guard's state directory made read-only and one queued task and no live lane, the ten consecutive stop attempts in the test run each print a PASS line for the unwritable-state-dir case, and no `{\"decision\":\"block\"}` text appears in that case's output."
    authored_at: 2026-08-05T00:00:00Z
  - surface: log_line
    observable: "With a real pending founder question on disk and the state-path resolver absent, the test output shows a PASS line for the unresolvable-questions-dir case and the hook's stderr reads `questions dir unresolvable`, with no block emitted."
    authored_at: 2026-08-05T00:00:00Z
  - surface: log_line
    observable: "The same test suite run against the unmodified hook at c4a6dda prints FAIL lines for those two cases, and the final summary line shows a non-zero FAIL count."
    authored_at: 2026-08-05T00:00:00Z
  - surface: log_line
    observable: "After the fix the suite's final summary line shows FAIL=0 with every case listed as PASS, including the writable-state-dir cap case that still reaches the cap at 8."
    authored_at: 2026-08-05T00:00:00Z
  - surface: file_artifact
    observable: "plugins/leadv2/hooks/hooks.json lists leadv2-idle-guard-arm.sh as the last SessionStart entry, and plugins/leadv2/hooks/leadv2-idle-guard-arm.sh exists in the commit."
    authored_at: 2026-08-05T00:00:00Z

LANE_WRITES: plugins/leadv2/hooks/leadv2-idle-lead-guard.sh, plugins/leadv2/hooks/leadv2-idle-guard-arm.sh, plugins/leadv2/hooks/hooks.json, plugins/leadv2/scripts/tests/test-idle-lead-guard.sh

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# IDLE-LEAD-GUARD-01 — fix round 2 (plugin repo ~/Projects/leadv2)

Round 1 is commit `c4a6dda` in worktree `.claude/worktrees/02a2c572`. Reviewed and **BLOCKED**.
Continue from those edits — do not start over. Full review:
`~/Projects/persona-engine/docs/handoff/DISPATCH-KILLED-BY-FG-TIMEOUT-01/idle-guard-review.md`.

Both critical findings were reproduced live. Both fail in the direction that causes harm. The rule
for this whole file: **when in doubt, allow the stop.** A hook that wedges an interactive session
is far worse than one that misses a stop.

## F1 — BLOCKING. Unwritable state dir permanently defeats the iteration cap → infinite block loop.
`leadv2-idle-lead-guard.sh:198` swallows the counter write with `|| true`, so the counter file is
never created, every later run re-reads `count=0`, and the cap at :77 never fires. Reproduced:
`chmod 555` the state dir, run the hook 10× with a queued row and zero live lanes — every call
blocks, counter frozen at 1/8 forever. This is the exact infinite loop the cap exists to prevent,
and the cap is the ONLY protection, since Anthropic's docs confirm no built-in consecutive-block
limit.

Fix: if the counter cannot be persisted, ALLOW the stop. A cap that cannot count must not block.

## F2 — BLOCKING. The pending-question check silently no-ops in the wrong direction.
Lines 90-117: if `QDIR` resolves empty — e.g. `leadv2-state-path.sh` missing or broken — the whole
pending-founder-question guard is skipped and execution proceeds as if no question were pending.
Reproduced: a real `status: pending` question file present, QDIR resolution broken → the hook still
emitted a block whose reason said "no pending question". That blocks the lead precisely while it is
waiting for a human answer.

Fix: if QDIR cannot be resolved, ALLOW the stop. Unknown question state is not evidence that no
question is pending.

## F3 — the tests miss both, by construction.
Case 5 (the cap loop) uses a writable state dir throughout. Case 4 and every `7x` case set
`LEADV2_IDLE_GUARD_QUESTIONS_DIR` directly, so the `leadv2-state-path.sh` resolution path is never
executed by any test.

Add tests that FAIL against `c4a6dda` and pass after the fix:
- state dir unwritable (`chmod 555`) + queued work + 0 live lanes → ALLOWS the stop; assert the
  hook does not block on the 2nd, 5th and 10th consecutive call.
- `leadv2-state-path.sh` unresolvable/absent, with a real pending question present → ALLOWS the stop.
- QDIR resolvable and a pending question present → ALLOWS, reason mentions the pending question.
- the existing cap test, but with the state dir writable, still reaches the cap at 8.
Show both runs (against `c4a6dda` and after) in your report.

## F4 — Medium, fix while here
The `stop_hook_active` comment at :23 claims the field is read for telemetry; nothing reads it
anywhere. Either read it or delete the comment — a comment that describes behaviour the code does
not have is how today's whole incident started. Counter files never expire; add an age-based reset.

## F5 — NEW REQUIREMENT (founder ruling 2026-08-05, binding)
**The founder typing anything by hand is excluded as a mechanism.** `/goal` is therefore not an
acceptable answer; neither is a session cron. Two consequences for this hook:

1. **Drive to a RESULT, not to an empty queue.** The block condition today is "queued rows exist",
   so the loop terminates when rows run out — which also happens when rows are merely closed.
   Add an optional goal/done-state: a declared session outcome the hook checks, and terminate on
   the outcome. Where the outcome cannot be expressed, say so plainly in your report rather than
   faking a condition.
2. **The plugin must arm the loop itself at SessionStart**, so nothing depends on a human
   remembering. Add the SessionStart wiring in this round, or report BLOCKED explaining why it
   cannot be done from a hook — do not silently leave it to the founder.

## Write set
Same as round 1, plus the SessionStart hook file and its `hooks.json` entry if F5.2 needs one.

## Base
Stay in worktree `02a2c572`. Round 1 skipped the rebase: do `git fetch origin && git rebase
origin/main` first and record the SHA.

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit + raw output of both test runs.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-28fe7b7e" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.