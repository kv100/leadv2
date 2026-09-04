verdict: NEEDS-INFO
next_action: review_round_2

Evidence gathered for D4; suite is 24/25 green (1 honest coverage-hole FAIL: D10 negative control #2); A2 also observed flaky (fail once in 3 reruns, timing race in fixture setup, not a logic bug).
- Per-function mutation matrix: 9/9 lib functions + 6/8 checkpoint functions flip RED→GREEN cleanly.
- Liveness review: stderr-classified kill -0, unknown never becomes dead — but liveness uses PID+cwd cross-check, NOT PID+start-time as literally required; flagged as a design deviation, not silently claimed compliant.
- EXTRA_SUITE_MAP row specified (not landed — file is lead-owned this lane); selection proof pasted.
Full: developer.full.md
