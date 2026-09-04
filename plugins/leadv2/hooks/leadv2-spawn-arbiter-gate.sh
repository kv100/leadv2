#!/usr/bin/env bash
# PreToolUse(Agent) ENFORCING gate: every agent spawn must pass through the
# route arbiter. FOUNDER DECISION 2026-09-04 (ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01):
# "во всех репо где есть плагин лида агенты спавнились через диспатч и арбитра, все".
#
# The predicate is the ABSENCE OF A RECORDED DECISION, deliberately not a name
# list: no subtype, model, provider or arm name is enumerated anywhere below.
# A spawn passes only when the arbiter has recorded a fresh, non-refused
# decision bound to this spawn's subagent_type (and to its model, when the
# spawn pins one). Everything else is denied with the way forward in the text.
#
# The arbiter only DECIDES and RECORDS (sub-second, in-process semantics); it
# does not create worktrees/registries/gates. Lane work keeps going through
# leadv2-dispatch-code.sh, which consults the same arbiter internally.
#
# Kill switch: LEADV2_ROUTE_ENFORCE=0 disables this gate entirely (the name is
# printed in every refusal). Infrastructure faults (corrupt journal, missing
# python3) fail OPEN with a stderr note -- a broken gate must never wedge all
# spawns in every consumer repo; a CLEAN absence of a decision is a deny.
set -euo pipefail
trap 'echo "[$(basename "$0")] error at line $LINENO" >&2; exit 0' ERR

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")"
[[ "$TOOL_NAME" != "Agent" ]] && exit 0

# The single decision-emission site. The negative control for this gate lives
# here: flipping this call's decision literal must flip the gate's observable
# behaviour, or the guard is inert.
emit_decision() {
  local decision="$1" text="$2"
  python3 - "$decision" "$text" <<'PY'
import json,sys
decision,text=sys.argv[1],sys.argv[2]
key='additionalContext' if decision=='allow' else 'permissionDecisionReason'
print(json.dumps({'hookSpecificOutput':{'hookEventName':'PreToolUse','permissionDecision':decision,key:text}}))
PY
}

# Hook-side context for the way-forward paths: resolve through symlink chains
# so the same bytes work from the repo tree and the installed plugin cache.
SELF="${BASH_SOURCE[0]}"
while [[ -h "$SELF" ]]; do
  _dir="$(cd -P "$(dirname "$SELF")" && pwd)"; _link="$(readlink "$SELF")"
  [[ "$_link" == /* ]] || _link="$_dir/$_link"; SELF="$_link"
done
HOOK_DIR="$(cd -P "$(dirname "$SELF")" && pwd)"
PLUGIN_ROOT="$(cd "$HOOK_DIR/.." && pwd)"
ARBITER_CLI="$PLUGIN_ROOT/scripts/lib/leadv2-route-arbiter.sh"
DISPATCHER="$PLUGIN_ROOT/scripts/leadv2-dispatch-code.sh"

# Kill switch FIRST: one env var, named in every refusal text below.
if [[ "${LEADV2_ROUTE_ENFORCE:-1}" == "0" ]]; then
  emit_decision "allow" "[leadv2-spawn-arbiter-gate] enforcement disabled (LEADV2_ROUTE_ENFORCE=0) -- spawn allowed without an arbiter decision."
  exit 0
fi

SUBTYPE="$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")"
MODEL="$(echo "$INPUT" | jq -r '.tool_input.model // empty' 2>/dev/null || echo "")"

# Decision lookup. A record satisfies the gate iff:
#   arm is a real decision (not refuse/empty), subtype matches the spawn's
#   subagent_type exactly (a record with no subtype binds nothing), the record
#   is fresher than the TTL, and -- when the spawn pins a model -- the DECIDED
#   model equals it (model_requested is provenance only and never matches).
LOOKUP="$(SUBTYPE="$SUBTYPE" MODEL="$MODEL" \
JOURNAL="${LEADV2_ROUTE_ARBITER_DECISIONS_FILE:-${TMPDIR:-/tmp}/leadv2-route-arbiter-decisions.jsonl}" \
TTL="${LEADV2_ROUTE_DECISION_TTL:-900}" \
python3 - <<'PY'
import json, os, sys, time
subtype, model = os.environ['SUBTYPE'], os.environ['MODEL']
journal, ttl = os.environ['JOURNAL'], float(os.environ['TTL'])
if not subtype or not os.path.isfile(journal):
    print(''); sys.exit(0)
now = time.time()
hit = ''
try:
    with open(journal) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except ValueError:
                continue  # one torn line must not fail-open the gate
            arm = str(r.get('arm') or '')
            if arm in ('', 'refuse'):
                continue
            if str(r.get('subtype') or '') != subtype:
                continue
            if now - float(r.get('ts_epoch') or 0) > ttl:
                continue
            if model and str(r.get('model') or '') != model:
                continue
            hit = json.dumps(r)
except OSError:
    pass  # unreadable journal -> fail open (stderr note printed by caller)
print(hit)
PY
)" || LOOKUP=""

if [[ -z "$LOOKUP" ]]; then
  # Distinguish clean absence (deny) from infrastructure fault (fail open):
  # the python above prints '' for BOTH, so re-test readability cheaply.
  JOURNAL_PATH="${LEADV2_ROUTE_ARBITER_DECISIONS_FILE:-${TMPDIR:-/tmp}/leadv2-route-arbiter-decisions.jsonl}"
  if [[ -f "$JOURNAL_PATH" && ! -r "$JOURNAL_PATH" ]]; then
    echo "[leadv2-spawn-arbiter-gate] journal unreadable ($JOURNAL_PATH) -- failing OPEN this spawn" >&2
    exit 0
  fi

  # set -e hazard: a `$( [[ cond ]] && cmd )` substitution whose condition is
  # false returns rc=1 and kills the hook via the assignment (caught live by
  # acceptance case 3 -- the model-less spawn). An `if` block is exempt.
  MODEL_PART=""
  if [[ -n "$MODEL" ]]; then MODEL_PART=" model=$MODEL"; fi
  DENY="[leadv2-spawn-arbiter-gate] DENIED: no route-arbiter decision is on record for this spawn (subagent_type=${SUBTYPE:-<none>}${MODEL_PART}). FOUNDER 2026-09-04: every agent spawn goes through the arbiter."
  if [[ -f "$ARBITER_CLI" ]]; then
    DENY="$DENY
Way forward (plain spawn): consult the arbiter, then re-issue this spawn with the decided model (or no model):
  bash $ARBITER_CLI worker '{\"work_kind\":\"build|recon|review|plan\",\"size\":\"standard\",\"subtype\":\"$SUBTYPE\",\"task\":\"one line\"}'"
  fi
  if [[ -f "$DISPATCHER" ]]; then
    DENY="$DENY
Way forward (lane work: worktree + registry + gates): route through the dispatcher instead of a bare Agent spawn:
  bash $DISPATCHER --help"
  fi
  if [[ ! -f "$ARBITER_CLI" && ! -f "$DISPATCHER" ]]; then
    DENY="$DENY
Way forward: this hook is installed without its plugin scripts -- re-install the leadv2 plugin (both consult and dispatch paths are missing)."
  fi
  DENY="$DENY
Kill switch: export LEADV2_ROUTE_ENFORCE=0 disables this gate (founder-level escape hatch, one step, no file edit)."
  emit_decision "deny" "$DENY"
  exit 0
fi

# Consulted: allow, and surface the recorded decision so it is readable back
# from the spawn's own context, not only from the journal file.
CTX="$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); print("[leadv2-spawn-arbiter-gate] arbiter decision on record: kind=%s arm=%s model=%s tier=%s reason=%s recorded=%s -- spawn honours this decision." % (r["work_kind"],r["arm"],r["model"],r["tier"],r["reason"],r["ts"]))' "$LOOKUP")"
emit_decision "allow" "$CTX"
exit 0
