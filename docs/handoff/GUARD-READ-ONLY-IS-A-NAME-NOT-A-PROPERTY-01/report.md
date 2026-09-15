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

Artifact: `mutation-control/20260915T093640Z-live-481.txt`

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

Artifact: `mutation-control/20260915T093651Z-live-6190.txt`

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

Artifact: `mutation-control/20260915T093657Z-live-13373.txt`

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

DELIVERABLE_COMPLETE
