#!/usr/bin/env bash
# leadv2-phase-record.sh — the ONE writer + sole phases.d reader + assert.
#
# PHASES-ARE-THE-ONLY-PATH-01: no work reaches a worker outside the phase pipeline,
# and the phase a lane is in is a fact that one script writes and everything else reads.
#
# This script is the single source of truth for phase records:
#   docs/handoff/dispatch-<sig8>/phases.d/<phase>.yaml
#
# Schema (flat, single-level, no nesting — parsed by flat_yaml()):
#   phase: <id>
#   status: running|done|n/a|waived
#   owner: <script:function>
#   handle: <worker handle>
#   artifact: <repo-relative path>
#   artifact_sha256: <hex digest>
#   started_at: <ISO-8601>
#   ended_at: <ISO-8601 or "">
#   reason: <text or "">
#
# Usage:
#   leadv2-phase-record.sh record <sig8> <phase> [flags]
#       --artifact <path>           required unless --status running|n/a|waived
#       --status running|done|n/a|waived   default: done
#       --handle <worker handle>    required when --status running
#       --reason <text>             required when --status n/a|waived
#       --task-id <founder task id> for the active.yaml mirror
#       --owner <script:function>   default: $(basename "$0")
#
#   leadv2-phase-record.sh assert <sig8> --class <Trivial|Light|Standard|Heavy>
#       [--waiver <phase>=<reason>]...
#       [--writes <csv>]
#
#   leadv2-phase-record.sh show <sig8>
#   leadv2-phase-record.sh plan-for --class <C>
#
# Exit codes:
#   0  ok / all mandatory phases satisfied
#   3  one or more mandatory phases missing or unproven (stdout: missing=<csv>)
#   4  usage error, malformed phases.yaml, refused waiver (stderr: error text)
set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── project root resolution ──────────────────────────────────────────────────
PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CACHE_BASE="${LEADV2_DISPATCH_CACHE_DIR:-${HOME}/.claude/cache}"
PHASES_DIR_BASE="${PROJECT_ROOT}/docs/handoff"
PHASES_YAML="${PROJECT_ROOT}/.claude/leadv2-overrides/phases.yaml"
JOURNAL_BIN="${LEADV2_JOURNAL_BIN:-${SCRIPT_DIR}/leadv2-journal.sh}"
ACTIVE_REGISTRY="${SCRIPT_DIR}/leadv2-active-registry.sh"

_log() { printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2; }
_log_err() { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; }

_emit() {
  [[ -x "$JOURNAL_BIN" || -f "$JOURNAL_BIN" ]] || return 0
  LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" bash "$JOURNAL_BIN" "$1" "$2" >/dev/null 2>&1 || true
}

_now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

_sha256() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

# ── phases.d path helpers ────────────────────────────────────────────────────
_phases_d() { printf '%s/dispatch-%s/phases.d' "$PHASES_DIR_BASE" "$1"; }
_phase_file() { printf '%s/%s.yaml' "$(_phases_d "$1")" "$2"; }

# ── class → phase table (§4) ─────────────────────────────────────────────────
# Returns mandatory/optional/conditional for a class+phase.
# M=mandatory, O=optional, C=conditional, -=not in subset
_phase_class_level() {
  local cls="$1" phase="$2"
  case "$phase" in
    classify) printf 'M' ;;
    diverge)
      case "$cls" in Heavy) printf 'M' ;; Standard) printf 'O' ;; *) printf '-' ;; esac
      ;;
    plan)
      case "$cls" in Trivial) printf '-' ;; Light) printf 'O' ;; *) printf 'M' ;; esac
      ;;
    gate1)
      case "$cls" in Trivial|Light) printf '-' ;; *) printf 'M' ;; esac
      ;;
    build) printf 'M' ;;
    test)
      case "$cls" in
        Trivial) printf 'C' ;;
        *) printf 'M' ;;
      esac
      ;;
    review) printf 'M' ;;
    deploy) printf 'C' ;;
    live_verify)
      case "$cls" in Trivial) printf '-' ;; Light) printf 'C' ;; *) printf 'M' ;; esac
      ;;
    e2e)
      case "$cls" in Trivial|Light) printf '-' ;; Standard) printf 'C' ;; Heavy) printf 'M' ;; esac
      ;;
    close) printf 'M' ;;
    *) printf '-' ;;
  esac
}

# Derived conditions: returns "mandatory" "n/a:<reason>" or "optional"
_phase_derived() {
  local cls="$1" phase="$2" writes="${3:-}" deploy_done="${4:-}"
  local level
  level="$(_phase_class_level "$cls" "$phase")"

  case "$level" in
    M) printf 'mandatory' ;;
    O) printf 'optional' ;;
    C)
      case "$phase" in
        test)
          # Trivial: mandatory iff --writes matches stack.yaml source globs, else n/a
          if [[ "$cls" == "Trivial" ]]; then
            # Simplified: if writes is non-empty and contains .py/.ts/.js/.go/.rs/.swift, mandatory
            if [[ -n "$writes" ]] && printf '%s' "$writes" | grep -qiE '\.(py|ts|js|go|rs|swift|rb|java|kt|c|cpp|h)$'; then
              printf 'mandatory'
            else
              printf 'n/a:docs_only'
            fi
          else
            printf 'mandatory'
          fi
          ;;
        deploy)
          # All classes: mandatory iff diff touches a runtime path per stack.yaml, else n/a
          if [[ -n "$writes" ]] && ! printf '%s' "$writes" | grep -qiE '\.(md|txt|yaml|json|yml|csv)$'; then
            printf 'mandatory'
          else
            printf 'n/a:no_runtime_surface'
          fi
          ;;
        live_verify)
          # Light: mandatory iff deploy recorded done
          if [[ "$deploy_done" == "done" ]]; then
            printf 'mandatory'
          else
            printf 'n/a:no_deploy'
          fi
          ;;
        e2e)
          # Standard: mandatory iff deploy recorded done
          if [[ "$deploy_done" == "done" ]]; then
            printf 'mandatory'
          else
            printf 'n/a:no_deploy'
          fi
          ;;
        *) printf 'mandatory' ;;
      esac
      ;;
    -) printf 'excluded' ;;
  esac
}

# ── phases.yaml override reader (embedded python) ────────────────────────────
# Parses .claude/leadv2-overrides/phases.yaml, returning a JSON object.
# Union semantics for mandatory, strict validation. Exit 4 on any error.
_read_phases_yaml() {
  local pyfile="$PHASES_YAML"
  if [[ ! -f "$pyfile" ]]; then
    printf '{"version":1,"class_overrides":{},"waivers_allowed":[],"steps":{}}'
    return 0
  fi
  python3 - "$pyfile" <<'PYEOF'
import json, sys, os
try:
    import yaml
except ImportError:
    print("phases.yaml: PyYAML required but not found", file=sys.stderr)
    sys.exit(4)

path = sys.argv[1]
try:
    with open(path) as f:
        data = yaml.safe_load(f) or {}
except Exception as e:
    print(f"phases.yaml: parse error: {e}", file=sys.stderr)
    sys.exit(4)

KNOWN_PHASES = {"classify","diverge","plan","gate1","build","test","review",
                "deploy","live_verify","e2e","close"}
KNOWN_CLASSES = {"Trivial","Light","Standard","Heavy"}
KNOWN_HOOKS = {"plan.post","gate1.main","build.post","review.pre","review.post",
               "deploy.main","deploy.post","verify.main","e2e.main","close.pre"}
REMOVAL_KEYS = {"remove","exclude","skip","optional","drop"}

version = data.get("version", 1)
if version != 1:
    print(f"phases.yaml: unsupported version {version}", file=sys.stderr)
    sys.exit(4)

# Validate top-level keys
for key in data:
    if key not in ("version","class_overrides","waivers_allowed","steps"):
        print(f"phases.yaml: unknown top-level key '{key}'", file=sys.stderr)
        sys.exit(4)

class_overrides = data.get("class_overrides") or {}
for cls, spec in class_overrides.items():
    if cls not in KNOWN_CLASSES:
        print(f"phases.yaml: class_overrides.{cls}: unknown class name", file=sys.stderr)
        sys.exit(4)
    if not isinstance(spec, dict):
        print(f"phases.yaml: class_overrides.{cls}: expected mapping", file=sys.stderr)
        sys.exit(4)
    for key in spec:
        if key == "mandatory":
            vals = spec[key]
            if not isinstance(vals, list):
                print(f"phases.yaml: class_overrides.{cls}: mandatory must be a list", file=sys.stderr)
                sys.exit(4)
            for ph in vals:
                if ph not in KNOWN_PHASES:
                    print(f"phases.yaml: class_overrides.{cls}: unknown phase '{ph}'", file=sys.stderr)
                    sys.exit(4)
        elif key in REMOVAL_KEYS:
            print(f"phases.yaml: class_overrides.{cls}: removals are not permitted (key '{key}'); shrink a class only via --phase-waiver", file=sys.stderr)
            sys.exit(4)
        else:
            print(f"phases.yaml: class_overrides.{cls}: unknown key '{key}'", file=sys.stderr)
            sys.exit(4)

waivers_allowed = data.get("waivers_allowed") or []
if not isinstance(waivers_allowed, list):
    print("phases.yaml: waivers_allowed must be a list", file=sys.stderr)
    sys.exit(4)
for ph in waivers_allowed:
    if ph not in KNOWN_PHASES:
        print(f"phases.yaml: waivers_allowed: unknown phase '{ph}'", file=sys.stderr)
        sys.exit(4)

steps = data.get("steps") or {}
if not isinstance(steps, dict):
    print("phases.yaml: steps must be a mapping", file=sys.stderr)
    sys.exit(4)
for hook in steps:
    if hook not in KNOWN_HOOKS:
        print(f"phases.yaml: steps: unknown hook point '{hook}'", file=sys.stderr)
        sys.exit(4)

print(json.dumps({
    "version": version,
    "class_overrides": class_overrides,
    "waivers_allowed": waivers_allowed,
    "steps": steps,
}))
PYEOF
}

# ── resolve the mandatory set for a class ────────────────────────────────────
# Prints one phase per line, each prefixed MANDATORY or DERIVED.
# Union: base table ∪ class_overrides.<Class>.mandatory
_resolve_mandatory() {
  local cls="$1" writes="${2:-}"
  local overrides_json waivers
  overrides_json="$(_read_phases_yaml)"

  # Check for deploy.done to feed derived conditions
  local deploy_done=""
  # deploy_done is passed as env, not computable here in isolation

  local phase
  for phase in classify diverge plan gate1 build test review deploy live_verify e2e close; do
    local level derived
    level="$(_phase_class_level "$cls" "$phase")"
    derived="$(_phase_derived "$cls" "$phase" "$writes" "${LEADV2_DEPLOY_DONE:-}")"

    # Check override: union semantics
    local in_override=""
    if printf '%s' "$overrides_json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
co=d.get('class_overrides',{})
cls='$cls'
if cls in co and '$phase' in (co[cls].get('mandatory') or []):
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
      in_override="1"
    fi

    # Final resolution: base table derived, plus override union
    if [[ "$derived" == "mandatory" || -n "$in_override" ]]; then
      printf 'MANDATORY %s\n' "$phase"
    elif [[ "$derived" == n/a:* ]]; then
      printf 'NA %s %s\n' "$phase" "${derived#n/a:}"
    elif [[ "$derived" == "optional" ]]; then
      printf 'OPTIONAL %s\n' "$phase"
    elif [[ "$derived" == "excluded" ]]; then
      :
    fi
  done
}

# ── verify artifact for a phase ──────────────────────────────────────────────
# Returns 0 if artifact is proven, 1 otherwise.
_verify_artifact() {
  local sig8="$1" phase="$2" artifact="${3:-}" sha="${4:-}"
  case "$phase" in
    plan)
      # context.yaml or prepass file with non-empty design
      local prepass_file
      prepass_file="$(_prepass_file "$sig8" 2>/dev/null)"
      if [[ -n "$prepass_file" && -s "$prepass_file" ]]; then return 0; fi
      local ctx_file="${PHASES_DIR_BASE}/dispatch-${sig8}/context.yaml"
      if [[ -s "$ctx_file" ]] && grep -q 'decisions' "$ctx_file" 2>/dev/null; then return 0; fi
      return 1
      ;;
    gate1)
      local gate_file="${PHASES_DIR_BASE}/dispatch-${sig8}/.gate1-passed"
      [[ -s "$gate_file" ]] && return 0
      return 1
      ;;
    build)
      # non-empty git diff vs lane base — checked at call site; here just check record exists
      [[ -n "$artifact" && -f "$artifact" ]] && return 0
      return 1
      ;;
    review)
      # review ledger row exists
      local ledger_dir="${CACHE_BASE}/code-review-ledger"
      local slug
      slug="$(basename "${LEDGER_REPO_ROOT:-${PROJECT_ROOT}}")" || slug="repo"
      local ledger_file="${ledger_dir}/${slug}.jsonl"
      [[ -s "$ledger_file" ]] && return 0
      return 1
      ;;
    test|deploy|live_verify|e2e)
      [[ -n "$artifact" && -f "$artifact" ]] && return 0
      return 1
      ;;
    close)
      local flag_file="${PHASES_DIR_BASE}/dispatch-${sig8}/phase8-passed.flag"
      [[ -s "$flag_file" ]] && return 0
      return 1
      ;;
    classify|diverge)
      # These are early phases — if the lane is dispatched, classify happened
      [[ -d "${PHASES_DIR_BASE}/dispatch-${sig8}" ]] && return 0
      return 1
      ;;
    *) return 1 ;;
  esac
}

_prepass_file() { printf '%s/dispatch-%s/architect-prepass.md' "$PHASES_DIR_BASE" "$1"; }

# ── record subcommand ─────────────────────────────────────────────────────────
cmd_record() {
  local sig8="" phase="" artifact="" status="done" handle="" reason="" task_id="" owner=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --artifact) artifact="$2"; shift 2 ;;
      --status)   status="$2"; shift 2 ;;
      --handle)   handle="$2"; shift 2 ;;
      --reason)   reason="$2"; shift 2 ;;
      --task-id)  task_id="$2"; shift 2 ;;
      --owner)    owner="$2"; shift 2 ;;
      --*)  _log_err "record: unknown flag: $1"; exit 4 ;;
      *)
        if [[ -z "$sig8" ]]; then sig8="$1"
        elif [[ -z "$phase" ]]; then phase="$1"
        else _log_err "record: unexpected positional: $1"; exit 4
        fi
        shift ;;
    esac
  done

  [[ -n "$sig8" ]] || { _log_err "record: <sig8> required"; exit 4; }
  [[ -n "$phase" ]] || { _log_err "record: <phase> required"; exit 4; }

  case "$status" in
    running|done|n/a|waived) ;;
    *) _log_err "record: invalid status '$status'"; exit 4 ;;
  esac

  # --artifact required unless status is running|n/a|waived, or the phase is a
  # meta-phase (classify/diverge) whose proof is the dispatch dir itself.
  if [[ "$status" == "done" && -z "$artifact" ]] \
     && [[ "$phase" != "classify" && "$phase" != "diverge" ]]; then
    _log_err "record: --artifact required for status=done"
    exit 4
  fi
  # --handle required when status=running
  if [[ "$status" == "running" && -z "$handle" ]]; then
    _log_err "record: --handle required for status=running"
    exit 4
  fi
  # --reason required when status=n/a or waived
  if [[ ("$status" == "n/a" || "$status" == "waived") && -z "$reason" ]]; then
    _log_err "record: --reason required for status=$status"
    exit 4
  fi

  [[ -n "$owner" ]] || owner="$(basename "$0")"

  local phases_d phase_file
  phases_d="$(_phases_d "$sig8")"
  phase_file="${phases_d}/${phase}.yaml"

  mkdir -p "$phases_d" || { _log_err "record: cannot mkdir $phases_d"; exit 4; }

  local sha="" started_at ended_at
  started_at="$(_now_iso)"
  if [[ "$status" == "running" ]]; then
    ended_at=""
  else
    ended_at="$started_at"
  fi

  if [[ -n "$artifact" && -f "${PROJECT_ROOT}/${artifact}" ]]; then
    sha="$(_sha256 "${PROJECT_ROOT}/${artifact}")"
  elif [[ -n "$artifact" && -f "$artifact" ]]; then
    sha="$(_sha256 "$artifact")"
  fi

  # Atomic write: mktemp in same dir + mv -f
  local tmp_file
  tmp_file="$(mktemp "${phases_d}/.${phase}.XXXXXX")" || { _log_err "record: mktemp failed"; exit 4; }

  {
    printf 'phase: %s\n' "$phase"
    printf 'status: %s\n' "$status"
    printf 'owner: %s\n' "$owner"
    printf 'handle: %s\n' "$handle"
    printf 'artifact: %s\n' "$artifact"
    printf 'artifact_sha256: %s\n' "$sha"
    printf 'started_at: %s\n' "$started_at"
    printf 'ended_at: %s\n' "$ended_at"
    printf 'reason: %s\n' "$reason"
  } > "$tmp_file"

  mv -f "$tmp_file" "$phase_file" || { _log_err "record: mv failed"; rm -f "$tmp_file"; exit 4; }

  # Journal observability
  local tid="${task_id:-$sig8}"
  _emit "phase_recorded" "phase=${phase} task=${tid} status=${status}"

  # Mirror to active.yaml — must never fail a dispatch
  if [[ "$status" == "running" || "$status" == "done" ]]; then
    if [[ -n "$task_id" ]] && declare -F leadv2_active_update_phase >/dev/null 2>&1; then
      if ! LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" leadv2_active_update_phase "$task_id" "$phase" >/dev/null 2>&1; then
        _emit "phase_mirror_miss" "task=${tid} phase=${phase}"
      fi
    elif [[ -n "$task_id" ]] && [[ -f "$ACTIVE_REGISTRY" ]]; then
      if ! LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" bash -c 'source "%s"; leadv2_active_update_phase "%s" "%s"' "$ACTIVE_REGISTRY" "$task_id" "$phase" >/dev/null 2>&1; then
        _emit "phase_mirror_miss" "task=${tid} phase=${phase}"
      fi
    fi
  fi

  return 0
}

# ── assert subcommand ─────────────────────────────────────────────────────────
cmd_assert() {
  local sig8="" cls="" writes=""
  local -a waivers=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --class)
        cls="$2"; shift 2 ;;
      --waiver)
        waivers+=("$2"); shift 2 ;;
      --writes)
        writes="$2"; shift 2 ;;
      --*)
        _log_err "assert: unknown flag: $1"; exit 4 ;;
      *)
        if [[ -z "$sig8" ]]; then sig8="$1"; else _log_err "assert: unexpected positional: $1"; exit 4; fi
        shift ;;
    esac
  done

  [[ -n "$sig8" ]] || { _log_err "assert: <sig8> required"; exit 4; }
  [[ -n "$cls" ]] || { _log_err "assert: --class required"; exit 4; }

  case "$cls" in
    Trivial|Light|Standard|Heavy) ;;
    *) _log_err "assert: invalid class '$cls'"; exit 4 ;;
  esac

  # Read phases.yaml
  local overrides_json
  overrides_json="$(_read_phases_yaml)" || exit $?

  # Process waivers
  local -a accepted_waivers=()
  local waivers_allowed
  waivers_allowed="$(printf '%s' "$overrides_json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for w in (d.get('waivers_allowed') or []):
    print(w)
" 2>/dev/null)"

  for w in "${waivers[@]}"; do
    # Validate format
    local w_phase w_reason
    if [[ "$w" != *=* ]]; then
      _log_err "waiver: bad format '$w' (expected <phase>=<reason>)"
      exit 4
    fi
    w_phase="${w%%=*}"
    w_reason="${w#*=}"
    if [[ -z "$w_reason" ]]; then
      _log_err "waiver: empty reason for phase '$w_phase'"
      exit 4
    fi

    # Rule 3: review/close hard-excluded
    if [[ "$w_phase" == "review" || "$w_phase" == "close" ]]; then
      _log_err "waiver: phase '$w_phase' is non-waivable (hard-excluded in plugin code)"
      exit 4
    fi

    # Validate phase is known
    local known=""
    for kp in classify diverge plan gate1 build test review deploy live_verify e2e close; do
      [[ "$w_phase" == "$kp" ]] && known="1"
    done
    [[ -n "$known" ]] || { _log_err "waiver: unknown phase '$w_phase'"; exit 4; }

    # Rule 4: must be in waivers_allowed
    if ! printf '%s\n' "$waivers_allowed" | grep -qxF "$w_phase"; then
      _log_err "waiver: phase '$w_phase' is not in waivers_allowed"
      exit 4
    fi

    # Accepted: write the record
    accepted_waivers+=("$w_phase")
    cmd_record "$sig8" "$w_phase" --status waived --reason "$w_reason"
    _emit "phase_waived" "task=${sig8} phase=${w_phase} reason=${w_reason}"
  done

  # Resolve mandatory set
  local missing=()
  while IFS=' ' read -r kind pname reason_text; do
    [[ "$kind" == "MANDATORY" ]] || continue

    # Skip accepted waivers
    local waived=""
    for aw in "${accepted_waivers[@]}"; do
      [[ "$aw" == "$pname" ]] && waived="1"
    done
    [[ -n "$waived" ]] && continue

    # Check if phase record exists and is proven
    local pfile
    pfile="$(_phase_file "$sig8" "$pname")"
    if [[ -f "$pfile" ]]; then
      local p_status
      p_status="$(grep '^status:' "$pfile" 2>/dev/null | awk '{print $2}' || true)"
      case "$p_status" in
        done|waived)
          # Verify artifact
          local p_artifact p_sha
          p_artifact="$(grep '^artifact:' "$pfile" 2>/dev/null | sed 's/^artifact:[[:space:]]*//' || true)"
          p_sha="$(grep '^artifact_sha256:' "$pfile" 2>/dev/null | awk '{print $2}' || true)"

          # For non-conditional phases, verify artifact
          if [[ "$pname" != "classify" && "$pname" != "diverge" ]]; then
            if _verify_artifact "$sig8" "$pname" "$p_artifact" "$p_sha"; then
              continue
            fi
          else
            continue
          fi
          ;;
        n/a)
          continue
          ;;
        running)
          # Running is not proven
          ;;
      esac
    fi
    missing+=("$pname")
  done < <(_resolve_mandatory "$cls" "$writes")

  if [[ ${#missing[@]} -gt 0 ]]; then
    local csv
    csv="$(IFS=,; printf '%s' "${missing[*]}")"
    printf 'missing=%s\n' "$csv"
    exit 3
  fi

  exit 0
}

# ── show subcommand ──────────────────────────────────────────────────────────
cmd_show() {
  local sig8="$1"
  local phases_d
  phases_d="$(_phases_d "$sig8")"
  if [[ ! -d "$phases_d" ]]; then
    printf 'No phase records for %s\n' "$sig8"
    return 0
  fi
  printf '%-14s %-10s %-24s %-12s\n' "PHASE" "STATUS" "OWNER" "STARTED"
  printf '%s\n' "----------------------------------------------"
  local f
  for f in "$phases_d"/*.yaml; do
    [[ -f "$f" ]] || continue
    local p s o st
    p="$(grep '^phase:' "$f" | awk '{print $2}')"
    s="$(grep '^status:' "$f" | awk '{print $2}')"
    o="$(grep '^owner:' "$f" | awk '{print $2}')"
    st="$(grep '^started_at:' "$f" | awk '{print $2}')"
    printf '%-14s %-10s %-24s %-12s\n' "$p" "$s" "$o" "$st"
  done
}

# ── plan-for subcommand ──────────────────────────────────────────────────────
cmd_plan_for() {
  local cls=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --class) cls="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "$cls" ]] || { _log_err "plan-for: --class required"; exit 4; }
  _resolve_mandatory "$cls"
}

# ── main ──────────────────────────────────────────────────────────────────────
[[ $# -eq 0 ]] && { _log_err "usage: $0 <record|assert|show|plan-for> ..."; exit 4; }
cmd="$1"; shift
case "$cmd" in
  record)   cmd_record "$@" ;;
  assert)   cmd_assert "$@" ;;
  show)     cmd_show "$@" ;;
  plan-for) cmd_plan_for "$@" ;;
  -h|--help) _log "usage: $0 <record|assert|show|plan-for> ..."; exit 0 ;;
  *)        _log_err "unknown command: $cmd"; exit 4 ;;
esac
