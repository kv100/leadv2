# MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01 — the status panel lies three ways

**Repo to change: `~/Projects/leadv2` (the plugin).** This file lives in persona-engine only
because the lead dispatches from there. Work in `~/Projects/leadv2` on your lane branch.

Surface: `plugins/leadv2/scripts/leadv2-status-surface.sh` (+ its `.10s.sh` SwiftBar wrapper).

## Three defects, all observed live on 2026-08-04 (evidence, not theory)

### 1. Dead lanes render as active

The panel showed `active 3` — `81ec9717 opus now`, `c33073fd sonnet 12m`, `0db1da80 sonnet 38m` —
when exactly ONE was real. Both `0db1da80` and `c33073fd` had dead worker PIDs (`kill -0` fails),
were already merged and deployed, and **carry correct terminal rows** in
`~/.claude/leadv2-state/persona-engine/dispatch-ledger.jsonl`
(`task_sig=0db1da80 terminal=no_work`, `task_sig=c33073fd terminal=no_work`).

So the terminal ledger is right and the surface fails to honour it. `has_terminal` (:2850) matches
`sig8 in terminals` or `str(task_id) in terminal_task_ids`, but the ledger's `task_id` is the
HUMAN name (`M1A-FACT-QUALITY-01`) while the live-process branch carries a different key. Note
also that even a successful match only downgrades the row to `closing` (:2852) — it never drops
it, so a correct cross-ref alone would STILL show three lanes.

### 2. The lead's own session is counted as a lane

The panel rendered `active 1 b5c26011 opus now` while the only real worker was elsewhere.
`b5c26011` appears in NONE of the six ledgers under `~/.claude/cache/dispatch-ledger/` — it comes
from the live-process branch and is the lead session itself.

### 3. The panel is per-repo and hides work in another repo

Lane `6bbcca99` was actively writing files in `~/Projects/leadv2` while the panel, rendered from a
persona-engine cwd, read persona-engine's ledger and showed nothing. The founder's words: "в
свифтбаре уже не видно что идет работа".

## Required

1. A lane with an unexpired terminal row must not render as `active` — and a finished lane should
   leave the list, not linger as `closing` forever. Make the cross-ref work on the key the ledger
   actually stores; do not "fix" it by loosening the match to a substring.
2. Never count the lead session as a lane.
3. Either aggregate across the ledgers the operator is working in, or label the panel with the
   repo it is scoped to. Aggregating is preferred — a founder must not have to know which repo a
   worker lives in to see that it exists. If you aggregate, the repo must be visible per row.
4. **Names.** `81ec9717` is the first 8 chars of the mission-content signature. The human task
   name is in the SAME ledger row (`task_id`) and the phase is in the lane journal
   (`architect_prepass` -> `worker_spawned` -> `review_gate` -> `dispatch_terminal`). Render
   `<task_id> · <phase> · <arm> <age>` and fall back to the sig8 only when the name is genuinely
   unknown. Keep it inside the menu-bar width — truncate the name, never the state.

## Rules

- **bash 3.2** — macOS SwiftBar launches with a minimal environment; `test-status-surface-bash32.sh`
  exists precisely for this and must stay green.
- The panel must never print a confident `0` when its data source failed. There is an existing
  test for that (T4, "a dead renderer produces the failure title, never a confident 0/0") — keep
  it passing and extend the same principle to any new source you read.
- Shared tree: branch only, no commit to main, no push, no merge — the lead does that.
- `.env` READS only.

## Done means

- A test with a fixture ledger where a lane has a terminal row: it does not render as active.
- A test proving the lead's own session is excluded.
- A test proving a lane in a second repo's ledger is visible (or, if you chose labelling, that the
  panel names its scope).
- A test proving a named lane renders its name and phase, and an unnamed one falls back to sig8.
- `bash -n` + `/bin/bash 3.2 -n` clean; run `test-status-surface-bash32.sh` and paste it in full.
- Do NOT run the whole `run-core-offline.sh` aggregate — it takes ~10 minutes and has eaten a
  previous worker's entire budget. Run the status-surface suites only.

## Attempt 2 note (lead, 2026-08-04T15:50Z)

Attempt 1 (lane `b0370efc`, arm glm) produced NOTHING — no stream file, byte-clean worktree —
and was then mislabelled `dead / e2e_regression` by a gate that ran the e2e suite over an empty
lane. Nothing about the mission changed; do not treat the previous death as a signal about the
work. This attempt excludes glm.

Reminder of the one budget rule that killed an earlier worker on a different mission: run the
status-surface suites ONLY. Do not run `run-core-offline.sh` — it takes ~10 minutes and will eat
your entire budget before you have edited anything.
