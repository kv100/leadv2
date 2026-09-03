# Census criterion — how the four self-disabling guards were selected

Recorded 2026-09-03 so the second pass over the remaining candidates uses the **same test**, not a
fresh hunch. If pass two changes the criterion, it cannot claim to have covered the class.

## The shape being hunted

A guard that **returns success early when one of its inputs is empty**, where that input is a field
the system frequently fails to populate. The damage is not the skip itself — it is that the skip is
indistinguishable, from the outside, from the guard having run and found nothing.

## The mechanical filter, exactly as run

```
grep -rnE '\[\[ -n "\$\{[A-Za-z_]+:?-?\}?" \]\] \|\| (return|exit)|\[\[ -z "\$\{[A-Za-z_]+:?-?\}?" \]\] && (return|exit)|\[ -z "\$\{?[A-Za-z_]+' \
  plugins/leadv2/scripts/*.sh plugins/leadv2/scripts/lib/*.sh \
  | grep -E 'return 0|return$|exit 0'
```

That yields **59 candidates** across the plugin's scripts. Pass one then narrowed by a second
filter — the one that must be replaced, not repeated, in pass two:

```
| grep -iE 'writes|scope|paths|lane|protect|dirty|files'
```

## The two-part admission test each candidate must pass

A grep hit is a *candidate*. It becomes a *finding* only when both hold, and both were checked by
reading the code, not by pattern:

1. **The gating variable is empty in practice, with a number.** For pass one that number was
   measured, not assumed: 237 of 241 `protection_derived` lines carry `writes=<none>` (98.3%), and
   `Reads:`/`Writes:`/`Touches:` appear in 0 of 324 lane missions. A candidate whose variable is
   normally populated is not a finding — it is an ordinary guard clause.
2. **The early return silently disables a protection**, not merely an optimisation. Ask: if this
   returns 0 on empty, what stops happening, and would anyone notice? `pc_stop_gate_autocommit`
   returning 0 means no checkpoint and no message. A cache lookup returning 0 on empty means a slower
   path and identical behaviour — not a finding.

Record the answer to (1) as a measured ratio per finding. "Probably often empty" does not qualify.

## What pass one found, and the cascade that made it worse

All four are fed by the same field, `WRITES_CSV="${LEADV2_DISPATCH_LANE_WRITES:-}"`
(`leadv2-dispatch-product-close.sh:31`):

| # | site | guard |
|---|---|---|
| 1 | `leadv2-dispatch-product-close.sh:1803` `pc_precheck_writes` | `[[ -n "${WRITES_CSV:-}" ]] \|\| return 0` — leaves `_PC_SCOPE_WRITES_CSV` empty |
| 2 | `leadv2-dispatch-product-close.sh:1911` `pc_stop_gate_autocommit` | `[[ -n "${_PC_SCOPE_WRITES_CSV:-}" ]] \|\| return 0` — **disabled by #1's own output** |
| 3 | `leadv2-dispatch-ledger.sh` `_dl_derive_lane_state` | dirty probe scoped to a `lane_writes` pathspec, so `dirty` is never set |
| 4 | `lib/leadv2-mission-writeset.sh:134` `leadv2_writeset_missing` | `[[ -n "${required}" ]] \|\| return 0` |

**Pass two must look for cascades, not only single sites.** #1 → #2 is why the checkpoint path was
already off before SIGKILL ever arrived: two independent ways to not fire, both silent. A single-site
census would have found #2 and reported "autocommit has a guard clause", missing that the guard could
never be satisfied.

## Scope of pass two

The remaining ~55 candidates, filtered by the admission test above rather than by the `writes|scope|
paths|lane|protect|dirty|files` keyword list — that list was pass one's scoping choice and would
simply re-find the same four. Report, for each finding: the site, the gating variable, its measured
empty-rate, what protection stops, and whether it feeds or is fed by another guard.
