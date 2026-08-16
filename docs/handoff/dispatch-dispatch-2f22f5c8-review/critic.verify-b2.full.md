# Refutation pass — finding "verification always lands here; never a lane"

Target: `plugins/leadv2/docs/phases.md` §Spawn-hygiene, added line 3 of the
placement summary (`/tmp/wp.diff` hunk `@@ -468,4 +468,9 @@`):

```
3. Otherwise — bounded question answerable from repo/prod/logs alone? → fresh agent (verification always lands here; never a lane).
```

Canonical rule, same diff, `plugins/leadv2/docs/work-placement.md` (new file,
`## Verification — two kinds, not one`):

- **(b1) Read-only fact check → fresh agent** — closed-set answer, nothing written,
  "no gated lifecycle step branches on it".
- **(b2) Phase 7 live verification → stays in the task-owning lane** — explicitly
  "not output-free": writes verify/close state, deposits probe evidence in the task
  journal, and owns the deploy/rollback decision (failure routes to Recovery).
  Verbatim: "Routing it to a fresh agent would hand a deploy/rollback gate to an
  agent with no worktree, no ownership, and nothing to roll back with."

The parenthetical is unqualified ("**always** … **never** a lane") and therefore
covers b2, which the canonical doc places in the lane. The summary and the rule it
summarizes disagree on the one case with a deploy/rollback gate attached. A lead
reading only phases.md §Spawn-hygiene — which is the point of a summary — routes
Phase 7 to a worktree-less fresh agent.

Attempted refutations, all fail:

1. *"Fresh agent applies only after the branch test, so b2 is already excluded."*
   No — b2 work does leave durable output (verify/close state, journal evidence),
   so it fails the diff test and never reaches clause 3; but the parenthetical is
   attached as a blanket statement about verification, not scoped to work that
   reached clause 3. "always … never" is exactly the wording that overrides the
   branch test for a reader.
2. *"'Verification' in the parenthetical obviously means the b1 sense."*
   Not obvious to the intended reader: phases.md is the phase doc, and Phase 7 in
   the same file is literally named verification. If anything the local context
   biases toward the wrong reading.
3. *"The pointer to `docs/work-placement.md` covers it."*
   The pointer names the canonical rule; a summary that states the opposite of the
   canonical rule is a defect regardless of the pointer — the reader has no signal
   that this line is the one to distrust.

Corroborating evidence that the b1/b2 split is recent and the summary is stale:
`docs/handoff/WHEN-TO-FORK-01/report.md` §Verification still describes the doc as
having a single §"Edge case (b): verification" (fresh agent, never a lane) — the
wording the phases.md parenthetical mirrors. The canonical doc was split into
b1/b2 in "fix round 1, 2026-08-17" (its own title line); phases.md was not updated
with it.

Required fix: scope the parenthetical, e.g.
`→ fresh agent (read-only fact checks land here; Phase 7 live verification stays in the owning lane — see work-placement.md §Verification)`.

VERIFY_VERDICT: upheld

DELIVERABLE_COMPLETE
