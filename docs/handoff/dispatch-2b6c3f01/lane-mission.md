Product implementation task dispatch-2b6c3f01. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# Architect prepass — PULSE-IS-A-PLUGIN-DUTY-01

Repo: `/Users/kostiantyn.vlasenko/Projects/leadv2` (plugin source of truth).
Role: design only. No implementation in this pass.

## 1. What is actually on disk today (verified, not assumed)

The founder's framing is "the pulse is a session cron". The code says something
more precise and more fixable: **the pulse is already plugin-owned; its
*delivery* is not.**

| Component | Path | State |
|---|---|---|
| 30-min beat scheduler | `plugins/leadv2/scripts/leadv2-supervise-loop.sh:95,814-822` | EXISTS. `BROAD_STATUS_S="${LEADV2_SUPERVISE_BROAD_STATUS_S:-1800}"`, fires `leadv2-broad-status.sh` every 1800s. |
| Content contract (table + prose) | `plugins/leadv2/scripts/leadv2-broad-status.sh` | EXISTS. Table rendered deterministically in python3; Haiku composes only the prose tail. |
| Durable artifact | `docs/leadv2/founder-status.md` (`LEADV2_FOUNDER_STATUS_PATH`) | EXISTS, written tmp+`mv` atomically at `leadv2-broad-status.sh:284`. |
| Log copy | `<control-plane>/supervise-loop.log` | EXISTS, append-only, block delimited `[BROAD_STATUS] … [BROAD_STATUS_END]`. |
| Ban on `CronCreate` | `plugins/leadv2/skills/leadv2-supervise/SKILL.md:136-143` | EXISTS as prose: "never spins up a `CronCreate` job… the cadence is a plugin-owned loop beat". |
| Survival mechanism | crontab `*/10` → `leadv2-supervise-watchdog.sh` → `--ensure` (`leadv2-supervise-loop.sh:152-182`) | EXISTS, idempotent, marker-tagged, lock-guarded. |

### The defect

`leadv2-broad-status.sh` contains **zero** occurrences of `URGENT` (verified by
grep). The founder-mandated attach pattern is

```
Monitor(command="tail -F -n0 '<supervise-loop.log>' | grep --line-buffered URGENT")
```

(`skills/leadv2-supervise/SKILL.md:110-131`, `docs/supervisor-role.md:30-33`).
`grep URGENT` therefore **filters the BROAD_STATUS block out**. The beat is
composed, timestamped, written to two files — and no live session is ever woken
by it. A lead that is silently mid-phase never learns a beat exists.

That is the complete causal chain for "every session re-invents a `CronCreate`":
the plugin-owned beat is real but undeliverable, so the model reaches for the
only wake primitive it has. **The fix is a delivery/wake contract, not a new
scheduler.** Building a second scheduler would be the wrong repair.

Two secondary gaps, both real:

- **PULSE MODE contradiction.** `hooks/leadv2-task-anchor.sh:221,697` and
  `commands/leadv2.md:231` enumerate the allowed chat outputs (Gate-1, async
  question, Phase-8 close) and do **not** list the status beat. The pulse duty
  is documented only on supervisor-mode surfaces. Two rules, resolved by
  whoever read last — exactly as the mission states.
- **"Dispatch before report" is unwritten.** `leadv2-supervise-loop.sh:377,404`
  runs the backlog pump every cycle, but nothing *orders* the pump before the
  beat, and no beat records what it dispatched. The rule exists in the founder's
  head, not in the plugin.

## 2. Design

Four changes. Ordered by dependency; each is independently revertable.

### C1 — Delivery: one URGENT-tagged ready-line per beat (the crux)

After `leadv2-broad-status.sh` writes the block and `founder-status.md`, append
**one additional line** to the loop log:

```
<iso> [SUPERVISE-URGENT] BROAD_STATUS_READY at=<iso> path=docs/leadv2/founder-status.md rows=<n> dispatched=<n>
```

Properties, all deliberate:

- It passes the existing `grep --line-buffered URGENT` filter → the attached
  lead wakes. No Monitor change, no new attach pattern to teach.
- It is **one line per 30 min**, not per lane. Token cost: 1 wake/beat, which is
  strictly cheaper than the `CronCreate` job it replaces (that job burned a full
  turn plus a composition).
- It is a **pointer, not the payload.** The lead reads `founder-status.md` and
  pastes it. Emitting the whole table through the Monitor would multiply the
  wake by the block's line count.
- It goes through the existing alarm-dedupe lib (`lib/leadv2-alarm-dedupe.sh`,
  key `broad_status_ready`, value = the beat's ISO timestamp) so a re-read or a
  double-`--ensure` cannot fire it twice for the same beat.
- On a beat that fails to render, emit `BROAD_STATUS_READY … degraded=1` rather
  than staying silent — a missing status must be visible, not inferred.

### C2 — Ordering: dispatch before report

In `leadv2-supervise-loop.sh`, the beat branch (`:814`) must, before invoking
`leadv2-broad-status.sh`:

1. call the backlog pump (`PUMP_SH`) and capture its dispatched count;
2. export it as `LEADV2_BROAD_STATUS_DISPATCHED=<n>` for the beat;
3. only then compose.

`leadv2-broad-status.sh` stamps `dispatched=<n>` into the ready-line (C1) and
one line into the block header. If the pump is unavailable, stamp
`dispatched=unavailable` — never `0`, which would be a fabricated fact.

This makes "a pulse dispatches before it reports" a code-enforced order rather
than an instruction, and it makes the claim auditable after the fact.

### C3 — Reconciliation: the pulse is a scheduled duty, not narration

Amend the four surfaces that state PULSE MODE so the beat stops being an
exception:

- `hooks/leadv2-task-anchor.sh` (both DIRECTIVE blocks, `:221` and `:697`) —
  rule 3 gains a fourth allowed output, phrased as a *duty with its own output
  contract*: "a `[BROAD_STATUS]` relay when the plugin emits
  `BROAD_STATUS_READY` (paste `founder-status.md` verbatim; never compose one)".
- `commands/leadv2.md:231` — same amendment, same wording.
- `hooks/leadv2-supervisor-mode-reinject.sh:137-140` — replace "you surface only
  what needs the founder" for the beat with the explicit relay trigger.
- `docs/supervisor-role.md` §"Speak only when it changes the founder's work" and
  §"Status reporting standard" — record that the beat is delivered by the
  ready-line and that hand-composing or `CronCreate`-ing a status is banned.

Wording rule for all four: **narration is model-generated prose about its own
work; the pulse is a verbatim relay of a plugin-generated artifact.** That
distinction is what dissolves the contradiction — the ban on the former never
touched the latter, but nothing said so.

### C4 — The `CronCreate` ban, stated where the lead reads it

The ban currently lives only in `skills/leadv2-supervise/SKILL.md`, which a
non-supervisor lead never loads. Move the sentence into C3's surfaces (anchor
hook + `commands/leadv2.md`), which every session sees on every prompt.

**Rejected alternative:** a `PreToolUse` hook denying `CronCreate` when the
prompt looks status-shaped. Rejected for two reasons: (a) a new hook requires a
`hooks.json` entry *plus* a copy into the plugin **cache** and a session restart
— `claude plugin update` no-ops for directory-source marketplaces when content
changed but the version did not, so a hook fix that isn't cache-copied never
loads (known trap, global CLAUDE.md); (b) `CronCreate` has legitimate uses and a
prompt-shape matcher will produce false denials. Text in a hook that already
fires on every prompt gets the same coverage at none of the cost.

## 3. Survival — stated honestly, per failure mode

The pulse's *scheduler* is the supervise loop. `--ensure` **becomes** the loop
in-process (`leadv2-supervise-loop.sh:329`, no fork/`setsid`/`nohup`), so when a
session attaches it via `Monitor`, the loop is a child of that session and dies
with it. Resurrection is entirely the crontab watchdog's job.

| Failure mode | Survives? | Mechanism / why not |
|---|---|---|
| `/compact` | **Yes** | Loop is a separate OS process; compaction touches only the model's context. The anchor-hook text (C3) is re-injected on the next prompt. |
| Lead session ends / terminal killed | **Yes, with a ≤10 min gap** | Loop dies with its parent Monitor; the `*/10` crontab watchdog detects a stale heartbeat and runs `--ensure`, which starts a loop as a **cron child** — detached, session-independent from then on. |
| Loop crash / hang | **Yes, ≤10 min** | Watchdog fires on `now - mtime(heartbeat) > 2×PULSE_S` or dead pid, logs `LOOP_SILENT`, then `--ensure`. |
| Machine reboot | **Yes, ≤10 min after cron starts** | crontab persists across reboot; first `*/10` tick re-ensures. Not demonstrated in this design's test — do not claim it as verified. |
| `crontab` unavailable / `LEADV2_SUPERVISE_BEAT_CRON=0` | **No** | `_install_beat_cron` returns 0 silently when `command -v crontab` fails. Residual gap; C1 should log one line when the install is skipped so the gap is visible instead of silent. |
| No session open at all | **No, by design** | The artifact keeps accruing to `founder-status.md`; chat delivery waits for the next session. The mission explicitly rules out a session-less daemon, and it is right to: with no session there are no lanes to report on. |

**Do not claim** "the pulse now survives anything". It survives a compact and a
session restart. It does not survive a host without cron, and it does not
deliver into a chat that does not exist.

## 4. Test — the transition it exists to survive

`plugins/leadv2/scripts/tests/test-broad-status-duty.sh`, hermetic
(`LEADV2_PROJECT_ROOT` = temp dir, `CRONTAB_BIN` = a stub that never touches the
real crontab, `LEADV2_BROAD_STATUS_CLAUDE_BIN` = a stub echoing fixed JSON so no
model is called, `LEADV2_SUPERVISE_BROAD_STATUS_S` = small).

1. **Ready-line is emitted and passes the real filter.** Run one beat; assert
   `founder-status.md` exists, and that
   `grep 'URGENT' supervise-loop.log | grep BROAD_STATUS_READY` returns exactly
   one line. This is the regression guard for the actual defect.
2. **Dedupe.** Re-run the same beat timestamp; assert still exactly one line.
3. **Ordering.** Stub pump increments a counter file; assert the counter was
   written **before** `founder-status.md`'s mtime and that the ready-line's
   `dispatched=` matches the stub.
4. **Session-death survival (the demonstration).** Start a loop, record its pid,
   `kill` it (simulating the session ending), age the heartbeat past
   `2×PULSE_S`, run `leadv2-supervise-watchdog.sh --project-root <tmp>`; assert
   a `LOOP_SILENT` line, a **new** live pid ≠ the old one, and a fresh beat
   afterwards. This is a run, not a claim.
5. **Degraded beat is visible.** Point the collector at a nonexistent binary;
   assert a `BROAD_STATUS_READY … degraded=1` line still appears.

Non-goal for the test: real crontab, real reboot, real `claude` invocation.

## 5. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | Ready-line becomes a per-lane wake storm if someone later "enriches" it. | Test 1 asserts **exactly one** line per beat; comment the invariant at the emit site. |
| R2 | Alarm-dedupe lib absent → pass-through fallback fires the line every poll. | The beat branch runs once per 1800s, not per poll, so pass-through still yields one line/beat. Verify in test 2 with the lib force-disabled. |
| R3 | Two loops (session-owned + cron-owned) both beat → duplicate statuses. | Existing single-owner sentinel + `FOREIGN` branch already prevent this; do not weaken it. Add an assertion, not a new lock. |
| R4 | C3 wording drifts between the four surfaces; the contradiction returns in a new shape. | Use one verbatim sentence in all four; grep for it in the test (cheap, catches drift). |
| R5 | `founder-status.md` read by the lead while being replaced. | Already tmp+`mv` (atomic rename); no change needed. Do **not** convert to in-place append. |
| R6 | Editing `hooks/leadv2-task-anchor.sh` changes text embedded in a materialized-core hook. | This is a text change in a plugin-source hook, not the cached hook body; if the anchor hook is cache-materialized, the implementer must copy to the cache and restart, per the known trap. Verify before claiming the DIRECTIVE changed. |
| R7 | `LEADV2_LEAD_GUARD=1` blocks `Edit` on canonical plugin `.sh`. | Known; fix-forward via the `/tmp` python patcher + `Bash`, per prior art. |

## 6. Constraint checklist

1. **Env naming** — all touched vars are `LEADV2_*`
   (`LEADV2_SUPERVISE_BROAD_STATUS_S`, `LEADV2_FOUNDER_STATUS_PATH`,
   `LEADV2_SUPERVISE_BEAT_CRON`, new `LEADV2_BROAD_STATUS_DISPATCHED`). No
   `LEAD_V2_*` drift introduced. PASS.
2. **Paths** — every path in §2 verified present on disk; only
   `scripts/tests/test-broad-status-duty.sh` is `(to-create)`. PASS.
3. **`claude -p` flags** — the only invocation
   (`leadv2-broad-status.sh:260`) already carries `--max-turns 1
   --permission-mode bypassPermissions --output-format json`. PASS, no change.
4. **Concurrent access** — `founder-status.md` tmp+`mv`; `supervise-loop.log`
   append-only; crontab rewrite under `fcntl` lock. Loop-vs-cron duplication
   covered by the ownership sentinel (R3). PASS.
5. **Config contradiction** — `LEADV2_SUPERVISE_BROAD_STATUS_S=0` remains the
   documented rollback and must keep disabling the ready-line too (else the
   kill-switch half-works). Called out as an explicit implementation
   requirement.

## 7. Out of scope (implementer: ignore)

- Changing what a pulse **says** — table columns, the 3-line prose cap, the
  Haiku composer split. Founder-settled.
- Any session-less daemon.
- A new `PreToolUse` hook (see C4 rejection).
- `docs/leadv2/open-threads.md` — untouched, per hard constraint.
- Refactoring `leadv2-supervise-loop.sh` ownership/sentinel logic.

## 8. Acceptance

```
acceptance:
  - surface: file_artifact
    observable: >
      The founder opens docs/leadv2/founder-status.md after killing the terminal
      that started supervision, and sees a status block whose header timestamp is
      within the last 30 minutes — a block written by a loop the dead session did
      not start.
    authored_at: 2026-08-16T18:04:37Z
  - surface: log_line
    observable: >
      In the supervise loop log, exactly one line per beat reads
      "[SUPERVISE-URGENT] BROAD_STATUS_READY at=… path=docs/leadv2/founder-status.md
      dispatched=…" — a line the founder's URGENT-filtered watcher visibly wakes on,
      where before nothing appeared at all.
    authored_at: 2026-08-16T18:04:37Z
  - surface: rendered_line
    observable: >
      A lead session's on-screen anchor block lists the status relay as an allowed
      output alongside Gate-1, async question, and Phase-8 close — so the founder
      reading it no longer sees a silence rule that forbids the pulse.
    authored_at: 2026-08-16T18:04:37Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh, plugins/leadv2/scripts/leadv2-supervise-loop.sh, plugins/leadv2/scripts/tests/test-broad-status-duty.sh, plugins/leadv2/hooks/leadv2-task-anchor.sh, plugins/leadv2/hooks/leadv2-supervisor-mode-reinject.sh, plugins/leadv2/commands/leadv2.md, plugins/leadv2/docs/supervisor-role.md, plugins/leadv2/skills/leadv2-supervise/SKILL.md

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# MISSION — PULSE-IS-A-PLUGIN-DUTY-01: the pulse must belong to the plugin, not to a session cron

Plugin repo: `/Users/kostiantyn.vlasenko/Projects/leadv2`. This is track 5.6–5.8, founder-raised and
never advanced.

Today the founder's 30-minute status pulse exists as a **session cron job**: created inside one
`/leadv2` session, held in that session's memory, and **gone the moment the session ends**. Every
session therefore re-invents it, and a session that forgets goes silent without anyone noticing —
the founder finds out from the absence of messages, which is the worst possible detector.

It is also an exception to PULSE MODE: the lead is told to stay silent between phases, and separately
told to emit a pulse. Two rules that contradict each other get resolved by whoever reads them last.

## What to build

Make the pulse a **duty of the plugin**, so it exists because `/leadv2` is running, not because some
session remembered to schedule it:

1. **Ownership** — the cadence, the content contract (one lane table + at most 3 lines), and the rule
   that a pulse *dispatches before it reports* live in the plugin, in one place.
2. **Survival** — it must survive a compact and a session restart. State plainly which failure modes
   it now survives and which it does not (a killed terminal? a reboot?). Never claim survival you
   have not demonstrated.
3. **Reconciliation with PULSE MODE** — express the pulse as a scheduled duty with its own output
   contract, distinct from the narration ban, so it stops being an exception.

## Deliberately not in scope
- Do not change what a pulse *says* — the table shape and the 3-line limit are the founder's and are
  settled.
- Do not build a daemon that runs with no session open: the pulse reports on lanes, and with no
  session there are no lanes. If the requirement implies one, say so rather than building it.

## How to prove it

A test that the duty survives the transition it exists to survive, plus a demonstration you actually
ran — not "this should now persist". If a session-scoped mechanism genuinely cannot survive a session
ending, deliver the smallest design that gets closest and state the residual gap plainly.

## Hard constraints
- Never `reset --hard`, `clean`, or `stash` — three live repos share this tree.
- Do not touch `docs/leadv2/open-threads.md`.
- Re-`git diff` immediately before you `git add`.

## Deliverable
The implementation, its test, and `docs/handoff/PULSE-IS-A-PLUGIN-DUTY-01/report.md` naming which
failure modes are covered and which remain. End with DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-2b6c3f01" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.