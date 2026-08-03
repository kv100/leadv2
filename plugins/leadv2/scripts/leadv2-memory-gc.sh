#!/usr/bin/env bash
# SHELL=/bin/bash
# leadv2-memory-gc.sh - Memory GC for leadv2 memory stores.
# Args: --project-root <path>  --apply  --max-age-days N
# Checks: (a) stale paths  (b) duplicates  (c) archive candidates
# Output: docs/leadv2/memory-gc-report.md  docs/leadv2/.memory-gc-last
# Exit: 0=ok 1=fatal. SHELL=/bin/bash required for cron.

set -euo pipefail

# Index mode deliberately dispatches before the legacy argument parser below.
# With no --memory-dir this file continues through the original code verbatim.
if [[ " ${*:-} " == *" --memory-dir "* ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  MEMORY_DIR=""; INDEX_PROJECT_ROOT=""; INDEX_MODEL="${LEADV2_MEMGC_MODEL:-haiku}"
  INDEX_APPLY=0; INDEX_RESTORE=""; INDEX_AUDIT=""; VERDICTS_FILE=""
  INDEX_BYTE_CAP="${LEADV2_MEMGC_BYTE_CAP:-}"; INDEX_LINE_LIMIT="${LEADV2_MEMGC_LINE_LIMIT:-}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --memory-dir) MEMORY_DIR="${2:-}"; shift 2 ;;
      --project-root) INDEX_PROJECT_ROOT="${2:-}"; shift 2 ;;
      --byte-cap) INDEX_BYTE_CAP="${2:-}"; shift 2 ;;
      --line-limit) INDEX_LINE_LIMIT="${2:-}"; shift 2 ;;
      --model) INDEX_MODEL="${2:-}"; shift 2 ;;
      --verdicts-file) VERDICTS_FILE="${2:-}"; shift 2 ;;
      --restore) INDEX_RESTORE="${2:-}"; shift 2 ;;
      --audit) INDEX_AUDIT="${2:-}"; shift 2 ;;
      --apply) INDEX_APPLY=1; shift ;;
      -h|--help) echo "Usage: $0 --memory-dir DIR --project-root PROJECT [--byte-cap BYTES --line-limit N] [--model M] [--apply] [--verdicts-file FILE] [--restore RUN_DIR] [--audit RUN_DIR]"; exit 0 ;;
      *) echo "[leadv2-memory-gc] unknown index-mode arg: $1" >&2; exit 1 ;;
    esac
  done
  [[ -n "$MEMORY_DIR" && -f "$MEMORY_DIR/MEMORY.md" ]] || { echo "[leadv2-memory-gc] --memory-dir must contain MEMORY.md" >&2; exit 1; }
  [[ -n "$INDEX_PROJECT_ROOT" && -d "$INDEX_PROJECT_ROOT" ]] || { echo "[leadv2-memory-gc] --project-root must be an accessible project directory" >&2; exit 1; }
  command -v python3 >/dev/null || { echo "[leadv2-memory-gc] python3 required" >&2; exit 1; }
  INDEX_GC="${SCRIPT_DIR}/leadv2-memory-index-gc.py"
  [[ -f "$INDEX_GC" ]] || { echo "[leadv2-memory-gc] missing $INDEX_GC" >&2; exit 1; }
  exec 9>"$MEMORY_DIR/.memory-gc.lock"
  flock -n 9 || { echo "[leadv2-memory-gc] index GC busy: $MEMORY_DIR" >&2; exit 4; }
  if [[ -n "$INDEX_RESTORE" ]]; then
    python3 "$INDEX_GC" restore --memory-dir "$MEMORY_DIR" --run-dir "$INDEX_RESTORE"
    exit $?
  fi
  if [[ -n "$INDEX_AUDIT" ]]; then
    python3 "$INDEX_GC" audit --run-dir "$INDEX_AUDIT" --project-root "$INDEX_PROJECT_ROOT"
    exit $?
  fi
  PLAN="$(mktemp "${TMPDIR:-/tmp}/leadv2-memory-gc.XXXXXX.json")"
  trap 'rm -f "$PLAN"' EXIT
  PREPARE=(prepare --memory-dir "$MEMORY_DIR" --project-root "$INDEX_PROJECT_ROOT" --plan "$PLAN")
  if [[ -n "$INDEX_BYTE_CAP" || -n "$INDEX_LINE_LIMIT" ]]; then
    PREPARE+=(--byte-cap "$INDEX_BYTE_CAP" --line-limit "$INDEX_LINE_LIMIT")
  fi
  python3 "$INDEX_GC" "${PREPARE[@]}" > /dev/null
  if [[ -s "$PLAN" ]] && [[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("early_exit", False))' "$PLAN")" == "True" ]]; then
    python3 "$INDEX_GC" finalize --plan "$PLAN" --memory-dir "$MEMORY_DIR" --model "$INDEX_MODEL"
    exit 0
  fi
  ARGS=(finalize --plan "$PLAN" --memory-dir "$MEMORY_DIR" --model "$INDEX_MODEL")
  [[ -n "$VERDICTS_FILE" ]] && ARGS+=(--verdicts-file "$VERDICTS_FILE")
  [[ "$INDEX_APPLY" == 1 ]] && ARGS+=(--apply)
  python3 "$INDEX_GC" "${ARGS[@]}"
  exit $?
fi

log()      { printf -- '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }
log_info() { log "INFO:  $*"; }
log_error(){ log "ERROR: $*"; }

PROJECT_ROOT="${PWD}"
APPLY=0
MAX_AGE_DAYS=90

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --apply)        APPLY=1;           shift   ;;
    --max-age-days) MAX_AGE_DAYS="$2"; shift 2 ;;
    -h|--help) printf -- 'Usage: %s [--project-root <path>] [--apply] [--max-age-days N]\n' "$(basename "$0")" >&2; exit 0 ;;
    *) log_error "Unknown arg: $1"; exit 1 ;;
  esac
done

PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)" || { log_error "project-root not accessible"; exit 1; }
command -v python3 &>/dev/null || { log_error "python3 required"; exit 1; }

LEADV2_DIR="${PROJECT_ROOT}/docs/leadv2"
REPORT_FILE="${LEADV2_DIR}/memory-gc-report.md"
STAMP_FILE="${LEADV2_DIR}/.memory-gc-last"
ARCHIVE_FILE="${LEADV2_DIR}/memory-gc-archive.yaml"
mkdir -p "$LEADV2_DIR"

log_info "Memory GC starting (project-root=${PROJECT_ROOT} apply=${APPLY} max-age-days=${MAX_AGE_DAYS})"

# ── copy bundled python scripts from plugin dir ────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GC_LOGIC="${SCRIPT_DIR}/leadv2-memory-gc-logic.py"
GC_RENDER="${SCRIPT_DIR}/leadv2-memory-gc-render.py"

if [[ ! -f "$GC_LOGIC" || ! -f "$GC_RENDER" ]]; then
  log_error "Missing bundled python helpers: $GC_LOGIC / $GC_RENDER"
  exit 1
fi

# ── run GC logic ─────────────────────────────────────────────────────────────
GC_OUTPUT="$(
  IMMUNE_FILE="${PROJECT_ROOT}/docs/leadv2/immune-patterns.yaml" \
  NM_FILE="${PROJECT_ROOT}/docs/leadv2-negative-memory.yaml" \
  PRIORS_FILE="${PROJECT_ROOT}/docs/leadv2-priors.yaml" \
  PATTERNS_MD="${PROJECT_ROOT}/.claude/ref/lead-patterns.md" \
  PROJECT_ROOT="$PROJECT_ROOT" \
  APPLY="$APPLY" \
  MAX_AGE_DAYS="$MAX_AGE_DAYS" \
  ARCHIVE_FILE="$ARCHIVE_FILE" \
  python3 "$GC_LOGIC"
)"

# ── parse counts ─────────────────────────────────────────────────────────────
COUNT_STALE=$(printf -- '%s' "$GC_OUTPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["counts"]["stale"])' 2>/dev/null || printf -- '?')
COUNT_DUPES=$(printf -- '%s' "$GC_OUTPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["counts"]["duplicates"])' 2>/dev/null || printf -- '?')
COUNT_ARCH=$(printf -- '%s' "$GC_OUTPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["counts"]["archive"])' 2>/dev/null || printf -- '?')
log_info "Counts — stale:${COUNT_STALE} duplicates:${COUNT_DUPES} archive-candidates:${COUNT_ARCH}"

# ── write report ─────────────────────────────────────────────────────────────
REPORT_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
APPLY_NOTE="report-only"
[[ "$APPLY" == "1" ]] && APPLY_NOTE="--apply (dedupes written; stale+archive-candidates are report-only)"

GC_OUTPUT_ESC="$GC_OUTPUT" \
REPORT_TS="$REPORT_TS" \
APPLY_NOTE="$APPLY_NOTE" \
PR_LABEL="$PROJECT_ROOT" \
MA_LABEL="$MAX_AGE_DAYS" \
COUNT_STALE="$COUNT_STALE" \
COUNT_DUPES="$COUNT_DUPES" \
COUNT_ARCH="$COUNT_ARCH" \
python3 "$GC_RENDER" > "$REPORT_FILE"

log_info "Report written to ${REPORT_FILE}"
date +%s > "$STAMP_FILE" 2>/dev/null || true
log_info "Memory GC complete."
exit 0
