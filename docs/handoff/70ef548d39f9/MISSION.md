# A-DEAD-INSTRUMENT-MUST-ANNOUNCE-ITSELF-01

Founder, 2026-09-14, after losing half a day to it: *«но если надо делать релогин, мб пускай статус
лайн говорит про это?»*. He is right, and the cost was not cosmetic — see below.

## Measured

The codex quota reader was returning, for ~12 hours:

```text
codex: status = "unknown"   error = "refresh http 401"   fetched_at = <fresh>
```

The token refresh on the **read** path was rejected. The **work** path was fine the whole time: a
lane ran 917s on `gpt-5.6-terra` and recorded its result during the outage. So this is the classic
pair — the instrument was dead, the provider was not.

**What the human saw:** `cx ~90%·wk/5d15h 12h15m old`. **What was true:** 17%.

That gap is not staleness. Immediately after the founder re-ran `codex login`:

```text
codex: status = ok   error = None
route decision: util_codex = 17   reset_codex = 122.21h_live
```

At the time of the displayed reading the same window had 5d15h (135h) to reset; now it has 122.21h.
The difference is the 12h15m of staleness, so **no reset happened in between** — and consumption
inside a window never decreases. Therefore `~90%` was never a measurement. It is the
unknown-fallback surfacing as a plain number: `util()` returns `pct=100.0` **with `unknown=True`**
when a provider's probe does not answer (`lib/leadv2-route-arbiter.sh:1110-1124`), and that flag
does not reach the display.

**The cost:** for ~12 hours the arbiter demoted codex believing it 90% burned when it was at 17%.
The demotion path itself is correct and deliberate — after the 2026-09-04/05 incident
(`util_codex=unknown_capped` in 122 of 143 decisions, six lanes killed by
`reason=all_arms_capped`) unknown was made a THIRD state that demotes rather than excludes. The
defect is upstream of that: nothing tells a human the instrument needs their hands.

## What to build

1. **A dead instrument must be visibly dead, not plausibly alive.** Wherever a provider's reading is
   rendered for a human — status line first, but find every surface — an `unknown` reading must be
   distinguishable at a glance from a measured one. A number the reader did not measure must never
   be printed as if it were measured. Decide the rendering yourself; the binding requirement is that
   a person glancing at it cannot mistake the two.
2. **When the remedy is a human action, name the action.** This outage needed exactly one thing:
   `codex login`. A reading that says only "unknown" still leaves the founder guessing. If the
   error class identifies a remedy (401 on refresh → re-login for that provider), the surface should
   say so. Where it does not, say "unknown" and do not invent a cause.
3. **Do not let it depend on someone looking.** Twelve hours passed because nobody read the line.
   Decide, and justify with what the repo already has, whether this warrants an active signal (the
   existing pulse/journal seam is the obvious candidate — `leadv2-journal.sh` already carries
   decision events, and the launcher-refusal work landed 2026-09-14 made exactly this kind of
   invisible fact into a journal event). Do not build a new notification mechanism if an existing
   seam carries it.

## Method — binding

- **Negative control, run it:** force the reader into `status=unknown` (a fixture, not a real
  logout) and show the human-facing surface changing. Then show a healthy reading rendering
  normally. A change you cannot demonstrate flipping is not demonstrated.
- The three states must stay three: measured, unknown, and genuinely-exhausted. A fix that renders
  unknown and exhausted identically has moved the bug, not removed it.
- **Never print a token, key, or session value.** Probes report HTTP status and error class only.
- Name the surface of every count.

## Acceptance

1. An `unknown` provider reading is visually distinguishable from a measured one on every
   human-facing surface you found; list the surfaces you checked, including any you decided not to
   change and why.
2. A 401-on-refresh names its remedy.
3. Negative control run both ways: forced-unknown flips the surface, healthy reading renders
   normally.
4. Exhausted and unknown remain distinguishable from each other.
5. New suite registered so `tests/run-all.sh --scope changed` SELECTS it.
6. Still green: `test-arbiter-prices-by-provider.sh`, `test-reset-urgency.sh`,
   `test-arbiter-decision-record-inputs.sh`, `test-launcher-refusal-event.sh`,
   `test-leadv2-task-judge.sh`, `test-codex-drain-fit.sh`, `test-codex-lane-token-total.sh`.

## Off limits

- The demotion logic itself (`UNKNOWN_PROBE_PENALTY` and the third-state handling) — it is correct
  and was paid for by an incident. This lane changes what a HUMAN sees, not how the arbiter ranks.
- `router_v2.cost`.
- Anything that would make a failed reading look successful to the arbiter.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
