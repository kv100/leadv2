# SAFETY-PIN-SECOND-DOOR-01

`HEAVY-TIER-VS-SAFETY-OPUS-01` closed one route into the safety pin and its census reported a
second one. **Your first job is to establish whether that second door is real**, because the
census cited a file that does not exist.

## What the census claimed

From `docs/handoff/HEAVY-TIER-VS-SAFETY-OPUS-01/report.md`, verbatim in substance:

> `leadv2-admission-class.sh` folds `risk_class=safety_publish_payments` into class Heavy while
> the route pin reads `RISK_TAGS`, so a judge-flagged safety task without explicit risk tags now
> takes the think arm.

The lane deliberately did not fix it — correctly, it is a cross-lane contract — and flagged it.

## What the lead checked, and what did not hold up

There is **no** `leadv2-admission-class.sh` in `plugins/leadv2/scripts/`. What exists:

    plugins/leadv2/scripts/leadv2-task-judge.sh:113    risk_class = 'safety_publish_payments'
    plugins/leadv2/scripts/leadv2-task-judge.sh:162    'risk_class': {'none','data','safety_publish_payments'}
    plugins/leadv2/scripts/leadv2-dispatch-code.sh:3945 elif risk == "safety_publish_payments":

and `dispatch-code.sh:3945` is inside the *override-reason* string that
`FREEPOOL-MUST-ACTUALLY-GET-WORK-01` round 2 added — it explains why the classifier overrode a
caller's `--task-class`, which is not the same thing as folding risk into a class. A grep for a
risk-to-Heavy fold in `leadv2-dispatch-code.sh` returned nothing.

So the claim may still be true by a different path, or it may be an artifact of a worker
describing code it did not read carefully. This repo has a standing rule about exactly this:
a worker's assertion about code is not evidence until someone runs it.

## What this task must deliver

1. **A verdict on the claim, from a live run — not from reading.** Construct a task that a judge
   flags `risk_class=safety_publish_payments` and that carries **no** `risk_tags`, dispatch it
   resolve-only (`--no-spawn`, `LEADV2_DISPATCH_SPAWN=0`), and paste the `route_resolved` line.
   Either it shows a non-Opus arm — the door is real, with the exact line that opened it — or it
   shows Opus, and the census was wrong. Say plainly which.
2. If the door is real, close it the way `HEAVY-TIER-VS-SAFETY-OPUS-01` closed the first: a pin
   the class check cannot outrank, outside the config/env override surface. Keep the `arch`
   carve-out consistent with the adjudication in
   `docs/handoff/HEAVY-TIER-VS-SAFETY-OPUS-01/fix-round-2.md` — read it first so the two doors
   end up with the same rule rather than two rules that will drift apart.
3. If the census was wrong, say so, correct the report in place with a one-line note, and stop.
   A clean "this was not real, here is the probe that shows it" is a complete and welcome answer;
   do not manufacture a fix to have something to show.
4. Either way: an assertion in `test-session-route.sh` covering the risk_class route, with a
   negative control (mutation → red → revert → green).
5. Green on macOS and in a Linux container, exit codes pasted.
6. Commit in this lane before you finish.

Off limits: `main`, `tests/known-red-suites.txt`, weakening assertions, and changing the `arch`
carve-out — that was a lead adjudication and is settled.
