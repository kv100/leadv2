#!/usr/bin/env bash
# PreToolUse(Agent): the direct-spawn gate + the legacy Codex-first nudge.
# ROUTING-HAS-NO-ENFORCING-LAYER-01 (2026-09-04, warn-mode landed 2026-09-07):
# a direct Agent() spawn that carries Write/Edit in its tool set and carries no
# recorded reason is JOURNALED as would-deny; read-only recon and sanctioned
# bypass roles (config/direct-spawn-gate.yaml) pass silently. Ships in WARN
# mode (GATE_PERMISSION_DECISION defaults to "warn", never exits 2) because a
# real-data replay (45 historical Agent spawns, 43 would-deny) showed the
# LEADV2-DIRECT-REASON discipline has never once been practiced -- flipping to
# enforce today would stop the fleet over behavior nobody has ever treated as
# a violation. Flip to deny via LEADV2_DIRECT_SPAWN_GATE_MODE=deny once
# would_deny drops from lead behavior change, not from weakening this check
# (see docs/leadv2/scheduled-decisions.md). The Codex-first reminder below
# stays WARN-only for everything the gate allows.
set -euo pipefail
trap 'echo "[$(basename "$0")] error at line $LINENO" >&2; exit 0' ERR

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")"
[[ "$TOOL_NAME" != "Agent" ]] && exit 0

SUBTYPE="$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")"
[[ -z "$SUBTYPE" ]] && exit 0

SUBTYPE_LOWER="$(echo "$SUBTYPE" | tr '[:upper:]' '[:lower:]')"

# ── DIRECT-SPAWN GATE (ROUTING-HAS-NO-ENFORCING-LAYER-01) ──────────────────────────────────────────────
# The discriminator is the CAPABILITY TO WRITE, never a list of names: a spawn
# whose effective tool set carries Write/Edit (explicit tool_input.tools, the
# target's agent definition frontmatter, or unprovable read-onlyness) and
# whose caller recorded no reason is flagged -- on every provider, with no
# model or provider name anywhere in the predicate. Passes untouched: provably
# read-only targets (recon), roles granted as sanctioned dispatcher bypasses
# in direct-spawn-gate.yaml (default-deny config), and prompts carrying a
# recorded LEADV2-DIRECT-REASON line (allowed only when the journal write
# succeeds -- recorded, not asserted). Nested spawns (agent_type present)
# belong to leadv2-routing-guard.sh and never reach this gate. Kill switches:
# LEADV2_DIRECT_SPAWN_GATE=0, or per-repo override
# .claude/leadv2-overrides/direct-spawn-gate.yaml with enabled: false.
GATE_PERMISSION_DECISION="${LEADV2_DIRECT_SPAWN_GATE_MODE:-warn}"

_gate_journal() { # <decision> -> rc 0 only when the line landed in the journal
  local decision="$1" line
  line="$(python3 -c "
import json, sys, time
print(json.dumps({
    'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'event': 'direct_spawn_gate',
    'decision': sys.argv[1],
    'session_id': sys.argv[2],
    'repo': sys.argv[3],
    'subagent_type': sys.argv[4],
    'model': sys.argv[5],
    'resolution': sys.argv[6],
    'reason': sys.argv[7],
}))
" "$decision" "$GATE_SESSION_ID" "$PROJECT_ROOT" "$SUBTYPE" "$GATE_MODEL" "$GATE_RES" "$GATE_REASON" 2>/dev/null)" || return 1
  [[ -n "$line" ]] || return 1
  {
    mkdir -p "$(dirname "$GATE_JOURNAL")" 2>/dev/null
    printf '%s\n' "$line" >> "$GATE_JOURNAL"
  } 2>/dev/null
}

_gate_deny() { # <cause> -> way-forward text on stderr, exit 2
  local why="$1" dispatch_bin="" _c
  for _c in "${_LV2_ROOT}/scripts/leadv2-dispatch-code.sh" \
            "${LEADV2_CANONICAL_ROOT:-${HOME:-$PWD}/Projects/leadv2}/plugins/leadv2/scripts/leadv2-dispatch-code.sh" \
            "${PROJECT_ROOT}/plugins/leadv2/scripts/leadv2-dispatch-code.sh"; do
    [[ -f "$_c" ]] && { dispatch_bin="$_c"; break; }
  done
  [[ -n "$dispatch_bin" ]] || dispatch_bin="<leadv2-dispatch-code.sh not found on this machine — plugin install broken; fix before write work>"
  {
    printf '[leadv2-codex-first-nudge] DENIED direct write-capable spawn (subagent_type=%s, model=%s, resolution=%s, cause=%s).\n' "$SUBTYPE" "$GATE_MODEL" "$GATE_RES" "$why"
    printf 'This Agent call was not launched through the dispatcher: no arm selection, no quota accounting, no fallback ladder (ROUTING-HAS-NO-ENFORCING-LAYER-01).\n'
    printf 'Way forward — pick one:\n'
    printf '  1) dispatch the code work (script verified to exist):\n'
    printf '       bash %s "<mission>"\n' "$dispatch_bin"
    printf '  2) or record why Claude must write directly — put this line in the spawn prompt:\n'
    printf '       LEADV2-DIRECT-REASON: <why Claude specifically, one line>\n'
    printf 'Denials and recorded reasons are journaled: %s\n' "$GATE_JOURNAL"
  } >&2
  exit 2
}

CALLER_AGENT_TYPE="$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || echo "")"

CWD="$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")"
[[ -z "$CWD" ]] && CWD="$PWD"
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$CWD")}}"

if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  _LV2_ROOT="${CLAUDE_PLUGIN_ROOT}"
else
  _LV2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

if [[ -z "$CALLER_AGENT_TYPE" && "${LEADV2_DIRECT_SPAWN_GATE:-1}" != "0" ]]; then
  GATE_POLICY_SRC="${_LV2_ROOT}/config/direct-spawn-gate.yaml"
  GATE_OVERRIDE="${PROJECT_ROOT}/.claude/leadv2-overrides/direct-spawn-gate.yaml"
  GATE_ON=1
  if [[ -f "$GATE_OVERRIDE" ]]; then
    GATE_POLICY_SRC="$GATE_OVERRIDE"
    if grep -qE '^[[:space:]]*enabled:[[:space:]]*false' "$GATE_OVERRIDE" 2>/dev/null; then
      GATE_ON=0
    fi
  fi
  if [[ "$GATE_ON" == "1" ]]; then
    GATE_RESULT="$(python3 -c "
import sys, os, re, json

d           = json.loads(sys.argv[1])
policy_src  = sys.argv[2]
plugin_root = sys.argv[3]
project_root = sys.argv[4]
home        = sys.argv[5]

inp        = d.get('tool_input') or {}
stype      = (inp.get('subagent_type') or '').strip()
stype_l    = stype.lower()
prompt     = inp.get('prompt') or ''
tools_param = inp.get('tools')

def emit(wc, sanc, reason, resolution):
    print('WRITE_CAPABLE=%d' % (1 if wc else 0))
    print('SANCTIONED=%d' % (1 if sanc else 0))
    print('REASON=%s' % reason[:200])
    print('RESOLUTION=%s' % resolution)
    sys.exit(0)

# Recorded reason: a line-anchored LEADV2-DIRECT-REASON marker anywhere in the prompt.
reason = ''
for ln in prompt.splitlines():
    m = re.match(r'^[ \t]*LEADV2-DIRECT-REASON:[ \t]*(.+?)[ \t]*$', ln)
    if m:
        reason = m.group(1)
        break

# Grants (default-deny posture; this file can only OPEN doors, never weaken the
# capability predicate). Missing/unreadable policy -> platform-truth fallback:
# explore is read-only, everything else unproven stays write-capable.
grants_ro, grants_sanc, loaded = ['explore'], [], False
src_text = ''
try:
    src_text = open(policy_src, encoding='utf-8', errors='replace').read()
    try:
        import yaml
        p = yaml.safe_load(src_text) or {}
        if isinstance(p, dict):
            grants_ro   = [str(x).lower() for x in (p.get('read_only_builtins') or [])]
            grants_sanc = [str(x).lower() for x in (p.get('sanctioned_bypass_roles') or [])]
            loaded = True
    except ImportError:
        pass
except Exception:
    pass
if not loaded and src_text:
    def _lst(key, text):
        m = re.search(r'^' + key + r':[ \t]*\n((?:[ \t]*-[ \t]*[^\n]+\n?)*)', text, re.M)
        if not m:
            return []
        return [r.strip().lstrip('-').strip().lower()
                for r in m.group(1).strip().splitlines() if r.strip().startswith('-')]
    grants_ro = _lst('read_only_builtins', src_text) or ['explore']
    grants_sanc = _lst('sanctioned_bypass_roles', src_text)

sanc = stype_l in grants_sanc

# Capability 1: explicit per-spawn tool list wins — model- and provider-blind.
WRITE_TOKENS = {'write', 'edit', 'notebookedit', 'notebookeditwrite', '*', 'all'}
if isinstance(tools_param, list) and tools_param:
    tl = set()
    for t in tools_param:
        if isinstance(t, dict):
            t = t.get('name') or ''
        tl.add(str(t).strip().lower())
    emit(bool(WRITE_TOKENS & tl), sanc, reason, 'tools-param')

# Capability 2: the target's agent definition (repo -> plugin -> user), first
# match wins. tools: absent or unparseable == inherits the full set == capable.
safe = re.sub(r'[^A-Za-z0-9._-]', '', stype_l) or 'unknown'
cands = []
if project_root:
    cands.append(os.path.join(project_root, '.claude', 'agents', safe + '.md'))
if plugin_root:
    cands.append(os.path.join(plugin_root, 'agents', safe + '.md'))
if home:
    cands.append(os.path.join(home, '.claude', 'agents', safe + '.md'))
for c in cands:
    try:
        text = open(c, encoding='utf-8', errors='replace').read()
    except Exception:
        continue
    fm = re.match(r'^---[ \t]*\n(.*?)\n---[ \t]*\n', text, re.S)
    if not fm:
        emit(True, sanc, reason, 'definition-unparseable:' + c)
    block = fm.group(1)
    tm = re.search(r'^tools:[ \t]*(.*)$', block, re.M)
    if not tm:
        emit(True, sanc, reason, 'definition-no-tools-field:' + c)
    inline = tm.group(1).strip()
    if inline:
        tl = set(t.strip().lower() for t in inline.strip('[]').split(',') if t.strip())
    else:
        rows = re.findall(r'^[ \t]+-[ \t]*(.+?)$', block[tm.end():], re.M)
        tl = set(r.strip().strip(chr(39)).strip(chr(34)).lower() for r in rows)
        if not tl:
            emit(True, sanc, reason, 'definition-unparseable-tools:' + c)
    emit(bool(WRITE_TOKENS & tl), sanc, reason, 'definition:' + c)

# Capability 3: no definition anywhere. A platform builtin granted read-only
# passes; everything else is unproven and stays write-capable (fail-safe).
if stype_l in grants_ro:
    emit(False, sanc, reason, 'builtin-read-only')
emit(True, sanc, reason, 'default-write-capable')
" "$INPUT" "$GATE_POLICY_SRC" "$_LV2_ROOT" "$PROJECT_ROOT" "${HOME:-}" 2>/dev/null || true)"

    GATE_WC="$(printf -- '%s' "$GATE_RESULT" | sed -n 's/^WRITE_CAPABLE=//p')"
    GATE_SANC="$(printf -- '%s' "$GATE_RESULT" | sed -n 's/^SANCTIONED=//p')"
    GATE_REASON="$(printf -- '%s' "$GATE_RESULT" | sed -n 's/^REASON=//p')"
    GATE_RES="$(printf -- '%s' "$GATE_RESULT" | sed -n 's/^RESOLUTION=//p')"

    # Resolver silence is a crash, not an all-clear: an empty result denies as
    # write-capable (cause=resolver_failed) instead of waving the spawn through.
    if [[ -z "$GATE_WC" ]]; then
      GATE_WC="1"; GATE_SANC="0"; GATE_REASON=""; GATE_RES="resolver_failed"
    fi

    if [[ "$GATE_WC" == "1" ]]; then
      GATE_SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")"
      [[ -z "$GATE_SESSION_ID" ]] && GATE_SESSION_ID="$PPID"
      GATE_MODEL="$(echo "$INPUT" | jq -r '.tool_input.model // empty' 2>/dev/null || echo "")"
      [[ -z "$GATE_MODEL" ]] && GATE_MODEL="inherited"
      GATE_JOURNAL="${LEADV2_DIRECT_SPAWN_GATE_JOURNAL:-${HOME:-$PWD}/.claude/leadv2-state/leadv2/direct-spawn-gate.jsonl}"

      if [[ "$GATE_SANC" == "1" ]]; then
        # Sanctioned bypass (config grant): allowed, but journaled so the quota
        # spend stays auditable (known-gap visibility, not enforcement).
        _gate_journal "sanctioned_bypass" || true
      elif [[ -n "$GATE_REASON" ]]; then
        # Recorded reason: allowed ONLY when the journal write succeeds — a
        # reason that cannot be read back later is an assertion, not a record.
        if ! _gate_journal "allow_with_reason"; then
          if [[ "$GATE_PERMISSION_DECISION" == "deny" ]]; then
            _gate_deny "journal_unavailable"
          fi
        fi
      else
        _gate_journal "deny" || true
        if [[ "$GATE_PERMISSION_DECISION" == "deny" ]]; then
          _gate_deny "no_recorded_reason"
        fi
      fi
    fi
  fi
fi

# Already routed to Codex -> nothing to nudge.
[[ "$SUBTYPE_LOWER" == *codex* ]] && exit 0

# Only nudge for build/review roles Codex is first-class for.
case "$SUBTYPE_LOWER" in
  *developer*|*postgres*|*frontend*|*critic*|*security*) ;;
  *) exit 0 ;;
esac

POLICY="$PROJECT_ROOT/.claude/leadv2-overrides/codex-policy.yaml"

# No policy file, or codex_enabled not true -> stay silent (this repo hasn't opted in).
[[ -f "$POLICY" ]] || exit 0
grep -qE '^[[:space:]]*codex_enabled:[[:space:]]*true' "$POLICY" 2>/dev/null || exit 0

# LEADV2-FANOUT-MAXIMIZE-CHEAP-MODELS-01: when the fanout child was launched
# with LEADV2_MAXIMIZE_CHEAP_MODELS=1 (default-on; kill switch =0, see
# scripts/leadv2-fanout.sh), strengthen the reminder into an explicit
# should-route directive and log every fitting-Claude selection to a
# repo-local ledger for visibility. This stays WARN-only (continueOnBlock:
# true, no permissionDecision:deny) — it never hard-blocks the spawn, it only
# makes the steer louder and durably visible instead of a one-shot stderr line.
MAXIMIZE="${LEADV2_MAXIMIZE_CHEAP_MODELS:-1}"

# H1 (codex review): cap the ledger at ~256KB so default-on per-spawn
# logging can't grow unbounded across the life of an installer's repo —
# rotate by keeping only the newest half once the cap is exceeded. Cheap:
# one wc -c + one tail -c, both bounded by LOG_CAP_BYTES, only on write.
# H2 (codex review): the entire probe+rotate+append is wrapped in ONE
# brace group whose stderr is redirected to /dev/null on the group itself
# (not tacked onto the individual append) — this protects the append's own
# `open()` failure (missing/unwritable dir or file) too, which a trailing
# `>>file 2>/dev/null` on a single command does NOT: the shell attempts the
# file-open redirect before the per-command stderr redirect takes effect,
# so a bad path would otherwise still print a shell-level error on every
# spawn despite `|| true`. The writability pre-check is belt-and-braces on
# top of that structural fix, not a substitute for it.
LOG_DIR="$PROJECT_ROOT/docs/leadv2"
LOG_FILE="$LOG_DIR/codex-first-nudge.log"
LOG_CAP_BYTES=262144

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")"
[[ -z "$SESSION_ID" ]] && SESSION_ID="$PPID"

# EFFICIENCY-TUNE-01 A4: read the ledger back before emitting — full ~380B
# reminder fires once per subtype/session; every subsequent matching spawn
# this session gets a 1-line pointer instead (was: full text every spawn,
# 8x380B=3.0KB/session -> ~660B, 78% cut per efficiency-tune-plan.md A-table row 4).
ALREADY_NUDGED=0
if [[ -f "$LOG_FILE" ]]; then
  grep -qF "session=${SESSION_ID} subtype=${SUBTYPE} " "$LOG_FILE" 2>/dev/null && ALREADY_NUDGED=1
fi

if [[ "$ALREADY_NUDGED" == "1" ]]; then
  REMINDER="[leadv2-codex-first-nudge] subtype=$SUBTYPE: route plan/review/fitting-dev to Codex and background/bulk work to GLM before Claude quota; use Claude only for integration-critical or safety-gate work."
else
  if [[ "$MAXIMIZE" == "1" ]]; then
    REMINDER="[leadv2-codex-first-nudge] MAXIMIZE_CHEAP_MODELS=1: subagent_type=$SUBTYPE SHOULD route to Codex (codex-task.sh --tier standard, or --tier top for Heavy/adversarial per codex-policy.yaml) for plan/review/fitting-dev, or to GLM for background/bulk work -- not Claude quota, unless this spawn is integration-critical or a safety-gate task. See docs/model-routing.md and .claude/leadv2-overrides/codex-policy.yaml (dev_on_codex_fitting/phase5_review_standard)."
    DECISION="claude-selected-where-codex-glm-fits"
  else
    REMINDER="[leadv2-codex-first-nudge] REMINDER: codex_enabled: true in $POLICY -- consider routing this task (subagent_type=$SUBTYPE) to Codex first (codex-task.sh) before Claude quota. See docs/model-routing.md."
    DECISION="reminder-only"
  fi

  {
    mkdir -p "$LOG_DIR"
    if [[ -w "$LOG_DIR" ]] && { [[ ! -e "$LOG_FILE" ]] || [[ -w "$LOG_FILE" ]]; }; then
      if [[ -f "$LOG_FILE" ]]; then
        LOG_SIZE="$(wc -c < "$LOG_FILE")"
        LOG_SIZE="${LOG_SIZE//[[:space:]]/}"
        if [[ "$LOG_SIZE" =~ ^[0-9]+$ ]] && (( LOG_SIZE > LOG_CAP_BYTES )); then
          tail -c "$(( LOG_CAP_BYTES / 2 ))" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
        fi
      fi
      printf -- '%s session=%s subtype=%s cwd=%s decision=%s\n' \
        "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$SESSION_ID" "$SUBTYPE" "$CWD" "$DECISION" >> "$LOG_FILE"
    fi
  } 2>/dev/null || true
fi
echo "$REMINDER" >&2

# ALSO emit stdout JSON: a stderr-only line on an allow decision is never
# injected into model context (its "audience" was never actually the model).
# additionalContext on an allow decision IS surfaced to the model.
python3 -c "
import json, sys
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'allow',
        'additionalContext': sys.argv[1],
    }
}))
" "$REMINDER"

exit 0
