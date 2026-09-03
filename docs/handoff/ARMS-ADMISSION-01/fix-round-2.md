# ARMS-ADMISSION-01 — round 2: the suite never touches the call site it exists to protect

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ARMS-ADMISSION-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/config/leadv2-routing.yaml,plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh,plugins/leadv2/scripts/tests/test-arm-admission.sh,tests/run-all.sh,docs/handoff/ARMS-ADMISSION-01/

HEAD is `8cbeeed`. Main is `7927b0f`.

The production changes look right and the suite is 16/0 with a clean repo-hygiene assertion.
But I ran the control myself and it does not hold.

## [Critical] the glm-flash fix is unproven — restoring the hardcode stays green

`leadv2-dispatch-code.sh:1920` now reads:

```bash
local -a _resolver_args=(... --base-arm "${_base_arm}" ...)
```

I put the old defect back:

```bash
local -a _resolver_args=(... --base-arm glm ...)
```

and re-ran:

```
rc=0
[SUMMARY] PASS=16 FAIL=0
```

Green with the entire point of the lane removed. The suite exercises fixture routing data and
the arbiter, but never the dispatcher's own resolver call — so `_base_arm` could be any
constant and nothing would notice. Your own in-suite `MUTATION` cases mutate the fixture, not
this line, which is why they all report GREEN afterwards.

Add an assertion that drives the real call site: with routing data that should select the
cheap/mechanical tier, the arguments actually handed to the resolver must carry that arm, and
flipping line 1920 back to a literal must turn this suite — **and only this suite** — red.

## [Critical] prove the other two halves at the call site too

The same doubt applies to the rest of the lane, so prove each with an external mutation, not a
fixture edit:

1. `--protected` + review/audit work ⇒ an untrusted arm is a candidate. Mutation: restore the
   wholesale exclusion at the protected-path branch; the suite must go red.
2. router/arbiter agreement on `light`. Mutation: put the `when: [standard, bulk]` restriction
   back on one side only; the suite must go red naming the disagreement.

State in `report.md`, for each of the three, the exact line you mutated and the assertion that
caught it.

## Rules

- Mutation INSIDE the production file on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. A fixture mutation is not a control for a call-site defect.
- A kill counts only if **this suite alone** goes red — if another gate kills your mutation
  first, the control proves nothing about your suite.
- A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Never hardcode an arm into or out of routing — data decides.
- Keep the repo-hygiene assertion you already have; it passed and it is worth keeping.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

Flipping `--base-arm "${_base_arm}"` back to a literal turns this suite red, and the same holds
for the protected-path exclusion and the router/arbiter disagreement — all three pasted, RED
and GREEN, with a clean diff.
