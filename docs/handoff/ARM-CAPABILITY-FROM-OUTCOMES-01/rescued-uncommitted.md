# ARM-CAPABILITY-FROM-OUTCOMES-01 — uncommitted work rescued from the checkout

Carried out of `.claude/worktrees/ARM-CAPABILITY-FROM-OUTCOMES-01` on 2026-09-06 by the blocking filter of
LEADV2-WORKTREE-ADJUDICATION-01, **before** any verdict was written about the
branch. A lane's branch can be an empty anchor while the work sits untracked or
merely staged inside its checkout: `git log` never sees the index, and removing
the checkout would take both with it.

Text only — nothing here is installed or made executable. Restoring any of it is
a deliberate act by whoever owns the row.

## `git diff HEAD -- plugins tests` (staged and unstaged)

```diff
diff --git a/plugins/leadv2/config/leadv2-routing.yaml b/plugins/leadv2/config/leadv2-routing.yaml
index 8877a1bc..d975eb74 100644
--- a/plugins/leadv2/config/leadv2-routing.yaml
+++ b/plugins/leadv2/config/leadv2-routing.yaml
@@ -40,6 +40,19 @@ router_v2:
     codex:  { work_pct: 90, review_pct: 95 }
     claude: { work_pct: 95, review_pct: 95 }
 
+  # ARM-CAPABILITY-FROM-OUTCOMES-01: local outcome evidence is an additive
+  # routing signal.  The ledger is authoritative for posterior counts; prior
+  # rows remain visibly vendor-sourced and are never presented as local proof.
+  # `failure_penalty` affects only cells with enough same-shape observations.
+  capability_evidence:
+    minimum_samples: 3
+    half_life_days: 7
+    failure_penalty: 20
+    priors:
+      - { arm: glm-flash, work_kind: code, label: "vendor prior: DeepSWE v1.1 63.4", source: "https://docs.z.ai/guides/llm/glm-5.3-flash" }
+      - { arm: codex, work_kind: code, model_prefix: gpt-5.6, label: "vendor prior: SWE-bench Pro 63.4/64.6 by tier", source: "https://openai.com/index/introducing-gpt-5-6/" }
+      - { arm: freepool, work_kind: code, model_prefix: nvidia_nim/nvidia/nemotron-3-super-120b-a12b, label: "vendor prior: SWE-bench 60.5", source: "https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b" }
+
   # T17 route arbiter capability matrix. This is data, not a second ladder.
   # `cost` is a relative unit used only among capable, uncapped arms.
   #
```

## `plugins/leadv2/scripts/leadv2-arm-capability.sh` (untracked, 6106 bytes)

```
#!/usr/bin/env bash
# leadv2-arm-capability.sh — aggregate outcome evidence by delivered work shape.
#
# The ledger is append-only JSONL.  Each row is sufficient to recompute a table:
# task, arm, concrete model, work_kind, complexity, terminal outcome, and timestamp.
# It deliberately reports counts; `signal` only emits a routing adjustment after the
# configured minimum number of records exists for the exact shape.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_LEDGER="${LEADV2_ARM_CAPABILITY_LEDGER:-${HOME}/.claude/cache/leadv2/arm-capability-ledger.jsonl}"
DEFAULT_ROUTING="${LEADV2_ARM_CAPABILITY_ROUTING_YAML:-${SCRIPT_DIR}/../config/leadv2-routing.yaml}"

usage() {
  cat >&2 <<'EOF'
usage:
  leadv2-arm-capability.sh record --ledger FILE --task ID --arm ARM --model MODEL --work-kind KIND --complexity COMPLEXITY --outcome OUTCOME [--ts ISO]
  leadv2-arm-capability.sh signal --ledger FILE --routing YAML --arm ARM --model MODEL --work-kind KIND --complexity COMPLEXITY
  leadv2-arm-capability.sh table --ledger FILE [--routing YAML]
EOF
}

cmd="${1:-table}"
[[ $# -gt 0 ]] && shift
ledger="${DEFAULT_LEDGER}"; routing="${DEFAULT_ROUTING}"
task=""; arm=""; model=""; work_kind=""; complexity="unknown"; outcome=""; ts=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ledger) ledger="${2:-}"; shift 2 ;;
    --routing) routing="${2:-}"; shift 2 ;;
    --task) task="${2:-}"; shift 2 ;;
    --arm) arm="${2:-}"; shift 2 ;;
    --model) model="${2:-}"; shift 2 ;;
    --work-kind) work_kind="${2:-}"; shift 2 ;;
    --complexity) complexity="${2:-}"; shift 2 ;;
    --outcome) outcome="${2:-}"; shift 2 ;;
    --ts) ts="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

case "${cmd}" in record|signal|table) ;; *) usage; exit 2 ;; esac

case "${cmd}" in
  record)
    [[ -n "${task}" && -n "${arm}" && -n "${model}" && -n "${work_kind}" && -n "${outcome}" ]] || { usage; exit 2; }
    mkdir -p "$(dirname "${ledger}")"
    ARM_CAP_TASK="${task}" ARM_CAP_ARM="${arm}" ARM_CAP_MODEL="${model}" \
    ARM_CAP_KIND="${work_kind}" ARM_CAP_COMPLEXITY="${complexity}" ARM_CAP_OUTCOME="${outcome}" \
    ARM_CAP_TS="${ts}" python3 - "${ledger}" <<'PY'
import datetime, json, os, sys
path=sys.argv[1]
row={
 "task":os.environ["ARM_CAP_TASK"], "arm":os.environ["ARM_CAP_ARM"],
 "model":os.environ["ARM_CAP_MODEL"], "work_kind":os.environ["ARM_CAP_KIND"],
 "complexity":os.environ["ARM_CAP_COMPLEXITY"], "outcome":os.environ["ARM_CAP_OUTCOME"],
 "ts":os.environ.get("ARM_CAP_TS") or datetime.datetime.utcnow().replace(microsecond=0).isoformat()+"Z"
}
with open(path,"a") as f: f.write(json.dumps(row,sort_keys=True,separators=(",",":"))+"\n")
PY
    ;;
  signal|table)
    ARM_CAP_CMD="${cmd}" ARM_CAP_ARM="${arm}" ARM_CAP_MODEL="${model}" \
    ARM_CAP_KIND="${work_kind}" ARM_CAP_COMPLEXITY="${complexity}" \
    python3 - "${ledger}" "${routing}" <<'PY'
import datetime, json, math, os, sys
ledger_path, routing_path=sys.argv[1:3]
cmd=os.environ["ARM_CAP_CMD"]
try:
    import yaml
    cfg=yaml.safe_load(open(routing_path)) or {}
except Exception: cfg={}
evidence=((cfg.get("router_v2") or {}).get("capability_evidence") or {})
minimum=int(evidence.get("minimum_samples",3) or 3)
half_life=float(evidence.get("half_life_days",7) or 7)
penalty=float(evidence.get("failure_penalty",20) or 20)
priors=evidence.get("priors") or []
rows=[]
try:
    with open(ledger_path) as f:
        for line in f:
            try:
                row=json.loads(line)
                if all(row.get(k) not in (None,"") for k in ("task","arm","model","work_kind","complexity","outcome","ts")):
                    rows.append(row)
            except Exception: pass
except IOError: pass
def prior_for(arm, model, kind):
    hits=[]
    for p in priors:
        if not isinstance(p,dict) or p.get("arm")!=arm or p.get("work_kind")!=kind: continue
        prefix=str(p.get("model_prefix") or "")
        if prefix and not model.startswith(prefix): continue
        hits.append(str(p.get("label") or p.get("source") or "published"))
    return ";".join(hits) or "none"
def parse_ts(raw):
    try:return datetime.datetime.fromisoformat(str(raw).replace("Z","+00:00"))
    except Exception:return None
def is_failure(outcome):
    return outcome not in ("landed","completed")
if cmd=="signal":
    arm=os.environ["ARM_CAP_ARM"]; model=os.environ["ARM_CAP_MODEL"]; kind=os.environ["ARM_CAP_KIND"]; complexity=os.environ["ARM_CAP_COMPLEXITY"]
    matched=[r for r in rows if r["arm"]==arm and r["model"]==model and r["work_kind"]==kind and r["complexity"]==complexity]
    attempts=len(matched); failures=sum(1 for r in matched if is_failure(r["outcome"])); successes=attempts-failures
    if attempts<minimum:
        print("status=insufficient attempts=%d successes=%d failures=%d adjustment=0"%(attempts,successes,failures)); raise SystemExit(0)
    now=datetime.datetime.now(datetime.timezone.utc); bad=good=0.0
    for r in matched:
        then=parse_ts(r["ts"])
        age=max(0.0,(now-then).total_seconds()/86400.0) if then and then.tzinfo else 0.0
        weight=math.pow(0.5,age/half_life)
        if is_failure(r["outcome"]): bad+=weight
        else: good+=weight
    adjustment=max(0.0,(bad-good)*penalty)
    print("status=sufficient attempts=%d successes=%d failures=%d adjustment=%.3f"%(attempts,successes,failures,adjustment))
    raise SystemExit(0)
groups={}
for r in rows:
    key=(r["arm"],r["model"],r["work_kind"],r["complexity"])
    groups.setdefault(key,[]).append(r)
print("arm\tmodel\twork_kind\tcomplexity\tattempts\tlanded\tcompleted\tfailures\tprior\ttasks")
for key, rs in sorted(groups.items(), key=lambda kv:(-len(kv[1]),kv[0])):
    outcomes={}
    for r in rs: outcomes[r["outcome"]]=outcomes.get(r["outcome"],0)+1
    failures=sum(v for k,v in outcomes.items() if is_failure(k))
    tasks=",".join(sorted(set(str(r["task"]) for r in rs)))
    print("%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%s\t%s"%(key+(len(rs),outcomes.get("landed",0),outcomes.get("completed",0),failures,prior_for(*key[:3]),tasks)))
PY
    ;;
esac
```

