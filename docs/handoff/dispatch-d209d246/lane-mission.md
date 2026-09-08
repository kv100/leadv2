# CODEX-REFUSAL-MARKER-CARRIES-ITS-CAUSE-01

Repo: ~/Projects/leadv2 (SHARED TREE — never `git add -A`, never `reset --hard`, never `clean`,
never `stash`, never push to origin. Name every path in `git add`, then confirm with
`git diff --cached --name-only`.)

**COMMIT AFTER EVERY STEP.** Five workers died on this machine on 2026-09-06, every one of them
after writing real code and before committing it. Your commits are the only thing that survives you.

## The defect, measured

`codex_spawn_gate()` in `plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh` has THREE distinct
refusal paths — (1) arm cooldown, (2) circuit open, (3) circuit state unknown / control plane
unreachable ⇒ refuse — and every one of them prints the SAME marker:

    printf 'LEADV2_DISPATCH_REFUSED: quota_gate\n' >&2

The dispatcher reads that one word and records a **quota** lockout. Live artifact from last night,
`~/.claude/cache/dispatch-ledger/quota-lockout-codex.json`:

    {"provider":"codex","locked_until":"2026-09-06T07:51:49Z","source":"launcher_refusal:quota_gate",
     "class":"provider_refusal","strikes":54}

Three separate falsehoods follow from it:

1. The cause is lost. The real cause overnight was five `transport_gone_app_server_absent` deaths —
   the arm cooldown path, correctly labelled at its own layer and destroyed at this boundary.
2. The lockout invents its own 30-minute expiry instead of inheriting the expiry of the thing that
   actually caused it. Measured: the lockout outlived its cause by 22 minutes.
3. Transport strikes accumulate in the QUOTA counter — 54 strikes while the arm sat at 9% of quota
   (`OK — codex 9% < 95%` from the ceiling check in the same window). A subscription-tier increase
   therefore cannot help, and nobody reading `strikes=54` would know that.

## What to change

1. Give the marker a cause: `LEADV2_DISPATCH_REFUSED: <cause>` where cause distinguishes at least
   quota / transport / circuit-unknown. Keep the old word as a valid value so any existing reader
   that greps `quota_gate` does not break — check who greps it before you decide the format.
2. The lockout must inherit its cause's expiry. A cooldown that ends at T must not produce a
   lockout that ends at T+22min.
3. Transport and circuit-unknown strikes must not increment the quota strike counter. Decide where
   they DO belong (a separate counter, or none) and say why in the report.

Callers to check: `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (the reader that writes the
ledger) and anything else that greps `LEADV2_DISPATCH_REFUSED`. Enumerate them, don't guess.

## Proof required

1. A suite driving all three refusal paths and asserting the three distinct markers, plus that a
   transport refusal does NOT write a quota lockout and does NOT bump the quota strike counter.
2. A negative control: an actual quota refusal STILL produces the quota lockout with its own expiry.
   A fix that just stops writing lockouts passes test 1 and breaks the real gate.
3. Mutation control, named in the suite header, applied INSIDE the changed function's body (a
   top-level line insert makes everything red for the wrong reason and reads as a pass). Show both
   colours with the run output.
4. CI selection, stateful: `rm -f "$(git rev-parse --git-dir)/leadv2-run-all-last-checked-sha"`,
   then `LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed`; capture to a FILE and
   grep it — do not pipe through `head`, which truncates evidence and reads as absence.
5. Run every suite that guards each file you touch (`# run-all-triggers:` headers). Baseline any red
   against clean main in a detached worktree before calling it a regression.
6. `tests/known-red-suites.txt` may only SHRINK.

`rc=0` means nothing — read the summary line; `rc=$?` after a pipe reads the LAST stage's status.
Derive every zero a second way.

## Report

`docs/handoff/CODEX-REFUSAL-MARKER-CARRIES-ITS-CAUSE-01/report.md`, under 80 lines: the caller
census, the marker format and why it is back-compatible, where transport strikes went, and all six
proofs with their output.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-d209d246" "<question>" \
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