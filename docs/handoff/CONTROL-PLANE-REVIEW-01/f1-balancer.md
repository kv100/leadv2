# CONTROL-PLANE-REVIEW-01 / F1 — balancer and quota-layer review

Scope: read-only source review on 2026-09-11.  S1/S4/S5 below are cited
measurements from `seed-facts.md`, not re-measured here.  “Consumed pct” means
the API's used percentage; lower is normally better.  `usable_now` means
remaining percentage-points per hour.

## Findings

1. **DEFECT — Fable's model-scoped ceiling is not a constraint in either the
   profile picker or the arbiter.**  S1 proves that the live Anthropic response
   contains both `weekly_all` and a Fable-scoped `weekly_scoped` limit
   (`seed-facts.md:12-21`).  The reader preserves `limits`, but only derives
   `five_hour` and `seven_day` windows (`plugins/leadv2/scripts/leadv2-quota-read.py:844-863`).
   The picker scores only the binding `*_pct`, then the max of those two pct
   fields (`plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py:117-133`).
   The arbiter likewise builds Claude windows solely from `five_hour` and
   `seven_day` (`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:654-699`),
   while mapping `fable` to the generic Claude provider
   (`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:748-755`).  Failure
   scenario: Fable's `weekly_scoped` reaches 100% while `weekly_all` and the
   two generic windows retain headroom; a Fable-capable task can still be
   selected and then hit its model-specific limit.  This is not cured by the
   model-capability comment; that file itself still asserts the now-refuted
   separate-bucket premise (`plugins/leadv2/config/model-capability.yaml:44-57`).

2. **DEFECT — the balancer is not ranking by `usable_now`; its S4 outcome only
   happens to agree with that availability measure.**  Given its declared
   inputs, the Python implementation deterministically ranks `(tier, raw pct,
   registry order)`, lowest first (`plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py:157-175`),
   and the raw pct is copied from the binding window (`:117-122`).  It never
   reads that window's `usable_now`.  In S4, personal (67% used, 1.62 usable)
   beat work (56% used, 0.397 usable) because work was `demoted`, not because
   either usable rate was compared (`seed-facts.md:58-72`; picker demotion is
   tiered ahead of score at `leadv2-claude-profile-pick.py:157-174`).
   Therefore: **(a)** the observed winner is correct *ex post* on the stated
   `usable_now` facts, and the code correctly applies its own tier/raw-pct
   rule; it is **not** a correct availability ranking.  Failure scenario: two
   non-demoted profiles at 56%-used/113h-to-reset and 67%-used/20h-to-reset are
   ranked toward 56 even though the latter has much more usable capacity per
   hour.

3. **DEFECT — `score=67` is not an honest, self-describing account of what was
   ranked.**  The runtime line labels the raw integer `score` and separately
   prints `binding`/`windows` (`plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py:183-196`);
   the module's own contract admits that this remains the “raw window pct”
   (`:25-35`).  S4 shows the resulting `score=67` attached to the higher
   *consumed* percentage (`seed-facts.md:63-73`).  The line never says
   `consumed_pct`, that lower is better, or that a tier-demotion overrode the
   numeric order.  Failure scenario: an operator treats 67 as capacity/quality
   or assumes higher is preferred, then concludes the balancer chose the more
   consumed account for no reason.  The `binding=` and `demoted=` fields help
   reconstruct the event, but they do not make the score token truthful on its
   own.

4. **SOUND — an unreadable 429 account is represented as unknown, never as
   free quota.**  The quota reader maps HTTP 429 to `status: unknown` with the
   explicit “NEVER 0” error (`plugins/leadv2/scripts/leadv2-quota-read.py:867-869`).
   The picker then assigns a non-live sentinel rather than a numeric capacity
   (`plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py:114-116`).  This
   preserves the deliberate safety property in S5 (`seed-facts.md:77-84`): a
   rate-limited bound credential cannot masquerade as 0%-consumed/free.

5. **DEFECT — the profile balancer silently substitutes the registry's readable
   slots for the session-bound account.**  Candidate records are constructed
   only from valid TSV registry rows (`plugins/leadv2/scripts/leadv2-claude-profile-select.sh:266-343`),
   then each is probed with that row's explicit credential/service
   (`:556-565`); `candidates` is simply the number of those records
   (`plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py:193-196`).  It
   does not add or assess the quota reader's top-level `active_account`.
   Thus S5's `candidates=2` describes only the two registry probes while the
   actual session credential is the 429/null-window account
   (`seed-facts.md:75-90`).  Failure scenario: the dispatching session is bound
   to an unregistered/default account whose quota cannot be read; the balancer
   reports a confident two-profile choice without saying that its own bound
   account was outside the comparison.

6. **DEFECT — the arbiter considers the bound account only long enough to
   replace it with a different readable account, without recording that
   substitution.**  It first locates `active`, but if that account is not `ok`
   it selects an `ok` account with the same label or the first `ok` account
   (`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:638-653`), then bases
   Claude pct and `usable_now` on that replacement (`:654-702`).  This is
   compositionally different from “the session-bound account is usable.”  S5
   is the concrete case: the bound account is 429/null while the other two are
   readable (`seed-facts.md:75-87`).  Failure scenario: the fallback account
   has ample quota, so the arbiter admits Fable/Sonnet even though the runtime
   credential that will execute is the unreadable bound account; its output
   names a Claude account state but no fallback-account provenance
   (`leadv2-route-arbiter.sh:1757-1760`).

7. **SOUND — the top-level `binding_window: null` is treated as unknown by the
   consumer that reads it, not converted to a zero.**  The producer intentionally
   derives the top-level field from the active account (`plugins/leadv2/scripts/leadv2-quota-read.py:893-901`),
   so S5's top-level null alongside readable non-active accounts' `seven_day`
   is an account-relative state, not evidence that every account lacks a
   binding window (`seed-facts.md:86-87`).  `leadv2-quota-shape.py` first reads
   the top-level binding and returns `None` on null (`plugins/leadv2/scripts/lib/leadv2-quota-shape.py:51-61`);
   for Anthropic it also requires the active account to be `ok` (`:70-79`).
   Its caller is the backlog-pump gate (`plugins/leadv2/scripts/leadv2-backlog-pump.sh:593-609`).
   Failure avoided: the 429 account cannot supply a fabricated remaining
   percentage to that gate.  This sound unknown handling does not repair the
   arbiter's distinct fallback in finding 6.

8. **DEFECT — cache TTL can be extended indefinitely while the payload's
   `fetched_at` grows stale, and the arbiter has no direct fresh-read knob.**
   Anthropic's nominal TTL is 300 seconds and `cache_get` tests file mtime
   (`plugins/leadv2/scripts/leadv2-quota-read.py:71-86`).  But every cache hit
   normalizes and writes that same object back (`:1057-1062`), resetting mtime
   without refreshing its API-derived `fetched_at`; this explains how S5 could
   serve a roughly 34-minute-old payload (`seed-facts.md:89-90`) despite the
   nominal five-minute TTL.  A fresh route is available to direct callers:
   `--no-cache` bypasses both daemon/disk cache branches
   (`leadv2-quota-read.py:1038-1064`), and the profile selector correctly uses
   it for every profile probe (`leadv2-claude-profile-select.sh:556-565`).
   The arbiter instead invokes quota-live as bare `json`
   (`leadv2-route-arbiter.sh:83-90`), while quota-live only forwards freshness
   when passed `--no-cache` (`leadv2-quota-live.sh:123-143`); no arbiter option
   supplies that flag.  Failure scenario: repeated arbiter calls preserve an
   old low/high consumed value and its old reset time, so `usable_now` changes
   the effective-cost sort using stale facts (`leadv2-route-arbiter.sh:1524-1553`).

9. **SOUND — the arbiter's use of `usable_now`, once it has a valid selected
   Claude account, is internally coherent and auditable.**  It retains the
   binding window's own `usable_now` (`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:693-702`),
   transforms it through a bounded monotone headroom weight (`:1514-1544`),
   and includes winner headroom information in its decision record
   (`:1738-1752`).  Thus its provider-level price ranking does not repeat the
   profile picker's raw-pct mistake.  This result is limited to the account it
   chose under finding 6 and to the cache freshness caveat in finding 8.
