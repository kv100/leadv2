verdict: APPROVE
next_action: continue

A2's tasks.yaml lookup and its own printed remedy (leadv2_tasks_release) both compared task_id against a fingerprint-keyed row's `id` only; fixed both to resolve by id OR intent's colon-anchored prefix.

- Added `resolve_task()`/`resolve_iid()` (shared semantics) to `leadv2_tasks_yaml_common.py` and `leadv2-tasks-lib.sh`; wired into A2's lookup and the `release` op.
- Replaced the false "check lane yamls as fallback" comment/message with an accurate one (no such fallback exists in that branch).
- New suite `test-phase8-a2-id-resolution.sh` (8/8 pass, incl. mutation-kill RED→GREEN proof); wired into `tests/run-all.sh` EXTRA_SUITE_MAP for both changed stems, selection proven via `--scope changed` trace.

Full: developer.full.md
