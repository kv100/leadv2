# PULSE-WAKE-01 — architect prepass (mechanism-closed design)

Base: `b4ceda8`. Repo: `~/Projects/leadv2`. Role: architect prepass. **No implementation performed.**

---

## 0. Three places the mission's framing is wrong; the design follows the code

All three were probed on the live tree, not assumed.

| # | Mission says | Tree says | Design decision |
|---|---|---|---|
| M1 | `docs/single-lead-pulse.md` | That path does not exist. The doc is `plugins/leadv2/docs/single-lead-pulse.md` (6298 B, 105 lines). `ls docs/single-lead-pulse.md` → `No such file or directory`. | Deliverable 3 targets `plugins/leadv2/docs/single-lead-pulse.md`. |
| M2 | founder-status.md path "via the state-path resolver, NOT hardcoded" | `founder-status.md` is **not** a control-plane file. `leadv2-state-path.sh:244-253` `STANDARD` = `{active.yaml, active.yaml.lock, bus.jsonl, .bus.lock, .bus-offsets, merge-queue.jsonl, .merge.lock, open-threads.md, questions}` — no `founder-status.md`. Both the writer (`leadv2-broad-status.sh:36`) and the reader (`hooks/leadv2-single-lead-beat.sh:132`) use `${LEADV2_FOUNDER_STATUS_PATH:-$PROJECT_ROOT/docs/leadv2/founder-status.md}`. | The watcher resolves the **same** expression. Routing it through `leadv2-state-path.sh founder-status.md` would yield `~/.claude/leadv2-state/<slug>/founder-status.md` — a path **nothing writes** → mtime never changes → the watcher is armed and permanently silent, i.e. it would reproduce the exact bug it exists to fix. This is the single most dangerous instruction in the mission and it is refused with evidence. `leadv2-state-path.sh` IS still used, but for `--no-link root` (state dir) only, exactly as the beat hook does at `leadv2-single-lead-beat.sh:107-109`. |
| M3 | (implicit) the doc just needs new wording | `plugins/leadv2/docs/single-lead-pulse.md:24-33` (§"Why hook-clock, not a daemon or `CronCreate`") **argues against this lane's entire mechanism** by name: "A detached 30-minute daemon armed via a lead-side `Monitor` would bill the founder for a wake on every remaining turn of an idle session, per `~/.claude/CLAUDE.md` §Token discipline rule 5". | That section is now superseded by founder order 2026-08-24 and must be **rewritten, not appended to**. A doc that keeps both claims is a doc that tells the next lead the watcher is a violation. The cost objection is real and is answered explicitly (see §3.3 of the new doc content, below), not deleted silently. |

Also probed and **not** a problem: `hooks/leadv2-orphan-monitor-sweep.sh:18-24` SIGKILLs monitor pgroups older than 15 min, but its `awk` selector requires the command text to contain `codex-task.sh status` AND `/bin/zsh -c`. The pulse watcher command contains neither, so it is not swept. This is a **naming constraint on the implementation**: the printed watcher command must never contain the substring `codex-task.sh status`.

`hooks/leadv2-monitor-cap-gate.sh:22-24` — deny threshold `LEADV2_MONITOR_DENY_AT` defaults to 1000000 (effectively never); advisory at 3. Arming one more Monitor is allowed; at ≥3 total Monitors in the transcript the lead gets a stdout advisory. Non-blocking.

---

## 1. CALLERS / CALLEES

### 1.1 New file `plugins/leadv2/scripts/leadv2-pulse-watch.sh`

**Callees** (everything it invokes):

| Callee | Where | Why |
|---|---|---|
| `stat -f %m <f>` (BSD) → fallback `stat -c %Y <f>` (GNU) | mtime probe, once per iteration | bash 3.2, macOS-first, Linux-safe. No `stat -c %m` — on GNU that is *birth* semantics confusion; `%Y` is mtime. |
| `head -n 1 <f>` | emission | one line, exits, so it flushes |
| `sleep <n>` | end of iteration | |
| `git -C "$PWD" rev-parse --show-toplevel` | PROJECT_ROOT fallback only | same idiom as `leadv2-pulse-beat.sh:31` |
| `plugins/leadv2/scripts/leadv2-state-path.sh --no-link root` | **not called** | see M2 — deliberately not on this path |

**Callers** (who invokes it):

| Caller | file:line | Mode | Notes |
|---|---|---|---|
| `hooks/leadv2-pulse-watch-arm.sh` (NEW) | new file | `--print` | SessionStart, captures stdout into the directive string |
| The lead's `Monitor(...)` tool call | runtime, not a repo file | `--emit-loop` | the long-lived process |
| `scripts/tests/test-pulse-watch.sh` (NEW) | new file | both | |
| Founder / operator by hand | — | `--print` | recovery path when the SessionStart line was missed |

**No existing caller changes behaviour.** The watcher is additive: nothing in `leadv2-pulse-beat.sh`, `leadv2-broad-status.sh`, or `hooks/leadv2-single-lead-beat.sh` is edited by this lane.

### 1.2 The mechanism's other half — the independent copies nobody named

The beat→relay path has **two** delivery-side consumers, and this lane touches neither. Both must keep working:

1. `hooks/leadv2-single-lead-beat.sh` — wired at `hooks.json` under `UserPromptSubmit` and `PostToolUse` matcher `.*`. Steps: DELIVER (`:135-172`) then TRIGGER (`:175-179`).
   - `:137` reads the last `BROAD_STATUS_(READY|FAILED)` line out of `supervise-loop.log`.
   - `:128` `leadv2_beat_role()` (sourced from `scripts/leadv2-beat-owner.sh`) decides `owner` vs `guest`.
   - `:154` guest → `RELAY=none` one-liner. `:156-158` owner → `RELAY=full`.
   - `:143-146` **body-hash dedupe**: `at=` change alone does not emit; `tail -n +2 founder-status.md | shasum -a 256` must also differ from `.pulse-body-hash.<sid>`.
2. `hooks/leadv2-task-anchor.sh:228-233` and `:883-888` — an **independent second copy** of the RELAY=full/none prose, injected into the task-anchor block. Two copies of the same contract wording exist in the tree. This lane changes neither, but any future wording edit that touches only one of them drifts. Flagged, not fixed here (out of scope, §6).

**The critical interaction:** the watcher does *not* deliver the status. It only **creates a turn**. On that turn, `UserPromptSubmit`/`PostToolUse` fires `leadv2-single-lead-beat.sh`, which does the actual RELAY injection. So the watcher's emitted line is a *wake token*, and it is fine — expected, even — for it to be redundant with what the beat hook then injects.

Corollary that constrains the emitted text: `leadv2-single-lead-beat.sh:154` deliberately keeps the `BROAD_STATUS_READY` bytes **out** of the guest line "so the task-anchor's verbatim-relay rule cannot latch". The watcher emits **line 1 of founder-status.md**, which is the status's own timestamp header — not a `BROAD_STATUS_READY` line — so it does not latch either. Requirement: **the watcher must not synthesize a `[SUPERVISE-URGENT] BROAD_STATUS_READY` string.** If it did, a guest session would be tricked into a full relay it is not the owner of.

### 1.3 New file `plugins/leadv2/hooks/leadv2-pulse-watch-arm.sh`

**Caller:** `plugins/leadv2/hooks/hooks.json`, `hooks.SessionStart[0].hooks[]`, appended **after** the `leadv2-idle-guard-arm.sh` entry (currently `hooks.json:69`) and **before** `leadv2-merged-worktree-sweep.sh` (`hooks.json:76`).

**Callees:**

| Callee | Why |
|---|---|
| `python3 -c` (stdin JSON → `session_id`, `cwd`, `agent_type` presence) | same idiom as `leadv2-idle-guard-arm.sh:33-40` |
| `source hooks/leadv2-mode-isolation.sh` → `leadv2_hook_is_supervisor_session` | same idiom as `leadv2-hardbans-reinject.sh:12-13` |
| `bash scripts/leadv2-pulse-watch.sh --print` | to obtain the command string |
| `git -C "$CWD" rev-parse --show-toplevel` | PROJECT_ROOT, same as `leadv2-idle-guard-arm.sh:51` |
| `jq -n` with `python3 -c json.dumps` fallback | JSON emission, same as `leadv2-single-lead-beat.sh:182-194` |

**Why a new hook file rather than extending `leadv2-idle-guard-arm.sh`:** that hook is gated on `LEADV2_IDLE_GUARD` (`:22`) and hard-requires `docs/tasks.yaml` (`:54`). Folding the pulse in would (a) make the idle-guard kill switch silently disable the founder pulse, and (b) suppress the pulse in any repo without `docs/tasks.yaml`. A separate file gives a one-line rollback (delete the `hooks.json` entry) and an independent kill switch.

---

## 2. STATES AND RETURN CODES

### 2.1 `leadv2-pulse-watch.sh --print`

| State | stdout | rc | What the caller (arm hook) does | User-visible consequence |
|---|---|---|---|---|
| normal | one line: `bash <abs>/leadv2-pulse-watch.sh --emit-loop` | 0 | wraps it in the PULSE-WAKE directive | lead arms the watcher on turn 1 |
| `LEADV2_PULSE_WATCH=0` | *(empty)* | 0 | empty command → hook emits **no** additionalContext | pulse watcher disabled; the pre-existing hook-clock relay still works, so the founder gets a beat on the next turn he types — i.e. today's behaviour, not silence-plus-nothing |
| `LEADV2_SINGLE_LEAD_BEAT=0` | *(empty)* | 0 | same | whole pulse feature off (existing master switch) |
| script path unresolvable (`CLAUDE_PLUGIN_ROOT` unset **and** `BASH_SOURCE` dir not readable) | *(empty)* | 0 | no directive | no watcher; founder-visible silence returns until he types. **This is the one silent-degradation path and it must be logged to stderr** so the SessionStart transcript shows it. |

`--print` **never** returns non-zero. A SessionStart hook that fails is a session that fails to start.

### 2.2 `leadv2-pulse-watch.sh --emit-loop`

| State | stdout | rc / lifetime | What Monitor does | User-visible consequence |
|---|---|---|---|---|
| armed, file exists, mtime unchanged | nothing | runs on | no event | quiet — correct, nothing changed |
| **first** observation after arming | nothing (suppressed) | runs on | no event | arming does not fake a beat |
| mtime changed, line 1 non-empty | `<line 1 of founder-status.md>` | runs on | one notification → **lead gets a turn** → `leadv2-single-lead-beat.sh` injects RELAY | founder sees the 30-min status in chat |
| mtime changed, line 1 **empty** | `[BROAD_STATUS] beat mtime=<epoch> path=docs/leadv2/founder-status.md (line 1 empty)` | runs on | one notification | founder still gets woken; the lead reads the file itself. Never emit a blank line — Monitor treats blank stdout as an event with no content, which reads as a phantom beat. |
| file absent at arm, appears later | line 1 on the appearance | runs on | event | a repo whose first beat has not composed yet still wakes on beat #1 |
| file absent at arm, still absent | nothing | runs on | no event | quiet; not an error — nothing has ever been composed |
| file deleted after having existed | nothing (mtime probe empty ⇒ treated as "no reading", `prev` untouched) | runs on | no event | watcher survives; when the composer rewrites the file the next beat fires. **Deliberate:** deletion must not emit, and must not poison `prev` such that the recreated file's mtime looks unchanged. |
| `--max-iters N` reached (test-only) | — | exit 0 | monitor ends, one completion notification | test determinism only; default is unbounded |
| `LEADV2_PULSE_WATCH=0` | nothing | exit 0 immediately | monitor ends instantly | kill switch honoured even for an already-issued command |
| SIGTERM (TaskStop / session end) | — | killed | watch ends | **silence returns.** See §4. |

**rc semantics:** `--emit-loop` never exits non-zero on a transient condition (unreadable file, stat failure, empty head). It exits 0 only on kill switch or `--max-iters`. A non-zero exit would surface in the Monitor completion notification as a failure and invite the lead to re-arm in a retry loop.

### 2.3 `hooks/leadv2-pulse-watch-arm.sh` (SessionStart)

| State | stdout | rc | Consumer behaviour | User-visible consequence |
|---|---|---|---|---|
| lead session, all gates pass | `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"PULSE-WAKE: …"}}` | 0 | line lands in session context | lead arms the watcher on turn 1 |
| `agent_type` present in stdin JSON | `{}`-equivalent (nothing) | 0 | no context | a subagent never arms a watcher — it has no founder chat to relay into, and its Monitor would die with the subsession |
| cwd matches `*/.claude/worktrees/*` | nothing | 0 | no context | lane workers do not arm; only the main-checkout lead does. Without this, N concurrent lanes each arm a watcher on the same file ⇒ N duplicate notifications per beat, which is precisely `~/.claude/CLAUDE.md` §Token discipline rule 5's "one watcher per journal, never two". |
| `leadv2_hook_is_supervisor_session` true | nothing | 0 | no context | supervisor mode owns its own cadence |
| no `<root>/docs/leadv2` dir | nothing | 0 | no context | non-leadv2 repo untouched |
| `--print` returned empty | nothing | 0 | no context | see §2.1 degradation row |
| `jq` missing | python3 `json.dumps` fallback line | 0 | line lands | identical behaviour |
| any internal error | nothing | **0** | no context | `trap 'exit 0' ERR` — a SessionStart hook must never block session start |

**Ordering constraint inside `hooks.SessionStart[0].hooks[]`:** the arm hook must run **after** `leadv2-orphan-monitor-sweep.sh` (`hooks.json` position 5). That sweep SIGKILLs monitor pgroups at session start; ordering the arm after it removes any chance of a race where a freshly-suggested watcher is described before the sweep runs. (The sweep does not match this command — §0 — so this is defence in depth, not a dependency.)

---

## 3. CONFIGURATION BOUNDARIES

Every input the mechanism reads, at five boundary values each.

### 3.1 `founder-status.md` (the watched file)

Resolution: `${LEADV2_FOUNDER_STATUS_PATH:-${PROJECT_ROOT}/docs/leadv2/founder-status.md}`, `PROJECT_ROOT = ${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(git -C "$PWD" rev-parse --show-toplevel)}}`.

| Boundary | Behaviour |
|---|---|
| absent | loop runs, emits nothing, does not exit, does not error (§2.2) |
| empty file (0 bytes) | mtime still changes on rewrite ⇒ fallback synthetic line emitted, not a blank event |
| minimum (1 line, 1 char) | that char is the event |
| maximum / over-cap (file is MBs) | **`head -n 1` only** — never `cat`, never `wc -l`, never a hash of the body. The watcher's per-beat cost is bounded by line 1's length regardless of file size. An over-cap founder-status.md must not be able to flood the conversation; this is the concrete instance of "an over-cap input that takes down more than the one operation it belongs to is a defect". |
| malformed (binary, no trailing newline, embedded NULs) | `head -n 1` may return NUL bytes. **Sanitize before emit:** `tr -d '\000' | cut -c1-500`. A 500-char cap on the emitted line bounds a single beat's conversation cost. No trailing newline is fine — `head -n1` still yields the content. |
| unreadable (mode 000) | stat may succeed while `head` fails ⇒ emit the synthetic fallback line, keep running |

### 3.2 `LEADV2_PULSE_WATCH_INTERVAL_S` (poll interval, default 60)

| Boundary | Behaviour |
|---|---|
| absent | 60 |
| empty | 60 |
| minimum | values `<5` clamp to 5. A 0 or 1 would busy-spin `stat` and (worse) shorten the window in which two rapid composer writes collapse into one event. |
| maximum / over-cap | clamp to 3600. An hour-long poll on a 30-min beat guarantees missed beats but must not be rejected outright — clamp, do not fail. |
| malformed (`abc`, `-5`, `1e3`) | regex `^[0-9]+$` fails ⇒ 60, and one stderr note. Never `sleep abc` (rc≠0 in a `set -e` script ⇒ silent loop death ⇒ silence). |

### 3.3 `LEADV2_PULSE_WATCH` (kill switch, default 1)

| Boundary | Behaviour |
|---|---|
| absent / empty / anything not `0` | enabled |
| `0` | `--print` silent, `--emit-loop` immediate rc 0, arm hook silent |

Deliberately a `== "0"` test, mirroring `LEADV2_SINGLE_LEAD_BEAT` at `leadv2-pulse-beat.sh:29`. Not a truthiness test — `LEADV2_PULSE_WATCH=false` leaves it **on**, consistent with every other switch in this plugin.

### 3.4 `LEADV2_FOUNDER_STATUS_PATH`

| Boundary | Behaviour |
|---|---|
| absent | `$PROJECT_ROOT/docs/leadv2/founder-status.md` |
| empty | treat as absent (`:-` handles this) |
| relative path | used as-is relative to the watcher's cwd. Documented hazard; the two existing consumers have the same property, so no new divergence is introduced. |
| points at a directory | `stat` succeeds, `head` fails ⇒ synthetic fallback line on every directory-mtime change. Acceptable; misconfiguration is loud, not silent. |
| malformed (contains newline / shell metachars) | the path is only ever used **quoted** inside the script. It is *not* interpolated into the printed `--print` command — `--print` emits a fixed `<abs-script> --emit-loop` string with no user-controlled bytes. This is the injection boundary and it is closed by construction. |

### 3.5 `CLAUDE_PLUGIN_ROOT` / `BASH_SOURCE` (script self-location, for `--print`)

| Boundary | Behaviour |
|---|---|
| `CLAUDE_PLUGIN_ROOT` set and `$CLAUDE_PLUGIN_ROOT/scripts/leadv2-pulse-watch.sh` exists | use it (stable across worktrees; this is the canonical plugin path) |
| unset | `cd "$(dirname "${BASH_SOURCE[0]}")" && pwd` |
| resolves under `*/.claude/worktrees/*` | **refuse and fall back** to `CLAUDE_PLUGIN_ROOT`, else print nothing. A watcher command pointing into a lane worktree dies when that worktree is swept — a self-inflicted silence bug with a 48h fuse (`LEADV2_SWEEP_MIN_AGE_H`, per `single-lead-pulse.md:64-79`). |
| path contains spaces | printed command must quote the path. `--print` output is a single line consumed verbatim by `Monitor(command=…)`. |

### 3.6 `hooks.json` SessionStart array

| Boundary | Behaviour |
|---|---|
| entry absent | no directive; today's behaviour (relay only when the founder types) |
| entry present, script missing on disk | Claude Code reports a hook failure at session start; other SessionStart hooks still run. Mitigation: the script ships in the same commit as the `hooks.json` edit. |
| plugin **cache** not refreshed | **The hook does not run at all.** Per `~/.claude/CLAUDE.md` §Shared trees: `claude plugin update` no-ops for directory-source marketplaces when content changed but the version did not. A hook fix must be copied into the plugin cache and the session restarted. This is a release-step requirement, not a code requirement, and it must appear in the doc. |

---

## 4. COUNTEREXAMPLE

**After every deliverable in this mission is built and every finding fixed, what can STILL produce long founder-visible silence?**

Four things, in descending likelihood — and the first is not a corner case, it is the default.

**(a) The Monitor's own lifetime.** The `Monitor` tool's `timeout_ms` defaults to **300000 ms (5 minutes)** and its documented maximum is **3600000 ms (1 hour)**; only `persistent: true` runs "for the lifetime of the session (no timeout)". A watcher armed with default arguments therefore dies **five minutes** into a thirty-minute cadence and the founder sees exactly the silence this lane exists to eliminate — with the added hazard that the lead believes the watcher is armed. **Therefore `persistent: true` is not a suggestion in the injected directive; it is part of the mechanism, and the arm hook must emit the full call with `persistent=true` spelled out rather than a bare command string.** Even then, "lifetime of the session" is the ceiling: a lead session that is killed, compacted into a new process, or `/clear`-ed loses the watcher. The SessionStart hook re-arms on the next session start, so the residual gap is [session death → next session start], which is bounded only by when the founder next opens a session. This is the honest limit of an in-session Monitor and it is the direct cost of deliverable 5's "do NOT build a daemon". It should be written into the doc as the contract's stated boundary, not hidden.

**(b) The beat never composes, so mtime never changes.** The watcher is downstream of `leadv2-pulse-beat.sh --check`, which is triggered only from `hooks/leadv2-single-lead-beat.sh:175-179` — i.e. from `UserPromptSubmit`/`PostToolUse`. **An idle session fires no tool calls, so nothing triggers the composer, so `founder-status.md` is never rewritten, so its mtime never changes, so the watcher correctly emits nothing.** The watcher fixes "a composed beat rots undelivered". It does **not** fix "no beat is composed while idle". If the founder's complaint («никогда долгого молчания») includes a session that is idle because the lead is blocked waiting on a lane, this design does not close it — the watcher would need to trigger the composer itself, which is a scope decision outside this prepass. **This is the single largest residual gap and it must be surfaced to the founder rather than absorbed.** (A minimal in-scope mitigation exists: have `--emit-loop` invoke `leadv2-pulse-beat.sh --check` once per iteration, which is throttled and background-safe by construction. Recommended as a follow-up decision, not silently added — deliverable 5 says "keep the diff minimal".)

**(c) Owner/guest role flip.** `leadv2-single-lead-beat.sh:128` resolves `owner` vs `guest` via `leadv2_beat_role()`, and a `guest` gets `RELAY=none` — one line, no status body. If two lead sessions are open and the founder is reading the guest, the watcher wakes it and it relays a pointer, not the status. Not silence, but not the status either. Unchanged by this lane, correctly so.

**(d) Body-hash dedupe.** `leadv2-single-lead-beat.sh:143-146` suppresses the relay when `tail -n +2 founder-status.md` hashes identically to the last delivered body. A beat that rewrites only the line-1 timestamp wakes the watcher (mtime changed) but produces **no** RELAY injection. The turn is still created — so the founder is not in silence — but the visible artifact is a bare wake line. Correct behaviour (nothing changed), worth documenting so it does not get filed as a bug.

**What I checked and found clean:** the orphan-monitor sweep does not match this command (§0); the Monitor cap gate does not deny (§0); `founder-status.md` is not in the state-path `STANDARD` set, so no symlink/migration race (§0/M2); no existing test asserts on SessionStart hook output for this array, so the `hooks.json` edit breaks no suite.

---

## 5. FILE-BY-FILE PLAN

### 5.1 `plugins/leadv2/scripts/leadv2-pulse-watch.sh` — NEW

- `#!/usr/bin/env bash`, `set -uo pipefail` (**not** `-e`: a failing `stat` inside the loop must not kill the watcher), no `trap ... ERR` that exits during `--emit-loop`.
- bash 3.2 only: no `mapfile`, no associative arrays, no `${var,,}`.
- Modes: `--print` (default, no args), `--emit-loop`, `--max-iters N`, `--help`.
- `--print` emits exactly one line and nothing else. It must **not** contain `codex-task.sh status` (§0).
- Loop: first iteration records mtime and sets `armed=1` without emitting, whatever the file's state.
- Emit path: `head -n 1 "$F" | tr -d '\000' | cut -c1-500`; empty → synthetic fallback line.
- All comparisons `[ ]`, quoted expansions everywhere.

### 5.2 `plugins/leadv2/hooks/leadv2-pulse-watch-arm.sh` — NEW

- `set -uo pipefail`, `trap 'exit 0' ERR`, exit 0 on every path.
- Gate order: kill switches → `agent_type` → worktree cwd → supervisor session → `docs/leadv2` exists → `--print` non-empty.
- Directive text (single line in `additionalContext`), naming `persistent=true` explicitly:
  `PULSE-WAKE: arm the beat watcher NOW: Monitor(command="<cmd>", description="founder pulse beat", persistent=true, timeout_ms=3600000). A lead session with no beat watcher armed is in violation — the 30-min founder status will not reach chat until the founder types. On a beat event, relay per the existing RELAY=full/none rules; do not compose a status yourself.`

### 5.3 `plugins/leadv2/hooks/hooks.json` — EDIT

One object appended to `hooks.SessionStart[0].hooks[]` between the entries currently at `:69` and `:76`:
`{"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-pulse-watch-arm.sh\"","timeout":5,"continueOnBlock":true,"statusMessage":"Arming founder pulse watcher..."}`

### 5.4 `plugins/leadv2/docs/single-lead-pulse.md` — EDIT

- Rewrite §"Why hook-clock, not a daemon or `CronCreate`" (`:24-33`) → §"Why an in-session Monitor, not a daemon or `CronCreate`". State the superseded position and why (founder order 2026-08-24), keep the `CronCreate` ban, answer the rule-5 cost objection: one watcher, one filter, one line per beat, `persistent=true`, armed exactly once per lead session and never in a worker.
- Rewrite §"Consequence" (`:32-33`) — "an idle session produces no beat, and that's correct" is no longer the accepted contract for delivery; it remains true for *composition* (§4b). Say both, separately.
- Add §"The armed-watcher contract": the lead arms at session start; a session without it armed is in violation; beat → relay per RELAY=full/none.
- Add §"Known limits" — §4(a) session-lifetime ceiling and §4(b) idle-composition gap, verbatim.
- Extend §Files, §Env (`LEADV2_PULSE_WATCH`, `LEADV2_PULSE_WATCH_INTERVAL_S`), §Test.
- Add the plugin-cache release note (§3.6).

### 5.5 `plugins/leadv2/scripts/tests/test-pulse-watch.sh` — NEW

Hermetic, modelled on `test-single-lead-beat.sh:29-56` (`lv2_mktemp_dir`, `lv2_assert_scratch_repo`, `LEADV2_PROJECT_ROOT`/`LEADV2_STATE_ROOT` sandbox, `PASS/FAIL/ERRORS` counters, `rm -rf "$TMP"`, non-zero exit on failure).

| # | Case | Assert |
|---|---|---|
| T1 | fixture exists, `--emit-loop --max-iters 2`, no touch | zero stdout lines |
| T2 | fixture exists, touch between iterations | exactly one line, equal to line 1 of the fixture |
| T3 | first observation | line 1 of a pre-existing file is never emitted on iteration 1 |
| T4 | fixture absent at arm, created during the run | one line (creation is a beat) |
| T5 | line 1 empty | one line, non-blank, containing `[BROAD_STATUS]` |
| T6 | `LEADV2_PULSE_WATCH=0` | `--print` empty; `--emit-loop` rc 0, no output |
| T7 | `--print` | exactly one line, ends `--emit-loop`, does not contain `codex-task.sh` |
| T8 | arm hook, lead payload | stdout parses as JSON with `hookSpecificOutput.additionalContext` containing `PULSE-WAKE` and `persistent` |
| T9 | arm hook, `{"agent_type":"developer",...}` | empty stdout |
| T10 | arm hook, cwd under `.claude/worktrees/` | empty stdout |
| T11 | malformed `LEADV2_PULSE_WATCH_INTERVAL_S=abc` | does not hang, does not error, uses default |
| T12 | `bash -n` on both new files | rc 0 |

`test-single-lead-beat.sh` is **not** modified (its 4 cases are unaffected); it is re-run as a regression check.

---

## 6. NON-GOALS (explicit — implementer must not do these)

1. No daemon, no `cron`, no `CronCreate`, no `launchd`. (Mission deliverable 5.)
2. No edit to `leadv2-broad-status.sh`, `leadv2-pulse-beat.sh`, or `hooks/leadv2-single-lead-beat.sh`.
3. No change to the RELAY=full/none semantics or to `leadv2-beat-owner.sh` role resolution.
4. No de-duplication of the two copies of the RELAY prose (`leadv2-single-lead-beat.sh:156-158` vs `leadv2-task-anchor.sh:228-233`/`:883-888`) — noted in §1.2, deferred.
5. No addition of `founder-status.md` to the `leadv2-state-path.sh` `STANDARD` set.
6. No change to `leadv2-orphan-monitor-sweep.sh` or `leadv2-monitor-cap-gate.sh`.
7. Not fixing §4(b) — the watcher does not trigger the composer in this lane. Flag to founder; do not implement unilaterally.
8. No new file under `docs/leadv2/` or `docs/handoff/`.

## 7. Mandatory constraint checklist

1. **Env naming** — `LEADV2_PULSE_WATCH`, `LEADV2_PULSE_WATCH_INTERVAL_S`; reuses existing `LEADV2_FOUNDER_STATUS_PATH`, `LEADV2_PROJECT_ROOT`, `LEADV2_SINGLE_LEAD_BEAT`. `LEADV2_*` throughout, no `LEAD_V2_*`. ✅
2. **Paths** — every path in §5 verified on disk or marked NEW. `docs/single-lead-pulse.md` proved absent (§0/M1). ✅
3. **`claude -p`** — this design introduces no `claude -p` invocation. N/A. ✅
4. **Concurrent access** — `founder-status.md` is written by `leadv2-broad-status.sh` and read by the watcher. The watcher takes **no lock**: it only `stat`s and `head`s. A torn read during a composer write yields a partial line 1 — a cosmetic wake line, and the RELAY that follows re-reads the settled file. Recommendation: no lock (a lock here could block the composer, which is strictly worse than a cosmetic line). Second race: N sessions each arming a watcher → N notifications per beat; closed by the worktree/`agent_type` gates (§2.3). ✅
5. **Config contradiction** — `LEADV2_FOUNDER_STATUS_PATH` grepped repo-wide: 3 usages (`leadv2-broad-status.sh:36`, `leadv2-single-lead-beat.sh:132`, `test-broad-status-duty.sh:337`), all identical `${VAR:-$PROJECT_ROOT/docs/leadv2/founder-status.md}` semantics. The watcher adds a 4th with the same semantics. No contradiction. The one contradiction found is documentary, not config: `single-lead-pulse.md:24-33` argues against this lane's mechanism — resolved in §5.4. ✅

## 8. Acceptance

```
acceptance:
  - surface: rendered_line
    observable: >-
      In a fresh lead session where the founder types nothing after the first
      turn, the founder-status text appears in the chat within roughly a minute
      of the plugin rewriting it, and keeps appearing on each later rewrite for
      as long as the session stays open.
    authored_at: 2026-08-24T17:05:00Z
  - surface: rendered_line
    observable: >-
      At the very start of a lead session the founder sees a one-line
      instruction telling the lead to arm the beat watcher, naming the watcher
      command and stating that the watcher must be persistent.
    authored_at: 2026-08-24T17:05:00Z
  - surface: rendered_line
    observable: >-
      Opening a session inside a lane worktree, or a subagent session, shows no
      such instruction — only the main lead session is told to arm it.
    authored_at: 2026-08-24T17:05:00Z
  - surface: file_artifact
    observable: >-
      The single-lead pulse document no longer tells the reader that a
      lead-side watcher is a token-discipline violation; it states instead that
      a lead session with no watcher armed is the violation, and lists the two
      situations in which the founder can still go quiet.
    authored_at: 2026-08-24T17:05:00Z
  - surface: log_line
    observable: >-
      The watcher, left running with the status file untouched, produces no
      chat notifications at all — arming it is silent until something actually
      changes.
    authored_at: 2026-08-24T17:05:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-pulse-watch.sh, plugins/leadv2/hooks/leadv2-pulse-watch-arm.sh, plugins/leadv2/hooks/hooks.json, plugins/leadv2/docs/single-lead-pulse.md, plugins/leadv2/scripts/tests/test-pulse-watch.sh

DELIVERABLE_COMPLETE
