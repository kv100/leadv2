verdict: APPROVE
next_action: continue

Gate inserts at product-close.sh:1816 (after `pc_scope_diff`, before the e2e stamp) — strictly before the pool resolver at :1978, so no review arm is seated; `leadv2-review-run.sh` needs no edit.

- Builder preamble: `_spawn_worker_body` (dispatch-code.sh:2499-2503), after `compute_sig`.
- CRITICAL traps: `py_compile` `__pycache__` pollutes the lane diff; foreign changed files must not red the lane.
- New exit 10; no `phase-record` call (closed enum).

Full: architect.full.md
