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
import time
from pathlib import Path

# DISPATCH-KIMI-ARM-MISMATCH-01 (2026-08-05, founder order 2026-08-04 «Кими
# убрать»): kimi removed from the build spill chain. Kimi remains a valid
# review arm (see kimi_review_available below) — only build dispatch retired.
# The launcher-side vocabulary mirror is _candidate_chain_for_arm in
# leadv2-dispatch-code.sh; both lists must agree.
DEFAULT_BUILD_SPILL = ["glm", "codex", "sonnet"]

# Launcher vocabulary: the set of arms the dispatcher can actually run as
# primary build arms. Applied to the spill walk so a stale tenant yaml that
# still lists a retired arm (e.g. kimi) cannot resurrect it. Must match the
# case-rows in _candidate_chain_for_arm (leadv2-dispatch-code.sh).
DISPATCHABLE_BUILD_ARMS = {"glm", "codex", "sonnet"}

# PLANNER-MODELS-DECISION-01: glm and kimi are build-only and are never admitted
# to a planning role. Role decides the SET; the ladder still decides the ORDER.
DISPATCHABLE_PLAN_ARMS = {"codex", "sonnet", "opus", "fable"}
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
# B1 R1: this list is the source of truth for the review-arm allowlist enforced by
# leadv2-phase-record.sh's _verify_artifact review check (LEADV2_REVIEW_ARMS env var).
# If you add/remove an arm here, update the default there too.
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


# ── dispatch-8e2a32be round 2: review pool must never be empty ──────────────────────
# D1: routing-yaml self-heal (mirrors resolve_review_pool_call()'s bash-side ordered
# candidate search -- tenant override, plugin-local canonical, canonical-root fallback).
_REVIEW_POOL_NEVER_EMPTY_CANDIDATES_DOC = (
    "order: --routing-yaml arg (tenant/test override) -> plugin-local "
    "(this file's own ../../config/leadv2-routing.yaml) -> "
    "$LEADV2_CANONICAL_ROOT (or ~/Projects/leadv2)/plugins/leadv2/config/leadv2-routing.yaml"
)


def _resolve_routing_yaml_path(explicit: str):
    """D1: first-existing-file-wins search. Returns (path_or_None, source) where
    source is one of tenant|plugin|canonical|none. Deliberately does NOT know about
    ${ROOT}/.claude/ref/leadv2-routing.yaml -- that tenant-override tier is resolved
    bash-side (resolve_review_pool_call) BEFORE --routing-yaml is even passed here;
    this is the safety net for callers that hand this script a stale/missing path."""
    candidates = []
    if explicit:
        candidates.append(("tenant", explicit))
    here = Path(__file__).resolve()
    plugin_local = here.parent.parent.parent / "config" / "leadv2-routing.yaml"
    candidates.append(("plugin", str(plugin_local)))
    canonical_root = os.environ.get("LEADV2_CANONICAL_ROOT") or str(Path.home() / "Projects" / "leadv2")
    canonical = os.path.join(canonical_root, "plugins", "leadv2", "config", "leadv2-routing.yaml")
    candidates.append(("canonical", canonical))
    for source, path in candidates:
        if path and os.path.isfile(path):
            return path, source
    return None, "none"


def extract_dispatch_ladder(routing_yaml_text: str) -> list:
    """router.dispatch_ladder entries (id/provider/review_rank/dispatch), for the
    review-pool floor (D3) and the on-disk lockout provider mapping (D4). Uses
    PyYAML -- already a hard dependency elsewhere in this codebase (see
    leadv2-dispatch-code.sh:_load_dispatch_ladder's own `import sys, yaml`), so this
    is not a new dependency surface. Fail-safe: any parse error -> empty list; every
    caller degrades gracefully (provider==arm, no rank table) rather than raising."""
    try:
        import yaml
        d = yaml.safe_load(routing_yaml_text) or {}
    except Exception:
        return []
    ladder = ((d.get("router") or {}).get("dispatch_ladder")) or []
    out = []
    for e in ladder:
        if not isinstance(e, dict):
            continue
        eid = e.get("id")
        if not eid:
            continue
        out.append({
            "id": eid,
            "provider": e.get("provider", eid),
            "review_rank": e.get("review_rank"),
            "dispatch": e.get("dispatch", True),
        })
    return out


def _now_epoch() -> int:
    """LEADV2_QUOTA_NOW_EPOCH override for deterministic tests (D4)."""
    raw = os.environ.get("LEADV2_QUOTA_NOW_EPOCH")
    if raw:
        try:
            return int(raw)
        except (TypeError, ValueError):
            pass
    return int(time.time())


def _lockout_blocked(provider: str, now_epoch: int, lockout_dir: str = None) -> bool:
    """D4: fail-open read of the on-disk quota-lockout store leadv2-dispatch-code.sh's
    record-quota-lockout / _record_quota_lockout writes (schema: provider/locked_until/
    locked_until_epoch/source -- see leadv2-dispatch-code.sh:_record_quota_lockout).
    Missing/malformed/expired file => NOT blocked. A corrupt cache file must never
    remove an arm from consideration -- same fail-open posture as every other quota
    read in this file (live_codex_weekly_pct etc.)."""
    if not provider:
        return False
    d = lockout_dir or os.environ.get("LEADV2_QUOTA_LOCKOUT_DIR") or os.path.join(
        os.environ.get("LEADV2_DISPATCH_CACHE_DIR") or os.path.join(os.path.expanduser("~"), ".claude", "cache"),
        "dispatch-ledger")
    path = os.path.join(d, "quota-lockout-%s.json" % provider)
    try:
        with open(path) as f:
            data = json.load(f)
        until_epoch = int(data.get("locked_until_epoch"))
    except Exception:
        return False
    return now_epoch < until_epoch


def _review_floor(author: str, rank_table: dict, dispatchable=None):
    """D3: TOTAL, non-hardcoded floor over the review_rank table. Returns
    (arm_or_None, ok) -- ok is False iff the original rank table has fewer than 2
    entries, which the caller must treat as pool_floor_table_degenerate (a hard
    resolver error, not a silent empty pool) rather than a normal "floor not needed"
    outcome. If an optional dispatchable filter leaves no eligible entry, there
    simply is no eligible floor: return (None, True) so the caller degrades to the
    documented all_review_arms_unavailable fallback instead of misclassifying a
    valid ladder as degenerate. A sole dispatchable entry remains a legitimate
    floor arm.

    floor(author) = the entry with rank > rank(author) that has the smallest such
    rank (escalate one step up), or -- if none exists (author at/above the top, or
    author absent from the table, i.e. rank(author) treated as -infinity) -- the
    entry with the largest rank. Total for any author string, including "" or an
    arm the table has never heard of.

    dispatchable: optional set of allowed arm names. When provided, arms NOT in
    this set are excluded from the rank table BEFORE floor selection. Used by
    the plan phase to ensure DISPATCHABLE_PLAN_ARMS filtering applies to the
    floor too (PLAN-FOLLOWUPS-01 caveat 4 — haiku must never enter the pool)."""
    rank_table = rank_table or {}
    if len(rank_table) < 2:
        return None, False
    if dispatchable is not None:
        rank_table = {k: v for k, v in rank_table.items() if k in dispatchable}
    author_rank = rank_table.get(author, float("-inf"))
    candidates = [(rid, r) for rid, r in rank_table.items() if rid != author]
    if not candidates:
        return None, True
    higher = [c for c in candidates if c[1] > author_rank]
    chosen = min(higher, key=lambda c: c[1]) if higher else max(candidates, key=lambda c: c[1])
    return chosen[0], True
# ── end dispatch-8e2a32be round 2 helpers ────────────────────────────────────────────


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
                         signals: dict = None, rank_table: dict = None,
                         ladder_providers: dict = None, lockout_dir: str = None,
                         now_epoch: int = None, job: str = "review") -> dict:
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
    # PLANNER-MODELS-DECISION-01: plan job filters the pool against DISPATCHABLE_PLAN_ARMS
    # (excludes glm/kimi). Review and build keep the existing unfiltered order.
    if job == "plan":
        order = [a for a in order if a in DISPATCHABLE_PLAN_ARMS]
    codex_threshold = gate.get("review_threshold_pct", DEFAULT_REVIEW_THRESHOLD_PCT)
    glm_threshold = gate.get("glm_review_threshold_pct", DEFAULT_GLM_REVIEW_THRESHOLD_PCT)
    anthropic_threshold = gate.get("anthropic_review_threshold_pct", DEFAULT_ANTHROPIC_REVIEW_THRESHOLD_PCT)
    pcts = dict(pcts) if pcts else {}
    ladder_providers = ladder_providers or {}
    now_epoch = now_epoch if now_epoch is not None else _now_epoch()

    def _provider_for(arm):
        return ladder_providers.get(arm, arm)

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
        # D4 (dispatch-8e2a32be): a live on-disk quota lockout for this arm's provider
        # bars it outright, BEFORE the kimi probe-gate and the pct/threshold gate below
        # -- a locked-out provider is never even quota-checked. Runs for every arm
        # uniformly (kimi included) via the ladder-derived provider mapping, never a
        # literal arm-name comparison.
        if _lockout_blocked(_provider_for(arm), now_epoch, lockout_dir):
            entries.append("%s:blocked:lockout" % arm)
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

    # D3 (dispatch-8e2a32be): the preferred pool above is genuinely exhausted (every
    # candidate author-excluded/locked-out/blocked/never assigned) -- fall to the
    # rank-table floor so the pool is NEVER empty just because codex+glm are both
    # quota-locked and the author happens to be excluded from reviewing itself. The
    # floor bypasses lockout/pct gating entirely (unconditional guarantee) and is
    # flagged via the pool entry's :floor:<pct|degraded> suffix -- "reason:
    # floor_reviewer" in the design doc's vocabulary, expressed here as the entry
    # disposition since --review-pool's CLI contract has no separate reason= line.
    if not reviewer:
        # PLAN-FOLLOWUPS-01 caveat 4: when job=plan, filter the floor by
        # DISPATCHABLE_PLAN_ARMS so haiku (or any non-plan arm) never enters
        # the planning pool via the floor path.
        _floor_dispatchable = DISPATCHABLE_PLAN_ARMS if job == "plan" else None
        floor_arm, floor_ok = _review_floor(author, rank_table, dispatchable=_floor_dispatchable)
        if floor_ok and floor_arm:
            floor_pct = _pct_for(floor_arm)
            suffix = _fmt_pct(floor_pct) if floor_pct is not None and _fmt_pct(floor_pct) else "degraded"
            entries.append("%s:floor:%s" % (floor_arm, suffix))
            reviewer = floor_arm
            refusal = ""
        elif rank_table and not floor_ok:
            # The original rank table has < 2 entries -- a config bug, not an
            # ordinary post-filter-empty result from an otherwise valid ladder.
            refusal = "pool_floor_table_degenerate"

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
        _dispatchable = DISPATCHABLE_PLAN_ARMS if job == "plan" else DISPATCHABLE_BUILD_ARMS
        if arm in blocked:
            skip = {arm, base_arm} | blocked
            nxt = [a for a in spill if a not in skip
                   and a in _dispatchable
                   and not (job == "review" and a in exclusions)]
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


def _emit_pool_lines(reviewer: str, entries, refusal: str) -> None:
    """D2 (dispatch-8e2a32be): the ONE place that prints reviewer=/pool=/refusal= --
    every --review-pool return path in _main (including every degraded/error path)
    calls this exactly once, so none of them can silently skip the pool output the
    way the pre-fix `no_routing_yaml` / `resolver_error` / top-level except paths did."""
    print("reviewer=%s" % (reviewer or ""))
    print("pool=%s" % ",".join(entries or []))
    print("refusal=%s" % (refusal or ""))


def _arg_from_argv(argv, flag: str) -> str:
    """Best-effort single-value argv sniff, same idiom as _job_from_argv, used by the
    degraded/error --review-pool paths that must re-derive a floor WITHOUT trusting
    any state from a _main() run that may have crashed partway through."""
    for i, tok in enumerate(argv):
        if tok == flag and i + 1 < len(argv):
            return argv[i + 1]
        if tok.startswith(flag + "="):
            return tok.split("=", 1)[1]
    return ""


def _best_effort_floor_pool(argv):
    """D2: independent, exception-safe re-derivation of just the review floor, used
    by every degraded/error --review-pool path so a resolver crash anywhere in the
    main body still leaves the review gate with a non-empty pool where possible.
    Deliberately does NOT reuse any state from the failed run -- re-resolves the
    routing yaml from scratch via the same D1 candidate search. Returns
    (reviewer, pool_entries, refusal).

    PLAN-FOLLOWUPS-01 caveat 4: when --plan-pool is present, filters the floor by
    DISPATCHABLE_PLAN_ARMS (haiku must never enter the planning pool)."""
    try:
        routing_yaml_arg = _arg_from_argv(argv, "--routing-yaml")
        author = _arg_from_argv(argv, "--author")
        path, _source = _resolve_routing_yaml_path(routing_yaml_arg)
        if not path:
            return "", [], "no_routing_yaml"
        text = Path(path).read_text()
        ladder = extract_dispatch_ladder(text)
        rank_table = {e["id"]: e["review_rank"] for e in ladder if e.get("review_rank") is not None}
        # PLAN-FOLLOWUPS-01 caveat 4: filter floor by DISPATCHABLE_PLAN_ARMS for plan job.
        _dispatchable = DISPATCHABLE_PLAN_ARMS if "--plan-pool" in argv else None
        arm, ok = _review_floor(author, rank_table, dispatchable=_dispatchable)
        if not arm:
            # A valid ladder can legitimately have no plan-dispatchable floor after
            # filtering (for example, only haiku ranks remain). That is an ordinary
            # unavailable-pool fallback, not a malformed rank-table hard error.
            return "", [], "pool_floor_table_degenerate" if rank_table and not ok else "all_review_arms_unavailable"
        return arm, ["%s:floor:degraded" % arm], ""
    except Exception:
        return "", [], "resolver_error"


def _main(argv):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--routing-yaml", required=True)
    ap.add_argument("--job", default="build")
    ap.add_argument("--signals", default="{}")
    ap.add_argument("--base-arm", default="glm")
    ap.add_argument("--quota-live", default=None)
    ap.add_argument("--review-pool", action="store_true")
    ap.add_argument("--plan-pool", action="store_true",
                    help="ONE-PATH-PLAN-RUN-01: resolve a planner arm pool "
                         "(--job plan, DISPATCHABLE_PLAN_ARMS filter, no author "
                         "exclusion). Structurally identical to --review-pool.")
    ap.add_argument("--author", default="")
    ap.add_argument("--kimi-bin", default=None,
                    help="kimi-coder.sh path for the review-pool probe gate "
                         "(KIMI-CHANNEL-01b); falls back to LEADV2_DISPATCH_KIMI_BIN "
                         "then scripts/kimi-coder.sh, mirroring dispatch-code.sh:1243.")
    args = ap.parse_args(argv)

    try:
        # D1: ordered self-heal search (tenant --routing-yaml -> plugin-local ->
        # canonical) BEFORE giving up -- the pre-fix code gave up the instant the
        # single passed-in path was unreadable, which is exactly the root cause of
        # this whole round (no routing yaml at .claude/ref/leadv2-routing.yaml ->
        # silent no-op fallback with zero reviewer=/pool=/refusal= output at all).
        routing_yaml_path, ry_source = _resolve_routing_yaml_path(args.routing_yaml)
        if routing_yaml_path is None:
            # DEFAULT_REVIEW_ARM_ORDER-level last resort: no yaml found ANYWHERE, so
            # there is no dispatch_ladder/review_rank data to float from either --
            # honest empty pool with a distinct refusal, not a fabricated arm. D1
            # should make this basically unreachable in any real deployment.
            _emit_fallback(args.job, "no_routing_yaml")
            if args.review_pool:
                _emit_pool_lines("", [], "no_routing_yaml")
            return 0
        text = Path(routing_yaml_path).read_text()

        glm_policy = extract_glm_policy_block(text)
        ladder = extract_dispatch_ladder(text)
        ladder_providers = {e["id"]: e["provider"] for e in ladder}
        rank_table = {e["id"]: e["review_rank"] for e in ladder if e.get("review_rank") is not None}

        try:
            signals = json.loads(args.signals)
        except Exception:
            signals = {}

        quota_live_bin = args.quota_live
        if quota_live_bin is None:
            quota_live_bin = str(Path(__file__).resolve().parent.parent / "leadv2-quota-live.sh")

        # KIMI-CHANNEL-01b: --kimi-bin -> LEADV2_DISPATCH_KIMI_BIN (same env name
        # leadv2-dispatch-code.sh:1243 reads) -> scripts/kimi-coder.sh, so tests and
        # prod share one knob. Only consumed on the --review-pool path.
        kimi_bin = args.kimi_bin
        if kimi_bin is None:
            kimi_bin = os.environ.get("LEADV2_DISPATCH_KIMI_BIN")
        if kimi_bin is None:
            kimi_bin = str(Path(__file__).resolve().parent.parent / "kimi-coder.sh")

        now_epoch = _now_epoch()
        lockout_dir = os.environ.get("LEADV2_QUOTA_LOCKOUT_DIR")

        result = resolve_glm_policy(glm_policy, signals, args.job, args.base_arm, quota_live_bin,
                                    kimi_bin=kimi_bin)
        # D4: a live codex lockout forces codex_quota_blocked=1 in THIS (non-pool)
        # output block too, independent of whatever live_codex_weekly_pct's own read
        # returned -- the resolver previously had zero awareness of the on-disk store.
        if _lockout_blocked(ladder_providers.get("codex", "codex"), now_epoch, lockout_dir):
            result["codex_quota_blocked"] = True
        print("arm=%s" % result["arm"])
        print("rule=%s" % result["rule"])
        print("reason=%s" % result["reason"])
        print("tier=%s" % result["tier"])
        print("codex_quota_blocked=%s" % ("1" if result["codex_quota_blocked"] else "0"))
        # ry_source (tenant|plugin|canonical) is journaled bash-side by
        # resolve_review_pool_call() -- that's the caller with TASK/emit() access;
        # this CLI process only needs its own routing-yaml resolution to be correct,
        # not to duplicate the journal write.

        # dispatch-00629379: additive-only -- absent --review-pool, output above is
        # byte-identical to pre-change (v1-equivalence, design §7 test f).
        if args.review_pool or args.plan_pool:
            # ONE-PATH-PLAN-RUN-01: --plan-pool uses the same resolve_review_pool
            # with job=plan (already filtered by DISPATCHABLE_PLAN_ARMS at line 427)
            # and no author exclusion (plan has no author-exclusion concept).
            _pool_job = "plan" if args.plan_pool else args.job
            pool_result = resolve_review_pool(glm_policy, args.author, quota_live_bin,
                                              kimi_bin=kimi_bin, signals=signals,
                                              rank_table=rank_table, ladder_providers=ladder_providers,
                                              lockout_dir=lockout_dir, now_epoch=now_epoch,
                                              job=_pool_job)
            _emit_pool_lines(pool_result["reviewer"], pool_result["pool"], pool_result["refusal"])
        return 0
    except Exception:
        # D2: resolver_error path -- MUST still print reviewer=/pool=/refusal= when
        # --review-pool/--plan-pool was requested, via the SAME independent floor
        # re-derivation the top-level except in __main__ uses, so a crash anywhere
        # above (a bad signals JSON that somehow slips past its own try/except, a
        # resolve_glm_policy bug, anything) never regresses to the old silent no-op.
        _emit_fallback(args.job, "resolver_error")
        if args.review_pool or args.plan_pool:
            reviewer, pool, refusal = _best_effort_floor_pool(argv)
            _emit_pool_lines(reviewer, pool, refusal)
        return 0


if __name__ == "__main__":
    try:
        sys.exit(_main(sys.argv[1:]) or 0)
    except Exception as _e:
        # D2: the true last-resort catch -- something failed even before/around
        # _main's own internal try/except (e.g. argparse itself, or an exception
        # inside _main's except block). Same independent floor re-derivation, so
        # --review-pool still gets non-empty output here too.
        sys.stderr.write("leadv2-glm-policy-resolve.py: resolver_error: %s\n" % _e)
        _argv = sys.argv[1:]
        _emit_fallback(_job_from_argv(_argv), "resolver_error")
        if "--review-pool" in _argv or "--plan-pool" in _argv:
            _reviewer, _pool, _refusal = _best_effort_floor_pool(_argv)
            _emit_pool_lines(_reviewer, _pool, _refusal)
        sys.exit(0)
