# HEAVY-TIER-VS-SAFETY-OPUS-01 — round 2: the lead's adjudication of the branch order

Round 1 (`99b4f865`) is accepted on its substance and its evidence. The split it made is the
right shape, the citations are real, the negative control was run, and it found a genuine extra
cause (on a Linux host without PyYAML the resolver degraded to the opus fallback, which is what
made the old assertion platform-dependent). Do not redo any of it.

One thing in it is the lead's call to make, not the lane's, and the lead is making it now.

## The defect: branch order puts class above safety

In `leadv2-session-route.sh` the new `heavy|strategic` think branch is evaluated **before** the
`_high_risk` branch. So a task that is Heavy **and** carries a high-risk tag takes the think arm
and routes to `fable`. Round 1's own comment says so plainly — the safety pin applies only "on a
non-Heavy class".

`HIGH_RISK_TAGS="auth,rls,safety,publish,security,arch"` (`leadv2-session-route.sh:89`). So today
a Heavy task tagged `safety`, `auth`, `rls`, `publish` or `security` routes to fable. A pin that
yields to the class check is not a pin, and round 1's own comment calls it "doctrine, not a
tunable".

## The adjudication

**Safety outranks the think tier — with one carve-out, and the carve-out is `arch`.**

1. `safety`, `auth`, `rls`, `publish`, `security` are **hard safety**. They pin
   `CLAUDE_SAFETY_MODEL` / `CLAUDE_SAFETY_EFFORT` regardless of class, Heavy and Strategic
   included. Move the `_high_risk` test **above** the `heavy|strategic` test for these tags.
2. `arch` is **not** hard safety in this plugin. `PLANNER-MODELS-DECISION-01` deliberately pins
   Heavy planning and architecture to Fable, and it is the newer, plugin-specific decision; the
   "arch -> Opus" wording elsewhere is about banning GLM from architecture work, not about
   displacing the think tier. A Heavy/Strategic task whose only high-risk tag is `arch` keeps the
   think arm. On a non-Heavy class, `arch` continues to behave as it does today.

Reason for the split, so a later session does not relitigate it: the five hard tags name
*consequences in the world* — an auth boundary, a row-level policy, a publish, a payment surface.
The think tier is about how hard a thing is to reason about, which is a different axis, and the
consequence axis wins when they disagree. `arch` names difficulty, not consequence.

## What round 2 must deliver

1. The reorder above, with `arch` carved out as specified. Keep the safety pin outside the
   config/env override surface exactly as round 1 built it — that part is right.
2. Two new assertions in `test-session-route.sh`, and they are the point of this round:
   - Heavy class **+** `safety` tag -> `model=opus`.
   - Heavy class **+** `arch` tag (and no other high-risk tag) -> the think arm.
   Round 1's existing assertions must stay green.
3. Negative controls, both directions: revert the reorder and show the Heavy+safety assertion goes
   red; drop the `arch` carve-out and show the Heavy+arch assertion goes red. Revert each, show
   green.
4. Green on macOS **and** in a Linux container, exit codes pasted, same as round 1.
5. State in the report whether any OTHER caller resolves a safety decision through a class check
   rather than a tag check. Round 1 found one instance; one is a bug, two is a pattern and the
   census belongs in the report.
6. Commit in this lane before you finish.

Off limits: `main`, `tests/known-red-suites.txt`, weakening any assertion, and re-opening the
(A) question — "Heavy planning -> fable" is settled and round 1 settled it correctly.
