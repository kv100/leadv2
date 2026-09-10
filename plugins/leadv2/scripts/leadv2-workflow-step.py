#!/usr/bin/env python3
"""leadv2-workflow-step.py -- the executable workflow-step boundary (§4 phase 1, row 4afa0ee2525a).

Workflow code lives in a JS runtime with no global bash() and no module
imports (workflows/leadv2-audit.js:41-43, workflows/leadv2-ledger.js:55), so
"just pass {model: decision.arm} to agent(...)" is impossible THERE. This
module is the seam that actually executes OUTSIDE that runtime
(SMART-ARBITER-DESIGN-20260907, section "The smallest seam that actually
executes"): it accepts a step request, consults the route arbiter through
its EXISTING CLI line protocol (the arbiter is not modified here --
structured output mode is a separate lane), verifies the decision against
the launch registry (lib/leadv2-launch-registry.py resolve_decision: exact
arm/model/tier/effort, never re-ranked, never substituted), launches through
a declared executor, and returns a complete receipt. A step without a
receipt did not happen: "success without a receipt" is exactly the false
green this boundary exists to prevent.

run_step(request) -> receipt dict (ALWAYS; refusals carry a refusal block).

Request (JSON object), validated STRICTLY -- unknown values are refusals,
never "allow by default":
    step_id, round, attempt          step identity (round >= 1)
    kind                             work_kind; must appear in the CURRENT
                                     routing yaml's capability kinds (plus the
                                     registry effort table's kinds). An unknown
                                     kind is REFUSED HERE, before the arbiter's
                                     legacy unknown->code coercion can turn it
                                     into permission (design: strict validation).
    size                             task_class: trivial|light|standard|heavy|
                                     complex|strategic|bulk
    provenance                       judge|flag|heuristic|unknown|estimate.
                                     'estimate' is preserved verbatim in the
                                     receipt and mapped to 'heuristic' for the
                                     arbiter call (design: never silently
                                     relabelled 'judge').
    required_capabilities            non-empty list; every entry must be in
                                     CAPABILITY_VOCABULARY below. A missing or
                                     unknown capability is a refusal.
    role                             worker (default) | reviewer
    task, subtype                    forwarded verbatim to the arbiter payload
    launchable_arms                  optional list; if present it must be
                                     NON-empty -- an explicitly empty set is a
                                     refusal, not permission
    quota_evidence                   REQUIRED {"sampled_at_epoch": int, ...}.
                                     Admission evidence older than
                                     FRESHNESS_LIMIT_S (60s) is refused BY NAME
                                     after at most one bounded refresh via the
                                     optional quota_refresh_cmd argv. ABSENT
                                     evidence is also a refusal: absent
                                     freshness is never permission to launch.
                                     KNOWN EDGE, named not masked: several
                                     parallel steps can observe the SAME free
                                     quota; this boundary checks freshness, not
                                     exclusivity -- reservations are a separate
                                     coordinator concern (deliberately not
                                     built in this lane).
    arbiter_cmd                      optional argv overriding the default
                                     [bash, lib/leadv2-route-arbiter.sh,
                                     worker] -- the hermetic test seam. The
                                     boundary suite REPLACES the arbiter with a
                                     stub executable because it tests the
                                     BOUNDARY, not routing.
    executor                         REQUIRED argv prefix: the transport the
                                     coordinator drives (a real adapter script
                                     in production, a fixture executable in
                                     tests). The registry's VERIFIED argv is
                                     appended to it before launch.
    output_schema, schema_id         optional JSON-Schema SUBSET
                                     (type/required/properties/enum/items/
                                     minItems/minLength). Unsupported keywords
                                     are REFUSED, not ignored. With a schema
                                     given, executor stdout must be JSON.
    repo_root, timeout_s             executor cwd / wall timeout (default 300s)
    workflow_run_id                  recorded verbatim in the receipt

Executor contract (what the boundary can verify, nothing more):
    * argv  = <executor prefix> + registry-verified argv
    * env LEADV2_STEP_RESULT_JSON names a path where a well-behaved executor
      reports {"arm","model","usage"} for the OBSERVED half of the receipt;
      an absent file falls back to the argv-pinned pair
      (source=argv_pinned). An executor-report arm/model that DIVERGES from
      the verified invocation is a loud invalid_output refusal -- the
      launched thing must be the decided thing.
    * exit 0 = ran (then schema decides ok vs invalid_output)
    * exit 75, or a stderr line containing LEADV2_STEP_TRANSPORT_FAILED
      = transport_failed (the transport named its own failure)
    * death by signal, including the boundary's own timeout kill
      = cancelled (killed from outside is not a transport refusal)
    * any other non-zero rc = unknown_completion -- the boundary does NOT
      guess a transport failure it cannot verify

Receipt outcome is a CLOSED SET: ok | invalid_output | transport_failed |
cancelled | unknown_completion. Pre-launch refusals are receipts too: their
outcome is invalid_output for validation/decision failures (invalid input at
this boundary; refusal.kind + refusal.field carry the precise cause) and
transport_failed when the arbiter subprocess itself could not be consulted.
status=refused with launched=false distinguishes them from executed steps.

decision_id is minted AT THE BOUNDARY (sha256 of step identity + the raw
decision line + wall clock, first 16 hex): the arbiter's journal suppresses
its own write exceptions, so the boundary durably appends its own receipt
(LEADV2_WORKFLOW_STEP_RECEIPTS_FILE, default
$TMPDIR/leadv2-workflow-step-receipts.jsonl) before returning; a failed
append sets receipt_persisted=false loudly rather than vanishing.

Env: LEADV2_ROUTE_ARBITER_ROUTING_YAML  shared with the arbiter and the
registry -- one routing vocabulary, one file, no second source;
LEADV2_WORKFLOW_STEP_RECEIPTS_FILE  receipts jsonl path.

CLI: leadv2-workflow-step.py --request <path|->   prints the receipt JSON.
"""
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
_REGISTRY_PATH = os.path.join(_HERE, "lib", "leadv2-launch-registry.py")
DEFAULT_ARBITER_CMD = ["bash", os.path.join(_HERE, "lib", "leadv2-route-arbiter.sh"), "worker"]

FRESHNESS_LIMIT_S = 60          # design: admission freshness limit for quota/readiness
ARBITER_TIMEOUT_S = 30
REFRESH_TIMEOUT_S = 30
EXECUTOR_TIMEOUT_S_DEFAULT = 300
EXECUTOR_TRANSPORT_RC = 75
TRANSPORT_MARKER = "LEADV2_STEP_TRANSPORT_FAILED"

TERMINAL_OUTCOMES = ("ok", "invalid_output", "transport_failed", "cancelled", "unknown_completion")
ROLES = ("worker", "reviewer")
# Raw provenance vocabulary: routing.yaml recognizes judge|flag|heuristic|unknown
# and the estimator emits 'estimate' -- both are kept, 'estimate' is MAPPED for
# routing only (design: preserve raw, never silently relabel).
KNOWN_PROVENANCE = ("judge", "flag", "heuristic", "unknown", "estimate")
PROVENANCE_ROUTE_MAP = {"estimate": "heuristic"}
# Declared capability vocabulary. Strict on purpose: a capability this boundary
# cannot name is a refusal, not an unchecked string that might mean anything.
CAPABILITY_VOCABULARY = frozenset(("read_repo", "write_repo", "json_result", "shell", "web"))

# The JSON-Schema subset this boundary can evaluate. Anything else in a schema
# is a refusal: a validator that silently ignores keywords it does not
# implement is a lying green (the same disease the closed outcome set exists
# to prevent).
_SCHEMA_KEYWORDS = frozenset(("type", "required", "properties", "enum", "items",
                              "minItems", "minLength", "description"))
_DECISION_LINE_RE = re.compile(r"(?:^|\s)([a-z_]+)=([^ ]*)")


def _load_registry():
    spec = importlib.util.spec_from_file_location("leadv2_launch_registry", _REGISTRY_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_REGISTRY = _load_registry()
# Task-class vocabulary is the registry's own (single source, never a copy).
KNOWN_SIZES = frozenset(_REGISTRY.SIZE_BY_TASK_CLASS)


def _known_kinds(routing_yaml=None):
    """Work-kind vocabulary = the CURRENT routing yaml's capability kinds plus
    the registry effort table's kinds. The matrix is the vocabulary (the
    2026-09-10 plugin-kind seam defect taught exactly this), so an unknown
    kind refuses HERE instead of being coerced by the arbiter's legacy path."""
    kinds = set(k for (k, _c) in _REGISTRY.EFFORT_BY_KIND_AND_CLASS)
    for row in _REGISTRY.load_capability_matrix(routing_yaml):
        kinds.update(row.get("kinds") or [])
    return kinds


def _refusal(kind, message, **fields):
    r = {"kind": kind, "message": message}
    r.update(fields)
    return r


def _receipt_path():
    return (os.environ.get("LEADV2_WORKFLOW_STEP_RECEIPTS_FILE")
            or os.path.join(os.environ.get("TMPDIR", "/tmp"), "leadv2-workflow-step-receipts.jsonl"))


def _iso(ts):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts))


def _write_receipt(receipt):
    try:
        with open(_receipt_path(), "a") as fh:
            fh.write(json.dumps(receipt, sort_keys=True) + "\n")
        return True
    except OSError:
        return False


# ── request validation (strict: never "allow by default") ───────────────────
def _validate_request(req):
    """-> (context, None) | (None, refusal). Every refusal names its field."""
    if not isinstance(req, dict):
        return None, _refusal("malformed_request", "request must be a JSON object")
    for field in ("step_id", "kind", "size", "provenance", "required_capabilities",
                  "quota_evidence", "executor"):
        if field not in req:
            return None, _refusal("missing_field", "required request field absent: %s" % field,
                                  field=field)
    step_id = req["step_id"]
    if not isinstance(step_id, str) or not step_id.strip():
        return None, _refusal("malformed_field", "step_id must be a non-empty string", field="step_id")
    rnd = req["round"]
    if not isinstance(rnd, int) or isinstance(rnd, bool) or rnd < 1:
        return None, _refusal("malformed_field", "round must be an integer >= 1", field="round")

    routing_yaml = req.get("routing_yaml")
    kind = str(req["kind"]).lower()
    if kind not in _known_kinds(routing_yaml):
        return None, _refusal("unknown_kind",
                              "kind='%s' is not in the routing vocabulary; the boundary refuses "
                              "rather than let the arbiter coerce it to 'code'" % kind,
                              field="kind", value=kind)
    size = str(req["size"]).lower()
    if size not in KNOWN_SIZES:
        return None, _refusal("unknown_size", "size='%s' is not a known task_class" % size,
                              field="size", value=size)
    provenance = str(req["provenance"]).lower()
    if provenance not in KNOWN_PROVENANCE:
        return None, _refusal("unknown_provenance", "provenance='%s' is not one of %s"
                              % (provenance, "|".join(KNOWN_PROVENANCE)),
                              field="provenance", value=provenance)
    caps = req["required_capabilities"]
    if not isinstance(caps, list) or not caps:
        return None, _refusal("missing_capability",
                              "required_capabilities must be a non-empty list", field="required_capabilities")
    unknown_caps = [c for c in caps if c not in CAPABILITY_VOCABULARY]
    if unknown_caps:
        return None, _refusal("unknown_capability",
                              "capabilities outside the declared vocabulary: %s" % ",".join(map(str, unknown_caps)),
                              field="required_capabilities", value=unknown_caps)
    role = str(req.get("role", "worker")).lower()
    if role not in ROLES:
        return None, _refusal("unknown_role", "role='%s' is not one of %s" % (role, "|".join(ROLES)),
                              field="role", value=role)
    arms = req.get("launchable_arms")
    if arms is not None:
        if not isinstance(arms, list) or not [a for a in arms if str(a).strip()]:
            return None, _refusal("empty_launchable_set",
                                  "launchable_arms was explicitly given but empty: an empty set is a "
                                  "refusal, never permission to widen the pool",
                                  field="launchable_arms", value=arms)
    arbiter_cmd = req.get("arbiter_cmd") or DEFAULT_ARBITER_CMD
    if not isinstance(arbiter_cmd, list) or not all(isinstance(a, str) for a in arbiter_cmd) or not arbiter_cmd:
        return None, _refusal("malformed_field", "arbiter_cmd must be a non-empty argv list of strings",
                              field="arbiter_cmd")
    executor = req["executor"]
    if not isinstance(executor, list) or not all(isinstance(a, str) for a in executor) or not executor:
        return None, _refusal("missing_executor",
                              "executor argv prefix is REQUIRED: the boundary launches nothing "
                              "without a declared transport", field="executor")
    schema = req.get("output_schema")
    if schema is not None:
        if not isinstance(schema, dict):
            return None, _refusal("malformed_field", "output_schema must be a JSON object", field="output_schema")
        bad = _schema_unsupported_keywords(schema)
        if bad:
            return None, _refusal("unsupported_schema_keyword",
                                  "output_schema uses keywords this boundary cannot evaluate: %s "
                                  "(refused, never silently ignored)" % ",".join(sorted(bad)),
                                  field="output_schema", value=sorted(bad))
    return {"step_id": step_id, "round": rnd, "attempt": int(req.get("attempt", 1)),
            "kind": kind, "size": size, "provenance": provenance,
            "role": role, "arms": arms, "arbiter_cmd": arbiter_cmd, "executor": executor,
            "routing_yaml": routing_yaml}, None


def _schema_unsupported_keywords(schema):
    bad = set(k for k in schema if k not in _SCHEMA_KEYWORDS)
    for key in ("properties",):
        for sub in (schema.get(key) or {}).values():
            if isinstance(sub, dict):
                bad |= _schema_unsupported_keywords(sub)
    if isinstance(schema.get("items"), dict):
        bad |= _schema_unsupported_keywords(schema["items"])
    return bad


# ── admission freshness ──────────────────────────────────────────────────────
def _quota_evidence_view(req, now):
    """-> (view, None) | (None, refusal). 60s limit; one bounded refresh at
    most; the refusal NAMES staleness and the shared-snapshot edge."""
    limit = int(req.get("freshness_limit_s", FRESHNESS_LIMIT_S))
    ev = req.get("quota_evidence")
    if not isinstance(ev, dict) or not isinstance(ev.get("sampled_at_epoch"), int):
        return None, _refusal("absent_quota_freshness",
                              "quota/readiness evidence with sampled_at_epoch is REQUIRED: absent "
                              "freshness is never permission to launch (parallel steps can observe "
                              "the SAME free quota; a shared snapshot is not a reservation)",
                              field="quota_evidence")
    refreshed = False
    age = now - ev["sampled_at_epoch"]
    if age > limit:
        refresh_cmd = req.get("quota_refresh_cmd")
        if isinstance(refresh_cmd, list) and refresh_cmd:
            try:
                proc = subprocess.run(refresh_cmd, capture_output=True, text=True, timeout=REFRESH_TIMEOUT_S)
                if proc.returncode == 0:
                    fresh = json.loads(proc.stdout)
                    if isinstance(fresh, dict) and isinstance(fresh.get("sampled_at_epoch"), int) \
                            and now - fresh["sampled_at_epoch"] <= limit:
                        ev, refreshed, age = fresh, True, now - fresh["sampled_at_epoch"]
            except (OSError, ValueError, subprocess.TimeoutExpired):
                pass
        if age > limit:
            return None, _refusal("stale_admission_evidence",
                                  "quota/readiness evidence is STALE: age=%ds exceeds the %ds "
                                  "freshness limit (sampled_at_epoch=%d). Rebuild the evidence or "
                                  "refuse; note the known edge -- parallel steps can observe the "
                                  "same free quota, so a stale snapshot may hide contention the "
                                  "freshness check alone cannot see" % (age, limit, ev["sampled_at_epoch"]),
                                  field="quota_evidence", age_s=age, limit_s=limit,
                                  sampled_at_epoch=ev["sampled_at_epoch"])
    return {"source": str(ev.get("source", "unknown")), "sampled_at_epoch": ev["sampled_at_epoch"],
            "age_s": age, "limit_s": limit, "refreshed": refreshed}, None


# ── arbiter consult (existing CLI, existing line protocol) ───────────────────
def _consult_arbiter(req, ctx):
    """-> (decision, None) | (None, refusal). Calls the UNMODIFIED arbiter CLI
    and parses its current single-line decision protocol."""
    payload = {"work_kind": ctx["kind"], "size": ctx["size"],
               "task": str(req.get("task", "")), "subtype": str(req.get("subtype", ""))}
    if ctx["arms"] is not None:
        payload["launchable_arms"] = ctx["arms"]
    try:
        proc = subprocess.run(ctx["arbiter_cmd"] + [json.dumps(payload)],
                              capture_output=True, text=True, timeout=ARBITER_TIMEOUT_S)
    except FileNotFoundError:
        return None, _refusal("arbiter_unavailable", "arbiter executable not found: %r" % ctx["arbiter_cmd"][0])
    except subprocess.TimeoutExpired:
        return None, _refusal("arbiter_timeout", "arbiter consult exceeded %ds" % ARBITER_TIMEOUT_S)
    except OSError as exc:
        return None, _refusal("arbiter_unavailable", "arbiter consult failed: %s" % exc)
    line = None
    for candidate in (proc.stdout or "").splitlines():
        if candidate.startswith("arm="):
            line = candidate
    if line is None:
        return None, _refusal("arbiter_no_decision",
                              "arbiter produced no decision line (rc=%d): %.300s"
                              % (proc.returncode, (proc.stderr or "").strip()),
                              arbiter_rc=proc.returncode)
    tokens = dict(_DECISION_LINE_RE.findall(line))
    if tokens.get("arm") == "refuse":
        return None, _refusal("arbiter_refused",
                              "arbiter refused the step: reason=%s" % tokens.get("reason", "unparsed"),
                              arbiter_reason=tokens.get("reason"))
    decision = {}
    for field in ("arm", "kind", "model", "tier", "effort"):
        if field not in tokens:
            return None, _refusal("malformed_decision",
                                  "decision line lacks %s=: %.200s" % (field, line), field=field)
        decision[field] = tokens[field]
    decision["reason"] = tokens.get("reason", "unparsed")
    decision["line"] = line
    return decision, None


# ── output schema (declared subset; unsupported keywords refused upstream) ───
def _validate_against_schema(value, schema):
    """-> (True, None) | (False, reason)."""
    stype = schema.get("type")
    if stype is not None:
        py = {"object": dict, "array": list, "string": str, "boolean": bool,
              "number": (int, float), "null": type(None)}.get(stype)
        if py is None:
            return False, "unknown schema type '%s'" % stype
        if not isinstance(value, py) or (stype == "number" and isinstance(value, bool)):
            return False, "expected type %s, got %s" % (stype, type(value).__name__)
    if "enum" in schema and value not in schema["enum"]:
        return False, "value not in enum"
    if isinstance(value, dict):
        for key in schema.get("required") or []:
            if key not in value:
                return False, "missing required property '%s'" % key
        for key, sub in (schema.get("properties") or {}).items():
            if key in value:
                ok, why = _validate_against_schema(value[key], sub)
                if not ok:
                    return False, "%s: %s" % (key, why)
    if isinstance(value, list):
        if len(value) < int(schema.get("minItems", 0)):
            return False, "fewer than minItems entries"
        if isinstance(schema.get("items"), dict):
            for idx, item in enumerate(value):
                ok, why = _validate_against_schema(item, schema["items"])
                if not ok:
                    return False, "[%d]: %s" % (idx, why)
    if isinstance(value, str) and len(value) < int(schema.get("minLength", 0)):
        return False, "shorter than minLength"
    return True, None


# ── the boundary ─────────────────────────────────────────────────────────────
def run_step(request):
    """One workflow step across the whole boundary. ALWAYS returns a receipt
    dict (and appends it to the receipts journal)."""
    started = time.time()
    base = {"schema_version": 1, "boundary": "leadv2-workflow-step/run_step",
            "workflow_run_id": request.get("workflow_run_id") if isinstance(request, dict) else None,
            "launched": False, "refusal": None, "observed": None, "usage": "unknown",
            "schema_validation": None, "raw_result": None, "arbiter": None}

    def refused(ctx_part, refusal, outcome="invalid_output"):
        receipt = dict(base)
        receipt.update(ctx_part)
        receipt.update({"status": "refused", "outcome": outcome, "refusal": refusal,
                        "elapsed_s": round(time.time() - started, 3),
                        "ts": _iso(time.time()), "ts_epoch": int(time.time())})
        receipt["receipt_persisted"] = _write_receipt(receipt)
        return receipt

    ctx, refusal = _validate_request(request)
    ident = {"step_id": (ctx or {}).get("step_id"), "round": (ctx or {}).get("round"),
             "attempt": (ctx or {}).get("attempt")}
    if refusal is not None:
        return refused(ident, refusal)

    now = time.time()
    quota_view, refusal = _quota_evidence_view(request, now)
    if refusal is not None:
        return refused(ident, refusal)

    decision, refusal = _consult_arbiter(request, ctx)
    if refusal is not None:
        return refused(ident, refusal, outcome="transport_failed")

    # decision_id is minted HERE: the arbiter's journal suppresses its own
    # write exceptions, so the boundary's receipt is the durable record.
    decision_id = hashlib.sha256(("%s|%s|%s|%s|%d" % (ctx["step_id"], ctx["round"], ctx["attempt"],
                                                      decision["line"], int(now))).encode()).hexdigest()[:16]
    ident.update({"decision_id": decision_id,
                  "decision": {k: decision[k] for k in ("arm", "kind", "model", "tier", "effort", "reason")},
                  # requested = what the decision asked for, present in EVERY
                  # receipt from here on (refusals included -- a receipt
                  # without the requested pair is not complete)
                  "requested": {k: decision[k] for k in ("arm", "model", "tier", "effort")},
                  "quota_evidence": quota_view})

    # registry verification: exact arm/model/tier/effort, never re-ranked
    invocation = _REGISTRY.resolve_decision(
        decision, {"kind": ctx["kind"], "role": ctx["role"], "task_class": ctx["size"],
                   "routing_yaml": ctx["routing_yaml"]})
    if not invocation.get("ok"):
        # propagate lookup()'s own reason (adapter_argv_not_registered, ...)
        # and its external-adapter scope verbatim -- a refusal a caller
        # cannot tell apart from "no launch path exists" is the A3 defect
        return refused(ident, _refusal("decision_not_launchable",
                                       invocation.get("message") or
                                       "registry refused the decision: %s (field=%s arm=%s) -- "
                                       "never a substituted neighbour"
                                       % (invocation.get("registry_reason") or invocation.get("reason"),
                                          invocation.get("field"), invocation.get("arm", decision["arm"])),
                                       registry_reason=invocation.get("registry_reason") or invocation.get("reason"),
                                       field=invocation.get("field"),
                                       arm=invocation.get("arm", decision["arm"]),
                                       decision_value=invocation.get("decision_value"),
                                       registry_value=invocation.get("registry_value"),
                                       adapter_scope=invocation.get("adapter_scope"),
                                       external_adapter=invocation.get("external_adapter")))

    requested = {"arm": invocation["arm"], "model": invocation["model"],
                 "tier": invocation["tier"], "effort": invocation["effort"]}
    ident["requested"] = requested

    # launch through the declared executor + the VERIFIED argv
    argv = list(ctx["executor"]) + list(invocation["argv"])
    raw_dir = os.path.join(os.path.dirname(_receipt_path()), "step-%s" % decision_id)
    result_path = os.path.join(raw_dir, "result.json")
    try:
        os.makedirs(raw_dir, exist_ok=True)
    except OSError:
        raw_dir, result_path = None, os.path.join(os.path.gettempdir(), "step-%s-result.json" % decision_id)
    env = dict(os.environ)
    env["LEADV2_STEP_RESULT_JSON"] = result_path
    timeout_s = int(request.get("timeout_s", EXECUTOR_TIMEOUT_S_DEFAULT))
    proc = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, cwd=request.get("repo_root") or None, env=env)
    try:
        out, err = proc.communicate(timeout=timeout_s)
        timeout_kill = False
    except subprocess.TimeoutExpired:
        # boundary timeout: TERM, wait, KILL -- a kill from this side is a
        # cancelled step, never a transport failure guess
        proc.terminate()
        try:
            proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
        out, err = "", ""
        timeout_kill = True
    rc = proc.returncode

    raw_path = os.path.join(raw_dir or os.path.dirname(result_path), "raw-output.txt") if raw_dir else None
    raw_view = None
    if raw_path:
        try:
            with open(raw_path, "w") as fh:
                fh.write(out)
            raw_view = {"path": raw_path, "bytes": len(out.encode()),
                        "sha256": hashlib.sha256(out.encode()).hexdigest()[:16]}
        except OSError:
            raw_view = None

    ident.update({"arbiter": {"decision_line": decision["line"]}, "launched": True})

    if timeout_kill or (rc is not None and rc < 0):
        return _finish(ident, base, started, outcome="cancelled",
                       detail=("boundary_timeout" if timeout_kill else "killed_by_signal=%d" % (-rc or 0)))
    if rc == EXECUTOR_TRANSPORT_RC or TRANSPORT_MARKER in (err or ""):
        return _finish(ident, base, started, outcome="transport_failed", detail="transport_named_failure rc=%s" % rc)

    observed, obs_source = {"arm": requested["arm"], "model": requested["model"]}, "argv_pinned"
    exec_report = None
    try:
        with open(result_path) as fh:
            exec_report = json.load(fh)
        if isinstance(exec_report, dict) and exec_report.get("model"):
            observed = {"arm": exec_report.get("arm"), "model": exec_report.get("model")}
            obs_source = "executor_report"
    except (OSError, ValueError):
        pass

    if rc != 0:
        # no verified cause: unknown, NOT a dressed-up transport failure
        receipt = _finish(ident, base, started, outcome="unknown_completion",
                          detail="executor rc=%d stderr=%.200s" % (rc, (err or "").strip()))
        receipt["observed"] = observed if obs_source == "executor_report" else None
        return _persist(receipt)

    if obs_source == "executor_report" and (
            observed.get("arm") != requested["arm"] or observed.get("model") != requested["model"]):
        diverged = "model" if observed.get("model") != requested["model"] else "arm"
        receipt = _finish(ident, base, started, outcome="invalid_output",
                          detail="executor identity diverged from the verified invocation")
        receipt["observed"], receipt["refusal"] = observed, _refusal(
            "executor_identity_divergence",
            "executor reports %r but the verified invocation is arm=%s model=%s -- the launched "
            "thing must be the decided thing" % (observed, requested["arm"], requested["model"]),
            field=diverged, decision_value=requested[diverged], registry_value=observed.get(diverged))
        return _persist(receipt)

    schema = request.get("output_schema")
    if schema is not None:
        try:
            parsed = json.loads(out)
        except ValueError:
            receipt = _finish(ident, base, started, outcome="invalid_output", detail="stdout is not JSON")
            receipt["schema_validation"] = {"schema_id": request.get("schema_id"), "valid": False,
                                            "error": "stdout_not_json"}
            receipt["observed"] = observed
            return _persist(receipt)
        ok, why = _validate_against_schema(parsed, schema)
        if not ok:
            receipt = _finish(ident, base, started, outcome="invalid_output", detail="schema: %s" % why)
            receipt["schema_validation"] = {"schema_id": request.get("schema_id"), "valid": False,
                                            "error": why}
            receipt["observed"] = observed
            return _persist(receipt)

    receipt = _finish(ident, base, started, outcome="ok", detail=None)
    receipt["schema_validation"] = ({"schema_id": request.get("schema_id"), "valid": True, "error": None}
                                    if schema is not None else None)
    receipt["observed"], receipt["observed_source"] = observed, obs_source
    if isinstance(exec_report, dict) and exec_report.get("usage") is not None:
        receipt["usage"] = exec_report["usage"]
    if raw_view:
        receipt["raw_result"] = raw_view
    return _persist(receipt)


def _finish(ident, base, started, outcome, detail):
    receipt = dict(base)
    receipt.update(ident)
    receipt.update({"status": "ok" if outcome == "ok" else "executed",
                    "outcome": outcome, "detail": detail,
                    "elapsed_s": round(time.time() - started, 3),
                    "ts": _iso(time.time()), "ts_epoch": int(time.time())})
    return receipt


def _persist(receipt):
    receipt["receipt_persisted"] = _write_receipt(receipt)
    return receipt


def _main(argv):
    if len(argv) != 3 or argv[1] != "--request":
        sys.stderr.write("usage: leadv2-workflow-step.py --request <path|->\n")
        return 2
    src = argv[2]
    raw = sys.stdin.read() if src == "-" else open(src).read()
    try:
        request = json.loads(raw)
    except ValueError as exc:
        print(json.dumps({"boundary": "leadv2-workflow-step/run_step", "status": "refused",
                          "outcome": "invalid_output", "launched": False,
                          "refusal": {"kind": "malformed_request", "message": str(exc)},
                          "receipt_persisted": False}, sort_keys=True))
        return 1
    print(json.dumps(run_step(request), sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
