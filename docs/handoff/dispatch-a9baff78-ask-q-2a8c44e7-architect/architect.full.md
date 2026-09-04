# Decision: dispatch-a9baff78 — edit tests/known-red-suites.txt or defer to lead?

DECISION_OPTION: a
RATIONALE: The shared-lane ban (docs/handoff/RESUME-20260903/_shared.md line 26, "ЗАПРЕЩЕНО: main; tests/known-red-suites.txt; ...") is a lead-owned concurrency rule protecting one hot file shared by every concurrent red-suite lane; a per-lane mission text cannot override it, so the lane hands the diff to the lead as a LEAD_ACTION.

## Why option a

1. **Ownership precedence.** `_shared.md` is the resume-wide contract for all lanes today; the mission text is one lane's local instruction. When they conflict, the shared contract wins (same principle as `context.yaml.off_limits` being a hard stop in the subagent protocol §7).
2. **The ban exists for exactly this file's failure mode.** `tests/known-red-suites.txt` is a single flat list edited by N concurrent lanes that each shrink or add entries. Parallel edits produce merge conflicts or, worse, silent lost updates when the merge queue serialises lanes and one lane's rebase drops another's removal. One writer (the lead) applying all proposed diffs in sequence eliminates that race.
3. **No loss of mission value.** The lane's substantive work is fixing the suites. The known-red list change is bookkeeping derived from that work; a proposed diff with reasons and owners in the deliverable carries identical information and lets the lead apply it once, atomically, after all lanes land.
4. **Option b violates a hard stop.** Editing a banned path "because the mission said so" is the anti-pattern the protocol names (§7: do not work around, escalate instead).

## What the lane should write (for the lead)

In `docs/handoff/SD-MAIN-CORE-SUITE-RED-01/<role>.full.md`:

```
LEAD_ACTION: apply to tests/known-red-suites.txt after lane merge
- REMOVE: <suite-name>            # fixed in this lane, commit <sha>
- ADD:    <suite-name> | reason: <env/self-broken cause> | owner: <who>
```

Include the exact proposed unified diff so the lead can apply it by hand or with `git apply`, and re-verify against the file's state at merge time (other lanes may have moved lines).

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Lead forgets to apply the LEAD_ACTION; fixed suite stays listed as red | Lane's summary.md names the LEAD_ACTION explicitly; lead's close checklist greps deliverables for `LEAD_ACTION:` before Phase 8 |
| Proposed diff goes stale as other lanes edit the file | Lane lists entries by suite name, not line number; lead applies semantically |
| Lane's own CI run still treats the fixed suite as "known red" until the lead applies | Acceptable: the lane proves the fix by the suite going green in its worktree run, independent of the list |

## Out of scope

- Restructuring `known-red-suites.txt` into per-suite files, which would remove the race structurally. Backlog candidate, not this decision.

DELIVERABLE_COMPLETE
