# Open-threads retirement report

## Scope status

The plugin half is committed with the ledger and its two dedicated plugin
programs removed. The cross-repository acceptance is still red: the sandbox
rejects every write below `/Users/kostiantyn.vlasenko/Projects/persona-engine`,
including the requested deletion of its modified ledger and removal of its
registered hook. The required async-question helper also failed before it could
write a question because its control-plane state directory is outside the
sandbox.

## Red acceptance output before the change

```text
FAIL file present: docs/leadv2/open-threads.md
```

## Anchor output before the change

```text
<task-anchor>
ACTIVE TASK: FORKPASS-810129d0 | phase: intake | class: ?

DIRECTIVE — this founder message does NOT replace the active task.
1. Route it: Skill(leadv2-founder-question-router). Answer inline in <=3 lines if it is a
   question/nuance; then CONTINUE the task from the phase above.
2. Only an explicit stop/scope-change order pauses the task. "Also do X" = file X in
   the BACKLOG (scripts/task-add.sh), do NOT switch to it. open-threads.md is ONLY
   for non-tasks: an unanswered founder question, a live background job, a promise.
3. PULSE MODE: no narration. Chat output is allowed ONLY at: Gate-1, an async question,
   Phase-8 close, a [BROAD_STATUS] relay when the plugin emits BROAD_STATUS_READY
   (RELAY=full: paste founder-status.md verbatim, never compose one; RELAY=none:
   relay only that single line, verbatim, and nothing else). Narration is
   model-generated prose about its own work; the pulse is a verbatim relay of a
   plugin-generated artifact — never a CronCreate job; the beat is plugin-owned.
   Before relaying, compare the ready-line's at= stamp with the timestamp
   leading line 1 of founder-status.md — if they differ, the file is from an
   earlier beat: publish that fact, not the file.
   Everything else is silent tool work.
4. Anything promised for later goes to docs/leadv2/scheduled-decisions.md the same turn.
</task-anchor>
```

## Anchor output after the change

```text
<task-anchor>
ACTIVE TASK: FORKPASS-810129d0 | phase: intake | class: ?

DIRECTIVE — this founder message does NOT replace the active task.
1. Route it: Skill(leadv2-founder-question-router). Answer inline in <=3 lines if it is a
   question/nuance; then CONTINUE the task from the phase above.
2. Only an explicit stop/scope-change order pauses the task. "Also do X" = file X in
   the BACKLOG (scripts/task-add.sh), do NOT switch to it.
3. PULSE MODE: no narration. Chat output is allowed ONLY at: Gate-1, an async question,
   Phase-8 close, a [BROAD_STATUS] relay when the plugin emits BROAD_STATUS_READY
   (RELAY=full: paste founder-status.md verbatim, never compose one; RELAY=none:
   relay only that single line, verbatim, and nothing else). Narration is
   model-generated prose about its own work; the pulse is a verbatim relay of a
   plugin-generated artifact — never a CronCreate job; the beat is plugin-owned.
   Before relaying, compare the ready-line's at= stamp with the timestamp
   leading line 1 of founder-status.md — if they differ, the file is from an
   earlier beat: publish that fact, not the file.
   Everything else is silent tool work.
4. Anything promised for later goes to docs/leadv2/scheduled-decisions.md the same turn.
</task-anchor>
```

## Stable-line diff

```text
--- REQUIRED-STABLE DIFF ---
```

The empty diff is the raw result of comparing the PULSE and scheduled-decision
lines from the two hook invocations.

## Falsification output

```text
BASH_N_RC=0
```

`tests/run-all.sh --scope changed` entered `run-core-offline.sh` but produced
no terminal result before this bounded lane could continue. It is not claimed
as green. The current exact-path census remains red because the persona half
cannot be written and plugin test/history fixtures still name the retired path.

## ARBITER-DECISION-INPUTS-01

### D1 — BUILT

`reset_urgency` is a bounded ranking multiplier in
`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`:

```text
waste = remaining_fraction * clamp(1 - hours_to_reset / period_hours, 0, 1)
weight = 1.0 + waste       # 1.0 <= weight <= 2.0
```

It takes the maximum waste across every readable window burned by an admitted
arm. That deliberately includes a five-hour session meter even when the weekly
meter is utilisation-binding: the former can still be the quota about to be
lost. Missing, zero, negative, and unknown-period reset readings are neutral.
Capability admission and every exclusion stage occur before `ecost()`, so this
term cannot create a capability cell. `LEADV2_ARBITER_RESET_URGENCY=0` is the
rollback.

Raw focused-suite output:

```text
PASS: (a) founder case: weekly Claude reset in 5h with 95pct left outranks Codex reset in 140h
PASS: (b) near reset with only 2pct left is not preferred
PASS: (c) unreadable reset is neutral (no Claude urgency token)
PASS: (d) negative and zero reset values are neutral, not stale-cache boosts
PASS: (e) non-binding five-hour meter supplies urgency while weekly remains binding
PASS: (f) same frozen decision twice is byte-identical (no reset oscillation)
PASS: (g) urgency cannot buy capability: unsupported Claude docs arm is absent
PASS: (h) kill switch restores cost order and removes urgency provenance
PASS: (i RED) removing the urgency formula flips the founder case to codex
PASS: (i GREEN) unmutated arbiter restores the founder-case Claude pick
SUMMARY: pass=10 fail=0
```

### D2 — MEASURED AND REJECTED

The pre-spawn estimate files provide expected tokens, but the actual journal
has no measured token target for a fit. This probe found 60 `cost_actual` rows
across the live event-cache files and `token_telemetry={'unknown': 60}`: every
row carried `tokens=-`. A regression fitted to those rows would not estimate
token spend, so no token-routing term was wired.

```text
files=118 cost_actual_rows=60
token_telemetry={'unknown': 60}
buckets=['heavy/codex=1', 'light/glm=1', 'standard/codex=9', 'standard/glm-flash=8', 'standard/glm=37', 'strategic/codex=1', 'strategic/glm=3']
```

### D3 — NOT REACHED

The local event journals contain worker and cost rows but no route-decision
rows to replay. No refinement was shipped without a decision-movement census.

### D4 — NOT REACHED

No GLM judge default or quota-picture consultation was changed. The required
ten-mission live agreement probe and forced-failure proof were not available in
this bounded implementation pass.

### D5 — falsification artifacts

`bash -n` passed for both changed shell files. The focused test above includes
the red/private-copy control and green revert. The authoritative shared control
was also run after the code commit:

## leadv2-mutation-control.sh artifact

```text
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-reset-urgency.sh file=plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh red_line=FAIL: (a) expected weekly urgency winner sonnet: arm=codex ... diff_hash=25402523d1bbff71ca551175d0bb3d01152aba698b661c54839ac4ca70f19941 lane_diff_hash=eb95acfe3725f6a6551a85fe2794c1ef8379fbaaab8e65b1b63acef12f81c099
```

Its committed artifact is `mutation-control/20260913T163610Z-2922.txt`, with
`baseline_rc=0`, `mutated_rc=1`, and the full red decision line.

Changed-scope selection was run after commit and selected the core runner, but
the explicitly bounded command timed out rather than returning a green result:

```text
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/48b8297b4cc1/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
CHANGED_SCOPE_RC=124
```
