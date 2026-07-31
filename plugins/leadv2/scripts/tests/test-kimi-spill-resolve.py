#!/usr/bin/env python3
"""Regression tests for KIMI-CHANNEL-01 fix round 1, finding C1.

lib/leadv2-glm-policy-resolve.py:resolve_glm_policy()'s codex_quota_gate spill
walk used to be a positional after-slice (spill[spill.index("codex")+1:]),
which is wrong once an arm sits BEFORE codex in the chain (kimi in
[glm, kimi, codex, sonnet] -- the after-slice there is still just ["sonnet"],
so kimi was unreachable). The fix walks the full spill chain with a skip set.

Covers: kimi reachable in the new 4-arm chain, byte-identical behavior on the
old 3-arm (pre-kimi) chain, safety_touched overriding the gate entirely, the
quota-unknown-is-blocked tri-state, and the gate-absent no-op path.
"""
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE.parent
RESOLVER_PATH = SCRIPTS / "lib" / "leadv2-glm-policy-resolve.py"

spec = importlib.util.spec_from_file_location("leadv2_glm_policy_resolve", RESOLVER_PATH)
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)

resolve_glm_policy = resolver.resolve_glm_policy


def _glm_policy(build_spill_order, review_arm_exclusions=None):
    return {
        "sonnet_exceptions": [{"id": "safety_gate_publish_payments", "when": "protected_path"}],
        "codex_quota_gate": {
            "build_spill_order": build_spill_order,
            "build_threshold_pct": 80.0,
            "review_threshold_pct": 95.0,
            "review_arm_exclusions": review_arm_exclusions or ["glm"],
        }
    }


import unittest


class KimiSpillWalkTests(unittest.TestCase):
    def test_kimi_reachable_in_new_default_chain(self):
        glm_policy = _glm_policy(["glm", "kimi", "codex", "sonnet"])
        signals = {"mission_kind": "doc_fix"}
        glm_policy["codex_fitting_mission_kinds"] = ["doc_fix"]
        result = resolve_glm_policy(glm_policy, signals, job="build", base_arm="glm",
                                     quota_codex_pct=95.0)
        self.assertEqual(result["arm"], "kimi")
        self.assertEqual(result["rule"], "codex_quota_gate_80pct")
        self.assertIs(result["codex_quota_blocked"], True)

    def test_pre_kimi_chain_still_yields_sonnet(self):
        glm_policy = _glm_policy(["glm", "codex", "sonnet"])
        signals = {"mission_kind": "doc_fix"}
        glm_policy["codex_fitting_mission_kinds"] = ["doc_fix"]
        result = resolve_glm_policy(glm_policy, signals, job="build", base_arm="glm",
                                     quota_codex_pct=95.0)
        self.assertEqual(result["arm"], "sonnet")
        self.assertEqual(result["rule"], "codex_quota_gate_80pct")

    def test_safety_touched_overrides_gate_regardless_of_kimi(self):
        glm_policy = _glm_policy(["glm", "kimi", "codex", "sonnet"])
        signals = {"safety_touched": True, "mission_kind": "doc_fix"}
        glm_policy["codex_fitting_mission_kinds"] = ["doc_fix"]
        result = resolve_glm_policy(glm_policy, signals, job="build", base_arm="glm",
                                     quota_codex_pct=95.0)
        self.assertEqual(result["arm"], "sonnet")
        self.assertEqual(result["rule"], "safety_gate_publish_payments")

    def test_quota_unknown_is_blocked_and_falls_to_kimi(self):
        glm_policy = _glm_policy(["glm", "kimi", "codex", "sonnet"])
        signals = {"mission_kind": "doc_fix"}
        glm_policy["codex_fitting_mission_kinds"] = ["doc_fix"]
        result = resolve_glm_policy(glm_policy, signals, job="build", base_arm="glm",
                                     quota_codex_pct=None, quota_live_bin=None)
        self.assertIs(result["codex_quota_blocked"], True)
        self.assertEqual(result["arm"], "kimi")

    def test_gate_absent_v1_output_shape_unchanged(self):
        glm_policy = {}
        signals = {"mission_kind": "doc_fix"}
        result = resolve_glm_policy(glm_policy, signals, job="build", base_arm="glm",
                                     quota_codex_pct=95.0)
        self.assertEqual(result["arm"], "glm")
        self.assertEqual(result["rule"], "none")
        self.assertIs(result["codex_quota_blocked"], False)


if __name__ == "__main__":
    unittest.main(verbosity=2)
