VERDICT: delete

# Reflect / self-learning decision

Date of measurement: 2026-09-12. Window: `2026-08-13T00:00:00Z` inclusive through
`2026-09-13T00:00:00Z` exclusive. The requested acceptance artifact is in the
`leadv2` checkout. The pinned persona-engine checkout was used only as a
cross-repo control because it contains the only recent structured reflect
artifact found on disk.

## Measurement first

### 1. Reflect reach versus dispatched work

Primary population: `~/Projects/leadv2`.

Command:

```text
python3 - <<'PY'
from pathlib import Path
import re
from datetime import datetime
root=Path('/Users/kostiantyn.vlasenko/Projects/leadv2/docs/leadv2/tasks')
cut='2026-08-13T00:00:00Z'; end='2026-09-13T00:00:00Z'
patterns={
 'dispatch_task_bound': re.compile(r'- (\d{4}-\d\d-\d\dT[^ ]+) .*dispatch_task_bound task=([^ ]+)'),
 'reflect': re.compile(r'- (\d{4}-\d\d-\d\dT[^ ]+) .*\b(?:reflect|lead-reflect|phase8_reflect)\b.*task=([^ ]+)'),
 'phase8': re.compile(r'- (\d{4}-\d\d-\d\dT[^ ]+) .*\bphase8[^ ]*\b.*task=([^ ]+)'),
}
sets={k:set() for k in patterns}; events={k:0 for k in patterns}
for p in root.glob('*/journal.md'):
  for line in p.read_text(errors='replace').splitlines():
    for k,pat in patterns.items():
      m=pat.search(line)
      if m and cut<=m.group(1)<end:
        events[k]+=1; sets[k].add(m.group(2))
print('window=2026-08-13T00:00:00Z..2026-09-13T00:00:00Z')
for k in patterns: print(f'{k}_events={events[k]} unique_tasks={len(sets[k])}')
PY
```

Raw output:

```text
window=2026-08-13T00:00:00Z..2026-09-13T00:00:00Z
dispatch_task_bound_events=758 unique_tasks=194
reflect_events=0 unique_tasks=0
phase8_events=0 unique_tasks=0
```

Independent artifact check:

```text
find docs/handoff -type f \( -name 'reflect-done.flag' -o -name 'phase8-passed.flag' \) \\
  -newermt '2026-08-13' ! -newermt '2026-09-13' -print
printf 'flags='; find docs/handoff -type f \( -name 'reflect-done.flag' -o -name 'phase8-passed.flag' \) \\
  -newermt '2026-08-13' ! -newermt '2026-09-13' | wc -l
```

Raw output:

```text
flags=       0
```

Therefore the primary measured rate is **0/194 unique dispatched runs = 0.0%**
(or 0/758 dispatch-bound events). The canonical `leadv2` checkout also has no
`docs/leadv2/reflect-history.yaml` or `docs/leadv2/learnings.md` at this
measurement point.

Cross-repo control, not substituted into the primary denominator:

```text
file=docs/leadv2/reflect-history.yaml lines=3787 total_entries=108
window_start=2026-08-13T00:00:00+00:00 window_end=2026-09-12T23:59:59+00:00
recent_entries=1
2026-08-31T12:32:43+00:00 task=V5-M0-SKELETON-01
```

This artifact is in the pinned `persona-engine` checkout, with a separate
dispatch ledger. It proves the writer can produce records, but it does not
prove any of the 194 `leadv2` runs reached reflect.

### 2. What reflect wrote

The following are verbatim samples from that cross-repo
`persona-engine/docs/leadv2/reflect-history.yaml` artifact. They are shown as
samples of the actual format, not as entries from the primary `leadv2` rate.

Sample A (`d6b01f1a7262`, structured close entry):

```yaml
- closed_at: 2026-07-19T22:44+00:00
  reflect:
    almost_missed: the queued task text named `claim_next_opportunity` picking only
      `.[0]` as root cause, and cited a wrong file path for it -- both wrong. Live
      VPS check (Step-0) proved `PE_V4_MAX_OPS_PER_CYCLE` correctly absent and the
      persona's comment=10 escalation already engaged; a live-tail of an actual cycle
      (PID 2141017) then named the REAL binding mechanism as the m1_preclaim early-break
      at the 80% ceiling, not the queued task's framing. Shipping the queued-task's
      literal fix (batch-claim jq slicing) would have been a no-op.
    codex_rounds: 0 -- codex-task.sh adversarial-review died silently twice in this
      session (SIGTERM at turn boundary, background bash processes get reaped by this
      environment's session teardown even with run_in_background/setsid); fell back
      to Agent(critic, sonnet) per the documented fallback, both review rounds.
```

Sample B (`V5-M0-SKELETON-01`, the only entry in that artifact's measurement
window):

```yaml
- evidence: merged cdd907e76; PRODUCT_KILL_RATE=12/12; isolation_error probe -> runner
    rc=3 + unscored=1; judge-verdict.md; SD-V5-M0-LAWS-REPROBE-AT-M1-01
  failure_class: none
  lesson: 'Enumerating forms does not converge: three rounds added literal, then Path(),
    then os.path.join, and a fifteenth form always existed. Round 4 inverted the default
    (unresolvable => violation) and found the deepest defect.'
  pattern: 'Four adversarial review rounds each found the SAME shape of defect: an
    assertion satisfied by the shape of the code rather than its behaviour.'
  phase: close
  recovery_decision: none
  task: V5-M0-SKELETON-01
  task_class: Heavy
  ts: '2026-08-31T12:32:43Z'
```

Sample C (real forced-close stub):

```yaml
- failure_class: skipped_close
  lesson: Run leadv2-close skill at the end of every task to populate reflect-history
  pattern: task b1af107ffbd7 reached verify phase but Phase 8 close was not invoked
  phase: verify
  stub: true
  task: b1af107ffbd7
  ts: '2026-07-28T13:45:35Z'
  written_by: force-reflect-hook
```

The samples show useful prose can exist, but also that the same store accepts a
forced-close stub. There is no observed downstream outcome attached to either
sample in the primary `leadv2` checkout.

### 3. Readers

The canonical source has one configured semantic consumer:

```text
nl -ba plugins/leadv2/workflows/leadv2-learn.js | sed -n '208,220p'
```

Relevant raw output:

```text
   208	  // Fan-out leg 1: signal aggregation (unchanged logic, model=haiku)
   209	  () => agent(
   210	    `Aggregate the leadv2 learning signals. Steps:\n` +
   211	    `1. Run: bash .claude/scripts/leadv2-signatures-aggregate.sh (if present) and read its output.\n` +
   212	    `2. Read all docs/handoff/*/review-signature.md lines (verdict/blocking/dims).\n` +
   213	    `3. Read docs/leadv2/reflect-history.yaml (if present) — this contains per-close reflect entries (patterns, failure_classes, lessons). It is the PRIMARY accumulated signal source (680+ lines). Parse each entry's failure_class, pattern, and lesson fields.\n` +
   214	    `4. Read docs/leadv2/immune-patterns.yaml (or .claude immune store) if present.\n` +
   215	    `5. Read docs/leadv2/signal-accumulator.yaml — merge its accumulated signals (from prior below-threshold runs) into the count for each class_key.\n` +
   216	    `Combine signals from BOTH review-signature.md files AND reflect-history.yaml entries. ` +
```

That is a workflow prompt to an `agent()` call, not evidence that the workflow
ran. In the primary checkout there are **zero observed learn proposals, zero
`.learn-trigger` files, and zero observed workflow-consumption artifacts** in
the window.

The other matching code is not a learning reader:

- `plugins/leadv2/scripts/leadv2-phase8-assert.sh` checks that an entry exists
  for the current task; it does not use its lesson to change a future task.
- `plugins/leadv2/hooks/leadv2-force-reflect.sh` checks for an entry and can
  write a stub; it is a completeness guard, not a consumer.
- `plugins/leadv2/hooks/learn-trigger-inject.sh` and
  `plugins/leadv2/hooks/leadv2-learn-consume.sh` read `.learn-trigger` and
  inject an instruction to run `leadv2-learn`; the source explicitly says the
  hook does not run the workflow.
- `plugins/leadv2/scripts/leadv2-rag-intake.sh` reads `LEAD_V2_STATE.md`, not
  `reflect-history.yaml`.

Conclusion for live behavior: **the reflect record is write-only in the
measured `leadv2` population**. There is a source-level reader, but no live
read execution or resulting proposal artifact was found.

### 4. Cost

The reflect writer is shell/Python persistence in
`plugins/leadv2/scripts/leadv2-phase8-close.sh`; it makes no model call. The
direct writer cost is therefore **0 model tokens per close**. Its relevant
raw source is:

```text
nl -ba plugins/leadv2/scripts/leadv2-phase8-close.sh | sed -n '620,674p'
```

The source shows a counter increment, a periodic `.learn-trigger` write, and
no `agent()`/workflow invocation. The separate `leadv2-learn.js` workflow
does make model calls when manually run, but no reflect-specific
`costs.yaml`, token ledger, or completed learn proposal exists for the
measured `leadv2` population. Consequently:

- observed reflect runs/week: `0 / 30 * 7 = 0`;
- directly attributable persistence cost/week: `0 tokens`;
- lead-side conversational tokens for the `lead-reflect` skill: **not
  measured**, so an honest `tokens per reflect run × runs per week` total is
  unavailable rather than inventable.

## Architecture judgement

The parked self-learning loop should not be reopened as a build. The measured
system has no live reflect output in the target checkout, no observed reader
execution, and no cost attribution. Adding more aggregation would increase
the amount of unconsumed text without creating a feedback edge.

Existing pieces and disposition:

| Existing piece | Decision |
|---|---|
| `plugins/leadv2/skills/lead-reflect/SKILL.md` | Delete as an automatic learning input; retain only a minimal close/audit record if the founder explicitly wants history. |
| `plugins/leadv2/scripts/leadv2-phase8-close.sh` lines 620–679 | Delete the periodic `.learn-close-counter` / `.learn-trigger` block. It currently schedules work that was not observed to run. |
| `plugins/leadv2/hooks/learn-trigger-inject.sh` | Delete; it only nudges a lead after a trigger exists. |
| `plugins/leadv2/hooks/leadv2-learn-consume.sh` | Delete; it consumes the nudge, not the learning data. |
| `plugins/leadv2/workflows/leadv2-learn.js` | Delete the dormant aggregation workflow unless a future owner first supplies a joined run ledger, an outcome metric, and a bounded cost budget. |
| `docs/leadv2/reflect-history.yaml` and `docs/leadv2/learnings.md` in repos that carry them | Archive/delete as write-only derived logs after checking for any human audit dependency. |
| `plugins/leadv2/hooks/leadv2-immune-intake-inject.sh` and the immune/negative-memory stores | Keep: these are separate, task-time readers with an actual injection path; they are not proof that reflect is consumed. |

Nothing new should be written for self-learning now. If the founder later
reopens it, the minimum new prerequisite is not another prompt: it is a
joined `dispatch_id → reflect_id → reader_run → proposal → accepted/rejected
outcome` ledger plus per-run token telemetry. Without that, the loop cannot be
distinguished from a write-only journal.

## Independent read

Author read: **delete**, based on 0/194 observed reflect reach in the target
checkout, zero observed live reader executions, and absent cost attribution.

The required second opinion is delegated to the plugin review round after this
file is committed. Any substantive disagreement found there must be recorded
below before final close; it must not be averaged away.

## Falsification set

This is a report-only change: no shell or Python files were changed.

```text
$ git diff --name-only --cached
docs/handoff/REFLECT-SELF-LEARNING-DECISION/decision.md

$ bash -n <changed shell files>
NO_CHANGED_SHELL_FILES

$ python3 -m py_compile <changed Python files>
NO_CHANGED_PYTHON_FILES

$ bash tests/run-all.sh --scope changed
suite-discovery: [UNTRACKED-SKIP] 232 suite file(s) refused: not tracked by git (stage or commit to admit; run directly while authoring) — GATE-DISCOVERS-246-UNTRACKED-SUITES-01
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
RUN_ALL_RC=142

$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
suite-discovery: [UNTRACKED-SKIP] 232 suite file(s) refused: not tracked by git (stage or commit to admit; run directly while authoring) — GATE-DISCOVERS-246-UNTRACKED-SUITES-01
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/tests/test-status-surface-bash32.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/tests/test-status-surface-single-lead.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/tests/test-status-surface-fast-names.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/test-plugin-cache-sync.sh
run-all: 5 selected, scope=changed, select_only=1
EXIT=0
```

The first run is the required real changed-scope execution. It hit the explicit
600-second foreground alarm (`142`, SIGALRM) while the pre-existing dirty main
checkout exposed 232 untracked suite files; this is ambient runner evidence,
not a failure in this report-only diff. The second run is the green changed-
scope selection proof after the report correction; it selected five suites and
did not execute them.
