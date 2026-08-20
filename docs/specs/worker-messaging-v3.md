# worker-messaging-v3 — design spec (V3-WORKER-MESSAGING-01)

Status: DESIGN. No code lands from this doc; the build lane implements it.
Scope: how a lane worker tells the lead what happened, and how the lead's status
surfaces stop polling for it. All paths relative to `plugins/leadv2/` unless absolute.

## 0. The problem, stated as four live faults (2026-08-20)

| id | fault | where today's code makes it invisible |
|----|-------|--------------------------------------|
| D1 | codex arm wrote ~100KB then `task_complete` with null `last_agent_message` in 1-3s; dispatcher saw a healthy detach, 4 lanes starved | `scripts/leadv2-dispatch-code.sh:3313-3315` — `_wait_arm_early_verdict` treats `complete` as unconditional `return 0`, with no floor on elapsed time or produced bytes. The sibling guard `_codex_first_byte_deadline_check` (:3348, called :3494) only covers *no* output, never *instant* output. |
| D2 | sonnet workers background a suite, arm a Monitor, idle-wait, get killed at `worker_timeout` (4 deaths) | `scripts/leadv2-dispatch-product-close.sh:875-896` (`pc_worker_alive`) proves only `kill -0`; `pc_await_worker_exit:1047-1108` counts wall clock to `LEADV2_PC_WORKER_MAX_WAIT_S` (4200) with no notion of *what* the worker is waiting on. An idle Claude and a Claude running a 40-min suite are byte-identical to it. |
| D3 | workers exit without committing, repeatedly | the lead learns only at `pc_scope_diff` → `review_gate ... terminal=no_work` (:1729-1731), i.e. after the full wait. There is no event at the moment of exit. |
| D4 | founder-status showed only stale pid-mismatch rows while 2 lanes were live | `founder-status.md` is composed by `scripts/leadv2-broad-status.sh:34,36` from `status-snapshot.json`, produced on a timer by `scripts/leadv2-status-collector.sh:107-130` out of `leadv2-lanes-snapshot.sh` (active.yaml pid rows) + `leadv2-lane-detail.sh`. Every layer polls a file; nothing receives a lane event. The beat hook then re-polls a *log* (`hooks/leadv2-single-lead-beat.sh:137`, `grep BROAD_STATUS_READY supervise-loop.log`) and dedupes on a body hash (:145-150) — the stem-file race. |

One sentence: **every path from worker to founder is a poll of a file written by something else.**

## 1. Event taxonomy

One append-only JSONL per repo, one line per event, written by `scripts/leadv2-event.sh`
(new). Schema (flat, stable keys):

```json
{"seq":1731,"ts":"2026-08-20T21:14:02Z","repo":"persona-engine","task":"dispatch-1a2b3c4d",
 "lane":"V3-STOP-GATE-01","arm":"sonnet","handle":"PID=48122","kind":"suite_started",
 "ttl_s":2400,"detail":"pytest tests/unit"}
```

| kind | emitter | when | consumer |
|------|---------|------|----------|
| `worker_spawned` | `leadv2-dispatch-code.sh` confirm path (:3455-3462) | handle confirmed live | lead, renderer |
| `first_byte` | lane driver, on first non-empty `_arm_final_output` / stream byte | ≤180s of spawn | D1 detector |
| `progress` | worker, via its own Bash calls | free-form, rate-capped 1/60s | renderer only |
| `needs_input` | `_pc_emit_pending_questions` (`leadv2-dispatch-product-close.sh:1096-1101`) | question written to the async store | lead (must answer) |
| `suite_started` / `suite_done` | worker (`ttl_s` REQUIRED on `suite_started`) | around any long fg command | timeout policy §5 |
| `commit_made` | worker Stop-gate hook (V3-STOP-GATE-01) | each commit in the lane worktree | D3 detector |
| `terminal` | lane driver, at every existing `_dl_note`/`review_gate` site (`leadv2-dispatch-product-close.sh:1731,1751-1755,1773-1777`) | lane end | lead, renderer, ledger |
| `died` | lane driver + Stop hook | reason ∈ `timeout \| no_commit \| silent_instant_complete \| crash \| killed` | lead |

`terminal` and `died` carry `commits=<n>` and `bytes=<n>` unconditionally. A `terminal`
with `commits=0` **is** the D3 signal; nothing further needs inventing.

Log path: `${LEADV2_EVENT_LOG_DIR:-$HOME/.claude/cache/leadv2-events}/<repo>.jsonl`,
mirroring the dispatch-ledger convention already read at
`scripts/leadv2-status-collector.sh:144`. `seq` is a monotonic counter in a sibling
`.seq` file, taken under the same `flock` discipline `leadv2-dispatch-ledger.sh:130`
uses. Rotation: 10MB, keep 3.

## 2. Transport tiers

Durability and latency are separate concerns and get separate mechanisms. **Tier 0 is
always written; a push is never the only copy.**

- **Tier 0 — append (durable, always).** `leadv2-event.sh emit …`. Plain file append,
  fail-open like `emit()` at `leadv2-dispatch-code.sh:1066-1073`. This alone makes every
  fault above *recoverable after the fact*; tiers 1-2 make it *fast*.
- **Tier 1 — inbox injection (push, bash-side, same machine).** A lead session's
  `SessionStart` hook persists its own `CLAUDE_CODE_MESSAGING_SOCKET` +
  `CLAUDE_CODE_MESSAGING_TOKEN` (both exported to hooks/Bash) to
  `<state>/lead-inbox.json`, mode 0600. `scripts/leadv2-event-relay.sh` — one per repo,
  started by the same hook — tails the event log and posts `terminal` / `died` /
  `needs_input` into that socket with the `{"type":"auth","token":…}` first frame.
  Per the CC docs this is an own-session post: it bypasses `crossSessionInbound` and
  needs no Claude-side tool call, which is why it works from a plain lane driver.
  Constraint: macOS/Linux only (we are Darwin-only), not Bedrock/Vertex.
- **Tier 2 — `SendMessage` with `notify_when_idle` (push, Claude-side, 2.1.236+).** The
  *lead* calls this once per lane, addressed to the worker session by name. This is the
  only mechanism that distinguishes "Claude is idle" from "process is alive", which is
  exactly the D2/D3 discriminator. Requires the worker to be nameable and inbox-bound:
  - `scripts/claude-subsession.sh:390-401` must add `--name "lane-${TASK_ID}"` to
    `CLAUDE_ARGS`; today the session has only a `--session-id` UUID (:392) and is
    therefore not addressable by `ListAgents`/`SendMessage` (bare-name delivery, 2.1.232).
  - It must NOT gain `--bare` — a `-p` session binds an inbox unless bare.
  - A `-p` session cannot show an approval dialog: set `crossSessionInbound: accept` for
    lanes, or a held message just expires at `dialogExpiry` and the lead is told
    "expired" — a silent stall dressed as a delivery.
- **Tier 3 — fallback.** If tier 1 and tier 2 are both unavailable (version below
  2.1.236, socket missing, non-Darwin), the existing beat hook still delivers, only
  slower. Availability is checked once per session and recorded in the event log as
  `note kind=transport_tier`; a degraded tier is visible, never assumed.

Non-goals: never send diffs, files, or history over `SendMessage` (plain text only,
~1M char cap, burst-refused up front since 2.1.236). Events are pointers; the artifact
stays on disk.

## 3. Lead-side subscription model

Replaces: the cron/beat pulse, the beat hook's log grep, and ad-hoc PID probes.

- **Subscription registry** `<state>/subscriptions.yaml`: one row per
  `(lane, kinds, armed_at, expires_at, transport_tier)`. Written when the lead dispatches
  a lane; cleared on `terminal`.
- **A wait is a registered subscription, never a promise.** The existing Stop-hook family
  already enforces the ending-turn contract (`hooks/leadv2-continuation-guard.sh`,
  `hooks/leadv2-promise-guard.sh`). Extend the guard's satisfaction test: a turn that ends
  while claiming to wait must show *either* a state-changing call *or* a subscription row
  in `subscriptions.yaml` that is armed and unexpired. "I'll check back" with no row is
  the same violation the guard blocks today, and becomes mechanically detectable.
- **Beat hook becomes a consumer, not a poller.** `hooks/leadv2-single-lead-beat.sh:136-169`
  drops the `grep BROAD_STATUS_READY` + `tail -n +2 | shasum` body-hash dedupe and instead
  reads `leadv2-event.sh since <seq>` against a per-session watermark file (the existing
  `.pulse-delivered.${SAFE_SID}` slot, :93, now holding a seq instead of an `at=`). Dedupe
  on a monotonic integer removes the stem-file race outright: two composers cannot produce
  the same seq.
- **Pulse fires on lane-terminal, not on wall clock.** `scripts/leadv2-pulse-beat.sh --check`
  keeps its flock and throttle but its trigger condition becomes "unconsumed `terminal` /
  `died` / `needs_input` events exist", with `LEADV2_SINGLE_LEAD_BEAT_S` (default 1800,
  `hooks/leadv2-single-lead-beat.sh:123`) demoted to a *floor* between beats, not the clock.
- **Delta only.** The pulse renders live + next; finished rows are never re-listed.

## 4. Renderer

`scripts/leadv2-broad-status.sh` gains a third input beside `status-snapshot.json` (:34)
and `.broad-status-prev.json` (:35): the event-log tail since the last beat's seq.

Join rule, stated so it cannot drift: **a lane's row is composed from its newest event;
the snapshot supplies only slow facts** (git head, unpushed count, repo facts —
`leadv2-status-collector.sh:78-98,185-198`). A lane present in the event log with a
non-terminal newest event is LIVE **even when `active.yaml` has no matching pid row** —
that inversion is exactly D4, and it must be asserted by a test, not by prose.
Consequently `leadv2-lane-detail.sh`'s HARD RULE 2 (liveness verbatim from
`leadv2-lane-liveness.sh`, :12-14) stays true for snapshot-derived rows and is
*superseded* by the event log where the two disagree, with the disagreement itself
rendered (`pid_row=stale`) rather than silently resolved.

## 5. Timeout policy — extend vs kill

Today `pc_await_worker_exit` has one budget for both cases
(`leadv2-dispatch-product-close.sh:1056-1058`). Split it on a signal the worker *declares*,
plus one the runtime *observes*:

- **Declared:** `suite_started` with a mandatory `ttl_s`. While the newest event for the
  lane is an unexpired `suite_started`, the wait ceiling extends to
  `max(max_wait_s, event.ts + ttl_s + grace)`; `suite_done` (or TTL expiry) reverts it. A
  worker that wants more wall clock must say so on the record — an unbounded
  `suite_started` is rejected at emit time.
- **Observed:** a tier-2 idle notification for the lane. A Claude session running a
  foreground command is *not* idle; one parked on a Monitor *is*. So an idle notification
  while no `suite_started` is live is the D2 signature: kill immediately with
  `died reason=idle_wait`, do not spend the remaining budget.
- **Neither:** silence past `LEADV2_PC_WORKER_SILENT_MAX_S` (default 900, reusing the
  existing `LEADV2_LANE_SILENT_MAX_S` semantics at `leadv2-lane-detail.sh:52`) with no
  event of any kind → `died reason=silent`, well before the 4200s ceiling.
- **D1 floor:** in `_wait_arm_early_verdict` (`leadv2-dispatch-code.sh:3311-3315`), the
  `complete` branch gains the same shape the `failed` branch already has — consult
  `_arm_final_output` first. `complete` with empty output *and* elapsed <
  `LEADV2_ARM_MIN_RUNTIME_S` (default 30) emits `died reason=silent_instant_complete` and
  returns 7 (spill to next arm), reusing the rc=7 branch at :3486-3493 verbatim.

## 6. Migration

**Slice 1 (ships alone, no hook changes, no CC version floor).** `scripts/leadv2-event.sh`
+ tier-0 emits at the sites that already exist: the four `_dl_note`/`review_gate` calls in
`leadv2-dispatch-product-close.sh` (:1731, :1751-1755, :1773-1777) and the confirm path in
`leadv2-dispatch-code.sh:3455-3462`. Lead reads `leadv2-event.sh since <seq>` by hand.
This alone gives D3 and D1 a durable record. Rollback: delete the script; every emit is
`|| true`.

**Slice 2.** D1 floor (§5) + `--name` on `claude-subsession.sh:390-401`. Independent of
transport.

**Slice 3.** Tier-1 relay + `lead-inbox.json` from a `SessionStart` hook (sibling of
`hooks/leadv2-idle-guard-arm.sh`). Kill switch `LEADV2_EVENT_RELAY=0`.

**Slice 4.** Beat hook + pulse + renderer flip to consuming the log (§3, §4). Kill switch
is the existing `LEADV2_SINGLE_LEAD_BEAT=0` (`hooks/leadv2-single-lead-beat.sh:32`).

**Slice 5.** Tier-2 `notify_when_idle` subscriptions + the §5 idle-kill. Gated on CLI
≥2.1.236 (installed is 2.1.235 — this slice cannot be verified before the upgrade).

Each slice is independently revertible and each has a falsifiable acceptance probe: an
event line on disk, not a claim.

## 7. Open questions (recommended default first)

1. **Event log per repo or per lane?** → *Default: per repo, one file.* Per-lane files
   reintroduce the glob-and-stat pattern that makes the current renderer slow and racy.
2. **Does the worker emit its own events, or only the lane driver?** → *Default: both,
   split by knowledge.* Only the worker knows `suite_started`/`ttl_s`; only the driver
   knows `terminal`. A worker-only design cannot report its own crash.
3. **`crossSessionInbound` for lane sessions?** → *Default: `accept`.* `hold` on a `-p`
   session expires at `dialogExpiry` and reports "expired" to the sender — a stall that
   looks like a delivery. Accept, and rely on the permission boundary (a message is never
   consent) rather than on holding.
4. **Do we adopt tier 2 at all, given it needs 2.1.236?** → *Default: yes, but last.*
   Slices 1-4 are version-free and fix D1/D3/D4. D2 is the only fault that genuinely needs
   the idle signal; ship the rest first, upgrade, then slice 5.
5. **Should the relay push `progress` events too?** → *Default: no.* Every pushed event is
   permanent conversation context re-sent on every later turn. Push only `terminal`,
   `died`, `needs_input`; `progress` stays tier-0 and is read on demand.
6. **Does `terminal` write the dispatch ledger, or mirror it?** → *Default: mirror for
   now.* `leadv2-dispatch-ledger.sh` keeps write-once ownership; the event log is a second,
   cheaper reader surface. Collapsing them is a follow-up once the event log has soaked.
7. **`CLAUDE_CODE_ENABLE_TODO_TOOLS`?** → *Default: leave unset.* Nothing in this design
   uses Task tools; the subscription registry is a plain YAML file precisely so it does not
   depend on a tool family that is off by default on current models (2.1.233).
