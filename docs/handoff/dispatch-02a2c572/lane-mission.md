Product implementation task dispatch-02a2c572. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# IDLE-LEAD-GUARD-01 — architect prepass

Scoped implementation design for a Stop hook that refuses a turn end while leadv2 work is
queued and no lane is live. **Design only — no code written here.**

---

## 1. Discovery findings (verified on disk, `~/Projects/leadv2`)

| Fact | Evidence |
|---|---|
| `Stop` registers exactly 6 hooks, none blocking on idle work | `plugins/leadv2/hooks/hooks.json` → `hooks.Stop[0].hooks[]` = force-reflect, auto-clear-after-close, lead-prose-guard, bg-stop-warn, supervise-sentinel-cleanup, promise-guard |
| `bg-stop-warn` and `promise-guard` carry `"continueOnBlock": true` | same file — so a hook appended **after** promise-guard still runs even when promise-guard blocks |
| A working `decision:block` Stop hook already exists as a template | `plugins/leadv2/hooks/leadv2-promise-guard.sh` (328 lines): kill switch → stdin parse → fail-open `trap … ERR; exit 0` → once-per-turn sentinel at `$HOME/.claude/leadv2-<name>-${SESSION_ID}.txt` → `print(json.dumps({"decision":"block","reason":…}))` → `exit 0` |
| Task store is `<project_root>/docs/tasks.yaml` | `plugins/leadv2/scripts/leadv2-tasks-lib.sh:21` `_TASKS_FILE="${_PROJECT_ROOT}/docs/tasks.yaml"` |
| Claimable vocabulary in the lib is `{"pending","queued"}` — **not** `{"queued","ready"}` | `leadv2-tasks-lib.sh:64` `CLAIMABLE = {"pending", "queued"}` |
| Lib exposes a read op `list_status <status>` printing `lane\tid`, shared lock | `leadv2-tasks-lib.sh:262-269` |
| Lib is **sourced**, never executed | `leadv2-tasks-lib.sh:3` "Source this file; do not execute directly"; consumers `leadv2-backlog-pump.sh:119`, `leadv2-supervise-pick.sh:50` |
| Authoritative liveness contract | `leadv2-lane-liveness.sh --all --json` → `{"lanes":[…],"jobs":[…],"availability":"authoritative"\|"unavailable","count_live":N}`; `count_live` (line ~481) is *the one definition of the numerator* — `alive` or `starting:*`; `silent:*` and `dead:*` excluded |
| `--no-codex` skips both `codex-task.sh status` shell-outs | `leadv2-lane-liveness.sh:52-58` — fast, but blind to Codex-provider lanes |
| Questions live at `$(leadv2-state-path.sh questions)/<qid>.yaml`; pending predicate is `status == "pending"` | `leadv2-answer.sh:36,57,65`; `leadv2-pending-questions-inject.sh:51-57` |
| Test-suite registration line format | `run-core-offline.sh:117` `run_check "foreground-dispatch guard hook" bash "$TEST_DIR/test-fg-dispatch-guard.sh"` |
| Nearest test template | `plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh` (338 lines): `PASS/FAIL` counters, `run_hook()` piping JSON to the hook, `make_payload()` python one-liner |

---

## 2. Layers affected

| Layer | Change |
|---|---|
| Hook runtime (`plugins/leadv2/hooks/`) | one new Stop hook script |
| Hook registration (`hooks.json`) | one appended entry in `hooks.Stop[0].hooks[]` |
| Offline test suite (`plugins/leadv2/scripts/tests/`) | one new fixture test + one `run_check` line |
| Everything else | **untouched** — see §8 non-goals |

No schema change, no migration, no DB. This is a pure hook-layer addition.

---

## 3. Data flow (numbered)

1. The lead's turn ends → Claude Code fires `Stop` and pipes the Stop-hook stdin JSON
   (`session_id`, `stop_hook_active`, `cwd`, `transcript_path`) to each registered hook in
   array order. Our hook runs **last**, after promise-guard.
2. **Kill switch** — `LEADV2_IDLE_GUARD` unset or `!= "0"` → continue; `=0` → `exit 0` silent (R5).
3. **stdin parse** — one `python3 -c` reading `session_id` and `cwd`. Unparseable / empty → `exit 0`
   silent (R4). `stop_hook_active` is read *for telemetry only* — the mission is explicit that this
   field is unconfirmed in official docs, so the hook does **not** gate on it.
4. **Project scoping (R6)** — `PROJECT_ROOT` = `git -C "$CWD" rev-parse --show-toplevel`, falling back
   to `$CWD`. If `$PROJECT_ROOT/docs/leadv2` does not exist **or** `$PROJECT_ROOT/docs/tasks.yaml`
   does not exist → `exit 0` silent. This is the "not a leadv2 project" gate.
5. **Iteration cap (R3)** — read the per-session counter file
   `$HOME/.claude/leadv2-idle-guard-${SESSION_ID}.count`. If `count >= CAP`
   (`LEADV2_IDLE_GUARD_MAX_BLOCKS`, default 8) → emit the one-line warning to **stderr**, reset the
   counter to 0, `exit 0` (allow the stop). Checking the cap *before* the expensive probes also
   bounds worst-case cost.
6. **Condition (c) — pending founder question.** Resolve `QDIR="$(leadv2-state-path.sh questions)"`.
   Scan `QDIR/*.yaml`; if any doc has `status == "pending"` → reset counter, `exit 0` (allow).
   Resolution failure, missing dir, or a YAML parse error → treat as **"cannot prove there is no
   pending question" → allow the stop** (fail-open, R4).
7. **Condition (a) — queued work.** Source `leadv2-tasks-lib.sh` (for `_TASKS_FILE` path resolution
   honouring the `PROJECT_ROOT > git root > CLAUDE_PROJECT_DIR` precedence), then one inline python
   pass over `_TASKS_FILE` collecting rows whose `status` ∈ `QUEUED_STATUSES`
   (`LEADV2_IDLE_GUARD_STATUSES`, default `queued,ready,pending` — see D1). Each hit yields
   `(id, lane, title)`. Zero hits → reset counter, `exit 0` (allow).
   *Sub-signal from R1(a) second clause* — a lane worktree with uncommitted changes whose liveness
   verdict is dead also counts as queued work. See D3: **deferred, not implemented in round 1.**
8. **Condition (b) — zero live lanes.** `timeout 4 leadv2-lane-liveness.sh --all --json
   --project-root "$PROJECT_ROOT"` (**without** `--no-codex` — R1(b) forbids inference, and
   `--no-codex` is exactly an inference that Codex lanes don't exist). Then:
   - non-zero exit / timeout / empty output / unparseable JSON → `exit 0` silent (R4);
   - `availability != "authoritative"` → `exit 0` silent (Codex job state unknown ⇒ cannot prove
     zero live);
   - `count_live > 0` → reset counter, `exit 0` (allow the stop);
   - `count_live == 0` → **block**.
9. **Block emission (R2).** Increment the counter file. Print to stdout:
   `{"decision":"block","reason":"<reason>"}` and `exit 0`.
10. **Reason construction (R2).** Names the next concrete action, never scolds:
    `IDLE-LEAD-GUARD: N queued row(s), 0 live lanes, no pending question. Next: dispatch <id> (<title, ≤60 chars>). Other queued: <id2>, <id3>. Cap: <k>/<CAP>. Kill: LEADV2_IDLE_GUARD=0.`
    The chosen `<id>` is the **first** row in `docs/tasks.yaml` file order among the matched
    statuses — deterministic, fixture-testable, and matches `list_status`'s own ordering. Titles are
    truncated and newline-stripped so the JSON stays one line.
11. **Counter reset discipline.** Every allow path in steps 5–8 writes `0` to the counter file
    before exiting. Only step 9 increments. This satisfies "reset the counter whenever a stop is
    allowed" (R3) without a separate reset hook.

---

## 4. Interface contracts

### 4.1 `leadv2-idle-lead-guard.sh` — process contract

| Aspect | Contract |
|---|---|
| stdin | Stop-hook JSON. Fields consumed: `session_id`, `cwd`. Anything else ignored. |
| stdout | Either **empty**, or exactly one line of JSON `{"decision":"block","reason":"…"}` |
| stderr | Empty, except the single cap-reached warning line (step 5) |
| exit code | **Always 0.** Never 2 — exit-2 semantics put the reason on stderr and would collide with the cap warning's stderr use. One channel, one meaning. |
| side effects | reads/writes `$HOME/.claude/leadv2-idle-guard-${SESSION_ID}.count` only |
| runtime budget | ≤4s (the `timeout 4` on the liveness probe dominates); hooks.json `timeout: 10` |

### 4.2 Env vars (all `LEADV2_*`, checklist item 1 ✅)

| Var | Default | Meaning |
|---|---|---|
| `LEADV2_IDLE_GUARD` | `1` | `0` disables entirely (R5, also the rollback) |
| `LEADV2_IDLE_GUARD_MAX_BLOCKS` | `8` | consecutive-block cap (R3) |
| `LEADV2_IDLE_GUARD_STATUSES` | `queued,ready,pending` | task statuses counted as work (D1) |
| `LEADV2_IDLE_GUARD_TASKS_FILE` | *(unset)* | test-only override of the task store path; fixtures set it instead of faking a git root |
| `LEADV2_IDLE_GUARD_LIVENESS_SH` | *(unset)* | test-only override of the liveness probe path; fixtures point it at a stub script |
| `LEADV2_IDLE_GUARD_QUESTIONS_DIR` | *(unset)* | test-only override of the questions dir |
| `LEADV2_IDLE_GUARD_STATE_DIR` | `$HOME/.claude` | test-only override of the counter-file directory |

Checklist item 5 (config contradiction): `LEADV2_IDLE_GUARD*` returns **zero** existing hits under
`plugins/leadv2/` — no collision, no `LEAD_V2_*` variant introduced. The three `*_SH` / `*_DIR` /
`*_FILE` overrides exist so fixtures never need a real git worktree, matching how
`leadv2-promise-guard.sh` uses `LEADV2_PROMISE_GUARD_TRANSCRIPT`.

### 4.3 Consumed contracts (read-only, unchanged)

| Producer | Invocation | Consumed field |
|---|---|---|
| `leadv2-lane-liveness.sh` | `--all --json --project-root <root>` | `count_live` (int), `availability` (str) |
| `leadv2-state-path.sh` | `questions` | absolute questions dir |
| `leadv2-tasks-lib.sh` | `source` | `_TASKS_FILE` |
| `<qdir>/*.yaml` | — | `status == "pending"` |
| `docs/tasks.yaml` rows | — | `status`, `id`, `lane`, `title` |

### 4.4 `hooks.json` change

Append **one** object to `hooks.Stop[0].hooks[]`, **after** `leadv2-promise-guard.sh`:

```
{ "type": "command",
  "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-idle-lead-guard.sh\"",
  "timeout": 10,
  "continueOnBlock": true,
  "statusMessage": "Idle-guard: checking queued work vs live lanes..." }
```

`timeout: 10` (not the customary 5) because the liveness probe shells out to `codex-task.sh` twice;
`timeout 4` inside the script keeps the real budget well under it. `continueOnBlock: true` is
defensive — it is last today, but keeps the array append-safe for a future seventh hook.

---

## 5. DB / migrations

**None.** No Supabase table, no RLS policy, no `supabase/migrations/` entry. `docs/tasks.yaml` is
read-only for this hook; its schema is untouched.

---

## 6. Risks and mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R-1 | **Infinite block loop wedges the lead.** The 8-block cap is the only backstop the mission trusts. | Critical | Cap check runs *first* (step 5), before any probe, so even a probe that hangs and times out every turn still terminates the loop in ≤8 turns. Counter file write failure (read-only `$HOME`) → `exit 0` fail-open rather than "assume 0". |
| R-2 | **`set -euo pipefail` + sourcing `leadv2-tasks-lib.sh`.** Line 20 of the lib runs an unguarded `git -C … rev-parse --show-toplevel` as its last-resort fallback; under `set -e` a failure kills the hook mid-flight. | High | `set +e; source …; set -e`, plus the `trap … ERR; exit 0` fail-open that promise-guard already uses. Also step 4 already proved `docs/tasks.yaml` exists, so the fallback branch is unreachable in practice. |
| R-3 | **False block from an undercounted live lane.** Today's verified incident was a false ALIVE; the symmetric failure (false DEAD → block while a lane is genuinely running) is what makes the lead loop. | High | Never use `--no-codex`. Treat `availability != "authoritative"` as "cannot prove zero" → allow. Only a positive, authoritative `count_live == 0` blocks. |
| R-4 | **Status-vocabulary drift.** Mission says `queued\|ready`; the lib's `CLAIMABLE` is `{"pending","queued"}`. `ready` appears in neither. A hardcoded `{queued,ready}` would silently miss every `pending` row — i.e. the guard never fires in the repo it was written for. | High | Default set is the **union** `queued,ready,pending`, overridable via `LEADV2_IDLE_GUARD_STATUSES`. See decision D1. |
| R-5 | **Concurrent access (checklist item 4).** Two parallel `claude` sessions in the same repo both read `docs/tasks.yaml` at Stop. | Low | Read-only path; the lib's shared-lock op is not used, and a torn read of a YAML file being rewritten manifests as a parse error → fail-open. Counter files are **per-`session_id`**, so two sessions never contend on the same counter. No lock needed. |
| R-6 | **Double block in one turn** — promise-guard and idle-guard both emit `decision:block`. | Low | Both are advisory guidance; the harness surfaces both reasons. Accepted, documented in the hook header. No once-per-turn sentinel here — unlike promise-guard, repeated blocking is the *intended* behaviour, and the cap is the limiter. |
| R-7 | **`transcript_path` / `stop_hook_active` reliance.** The mission explicitly says the `stop_hook_active` field and the "8 consecutive blocks" harness cap could not be confirmed in Anthropic docs. | Medium | The hook reads neither for control flow. Its own counter is the sole cap. |
| R-8 | **Slow Stop path on every turn.** Adding a liveness probe to every single turn end costs a shell-out per turn. | Medium | Cheap gates ordered first: kill switch → stdin → `docs/leadv2` existence → cap → questions → queued rows. The liveness probe (the only expensive call) runs **last**, and only when queued work already exists. On a repo with an empty queue the hook is 2 python starts and a `test -d`. |
| R-9 | **`file_artifact` acceptance is fixture-only** — no live-lane proof. | Medium | Accepted by the mission ("each a fixture test, no live lane needed"). The stub-probe override (`LEADV2_IDLE_GUARD_LIVENESS_SH`) makes the `count_live` branch deterministic without a real lane. |

### Mandatory checklist results

1. **Env var naming** ✅ — all seven vars are `LEADV2_*`; no `LEAD_V2_*` introduced; no collision with existing names.
2. **File paths** ✅ — `plugins/leadv2/hooks/hooks.json`, `plugins/leadv2/scripts/tests/run-core-offline.sh`, `plugins/leadv2/scripts/leadv2-lane-liveness.sh`, `leadv2-state-path.sh`, `leadv2-tasks-lib.sh` all verified present. `plugins/leadv2/hooks/leadv2-idle-lead-guard.sh` **(to-create)**, `plugins/leadv2/scripts/tests/test-idle-lead-guard.sh` **(to-create)**.
3. **`claude -p` commands** — N/A, this plan invokes none.
4. **Concurrent access** ✅ — analysed in R-5; per-session counter files, read-only task store, no lock required.
5. **Config contradiction** ⚠️ — one found and resolved as D1 (status vocabulary). No env-var contradiction.

---

## 7. Decisions

- **D1 — status vocabulary is a union, not the mission's literal pair.** `source: architect(self-check)`.
  The mission's `queued|ready` does not match `leadv2-tasks-lib.sh:64` `CLAIMABLE = {"pending","queued"}`,
  and the lib's own comment records that persona-engine's live store stamps `queued` where the
  generator stamps `pending`. Taking the mission literally would produce a guard that never fires on
  a `pending`-only store. Resolution: default `queued,ready,pending`, env-overridable. The
  implementer must **not** silently narrow this.
- **D2 — exit 0 + stdout JSON only; never exit 2.** Both are valid block channels per the confirmed
  contract, but exit 2 routes the reason through stderr, which the cap warning also uses. One
  channel per meaning keeps the fixture assertions unambiguous.
- **D3 — the "dirty worktree + dead probe" arm of R1(a) is DEFERRED.** `source: architect(self-check)`.
  It needs a lane→worktree map plus a `git status --porcelain` per worktree, which is both the
  slowest possible thing to put on every turn end (R-8) and the arm most likely to produce a false
  block on a worktree left dirty on purpose. Round 1 ships the `docs/tasks.yaml` arm only, which
  covers every stated acceptance case. If the lead needs the second arm, it lands as
  IDLE-LEAD-GUARD-02 behind `LEADV2_IDLE_GUARD_DIRTY_WORKTREE=1`, default off.
- **D4 — no once-per-turn sentinel.** promise-guard's sentinel exists to block *at most once*; this
  hook must block *repeatedly* until work is dispatched. The counter, not a sentinel, is the limiter.

---

## 8. Out of scope (implementer: ignore these)

- `/goal` — not touched, not wrapped, not referenced in code.
- The other six Stop hooks — no edit to force-reflect, auto-clear-after-close, lead-prose-guard,
  bg-stop-warn, supervise-sentinel-cleanup, promise-guard.
- The dispatcher (`leadv2-dispatch-code.sh`, `leadv2-fanout.sh`), routing, `leadv2-supervise*`.
- Any heartbeat, cron, `CronCreate`, or background watcher.
- `leadv2-lane-liveness.sh` itself — consumed as-is, zero edits.
- `docs/tasks.yaml` schema, `leadv2-tasks-lib.sh` — sourced, never modified.
- Anything under `docs/leadv2/` or `docs/handoff/` — no runtime writes there.

---

## 9. Test plan — `test-idle-lead-guard.sh`

Structure mirrors `test-fg-dispatch-guard.sh`: `PASS`/`FAIL` counters, `pass()`/`fail()`, a
`run_hook()` that pipes a JSON payload and captures stdout + stderr + rc. A `setup_fixture()`
builds a temp dir with `docs/leadv2/`, a `docs/tasks.yaml`, a questions dir, and a stub liveness
script echoing a canned `{"availability":"authoritative","count_live":N}`; the four test-only env
overrides point the hook at them. `LEADV2_IDLE_GUARD_STATE_DIR` isolates the counter per test.

| # | Fixture | Expected |
|---|---|---|
| 1 | 2 queued rows, stub `count_live=0`, no pending question | stdout parses as JSON, `.decision == "block"`, `.reason` contains the first queued row's id |
| 2 | 2 queued rows, stub `count_live=1` | empty stdout, rc 0 |
| 3 | tasks.yaml with only `status: done` rows | empty stdout, rc 0 |
| 4 | 2 queued rows, `count_live=0`, one question yaml with `status: pending` | empty stdout, rc 0 |
| 5 | loop the blocking payload 9× against one counter file | invocations 1–8 block; the 9th emits empty stdout, rc 0, and a stderr line containing `IDLE-LEAD-GUARD` and `cap` |
| 6 | `LEADV2_IDLE_GUARD=0` + the blocking fixture | empty stdout, empty stderr, rc 0 |
| 7a | stdin `not json at all` | empty stdout, rc 0 |
| 7b | queued rows but `docs/tasks.yaml` deleted | empty stdout, rc 0 |
| 7c | `LEADV2_IDLE_GUARD_LIVENESS_SH` pointing at a nonexistent path | empty stdout, rc 0 |
| 7d | stub liveness emitting `{"availability":"unavailable"}` | empty stdout, rc 0 |
| 8 | fixture root with no `docs/leadv2/` | empty stdout, rc 0 |
| 9 | after a blocking run, an allowing run (case 2), then the blocking fixture again | the third invocation blocks with counter back at 1 — proves R3 reset |
| 10 | `hooks.json` parses as JSON **and** `hooks.Stop[0].hooks[]` contains `leadv2-idle-lead-guard.sh` | registration assertion (mirrors fg-dispatch-guard's own hooks.json check) |

**Red-first proof (mandatory).** Case 10 is the registration assertion: with the `hooks.json` entry
absent it FAILS and with it present it passes, so the suite is genuinely red before the change.
Cases 1–9 fail before the hook script exists (`bash <missing path>` → rc 127, no JSON on stdout).
The implementer must run the suite **once with `hooks.json` unmodified and the hook script absent**,
paste that failing output into the report, then run it again after both land. A test green in both
states must be rewritten.

Registration line to append to `run-core-offline.sh`, adjacent to line 117's sibling guard entry:

```
run_check "idle-lead guard hook" bash "$TEST_DIR/test-idle-lead-guard.sh"
```

### Suite-level expectation
The core offline suite must be green from the rebased base **except** the pre-existing
`supervisor reconciliation` failure (`test-supervise-v2.sh` Test 1a), which already fails on
untouched `main`. Any *other* new red is this lane's regression.

---

## 10. Rollback

Two independent levers, both documented in the hook's header comment and required in the report:
1. `export LEADV2_IDLE_GUARD=0` — instant, no file edit, no restart.
2. Remove the appended object from `hooks.Stop[0].hooks[]` in `plugins/leadv2/hooks/hooks.json`.

Per the global shared-trees rule, the hook lands **once** in `~/Projects/leadv2`. Note the standing
hooks caveat: the plugin **cache** is a separate copy and `claude plugin update` no-ops for a
directory-source marketplace when content changed but the version did not — so a hook change must be
copied into the cache and the session restarted, or it never loads. Verifying live behaviour is
therefore out of this lane's fixture-only acceptance.

---

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >
      The core offline suite run prints a line reading
      "[CHECK] PASS: idle-lead guard hook", and the summary that follows reports
      no failures other than the pre-existing "supervisor reconciliation" entry.
    authored_at: 2026-08-05T00:00:00Z
  - surface: rendered_line
    observable: >
      When the lead tries to end a turn while the project's task store holds queued rows
      and no lane is live, the turn does not end; instead the session shows a guidance line
      beginning "IDLE-LEAD-GUARD:" that states how many queued rows and how many live lanes
      there are and names one specific task id to dispatch next.
    authored_at: 2026-08-05T00:00:00Z
  - surface: rendered_line
    observable: >
      After the guard has held the turn open eight times in a row, the ninth attempt to end
      the turn succeeds, and the session shows a single warning line naming the guard and
      saying its cap was reached.
    authored_at: 2026-08-05T00:00:00Z
  - surface: file_artifact
    observable: >
      plugins/leadv2/hooks/hooks.json opens as valid JSON and its Stop section lists
      leadv2-idle-lead-guard.sh as the last entry, after leadv2-promise-guard.sh.
    authored_at: 2026-08-05T00:00:00Z
  - surface: rendered_line
    observable: >
      With LEADV2_IDLE_GUARD=0 set, ending a turn under the same queued-work-and-no-live-lane
      conditions produces no guard line at all and the turn ends normally.
    authored_at: 2026-08-05T00:00:00Z
```

LANE_WRITES: plugins/leadv2/hooks/leadv2-idle-lead-guard.sh, plugins/leadv2/hooks/hooks.json, plugins/leadv2/scripts/tests/test-idle-lead-guard.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# IDLE-LEAD-GUARD-01 — build (plugin repo ~/Projects/leadv2)

## Outcome
The lead cannot end a turn while work is queued and no lane is live. Autonomy stops depending on
the founder remembering to type `/goal`.

## Problem (verified 2026-08-05)
Emitting chat text ends the turn; an interactive session has no continuation loop, so every status
report is simultaneously a full stop. `hooks.json` registers six Stop hooks (force-reflect,
auto-clear-after-close, lead-prose-guard, bg-stop-warn, supervise-sentinel-cleanup, promise-guard)
and **none** refuses a turn end while work remains. Two standing memories already state the rule
(`feedback-never-end-turn-on-a-promise`, `feedback-turn-ends-only-when-queue-is-refilled`) and it
has no enforcer — the same rule-without-a-reader defect fixed earlier today in the fg-dispatch guard.

`/goal` (https://code.claude.com/docs/en/goal) is real and is the same mechanism, but it is
session-scoped and human-typed. This hook is the plugin-owned equivalent that needs nobody to
remember anything.

## Repo / base
`~/Projects/leadv2`. First action: `git fetch origin` then `git rebase origin/main` (NOT
`--ff-only merge` — it fails once the lane has its own commits). Record the SHA.

## Write set (allowed paths ONLY)
- `plugins/leadv2/hooks/leadv2-idle-lead-guard.sh` (new)
- `plugins/leadv2/hooks/hooks.json` (register the Stop hook)
- `plugins/leadv2/scripts/tests/test-idle-lead-guard.sh` (new)
- `plugins/leadv2/scripts/tests/run-core-offline.sh` (register the test)

## Hook contract — confirmed against official docs, use exactly this
- exit 0 + stdout `{"decision":"block","reason":"<next action>"}` → forces another turn, reason is
  fed back as guidance.
- exit 2 → also blocks; stderr becomes the reason.
- `{"continue":false,"stopReason":"..."}` → hard stop regardless.
The "8 consecutive blocks" cap and a `stop_hook_active` field could **NOT** be confirmed in
Anthropic's own docs — only in third-party blogs. **Do not rely on them.** This hook MUST carry its
own iteration cap.

## Requirements

**R1 — block condition.** Block the stop when ALL hold:
(a) there is queued/ready work — a `status: queued|ready` row in the project's task store, or a
lane worktree with uncommitted changes and a dead liveness probe;
(b) zero lanes are live — use `leadv2-lane-liveness.sh`, the authoritative probe. **Never** infer
liveness from file mtime or directory existence; both lied today and caused a false ALIVE report;
(c) no founder question is pending (check the control-plane questions path via
`leadv2-state-path.sh questions`).

**R2 — the reason must name the next action**, not scold. e.g.
`2 queued rows, 0 live lanes. Next: dispatch a2079527a14e (comment topic gate).` A vague reason
produces a vague next turn.

**R3 — own iteration cap.** Count consecutive blocks in a per-session state file. Default cap 8,
override `LEADV2_IDLE_GUARD_MAX_BLOCKS`. At the cap, stop blocking and emit a one-line warning so
the lead can hand back to the founder. Reset the counter whenever a stop is allowed.

**R4 — fail open, always.** Any error, unparseable input, missing task store, or missing probe →
exit 0 with no output. A hook that wedges the lead into an infinite loop is far worse than one
that misses a stop.

**R5 — kill switch.** `LEADV2_IDLE_GUARD=0` disables it entirely.

**R6 — do not fire outside leadv2 work.** If the project has no leadv2 task store / no
`docs/leadv2/`, exit 0 silently.

## Non-goals
Do not touch `/goal`, the other six Stop hooks, the dispatcher, or routing. Do not add a heartbeat
or cron — out of scope.

## Acceptance (each a fixture test, no live lane needed)
- queued work + zero live lanes + no pending question → BLOCKS, reason names a specific task id.
- queued work + one live lane → allows the stop.
- zero queued work → allows the stop.
- pending founder question → allows the stop.
- 8 consecutive blocks → 9th allows the stop and warns.
- `LEADV2_IDLE_GUARD=0` → allows the stop.
- malformed stdin / missing task store / probe binary absent → exit 0, no output.
- a repo with no `docs/leadv2/` → exit 0, no output.
- Each new test must FAIL with the hook unregistered and pass with it registered — state this in
  your report and show the failing run. A test that passes both ways proves nothing.
- The core offline suite is green from the rebased base, EXCEPT the pre-existing failure in
  `supervisor reconciliation` (test-supervise-v2.sh Test 1a) which already fails on untouched main.

## Rollback
`LEADV2_IDLE_GUARD=0`, or remove the entry from `hooks.json`. Name it in your report.

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit + raw test output.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-02a2c572" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.