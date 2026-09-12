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
