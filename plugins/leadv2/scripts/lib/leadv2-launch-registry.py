#!/usr/bin/env python3
"""leadv2-launch-registry.py -- ARMS-CANNOT-LAUNCH-THEMSELVES-01 P1, lane 64fa36bd9571 (part A).

THE BUG THIS EXISTS TO FIX (measured 2026-09-07): leadv2-dispatch-code.sh:6251
launches every Claude-family worker with the LITERAL `--model sonnet`,
regardless of what the route arbiter resolved (`arm=fable`/`haiku`/`opus`
still launches sonnet). The routing decision and the launched model are
different facts today and nothing checks that they agree. This module is the
registry that makes "arm -> the exact adapter argv" a lookup instead of a
hardcoded literal, plus a `check()` a caller can use to REFUSE a mismatch
instead of launching it.

SERIAL QUEUE (SD-SMART-ROUTING-SERIAL-QUEUE-01): the actual call site
(leadv2-dispatch-code.sh:6251), the arbiter (lib/leadv2-route-arbiter.sh) and
config/leadv2-routing.yaml are owned by a concurrent lane (8ca00e79) and are
NOT edited here. This file is a standalone, importable, independently
testable unit -- every fixture in
plugins/leadv2/tests/test-launch-registry-argv.sh proves descriptor ->
registry lookup -> adapter argv without touching any of those three files.
Wiring the call site to use this registry is PART B.

Design doc: ~/Projects/persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/PLAN.md
section P1.

Only Anthropic Claude-family arms (haiku, sonnet, opus, fable) and Codex are
built out with verified adapter argv shapes (below). glm/glm-flash/freepool
are NOT adapter-less -- they launch through their OWN adapters
(scripts/glm-coder.sh, scripts/freepool-coder.sh) which the dispatcher drives
directly, never through this registry. A3-LAUNCH-REGISTRY (2026-09-09): their
lookup() refusal keeps reason=adapter_argv_not_registered (pinned verbatim by
tests/test-launch-registry-argv.sh) but now carries adapter_scope="external"
via _EXTERNAL_ADAPTERS, so "no launch path exists" and "the launch path is
not mine to describe" are distinguishable answers instead of the same
ok:false a caller cannot tell apart.

CLI:
    leadv2-launch-registry.py --kind <kind> --role <role> --arm <arm> \\
        --task-class <class> [--json]
    leadv2-launch-registry.py --check --arm <arm> --model <model>

Env overrides (hermetic tests):
    LEADV2_ROUTE_ARBITER_ROUTING_YAML   routing.yaml path (mirrors the
        arbiter's own env var name/precedence so a test fixture can point
        both at the same file without a second knob).
    LEADV2_LAUNCH_REGISTRY_GLM_POLICY_MODULE   path to a
        leadv2-glm-policy-resolve.py-shaped module providing
        DISPATCHABLE_BUILD_ARMS / DISPATCHABLE_PLAN_ARMS (fixture override).
"""
import importlib.util
import json
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_DEFAULT_ROUTING_YAML = os.path.join(_HERE, "..", "..", "config", "leadv2-routing.yaml")
_DEFAULT_GLM_POLICY_MODULE = os.path.join(_HERE, "leadv2-glm-policy-resolve.py")

# ── task-class -> matrix `sizes` bucket ──────────────────────────────────────
# Reuses the SAME `sizes:` field every capability_matrix row already carries
# (config/leadv2-routing.yaml) instead of inventing a second size vocabulary.
SIZE_BY_TASK_CLASS = {
    "trivial": "standard", "light": "standard", "standard": "standard",
    "heavy": "heavy", "complex": "heavy", "strategic": "heavy", "bulk": "bulk",
}

# ── (kind, task_class) -> effort ─────────────────────────────────────────────
# EFFORT-IS-NOT-WIRED-01 / founder requirement (verbatim): models must be
# selectable "и выбирать эффорт везде в зависимости от задач" -- effort
# follows kind+hardness, never one global default. This table answers a
# narrower question than routing.yaml's arbiter-owned `effort_matrix` (which
# ranks COST across arms): what effort should THIS adapter be launched with
# for this task shape. Deliberately not read from routing.yaml -- that file
# is owned by the blocked lane; duplicating its cost-ranking logic here would
# be a second, driftable copy of a DIFFERENT decision.
EFFORT_BY_KIND_AND_CLASS = {
    ("safety", None): "high",
    ("plan", None): "high",
    ("audit", None): "high",
    ("review", None): "high",
    ("code", "heavy"): "high",
    ("code", "complex"): "high",
    ("code", None): "medium",
    ("docs", None): "low",
    ("recon", None): "low",
    ("fanout-class-funnel", None): "low",
    ("backlog-pump", None): "low",
}


def resolve_effort(kind, task_class):
    return (EFFORT_BY_KIND_AND_CLASS.get((kind, task_class))
            or EFFORT_BY_KIND_AND_CLASS.get((kind, None))
            or "medium")


# ── codex (model, tier) launch table (A1-CODEX-TIERS-A2 part A) ──────────────
# One entry per (codex model, tier) pair codex-task.sh's tier table can now
# launch AS ITSELF: each tier's primary model plus its journaled-fallback
# models (top: sol, terra, astra; standard: terra, astra; volume: luna,
# astra). lookup() REFUSES a matrix row whose (model, tier) pair is not in
# this table -- the registry narrows what is launchable, never widens what
# the matrix allows.
#
# EFFORT IS PART OF THE ENTRY, not a constant: founder requirement (verbatim)
# -- models must be selectable "и выбирать эффорт везде в зависимости от
# задач" -- so each pair carries its own per-TASK-CLASS effort, derived from
# the tier's codex-task.sh effort (top=high / standard=medium / volume=low,
# EFFORT-RECAL 2026-07-10) shifted one codex-wire step by hardness
# ({none,minimal,low,medium,high,xhigh}): heavy/complex/strategic up,
# trivial/light down, bulk at base -- EFFORT_BY_KIND_AND_CLASS's doctrine
# (mechanical ⇒ low, ordinary ⇒ medium, high-stakes ⇒ high) mapped onto the
# class axis. Two pairs in the same tier share the table because the MODEL
# does not change the marginal value of extra thinking; the TASK does.
_CODEX_EFFORT_TABLES = {
    "top": {
        "trivial": "medium", "light": "medium", "standard": "high",
        "heavy": "xhigh", "complex": "xhigh", "strategic": "xhigh", "bulk": "high",
    },
    "standard": {
        "trivial": "low", "light": "low", "standard": "medium",
        "heavy": "high", "complex": "high", "strategic": "high", "bulk": "medium",
    },
    "volume": {
        "trivial": "low", "light": "low", "standard": "low",
        "heavy": "medium", "complex": "medium", "strategic": "medium", "bulk": "low",
    },
}
CODEX_MODEL_TIERS = {
    ("gpt-5.6-sol", "top"): _CODEX_EFFORT_TABLES["top"],
    ("gpt-5.6-terra", "top"): _CODEX_EFFORT_TABLES["top"],
    ("gpt-5.6-terra", "standard"): _CODEX_EFFORT_TABLES["standard"],
    ("gpt-5.6-luna", "volume"): _CODEX_EFFORT_TABLES["volume"],
    ("gpt-6-astra", "top"): _CODEX_EFFORT_TABLES["top"],
    ("gpt-6-astra", "standard"): _CODEX_EFFORT_TABLES["standard"],
    ("gpt-6-astra", "volume"): _CODEX_EFFORT_TABLES["volume"],
}


def codex_effort_for(model, tier, task_class):
    """Per-task-class effort for a REGISTERED (codex model, tier) pair, or
    None when the pair is not launchable (lookup() refuses on that)."""
    table = CODEX_MODEL_TIERS.get((model, tier))
    if table is None:
        return None
    return table.get((task_class or "").lower()) or table["standard"]


# ── pool_default registry DATA (brief item 1) ────────────────────────────────
# opus stays out of the default auction (shares the lead's own window) --
# reachable by explicit pool or pin, never by default. Recorded here as DATA
# only; REMOVING the pre-arbiter opus park (leadv2-dispatch-code.sh:8386) on
# the new path, and actually consulting this flag before admission, is part B.
POOL_DEFAULT_OVERRIDES = {"opus": False}


def pool_default(arm):
    return POOL_DEFAULT_OVERRIDES.get(arm, True)


# ── DISPATCHABLE_*_ARMS: imported live, never duplicated ────────────────────
def _load_glm_policy_module():
    path = os.environ.get("LEADV2_LAUNCH_REGISTRY_GLM_POLICY_MODULE", _DEFAULT_GLM_POLICY_MODULE)
    spec = importlib.util.spec_from_file_location("leadv2_glm_policy_resolve_ro", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _dispatchable_arm_sets():
    """(build_arms, plan_arms) sets, read live from the resolver -- never a
    copy that could silently drift from the file that is the actual source
    of truth (both must match _candidate_chain_for_arm's case-rows per that
    file's own header comment)."""
    try:
        mod = _load_glm_policy_module()
        return (set(mod.DISPATCHABLE_BUILD_ARMS), set(mod.DISPATCHABLE_PLAN_ARMS))
    except Exception:
        # Fail-safe mirrors resolve_glm_policy()'s own contract (this file's
        # docstring): a broken resolver must never block dispatch. Falling
        # back to "nothing is dispatchable" would be the opposite of
        # fail-safe here (it would refuse everything), so fall back to the
        # narrowest KNOWN-true set instead -- verified 2026-09-07 against the
        # live file, named explicitly so a real drift is visible in a diff.
        return ({"glm", "glm-flash", "codex", "sonnet", "freepool"},
                {"codex", "sonnet", "opus", "fable"})


# ── capability_matrix loader ─────────────────────────────────────────────────
_FLOW_ROW_RE = re.compile(r"^\s*-\s*\{(.*)\}\s*#?.*$")


def _parse_flow_row(text):
    """Minimal parser for one `- { key: val, key: [a, b], ... }` YAML flow
    row. Used ONLY as the no-PyYAML fallback -- capability_matrix rows are
    single-line flow mappings, never nested, so a targeted parse is safe
    here where a general YAML fallback would not be."""
    row = {}
    depth = 0
    buf = ""
    parts = []
    for ch in text:
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(buf)
            buf = ""
        else:
            buf += ch
    if buf.strip():
        parts.append(buf)
    for part in parts:
        if ":" not in part:
            continue
        key, _, val = part.partition(":")
        key = key.strip()
        val = val.strip()
        if val.startswith("[") and val.endswith("]"):
            inner = val[1:-1].strip()
            row[key] = [t.strip() for t in inner.split(",") if t.strip()] if inner else []
        elif val in ("true", "false"):
            row[key] = (val == "true")
        else:
            try:
                row[key] = int(val)
            except ValueError:
                try:
                    row[key] = float(val)
                except ValueError:
                    row[key] = val.strip('"\'')
    return row


def _load_capability_matrix_fallback(path):
    rows = []
    in_matrix = False
    with open(path) as fh:
        for raw in fh:
            stripped = raw.strip()
            if stripped.startswith("capability_matrix:"):
                in_matrix = True
                continue
            if in_matrix:
                if stripped and not stripped.startswith("#") and not raw.startswith(("  ", "\t")):
                    break
                m = _FLOW_ROW_RE.match(raw)
                if m:
                    rows.append(_parse_flow_row(m.group(1)))
    return rows


def load_capability_matrix(routing_yaml=None):
    path = routing_yaml or os.environ.get("LEADV2_ROUTE_ARBITER_ROUTING_YAML", _DEFAULT_ROUTING_YAML)
    try:
        import yaml  # noqa: local import -- optional dependency, see fallback below
        with open(path) as fh:
            doc = yaml.safe_load(fh) or {}
        rows = ((doc.get("router_v2") or {}).get("capability_matrix")) or []
        if rows:
            return rows
    except Exception:
        pass
    return _load_capability_matrix_fallback(path)


# ── PRICE-THE-ARM-PER-PROVIDER-01 (dispatch-f8880421) ────────────────────────
# capability_matrix rows no longer carry `cost:` -- this registry's own row
# picker (lookup()'s cheapest-tier tie-break, e.g. codex luna/terra/sol) must
# read the SAME router_v2.cost source the arbiter prices from, or its verdict
# silently drifts from what the arbiter actually charged. Mirrors the
# arbiter's price_key()/provider_cost() semantics exactly (see
# lib/leadv2-route-arbiter.sh): glm-flash prices off its own arm key, every
# other row off `provider`; a routing yaml with no router_v2.cost block at
# all (legacy fixtures) falls back to the row's own `cost:` field.
def _price_key(row):
    return "glm-flash" if row.get("arm") == "glm-flash" else row.get("provider")


def load_provider_cost(routing_yaml=None):
    """-> (cost_dict_or_None, unpriced_policy). None means the yaml carries no
    router_v2.cost block at all (LEGACY: provider_cost() reads row['cost'])."""
    path = routing_yaml or os.environ.get("LEADV2_ROUTE_ARBITER_ROUTING_YAML", _DEFAULT_ROUTING_YAML)
    try:
        import yaml  # noqa: local import -- optional dependency, see fallback below
        with open(path) as fh:
            doc = yaml.safe_load(fh) or {}
        router_v2 = doc.get("router_v2") or {}
        if "cost" in router_v2:
            return router_v2.get("cost") or {}, str(router_v2.get("cost_unpriced_policy", "matrix_median"))
        return None, "matrix_median"
    except Exception:
        pass
    return _load_provider_cost_fallback(path)


def _load_provider_cost_fallback(path):
    cost, found_block, in_cost = {}, False, False
    with open(path) as fh:
        for raw in fh:
            stripped = raw.strip()
            if in_cost:
                if stripped and not stripped.startswith("#") and not raw.startswith("    "):
                    in_cost = False
                else:
                    m = re.match(r"^([\w-]+):\s*([^\s#]+)", stripped)
                    if m:
                        k, v = m.group(1), m.group(2)
                        cost[k] = None if v == "null" else (_num(v) if _num(v) is not None else v)
                    continue
            if re.match(r"^cost:\s*(#.*)?$", stripped):
                in_cost = True
                found_block = True
    return (cost if found_block else None), "matrix_median"


def _num(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


def provider_cost(row, cost_cfg):
    """cost_cfg is load_provider_cost()'s first return value. Same fallback
    ladder as the arbiter: LEGACY (cost_cfg is None) reads row['cost'];
    otherwise an unpriced/missing key prices at the median of the numeric
    entries (1.0 if every entry is null/absent -- never a refusal)."""
    if cost_cfg is None:
        v = _num(row.get("cost"))
        return v if v is not None else 999.0
    numeric = sorted(v for v in cost_cfg.values() if isinstance(v, (int, float)))
    median = 1.0
    if numeric:
        n = len(numeric)
        mid = n // 2
        median = numeric[mid] if n % 2 else (numeric[mid - 1] + numeric[mid]) / 2.0
    v = cost_cfg.get(_price_key(row))
    return v if isinstance(v, (int, float)) else median


# ── adapter argv builders (verified shapes only) ─────────────────────────────
# claude-subsession.sh:124 accepts --model opus*|sonnet*|haiku*|fable*|claude*
# and threads it straight through to the `claude` CLI (:595); :6251 already
# threads --effort via _sonnet_effort_args when RESOLVED_EFFORT is set. So
# for the whole claude family the fix is generalizing the MODEL literal --
# the effort plumbing already exists.
def _argv_claude(role, model, tier, effort, kind=None):  # kind: builder-call parity; claude wire never branches on it
    argv = ["--role", role, "--model", model]
    if effort:
        argv += ["--effort", effort]
    return argv, True


# codex-task.sh resolves --tier <volume|standard|top> to a concrete model
# INTERNALLY (_resolve_tier_model_effort, A1-CODEX-TIERS-A2: sol/terra/luna
# per tier with journaled fallback to astra), and --reason is REQUIRED for
# --tier top (codex-task.sh, hard exit otherwise). For the kinds that run
# codex-task.sh `task`, an EXPLICIT --model/--effort always wins over the
# tier-resolved value (codex-task.sh: "explicit --model already present" /
# "explicit --effort already present"), so those argv PIN the registered
# (model, effort) -- the pair the arbiter chose is exactly what launches,
# not whatever the tier table might fall back to at runtime. `review` keeps
# the tier-only argv (frozen by test-launch-registry-argv.sh: the review
# command takes no --effort wire, and that suite asserts ["--tier",
# "standard"] verbatim); `plan` keeps it too (leadv2-codex-planner.sh
# REJECTS --model and its tier table is still all-astra -- wiring plan is
# part B together with the planner's own table adoption). The 4-arg call
# without kind is the pre-A2 shape, preserved for the same suite.
_CODEX_TASK_WIRE_KINDS = frozenset(
    ("code", "docs", "recon", "fanout-class-funnel", "backlog-pump"))


def _argv_codex(role, model, tier, effort, kind=None):
    argv = ["--tier", tier]
    if kind in _CODEX_TASK_WIRE_KINDS and (model, tier) in CODEX_MODEL_TIERS:
        argv += ["--model", model, "--effort", effort]
        return argv, True
    if tier == "top":
        argv += ["--reason", "registry-resolved-top-tier"]
    return argv, False


_FAMILY_BUILDERS = {
    "claude": _argv_claude,
    "codex": _argv_codex,
}

# ── external adapters: launch paths this registry does NOT own ──────────────
# A3-LAUNCH-REGISTRY (2026-09-09): "can arm X launch" had two truths. This
# registry answered a bare adapter_argv_not_registered for glm/glm-flash/
# freepool -- indistinguishable from "no launch path exists" -- while the
# dispatcher launched those arms all day (journal: CODEX-ALWAYS-UP,
# RECON-5H-WINDOW author=glm; B2 route_resolved role=reviewer arm=glm), and
# the launchability seam (_arm_launchable_arms) had to hardcode
# {'glm','glm-flash','freepool'} shell-side to paper over the disagreement.
# This map is the registry-side declaration of the same scope: providers
# whose launch path is REAL but lives outside this registry, keyed by
# provider (the adapter-level truth -- one adapter serves every arm of that
# provider), value = the adapter script the dispatcher actually drives
# (GLM_BIN/FREEPOOL_BIN defaults under scripts/). A name here WITHOUT a live
# dispatcher-driven launch path would be the lying-green disease in registry
# form; this map must name only adapters that really run.
_EXTERNAL_ADAPTERS = {
    "glm": "glm-coder.sh",        # serves glm + glm-flash (provider glm)
    "freepool": "freepool-coder.sh",
}

# Canonical "arm launches as itself" model literal, used by check(). Claude
# family: the arm name IS the --model value (claude-subsession.sh:124).
_CLAUDE_ARMS = ("haiku", "sonnet", "opus", "fable")


def _canonical_models(arm, matrix_rows):
    """Every canonical "arm launches as itself" model literal for `arm`, as a
    tuple. Claude family: the arm name IS the --model value
    (claude-subsession.sh:124). Codex (A1-CODEX-TIERS-A3): every model the
    matrix carries on a codex row, NARROWED to pairs this registry can wire
    (CODEX_MODEL_TIERS) -- with three per-tier codex models the old
    first-row-wins scalar answered check("codex", "gpt-5.6-sol")=refuse, so
    the refusal helper would have vetoed exactly the models part A made
    launchable once part B's matrix rows land."""
    if arm in _CLAUDE_ARMS:
        return (arm,)
    models = []
    for row in matrix_rows:
        if row.get("arm") == arm and row.get("provider") == "codex":
            m = row.get("model")
            if m and (m, row.get("tier")) in CODEX_MODEL_TIERS and m not in models:
                models.append(m)
    return tuple(models)


def check(arm, model, routing_yaml=None):
    """(arm, model) -> "ok" | "refuse" | "not_applicable".

    "refuse": this arm's canonical launch model is known and `model` is
    something else -- e.g. check("fable", "sonnet") is exactly the bug this
    registry exists to catch. "not_applicable": arm has no registered
    canonical-model concept yet (glm family / freepool -- see module
    docstring) so no verdict can be made either way.
    """
    matrix_rows = load_capability_matrix(routing_yaml)
    canonical = _canonical_models(arm, matrix_rows)
    if not canonical:
        return "not_applicable"
    return "ok" if model in canonical else "refuse"


def normalize_kind(kind, matrix_rows):
    """Return the matrix vocabulary kind used by every launchability reader.

    Out-of-vocabulary dispatch kinds are ordinary build work, matching the
    arbiter's existing kind_unmapped fallback.  The matrix remains the single
    vocabulary source; callers never maintain a parallel alias list.
    """
    known_kinds = {k for row in matrix_rows for k in (row.get("kinds") or [])}
    return kind if kind in known_kinds else "code"


def lookup(kind, role, arm, task_class, routing_yaml=None):
    """(kind, role, arm, task_class) -> descriptor dict.

    Resolves model/tier/effort internally from the capability_matrix (never
    widening it) and DISPATCHABLE_BUILD_ARMS/DISPATCHABLE_PLAN_ARMS (narrows
    `code` and `review`/`plan` kinds only -- every other kind is governed by
    the matrix alone, matching what those two sets actually gate today).
    Returns {"ok": False, "reason": ...} on any capability miss -- never a
    substituted arm/model.
    """
    matrix_rows = load_capability_matrix(routing_yaml)
    # CAPABILITY-GATES-DISAGREE-AND-THE-JOURNAL-CANNOT-SEE-IT-01: dispatch
    # and the arbiter deliberately treat a kind outside the matrix vocabulary
    # as ordinary build work (`code`).  Before this lived only in the
    # dispatch-side launchability preflight: the same plugin dispatch could
    # pass the arbiter, then reach this real launcher with raw kind=plugin and
    # be refused as arm_not_capable_for_kind.  Make the launch registry own
    # the normalization too, from the matrix it already reads; there is no
    # second capability table and no arm-specific exception.
    kind = normalize_kind(kind, matrix_rows)
    build_arms, plan_arms = _dispatchable_arm_sets()

    if kind == "code" and arm not in build_arms:
        return {"ok": False, "reason": "not_a_build_arm", "arm": arm, "kind": kind}
    if kind == "plan" and arm not in plan_arms:
        return {"ok": False, "reason": "not_a_plan_arm", "arm": arm, "kind": kind}

    size = SIZE_BY_TASK_CLASS.get((task_class or "").lower(), "standard")
    candidates = [r for r in matrix_rows if r.get("arm") == arm and kind in (r.get("kinds") or [])]
    if not candidates:
        return {"ok": False, "reason": "arm_not_capable_for_kind", "arm": arm, "kind": kind}
    if kind == "review":
        reviewer_candidates = [r for r in candidates if r.get("review") is True]
        if not reviewer_candidates:
            return {"ok": False, "reason": "arm_not_a_reviewer", "arm": arm, "kind": kind}
        candidates = reviewer_candidates

    size_matched = [r for r in candidates if size in (r.get("sizes") or [])]
    size_fallback = not size_matched
    pool = size_matched or candidates
    cost_cfg, _cost_policy = load_provider_cost(routing_yaml)
    row = min(pool, key=lambda r: provider_cost(r, cost_cfg))

    provider = row.get("provider")
    builder = _FAMILY_BUILDERS.get(provider)
    if builder is None:
        # A3-LAUNCH-REGISTRY (2026-09-09): two cases used to share one
        # answer. (a) The provider genuinely has no launch path here -- an
        # invented provider, a matrix row nobody wired: ok:false IS the
        # verdict. (b) The arm HAS a launch path this registry does not own
        # (see _EXTERNAL_ADAPTERS): the old unqualified refusal read as
        # "cannot launch" for arms that demonstrably run, so the refusal now
        # carries adapter_scope="external" + the real adapter -- an honest
        # "not my arm" a caller derives launchability from instead of
        # duplicating arm names shell-side. The reason string itself is
        # unchanged (tests/test-launch-registry-argv.sh pins it verbatim),
        # and no argv is fabricated: registering a claude-shaped --model argv
        # for these arms would be a green answer nothing executes.
        refusal = {"ok": False, "reason": "adapter_argv_not_registered", "arm": arm,
                   "provider": provider, "kind": kind}
        if provider in _EXTERNAL_ADAPTERS:
            refusal["adapter_scope"] = "external"
            refusal["external_adapter"] = _EXTERNAL_ADAPTERS[provider]
        return refusal
    if provider == "codex" and (row.get("model"), row.get("tier")) not in CODEX_MODEL_TIERS:
        # A1-CODEX-TIERS-A2: the matrix won a (model, tier) this registry
        # cannot launch AS ITSELF -- refuse rather than emit a --tier that
        # would resolve to some other model at runtime. Narrowing only: no
        # previously-launchable pair was removed.
        return {"ok": False, "reason": "codex_model_tier_not_registered", "arm": arm,
                "kind": kind, "model": row.get("model"), "tier": row.get("tier")}

    if provider == "codex":
        # Effort from the PAIR's own per-class table (founder: «и выбирать
        # эффорт везде в зависимости от задач»), not the kind doctrine that
        # governs the claude family.
        effort_requested = codex_effort_for(row.get("model"), row.get("tier"), task_class)
    else:
        effort_requested = resolve_effort(kind, task_class)
    argv, effort_supported = builder(role, row.get("model"), row.get("tier"), effort_requested, kind)
    return {
        "ok": True,
        "kind": kind, "role": role, "arm": arm, "task_class": task_class,
        "model": row.get("model"), "tier": row.get("tier"),
        "size": size, "size_fallback": size_fallback,
        "effort_requested": effort_requested,
        "effort_applied": effort_requested if effort_supported else None,
        "effort_supported": effort_supported,
        "pool_default": pool_default(arm),
        "argv": argv,
    }


# ── §4 phase 1 (row 4afa0ee2525a): decision verification, not re-ranking ────
# SMART-ARBITER-DESIGN-20260907, "The smallest seam that actually executes":
# the workflow-step boundary (leadv2-workflow-step.py run_step) asks the
# arbiter, then hands the decision HERE for verification. lookup() stays the
# single resolution path for existing callers; resolve_decision never ranks,
# never substitutes, never re-resolves -- it only checks that what arrived is
# exactly what this registry would launch, and names the field that diverged.
def resolve_decision(decision, step_context):
    """(decision dict, step_context dict) -> {"ok": True, invocation...} |
    {"ok": False, reason, field, ...}.

    decision: the parsed arbiter decision line (arm/kind/model/tier/effort).
    step_context: {"kind", "role", "task_class", "routing_yaml" (optional)}.

    Verifies (1) the arm is launchable through THIS registry at all -- an
    external-adapter arm (glm/freepool) or an out-of-set arm is a refusal
    NAMING THE ARM, never a substituted neighbour (same defect class the
    10ee163f7a3e guard fixes); (2) model/tier match the registry's own
    descriptor for (kind, role, arm, task_class) field by field; (3) the
    selected effort is APPLICABLE (effort_applied is not None) and equal --
    an executor that cannot apply the decision's effort refuses, it never
    silently launches a cheaper tier/effort.
    """
    kind = step_context.get("kind")
    role = step_context.get("role", "worker")
    task_class = step_context.get("task_class")
    arm = decision.get("arm")

    desc = lookup(kind, role, arm, task_class, routing_yaml=step_context.get("routing_yaml"))
    if not desc.get("ok"):
        # Loud, arm-naming refusal: keep lookup()'s own reason verbatim
        # (not_a_build_arm / arm_not_capable_for_kind /
        # adapter_argv_not_registered with adapter_scope=external, ...).
        refusal = {"ok": False, "reason": "arm_not_launchable", "field": "arm",
                   "arm": arm, "registry_reason": desc.get("reason")}
        if desc.get("adapter_scope"):
            refusal["adapter_scope"] = desc["adapter_scope"]
            refusal["external_adapter"] = desc.get("external_adapter")
        return refusal

    if desc.get("effort_applied") is None:
        # the executor cannot apply the selected effort: refuse, never
        # silently re-resolve a cheaper tier (design, same section)
        return {"ok": False, "reason": "effort_not_applicable", "field": "effort",
                "arm": arm, "decision_value": decision.get("effort"),
                "registry_value": None,
                "message": "the registry's launch path for arm=%s cannot apply effort=%r"
                           % (arm, decision.get("effort"))}

    # decision-match-mut (negative control, row 4afa0ee2525a): this loop is
    # the arm/model verification; leadv2-mutation-control.sh drops "arm",
    # "model" from the tuple below and test-workflow-step-runner.sh must go
    # red on the paired substitution case. Registry values are the truth;
    # the decision must match them EXACTLY.
    for _field in ("arm", "model", "tier", "effort"):
        _d = decision.get(_field)
        _r = desc.get("effort_applied") if _field == "effort" else desc.get(_field)
        if _d != _r:
            return {"ok": False, "reason": "decision_field_mismatch", "field": _field,
                    "arm": arm, "decision_value": _d, "registry_value": _r,
                    "message": "arbiter decision field '%s' (%r) diverged from the registry "
                               "launch metadata (%r) for arm=%s -- refusing rather than "
                               "substituting or re-ranking" % (_field, _d, _r, arm)}

    return {"ok": True, "reason": "decision_verified",
            "verified_fields": ["arm", "model", "tier", "effort"],
            "kind": kind, "role": role, "arm": arm, "task_class": task_class,
            "model": desc["model"], "tier": desc["tier"],
            "effort": desc["effort_applied"], "effort_supported": desc["effort_supported"],
            "size": desc["size"], "size_fallback": desc["size_fallback"],
            "pool_default": desc["pool_default"], "argv": desc["argv"]}


def _cli(argv):
    args = {}
    i = 0
    flags = set()
    while i < len(argv):
        a = argv[i]
        if a in ("--json", "--check"):
            flags.add(a.lstrip("-"))
            i += 1
            continue
        if a.startswith("--") and i + 1 < len(argv):
            args[a.lstrip("-").replace("-", "_")] = argv[i + 1]
            i += 2
            continue
        i += 1

    if "check" in flags:
        arm = args.get("arm")
        model = args.get("model")
        if not arm or not model:
            sys.stderr.write("usage: leadv2-launch-registry.py --check --arm <arm> --model <model>\n")
            return 2
        verdict = check(arm, model)
        print(verdict)
        return 0 if verdict != "refuse" else 1

    kind = args.get("kind")
    role = args.get("role")
    arm = args.get("arm")
    task_class = args.get("task_class")
    if not (kind and role and arm):
        sys.stderr.write("usage: leadv2-launch-registry.py --kind <k> --role <r> --arm <a> "
                         "--task-class <c> [--json]\n")
        return 2
    result = lookup(kind, role, arm, task_class)
    if "json" in flags:
        print(json.dumps(result))
        return 0 if result.get("ok") else 1
    if not result.get("ok"):
        sys.stderr.write("refused: %s\n" % result.get("reason"))
        return 1
    for token in result["argv"]:
        print(token)
    return 0


if __name__ == "__main__":
    sys.exit(_cli(sys.argv[1:]))
