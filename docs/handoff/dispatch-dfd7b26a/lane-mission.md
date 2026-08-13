# The architect prepass wrapper mismanages its child — two live defects, one root

Repo for this lane: **`/Users/kostiantyn.vlasenko/Projects/leadv2`**. All edits land there.
Both defects are in `plugins/leadv2/scripts/leadv2-dispatch-code.sh` around the prepass wrapper
(`~L1930-1990`). They block every product dispatch when they fire, and both are silent.

The wrapper as it stands:

```python
proc = subprocess.Popen(
    ["bash", binary, "--role", "architect", "--model", model,
     "--task-id", task_id, "--mission-file", mission_file, "--wait"],
    env=os.environ.copy(), text=True, stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT, start_new_session=True,
)
stdout, _ = proc.communicate(timeout=int(timeout))
```

and the guard that consumes it:

```bash
local adir="${PROJECT_ROOT}/docs/handoff/dispatch-${sig8}-${ARCHITECT_LANE_SUFFIX}"
for cand in "${adir}/architect.full.md" "${adir}/architect.md" "${adir}/architect.summary.md"; do
  [[ -s "${cand}" ]] && { design="${cand}"; break; }
done
if [[ ${rc} -ne 0 && -z "${design}" ]]; then … return 1; fi
```

## D1 — a lane is parked after the architect succeeded

Observed on lane `75d151fe`: `architect_prepass status=failed reason=failed_rc_1` → `retrying` →
`parked`, all within the same second — while the architect had in fact completed. Its subsession
recorded `terminal_reason: completed`, `subtype: success`, and wrote a complete design to
`docs/handoff/dispatch-75d151fe-architect/architect.full.md`, which is the **first** path the
`for cand` loop checks. So the guard was written to survive exactly this and did not: either
`design` was still empty because the artifact had not landed when the loop ran (a race between the
child's last write and the parent's read), or `adir` pointed somewhere else.

`adir` is built from `PROJECT_ROOT`. Note that a lane dispatched from `persona-engine` for plugin
work dies separately with `terminal=no_work cause=empty_diff` because the lane worktree is created
in the dispatching repo — the same `PROJECT_ROOT` ambiguity, which is why this is the first thing
to check. **Confirm or refute both hypotheses with evidence before fixing.** Instrument a real
dispatch: log the resolved `adir`, whether each candidate existed at read time, the child's exit
code, and the subsession's own terminal record. Do not fix on a code-reading hypothesis.

## D2 — the prepass timeout is not enforced

`ARCHITECT_PREPASS_TIMEOUT_SEC` defaults to 420 (`:409`). Lane `117656b5` entered its prepass at
05:41:49Z and was **still writing to `architect.stream.jsonl` at 06:44Z — 63 minutes**, over 9× the
bound, with the lane's handoff dir still empty and no developer ever spawned. The lane looks
"in progress" the whole time; the pulse sees a live process and reports it healthy; the only
symptom is that nothing happens.

`communicate(timeout=…)` does bound the process it was given, so the likely mechanism is that the
bounded process is not the agent: `claude-subsession.sh --wait` may return once the agent is
launched, leaving a detached descendant (`start_new_session=True` puts it in its own group) that
keeps running unbounded — the wrapper's own comment already acknowledges descendants inheriting
stdout. Another candidate is that this run never entered the wrapper at all (the journal shows a
`status=cached reason=sig_match` path elsewhere). Again: **prove which, with an instrumented run,
before changing anything.**

## What the fix must achieve

- On timeout, the wrapper kills the **whole process group of the actual agent**, not just a
  launcher that has already exited, and the journal records
  `architect_prepass status=timeout` when it does. Right now nothing is emitted at all.
- A prepass whose artifact exists is never treated as a failure, whatever the launcher's rc — and
  if the artifact can land after the read, the read must wait for it (bounded) rather than race it.
- Both `adir` and the lane worktree resolve to the repo the edits belong to, or the dispatcher
  refuses loudly when they disagree. A silent cross-repo mismatch is worse than a refusal.

## Proof required

- For each defect: a reproduction that fails before your change and passes after, run through the
  real dispatcher, not a hand-built mock. Paste both runs.
- A test per defect in `plugins/leadv2/scripts/tests/`, each shown RED against the pre-fix file.
- `architect_prepass status=timeout` appearing in a journal from an actual timed-out run.
- Do not raise the timeout to make the symptom go away, and do not remove the rc check.

## Hard limits

- Do not change what the architect role does, its model, or its prompt — only the wrapper's child
  management and artifact read.
- Do not add either affected suite to any known-failures registry.
- If the evidence refutes both hypotheses above, say so and report what the instrumented run
  actually showed rather than fixing something that is not broken.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-dfd7b26a" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.