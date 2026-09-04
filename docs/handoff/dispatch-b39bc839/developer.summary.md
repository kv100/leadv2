verdict: APPROVE
next_action: review_round_2

Added case5 to test-arm-admission.sh driving resolve_arm()'s real resolver call; all 3 call-site mutations (glm-flash hardcode, protected exclusion, router/arbiter `when:` drift) now RED, revert GREEN (18/0).

- New `resolve_arm_harness()` extracts `_select_base_arm`+`resolve_arm` live from production, stubs the resolver, asserts argv carries `--base-arm cheap-arm`.
- Real edits at leadv2-dispatch-code.sh:1920 and :2087, plus fixture `when:`, each turned only this suite red; reverted, `git diff --stat` clean (only test file +48).
- `tests/run-all.sh --scope changed` timed out on a lock held by a concurrent lane (unrelated); ran the target suite directly instead.

Full: docs/handoff/ARMS-ADMISSION-01/report.md
