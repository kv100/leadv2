# REVIEWER-CHOICE-MUST-EXPLAIN-ITSELF-AND-FABLE-IS-NOT-THE-DEFAULT-01

Founder, 2026-09-14, two rulings. Take both verbatim; the second replaces a wrong rationale the lead
wrote into this row earlier.

1. *«fable слишком дорогой как ревьюер… сделай так, чтобы fable был не всегда ревьюером, а чтобы
   арбитр понимал почему и когда кого брать как ревью»*.
2. *«фейбл ок и для размышления и для ревью, но только для реально сложных и важных задач»*.

## Part 1 — the instrument. The decision cannot be explained by its own record.

Measured on `dispatch-d86e24e8`, the line the arbiter wrote:

```
route_resolved by=arbiter role=reviewer arm=fable reason=cheapest_capable
  util_glm=83 util_codex=18 util_claude=56
  headroom_priced=codex:0.268396,glm:0.24867
```

**The winning arm is absent from its own decision record.** Cause, one line —
`lib/leadv2-route-arbiter.sh:1862`:

```python
if _w != 1.0: _headroom_priced[_lbl]=_w
```

An arm whose headroom weight is exactly 1.0 is never written, so the arm that won is systematically
invisible while the arms that lost are listed with their weights. Three fable reviews happened today
and not one of them can be explained from the journal.

Fix that first. It is the precondition for the rest: a policy you cannot audit is a policy you
cannot trust.

## Part 2 — the policy

**fable is not the default reviewer.** It is allowed on genuinely hard / important work — the
founder's words — and on reviewing the output of strong arms (opus, codex-sol, astra). On ordinary
work authored by sonnet / glm / terra, the reviewer comes from the cheaper capable set, **preferring
a DIFFERENT VENDOR**.

### Do not repeat the lead's error here

The lead argued in chat that swapping fable→opus "changes nothing because both are Anthropic". That
is **wrong**, and the founder corrected it. `lib/leadv2-route-arbiter.sh` (~:775-795, contract 0485)
states it plainly:

> "The SHARED session window (five_hour) stays in the set — an arm scoped on the weekly group still
> burns the account session window; a fix that freed it from five_hour would be wrong."

So fable's scoped meter **replaces only the account WEEKLY aggregate** for that arm; the shared
`five_hour` window stays. fable drains both. It is not an isolated bucket, and routing work to it
does not spare the shared Anthropic window. Measured the same day in repo `leadv2`, hourly max — the
two meters move together:

```
hour       00   01   08   09   10   11
fable      15   17   21   28   58   56
claude     17   18   22   28   84   56     <- shared window
```

Express the policy as matrix rows / a declared axis, never as an `if arm == "fable"` branch
(`ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01`). "Genuinely hard and important" has to become
something the arbiter can evaluate — class, protected flag, subsystem count, whatever you can defend
— and you must say in the report which signal you chose to stand for it and why.

## Known context — take as given, do not re-derive

- `DEFAULT_REVIEW_EXCLUSIONS = ["glm", "glm-flash", "freepool"]`
  (`lib/leadv2-glm-policy-resolve.py:77`): glm family never reviews. So "why not glm" is not a
  question. A sibling row (`dc241a745d89`) owns a measured contradiction with this list; ignore it
  here.
- The standing review rule, pinned verbatim: *a review is valid when the reviewer is a different
  vendor from the author, OR the reviewer's `capability` is strictly greater. Everything else
  refuses.* That rule landed today (`0921a034`) and is NOT up for revision — you are adding a
  preference ORDER underneath it, not changing what is legal.
- Capability order (founder ruling, load-bearing, do not renumber): 6 astra/fable · 5 codex-sol/sol/
  opus · 4 glm/terra/sonnet · 3 luna · 2 haiku/glm-flash/freepool.
- One of today's three fable reviews is already explained: `util_codex=unknown_capped` — the codex
  quota reader was dead, codex was demoted, fable won by default. That instrument is fixed
  (`cf38b366d94d`). The other two are not explained, and Part 1 is why.

## Acceptance

1. The reviewer decision record names **every candidate with its weight, including the winner**, and
   a refusal reason for each arm dropped. Show the before/after line verbatim.
2. Two live resolves: author=sonnet yields a **non-fable** reviewer; author=opus/sol/astra (or a
   task carrying whatever signal you chose for "hard and important") yields fable.
3. **Negative control, run it:** removing the new policy returns fable on the author=sonnet case. A
   preference you cannot demonstrate collapsing did not happen.
4. New suite registered so `tests/run-all.sh --scope changed` SELECTS it.

## Off limits

- `capability` numbers · `router_v2.cost` · the class→arm think tiering (`2a715fc3`).
- The findings-extraction path — sibling row `dc241a745d89`.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
