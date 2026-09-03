# Unmerged worktree-* branch triage — 2026-08-27 (lead, WORKTREE-ZERO-01 follow-up)

Census: 132 `worktree-*` branches existed after the sweep; **63 content-empty (anchor-only) deleted**;
**69 with real diffs vs main kept** — regenerate the list any time:
`for b in $(git for-each-ref --format='%(refname:short)' 'refs/heads/worktree-*'); do echo "$(git log -1 --format='%cs' $b) $b files=$(git diff --name-only main...$b | wc -l)"; done | sort`

## Disposition

- **57 branches dated ≤2026-08-19** — declared SUPERSEDED: their base predates the T13/T14/T15/T17/T18/T19
  merge wave; the subsystems they patch were rewritten. Kept in git (cost: none). Safe to bulk-delete after
  2026-09-10 if nobody claims one.
- **12 branches dated 2026-08-23..26** — reviewed by tip:
  - `worktree-PREPASS-PROVIDER-FALLBACK-01-R7` (`fix(prepass): gate fallback runner startup`) — **REAL
    candidate**, latest round of a 7-round series (R3-R6 superseded by R7). Merge AFTER the T16 lane
    closes (both touch `leadv2-dispatch-code.sh`).
  - `worktree-CTX-COST-GUARDS-01C` (`fix(scope-gate): stop refusing a lane for bootstrap dirt`) — **REAL
    candidate**, touches 2 hooks; merge AFTER T16 (hook overlap). `-01B` is its park-chore predecessor.
  - `worktree-N7F-C3-BOUND-ID` — parked test + doc for dispatch-ledger task-id escape; fold into the next
    dispatch-code round rather than a standalone merge.
  - `worktree-db9a8aa8` and other `park lane work (WORKTREE-ZERO-01)` chores — bookkeeping parks (docs
    churn, phases.d yaml); nothing to merge, delete with the ≤08-19 batch.

## Owner note
Two real candidates (PREPASS-R7, CTX-COST-GUARDS-01C) are queued behind the T16 hygiene lane in this
session; if the session ends first, these two are the only branches worth a human look.
