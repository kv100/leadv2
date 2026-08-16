# Work Placement — fork vs plain agent vs lane (WHEN-TO-FORK-01, 2026-08-16; round 3, 2026-08-17)

Canonical rule for **where** work goes when the lead moves it off its own context. One
**precondition asked first**, then **hard constraints (the must-not-fork gate)**, then a
**preference that favours the fork within the channels the constraints leave eligible** —
three peer channels, none of them "the normal one".

> This doc decides *where* work runs. `docs/model-effort-matrix.md` decides *which model*
> runs it. Orthogonal axes: answer placement here first, model there second.

A rule that lives only in judgement degrades exactly when a session is long and tired —
which is when it matters most. So everything below is a yes/no question about an
**observable property of the work**, checkable in one look. Adjectives are not tests.

---

## Step 0 — precondition (asked first, always; not a branch)

*Does doing this work require something that exists only in this conversation — a decision
made earlier in this session, text this session authored, a founder statement not written
to disk?*

If **yes**, you must do one of two things before dispatching anywhere:

1. **Materialize it** — write the decision/statement verbatim into the mission text or
   `context.yaml` `decisions[]`. It is now on disk, the precondition is discharged, and
   the work continues through the hard-constraint check and preference below like any
   other work.
2. **Fork** — when the dependency is the session's *whole* reasoning trail and not a
   quotable fact or two, so materializing it means transcribing the session. This
   discharge exists **only when the hard-constraint check below returns all-no**. When
   any hard constraint is yes, the fork discharge does not exist: materialize whatever
   the lane's mission needs — transcribe more than feels comfortable if you must — and
   open the lane. A lane briefed from a long transcript is a cost; a reviewed diff that
   skipped its review gate is a defect.

Materializing is the default; forking is the escape hatch for when materializing is not
tractable. Never dispatch context-dependent work without discharging this step — that is
the exact failure this rule exists to prevent. Forking is not discouraged: when the
dependency really is the session's whole reasoning trail and the hard constraints leave
it eligible, a fork is the correct discharge.
**Step 0 never selects a destination. It only decides what must be written down before one
is selected.**

## The three channels — one table, no "normal one"

| Channel | Costs | Inherits | Can produce | Cannot produce |
|---|---|---|---|---|
| **Fork** | the session's context re-sent once; no worktree, no spawn ceremony | everything this session knows — decisions, wrong turns, founder statements never written to disk | an answer, a judgement, a synthesis, a file written in the shared tree | a reviewed diff; isolation from this session's uncommitted state; anything that must outlive the session |
| **Dispatch lane (another model)** | worktree claim + architect prepass + worker + review gate + close ≈ several agent hops, minutes | only what the mission file says — always a lossy copy of the session | a committed, reviewed diff; a citable deliverable; a recorded close | anything depending on unwritten session context (it starts blind) |
| **Plain agent** ("fresh agent" — same channel, both names stay in use) | one spawn, one summary back | only its prompt | a bounded answer from repo/prod/logs | a diff, a review gate, a durable record |

The rows are in no priority order — precedence is decided by the sections below, not by
row order. Reaching for a lane on a 70-second question is not caution, it is a ~50×
overpay.

## Hard constraints — decided first (the must-not-fork gate)

These are constraints, not preferences. Nothing below overrides them, and no Step-0
discharge routes a yes away from a lane. Any yes → lane, always:

1. **It must land a reviewed diff.** A fork buys no review gate. Diff work → lane, always.
2. **It needs isolation from this session's uncommitted state.** A fork sees this tree as
   it is right now, mid-edit. Anything that must build/test against a clean base → lane.
3. **It outlives the session.** If a later session must cite it or resume it, it needs a
   worktree, a close, and a record. A fork dies with its parent.

Mechanical restatement, checkable in one look: *diff? isolation? outlives?* — any yes →
lane. All no → fork is available, and by the preference below it is preferred.

## The preference

> **Among the channels still eligible after the hard constraints, choose the one that does
> not have to be re-briefed.** A fork inherits; a lane is re-explained. Re-explaining is
> where the loss happens, so a lane is the *justified* choice, not the reflex one: if you
> open a lane where a fork would have been adequate, you owe a one-line reason — and "it
> felt bigger" is not one. Use forks to the maximum *within that set*: every answer,
> judgement, or synthesis that leans on what this session already knows — and that lands
> no reviewed diff, needs no isolation, and outlives nothing — is a fork by default.

## Precedence

Three layers, in order; this is the only ordering statement in the doc:

1. **Step 0 precondition, asked first, always** — does this need something only this
   conversation holds? It states a requirement (materialize, or take the fork discharge),
   never a destination.
2. **Hard constraints** — diff? isolation? outlives? Any yes → lane. Mandatory; nothing
   overrides it, and the fork discharge of Step 0 does not exist when any answer is yes.
3. **The preference** — choose among the channels still eligible after the hard
   constraints; prefer the one that needs no re-briefing.

### Report-only work is not an edge case

Hard constraint #3 ("it outlives the session") already decides it. Report-only work (a
deliverable file, not a diff) whose close-time handling is governed by `REPORT-ONLY-GATE-01`
(prose rubric: `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:1987`) matches
**lane**: the review gate is what makes the report citable; a report nobody reviewed is a
claim, not evidence. If nothing will read the file after this session ends, it never hits
hard constraint #3 — answer in ≤50 words to chat, no file.

### Not tests

"Complex", "important", "big", "risky", "it's been a long session" — none of these select
an outcome. If Step 0 and the hard-constraint check do not decide it, the honest answer is
that the work is under-specified; split it until each piece answers them.

---

## Verification — two kinds, not one

### (b1) Read-only fact check → fresh agent

*"Is this ledger row still true?"* — the answer is one of a small closed set (true/false,
a number, a path), it is checkable against disk or prod without editing anything, nothing
is written, and no gated lifecycle step branches on it. Nothing to isolate, nothing to
review.

### (b2) Phase 7 live verification → stays in the task-owning lane

Phase 7 verification is **not output-free**. Its outputs:

| Output | Where it lands | Why it is not "output-free" |
|---|---|---|
| The pass/fail verdict itself | verify/close state written by the lane's close path | A later session reads it as the record of whether the change actually worked |
| Probe evidence (the live signal, re-probed on every 0/null) | task journal / handoff artifacts | It is the evidence backing the completion claim |
| The deploy/rollback decision | acted on, not just reported | Phase 7 failing routes to Recovery — the verifier owns that handoff |

Phase 7 verification is a **gated lifecycle step of the owning lane**, not a question the
lane asks someone else. It is not dispatched anywhere; it runs where the task's ownership,
worktree, and rollback authority already live. Routing it to a fresh agent would hand a
deploy/rollback gate to an agent with no worktree, no ownership, and nothing to roll back
with — the weakest accountability surface in the system.

### The discriminator (mechanical, one look)

*Does anything downstream branch on this answer, or does the answer get written somewhere
a later session reads?*
Either yes → it is not a fact check. It belongs to the lane that owns the thing being
verified. Both no → fresh agent.

---

## Worked examples (from the session that wrote round 2)

System findings, not agent blame — the repetition is the evidence that this is a reflex,
not a one-off misjudgement:

| Work | Went to | Should have been | Why |
|---|---|---|---|
| Ledger-row verification ("is this row still true?") — **twice** | full dispatch lane, twice | fork (or plain agent when the row is checkable from disk alone) | a ~70-second answer paid worktree + prepass + review + close; no diff, no isolation need, nothing outlived the session |
| Audit synthesis | lane | fork | the input was this session's own findings; the mission file was a lossy re-copy of what the session already held |
| Judgement calls about our own earlier decisions | lane | fork | the subject *is* the session's reasoning trail — Step 0 says this is the one dependency that cannot be materialized without transcribing the session — no reviewed diff, no isolation need, nothing outlived the session |

---

## If this needs teeth (not built here)

Stated so a future task has a spec; this doc ships a rule, not machinery:

- A `PreToolUse` advisory modelled exactly on `leadv2-routing-guard.sh` (see
  `docs/routing-enforcement.md`): fires when a dispatch/fanout is opened, greps the
  mission text for a diff-producing intent (`LANE_WRITES:` present, or an `acceptance:`
  surface of `rendered_line|prod_db_row|http_response|file_artifact`), and when absent
  emits to stderr: *"this mission produces no diff and names no durable deliverable — the
  branch test says fresh agent; see docs/work-placement.md"*. **Advisory, exit 0, never
  blocks** — the hook warns, the lead decides.
- Cheaper still: the dispatch door already requires a `LANE_WRITES:` line. A mission
  whose `LANE_WRITES` is empty is, by the hard-constraint check, a fork/plain-agent candidate — the
  signal already exists on disk and only needs reading. Round 2 sharpens it: a mission
  whose `LANE_WRITES` is empty *and* whose brief cites session context is a fork
  candidate, not a lane — still subject to the hard constraints. Docs-only is *not* that
  signal: a durable deliverable is a lane.

## Non-goals of this doc

No hook, no script, no gate was added by the lane that authored this rule. Placement is
advisory documentation the lead reads; nothing here blocks a dispatch.
