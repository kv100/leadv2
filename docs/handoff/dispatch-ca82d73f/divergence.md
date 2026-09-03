# FP-06 divergence (mini)
- A. Telemetry via separate collector daemon — REJECTED: new moving part, violates no-new-daemon budget.
- B. Telemetry inside each arm coder script — REJECTED: N emit points drift (three doors disease).
- C. Single emit at dispatch terminal journal point + CSV mirror — CHOSEN: one choke point already exists.
- Floor knob: env-only vs yaml+env — CHOSEN yaml+env (operator surface documented in FP-05 block).
