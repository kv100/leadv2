# EFFORT-IS-NOT-WIRED-01 — the second routing knob exists in config and doctrine, and reaches no spawn

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/EFFORT-IS-NOT-WIRED-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh,plugins/leadv2/config/leadv2-routing.yaml,plugins/leadv2/scripts/tests/test-effort-routing.sh,tests/run-all.sh,docs/handoff/EFFORT-IS-NOT-WIRED-01/

Main is `7927b0f` in `~/Projects/leadv2`. Branch from it.

## What I established before writing this

The plugin's own doctrine says there are **two knobs per spawn: model = hardness, effort =
marginal value of extra thinking**, and it ships a 97-line `docs/model-effort-matrix.md` plus
per-role `effort:` values in `config/session-routing.yaml` (`low`/`medium`/`high`).

Then:

```
grep -n 'effort' leadv2-dispatch-code.sh  -> 8 hits, ALL the phrase "best-effort"
grep -n 'effort' lib/leadv2-route-arbiter.sh -> nothing
```

**Neither the dispatcher nor the arbiter mentions effort at all.** The knob is documented,
configured, and completely unwired: every spawn goes out at whatever the provider defaults to.
A cheap mechanical edit and an adversarial safety review get identical thinking budgets —
we overpay on the first and underthink the second.

## [Critical] the arbiter must resolve an effort alongside the arm

The arbiter already decides the arm from task class, work kind and quota. Effort is the same
kind of decision from the same inputs, and it must come out of the same call — one resolution,
two outputs (`arm`, `effort`), so they can never disagree.

Drive it from data, not from a name literal: `config/leadv2-routing.yaml` (and the existing
`session-routing.yaml` role rows) are where the mapping lives, and adding a rule must not
require touching a script. The founder has a standing rule against hardcoding an arm — the
same applies to effort: no `if arm == X then effort = high`.

Sensible shape of the decision, to be expressed as data:
- adversarial review, safety judgment, architecture, a final verdict ⇒ the top tier;
- ordinary build and fix rounds ⇒ the middle;
- mechanical work — reads, greps, formatting, census, aggregation ⇒ the bottom.

## [Critical] the resolved effort must actually reach the spawn

Resolving it and not passing it is the same bug one layer up. Every arm the dispatcher can
launch has its own way to receive a thinking budget, and they are not uniform — codex takes a
tier, the Claude arms take an effort, some arms take neither. Map the resolved effort onto
each arm's own parameter, and for an arm that genuinely has no such control, log that the
effort was dropped and why. A silently ignored effort is indistinguishable from no effort at
all, which is today's state.

Note the operational caveat already recorded at `config/model-capability.yaml:193` about
`reasoning_effort` on Moonshot — read it before mapping that arm, and do not contradict it.

## [Medium] make the choice visible

The dispatch decision line already names the arm. It must name the effort too, with the rule
that produced it — otherwise nobody can tell an intentional `low` from an unset one, which is
exactly how this defect survived.

## Acceptance

Build `test-effort-routing.sh` against fixture routing data — never a live provider, never a
real dispatch — covering:

1. an adversarial-review task ⇒ resolves to the top tier;
2. a mechanical/census task ⇒ resolves to the bottom tier;
3. an ordinary build ⇒ the middle;
4. the resolved effort appears in the arm's launch arguments, asserted per arm, for at least
   two arms with different parameter shapes;
5. an arm with no effort control ⇒ a log line naming the drop, and no crash;
6. adding a new rule to the routing yaml changes the outcome with **no script edit** — this is
   the anti-hardcoding assertion;
7. the decision line names both the arm and the effort.

Add the `EXTRA_SUITE_MAP` rows for every touched script and prove selection with
`--scope changed`.

## Rules

- Mutation INSIDE the production function body, RED, revert, GREEN, clean `git diff --stat`.
  A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0.
- A kill counts only if **this suite alone** goes red — if another gate (a linter, a type
  check) kills your mutation first, the control proves nothing about your suite.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Never hardcode an arm or an effort into or out of routing — data decides.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A spawn's effort is resolved from data beside its arm, reaches the arm's own parameter, is
named in the decision line, and a mutation that drops the resolution or the pass-through turns
the suite red with the exit code following.
