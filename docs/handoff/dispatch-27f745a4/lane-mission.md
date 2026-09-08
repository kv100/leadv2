# Mission: ARBITER-SCORING-DESIGN-01 implementation, Step 2 (additive, still off by default)

Spec: `docs/handoff/F1-ARBITER-SCORING-20260907/design.md` in persona-engine (commits `f88e15c3c`,
`e678b4eb2`, `788106e7f` — read all of it, especially §5.1, §6, §7.1, §7.2, §8 row 2). Step 1 is
already landed (leadv2 commit `b64ce433`, branch `worktree-F1-ARBITER-SCORING-20260907-step1`,
reviewed and accepted) — this mission builds ON that branch/commit, do not redo Step 1's work or
re-touch its files beyond what Step 2 requires.

Founder go-ahead for this shared-plugin edit is already granted (§8 Step 0) — do not re-ask.

## Scope: implement ONLY Step 2 of §8. Do not touch Step 3's shadow-env-var wiring or Step 4's
`enabled: true` flip.

1. `~/Projects/leadv2/plugins/leadv2/scripts/leadv2-task-judge.sh`:
   - Add an optional `complexity_basis` field to the estimate JSON, valued `judge` (judge branch,
     around :328), `class_hint` (around :130-135), or `line_count` (around :136-143) — per §7.2 of
     design.md. **Must NOT be added to the JSON schema's `REQUIRED` list** (around :244-246) — add
     it to `ALLOWED` only, or every cached estimate already on disk fails validation (design.md
     calls this out explicitly, do not skip it).
   - Append ` complexity_basis=${basis:-none}` to the existing journal line around :361.

2. `~/Projects/leadv2/plugins/leadv2/scripts/leadv2-dispatch-code.sh`:
   - Add a new descriptor key `complexity_source` at the descriptor-build site around :8286,
     derived per §5.1/§7.1's mapping table (judge / flag / heuristic / unknown) — read §5.1 in
     full, it specifies exactly which conditions map to which source value (judge branch,
     explicit `--task-class` flag, admission-source flag/task_record, vs the heuristic
     line-count fallback).
   - Apply the declared-class floor to `complexity`: an explicit/admission-derived class hint
     RAISES the effective complexity floor (never lowers it) per §5.1 — verify the exact mapping
     (Light→simple, Standard→standard, Heavy/Strategic→complex, same table task-judge already
     uses at :130-135) before wiring it.
   - design.md flags one thing as UNVERIFIED for the implementer to confirm: which of the two
     task-judge call sites (dispatch-code :3051 or :3094) actually feeds the `DC_COMPLEXITY` /
     `DC_DURATION_CLASS` variables used at :7609-7612 — resolve this ambiguity and record which
     one it actually is in your report; don't guess silently.

3. Do NOT touch Step 1's arbiter/yaml files beyond anything Step 2 genuinely requires (e.g. if the
   arbiter needs a trivial wiring change to consume the new `complexity_source` descriptor key
   that Step 1 already reads as `d.get('complexity_source','unknown')` — check §6's pseudocode,
   Step 1 already added the READ side; Step 2 is about making sure something real gets WRITTEN
   into that field). If Step 1 already fully covers the read side and nothing needs to change
   there, say so explicitly in your report rather than touching working code.

4. Acceptance target from §8 row 2: "descriptor carries provenance; still off" — verify via a
   live journal check: `complexity_source=unknown` count = 0 over ≥20 NEW `route_resolved` lines
   generated during your own testing, with ≥1 `complexity_source=heuristic` line as the positive
   control (i.e. don't just claim zero unknowns — show the ≥20-line sample and that at least one
   real line has a non-unknown source, proving the field is actually being populated, not just
   defaulting silently to a value that happens to not print as "unknown").

## Out of scope (§11, read it — same list as Step 1, still applies): task_class's sizes-filter
role, freepool floor mode, UNKNOWN_PROBE_PENALTY, failure-memory demotion, effort_matrix, legacy
resolver/kimi arm, complexity_penalty itself, any persona-engine file, Step 3's shadow env var,
Step 4's `enabled: true` flip.

## Acceptance (I run this myself before accepting — do not self-certify as done)

- New/changed tests still green plus Step 1's existing `tests/test-router-v2-capability-fit.sh`
  and `tests/test-router-v2-headroom-order.sh` both still green (no regression).
- Live demonstration: ≥20 new `route_resolved` lines with `complexity_source=unknown` count 0 among
  ones that had a real source, and ≥1 `complexity_source=heuristic` positive control line, per §8
  row 2's acceptance text — quote the actual grep output, not a paraphrase.
- Report which of :3051/:3094 actually feeds :7609-7612 (the design doc's own flagged unknown).
- `checked=N` for every claimed count, per this project's measurement discipline.
- Report back the git commit hash and branch, same as Step 1's report format.

Lead (this session) does the review and acceptance against §9.2/§9.3 and this mission's specific
acceptance bullets — you are not self-certifying this as done, you are handing it back for review.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-27f745a4" "<question>" \
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