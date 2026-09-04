# SUITE-THAT-CANNOT-FAIL-01 — report

A suite that cannot go red must not be accepted as evidence.

## What was built

| File | Role |
|------|------|
| `plugins/leadv2/scripts/leadv2-suite-falsifiable.sh` | Behavioural falsifiability checker for a single suite file |
| `plugins/leadv2/scripts/leadv2-review-run.sh` (+55 lines) | Gate wired before pool resolve: a changed suite that cannot go red cannot reach `status: pass` |
| `plugins/leadv2/scripts/tests/test-suite-falsifiable.sh` | Test suite, fixtures only (never a real lane, never the real review) |
| `tests/run-all.sh` | Two `EXTRA_SUITE_MAP` rows so `--scope changed` selects the new suite when `leadv2-review-run.sh` or `leadv2-suite-falsifiable.sh` changes |

Note: an earlier session on this lane had left uncommitted drafts (a checker
whose grep shim recursed into itself and counted "output differs, exit 0" as
falsifiable; a test suite that printed `✗ FAIL` but always exited 0 — the
exact disease this lane removes). Both files were rewritten from scratch.

## 1. The falsifiability check — mechanism

`leadv2-suite-falsifiable.sh <suite>` decides from **behaviour only** — the
suite's source is never inspected (no grep of source text, no naming
convention, no `PASS/FAIL` line counting):

1. **Baseline** — run the suite as-is (`bash <suite>`, cwd = suite dir),
   watchdog-timed (`LEADV2_SUITE_FALSIFIABLE_TIMEOUT`, default 60s).
2. **Injection battery**, each a full re-run:
   - `assertion_tools_broken` — a PATH-front shim dir makes `grep egrep
     fgrep diff cmp` exit 1. Every shim invocation is logged to a marker
     file, so "the suite really called a sabotaged tool" (engaged) is
     distinguishable from "never touched" — the engagement count is printed
     in the verdict.
   - `empty_cwd` — the suite runs from a directory containing nothing.
   - `stripped_env` — `env -i`: only PATH/HOME/TMPDIR survive.

**Exit codes:** `0` falsifiable (some injection turned a green baseline
red) · `1` NOT falsifiable (green baseline, green under every injection) ·
`2` could-not-determine (missing file, timed out, or **already red at
baseline** — falsifiability cannot be assessed from a failing run; never a
pass, never an accusation) · `3` usage.

### Why these injections, and the false-accusation story

- **Setup tools are deliberately NOT sabotaged** (`mktemp`, `mkdir`,
  `dirname`, `rm`, `cp`, interpreters). If they were, the 0d61b3c suite —
  `set -euo pipefail` with fragile setup and vacuous `|| true` assertions —
  would crash non-zero under injection and be *declared falsifiable while
  asserting nothing*. Restricting the failing shims to the canonical
  assertion tools keeps "setup crashed" separate from "assertion fired";
  the empty-cwd and stripped-env probes likewise leave TMPDIR/HOME/PATH
  intact so ordinary setup survives.
- **A red under injection is counted as falsifiable even if we cannot prove
  which assertion fired.** This errs toward the safe direction for the
  worker (we never call an honest suite a liar); the opposite error (calling
  a lying suite honest) requires the suite to stay exit 0 while *everything
  we can reach* is broken — which is precisely the claim "not falsifiable"
  makes.
- **Honest suite that legitimately asserts via pure builtins** (inline
  logic, no external tool, no cwd/env/file dependence) is a real blind spot:
  no generic environmental probe can engage it, and it would be reported not
  falsifiable. This is documented rather than hidden: a lane writing such a
  suite makes it checkable by asserting through any of the sabotaged tools
  (e.g. `grep -q`/`diff` against expected output) — which is how the suite
  would have to assert against real production output anyway. The verdict
  output names the probes and the engagement count so a human can see the
  difference between "engaged and ignored" and "nothing engaged".
- Baseline red ⇒ exit 2 (undetermined), not an accusation: a suite failing
  for an unrelated reason (missing dependency — acceptance case 4) is
  neither passed nor falsely accused.

## 2. Wiring — where the lying green actually enters

`leadv2-review-run.sh` is the sole owner of the verdict; the gate is wired
in Main, after the machine round-0 selfcheck block and **before pool
resolve**, so a refusal never spends a reviewer arm.

**What a review round is responsible for — keyed on `--diff DIFF_FILE`:**
the engine parses `+++ b/<path>` lines of the round's own diff and selects
paths matching the repo's test-suite locations
(`tests/test-*.sh`, `plugins/leadv2/scripts/tests/test-*.sh`,
`.claude/scripts/tests/test-*.sh`, `plugins/leadv2/tests/test-*.sh`).
Deletions (`/dev/null`) and files absent from ROOT are skipped. So:

- **never blocks on a suite the lane did not touch** — only suites in this
  round's diff are evaluated; pre-existing debt cannot fail an unrelated
  lane;
- **never silently skips** — every selected suite is run through the
  checker; rc 1 ⇒ `status: fail` + `reason: suite_not_falsifiable`,
  exit 7 (counts as a review attempt via `_review_state_write`, mirroring
  `selfcheck_red_round0`); rc ≥ 2 ⇒ `status: blocked` +
  `reason: suite_falsifiability_undetermined`, exit 8 — a visible state
  that is not an implicit pass.

## 3. Legibility

The refusal written into `review-gate.md` (and the checker's own output)
tells the worker exactly what is missing: the suite's exit code did not
change under failure injection (assertion tools broken / empty cwd /
stripped env), a printed `FAIL:` line that leaves `$?` at 0 is not an
assertion, and how to fix it (exit 1 on failure, or let the failing command
propagate — no `|| true` around the checked command).

## 4. Selection — EXTRA_SUITE_MAP

```
leadv2-review-run.sh:plugins/leadv2/scripts/tests/test-suite-falsifiable.sh
leadv2-suite-falsifiable:plugins/leadv2/scripts/tests/test-suite-falsifiable.sh
```

Proof (scratch git repo containing the real `tests/run-all.sh` + the new
suite, with ONLY `plugins/leadv2/scripts/leadv2-review-run.sh` modified —
the suite file itself clean, so self-selection cannot explain the hit):

```
$ bash tests/run-all.sh --scope changed   # in scratch repo
[RUN] .../plugins/leadv2/scripts/tests/test-suite-falsifiable.sh
```

## 5. Test suite — `test-suite-falsifiable.sh`

All eight acceptance cases plus usage-error paths (20 assertions), each a
real assertion (expected-vs-actual exit codes, gate-file content); any
failure makes the suite exit 1. **Case 8 is self-application:** the suite
runs the checker on itself and requires `falsifiable` — this suite obeys
its own rule. Recursion is cut by a TMPDIR sentinel file (the checker's
`env -i` probe deletes environment variables, so an env-var-only guard
would re-open recursion under exactly that probe); nested runs still
execute the checker cases 1–4, so the suite remains observably red-able
while probed.

## 6. Verification (raw evidence in lane chat)

- Checker on the four fixture shapes: honest→rc 0, printer→rc 1,
  resume-lane exact shape→rc 1, missing-dep→rc 2.
- Suite: **20 passed, 0 failed**, exit 0 (~90s).
- Mutation 1 (gate's rc-1 branch made unreachable — equivalent to removing
  the gate): case 5 RED (3 FAIL, suite exit 1). Reverted → green.
- Mutation 2 (checker's NOT-FALSIFIABLE verdict exits 0 instead of 1): 6
  FAIL including end-to-end case 5 (lying suite sails to pass). Reverted →
  green (20/0).
- `bash -n` and `/bin/bash -n` (3.2) clean on all four shell files;
  no Python files changed.
- Repo changed-scope runner (`tests/run-all.sh --scope changed`): see
  final chat report for the raw tail.

## 7. Limitations owned

- Pure-builtin inline-logic suites are a blind spot (§1) — reported not
  falsifiable; the engagement count in the verdict output makes this legible.
- The gate runs the changed suites up to 4× each (baseline + 3 probes);
  with the 60s default watchdog a pathological suite can cost up to ~4 min
  in review. Honest suites finish in their normal runtime.
- If the checker script is absent, the gate block degrades to a no-op
  (same guarded-source pattern as `leadv2-review-findings.sh` in this
  engine) — the engine stays runnable from a bare checkout.
