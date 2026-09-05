Review ONLY the diff at /tmp/FABLE-THINK-TIER-01-review.diff. You are independent of the author (sonnet).
Report correctness findings by severity (Critical / High / Medium / Low).
VERIFICATION-ONLY ROUND 3

This diff already went through review. Below are the prior findings from the previous round.
For each one, verify by execution whether each prior finding below is fixed.
Admit a NEW finding ONLY if the fixes introduced it. Do not re-litigate pre-existing issues you were not asked to verify.

Prior findings:
- [Critical/design] plugins/leadv2/skills/leadv2-judge/SKILL.md:9 Hardcoded `fable` at 7 think-role spawn sites never consults the resolver, so the `unavailable: true` opus kill-switch — the change's only documented rollback — is unreachable; census regex matches only `opus`, so it can never detect 
- [Critical/correctness] plugins/leadv2/scripts/leadv2-repo-install.sh:302 Writing LEADV2_MAIN_MODEL=fable makes leadv2-main-model-check.sh:60 return early, silently disabling opus_mode_guardrails and the daily budget check for every repo on next install/refresh, with no replacement and no test.
- [High/correctness] plugins/leadv2/scripts/leadv2-llm-judge.sh:393 Router invoked one line before its own `[[ -f "$ROUTER_SCRIPT" ]]` check; under `set -euo pipefail` a missing router aborts the script, so the `model="${model:-fable}"` guard on the next line is unreachable on exactly the failure it
- [High/correctness] plugins/leadv2/scripts/leadv2-session-route.sh:193 Two unguarded resolver command substitutions (:63 and :193) with no `|| true` under `set -euo pipefail` — a nonzero resolver kills session routing outright instead of degrading; :63 is also dead (overwritten by :193) and config 
- [High/correctness] plugins/leadv2/scripts/leadv2-ask.sh:0 `_architect_decide()` resolves via `lib/leadv2-think-model.sh` with `2>/dev/null` and NO fallback and NO empty-guard, so a failing or empty resolver yields `model=""` and spawns with an empty model.
- [High/correctness] plugins/leadv2/scripts/tests/test-fable-think-tier.sh:1108 Tree-wide census greps scripts/workflows/skills/hooks but NOT config/ — the exact blind spot that let `config/session-routing.yaml:31` pin opus and produce the round-4 regression; a second config pin in any other consume
- [High/design] plugins/leadv2/scripts/tests/test-fable-think-tier.sh:1072 The allowlist exempts a self-admitted LIVE think-role opus pin (`leadv2-causal-critique.js`, reason text says "PRE-EXISTING think-role pin … NOT fixed here"), so the census is green by exemption rather than by compliance.
- [High/correctness] plugins/leadv2/workflows/leadv2-diverge.js:1539 New opus fallback is a bare `await agent(...)` outside `synthAgent`'s try/catch, so a throw now aborts the workflow where it was previously swallowed and fell through to the haiku fallback; same shape in leadv2-po-feedback-loop.js.
- [High/design] plugins/leadv2/scripts/leadv2-dispatch-code.sh:485 Call-site fallbacks diverge across nine resolver sites (opus / fable / sonnet / none), directly contradicting the diff's own stated invariant that "that opus fallback lives in exactly ONE place — the router — never at a call site".

Your review MUST contain these two lines, verbatim format, before any prose:
REVIEW_VERDICT: <FAIL|PASS|PASS_WITH_NITS>
REVIEW_FINDINGS: critical=<n> high=<n> medium=<n> low=<n>
FAIL if any Critical or High finding. PASS if the diff is clean. PASS_WITH_NITS otherwise.
Also report every Critical/High finding on its own line, exact format:
FINDING: severity=<Critical|High> file=<path> line=<n> dimension=<correctness|security|design|perf> desc=<one line>

If no findings are found, please output a brief explanation (at least one sentence) after the required lines to ensure the review body is sufficient for processing.
