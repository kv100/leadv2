Product implementation task dispatch-e283a9f5. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# Architect prepass — WHEN-TO-FORK-01 round 2

Design only. No implementation here. Resume worktree `e7d05157`; round 1 shipped
`plugins/leadv2/docs/work-placement.md` (129 lines) there.

## 1. What exists today (verified)

| Fact | Evidence |
|---|---|
| Round-1 rule doc exists, 129 lines, fix-round-1 applied | `.claude/worktrees/e7d05157/plugins/leadv2/docs/work-placement.md:1` |
| Step 0 precondition is asked first, not a branch | same file, lines 16–33 |
| Phase 7 verification is explicitly **not** output-free | same file, lines 85–99 |
| Fork appears **only** as Step 0's escape hatch — it has no row, no cost line, no capability statement | same file: fork is mentioned at :27, :68, :71 and nowhere else |
| `phases.md` §Spawn-hygiene carries a *competing* 3-test ordering with the diff test first | `plugins/leadv2/docs/phases.md:472-474` |
| `phases.md` also asserts "verification always lands here; never a lane" | `plugins/leadv2/docs/phases.md:475` |

Two drifts fall out of the last two rows and both must be fixed by this round, because
`phases.md` is the file the lead actually reads in-flight:

- **D1 (ordering drift).** `phases.md` says "three tests, first match wins" with the diff
  test first. Round 1's fix made the precondition unconditional and first. As written,
  a lead following `phases.md` routes context-dependent diff work to a lane and never
  asks Step 0 — the exact regression the mission forbids.
- **D2 (verification drift).** `phases.md:475` says verification is "never a lane";
  `work-placement.md` §(b2) says Phase 7 verification stays in the owning lane. Directly
  contradictory. `work-placement.md` is correct (Phase 7 has outputs and a rollback
  handoff); `phases.md` must be narrowed to *read-only fact checks*.

## 2. Design — what round 2 adds

### 2.1 Three peer channels, one table (new §, replaces the current asymmetric prose)

Presented as one table with identical columns and no "normal one". Column set, fixed:
`Channel | Costs | Inherits | Can produce | Cannot produce`.

| Channel | Costs | Inherits | Can produce | Cannot produce |
|---|---|---|---|---|
| **Fork** | the session's context re-sent once; no worktree, no spawn ceremony | everything this session knows — decisions, wrong turns, founder statements never written to disk | an answer, a judgement, a synthesis, a file written in the shared tree | a reviewed diff; isolation from this session's uncommitted state; anything that must outlive the session |
| **Dispatch lane (another model)** | worktree claim + architect prepass + worker + review gate + close ≈ several agent hops, minutes | only what the mission file says — always a lossy copy of the session | a committed, reviewed diff; a citable deliverable; a recorded close | anything depending on unwritten session context (it starts blind) |
| **Plain agent** | one spawn, one summary back | only its prompt | a bounded answer from repo/prod/logs | a diff, a review gate, a durable record |

Presentation constraints for the implementer: no channel gets extra prose the others do
not; the fork row is written first; the word "normal"/"default channel" appears for none
of them.

### 2.2 The stated default (new §, one paragraph, must be quotable)

> **When two channels both fit, choose the one that does not have to be re-briefed.**
> A fork inherits; a lane is re-explained. Re-explaining is where the loss happens, so a
> lane is the *justified* choice, not the reflex one: if you open a lane where a fork
> would have been adequate, you owe a one-line reason — and "it felt bigger" is not one.
> Use forks to the maximum: every answer, judgement, or synthesis that leans on what this
> session already knows is a fork by default.

This inverts the burden of proof and is the load-bearing sentence of round 2. It must not
be softened into "consider a fork".

### 2.3 Must-not-fork list (new §, sharp, three entries)

Keep short — the default above is only safe because this list is unambiguous:

1. **It must land a reviewed diff.** A fork buys no review gate. Diff work → lane, always.
2. **It needs isolation from this session's uncommitted state.** A fork sees this tree as
   it is right now, mid-edit. Anything that must build/test against a clean base → lane.
3. **It outlives the session.** If a later session must cite it or resume it, it needs a
   worktree, a close, and a record. A fork dies with its parent.

Mechanical restatement so it is checkable in one look: *diff? isolation? outlives?* — any
yes → lane. All no → fork is available, and by §2.2 it is preferred.

### 2.4 Worked examples from this session (new §, named, with the counterfactual)

Each entry states what was done, what should have been done, and the cost delta. Required
entries, from the mission:

| Work | Went to | Should have been | Why |
|---|---|---|---|
| Ledger-row verification ("is this row still true?") — twice | full dispatch lane, twice | fork (or plain agent when the row is checkable from disk alone) | a ~70-second answer paid worktree + prepass + review + close; no diff, no isolation need, nothing outlived the session |
| Audit synthesis | lane | fork | the input was this session's own findings; the mission file was a lossy re-copy of what the session already held |
| Judgement calls about our own earlier decisions | lane | fork | the subject *is* the session's reasoning trail — Step 0 says this is the one dependency that cannot be materialised without transcribing the session |

The implementer should keep the ledger-row entry's "twice" — repetition is the evidence
that this is a reflex, not a one-off misjudgement.

### 2.5 Reconciling Step 0 with the new default (no regression)

Ordering after round 2, unchanged in sequence:

1. **Step 0 precondition, asked first, always** — does this need something only this
   conversation holds? Materialise it, or fork. (Round-1 text stands verbatim; §2.2 only
   strengthens the fork arm — it does not let anyone skip the question.)
2. **Must-not-fork check** (§2.3) — three yes/no questions.
3. **Channel choice** under the §2.2 default.

§(b2) Phase 7 (lines 85–99) is untouched. The implementer must not re-word it while
editing neighbouring sections; a diff touching lines 85–99 is a review-blocking regression.

### 2.6 phases.md §Spawn-hygiene rewrite (fixes D1 + D2)

Replace `plugins/leadv2/docs/phases.md:471-475` with an ordering that matches
`work-placement.md`: precondition first; then the must-not-fork triple; then "prefer the
channel that needs no re-brief"; and narrow the verification clause to *read-only fact
checks* land on a fork/plain agent — **Phase 7 live verification stays in the owning lane**.
Keep the pointer to `docs/work-placement.md` as canonical and keep this section short — it
is an index, not a second copy of the rule.

## 3. Files

`writes` (repo-relative, inside worktree `e7d05157`):
- `plugins/leadv2/docs/work-placement.md` — exists; add §2.1–§2.4, adjust §2.5 framing.
- `plugins/leadv2/docs/phases.md` — exists; §Spawn-hygiene only (lines ~471–475).

`reads`: the two files above; `plugins/leadv2/docs/model-effort-matrix.md` (exists — for the
orthogonality note only); `docs/handoff/WHEN-TO-FORK-01/mission-round2.md` (exists).

`off_limits`: `docs/leadv2/open-threads.md`; any `plugins/leadv2/scripts/**`;
`work-placement.md` lines 85–99 (Phase 7 §b2) and 16–33 (Step 0) except as §2.5 allows;
`git reset --hard`, `git clean`, `git stash` — three live repos share this tree.

## 4. Risks

| Risk | Mitigation |
|---|---|
| **The default is read as "fork everything"** and diff work starts skipping the review gate | §2.3 is stated as a hard gate *before* the preference, not as a footnote after it; the preference sentence itself names "where a fork is adequate" |
| **Round-1 regression** — a rewrite quietly re-orders Step 0 or trims Phase 7 §b2 | named as off_limits line ranges; reviewer instruction: `git diff` must show no change inside 16–33 or 85–99 |
| **Doc drift** — `phases.md` and `work-placement.md` disagree again (this is exactly what D1/D2 are) | `phases.md` keeps only the ordering + pointer; every criterion lives in one file |
| **Three-column table under-specifies "inherits"** and readers assume a fork inherits a worktree | the fork row says explicitly "no worktree"; must-not-fork #2 repeats it |
| **Un-enforceable rule** — markdown only | mission permits this; §"If this needs teeth" (lines 110–124) already names the advisory `PreToolUse` hook and the `LANE_WRITES:`-empty signal. Round 2 should extend that section with one line: a mission whose `LANE_WRITES` is empty *and* whose brief cites session context is a fork candidate, not a lane. Still advisory, still not built here. |
| **Worked examples name real prior lanes** and read as blame | write them as system findings ("this reflex cost N lanes"), no agent/session ids |

## 5. Non-goals (implementer ignores)

- No hook, script, gate, or `PreToolUse` implementation. Round 2 ships markdown.
- No change to `model-effort-matrix.md` — model choice stays orthogonal.
- No change to `REPORT-ONLY-GATE-01` behaviour or `leadv2-dispatch-product-close.sh`.
- No new fork tooling; FORK-RUNS-A-SESSION-01 (fork owns Phase 0→8) is a separate task and
  must not be pre-empted here.
- No edits to `docs/leadv2/open-threads.md`, board, or active.yaml.
- No renaming of "fresh agent" → "plain agent" anywhere outside the new table's label; keep
  both terms tied together on first use so existing references stay findable.

acceptance:
  surface: file_artifact
  observable: |
    Opening plugins/leadv2/docs/work-placement.md, a reader sees one table whose rows are
    Fork, Dispatch lane, and Plain agent under the identical columns Costs / Inherits /
    Can produce / Cannot produce; below it a stated default sentence saying that when two
    channels both fit, the one that does not have to be re-briefed wins and a lane must be
    justified; a numbered must-not-fork list of exactly three items (reviewed diff,
    isolation from uncommitted state, outlives the session); and a worked-examples section
    naming ledger-row verification (twice), audit synthesis, and judgement calls about the
    session's own earlier decisions as work that took a lane and should have been a fork.
    The Step 0 precondition still appears before any branch, and the Phase 7 section still
    states that verification is not output-free.
  authored_at: 2026-08-17T00:00:00Z

LANE_WRITES: plugins/leadv2/docs/work-placement.md, plugins/leadv2/docs/phases.md

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# MISSION — WHEN-TO-FORK-01, round 2: the fork is a first-class channel, not the exception

Resume the same worktree (`e7d05157`). Round 1's rule is in place and its two review findings are
fixed. **Founder direction, 2026-08-16:** the rule must not merely say *when a fork is allowed* — it
must put the fork on equal footing with the other two channels, and the lead should **use forks to
the maximum** rather than defaulting to a dispatch lane.

Today's real behaviour, which this rule exists to change: the lead reaches for a dispatch lane by
reflex. That is the most expensive channel — worktree, spawn, review gate, close — and it starts
blind, so the lead re-explains the task in a mission file that is always a lossy copy of what the
session already knows.

## What round 2 must add

1. **Three peer channels, one table.** Fork · dispatch-to-another-model · plain agent — presented as
   equals, same columns: what it costs, what it inherits, what it can produce, what it cannot. No
   channel described as "the normal one".
2. **A default that favours the fork where a fork is adequate.** State it explicitly: when two
   channels both fit, prefer the one that does not have to be re-briefed. The lead must justify
   choosing a lane over a fork, not the reverse.
3. **The cases where a fork must NOT be used** — keep these sharp, they are what makes the default
   safe: work that must land a reviewed diff; work needing isolation from the session's own
   uncommitted state; work that outlives the session.
4. **What "maximum use" looks like concretely.** Name work from this session that went to a lane and
   should have been a fork: ledger-row verifications (a 70-second answer that cost a full lane,
   twice), audit synthesis, and judgement calls about our own earlier decisions.

## Keep round 1's corrections

The "needs this session's history" precondition is asked **first, always**, before any branch, and
Phase 7 verification is **not** output-free. Do not regress either.

## Hard constraints
- Never `reset --hard`, `clean`, or `stash` — three live repos share this tree.
- Do not touch `docs/leadv2/open-threads.md`.
- Rules are markdown. If enforcement is needed, name what would enforce it.

## Deliverable
The three-channel table, the stated default, the must-not-fork list, and this session's worked
examples, in the same plugin home as round 1. End with DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-e283a9f5" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.