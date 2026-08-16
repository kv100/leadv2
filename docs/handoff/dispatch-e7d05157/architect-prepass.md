# WHEN-TO-FORK-01 — architect prepass

Put the fork / fresh-agent / lane choice in the plugin as a **checkable three-test rule**, in one
canonical doc, cited from the three places the lead actually looks before moving work off its
context. No hook, no script, no enforcement code in this lane.

---

## 1. Layers affected

| Layer | File | Change |
|---|---|---|
| Plugin doc (new) | `plugins/leadv2/docs/work-placement.md` | **(to-create)** the canonical rule |
| Lead entry | `plugins/leadv2/commands/leadv2.md` | one pointer line in `# Routing summary` (~L17-20) |
| Phase reference | `plugins/leadv2/docs/phases.md` | `§Spawn-hygiene` (~L469) gains the 3 tests inline + pointer |
| Supervisor doc | `plugins/leadv2/docs/supervisor-role.md` | pointer at `§What a supervisor session IS` / dispatch-funnel para (~L116) |
| Report | `docs/handoff/WHEN-TO-FORK-01/report.md` | **(to-create)** one worked example per branch |

Why these three citation sites and no others: `commands/leadv2.md` is loaded on every `/leadv2`
invocation (routing summary already delegates to `docs/model-effort-matrix.md` — same pattern, same
place); `phases.md §Spawn-hygiene` is the existing home of "what a spawn costs"; `supervisor-role.md`
is where the lead stands when it is about to reach for the dispatch funnel. The dispatch door itself
(`leadv2-dispatch-code.sh`, `leadv2-fanout.sh`) is **not** edited — it is a script, and a markdown
rule does not belong inside it.

## 2. The rule — three tests, ordered, first match wins

`work-placement.md` states the tests as properties checkable in one look, never as adjectives.

**Test 1 — the diff test → dispatch lane.**
*Does this work end in something that must be committed to the repo and reviewed before it is
trusted — a diff, or a deliverable file another session will cite after this one ends?*
Yes → lane. A lane exists to buy exactly three things: an isolated worktree, a review gate, and a
close that records what landed. Work that produces nothing to land is paying for all three and using
none.

**Test 2 — the "only this session knows" test → fork.**
*Does answering require something that exists only in this conversation — a decision made earlier in
this session, text this session authored, a founder statement not written to disk?*
Yes → fork. A fork inherits the session's history; that inheritance is the entire product being
bought, and it is worth nothing when the answer is on disk.

**Test 3 — otherwise → fresh agent.**
A bounded question answerable from repo, prod, or logs alone. Session context is not neutral here,
it is noise: it costs tokens on every remaining turn of the parent and can poison the answer with
the session's own wrong turns.

**Not tests.** "Complex", "important", "big", "risky", "it's been a long session" — none of these
select a branch. If the three tests above do not decide it, the honest answer is that the work is
under-specified; split it until each piece answers one test.

**Cost asymmetry (stated so the default stops being "lane").** A lane = worktree claim + architect
prepass + worker + review gate + close ≈ several agent hops and minutes of wall-clock. A fresh agent
= one spawn, one summary back. A fork = the session's whole context re-sent. Reaching for a lane on
a 70-second question is not caution, it is a ~50× overpay.

## 3. The two edge cases, settled explicitly

**(a) Report-only work** (produces a deliverable file, not a diff). The dispatch door already knows
how to close such a lane (`REPORT-ONLY-GATE-01`; the prose rubric lives at
`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:1987`). The placement question is separate
and the rule answers it with one test:

> *Will anything read this file after this session ends — another lane, a later task, the founder?*
> Yes → lane (the review gate is what makes the report citable; a report nobody reviewed is a claim,
> not evidence). No → fresh agent, answer in ≤50 words to chat, no file.

**(b) Verification** ("is this ledger row still true?"). **Always a fresh agent. Never a lane.**
The test that makes this mechanical: *the answer is one of a small closed set — true/false, a
number, a path — and it is checkable against disk or prod without editing anything.* Nothing is
produced, so there is nothing for a worktree to isolate and nothing for a review gate to review.
This is the case that cost two full lanes in the observed session.

## 4. Data flow — how the lead reaches the rule

1. Lead is about to move work off its own context (any phase).
2. `commands/leadv2.md` `# Routing summary` names `docs/work-placement.md` beside the existing
   `docs/model-effort-matrix.md` pointer — *placement* first, *model* second. They are orthogonal
   and the doc says so in one line, so neither is mistaken for the other.
3. Lead applies Test 1 → Test 2 → Test 3, first match wins.
4. Lane branch → `supervisor-role.md` / `leadv2-fanout.sh` funnel, unchanged.
   Fork branch → session fork, unchanged.
   Fresh-agent branch → `Agent(...)` under the existing `phases.md §Spawn-hygiene` chat budget.

No new state, no new file formats, no schema, no migration. This is documentation with three
cross-references.

## 5. Risks and mitigations

| Risk | Mitigation |
|---|---|
| A fourth copy of the rule drifts from the other three | Only `work-placement.md` states the tests in full. `supervisor-role.md` and `commands/leadv2.md` carry a **pointer only**. `phases.md §Spawn-hygiene` may restate the three one-line tests (it is the doc a lead reads mid-spawn) — it must carry the pointer on the same line so the canonical source is one hop away. |
| Rule read as advice, ignored under load — the exact failure it targets | The tests are yes/no on observable properties, so "I judged it complex" is not an available answer. Enforcement is **named, not built** (§6). |
| Founder reads this as new machinery | Non-goals section in the doc itself: no hook, no script, no gate added by this lane. |
| Shared-tree blast radius | All edits are inside `plugins/leadv2/` — the plugin repo is the single source and this IS that repo. No per-repo `.claude/leadv2-overrides/` touched, no `~/.claude/leadv2-shared/` touched. |
| Editing `phases.md` / `supervisor-role.md` collides with a parallel session | Both are append-at-a-section edits in distinct sections; re-`git diff` immediately before staging (global rule). Three live repos share this tree — **never** `reset --hard` / `clean` / `stash`. |
| `docs/leadv2/open-threads.md` | Hard off-limits per mission. Not in `LANE_WRITES`. |

## 6. Enforcement — what *would* enforce it (nothing built here)

Stated in the doc under "If this needs teeth", so a future task has a spec and this lane ships a
rule:

- A `PreToolUse` advisory modelled exactly on `leadv2-routing-guard.sh` (see
  `docs/routing-enforcement.md`): fires when a dispatch/fanout is opened, greps the mission text for
  a diff-producing intent (`LANE_WRITES:` present, or an `acceptance:` surface of
  `rendered_line|prod_db_row|http_response`), and when absent emits to stderr:
  *"this mission produces no diff and names no durable deliverable — Test 1 says fresh agent; see
  docs/work-placement.md"*. **Advisory, exit 0, never blocks** — the hook warns, the lead decides.
- Cheaper still and worth naming: the dispatch door already requires a `LANE_WRITES:` line. A
  mission whose `LANE_WRITES` is empty or docs-only is, by Test 1, a fresh-agent candidate — the
  signal already exists on disk and only needs reading.

Neither is in scope here. The mission says: say what would enforce it rather than build a hook
nobody asked for.

## 7. Out of scope (for the implementing agent)

- No changes to `leadv2-dispatch-code.sh`, `leadv2-fanout.sh`, `leadv2-supervise.sh`, or any script.
- No new hook, no `settings.json` change, no new env var (so constraint-checklist items 1, 3 and 5
  are vacuous for this lane: no env vars introduced, no `claude -p` invocation added, no config
  semantics touched).
- No change to how lanes close, to `REPORT-ONLY-GATE-01`, or to the review gate.
- No touching `docs/leadv2/open-threads.md`, `active.yaml`, or any control-plane state.
- No rewriting of `model-effort-matrix.md` — placement and model routing stay separate docs, linked.
- No test file. This lane's artifact is prose; there is no behaviour to assert.

## 8. Constraint checklist

1. **Env vars** — none introduced. N/A.
2. **File paths** — `plugins/leadv2/docs/{phases,supervisor-role}.md`, `plugins/leadv2/commands/leadv2.md` verified present on disk this turn. `plugins/leadv2/docs/work-placement.md` and `docs/handoff/WHEN-TO-FORK-01/report.md` are **(to-create)**.
3. **`claude -p`** — no invocation added. N/A.
4. **Concurrent access** — `phases.md` and `supervisor-role.md` are read by every live lead session. Edits are additive within one section each; re-`git diff` immediately before `git add`. No lock needed for an additive markdown edit.
5. **Config contradiction** — no config touched. The one semantic overlap is `docs/model-effort-matrix.md` (which model), disambiguated by an explicit one-line "this doc decides *where*, that one decides *which model*" in `work-placement.md`.

---

acceptance:
  - surface: file_artifact
    observable: "plugins/leadv2/docs/work-placement.md exists and its body states three numbered branches — lane, fork, fresh agent — each introduced by a yes/no question about an observable property of the work, and contains a section naming verification work as fresh-agent and a section naming when report-only work belongs in a lane."
    authored_at: 2026-08-16T00:00:00Z
  - surface: rendered_line
    observable: "A lead reading plugins/leadv2/commands/leadv2.md '# Routing summary' sees a line naming docs/work-placement.md as the doc that decides fork vs fresh agent vs lane, beside the existing model-effort-matrix.md pointer."
    authored_at: 2026-08-16T00:00:00Z
  - surface: rendered_line
    observable: "A lead reading plugins/leadv2/docs/phases.md '§Spawn-hygiene' sees the three tests stated in one line each with a pointer to docs/work-placement.md on the same line."
    authored_at: 2026-08-16T00:00:00Z
  - surface: file_artifact
    observable: "docs/handoff/WHEN-TO-FORK-01/report.md contains three worked examples from this session's real lanes — one that should have been a fork, one that should have been a fresh agent, one correctly a lane — each naming the lane or spawn it refers to, and ends with DELIVERABLE_COMPLETE."
    authored_at: 2026-08-16T00:00:00Z

LANE_WRITES: plugins/leadv2/docs/work-placement.md, plugins/leadv2/docs/phases.md, plugins/leadv2/docs/supervisor-role.md, plugins/leadv2/commands/leadv2.md

DELIVERABLE_COMPLETE
