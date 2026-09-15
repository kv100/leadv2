# GUARD-READ-ONLY-IS-A-NAME-NOT-A-PROPERTY-01

## Diff summary

- Added `general-purpose` to the single `_is_write_role()` list. The lead and
  nested paths retain their shared function and the existing journalled
  `LEADV2_LEAD_WRITE_SPAWN_ALLOW=1` escape hatch remains unchanged.
- Added an inline real-input Bash sub-hook for read-only callers `Explore` and
  `recon`. It refuses only `git commit`, `git push`, `sed -i`, `ssh`, `docker
  exec`, and `curl -X` / `--request` with `POST`, `PUT`, or `DELETE`.
- Added `test-readonly-caller-cannot-mutate.sh`, self-registered through
  `run-all-triggers`, and updated the existing lead write-role suite for the
  new classification.

## Classification line

`Explore` and `recon` retain Bash for local discovery. `git log`, `grep`, and
`curl` without an explicit mutating method are admitted. `ssh host true` is
refused: a local pre-dispatch hook cannot prove that a remote command is
read-only, so all `ssh` is classified as a mutating-capable remote boundary.
That is intentionally the narrow exception to command-text-only inspection;
the other named rules do not attempt a broad shell-mutation detector.

## Live refusal output

The actual dispatcher was invoked with a real PreToolUse Bash input, not a
reimplemented matcher:

```text
[leadv2-bash-pre-dispatch] DENIED read-only caller mutation: agent_type="explore" command_class="git_commit". Read-only callers may inspect local state only; return the mutation to the lead.
live_refusal_rc=2
general-purpose-role-census_rc=0
```

## Focused suite green

```text
PASS: GREEN A: Explore git commit refused by real Bash hook with named cause
PASS: GREEN B: Explore read-only command admitted: git log -1 --oneline
PASS: GREEN B: Explore read-only command admitted: grep needle local-file
PASS: GREEN B: Explore read-only command admitted: curl https://example.invalid/health
PASS: GREEN B2: Explore mutation class refused: git_push
PASS: GREEN B2: Explore mutation class refused: sed_in_place
PASS: GREEN B2: Explore mutation class refused: ssh
PASS: GREEN B2: Explore mutation class refused: docker_exec
PASS: GREEN B2: Explore mutation class refused: curl_mutating_method
PASS: GREEN C: lead general-purpose spawn refused with dispatch remedy
PASS=13 FAIL=0
```

The established lead-path suite also passed with `PASS=8 FAIL=0`; the existing
dispatcher-verdict suite passed all 21 checks.

Changed-scope registration was checked independently:

```text
[SELECT] .../plugins/leadv2/scripts/tests/test-readonly-caller-cannot-mutate.sh
run-all: 11 selected, scope=changed, select_only=1
```

## Negative controls: live mutation-control artifacts

All three controls ran through `leadv2-mutation-control.sh --live` against the
real files. Each artifact records a green baseline (`baseline_rc=0`), a red
mutant (`mutated_rc=1`), restoration, and identical pre/post porcelain.

### 1. Remove `general-purpose` classification

Artifact: `mutation-control/*.txt` (the matching live-run artifact is bound to
this committed lane diff).

```text
suite=plugins/leadv2/scripts/tests/test-readonly-caller-cannot-mutate.sh
file=plugins/leadv2/hooks/leadv2-routing-guard.sh
anchor=s/|general-purpose) return 0 ;;/) return 0 ;;/
mode=live
baseline_rc=0
mutated_rc=1
red_line=FAIL: GREEN C: general-purpose spawn rc=0; expected rc=2 and remedy
porcelain_clean=yes
restored=yes
```

### 2. Remove the mutating-command sub-hook

Artifact: `mutation-control/*.txt` (the matching live-run artifact is bound to
this committed lane diff).

```text
suite=plugins/leadv2/scripts/tests/test-readonly-caller-cannot-mutate.sh
file=plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh
anchor=s/explore|recon) ;;/*) return 0 ;;/
mode=live
baseline_rc=0
mutated_rc=1
red_line=FAIL: GREEN A: Explore git commit rc=0; expected rc=2 and named cause
porcelain_clean=yes
restored=yes
```

### 3. Widen the sub-hook to refuse everything

Artifact: `mutation-control/*.txt` (the matching live-run artifact is bound to
this committed lane diff).

```text
suite=plugins/leadv2/scripts/tests/test-readonly-caller-cannot-mutate.sh
file=plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh
anchor=s/local _lv2_command_class=""/local _lv2_command_class="all_commands"/
mode=live
baseline_rc=0
mutated_rc=1
red_line=FAIL: GREEN B: read-only command over-refused (rc=2): git log -1 --oneline
porcelain_clean=yes
restored=yes
```

The suite also contains exact-once scratch mutation anchors. An unmatched
anchor exits non-zero rather than silently skipping the control.

## Falsification and syntax checks

```text
bash -n plugins/leadv2/hooks/leadv2-routing-guard.sh                 rc=0
bash -n plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh             rc=0
bash -n plugins/leadv2/scripts/tests/test-readonly-caller-cannot-mutate.sh rc=0
bash -n plugins/leadv2/scripts/tests/test-lead-write-role-spawn-gate.sh    rc=0
bash plugins/leadv2/scripts/tests/test-readonly-caller-cannot-mutate.sh    PASS=13 FAIL=0
bash plugins/leadv2/scripts/tests/test-lead-write-role-spawn-gate.sh       PASS=8 FAIL=0
bash plugins/leadv2/scripts/tests/test-bash-pre-dispatch-verdict.sh        ALL PASS: 21 checks passed
timeout 600 bash tests/run-all.sh --scope changed                           rc=0
```

No Python files changed, so there is no `py_compile` target.

## Known limit

These are spawn and subagent-Bash gates, not action gates for the lead itself.
A lead can still run `deploy-latest.sh` from its own Bash without spawning an
agent, so no routing gate sees that action. This narrows the bypass; it does
not make the arbiter impossible to bypass.

## Round 2

### Failing case

`plugins/leadv2/scripts/tests/test-nested-depth.sh:64-79` (T1). Input: caller
`explore` (already a nested sub-run), target `general-purpose`. Guard code:
`plugins/leadv2/hooks/leadv2-routing-guard.sh`.

Before this round, the guard checked write-role (Gap #2, target-scoped)
before depth (Gap #1, caller-scoped). Round 1 added `general-purpose` to
`_is_write_role`, so T1's target now matches the write-role check too. Since
that check ran first, it denied with `route.subrun.write_role_denied` before
the depth check ever ran, so `route.subrun.depth_exceeded` was never
recorded — RC stayed 2 (T1's first assertion still passed) but the audit-log
assertion (T1's second) failed.

### Which reading is true, and why

**Reading (b): the ordering is the defect.** The two checks are genuinely
independent and both true simultaneously for this input — but they are not
equally authoritative. Depth is a **caller-scoped, totalizing** gate: once a
caller is itself a nested sub-run, it cannot spawn *anything* further,
regardless of target. Write-role is a **target-scoped** gate: it only says
this particular target is disallowed. Checking write-role first produces a
verdict — "this target is denied" — that misleadingly implies a different
target would succeed, when in fact this caller cannot spawn any target at
all. That is exactly "one refusal wearing another's name": the log records
the narrower, less-true cause and hides the broader one. The pre-existing
top-of-file doctrine comment (lines 26-33, unchanged by round 1) already
listed depth as gap "a" before write-role as gap "b" — the code just didn't
implement that order. Fix: reorder so depth (Gap #1) is checked before
write-role (Gap #2), within the same `LEADV2_NESTED_DEPTH_GATE` block. No
other file needed to change; T2 (caller=`developer`, non-nested) still falls
through the depth `case` untouched and hits the write-role check exactly as
before.

I did not edit `test-nested-depth.sh` at all — under reading (b) the existing
T1 assertions (rc=2, log contains `route.subrun.depth_exceeded`) are correct
as written; the guard was wrong, not the test.

### Suite numbers (paired, same bound, this machine/darwin)

| suite | main @ `60804552` | this lane (post-fix) | verdict |
|---|---|---|---|
| `plugins/leadv2/scripts/tests/test-nested-depth.sh` | not re-run (round-2 mission's own paired measurement recorded 7/0 green) | **7/0 green** (`PASS=7 FAIL=0`) | fixed — matches main |
| `plugins/leadv2/scripts/tests/test-nested-count-fix.sh` | `PASS=5 FAIL=2` (T1 scorecard nested_spawns=0 expected 1; T2 per-task tasks/ dir unexpectedly created) | `PASS=5 FAIL=2`, identical two FAIL lines | pre-existing red, not touched, not mine — mission's stated "6/1" does not reproduce on this machine at `60804552`; measured paired 5/2==5/2 |
| `tests/test-status-surface-bash32.sh` | hangs after 8 `ok` lines (T1-T5 complete, T6 header prints then no further output), `timeout 120` → rc=124, zero `FAIL`/`bad` lines emitted | identical: hangs after the same 8 `ok` lines, `timeout 120` → rc=124, zero `FAIL`/`bad` lines | pre-existing on main, not mine — matches memory note on status-surface live-state flakes |

### New control: reorder-revert mutation (round 2)

Mutation: a unified-diff patch that swaps Gap #1/Gap #2 back to the
pre-round-2 order (write-role check runs before depth check again), applied
`--live` to the real guard file, restored after.

```text
suite=plugins/leadv2/scripts/tests/test-nested-depth.sh
file=plugins/leadv2/hooks/leadv2-routing-guard.sh
anchor=/tmp/reorder-mutant.patch (pure block-swap of Gap #1 and Gap #2, no wording changed)
mode=live
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: T1: audit log missing route.subrun.depth_exceeded reason
porcelain_clean=yes
restored=yes
```

Artifact: `docs/handoff/GUARD-READ-ONLY-IS-A-NAME-NOT-A-PROPERTY-01/mutation-control/20260915T104314Z-live-94300.txt`.

Green (post-fix, same suite, unmutated):

```text
[TEST] PASS: T1: depth-exceeded spawn denied (rc=2)
[TEST] PASS: T1: audit log has route.subrun.depth_exceeded
[TEST] PASS: T2: write-role nested spawn denied (rc=2)
[TEST] PASS: T2: audit log has route.subrun.write_role_denied
[TEST] PASS: T3: 4th task-wide nested spawn denied at max_nested_per_task=3 (rc=2)
[TEST] PASS: T3: audit log has route.subrun.count_exceeded
[TEST] PASS: T4: kill-switch off restores pre-existing allow behavior (rc=0)

[TEST SUMMARY] PASS=7 FAIL=0
```

### Second casualty found via `tests/run-all.sh --scope changed`: `test-lead-write-role-spawn-gate.sh` T5

Reordering surfaced a second suite exercising the same overlap:
`test-lead-write-role-spawn-gate.sh:118-128` (T5) used `caller=explore`,
`target=developer` to check the nested write-role denial. `explore` is
itself in the depth-cap's `case`, so — same shape as T1 — after the
reorder this input now hits the depth check first and logs
`route.subrun.depth_exceeded` instead of the `route.subrun.write_role_denied`
T5 asserted. `run-all --scope changed` caught this as a real regression:

```text
[TEST] FAIL: T5: nested denial did not audit route.subrun.write_role_denied
```

T5's own docstring states its intent: confirm the nested path's write-role
list still denies write-capable targets ("ONE list, both paths") — it is
not about caller-depth precedence. `explore` was an incidental caller
choice that happened to collide with the (now-corrected) depth-cap case,
exactly the same shape as T1's incidental target choice, mirrored onto the
caller axis instead of the target axis. Verified on `main@60804552` that
this suite is 8/0 green there (write-role check ran first pre-round-2, so
the collision was latent, never triggered) — this is not pre-existing red,
it is a second, real consequence of the same ordering fix.

Fix: changed T5's caller from `explore` to `developer` — write-capable but
not itself in the depth-cap's `case`, so it isolates the write-role check
exactly as T2 in `test-nested-depth.sh` already does (`caller=developer`,
`target=developer`). No assertion, grep, or expected reason was loosened;
only the caller fixture value changed, with the reasoning recorded inline
at both the docstring and the call site. Re-verified: `PASS=8 FAIL=0`.

### Falsification (round 2, final)

```text
bash -n plugins/leadv2/hooks/leadv2-routing-guard.sh                              rc=0
bash -n plugins/leadv2/scripts/tests/test-lead-write-role-spawn-gate.sh           rc=0
bash plugins/leadv2/scripts/tests/test-nested-depth.sh                           PASS=7 FAIL=0
bash plugins/leadv2/scripts/tests/test-lead-write-role-spawn-gate.sh             PASS=8 FAIL=0
bash plugins/leadv2/scripts/tests/test-readonly-caller-cannot-mutate.sh          PASS=13 FAIL=0
bash plugins/leadv2/scripts/tests/test-nested-count-fix.sh                      PASS=5 FAIL=2 (pre-existing, matches main)
timeout 120 bash tests/test-status-surface-bash32.sh                            rc=124 (pre-existing hang, matches main)
timeout 580 bash tests/run-all.sh --scope changed                               run-all: 9 passed, 2 failed, scope=changed, rc=0
```

The 2 remaining `run-all --scope changed` failures are
`run-core-offline.sh` (documented in `tests/run-all.sh` itself as
budget/environment-gated under `--scope changed`, unrelated to
`leadv2-routing-guard.sh`; matches the `run-all-changed-scope-runtime`
memory note) and `test-nested-count-fix.sh` (pre-existing, confirmed 5/2 on
`main@60804552` with identical FAIL lines, per above). Neither was touched.

No Python files changed in round 2, so there is no `py_compile` target.

DELIVERABLE_COMPLETE
