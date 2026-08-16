# MISSION — PULSE-IS-A-PLUGIN-DUTY-01: the pulse must belong to the plugin, not to a session cron

Plugin repo: `/Users/kostiantyn.vlasenko/Projects/leadv2`. This is track 5.6–5.8, founder-raised and
never advanced.

Today the founder's 30-minute status pulse exists as a **session cron job**: created inside one
`/leadv2` session, held in that session's memory, and **gone the moment the session ends**. Every
session therefore re-invents it, and a session that forgets goes silent without anyone noticing —
the founder finds out from the absence of messages, which is the worst possible detector.

It is also an exception to PULSE MODE: the lead is told to stay silent between phases, and separately
told to emit a pulse. Two rules that contradict each other get resolved by whoever reads them last.

## What to build

Make the pulse a **duty of the plugin**, so it exists because `/leadv2` is running, not because some
session remembered to schedule it:

1. **Ownership** — the cadence, the content contract (one lane table + at most 3 lines), and the rule
   that a pulse *dispatches before it reports* live in the plugin, in one place.
2. **Survival** — it must survive a compact and a session restart. State plainly which failure modes
   it now survives and which it does not (a killed terminal? a reboot?). Never claim survival you
   have not demonstrated.
3. **Reconciliation with PULSE MODE** — express the pulse as a scheduled duty with its own output
   contract, distinct from the narration ban, so it stops being an exception.

## Deliberately not in scope
- Do not change what a pulse *says* — the table shape and the 3-line limit are the founder's and are
  settled.
- Do not build a daemon that runs with no session open: the pulse reports on lanes, and with no
  session there are no lanes. If the requirement implies one, say so rather than building it.

## How to prove it

A test that the duty survives the transition it exists to survive, plus a demonstration you actually
ran — not "this should now persist". If a session-scoped mechanism genuinely cannot survive a session
ending, deliver the smallest design that gets closest and state the residual gap plainly.

## Hard constraints
- Never `reset --hard`, `clean`, or `stash` — three live repos share this tree.
- Do not touch `docs/leadv2/open-threads.md`.
- Re-`git diff` immediately before you `git add`.

## Deliverable
The implementation, its test, and `docs/handoff/PULSE-IS-A-PLUGIN-DUTY-01/report.md` naming which
failure modes are covered and which remain. End with DELIVERABLE_COMPLETE.
