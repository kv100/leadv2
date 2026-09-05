# FP-06 — model-selection telemetry + capability_floor knob (P2, Standard)

Repo: canonical leadv2 plugin. Context: docs/leadv2/freepool-backlog.md §FP-06.

FIRST STEP, mandatory: in your lane worktree run `git merge worktree-60ec85a4` —
it carries MON-PULSE-01 (in review) so your dispatch-code edits do not conflict.

Part 1 — telemetry. One machine-parseable journal line per dispatch attempt, emitted by
leadv2-dispatch-code.sh at terminal (win or fail), via the existing journal helper:
`model_select_telemetry task=<sig> role=<role> class=<class> work_kind=<wk> arm=<arm>
model=<model> fallback_depth=<N> floor=<applied|none> spawn_to_terminal_s=<S>
terminal=<t> cause=<c>`
- fallback_depth = how many arms were tried before this one (route_fallback count).
- floor mirrors arm_floor_applied.
- Also append the same line as CSV to docs/leadv2/model-select-telemetry.csv (header
  auto-created) so FP-04's 20-diff quality gate has a dataset. No new daemon — emit at
  the point the terminal is journaled.

Part 2 — capability_floor knob (founder ask 2026-08-28: raise freepool to Standard).
The FP-08 floor is currently hardcoded (`floor_applies = size_raw in (...) and kind=='code'`)
in lib/leadv2-route-arbiter.sh. Make it config-driven, preserving current behavior as
default: read `capability_floor: bulk_only|full` from config/freepool-arm.yaml (env
override FREEPOOL_CAPABILITY_FLOOR wins). bulk_only = today's rule; full = floor never
applies (freepool rank-eligible for Standard/Heavy). Journal the mode once per dispatch:
`freepool_floor_mode mode=<m> source=<yaml|env|default>`. Document both values in the
arm.yaml knob block (FP-05 section).

Tests (hermetic, extend test-freepool-capability-floor.sh + new telemetry suite):
(a) telemetry line present on a stubbed win AND on a stubbed no_work fail, fields parse;
(b) CSV row appended, header once;
(c) floor mode full -> freepool wins a Standard build (inverse of the existing floor test)
    and floor mode bulk_only keeps current behavior;
(d) NEGATIVE CONTROL declared + RUN red: break telemetry emission -> (a) fails.
EXTRA_SUITE_MAP rows. bash -n all touched scripts.

Commit: feat(leadv2): FP-06 model-selection telemetry + capability_floor knob.
Report: docs/handoff/FP-06/report.md (max 250 words, raw tails), end DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-5aeaa8bb" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.