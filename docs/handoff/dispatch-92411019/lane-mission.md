# WRITESET-PENDING-BLOCKS-WITHOUT-ANY-OVERLAP-01 — a lane with no declared writes blocks everything

Repo: `~/Projects/leadv2` (shared plugin tree). Founder standing permission is recorded at
`persona-engine/.claude/leadv2-overrides/extensions.md:748`; the approved scope is this task only.
Anything wider — stop and ask.

## The behaviour, measured

`leadv2-active-registry.sh:388-400`: when an incumbent row has **no write set** and is still inside
`_lv2_ws_pending()`'s window (`LEADV2_WRITESET_PENDING_WINDOW_SEC`, default 900 s), register exits 5
**before comparing a single path**. Two leads have each lost a round to this today, and two of the
other lead's lanes stood blocked with **zero files in common** with the incumbent.

Worse instances, both observed 2026-09-04:
- an orphan row `04040e45` with `pid=None` and `writes=None` blocked every dispatch until it was
  removed by hand;
- a row recreated every couple of minutes never ages out at all, because recreation resets
  `started_at` — the window is real in the code and unreachable in practice.

## Read this before you "fix" it — the check is not simply wrong

**Do not delete the branch and do not shorten the window.** An incumbent that has declared no write
set is genuinely *unknown*, not *harmless*: we cannot prove disjointness against an unknown set, and
the window exists to close a real race where two lanes declare their sets at the same moment. Removing
it converts a loud refusal into a silent double-write, which is strictly worse — that is the same
trade this codebase has already lost several times (see the standing note about a green suite CI
never runs).

The defect is not the fail-closed rule. It is that **rows with no write set exist at all, routinely**,
so a branch meant for a rare race fires as the normal case. Attack that, in this order:

1. **Find who creates a row without a write set.** Enumerate the call sites of
   `leadv2_active_register` (there are at least two in `leadv2-dispatch-code.sh`, plus a duplicate
   definition of the function itself in `leadv2-helpers.sh:1441` beside
   `leadv2-active-registry.sh:899`) and any recovery/orphan path that recreates rows. Report each
   with file:line and say whether it *can* know the lane's writes at that moment.
2. **Make every creator that can declare, declare.** A lane that knows its write set must never land
   a row without one.
3. **For a creator that genuinely cannot know** (a recovery attaching to an existing process, say),
   keep fail-closed but make it *legible*: the row must record why it has no set, and the refusal
   must say so. Thanks to `WRITESET-REFUSAL-NEVER-NAMES-THE-BLOCKER-01` (merged today) the refusal
   already prints `blocked_by=<task_id> age_s=<n> window_s=<n>` — extend that, do not replace it.
4. **Only then** consider whether the window's clock should be immune to recreation (an
   `first_seen_at` that recreation does not reset). Argue it in the commit body if you do it.

## Acceptance — behavioural, with a negative control

1. **The routine case stops firing.** Show a dispatch that previously refused now proceeding, and
   name which creator you taught to declare.
2. **The race case still refuses.** Construct an incumbent that genuinely cannot declare, and show
   the refusal still happens and now says why. A fix that makes everything pass has removed a
   guard, not repaired it.
3. **Negative control, mandatory, inside a suite** — not a hand demonstration. Anchor the mutation
   by regexp inside the function body, record `anchor= baseline_rc= mutated_rc= red_line=` under
   `mutation-control/`. A hand demo is worth nothing: it was exactly the objection that sent
   `DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01` back for another round today.
4. **`# run-all-triggers:` header** naming `leadv2-active-registry.sh`, and a selection proof taken
   by touching a **production** file — never the suite itself, which is dirty and would select by
   its own filename. Use `LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed`.

## Constraints and traps (all measured today — do not re-derive)

- **Never run the full `tests/run-all.sh` in a live checkout.** It redirects five control-plane
  symlinks into a temp dir and deletes their targets. `SELECT_ONLY=1` always.
- **After any `git merge`:** `find docs/leadv2 -maxdepth 1 -type l | wc -l` must be **16**.
- **Never `git add -A`.** This checkout carries other sessions' live control-plane files
  (`docs/leadv2/bus.jsonl`, locks) and foreign `docs/handoff/*/phases.d/*.yaml`. Stage by path.
- **Silence kills you:** `STALL_KILL idle_s=1822 limit_s=1800` — print a line to stdout at least
  every 10 minutes. A worker that goes off to wait for its own background run is a dead worker;
  background completions wake the lead, not you.
- **Touch a file outside your declared write set and the guard commits NOTHING**
  (`foreign_dirty=undeclared_lane_writes` → `auto_committed=0`). Declare wide enough up front.
- A `no_work` verdict is not evidence your branch is empty — check `git diff --stat main...HEAD`
  before believing it (9 of 14 such verdicts were false in today's census).

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-92411019" "<question>" \
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