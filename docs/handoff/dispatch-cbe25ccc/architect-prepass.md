# architect — BROAD-STATUS-RELAY-SCOPE-01 ROUND 2 (resume of lane 91f975bf)

Design only. No implementation. Round-1 code is **uncommitted** in
`/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/91f975bf` (branch `worktree-91f975bf`,
at `85ae886`): 3 modified files + 2 untracked new files. Round 2 continues **in that worktree** and
commits round-1 + round-2 as one commit.

## 0. Ground truth established (facts the fix depends on)

| Fact | Evidence |
|---|---|
| Round-1 diff is uncommitted; nothing named `*beat-owner*` exists in any branch | `git log --all -- '*beat-owner*'` empty; worktree `git status` shows 3 M + 2 `??` |
| Two unrelated files are dirty in the same worktree | `docs/leadv2/tasks/dispatch-567ba028/journal.md`, `dispatch-59ae8b51/journal.md` — **must stay out of the commit** (critic LOW-3) |
| `.supervise-active` is a dead path | only writer is the retired `leadv2-supervise.sh:163` |
| lanes detach with `setsid`+`disown` (`leadv2-dispatch-code.sh:40,88,2358`) | ⇒ **process ancestry cannot link a lane pid back to the dispatching session.** Any "who owns this lane" design based on `ps` ancestry is unsound |
| `active.yaml` `sessions[]` rows carry `session_id` of the form `s-<ts>-<pid>-<$$>`, `pid`, `pid_birth`, `parent_session_id` — **never the Claude session UUID** | `leadv2-active-registry.sh:82-234` |
| the only per-lane artifact written *inside the dispatching session's process* is `docs/handoff/dispatch-<sig8>/arm-registered` | `leadv2-dispatch-code.sh:508-520`; sample line: `arm=sonnet handle=PID=82029 LABEL=… SESSION_ID=<lane uuid> STREAM=… epoch=…` — `SESSION_ID` there is the **lane's** uuid, not the lead's |
| `CLAUDE_SESSION_ID` is available to plugin scripts run from a session | `codex-task.sh:1150`, `leadv2-ask.sh:176`, `leadv2-reply-router.sh:52` |
| lane liveness already has an authoritative reader | `leadv2-lane-heartbeat.sh status --all --json` (verdicts `running`/`running_stale`/`dead`/`completed`/…) |
| no `.gitignore` entry covers `docs/leadv2/.pulse-*` | `grep -n 'pulse\|docs/leadv2' .gitignore` → empty (critic contradiction-scan item left open) |
| runner idiom | `run_check "<label>" bash "$TEST_DIR/<suite>.sh"`, `TEST_DIR="$PLUGIN_ROOT/scripts/tests"` (`run-core-offline.sh:34,125-130`) |

## 1. Target design

Ladder in `scripts/leadv2-beat-owner.sh` becomes (first match wins, rc always 0):

```
0. LEADV2_BEAT_RELAY_SCOPE=0 (kill-switch)                          -> unresolved
1. LEADV2_BEAT_OWNER_OVERRIDE set (test seam, kept, test-only)      -> owner|guest
2. .pulse-beat-owner missing / unparseable / epoch older than 1x BEAT_S   -> unresolved
3. owner session's .pulse-session.<sid> missing or older than 1x BEAT_S   -> unresolved   (HIGH-1)
4. owner session has 0 live lanes (lane-attribution gate)                 -> unresolved   (HIGH-2)
5. owner sid == my safe_sid                                         -> owner
6. otherwise                                                        -> guest
```
Rows 2/3 of round 1 (`.supervise-active` + `_lv2_is_ancestor`) are **deleted** — see D3.
Every reject path is `unresolved` ⇒ full relay to every session ⇒ the founder can never be starved.

### 1.1 HIGH-1 — dead owner must not starve the founder

* New state file, one per live session: `${STATE_DIR}/.pulse-session.<safe_sid>`, body = decimal
  epoch, written atomically (`tmp.$$` + `mv -f`) by `hooks/leadv2-single-lead-beat.sh` on **every**
  fire, before role resolution. Cost: one `date`, one `printf`, one `mv` — no `python3`, no `find`.
* New resolver helper `_lv2_session_alive <state_dir> <safe_sid> <beat_s>` → rc0 iff that file
  exists, parses as an integer, and `now - epoch < beat_s` (strict `<`, no floor, no 2× multiplier).
* `_lv2_beat_owner_fresh`: `max_age = beat_s` exactly — **drop `beat_s*2` and the 3600 floor**; parse
  with `read -r sid epoch _ <<<"$line"` so a 3rd field cannot corrupt it (critic LOW-1).
* Ship behaviour (reviewer Scenario E): the mandated cache-copy restart mints a new `session_id`; the
  stale owner file names the pre-restart session whose `.pulse-session.<old>` is absent (or ages out
  within one BEAT_S) ⇒ row 3 ⇒ `unresolved` ⇒ **full relay**. Defect closed.
* Accepted degradation (document it in `developer.full.md`): a genuinely-alive owner that fires no
  hook for > BEAT_S loses ownership and the beat goes to everyone. Fail-open by design; it is the
  same outcome as pre-lane behaviour, never a drop.
* GC glob must gain `.pulse-session.*` (§1.4).

### 1.2 HIGH-2 — ownership requires a live lane, not a won race

Two-sided gate; the **read side is authoritative** so a bad write cannot grant ownership.

*Write side* (`scripts/leadv2-pulse-beat.sh`, replacing the current unconditional +115-124 block):
write `.pulse-beat-owner` only when `LEADV2_BEAT_OWNER_SESSION` is non-empty **and**
`leadv2_session_has_live_lane` returns rc0 for it. Otherwise leave the file untouched (never write an
empty or unqualified owner). The resolver is sourced by path next to `$SCRIPT_DIR`; if it is absent,
skip the write (fail-open).

*Read side* (`leadv2-beat-owner.sh`, new public helper):

| Signature | Contract |
|---|---|
| `leadv2_session_has_live_lane <safe_sid> <state_dir> <project_root>` | rc0 iff ≥1 lane row is live **and** attributed to `<safe_sid>`. rc1 on "no live lane", "no attribution possible", or any internal failure. Never prints. Bounded: ≤1 `python3` call, ≤12 handoff dirs read. |

Attribution source: **`arm-registered`**, extended with one additive field `LEAD_SESSION=<uuid>`
(the dispatching session's `CLAUDE_SESSION_ID`, sanitised the same way the hook sanitises
`SAFE_SID`: `tr -c 'A-Za-z0-9._-' '_'`, first 64 chars). Algorithm:

1. Read live lanes: `leadv2-lane-heartbeat.sh status --all --json`, keep rows whose verdict is
   `running` (only `running` — `running_stale` is explicitly the honest "don't know" and must not
   confer ownership).
2. For each live lane's `task_id`, read `docs/handoff/<task_id>/arm-registered` and collect
   `LEAD_SESSION=` values.
3. rc0 iff `<safe_sid>` appears in that set.
4. If **no** live-lane row yields any `LEAD_SESSION=` field (pre-upgrade lanes, or
   `CLAUDE_SESSION_ID` unset at dispatch) ⇒ rc1 ⇒ `unresolved` ⇒ full relay everywhere. Degrades to
   today's behaviour, never to silence.

Consequence: a chatty focused session with no lanes can no longer arm-and-own; it either receives the
full relay (when nobody qualifies) or the one-line pointer (when a real dispatcher owns the beat).
That is the founder's original incident, closed at the root.

**D1 — write-set extension, needs lead sign-off.** Step 2 requires one additive change in
`plugins/leadv2/scripts/leadv2-dispatch-code.sh` (append ` LEAD_SESSION=${CLAUDE_SESSION_ID:-}` to
the existing append-only `arm-registered` line — no behaviour change, no new file, no new env var,
readers that ignore the field are unaffected). Mission off_limits says "same write-set as round 1".
**Given the setsid/disown fact above there is no in-write-set way to attribute a lane to a Claude
session**; the only alternative is the strictly weaker fallback D2. Recommendation: take D1.

**D2 — fallback if the lead refuses D1.** Gate ownership on "≥1 live lane exists anywhere in the
repo" *without* per-session attribution: zero live lanes ⇒ `unresolved` for everyone (a focused
session in a lane-free repo can never suppress anyone), ≥1 live lane ⇒ arming session may own.
This closes the lane-free half of HIGH-2 and leaves the "wrong live session in a repo with lanes"
half open; the critic will very likely re-flag it. Must be stated loudly in `developer.full.md` as a
knowingly-partial fix if chosen.

### 1.3 HIGH-3 — the suite must drive the real mechanism

`scripts/tests/test-broad-status-relay-scope.sh` keeps T1-T8 and adds real-state cases. Every new
case is **red-first**: capture failing output against the round-1 resolver first, paste both outputs
into `developer.full.md`.

| Case | Real state created | Expected role / assertion |
|---|---|---|
| T9 | `.pulse-beat-owner` = "`<me> <now>`", `.pulse-session.<me>` fresh, one live lane attributed to `<me>` | `owner` — full ready-line + `RELAY=full` in `additionalContext` |
| T10 | same but owner sid = `<other>` (with `<other>`'s heartbeat fresh + lane) | `guest` — exactly one line, contains no `BROAD_STATUS_READY` bytes |
| T11 | fresh owner file naming `<other>`, **no** `.pulse-session.<other>` (reviewer Scenario E) | `unresolved` → full relay |
| T12 | fresh owner file, `.pulse-session.<other>` stamped `now - beat_s - 1` | `unresolved` → full relay |
| T13 | owner file torn/one-field/`epoch=abc`/3-field-plus | `unresolved`, no crash, `read -r sid epoch _` path exercised |
| T14 | owner file + fresh heartbeat, but **zero** live lanes for that sid | `unresolved` (HIGH-2 read-side gate) |
| T15 | `.pulse-beat-owner` absent; run real `leadv2-pulse-beat.sh --check` with `LEADV2_BEAT_OWNER_SESSION=<me>` and a live attributed lane | file created, contains `<me> <epoch>` |
| T16 | same, but no live lane for `<me>` | file **not** created (write-side gate) |
| T17 | same, `LEADV2_BEAT_OWNER_SESSION` empty | file untouched (round-1 invariant preserved) |
| T18 | `.supervise-active` present with a **live real child pid** | role unaffected by it — regression pin that the retired path is inert (replaces the deleted ancestry test) |
| T19 | hook fires with `LEADV2_BEAT_OWNER_OVERRIDE` unset and `BEAT_OWNER_SH` deleted | role `unresolved`, full relay, **one stderr line** emitted (MEDIUM-2) |

Harness rules: throwaway repo under `mktemp -d`, `LEADV2_STATE_ROOT`/`LEADV2_PROJECT_ROOT` pointed at
it, **no `LEADV2_BEAT_OWNER_OVERRIDE`** in T9-T19, lane liveness faked by writing a real
`active.yaml` row + heartbeat through `leadv2-active-registry.sh`/`leadv2-lane-heartbeat.sh` (or, if
that proves too heavy, by stubbing `leadv2-lane-heartbeat.sh` on `PATH`-equivalent lookup — but then
T15/T16 must still exercise the real resolver helper, not a seam), and `arm-registered` hand-written
with a `LEAD_SESSION=` field. T18 spawns `sleep 30 &` and uses `$!` as the real pid.

### 1.4 MEDIUMs and LOWs

| ID | File:anchor | Change |
|---|---|---|
| M1 | `scripts/tests/run-core-offline.sh` after line 130 | `run_check "broad-status relay scoping" bash "$TEST_DIR/test-broad-status-relay-scope.sh"` |
| M2a | new test file | `chmod 755` (resolver stays 644, it is sourced) |
| M2b | `hooks/leadv2-single-lead-beat.sh:74` | `else printf -- '[single-lead-beat] beat-owner resolver missing: %s\n' "$BEAT_OWNER_SH" >&2` on the `[[ -f ]]` miss; add `# shellcheck source=/dev/null` above the `source` (LOW-2) |
| M3 | `hooks/leadv2-supervisor-mode-reinject.sh:~136-140` | make the directive RELAY-conditional: `RELAY=full` → paste `docs/leadv2/founder-status.md` verbatim, never compose one; `RELAY=none` → relay only that single beat line and do not read the file. Keep the existing `plugin-generated artifact` / narration sentences **byte-identical** — they are counted anchor invariants |
| M4 | `hooks/leadv2-single-lead-beat.sh:126` | guest line tail becomes `… (RELAY=none); do not read founder-status.md; relay only this line.` Invariant: still exactly one line, still contains no `BROAD_STATUS_READY` substring, so the anchor's verbatim-relay rule cannot latch. Re-check `task-anchor.sh:223,706` wording agrees |
| M5 | `hooks/leadv2-single-lead-beat.sh:93-94` | gate the prune behind a daily stamp: if `${STATE_DIR}/.pulse-gc-day` != `$(date +%Y%m%d)` then write the stamp and run the `find` once; add `-o -name '.pulse-session.*'` to the globs. Pure-bash on the 99.99% path — no `find` per `PostToolUse` |
| LOW-1 | `leadv2-beat-owner.sh:35-36` | `read -r sid epoch _ <<<"$line"` |
| LOW-3 | commit hygiene | `git add` only the 7 lane paths; leave both `journal.md` files unstaged |
| CS-1 | `.gitignore` | add `docs/leadv2/.pulse-*` (+ `.broad-status-prev.json` if not already ignored) — closes the critic's open contradiction-scan item so state files are not committed by a later lane |

## 2. Data flow (numbered, post-change)

1. Any hook event → `leadv2-single-lead-beat.sh` parses `session_id`, computes `SAFE_SID`.
2. Hook writes `.pulse-session.<SAFE_SID>` = now (atomic). *(new)*
3. Hook resolves `STATE_DIR`, sources `leadv2-beat-owner.sh` (stderr line if missing).
4. Hook runs the daily-stamped GC. *(changed)*
5. `leadv2_beat_role SAFE_SID STATE_DIR BEAT_S` → `owner|guest|unresolved` per §1 ladder, consulting
   `.pulse-beat-owner`, `.pulse-session.<owner>`, and `leadv2_session_has_live_lane`.
6. DELIVER: unchanged dedupe (`at=` watermark + body hash); `guest` ⇒ one-line pointer (M4 wording),
   `owner`/`unresolved` ⇒ ready-line + `RELAY=full`.
7. TRIGGER: background `leadv2-pulse-beat.sh --check` with `LEADV2_BEAT_OWNER_SESSION=$SAFE_SID`.
8. `pulse-beat --check` passes loop-liveness + throttle, stamps `.pulse-beat-last`, then writes
   `.pulse-beat-owner` **only if** the arming session has a live attributed lane. *(changed)*
9. `--now` child runs pump + composer; `founder-status.md` rewritten; next hook fire delivers it.

## 3. Risks

| Risk | Mitigation |
|---|---|
| Attribution silently never works (no `LEAD_SESSION` field in production) ⇒ scoping permanently off | intended fail-open; T-case asserts it, and `developer.full.md` must say "verify a post-ship `arm-registered` line carries `LEAD_SESSION=`" as the live check |
| `leadv2-lane-heartbeat.sh status --all --json` is slow or `set -euo pipefail`-aborts inside the resolver | resolver is `set -uo pipefail` only and must call it in a subshell with `|| true` + `2>/dev/null`; treat any non-zero/unparseable output as rc1 (unresolved) |
| resolver now runs on **every** hook fire including `PostToolUse` | budget: ≤1 `python3`/`json` parse + ≤12 small file reads, only reached when `.pulse-beat-owner` exists and is fresh; rows 2/3 short-circuit before any lane work |
| concurrent access: `.pulse-beat-owner` written by background `--check` while a foreground hook reads it | writes are `tmp.$$`+`mv -f` (atomic rename), readers tolerate a torn/absent read via T13 path — no lock needed |
| `.pulse-session.<sid>` unbounded growth | daily-stamped GC prunes `-mtime +7` (M5) |
| hook change not live | **canonical edit is NOT live**: `leadv2-single-lead-beat.sh`, `leadv2-task-anchor.sh`, `leadv2-supervisor-mode-reinject.sh` all need a **plugin-cache copy + session restart**. Restate this loudly in both deliverable files (round-1 critic accepted this only because it was explicit) |
| deleting `_lv2_is_ancestor` deviates from the mission's literal test list | D3 below — state it prominently |

**D3.** `_lv2_supervise_active_pid` + `_lv2_is_ancestor` and ladder rows 2/3 are deleted: the
supervisor is retired, and setsid-detached lanes make ancestry unusable for the new gate — keeping
them would be dead code with a test that proves nothing. Mission item 3 asked for `_lv2_is_ancestor`
coverage; the design satisfies its *intent* (test the mechanism, not the seam) via T18, which pins
that a live `.supervise-active` pid is inert. Implementer must say so in `developer.full.md`.

## 4. Constraint checklist

1. **Env vars** — no new ones. Existing `LEADV2_BEAT_RELAY_SCOPE`, `LEADV2_BEAT_OWNER_OVERRIDE`,
   `LEADV2_BEAT_OWNER_SESSION`, `LEADV2_SINGLE_LEAD_BEAT{,_S}` all `LEADV2_*`; no `LEAD_V2_*` drift.
2. **Paths** — all listed files exist except the two new round-1 files (present, untracked) and
   `.pulse-session.*` / `.pulse-gc-day` (to-create at runtime).
3. **`claude -p`** — none introduced. N/A.
4. **Concurrent access** — `.pulse-beat-owner` (bg writer / fg reader) and `.pulse-session.<sid>`
   (single writer) covered above; atomic rename, no lock.
5. **Config contradiction** — `.supervise-active` readers elsewhere are untouched by this diff;
   removing this file's dependency on it changes no other caller.

## 5. Out of scope

Product-close, review-run, `leadv2-broad-status.sh` (composer), throttle/cadence,
`leadv2-supervise*.sh`, `test-broad-status-duty.sh` (pre-existing wall-clock failures, unregistered —
do not fix here), the tracked-vs-untracked audit of `.claude/scripts/tests/`, and the two dirty
`journal.md` files.

## 6. Verification gate for the implementer

`bash -n` on every touched script; `shellcheck` (only SC1090 tolerated, and that one gets a
directive); the new suite green **and** its red-first predecessor output captured; `run-core-offline.sh`
green with the new row and no new failures; the three reviewer contexts (owner / guest / fail-open)
plus Scenario E re-run against **real** state with no override, raw output pasted; single commit on
`worktree-91f975bf` excluding the two `journal.md` files.

acceptance:
- surface: rendered_line
  observable: In a Claude session started after the mandated hook-cache restart (new session_id),
    while docs/leadv2/.pulse-beat-owner still names the previous session, the founder sees the whole
    founder-status.md pasted into chat — not the single "full status in owning session (RELAY=none)"
    pointer line.
  authored_at: 2026-08-19T13:55:00Z
- surface: rendered_line
  observable: With two live sessions where only one has a running dispatched lane, the founder sees
    the full status text in the dispatching session's chat and, in the other session, exactly one
    line ending "do not read founder-status.md; relay only this line."
  authored_at: 2026-08-19T13:55:00Z
- surface: log_line
  observable: The core-offline runner's printed result list contains a row labelled
    "broad-status relay scoping" marked ok, and its trailing failure count is still 0.
  authored_at: 2026-08-19T13:55:00Z
- surface: file_artifact
  observable: A reader of the round-2 commit on branch worktree-91f975bf sees the 3 HIGH and 5 MEDIUM
    finding ids each named with its fix, and sees no docs/leadv2/tasks/*/journal.md file in the commit.
  authored_at: 2026-08-19T13:55:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-beat-owner.sh, plugins/leadv2/scripts/leadv2-pulse-beat.sh, plugins/leadv2/hooks/leadv2-single-lead-beat.sh, plugins/leadv2/hooks/leadv2-task-anchor.sh, plugins/leadv2/hooks/leadv2-supervisor-mode-reinject.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, .gitignore

DELIVERABLE_COMPLETE
