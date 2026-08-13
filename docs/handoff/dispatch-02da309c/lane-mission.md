# STATUS-SURFACE-SHOWS-STALE-TRUTH-01 — the founder's menu bar is lying again

## Where you work

Edit ONLY in `/Users/kostiantyn.vlasenko/Projects/leadv2` — the single source for plugin code.
A project's copy is a symlink to it; **never** create a real copy of a plugin-owned file inside
`~/Projects/persona-engine`. Target: `plugins/leadv2/scripts/leadv2-status-surface.sh` and its
`leadv2-status-surface.5s.sh` entry point. (This mission file lives in persona-engine only because a
scope guard blocks writing it into the plugin repo — the *code* still belongs in `~/Projects/leadv2`.)

## The symptom

The SwiftBar plugin shows:

```
🛠 Round 2 sonnet (7s)
Round 2 · ~ · sonnet 1h · persona-engine
```

No lane is running. All three dispatch signatures — `faf16de3`, `672e870b`, `015f655a` — finished
hours ago and carry terminal records in `~/.claude/leadv2-state/persona-engine/dispatch-ledger.jsonl`
(`landed` @15:52Z, `dead` @16:47Z, `dead` @16:58Z). `active.yaml` is `sessions: []`. Nothing is alive.

## Confirm or refute this lead FIRST, at runtime

A prior read found `~/.claude/cache/status-surface/all.payload` stale past its 8s TTL, with a
refresh in flight whose `all.payload.tmp` was **zero bytes**. A zero-byte tmp is never promoted, so
the previous payload survives — and the bar renders hours-old state as current, forever, with no
visible sign it is frozen.

That is a hypothesis, not a finding. **Prove the mechanism before writing any fix.** Run the refresh
path by hand, watch the tmp file, and establish why it emits nothing — a crash mid-render, a `set -e`
exit, a subshell whose stdout goes elsewhere, or a legitimately empty result. **Read stderr first**;
do not theorise from code. If stderr is swallowed, re-run with it visible — silent failure and silent
success are indistinguishable from the artifact alone.

If the real mechanism differs from this lead, fix the real one and say so plainly. Do not bend the
evidence toward the hypothesis you were handed.

## What to fix

1. **The refresh must not fail silently.** Whatever makes it emit nothing, fix that cause.

2. **A stale payload must never be presented as current.** This is the part that matters most, and it
   must hold for failure modes nobody has thought of yet. If the payload is older than a threshold
   you pick and justify (refresh interval 5s, TTL 8s), the bar says so in its own title — a distinct
   icon plus e.g. `stale 3h`. A frozen bar that looks healthy is worse than one that admits it is
   blind. Same lying-green disease we have been killing all week.

3. **A lane with a terminal record in the ledger must never render as live**, whatever the
   reservation files say. If the renderer only consults terminal records for rows found in
   reservations, a row that outlived its reservation escapes the check entirely. Make the ledger's
   terminal record authoritative.

## Discipline — non-negotiable

- Every fix carries a test, and you must **show the test failing against pre-fix code**, transcript
  pasted. A test you cannot make go red proves nothing — twice this week a test written to prove a
  fix compared the new code against a copy of itself.
- Verify by running the actual plugin and pasting its raw output **before and after**. Code-reading
  makes hypotheses; runtime confirms.
- `bash -n` + `shellcheck -S warning` clean on every shell file touched; no syntax errors in Python.
- Stage explicit paths. **Never `git add -A`** — three lanes today would have silently reverted a
  shared doc that way.
- Commit in `~/Projects/leadv2` with a `fix:` message naming the mechanism, not the symptom.
- Do **not** sub-delegate. You are judged by the diff on disk when your turn ends. If your first
  Read is denied, retry — that gate denies once, then permits.

## Report

The proven mechanism with its runtime evidence, what changed, the red-before transcript, the
plugin's raw output before and after, and anything you chose not to fix and why.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-02da309c" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.