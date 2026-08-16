Product implementation task dispatch-6c326da4. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# Architect prepass — WHEN-TO-FORK-01 round 3

**Worktree:** `.claude/worktrees/e7d05157` (resume, do not create a new one).
**Change class:** documentation-only. No script, hook, gate, or test is added or modified.

## 1. The defect, stated precisely

`plugins/leadv2/docs/work-placement.md` currently contains **three** sections that each
state a destination for the same case, and they disagree:

| Site | Text (current) | Destination it mandates |
|---|---|---|
| `:22-33` Step 0, arm 2 | "**Fork** — when the dependency is the session's *whole* reasoning trail" | fork |
| `:47-54` The default | "Use forks to the maximum: every answer, judgement, or synthesis that leans on what this session already knows is a fork by default." | fork |
| `:56-67` Must-not-fork | "It must land a reviewed diff … Diff work → lane, always." | lane |

The overlapping case is real and common: **work that leans on this session's reasoning
trail and also lands a reviewed diff.** Round 2's own worked example (`:139`, "judgement
calls about our own earlier decisions") lives one step from it. A reader following the
document top-to-bottom meets the two fork mandates *before* the gate (`:47` precedes
`:56`), so the cheaper reading is also the first reading — a reviewed diff lands in a fork
with no review gate.

A secondary contributor: `:43-45` frames the channel table as ordered by preference ("the
fork row is written first because it is the arm Step 0 and the default below both push
toward"), reinforcing the same inversion.

Two more files paraphrase the rule and reproduce the same double mandate:

- `plugins/leadv2/commands/leadv2.md:19-21` — "diff test → lane; only-this-session-knows
  test → fork" — two co-equal tests, no precedence; work that trips both has no answer.
- `plugins/leadv2/docs/supervisor-role.md:59-62` — "session-context judgements are forks",
  unqualified.

Third owed item, from round 1: `plugins/leadv2/docs/phases.md:471-476` restates the rule as
a three-line paraphrase. Paraphrases drift — that is what round 1 caught and what will
recur. It must become a pointer.

## 2. Design — explicit precedence, single destination per case

### 2.1 Layer model

Three layers, each with a distinct output type. This is the whole fix; everything else is
its mechanical consequence.

| Layer | Section | Output type | May be overridden by |
|---|---|---|---|
| **Step 0** | precondition, asked first | a **requirement** (materialize, or take the fork discharge) — *never a destination* | nothing; but its fork discharge is conditional on Layer 1 |
| **Layer 1** | Hard constraints (must-not-fork) | a **destination**, when any answer is yes → lane | nothing — no preference, no cheapness argument, no Step-0 discharge |
| **Layer 2** | The preference | a **destination**, chosen among channels still eligible after Layer 1 | nothing below it (it is last) |

The single invariant that makes the review finding impossible to reintroduce:

> **No section states a destination for a case that another section also claims.**
> Layer 1 is the only place a mandatory destination is written. Layer 2 chooses only
> within the set Layer 1 left eligible. Step 0 states a requirement, not a destination.

### 2.2 Step 0 — the arm that has to change

Step 0's fork arm is currently written as a destination and is the primary source of the
contradiction. Rewrite it as a *conditional discharge*:

- Materializing stays the default discharge, unchanged.
- The fork discharge is available **only when the Layer-1 check below returns all-no.**
  When any hard constraint is yes, the fork discharge does not exist: materialize whatever
  the lane's mission needs — transcribe more than feels comfortable if you must — and open
  the lane. A lane briefed from a long transcript is a cost; a reviewed diff that skipped
  its review gate is a defect.
- Explicit sentence to add: *"Step 0 never selects a destination. It only decides what must
  be written down before one is selected."*

This keeps round 1's "precondition asked first, always" intact — the question is still the
first thing asked, and it is still not a branch.

### 2.3 Layer 1 — Hard constraints (renamed, content preserved)

Heading becomes `## Hard constraints — decided first (the must-not-fork gate)`. Keeping the
literal string `must-not-fork` in the heading preserves every existing grep and cross-file
reference. The three items (`reviewed diff` / `isolation from uncommitted state` /
`outlives the session`) and the mechanical restatement *diff? isolation? outlives?* are
kept verbatim — the mission requires it.

Added, one sentence: *"These are constraints, not preferences. Nothing below overrides
them, and no Step-0 discharge routes a yes away from a lane."*

Section is **moved above** "The preference" so document order matches precedence order. The
current `:56` line "checked before the default" becomes unnecessary and is dropped — a
tie-break sentence is exactly what the mission forbids adding.

### 2.4 Layer 2 — The preference (scoped)

Rewritten so every sentence is explicitly scoped to the eligible set:

> **Among the channels still eligible after the hard constraints, choose the one that does
> not have to be re-briefed.** A fork inherits; a lane is re-explained… Use forks to the
> maximum *within that set*: an answer, judgement, or synthesis that leans on what this
> session already knows — and that lands no reviewed diff, needs no isolation, and outlives
> nothing — is a fork by default.

The founder's "use forks to the maximum" and the "you owe a one-line reason for a lane a
fork could have served" teeth both survive; they simply no longer reach work the hard
constraints already claimed.

### 2.5 Channel table framing

`:43-45` loses the "fork row is written first because …" sentence (it asserts a global
preference the precedence no longer supports). Replace with: rows are in no priority order;
keep the "~50× overpay on a 70-second question" line, which is a cost fact, not a
destination.

### 2.6 Downstream sections — audit for stray mandates

- **Report-only work** (`:79-86`) — keep. It already derives from hard constraint #3 and
  the `≤50 words to chat` case is a Layer-2 outcome after an all-no. Reword its first
  sentence to name the layer (`hard constraint #3`) so provenance is visible.
- **Worked examples** (`:130-139`) — keep all three rows (mission requires). Row 3
  ("judgement calls about our own earlier decisions → fork") gains the qualifier *"— no
  reviewed diff, no isolation need, nothing outlived the session"* in the Why column, so it
  cannot be read as a rule that beats Layer 1.
- **Verification §b1/§b2** (`:96-126`) — unchanged. Phase 7 stays a gated lifecycle step of
  the owning lane, not output-free. Heading text `## Verification — two kinds, not one` is
  preserved verbatim because `phases.md` links to it.
- **If this needs teeth** (`:143-158`) — keep; append *"still subject to the hard
  constraints"* to the "empty `LANE_WRITES` + session context → fork candidate" bullet,
  which today reads as a standalone destination.
- **Ordering after round 2** (`:69-77`) — becomes `## Precedence`, restating the three
  layers in order. It is the only ordering statement in the doc.

### 2.7 The three paraphrase sites → pointers

Paraphrase is the drift mechanism. All three become pointers that name sections, not tests.

| File | Current | Becomes |
|---|---|---|
| `plugins/leadv2/docs/phases.md:471-476` | 3-line restatement + Phase-7 sentence | pointer: canonical rule is `docs/work-placement.md`, read in order — §Step 0 precondition → §Hard constraints → §The preference → §Verification — two kinds, not one. No tests restated here. |
| `plugins/leadv2/commands/leadv2.md:19-21` | "diff test → lane; only-this-session-knows test → fork" | pointer: "placement is decided by `docs/work-placement.md` — hard constraints first, preference second"; no per-test destinations |
| `plugins/leadv2/docs/supervisor-role.md:59-62` | "session-context judgements are forks" | pointer: "run the placement rule (`docs/work-placement.md`) before reaching for the funnel"; keep the supervisor-specific point (the supervisor dispatches, never implements) |

Round 1's phases.md complaint (inverted test order, Phase-7 contradiction) is answered
structurally: with no paraphrase there is no order to invert and nothing to contradict.

## 3. Files touched

| Path | Exists | Change |
|---|---|---|
| `plugins/leadv2/docs/work-placement.md` | yes | reorder + rewrite Step 0 arm 2, hard-constraints preamble, preference scoping, precedence section, table framing, 3 downstream qualifiers |
| `plugins/leadv2/docs/phases.md` | yes | §Spawn-hygiene placement block → pointer |
| `plugins/leadv2/commands/leadv2.md` | yes | routing-summary placement line → pointer |
| `plugins/leadv2/docs/supervisor-role.md` | yes | dispatch bullet placement clause → pointer |

All four are canonical plugin files inside `~/Projects/leadv2` — edited once, in the
worktree, never copied into a consuming repo (global shared-trees policy).

## 4. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | Renaming "Must-not-fork" breaks the cross-file reference and greps | keep the literal `must-not-fork` inside the new heading; keep `## Verification — two kinds, not one` byte-identical since `phases.md` links to it |
| R2 | Reordering silently drops round-1/2 content | edit in place, never rewrite the file wholesale; the five mandated survivals (precondition-first, Phase-7-not-output-free, three peer channels, the must-not-fork list, the worked examples) are checked off explicitly before commit |
| R3 | A fourth paraphrase exists somewhere and re-creates the conflict | before commit, grep the worktree for `work-placement` and confirm the only remaining hits are the four files above; any new hit must be a pointer, not a restatement |
| R4 | Pointer-only `phases.md` loses at-a-glance guidance | the pointer names the four section headings in reading order — enough to act on, nothing to drift |
| R5 | Softening "use forks to the maximum" reads as reversing the founder | the sentence is kept, scoped rather than weakened; the doc says in as many words that the preference is unchanged for work the hard constraints do not claim |
| R6 | Adding a tie-break sentence instead of fixing the conflict (explicitly forbidden) | the fix is structural — Step 0's fork arm becomes conditional and the preference is scoped; no sentence of the form "if X and Y conflict, prefer …" is introduced |

Persona-engine constraint checklist: items 1 (env-var naming), 3 (`claude -p` flags),
4 (concurrent access), 5 (config contradiction) are not engaged — no env var, no
invocation, no code, no shared mutable file. Item 2 (path existence) is satisfied: all four
paths verified present in the worktree; no `(to-create)` paths.

## 5. Non-goals — the implementer ignores these

- No hook, script, gate, or test. `leadv2-routing-guard.sh` and the advisory hook sketched
  in §"If this needs teeth" stay unbuilt; that section stays a spec.
- No change to `docs/model-effort-matrix.md` (orthogonal axis) or to
  `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` (REPORT-ONLY-GATE-01 rubric).
- No change to the substance of the three hard constraints, the three channels, or the
  Phase-7 verification rule — only their ordering, framing, and the scoping of the
  preference.
- `docs/leadv2/open-threads.md` is not touched. No `reset --hard`, `clean`, or `stash`.
- The file is not renamed and its headings are not restyled beyond the two changes named
  above.

## 6. Acceptance

```
acceptance:
  - surface: file_artifact
    observable: |
      Reading plugins/leadv2/docs/work-placement.md top to bottom, the hard-constraint
      section (diff / isolation / outlives) appears before the preference section, and the
      preference paragraph reads "Among the channels still eligible after the hard
      constraints ..." — a reader who stops at the first destination-bearing section is sent
      to a lane for diff work, not to a fork.
    authored_at: 2026-08-16T23:20:26Z
  - surface: file_artifact
    observable: |
      In the same file, Step 0's second option no longer reads as a destination: it states
      that the fork discharge is available only when the hard-constraint check returns
      all-no, and that Step 0 never selects a destination. No case in the document names two
      mandatory destinations, and no sentence of the form "if these conflict, prefer X" was
      added.
    authored_at: 2026-08-16T23:20:26Z
  - surface: file_artifact
    observable: |
      plugins/leadv2/docs/phases.md §Spawn-hygiene shows a pointer naming the canonical
      doc's sections in reading order instead of a three-line restatement of the tests, so
      a reader comparing the two files finds nothing that could disagree — including on
      Phase 7 verification.
    authored_at: 2026-08-16T23:20:26Z
  - surface: file_artifact
    observable: |
      plugins/leadv2/commands/leadv2.md and plugins/leadv2/docs/supervisor-role.md each show
      a pointer to the placement rule with no per-test destination ("only-this-session-knows
      test -> fork", "session-context judgements are forks") remaining in either file.
    authored_at: 2026-08-16T23:20:26Z
```

LANE_WRITES: plugins/leadv2/docs/work-placement.md, plugins/leadv2/docs/phases.md, plugins/leadv2/commands/leadv2.md, plugins/leadv2/docs/supervisor-role.md

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# MISSION — WHEN-TO-FORK-01, round 3: the "prefer a fork" default must not route reviewed work away from a lane

Resume the same worktree (`e7d05157`). Review of round 2:
`docs/handoff/dispatch-e283a9f5/review-codex.md`, status **fail**, 0 critical, 1 high.

**`plugins/leadv2/docs/work-placement.md:29-64` — conflicting mandatory destinations bypass the
review lane.** Round 2 added the founder's "prefer the channel that needs no re-briefing" default,
and it now collides with the rule that work producing a landed diff must go through a dispatch lane.
Read literally, some work is mandated to two destinations at once, and the cheaper reading wins —
which is how a reviewed diff ends up in a fork with no review gate.

That inverts the founder's intent. "Use forks to the maximum" means *for work that does not need the
lane's machinery*; it never meant routing a landing diff past review.

## Fix

Make the precedence explicit, in this order:

1. **Hard constraints first** — if the work must land a reviewed diff, must be isolated from the
   session's uncommitted state, or must outlive the session, the destination is a lane. Not a
   preference; no default may override it.
2. **Then the preference** — among the channels still eligible, prefer the one that needs no
   re-briefing.

No rule may state a mandatory destination that another rule contradicts. If two sections both claim
a case, one of them is wrong — fix it rather than adding a tie-break sentence.

## Also still owed, from round 1's review

`plugins/leadv2/docs/phases.md:471` and `:474` — the summary inverts the canonical test order and
contradicts `work-placement.md` on Phase 7 verification. Derive the summary from the rule; if it
cannot be kept in sync, make it a pointer instead of a paraphrase.

## Hard constraints
- Never `reset --hard`, `clean`, or `stash` — three live repos share this tree.
- Do not touch `docs/leadv2/open-threads.md`.
- Keep rounds 1–2: precondition asked first, Phase 7 verification not output-free, three peer
  channels, the must-not-fork list, the worked examples.

## Deliverable
The precedence fix, `phases.md` reconciled with the rule, and no case left with two mandatory
destinations. End with DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-6c326da4" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.