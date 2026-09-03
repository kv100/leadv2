# NUDGE-TAX-01 — two hooks are 95% of all hook traffic and ~147K injected tokens a day

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- **Commit after every step.** Rounds died today with work uncommitted.
- Suite path is `tests/run-all.sh` at the repo **ROOT**. Do NOT open this round with a full suite
  run — a sibling round burned three hours that way and committed nothing. Prove your change
  granularly first; run the suite at the end.

**Class:** Standard. **Repo:** leadv2 plugin.

## The measurement

Ten-day transcript window (2026-08-23 → 2026-09-02, 3,631 `.jsonl`, all repos), counted on
`"stderr":"[leadv2-<hook>]` anchored at field start — not a substring grep, because several hooks
contain their own bracketed tag as a literal and any transcript that merely *read* the source would
otherwise count as a fire:

| hook | fires/10d | fires/day |
|---|---|---|
| `leadv2-lead-delegation-nudge` | 38,724 | ~3,872 |
| `leadv2-loop-detect` | 19,894 | ~1,989 |
| everything else combined | ~2,900 | ~290 |

Those two are **95% of all measured hook traffic**. At ~38 tokens per injected message the nudge
alone is **~147,000 tokens per day**, and because every injected message re-enters the conversation
on every later turn, that cost is paid again on each subsequent turn of a long session.

Measured latency of the shared pre-dispatch path, by hand-invoking `leadv2-bash-pre-dispatch.sh`:
**~335 ms** for a plain command (2 ALWAYS guards), **~1.0 s** for `git commit` (6 guards). Every
Bash call pays it.

## The argument you must engage with

A message that fires 3,872 times a day is not changing behaviour — it is a tax. Either the condition
it detects is genuinely occurring 3,872 times a day (in which case the *system* is wrong, not the
lead, and the nudge is reporting a design failure it cannot fix by repeating itself), or the
condition is over-broad. Find out which, with numbers, before you change anything.

## Deliver

1. **Characterise the fires.** How many are distinct situations versus the same situation re-fired
   within one turn or one session? Group them. The answer decides the fix: dedupe if it is the same
   situation repeating, tighten the predicate if the predicate is wrong. Do not guess.
2. **Fix accordingly — and keep the signal.** The goal is not silence. Whatever remains must still
   fire on the case the hook was built for. Prove that case still fires after your change.
3. **A firing budget.** Whatever mechanism you choose, express it so it cannot regress silently:
   the hook fires at most N times per session/phase, and something fails if it exceeds that.
   Choose N from your measurement in item 1, not from a round number.
4. **Do the same for `loop-detect`**, or state with evidence why it needs no change.
5. **Report the projected new daily token cost** against the ~147K baseline, from the same counting
   method. A number, not an adjective.

## Prove it
- Reproduce the current firing rate on a captured sample → paste it.
- After the change, the same sample → paste the new count.
- The case the hook exists for still fires → paste it. **This is the one that matters**; a nudge
  that has gone quiet by ceasing to work is a regression dressed as a win.
- **Negative control:** remove your dedupe/predicate in a mktemp FULL copy of the tree whose
  baseline is proven green → the "fires at most N" check goes red. Paste baseline and mutant runs.
  Insert the mutation INSIDE the function body; a top-level insert makes everything red for the
  wrong reason and reads as a pass.
- `tests/run-all.sh --scope changed` from the LANE ROOT at the END, FOREGROUND, `timeout 1800`.
  Paste the real tail. A placeholder token where run output belongs fails this round outright.

## Note on the known-red list
`run-all.sh` now applies `tests/known-red-suites.txt` to granular nested suite names (landed on the
CI lane). If an allow-listed suite still blocks you, say so — that is a gap in the plumbing and
worth more than this round.

## Out of scope
Deleting dead hooks (`DEAD-HOOKS-DELETE-01`), the promise-guard blind spot, the watcher leak.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only.

## Done when
The fires are characterised with numbers; the change is proven to cut the rate on a real sample; the
hook's own case still fires; the budget check exists and its negative control is red against a green
baseline; the projected daily token cost is in the report.
