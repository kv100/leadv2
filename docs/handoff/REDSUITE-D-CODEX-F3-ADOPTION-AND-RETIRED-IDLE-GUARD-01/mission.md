# REDSUITE-D-CODEX-F3-ADOPTION-AND-RETIRED-IDLE-GUARD-01

Row `d7d40fc0754c`. Two red suites, two small independent causes, no subject shared with any other
lane in this plan.

**Read `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md` first and follow it.**

## What was measured, by the lead, on main, before this lane existed
macOS Darwin 25.6.0, each run alone at a 400s ceiling, 2026-09-15:

```
test-codex-quota-guardrails.sh  rc=1  wall=14s
test-idle-lead-guard.sh         rc=1  wall=15s
```

### Suite 1 — `test-codex-quota-guardrails.sh`: fourteen green, one red
```
FAIL: f3 gate unavailable -> exit 2, no spawn
  rc=9
  err=[leadv2-lead-identity] WARNING: resolver unavailable or failed, falling back to direct
      [leadv2-codex-session-runner] ERROR: lane adoption refused (rc=9): f3-task has no reusable
      registry row and no inheritable write set -- refusing to run as an unregistered lane
```
The neighbouring cases all pass, including the ones that matter most — `f1 pre-opened circuit ->
exit 2, zero codex invocations`, `f2 codex usage-limit -> circuit opened with parsed horizon, 1
spawn`, `e1 unparseable circuit marker -> gate refuses (fail-closed)`, `e2 quota reader missing ->
fail-OPEN`.

So f3 is `never_reaches_subject`: the case is meant to prove that an **unavailable gate** exits 2
without spawning, but the fixture task `f3-task` is refused earlier, by lane adoption, for being an
unregistered lane. It never gets as far as the gate it is testing.

Two candidate fixes, and you must choose deliberately and say why:
- give the fixture a registry row / inheritable write set so the case reaches the gate; or
- make the runner distinguish "gate unavailable" from "unregistered lane", if those genuinely
  deserve different exits.
The first is smaller and probably right, but only if the adoption refusal is correct behaviour for
a real unregistered lane. Decide that question explicitly rather than by picking the easier diff.
The lead-identity resolver warning on the same line ("resolver unavailable or failed, falling back
to direct") may be incidental noise or may be part of the cause — say which, with evidence.

### Suite 2 — `test-idle-lead-guard.sh`: one red case
```
FAIL: case 10: retired idle-lead-guard found registered in hooks.json
AssertionError: leadv2-idle-lead-guard.sh is REGISTERED in hooks.json Stop[0] but was retired by
ONE-LANE-WATCH-01 (9f00e7ed)
```
A hook retired by a recorded decision is still wired into `hooks.json`. Read `ONE-LANE-WATCH-01`
(`9f00e7ed`) before removing anything, and confirm the retirement really happened and was not
reverted — if the retirement was itself undone, the suite is the stale party and `lane-rules.md`
tells you what you must prove to change a test instead of a subject.

`hooks.json` governs live sessions. Change exactly the one `Stop[0]` entry the assertion names and
nothing else, and state in the report what else is registered there that you did NOT touch.

## Deliverables
- Both fixes, each with its own negative control (they are independent claims — two controls
  minimum).
- `docs/handoff/REDSUITE-D-CODEX-F3-ADOPTION-AND-RETIRED-IDLE-GUARD-01/report.md` per
  `lane-rules.md`.

## Acceptance
```
cd ~/Projects/leadv2 \
  && bash plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh >/dev/null 2>&1 \
  && bash plugins/leadv2/scripts/tests/test-idle-lead-guard.sh >/dev/null 2>&1
```
Red today (rc=1).
