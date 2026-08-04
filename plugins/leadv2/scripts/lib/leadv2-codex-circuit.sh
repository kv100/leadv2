#!/usr/bin/env bash
# lib/leadv2-codex-circuit.sh — circuit breaker for codex usage-limit refusals.
#
# While open, every codex spawn arm is refused and work spills to the ladder
# (glm→sonnet per policy). Auto-closes when now >= until. One marker per repo,
# shared across all worktrees via the leadv2 control-plane state dir.
#
# Sourced by codex-task.sh and leadv2-codex-session-runner.sh (via the
# quota-gate lib). Does not change shell options; every public API fails open
# on read errors it cannot attribute, except codex_circuit_state which
# distinguishes "closed" (healthy) from "unknown" (control plane unreachable).

# Resolve the circuit marker path.
#   Honors LEADV2_CODEX_CIRCUIT_FILE (test seam) then leadv2-state-path.sh.
#   Returns 0 + path on stdout, or rc 1 if the control plane is unresolvable.
codex_circuit_path() {
  if [[ -n "${LEADV2_CODEX_CIRCUIT_FILE:-}" ]]; then
    printf '%s' "$LEADV2_CODEX_CIRCUIT_FILE"
    return 0
  fi
  local _script_dir _resolver _path
  _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _resolver="$_script_dir/leadv2-state-path.sh"
  _path="$(env PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}" "$_resolver" --no-link codex-circuit.json 2>/dev/null)" || return 1
  [[ -n "$_path" ]] || return 1
  printf '%s' "$_path"
}

# Read circuit state.
#   stdout: "open <until_iso> <source>" | "closed" | "unknown"
#   "unknown" = marker file exists but is unparseable (corruption — fail-closed).
#   Path-unresolvable (no git / isolated env) ⇒ "closed" — bricking codex on an
#   infrastructure gap is worse than missing a circuit (R4: CODEX_SKIP_QUOTA_GATE
#   hatch covers the deliberate-bypass case).
#   Always rc 0 — the caller decides fail-open vs fail-closed based on the value.
codex_circuit_state() {
  local _path _raw _until _source _now
  _path="$(codex_circuit_path 2>/dev/null)" || { printf 'closed'; return 0; }
  [[ -n "$_path" ]] || { printf 'closed'; return 0; }
  [[ -f "$_path" ]] || { printf 'closed'; return 0; }
  _raw="$(cat "$_path" 2>/dev/null)" || { printf 'unknown'; return 0; }
  _until="$(printf '%s' "$_raw" | python3 -c '
import sys, json
try:
    o = json.load(sys.stdin)
    print(o.get("until",""))
except Exception:
    sys.exit(1)
' 2>/dev/null)" || { printf 'unknown'; return 0; }
  [[ -n "$_until" ]] || { printf 'unknown'; return 0; }
  # Auto-close: lexicographic comparison works on ISO-8601 UTC strings.
  _now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || { printf 'unknown'; return 0; }
  if [[ "$_now" > "$_until" ]]; then
    printf 'closed'
    return 0
  fi
  _source="$(printf '%s' "$_raw" | python3 -c '
import sys, json
try:
    o = json.load(sys.stdin)
    print(o.get("source","unknown"))
except Exception:
    print("unknown")
' 2>/dev/null)" || _source="unknown"
  printf 'open %s %s' "$_until" "$_source"
}

# Parse "try again at <text>" from stdin → ISO-8601 UTC.
# Verbatim lift of the date parser from codex-task.sh:311-333.
# rc 0 + ISO on stdout, or rc 1 when the text does not parse.
codex_circuit_parse_until() {
  local _reset_text
  _reset_text="$(grep -oiE 'try again at [^.)]+' 2>/dev/null | head -1 \
    | sed -E 's/^[Tt]ry again at[[:space:]]*//; s/[.)]+$//')" || true
  [[ -n "$_reset_text" ]] || return 1
  printf '%s' "$_reset_text" | python3 -c '
import sys, re, datetime
s = sys.stdin.read().strip()
s2 = re.sub(r"(\d+)(st|nd|rd|th)", r"\1", s)
fmts = ["%b %d, %Y %I:%M %p", "%b %d, %Y %H:%M", "%B %d, %Y %I:%M %p",
        "%B %d, %Y %H:%M", "%d %b %Y %I:%M %p", "%d %B %Y %I:%M %p"]
for f in fmts:
    try:
        dt = datetime.datetime.strptime(s2, f)
        print(dt.strftime("%Y-%m-%dT%H:%M:%SZ"))
        sys.exit(0)
    except Exception:
        continue
sys.exit(1)
' 2>/dev/null
}

# Open the circuit.
#   $1 = until ISO-8601 (empty/unparseable ⇒ now+24h)
#   $2 = source label (e.g. "codex-task", "session-runner")
#   Idempotent: skips if an equal-or-later circuit is already open.
#   Journals "codex_circuit_open until=<ts>" to stderr exactly once per open.
codex_circuit_open() {
  local _until_raw="${1:-}" _source="${2:-unknown}"
  local _path _until_iso _now _dir

  _path="$(codex_circuit_path 2>/dev/null)" || return 0
  [[ -n "$_path" ]] || return 0

  _now="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)" || return 0

  if [[ -n "$_until_raw" ]]; then
    _until_iso="$_until_raw"
  else
    # now+24h — portable across macOS (date -v) and Linux (date -d)
    _until_iso="$(date -u -v+24H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
               || date -u -d "+24 hours" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)" || return 0
  fi

  # Idempotent: if an existing circuit is open with until >= this one, skip.
  local _existing _existing_until
  _existing="$(codex_circuit_state 2>/dev/null)" || _existing=""
  case "$_existing" in
    open\ *)
      _existing_until="${_existing#open }"
      _existing_until="${_existing_until%% *}"
      if [[ "$_existing_until" > "$_until_iso" ]] || [[ "$_existing_until" == "$_until_iso" ]]; then
        return 0
      fi
      ;;
  esac

  # Ensure parent dir exists.
  _dir="$(dirname "$_path" 2>/dev/null)"
  [[ -n "$_dir" ]] && mkdir -p "$_dir" 2>/dev/null || true

  # Atomic write via mktemp + mv.
  local _tmp
  _tmp="$(mktemp 2>/dev/null)" || return 0
  printf '{"until":"%s","opened_at":"%s","source":"%s","reason":"usage_limit"}\n' \
    "$_until_iso" "$_now" "$_source" > "$_tmp"
  mv -f "$_tmp" "$_path" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 0; }

  # Journal once.
  printf 'codex_circuit_open until=%s\n' "$_until_iso" >&2
}
