# CODEX-DETACH-01 — round 2: half the guarantee is unasserted

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CODEX-DETACH-01`

LANE_WRITES: plugins/leadv2/scripts/codex-task.sh,plugins/leadv2/scripts/codex-guard.sh,plugins/leadv2/scripts/tests/test-codex-broker-staleness.sh,tests/run-all.sh,docs/handoff/CODEX-DETACH-01/

HEAD is `fad9908`. Main is `7927b0f`. **This lane is blocking another session** — it is holding
off codex dispatches until the validation lands, so this round matters beyond the lane.

`_codex_validate_broker` is the right shape and stays. The suite is 3/0. The control is not.

## [Critical] removing the sessionDir check leaves the suite green

I ran it myself. Dropping the `-d` test so a swept directory counts as present:

```bash
  if [[ -n "$_session_dir" ]]; then     # was: [[ -n "$_session_dir" && -d "$_session_dir" ]]
```

```
rc=0
[CODEX-BROKER-STALENESS] pass=3 fail=0
```

Green with half the guarantee gone. The reason is in the fixture: case 1 pairs a **dead pid**
with a swept `sessionDir`, so the pid half decides every assertion on its own and the sessionDir
half is never the reason for any verdict.

That is exactly the case the brief singled out, and it is still unprotected: a swept
`sessionDir` whose pid has been **reused by an unrelated live process**. `kill -0` succeeds, the
broker is gone, and a pid-only check waves the worker straight onto a corpse.

Add that fixture — a **live** pid (spawn a real short-lived process the test controls, and use
its pid) together with a `sessionDir` that does not exist — and assert the broker is moved
aside. Then prove it: remove the `-d "$_session_dir"` test, show this suite go red naming that
assertion, restore it, show green, paste a clean `git diff --stat`.

Mirror it for the other half if it is not already load-bearing: a **live** pid with a present
sessionDir must be left untouched (you have this as case 2 — confirm a mutation to the pid
check turns it red, and say so).

## [Medium] the death report enrichment is unverified

The brief asked the reaper's failure record to carry the worker log's last line and the
broker's age plus whether its `sessionDir` existed at reap time. Nothing in the suite asserts
it. Add an assertion on the persisted record — not on source text — and mutation-prove it.

This matters because the absence of that detail is precisely why three sol-worker deaths read
as a 5-minute timeout across two sessions for two days.

## Rules

- Mutation INSIDE the production function body, RED, revert, GREEN, clean `git diff --stat`.
- A kill counts only if **this suite alone** goes red — if another gate kills your mutation
  first, the control proves nothing about your suite.
- A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Never touch `~/.claude/plugins/cache/openai-codex/` or any real state root under
  `~/.claude/plugins/data/` — fixtures only, removed on every exit path including failure.
- Any process the suite spawns for a live-pid fixture must be reaped on every exit path.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A live pid with a swept sessionDir moves the broker aside; removing the `-d` test turns this
suite red; the enriched death report is asserted on the record and mutation-proven. Then the
lane is merge-ready and the other session's codex hold can be lifted.
