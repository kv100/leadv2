# Lead note, 2026-09-17 — a live measurement that may be the cause

Probed `glm-4.6` directly from the VPS against `api.z.ai/api/anthropic/v1/messages`:

| max_tokens | HTTP | content[0].type | visible text |
|---|---|---|---|
| 16 | 200 | (none reached) | **empty** |
| 64 | 200 | `thinking` | **empty**, `stop_reason: max_tokens` |

GLM 4.6 emits a **thinking block before any text block**. With a small budget it spends the
whole allowance reasoning and never reaches `text` — while the transport reports success.

**Hypothesis for this row, not yet proven:** the reviewer resolves GLM, gets HTTP 200 and an
empty body, and emits no verdict marker. Every transport check passes, so the failure looks
like "the arm had no opinion".

Two cheap checks that settle it, and they must be run before this explanation is believed:
1. what `max_tokens` the reviewer path actually sends to a GLM arm;
2. whether the verdict parser reads `content[0].text` blindly instead of scanning
   `content[*]` for `type == "text"`.

If both point the same way, the fix is budget plus a parser that treats
`stop_reason: max_tokens` with no text block as a **named** failure — never as "no verdict".
A silence must be distinguishable from a verdict.

## Corroboration, same day, from the review engine itself

Re-running review over this branch produced:

```
status: blocked
reason: empty_response
```

That is the same shape the direct probe produced: the arm answered, the transport was fine,
and there was no text. It is not proof that the thinking budget is the cause — the probe and
this run share a suspect but not a measurement — yet it does rule out "the reviewer never ran".
Something returns, and what it returns is empty.

Also recorded from the same run: the reviewer pool showed `glm=blocked:lockout` on every
attempt today, so GLM was excluded from review by quota while this row is about GLM as a
reviewer. Any re-measurement has to wait for the lockout to clear, or it measures the lockout.

## CORRECTION, same evening — this was NOT GLM

The paragraph above reads the `empty_response` verdict as corroboration of the GLM
thinking-budget probe. **It is not.** The gate names the arm:

```
status: blocked
reason: empty_response
arm_rc: fable=0
unreadable: fable=unparsable_verdict
```

GLM was locked out of the pool at the time, so **fable** did the review, exited 0, and
produced a verdict the parser could not read. That is a different defect wearing the same
word, and it is arguably the larger one: the verdict parser fails on a Claude arm too, so
"arm returned nothing readable" is not GLM-specific.

What survives unchanged: the direct API probe at the top of this file. That was measured
against GLM itself and does not depend on this review run. What does NOT survive: the claim
that this run reproduced it.

## Live reproduction WITH GLM, 2026-09-17 19:56Z

The lockout expired at 18:48Z, so GLM re-entered the reviewer pool and was picked on merit:

```
route_resolved role=reviewer arm=glm reason=cheapest_capable
review_pool_resolve rc=0 reviewer=glm pool_n=6
review_gate status=arm_no_verdict arm=glm reason=no_verdict_marker tried=glm remaining=2
```

This is the first clean reproduction of this row with GLM itself as the arm — the earlier
`empty_response` was fable and was corrected above. The engine fell through to the remaining
arms rather than stalling, so the cost of the defect is a wasted reviewer slot per lane, not a
dead lane.

It does NOT settle the cause. `no_verdict_marker` says the parser found no marker; it does not
say whether the arm emitted none, emitted one the parser cannot match, or spent its budget on
a thinking block as the direct probe showed. The two cheap checks named at the top of this file
are still the way to decide, and they are still unrun.
