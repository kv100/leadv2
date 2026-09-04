verdict: APPROVE
next_action: review_round_2

# REVIEW-MISSING-DIFF-WRITES-NO-MISSION-01 round 3 — shellcheck gate un-silenced

## What was wrong (confirmed)

Both `test-review-roundcap.sh` and `test-review-round-exhaustive.sh` widened the shellcheck
exclusion list from main's baseline `SC1091,SC2034,SC2094` to
`SC1091,SC2034,SC2094,SC2016,SC2004` — file-wide, in files outside this lane's declared write
set. Reverted both back to the baseline.

## Premise correction (measured, not assumed)

Mission stated "the three SC2016 are printf lines... the two SC2004 are array-index style: ...
and its sibling." Measured on this branch before any fix:

```
$ shellcheck -x -e SC1091,SC2034,SC2094 -f json plugins/leadv2/scripts/leadv2-review-run.sh | \
    python3 -c "import json,sys; [print(i['line'],i['code']) for i in json.load(sys.stdin)]" | grep -E "2016|2004"
1296 2016
1298 2016
1584 2004
```

Only **2** SC2016 and **1** SC2004 exist, not 3/2. I grepped for a "sibling" `ran_arms[${...}]`
write-context and found only reads (`ran_arms[${_ran_index}]` at line 1551, an rvalue — shellcheck
does not flag reads the same way) — no second SC2004 write site exists. I fixed exactly what
shellcheck reports rather than fabricate a second edit to match the mission's count.

## Fixes applied (leadv2-review-run.sh only)

- Lines 1296/1298 (falsifiability gate copy, `printf '...backtick...$?...'`): added a
  `# shellcheck disable=SC2016` comment on its own line immediately above each printf, with a
  one-line reason. (First attempt put the reason inline after `--` on the directive line itself —
  shellcheck's directive parser chokes on literal backticks/`$` in that position, SC1072/SC1073.
  Moved the reason to a separate comment line above the directive; directive line now contains
  only `# shellcheck disable=SC2016`.)
- Line 1584: `ran_arms[${_ran_index}]="${_arm}"` → `ran_arms[_ran_index]="${_arm}"` (arithmetic
  context already expands the bare name; no-op at runtime).

Nothing else in `leadv2-review-run.sh` changed — the T12 fallback (line ~1345,
`REVIEW_DIFF_HASH_OK` gate around the DoD-gate call) is untouched from round 2.

## Proof: shellcheck exits 0 at main's baseline

```
$ shellcheck -x -e SC1091,SC2034,SC2094 plugins/leadv2/scripts/leadv2-review-run.sh
$ echo $?
0
```

(no output, clean exit)

## Proof: 30 consecutive-run count lines (10 each)

`test-review-round-exhaustive.sh` x10:
```
review-round-exhaustive: PASS=24 FAIL=0   (x10, all identical)
```
`test-review-roundcap.sh` x10:
```
review-roundcap: PASS=14 FAIL=0   (x10, all identical)
```
`test-codex-dead-reroute.sh` x10:
```
=== 11 passed, 0 failed ===   (x10, all identical)
```
Verified via `grep -c` on the captured log: `PASS=24 FAIL=0` → 10, `PASS=14 FAIL=0` → 10,
`passed, 0 failed` → 10.

## Negative control for T12 (mandatory) — tool incompatibility found and worked around, documented

Attempted via `plugins/leadv2/scripts/leadv2-mutation-control.sh` first, as required:

```
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh \
    plugins/leadv2/scripts/leadv2-review-run.sh \
    's/"${REVIEW_DIFF_HASH_OK:-0}" -eq 1 && -f "${_DOD_GATE_SH}"/-f "${_DOD_GATE_SH}"/' \
    docs/handoff/dispatch-3011c36c/mutation-control
MUTATION-CONTROL control_not_applied reason=baseline_not_green baseline_rc=1
...
FAIL: T7 red-first: git archive 85ae886 extraction failed
review-round-exhaustive: PASS=16 FAIL=1
```

Root cause (verified, not assumed): the tool's scratch clone is a **fresh `git init` with one
commit** of the current working tree (its own comment says so, "never `git worktree add`"). T7 in
this suite does `git -C "${LEADV2_REPO}" archive "${LEADV2_TEST_BASELINE_REF}" ...` where
`LEADV2_REPO` resolves to the git toplevel of the *running* script's directory — inside the
scratch, that's the scratch's own one-commit repo, which has no `85ae886` object. I confirmed this
is unrelated to my mutation by re-running the unmutated suite through the same tool logic
(exporting `LEADV2_TEST_BASELINE_REF=HEAD` into the scratch run): T7 still fails, just with the
opposite symptom (baseline cases unexpectedly pass because "baseline" == current fixed code, not
older/broken code). **This suite's T7 pattern (diff against real git history) is structurally
incompatible with `leadv2-mutation-control.sh`'s single-commit scratch snapshot — this predates my
change and is not something in this lane's write set to fix.**

Given that, I ran the equivalent control manually, directly in the worktree (not a scratch/copy —
captured before/after, restored the file to the committed state immediately after, verified via
`git diff --stat` that `leadv2-review-run.sh` shows zero diff afterward):

```
$ cp leadv2-review-run.sh leadv2-review-run.sh.orig      # snapshot of the committed fix
$ bash test-review-round-exhaustive.sh; echo baseline_rc=$?
review-round-exhaustive: PASS=24 FAIL=0
baseline_rc=0

$ sed -i.bak 's/"${REVIEW_DIFF_HASH_OK:-0}" -eq 1 && -f "${_DOD_GATE_SH}"/-f "${_DOD_GATE_SH}"/' leadv2-review-run.sh
$ diff leadv2-review-run.sh.orig leadv2-review-run.sh
1345c1345
< if [[ "${REVIEW_DIFF_HASH_OK:-0}" -eq 1 && -f "${_DOD_GATE_SH}" ]]; then
---
> if [[ -f "${_DOD_GATE_SH}" ]]; then

$ bash test-review-round-exhaustive.sh; echo mutated_rc=$?
...
FAIL: T12 missing diff file -> exhaustive, no sidecar, stderr
review-round-exhaustive: PASS=23 FAIL=1
mutated_rc=1

$ grep '^FAIL' <mutated output>
FAIL: T12 missing diff file -> exhaustive, no sidecar, stderr
```

`baseline_rc=0` / `mutated_rc=1`, exactly and only T12 red — a real assertion failure ("FAIL: T12
..."), not a crash/stack-trace. This is inside-the-function-body mutation (the `REVIEW_DIFF_HASH_OK`
guard on the DoD-gate call, which is the exact condition round 2's T12 fix depends on), never a
top-level/no-op edit.

File restored immediately after capture: `cp leadv2-review-run.sh.orig leadv2-review-run.sh; rm
leadv2-review-run.sh.bak`. Confirmed clean via `git diff --stat` (empty for this file) and a
final green re-run: `PASS=24 FAIL=0`.

## Self-check falsification

```
$ bash -n plugins/leadv2/scripts/leadv2-review-run.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-review-roundcap.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh && echo OK
OK
```
No Python files changed.

## Final diff scope

```
$ git diff --name-only main...HEAD
docs/handoff/dispatch-e525df4d/t12-mutation-probe.sh      (pre-existing, from facd6096/d76d7bd3, not touched this round)
plugins/leadv2/scripts/leadv2-review-run.sh
plugins/leadv2/scripts/tests/test-codex-dead-reroute.sh   (pre-existing, from facd6096/d76d7bd3, not touched this round)
plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh
plugins/leadv2/scripts/tests/test-review-roundcap.sh
```
Matches the constraint exactly: only the 4 named scripts + docs/handoff/. Did not touch
`tests/run-all.sh`, `known-red-suites.txt`, `main`, or `docs/leadv2/`.

## Commits

```
79163fc1 fix(review): satisfy shellcheck baseline instead of widening exclusions
facd6096 fix(review): missing/unreadable diff file must degrade to exhaustive round 1, not silence
d76d7bd3 fix(review): missing/unreadable diff file must degrade to exhaustive round 1, not silence
```
My new commit is 79163fc1, containing only the 3 files: leadv2-review-run.sh,
test-review-round-exhaustive.sh, test-review-roundcap.sh.

## Left alone / not merged

- Did not merge to main.
- Did not touch `tests/run-all.sh` or `docs/leadv2/`.
- Did not modify `leadv2-mutation-control.sh` despite finding a real T7-scratch incompatibility —
  out of this lane's write set; flagging it here for the founder/lead as a separate finding, not
  fixing it under this task.

DELIVERABLE_COMPLETE
