verdict: APPROVE
next_action: review_round_2

Fixed leadv2-review-run.sh's findings parser to recognize flat bracket-severity findings (Codex shape), stopping false `findings_lost` blocks.

- Added additive bracket-list parsing branch to the per-arm FINDING: union loop (only when no `FINDING:` lines present).
- product-close.sh's gate (the other emit site) already reads the arm's self-declared `REVIEW_FINDINGS:` line directly — confirmed unaffected, left untouched.
- New suite `test-review-gate-codex-flat-list.sh` (9/9 green) with real specimen fixture, negative control (empty report still blocks), and mutation control (RED without fix, restored).

Full: report.md / developer.full.md
