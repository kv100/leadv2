# FIVE-HOUR-WINDOW-NEVER-ENTERS-THE-ACCOUNT-CHOICE-01

Row `7ea4fed65451`. Founder order 2026-09-16. Standing rules:
`docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md` — read them before you start.

## The founder's order, in his words and then in ours

> "я ставил задачу мол когда сброс лимита скоро, надо использовать квоту по максимум,
>  но я говорил лишь про недельную квоту, а не про квоту 5 часов"

The "burn it when the reset is near" rule was ordered for the **weekly** window only. It must not
govern the **five-hour** window. The five-hour window is what decides how much work an account can
actually absorb in the next hour, and it must be compared as a **reserve** (how much is left), never
as a rate (how much is left per hour until it resets).

The same order carries a scope: "это тот фикс который должен работать и тут и там и везде где плагин
есть". That is satisfied by fixing once in `~/Projects/leadv2` — one inode, commit to main IS the
deploy. Do not copy anything into a consuming repo.

## The mechanism, measured — not inferred

Three sites, read them before touching anything:

| # | Site | What it does |
|---|---|---|
| 1 | `plugins/leadv2/scripts/leadv2-quota-read.py:167-169` | `usable_now = remaining_pct / max(hours_to_reset, 1.0)` |
| 2 | `plugins/leadv2/scripts/leadv2-quota-read.py:181-186` | `binding_window()` returns the window with the **lowest** `usable_now` |
| 3 | `plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py:149-157` | ranks accounts by **that** window's `usable_now`, highest first |

Because site 1 divides by hours-to-reset, `usable_now` is **not commensurable between windows of
different length**: for the same remaining percentage the 168-hour weekly figure is roughly 33× smaller
than the 5-hour figure. Site 2 then takes the minimum, so the binding window is `seven_day` in
essentially every normal state, and the five-hour window never reaches the comparison at site 3.

Measured hermetically by the lead 2026-09-16 against the picker (a pure module: stdin only, no env,
no filesystem, no network), using the weekly percentages read live from both accounts today:

```
personal: 5h=20% left   weekly=79% left (usable 1.317)  binding=seven_day
work    : 5h=95% left   weekly=96% left (usable 0.627)  binding=seven_day
picker -> profile=personal  reason=binding_window  binding=seven_day:usable_now=1.317
```

`work` has nearly five times the five-hour budget and loses, because the five-hour numbers were never
compared. That is the founder's complaint, reproduced.

**Second defect, same root.** When the five-hour window *does* become binding — which happens only
once it is nearly empty, since only then does its inflated figure fall below the weekly one — the
picker compares one account's **five-hour** rate against another account's **weekly** rate:

```
personal: 5h=2% left  -> binding=five_hour  usable 0.50
work    : 5h=99% left -> binding=seven_day  usable 0.627
picker -> profile=work
```

It returned the right account here, but not by a correct comparison — 0.50 against 0.627 is a
five-hour rate against a 168-hour rate. Two different quantities were ranked against each other and
the answer happened to land. Do not treat that run as evidence the path works.

## What the fix must establish

1. The weekly window keeps the rate metric. The near-reset burn rule is the founder's, it stays.
2. The five-hour window is compared as a **reserve** — remaining percentage, not divided by
   hours-to-reset.
3. Accounts are **never ranked against each other on different windows**. Either compare the same
   window across all candidates, or gate on the five-hour reserve first and use the weekly rate as
   the tiebreak. Choose one and say in the report why, with the losing option named.
4. `SELECTOR-SKIPS-EXHAUSTED-01` at `leadv2-claude-profile-select.sh:705-748` reads `binding_window`
   for the same purpose. Whatever you change about the meaning of `binding_window` must be correct
   there too, or an account will be wrongly declared exhausted. Check it; do not assume.
5. `SELF-SLOT-DEMOTION-YIELDS-01` (the demote-yield margin, `leadv2-claude-profile-pick.py`, founder
   2026-09-12) compares a margin against `usable_now`. If the ranked quantity changes units, that
   margin's threshold changes meaning. Either keep its units intact or restate the threshold and say
   so explicitly — silently rescaling a founder-set margin is not allowed.

## Acceptance (red at dispatch, rc=1 measured 2026-09-16)

The row carries it. It builds two records, pipes them into
`lib/leadv2-claude-profile-pick.py`, and requires `profile=work` for the founder's case above.
It is hermetic and gives the same verdict on any machine.

## Controls — one per independent claim

- **Write the suite.** `plugins/leadv2/scripts/tests/test-five-hour-window-ranks-by-reserve-01.sh`,
  in the house style of the existing suites (`pass=N fail=N`, per-case PASS/FAIL, exit 1 on failure).
  It must cover the reserve case AND the cross-window case, and it must carry a **passing control** —
  a case today's code already answers correctly, e.g. two accounts both binding on `seven_day` where
  the higher `usable_now` wins (verified green by the lead). Without it an all-green run cannot be
  distinguished from a harness that stopped asserting.
- **Do not regress the existing guards.** Run and report, by name and count:
  `test-claude-profile-select.sh`, `test-claude-profile-requested.sh`,
  `test-profile-select-skips-exhausted.sh`, `test-quota-weekly-live.sh`, `test-quota-weekly-total.sh`,
  `test-quota-unknown-surfaces.sh`, `nc-claude-profile-select.sh`. If one was already red before your
  change, say so with the before/after, do not absorb it.
- The lane-rules prohibition is in force: never make a suite green by deleting an assertion,
  loosening a grep, or adding `|| true`.

## Write set — FILES, never directories

```
plugins/leadv2/scripts/leadv2-quota-read.py
plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py
plugins/leadv2/scripts/leadv2-claude-profile-select.sh
plugins/leadv2/scripts/tests/test-five-hour-window-ranks-by-reserve-01.sh
docs/handoff/FIVE-HOUR-WINDOW-NEVER-ENTERS-THE-ACCOUNT-CHOICE-01/report.md
```

It cannot be widened after dispatch. If the fix needs a file outside this list, stop and say so in
the report rather than reaching for it.

## Report

`docs/handoff/FIVE-HOUR-WINDOW-NEVER-ENTERS-THE-ACCOUNT-CHOICE-01/report.md`. It must carry: which
of the two designs in point 3 you chose and what you rejected; the before/after picker output for
both measured cases above; the suite's `pass=N fail=N`; the named counts for every regression suite
listed; and what you did about points 4 and 5. Every number carries its boundary — how many, of how
many, on which platform, from which commit.

## Not in scope

The architect-prepass classifier defects found the same day (`leadv2-dispatch-code.sh:5672` raw-text
`rate_limit` matching the event *name*, and `:5724` quote-blind `status:allowed` parsing), and the
hardcoded `codex|glm` fallback ladder at `:6036-6038`. Separate rows. Do not touch them here.
