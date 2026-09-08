verdict: APPROVE
next_action: review_round_2

Fixed: run-all.sh now forwards its own `--scope` to run-core-offline.sh instead of invoking it bare (which silently ran the full 95-suite set every time regardless of `--scope changed`).

- `tests/run-all.sh`: new `core_offline_scope_arg()` forwards `${SCOPE}`; delegation line logs what was forwarded.
- New hermetic suite `tests/test-run-all-forwards-scope.sh`, self-registered (`run-all-triggers: run-all run-core-offline`), both negative controls confirmed red via `leadv2-mutation-control.sh`.
- Found (not fixed, out of LANE_WRITES): pre-existing pipefail/`grep -q` SIGPIPE race in `tests/test-run-all-self-registration.sh`, reproduces on clean main too.

Full: full.md
