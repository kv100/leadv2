# Fixed-shape workflow-step receipt

`plugins/leadv2/scripts/lib/leadv2-workflow-step.sh` exposes `run-step` / `leadv2_workflow_run_step(request)`. It is a workflow-facing facade, not a launcher: it calls the existing `leadv2-dispatch-code.sh` spine with the admitted arm pinned, then checks the dispatcher's own emitted arbiter record against the admitted `(arm, model, tier, effort)` tuple.

The request records `workflow_run_id`, `step_id`, `attempt`, input text (whose SHA-256 is receipt-bound), fixed `admitted_W` / `admitted_R`, the exact arbiter tuple, mission text, and lane writes. It has no shape policy inputs or adaptive branches.

Every invocation appends one terminal JSON receipt to `${LEADV2_WORKFLOW_RECEIPTS_LEDGER:-$HOME/.claude/state/leadv2/workflow-receipts.jsonl}` and prints that same receipt. The ledger is external append-only runtime data, never a repository state file. `admitted_arbiter_decision` preserves the supplied decision; `arbiter_decision` records the tuple the dispatcher actually emitted (or `null` if no dispatch decision exists), and `decision_matches_admission` makes disagreement explicit. A successful dispatch only proves that an asynchronous worker was admitted; without an observed completion it is `unknown_completion`, never `completed`. Dispatcher budget and control-plane exits map to `budget_exhausted` and `blocked_control_plane`; callers may supply observed terminal counts for a completed step.

The receipt makes the initial measurement directly computable:

```text
shape_realization_rate = completed_receipts_with(actual_steps == admitted_W and actual_rounds == admitted_R)
                       / terminal_workflow_receipts
```

All four terminal statuses remain in the denominator. `shape_realized` is true only for a completed receipt whose observed counts equal the admitted fixed shape. It is derived from observed counts, not copied from the plan.
