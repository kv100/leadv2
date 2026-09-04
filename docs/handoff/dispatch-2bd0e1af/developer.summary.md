verdict: APPROVE
next_action: review_round_3_or_close

Round 2: root cause found (reasoning-token starvation, not credentials — every ranked route answers HTTP 200) and fixed with a content-based liveness probe, mutation-proven; rank list re-ranked from a real bakeoff including nemotron.

- Probe: `leadv2-freepool-model-select.sh` `_probe()` now requires non-whitespace response text (max_tokens 1→64), not just a 2xx status. New `test-freepool-model-liveness.sh` 5/5, RED control kills a status-only revert.
- Rank: `freepool-arm.yaml` reordered groq/gpt-oss-120b → mistral-code-latest → nemotron-3-super → kimi-k3 → gemini-3.7-flash; deepseek-v4-pro excluded (hung twice at real-work token budgets, not just blank at tiny budgets).
- Fixed a pre-existing test fixture broken by the probe's new content-check contract (`test-freepool-model-selector.sh`, back to 25/25); re-verified round-1's gate (8/8) and arbiter-exclusion (4/4) suites still green.
- Committed on lane branch `worktree-FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01` (8c5db82).

Full: full.md
