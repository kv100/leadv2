# assessment-claude.md — the lead's independent assessment

Written 2026-09-03 before reading `assessment-codex.md` or `assessment-glm.md`; neither existed when
this was committed.

## The bias line, first, because the founder asked for it

**My recommendation moves money away from Anthropic.** It says: do not renew Max 20x, buy one Max 5x
instead, and spend the freed $100 on Codex. I am Anthropic's model. I am putting this at the top so
the founder can check the rest against it rather than take my word for the disclosure.

## The premise needs correcting, and this is the whole answer

The founder's stated pain is the 5-hour window: «не хочу упираться в 5 часовой лимит клода как
орекстратора». **Our own live probe says the 5-hour window is not what binds us.**

From `~/.claude/burn/history.db`, table `kv`, key `rate_limit_anthropic`, captured
2026-09-03T15:26Z (epoch 1788444418):

    account_label:  max_20x
    five_hour_pct:  16.0     five_hour_reset:  2026-09-03T14:49:59Z
    seven_day_pct:  41.0     seven_day_reset:  2026-09-04T21:59:59Z
    binding_window: "seven_day"
    overageStatus:  normal

The probe names the binding window itself, and it is the **weekly** one — 41% consumed against 16%
on the 5-hour. The weekly window is 2.5× further along than the one the founder is worried about.

**Caveat, stated plainly: this is ONE sample.** I looked for a history of this field and there is
none — `kv` holds a single current row, and the strings I first found in the freepool journals turned
out to be source code, not probe samples. So the correct status of "our binding window is weekly" is
*measured once, today, and consistent with the burn table*, not *established over time*. See the
deliverable at the end.

## Why that single fact decides the purchase

The Reddit thread the founder pointed at (`1w38v98`, 2026-08-31, 1 690 upvotes) claims, consistently
across several commenters and with no official Anthropic source cited by anyone:

- Max 20x multiplies the **5-hour** window by 20×.
- It multiplies the **weekly** allowance by only about **1.7–2×** over Max 5x.
- Therefore two Max 5x subscriptions ($100 + $100) yield **more weekly** capacity than one Max 20x
  ($200) — "2.0x instead of 1.7x for the same price".
- One commenter reports running two Max 5x on the same card and name with no enforcement action.
- A separate claim, same thread: Max 20x charges *more* weekly budget per Fable token than Max 5x
  does, giving 20x only ~1.5× the Fable usage of 5x.

**This is community observation, not vendor documentation.** Multiple commenters note the numbers
are not in Anthropic's docs, which is itself the reason three of us are assessing this. Treat the
1.7× as the thing to verify, not as a fact.

But if it is even roughly right, then combined with our own probe:

| option | founder's cost | 5-hour capacity | weekly capacity |
|---|---|---|---|
| Max 20x (today) | **$200** | 20× — the window we sit at 16% of | ~1.7× |
| employer's Max 5x + his own Max 5x | **$100** | 5× per account, **does not combine within one session** | **2.0×** |

He is buying a 20× multiplier on the window he is not hitting, and paying twice as much for less of
the window he is hitting. The employer's free Max 5x is what makes this lopsided: he needs to buy
**one** $100 seat, not two, to reach 2.0× weekly.

## The honest catch, and it is real

Two accounts do **not** raise a single session's 5-hour ceiling. They are two separate buckets. So:

- If our binding window is weekly → two Max 5x wins clearly, and the 20× is money for nothing.
- If the binding window is ever the 5-hour one during a long orchestrator session → only Max 20x
  raises that ceiling, and two accounts help only if work is *routed* across them mid-session.

Our one sample says weekly. The founder's felt experience says 5-hour. **Both can be true**: a lead
session can wall on the 5-hour window on a bad afternoon while the weekly window is what actually
runs out over the month. That is precisely why this needs recording rather than one probe.

## Moving the lead to Codex — answering it separately

The founder's own alternative is «перейду в кодекс как лид так как там нет 5 часового окна».

The lead is now a thin router (today's `LEAD-IS-OPUS-THINK-IS-FABLE-01` decision) — it talks to the
founder, classifies, dispatches, adjudicates. Volume lives in the workers. So moving the lead off
Claude removes Claude's *interactive* burn but not the workers', and the workers are the larger
number: on 2026-08-23, 1.23B of that day's 1.81B was headless (87 developer + 104 critic + 111
architect sessions).

Two things I cannot answer from evidence and will not guess at:

- Whether Codex-as-lead is *good* at this job. We have never run it as the primary interactive lead
  for a full session. `/leadv2 codex` exists as a thin-relay mode; it is not the same thing.
- Whether Codex's $100 tier has a weekly cap of its own. One commenter posted an OpenAI reply about
  Codex 20x as an image; I cannot read it. **Not established.**

## Two accounts: does the routing exist?

Being straight about this, because it is the load-bearing engineering question and a peer session
asked me the same thing an hour ago: **I do not have evidence that second-account dispatch works
here.** The one attempt I know of (`docs/handoff/dispatch-a2b844cf` in leadv2) ended
`status: blocked / reason: no_work` with a zero-line diff. I have not personally seen a lane run on
a second Claude account and produce a commit. If the founder has, the mechanism is on his side and I
have not been shown it.

So the $100 plan's value depends on work that may not be built. That is a cost the arithmetic above
does not include.

## Recommendation

1. **Do not buy the 20× multiplier for a window you are 16% into.** On the evidence available, drop
   Max 20x and run the employer's Max 5x plus one purchased Max 5x. Saves $100/month and, if the
   community numbers hold, *increases* weekly capacity from ~1.7× to 2.0×.
2. **Spend the freed $100 on Codex**, which is the arm we already offload review to, and which has
   no 5-hour window.
3. **GLM Max: yes**, and this one is not close. Our own measurement already showed the current
   Legacy V2 Pro at $30 gives ~70M tokens/week at our mix while the current-generation Pro gives
   263–526M — 4–8× for a plan we are already paying for. That is the least controversial line item
   here.
4. **Do not act on step 1 until the binding window is recorded, not sampled.** One probe is not a
   basis for a $1 200/year decision.

## The one measurement that would change my mind

**Log `binding_window`, `five_hour_pct` and `seven_day_pct` on every probe for one full week.** If
`binding_window` comes back `five_hour` on any meaningful fraction of samples — especially during
interactive lead sessions rather than headless nights — then the 20× is buying something real and
this recommendation is wrong. Today that field is written once and overwritten; nobody can answer
the founder's question from history because nobody kept it.

Second, cheaper measurement: our `baselines_json` already holds 331 five-hour windows with median
197M, p75 323M, p90 403M. Establish what the Max 5x and Max 20x 5-hour ceilings actually are in the
same unit, and the p90 tells us immediately whether a 5x seat would have walled.

**Both belong in the backlog whatever the purchase decision is** — the founder should not have to ask
three models to guess at a number his own tooling could have been recording all along.
