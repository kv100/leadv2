# PREPASS-CLASSIFIER-MISREADS-AN-ALLOWED-PAYLOAD-01

Founder order 2026-09-16 (item 4 of the balancer list). Standing rules:
`docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`.

## Three defects in the architect prepass, all in `plugins/leadv2/scripts/leadv2-dispatch-code.sh`

They matter together because they make the prepass lie about **why** it failed, which is how a
provider that answered "go ahead" gets recorded as a quota lockout.

**1. `:5672` — the rate-limit regex greps the event's own name.**

```bash
_ARCH_FAIL_RATE_RE='rate[ _-]?limit|HTTP 429|too many requests|overloaded_error'
```

It runs against the RAW response text, which contains literals like `rate_limit_event` and
`rate_limit_info`. `rate[ _-]?limit` matches the **name of the event**, so any informational message
about limits is classified as having hit one.

**2. `:5724`, inside `_architect_prepass_admission_status()` (`:5716`) — the admission parse is
blind to the quote.**

```bash
if printf '%s' "${evidence}" | grep -qiE 'status[=:][[:space:]]*allowed'; then
```

Against JSON `"status":"allowed"` the character after the colon is `"`, which is neither whitespace
nor `a`, so the pattern does not match and the function falls through to `unknown`.

Measured at runtime, not read off the regex — the function was sourced
(`LEADV2_DISPATCH_SOURCE_ONLY=1`) and called directly:

```
payload : {"type":"rate_limit_event","status":"allowed","limits":[{"kind":"session","percent":34}]}
returned: unknown          <- the payload says allowed
```

Together, 1 and 2 turn "allowed, proceed" into "unknown plus rate-limited".

**3. `:6036-6038` — the fallback ladder is hardcoded to two arms.**

```bash
case "${arm}" in
  codex|glm) : ;;
  *) emit decision "architect_prepass_fallback ... outcome=skipped reason=no_architect_launcher"
```

Every other arm is skipped by the `*)` branch. No tenant yaml can change this, which contradicts the
standing rule that quota/task/complexity decides an arm, never a hand-kept list. Related and NOT to
be fixed here: `_architect_fallback_design` (`:6026-6090`) contains **zero** references to
`profile-select`, `account-switch`, `profile-pick` or `CLAUDE_CONFIG_DIR` (grep returned 0), so a
Claude limit triggers a cross-**provider** fallback only, never an account swap. Report that; it is
owned by the account-selection rows.

One thread is explicitly unresolved and must not be smoothed over: the journal line
`arm=codex outcome=skipped reason=same_provider` is unexplained — codex's provider is not anthropic,
so `same_provider` looks wrong there. Investigate and report; if you cannot establish it, say so.

## Acceptance (red at dispatch, rc=1 measured 2026-09-16)

```
bash docs/handoff/PREPASS-CLASSIFIER-MISREADS-AN-ALLOWED-PAYLOAD-01/probe.sh
```

It covers defect 2 only — the one with a clean behavioural seam. Defects 1 and 3 need their own
controls, written by this lane; a green probe is not evidence they were fixed.

Not in your write set. Do not edit it.

## Controls — one per independent claim, three claims

- Defect 2: the probe above, red before / green after.
- Defect 1: feed a payload whose only occurrence of the string is the event NAME and assert it is not
  classed as a rate limit; feed a real limit message and assert it still is. Both halves, or the fix
  could simply stop detecting rate limits.
- Defect 3: assert an arm outside `codex|glm` reaches the fallback instead of
  `reason=no_architect_launcher`. Drive it from routing config, not by editing a literal list.

## Write set — FILES, never directories

```
plugins/leadv2/scripts/leadv2-dispatch-code.sh
plugins/leadv2/scripts/tests/test-prepass-admission-truth-01.sh
docs/handoff/PREPASS-CLASSIFIER-MISREADS-AN-ALLOWED-PAYLOAD-01/report.md
```

## Ordering constraint — the dispatcher file is held, and a bundle already waits for it

`leadv2-dispatch-code.sh` is in the declared write set of live lane `8dde34a2`
(`GROUP-A1-ABSOLUTE-MISSION-PATH-AND-LANDED-AT-SPAWN-01`), verified from its journal.

**DECIDED 2026-09-16: this row FOLDS INTO `PLUGIN-PREPASS-TRUTH-BUNDLE-01` — do not dispatch it as
a separate lane.** That bundle (rows `28c85708da3e`, `09714c4fc3a7`, `9314a9ffdd6e`, held by
`SD-PREPASS-BUNDLE-AWAITS-DISPATCH-CODE-01`) was read, and it already owns two of the three defects:

| This row | The bundle |
|---|---|
| Defect 1, `:5672` regex matching the event's own name | Bundle Defect 2 — "every prepass failure is labelled `rate_limited`" |
| The `arm=codex ... reason=same_provider` thread flagged above | Bundle Defect 3 — "codex is excluded as `same_provider`" |
| Defect 2, `:5724` quote-blind admission parse | adjacent to Bundle Defect 1 — "the prepass admits Build on the arm's PROSE": same site, different framing. Reconcile them; do not fix it twice |

**What this row contributes that the bundle does not have, and which must be carried over:**

1. **A behavioural probe in place of two greps.** The bundle's acceptance is
   `grep -q design_artifact_verified …` and `grep -q prepass_timeout …` — those assert a string
   exists in a file, not that the code behaves, and cannot go red when the function regresses.
   Use `docs/handoff/PREPASS-CLASSIFIER-MISREADS-AN-ALLOWED-PAYLOAD-01/probe.sh` instead or as well:
   it sources the dispatcher (`LEADV2_DISPATCH_SOURCE_ONLY=1`) and calls
   `_architect_prepass_admission_status` directly.
2. **The runtime measurement**: the function returns `unknown` for a payload containing
   `"status":"allowed"`. Reading the regex suggests that; running it proves it.
3. **Defect 3 above — `:6036-6038`, the hardcoded `codex|glm` fallback ladder.** Not covered by the
   bundle mission at all.

Honest note on provenance: the duplicate gate fired when this row was filed and was overridden
without its candidates being read. The gate would have been substantially right.

## AMENDED 2026-09-16 (lead) — the ordering constraint above is VOID; dispatch this row

The "DECIDED: folds into the bundle, do not dispatch" instruction rested on one premise:
`leadv2-dispatch-code.sh` being held by the live lane `8dde34a2`. That premise was measured again
and is false on both counts.

1. **Lane `8dde34a2` (A1) is dead**, and released its claim at 2026-09-16T12:56:05Z
   (`active_lane_released ... rows=1 removed=1 live_worker_kept=0`). It is also NOT landing: run
   paired against main, its branch leaves `test-lane-placement-pin.sh` red (its own acceptance) and
   turns `test-journal-honours-the-pinned-root.sh` from green to red, because the root-resolution
   rung it adds overrides an explicit `CLAUDE_*` pin — two negative controls fail on exactly that.
   A1 goes back for a fix round; nothing of it reaches this file.
2. **The real holders of the file were two dead rows**, not A1: `13d1c86d` (2026-09-08, pid 1 =
   launchd, reparented) and `DISPATCH-HONESTY-01` (2026-09-10, pid 27360, gone). Both were 6-8 days
   stale and both are now marked stale by `leadv2-stale-sweeper.sh --mark-only`.

No bundle lane is in flight and no bundle row is dispatched, so there is nothing to fold into right
now. This row carries the only behavioural probe of the three, so it leads rather than follows.
When a bundle lane is later dispatched it must reconcile against whatever lands here, not re-fix it.

## The acceptance probe was REPLACED (lead, 2026-09-16)

The probe this mission points at was a stub: it referenced `$OUT`, which nothing set, so under
`set -u` it exited 1 having measured nothing. It could never have gone green. The replacement makes
three measurements and is red on main at `pass=1 fail=2`:

```
json "status":"allowed"            -> expect allowed        got unknown
json "status":"quota_refused"      -> expect quota_refused  got unknown
bare status=allowed (control)      -> expect allowed        got allowed
```

Two corrections to the mission body above, both measured, neither cosmetic:

- Defect 2 is **wider than stated**. The quote-blindness breaks both branches of the function, not
  just the `allowed` one: a payload saying `"status":"quota_refused"` also returns `unknown`. So the
  prepass cannot tell a real quota refusal from a silence either. Fix both.
- The third case above is a **positive control on the instrument**, and it must keep passing. It
  already passes on main, so if it ever fails, the probe has lost its grip on the function rather
  than the fix having regressed. And case 2 must not become `allowed` — that is what stops a "fix"
  that just returns `allowed` for everything from looking correct.

Defect 1 was also confirmed at runtime on main, independently of the probe: the payload whose only
occurrence of the string is the event NAME (`"type":"rate_limit_event"`) is classed as rate-limited,
while a real limit message is still classed correctly. Both halves, as the controls section demands.
