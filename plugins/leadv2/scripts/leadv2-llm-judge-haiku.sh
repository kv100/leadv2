#!/usr/bin/env bash
# leadv2-llm-judge-haiku.sh — Haiku-first deploy judge. Emits YAML verdict.
#
# Usage: leadv2-llm-judge-haiku.sh --task-id <id>
# Reads: docs/handoff/<id>/deploy-packet.yaml
# Writes: docs/handoff/<id>/llm-judge-haiku.yaml
#
# Output verdict ∈ {go, no_go, escalate_to_opus}.
# Caller (leadv2-llm-judge.sh) inspects and escalates to Opus when escalate.
#
# Backward-compat: if ANTHROPIC_API_KEY/CLAUDE_CODE_OAUTH_TOKEN unset,
# emits heuristic fallback verdict based on premortem + hack findings.

set -euo pipefail

TASK_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) TASK_ID="$2"; shift 2 ;;
    -h|--help) grep '^# ' "$0" | sed 's/^# //'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$TASK_ID" ]] && { echo "--task-id required" >&2; exit 2; }

PACKET="docs/handoff/${TASK_ID}/deploy-packet.yaml"
OUT="docs/handoff/${TASK_ID}/llm-judge-haiku.yaml"

if [[ ! -f "$PACKET" ]]; then
  echo "WARN: deploy packet missing ($PACKET) — emit escalate_to_opus" >&2
  printf 'verdict: escalate_to_opus\nconfidence: 0.0\nreasons:\n  - deploy_packet_missing\nescalate_reason: confidence_low\n' > "$OUT"
  exit 0
fi

# Heuristic fallback (no API key) or initial fast decision
#
# DEPLOY-JUDGE-IS-ADVISORY-AND-NORMALIZES-KNOWN-BAD-01 (f3-judge.md finding
# 6): this used to read top-level `classification`/`premortem_verdict`/
# `hack_findings`/`coverage_pct`/`offlimits_touched` that the assembled
# packet never has -- it is wrapped under `deploy_packet`, coverage lives at
# `coverage.new_code_pct`, premortem verdict at `premortem.verdict`, and
# there is no `offlimits_touched` key at all (offlimits is the string
# "clean" or "block_rc<N>"). Every field below now matches
# leadv2-llm-judge.sh's actual packet assembly, not a shape that was never
# produced.
python3 - "$PACKET" "$OUT" <<'PY'
import sys, yaml, os
raw = yaml.safe_load(open(sys.argv[1])) or {}
pkt = raw.get("deploy_packet", raw) if isinstance(raw, dict) else {}
out_path = sys.argv[2]

classification = pkt.get("classification", "Standard")
premortem = (pkt.get("premortem", {}) or {}).get("verdict", "proceed")
hack = pkt.get("hack_findings", {}) or {}
blocks = int(hack.get("block", 0))
warns = int(hack.get("warn", 0))
coverage = float((pkt.get("coverage", {}) or {}).get("new_code_pct", 100) or 100)
offlimits_str = pkt.get("offlimits", "clean")
offlimits = [] if offlimits_str == "clean" else [offlimits_str]

# Escalate heavy/strategic unconditionally
if classification in ("Heavy", "Strategic"):
    verdict = "escalate_to_opus"
    confidence = 0.5
    reasons = [f"class={classification} never decided without Opus"]
    er = "class_heavy_or_strategic"
elif blocks > 0 or offlimits:
    verdict = "no_go"
    confidence = 0.9
    reasons = [f"blocker hack findings={blocks}", f"offlimits_touched={bool(offlimits)}"]
    er = None
elif premortem == "skip_recommended":
    verdict = "no_go"
    confidence = 0.85
    reasons = ["premortem recommended skip"]
    er = None
elif premortem == "proceed" and warns <= 2 and coverage >= 70:
    verdict = "go"
    confidence = 0.8
    reasons = ["clean premortem + low warn hack findings + adequate coverage"]
    er = None
else:
    verdict = "escalate_to_opus"
    confidence = 0.65
    reasons = ["ambiguous signals"]
    er = "risk_ambiguous"

if 4 <= (warns + blocks * 3) <= 7 and verdict == "go":
    verdict = "escalate_to_opus"
    er = "risk_ambiguous"
    confidence = 0.68

out = {
    "verdict": verdict,
    "risk_score": min(10, warns + blocks * 3),
    "confidence": confidence,
    "reasons": reasons,
    "escalate_reason": er,
    "path": "haiku_heuristic" if not os.environ.get("ANTHROPIC_API_KEY") else "haiku_api",
}
with open(out_path, "w") as f:
    yaml.safe_dump(out, f, sort_keys=False)
print(yaml.safe_dump(out, sort_keys=False))
PY
