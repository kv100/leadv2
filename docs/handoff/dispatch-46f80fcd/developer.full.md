verdict: APPROVE
next_action: deploy

# SCAN-ROOTS-MAP-MISSES-THE-PLUGIN-TEST-DIR-01 — investigation and fix

## Which side was right: the scanner, or the test's assertion?

Neither of the two hypotheses in the mission ("map is stale" / "scanner stops short")
was correct. `scan_suite_triggers()` in `tests/run-all.sh` (lines 221-240, unchanged
in this diff) already walks all four roots, including
`plugins/leadv2/scripts/tests`:

```
223	  for _dir in "${ROOT}/plugins/leadv2/scripts/tests" \
224	              "${ROOT}/.claude/scripts/tests" \
225	              "${ROOT}/plugins/leadv2/tests" \
226	              "${ROOT}/tests"; do
```

Evidence it actually walks it (run standalone, no pipefail interference):

```
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | wc -l
848
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | grep -c "plugins/leadv2/scripts/tests/"
765
```

So the listing was never wrong. The bug was in
`tests/test-run-all-self-registration.sh`'s own "every scan root that holds a
declared suite must appear in the map" check (added recently per its own
comment, SCAN-ROOT-CAN-BE-DROPPED-SILENTLY-01, 2026-09-04):

```
498	MAP_OUT="$( env LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash "$RUN_ALL" 2>/dev/null )"
...
505	  if ! printf '%s\n' "$MAP_OUT" | grep -qE "^[^:]+:${_r}/"; then
```

This file has `set -uo pipefail` at the top (line 20). `grep -q` exits the
instant it finds its first match. When that match sits early in a large
piped stream — and rows for `plugins/leadv2/scripts/tests/` are exactly that,
since `scan_suite_triggers` visits that root FIRST in its loop — `grep -q`
can close its stdin and exit 0 well before `printf` finishes writing the
remaining ~800 lines. `printf` then dies of SIGPIPE (exit 141), and with
`pipefail` the pipeline's reported exit status is `printf`'s non-zero exit,
not `grep`'s success. The check misreports a real match as a miss. This is
the classic `grep -q` + `pipefail` gotcha — nothing to do with
`scan_suite_triggers`.

### Minimal reproduction (standalone, isolated from run-all.sh entirely)

```
$ bash -c '
set -uo pipefail
MAP_OUT="$(printf "a:plugins/leadv2/scripts/tests/x\n"; for i in $(seq 1 5000); do printf "b%d:tests/y\n" "$i"; done)"
for i in 1 2 3 4 5; do
  if printf "%s\n" "$MAP_OUT" | grep -qE "^[^:]+:plugins/leadv2/scripts/tests/"; then
    echo "iter $i: MATCH rc=$?"
  else
    echo "iter $i: NOMATCH rc=$?"
  fi
done
'
iter 1: NOMATCH rc=141
iter 2: NOMATCH rc=141
iter 3: NOMATCH rc=141
iter 4: NOMATCH rc=141
iter 5: NOMATCH rc=141
```

Same shape (an early match followed by a long tail), same `set -o pipefail`,
same false failure — 5/5. Switching to a here-string removes the pipe
entirely, so there is nothing to SIGPIPE:

```
$ bash -c '
set -uo pipefail
MAP_OUT="$(printf "a:plugins/leadv2/scripts/tests/x\n"; for i in $(seq 1 5000); do printf "b%d:tests/y\n" "$i"; done)"
for i in 1 2 3; do
  if grep -qE "^[^:]+:plugins/leadv2/scripts/tests/" <<<"$MAP_OUT"; then
    echo "iter $i: MATCH"
  else
    echo "iter $i: NOMATCH"
  fi
done
'
iter 1: MATCH
iter 2: MATCH
iter 3: MATCH
```

## Fix

`tests/test-run-all-self-registration.sh` only, one line, with a comment
explaining why (so nobody "cleans it up" back to a pipe later):

```diff
-  if ! printf '%s\n' "$MAP_OUT" | grep -qE "^[^:]+:${_r}/"; then
+  if ! grep -qE "^[^:]+:${_r}/" <<<"$MAP_OUT"; then
```

`tests/run-all.sh` is NOT touched by this fix — diffed byte-identical to its
committed state (`3cb4c49f`) after the negative control below.

This is the third scenario the mission asked me to rule in or out before
touching anything: not a stale map, not a scanner that stops short, but the
test's own assertion using a pipe that races under `pipefail`. Per the
mission's constraint ("touch the self-registration suite if, and only if,
the investigation proves the assertion itself is wrong — in which case say
so loudly"), that is exactly what happened, and this is that explanation.

## Before / after (`bash tests/test-run-all-self-registration.sh`)

Before (measured on `3cb4c49f`, matches the mission's report):
```
test-run-all-self-registration: 11 passed, 1 failed
FAIL: scan roots: declaring root(s) missing from the map: plugins/leadv2/scripts/tests — scan_suite_triggers stopped walking a directory that holds declared suites
```

After (5 consecutive runs, no flakiness):
```
PASS: scan roots: all 3 declaring root(s) contribute rows to the discovered map
test-run-all-self-registration: 12 passed, 0 failed
test-run-all-self-registration: 12 passed, 0 failed
test-run-all-self-registration: 12 passed, 0 failed
test-run-all-self-registration: 12 passed, 0 failed
test-run-all-self-registration: 12 passed, 0 failed
```

## Acceptance evidence

```
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | wc -l
848    # same before and after — run-all.sh was never touched
$ bash tests/test-run-all-self-registration.sh 2>&1 | tail -1
test-run-all-self-registration: 12 passed, 0 failed
```
848 >= 848 (pre-fix value): satisfied. 0 failures: satisfied.

## Negative control (E2E-KILLRATE-01)

Per the mission's template this asks to revert, inside a function body, the
decision that made the directory reachable. Since `scan_suite_triggers` was
not the file I changed, I applied the equivalent control to the actual
mechanism under test: temporarily removed
`"${ROOT}/plugins/leadv2/scripts/tests"` from `scan_suite_triggers()`'s
`for _dir in ...` loop in `tests/run-all.sh` (never committed — reverted
before finishing), to prove the FIXED assertion still catches a genuinely
dropped root rather than just silencing the false positive.

RED (root dropped from scan_suite_triggers, inside its function body, not top-level):
```
FAIL: scan roots: declaring root(s) missing from the map: plugins/leadv2/scripts/tests — scan_suite_triggers stopped walking a directory that holds declared suites
test-run-all-self-registration: 5 passed, 7 failed
```
(7 failures, not 1 — because with that root gone, ~412 suites in
`plugins/leadv2/scripts/tests` also stop parsing/enumerating, cascading into
the other checks earlier in the file. This confirms the assertion is
exercising the real mechanism, not a fixture.)

RESTORE, GREEN:
```
PASS: scan roots: all 3 declaring root(s) contribute rows to the discovered map
test-run-all-self-registration: 12 passed, 0 failed
```

`tests/run-all.sh` after restore, diffed against the pre-control copy:
```
$ diff /tmp/run-all-orig.sh tests/run-all.sh && echo "run-all.sh IDENTICAL to committed state"
run-all.sh IDENTICAL to committed state
```

## Self-check (bash -n / falsification set)

```
$ bash -n tests/run-all.sh && echo "run-all.sh: OK"
run-all.sh: OK
$ bash -n tests/test-run-all-self-registration.sh && echo "test file: OK"
test file: OK
```
No Python files touched. `git diff --stat` shows exactly one file changed:
`tests/test-run-all-self-registration.sh`, +9/-1.

## Constraints honored

- Touched `tests/test-run-all-self-registration.sh` only (permitted explicitly
  by the mission's carve-out, since the assertion itself was proven wrong).
- `tests/run-all.sh` untouched — verified byte-identical to its committed
  state after the negative control.
- Did not touch `plugins/leadv2/scripts/tests/*`, `leadv2-phase8-e2e-gate.sh`,
  `run-core-offline.sh`, `leadv2-dispatch-code.sh`, or
  `core_offline_scope_arg()`.
- No associative arrays / bash4-isms introduced.
- No `git add -A`; staged the single file explicitly, verified
  `git diff --cached --stat` before committing without a pathspec.
- No destructive git operations. Committed on the lane branch
  (`worktree-2fe9ecbd`, commit `fb4f0c7c`).

## Left alone (out of scope, noted not fixed)

Six other `printf ... | grep -q` call sites exist in the same test file
(lines ~378, 384, 394, 405, 443-444, 457, 468). All of them grep over `$out`,
which is the SMALL scratch-repo run-all output (a handful of lines), not the
~850-line real `$MAP_OUT` — the SIGPIPE race needs an early match followed by
a long unread tail, which those call sites don't have. They were not
observed failing and are outside this task's scope, so I left them as-is
rather than doing a drive-by cleanup.

DELIVERABLE_COMPLETE
