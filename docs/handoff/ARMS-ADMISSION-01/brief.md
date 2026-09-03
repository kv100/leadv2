# ARMS-ADMISSION-01 — glm-flash is built but never a candidate, and `--protected` bans free arms wholesale

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ARMS-ADMISSION-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/config/routing.yaml,plugins/leadv2/scripts/tests/test-arm-admission.sh,tests/run-all.sh,docs/handoff/ARMS-ADMISSION-01/

Main is `95ed6f310` in `~/Projects/leadv2`. Branch from it.

This lane closes two backlog rows at once — `ROUTER-ARBITER-DISAGREE-ON-FREEPOOL-01` and the
unmet half of `FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01` — plus the founder's standing ask that
glm-flash 5.3 actually run. Founder's framing: every task a free arm completes is money not
spent on a paid subscription's quota.

## Three findings, each with its line

**1. glm-flash is fully built and connected to nothing.** `leadv2-dispatch-code.sh:1959`:

```bash
_resolver_args=(--routing-yaml "${ROUTING_YAML}" --job build --base-arm glm --signals "${signals_json}")
```

`--base-arm glm` is hardcoded, so the policy resolver never receives `glm-flash` as a
candidate and returns only glm/sonnet/codex/kimi/opus. Everything else for the arm exists:
`glm-coder.sh:102` describes it as the cheap/mechanical tier, `leadv2-dispatch-product-close.sh:719`
knows its launcher, `dispatch-code.sh:2721` knows its branch. One argument keeps it out.

**2. `--protected` bans untrusted arms wholesale.** `leadv2-dispatch-code.sh:2056-2075` drops
every untrusted arm when `DC_PROTECTED=1`, with `reason=protected_path`. freepool and
glm-flash are untrusted, and every lane that edits plugin scripts is protected — so those arms
have never been candidates at all. `util_freepool=0` means "never offered", not "idle".

**3. The router and the arbiter disagree about `light`.** The router excludes freepool as
`arm_not_capable_for_size` for `task_class=light` (its `when:` list is `[standard, bulk]`),
while the arbiter's `SIZE_MAP` maps `light → standard` and would admit it. Find both decision
points, quote them, and make them agree — the disagreement is the row
`ROUTER-ARBITER-DISAGREE-ON-FREEPOOL-01`.

## [Critical] `--protected` must mean "does not write production code", not "does not exist"

Split the flag's meaning. An untrusted arm stays barred from writing production files on a
protected lane, and remains admissible for work that writes nothing dangerous — review, audit,
census, discovery. Decide from the work kind and the lane's `LANE_WRITES`, not from a
hand-kept list of arm names; the founder has a standing rule against hardcoding an arm out of
routing.

## [Critical] glm-flash must be able to win a task it deserves

Stop pinning `--base-arm glm`. The base arm has to come from the same routing data every other
choice comes from, so glm-flash competes as the cheap/mechanical tier it was built to be. Do
not special-case it into first place either — it wins when the routing data says it wins.

## [Medium] router and arbiter agree on size

One source of truth for whether an arm is capable at a given `task_class`. Say in `report.md`
which side you made authoritative and why.

## Acceptance

Build `test-arm-admission.sh` against fixture routing data — never the live proxy, never a
real dispatch — covering:

1. a protected lane whose work writes production code ⇒ untrusted arms excluded, as today;
2. a protected lane whose work is review/audit only ⇒ an untrusted arm IS a candidate;
3. `task_class=light` ⇒ router and arbiter return the same admission verdict for freepool;
4. a mechanical build task ⇒ `glm-flash` appears among the resolver's candidates;
5. no arm is excluded by a name literal anywhere in the decision path.

Add the `EXTRA_SUITE_MAP` rows for every touched script and prove selection with
`--scope changed`.

## Rules

- Mutation INSIDE the production function body, RED, revert, GREEN, clean `git diff --stat`.
  A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0 — that exact defect shipped in another lane last night.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Never hardcode an arm into or out of routing — quota, task kind and complexity decide.
- The suite must leave every repo path and every real state root byte-identical, on the failure
  path too.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A protected review task can be taken by a free arm, glm-flash appears as a candidate for
mechanical work, router and arbiter agree on `light`, and a mutation that restores any of the
three exclusions turns the suite red with the exit code following.
