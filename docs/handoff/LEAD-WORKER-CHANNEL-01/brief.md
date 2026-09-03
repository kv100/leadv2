# LEAD-WORKER-CHANNEL-01 — workers cannot reach the lead, and the lead cannot reach a worker

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LEAD-WORKER-CHANNEL-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-notify-lead.sh,plugins/leadv2/scripts/leadv2-inbox.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-ask.sh,plugins/leadv2/scripts/ask-lead.sh,plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/tests/test-lead-worker-channel.sh,tests/run-all.sh,docs/handoff/LEAD-WORKER-CHANNEL-01/

Main is `de44cc7` in `~/Projects/leadv2`. Branch from it. Rebase before you commit.

## Why this task exists

Today two sessions in different repos talked to each other all day via `ListAgents` +
`SendMessage`, and it was the single most productive channel of the day — it carried five real
findings that neither session would have found alone. The founder wants the same channel between
**the lead and its workers**, working across sessions and across repos.

It does not exist. Verified in source, do not re-derive:

- `grep -rn 'SendMessage\|ListAgents' plugins/leadv2/scripts/leadv2-ask.sh` -> **0 hits**. The
  worker->lead wake-up is documented in `SKILL.md` as prose addressed to the worker model. It is
  not code. It fires only if a worker LLM chooses to obey a paragraph — and there is no lead-side
  handler if it does.
- `ask-lead.sh` writes `docs/handoff/<task>/questions/<qid>-pending.yaml` and then **polls**. The
  lead learns about a question only if it happens to look. Every stall we have debugged today had
  this shape: the fact existed on disk and nobody was told.
- The lead's identity IS already captured — `leadv2-dispatch-code.sh:6517-6519` computes
  `_lead_session_id` and passes it to `lane_register`. Nothing downstream ever uses it to address
  anyone.

So the channel that worked was two models improvising. Make it a mechanism.

## The design constraint that decides everything

**Bash cannot call `SendMessage`.** Only a model can. So a design where delivery depends on the
message is a design that goes silent the moment a model is busy, dead, or headless — the exact
disease this session has spent the day removing.

Therefore: **the message is the fast path, the file is the guaranteed path.** Same contract the
question store already has, and it must hold here too:

- every event writes a durable row, unconditionally, with no network and no model involved;
- the `SendMessage` wake-up is an optimisation on top, and its failure is never fatal;
- nothing is ever *only* a message.

Do not invert this. A test that proves the message arrives but not that the row was written is
testing the wrong half.

## [Critical] one worker->lead notifier, called at every moment worth waking a lead

Build `leadv2-notify-lead.sh <task-id> <event> <one-line-text>`. It must:

1. append one row to a durable per-lead inbox — keyed by the **lead session id**, not by repo, so
   a worker in `persona-engine` and a worker in `leadv2` reach the same lead. Say in `report.md`
   where you put it and why that path is reachable from both repos;
2. record `repo`, `task-id`, `lane`, `event`, `at` (UTC), and the text, so the lead can render a
   line without opening anything else;
3. print, on stdout, the exact one-line `SendMessage` payload the worker model should relay, in
   the `[leadv2-q]`-style form already documented in `SKILL.md`. Printing it is the whole
   contract — the script does not send;
4. exit 0 when the lead is unknown or unreachable. A notifier that can fail a lane is worse than
   no notifier.

Wire it at these events, each exactly once, in the code that already knows the fact:

- a question is asked (`ask-lead.sh`, `leadv2-ask.sh`) — the case that exists today as prose;
- a lane is **blocked** (review round cap, gate refusal, admission refusal);
- a **control failed** — a mutation that did not turn its suite red;
- a lane **finished** (commit landed) and a lane **died** (no pid, no commit). These are two
  different facts and must not collapse into one event;
- a lane has been **silent** past its own threshold.

Say in `report.md` which call sites you found for each, and name any you deliberately did not wire.

## [Critical] the lead must drain the inbox without being told

Build `leadv2-inbox.sh drain [--lead <id>]`: prints unread rows oldest-first, marks them read
atomically, exits 0 with no output when empty. Then call it from the beat in
`leadv2-broad-status.sh`, so an unread event reaches the founder's status table on the next pulse
**even if every message was lost**. That is the property that makes this mechanism real rather
than another thing that works when everything already works.

Unread rows must survive a compact, a lead restart, and a second concurrent lead session; two
leads draining at once must not lose or double-deliver a row.

## [Medium] lead->worker

The lead already answers via `/leadv2 reply`, which writes the answered yaml the worker polls for.
Keep that as the guaranteed path — do not replace it. Add only the wake-up: record, at dispatch,
whatever identity a worker session can actually be addressed by, and say in `report.md` **what you
found by running `ListAgents`, not what you assume** — if dispatched arms are not addressable,
write that down plainly and wire nothing. An unverified addressing scheme is worse than none.

## Acceptance

Build `test-lead-worker-channel.sh` against fixture state roots and fixture handoff trees — never
a real lane, never the real lane registry, never a real inbox:

1. an event with **no lead reachable** => row still written, exit 0;
2. an event from repo A and an event from repo B for the same lead => both land in one inbox,
   in order;
3. `drain` returns each row exactly once across two consecutive calls;
4. two concurrent `drain` calls => every row delivered exactly once, none lost;
5. an undrained row => appears in the beat's rendered status;
6. `finished` and `died` produce distinct events for the same lane;
7. the notifier failing (unwritable inbox) => the caller's exit code is unchanged.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production function body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Mutate the **durable write**, not the message — dropping the row must turn
  the suite red.
- A kill counts only if **this suite alone** goes red, and only if the suite was green first.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence. A
  printed `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Never write to the real `~/.claude` state root from a test.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A worker in any repo can record a lead-addressed event with one call that cannot fail its lane,
the lead sees unread events on its next beat without anyone messaging it, and a mutation that
drops the durable row turns the suite red with the exit code following.

## Addendum — the lead measured the addressing scheme, so you do not have to

Run at 2026-08-31 from the lead session `persona-engine-d2`, immediately after dispatching a lane:

```
ListAgents ->
  close-gate-a2-id-scheme-mismatch-01-76 [b6c58d] · interactive · started 5m ago
SendMessage to that name -> success:true
```

**A dispatched lane IS addressable by name, and the name is the founder task id lowercased with a
numeric suffix.** So the [Medium] section is not speculative: record the name at dispatch and the
lead->worker wake-up is wireable. Still verify it yourself before wiring, and still keep the
answered-yaml poll as the guaranteed path — the name carries a suffix the dispatcher does not
choose, so it must be discovered via ListAgents, never constructed.

**Correction, measured minutes later:** `SendMessage` returned `success:true`, but the delivery
notice said the message was **held for the recipient user's approval** and never reached that
session. So lead->worker is NOT an autonomous channel — a human must approve each inbound message.
A `success:true` from SendMessage is therefore NOT proof of delivery. Treat lead->worker wake-up as
unavailable for unattended lanes, keep the answered-yaml poll as the only real path, and say so in
`report.md` rather than wiring a channel that silently needs a human.

**Final measurement (same lane, ~20 min later):** the held message **expired unapproved and was never
delivered**. So lead->worker via SendMessage is not merely gated, it is unusable for an unattended
lane: nobody is sitting at the worker to approve it. Wire NOTHING in that direction. The [Medium]
section is answered — record the finding in `report.md`, keep the answered-yaml poll, and spend the
effort on worker->lead, which is the direction that actually works.
