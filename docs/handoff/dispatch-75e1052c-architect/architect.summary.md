verdict: APPROVE
next_action: continue

Writer: leadv2-dispatch-product-close.sh:550; its only worker-wait (:353-355) fires solely for `sonnet` + numeric PID, so codex/glm/kimi lanes scope the diff at spawn time.

- Fix: provider-aware `pc_await_worker_exit()` before `pc_scope_diff`; timeout → `dead/timeout`, never `no_work`.
- Probes: leadv2-lane-liveness.sh (codex) + job-registry + glm/kimi meta.yaml pid.
- 5 new test cases; suite registered in run-core-offline (22→23).

Full: architect.full.md
