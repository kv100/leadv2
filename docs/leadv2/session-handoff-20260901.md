# Session handoff — 2026-09-01, leadv2 plugin repair session

Read this file FIRST in the new session, then `docs/leadv2/open-threads.md`. Everything below is on
disk; nothing here depends on the previous session's context.

All work is in **`~/Projects/leadv2`** (the plugin repo), not in persona-engine.

## 1. Read this before you touch anything

**Ending a Claude session can kill a live codex worker.** The openai-codex plugin's `SessionEnd`
hook tears down the shared `codex app-server` broker for the cwd, and the broker is the process tree
every codex job depends on. Memory: `reference-codex-sessionend-kills-other-sessions`. The lane
`TESTS-POLLUTE-REAL-JOURNAL-01` is running on codex right now and has already died six times today —
assume it is dead when you arrive and check it first.

**`hooks.json` changed this session** (the lane watcher now arms itself on `Stop` and disarms on
`SessionEnd`, replacing `leadv2-idle-guard-arm.sh` + `leadv2-idle-lead-guard.sh`). Hook tables are
read at session start from the plugin cache, so the new session is the first one that will actually
run it. If it does not arm, the cache copy is stale — that is the known plugin-cache exception in
`~/.claude/CLAUDE.md`.

**The phase gate now enforces.** A brand-new lane is refused with
`missing mandatory phases: plan,gate1`. That is correct and intended — it is this session's fix.
Before dispatching a NEW lane, record both, with `LEADV2_PROJECT_ROOT` exported (the script reads
that name, not `PROJECT_ROOT`):

```bash
export LEADV2_PROJECT_ROOT=~/Projects/leadv2
bash plugins/leadv2/scripts/leadv2-phase-record.sh record <sig8> plan  --artifact docs/handoff/<ID>/brief.md
bash plugins/leadv2/scripts/leadv2-phase-record.sh record <sig8> gate1 --reason "<one line>"
```

The `<sig8>` is printed by the refused dispatch itself (`dispatch_task_bound task=<sig8>`).

## 2. In flight — four lanes, all out of process, all survive a session change

| Lane | Arm | Commits over main | Last write | What it owes |
|---|---|---|---|---|
| `RESUME-LANE-ACCEPTS-PATH-01` | freepool | 4 | 12 min | round 2: the suite is 21/0 but stays 21/0 when the fix is mutated — make it depend on the branch |
| `ONE-LANE-WATCH-01-R2` | freepool | 2 | 37 min | round 2: mtime grace never expires; codex lane has no dispatch age; single signal; the idle-guard's "queued work, no live lane" job was dropped |
| `PLUGIN-PAPERCUTS-01` | freepool | 0 | 33 min | round 2: P1 asserts a contract main deliberately retired |
| `TESTS-POLLUTE-REAL-JOURNAL-01` | codex | 0 (anchor only) | 5 h | tests write into the real journal; **six codex deaths, expect it dead** |

Each lane's instructions are its own `docs/handoff/<ID>/fix-round-2.md` (or `brief.md`) in
`~/Projects/leadv2`. Worktrees are `~/Projects/leadv2/.claude/worktrees/<ID>`.

**Check a lane like this** — never trust a status field, and never trust `lane-liveness --all`
(measured this session: 231 rows, 0 alive, while a lane was actively writing):

```bash
cd ~/Projects/leadv2
W=.claude/worktrees/<ID>
git -C $W log --oneline main..HEAD | head
git -C $W status --porcelain | grep -vE 'docs/leadv2/|docs/handoff/dispatch-|LEAD_V2_STATE'
```

Uncommitted work in a lane means the worker died mid-flight: commit it as
`salvage(<ID>): ...` immediately, before anything else. That happened twice today and both times
the work was complete and would have been lost.

## 3. Re-dispatch commands

Resume an existing lane (worktree already exists):

```bash
cd ~/Projects/leadv2 && export LEADV2_PROJECT_ROOT=~/Projects/leadv2
bash plugins/leadv2/scripts/leadv2-dispatch-code.sh @docs/handoff/<ID>/fix-round-2.md \
  --task-id <ID> --resume-lane <ID> --task-class standard --force
```

A new lane drops `--resume-lane` and needs plan+gate1 recorded first (§1).

## 4. Not started — briefs are written, dispatch is one command each

| Lane | Estimate | Brief |
|---|---|---|
| `PROMISE-GUARD-TURN-IT-ON-01` | ~40 min | `docs/handoff/PROMISE-GUARD-TURN-IT-ON-01/brief.md` |
| `DISPATCH-HANDLE-SLICE-UNATTRIBUTED-01` | ~40 min | filed today, backlog priority 96 |
| `CODEX-COOLDOWN-DOES-NOT-ESCALATE-01` | ~40 min | filed today, backlog priority 97 |
| `ARM-CAPABILITY-FROM-OUTCOMES-01` | ~1 h | `docs/handoff/ARM-CAPABILITY-FROM-OUTCOMES-01/brief.md` |
| `CLASS-IS-COMPUTED-NOT-DECLARED-01` | ~1 h | `docs/handoff/CLASS-IS-COMPUTED-NOT-DECLARED-01/brief.md` |
| `MAIN-CORE-SUITE-RED-01` | ~1 h | `docs/handoff/MAIN-CORE-SUITE-RED-01/brief.md` |

Lane cap is **4** (founder order). Keep four running.

## 5. Merged today, each with a mutation negative control the lead ran itself

| Commit | Lane | Control |
|---|---|---|
| `028da82` | GUARDS-MUST-PROVE-THEY-FIRE-01 | early-return in `_leadv2_gv_bail_on_exit` ⇒ 21/2, exit 1 |
| `c49cc9f` | ONE-LANE-WATCH-01 | `if false` on the stall decision ⇒ 9/4, exit 1 |
| `9ab58c7` | PHASE-GATE-IS-INVERTED-01 | `_lane_bootstrap=1` in the store probe ⇒ 9/4, exit 1 |
| `abcef42` | — | salvage: an unattributed handle parser found uncommitted on main, load-bearing |

Plus earlier in the session: `7b9faac`, `7891d7e`, `1d17985`, `c01e983`, `9813ca0`.

## 6. Two things that are true and must not be re-derived

**The codex deathwatch works.** It named a real death on the live path today, not in a test:

```
2026-09-01T17:32:42Z ARM_COOLDOWN arm=codex reason=transport_gone_app_server_absent
  reprobe_at=2026-09-01T17:47:42Z cooldown_s=900 job=task-mtixzrp8-g608xy
```

That handle is the one the dispatcher returned. Store: `~/.claude/cache/arm-cooldown/codex.state`.
What is missing is escalation — the cooldown is always 900 s, so the arm is re-elected 15 minutes
later and dies again. **Never fix this by excluding codex from routing** (founder standing rule).

**`test-phase-precondition` is 75/4 RED on main and has been.** Identical failure set from a lane
worktree, so no lane caused it. Cause is one step earlier than believed: not `rc=127` but
`project_root_guard status=foreign_env_overridden`. Recorded in `MAIN-CORE-SUITE-RED-01/brief.md`.

## 7. Owed, deliberately deferred by the founder

`SD-PLUGIN-FIXES-BEHAVIOURAL-PROOF-01` in `docs/leadv2/scheduled-decisions.md`: after ALL lanes
close, prove four fixes behaviourally (real `EAGAIN`; real review-gate refusal; a real dispatch where
liveness reports alive on any arm; a failed POST in task-add), each with a control proving the probe
is not blind. Founder's words: green tests are not proof a feature works.

The lane watcher this session ran by hand lives at
`plugins/leadv2/scripts/leadv2-lane-watch-v2.sh` on main; its two known bugs are the content of
`ONE-LANE-WATCH-01-R2`. Until that lands, a session can watch lanes manually with the same script.
