#!/usr/bin/env bash
# lib/leadv2-worker-mcp.sh — role-scoped MCP resolution for worker spawns.
#
# T14 (2026-08-26): extracted verbatim from claude-subsession.sh
# (WORKER-CONTEXT-DIET-01 D-A) so the glm-coder.sh spawn path shares ONE
# resolution implementation with the claude-subsession.sh escalation path --
# never a drifting copy (single-source rule). The old in-function
# LEADV2_SUBSESSION_SLIM_MCP kill-switch check moved OUT to the callers:
#   - claude-subsession.sh gates on LEADV2_SUBSESSION_SLIM_MCP (default 0, opt-in)
#   - glm-coder.sh gates on LEADV2_WORKER_MCP (default 1: dispatched workers
#     get the role-scoped code-intel MCP servers by default; =0 restores the
#     pre-T14 behaviour of no --mcp-config on the spawn line)
# The two switches are intentionally SEPARATE (disjoint spawn paths, one
# shared resolver here) — neither implies the other.
#
# resolve_role_mcp_config()
#   Input : $1 = role name, $2 = handoff dir (for the resolved-config output),
#           $3 = project root (defaults to $PROJECT_ROOT) -- where .mcp.json
#           and .claude/settings.json are read from
#   Output: path to a resolved --mcp-config JSON file (stdout) on rc=0
#   Return: 0 success | 11 no allowlist | 12 nothing resolved | 13
#           parse/validation failure | 14 python3 missing
#           | 15 handoff dir/resolved-config write failure
#
# Every non-zero rc is FAIL-OPEN: caller must treat empty stdout as "append
# no MCP flags", never as an error to propagate. A malformed --mcp-config on
# the backgrounded arm would kill the spawned `claude` after `setsid_wrapper`
# already returned a PID, scoring the lane as "opened and closed with no
# work" -- see docs/handoff/dispatch-9341e2eb-architect/architect.full.md §2a.
#
# plugins/leadv2/config/mcp-role-<role>.json holds an ALLOWLIST OF SERVER
# NAMES ONLY, never server definitions: repowise is registered per-repo with
# different commands (and the user-level definition is hard-pinned to this
# repo's path), so a baked definition would silently point a worker at the
# wrong repo's index. Definitions are resolved here, at spawn time, from the
# live config chain (.mcp.json -> .claude/settings.json -> ~/.claude/settings.json).
# ---------------------------------------------------------------------------
resolve_role_mcp_config() {
  local role="$1"
  local handoff_dir="$2"
  local project_root="${3:-${PROJECT_ROOT:-}}"

  local safe_role="$role"
  [[ "$safe_role" =~ ^[a-z0-9-]+$ ]] || safe_role="default"

  # BASH_SOURCE[0] is THIS lib file (scripts/lib/), so .. is the scripts dir
  # and ../.. the plugin root -- same resolution as the original inline
  # function in claude-subsession.sh.
  local _script_dir
  _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local config_dir="${CLAUDE_PLUGIN_ROOT:-${_script_dir}/..}/config"
  local allow_file="${config_dir}/mcp-role-${safe_role}.json"
  if [[ ! -f "$allow_file" ]]; then
    allow_file="${config_dir}/mcp-role-default.json"
  fi
  if [[ ! -f "$allow_file" ]]; then
    echo "[worker-mcp] WARN context-diet: no mcp allowlist for role=${role} — spawning with full MCP set" >&2
    return 11
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "[worker-mcp] WARN context-diet: python3 not found — spawning with full MCP set" >&2
    return 14
  fi

  local resolved_path="${handoff_dir}/mcp-role-${safe_role}.resolved.json"

  local py_out py_rc
  set +e
  py_out=$(python3 - "$allow_file" "$project_root" "$HOME" <<'PYEOF'
import json, os, sys

allow_file, project_root, home = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(allow_file) as f:
        allow = json.load(f)
except Exception:
    print("PARSE_ERROR", file=sys.stderr)
    sys.exit(13)

servers = allow.get("servers")
if not isinstance(servers, list):
    print("PARSE_ERROR: servers not a list", file=sys.stderr)
    sys.exit(13)

names = []
seen = set()
for n in servers:
    if not isinstance(n, str):
        print("WARN_SKIP non-string server name", file=sys.stderr)
        continue
    if n in seen:
        continue
    seen.add(n)
    names.append(n)

sources = []
if project_root and os.path.isdir(project_root):
    sources.append(os.path.join(project_root, ".mcp.json"))
    sources.append(os.path.join(project_root, ".claude", "settings.json"))
if home:
    sources.append(os.path.join(home, ".claude", "settings.json"))

resolved = {}
unresolved = list(names)
for src in sources:
    if not unresolved:
        break
    if not os.path.isfile(src):
        continue
    try:
        with open(src) as f:
            data = json.load(f)
    except Exception:
        print("WARN_SKIP malformed source %s" % src, file=sys.stderr)
        continue
    servers_obj = data.get("mcpServers")
    if not isinstance(servers_obj, dict):
        continue
    still_unresolved = []
    for name in unresolved:
        defn = servers_obj.get(name)
        if isinstance(defn, dict) and "command" in defn:
            resolved[name] = defn
        else:
            still_unresolved.append(name)
    unresolved = still_unresolved

for name in unresolved:
    print("WARN_UNRESOLVED %s" % name, file=sys.stderr)

if not resolved and names:
    sys.exit(12)

print(json.dumps({"mcpServers": resolved}))
sys.exit(0)
PYEOF
  )
  py_rc=$?
  set -e

  if [[ $py_rc -eq 12 ]]; then
    echo "[worker-mcp] WARN context-diet: role=${role} servers unresolved in .mcp.json/.claude/settings.json/~/.claude/settings.json — spawning with full MCP set" >&2
    return 12
  fi
  if [[ $py_rc -ne 0 ]]; then
    echo "[worker-mcp] WARN context-diet: role=${role} allowlist ${allow_file} malformed or unreadable — spawning with full MCP set" >&2
    return 13
  fi

  if ! mkdir -p "$handoff_dir" 2>/dev/null || ! printf '%s' "$py_out" > "$resolved_path" 2>/dev/null; then
    echo "[worker-mcp] WARN context-diet: role=${role} cannot write ${resolved_path} — spawning with full MCP set" >&2
    return 15
  fi
  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$resolved_path" >/dev/null 2>&1; then
    echo "[worker-mcp] WARN context-diet: role=${role} resolved config failed round-trip validation — spawning with full MCP set" >&2
    rm -f "$resolved_path" 2>/dev/null || true
    return 13
  fi

  printf '%s' "$resolved_path"
  return 0
}

# ---------------------------------------------------------------------------
# worker_mcp_preamble_for_arm() — WORKER-MCP-ALL-ARMS-01 R3 (review H2).
#
# The dispatcher may inject the code-intel preamble (which tells the worker to
# call mcp__* tools) ONLY into spawns that will actually carry the role-scoped
# MCP config. Round 2 injected it unconditionally for every arm, so codex
# (which has no MCP wiring at all) and every fail-open path received missions
# promising tools that provably do not exist in that session.
#
# This predicate is implemented ON TOP of resolve_role_mcp_config() — never a
# second resolver — because the launchers make the attach decision through
# THIS SAME lib at spawn time (same gate env, same role, same config chain,
# same fail-open taxonomy). The prediction is therefore deterministic; the
# launcher's worker_mcp_attached / worker_mcp_skipped journal line stays the
# record of what actually happened.
#
#   Input : $1 = arm (glm|glm-flash|kimi|freepool|sonnet|codex)
#           $2 = project root the worker will cwd into (config-chain source)
#           $3 = out dir for the resolved probe (optional; a private mktemp
#                scratch is used and removed when empty)
#   Output: rc=0  attached  → the full worker-code-intel-preamble.md on stdout
#           rc=3  fail-open → nothing on stdout (WORKER-MCP-ALL-ARMS-01 R4:
#                             every fail-open path here skips ONLY the
#                             role-scoped diet resolve — the launcher still
#                             appends no --strict-mcp-config, so the child
#                             `claude` falls back to inheriting the project's
#                             FULL default MCP set, same as an un-dieted
#                             session. A "code-intel MCP unavailable" note on
#                             this branch was therefore backwards: it told the
#                             session with the widest tool set to stop using
#                             tools it still has. Silence is the only claim
#                             that is never false here.)
#           rc=4  unwired   → nothing on stdout (arm has no MCP wiring at
#                             all — codex; this is the one branch where "no
#                             mcp__* tools" is actually true)
#   Every rc is a decision, never an error to propagate — the caller only
#   picks the printed text (or its absence) and logs the mode.
worker_mcp_preamble_for_arm() { # $1=arm $2=project root (worker cwd) $3=out dir (optional)
  local arm="$1" project_root="$2" out_dir="${3:-}"
  local role="${LEADV2_WORKER_ROLE:-developer}"
  [[ "${role}" =~ ^[a-z0-9-]+$ ]] || role="developer"

  case "${arm}" in
    codex)
      # codex-task.sh has NO MCP wiring (the companion spawns its own task
      # worker with fixed argv; probed 2026-09-02) — promising mcp__* tools
      # there is a falsehood the worker cannot satisfy.
      return 4
      ;;
    sonnet)
      # claude-subsession.sh resolves role MCP only under the opt-in
      # LEADV2_SUBSESSION_SLIM_MCP=1; the default (0) spawn appends no
      # --mcp-config and writes no worker_mcp_attached record, so the honest
      # answer is "not attached" — never promise.
      if [[ "${LEADV2_SUBSESSION_SLIM_MCP:-0}" != "1" ]]; then
        # No --mcp-config is appended on this path (see doc block above) —
        # the child inherits the FULL default MCP set, so printing "MCP
        # unavailable" here would be false. Say nothing.
        return 3
      fi
      ;;
    *)
      # glm/glm-flash/kimi/freepool launchers gate on LEADV2_WORKER_MCP
      # (default 1). Mirror their default exactly.
      if [[ "${LEADV2_WORKER_MCP:-1}" != "1" ]]; then
        # Same fail-open shape: worker_mcp_resolve() short-circuits, no
        # --strict-mcp-config is appended, the child inherits the FULL
        # default MCP set. Say nothing rather than claim it has none.
        return 3
      fi
      ;;
  esac

  local scratch=""
  if [[ -z "${out_dir}" ]]; then
    scratch="$(mktemp -d "${TMPDIR:-/tmp}/worker-mcp-preamble.XXXXXX")" || scratch=""
    if [[ -z "${scratch}" ]]; then
      # Can't run the prediction probe at all — unknown, not "unavailable".
      # The real launcher's own resolve call is unaffected by this failure.
      return 3
    fi
    out_dir="${scratch}"
  fi
  local mcp_cfg="" rc=0
  mcp_cfg="$(resolve_role_mcp_config "${role}" "${out_dir}" "${project_root}")" || rc=$?
  [[ -z "${scratch}" ]] || rm -rf "${scratch}" 2>/dev/null || true
  if [[ ${rc} -ne 0 || -z "${mcp_cfg}" ]]; then
    # resolve_role_mcp_config() failed/returned nothing -- its own callers
    # (this same fail-open taxonomy) fall back to spawning with the FULL
    # default MCP set, never zero. Say nothing rather than claim otherwise.
    return 3
  fi

  local _script_dir
  _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # Preamble is resolved LIB-RELATIVE FIRST: the launcher runs from the tree
  # that ships this lib, so its prompts/ sibling is the live copy.
  # CLAUDE_PLUGIN_ROOT (an installed/cache copy) is only a fallback and can be
  # stale — a fresh prompts file does not exist there until the plugin is
  # redeployed (observed 2026-09-02: installed copy predates this lane).
  local preamble_file="${_script_dir}/../prompts/worker-code-intel-preamble.md"
  [[ -f "${preamble_file}" ]] || preamble_file="${CLAUDE_PLUGIN_ROOT:-${_script_dir}/..}/prompts/worker-code-intel-preamble.md"
  if [[ ! -f "${preamble_file}" ]]; then
    # mcp_cfg resolved fine -- this spawn WILL attach role-scoped MCP, only
    # the routing-text file is missing. "MCP unavailable" would be false in
    # the opposite direction from the other rc=3 branches (this one really
    # does attach); say nothing rather than assert either way.
    return 3
  fi
  cat "${preamble_file}"
  return 0
}
