verdict: APPROVE
next_action: review_round_2

leadv2 plugin repo now has docs/tasks.yaml with all 74 migrated leadv2-scoped rows, plus a proven negative-control suite.

- Seeded {total_open, tasks:[]} then populated via 74 real `leadv2_tasks_add` calls (file-only, no Supabase stub).
- New suite test-plugin-repo-backlog.sh: verified RED (mutated load_tasks) → GREEN (reverted); registered in EXTRA_SUITE_MAP, proven selected via `LEADV2_RUN_ALL_SELECT_ONLY=1`.
- persona-engine-close-commands.txt written (not run) for orchestrator to execute post-merge.

Full: developer.full.md
