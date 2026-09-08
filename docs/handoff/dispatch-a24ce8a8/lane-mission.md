P1a — ARMS-CANNOT-LAUNCH-THEMSELVES-01, PART A: the half that lives in NEW and UNCONTENDED files.
Row `64fa36bd9571`. The parent brief follows verbatim below the divider — read all of it; this header
only narrows the scope and the write set. Where the two disagree, THIS HEADER WINS.

## Why this lane is a HALF, and what part B is

These five files are owned RIGHT NOW by a live lane (`8ca00e79`, founder row `13581c3eb064`):

    plugins/leadv2/scripts/leadv2-dispatch-code.sh
    plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
    plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py
    plugins/leadv2/config/leadv2-routing.yaml
    tests/run-all.sh

Do NOT touch them. Not one line. READ them freely — you need them to derive the allowed tuples — but
every edit to them is part B, which is queued behind that lane and is not yours. If your work seems to
require editing one, STOP and report it rather than working around it. This queue is recorded as
`SD-SMART-ROUTING-SERIAL-QUEUE-01`; the dispatcher refusing on those paths is the queue working, not a
defect.

Consequence for design: build the registry and the account-truth classifier as standalone, importable,
independently testable units whose call sites are left for part B to wire. **A unit that cannot be
tested without editing a blocked file is designed wrong for this lane** — give it an injectable seam
instead. Make the producer's output shape final, so part B is a wiring change and not a redesign.

## Scope — exactly four files, no others

1. `plugins/leadv2/scripts/lib/leadv2-launch-registry.py` (NEW) — the registry, a lookup function, and
   a CLI entry (`--kind … --role … --arm … --task-class …` printing the argv as JSON or one token per
   line) so a shell caller and a test can both use it without importing Python. It must also expose a
   check `(arm, model) -> ok|refuse`, so part B can refuse a disagreement between the resolved arm and
   the launched model instead of launching it.
   Record `pool_default: false` for opus as registry DATA. Do NOT implement removal of the pre-arbiter
   opus park — that edit lives in the blocked dispatcher and is part B.
2. `plugins/leadv2/scripts/leadv2-quota-read.py` — `_keychain_services` and the account-state
   classifier ONLY. This file is uncontended; edit it. Expose the classification as a callable/CLI
   result. Its consumer (`lib/leadv2-route-arbiter.sh`) is blocked — leave the consumer to part B.
3. `plugins/leadv2/tests/test-launch-registry-argv.sh` (NEW)
4. `plugins/leadv2/tests/test-claude-account-states.sh` (NEW)

Note on the `:6251` call site named in the parent brief: it already threads
`"${_sonnet_effort_args[@]}"` and `"${_sonnet_profile_args[@]}"`, so the EFFORT plumbing exists and the
MODEL is the literal. Generalizing that line is part B. Your job is the registry that makes the
generalization a one-line lookup.

## CI mapping — do not add it, hand it over

The `EXTRA_SUITE_MAP` row lives in blocked files (`leadv2-dispatch-code.sh`, `leadv2-helpers.sh`,
`tests/run-all.sh`). Do NOT add it. Instead write in your report the exact row part B must add for each
new suite, so wiring it is a copy-paste and not a rediscovery. State plainly in the report that until
that row exists **CI does not select these suites** — a green test CI never runs is worth nothing.

## Acceptance — the argv, never the selector's stdout

A registry entry counts as enabled only when a fixture proves descriptor → registry lookup → **the
actual adapter argv**. `arm=fable` appearing in selector stdout IS NOT THE TEST: that exact string is
what has been passing while the wrong model launched. Assert on the argv tokens.

Run the parent brief's three negative controls and SHOW each one red, mutating INSIDE the function
body (a top-level insert makes every suite red for the wrong reason and reads as a pass).

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-launch-registry.py, plugins/leadv2/scripts/leadv2-quota-read.py, plugins/leadv2/tests/test-launch-registry-argv.sh, plugins/leadv2/tests/test-claude-account-states.sh

────────────────────────── PARENT BRIEF (verbatim, minus its own LANE_WRITES) ──────────────────────────
ARMS-CANNOT-LAUNCH-THEMSELVES-01 — make every Anthropic model and every Codex model actually launchable, and stop poisoning the Claude price with keychain entries no dispatcher will ever use.

REPO: ~/Projects/leadv2 (the plugin repo is the single source; edit there, never a copy in a project).
Design this implements: ~/Projects/persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/PLAN.md
sections §0, P1 and P5. Read it first — it carries the verified file:line evidence and the two
independent designs it merges (design-fable.md, design-codex.md in the same directory).

## The mechanism, measured 2026-09-07, not assumed

1. `grep -n -- '--model' plugins/leadv2/scripts/leadv2-dispatch-code.sh` returns exactly TWO sites.
   `:6251` is the Claude worker branch and it is hardcoded `--role developer --model sonnet`.
   `:5344` is the architect prepass and takes its model from `LEADV2_DISPATCH_ARCHITECT_MODEL`,
   never from the arbiter's arm. So an arbiter verdict of `arm=fable` (or haiku, or opus) on a
   worker role launches SONNET. The routing decision and the launched model are different facts
   today, and nothing checks that they agree.
2. `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:55` —
   `DISPATCHABLE_BUILD_ARMS = {glm, glm-flash, codex, sonnet, freepool}`. fable/opus/haiku are not
   build arms at all. `:60` — `DISPATCHABLE_PLAN_ARMS = {codex, sonnet, opus, fable}`. That
   plan/build split is DELIBERATE and must be preserved: enabling fable for plan must never enable
   a fable code worker.
3. `leadv2-dispatch-code.sh:8386-8417` — opus is parked before the arbiter runs
   (`_dl_note parked resolved_opus_lead_judgment`, `exit 3`).
4. `leadv2-quota-read.py:310-322` (`_keychain_services`) enumerates EVERY
   `Claude Code-credentials*` keychain entry. There are four. Live probe, 2026-09-07T18:21Z:
   - `eb6c5b97` (label max_20x, sub max) → http 200, 7d 52% used, 48% remaining. This is the
     registry's `personal` slot.
   - `5a3c2328` (label max_5x, sub team) → http 401. This is the registry's `work` slot, and its
     credential resolves correctly — `leadv2-claude-account-check.sh` reports
     `slot=work dir_hash=5a3c2328 account=..502204 org=..f6715f sub=team tier=default_claude_max_5x`.
     The TOKEN is alive; the USAGE endpoint 401s. This is the known team-account class the file's
     own comment names (`leadv2-claude-profile-select.sh:111`, TEAM-ACCOUNT-QUOTA-WINDOW-UNPARSED-01).
   - `default` and `47fc2659` → http 401, and neither appears in the registry
     `~/.claude/state/leadv2/claude-profiles.tsv` (which has exactly two rows: personal, work).
     These are stale entries from accounts we no longer use.
   Consequence: `util('claude')` in the arbiter returns `unknown=True`, which applies
   `UNKNOWN_PROBE_PENALTY=50` (`lib/leadv2-route-arbiter.sh:311, :340-347, :829, :887`) to EVERY
   Claude cell. While that holds, sonnet/haiku/opus/fable cannot win any auction even when they are
   in the pool — so the launch fix alone delivers reachability with no reachable outcome.

## What to build

### A. Launch-capability registry
A single registry keyed by `(kind, role, arm, model, tier, effort)` → the exact adapter argv.
Populate ONLY tuples an adapter actually supports. Generalize the `claude-subsession.sh` call at
`:6251` so the model comes from the resolved arm, not a literal. Preserve every matrix kind/trust
restriction from `config/leadv2-routing.yaml:188-233` — the registry narrows what is launchable, it
never widens what is allowed.

Anthropic models that must be launchable as themselves: haiku, sonnet, opus, fable — each only on
the roles its matrix cell and the DISPATCHABLE_*_ARMS split already permit.

Codex models: read `config/leadv2-routing.yaml` for the codex rows and make every configured codex
model reachable through the registry with its own tier, not one hardcoded default.

**Effort is part of the key, not a constant.** The founder's requirement, verbatim: models must be
selectable "и выбирать эффорт везде в зависимости от задач". So the registry entry carries an effort
per (kind, task_class) rather than one global default — a trivial docs lane and a heavy integration
lane must not request the same effort from the same model. Where an adapter already accepts an
effort argument, thread the chosen value through; where it does not, the registry entry records
`effort_unsupported` and the decision line says so rather than silently pretending.

Remove the pre-arbiter opus park (`:8386-8417`) on the NEW path only. opus stays out of the default
auction (it shares the lead's own window) — reachable by explicit pool or pin, never by default.
That exclusion belongs in the matrix as a `pool_default: false` flag, not as a park before routing.

### B. Claude account truth (P5)
`_keychain_services` must stop treating every keychain entry it can find as an account. The registry
`~/.claude/state/leadv2/claude-profiles.tsv` (env override `LEADV2_CLAUDE_PROFILES_FILE`) is the
list of accounts we actually dispatch to. An entry not in the registry is not our account and must
not enter `util('claude')` at all — not as unknown, not as anything.

Then distinguish two things the code currently conflates into "unknown":
- **credential dead** → genuinely unknown, keep today's penalty.
- **usage endpoint not served for this account class** (the team account, http 401 while the token
  resolves and the account-check passes) → the account is USABLE and UNMETERABLE. It must not carry
  the +50 unknown penalty, and it must not be priced as if it had free headroom either. Give it an
  explicit third state and price it conservatively from the configured allowance, naming the state
  on the decision line (`claude:work=unmetered`). Do not invent a usage number for it.

**Do NOT delete anything from the macOS keychain.** Two stale entries exist; excluding them in code
is the fix, and it is reversible. If the founder wants them removed from the keychain that is his
own `security delete-generic-password` to run, not this lane's.

## Acceptance
acceptance:
  surface: log_line
  observable: A dispatch whose arbiter decision is a Claude-family arm other than sonnet shows that
    same model in the launched adapter's own argv — the operator sees the arm and the launched model
    agree on one line, and a mismatch is refused rather than launched. A live quota probe shows the
    two stale accounts absent entirely and the team account named as usable-but-unmetered rather
    than unknown.
  authored_at: 2026-09-07T18:30:00Z

## Negative controls (E2E-KILLRATE-01 — run them, show them red)
1. Inside the registry lookup body, make it return sonnet's argv for a fable tuple. The suite must
   go red on the argv, NOT on `arm=fable` appearing in selector stdout — that string is what has
   been passing while the wrong model launched.
2. Inside `_keychain_services`, re-admit a service not present in the registry. The probe test must
   go red.
3. Inside the account-state classifier, collapse `unmetered` back into `unknown`. The pricing test
   must go red.
Insert each mutation INSIDE the function body, never at top level — a top-level insert makes every
suite red for the wrong reason and reads as a pass.

Also add the CI mapping row so the new suites are actually SELECTED (`EXTRA_SUITE_MAP`), and prove
it with `--scope changed`. A green test CI never runs is worth nothing.

## Constraints
- Never `git add -A`; name every path. Never `reset --hard`, `clean`, `stash`, `worktree prune`.
- Never print or commit `~/.claude/state/leadv2/claude-profiles.tsv`; refer to slots by LABEL only
  (personal, work) and to keychain entries by their dir-hash suffix.
- Never push to origin.
- Every claim in your report carries its artifact: a diff hunk, a probe line, or a suite output.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-a24ce8a8" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.