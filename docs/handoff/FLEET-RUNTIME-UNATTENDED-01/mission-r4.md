# FLEET-RUNTIME round 4 — four edits, nothing else

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`.

**Do not read `mission.md`.** Its top half is the round-1 spec and it contradicts this file — it
lists `Restart=always` as a requirement, which is the very defect you are here to remove. That
contradiction is the lead's mistake and is the likely reason three rounds missed the same items.
This file supersedes it entirely.

## State

The branch `worktree-583d804d01e5` already carries 2050 insertions of fleet runtime across three
rounds. **Add no features and no tests beyond what is named below.** Reviews of rounds 1, 2 and 3
each reported the same four defects; all four are still present, verified by direct grep at
2026-09-17 20:30Z. Volume is not the problem. These four edits are.

## The four edits

**1. A controlled stop must not be restarted.**
`leadv2-fleet-unit.sh:96` currently renders `Restart=${4}` and callers pass `always`. Choose one
model and make the unit and the runner agree: e.g. `Restart=on-failure` plus
`SuccessExitStatus=` listing the runner's deliberate-stop code, and the runner exits with that
code for FLEET-STOP and for each of the three self-stops. Any equivalent design is fine; what is
not fine is a deliberate stop that systemd restarts.

**2. The unit file does not load.**
- `WorkingDirectory="${2}"` — quotes are not valid there; systemd treats the line as malformed.
- `Environment=LEADV2_FLEET_LANE_CMD=${5}` — unquoted, so any space in the command breaks it.

**3. A control mutation is shipped inside the product.**
`leadv2-fleet-unit.sh:96` ends with `# c1-mut: restart policy passthrough`. A trailing comment on
a systemd directive line makes systemd ignore the directive. Three files under
`plugins/leadv2/scripts/fleet/` still carry `c*-mut` markers. Remove every one, and add a single
suite case asserting none survives anywhere under that directory.

**4. The reaper still forces.**
`leadv2-fleet-guard.sh` still contains two occurrences of `git worktree remove --force`. Use the
non-forcing removal and **refuse** when it declines, recording the refusal. A reaper that can
delete unlanded work is worse than no reaper.

## Declared write set — nothing outside it

`leadv2-fleet-unit.sh`, `leadv2-fleet-guard.sh`, `leadv2-fleet-state.sh`, `runner.sh`, `lib.sh`,
`test-fleet-runtime-guards.sh`, and `docs/handoff/FLEET-RUNTIME-UNATTENDED-01/report.md`.

Rounds 2 and 3 both edited files outside their declared set (round 3 touched
`tests/mutations/catalog.yaml`). The review diff is built from the declared set, so those edits
are invisible to the judge and the round is judged on an incomplete picture. **If an edit needs a
file outside this list, stop and write that in the report instead of making it.**

## Controls — two, both RUN, both pasted

1. A controlled stop is not restarted. Negative control: put `Restart=always` back and show the
   restart returning.
2. A generated unit passes verification (`systemd-analyze verify`, or a parser stub where systemd
   is absent). Negative control: reintroduce the quoted `WorkingDirectory` and show it failing.

Assert each mutation target string is present before running its control, so a control cannot rot
into a permanent green. Then assert no `c*-mut` marker remains — see edit 3.

## Done means

All four greps come back clean on your branch, and you paste them in the report:

```
grep -n 'Restart='                 plugins/leadv2/scripts/fleet/leadv2-fleet-unit.sh
grep -rn 'c[0-9]-mut'              plugins/leadv2/scripts/fleet/
grep -n 'WorkingDirectory'         plugins/leadv2/scripts/fleet/leadv2-fleet-unit.sh
grep -n 'worktree remove --force'  plugins/leadv2/scripts/fleet/leadv2-fleet-guard.sh
```
