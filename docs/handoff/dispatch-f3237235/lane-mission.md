# Codex must always be available: one dead job must never park the provider

**Priority 0, above everything else on the pre-WAVES list.** Founder order, 2026-09-08:

> «твоя самая важная задача в жизни это сделать так чтобы кодекс работал всегда, мы никогда не
> проёбывались с локаутами и тд. Кодекс доступен всегда, глм только когда у него НЕ пиковые часы,
> клод тоже всегда доступен, оба аккаунта.»

REPO: `~/Projects/leadv2`. Its `main` IS the live path — symlink deploy, so a fix not committed to
main is not delivered. **Dispatch and work from `~/Projects/leadv2`.**

---

## The mechanism, read out of the live tree and the live lockout store

`plugins/leadv2/scripts/leadv2-dispatch-code.sh:7146-7180`,
`_codex_worker_liveness_deadline_check`. Two paths, and **each parks the whole codex provider for
an hour**:

```
:7163  emit decision "arm_dead_worker_liveness arm=codex ... reason=vanished_job"
:7165  record-quota-lockout --provider codex --hours 1 --reason arm_dead_worker_liveness

:7174  emit decision "arm_dead_worker_liveness arm=codex ... reason=turn_aborted rollout=${f}"
:7176  record-quota-lockout --provider codex --hours 1 --reason arm_dead_worker_liveness
```

The live record on this machine, read 2026-09-08T15:40Z:

```json
{"provider":"codex","locked_until":"2026-09-07T12:38:16Z","locked_until_epoch":1788784696,
 "source":"standdown:arm_dead_worker_liveness","class":"standdown","strikes":55}
```

**Fifty-five strikes.** And in the same window the live quota gate answers
`[provider-quota-gate] OK — codex 27% < 95% rc=0`. So codex has been parked 55 times by *our own*
machinery while the provider itself was fine and nowhere near its ceiling.

Neither trigger is a provider refusal:

- `vanished_job` — codex-task `status <handle>` positively returned "No job found". That is **one
  job's row** missing.
- `turn_aborted` — the newest rollout file since spawn contains a turn-aborted event. That is
  **one turn** aborting.

A provider lockout is the instrument for "the provider is refusing us" (429, usage limit). Using it
for "this one worker died" removes the arm from **every future selection for an hour**, across
every lane and every session. That is the founder's «проёбывались с локаутами», precisely.

### And the trigger can fire on the wrong job

`_codex_newest_rollout_since` picks the newest rollout under `~/.codex/sessions`. The B4 dispatch
log carries, from a healthy lane:

```
arm_dead_instant_complete_ambiguous_rollout arm=codex task=1401655b candidates=2
  picked=…/rollout-2026-09-08T18-18-29-01a08199-….jsonl
```

Two candidates, one picked. We now run up to **eight concurrent lanes**, so several codex rollouts
exist at once and the scan is choosing between them. If it attributes another lane's aborted turn
to this lane's healthy worker, a healthy worker parks the provider for an hour. **Establish whether
that is actually happening** — `strikes=55` is a lot of genuinely dead workers, and misattribution
is the cheaper explanation. Measure it; do not assume it either way.

---

## What the fix has to achieve

**A dead codex JOB must never make the codex PROVIDER unavailable.** That is the acceptance
criterion.

Concretely:

- The job-level response stays: a dead worker must still abort its reservation and spill (the
  `rc=7` contract), so a lane does not hang. Keep that.
- The provider-level response goes: no `record-quota-lockout` from a worker-liveness verdict.
  Whether the strike should be recorded somewhere non-blocking (a counter, an arm cooldown that
  deprioritises rather than excludes, a journal line only) is yours to determine and defend — but
  the arm must remain **selectable**.
- **A genuine provider refusal must still park codex.** A 429 or a usage-limit refusal is what the
  lockout store is for and it stays. Name which code paths those are so it is clear you did not
  disarm them along with this one. `lib/leadv2-codex-quota-gate.sh` distinguishes
  `quota_gate` / `quota_circuit_open` / `circuit_unknown` / `transport_cooldown` — read that
  vocabulary before you touch anything; it already separates "provider refused" from "our runtime
  broke", and that distinction is the fix's backbone.
- Fix the rollout attribution, or state plainly that you could not and why. A liveness check that
  reads another lane's file is wrong even after the lockout is removed, because it will still spill
  a healthy worker.

**Do not simply set `LEADV2_CODEX_WORKER_LIVENESS_SECS=0`.** That disables the detection entirely
and reintroduces the hanging-lane failure the check exists to prevent — which is the sibling of B4,
already a P0 in this same plan. Keep the detection, remove the punishment.

---

## While you are in there: the other two arms of the same order

The founder's order covers three arms. Codex is the whole of this mission; the other two are
**context, not scope** — do not implement them here, but say in your report whether your change
interacts with them:

- **Claude — always available, both accounts.** In flight as D1
  (`missions/d1-a-401-is-not-a-dead-account.md`): a 401 from the usage endpoint currently classifies
  `unknown` and carries `UNKNOWN_PROBE_PENALTY=50.0`, which exceeds the entire cost range and prices
  the account out of every selection.
- **GLM — available except at its peak hours.** Today GLM is gated by a *utilization ceiling*, not
  by time. I raised that ceiling 80→95 today (`9bfebf21`) because it was refusing at 80 while codex
  and claude ran to 95. A peak-hours gate does not exist yet and is not yours to build.

---

## Negative controls (E2E-KILLRATE-01, non-negotiable — two, both run, red then green)

1. **The symptom.** A codex worker declared dead by the liveness check must leave the codex provider
   **selectable** — assert that a subsequent resolution still offers codex, and assert the lockout
   record's absence as a **value**, not a log string. Before your fix this must FAIL.
2. **The guard.** A genuine provider refusal (usage-limit / 429 shape) must STILL park codex.
   Break your own rule deliberately (suppress every lockout write) and show the suite goes red.
   Without this control the fix is "codex is never locked out", which is a different bug wearing
   the founder's words.

Insert every mutation **inside the function body**, never at top level: a top-level insert reddens
everything for the wrong reason and reads as a pass. That mistake has already invalidated one
measurement in this repo.

Register your suite with a `# run-all-triggers: leadv2-dispatch-code` header. **Then prove selection
correctly** — `--scope changed` lies in three ways: it counts from
`$GIT_DIR/leadv2-run-all-last-checked-sha` when that file exists (`:294-310`); with no checkpoint
and no resolvable base ref it degrades to `HEAD~1..HEAD` (`:308-317`); so a correctly registered
suite can look unregistered and a broken one can look fine. Pin the range to the merge base for the
proof and state which range you measured from.

---

## Constraints

- **`plugins/leadv2/scripts/leadv2-dispatch-code.sh` is contended.** Lane `A4-WIRE-ESTIMATOR` holds
  it. Do not start until the lead tells you it is free — two lanes writing that file is how a fix
  gets silently reverted, and this is the one fix that must not be lost.
- Do not merge. Report, and the lead verifies and merges.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`. Never
  `git add -A` — enumerate paths.
- Report `main...HEAD` (three dots), never `main..HEAD`.
- Do not delete or edit live lockout records under `~/.claude/cache/dispatch-ledger/` as part of the
  fix. If a stale record needs clearing, say so and let the lead do it.

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/tests/test-a-dead-codex-job-does-not-park-the-provider.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-f3237235" "<question>" \
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