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
are NOT reported broken by the brief (their model literals are already
threaded dynamically, or -- for glm -- the `--model` value passed to the
underlying `claude` CLI is a fixed translation-layer literal unrelated to
arm selection) and are intentionally left `adapter_argv_not_registered` here
rather than guessing an unverified CLI shape for them.

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

# Canonical "arm launches as itself" model literal, used by check(). Claude
# family: the arm name IS the --model value (claude-subsession.sh:124).
_CLAUDE_ARMS = ("haiku", "sonnet", "opus", "fable")


def _canonical_model(arm, matrix_rows):
    if arm in _CLAUDE_ARMS:
        return arm
    for row in matrix_rows:
        if row.get("arm") == arm and row.get("provider") == "codex":
            return row.get("model")
    return None


def check(arm, model, routing_yaml=None):
    """(arm, model) -> "ok" | "refuse" | "not_applicable".

    "refuse": this arm's canonical launch model is known and `model` is
    something else -- e.g. check("fable", "sonnet") is exactly the bug this
    registry exists to catch. "not_applicable": arm has no registered
    canonical-model concept yet (glm family / freepool -- see module
    docstring) so no verdict can be made either way.
    """
    matrix_rows = load_capability_matrix(routing_yaml)
    canonical = _canonical_model(arm, matrix_rows)
    if canonical is None:
        return "not_applicable"
    return "ok" if model == canonical else "refuse"


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
    row = min(pool, key=lambda r: r.get("cost", 0))

    provider = row.get("provider")
    builder = _FAMILY_BUILDERS.get(provider)
    if builder is None:
        return {"ok": False, "reason": "adapter_argv_not_registered", "arm": arm,
                "provider": provider, "kind": kind}
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
