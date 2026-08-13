# CORE-OFFLINE-CODEX-RECURSION-01 — fix the one real RED in run-core-offline on plugin main

Repo: `~/Projects/leadv2` (plugin repo — the single source). Branch: `main` @ `58d1e99`.
Class: Standard. Diagnosis-then-fix. Read-then-change, minimal diff.

## Premise (measured, not assumed)

`bash plugins/leadv2/scripts/tests/run-core-offline.sh` on pristine main gives
**passed=20 failed=1 missing=0** — NOT the "8 of 21" the backlog row claims. Correct the
row's premise in your deliverable.

The single failing suite is **Codex full-cycle runner**
(`plugins/leadv2/scripts/tests/test-codex-session-runner.sh`), PASS=6 FAIL=1.

Failing case (test file lines ~171-183): `recursion`.
- Expected: `rc=5`, `calls=1` — the launcher-self-invocation guard fires after ONE codex
  turn.
- Actual: `rc=4`, `calls=6` — the specific guard never fires; the generic stall-streak guard
  trips instead after 6 turns.

## Why this matters (not a test-only cosmetic)

The runner burns 6 real Codex turns before stopping when a child session self-recurses.
`run-core-offline.sh` is the e2e gate on every dispatch, so this one RED makes the gate
false-RED for every worker.

## Two candidate mechanisms — prove which, with runtime evidence, do not code-read your way to a verdict

1. **Log never written.** The failure output contains:
   `leadv2-codex-session-runner.sh: line 432: <tmp>/recursion/docs/handoff/CODEX-SMOKE-RECURSION/codex-session-runner.log: No such file or directory`
   `LOGF` is set at :73 from `TASK_DIR` (:63) and `mkdir -p "$TASK_DIR"` exists at :64 — so
   establish WHY the directory is absent at :432 anyway (PROJECT_ROOT reassigned after :63?
   test harness recreating the tree? cwd change?). If LOGF is empty,
   `_launcher_spawn_detected` (:193) reads nothing and fails OPEN — that alone explains
   rc=4/calls=6.
2. **Detector shape mismatch.** The stub (`test-codex-session-runner.sh` :33-35) emits
   `{"type":"response_item","item":{"type":"function_call","name":"exec_command",...}}`,
   while the detector's post-CODEX-LEAD-RECURSION-FALSEKILL-01 narrowing scans only
   `command_execution.command` fields. If so, the guard is blind to that JSON shape in
   production too — check against a REAL codex JSON stream shape before deciding whether the
   stub or the detector is wrong.

Both may be true. Fix each one you prove; do not "fix" one you did not prove.

## Hard constraints

- **Do not weaken CODEX-LEAD-RECURSION-FALSEKILL-01.** The narrowing exists because the old
  guard killed a child that merely read/grepped/echoed a launcher name. Any detector change
  must keep every existing PASS in that suite green — a bare mention, a `grep`/`sed`/`cat`
  operand, and a briefing that names a launcher must still NOT trip it.
- **Do not change the test's expectation to match the code** unless you first prove the
  expectation is the wrong one, and say so explicitly with evidence.
- Minimal diff. No new `PE_*`/`LEADV2_*` flag.

## Acceptance (all four, evidence pasted into the deliverable)

1. `bash plugins/leadv2/scripts/tests/test-codex-session-runner.sh` → `FAIL=0`.
2. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` → `failed=0`, and passed is still
   >= 20 (no suite silently disappeared).
3. **Non-tautological proof**: the recursion test FAILS against pre-fix HEAD and PASSES
   after — run both, paste both result lines. Do it in an isolated tree, never by swapping
   files in the shared main checkout.
4. If mechanism 2 is real: one added assertion covering the *production* JSON shape, plus a
   re-run of the FALSEKILL-01 negative cases showing they still do not trip.

## Deliverable

`docs/handoff/CORE-OFFLINE-CODEX-RECURSION-01/diagnosis.md` — root cause with the runtime
evidence that proved it, what you changed and why, the four acceptance outputs verbatim, and
anything you deliberately did NOT change with the reason. End with `DELIVERABLE_COMPLETE`.

Do not commit. The lead reviews and commits.
