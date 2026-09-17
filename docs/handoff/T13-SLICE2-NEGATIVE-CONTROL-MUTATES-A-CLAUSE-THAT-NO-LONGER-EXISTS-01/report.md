# T13-SLICE2-NEGATIVE-CONTROL-MUTATES-A-CLAUSE-THAT-NO-LONGER-EXISTS-01

## Reproduction (before)

Command (from the lane worktree, unmodified branch):

```
timeout 120 bash plugins/leadv2/scripts/tests/test-t13-slice2.sh
[SUMMARY] PASS=14 FAIL=1
[TEST] FAIL: NEGATIVE CONTROL 1: mutated arbiter (no allowed_arms filter) unexpectedly still passed
rc=1 (measured unpiped)
```

Cause class: `never_reaches_subject` — the control's mutation never reached the subject's
behaviour. Verified the sed was a no-op:

```
$ sed 's/ and (allowed is None or c\.get(.arm.) in allowed)//' \
    plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh > /tmp/mut1.sh
$ cmp /tmp/mut1.sh plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh && echo IDENTICAL
IDENTICAL
```

The mutation target clause no longer exists; the real `allowed_arms` filter today lives at
`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:1306`:

```
if allowed is not None: return arm in allowed
```

(inside `_pool_contains`, line 1300 in the same block). The arbiter itself was NOT touched —
it is not the defect.

## Fix

`plugins/leadv2/scripts/tests/test-t13-slice2.sh` — negative control 1 re-pointed and made
self-checking:

1. Mutation target is now the live clause `if allowed is not None: return arm in allowed`,
   removed with `grep -vF` (the previous anchored `sed` form degenerates on BSD sed when the
   pattern is spliced into `^...$` — see also the bsd-sed brace-anchor hazard; `grep -vF`
   drops the exact line deterministically).
2. Before mutating, the control asserts the target is present in the subject with
   `grep -qF`; if absent it emits
   `FAIL: NEGATIVE CONTROL 1: mutation target absent from arbiter (...) — control cannot bite`
   and the suite goes red loudly instead of reporting a colour from a no-op mutant.
3. After mutating, it asserts the target is gone from the mutant
   (`FAIL: ... mutation did not land` otherwise) before running case1 against it.

## One claim, one control, both outputs

Mutation applied inside the lane worktree subject copy (via the suite's own mechanism, which
mutates into `${TMP}` from the registered lane worktree subject — not a detached scratch copy).

Unmutated arbiter passes case 1:

```
[TEST] PASS: allowed_arms excludes glm/freepool from pick and chain
```

Mutated arbiter (filter line removed) fails case 1 — the control bites:

```
[TEST] PASS: NEGATIVE CONTROL 1: mutated arbiter (no allowed_arms filter) correctly fails case1
```

Target-presence proof:

```
$ grep -cF 'if allowed is not None: return arm in allowed' \
    plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh /tmp/route-arbiter.mutated.sh
plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:1
/tmp/route-arbiter.mutated.sh:0
```

## How the control now detects its own target going missing

If a future refactor moves or rewrites the `allowed is not None` filter line, `grep -qF` on the
subject fails and the control emits a hard FAIL naming the missing target — the suite can no
longer silently turn the control into a no-op copy and stay (falsely) green; it goes red with an
explicit "control cannot bite" message until someone re-points it.

## After

Boundary: macOS Darwin 25.6.0 (bash 3.2-compatible suite), per-suite ceiling 120s, lane worktree
`afc9d6610b5c` at commit ee5e46f2 + this fix.

Whole suite re-run (not just the control case):

```
timeout 120 bash plugins/leadv2/scripts/tests/test-t13-slice2.sh
[SUMMARY] PASS=15 FAIL=0
rc=0
```

Changed-scope runner:

```
bash tests/run-all.sh --scope changed
run-all: 5 passed, 0 failed, 0 known-red (allow-listed, non-blocking), 1 known-red-skipped (budget mode, still run by --scope all), 0 gone-green, scope=changed
```

(The one known-red-skipped suite is the pre-existing t13 budget-mode skip, not touched here.)

## Self-check

- `bash -n plugins/leadv2/scripts/tests/test-t13-slice2.sh` → clean (SYNTAX-OK).
- No Python files changed; no `bash -n` failures.
- No state paths touched (docs/leadv2/, docs/LEAD_V2_STATE.md, docs/handoff/dispatch-nw*) —
  only the test file and this report.
