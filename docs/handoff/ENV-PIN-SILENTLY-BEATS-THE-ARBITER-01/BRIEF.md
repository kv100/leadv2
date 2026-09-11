# ENV-PIN-SILENTLY-BEATS-THE-ARBITER-01

Backlog row: `2c3e85970038` (persona-engine `docs/tasks.yaml`, group leadv2).

Founder order, 2026-09-11, verbatim: **«надо всегда думать и выбирать, ничего жестко
пинить никуда не надо, ни в одном их моих репо и в плагине тоже».**

Model selection must always go through the arbiter. No hard pin anywhere.

## Measured state (2026-09-11)

`scripts/leadv2-router.sh`, `think_model()` around line 466:

```bash
verdict="$(_think_arbiter_decide "$role" "$task_class" "${THINK_TASK_ID:-}")"
...
if [[ -n "${LEADV2_THINK_MODEL:-}" ]]; then
    resolved="$(_think_resolve_candidate "${LEADV2_THINK_MODEL}")"
    reason="env_pin"
else
    resolved="${verdict%%|*}"
    reason="${verdict_tail%%|*}"
    if [[ -z "$resolved" ]]; then
      resolved="$(_think_resolve_candidate fable)"
      reason="fail_open_legacy_${reason}"
    fi
fi
```

The arbiter is consulted and its answer is then **thrown away** whenever the env var is
set. Two hard pins in one function:

1. `LEADV2_THINK_MODEL` beats the arbiter outright, journalled only as `reason=env_pin` —
   a phrase that reads as "intended" rather than as "the arbiter was overruled".
2. The fail-open branch resolves a **hardcoded literal `fable`**.

This contradicts the contract written in `scripts/lib/leadv2-think-model.sh`'s own header:

> the env only supplies the DEFAULT candidate, never an outright override; opus is used
> ONLY when the candidate is unavailable

Comment and code disagree, and the code wins.

**Effect, censused across every lane journal:** 497 resolutions `fable reason=env_pin`,
145 `opus reason=env_pin`, and exactly **3 ever** via `reason=arbiter_cheapest_capable`.
Latest `env_pin` 2026-09-11T14:40. Asked with a clean environment the same day, the
arbiter picks `codex` for **every** think role — default, judge, diagnose, plan,
architect, learn. Fable zero times.

## What to change

### 1. `scripts/leadv2-router.sh` — `think_model()`

The arbiter verdict always wins. `LEADV2_THINK_MODEL` demotes from override to the
**fail-open candidate**, replacing the hardcoded `fable` literal:

- arbiter returned a model → use it, journal the arbiter's own reason;
- arbiter returned nothing AND `LEADV2_THINK_MODEL` is set → use it, journal
  `reason=fail_open_env_candidate`;
- arbiter returned nothing and no env candidate → keep today's last-resort behaviour but
  journal it as a distinct reason, not as a choice.

**The model-capability kill switch keeps its precedence.** An exclusion is not a pin: the
founder's order is that nothing forces a model, not that a model known to be unavailable
may be selected. If `model-capability.yaml` marks an arm `unavailable: true`, it stays
excluded regardless of what the arbiter or the env says. Do not weaken that path.

**The journal line is half the deliverable.** `reason=env_pin` is what let this survive:
it names a mechanism, not a fact about whether a decision was made. Whatever reasons you
emit must let a reader tell "the arbiter chose this" from "the arbiter was not consulted"
from "the arbiter had no answer and this is a fallback". One grep of the journal must
answer "how often is a model actually chosen?".

### 2. Do NOT touch these

- `LEADV2_MAIN_MODEL` and `LEADV2_FORCE_OPUS_LEAD`. These set the LEAD's own model, and
  `CLAUDE.md` records opus-as-lead as a standing founder decision with its rationale
  (FABLE-RESTORE-01 states explicitly that the lead's own default model is unchanged).
  Changing it needs a separate answer from him, and this row does not have it.
- `~/Projects/getmany-followup-bot/.claude/settings.json`, which sets
  `LEADV2_THINK_MODEL=fable` in its env block. Another session owns commits in that repo;
  it is being told separately. Once change 1 lands, that entry stops being an override and
  becomes a harmless fallback candidate anyway.

### 3. Suite: `scripts/tests/test-think-model-arbiter-wins.sh`

Fixtures in the suite's own temp dir; stub the arbiter through `LEADV2_TEST_ROUTER` or an
equivalent seam rather than calling the live one — a suite whose result depends on live
quota utilisation is a suite that goes red on a healthy system.

Cases:

1. Arbiter returns a model, `LEADV2_THINK_MODEL` unset → arbiter's model, arbiter's reason.
2. Arbiter returns a model, `LEADV2_THINK_MODEL=fable` set → **arbiter's model still wins**,
   and the journal reason is NOT `env_pin`. This is the whole row.
3. Arbiter returns nothing, `LEADV2_THINK_MODEL=fable` → fable, reason names it a fallback.
4. Arbiter returns nothing, env unset → last-resort path, journalled distinctly.
5. Arm marked `unavailable: true` in model-capability.yaml → excluded even when the arbiter
   names it AND the env names it. The kill switch outranks both.
6. Every role — default, judge, diagnose, plan, architect, learn — takes the same path;
   none of them carries its own literal.

### 4. Negative control: `scripts/tests/nc-think-model-arbiter-wins.sh`

Mutate the **real** `leadv2-router.sh` into a scratch copy the suite is pointed at, run the
suite against the mutant, assert RED. Two mutations:

- (a) restore the `env_pin` override branch → case 2 must go red;
- (b) make the kill switch advisory instead of binding → case 5 must go red.

If a mutation pattern is not found, **exit non-zero loudly**. A row filed today
(`BALANCER-NEGATIVE-CONTROL-HALF-ROTTED-01`) exists because `nc-claude-profile-select.sh`
printed `NC2-SETUP-FAIL` and still reported an overall pass.

Refuse to write a mock onto a tracked file:

    git -C "$(dirname "$T")" ls-files --error-unmatch "$(basename "$T")" >/dev/null 2>&1 \
      && { echo "REFUSED: mock target is tracked"; exit 2; }

A suite in this repo overwrote its own production `codex-task.sh` twice on 2026-09-11 by
skipping that check.

## Hard constraints

- Another lane (`3b69d511`, worktree `0e3619bc27e0`) is editing
  `scripts/leadv2-dispatch-code.sh` right now. Do not touch that file. Commit with
  `git commit -- <your paths>` so a shared index cannot sweep in someone else's work.
- `scripts/leadv2-plugin-cache-sync.sh` is modified in the working tree by someone else.
  Leave it; keep it out of your commit.
- Never `git stash`, `git reset --hard`, `git clean`, or `git worktree prune`.
- Suites must never write to `~/.claude/leadv2-state/`.
- Commit in `~/Projects/leadv2`; committing to main IS the deploy. Do not push.

## Report back

Under 300 words: commit sha, suite pass/fail counts, the NC output for both mutations, and
a before/after of one live resolution showing `reason` changed from `env_pin` to an
arbiter reason with `LEADV2_THINK_MODEL` still set in the environment.
