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
#                OR a brief/fix-round file the dispatch was    attested
#                launched with (docs/handoff/<task>/brief.md
#                or fix-round-N.md), non-empty
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

# B1 R1: the review-arm vocabulary. Source of truth:
# scripts/lib/leadv2-glm-policy-resolve.py:66 (DEFAULT_REVIEW_ARM_ORDER).
# A repo with a novel arm overrides via LEADV2_REVIEW_ARMS.
REVIEW_ARMS="${LEADV2_REVIEW_ARMS:-codex,glm,kimi,opus,sonnet}"

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
# Returns 0 if artifact is proven, 1 otherwise. On a 0 return for plan/gate1,
# also sets _VA_STRENGTH to "verified" (machine-checked artifact) or
# "attested" (lead-authored brief / explicit recorded decision) — cmd_record
# reads this to stamp the proof field honestly (§ DISPATCH-PHASE-DEADLOCK-01).
_VA_STRENGTH=""
_verify_artifact() {
  local sig8="$1" phase="$2" artifact="${3:-}" sha="${4:-}" commit="${5:-}" reason="${6:-}"
  _VA_STRENGTH=""
  case "$phase" in
    plan)
      # context.yaml or prepass file with non-empty design — machine-checked,
      # full proof.
      local prepass_file
      prepass_file="$(_prepass_file "$sig8" 2>/dev/null)"
      if [[ -n "$prepass_file" && -s "$prepass_file" ]]; then _VA_STRENGTH="verified"; return 0; fi
      local ctx_file="${PHASES_DIR_BASE}/dispatch-${sig8}/context.yaml"
      if [[ -s "$ctx_file" ]] && grep -q 'decisions' "$ctx_file" 2>/dev/null; then _VA_STRENGTH="verified"; return 0; fi
      # DISPATCH-PHASE-DEADLOCK-01: a lead-authored brief or fix-round note is
      # a real plan — it just does not live in context.yaml. Accept it, but
      # only ever as "attested": this is a human artifact, not a
      # machine-checked one, and the distinction must not be lost. Restricted
      # to the docs/handoff/<task>/{brief.md,fix-round-N.md} naming so an
      # arbitrary --artifact string cannot forge plan proof.
      if [[ -n "$artifact" ]]; then
        local _resolved=""
        if [[ -f "${PROJECT_ROOT}/${artifact}" ]]; then _resolved="${PROJECT_ROOT}/${artifact}"
        elif [[ -f "$artifact" ]]; then _resolved="$artifact"
        fi
        if [[ -n "$_resolved" && -s "$_resolved" ]] \
           && printf '%s' "$artifact" | grep -qE '^(.*/)?docs/handoff/[^/]+/(brief\.md|fix-round-[0-9]+\.md)$'; then
          _VA_STRENGTH="attested"
          return 0
        fi
      fi
      return 1
      ;;
    gate1)
      local gate_file="${PHASES_DIR_BASE}/dispatch-${sig8}/.gate1-passed"
      if [[ -s "$gate_file" ]]; then _VA_STRENGTH="verified"; return 0; fi
      # DISPATCH-PHASE-DEADLOCK-01: when the lead has taken gate 1 without
      # going through leadv2-gate1-prompt.sh (which writes the sentinel
      # above), the phase record itself — carrying a non-empty --reason that
      # explains the decision — IS the record of that decision. Weaker than
      # the sentinel (no filesystem proof beyond the phases.d record a lead
      # or worker could equally have written), so "attested", never
      # "verified".
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
            _emit "review_ledger_tamper" "repo=${slug} ledger_rows=${_ledger_rows} recorded_rows=${_recorded_rows}"
            return 1
          fi
        fi
      else
        # Sidecar absent.  If the adopted marker exists, the sidecar was created
        # (and later deleted) → tamper, reject.  Only a repo that never used the
        # sidecar mechanism gets the legacy accept.
        if [[ -f "$_adopted" ]]; then
          _emit "review_sidecar_tamper" "repo=${slug} sidecar=${sidecar##*/} adopted=${_adopted##*/}"
          return 1
        fi
        _emit "review_ledger_unchained" "repo=${slug}"
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
arms = set(os.environ.get("LEADV2_REVIEW_ARMS", "codex,glm,kimi,opus,sonnet").split(","))
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
  # the phase is gate1 with a non-empty --reason (DISPATCH-PHASE-DEADLOCK-01:
  # an explicit recorded gate decision is admissible gate1 evidence in its
  # own right — see _verify_artifact).
  if [[ "$status" == "done" && -z "$artifact" ]] \
     && [[ "$phase" != "classify" && "$phase" != "diverge" ]] \
     && ! [[ "$phase" == "gate1" && -n "$reason" ]]; then
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
    # §3 honesty: run the SAME _verify_artifact path that assert uses.
    # proof=verified only when _verify_artifact accepts; otherwise unverified.
    # test/live_verify/e2e are "attested" (sha256 match only, not semantic proof).
    # Running/n/a/waived phases get an empty proof — it does not apply.
    local _proof=""
    if [[ "$status" == "done" ]]; then
      if _verify_artifact "$sig8" "$phase" "$artifact" "$sha" "$commit" "$reason" 2>/dev/null; then
        case "$phase" in
          test|live_verify|e2e) _proof="attested" ;;
          plan|gate1) _proof="${_VA_STRENGTH:-verified}" ;;
          *) _proof="verified" ;;
        esac
      else
        _proof="unverified"
        _log "WARN: phase '$phase' for $sig8 recorded done but proof NOT verified — assert will refuse"
      fi
    fi
    printf 'proof: %s\n' "$_proof"
    [[ -n "$commit" ]] && printf 'commit: %s\n' "$commit"
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
  local sig8="" cls="" writes="" scope="full"
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
          local p_artifact p_sha p_commit p_reason
          p_artifact="$(grep '^artifact:' "$pfile" 2>/dev/null | sed 's/^artifact:[[:space:]]*//' || true)"
          p_sha="$(grep '^artifact_sha256:' "$pfile" 2>/dev/null | awk '{print $2}' || true)"
          p_commit="$(grep '^commit:' "$pfile" 2>/dev/null | awk '{print $2}' || true)"
          p_reason="$(grep '^reason:' "$pfile" 2>/dev/null | sed 's/^reason:[[:space:]]*//' || true)"

          # For non-conditional phases, verify artifact
          if [[ "$pname" != "classify" && "$pname" != "diverge" ]]; then
            if _verify_artifact "$sig8" "$pname" "$p_artifact" "$p_sha" "$p_commit" "$p_reason"; then
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
  done < <(_resolve_mandatory "$cls" "$writes" "$scope")

  if [[ ${#missing[@]} -gt 0 ]]; then
    local csv
    csv="$(IFS=,; printf '%s' "${missing[*]}")"
    if [[ "$_lane_bootstrap" == "1" ]]; then
      # PHASE-BOOTSTRAP-01: this lane has never recorded a single phase — admit
      # unconditionally. Do NOT read this as "always true for this sig8": the
      # very next assert call, once the caller has recorded even one phase
      # (classify at minimum), re-derives _lane_bootstrap=0 and enforces the
      # missing set above exactly as before.
      _emit "phase_precondition_bootstrap" "task=${sig8} class=${cls} would_be_missing=${csv}"
      exit 0
    fi
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
