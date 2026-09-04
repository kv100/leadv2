# V3-WORKER-MESSAGING-01 — architect prepass (design-spec lane)

Scope of THIS lane: author one document, `docs/specs/worker-messaging-v3.md`.
No code. The build lane implements from that document.

---

## 0. Discovery notes (what exists on disk today)

Verified in `~/Projects/leadv2` @ `main` (4f9d4b8) by direct probe:

| Fact | Probe |
|---|---|
| Beat/pulse driver | `plugins/leadv2/scripts/leadv2-pulse-beat.sh` — "dispatch, then compose", kill-switch `LEADV2_SINGLE_LEAD_BEAT=0` |
| Status composer | `leadv2-broad-status.sh` — deterministic python3 table + haiku prose tail |
| Renderer | `leadv2-status-render.sh` — "render the last collected snapshot. NO probes"; pairs with `leadv2-status-collector.sh` (poll model → D4) |
| Beat ownership | `leadv2-beat-owner.sh` → `owner|guest|unresolved`, fail-open |
| Liveness | `leadv2-lane-heartbeat.sh` — durable heartbeat in `docs/leadv2/active.yaml` via `leadv2-active-registry.sh` |
| Journal | `leadv2-journal.sh append|tail <task-id> <type>` → `docs/leadv2/tasks/<task-id>/journal.md`, "single-writer, plain-append, no locking" |
| Existing event vocabulary | grep over `plugins/leadv2/scripts/*.sh`: `worker_spawned` (16), `review_gate` (37), `lane_terminal` (13), `dispatch_terminal*`, `e2e_gate` (10) |
| worker_timeout today | `leadv2-dispatch-product-close.sh:1751,1773` — writes `review-gate.md status: blocked reason: worker_timeout`, `terminal=dead cause=timeout`. One wall-clock number, no distinction between "suite running" and "idle wait" (D2 root cause) |

**Missing input — BLOCKING for the build lane, not for this prepass.**
`docs/handoff/CC-RELEASE-AUDIT-230-236.md` does **not exist** in this repo:
`find . -iname "*RELEASE-AUDIT*"` → no matches; `ls docs/handoff/*b9b04206*` → no matches
(no `context.yaml` for this dispatch either). Consequence: every capability claim about
Claude Code 2.1.224/2.1.232/2.1.234/2.1.236 is currently unsourced.

UNVERIFIED: cross-session `SendMessage`/`ListAgents` reaching headless workers (2.1.224+),
`notify_when_idle` (2.1.236), `fork` subagent type (2.1.232), teammate-inherits-lead-model
(2.1.234). No probe artifact available in this subsession (no MCP, file absent).
→ Design rule below (D-1) makes the whole design tolerate these being false.

---

## 1. Design decisions the spec must encode

**D-1 — journal-first, SendMessage-as-accelerator.** The event bus of record is an
append-only file (`docs/leadv2/tasks/<task-id>/events.jsonl`, one JSON object per line).
`SendMessage` is a *latency optimisation* layered on top, never the only copy of an event.
Rationale: the CC capability set is unverified (§0), headless workers are a separate
process tree, and a message lost on a dead session is unrecoverable while a line on disk
is not. This is the same "context is cache, disk is truth" rule `leadv2-journal.sh` already
states in its header.

**D-2 — one emitter, one consumer.** Workers never write status files; they call one
emitter script. The lead never polls; it runs one subscriber. Everything else (renderer,
pulse, watchdog) reads the subscriber's derived state, not the raw sources. This is what
kills D4: `leadv2-status-render.sh` stops reading collector snapshots + stem files and
reads the derived lane-state table instead.

**D-3 — a wait is a subscription, never a promise.** D2's four deaths came from a worker
that backgrounded a suite, armed a Monitor, then idled. The spec must define the inverse:
a worker that must wait emits `suite_started` with an expected-duration hint and a
liveness contract; the *lead* owns the wait. A worker with nothing to do is a worker that
should terminate.

**D-4 — new event file, existing vocabulary.** Reuse the already-emitted names
(`worker_spawned`, `lane_terminal`, `dispatch_terminal`, `review_gate`, `e2e_gate`) as the
`event` values where they already exist; do not rename them. `journal.md` stays as-is
(human trace); `events.jsonl` is the machine stream. Additive only — nothing that reads
`journal.md` today changes.

**D-5 — every event is idempotent and monotonic.** `(task_id, seq)` primary key, `seq`
strictly increasing per task, writer uses `>>` with a single `printf` of one line < 4KB
(POSIX atomic-append territory) — no lock. Duplicate delivery is expected (file + message);
the consumer dedupes on `(task_id, seq)`.

---

## 2. What the spec file must contain (section-by-section brief)

The build lane writes `docs/specs/worker-messaging-v3.md` with exactly these sections.
Target ≤250 lines, tables over prose.

1. **Event taxonomy** — table with columns `event | emitter | payload fields | transport |
   consumer | fires-at-most`. Rows: `worker_spawned`, `first_byte`, `progress`,
   `needs_input`, `suite_started`, `suite_done`, `commit_made`, `terminal(kind)`,
   `died(reason)`. Each row must name the *disease* it detects: `first_byte` → D1
   (codex rollout written then `task_complete` with null `last_agent_message` in 1–3s —
   a detach with no first byte is a starvation, not a health signal);
   `commit_made` absent before `terminal` → D3; `suite_started` without `suite_done` → D2.
2. **Transport table + fallback ladder** — per event: primary (`SendMessage` when the lead
   session is addressable), always-on (`events.jsonl` append), degraded (file-watch/tail on
   the same file). State the headless constraint explicitly and mark it UNVERIFIED until
   the CC audit doc is recovered. State what `notify_when_idle` covers if real: a worker
   idle without a `terminal` event = the D2/D3 detector; if it is not real, the fallback is
   the heartbeat-gap rule in §5.
3. **Lead-side subscription model** — replaces: the cron pulse, beat log-polling, ad-hoc PID
   probes. Define one subscriber (`leadv2-event-subscribe.sh`) that tails `events.jsonl`
   for all active tasks in `docs/leadv2/active.yaml`, folds them into a derived
   `docs/leadv2/lane-state.json`, and emits at most one lead-visible notification per
   lane-terminal. Explicit rule (global token-discipline §5): one watcher per journal,
   filter to the ONE line acted on, never wrap a wait in a background command.
4. **Renderer** — `leadv2-status-render.sh` + `leadv2-broad-status.sh` read
   `lane-state.json` only. Kills the stem-file race and the stale pid-mismatch table (D4).
   Keep the existing rule: a section that cannot be measured renders "не удалось измерить",
   never `0`. Keep `leadv2-beat-owner.sh` semantics unchanged.
5. **Timeout policy** — replace the single `worker_timeout` at
   `leadv2-dispatch-product-close.sh:1751/1773` with a two-state rule:
   - `suite_started` seen and heartbeat fresh → **extend** to `suite_started.expected_s × 2`,
     capped by `LEADV2_WORKER_SUITE_MAX_S`.
   - no `first_byte` within `LEADV2_WORKER_FIRSTBYTE_S` → **kill immediately** (D1).
   - `progress`/heartbeat gap > `LEADV2_WORKER_IDLE_S` with no open `suite_started` →
     **kill** (D2 idle-wait).
   The proposed signal is therefore *the open-span set*, not wall-clock: a worker is
   "legitimately slow" only while it holds an open, heartbeat-backed span.
   Env names follow the `LEADV2_*` convention already used by `LEADV2_SINGLE_LEAD_BEAT`.
6. **Migration plan** — three slices, each shippable alone:
   - **M1 (first slice, ship alone):** emitter + `events.jsonl` + `terminal`/`died` events
     only, written *in addition to* today's `review-gate.md`. Nothing consumes it but a
     manual `tail`. Zero behaviour change, pure observability. Rollback = stop emitting.
   - **M2:** subscriber + `lane-state.json` + timeout policy §5. Renderer still on the old
     path; the two are cross-checked for one cycle.
   - **M3:** renderer/pulse cut over to `lane-state.json`; cron pulse and log-polling
     deleted; `SendMessage` fast path added behind `LEADV2_EVENT_SENDMSG=1` (default 0
     until the CC audit doc is recovered and the capability probed).
   Kill-switch for the whole feature: `LEADV2_EVENTS=0` → emitter is a no-op, exactly the
   pattern `leadv2-pulse-beat.sh` already uses.
7. **Open questions for the founder** — each with a recommended default:
   - Q1 Is the CC release audit doc recoverable, or must the build lane re-probe the CC
     capabilities live? **Default: re-probe; treat all four capabilities as absent until a
     probe artifact exists, and ship M1+M2 which need none of them.**
   - Q2 Per-task `events.jsonl` or one global stream? **Default: per-task, matching
     `leadv2-journal.sh`'s single-writer design; the subscriber does the fan-in.**
   - Q3 Do workers keep writing `journal.md` too? **Default: yes, unchanged — additive only.**
   - Q4 Should `died(reason)` from the lead-side watchdog be written into the worker's own
     stream? **Default: yes, `emitter=lead`, so one file tells the whole story.**
   - Q5 Hard-kill on missing `commit_made` before `terminal`, or flag-and-continue?
     **Default: flag + block the review gate (V3-STOP-GATE-01 owns the kill).**

---

## 3. Risks

| # | Risk | Mitigation (spec must state it) |
|---|---|---|
| R1 | CC capability claims are unsourced (§0) → design built on a feature that does not exist | D-1: journal-first; `SendMessage` behind a default-off flag until probed |
| R2 | Concurrent append from worker + lead watchdog to one `events.jsonl` | One `printf` of one <4KB line, `>>`, no lock — same contract as `leadv2-journal.sh`; consumer dedupes on `(task_id, seq)`; spec must state the size cap explicitly |
| R3 | Second watcher on the same file → duplicated notifications, permanent context cost | §3 rule: exactly one subscriber; `TaskStop` any prior Monitor before arming |
| R4 | Renderer cutover (M3) leaves a window where neither path is authoritative | M2 runs both and cross-checks for one cycle before M3 deletes the old path |
| R5 | Timeout extension becomes an infinite extension | `LEADV2_WORKER_SUITE_MAX_S` hard cap + heartbeat freshness required to extend |
| R6 | Event vocabulary drifts from the 16/13/37 existing emit sites | D-4: reuse existing names verbatim; spec includes the grep census as an appendix |
| R7 | Spec grows past 250 lines and stops being implementable | Tables, no rationale prose beyond one line per decision |

Checklist (mandatory self-check): env vars all `LEADV2_*` ✓ (no `.claude/settings.json` `env`
block found in this repo — nothing to drift against). Paths: `docs/specs/` marked
`(to-create)` — the directory does not exist. No `claude -p` invocation introduced.
Concurrency surface named in R2/R3. No existing env var redefined.

---

## 4. Non-goals (implementing agent: ignore these)

- Any code change whatsoever — this lane writes one markdown file.
- Implementing the emitter/subscriber/renderer changes (that is the build lane, M1–M3).
- V3-STOP-GATE-01's commit enforcement — this spec only defines how the lead *learns*
  of an uncommitted exit.
- Deleting/refactoring `leadv2-status-collector.sh`, `leadv2-supervise.sh` remnants, or
  the beat-owner logic.
- Recovering the missing CC audit doc (flag it; do not reconstruct it from memory).
- Any file outside `docs/specs/` and this dispatch's handoff dir.

---

acceptance:
  surface: file_artifact
  observable: |
    A human opens docs/specs/worker-messaging-v3.md on the lane branch and reads, in one
    file under 250 lines: a 9-row event table naming an emitter and a transport for each of
    worker_spawned/first_byte/progress/needs_input/suite_started/suite_done/commit_made/
    terminal/died; a transport-fallback table whose every Claude-Code-capability claim is
    either followed by a probe artifact or carries the literal token UNVERIFIED:; a
    timeout section that names the two distinguishable states (open suite span vs idle
    wait) and the LEADV2_* env var for each; a three-slice migration plan whose first
    slice is described as shippable with no consumer; and five founder questions each
    followed by a recommended default. The file is committed on the lane branch.
  authored_at: 2026-08-20T06:22:00Z

LANE_WRITES: docs/specs/worker-messaging-v3.md

DELIVERABLE_COMPLETE
