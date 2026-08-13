# Re-dispatching a lane whose terminal is already recorded silently does nothing

Repo for this lane: **`/Users/kostiantyn.vlasenko/Projects/leadv2`**. All edits land there.

## The defect

Re-dispatching a round-2 mission for a lane that already had a terminal recorded resolved to the
**same** task id (`466b8998`) and produced:

```
review_gate status=dedup diff=a80247f7
dispatch_terminal_dedup task=466b8998 attempted=dead reason=terminal_already_recorded
dispatch_terminal_dedup task=466b8998 attempted=dead reason=terminal_already_recorded
```

No worker output, no new diff, no error, exit code 0. From the outside this is indistinguishable
from "a lane ran and changed nothing" — which is exactly how it was first misdiagnosed as a worker
that did no work. The round was lost. Round 3 only got a fresh id (`644424d1`) because the mission
file had been rewritten enough to change its signature.

## What to build

A re-dispatch against a task whose terminal is already recorded must do one of two things, never
the current silent third:

1. **Refuse loudly** — non-zero exit, one journal line naming the recorded terminal, its cause and
   its timestamp, and a message on stderr telling the operator how to proceed. Or
2. **Re-open deliberately** — clear the recorded terminal and run, but only behind an explicit
   opt-in (a flag or an argument), and journal that the terminal was cleared and by what.

Pick one and say why in the commit message. Whichever you pick, the failure mode being removed is
"returns 0, does nothing, says nothing".

Related and worth reading while you are in here: the dedup fires on the **diff hash**, so a lane
whose fix genuinely produces the same diff also lands here. The message must distinguish "you
re-ran an already-finished task" from "your new work produced an identical diff" — they need
different operator responses.

## Tests

- Re-dispatch of a task with a recorded terminal: assert non-zero exit (or the explicit re-open
  path if that is the design), and assert the journal line names the prior terminal and cause.
  **Show it RED against the current dispatcher** — today it exits 0 silently.
- A first dispatch of a fresh task is unaffected: same exit code and same journal shape as now.
- If you implement the re-open path, a test that without the opt-in it still refuses.

## Proof required

- Each test RED against the pre-fix file, then green, pasted.
- One real re-dispatch showing the new behaviour, journal lines verbatim.

## Hard limits

- Do not change how task ids are derived from the mission text — that is a separate concern and
  changing it would invalidate the prepass cache.
- Three suites are red on untouched `main` and are not yours: `run-core-offline.sh` (rc=124 at
  600s, two codex-lifecycle assertions). Say so if a gate blocks you on one.
- Never `git add -A` from the lane worktree; stage your paths explicitly.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-f41dfb1b" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.