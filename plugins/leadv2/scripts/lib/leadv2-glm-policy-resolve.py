#!/usr/bin/env python3
"""leadv2-glm-policy-resolve.py — the ONE glm_policy / codex_quota_gate resolver.

T-b (SUPERVISOR-AUDIT-01): formerly two independent copies of the GLM-FIRST-01
predicate chain existed — leadv2-dispatch-code.sh:resolve_arm() (regex-parsed
the yaml, no pyyaml dep) and leadv2-router.sh's per-invocation python helper
(used its own already-parsed cfg dict). Both callers now call resolve_glm_policy()
here; editing behaviour in this ONE file changes both build-phase dispatch and
router.sh phase/step routing identically.

CLI mode (leadv2-dispatch-code.sh: no pyyaml, parses routing.yaml itself):
    leadv2-glm-policy-resolve.py --routing-yaml PATH --job build|review \
        --signals '{"mission_kind": "...", ...}' [--base-arm glm] [--quota-live PATH]
    stdout: arm=...\\nrule=...\\nreason=...\\ntier=...\\n

Import mode (leadv2-router.sh: already has glm_policy as a parsed dict via
PyYAML, calls resolve_glm_policy() directly — see leadv2-router.sh's
importlib.util.spec_from_file_location loader):
    from leadv2_glm_policy_resolve import resolve_glm_policy
    result = resolve_glm_policy(glm_policy, signals, job, base_arm, quota_live_bin)

Fail-safe throughout: any routing.yaml / quota-read error resolves to the
cheapest default (glm, no gate) rather than raising — a broken resolver must
never block dispatch (mirrors resolve_arm()'s original `|| printf 'arm=glm...'`
contract and leadv2-glm-quota-gate.sh's fail-OPEN contract for the live-quota
read).
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# KIMI-CHANNEL-01: kimi sits between glm and codex in the build spill chain
# (glm -> kimi -> sonnet is the founder-approved default; codex stays in the
# chain for repos/configs that already rely on codex_quota_gate spill).
# Additive only -- sonnet_exceptions and the task-shape precedence rules below
# (resolve_glm_policy's `rules` list) stay glm/kimi-blind: a safety/payments/
# UI-judgment/glm-failed-twice/lock-busy signal routes straight to sonnet or
# opus and never touches this spill order.
DEFAULT_BUILD_SPILL = ["glm", "kimi", "codex", "sonnet"]
DEFAULT_REVIEW_EXCLUSIONS = ["glm"]
DEFAULT_BUILD_THRESHOLD_PCT = 80.0
DEFAULT_REVIEW_THRESHOLD_PCT = 95.0

# dispatch-00629379 (P0, 2026-07-30): the review gate had no available reviewer once
# Codex hit its weekly cap and GLM tripped the (build-only) 80% gate -- every build
# resolved to sonnet, so the reviewer (identical to the author list pre-fix) was also
# sonnet, and the gate correctly refused the self-review, forever. Two founder
# decisions this defaults set encodes: (1) opus becomes a valid reviewer arm, (2) glm
# reviews up to its OWN 90% band (deliberately above the 80% BUILD gate -- review-only
# headroom, same shape as Codex's existing 80-build/95-review reserve). Defaults carry
# the fix so a repo whose yaml never opts into these keys still gets it (R7).
#
# KIMI-CHANNEL-01b (2026-07-31): kimi joins the review pool BETWEEN glm and the paid
# Anthropic arms -- a cheap extra free voice (TokenRouter kimi-k3-free) after the two
# proven arms, before opus/sonnet (unproven quality, never the only reviewer if the
# proven arms have headroom). Same positioning rationale as DEFAULT_BUILD_SPILL above.
# kimi is PROBE-gated, not quota-gated: it has NO *_review_threshold_pct key, and its
# only admission signal is kimi-coder.sh probe reachability (see kimi_review_available).
DEFAULT_REVIEW_ARM_ORDER = ["codex", "glm", "kimi", "opus", "sonnet"]
DEFAULT_GLM_REVIEW_THRESHOLD_PCT = 90.0
DEFAULT_ANTHROPIC_REVIEW_THRESHOLD_PCT = 95.0


def _num_ge(val, n):
    try:
        return val is not None and float(val) >= n
    except (TypeError, ValueError):
        return False


def extract_glm_policy_block(routing_yaml_text: str) -> dict:
    """Regex-only glm_policy extractor (no pyyaml dep) for the CLI path.
    Mirrors the exact fields the import-mode caller (router.sh, which has
    PyYAML) reads for free from its own parsed cfg — both paths see the same
    policy shape regardless of which extractor produced it."""
    exc_ids, opus_kinds, codex_kinds = [], [], []
    codex_default_tier = "standard"
    # MAJOR fix (resolver:55-60): gate stays None unless `codex_quota_gate:`
    # is actually present in the yaml -- repos/configs that never opted into
    # T-q get exact old v1 behaviour (no thresholds/spill/review-exclusion
    # applied from hardcoded defaults).
    gate = None
    m = re.search(r'(?m)^  glm_policy:\s*\n((?:^[ \t]{4,}.*\n|^[ \t]*\n)+)', routing_yaml_text)
    if m:
        block = m.group(1)
        for idm in re.finditer(r'(?m)^[ \t]*-[ \t]*id:[ \t]*([A-Za-z0-9_-]+)', block):
            exc_ids.append(idm.group(1))
        okm = re.search(r'(?m)^[ \t]*opus_only_mission_kinds:[ \t]*\[([^\]]*)\]', block)
        if okm:
            opus_kinds = [s.strip() for s in okm.group(1).split(',') if s.strip()]
        cxkm = re.search(r'(?m)^[ \t]*codex_fitting_mission_kinds:[ \t]*\[([^\]]*)\]', block)
        if cxkm:
            codex_kinds = [s.strip() for s in cxkm.group(1).split(',') if s.strip()]
        cxtm = re.search(r'(?m)^[ \t]*codex_default_tier:[ \t]*([A-Za-z0-9_-]+)', block)
        if cxtm:
            codex_default_tier = cxtm.group(1)
        if re.search(r'(?m)^[ \t]*codex_quota_gate:', block):
            gate = {
                "build_threshold_pct": DEFAULT_BUILD_THRESHOLD_PCT,
                "review_threshold_pct": DEFAULT_REVIEW_THRESHOLD_PCT,
                "build_spill_order": list(DEFAULT_BUILD_SPILL),
                "review_arm_exclusions": list(DEFAULT_REVIEW_EXCLUSIONS),
            }
            btm = re.search(r'(?m)^[ \t]*build_threshold_pct:[ \t]*([0-9.]+)', block)
            if btm:
                gate["build_threshold_pct"] = float(btm.group(1))
            rtm = re.search(r'(?m)^[ \t]*review_threshold_pct:[ \t]*([0-9.]+)', block)
            if rtm:
                gate["review_threshold_pct"] = float(rtm.group(1))
            bso = re.search(r'(?m)^[ \t]*build_spill_order:[ \t]*\[([^\]]*)\]', block)
            if bso:
                gate["build_spill_order"] = [s.strip() for s in bso.group(1).split(',') if s.strip()]
            rex = re.search(r'(?m)^[ \t]*review_arm_exclusions:[ \t]*\[([^\]]*)\]', block)
            if rex:
                gate["review_arm_exclusions"] = [s.strip() for s in rex.group(1).split(',') if s.strip()]
            # dispatch-00629379: pool-mode-only keys, all optional -- absent means
            # resolve_review_pool() falls back to its own DEFAULT_* constants.
            # KIMI-CHANNEL-01b: review_arm_order is the per-repo opt-out for kimi --
            # an explicit list (e.g. [codex, glm, opus, sonnet]) OVERRIDES the default
            # and so omits kimi entirely; listing it (e.g. [codex, glm, kimi, opus,
            # sonnet]) opts in. kimi is probe-gated, so it has NO *_review_threshold_pct
            # key here -- glm_review_threshold_pct and anthropic_review_threshold_pct
            # are the only threshold keys the pool reads.
            rao = re.search(r'(?m)^[ \t]*review_arm_order:[ \t]*\[([^\]]*)\]', block)
            if rao:
                gate["review_arm_order"] = [s.strip() for s in rao.group(1).split(',') if s.strip()]
            grtm = re.search(r'(?m)^[ \t]*glm_review_threshold_pct:[ \t]*([0-9.]+)', block)
            if grtm:
                gate["glm_review_threshold_pct"] = float(grtm.group(1))
            artm = re.search(r'(?m)^[ \t]*anthropic_review_threshold_pct:[ \t]*([0-9.]+)', block)
            if artm:
                gate["anthropic_review_threshold_pct"] = float(artm.group(1))
    return {
        "sonnet_exceptions": [{"id": i} for i in exc_ids],
        "opus_only_mission_kinds": opus_kinds,
        "codex_fitting_mission_kinds": codex_kinds,
        "codex_default_tier": codex_default_tier,
        "codex_quota_gate": gate,
    }


def live_codex_weekly_pct(quota_live_bin):
    """Fail-open: any error -> None (gate never fires on an unknown reading).
    Same live-quota script leadv2-glm-quota-gate.sh uses for GLM
    (leadv2-quota-live.sh), read via the "codex" bucket. Codex's schema
    differs from GLM's (windows[]/binding_window, not five_hour/weekly) —
    binding_window picks the window whose used_percent is the live figure
    (observed: "primary", 7-day/604800s window == weekly)."""
    if not quota_live_bin or not os.path.exists(quota_live_bin):
        return None
    try:
        out = subprocess.run(["bash", quota_live_bin, "codex"], capture_output=True,
                              text=True, timeout=10)
        if out.returncode != 0:
            return None
        d = json.loads(out.stdout)
        if d.get("status") != "ok":
            return None
        windows = d.get("windows") or []
        binding = d.get("binding_window")
        for w in windows:
            if w.get("kind") == binding:
                return w.get("used_percent")
        return windows[0].get("used_percent") if windows else None
    except Exception:
        return None


def live_glm_pct(quota_live_bin):
    """Fail-open: any error -> None. max(five_hour.pct, weekly.pct) -- mirrors
    leadv2-glm-quota-gate.sh:112's OR-of-both-windows trip condition (either window
    over threshold blocks the arm); a weekly-only reading would miss a hot 5h window."""
    if not quota_live_bin or not os.path.exists(quota_live_bin):
        return None
    try:
        out = subprocess.run(["bash", quota_live_bin, "glm"], capture_output=True,
                              text=True, timeout=10)
        if out.returncode != 0:
            return None
        d = json.loads(out.stdout)
        if d.get("status") != "ok":
            return None
        five = (d.get("five_hour") or {}).get("pct")
        weekly = (d.get("weekly") or {}).get("pct")
        vals = [v for v in (five, weekly) if v is not None]
        return max(vals) if vals else None
    except Exception:
        return None


def live_anthropic_pct(quota_live_bin):
    """Fail-open: any error -> None. The ACTIVE account's max(five_hour_pct,
    seven_day_pct) -- mirrors leadv2-quota-read.py's own account_resolution;
    reviewing arms (opus/sonnet) share this one Anthropic-account reading."""
    if not quota_live_bin or not os.path.exists(quota_live_bin):
        return None
    try:
        out = subprocess.run(["bash", quota_live_bin, "anthropic"], capture_output=True,
                              text=True, timeout=10)
        if out.returncode != 0:
            return None
        d = json.loads(out.stdout)
        if d.get("status") != "ok":
            return None
        accounts = d.get("accounts") or []
        active = next((a for a in accounts if a.get("active")), None)
        if active is None:
            active_label = d.get("active_account")
            active = next((a for a in accounts if a.get("account_label") == active_label), None)
        if active is None and accounts:
            active = accounts[0]
        if active is None:
            return None
        five = active.get("five_hour_pct")
        weekly = active.get("seven_day_pct")
        vals = [v for v in (five, weekly) if v is not None]
        return max(vals) if vals else None
    except Exception:
        return None


def kimi_review_available(kimi_bin):
    """KIMI-CHANNEL-01b: probe-gate for kimi as a reviewer arm. kimi rides a FREE
    TokenRouter arm (kimi-k3-free) so it has NO quota concept -- its only admission
    signal is reachability of kimi-coder.sh's `probe` (GET /v1/models only, no lock,
    no run-id -- see kimi-coder.sh:1483 cmd_probe / kimi_launch_probe).

    Returns True | False | None (tri-state, same posture as live_*_pct):
      True  -- rc 0 (channel up);
      False -- rc 77 (channel down / unreachable, kimi-coder.sh emits the
               LEADV2_DISPATCH_REFUSED marker here);
      None  -- bin falsy/missing, OR rc 75 (secret/usage/lock error), OR any other
               rc, OR timeout/subprocess exception. None is fail-open-to-UNKNOWN:
               it blocks kimi UNLESS kimi is the terminal arm in `order` (it is not,
               in the default) -- identical to how an unmeasured bucket blocks a
               non-terminal arm. 15s timeout > kimi-coder.sh's own 10s curl cap so
               the probe's own deadline always fires before we kill it."""
    if not kimi_bin or not os.path.exists(kimi_bin):
        return None
    try:
        out = subprocess.run(["bash", kimi_bin, "probe"], capture_output=True,
                             timeout=15)
        if out.returncode == 0:
            return True
        if out.returncode == 77:
            return False
        return None
    except Exception:
        return None


def _fmt_pct(pct):
    try:
        f = float(pct)
        return "%d" % int(f) if f.is_integer() else str(f)
    except (TypeError, ValueError):
        return ""


def resolve_review_pool(glm_policy: dict, author: str, quota_live_bin: str = None,
                         pcts: dict = None, kimi_bin: str = None,
                         signals: dict = None) -> dict:
    """dispatch-00629379 §3.2: the ordered, quota-filtered, author-excluding reviewer
    pool -- the fix for "review gate has no available reviewer". Unlike
    resolve_glm_policy() (single arm, build+review), this always returns every
    candidate's disposition so the caller (leadv2-dispatch-product-close.sh) can pick
    the first eligible arm and still audit why every other arm was skipped.

    pcts: optional injection for pure/test use -- keys "codex"/"glm"/"anthropic"
    (opus and sonnet share the single "anthropic" account reading). When a key is
    absent, the live read is fetched via quota_live_bin (fail-open to None).

    kimi_bin / signals (KIMI-CHANNEL-01b): both optional and defaulted so every
    existing caller is byte-compatible. kimi is PROBE-gated (kimi_review_available),
    not quota-gated -- it has no entry in `pcts` and no threshold key. If a signals
    dict carries safety_touched or protected_path, kimi is dropped with
    kimi:excluded:safety (safety reviews never route to a free unproven arm). NB: the
    live close-gate caller (resolve_review_pool_call) currently passes --signals '{}',
    so this safety guard is latent in prod today -- it protects any caller that plumbs
    signals and is unit-tested; plumbing real signals is OUT OF SCOPE for KIMI-CHANNEL-01b.

    Unknown-quota rule (§3.3): an unknown read blocks an arm ONLY if a later arm
    exists in the pool -- the terminal arm in `order` is never blocked by an unknown
    read (an unmeasured bucket beats an outage). A KNOWN over-threshold reading blocks
    an arm regardless of position -- the terminal-arm exception is for unknown reads
    only, never for a confirmed-over-threshold one.
    """
    gate = glm_policy.get("codex_quota_gate") or {}
    order = gate.get("review_arm_order") or list(DEFAULT_REVIEW_ARM_ORDER)
    codex_threshold = gate.get("review_threshold_pct", DEFAULT_REVIEW_THRESHOLD_PCT)
    glm_threshold = gate.get("glm_review_threshold_pct", DEFAULT_GLM_REVIEW_THRESHOLD_PCT)
    anthropic_threshold = gate.get("anthropic_review_threshold_pct", DEFAULT_ANTHROPIC_REVIEW_THRESHOLD_PCT)
    pcts = dict(pcts) if pcts else {}

    def _pct_for(arm):
        if arm in pcts:
            return pcts[arm]
        if arm == "codex":
            return live_codex_weekly_pct(quota_live_bin)
        if arm == "glm":
            return live_glm_pct(quota_live_bin)
        if arm in ("opus", "sonnet"):
            if "anthropic" in pcts:
                return pcts["anthropic"]
            return live_anthropic_pct(quota_live_bin)
        return None

    def _threshold_for(arm):
        if arm == "codex":
            return codex_threshold
        if arm == "glm":
            return glm_threshold
        return anthropic_threshold

    entries = []
    reviewer = ""
    last_idx = len(order) - 1
    for i, arm in enumerate(order):
        if arm == author:
            entries.append("%s:author:" % arm)
            continue
        # KIMI-CHANNEL-01b: kimi is probe-gated, not quota-gated. It has NO threshold
        # key and MUST branch here BEFORE the pct/threshold logic -- _threshold_for()'s
        # fallback returns the Anthropic threshold for any non-codex/non-glm arm, which
        # would silently treat kimi as a 95%-Anthropic arm and block it; _pct_for() has
        # no kimi branch and would return None (unknown) on the live read path, but the
        # threshold trap is the one this ordering kills. Author-exclusion is handled by
        # the branch above. Safety (signals) excludes kimi outright (see §2.2).
        if arm == "kimi":
            if signals and (signals.get("safety_touched") or signals.get("protected_path")):
                entries.append("kimi:excluded:safety")
                continue
            avail = kimi_review_available(kimi_bin)
            if avail is True:
                entries.append("kimi:ok:")  # empty 3rd field -- kimi has no pct
                if not reviewer:
                    reviewer = arm
            elif avail is False:
                entries.append("kimi:blocked:probe")
            else:  # None -- bin missing / rc 75 / other rc / timeout
                entries.append("kimi:unknown:")
                if i == last_idx and not reviewer:
                    reviewer = arm
            continue
        pct = _pct_for(arm)
        if pct is None:
            entries.append("%s:unknown:" % arm)
            if i == last_idx and not reviewer:
                reviewer = arm
            continue
        if _num_ge(pct, _threshold_for(arm)):
            entries.append("%s:blocked:%s" % (arm, _fmt_pct(pct)))
        else:
            entries.append("%s:ok:%s" % (arm, _fmt_pct(pct)))
            if not reviewer:
                reviewer = arm

    refusal = "" if reviewer else "all_review_arms_unavailable"
    return {"reviewer": reviewer, "pool": entries, "refusal": refusal}


def resolve_glm_policy(glm_policy: dict, signals: dict, job: str,
                        base_arm: str = "glm", quota_live_bin: str = None,
                        quota_codex_pct=None, enable_codex_fitting_rule: bool = True,
                        kimi_bin: str = None) -> dict:
    """ONE authority for GLM-FIRST-01 predicates + T-q codex_quota_gate.

    base_arm: the arm the caller would pick with NO glm_policy applied at all.
      Both current callers always pass "glm" for build-phase resolution (glm
      is the routing.yaml default there) and whatever the step's own default
      resolves to for other phases (e.g. "codex" for review) — kept a
      parameter, not hardcoded, so a future non-glm-default step can still
      get quota-gate-only enforcement without touching this function.
    job: "build" | "review" (anything else falls back to "build" semantics —
      review_arm_exclusions and the review threshold only ever apply when the
      caller explicitly asks for job="review").
    enable_codex_fitting_rule: the two pre-T-b duplicates had ALREADY drifted —
      dispatch-code.sh:resolve_arm() carried the ROUTING-ENFORCEMENT-01
      codex_fitting_mission_kind rule, leadv2-router.sh's copy never got it
      (its own command_template builder has no dispatch branch for a bare
      "codex" build arm). Default True preserves dispatch-code.sh's existing
      reach; leadv2-router.sh passes False so unifying the resolver does not
      silently hand its build-phase command builder an arm it cannot dispatch
      — a separate command_template fix, out of T-b's scope.
    Returns: {arm, rule, reason, tier, codex_quota_blocked, job}
    """
    opus_kinds = glm_policy.get("opus_only_mission_kinds", []) or []
    exc_ids = [e.get("id") for e in (glm_policy.get("sonnet_exceptions", []) or [])
               if isinstance(e, dict) and e.get("id")]
    codex_kinds = glm_policy.get("codex_fitting_mission_kinds", []) or [] if enable_codex_fitting_rule else []
    codex_default_tier = glm_policy.get("codex_default_tier", "standard")
    # MAJOR fix (resolver:55-60): None (not {}) when the gate key/block is
    # absent -- distinguishes "opted out" from "opted in with defaults" so the
    # enforcement block below can skip entirely rather than applying hardcoded
    # thresholds/spill/review-exclusion to a repo/config that never asked for them.
    gate = glm_policy.get("codex_quota_gate")

    # Collateral fix (surfaced by router.sh:595-609 preserving this reason
    # verbatim): "glm_default" is only a truthful sentinel when base_arm=="glm"
    # (build's only base_arm). review's base_arm is "codex" -- reusing
    # "glm_default" there fed router.sh's bandit-allowed-arms special-case
    # (glm_default -> allowed=["glm"]) and forced GLM onto a review job, the
    # exact outcome GLM-FIRST-01/review_arm_exclusions exists to prevent.
    arm, rule, reason = base_arm, "none", ("glm_default" if base_arm == "glm" else "base_arm_default")
    if base_arm == "glm":
        # STRICT precedence, first match wins — identical order/semantics to
        # the two deleted duplicates (dispatch-code.sh:337-418,
        # router.sh:190-259 pre-T-b).
        rules = [
            (bool(signals.get("mission_kind")) and signals.get("mission_kind") in opus_kinds,
             None, "opus", "opus_mission_kind"),
            (bool(signals.get("protected_path") or signals.get("safety_touched")),
             "safety_gate_publish_payments", "sonnet", "sonnet_exception"),
            (_num_ge(signals.get("subsystem_count"), 4) or bool(signals.get("needs_midflight_interaction")),
             "integration_critical_4subsystems", "sonnet", "sonnet_exception"),
            (bool(signals.get("ui_design_judgment")),
             "ui_design_judgment", "sonnet", "sonnet_exception"),
            (_num_ge(signals.get("glm_failure_count"), 2),
             "glm_failed_twice", "sonnet", "sonnet_exception"),
            (bool(signals.get("glm_lock_busy")),
             "glm_lock_busy_no_second_channel", "sonnet", "sonnet_exception"),
            (bool(signals.get("mission_kind")) and signals.get("mission_kind") in codex_kinds,
             None, "codex", "codex_fitting_mission_kind"),
        ]
        for pred, rid, rbase, rsn in rules:
            if not pred:
                continue
            if rid is not None and rid not in exc_ids:
                continue  # rule id absent from yaml -> cannot fire (single source of truth)
            arm, rule, reason = rbase, (rid or ("codex_fitting_kind" if rbase == "codex" else "opus_only_kind")), rsn
            break

    # UI-TO-KIMI-01 (founder decision, no A/B): the ui_design_judgment exception
    # resolves to kimi when the kimi channel probe is reachable, sonnet otherwise.
    # This is the ONE exception row whose arm becomes dynamic; every other row is
    # byte-identical to before.
    #
    # LAZY: the probe is a 15s-timeout subprocess, so it runs ONLY after the UI
    # rule matched (rule == "ui_design_judgment") AND a kimi bin was supplied. A
    # caller that never passes kimi_bin gets EXACT today's behaviour -- arm
    # "sonnet", reason "sonnet_exception", no subprocess, no per-build tax.
    #   probe True  -> arm kimi,    reason sonnet_exception:kimi
    #   probe False -> arm sonnet,  reason sonnet_exception:kimi_probe_down
    #   probe None  -> arm sonnet,  reason sonnet_exception:kimi_probe_unknown
    # Both non-True states collapse to sonnet -- UNKNOWN must fail CLOSED here
    # (deliberately different from resolve_review_pool's fail-open-to-UNKNOWN):
    # stranding a UI task on an unreachable arm is a stall, not a downgrade.
    # rule stays "ui_design_judgment" in every branch -- it is the yaml
    # sonnet_exceptions id and the single-source-of-truth gate (rid not in
    # exc_ids -> cannot fire), and downstream consumers key on it (router.sh:595-
    # 609 passes reason through verbatim; the bandit special-case keys on
    # glm_default). Only arm + reason vary. Precedence is untouched:
    # safety_gate_publish_payments and integration_critical_4subsystems sit ABOVE
    # this row and break first, so a safety-touched UI task still resolves sonnet.
    if rule == "ui_design_judgment" and kimi_bin:
        _kimi_avail = kimi_review_available(kimi_bin)
        if _kimi_avail is True:
            arm = "kimi"
            reason = "sonnet_exception:kimi"
        elif _kimi_avail is False:
            arm = "sonnet"
            reason = "sonnet_exception:kimi_probe_down"
        else:  # None -- bin missing / rc 75 / other rc / timeout / exception
            arm = "sonnet"
            reason = "sonnet_exception:kimi_probe_unknown"

    tier = codex_default_tier if arm == "codex" else ""
    job = job if job in ("build", "review") else "build"
    codex_blocked = False

    # --- T-q enforcement (SUPERVISOR-AUDIT-01 T-b): codex_quota_gate + review_arm_exclusions ---
    # MAJOR fix (resolver:55-60): only enforce when the yaml explicitly
    # declares codex_quota_gate -- absent block => exact old v1 output
    # (arm/rule/reason/tier from the precedence rules above, untouched).
    if isinstance(gate, dict):
        exclusions = gate.get("review_arm_exclusions", DEFAULT_REVIEW_EXCLUSIONS) if job == "review" else []
        spill = gate.get("build_spill_order", DEFAULT_BUILD_SPILL)
        threshold = (gate.get("review_threshold_pct", DEFAULT_REVIEW_THRESHOLD_PCT) if job == "review"
                     else gate.get("build_threshold_pct", DEFAULT_BUILD_THRESHOLD_PCT))

        if quota_codex_pct is None and quota_live_bin:
            quota_codex_pct = live_codex_weekly_pct(quota_live_bin)
        # BLOCKING fix (resolver:192-200): quota unknown != known-0%. A read
        # failure (None) must NOT resolve as "below threshold" -- treat it as
        # blocked (codex ineligible) until a valid weekly reading exists.
        quota_known = quota_codex_pct is not None
        codex_blocked = (not quota_known) or _num_ge(quota_codex_pct, threshold)

        # founder rule: GLM is NEVER a review arm, regardless of quota.
        if job == "review" and arm in exclusions:
            arm = "sonnet" if codex_blocked else "codex"
            rule, reason = "review_arm_exclusions", "review_arm_exclusion"
            tier = codex_default_tier if arm == "codex" else ""

        # KIMI-CHANNEL-01 fix round 1 (C1): a positional after-slice
        # (spill[spill.index("codex")+1:]) is wrong once an arm sits BEFORE
        # codex in spill (e.g. kimi in [glm, kimi, codex, sonnet]) -- the
        # after-slice there is still just ["sonnet"], so kimi is unreachable.
        # Walk the FULL spill chain instead, skipping the blocked arm(s), the
        # currently-selected arm, and base_arm (base_arm was already
        # overridden by the precedence rules above -- resurrecting it here
        # would undo that decision). Assumes base_arm never appears AFTER the
        # blocked arm in spill (true for every shipped config today; glm is
        # always first).
        blocked = {"codex"} if codex_blocked else set()
        if arm in blocked:
            skip = {arm, base_arm} | blocked
            nxt = [a for a in spill if a not in skip and not (job == "review" and a in exclusions)]
            arm = nxt[0] if nxt else "sonnet"
            rule = "codex_quota_gate_%dpct" % int(threshold)
            reason = "codex_quota_gate"
            tier = ""

    return {"arm": arm, "rule": rule, "reason": reason, "tier": tier,
            "codex_quota_blocked": codex_blocked, "job": job}


def _emit_fallback(job: str, reason: str) -> None:
    """BLOCKING fix (resolver:227-231,:252-257): every review-mode error path
    must fall back Codex->Sonnet, NEVER glm (founder rule: GLM is never a
    review arm, no exception path -- not even a resolver crash). With no
    quota reading available, treat quota as unknown (blocked, per the tri-state
    fix above), which lands review on sonnet -- the safe end of the
    Codex->Sonnet chain. Non-review jobs keep the pre-existing cheap-default
    fallback (arm=glm)."""
    if job == "review":
        print("arm=sonnet"); print("rule=none"); print("reason=%s" % reason)
        print("tier="); print("codex_quota_blocked=1")
    else:
        print("arm=glm"); print("rule=none"); print("reason=%s" % reason)
        print("tier="); print("codex_quota_blocked=0")


def _job_from_argv(argv) -> str:
    """Best-effort --job sniff for fallback paths that run before (or instead
    of) argparse -- e.g. the top-level exception handler in __main__."""
    for i, tok in enumerate(argv):
        if tok == "--job" and i + 1 < len(argv):
            return argv[i + 1]
        if tok.startswith("--job="):
            return tok.split("=", 1)[1]
    return "build"


def _main(argv):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--routing-yaml", required=True)
    ap.add_argument("--job", default="build")
    ap.add_argument("--signals", default="{}")
    ap.add_argument("--base-arm", default="glm")
    ap.add_argument("--quota-live", default=None)
    ap.add_argument("--review-pool", action="store_true")
    ap.add_argument("--author", default="")
    ap.add_argument("--kimi-bin", default=None,
                    help="kimi-coder.sh path for the review-pool probe gate "
                         "(KIMI-CHANNEL-01b); falls back to LEADV2_DISPATCH_KIMI_BIN "
                         "then scripts/kimi-coder.sh, mirroring dispatch-code.sh:1243.")
    args = ap.parse_args(argv)

    try:
        text = Path(args.routing_yaml).read_text()
    except Exception:
        _emit_fallback(args.job, "no_routing_yaml")
        return 0

    glm_policy = extract_glm_policy_block(text)
    try:
        signals = json.loads(args.signals)
    except Exception:
        signals = {}

    quota_live_bin = args.quota_live
    if quota_live_bin is None:
        quota_live_bin = str(Path(__file__).resolve().parent.parent / "leadv2-quota-live.sh")

    # KIMI-CHANNEL-01b: --kimi-bin -> LEADV2_DISPATCH_KIMI_BIN (same env name
    # leadv2-dispatch-code.sh:1243 reads) -> scripts/kimi-coder.sh, so tests and prod
    # share one knob. Only consumed on the --review-pool path.
    kimi_bin = args.kimi_bin
    if kimi_bin is None:
        kimi_bin = os.environ.get("LEADV2_DISPATCH_KIMI_BIN")
    if kimi_bin is None:
        kimi_bin = str(Path(__file__).resolve().parent.parent / "kimi-coder.sh")

    result = resolve_glm_policy(glm_policy, signals, args.job, args.base_arm, quota_live_bin,
                                kimi_bin=kimi_bin)
    print("arm=%s" % result["arm"])
    print("rule=%s" % result["rule"])
    print("reason=%s" % result["reason"])
    print("tier=%s" % result["tier"])
    print("codex_quota_blocked=%s" % ("1" if result["codex_quota_blocked"] else "0"))

    # dispatch-00629379: additive-only -- absent --review-pool, output above is
    # byte-identical to pre-change (v1-equivalence, design §7 test f).
    if args.review_pool:
        pool_result = resolve_review_pool(glm_policy, args.author, quota_live_bin,
                                          kimi_bin=kimi_bin, signals=signals)
        print("reviewer=%s" % pool_result["reviewer"])
        print("pool=%s" % ",".join(pool_result["pool"]))
        print("refusal=%s" % pool_result["refusal"])
    return 0


if __name__ == "__main__":
    try:
        sys.exit(_main(sys.argv[1:]) or 0)
    except Exception as _e:
        sys.stderr.write("leadv2-glm-policy-resolve.py: resolver_error: %s\n" % _e)
        _emit_fallback(_job_from_argv(sys.argv[1:]), "resolver_error")
        sys.exit(0)
