#!/usr/bin/env bash
# leadv2-admission-class.sh — PHASE-DISCIPLINE-01 D1/D2 shared admission helpers.
#
# Sourced (never executed) by leadv2-dispatch-code.sh and
# leadv2-backlog-pump.sh. Owns exactly three things so the two call sites can
# never drift apart:
#   1. the deterministic TaskEstimate -> task-class map (D1);
#   2. the admission receipt read/write (D2) — task id + mission digest bound;
#   3. the FREEPOOL_ROLE projection off work_kind (D6).
#
# D1 map (deterministic, no model call in THIS file — the estimate itself
# comes from leadv2-task-judge.sh, haiku + code-only fallback + sig8 cache):
#   complexity trivial|simple            -> Light
#   complexity standard                   -> Standard
#   complexity complex
#     OR risk_class=safety_publish_payments
#     OR subsystems_touched>=4            -> Heavy
# An explicit --task-class flag wins but may only be ESCALATED by risk
# signals (never de-escalated). Classifier failure is the CALLER's branch:
# Standard/phases, source=classifier_error — this map never fails open.
#
# Bash 3.2 safe: no mapfile, no ${var^^}, no declare -A, no associative traps.
_admission_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
source "${_admission_lib_dir}/leadv2-lane-guard.sh"

# Same normalization pipeline as leadv2-dispatch-code.sh's compute_sig — one
# source of truth for the mission digest so a receipt minted by the pump is
# byte-comparable with one minted at the dispatch door.
leadv2_admission_sig() {  # stdin: mission text -> stdout: sha256 hex
  tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' | shasum -a 256 | awk '{print $1}'
}

leadv2_admission_map_class() {  # <estimate-json> -> stdout: Light|Standard|Heavy (empty on parse failure)
  python3 -c '
import json, sys
try:
    e = json.loads(sys.argv[1])
    complexity = e.get("complexity", "")
    risk = e.get("risk_class", "")
    try:
        subs = int(e.get("subsystems_touched", 0))
    except (TypeError, ValueError):
        subs = 0
except Exception:
    sys.exit(1)
if complexity == "complex" or risk == "safety_publish_payments" or subs >= 4:
    print("Heavy")
elif complexity == "standard":
    print("Standard")
elif complexity in ("trivial", "simple"):
    print("Light")
else:
    sys.exit(1)
' "$1" 2>/dev/null
}

# <explicit-class> <flagged 0|1> <estimate-json> -> stdout: "class<TAB>source"
# source: flag (explicit flag decided), judge|fallback (estimate_source won),
# or empty stdout on unparseable estimate (caller takes classifier_error).
leadv2_admission_class() {
  local explicit="$1" flagged="$2" estimate="$3" mapped src
  mapped="$(leadv2_admission_map_class "$estimate")"
  [[ -n "$mapped" ]] || { printf ''; return 0; }
  src="$(printf '%s' "$estimate" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("estimate_source",""))' 2>/dev/null)"
  [[ "$src" == "judge" || "$src" == "fallback" ]] || src="fallback"
  if [[ "$flagged" == "1" && -n "$explicit" ]]; then
    # Escalate-only: the flag wins unless the estimate's risk/complexity
    # signals rank ABOVE it (Light<Standard<Heavy<Strategic).
    local rank_explicit rank_mapped
    rank_explicit="$(_lv2_class_rank "$explicit")"
    rank_mapped="$(_lv2_class_rank "$mapped")"
    if (( rank_mapped > rank_explicit )); then
      printf '%s\t%s\n' "$mapped" "$src"
    else
      printf '%s\t%s\n' "$explicit" "flag"
    fi
    return 0
  fi
  printf '%s\t%s\n' "$mapped" "$src"
}

# D6: FREEPOOL_ROLE projection off TaskEstimate.work_kind. review->review,
# build/diagnose->implement, docs->bulk. Anything else (including empty)
# returns empty so the caller exports nothing and freepool-coder.sh's own
# narrow direct-invocation fallback applies.
leadv2_admission_freepool_role() {  # <work_kind> -> stdout: review|implement|bulk|"" (never errors)
  case "$1" in
    review)                    printf 'review' ;;
    build|diagnose)            printf 'implement' ;;
    docs)                      printf 'bulk' ;;
    *)                         printf '' ;;
  esac
  return 0
}

# ── admission receipt (D2) ───────────────────────────────────────────────────
# Flat single-level YAML, same parse contract as leadv2-phase-record.sh's
# records. Path: <root>/docs/handoff/dispatch-<sig8>/admission-receipt.yaml.
leadv2_admission_receipt_path() {  # <root> <sig8>
  printf '%s/docs/handoff/dispatch-%s/admission-receipt.yaml' "$1" "$2"
}

leadv2_admission_task_receipt_path() { printf '%s/docs/handoff/%s/task-class.yaml' "$1" "$2"; }
leadv2_admission_read_task_receipt() { # <root> <task-id> -> class
  local f; f="$(leadv2_admission_task_receipt_path "$1" "$2")"
  [[ -f "$f" ]] || return 1
  sed -n 's/^task_class:[[:space:]]*//p' "$f" | head -1
}

# -> stdout: "class<TAB>route<TAB>source<TAB>work_kind<TAB>digest<TAB>task_id", empty if absent/corrupt
leadv2_admission_read_receipt() {  # <root> <sig8>
  local f
  f="$(leadv2_admission_receipt_path "$1" "$2")"
  [[ -f "$f" ]] || { printf ''; return 0; }
  python3 -c '
import sys
def flat(path):
    d = {}
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if ":" not in line or line.startswith((" ", "#")):
            continue
        k, v = line.split(":", 1)
        d[k.strip()] = v.strip()
    return d
d = flat(sys.argv[1])
keys = ("task_class", "route", "source", "work_kind", "mission_digest", "task_id")
if not all(d.get(k) for k in keys):
    sys.exit(1)
print("\t".join(d[k] for k in keys))
' "$f" 2>/dev/null || printf ''
}

# Find the unique receipt for a founder task. A full-cycle build re-entry does
# not reuse the intake mission text, so this is the canonical task->intake
# digest join used by both Gate 1 and dispatch-code's phase guard.
leadv2_admission_find_receipt_for_task() {  # <root> <task_id>
  local root="$1" task_id="$2"
  python3 - "$root" "$task_id" <<'PY' 2>/dev/null
import glob, os, re, sys
root, task_id = sys.argv[1:]
rows = []
for path in glob.glob(os.path.join(root, "docs", "handoff", "dispatch-*", "admission-receipt.yaml")):
    d = {}
    try:
        for line in open(path, encoding="utf-8"):
            if ":" in line and not line.startswith((" ", "#")):
                k, v = line.rstrip("\n").split(":", 1)
                d[k.strip()] = v.strip()
    except OSError:
        continue
    digest = d.get("mission_digest", "")
    sig8 = os.path.basename(os.path.dirname(path)).replace("dispatch-", "", 1)
    if (d.get("task_id") == task_id and re.fullmatch(r"[0-9a-f]{64}", digest)
            and sig8 == digest[:8]
            and all(d.get(k) for k in ("task_class", "route", "source", "work_kind"))):
        rows.append((sig8, d["task_class"], d["route"], d["source"], d["work_kind"], digest, d["task_id"]))
if len(rows) != 1:
    sys.exit(1)
print("\t".join(rows[0]))
PY
}

# Writes the receipt atomically (tmp+mv). Existing receipt is NEVER
# overwritten (once per intake: a re-dispatch reads, not re-mints).
# rc 0 written or already present; rc 1 write failed.
leadv2_admission_write_receipt() {  # <root> <sig8> <task_id> <digest> <class> <route> <source> <work_kind>
  local root="$1" sig8="$2" task_id="$3" digest="$4" cls="$5" route="$6" src="$7" wk="$8"
  local f dir tmp
  f="$(leadv2_admission_receipt_path "$root" "$sig8")"
  [[ -f "$f" ]] && return 0
  dir="$(dirname "$f")"
  mkdir -p "$dir" 2>/dev/null || return 1
  tmp="${dir}/.admission.$$.tmp"
  {
    printf 'receipt_v: 1\n'
    printf 'task_id: %s\n' "$task_id"
    printf 'mission_digest: %s\n' "$digest"
    printf 'task_class: %s\n' "$cls"
    printf 'route: %s\n' "$route"
    printf 'source: %s\n' "$src"
    printf 'work_kind: %s\n' "$wk"
    printf 'recorded_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  if [[ -n "${task_id}" ]]; then
    local tf tdir ttmp
    tf="$(leadv2_admission_task_receipt_path "$root" "$task_id")"; tdir="$(dirname "$tf")"
    mkdir -p "$tdir" 2>/dev/null || return 1
    ttmp="${tdir}/.task-class.$$.tmp"
    { printf 'task_id: %s\n' "$task_id"; printf 'task_class: %s\n' "$cls"; printf 'source: %s\n' "$src"; } > "$ttmp" && mv -f "$ttmp" "$tf" || { rm -f "$ttmp"; return 1; }
  fi
  return 0
}
