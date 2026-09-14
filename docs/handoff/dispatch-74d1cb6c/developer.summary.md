verdict: APPROVE
next_action: review_round_2

A dead quota probe now renders `⚠` + reader error (+ named remedy, e.g. "codex login") instead of a plausible percentage, on both human-facing surfaces (status-surface `--limits`, codex-lead statusline), plus an edge-triggered `[SUPERVISE-URGENT] QUOTA_UNKNOWN` pulse-log line.

- Fixed a bash brace-expansion fixture bug (`${VAR:-{}}`) and a test sequencing gap in the new suite while verifying it (both were test-only, not production).
- 15/15 new suite assertions pass with real negative (forced-unknown) and positive (recovery) controls; 7 named regression suites still green.

Full: developer.full.md
