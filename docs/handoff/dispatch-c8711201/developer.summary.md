verdict: APPROVE
next_action: review_round_2

Built the codex drain series + NNLS fit; aggregate R2=-0.40 keeps codex null (correctly, per binding rule), per-model fit R2=0.15 gives terra=+0.07/1M tokens but sonnet/glm have no valid comparison number either (their own fit is R2-negative too).

- New tool `leadv2-codex-drain-fit.py`: journal.md util_codex readings + arm-registered ground truth + job-json request.model, reusing the sibling fitter's NNLS/reset-drop logic. gpt-6-astra (launcher alias, not a 4th model) explicitly excluded.
- New suite `test-codex-drain-fit.sh` (13 assertions, registered), all six mission-mandated suites green.
- 10 unrelated NOT-KNOWN-RED failures in changed-scope run verified pre-existing (reverted my one routing.yaml comment edit, same failures on bare HEAD).

Full: developer.full.md
