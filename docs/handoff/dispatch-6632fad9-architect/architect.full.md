# V3-ENV-GUARDS-01 — architect prepass (scoped implementation design)

Repo: `~/Projects/leadv2` (plugin repo). No `context.yaml` existed for this task
(`ls docs/handoff/dispatch-6632fad9-architect/` → only `architect.*`), so `decisions:` /
`off_limits:` are taken verbatim from the mission text.

---

## 0. Root causes established by probe (not assumed)

### Item 1 — where the junk actually comes from

`plugins/leadv2/scripts/leadv2-backlog-pump.sh` resolves its root fail-closed with a
`git rev-parse --show-toplevel` fallback:

```
102: PROJECT_ROOT=""
103: if [[ -n "${LEADV2_PROJECT_ROOT:-}" ]]; then PROJECT_ROOT="$LEADV2_PROJECT_ROOT"
105: elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then PROJECT_ROOT="$CLAUDE_PROJECT_DIR"
107: elif _lv2bp_top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"; then
108:   PROJECT_ROOT="$_lv2bp_top"
```

Inside a lane worktree (`.claude/worktrees/<id>`), `--show-toplevel` returns **the worktree**,
not the main checkout. Everything derived from it then lands in the lane:

```
219: CACHE_DIR="${PROJECT_ROOT}/.claude/cache/backlog-pump"
220: LANE_MAP_DIR="${CACHE_DIR}/backlog-pump-lane-map"
284:   local cache="${CACHE_DIR}/liveness.json" sigfile="${CACHE_DIR}/liveness.sig" tsfile="${CACHE_DIR}/liveness.ts"
871: EMPTY_STREAK_DIR="${PROJECT_ROOT}/.claude/cache/backlog-pump-empty-streak"
```

Line 284 is the exact writer of the three files that false-blocked task `6632fad9`
(`liveness.json` / `.sig` / `.ts`, written at lines 314-316 of the same function).

**Second writer, same bug class** — the pump *caller* hook:

```
plugins/leadv2/hooks/leadv2-supervisor-pump-caller.sh:164:
  BELOW_FLOOR_SENTINEL="${CWD_FROM_INPUT}/.claude/cache/backlog-pump/backlog-pump-below-floor"
```

`CWD_FROM_INPUT` is the hook payload's cwd — i.e. the worker session's cwd — so a worker
session firing this hook inside a lane writes the sentinel into the lane too. Fixing only
`leadv2-backlog-pump.sh` leaves this path live. Both are in scope.

### Item 2 — the dead shape, with its probe artifact

Live rollout from tonight's incident window
(`~/.codex/sessions/2026/08/20/rollout-2026-08-20T05-22-53-01a01cfa-...jsonl`, 13 lines total):

```
{"timestamp":"2026-08-20T02:22:58.199Z","type":"event_msg",
 "payload":{"type":"task_complete","turn_id":"01a01cfa-8ccd-...","last_agent_message":null,
            "completed_at":1787192578,"duration_ms":946}}
```

Preceding line is `event_msg/token_count` with
`"credits":{"has_credits":false,"unlimited":false,"balance":"0"}`. Event-type census for the
file: `response_item/message ×5, session_meta, thread_settings_applied, task_started,
world_state, turn_context, user_message, token_count, task_complete`.

So the dead shape is **terminal `event_msg.payload.type == "task_complete"` with
`last_agent_message == null` and a sub-second `duration_ms`** — and the rollout is ~100 KB of
context, which is why `_codex_first_byte_probe` (line 3368: `codex-task.sh log <handle>` returns
non-empty) reports a healthy first byte and `_codex_first_byte_deadline_check` never fires.
The two guards are complementary, not redundant.

Existing spill machinery to reuse verbatim (dispatch-code.sh 3494-3506): codex-only block
inside the confirmed-spawn path, `rc=7` → `LAST_ARM_OUTCOME` → `emit decision arm_refused` →
`dispatch_abort` → `return 7` (spill) / `return 5` (abort failed).

Stand-down verb exists and already accepts minutes (4766-4802):
`leadv2-dispatch-code.sh record-quota-lockout --provider <p> --minutes <1..10080> --reason <r>`.

### Item 3 — the audit answer, with evidence

- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is **set nowhere** in this repo
  (`grep -rn CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS plugins/ .claude/settings.json docs/` → no
  hits outside handoff docs). So the guard is purely inheritance defence: a stray shell profile
  on the founder's machine exporting `=1` would leak into every worker.
- `CLAUDE_CODE_ENABLE_TODO_TOOLS`: **workers do depend on the Task-tool family.**
  - `plugins/leadv2/hooks/leadv2-continuation-guard.sh:172` counts `'TaskCreate', 'TaskUpdate'`
    as productive tool calls — a worker without those tools is mis-scored by the guard.
  - `plugins/leadv2/hooks/hooks.json:693` registers a `TaskCreated` hook event, which cannot
    fire at all if the tools are absent.
  - Upstream cause (doc, read at
    `~/Projects/persona-engine/docs/handoff/CC-RELEASE-AUDIT-230-236.md:174-178`):
    "Todo/task-tracking tools (TaskCreate/Get/Update/List, TodoWrite) no longer available by
    default on Opus 4.8, Sonnet 5, Fable 5, Mythos 5 and newer — set
    `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` to restore."
  - **Audit verdict: SET it in the worker env** (`=1`), gated by
    `LEADV2_WORKER_TODO_TOOLS` so it can be turned back off without a code change.
  - `UNVERIFIED:` the same audit doc (line 427-430) flags that it could not confirm from a
    single source that agent-teams' shared task list is literally the same tool family. That
    caveat does not affect this design — we only care about `TaskCreate`/`TaskUpdate`/the
    `TaskCreated` hook event, which the changelog line names directly.

---

## 1. Changes — exact files

### 1.1 `plugins/leadv2/scripts/leadv2-backlog-pump.sh`

**(a) canonical-root helper**, inserted immediately after the existing root block (~line 115,
before `export LEADV2_PROJECT_ROOT`):

```
_lv2bp_canonical_root() {   # <candidate> -> main-worktree root on stdout
  # A linked worktree's --git-common-dir points at the MAIN checkout's .git.
  # dirname of that = the main working tree. Non-worktree repos: common-dir ==
  # "$candidate/.git" -> dirname == candidate (identity, no behaviour change).
}
```

Implementation constraints for the developer:
- Use `git -C "$cand" rev-parse --git-common-dir`; the result may be **relative** (`.git`) on
  older git, so resolve with `cd "$cand" && cd "$(git rev-parse --git-common-dir)" && cd .. && pwd`
  inside a subshell. Do **not** use `--path-format=absolute` (git ≥ 2.31 only) — the repo
  standing decision bans version-fragile flags in shell.
- Bare/absent git → echo the candidate unchanged (identity fallback, never fail).
- Bash-3.2 only (macOS stock). No `declare -A`, no `${var@Q}`.

**(b) root de-worktreeing.** After resolution, set `PROJECT_ROOT="$(_lv2bp_canonical_root "$PROJECT_ROOT")"`.
Rationale: a pump running against a lane worktree is wrong in *every* respect, not just the
cache — it would read the lane's stale `docs/tasks.yaml` and `docs/leadv2/active.yaml` copies.
Emit one journal line when the value actually changed:
`jemit decision "pump_root_deworktreed from=<worktree> to=<canonical>"`.

**(c) cache pinned to the canonical root regardless.** Belt-and-braces, and the seam the test
drives:

```
CACHE_DIR="${LEADV2_BACKLOG_PUMP_CACHE_DIR:-${CANONICAL_ROOT}/.claude/cache/backlog-pump}"
EMPTY_STREAK_DIR="${LEADV2_BACKLOG_PUMP_CACHE_DIR:+${LEADV2_BACKLOG_PUMP_CACHE_DIR}-empty-streak}"
   # …with the existing ${CANONICAL_ROOT}/.claude/cache/backlog-pump-empty-streak default
```

`CANONICAL_ROOT` is a new script-local set alongside `PROJECT_ROOT` in (b). Even if (b) is
later reverted, (c) alone satisfies acceptance.

### 1.2 `plugins/leadv2/hooks/leadv2-supervisor-pump-caller.sh`

Line 164: `BELOW_FLOOR_SENTINEL` must use the canonical root derived from `CWD_FROM_INPUT`, not
`CWD_FROM_INPUT` itself. The hook is a standalone process and must not source the pump; give it
a 4-line inline equivalent of `_lv2bp_canonical_root` (same subshell `cd`/`git rev-parse
--git-common-dir`/`cd ..`/`pwd` idiom), with identity fallback on failure. This is a duplicated
5-line idiom, not shared code — extracting a lib for two call sites is over-engineering here
(`# lean:` marker on the hook copy pointing at the pump as the reference implementation).

### 1.3 `plugins/leadv2/scripts/lib/leadv2-codex-rollout-shape.py` *(to-create)*

Single-purpose parser, keeps JSON off the shell:

| in | out (stdout, one line) | exit |
|----|------------------------|------|
| `<rollout.jsonl>` | `shape=dead bytes=<n> lines=<n>` — terminal `task_complete` with `last_agent_message` null | 0 |
| | `shape=alive bytes=<n> lines=<n>` — terminal `task_complete` with non-null `last_agent_message` | 0 |
| | `shape=running bytes=<n> lines=<n>` — no `task_complete` yet | 0 |
| unreadable / not JSONL | `shape=unknown bytes=0 lines=0` | 0 |

Never non-zero exit; never raises. Scans only `type=="event_msg"` records whose
`payload.type=="task_complete"`, takes the LAST one. `bytes` = `os.path.getsize`.

### 1.4 `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — item 2 (codex arm)

New helper beside `_codex_first_byte_deadline_check` (insert after line 3402):

```
_codex_rollout_for_task <sig8> <work_root> <since_epoch>   -> rollout path | ""
_codex_instant_complete_check <handle> <sig8>              -> 0 proceed | 7 dead
```

**Binding a rollout to this task** (the one genuinely tricky part):
`codex-task.sh` exposes no rollout path (verified: only `task` / `status` / `log` verbs are
invoked at 3074 / 3103 / 3369). So bind by **content + time**:
1. Enumerate `${LEADV2_CODEX_SESSIONS_DIR:-$HOME/.codex/sessions}/*/*/*/rollout-*.jsonl`
   with mtime ≥ `since_epoch − 5`.
2. Keep those whose `event_msg/user_message` payload contains `${WORK_ROOT}` (the lane worktree
   path — the live rollout above proves the mission text is echoed verbatim into that record,
   including the `WORKTREE PIN: all edits go in …/.claude/worktrees/9c027877` line).
3. Newest match wins. **Zero matches → return 0 (proceed).** Never spill on an unbound rollout:
   a false spill burns a codex arm on every dispatch, which is strictly worse than the fault.

**Verdict window:** `LEADV2_CODEX_INSTANT_COMPLETE_SECS` (default 30, `0` disables — mirrors
`LEADV2_CODEX_FIRST_BYTE_SECS`'s contract exactly). Poll at
`LEADV2_ARM_EARLY_VERDICT_POLL_S` (reuse, default 1):

| observation | verdict |
|---|---|
| `shape=running` and `bytes` grew since last sample | proceed (0) — growing |
| `shape=running` and flat, deadline not reached | keep polling |
| `shape=running` at deadline | proceed (0) — first-byte guard owns true silence |
| `shape=alive` | proceed (0) |
| `shape=dead` | **dead (7)** |
| `shape=unknown` | proceed (0) |

**On dead (7):**
```
emit decision "arm_dead_instant_complete arm=codex task=${sig8} job=${handle} rollout=<basename> duration_ms=<n>"
bash "${DISPATCH_SELF_BIN:-…/leadv2-dispatch-code.sh}" record-quota-lockout \
     --provider codex --minutes "${LEADV2_CODEX_INSTANT_COMPLETE_LOCKOUT_MIN:-15}" \
     --reason arm_dead_instant_complete >/dev/null 2>&1 || true
```
(`--minutes` is validated 1..10080 at line 4793 — a short lockout, not the 1-hour
`--hours` used by the first-byte guard, because instant-complete is usually a transient
credits/backend blip.)

**Call site** — extend the existing codex block at 3494-3506, *after* the first-byte check
returns 0, same shape:

```
LAST_ARM_OUTCOME="codex_dead_instant_complete"
emit decision "arm_refused by=router model=codex task=${sig8} reason=instant_complete"
log "spawn(codex) instant task_complete with null last message; spilling to next arm"
dispatch_abort "${token}" || _abort_rc=$?
[[ ${_abort_rc} -eq 0 ]] && return 7
return 5
```

Ordering matters: first-byte first (cheap, `codex-task.sh log`), instant-complete second (needs
the rollout on disk, which only exists once bytes landed).

### 1.5 `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — item 3 (worker env asserts)

New helper `_worker_env_asserts <arm> <sig8>`, called **once at the top of `spawn_worker()`**
(line 2749), before the `case "${arm}"` — so all three arms (glm / sonnet / codex) get it.
`spawn_worker` runs in dispatch-code's own process, so plain `unset` / `export` here is
inherited by every launcher it invokes. No `env -i` rewrite.

| assert | condition | action | journal line |
|---|---|---|---|
| A1 | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` set and not `""`/`0` | `unset` it | `worker_env_assert arm=<arm> task=<sig8> var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=unset was=<v>` |
| A1' | unset or `0` | no-op | `worker_env_assert arm=<arm> task=<sig8> var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok` |
| A2 | `LEADV2_WORKER_TODO_TOOLS` ≠ `0` (default `1`) | `export CLAUDE_CODE_ENABLE_TODO_TOOLS=1` | `worker_env_assert arm=<arm> task=<sig8> var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1` |
| A2' | `LEADV2_WORKER_TODO_TOOLS=0` | no-op | `worker_env_assert arm=<arm> task=<sig8> var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=skip reason=opt_out` |

"Journal one line per assert" (mission) → exactly two lines per spawn, always, including the
`action=ok` case. A silent pass is indistinguishable from a guard that never ran.

### 1.6 `plugins/leadv2/scripts/tests/test-env-guards-01.sh` *(to-create)* + registration

Registered in `plugins/leadv2/scripts/tests/run-core-offline.sh` as one entry appended to the
suite list (after line 227's `deferred-GLM ladder` row):

```
"env guards (pump cwd junk + codex instant-complete + worker env asserts)|||bash $TEST_DIR/test-env-guards-01.sh"
```

Harness conventions copied from `test-glm-deferred-ladder.sh`: `set -uo pipefail`,
`mktemp -d` + `trap rm -rf`, `pass()/fail()`, self `bash -n`, `bash -n` on every binary under
test, and a **poison fence** — `LEADV2_DISPATCH_CODEX_BIN` / `LEADV2_DISPATCH_KIMI_BIN` /
`LEADV2_BACKLOG_PUMP_DISPATCH_BIN` pointed at scripts that `exit 99` on invocation, so no real
provider can be reached.

Legs (each with its RED-first leg demonstrated by `git stash`-ing the fix and re-running):

| # | leg | red before fix | green after |
|---|---|---|---|
| 1 | run pump `status` with `cwd` = fake worktree (`git worktree add` inside a temp repo), `LEADV2_PROJECT_ROOT`/`CLAUDE_PROJECT_DIR` unset | `find <wt>/.claude/cache -name 'liveness.*'` → 3 files | → 0 files; files appear under the main checkout instead |
| 2 | same, hook `leadv2-supervisor-pump-caller.sh` below-floor path | sentinel under `<wt>/.claude/cache/backlog-pump/` | sentinel under main root |
| 3 | rollout fixture with terminal `task_complete`/`last_agent_message:null` + a `user_message` containing the fake `WORK_ROOT`; stubbed `codex-task.sh` returning a live handle; `LEADV2_CODEX_SESSIONS_DIR` → fixture dir | dispatch confirms codex, journal has no `arm_dead_instant_complete` | journal has `arm_dead_instant_complete arm=codex task=<sig8>` **and** `arm_refused … reason=instant_complete`; `LAST_ARM_OUTCOME=codex_dead_instant_complete`; spill to next arm observed |
| 3b | rollout fixture with non-null `last_agent_message` | — | no `arm_dead_instant_complete`; codex confirmed (proves no false spill) |
| 3c | no rollout binds (empty sessions dir) | — | no `arm_dead_instant_complete` (fail-open) |
| 4 | spawn with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` exported into the dispatcher | no `worker_env_assert` lines | `…action=unset was=1` line present; the launcher stub records the var as **absent** in its own env |
| 4b | spawn with the var unset | — | `…action=ok` + `…CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1`; launcher stub records `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` |

Leg 4/4b assert on the **launcher stub's observed env**, not on the dispatcher's source — the
CLAIM-EVIDENCE-GATE-01 lesson already encoded in `test-glm-deferred-ladder.sh` leg (d).

Fixture rollouts live under `plugins/leadv2/scripts/tests/fixtures/codex-rollouts/`.

---

## 2. Data flow (numbered)

**Item 1 (pump write path)**
1. Hook or supervisor invokes `leadv2-backlog-pump.sh <verb>` with the *caller's* cwd.
2. Root block resolves `PROJECT_ROOT` (env → env → git toplevel).
3. **NEW** `_lv2bp_canonical_root` maps a linked-worktree root → the main checkout; sets
   `CANONICAL_ROOT` and (b) rewrites `PROJECT_ROOT`.
4. `CACHE_DIR` / `EMPTY_STREAK_DIR` derive from `CANONICAL_ROOT`.
5. `_resolve_liveness_json` writes `liveness.{json,sig,ts}` — now always in the main checkout.
6. product-close's `unscoped_lane_work` gate sees a clean lane.

**Item 2 (codex arm)**
1. `spawn_worker(codex)` → `codex-task.sh task … --background --cwd $WORK_ROOT` → handle.
2. `_wait_arm_early_verdict` (existing) — terminal-failure / no-work window.
3. `_codex_first_byte_deadline_check` (existing) — silence window.
4. **NEW** `_codex_rollout_for_task` binds a rollout by mtime + `$WORK_ROOT` in `user_message`.
5. **NEW** `_codex_instant_complete_check` polls `leadv2-codex-rollout-shape.py` for ≤N s.
6. `shape=dead` → journal `arm_dead_instant_complete`, short provider lockout, `dispatch_abort`,
   `return 7` → the existing candidate loop spills to the next arm.

**Item 3 (worker env)**
1. `spawn_worker()` entered.
2. **NEW** `_worker_env_asserts` runs A1 + A2 in the dispatcher's own process; journals 2 lines.
3. `case "${arm}"` launches glm / sonnet / codex, which inherit the corrected env.

---

## 3. Interface contracts

| Symbol | Signature | Contract |
|---|---|---|
| `_lv2bp_canonical_root` | `<candidate> -> stdout root` | Never fails; identity on non-worktree / non-git |
| `LEADV2_BACKLOG_PUMP_CACHE_DIR` | env, path | Test seam; absent ⇒ `${CANONICAL_ROOT}/.claude/cache/backlog-pump` |
| `leadv2-codex-rollout-shape.py` | `<path>` → `shape=<dead\|alive\|running\|unknown> bytes=<n> lines=<n>` | Always exit 0 |
| `_codex_rollout_for_task` | `<sig8> <work_root> <since_epoch>` → path or `""` | `""` ⇒ caller proceeds |
| `_codex_instant_complete_check` | `<handle> <sig8>` → `0` proceed / `7` dead | Mirrors `_codex_first_byte_deadline_check` |
| `LEADV2_CODEX_SESSIONS_DIR` | env, dir | Default `$HOME/.codex/sessions` |
| `LEADV2_CODEX_INSTANT_COMPLETE_SECS` | env, int | Default `30`; `0` disables |
| `LEADV2_CODEX_INSTANT_COMPLETE_LOCKOUT_MIN` | env, int 1..10080 | Default `15` |
| `LEADV2_WORKER_TODO_TOOLS` | env, `0`/`1` | Default `1` |
| `_worker_env_asserts` | `<arm> <sig8>` → always 0 | Journals exactly 2 lines |

DB schema / migrations: **none** — this lane touches no database.

---

## 4. Mandatory constraint checklist

1. **Env-var naming** — all six new vars carry the `LEADV2_` prefix and match the existing
   neighbours (`LEADV2_CODEX_FIRST_BYTE_SECS`, `LEADV2_BACKLOG_PUMP_LIVENESS_BIN`,
   `LEADV2_ARM_EARLY_VERDICT_POLL_S`). `CLAUDE_CODE_ENABLE_TODO_TOOLS` /
   `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` are upstream Claude Code vars, correctly un-prefixed.
   No `LEAD_V2_*` drift introduced.
2. **File paths** — verified on disk: `leadv2-backlog-pump.sh`, `leadv2-supervisor-pump-caller.sh`,
   `leadv2-dispatch-code.sh`, `tests/run-core-offline.sh`, `tests/fixtures/`. Marked
   `(to-create)`: `lib/leadv2-codex-rollout-shape.py`, `tests/test-env-guards-01.sh`,
   `tests/fixtures/codex-rollouts/*`.
3. **`claude -p` commands** — this lane introduces none. N/A.
4. **Concurrent access** — `CACHE_DIR` is written by the pump under the existing
   `PUMP_LOCK_DIR` flock (line 498, keyed on `PROJECT_ROOT`). Moving `PROJECT_ROOT` to the
   canonical root **strengthens** that lock: today two pumps in two worktrees hash to two
   different lock dirs and do not exclude each other. No new lock needed.
   `_worker_env_asserts` mutates process-global env inside `spawn_worker` — safe only because
   dispatch-code spawns one arm at a time per process (verified: the candidate loop is
   sequential). Flagged as a constraint the implementer must not break.
5. **Config contradiction** — `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` has zero other usages in
   the repo, so `unset` contradicts nothing. `CLAUDE_CODE_ENABLE_TODO_TOOLS` likewise has zero
   settings-level usages; the only consumers are the two hooks named in §0. No contradiction.

---

## 5. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | De-worktreeing `PROJECT_ROOT` (§1.1b) changes which `tasks.yaml` / `active.yaml` the pump reads — behaviour change beyond the cache | (c) is independent of (b) and alone satisfies acceptance. If the lane's core-offline shows any pump-adjacent red, drop (b) and ship (c). Journal line `pump_root_deworktreed` makes the change visible. |
| R2 | Rollout binding false-positive: another codex job in the same second whose mission also names this `WORK_ROOT` | `WORK_ROOT` is a per-task worktree path, so cross-task collision is not possible; same-task retry collision resolves to the newest, which is the one we care about. |
| R3 | Rollout binding false-negative on a codex build that stops echoing the mission into `user_message` | Fail-open by design (zero matches ⇒ proceed). Guard degrades to today's behaviour, never worse. Leg 3c pins this. |
| R4 | 30 s instant-complete window adds latency to every healthy codex spawn | It does **not**: `shape=running` with growing bytes returns immediately on the first poll. Worst case is a genuinely flat-but-alive job, bounded at 30 s and tunable to `0`. |
| R5 | `--minutes 15` lockout on a false positive starves codex | Short by design, and `record-quota-lockout` is already `|| true`-guarded so a lockout failure never fails the dispatch. |
| R6 | `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` restores tools that add worker token cost | Gated by `LEADV2_WORKER_TODO_TOOLS`; one env var flips it back with no code change. |
| R7 | `git rev-parse --git-common-dir` returns a relative path on older git → wrong `cd ..` | Explicitly designed around (subshell `cd` chain, §1.1a). Must be covered by leg 1 running on the stock-macOS git. |
| R8 | Suite registration line lands in a `run-core-offline.sh` region a parallel lane is also editing | Append as the last suite row; re-`git diff` immediately before `git add` (global rule). |
| R9 | `_worker_env_asserts` unsets a var the *lead* session legitimately wanted | It runs inside `spawn_worker`, whose scope is the worker launch only; the lead process is a different process. |

---

## 6. Explicitly out of scope (implementer: ignore)

- `leadv2-dispatch-product-close.sh` and `lib/leadv2-builder-selfcheck.sh` — **off_limits**, a
  live lane owns them. The `unscoped_lane_work` gate is *not* to be relaxed; item 1 removes the
  junk, it does not weaken the gate.
- Routing order, arm ceilings, the candidate-arm ladder — untouched. Item 2 adds one new spill
  reason to an existing spill path; it does not reorder arms.
- `supervise*` — deleted; resurrect nothing. (`leadv2-supervisor-pump-caller.sh` is a *hook*
  that survives the supervisor's deletion and is edited in place — no supervisor code returns.)
- Any change to `_codex_first_byte_deadline_check`'s own semantics or its 180 s default.
- Any DB/migration work, any `.claude/settings.json` edit, any shared-tree
  (`~/.claude/leadv2-shared`) edit.
- The `one-copy drift` regressions reported by the session-start hook — a separate task.
- Cleaning up already-committed junk in other lanes.

---

## 7. Acceptance

```yaml
acceptance:
  authored_at: 2026-08-20T07:05:00Z
  items:
    - id: item-1-pump-junk
      surface: file_artifact
      observable: >
        After the backlog pump runs with its working directory set to a lane worktree,
        that worktree contains no .claude/cache/backlog-pump directory at all — a
        directory listing of the worktree shows the same entries before and after the
        pump ran, and the liveness.json / liveness.sig / liveness.ts files are visible
        under the main checkout instead.
    - id: item-1-hook-sentinel
      surface: file_artifact
      observable: >
        The backlog-pump-below-floor sentinel file is visible under the main checkout's
        cache directory and is absent from the lane worktree, after the pump-caller hook
        fires from a session whose working directory is that worktree.
    - id: item-2-instant-complete
      surface: log_line
      observable: >
        The task journal shows the line "arm_dead_instant_complete arm=codex task=<sig8>"
        immediately followed by "arm_refused by=router model=codex task=<sig8>
        reason=instant_complete", and the next journal line shows a different arm being
        spawned for the same task — never a confirmed codex worker.
    - id: item-2-no-false-spill
      surface: log_line
      observable: >
        For a codex job whose rollout ends with a non-null last agent message, the task
        journal contains no arm_dead_instant_complete line and shows the codex arm
        confirmed.
    - id: item-3-env-asserts
      surface: log_line
      observable: >
        Every worker spawn writes exactly two worker_env_assert lines to the task journal
        — one naming CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS and one naming
        CLAUDE_CODE_ENABLE_TODO_TOOLS — and when the agent-teams variable was present in
        the dispatcher's environment its line reads action=unset.
    - id: suite-green
      surface: log_line
      observable: >
        run-core-offline.sh, run solo in the foreground, prints a final summary line whose
        failed and missing counts are both zero, and the new "env guards" suite name
        appears in its per-suite output as passed.
```

---

LANE_WRITES: plugins/leadv2/scripts/leadv2-backlog-pump.sh, plugins/leadv2/hooks/leadv2-supervisor-pump-caller.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/lib/leadv2-codex-rollout-shape.py, plugins/leadv2/scripts/tests/test-env-guards-01.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/tests/fixtures/codex-rollouts/*

DELIVERABLE_COMPLETE
