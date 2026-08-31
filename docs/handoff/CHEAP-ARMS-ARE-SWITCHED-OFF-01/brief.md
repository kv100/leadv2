# CHEAP-ARMS-ARE-SWITCHED-OFF-01 — every cheap arm is disabled by config, not by quota

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CHEAP-ARMS-ARE-SWITCHED-OFF-01`

LANE_WRITES: plugins/leadv2/config/leadv2-routing.yaml,plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/codex-task.sh,plugins/leadv2/scripts/tests/test-cheap-arms-admitted.sh,tests/run-all.sh,docs/handoff/CHEAP-ARMS-ARE-SWITCHED-OFF-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## The finding

Every dispatch today resolved to Sonnet. Not because Sonnet won — because the other three arms
were removed before or during the auction. From the live logs of three consecutive dispatches:

```
arm_excluded by=router arm=freepool   reason=protected_path
arm_excluded by=router arm=glm-flash  reason=protected_path
route_resolved arbiter_pick=codex tier=spark util_glm=1 util_codex=6 util_claude=49 util_freepool=100
ERROR: spawn(codex) failed rc=1: [codex-task] unknown --tier: spark (expected top|standard|volume)
route_resolved by=router model=sonnet reason=cheapest_capable
```

And from `leadv2-quota-status.sh` on the same machine:

```
glm weekly (live, z.ai): 1%   — real provider number, matches z.ai console
codex:  unmeasured (ChatGPT subscription, not in this db)
anthropic wk: 1.99B / 4.18B cap
```

Four separate defects, each independently sufficient to disable an arm.

## [Critical] 1 — `util_freepool=100` is a default for "no telemetry", not a measurement

Freepool has no rows in the quota database at all. The arbiter renders that absence as 100%
utilisation, i.e. exhausted — so the one arm that is supposed to be effectively unlimited is the
one the arbiter believes is most spent.

Absence of telemetry must never render as exhaustion. Decide and implement an explicit
`unmeasured` state, distinct from both 0% and 100%, and define how the arbiter ranks it. Say in
`report.md` what you chose. The same bug applies to Codex (`unmeasured` in the same output while
the arbiter prints `util_codex=6` — also not a real number); fix both, or say why one differs.

## [Critical] 2 — `tier: spark` is a tier the launcher has never accepted

`leadv2-routing.yaml:74` pins the codex cell to `tier: spark`. `codex-task.sh` accepts only
`top|standard|volume`. So the codex cell wins the auction and dies at spawn, every single time —
it has been dead on arrival for as long as that line has existed, and nothing detected it because
the ladder silently falls through to Sonnet.

Two things, not one:
- make the config's tier value **validated against what the launcher accepts**, at load or at the
  latest at spawn, so an unknown tier is a loud config error rather than a silent fallthrough;
- pick the correct current tier for that cell. `spark` is obsolete. Establish what
  `codex-task.sh` supports today, and say in `report.md` how you determined it — do not guess from
  this brief.

**A fallthrough to a more expensive arm must be logged as a failure**, with the arm and the reason,
not as an ordinary `route_resolved`. Today the expensive fallback is indistinguishable from a
deliberate choice, which is why this went unnoticed for weeks.

## [Critical] 3 — `untrusted: true` disables arms by config, not by evidence

`untrusted: true` sits on the glm and freepool ladder entries (`:247`, `:302`), and `DC_PROTECTED=1`
strips **every** untrusted arm from the chain. `ARMS-ADMISSION-01` already narrowed this so that
`review|audit|plan` no longer count as writing to production — but `build` still does, and every
lane we dispatch is `build`. So both cheap arms are removed from the majority of real work.

The founder's standing rule is that quota, task shape and complexity decide routing — never a
hand-kept exclusion list. Replace the blanket strip with an admission rule tied to what actually
needs trust: production-writing paths, safety, payments. A lane whose `LANE_WRITES` is tests,
docs and plugin scripts is not a production write.

Say in `report.md` exactly which work still excludes untrusted arms after your change, and why each
exclusion is justified by something other than "it was on the list".

## [Medium] 4 — GLM sits at 1% while Claude sits near half its weekly cap

That is the consequence, and it is the measurable acceptance signal. After this lane, a plain
`build` dispatch with `--protected` must be able to resolve to glm-flash or freepool when they are
capable and cheap, and the resolution must be visible in `route_resolved`.

## Acceptance

Build `test-cheap-arms-admitted.sh` against fixture routing configs and a fixture quota source —
never the real quota db, never a real dispatch:

1. an arm with no telemetry ⇒ ranked as `unmeasured`, **not** as exhausted; it remains selectable;
2. a `build` lane whose write set is tests/docs/scripts ⇒ glm-flash and freepool are admitted even
   with `--protected`;
3. a lane that genuinely writes production/safety paths ⇒ untrusted arms still excluded;
4. a config tier the launcher does not accept ⇒ loud validation error, never a silent fallthrough;
5. a spawn failure that falls through to a costlier arm ⇒ logged as a failure naming the arm and
   reason;
6. given equal capability, the cheaper arm with free quota wins over the near-cap arm.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Restoring the blanket untrusted strip must turn this suite red.
- A kill counts only if this suite alone goes red, and only if the suite was green first.
- Never hardcode an arm in or out of the ladder — that is the defect, not the fix.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A build lane can resolve to a cheap arm, an unmeasured arm is not treated as exhausted, an unknown
tier fails loudly instead of falling through to Sonnet, and restoring the blanket untrusted strip
turns the suite red with the exit code following.

## Addendum — corrections from the founder, and two additions

**Correction to [Critical] 1.** I wrote that Codex is "unmeasured". That was the output of
`leadv2-quota-status.sh` only, whose db has no Codex rows — it is NOT true that Codex cannot be
measured. `codex-task.sh` already carries CODEX-GATE-01 with a live quota reader
(`_codex_quota_read` :206, `_codex_quota_thresholds` :156, threshold sourced from routing.yaml
via `_codex_quota_routing_yaml` :135). The founder confirms Codex was working normally this
morning.

So the defect is narrower and more embarrassing than "no telemetry": **a live reader exists and
the arbiter does not use it.** `util_codex=6` is a number from somewhere else. Find where the
arbiter gets its per-arm utilisation, wire it to the reader that already exists, and say in
`report.md` what it was reading before.

**[Critical] 5 — Codex must actually carry work.** It is a paid subscription sitting idle while
Anthropic runs near half its weekly cap. After this lane, a review or build lane that Codex is
capable of must be able to resolve to Codex and SPAWN successfully — the acceptance signal is a
real `worker_spawned ... arm=codex`, not a `route_resolved` followed by a spawn error.

**[Critical] 6 — both Anthropic accounts must be usable.** Routing today treats "anthropic" as a
single pool with a single weekly cap (1.99B / 4.18B observed). There are two accounts available.
Establish how a second account is selected (env, profile, credential path — determine it, do not
guess), and make the ladder able to route to either, so one account nearing its cap does not stall
work while the other is idle. If this cannot be done without a credential the lane does not have,
say so plainly in `report.md` and implement the routing seam so only the credential is missing.

Acceptance gains two cases: (7) a capable Codex cell resolves AND spawns; (8) with account A over
threshold and account B idle, a Claude-capable lane routes to B rather than falling back to a
costlier or slower arm.
