verdict: APPROVE
next_action: review_round_2

# dispatch-a24ce8a8 — developer, lane 64fa36bd9571, PART A

Parent brief: ARMS-CANNOT-LAUNCH-THEMSELVES-01 (design doc:
`~/Projects/persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/PLAN.md`,
sections P1 and P5). Sibling lane `8ca00e79` (founder row `13581c3eb064`) owns
PART B (wiring `leadv2-dispatch-code.sh`, `lib/leadv2-route-arbiter.sh`,
`lib/leadv2-glm-policy-resolve.py`, `config/leadv2-routing.yaml`,
`tests/run-all.sh` — queue `SD-SMART-ROUTING-SERIAL-QUEUE-01`). This lane
touches exactly the four LANE_WRITES files, new or uncontended, and reads
the blocked files freely for spec/shape but edits none of them.

## Scope delivered

### 1. `plugins/leadv2/scripts/lib/leadv2-launch-registry.py` (NEW)

Standalone registry: `(kind, role, arm, task_class) -> adapter argv`, plus
`check(arm, model) -> "ok"|"refuse"|"not_applicable"` and a CLI.

- `load_capability_matrix()` reads `config/leadv2-routing.yaml`'s
  `router_v2.capability_matrix` live (PyYAML first, with a regex-based
  fallback parser `_load_capability_matrix_fallback`/`_parse_flow_row` for a
  PyYAML-less environment) — never a duplicated copy.
- `_dispatchable_arm_sets()` imports `DISPATCHABLE_BUILD_ARMS` /
  `DISPATCHABLE_PLAN_ARMS` live via `importlib.util.spec_from_file_location`
  from the blocked `leadv2-glm-policy-resolve.py` — reading a blocked file is
  explicitly permitted; this eliminates drift risk entirely instead of
  copying the two sets and risking silent divergence.
- `_argv_claude(role, model, tier, effort)` -> `["--role", role, "--model",
  model, ("--effort", effort) if effort]` — matches
  `claude-subsession.sh`'s confirmed `--model opus*|sonnet*|haiku*|fable*`
  passthrough (verified by grep, not edited).
- `_argv_codex(role, model, tier, effort)` -> `["--tier", tier, ("--reason",
  "...") if tier=="top"]`, `effort_supported=False` always — a real adapter
  fact (`codex-task.sh` resolves tier->model+effort internally, no
  `--effort` passthrough exists), not a gap.
- `_FAMILY_BUILDERS = {"claude": _argv_claude, "codex": _argv_codex}` —
  glm/glm-flash/freepool are **intentionally excluded** (`kind="code"` on
  those arms returns `adapter_argv_not_registered`, `check()` returns
  `not_applicable`). Verified their adapters (`glm-coder.sh`,
  `freepool-coder.sh`) via grep: glm-coder's `--model sonnet` is a
  translation-layer artifact, not a real arm-selecting flag, and fabricating
  an unverified argv shape for it would be worse than declining. The brief's
  scope is explicitly "Anthropic models... Codex models" — this is a stated
  scope limit, not an oversight.
- `POOL_DEFAULT_OVERRIDES = {"opus": False}`, `pool_default(arm)` — recorded
  as **data only**. Removing the pre-arbiter opus park at
  `leadv2-dispatch-code.sh:8386-8417` and actually consulting this flag
  before admission is PART B's job; this lane only records the fact.
- CLI: `--kind --role --arm --task-class [--json]` or `--check --arm --model`.

Verified: `python3 -m py_compile` clean; 9+ manual smoke invocations against
the real `leadv2-routing.yaml` during development, all correct (see prior
session); the new test suite below re-verifies all of this as a permanent
regression suite.

### 2. `plugins/leadv2/scripts/leadv2-quota-read.py` (edited — uncontended)

**a) `_keychain_services` registry filter.** Added
`_registry_keychain_services(registry_path=None)`: reads
`~/.claude/state/leadv2/claude-profiles.tsv` (env override
`LEADV2_CLAUDE_PROFILES_FILE`), extracts only `keychain:<service>` credential
sources (TSV format confirmed against `leadv2-claude-account-check.sh`).
`_keychain_services()` now intersects the real `security dump-keychain`
enumeration against `registry_services ∪ {prefix}` (the unsuffixed prefix is
always admitted — it's the ambient session credential Claude Code itself
uses, not a registered multi-profile slot). **Fails OPEN** (returns the
unfiltered set) when the registry is missing/unreadable/empty — a
misconfigured or not-yet-populated registry must never silently drop every
account to zero.

**b) Account-state classifier.** `classify_account_state(subscription_type,
http_code) -> "ok"|"unmetered"|"unknown"`:
- `http_code == 200` -> `"ok"`.
- `subscription_type == "team" and http_code == 401` -> `"unmetered"` (the
  named TEAM-ACCOUNT-QUOTA-WINDOW-UNPARSED-01 class: token/org resolve fine
  — confirmed live via `leadv2-claude-account-check.sh` output shape,
  `sub=team tier=default_claude_max_5x` — but `/api/oauth/usage` 401s
  anyway). Deliberately narrow: only this one measured shape reclassifies;
  a 401 on a non-team account stays `"unknown"`.
- Everything else -> `"unknown"` (keeps today's `UNKNOWN_PROBE_PENALTY`).

`CLAUDE_ACCOUNT_STATE_PRICING` table: `ok`/`unmetered` both `penalty: 0`
(unmetered priced `"configured_allowance_conservative"`, never a measured
number, never the unknown penalty), `unknown` keeps `penalty: 50`.

Wired **additively** into `read_anthropic()`'s per-account dict — every
existing `"status"` value is untouched (still `"ok"`/`"unknown"` exactly as
before); only a new `"account_state"` key is added. This is a deliberate
backward-compat decision: no existing consumer of `status` changes behavior
from this edit. The arbiter (`lib/leadv2-route-arbiter.sh`) is blocked and is
PART B's job to wire against the new field.

New CLI verb `classify-account <subscription_type|-> <http_code>` (handled
before the `READERS` dispatch in `main()`) for standalone classification
without a live probe — used by the new test suite.

Verified: `python3 -m py_compile` clean; manual CLI smoke tests (team+401,
pro+401, team+200, team+429 all correct); hermetic unit tests below re-verify
both changes as a permanent regression suite.

### 3. `plugins/leadv2/tests/test-launch-registry-argv.sh` (NEW)

13 assertions, all on **argv tokens** parsed from JSON — never on an arm
name appearing in stdout (the E2E-KILLRATE-01 discipline the brief demanded,
since a test that only greps `arm=fable` would pass even if the argv itself
still said `--model sonnet`, exactly the shipped bug shape):
fable+plan, sonnet+code, haiku+recon, codex+review-heavy exact-argv checks;
`check()` verdicts (fable/sonnet->refuse, fable/fable->ok, glm->
not_applicable); refusal reasons (`not_a_build_arm`,
`adapter_argv_not_registered`); `pool_default` data checks (opus false,
fable true); `_argv_codex(tier=top)` `--reason` shape (checked directly
against the real function since the shipped `capability_matrix` never makes
`top` win the auction naturally — every top row is strictly costlier than a
same-size-capable lower tier, so this is the real function body, not a
fabricated routing scenario).

**Negative control**, mutated INSIDE `_argv_claude`'s function body (never a
top-level swap): the copy's `argv = ["--role", role, "--model", model]` line
is replaced with a hardcoded `"sonnet"` literal — reproducing exactly
leadv2-dispatch-code.sh:6251's bug shape. The suite proves its own
exact-argv assertion disagrees with the mutant's output (i.e. the assertion
would go RED against this exact class of regression), not merely that
"fable" appears somewhere in the mutant's JSON.

The mutant file is written inside `scripts/lib/` (not a tmpdir) so its own
`_HERE`-relative routing-yaml path resolution stays correct, and is removed
by an EXIT trap regardless of pass/fail.

### 4. `plugins/leadv2/tests/test-claude-account-states.sh` (NEW)

10 assertions, fully hermetic (no real keychain read, no real network call,
no real registry file touched — `security dump-keychain` is monkeypatched to
a synthetic dump, the registry path is pinned to a temp TSV):
- keychain probe excludes a synthetic stale service not in the registry,
  admits the registered slot + ambient prefix;
- missing-registry fail-open (unfiltered enumeration, not zero);
- `classify_account_state` via the new CLI verb: team+401->unmetered,
  pro+401->unknown, team+200->ok, team+429->unknown, unresolved-sub+401->
  unknown;
- unmetered pricing carries no unknown-probe penalty and is not
  measured.

**Negative control #2**, mutated INSIDE `_keychain_services`'s body: the
`allowed = allowed | {prefix}` line is replaced with `allowed = services`
(defeats the registry filter entirely). The suite proves the mutant
re-admits the stale entry and that the real probe assertion disagrees with
it.

**Negative control #3**, mutated INSIDE `classify_account_state`'s body: the
`if subscription_type == "team" and http_code == 401:` branch is replaced
with `if False:` (collapses `unmetered` back into `unknown`). The suite
proves the mutant reports `"unknown"` and that the real pricing assertion
disagrees with it.

Both mutant files are written inside `plugins/leadv2/scripts/` (dotfile
names) and removed by an EXIT trap.

## Test selection — corrected from the brief's assumption

The brief (inherited from the parent design doc) assumed
`plugins/leadv2/scripts/lib/*.py` is absent from `tests/run-all.sh`'s
`--scope changed` stem-derivation allowlist (line 384:
`plugins/leadv2/scripts/*.sh|plugins/leadv2/scripts/lib/*.sh|plugins/leadv2/scripts/*.py|plugins/leadv2/hooks/*.sh`),
and that `leadv2-launch-registry.py` (under `scripts/lib/`) would therefore
need a `tests/run-all.sh` edit (blocked file) to self-select.

**This assumption is wrong, empirically verified this session.** Bash's
`[[ string == pattern ]]` matching does **not** respect `/` as a path
boundary the way filename globbing does — `*` matches across `/`. Confirmed
directly:

```
$ bash -c 'cf="plugins/leadv2/scripts/lib/leadv2-launch-registry.py"
[[ "$cf" == plugins/leadv2/scripts/*.py ]] && echo MATCHES'
MATCHES
```

So the existing generic allowlist entry `plugins/leadv2/scripts/*.py`
**already** matches `plugins/leadv2/scripts/lib/leadv2-launch-registry.py`,
producing `stem="leadv2-launch-registry"` (extension stripped) — which
matches my suite's `# run-all-triggers: leadv2-launch-registry` header
exactly. **No `tests/run-all.sh` edit is needed for either new suite.**

I verified this empirically, not just by reading the code: staged only the
two production files (no test files in the diff — simulating a *future*
commit that touches production without touching its own test), ran
`LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed`, and
confirmed both suites self-select purely via the trigger mechanism:

```
[SELECT] .../plugins/leadv2/tests/test-claude-account-states.sh
[SELECT] .../plugins/leadv2/tests/test-launch-registry-argv.sh
run-all: 6 selected, scope=changed, select_only=1
```

(4 of the 6 are always-on suites unrelated to this change — SWIFTBAR-*,
run-core-offline.sh — selected regardless of scope.)

**One real bug this caught in my own work**: my first draft of
`test-claude-account-states.sh` declared `# run-all-triggers:
leadv2-quota-read.py` (with the `.py` suffix), copying the special-cased
convention used for `leadv2-glm-policy-resolve.py` elsewhere in
`run-all.sh`. But `leadv2-quota-read.py` is a top-level `scripts/*.py` file,
which hits the **generic** allowlist branch (stem = basename **minus**
extension, i.e. `"leadv2-quota-read"`), not the special-cased elif chain
that preserves the `.py` suffix for a handful of individually-named data/lib
files. The mismatched trigger meant the suite silently failed to self-select
under `--scope changed` for its own production file's changes (only worked
in my first test because the new test file itself was also in the diff,
which self-selects via a separate rule). Fixed to `# run-all-triggers:
leadv2-quota-read` (no suffix) and re-verified empirically as shown above.
**No `tests/run-all.sh` patch is required for anything in this lane** — the
above was entirely a fix to my own suite's trigger declaration.

## Verification (paste, red-then-green where applicable)

### Syntax / compile — all four LANE_WRITES files

```
$ bash -n plugins/leadv2/tests/test-launch-registry-argv.sh && echo OK
OK
$ bash -n plugins/leadv2/tests/test-claude-account-states.sh && echo OK
OK
$ python3 -m py_compile plugins/leadv2/scripts/lib/leadv2-launch-registry.py && echo OK
OK
$ python3 -m py_compile plugins/leadv2/scripts/leadv2-quota-read.py && echo OK
OK
```

### Suite runs (both green, 23/23)

```
$ bash plugins/leadv2/tests/test-launch-registry-argv.sh
PASS: fable+plan -> --model fable (never sonnet)
PASS: sonnet+code standard -> --model sonnet, medium effort
PASS: haiku+recon -> --model haiku, low effort
PASS: codex+review heavy -> cheapest heavy-capable tier (standard), no --reason
PASS: check(fable, sonnet) -> refuse
PASS: check(fable, fable) -> ok
PASS: check(glm, *) -> not_applicable (glm family out of scope, documented)
PASS: fable+code -> not_a_build_arm (fable is a plan-only arm)
PASS: glm+code -> adapter_argv_not_registered (glm family intentionally out of scope)
PASS: opus lookup carries pool_default:false (data only -- admission wiring is part B)
PASS: fable lookup carries pool_default:true (no override recorded)
PASS: _argv_codex(tier=top) appends the required --reason, effort_supported=False
PASS: negative control: mutated _argv_claude (hardcoded sonnet) is caught by the exact-argv assertion, not by an arm=fable string match
----
PASS=13 FAIL=0

$ bash plugins/leadv2/tests/test-claude-account-states.sh
PASS: _keychain_services() admits the ambient prefix + registered slot, excludes the stale zzz999 entry
PASS: missing registry file fails OPEN (unfiltered enumeration), never drops every account to zero
PASS: team+401 -> unmetered (TEAM-ACCOUNT-QUOTA-WINDOW-UNPARSED-01, priced conservatively)
PASS: pro+401 -> unknown (an ordinary dead credential, keeps today's penalty)
PASS: team+200 -> ok
PASS: team+429 -> unknown (rate-limited, never priced as unmetered)
PASS: -(unresolved subscription)+401 -> unknown
PASS: unmetered pricing carries no unknown-probe penalty and is not measured (conservative, configured-allowance basis)
PASS: negative control: mutated _keychain_services (filter defeated) is caught -- stale zzz999 re-admitted, real probe assertion would fail
PASS: negative control: mutated classify_account_state (team+401 collapsed) is caught -- reports unknown, real pricing assertion would fail
----
PASS=10 FAIL=0
```

### Negative controls, isolated red-then-green

Each control mutates the real module's function body (never top level),
re-runs the assertion, requires it to *disagree* with the correct/expected
value (i.e. proves the assertion would report RED against exactly this
class of regression), then the outer suite reports PASS on the meta-check
that detection worked. All three:

1. `_argv_claude` hardcoded to `"sonnet"` -> `test-launch-registry-argv.sh`'s
   exact-argv assertion disagrees (mismatch: expected `fable`, mutant
   produced `sonnet`) -> negative control PASS (detection proven).
2. `_keychain_services`'s `allowed = allowed | {prefix}` replaced with
   `allowed = services` -> probe assertion disagrees (mutant re-admits the
   stale `zzz999` service) -> negative control PASS.
3. `classify_account_state`'s team+401 branch replaced with `if False:` ->
   pricing assertion disagrees (mutant reports `"unknown"` instead of
   `"unmetered"`) -> negative control PASS.

All three shown above inline in the two suite runs (each suite's last two
or three PASS lines are the negative-control meta-checks).

### `--scope changed` self-registration proof (both suites, no production
files' own test file needed in the diff)

```
$ git status --porcelain   # only production files staged, test files untracked
 M plugins/leadv2/scripts/leadv2-quota-read.py
A  plugins/leadv2/scripts/lib/leadv2-launch-registry.py
?? plugins/leadv2/tests/test-claude-account-states.sh
?? plugins/leadv2/tests/test-launch-registry-argv.sh

$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
[SELECT] .../plugins/leadv2/tests/test-claude-account-states.sh
[SELECT] .../plugins/leadv2/tests/test-launch-registry-argv.sh
run-all: 6 selected, scope=changed, select_only=1
```

### `LEADV2_RUN_ALL_LIST_TRIGGERS` (self-registration discovered correctly)

```
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | grep -E "launch-registry|quota-read"
leadv2-quota-read:plugins/leadv2/tests/test-claude-account-states.sh
leadv2-launch-registry:plugins/leadv2/tests/test-launch-registry-argv.sh
```

## Scope limits stated explicitly (not oversights)

- glm/glm-flash/freepool are out of `_FAMILY_BUILDERS` — brief's stated
  scope is Anthropic + Codex models only; their adapter argv shapes were not
  independently verified to the same standard and fabricating one would be
  worse than declining (`adapter_argv_not_registered` / `not_applicable`).
- Removing the pre-arbiter opus park (`leadv2-dispatch-code.sh:8386-8417`)
  and actually consulting `pool_default()` before admission is PART B —
  this lane only records the fact as data.
- Wiring `classify_account_state`'s output into the arbiter's pricing
  decision (`lib/leadv2-route-arbiter.sh`) is PART B — this lane only
  exposes the classification as a callable/CLI result, additive to the
  existing `status` field.

## Constraints honored

- No `git add -A` — every path named explicitly in every `git add`.
- No `reset --hard`/`clean`/`stash`/`worktree prune`/push.
- `claude-profiles.tsv` content never printed or committed; all references
  in code/tests/this report use synthetic hermetic fixtures or slot labels
  only (`personal`/`work`, or synthetic dir-hash-shaped suffixes like
  `aaa111`/`zzz999` — never a real dir-hash or credential value).
- `.env`/credentials read-only; no token ever echoed (all classifier tests
  use synthetic `http_code`/`subscription_type` values, never a real token).
- `docs/leadv2/.compact-freeze.md` was touched by a session hook
  (unrelated to this lane's scope) — left untouched, not staged, not
  committed.

DELIVERABLE_COMPLETE
