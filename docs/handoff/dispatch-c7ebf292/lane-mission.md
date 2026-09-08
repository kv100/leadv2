# Seamless account switching — design mission (fable arm)

**Design mission, not an implementation mission.** Produce a report; write no production code.
Section E1 of `PRE-WAVES-PLAN.md`, ordered by the founder on 2026-09-08 as pre-WAVES work.

This same mission is being given to **two arms independently**. You will not see the other report
and it will not see yours. That is deliberate: on the two previous design questions the second arm
caught a factual error in the first, and on one of them it caught an error of mine. Do not try to
guess what the other arm will say, and do not hedge toward a middle position.

REPO: `~/Projects/leadv2` (the plugin's `main` is the live path). Read `~/Projects/persona-engine`
too — it is the repo that dispatches.

---

## The problem, in the founder's own framing

> «как будто бы чтобы не делать свитч каждый раз и не делать релоад сессий из-за этого (еще и
> после свитча нереально сделать resume и надо поднимать новые сессии) надо придумать бесшовный
> механизм, это особенно важно в связи с тем что у нас будут теперь 2 max x5 аккаунта.»

Three costs stated there, and the third is the one that changes the arithmetic:

1. A switch forces a **session reload**.
2. After a switch, **`resume` does not work** — new sessions have to be raised from scratch, losing
   the lead's context and every lane's.
3. With **two max_5x accounts**, switching stops being a rare event and becomes routine load
   balancing. A cost paid rarely is a nuisance; the same cost paid routinely is the design.

---

## What the report must settle

**1. Where exactly does a switch break resume?** Not "somewhere in the session layer" — name the
file and the mechanism. Is the transcript keyed to the account? Is it the credential store, the
session id, an on-disk path, a server-side conversation binding, a cached OAuth token? The answer
determines whether this is fixable at all in the client we have, and that is the most valuable
sentence you can write. If the honest answer is "resume is bound to the account server-side and no
local change can preserve it", say that plainly — it is a finding, and it reshapes the rest.

**2. Can a live session's credential change without killing the session?** There is a partial
precedent already in the tree and it is worth reading before theorising: **lanes are already
halfway there.** A dispatched lane runs as a separate process with its own `--claude-profile`, so
per-process account selection already exists and works. The open question is the *lead's own*
session, not the lanes'. Say what is different about it.

**3. How does the balancer know which account is free — without asking a usage endpoint?**
This constraint is not arbitrary. See `D1` in the plan and the mission
`d1-a-401-is-not-a-dead-account.md`: an account whose token resolves and whose usage endpoint
answers **401** is currently classified `unknown` and charged `UNKNOWN_PROBE_PENALTY=50.0`
(`lib/leadv2-route-arbiter.sh:913`), which prices it out of every selection — and **`max_5x` is a
team account whose usage endpoint answers 401 by design**, with a standing rule that we do not
measure spend on it and that a 401 never by itself proves a token is dead. So with two max_5x
accounts, the balancer's primary signal is unavailable *for exactly the accounts it must balance*.
Design against that, not around it. D1 is in flight; assume it lands, but do not assume it restores
a usage number — it may only stop the penalty.

**4. What is the smallest thing that actually helps?** Rank your proposals by cost. If a full
seamless switch is out of reach, what partial measure removes most of the pain — pre-warmed
sessions on each account, a switch that preserves the transcript even if it cannot preserve the
process, per-lane accounts with the lead pinned to one, a handoff file? A ranked list with honest
costs beats one ambitious design.

---

## Rules of evidence, which are the point of this exercise

- **Measure, do not read.** Every previous design mission that reported from a single grep produced
  a false fact that had to be retracted. One arm reported three "measured facts" from one checkout
  and one grepped file; all three were false. Check a claim in more than one place before you write
  it as a finding.
- **A count is a claim.** If you count files, say how you enumerated them and whether the
  enumeration was truncated — a census truncated at 400 entries produced wrong numbers on this
  exact project three days ago and I was the one who produced them.
- **Say what you did not check.** An explicit gap is worth more than a confident guess. "I could not
  determine X, here is the command that would" is a finding.
- **Contradict me if I am wrong.** Everything in this mission that is not quoted from the founder
  is my summary and may be wrong.

---

## Hard constraints

- **Never print, commit, or paste the contents of `~/.claude/state/leadv2/claude-profiles.tsv`.**
  Refer to account slots by **LABEL only** (personal, work). This is absolute.
- **Do not read or modify `~/.claude/settings.json`** or any permission file. A project's own
  `.claude/settings.json` is a different file and is readable.
- **Do not perform repeated live authentication attempts against any account.** One probe is a
  probe; several is credential abuse and trips fraud heuristics. Describe the probe, run it at most
  once, and say you did.
- **Do not switch the founder's live account** to test anything. Ever.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`.
- Never `git add -A` — enumerate paths.
- Report `main...HEAD` (three dots), never `main..HEAD`.

---

## Deliverable

One markdown report. **Write it to `docs/audits/`, NOT `docs/handoff/`** — a mission whose declared
write set lies entirely under `docs/handoff/` is refused as `undiffable_write_set` about 25 seconds
after the worker spawns, and that killed two design lanes on 2026-09-08 with the work already paid
for.

Filename: `docs/audits/seamless-account-switching-fable.md`.

LANE_WRITES: docs/audits/seamless-account-switching-fable.md

<!-- arm=fable; a sibling file carries the identical mission for the codex/astra arm. Two
     files, not one: the dispatcher dedupes on mission-content signature, so dispatching one
     file twice is refused as duplicate_task_signature and only one arm ever runs. That
     happened on 2026-09-08 and cost the fable half of this design. -->

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-c7ebf292" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.