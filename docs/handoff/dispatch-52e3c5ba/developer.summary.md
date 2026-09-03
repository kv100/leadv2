verdict: APPROVE
next_action: review_round_2

Registered 13 of 14 dark suites in tests/run-all.sh EXTRA_SUITE_MAP; --scope changed selection proven on macOS + Linux (17/17), negative control (baseline_rc=0/mutated_rc=1) proven both OSes.

- 17 new EXTRA_SUITE_MAP rows keyed to each suite's real SUT script
- Selection proof: touched each of 9 production files, confirmed [SELECT] on both OSes
- Negative control: function-body mutation in leadv2-lane-liveness.sh via leadv2-mutation-control.sh, red then revert-green, both OSes

Full: docs/handoff/DARK-SUITES-UNREACHABLE-BY-RUNNER-01/report.md (canonical deliverable); docs/handoff/dispatch-52e3c5ba/developer.full.md has the WRITE_ROOT note.
