#!/usr/bin/env python3
"""
leadv2-router-v2.py -- deterministic, quota-driven arm selection (T6).

ROUTER-QUOTA-DRIVEN-01: replaces the hand-maintained ~/.claude/leadv2-excluded-arms
stopgap. An arm whose live quota truth (leadv2-quota-read.py T1 usable_now, see
that file's normalize_window/binding_window) shows zero usable headroom is
skipped AUTOMATICALLY; it returns to rotation on its own the moment usable_now
recovers past 0, because usable_now is recomputed live from reset_iso vs now on
every call -- nothing to edit, nothing to remember, nothing to expire.

Policy (mission-specified, not the full smart-routing-v2.md L3 scorer -- no
task judge, no learned competence table; those are separate tasks):
    usable_now <= 0     -> EXCLUDED  reason=quota_exhausted
    usable_now is None  -> ELIGIBLE  reason=unknown_headroom_failopen  (an
                            unknown read is never treated as exhausted NOR as
                            healthy -- it is rankable, just not preferred over
                            a known-healthy arm; see resolve()'s ordering)
    usable_now > 0       -> ELIGIBLE  reason=headroom_available

Winner selection is deterministic: known-healthy arms (usable_now > 0) are
tried first in the caller's chain order, THEN unknown-headroom arms in chain
order, so an unknown read never displaces a provably-healthy arm but also
never gets treated as exhausted (fail-open, matching leadv2-glm-quota-gate.sh
sec3 and quota-read.py's "unknown is never 0%" invariant). Every arm's full
vector (usable_now, eligible, reason) is always returned so the caller can
journal a fully audit-able decision.

Usage:
    leadv2-router-v2.py resolve  --chain glm,codex,sonnet [--quota-json FILE]
    leadv2-router-v2.py dry-run  --chain glm,codex,sonnet [--quota-json FILE]
    leadv2-router-v2.py filter   --arms-json FILE --glm-policy-json FILE
                                  [--mission-kind K] [--protected-path]
                                  [--glm-quota-gate-tripped]
                                  [--glm-failure-count N] [--channel-down a,b]

`resolve` prints pipe-friendly key=value lines (matching the rest of the
dispatch tooling's journal style) and exits 0 with a winner, 3 with no
eligible arm. `dry-run` prints the full decision vector as indented JSON,
always exits 0 -- for humans / --dry-run smoke tests, never gates a real
dispatch.

`filter` (T4, SMART-ROUTING-V2 L1 hard filters) is a DIFFERENT, EARLIER
layer than `resolve`'s quota-headroom ordering above: it decides which arms
are eligible AT ALL, from policy + registry facts alone -- never from
usable_now/headroom. See filter_arms() below for the invariant this exists
to guarantee (an excluded arm is never resurrected by a headroom number).
Prints the same eligible=/filtered= key=value lines `resolve` uses so
callers can pipe filter's `eligible` list straight into resolve's `--chain`.
Always exits 0 (a filter producing zero eligible arms is a valid, reportable
outcome for the caller to act on -- not this layer's failure).
"""
import argparse
import importlib.util
import json
import os
import subprocess
import sys

# T-b tail (SUPERVISOR-AUDIT-01): filter_arms() used to reimplement its OWN copy of
# the opus_only_mission_kinds / protected_path / glm_failed_twice predicates against
# the SAME phases.glm_policy dict lib/leadv2-glm-policy-resolve.py already reads --
# a THIRD independent copy alongside the two dispatch-code.sh/router.sh already
# unified (see that file's own T-b doc header). Lazily loaded (not imported at
# module scope) so a repo with no lib/ copy still gets resolve()/dry-run working;
# filter_arms() itself degrades to "policy fires nothing" on load failure, same
# fail-open contract the resolver documents for its own callers.
_RESOLVE_GLM_POLICY_FN = None
_RESOLVE_GLM_POLICY_LOAD_ATTEMPTED = False


def _load_resolve_glm_policy():
    global _RESOLVE_GLM_POLICY_FN, _RESOLVE_GLM_POLICY_LOAD_ATTEMPTED
    if _RESOLVE_GLM_POLICY_LOAD_ATTEMPTED:
        return _RESOLVE_GLM_POLICY_FN
    _RESOLVE_GLM_POLICY_LOAD_ATTEMPTED = True
    path = os.environ.get("LEADV2_GLM_POLICY_RESOLVER")
    if not path or not os.path.isfile(path):
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             "lib", "leadv2-glm-policy-resolve.py")
    if not os.path.isfile(path):
        return None
    try:
        spec = importlib.util.spec_from_file_location("leadv2_glm_policy_resolve", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        _RESOLVE_GLM_POLICY_FN = mod.resolve_glm_policy
    except Exception:
        _RESOLVE_GLM_POLICY_FN = None
    return _RESOLVE_GLM_POLICY_FN

# Arm id -> quota bucket key in leadv2-quota-live.sh json output. The Anthropic
# arms (sonnet/opus/haiku, however the caller spells them) share ONE quota
# bucket -- the account leadv2-quota-read.py resolved as active (T2) -- because
# that is what the account actually meters, not the model chosen within it.
BUCKET_FOR_ARM = {
    "glm": "glm",
    "codex": "codex",
    "sonnet": "anthropic",
    "opus": "anthropic",
    "haiku": "anthropic",
    "claude-sonnet": "anthropic",
    "claude-opus": "anthropic",
    "claude-haiku": "anthropic",
}

EXHAUSTED_AT_OR_BELOW = 0.0


def headroom_weight(usable_now, weights):
    """Return the configured monotone weight for usable_now.

    ``usable_now is None`` is *unknown*, not zero and not abundant.  Unknown
    headroom does not trip the reserve rule (there is no evidence it is below
    reserve), remains fail-open/rankable, and receives only the explicit
    ``min_usable_now: null`` weight.  Thus it cannot masquerade as healthy.
    """
    if usable_now is None:
        for row in weights:
            if row.get("min_usable_now") is None:
                return float(row["weight"])
        return 0.2
    known = sorted((r for r in weights if r.get("min_usable_now") is not None),
                   key=lambda r: float(r["min_usable_now"]), reverse=True)
    for row in known:
        if float(usable_now) >= float(row["min_usable_now"]):
            return float(row["weight"])
    return float(known[-1]["weight"]) if known else 1.0


def select_arms(arms, l1_result, quota, estimate, samples, headroom_weights):
    """L3 selector: L1 survivors -> reserve -> samples*headroom -> argmax.

    This deliberately accepts L1's *already filtered* set, rather than all
    arms plus filter inputs.  Consequently an L1-rejected arm has no code path
    to scoring or selection, irrespective of quota, sample, or score.
    """
    arm_by_id = {arm["id"]: arm for arm in arms}
    survivors = [arm_by_id[aid] for aid in l1_result["eligible"] if aid in arm_by_id]
    # Preserve L1 reasons first; they are never overwritten downstream.
    filtered = list(l1_result.get("filtered", []))
    vector = []
    for arm in survivors:
        aid = arm["id"]
        bucket = arm.get("bucket", aid).split(":", 1)[0]
        usable = bucket_usable_now(quota.get(bucket) or {})
        threshold = float(arm.get("reserve_threshold", 0))
        allowed = (estimate.get("duration_class") == "short" and
                   estimate.get("work_kind") in set(arm.get("reserve_allow") or ["review"]))
        # Unknown is not comparable to the threshold: fail open, but its
        # configured unknown weight below makes it rank last absent competence.
        if usable is not None and usable < threshold and not allowed:
            filtered.append({"arm": aid, "reason": "reserve"})
            continue
        sample = float(samples.get(aid, 0.75))
        weight = headroom_weight(usable, headroom_weights)
        vector.append({"arm": aid, "bucket": bucket, "usable_now": usable,
                       "reserve_threshold": threshold, "sample": sample,
                       "headroom_weight": weight, "score": sample * weight})
    winner_row = max(vector, key=lambda row: (row["score"], -l1_result["eligible"].index(row["arm"])),
                     default=None)
    # `eligible` is an L1 compatibility surface: callers that use it retain
    # their chain order.  `ordered` is the explicit, scored consumption
    # surface.  Compute both from this one vector/quota read.
    ordered_rows = sorted(
        vector,
        key=lambda row: (-row["score"], l1_result["eligible"].index(row["arm"])),
    )
    return {
        "eligible": [row["arm"] for row in vector], "filtered": filtered,
        "ordered": [row["arm"] for row in ordered_rows],
        "vector": vector, "headroom": {row["arm"]: row["usable_now"] for row in vector},
        "samples": {row["arm"]: row["sample"] for row in vector},
        "winner": ordered_rows[0]["arm"] if ordered_rows else None,
        "winner_reason": "max_sample_x_headroom" if winner_row else "all_arms_filtered",
        # COMPLEXITY-ESTIMATOR-IS-OFF-01 (Critical #2): carry complexity as its
        # own segment instead of collapsing duration_class+complexity into one
        # short/long binary -- a trivial one-liner and a multi-subsystem
        # refactor must not share the same task_class whenever both happen to
        # read duration_class=="long".
        "task_class": "%s:%s:%s" % (estimate.get("work_kind", "unknown"),
                                     estimate.get("duration_class", "unknown"),
                                     estimate.get("complexity", "unknown")),
        "estimate_id": estimate.get("estimate_id", "unknown"),
    }

# Mirrors leadv2-glm-quota-gate.sh sec1 exactly (same env var, same >=threshold-
# on-EITHER-window semantics) so GLM's existing 80% reroute policy is reused,
# not reimplemented as a second, possibly-drifting gate ("never open a second
# channel to bypass a gate" -- this IS the sanctioned gate, applied a step
# earlier, before a spawn attempt is even made).
GLM_GATE_ENV = "GLM_QUOTA_THRESHOLD"
GLM_GATE_DEFAULT = 80.0


def _glm_gate_exceeded(bucket_payload):
    if not isinstance(bucket_payload, dict) or bucket_payload.get("status") != "ok":
        return False
    try:
        threshold = float(os.environ.get(GLM_GATE_ENV, GLM_GATE_DEFAULT))
    except (TypeError, ValueError):
        threshold = GLM_GATE_DEFAULT
    for window_name in ("five_hour", "weekly"):
        pct = (bucket_payload.get(window_name) or {}).get("pct")
        try:
            if pct is not None and float(pct) >= threshold:
                return True
        except (TypeError, ValueError):
            continue
    return False


def _window_usable_now(window):
    if not isinstance(window, dict):
        return None
    return window.get("usable_now")


def bucket_usable_now(bucket_payload):
    """Return usable_now for one provider payload's binding window, or None.

    None covers both "provider unreachable" (status != ok) and "provider
    answered but no binding window could be resolved" -- both are unknown,
    never fabricated as 0.
    """
    if not isinstance(bucket_payload, dict):
        return None
    if bucket_payload.get("status") != "ok":
        return None
    provider = bucket_payload.get("provider")
    binding = bucket_payload.get("binding_window")
    if provider == "glm":
        return _window_usable_now(bucket_payload.get(binding) if binding else None)
    if provider == "codex":
        windows = bucket_payload.get("windows") or []
        window = next((w for w in windows if w.get("kind") == binding), None)
        return _window_usable_now(window)
    if provider == "anthropic":
        accounts = bucket_payload.get("accounts") or []
        active = next((a for a in accounts if a.get("active")), None)
        if not active or active.get("status") != "ok":
            return None
        acct_binding = active.get("binding_window")
        return _window_usable_now(active.get(acct_binding) if acct_binding else None)
    return None


def classify_arm(arm, quota):
    bucket = BUCKET_FOR_ARM.get(arm)
    if bucket is None:
        return {"arm": arm, "bucket": None, "usable_now": None,
                "eligible": False, "reason": "unmapped_arm"}
    payload = quota.get(bucket) or {}
    if arm == "glm" and _glm_gate_exceeded(payload):
        return {"arm": arm, "bucket": bucket, "usable_now": bucket_usable_now(payload),
                "eligible": False, "reason": "quota_gate"}
    usable_now = bucket_usable_now(payload)
    if usable_now is None:
        return {"arm": arm, "bucket": bucket, "usable_now": None,
                "eligible": True, "reason": "unknown_headroom_failopen"}
    if usable_now <= EXHAUSTED_AT_OR_BELOW:
        return {"arm": arm, "bucket": bucket, "usable_now": usable_now,
                "eligible": False, "reason": "quota_exhausted"}
    return {"arm": arm, "bucket": bucket, "usable_now": usable_now,
            "eligible": True, "reason": "headroom_available"}


def resolve(chain, quota):
    """Pure function: chain (ordered arm ids) + quota json -> decision dict.

    No I/O, no clock read -- fully deterministic given its two inputs, which
    is what makes "byte-deterministic on a seeded/fixture run" true without
    needing to seed anything.
    """
    vector = [classify_arm(arm, quota) for arm in chain]
    eligible = [v for v in vector if v["eligible"]]
    filtered = [v for v in vector if not v["eligible"]]
    # Known-healthy first in *live headroom* order, then unknown-headroom in
    # chain order.  The static chain is only a deterministic tie-breaker: it
    # must not decide between two observable buckets.  `score` is deliberately
    # the same usable_now value that chooses the arm, so the dispatch journal
    # can show the exact numbers behind a quota-gate reroute.
    known = [v for v in eligible if v["usable_now"] is not None]
    unknown = [v for v in eligible if v["usable_now"] is None]
    for row in vector:
        row["score"] = row["usable_now"]
    known.sort(key=lambda row: (-float(row["usable_now"]), chain.index(row["arm"])))
    ordered_eligible = known + unknown
    winner = ordered_eligible[0] if ordered_eligible else None
    return {
        "chain": chain,
        "vector": vector,
        "eligible": [v["arm"] for v in eligible],
        "ordered": [v["arm"] for v in ordered_eligible],
        "filtered": [{"arm": v["arm"], "reason": v["reason"]} for v in filtered],
        "winner": winner["arm"] if winner else None,
        "winner_reason": winner["reason"] if winner else "all_arms_exhausted",
        "headroom": {v["arm"]: v["usable_now"] for v in vector},
        # Credits are deliberately journaled, not turned into a second
        # eligibility meter: the routing policy's sole numeric truth remains
        # the binding-window usable_now value above.
        "credits": {v["arm"]: (quota.get(v["bucket"]) or {}).get("credits")
                    for v in vector if (quota.get(v["bucket"]) or {}).get("credits") is not None},
    }


# ---------------------------------------------------------------------------
# T4 -- L1 hard filters (SMART-ROUTING-V2 docs/specs/smart-routing-v2.md sec3).
#
# Deliberately narrower inputs than resolve()'s: filter_arms() never receives
# usable_now/headroom, so a filtered arm CANNOT be traded back in by a good
# score -- the invariant is structural (the function has no parameter to leak
# it through), not just a behavioural promise a test happens to check.
#
# Reason-code priority mirrors the spec table order; a filtered arm gets the
# FIRST rule that excludes it (setdefault), matching "reason codes matter as
# much as the verdict" -- one code per arm, the one that actually decided it.
# ---------------------------------------------------------------------------

# GLM-FIRST-01's own build arm plus the codex-fitting arm are the only two
# ROUTER-QUOTA-DRIVEN-01/T3-registry buckets a mission_kind policy ban can
# reach; sonnet/opus/haiku all sit on the anthropic bucket and are the
# opus_only_mission_kinds' intended DESTINATION, never its target.
POLICY_BAN_BUCKETS = ("glm", "codex")


def filter_arms(arms, glm_policy, signals, resolve_glm_policy_fn=None):
    """Pure function: registry + policy + per-dispatch signals -> {eligible, filtered}.

    arms: list of {id, channel, model, bucket, reserve_threshold, reserve_allow}
          (T3 router_v2.arms shape; extra keys ignored).
    glm_policy: the routing.yaml phases.glm_policy dict (opus_only_mission_kinds
          etc.), or None/{} if absent -- an absent policy bans nothing (the
          block staying the SOLE source of policy bans means "missing" is
          "no ban configured", not "ban everything").
    signals: {
        mission_kind: str | None,
        protected_path: bool,
        glm_quota_gate_tripped: bool,   # caller already ran leadv2-glm-quota-gate.sh
        glm_failure_count: int,          # F1-spoof-fix note below
        channel_down: [arm_id, ...],
    }
    resolve_glm_policy_fn: injectable for tests (defaults to the lazily-loaded
          module from lib/leadv2-glm-policy-resolve.py); None-injection is only
          honoured when explicitly passed, so production callers always get the
          real resolver via _load_resolve_glm_policy()'s own lazy singleton.

    T-b tail (SUPERVISOR-AUDIT-01): the opus_only_mission_kinds / glm_failed_twice
    predicates are resolved by the ONE reader, lib/leadv2-glm-policy-resolve.py:
    resolve_glm_policy() -- this function no longer reimplements that predicate
    chain as its PRIMARY path, only translates its single-arm verdict into this
    layer's multi-arm eligible/filtered shape. wave2 round2 finding 5: because
    both are HARD policies, an independent local recomputation of the SAME two
    predicates also runs whenever the resolver call did not produce a decision
    at all (module unavailable, import raised, call raised) -- see
    `resolver_unavailable` below -- so a missing/failing resolver fails CLOSED
    instead of silently admitting architecture-class or twice-failed-GLM work.
    protected_path, quota_gate, and channel_down stay
    local and are NEVER routed through the resolver's single winning `rule`:
    protected_path (wave2 finding 8 fix) is an independent hard filter read
    directly off `signals`, enforced unconditionally so it can never be
    shadowed by opus_only_kind winning the SAME resolver call for a mission
    that is simultaneously architecture-flagged and protected-path-touching --
    a case the old `elif rule == "safety_gate_publish_payments"` translation
    got wrong (protected_path silently never fired). quota_gate is a
    caller-precomputed signal (the caller already ran the sanctioned
    leadv2-glm-quota-gate.sh), and channel_down is a router_v2-only concept the
    resolver has no notion of -- none of the three is part of glm_policy, so
    none belongs behind the resolver. Reason-priority is preserved byte-for-byte:
    policy_ban > protected_path > quota_gate > failed_twice > channel_down
    (first match wins per arm, via setdefault, exactly as before this refactor).

    No LLM, no I/O, no clock -- same determinism contract as resolve(). The
    resolver call itself is pure (a routing.yaml block + a signals dict in, a
    verdict dict out -- no file/subprocess I/O of its own for this call shape).
    """
    glm_policy = glm_policy or {}
    reasons = {}  # arm_id -> reason (first match wins, spec table order)

    # wave2 round2 finding 5: glm_failure_count / ledger-verification gating and the
    # sonnet_exceptions membership check are needed by BOTH the resolver call below
    # AND the resolver-independent fallback further down, so compute them once here.
    glm_failure_count = signals.get("glm_failure_count") or 0
    ledger_verified = bool(signals.get("glm_failure_count_ledger_verified"))
    # F1-spoof-fix (leadv2-dispatch-code.sh "FIX PASS 2"): an unverified count must
    # never trip the rule -- same posture as dispatch-code.sh's own capped/ignored-
    # and-journalled handling.
    verified_glm_failure_count = glm_failure_count if ledger_verified else 0
    mission_kind = signals.get("mission_kind")
    opus_kinds = glm_policy.get("opus_only_mission_kinds", []) or []
    exc_ids = [e.get("id") for e in (glm_policy.get("sonnet_exceptions", []) or [])
               if isinstance(e, dict) and e.get("id")]

    resolve_fn = resolve_glm_policy_fn if resolve_glm_policy_fn is not None else _load_resolve_glm_policy()
    rule = None
    decision = None
    if resolve_fn is not None:
        resolve_signals = {
            "mission_kind": mission_kind,
            "protected_path": bool(signals.get("protected_path")),
            "glm_failure_count": verified_glm_failure_count,
        }
        try:
            decision = resolve_fn(glm_policy, resolve_signals, "build", base_arm="glm",
                                   enable_codex_fitting_rule=False)
        except Exception:
            decision = None
        rule = (decision or {}).get("rule")

    # wave2 round2 finding 5: opus_only_kind and glm_failed_twice are HARD routing
    # policies (architecture-class work must never reach GLM/codex/claude-haiku; a
    # GLM arm that has already failed this task twice must never be handed a third
    # try) -- they must fire even when the resolver module is missing (not loaded),
    # its own import raises, or the call itself raises. All three collapse `decision`
    # (not just `rule`) to None above -- that is the ONLY signal this treats as
    # "resolver unavailable"; an explicit, successfully-returned decision (even one
    # that names some OTHER rule, or "none") is always trusted as-is and never
    # second-guessed, so an injected test resolver's own verdict still governs
    # whenever it actually ran. resolver_unavailable therefore gates this fallback
    # to the genuine failure case only. Evaluated independently here, mirroring
    # lib/leadv2-glm-policy-resolve.py's own opus_mission_kind / glm_failed_twice
    # predicates (including glm_failed_twice's sonnet_exceptions gate, so a repo
    # that never opted that exception in still gets exactly the configured
    # behavior) rather than trusting resolve_fn's single winning `rule` string,
    # which used to be the ONLY way either ban could fire -- an unavailable
    # resolver used to silently disable both, exactly like protected_path used to
    # be shadowed before the wave2 fix.
    resolver_unavailable = decision is None
    is_opus_only_kind = resolver_unavailable and bool(mission_kind) and mission_kind in opus_kinds
    is_failed_twice = (
        resolver_unavailable
        and "glm_failed_twice" in exc_ids
        and verified_glm_failure_count is not None
        and float(verified_glm_failure_count) >= 2
    )

    if rule == "opus_only_kind" or is_opus_only_kind:
        for arm in arms:
            if arm.get("bucket") in POLICY_BAN_BUCKETS:
                reasons.setdefault(arm["id"], "policy_ban")
    # quota_gate (below) must win over failed_twice when both are true --
    # apply failed_twice's ban AFTER quota_gate so setdefault preserves the
    # original priority order even though the resolver picks ONE rule.
    _pending_failed_twice = (rule == "glm_failed_twice") or is_failed_twice

    # T-b tail wave2 finding 8 fix: protected_path used to be gated on the RESOLVER's
    # single winning `rule` (an `elif` keyed on rule == "safety_gate_publish_payments"),
    # so a mission that was BOTH architecture-flagged AND touched a protected path lost
    # the protected-path ban entirely whenever the resolver's own priority picked
    # opus_only_kind instead -- glm/codex/claude-haiku all stayed eligible with a
    # protected path in play. protected_path is now read directly off `signals`,
    # independent of and never shadowed by whichever single rule the resolver
    # returned (and enforced even when the resolver itself is unavailable or the
    # policy dict is empty, since it needs no resolver input at all). setdefault
    # still preserves the documented priority: policy_ban above already claimed any
    # overlapping arm, so protected_path only fills in the ones the resolver's
    # opus_only_kind ban didn't reach (e.g. claude-haiku, which is never in
    # POLICY_BAN_BUCKETS).
    if signals.get("protected_path"):
        for arm in arms:
            if arm.get("model") not in ("sonnet", "opus"):
                reasons.setdefault(arm["id"], "protected_path")

    if signals.get("glm_quota_gate_tripped"):
        for arm in arms:
            if arm.get("bucket") == "glm":
                reasons.setdefault(arm["id"], "quota_gate")

    if _pending_failed_twice:
        for arm in arms:
            if arm.get("bucket") == "glm":
                reasons.setdefault(arm["id"], "failed_twice")

    channel_down = set(signals.get("channel_down") or [])
    for arm in arms:
        if arm["id"] in channel_down:
            reasons.setdefault(arm["id"], "channel_down")

    eligible = [arm["id"] for arm in arms if arm["id"] not in reasons]
    filtered = [{"arm": aid, "reason": reasons[aid]}
                for aid in [a["id"] for a in arms] if aid in reasons]
    return {"eligible": eligible, "filtered": filtered}


def load_quota(quota_json_path, quota_live_path):
    if quota_json_path:
        with open(quota_json_path) as fh:
            return json.load(fh)
    live = quota_live_path or os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                           "leadv2-quota-live.sh")
    out = subprocess.check_output(["bash", live, "json"], text=True)
    return json.loads(out)


def _run_filter(args):
    with open(args.arms_json) as fh:
        arms = json.load(fh)
    glm_policy = {}
    if args.glm_policy_json:
        with open(args.glm_policy_json) as fh:
            glm_policy = json.load(fh) or {}
    channel_down = [a.strip() for a in (args.channel_down or "").split(",") if a.strip()]
    signals = {
        "mission_kind": args.mission_kind,
        "protected_path": bool(args.protected_path),
        "glm_quota_gate_tripped": bool(args.glm_quota_gate_tripped),
        "glm_failure_count": args.glm_failure_count or 0,
        "glm_failure_count_ledger_verified": bool(args.glm_failure_count_ledger_verified),
        "channel_down": channel_down,
    }
    result = filter_arms(arms, glm_policy, signals)
    print("eligible=%s" % ",".join(result["eligible"]))
    print("filtered=%s" % json.dumps(result["filtered"], sort_keys=True))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=["resolve", "dry-run", "filter"])
    parser.add_argument("--chain",
                        help="resolve/dry-run: comma-separated ordered arm ids, e.g. glm,codex,sonnet")
    parser.add_argument("--quota-json", help="fixture file (tests); default reads live quota")
    parser.add_argument("--quota-live", help="override path to leadv2-quota-live.sh")
    parser.add_argument("--arms-json", help="filter/resolve: path to router_v2.arms as JSON array")
    parser.add_argument("--glm-policy-json", help="filter: path to phases.glm_policy as JSON object")
    parser.add_argument("--l1-json", help="resolve: JSON L1 filter result (eligible/filtered)")
    parser.add_argument("--estimate-json", help="resolve: arm-blind TaskEstimate JSON")
    parser.add_argument("--samples-json", help="resolve: arm-id -> pre-sampled competence JSON")
    parser.add_argument("--headroom-weights-json", help="resolve: router_v2.headroom_weights JSON")
    parser.add_argument("--mission-kind", help="filter: mission_kind signal")
    parser.add_argument("--protected-path", action="store_true",
                        help="filter: safety-gate/publish/payments touched")
    parser.add_argument("--glm-quota-gate-tripped", action="store_true",
                        help="filter: caller already ran leadv2-glm-quota-gate.sh and it exited non-zero")
    parser.add_argument("--glm-failure-count", type=int, default=0,
                        help="filter: only acted on with --glm-failure-count-ledger-verified (F1-spoof-fix)")
    parser.add_argument("--glm-failure-count-ledger-verified", action="store_true",
                        help="filter: caller confirms --glm-failure-count is ledger-backed, not caller-guessed")
    parser.add_argument("--channel-down", help="filter: comma-separated arm ids that are hard-unavailable")
    args = parser.parse_args(argv)

    if args.mode == "filter":
        if not args.arms_json:
            sys.stderr.write("leadv2-router-v2.py filter: --arms-json is required\n")
            return 2
        return _run_filter(args)

    # The complete T6/T7 L3 path.  Its inputs are materialized JSON so it is
    # pure and replayable from the journal; the shell wrapper obtains them from
    # T4/T5/L4 in production.  Supplying --l1-json structurally prevents any
    # L1-filtered arm from being revived by later layers.
    if args.mode == "resolve" and args.l1_json:
        required = (args.arms_json, args.estimate_json, args.samples_json,
                    args.headroom_weights_json)
        if not all(required):
            sys.stderr.write("leadv2-router-v2.py resolve: L3 requires --arms-json --estimate-json --samples-json --headroom-weights-json\n")
            return 2
        with open(args.arms_json) as fh:
            arms = json.load(fh)
        with open(args.l1_json) as fh:
            l1 = json.load(fh)
        with open(args.estimate_json) as fh:
            estimate = json.load(fh)
        with open(args.samples_json) as fh:
            samples = json.load(fh)
        with open(args.headroom_weights_json) as fh:
            weights = json.load(fh)
        quota = load_quota(args.quota_json, args.quota_live)
        result = select_arms(arms, l1, quota, estimate, samples, weights)
        print("winner=%s" % (result["winner"] or ""))
        print("reason=%s" % result["winner_reason"])
        print("eligible=%s" % ",".join(result["eligible"]))
        print("ordered=%s" % ",".join(result["ordered"]))
        print("filtered=%s" % json.dumps(result["filtered"], sort_keys=True))
        print("headroom=%s" % json.dumps(result["headroom"], sort_keys=True))
        print("credits=%s" % json.dumps(result.get("credits", {}), sort_keys=True))
        print("vector=%s" % json.dumps(result["vector"], sort_keys=True))
        print("samples=%s" % json.dumps(result["samples"], sort_keys=True))
        print("task_class=%s" % result["task_class"])
        print("estimate_id=%s" % result["estimate_id"])
        return 0 if result["winner"] else 3

    if not args.chain:
        sys.stderr.write("leadv2-router-v2.py: --chain is required for resolve/dry-run\n")
        return 2
    chain = [a.strip() for a in args.chain.split(",") if a.strip()]
    if not chain:
        sys.stderr.write("leadv2-router-v2.py: --chain must name at least one arm\n")
        return 2
    quota = load_quota(args.quota_json, args.quota_live)
    result = resolve(chain, quota)

    if args.mode == "dry-run":
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0

    print("winner=%s" % (result["winner"] or ""))
    print("reason=%s" % result["winner_reason"])
    print("eligible=%s" % ",".join(result["eligible"]))
    print("ordered=%s" % ",".join(result["ordered"]))
    print("filtered=%s" % json.dumps(result["filtered"], sort_keys=True))
    print("headroom=%s" % json.dumps(result["headroom"], sort_keys=True))
    print("credits=%s" % json.dumps(result.get("credits", {}), sort_keys=True))
    print("vector=%s" % json.dumps(result["vector"], sort_keys=True))
    return 0 if result["winner"] else 3


if __name__ == "__main__":
    sys.exit(main())
