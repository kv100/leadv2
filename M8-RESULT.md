# M8-RESULT — fix round 1: the skill proof gate

**Worktree:** `0e61446b` · **Branch:** `worktree-0e61446b`
**Date:** 2026-08-03

## Verdicts per finding

### F1 — non-portable millisecond clock → **PASS**

Added `now_ms()` helper with output-shape validation across 4 tiers (GNU date
`%3N` → perl `Time::HiRes` → python3 → POSIX `%s` × 1000). Replaced the dead
`date +%s%3N || python3` calls in `execute_proof`. Duration computation is now
shape-guarded: if either endpoint fails `^[0-9]+$`, `PROOF_DURATION_MS` degrades
to 0 instead of aborting.

No "value too great for base" errors appear in any run output.

### F2 — `case "$1"` under `set -u` → **PASS**

Deleted the `$# -eq 0` special case and the duplicated `do_run || exit $?; exit 0`
tail. Rewrote to `case "${1:-run}"` with a single `do_run` call site. Bare
invocation, `run`, and `--only X` all converge on one entry/exit path.

No "unbound variable" errors appear in any run output.

### F3 — exit code always 0 (lying-green) → **PASS**

Added `RUN_COMPLETED=0` sentinel + `trap '_final' EXIT`. `do_run` sets
`RUN_COMPLETED=1` only on the line before its final return. If the `run`
subcommand exits 0 without completing, the trap converts to exit 2.

Verified: (a) GREEN exits 0, (b) RED-FAILED exits 1, (e) mixed exits 1, bare
real-tree run exits 1.

### F4 — shellcheck → **PASS**

- SC2034 `exit_code`: deleted the dead variable.
- SC2034 `SUBCOMMAND`: resolved by using it (trap gates on it, arg-parse sets it).
- SC2317 `do_validate` unreachable: removed redundant `exit $?` — `do_validate`
  always exits internally.
- SC2317 `do_list` / new SC2329 `_final`: `_final` is invoked via
  `trap '_final' EXIT`; justified inline with `# shellcheck disable=SC2329`.

`shellcheck -x` clean.

### F5 — harness pipefail bug on (c) REFUSED → **PASS**

**This is a test fix, not a test weakening.** The gate correctly exits 3 for a
refused proof. Under `set -o pipefail`, the pipeline
`bash "$GATE" validate ... 2>&1 | grep -qi 'REFUSED'` inherits exit 3 from the
left side regardless of grep's result, making the `if` always false. Fixed by
capturing output first: `out=$(... ) || true` then `grep -qi 'REFUSED' <<<"$out"`.

This *strengthens* observability: the assertion now actually tests the REFUSED
message instead of being structurally impossible to satisfy.

## Verification step output

### Step 1: shellcheck

```
$ shellcheck -x plugins/leadv2/scripts/leadv2-skill-proof.sh
$ echo $?
0
```
Clean.

### Step 2: test suite

```
$ bash plugins/leadv2/scripts/tests/test-skill-proof-gate.sh
[TEST] PASS: bash -n: leadv2-skill-proof.sh
[TEST] PASS: bash -n: leadv2-proof-lib.sh
[TEST] PASS: shellcheck: leadv2-skill-proof.sh
[TEST] PASS: shellcheck: leadv2-proof-lib.sh
[TEST] PASS: (a) valid+passing → GREEN, exit 0
[TEST] PASS: (b) valid+failing → RED-FAILED, exit 1
[TEST] PASS: (c) validate → exit 3 (refused)
[TEST] PASS: (c) full run → RED-INVALID
[TEST] PASS: (c) validate prints refusal message
[TEST] PASS: (d) no-proof → RED-NO-PROOF, exit 1
[TEST] PASS: (e) mixed tree → exit 1
[TEST] PASS: (e) mixed tree → green=1
[TEST] PASS: (e) mixed tree → red=2
[TEST] PASS: (f) step 1: GREEN recorded in state
[TEST] PASS: (f) step 3: hash mismatch → RED-NEVER-RUN
[TEST] PASS: list subcommand → correct matrix
[TEST] ----
[TEST] PASS=16 FAIL=0
$ echo $?
0
```

### Step 3: bare invocation on real skills tree

```
$ bash plugins/leadv2/scripts/leadv2-skill-proof.sh; echo "rc=$?"
──────────────────────────────────────────────────────────────────────────
SKILL                               STATUS           TIME  REASON
──────────────────────────────────────────────────────────────────────────
audit-cluster                       RED-NO-PROOF        -  no PROOF.sh in skill directory
...
leadv2-memory-gc                    GREEN           1339ms  exit 0
leadv2-negative-memory              GREEN            583ms  exit 0
...
leadv2-premortem                    RED-FAILED       147ms  exit 1
...
writing-great-skills                RED-NO-PROOF        -  no PROOF.sh in skill directory
──────────────────────────────────────────────────────────────────────────

green=2 red=38 (no-proof=37 failed=1 invalid=0 never-run=0) skills=40
rc=1
```

**Note on leadv2-premortem RED-FAILED:** This is a pre-existing defect in the
premortem script (returns exit 1 where the proof expects exit 2 for
skip_recommended). It is unrelated to this fix round — the F3 lying-green bug
previously hid it. The gate now correctly surfaces it. Fixing it is out of scope
(non-goal: "No change to what the three existing proofs assert").

The acceptance criterion "three skills shown as GREEN" was written assuming all
three proofs pass. `leadv2-memory-gc` and `leadv2-negative-memory` are GREEN;
`leadv2-premortem` has a pre-existing script/proof mismatch. The gate behavior
(table printed, non-zero exit, no arithmetic errors) is correct.

### Step 4: break/restore leadv2-memory-gc

**Break** (changed `"--model"` to `"--m"` at line 327 of
`leadv2-memory-index-gc.py` — the model flag no longer reaches the CLI stub):

```
$ bash plugins/leadv2/skills/leadv2-memory-gc/PROOF.sh; echo "rc=$?"
memory-index-gc: dry-run report .../memory-gc-report.md
[PROOF-FAIL] --model haiku flag reached the CLI (needle=<--model haiku> not found in haystack)
rc=1
```

**Restore** (`git checkout -- plugins/leadv2/scripts/leadv2-memory-index-gc.py`):

```
$ bash plugins/leadv2/skills/leadv2-memory-gc/PROOF.sh; echo "rc=$?"
memory-index-gc: dry-run report .../memory-gc-report.md
[PROOF] leadv2-memory-gc: all assertions passed
rc=0
```

`git status` confirmed clean of the temporary break.

### Step 5: run-core-offline.sh

```
$ bash plugins/leadv2/scripts/tests/run-core-offline.sh
...
[CORE-OFFLINE] skill proof gate unit tests
[TEST] PASS=16 FAIL=0
...
[CORE-OFFLINE] suites passed=24 failed=0 missing=0
exit=0
```

24/0 — no worse than main (22/0 baseline); actually 2 better because the
skill-proof-gate suite is now fully green and counted. `test-no-work-terminal.sh`
did not fail.

## Changed paths

| path | change |
|---|---|
| `plugins/leadv2/scripts/leadv2-skill-proof.sh` | `now_ms()` + shape-guarded duration (F1); arg-parse rewrite, single exit path (F2); `RUN_COMPLETED` sentinel + EXIT trap (F3); shellcheck cleanup (F4) |
| `plugins/leadv2/scripts/tests/test-skill-proof-gate.sh` | pipefail fix at (c) REFUSED assertion (F5) |
| `plugins/leadv2/docs/skill-proof-dod.md` | documented portable-clock rule and enforced exit-code table |

## Commit SHA

`327d6d7`
