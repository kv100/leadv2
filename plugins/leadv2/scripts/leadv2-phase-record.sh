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
#   proof: verified|attested|unverified   (§3: attested for test/live_verify/e2e; unverified when _verify_artifact fails; absent on older records)
#   commit: <40-hex sha>  (deploy only; additive, may be absent on older records)
#
# Proof level per phase (what _verify_artifact actually checks):
#
#   Phase        Proof                                        Level
#   -----        -----                                        -----
#   plan         context.yaml or prepass exists + has body    full (verified)
#                OR any single .md file inside the task's own  attested
#                docs/handoff/<task>/ dir (any name) clearing a
#                substance floor: >=120 non-whitespace chars
#                AND >=2 non-blank lines
#   gate1        .gate1-passed sentinel non-empty             full (verified)
#                OR the phase record itself carries a          attested
#                non-empty --reason (an explicit recorded
#                gate decision, not a machine-checked sentinel)
#   build        artifact integrity + lane diff non-empty     full
#   review       diff_hash match + verdict PASS/PASS_NITS     full
#   deploy       artifact integrity + commit descendant of lane base full
#   close        phase8-passed.flag non-empty                 full
#   test         artifact integrity only                      unprovable
#   live_verify  artifact integrity only                      unprovable
#   e2e          artifact integrity only                      unprovable
#   classify     dispatch dir exists                          full (meta)
#   diverge      dispatch dir exists                          full (meta)
#
# test / live_verify / e2e: integrity (sha256 match) is strictly stronger than
# bare existence, but is NOT semantic proof that a test ran or a deploy is live.
# These three phases are declared UNPROVABLE beyond integrity — there is no
# writer that records them `done` today, and no semantic assertion is available.
#
# DISPATCH-PHASE-DEADLOCK-01: plan/gate1's "attested" paths above exist because
# _verify_artifact's ONLY prior acceptance for those two phases was a
# machine-produced artifact (context.yaml.decisions / architect-prepass.md /
# .gate1-passed) — none of which exist before a worker has ever run. A
# brand-new Standard/Heavy lane whose plan and gate 1 were genuinely done by
# the LEAD (a brief was written, a gate decision was taken) had no admissible
# proof at all: the printed remedy pointed at a command that could never
# satisfy the gate it was offered for (measured cost: 8 hand-written-file
# workarounds on 2026-08-31, plus a red main-branch test tripping the same
# refusal). "attested" is deliberately a WEAKER proof tier than "verified" —
# see cmd_record's proof field — so this does not silently upgrade lead
# say-so to the same strength as a machine-checked artifact.
#
# DISPATCH-PHASE-DEADLOCK-01: a lane with ZERO phase records at all (phases.d
# absent or empty) is at BOOTSTRAP, not in violation — cmd_assert admits it
# unconditionally (see PHASE-BOOTSTRAP-01 below). The instant any phase
# record exists for the lane (typically `classify`, written by dispatch-code
# immediately before it calls the guard), bootstrap is over and every
# mandatory phase is enforced exactly as before. Do not read this as "phases
# are now optional" — a Standard/Heavy lane that genuinely skipped planning
# after classify was recorded is still refused (acceptance criterion 5 in
# test-phase-precondition-bootstrap.sh).
#
# PHASE-GATE-IS-INVERTED-01 (2026-09-01): the bootstrap answer is derived by
# the CHECKER from the store, never accepted from the caller. Because
# dispatch-code records classify before it asserts, the zero-record exemption
# is unreachable on the real dispatch path — a fresh Standard/Heavy dispatch
# MUST carry plan+gate1 (lead-authored brief.md + recorded Gate-1 reason are
# valid pre-spawn evidence, see _verify_artifact) before a worker is spawned.
# The deadlock the exemption was added for no longer exists: the evidence
# path above is satisfiable BEFORE dispatch, which is how it must be used.
#
# review — residual forgery surface (honest scope):
#   What the review proof DOES establish: the ledger row's diff_hash matches
#   the target diff, the verdict is PASS/PASS_WITH_NITS, the reviewer arm is
#   allowed, and the row carries a guard_token that was minted for THIS exact
#   diff_hash by the guarded write path (record-review in leadv2-dispatch-code).
#   A token stolen from a different diff will not satisfy the check.
#   What it does NOT establish: it does not stop a process that has write
#   access to ${CACHE_BASE}/code-review-provenance/ from appending a matching
#   <diff_hash> <token> pair and forging a valid-looking row.  Every build
#   worker runs as the same Unix user as the verifier, so there is no
#   filesystem boundary between them — this cannot be closed by file layout
#   alone, only by an authority outside the process (or by making a forged
#   row visible in a diff that a human reads).
#
# gate1 — residual forgery surface (honest scope):
#   The .gate1-passed sentinel need only be non-empty, and any process with
#   write access to docs/handoff/dispatch-<sig>/ can create it.  This is the
#   same residual class as the review provenance directory above: the worker
#   and the verifier are the same Unix user, so no file-based sentinel can
#   carry founder authority.  The sentinel proves only that a file exists at
#   that path, not that a human approved the gate.
#
# Usage:
#   leadv2-phase-record.sh record <sig8> <phase> [flags]
#       --artifact <path>           required unless --status running|n/a|waived
#       --status running|done|n/a|waived   default: done
#       --handle <worker handle>    required when --status running
#       --reason <text>             required when --status n/a|waived;
#                                    for phase=gate1 status=done, a non-empty
#                                    --reason is ALSO accepted as an explicit
#                                    recorded gate decision (proof: attested)
#       --task-id <founder task id> for the active.yaml mirror
#       --owner <script:function>   default: $(basename "$0")
#
# exit 5 (record) = the phase was asked to be recorded `done` but its proof does
#                   not verify. Nothing is written. See
#                   PHASE-GATE-NAMES-EVERYTHING-AT-ONCE-01.
#
#   leadv2-phase-record.sh assert <sig8> --class <Trivial|Light|Standard|Heavy>
#       [--waiver <phase>=<reason>]...
#       [--writes <csv>]
#       [--at-bootstrap]   ACCEPTED BUT IGNORED (PHASE-GATE-IS-INVERTED-01):
#                          a caller-attested bootstrap answer is an assertion
#                          by the party being checked, and forwarding it let
#                          every brand-new lane skip plan/gate1. The guard
#                          derives bootstrap state itself, from the store, at
#                          assert time (see PHASE-BOOTSTRAP-01 in cmd_assert).
#
#   leadv2-phase-record.sh is-bootstrap <sig8>
#       exit 0 iff the lane has no phase record at all (phases.d absent or
#       empty), 1 otherwise. dispatch-code calls this BEFORE recording its own
#       classify so the bootstrap fact survives the classify write.
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
source "${SCRIPT_DIR}/lib/leadv2-test-context.sh" || exit 4

# ── project root resolution ──────────────────────────────────────────────────
# PHASE-GATE-IS-INVERTED-01 [Medium] 4: this script read ONLY LEADV2_PROJECT_ROOT
# while its own variable (and the dispatcher's sub-invocations) say PROJECT_ROOT
# — an operator exporting just PROJECT_ROOT silently wrote a DIFFERENT store,
# and `show` then reported done from a store the dispatcher never reads. Both
# names now resolve the store (LEADV2_PROJECT_ROOT wins when both are set).
# A divergent pair is never silent: a WRITE refuses outright (a record the
# dispatcher cannot read is the lying-green shape this fix exists to kill); a
# READ warns and proceeds on LEADV2_PROJECT_ROOT.
_lv2_root_a="${LEADV2_PROJECT_ROOT:-}"
_lv2_root_b="${PROJECT_ROOT:-}"
_lv2_root_cmd="${1:-}"
if [[ -n "$_lv2_root_a" && -n "$_lv2_root_b" && "$_lv2_root_a" != "$_lv2_root_b" ]]; then
  if [[ "$_lv2_root_cmd" == "record" ]]; then
    printf '[%s] ERROR: project root conflict: LEADV2_PROJECT_ROOT=%s vs PROJECT_ROOT=%s — refusing to guess which phase store to WRITE\n' \
      "$SCRIPT_NAME" "$_lv2_root_a" "$_lv2_root_b" >&2
    exit 4
  fi
  printf '[%s] WARN: project root conflict: LEADV2_PROJECT_ROOT=%s wins over PROJECT_ROOT=%s for this read\n' \
    "$SCRIPT_NAME" "$_lv2_root_a" "$_lv2_root_b" >&2
fi
PROJECT_ROOT="${_lv2_root_a:-${_lv2_root_b:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
CACHE_BASE="${LEADV2_DISPATCH_CACHE_DIR:-${HOME}/.claude/cache}"
PHASES_DIR_BASE="${PROJECT_ROOT}/docs/handoff"
PHASES_YAML="${PROJECT_ROOT}/.claude/leadv2-overrides/phases.yaml"
JOURNAL_BIN="${LEADV2_JOURNAL_BIN:-${SCRIPT_DIR}/leadv2-journal.sh}"
ACTIVE_REGISTRY="${SCRIPT_DIR}/leadv2-active-registry.sh"

# PHASE-BOOTSTRAP-ADMIT-02: global proof-kind side channel written by
# _verify_artifact on every successful (0) return -- see that function.
# Declared here so `set -u` never trips before the first call sets it.
_VERIFY_PROOF_KIND="verified"

_log() { printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2; }
_log_err() { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; }

# WAVE0-LIB-SWALLOWS-ITS-OWN-FAILURE-01 (P-7): _emit used to pass the event
# name as $1 and the text as $2 — leadv2-journal.sh reads those as MODE and
# task-id, so `MODE=phase_recorded` hit "Unknown mode", exit 1, and the `||
# true` swallowed it: NO phase_*/review_* event has ever reached a journal
# (dispatch-96d97702, 2026-09-04: zero phase_precondition lines). The
# signature is now <task-id> <event> <text> and the verb is `append`. The
# event name is mapped into the journal's type whitelist by prefix and
# prepended to the text, so a line lands as `- <ts> [phase] phase_recorded
# phase=... task=...`. Journaling is telemetry: a failure prints its own
# line, counts into _EMIT_MISS (summarised once at exit by _emit_summary),
# returns rc 2 — and never changes the record/assert verbs' rc.
_EMIT_MISS=0
_emit() { # <task-id> <event> <text>
  local _e_task="$1" _e_event="$2" _e_text="$3" _e_type
  case "${_e_event}" in
    phase_*)  _e_type="phase" ;;
    review_*) _e_type="finding" ;;
    *)        _e_type="note" ;;
  esac
  if [[ -z "${JOURNAL_BIN}" || ! -f "${JOURNAL_BIN}" ]]; then
    # No journal binary resolved: nothing was REFUSED, so nothing prints (the
    # counted lines below are for refused writes only; a skip notice here
    # broke the success-is-silent contract of test-phase-record-worktree-axis
    # in hermetic fixtures that have no journal bin).
    return 0
  fi
  if ! LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" bash "${JOURNAL_BIN}" append "${_e_task}" "${_e_type}" "${_e_event} ${_e_text}" >/dev/null 2>&1; then
    printf '[phase-record] journal_write_failed=1 event=%s task=%s\n' "${_e_event}" "${_e_task}" >&2
    return 2
  fi
  return 0
}
_emit_summary() {
  if [[ "${_EMIT_MISS}" -gt 0 ]]; then
    printf '[phase-record] journal_events_missed=%s\n' "${_EMIT_MISS}" >&2
  fi
  return 0
}
trap _emit_summary EXIT

_now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# B1 R1: the review-arm vocabulary. Source of truth:
# scripts/lib/leadv2-glm-policy-resolve.py:66 (DEFAULT_REVIEW_ARM_ORDER).
# A repo with a novel arm overrides via LEADV2_REVIEW_ARMS.
REVIEW_ARMS="${LEADV2_REVIEW_ARMS:-codex,glm,kimi,fable,opus,sonnet}"

_sha256() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

# ── phases.d path helpers ────────────────────────────────────────────────────
_phases_d() { printf '%s/dispatch-%s/phases.d' "$PHASES_DIR_BASE" "$1"; }
_phase_file() { printf '%s/%s.yaml' "$(_phases_d "$1")" "$2"; }

# Common-dir identifies a repository; toplevel identifies ONE working tree.
# Resolve git's relative/absolute output from the directory it was queried in.
_phase_common_dir() {
  local dir
  dir="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$dir" in /*) ;; *) dir="$1/$dir" ;; esac
  (cd "$dir" && pwd -P)
}

_phase_check_worktree() {
  local target="$1" root_id script_id cwd_id root_tree cwd_tree in_test=0
  lv2_test_context && in_test=1
  if [[ "$in_test" == 1 && -z "$_lv2_root_a" && -z "$_lv2_root_b" ]]; then
    lv2_refuse_test_write "$SCRIPT_NAME" "$target" "LEADV2_PROJECT_ROOT (isolated fixture)"
    return 3
  fi
  root_id="$(_phase_common_dir "$PROJECT_ROOT")" || return 0
  script_id="$(_phase_common_dir "$SCRIPT_DIR")" || script_id=""
  # Extend the shared-sink test refusal to every worktree of the code's repo.
  # Merely exporting a root that points back at a live tree is not isolation.
  # Separate fixture repos (and non-git fixture directories) remain writable.
  if [[ "$in_test" == 1 && -n "$script_id" && "$root_id" == "$script_id" ]]; then
    lv2_refuse_test_write "$SCRIPT_NAME" "$target" "LEADV2_PROJECT_ROOT (isolated fixture)"
    return 3
  fi
  cwd_id="$(_phase_common_dir "$(pwd -P)")" || return 0
  if [[ "$cwd_id" == "$root_id" ]]; then
    root_tree="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel)" || return 4
    cwd_tree="$(git rev-parse --show-toplevel)" || return 4
    root_tree="$(cd "$root_tree" && pwd -P)" || return 4
    cwd_tree="$(cd "$cwd_tree" && pwd -P)" || return 4
    if [[ "$root_tree" != "$cwd_tree" ]]; then
      _log_err "record: REFUSED foreign worktree: cwd=$cwd_tree resolved_root=$root_tree target=$target; run from the owning tree with matching LEADV2_PROJECT_ROOT/PROJECT_ROOT"
      return 4
    fi
  fi
}

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
  local cls="$1" writes="${2:-}" scope="${3:-full}"
  local overrides_json waivers
  overrides_json="$(_read_phases_yaml)"

  # Check for deploy.done to feed derived conditions
  local deploy_done=""
  # deploy_done is passed as env, not computable here in isolation

  # PHASE-DISCIPLINE-01 step 2: scope=pre-build restricts the table to the
  # phases that must ALREADY exist when work ENTERS build (classify/diverge/
  # plan/gate1 per class). Used by dispatch-code's admission guard for the
  # Phase-4 re-entry check — the full scope stays the completion contract.
  local -a phase_list
  if [[ "$scope" == "pre-build" ]]; then
    phase_list=(classify diverge plan gate1)
  else
    phase_list=(classify diverge plan gate1 build test review deploy live_verify e2e close)
  fi

  local phase
  for phase in "${phase_list[@]}"; do
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

# ── repo slug (mirrors dispatch-code.sh:repo_slug byte-for-byte) ─────────────
# Sanitized to filesystem-safe so the ledger file assert reads matches the file
# the writer (dispatch-code.sh) created.
_repo_slug() {
  local base
  base="$(basename "${LEDGER_REPO_ROOT:-${PROJECT_ROOT}}")"
  printf '%s' "${base}" | tr -cd 'A-Za-z0-9._-'
}

# ── artifact integrity (applies to every artifact-bearing phase) ─────────────
# Resolves the artifact path the same way cmd_record does (:417-421), then
# compares the on-disk sha256 to the recorded sha.  rc 0 = intact, 1 = not.
_artifact_integrity() {
  local artifact="$1" recorded_sha="$2"
  local resolved=""
  if [[ -n "$artifact" && -f "${PROJECT_ROOT}/${artifact}" ]]; then
    resolved="${PROJECT_ROOT}/${artifact}"
  elif [[ -n "$artifact" && -f "$artifact" ]]; then
    resolved="$artifact"
  else
    return 1
  fi
  [[ -n "$recorded_sha" ]] || return 1
  local actual_sha
  actual_sha="$(_sha256 "$resolved")"
  [[ "$actual_sha" == "$recorded_sha" ]] || return 1
  return 0
}

# ── resolve the lane diff base (mirrors product-close.sh:_pc_diff_base) ──────
# Returns the merge-base sha on stdout, or empty if none resolves.
_resolve_lane_diff_base() {
  local sig8="$1" sha="${LEADV2_LANE_START_SHA:-}" base
  if [[ -z "$sha" ]]; then
    sha="$(cat "${CACHE_BASE}/dispatch-${sig8}.start-sha" 2>/dev/null || true)"
  fi
  if [[ -n "$sha" ]] && git -C "$PROJECT_ROOT" cat-file -e "${sha}^{commit}" 2>/dev/null; then
    base="$(git -C "$PROJECT_ROOT" merge-base "$sha" HEAD 2>/dev/null || true)"
    [[ -n "$base" ]] && { printf '%s' "$base"; return 0; }
  fi
  if git -C "$PROJECT_ROOT" cat-file -e "origin/main^{commit}" 2>/dev/null; then
    base="$(git -C "$PROJECT_ROOT" merge-base origin/main HEAD 2>/dev/null || true)"
    [[ -n "$base" ]] && printf '%s' "$base"
  fi
}

# ── verify artifact for a phase ──────────────────────────────────────────────
# Returns 0 if artifact is proven, 1 otherwise. Sets the GLOBAL _VA_STRENGTH
# to "verified" (machine-checked artifact) or "attested" (lead-authored brief /
# explicit recorded decision) before every successful return — callers that
# stamp a proof level MUST read it right after a 0 return (§ DISPATCH-PHASE-
# DEADLOCK-01; PHASE-BOOTSTRAP-ADMIT-02): "attested" is real evidence, but not
# something a machine independently derived.
_VA_STRENGTH=""
# PLAN-ARTIFACT-HAS-THREE-DIFFERENT-ADDRESSES-01: side channel carrying the
# addresses a FAILED verification actually consulted, so the refusal can name
# them instead of leaving the caller to guess which of three homes was meant.
_VA_LOOKED_AT=""
_verify_artifact() {
  local sig8="$1" phase="$2" artifact="${3:-}" sha="${4:-}" commit="${5:-}" reason="${6:-}"
  _VA_STRENGTH=""
  _VA_LOOKED_AT=""
  case "$phase" in
    plan)
      # context.yaml or prepass file with non-empty design — machine-checked,
      # full proof.
      local prepass_file
      prepass_file="$(_prepass_file "$sig8" 2>/dev/null)"
      if [[ -n "$prepass_file" && -s "$prepass_file" ]]; then _VA_STRENGTH="verified"; return 0; fi
      local ctx_file="${PHASES_DIR_BASE}/dispatch-${sig8}/context.yaml"
      if [[ -s "$ctx_file" ]] && grep -q 'decisions' "$ctx_file" 2>/dev/null; then _VA_STRENGTH="verified"; return 0; fi
      # DISPATCH-PHASE-DEADLOCK-01 / PHASE-BOOTSTRAP-ADMIT-02 /
      # PHASE-PLAN-PROOF-IS-FILENAME-BASED-01: a lead-authored brief,
      # fix-round or continue-round note is a real plan — it just does not
      # live in context.yaml, and context.yaml/architect-prepass.md are
      # machine-derived artifacts that cannot exist before a worker/architect
      # has actually run (the bootstrap deadlock). Accept it, but only ever as
      # "attested": a human artifact, not a machine-checked one, and the
      # distinction must not be lost.
      #
      # THREE independent guards, all required. This rebase resolution keeps
      # BOTH branches' protections — neither alone is sufficient:
      #  (a) LOCATION: the artifact lives directly in the task's own
      #      docs/handoff/<task>/ dir, exactly one path segment. Task dirs are
      #      named by task-id, not the dispatch sig — pinning to
      #      dispatch-<sig8>/ would reject every real lead brief, see
      #      test-phase-precondition-bootstrap.sh test 3.
      #  (b) INTEGRITY: a matching sha256, so an arbitrary --artifact string —
      #      or a foreign lane's still-evolving brief — cannot forge proof.
      #  (c) SUBSTANCE: >=120 non-whitespace chars AND >=2 non-blank lines,
      #      strictly tighter than the old bare non-empty (-s) check, so
      #      TBD/WIP/N/A one-liners that passed before now fail.
      #
      # The old two-name (brief.md|fix-round-N.md) allowlist is gone: it added
      # no protection beyond (a) and only over-fit two literal names,
      # rejecting real plan notes like continue-round-2.md (measured
      # 2026-09-03: it stalled seven Wave-4 lanes on rc=3 missing=plan until
      # the files were renamed). A Standard/Heavy lane that genuinely skipped
      # planning still falls through to `return 1` below — a wider
      # acceptable-evidence set, not a weaker check.
      # TODO(PHASE-PLAN-PROOF-IS-FILENAME-BASED-01): the [^/]+ task-id segment
      # is never checked against the CALLING sig8 — a substantial note in a
      # different task's handoff dir also passes. Pre-existing gap,
      # deliberately not fixed in this lane.
      if [[ -n "$artifact" ]]; then
        local _resolved=""
        if [[ -f "${PROJECT_ROOT}/${artifact}" ]]; then _resolved="${PROJECT_ROOT}/${artifact}"
        elif [[ -f "$artifact" ]]; then _resolved="$artifact"
        fi
        if [[ -n "$_resolved" && -s "$_resolved" ]] \
           && printf '%s' "$artifact" | grep -qE '^(.*/)?docs/handoff/[^/]+/[^/]+\.md$' \
           && _artifact_integrity "$artifact" "$sha"; then
          local _nonws _nonblank
          _nonws="$(tr -d '[:space:]' < "$_resolved" | wc -c | tr -d ' ')"
          _nonblank="$(grep -cv '^[[:space:]]*$' "$_resolved" 2>/dev/null | tr -d ' ')"
          if [[ "${_nonws:-0}" -ge 120 && "${_nonblank:-0}" -ge 2 ]]; then
            _VA_STRENGTH="attested"
            return 0
          fi
        fi
      fi
      # The three addresses are deliberate, not an accident: (1) and (2) are
      # machine-derived artifacts that only exist once an architect/worker ran,
      # (3) is a human-authored brief that lives under the TASK-ID directory and
      # is accepted only as `attested`. What was missing is that a refusal named
      # none of them, so a lead who put context.yaml under docs/handoff/<TASK-ID>/
      # (the path the dispatcher's own lane_plan_missing line prints, which is a
      # DELIVERY source, not a proof address) reads the refusal as "there is no
      # plan". Measured 2026-09-05 on task 11b25531: four dispatch attempts, the
      # first three writing the file at an address nothing verifies.
      local _p1=absent _p2=absent
      if [[ -s "$prepass_file" ]]; then _p1=present; fi
      if [[ -s "$ctx_file" ]]; then _p2=present; fi
      _VA_LOOKED_AT="plan proof is read at exactly these addresses and no other: (1) ${prepass_file} [${_p1}]; (2) ${ctx_file}, and it must contain a 'decisions' key [${_p2}]; (3) --artifact docs/handoff/<TASK-ID>/{brief,brief-*,fix-round-N}.md with a matching --sha, accepted as attested [--artifact was: ${artifact:-<none passed>}]"
      return 1
      ;;
    gate1)
      local gate_file="${PHASES_DIR_BASE}/dispatch-${sig8}/.gate1-passed"
      if [[ -s "$gate_file" ]]; then _VA_STRENGTH="verified"; return 0; fi
      # DISPATCH-PHASE-DEADLOCK-01 / PHASE-BOOTSTRAP-ADMIT-02: an explicit
      # recorded gate decision (a non-empty --reason on THIS gate1 phase
      # record) is real gate evidence even without the .gate1-passed sentinel
      # a worker/leadv2-gate1-prompt.sh would normally create — that sentinel
      # cannot exist before the gate ever ran once, same deadlock class as
      # `plan` above. Weaker than the sentinel, so "attested", never
      # "verified". A lane with neither the sentinel nor a reason still falls
      # through and refuses, unchanged.
      if [[ -n "$reason" ]]; then _VA_STRENGTH="attested"; return 0; fi
      return 1
      ;;
    build)
      # F2: artifact integrity first, then non-empty lane diff vs base.
      _artifact_integrity "$artifact" "$sha" || return 1
      # Non-empty git diff vs lane base proves build produced changes.
      git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 1
      local base
      base="$(_resolve_lane_diff_base "$sig8")"
      [[ -n "$base" ]] || return 1
      git -C "$PROJECT_ROOT" diff --quiet "$base" 2>/dev/null && return 1
      return 0
      ;;
    review)
      # F1: require a code-review-ledger row whose diff_hash matches this lane's
      # review.diff and whose verdict is PASS or PASS_WITH_NITS.
      # B1 R1: reviewer must be one of the five review arms.
      # B1 R3: row-count sidecar must agree (detects raw >> appends).
      local lane_diff="${PHASES_DIR_BASE}/dispatch-${sig8}/review.diff"
      [[ -s "$lane_diff" ]] || return 1
      local h
      h="$(_sha256 "$lane_diff")"
      local slug ledger_file sidecar
      slug="$(_repo_slug)"
      ledger_file="${CACHE_BASE}/code-review-ledger/${slug}.jsonl"
      [[ -f "$ledger_file" ]] || return 1

      # B1 R4: sidecar row-count check + adopted-marker tamper detection.
      # The sidecar is created exclusively by _increment_review_sidecar (the guarded
      # write path).  An "adopted" marker outside the ledger dir records that the
      # sidecar mechanism has been used for this slug.  Once adopted, sidecar-absent
      # is tamper (e.g. attacker ran `rm <slug>.jsonl.rows`), not legacy.
      sidecar="${CACHE_BASE}/code-review-ledger/${slug}.jsonl.rows"
      local _adopted="${CACHE_BASE}/code-review-provenance/${slug}.adopted"
      if [[ -f "$sidecar" ]]; then
        local _recorded_rows _ledger_rows
        _recorded_rows="$(cat "$sidecar" 2>/dev/null | tr -d ' \n')"
        _ledger_rows="$(wc -l < "$ledger_file" 2>/dev/null | tr -d ' ')"
        if [[ "$_ledger_rows" != "$_recorded_rows" ]]; then
          # R-4 mitigation: ledger_rows == recorded+1 is an in-flight append.
          if [[ "$_ledger_rows" -eq $((_recorded_rows + 1)) ]] 2>/dev/null; then
            sleep 0.2
            _ledger_rows="$(wc -l < "$ledger_file" 2>/dev/null | tr -d ' ')"
          fi
          if [[ "$_ledger_rows" != "$_recorded_rows" ]]; then
            _emit "${task_id:-$sig8}" "review_ledger_tamper" "repo=${slug} ledger_rows=${_ledger_rows} recorded_rows=${_recorded_rows}" || _EMIT_MISS=$((_EMIT_MISS+1))
            return 1
          fi
        fi
      else
        # Sidecar absent.  If the adopted marker exists, the sidecar was created
        # (and later deleted) → tamper, reject.  Only a repo that never used the
        # sidecar mechanism gets the legacy accept.
        if [[ -f "$_adopted" ]]; then
          _emit "${task_id:-$sig8}" "review_sidecar_tamper" "repo=${slug} sidecar=${sidecar##*/} adopted=${_adopted##*/}" || _EMIT_MISS=$((_EMIT_MISS+1))
          return 1
        fi
        _emit "${task_id:-$sig8}" "review_ledger_unchained" "repo=${slug}" || _EMIT_MISS=$((_EMIT_MISS+1))
      fi

      # B1 R1+R2: single python3 pass — checks reviewer allowlist, verdict,
      # diff_hash, and guard_token together.  Malformed JSON lines are skipped,
      # not fatal.  B1 R5: the guard_token must appear in the provenance tokens
      # file (outside the ledger dir), proving the row was written by the
      # guarded path, not raw file append.  R9: the token is bound to the
      # diff_hash it was minted for — a stolen token from a different diff
      # cannot satisfy the check.
      local _tokens_file="${CACHE_BASE}/code-review-provenance/${slug}.tokens"
      local _has_tokens="0"
      [[ -f "$_tokens_file" ]] && _has_tokens="1"
      LEADV2_REVIEW_ARMS="${REVIEW_ARMS}" LEADV2_TOKENS_FILE="${_tokens_file}" \
      LEADV2_HAS_TOKENS="${_has_tokens}" python3 - "$ledger_file" "$h" <<'PYEOF' || return 1
import json, os, sys
ledger_file, target_hash = sys.argv[1], sys.argv[2]
arms = set(os.environ.get("LEADV2_REVIEW_ARMS", "codex,glm,kimi,fable,opus,sonnet").split(","))
has_tokens = os.environ.get("LEADV2_HAS_TOKENS", "0") == "1"
tokens_file = os.environ.get("LEADV2_TOKENS_FILE", "")
valid_pairs = set()  # (diff_hash, token) pairs
if has_tokens and tokens_file:
    try:
        with open(tokens_file) as tf:
            for line in tf:
                line = line.strip()
                if not line:
                    continue
                parts = line.split(None, 1)
                if len(parts) == 2:
                    # R9 format: <diff_hash> <token>
                    valid_pairs.add((parts[0], parts[1]))
                # Old token-only lines (no diff_hash binding) are ignored.
    except OSError:
        pass
with open(ledger_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue  # skip malformed/truncated lines
        if obj.get("diff_hash") != target_hash:
            continue
        if obj.get("verdict") not in ("PASS", "PASS_WITH_NITS"):
            continue
        reviewer = obj.get("reviewer", "")
        arm = reviewer.split(":")[0]  # codex:standard → codex
        if arm not in arms:
            continue
        # B1 R5: if the tokens file exists, the row must carry a guard_token
        # that was minted by the guarded write path.  R9: the token must
        # be bound to this row's diff_hash — a stolen token from a
        # different diff does not satisfy the check.
        if has_tokens:
            gt = obj.get("guard_token", "")
            if not gt or (target_hash, gt) not in valid_pairs:
                continue
        sys.exit(0)  # all checks passed
sys.exit(1)  # no matching row
PYEOF
      return 0
      ;;
    test|live_verify|e2e)
      # F2: integrity-only — declared unprovable beyond sha256 match.
      # See the proof-level table in the header doc-block.
      _artifact_integrity "$artifact" "$sha" || return 1
      return 0
      ;;
    deploy)
      # F2: artifact integrity + recorded commit is a descendant of the lane's
      # own start-sha (B2: was merely "ancestor of origin/main" which accepts
      # origin/main's tip with zero work from this lane).
      _artifact_integrity "$artifact" "$sha" || return 1
      [[ -n "$commit" ]] || return 1
      git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 1
      local _deploy_base
      _deploy_base="$(_resolve_lane_diff_base "$sig8")"
      [[ -n "$_deploy_base" ]] || return 1
      # commit must be a STRICT descendant of the lane base: base is an ancestor
      # of commit AND commit ≠ base (otherwise zero-work deploy passes).
      [[ "$commit" != "$_deploy_base" ]] || return 1
      git -C "$PROJECT_ROOT" merge-base --is-ancestor "$_deploy_base" "$commit" 2>/dev/null || return 1
      return 0
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
  local sig8="" phase="" artifact="" status="done" handle="" reason="" task_id="" owner="" commit=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --artifact) artifact="$2"; shift 2 ;;
      --status)   status="$2"; shift 2 ;;
      --handle)   handle="$2"; shift 2 ;;
      --reason)   reason="$2"; shift 2 ;;
      --task-id)  task_id="$2"; shift 2 ;;
      --owner)    owner="$2"; shift 2 ;;
      --commit)   commit="$2"; shift 2 ;;
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
  # meta-phase (classify/diverge) whose proof is the dispatch dir itself, or
  # phase=gate1 with a non-empty --reason: an explicit recorded gate decision
  # is admissible gate1 evidence in its own right (DISPATCH-PHASE-DEADLOCK-01 /
  # PHASE-BOOTSTRAP-ADMIT-02 — see _verify_artifact's gate1 case).
  if [[ "$status" == "done" && -z "$artifact" ]] \
     && [[ "$phase" != "classify" && "$phase" != "diverge" ]] \
     && ! [[ "$phase" == "gate1" && -n "$reason" ]]; then
    _log_err "record: --artifact required for status=done (or --reason for an explicit gate1 decision)"
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
  _phase_check_worktree "$phase_file" || exit $?

  # PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01: `record` trusts the resolved
  # root blindly, and an inherited LEADV2_PROJECT_ROOT (another repo's
  # settings.json env block) resolves SILENTLY — the conflict guard at the
  # top of this script fires only when BOTH root vars are set and disagree.
  # The one legitimate missing-dispatch-dir shape is a SAME-REPO first
  # record: on a fresh dispatch, dispatch-code's own `record classify`
  # (resolve :7125) IS the step that creates docs/handoff/dispatch-<sig8>/
  # via the mkdir below — refusing a missing dir unconditionally breaks
  # every fresh dispatch (measured 2026-09-06: the empty store then trips
  # the bootstrap exemption and the pre-spawn plan/gate1 refusal is
  # bypassed entirely). The bug shape is CROSS-REPO: cwd inside repo A
  # while the root resolves into repo B. So refuse a missing dir only when
  # the cwd's repo identity (git common-dir, realpath fallback) differs
  # from the resolved root's. Reads (assert/show/is-bootstrap) keep the
  # warn-and-proceed asymmetry above.
  local _own_dispatch_dir="${PHASES_DIR_BASE}/dispatch-${sig8}"
  if [[ ! -d "$_own_dispatch_dir" ]]; then
    # WAIVER-REGRESSION-01 (2026-09-06): a root that is not a git repository at
    # all (no common dir) is the isolated test-fixture shape every suite uses
    # (LEADV2_PROJECT_ROOT=$(mktemp -d), cwd = the harness repo) -- the same
    # non-git-fixture carve-out _phase_check_worktree applies above. It cannot
    # be "a foreign REPO": there is no repo to write into. cmd_assert's
    # accepted-waiver path (record --status waived) is exactly a first record
    # for a sig8 with no dispatch dir yet, and the old realpath-fallback
    # comparison refused it (80/2). The refusal stays armed only when the
    # resolved root IS a git repo whose identity differs from cwd's -- the
    # case-5c cross-repo abuse shape.
    local _cwd_id _root_id
    _root_id="$(_phase_common_dir "$PROJECT_ROOT")" || _root_id=""
    if [[ -n "$_root_id" ]]; then
      _cwd_id="$(_phase_common_dir "$(pwd -P)")" || _cwd_id="$(pwd -P)"
      if [[ "${_cwd_id%/}" != "${_root_id%/}" ]]; then
        _log_err "record: project root not permitted: dispatch-${sig8}/ does not exist under resolved root ${PROJECT_ROOT} (missing: ${_own_dispatch_dir}), and cwd resolves to a different repo (${_cwd_id} vs ${_root_id}) — refusing to write phase ${phase}; an inherited LEADV2_PROJECT_ROOT/PROJECT_ROOT from another repo's session makes record write into a foreign repo, check LEADV2_PROJECT_ROOT / PROJECT_ROOT / cwd"
        exit 4
      fi
    fi
  fi

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

  # PHASE-GATE-NAMES-EVERYTHING-AT-ONCE-01 (second defect): resolve the proof
  # BEFORE writing anything. This block used to sit inside the heredoc below: a
  # `done` record whose artifact failed verification was written anyway, with
  # `proof: unverified`, and the writer printed
  #   "WARN: phase 'plan' recorded done but proof NOT verified — assert will refuse"
  # — announcing its own future refusal and proceeding. That record is worse
  # than no record twice over. It does not satisfy the gate, AND its mere
  # existence ends the lane's bootstrap grace (cmd_assert's _lane_bootstrap is
  # "phases.d has any record at all", and _phase_precondition_guard's is "any
  # record other than classify"), so writing an unprovable `plan` converts a
  # lane that would have been admitted into one that is refused. A write that is
  # known at write time to fail the very check it exists to pass must refuse at
  # write time.
  #
  # Scope mirrors cmd_assert exactly: classify and diverge are the phases assert
  # does not verify, so they are the phases this refusal does not apply to. The
  # verifier is the same _verify_artifact call, on the same arguments.
  local _proof=""
  if [[ "$status" == "done" ]]; then
    if _verify_artifact "$sig8" "$phase" "$artifact" "$sha" "$commit" "$reason" 2>/dev/null; then
      case "$phase" in
        test|live_verify|e2e) _proof="attested" ;;
        plan|gate1) _proof="${_VA_STRENGTH:-verified}" ;;
        *) _proof="verified" ;;
      esac
    elif [[ "$phase" == "classify" || "$phase" == "diverge" ]]; then
      _proof="verified"
    elif [[ -n "$artifact" ]] && ! _artifact_integrity "$artifact" "$sha" 2>/dev/null; then
      # THE NARROW, DECIDABLE CASE — and it is deliberately narrower than "the
      # whole verifier said no". Verification at WRITE time is not the same
      # question as verification at ASSERT time: several phases finish earning
      # their evidence after the record lands. `record-review` (dispatch-code)
      # writes the phase record and the provenance ledger row in one flow, so a
      # review record legitimately fails _verify_artifact at the instant it is
      # written and passes seconds later; refusing on the verifier's whole
      # answer broke exactly that path (measured 2026-09-05: six green cases of
      # test-phase-precondition.sh -- G7b/c/e/f/g, G9a -- went red because the
      # review and deploy records were refused and never existed).
      #
      # Artifact integrity is the part that IS decided at write time and can
      # never become true later: the named file is absent, unreadable, or its
      # content does not hash to the sha being recorded alongside it. Nothing
      # downstream repairs that, so this record is knowably dead on arrival and
      # refuses now instead of announcing its own future refusal and proceeding.
      _log_err "record: refusing to record phase '$phase' for $sig8 as done — its artifact does not exist or does not match the recorded sha, so assert can never accept it"
      _log_err "  artifact: ${artifact}"
      _log_err "  nothing was written: an unprovable record does not satisfy the gate AND ends this lane's bootstrap grace, so it leaves the lane worse off than no record at all"
      _log_err "  fix the artifact, then re-run this same command ('leadv2-phase-record.sh assert <sig8> --class <class>' prints the whole required set at once)"
      _emit "${task_id:-$sig8}" "phase_record_refused" "task=${task_id:-$sig8} phase=${phase} reason=artifact_integrity" || _EMIT_MISS=$((_EMIT_MISS+1))
      exit 5
    else
      # Everything else keeps today's behaviour: the artifact is real, but some
      # piece of evidence the verifier also wants is not in place YET. Recorded
      # unverified, and said out loud -- this one genuinely may become true.
      _proof="unverified"
      _log "WARN: phase '$phase' for $sig8 recorded done with proof NOT yet verified — assert will refuse until the rest of its evidence lands${_VA_LOOKED_AT:+ -- }${_VA_LOOKED_AT}"
    fi
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
    # §3 honesty: _proof was resolved above, BEFORE this file was opened, and an
    # unprovable `done` never reaches this point — it refused. Running/n/a/waived
    # phases get an empty proof: it does not apply to them.
    printf 'proof: %s\n' "$_proof"
    [[ -n "$commit" ]] && printf 'commit: %s\n' "$commit"
  } > "$tmp_file"

  mv -f "$tmp_file" "$phase_file" || { _log_err "record: mv failed"; rm -f "$tmp_file"; exit 4; }

  # Journal observability
  local tid="${task_id:-$sig8}"
  _emit "${tid}" "phase_recorded" "phase=${phase} task=${tid} status=${status}" || _EMIT_MISS=$((_EMIT_MISS+1))

  # Mirror to active.yaml — must never fail a dispatch
  if [[ "$status" == "running" || "$status" == "done" ]]; then
    if [[ -n "$task_id" ]] && declare -F leadv2_active_update_phase >/dev/null 2>&1; then
      if ! LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" leadv2_active_update_phase "$task_id" "$phase" >/dev/null 2>&1; then
        _emit "${tid}" "phase_mirror_miss" "task=${tid} phase=${phase}" || _EMIT_MISS=$((_EMIT_MISS+1))
      fi
    elif [[ -n "$task_id" ]] && [[ -f "$ACTIVE_REGISTRY" ]]; then
      if ! LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" bash -c 'source "%s"; leadv2_active_update_phase "%s" "%s"' "$ACTIVE_REGISTRY" "$task_id" "$phase" >/dev/null 2>&1; then
        _emit "${tid}" "phase_mirror_miss" "task=${tid} phase=${phase}" || _EMIT_MISS=$((_EMIT_MISS+1))
      fi
    fi
  fi

  return 0
}

# ── _phase_satisfied <sig8> <phase> <accepted-waivers-csv> -> 0 satisfied ─────
# PHASE-GATE-NAMES-EVERYTHING-AT-ONCE-01: lifted verbatim out of cmd_assert's
# mandatory loop so the identical check can run over BOTH the current scope
# (which decides the refusal) and the full contract (which the refusal now
# names). One checker, two questions — never two checkers that can disagree.
_phase_satisfied() {
  local sig8="$1" pname="$2" waivers_csv="${3:-}"

  local aw
  for aw in $(printf '%s' "$waivers_csv" | tr ',' ' '); do
    [[ "$aw" == "$pname" ]] && return 0
  done

  local pfile
  pfile="$(_phase_file "$sig8" "$pname")"
  [[ -f "$pfile" ]] || return 1

  local p_status
  p_status="$(grep '^status:' "$pfile" 2>/dev/null | awk '{print $2}' || true)"
  case "$p_status" in
    done|waived)
      local p_artifact p_sha p_commit p_reason
      p_artifact="$(grep '^artifact:' "$pfile" 2>/dev/null | sed 's/^artifact:[[:space:]]*//' || true)"
      p_sha="$(grep '^artifact_sha256:' "$pfile" 2>/dev/null | awk '{print $2}' || true)"
      p_commit="$(grep '^commit:' "$pfile" 2>/dev/null | awk '{print $2}' || true)"
      # PHASE-BOOTSTRAP-ADMIT-02: gate1's explicit-decision fallback reads this
      # back on re-assert (e.g. a Phase-4 re-entry days later), same as
      # p_artifact/p_sha/p_commit above -- sed, not awk, since a decision
      # reason is free text and may contain spaces.
      p_reason="$(grep '^reason:' "$pfile" 2>/dev/null | sed 's/^reason:[[:space:]]*//' || true)"
      if [[ "$pname" != "classify" && "$pname" != "diverge" ]]; then
        _verify_artifact "$sig8" "$pname" "$p_artifact" "$p_sha" "$p_commit" "$p_reason" && return 0
        return 1
      fi
      return 0
      ;;
    n/a)
      return 0
      ;;
  esac
  # running (and anything else) is not proven
  return 1
}

# ── assert subcommand ─────────────────────────────────────────────────────────
cmd_assert() {
  local sig8="" cls="" writes="" scope="full" caller_bootstrap=0
  local -a waivers=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --class)
        cls="$2"; shift 2 ;;
      --waiver)
        waivers+=("$2"); shift 2 ;;
      --writes)
        writes="$2"; shift 2 ;;
      --pre-build)
        scope="pre-build"; shift ;;
      --at-bootstrap)
        caller_bootstrap=1; shift ;;
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

  # PHASE-BOOTSTRAP-01 (DISPATCH-PHASE-DEADLOCK-01): capture whether this lane
  # has ANY phase record at all, BEFORE the waiver loop below can create one.
  # A lane with zero records has never started — that is not the same fact as
  # "phases were skipped after starting", and conflating the two is exactly
  # what produced the deadlock this const exists to prevent (a new lane
  # refused for missing phases it had no way to satisfy). The instant one
  # phase record exists (classify, written by dispatch-code right before it
  # calls the guard, is the common case), bootstrap is over for every later
  # assert on this sig8 — full enforcement resumes.
  #
  # Deliberately scoped to scope=="pre-build" ONLY: the reported deadlock is
  # the dispatch-code admission guard's pre-build re-entry check (_phase_
  # precondition_guard's D3 default for Standard/Heavy). A full-scope assert
  # (build/test/review/deploy/close mandatory too) fires later in a lane's
  # life, when zero phase records is a much stronger signal that nothing ran
  # at all — test-phase-precondition.sh's own Test 1 locks that full-scope
  # refusal in and must keep failing a bootstrap-state full assert.
  local _lane_bootstrap=0
  if [[ "$scope" == "pre-build" ]]; then
    _lane_bootstrap=1
    local _phases_d_probe
    _phases_d_probe="$(_phases_d "$sig8")"
    if [[ -d "$_phases_d_probe" ]]; then
      local _probe_f
      for _probe_f in "$_phases_d_probe"/*.yaml; do
        [[ -f "$_probe_f" ]] || continue
        _lane_bootstrap=0
        break
      done
    fi
    # PHASE-GATE-IS-INVERTED-01: the round-2 caller-attested --at-bootstrap
    # flag is DEAD. Forwarding the caller's own pre-classify probe inverts the
    # gate: a brand-new lane (the one nobody has planned) was always admitted
    # because dispatch-code probed "zero records" before writing its own
    # classify, then handed that stale answer here — while a resumed lane,
    # which has records, was the only kind ever enforced (measured 2026-09-01:
    # faee3fc5 shipped to main with no plan and no gate1). The bootstrap fact
    # is now derived ONLY from the store, by this checker, at assert time.
    # The flag is still parsed so old callers do not die on a usage error, but
    # it decides nothing and its presence is journalled.
    if [[ "$caller_bootstrap" == "1" ]]; then
      _emit "${sig8}" "bootstrap_claim_ignored" "task=${sig8} reason=caller_attested_bootstrap_removed" || _EMIT_MISS=$((_EMIT_MISS+1))
    fi
  fi

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
    _emit "${sig8}" "phase_waived" "task=${sig8} phase=${w_phase} reason=${w_reason}" || _EMIT_MISS=$((_EMIT_MISS+1))
  done

  # Resolve mandatory set, in THIS scope and — PHASE-GATE-NAMES-EVERYTHING-AT-ONCE-01
  # — across the FULL contract as well, so one refusal can name everything the
  # lane will eventually have to satisfy instead of revealing it an installment
  # at a time.
  local waivers_csv
  waivers_csv="$(IFS=,; printf '%s' "${accepted_waivers[*]-}")"
  local missing=() required_full=() unmet_full=()
  if [[ "$scope" == "full" ]]; then
    while IFS=' ' read -r kind pname reason_text; do
      [[ "$kind" == "MANDATORY" ]] || continue
      required_full+=("$pname")
      if ! _phase_satisfied "$sig8" "$pname" "$waivers_csv"; then
        missing+=("$pname"); unmet_full+=("$pname")
      fi
    done < <(_resolve_mandatory "$cls" "$writes" full)
  else
    # pre-build scope. The scoped loop decides the refusal; the full loop only
    # NAMES the rest of the contract, and the phases it adds (build/test/review/
    # deploy/live_verify/e2e/close) are disjoint from the scoped set
    # (classify/diverge/plan/gate1), so no phase is verified twice here either.
    local scoped_pnames=" "
    while IFS=' ' read -r kind pname reason_text; do
      [[ "$kind" == "MANDATORY" ]] || continue
      scoped_pnames="${scoped_pnames}${pname} "
      _phase_satisfied "$sig8" "$pname" "$waivers_csv" || missing+=("$pname")
    done < <(_resolve_mandatory "$cls" "$writes" "$scope")
    local _m
    while IFS=' ' read -r kind pname reason_text; do
      [[ "$kind" == "MANDATORY" ]] || continue
      required_full+=("$pname")
      if [[ "$scoped_pnames" == *" ${pname} "* ]]; then
        # Already answered by the scoped loop above — reuse it rather than
        # re-running a checker that can have side effects.
        for _m in ${missing[@]+"${missing[@]}"}; do
          [[ "$_m" == "$pname" ]] && unmet_full+=("$pname") && break
        done
      else
        _phase_satisfied "$sig8" "$pname" "$waivers_csv" || unmet_full+=("$pname")
      fi
    done < <(_resolve_mandatory "$cls" "$writes" full)
  fi
  local required_csv unmet_csv
  required_csv="$(IFS=,; printf '%s' "${required_full[*]-}")"
  unmet_csv="$(IFS=,; printf '%s' "${unmet_full[*]-}")"

  if [[ ${#missing[@]} -gt 0 ]]; then
    local csv
    csv="$(IFS=,; printf '%s' "${missing[*]}")"
    if [[ "$_lane_bootstrap" == "1" ]]; then
      # PHASE-BOOTSTRAP-01: this lane has never recorded a single phase — admit
      # unconditionally. Do NOT read this as "always true for this sig8": the
      # very next assert call, once the caller has recorded even one phase
      # (classify at minimum), re-derives _lane_bootstrap=0 and enforces the
      # missing set above exactly as before.
      _emit "${sig8}" "phase_precondition_bootstrap" "task=${sig8} class=${cls} would_be_missing=${csv}" || _EMIT_MISS=$((_EMIT_MISS+1))
      # PHASE-GATE-DEFAULT-CLASS-ESCAPES-IT-01 (B): the caller-side trace. _emit
      # above reaches only an argv-agnostic stub under the tests; the real
      # leadv2-journal.sh CLI is `append <task-id> <type> <text>`, so the event
      # was dropped live (dispatch-96d97702, 2026-09-04: zero phase_precondition
      # lines). Print the admission on stdout so _phase_precondition_guard can
      # journal it through its own working emit.
      printf 'admitted=bootstrap would_be_missing=%s\n' "$csv"
      printf 'required=%s\n' "$required_csv"
      printf 'unmet=%s\n' "$unmet_csv"
      exit 0
    fi
    printf 'missing=%s\n' "$csv"
    # PHASE-GATE-NAMES-EVERYTHING-AT-ONCE-01: the gate knows the class's whole
    # mandatory contract before it refuses anything, so it must say it once.
    # Measured 2026-09-05 on a Standard lane with only classify recorded: the
    # pre-build refusal says `missing=plan,gate1`, while the SAME lane in the
    # SAME state owes `plan,gate1,build,test,review,live_verify,close` — five
    # phases the operator only meets on a later dispatch cycle, at roughly two
    # minutes a discovery.
    printf 'required=%s\n' "$required_csv"
    printf 'unmet=%s\n' "$unmet_csv"
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
  printf '%-14s %-10s %-14s %-24s %-12s\n' "PHASE" "STATUS" "PROOF" "OWNER" "STARTED"
  printf '%s\n' "------------------------------------------------------------"
  local f
  for f in "$phases_d"/*.yaml; do
    [[ -f "$f" ]] || continue
    local p s o st pr
    p="$(grep '^phase:' "$f" | awk '{print $2}')"
    s="$(grep '^status:' "$f" | awk '{print $2}')"
    o="$(grep '^owner:' "$f" | awk '{print $2}')"
    st="$(grep '^started_at:' "$f" | awk '{print $2}')"
    pr="$(grep '^proof:' "$f" | awk '{print $2}')"
    case "$pr" in
      attested) pr="self-attested" ;;
      verified) pr="verified" ;;
      unverified) pr="UNVERIFIED" ;;
      *) pr="-" ;;
    esac
    printf '%-14s %-10s %-14s %-24s %-12s\n' "$p" "$s" "$pr" "$o" "$st"
  done
}

# ── plan-for subcommand ──────────────────────────────────────────────────────
cmd_plan_for() {
  local cls="" writes=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --class) cls="$2"; shift 2 ;;
      --writes) writes="$2"; shift 2 ;;
      --*) _log_err "plan-for: unknown flag: $1"; exit 4 ;;
      *) shift ;;
    esac
  done
  [[ -n "$cls" ]] || { _log_err "plan-for: --class required"; exit 4; }

  case "$cls" in
    Trivial|Light|Standard|Heavy) ;;
    *) _log_err "plan-for: invalid class '$cls'"; exit 4 ;;
  esac

  _resolve_mandatory "$cls" "$writes"
}

# ── is-bootstrap: does this lane have zero phase records? ────────────────────
# exit 0 iff phases.d is absent or carries no record; 1 otherwise. Read-only
# probe; no caller's answer to it is trusted by cmd_assert any more
# (PHASE-GATE-IS-INVERTED-01 removed the caller-attested --at-bootstrap — the
# guard derives bootstrap state itself from the store).
cmd_is_bootstrap() {
  local sig8=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --*)
        _log_err "is-bootstrap: unknown flag: $1"; exit 4 ;;
      *)
        if [[ -z "$sig8" ]]; then sig8="$1"; else _log_err "is-bootstrap: unexpected positional: $1"; exit 4; fi
        shift ;;
    esac
  done
  [[ -n "$sig8" ]] || { _log_err "is-bootstrap: <sig8> required"; exit 4; }
  local d probe_f
  d="$(_phases_d "$sig8")"
  [[ -d "$d" ]] || return 0
  for probe_f in "$d"/*.yaml; do
    [[ -f "$probe_f" ]] || return 0
    return 1
  done
}

# ── main ──────────────────────────────────────────────────────────────────────
[[ $# -eq 0 ]] && { _log_err "usage: $0 <record|assert|show|plan-for|is-bootstrap> ..."; exit 4; }
cmd="$1"; shift
case "$cmd" in
  record)   cmd_record "$@" ;;
  assert)   cmd_assert "$@" ;;
  show)     cmd_show "$@" ;;
  plan-for) cmd_plan_for "$@" ;;
  is-bootstrap) cmd_is_bootstrap "$@" ;;
  -h|--help) _log "usage: $0 <record|assert|show|plan-for|is-bootstrap> ..."; exit 0 ;;
  *)        _log_err "unknown command: $cmd"; exit 4 ;;
esac
