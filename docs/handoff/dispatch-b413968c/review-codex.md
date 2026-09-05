# Codex Adversarial Review

Target: branch diff against 2eaea77cb05edd6cae11db851ae05197e5de72e5
Verdict: needs-attention

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=7 medium=0 low=0
FINDING: severity=High file=plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py line=335 dimension=correctness desc=A top-level Codex limit_reached=true is ignored whenever the binding window exists without its own true flag, so the resolver can select a provider that has already declared a hard stop.
FINDING: severity=High file=plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh line=68 dimension=correctness desc=The new unconditional live gate makes existing core-offline quota-guardrail cases depend on the host Codex quota state and fail when real usage is at the ceiling.
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-glm-quota-gate.sh line=44 dimension=correctness desc=A nonnumeric documented LEADV2_CEIL_GLM_WORK override now reaches arithmetic under set -u and aborts the GLM gate instead of following its fail-open contract.
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-provider-quota-gate.sh line=28 dimension=perf desc=An unbounded LEADV2_QUOTA_READ_TIMEOUT can make the polling loop block every Codex spawn for days, defeating the stated bounded-subprocess guarantee.
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-provider-quota-gate.sh line=61 dimension=design desc=The decision-driving claim that Codex limit_reached means 100% is neither tagged UNVERIFIED nor supported by an inline provider document and live probe.
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-burn-governor.sh line=217 dimension=design desc=The decision-driving claim that Codex limit_reached means 100% is neither tagged UNVERIFIED nor supported by an inline provider document and live probe.
FINDING: severity=High file=plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py line=335 dimension=design desc=The decision-driving claim that Codex limit_reached means 100% is neither tagged UNVERIFIED nor supported by an inline provider document and live probe.
No-ship: the resolver can admit a hard-limited provider, and the added gate is neither reliably bounded nor isolated from offline tests.

Findings:
- [high] Top-level hard limit is bypassed by binding-window lookup (plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:335-338)
  When top-level `limit_reached` is true while the binding window has false or missing `limit_reached`, this returns its low `used_percent` before checking the global stop, allowing review-pool selection of a provider that has already refused requests.
  Recommendation: Check top-level `limit_reached` before iterating windows, then add a fixture with top-level true and a binding window at a low percentage.
- [high] Offline test suite now reads live account state (plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh:68-69)
  The unconditional provider-gate call makes existing `test-codex-quota-guardrails.sh` pass-path invocations query the real quota helper because those tests isolate only cooldown and circuit state, so a real account at or above 90% makes the offline suite fail.
  Recommendation: Update every existing `codex_spawn_gate` test seam to supply deterministic `LEADV2_QUOTA_LIVE` and cache paths, or make the new check explicitly injectable in those tests.
- [high] Malformed new ceiling override aborts GLM dispatch (plugins/leadv2/scripts/leadv2-glm-quota-gate.sh:44)
  A nonnumeric `LEADV2_CEIL_GLM_WORK` is accepted here and later used in arithmetic under `set -u`, which aborts the gate rather than honoring its stated fail-open behavior for configuration faults.
  Recommendation: Validate the resolved threshold as a bounded integer before assigning `THRESHOLD`, default or fail open on invalid input, and add this environment-override test.
- [high] Configurable timeout is not actually bounded (plugins/leadv2/scripts/leadv2-provider-quota-gate.sh:28-31)
  An arbitrarily large `LEADV2_QUOTA_READ_TIMEOUT` drives this sleep loop for the supplied duration and can stall every Codex spawn for days, contrary to the documented bounded-subprocess guarantee.
  Recommendation: Accept only a small positive integer range and fall back to a fixed maximum for invalid or excessive values.
- [high] Provider hard-stop semantics lack required evidence (plugins/leadv2/scripts/leadv2-provider-quota-gate.sh:61-62)
  The gate converts the external Codex `limit_reached` field into a dispatch refusal at 100% without an inline live probe and provider-document evidence or the required `UNVERIFIED` tag.
  Recommendation: Attach a versioned provider-document link plus recorded live probe output at this decision, or mark it `UNVERIFIED` and avoid using it as a blocking admission rule.
- [high] Burn classifier hard-stop semantics lack required evidence (plugins/leadv2/scripts/leadv2-burn-governor.sh:217)
  The new provider-mode classifier converts the external Codex `limit_reached` field into a hard verdict at 100% without an inline live probe and provider-document evidence or the required `UNVERIFIED` tag.
  Recommendation: Attach a versioned provider-document link plus recorded live probe output at this decision, or mark it `UNVERIFIED` and avoid using it as a hard classifier.
- [high] Review resolver hard-stop semantics lack required evidence (plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:335-338)
  The resolver converts the external Codex `limit_reached` field into a 100% routing decision without an inline live probe and provider-document evidence or the required `UNVERIFIED` tag.
  Recommendation: Attach a versioned provider-document link plus recorded live probe output at this decision, or mark it `UNVERIFIED` and avoid using it as a blocking routing rule.

Next steps:
- Fix global `limit_reached` precedence and add the mixed top-level/window fixture.
- Bound and validate timeout and ceiling configuration values.
- Make existing offline gate tests fully deterministic and add evidence for every `limit_reached`-based decision.
