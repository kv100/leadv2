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
# UI-TO-KIMI-01 tests monkey-patch resolver.kimi_review_available (the name the
# resolver looks up in its own module at call time) -- never a live network call.


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


class UiToKimiOverrideTests(unittest.TestCase):
    """UI-TO-KIMI-01: ui_design_judgment exception routes to kimi when the probe
    is reachable, sonnet otherwise. Only this ONE exception row is dynamic; every
    other row is byte-identical. The probe is monkey-patched -- NEVER a live
    network call in a unit test."""

    def _ui_policy(self):
        # sonnet_exceptions carries ui_design_judgment (the gate: rid must be in
        # exc_ids to fire). No codex_quota_gate -- the override is upstream of the
        # gate block and kimi is never in `blocked`, so the gate is irrelevant.
        return {"sonnet_exceptions": [{"id": "ui_design_judgment"},
                                      {"id": "safety_gate_publish_payments"}]}

    def _patch_probe(self, retval):
        # Patch on the module the resolver reads its own name from.
        original = resolver.kimi_review_available
        resolver.kimi_review_available = lambda _bin: retval
        self.addCleanup(setattr, resolver, "kimi_review_available", original)

    def test_ui_kimi_available_routes_to_kimi(self):
        self._patch_probe(True)
        result = resolve_glm_policy(self._ui_policy(), {"ui_design_judgment": True},
                                    job="build", base_arm="glm",
                                    kimi_bin="/fake/kimi-coder.sh")
        self.assertEqual(result["arm"], "kimi")
        self.assertEqual(result["rule"], "ui_design_judgment")
        self.assertEqual(result["reason"], "sonnet_exception:kimi")

    def test_ui_kimi_unavailable_routes_to_sonnet_false(self):
        self._patch_probe(False)
        result = resolve_glm_policy(self._ui_policy(), {"ui_design_judgment": True},
                                    job="build", base_arm="glm",
                                    kimi_bin="/fake/kimi-coder.sh")
        self.assertEqual(result["arm"], "sonnet")
        self.assertEqual(result["rule"], "ui_design_judgment")
        self.assertEqual(result["reason"], "sonnet_exception:kimi_probe_down")

    def test_ui_kimi_unknown_routes_to_sonnet_none(self):
        # None (bin present but rc 75 / timeout / exception) fails CLOSED to
        # sonnet -- different from resolve_review_pool's fail-open-to-UNKNOWN.
        self._patch_probe(None)
        result = resolve_glm_policy(self._ui_policy(), {"ui_design_judgment": True},
                                    job="build", base_arm="glm",
                                    kimi_bin="/fake/kimi-coder.sh")
        self.assertEqual(result["arm"], "sonnet")
        self.assertEqual(result["reason"], "sonnet_exception:kimi_probe_unknown")

    def test_safety_overrides_ui_even_with_kimi_available(self):
        # safety_gate_publish_payments sits ABOVE ui_design_judgment in the
        # precedence list and breaks first; a safety-touched UI task is sonnet,
        # rule safety_gate_publish_payments, and the kimi probe is never reached.
        self._patch_probe(True)
        result = resolve_glm_policy(self._ui_policy(),
                                    {"protected_path": True, "ui_design_judgment": True},
                                    job="build", base_arm="glm",
                                    kimi_bin="/fake/kimi-coder.sh")
        self.assertEqual(result["arm"], "sonnet")
        self.assertEqual(result["rule"], "safety_gate_publish_payments")

    def test_no_probe_when_not_ui(self):
        # LAZINESS: a non-UI build must NEVER pay the probe subprocess. A raising
        # stub fails the test if the resolver calls it.
        def _boom(_bin):
            raise AssertionError("kimi probe must not run on a non-UI task")
        original = resolver.kimi_review_available
        resolver.kimi_review_available = _boom
        self.addCleanup(setattr, resolver, "kimi_review_available", original)
        result = resolve_glm_policy(self._ui_policy(), {"mission_kind": "doc_fix"},
                                    job="build", base_arm="glm",
                                    kimi_bin="/fake/kimi-coder.sh")
        self.assertEqual(result["arm"], "glm")  # no exception matched -> base arm

    def test_no_kimi_bin_is_byte_identical_to_today(self):
        # A caller that never passes kimi_bin gets exact pre-UI-TO-KIMI-01
        # behaviour: arm sonnet, reason sonnet_exception, no probe.
        def _boom(_bin):
            raise AssertionError("probe must not run when kimi_bin is absent")
        original = resolver.kimi_review_available
        resolver.kimi_review_available = _boom
        self.addCleanup(setattr, resolver, "kimi_review_available", original)
        result = resolve_glm_policy(self._ui_policy(), {"ui_design_judgment": True},
                                    job="build", base_arm="glm")
        self.assertEqual(result["arm"], "sonnet")
        self.assertEqual(result["rule"], "ui_design_judgment")
        self.assertEqual(result["reason"], "sonnet_exception")


if __name__ == "__main__":
    unittest.main(verbosity=2)
