verdict: APPROVE
next_action: continue

Built the standalone P6a complexity estimator + its easy-half test suite; both negative controls verified red via leadv2-mutation-control.sh.

- New `plugins/leadv2/scripts/lib/leadv2-complexity-estimate.py`: real estimate from mission text + write-set/subsystem signals; `complexity_source` in flag|estimate|unknown (flag is an explicit exception, not default).
- New `plugins/leadv2/scripts/tests/test-complexity-estimate-easy-half.sh` (5/5 pass), self-registers via `run-all-triggers`.
- Wiring into leadv2-dispatch-code.sh explicitly NOT done (out of scope; report names the exact `EXTRA_SUITE_MAP` line part B still owes).

Full: full.md
