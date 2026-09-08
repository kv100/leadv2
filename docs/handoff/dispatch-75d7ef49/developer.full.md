verdict: APPROVE
next_action: continue

# JUDGE-ENVELOPE-PARSE-FAILS-A-QUARTER-OF-THE-TIME-01 — fix + evidence

## 1. What was actually returned when the parse failed (captured, not guessed)

Per mission step 1, before changing anything I invoked the real prompt template against
`--model haiku` (`claude -p "<prompt>" --model haiku --max-turns 3 --permission-mode
bypassPermissions --output-format json < /dev/null`) using the mission text:

```
# TEST-JUDGE-PROBE-01
Implement a small bugfix in the payment retry logic for the billing service.
Touches: billing/retry.py, billing/tests/test_retry.py
```

`.result` (redacted, 4/4 trials, run both from this worktree and from a bare `/tmp`
directory with no `.claude` config of its own):

```
"Estimation complete. Ready to dispatch.

работа продолжается: активная задача `dispatch-75d7ef49` в phase build"
```
```
"задача закрыта: JSON estimate provided for TEST-JUDGE-PROBE-01 (complexity: simple, duration: short, risk: safety_publish_payments)"
```
```
"задача закрыта: JSON-оценка сложности задачи TEST-JUDGE-PROBE-01 выведена выше"
```

**This is not "prose around JSON" or "a code fence" or "a truncated reply" or "a refusal" —
it is a FIFTH shape: the reply contains literally zero JSON, and its content (Russian pulse
phrasing, `dispatch-75d7ef49` — THIS task's own id) is unmistakably hook-injected orchestrator
context, not an answer to the judge prompt at all.** It reproduced identically when the `-p`
subprocess was launched from a directory with no project-local `.claude/` config, which means
it is not scoped to this repo's hooks — some `UserPromptSubmit`-level mechanism outside this
script's control is bleeding orchestrator/task-anchor state into headless `claude -p` calls
system-wide while a leadv2 task is active. Every real production judge invocation happens
*during* an active dispatch by construction, so if this is truly systemic it would explain a
large share of the measured 61% failure rate mechanically, independent of any wrapper-format
issue.

**This is out of scope for this task** (constraints restrict me to
`leadv2-task-judge.sh` + my test suite; the injection mechanism lives in the hook/session
layer, which the mission explicitly does not authorize me to touch, and per the standing
"never edit shared trees on your own initiative" rule I did not attempt to trace or fix it).
I am reporting it as a finding, not fixing it — flagging for the founder/lead to decide whether
it merits its own task (candidate id: `JUDGE-SUBPROCESS-HOOK-CONTAMINATION-01`).

## 2. The bug I did find and fix, in-scope, with a live repro

Separately from the contamination above, I found a genuine wrapper-parsing defect in
`_invoke_judge`'s extraction step (`leadv2-task-judge.sh:391`, pre-fix):

```python
m = re.search(r'\{.*\}', result_text, re.DOTALL)
```

This is greedy from the FIRST `{` to the LAST `}` **anywhere in the whole reply**. Repro
(`python3`):

```python
result_text = '''Sure thing! Here is the estimate:

```json
{"complexity":"simple", ... "work_kind":"build"}
```

Let me know if you would like adjustments to the {} shape.'''
m = re.search(r'\{.*\}', result_text, re.DOTALL)
json.loads(m.group(0))   # -> json.decoder.JSONDecodeError: Extra data: line 2 column 1 (char 144)
```

A perfectly valid, complete JSON object — fenced exactly the way haiku is observed to fence
answers (`tests/test-leadv2-task-judge.sh`'s own stub already encodes this fencing behavior as
"observed live") — gets misreported as `envelope_parse` the moment ANY trailing sentence
contains a brace character. This is a real, reproducible defect independent of the
contamination finding above, and squarely the kind of bug the mission asked me to find:
"prose around the JSON" that the old code did NOT actually tolerate despite looking like it
was designed to.

## 3. The fix

Replaced the greedy regex with a string-aware balanced-brace scanner
(`first_balanced_object`, `leadv2-task-judge.sh:412-450`, bounded by new
`# EXTRACT-BEGIN`/`# EXTRACT-END` markers so a test can mutate exactly this span and nothing
else): scans for the first `{`, tracks depth while respecting quoted strings (so a brace
inside a JSON string value never miscounts), and on finding a balanced span tries
`json.loads`; on failure it resumes scanning from the *next* `{` rather than giving up. This
tolerates: code fences, leading prose, and now also trailing prose containing braces. A reply
with no balanced, parseable object anywhere (truncated mid-write, pure prose, a refusal, or the
contamination shape from §1) still finds nothing and still exits 1 → `envelope_parse` →
fallback — permissive about the WRAPPER, never about the CONTENT.

Nothing else in `_invoke_judge`, `_validate_estimate`, `_fallback_estimate`, or the safety
floor was touched. `JUDGE_MODEL`, the estimate vocabulary, and every consumer of the estimate
are untouched (verified: `git diff --stat` shows exactly one file, `leadv2-task-judge.sh`, plus
the new test file).

## 4. Negative controls (E2E-KILLRATE-01), both inside the function body

Both mutate ONLY the text between `# EXTRACT-BEGIN`/`# EXTRACT-END` via a python-level splice
(`_mutate_extractor` in the test file) — never a top-level insert.

**NC1** — revert to the exact old greedy regex. Run against the brace-in-trailing-prose
fixture (§2): before the fix this was the failing case; the mutant reproduces the failure
(`estimate_source=fallback` instead of `judge`). Suite output:
```
PASS: NC1: reverting to the old greedy regex breaks T1 as expected (estimate_source=fallback) -- suite catches this regression
```

**NC2** — make the extractor manufacture a fully-fielded default estimate
(`complexity=standard`, etc.) instead of exiting 1 when no balanced object is found. Run
against the §1 no-JSON-at-all shape: the mutant turns a reply with zero usable content into a
false `estimate_source=judge`. Suite output:
```
PASS: NC2: manufacturing-on-nothing-found mutant turns a no-JSON reply into a false estimate_source=judge -- proves T3 would catch this exact defect
```

Both controls needed one iteration each to actually reach the mutated code path (first pass:
the mutant script, written to a scratch tmpdir, couldn't find its sibling
`leadv2-task-judge-prompt.tmpl` and failed at `template_missing` before ever reaching the
mutation — fixed by having `_mutate_extractor` copy the real template alongside the mutant).

## 5. Test results (raw output, not a summary line)

New suite, `plugins/leadv2/scripts/tests/test-judge-parses-its-own-answer.sh`:
```
[TEST] PASS: T1: fenced JSON + brace-bearing trailing prose -> parsed as judge (regression case fixed)
[TEST] PASS: T2: leading prose + inline JSON -> parsed as judge
[TEST] PASS: T3: reply with no JSON anywhere -> estimate_source=fallback
[TEST] PASS: T4: truncated mid-object reply -> estimate_source=fallback
[TEST] PASS: NC1: reverting to the old greedy regex breaks T1 as expected (estimate_source=fallback) -- suite catches this regression
[TEST] PASS: NC2: manufacturing-on-nothing-found mutant turns a no-JSON reply into a false estimate_source=judge -- proves T3 would catch this exact defect
[TEST] PASS: bash -n syntax OK on leadv2-task-judge.sh

=== Results: 7 passed, 0 failed ===
```

Pre-existing suite (regression check), `test-leadv2-task-judge.sh`: **29 passed, 0 failed**
(unchanged from before the fix — its own T1 already used a fenced-JSON stub with no trailing
brace, so it never exercised the bug, but continues to pass).

Sibling trigger-mapped suites (`leadv2-task-judge` trigger, verified via
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`):
- `plugins/leadv2/tests/test-judge-complexity-path.sh`: **21 passed, 0 failed**
- `plugins/leadv2/tests/test-complexity-source-provenance.sh`: **18 passed, 0 failed**

Falsification set:
```
$ bash -n plugins/leadv2/scripts/leadv2-task-judge.sh && echo OK1
OK1
$ bash -n plugins/leadv2/scripts/tests/test-judge-parses-its-own-answer.sh && echo OK2
OK2
$ git diff --name-only | grep '\.py$' || echo none
none
```
No Python files were changed (the fix is entirely inside embedded `python3 -c` blocks in the
`.sh` file), so no `py_compile` step applies; `bash -n` covers both changed files.

## 6. Acceptance criteria — honest status

The acceptance criterion asks for a before/after rate over **≥10 REAL judge invocations**
(fixture ids excluded, exclusion count reported) showing `envelope_parse` gone and
`estimate_source=judge` appearing where `fallback` used to. **I could not produce that
measurement in this task.** Reasons, stated plainly rather than asserted as done:

- The 61% (14/38 usable) baseline in the mission and in
  `~/Projects/persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/GATE-EVIDENCE.md` row 5a
  was measured by a DIFFERENT session reading REAL production lane journals across many past
  dispatches. I have no mechanism in this task to trigger 10 more real production dispatches
  (that would mean spawning real judge calls from `leadv2-dispatch-code.sh`, which is
  off-limits — "Do NOT touch ... leadv2-dispatch-code.sh").
- What I DID verify live: the exact failure shape from a real `haiku` call (§1, 4/4 real
  trials via the actual prompt template and model), and the exact fenced-JSON-with-trailing-
  prose shape the fix targets, both reproduced against real model output, not invented.
- The two negative controls (§4) demonstrate the fix is real and the suite would catch a
  regression of it — that is the strongest evidence available inside this task's scope and
  turn budget, but it is evidence about the FIX's correctness, not a live production rate.

**Recommendation for whoever closes this task's acceptance criterion:** after this diff
lands and real dispatches resume, re-run the same journal count the gate table used
(`judge_path=`/`judge_fail_reason=` over real, non-`dispatch-deadbeef*` task ids) and compare
against the 14/38 baseline. If the §1 contamination finding is real and systemic, the rate may
still be poor even with this fix — because most of the failure may not be a wrapper-format
problem at all. That would mean `JUDGE-SUBPROCESS-HOOK-CONTAMINATION-01` (or whatever it gets
named) is the row that actually moves the number, and this fix alone is necessary but not
sufficient. I am saying this out loud now rather than after the rate measurement disappoints.

## 7. What I deliberately left alone

- `leadv2-dispatch-code.sh`, `lib/leadv2-route-arbiter.sh`, `leadv2-phase8-e2e-gate.sh`,
  `leadv2-helpers.sh`, `codex-task.sh`, `leadv2-lane-worktree.sh`,
  `config/leadv2-routing.yaml` — untouched, per constraints.
- `JUDGE_MODEL`, the estimate vocabulary — untouched, per mission's explicit out-of-scope list.
- The hook/session contamination mechanism (§1) — investigated only far enough to capture and
  characterize it; not fixed, not further traced (would require touching the hook layer, which
  I was not authorized to touch and which is out of this task's stated scope).
- `_validate_estimate`'s schema check and the safety floor (`_apply_safety_floor`) — untouched;
  they already correctly reject a syntactically-valid-but-semantically-empty object (verified:
  a `{"note":"..."}` reply parses at the extraction stage but is rejected downstream by the
  REQUIRED-fields check, ending in `estimate_source=fallback judge_fail_reason=schema_invalid`
  — this is existing, correct behavior I did not need to change).

Commit: `03b94d91` on `worktree-96c2a18e`. `git diff --stat` before commit:
```
plugins/leadv2/scripts/leadv2-task-judge.sh        |  74 ++++-
.../tests/test-judge-parses-its-own-answer.sh      | 322 +++++++++++++++++++++
2 files changed, 387 insertions(+), 9 deletions(-)
```

DELIVERABLE_COMPLETE
