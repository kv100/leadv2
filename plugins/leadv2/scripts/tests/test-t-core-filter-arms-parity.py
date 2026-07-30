#!/usr/bin/env python3
"""T-b tail parity (SUPERVISOR-AUDIT-01): leadv2-router-v2.py:filter_arms() no longer
reimplements the GLM-FIRST-01 predicate chain -- it now delegates opus_only_mission_kinds /
protected_path / glm_failed_twice to lib/leadv2-glm-policy-resolve.py:resolve_glm_policy(),
the ONE reader dispatch-code.sh and router.sh already share.

Five representative inputs, each asserting filter_arms()'s NEW (delegated) output is
byte-identical to the OLD (deleted) inline implementation's documented behavior for the
same signals -- reconstructed from the pre-refactor source (see build-t-core.md's parity
table for the side-by-side). quota_gate and channel_down stay local (never routed through
the resolver -- see filter_arms()'s own docstring), so they are covered too, including the
priority-ordering case (4: quota_gate must still win over failed_twice) that only a
byte-for-byte port could get wrong.
"""
import importlib.util
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE.parent

spec = importlib.util.spec_from_file_location("router_v2", SCRIPTS / "leadv2-router-v2.py")
router_v2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(router_v2)

ARMS = [
    {"id": "glm", "channel": "glm", "model": "glm", "bucket": "glm"},
    {"id": "codex", "channel": "codex", "model": "codex", "bucket": "codex"},
    {"id": "sonnet", "channel": "anthropic", "model": "sonnet", "bucket": "anthropic"},
    {"id": "opus", "channel": "anthropic", "model": "opus", "bucket": "anthropic"},
]

GLM_POLICY = {
    "sonnet_exceptions": [
        {"id": "safety_gate_publish_payments"},
        {"id": "glm_failed_twice"},
    ],
    "opus_only_mission_kinds": ["architecture", "safety_review"],
}


class FilterArmsParityTests(unittest.TestCase):
    """Uses the REAL resolver (no injection) -- proves the production wiring, not a stub."""

    def test_1_no_signals_all_eligible(self):
        result = router_v2.filter_arms(ARMS, GLM_POLICY, {})
        self.assertEqual(sorted(result["eligible"]), ["codex", "glm", "opus", "sonnet"])
        self.assertEqual(result["filtered"], [])

    def test_2_opus_only_mission_kind_bans_glm_and_codex(self):
        result = router_v2.filter_arms(ARMS, GLM_POLICY, {"mission_kind": "architecture"})
        self.assertEqual(sorted(result["eligible"]), ["opus", "sonnet"])
        reasons = {f["arm"]: f["reason"] for f in result["filtered"]}
        self.assertEqual(reasons, {"glm": "policy_ban", "codex": "policy_ban"})

    def test_3_protected_path_bans_non_sonnet_opus(self):
        result = router_v2.filter_arms(ARMS, GLM_POLICY, {"protected_path": True})
        self.assertEqual(sorted(result["eligible"]), ["opus", "sonnet"])
        reasons = {f["arm"]: f["reason"] for f in result["filtered"]}
        self.assertEqual(reasons, {"glm": "protected_path", "codex": "protected_path"})

    def test_4_quota_gate_wins_over_failed_twice_same_arm(self):
        # Priority must stay policy_ban > protected_path > quota_gate > failed_twice >
        # channel_down even though the resolver itself only ever returns ONE winning
        # rule per call -- this is the case a naive "just take the resolver's rule"
        # port would get wrong (it would report failed_twice, not quota_gate).
        result = router_v2.filter_arms(
            ARMS, GLM_POLICY,
            {"glm_quota_gate_tripped": True, "glm_failure_count": 2,
             "glm_failure_count_ledger_verified": True},
        )
        reasons = {f["arm"]: f["reason"] for f in result["filtered"]}
        self.assertEqual(reasons.get("glm"), "quota_gate")
        self.assertNotIn("codex", reasons)  # quota_gate/failed_twice only ever ban glm's bucket
        self.assertIn("sonnet", result["eligible"])

    def test_5_unverified_glm_failure_count_is_ignored(self):
        # F1-spoof-fix: an UNVERIFIED count >= 2 must not trip the rule.
        result = router_v2.filter_arms(
            ARMS, GLM_POLICY,
            {"glm_failure_count": 2, "glm_failure_count_ledger_verified": False},
        )
        self.assertIn("glm", result["eligible"])
        self.assertEqual(result["filtered"], [])


class FilterArmsInjectedResolverTests(unittest.TestCase):
    """Confirms the delegation seam itself (resolve_glm_policy_fn injection point) without
    depending on lib/'s on-disk layout -- a resolver that never fires must leave filter_arms
    behaving exactly as if no policy applied at all."""

    def test_resolver_returning_base_arm_bans_nothing(self):
        def _stub(_policy, _signals, _job, base_arm="glm", **_kw):
            return {"arm": base_arm, "rule": "none", "reason": "glm_default", "tier": "",
                    "codex_quota_blocked": False, "job": _job}

        result = router_v2.filter_arms(ARMS, GLM_POLICY, {"mission_kind": "architecture"},
                                        resolve_glm_policy_fn=_stub)
        self.assertEqual(result["filtered"], [])

    def test_resolver_missing_degrades_to_local_signals_only(self):
        # wave2 round2 finding 5: opus_only_mission_kinds used to need the resolver --
        # unavailable meant it silently did NOT fire. It is now a hard policy enforced
        # independently of resolver availability (fail CLOSED), so a missing resolver
        # must still ban glm/codex for an architecture-kind mission.
        result = router_v2.filter_arms(
            ARMS, GLM_POLICY, {"mission_kind": "architecture", "glm_quota_gate_tripped": True},
            resolve_glm_policy_fn=lambda *a, **k: None,
        )
        reasons = {f["arm"]: f["reason"] for f in result["filtered"]}
        self.assertEqual(reasons.get("glm"), "policy_ban")
        self.assertEqual(reasons.get("codex"), "policy_ban")
        self.assertEqual(sorted(result["eligible"]), ["opus", "sonnet"])

    def test_resolver_missing_protected_path_still_enforced(self):
        # Wave2 finding 8: protected_path must never depend on the resolver being
        # available at all -- it is read straight off `signals`.
        result = router_v2.filter_arms(
            ARMS, GLM_POLICY, {"protected_path": True},
            resolve_glm_policy_fn=lambda *a, **k: None,
        )
        reasons = {f["arm"]: f["reason"] for f in result["filtered"]}
        self.assertEqual(reasons.get("glm"), "protected_path")
        self.assertEqual(reasons.get("codex"), "protected_path")
        self.assertEqual(sorted(result["eligible"]), ["opus", "sonnet"])


REAL_PROD_ARMS = [
    {"id": "glm", "channel": "glm-coder.sh", "model": "glm-5.2", "bucket": "glm"},
    {"id": "codex", "channel": "codex-task.sh", "model": "gpt-5.6-terra", "bucket": "codex"},
    {"id": "claude-haiku", "channel": "claude-subsession.sh", "model": "haiku", "bucket": "anthropic:max_20x"},
    {"id": "claude-sonnet", "channel": "claude-subsession.sh", "model": "sonnet", "bucket": "anthropic:max_20x"},
    {"id": "claude-opus", "channel": "claude-subsession.sh", "model": "opus", "bucket": "anthropic:max_20x"},
]


class FilterArmsWave2Finding8Tests(unittest.TestCase):
    """Wave2 finding 8: protected_path used to be gated on the RESOLVER's single
    winning `rule` (an `elif` reachable only when the resolver picked
    safety_gate_publish_payments over any competing rule such as opus_only_kind).
    A mission that is BOTH architecture-flagged AND protected-path-touching lost
    the protected-path ban entirely -- glm, codex, and claude-haiku all stayed
    eligible with a protected path in play. These use the REAL production arm
    registry shape (router_v2.arms from leadv2-routing.yaml), not the abbreviated
    ARMS fixture above, and the REAL resolver (no injection)."""

    def test_real_prod_arms_protected_path_alone_bans_glm_codex_haiku(self):
        result = router_v2.filter_arms(REAL_PROD_ARMS, GLM_POLICY, {"protected_path": True})
        self.assertEqual(sorted(result["eligible"]), ["claude-opus", "claude-sonnet"])
        reasons = {f["arm"]: f["reason"] for f in result["filtered"]}
        self.assertEqual(reasons.get("claude-haiku"), "protected_path")
        self.assertEqual(reasons.get("glm"), "protected_path")
        self.assertEqual(reasons.get("codex"), "protected_path")

    def test_real_prod_arms_architecture_plus_protected_combined(self):
        # THE regression this finding names: mission_kind=architecture (which wins
        # opus_only_kind against the resolver's own internal priority) must never
        # shadow protected_path -- claude-haiku is not in POLICY_BAN_BUCKETS, so
        # only protected_path's own filter can ever exclude it.
        result = router_v2.filter_arms(
            REAL_PROD_ARMS, GLM_POLICY,
            {"mission_kind": "architecture", "protected_path": True},
        )
        reasons = {f["arm"]: f["reason"] for f in result["filtered"]}
        self.assertEqual(reasons.get("glm"), "policy_ban")
        self.assertEqual(reasons.get("codex"), "policy_ban")
        self.assertEqual(reasons.get("claude-haiku"), "protected_path")
        self.assertEqual(sorted(result["eligible"]), ["claude-opus", "claude-sonnet"])

    def test_real_prod_arms_missing_policy_protected_path_still_bans_haiku(self):
        # glm_policy=None/{} means "no ban configured" for opus_only/failed_twice --
        # but protected_path needs no policy input at all, so it must still fire and
        # ban every non-sonnet/opus arm (glm/codex/haiku alike), with reason
        # "protected_path" specifically (never "policy_ban" -- that needs a policy).
        result = router_v2.filter_arms(REAL_PROD_ARMS, None, {"protected_path": True})
        reasons = {f["arm"]: f["reason"] for f in result["filtered"]}
        self.assertEqual(reasons.get("claude-haiku"), "protected_path")
        self.assertEqual(reasons.get("glm"), "protected_path")
        self.assertEqual(reasons.get("codex"), "protected_path")
        self.assertEqual(sorted(result["eligible"]), ["claude-opus", "claude-sonnet"])

    def test_real_prod_arms_missing_resolver_protected_path_still_bans_haiku(self):
        # wave2 round2 finding 5: opus_only_kind is now a hard policy enforced
        # independently of resolver availability, so a missing resolver no longer
        # leaves glm/codex to protected_path alone -- they are banned by policy_ban
        # (the local fail-closed fallback), same as if the resolver had been present
        # and returned opus_only_kind itself. claude-haiku is never in
        # POLICY_BAN_BUCKETS, so only protected_path's own filter excludes it --
        # THAT is the part of this scenario that needs no resolver at all, still true.
        result = router_v2.filter_arms(
            REAL_PROD_ARMS, GLM_POLICY, {"mission_kind": "architecture", "protected_path": True},
            resolve_glm_policy_fn=lambda *a, **k: None,
        )
        reasons = {f["arm"]: f["reason"] for f in result["filtered"]}
        self.assertEqual(reasons.get("glm"), "policy_ban")
        self.assertEqual(reasons.get("codex"), "policy_ban")
        self.assertEqual(reasons.get("claude-haiku"), "protected_path")
        self.assertEqual(sorted(result["eligible"]), ["claude-opus", "claude-sonnet"])


class FilterArmsWave2Round2Finding5Tests(unittest.TestCase):
    """wave2 round2 finding 5: opus_only_kind / glm_failed_twice must fail CLOSED --
    fire independently of resolver availability -- rather than silently disabling
    both bans whenever the resolver is missing, its import raises, or its call
    raises. Each case here would PASS against the pre-round2-fix filter_arms (the
    predicates simply never fired), so these measure the actual regression, not
    just exercise the code path."""

    def test_resolver_import_failure_still_bans_opus_only_kind(self):
        # Simulates _load_resolve_glm_policy() failing to import the module at all
        # (a bad on-disk path, a syntax error in lib/) -- the injected callable
        # itself raises, which filter_arms must catch and treat as "unavailable",
        # not "no rule applies".
        def _raising_resolver(*_a, **_k):
            raise ImportError("simulated: state.mjs/lib import failed")

        result = router_v2.filter_arms(
            REAL_PROD_ARMS, GLM_POLICY, {"mission_kind": "architecture"},
            resolve_glm_policy_fn=_raising_resolver,
        )
        reasons = {f["arm"]: f["reason"] for f in result["filtered"]}
        self.assertEqual(reasons.get("glm"), "policy_ban")
        self.assertEqual(reasons.get("codex"), "policy_ban")
        self.assertEqual(sorted(result["eligible"]), ["claude-haiku", "claude-opus", "claude-sonnet"])

    def test_empty_policy_file_bans_nothing_even_with_resolver_down(self):
        # An empty/absent glm_policy (no opus_only_mission_kinds configured at all)
        # must still ban NOTHING via the fail-closed fallback -- "missing resolver"
        # must never be conflated with "ban every arm regardless of config". Both
        # None and {} are exercised (the documented "absent policy" contract).
        for empty_policy in (None, {}):
            result = router_v2.filter_arms(
                REAL_PROD_ARMS, empty_policy, {"mission_kind": "architecture"},
                resolve_glm_policy_fn=lambda *a, **k: None,
            )
            self.assertEqual(result["filtered"], [], repr(empty_policy))
            self.assertEqual(
                sorted(result["eligible"]),
                ["claude-haiku", "claude-opus", "claude-sonnet", "codex", "glm"],
                repr(empty_policy),
            )

    def test_failed_twice_ban_fires_with_resolver_down(self):
        # glm_failed_twice needs BOTH a verified count >= 2 AND the id present in
        # sonnet_exceptions (GLM_POLICY has it) -- must still fire when the
        # resolver never got a chance to evaluate it.
        result = router_v2.filter_arms(
            REAL_PROD_ARMS, GLM_POLICY,
            {"glm_failure_count": 2, "glm_failure_count_ledger_verified": True},
            resolve_glm_policy_fn=lambda *a, **k: None,
        )
        reasons = {f["arm"]: f["reason"] for f in result["filtered"]}
        self.assertEqual(reasons.get("glm"), "failed_twice")
        self.assertNotIn("codex", reasons)  # failed_twice only ever bans glm's bucket
        self.assertIn("codex", result["eligible"])

    def test_failed_twice_ban_respects_sonnet_exceptions_gate_even_with_resolver_down(self):
        # If the repo's own routing.yaml never opted "glm_failed_twice" into
        # sonnet_exceptions, the fallback must NOT invent the ban -- config, not
        # resolver availability, is still the single source of truth for whether
        # this rule is active at all.
        policy_without_exception = {
            "sonnet_exceptions": [{"id": "safety_gate_publish_payments"}],
            "opus_only_mission_kinds": ["architecture"],
        }
        result = router_v2.filter_arms(
            REAL_PROD_ARMS, policy_without_exception,
            {"glm_failure_count": 5, "glm_failure_count_ledger_verified": True},
            resolve_glm_policy_fn=lambda *a, **k: None,
        )
        self.assertEqual(result["filtered"], [])


if __name__ == "__main__":
    unittest.main()
