verdict: APPROVE
next_action: continue

Factor the pin string into `_set_worktree_pin_line` (~line 581); call it after the PLACEMENT_PINNED guard closes (line 2282), keyed on final WORK_ROOT.

- Two unpinned branches, not one: ensure-created (2272) AND launcher-pre-exported (267).
- Shipped assertion P-h(g) asserts pin ABSENT on default path — it encodes the bug; invert it.
- 21 → 24 assertions.

Full: architect.full.md
