# ROUTING-HAS-NO-ENFORCING-LAYER-01 — uncommitted work rescued from the checkout

Carried out of `.claude/worktrees/ROUTING-HAS-NO-ENFORCING-LAYER-01` on 2026-09-06 by the blocking filter of
LEADV2-WORKTREE-ADJUDICATION-01, **before** any verdict was written about the
branch. A lane's branch can be an empty anchor while the work sits untracked or
merely staged inside its checkout: `git log` never sees the index, and removing
the checkout would take both with it.

Text only — nothing here is installed or made executable. Restoring any of it is
a deliberate act by whoever owns the row.

## `git diff HEAD -- plugins tests` (staged and unstaged)

```diff
diff --git a/plugins/leadv2/hooks/hooks.json b/plugins/leadv2/hooks/hooks.json
index f6d7e0e0..757329de 100644
--- a/plugins/leadv2/hooks/hooks.json
+++ b/plugins/leadv2/hooks/hooks.json
@@ -239,8 +239,7 @@
             "type": "command",
             "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-codex-first-nudge.sh\"",
             "timeout": 5,
-            "continueOnBlock": true,
-            "statusMessage": "Codex-first nudge (WARN-only)..."
+            "statusMessage": "Codex-first nudge + direct-spawn gate..."
           },
           {
             "type": "command",
diff --git a/plugins/leadv2/hooks/leadv2-codex-first-nudge.sh b/plugins/leadv2/hooks/leadv2-codex-first-nudge.sh
index 01bc7b88..ead522c6 100755
--- a/plugins/leadv2/hooks/leadv2-codex-first-nudge.sh
+++ b/plugins/leadv2/hooks/leadv2-codex-first-nudge.sh
@@ -1,8 +1,11 @@
 #!/usr/bin/env bash
-# PreToolUse(Agent) WARN-only nudge: remind the lead to route fitting build/review
-# tasks to Codex when a repo has opted into codex_enabled: true. NEVER blocks/denies —
-# purely informational stderr reminder. Mirrors leadv2-block-codex.sh's cwd/policy
-# resolution so behavior stays consistent across hooks.
+# PreToolUse(Agent): the direct-spawn gate + the legacy Codex-first nudge.
+# ROUTING-HAS-NO-ENFORCING-LAYER-01 (2026-09-04): this hook is now the one
+# enforcing layer in the call path. A direct Agent() spawn that carries Write/Edit
+# in its tool set and carries no recorded reason is DENIED (exit 2) and pointed at
+# leadv2-dispatch-code.sh; read-only recon and sanctioned bypass roles
+# (config/direct-spawn-gate.yaml) pass. The Codex-first reminder below stays
+# WARN-only for everything the gate allows.
 set -euo pipefail
 trap 'echo "[$(basename "$0")] error at line $LINENO" >&2; exit 0' ERR
 
@@ -17,6 +20,237 @@ SUBTYPE="$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/nul
 
 SUBTYPE_LOWER="$(echo "$SUBTYPE" | tr '[:upper:]' '[:lower:]')"
 
+# ── DIRECT-SPAWN GATE (ROUTING-HAS-NO-ENFORCING-LAYER-01) ──────────────────────────────────────────────
+# One layer now stands in the path of the call. The discriminator is the
+# CAPABILITY TO WRITE, never a list of names: a spawn whose effective tool set
+# carries Write/Edit (explicit tool_input.tools, the target's agent definition
+# frontmatter, or unprovable read-onlyness) and whose caller recorded no reason
+# is denied — on every provider, with no model or provider name anywhere in the
+# predicate. Passes untouched: provably read-only targets (recon), roles granted
+# as sanctioned dispatcher bypasses in direct-spawn-gate.yaml (default-deny
+# config), and prompts carrying a recorded LEADV2-DIRECT-REASON line (allowed
+# only when the journal write succeeds — recorded, not asserted). Nested spawns
+# (agent_type present) belong to leadv2-routing-guard.sh and never reach this
+# gate. Kill switches: LEADV2_DIRECT_SPAWN_GATE=0, or per-repo override
+# .claude/leadv2-overrides/direct-spawn-gate.yaml with enabled: false.
+GATE_PERMISSION_DECISION="deny"
+
+_gate_journal() { # <decision> -> rc 0 only when the line landed in the journal
+  local decision="$1" line
+  line="$(python3 -c "
+import json, sys, time
+print(json.dumps({
+    'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
+    'event': 'direct_spawn_gate',
+    'decision': sys.argv[1],
+    'session_id': sys.argv[2],
+    'repo': sys.argv[3],
+    'subagent_type': sys.argv[4],
+    'model': sys.argv[5],
+    'resolution': sys.argv[6],
+    'reason': sys.argv[7],
+}))
+" "$decision" "$GATE_SESSION_ID" "$PROJECT_ROOT" "$SUBTYPE" "$GATE_MODEL" "$GATE_RES" "$GATE_REASON" 2>/dev/null)" || return 1
+  [[ -n "$line" ]] || return 1
+  {
+    mkdir -p "$(dirname "$GATE_JOURNAL")" 2>/dev/null
+    printf '%s\n' "$line" >> "$GATE_JOURNAL"
+  } 2>/dev/null
+}
+
+_gate_deny() { # <cause> -> way-forward text on stderr, exit 2
+  local why="$1" dispatch_bin="" _c
+  for _c in "${_LV2_ROOT}/scripts/leadv2-dispatch-code.sh" \
+            "${LEADV2_CANONICAL_ROOT:-${HOME:-$PWD}/Projects/leadv2}/plugins/leadv2/scripts/leadv2-dispatch-code.sh" \
+            "${PROJECT_ROOT}/plugins/leadv2/scripts/leadv2-dispatch-code.sh"; do
+    [[ -f "$_c" ]] && { dispatch_bin="$_c"; break; }
+  done
+  [[ -n "$dispatch_bin" ]] || dispatch_bin="<leadv2-dispatch-code.sh not found on this machine — plugin install broken; fix before write work>"
+  {
+    printf '[leadv2-codex-first-nudge] DENIED direct write-capable spawn (subagent_type=%s, model=%s, resolution=%s, cause=%s).\n' "$SUBTYPE" "$GATE_MODEL" "$GATE_RES" "$why"
+    printf 'This Agent call was not launched through the dispatcher: no arm selection, no quota accounting, no fallback ladder (ROUTING-HAS-NO-ENFORCING-LAYER-01).\n'
+    printf 'Way forward — pick one:\n'
+    printf '  1) dispatch the code work (script verified to exist):\n'
+    printf '       bash %s "<mission>"\n' "$dispatch_bin"
+    printf '  2) or record why Claude must write directly — put this line in the spawn prompt:\n'
+    printf '       LEADV2-DIRECT-REASON: <why Claude specifically, one line>\n'
+    printf 'Denials and recorded reasons are journaled: %s\n' "$GATE_JOURNAL"
+  } >&2
+  exit 2
+}
+
+CALLER_AGENT_TYPE="$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || echo "")"
+
+CWD="$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")"
+[[ -z "$CWD" ]] && CWD="$PWD"
+PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$CWD")}}"
+
+if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
+  _LV2_ROOT="${CLAUDE_PLUGIN_ROOT}"
+else
+  _LV2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
+fi
+
+if [[ -z "$CALLER_AGENT_TYPE" && "${LEADV2_DIRECT_SPAWN_GATE:-1}" != "0" ]]; then
+  GATE_POLICY_SRC="${_LV2_ROOT}/config/direct-spawn-gate.yaml"
+  GATE_OVERRIDE="${PROJECT_ROOT}/.claude/leadv2-overrides/direct-spawn-gate.yaml"
+  GATE_ON=1
+  if [[ -f "$GATE_OVERRIDE" ]]; then
+    GATE_POLICY_SRC="$GATE_OVERRIDE"
+    if grep -qE '^[[:space:]]*enabled:[[:space:]]*false' "$GATE_OVERRIDE" 2>/dev/null; then
+      GATE_ON=0
+    fi
+  fi
+  if [[ "$GATE_ON" == "1" ]]; then
+    GATE_RESULT="$(python3 -c "
+import sys, os, re, json
+
+d           = json.loads(sys.argv[1])
+policy_src  = sys.argv[2]
+plugin_root = sys.argv[3]
+project_root = sys.argv[4]
+home        = sys.argv[5]
+
+inp        = d.get('tool_input') or {}
+stype      = (inp.get('subagent_type') or '').strip()
+stype_l    = stype.lower()
+prompt     = inp.get('prompt') or ''
+tools_param = inp.get('tools')
+
+def emit(wc, sanc, reason, resolution):
+    print('WRITE_CAPABLE=%d' % (1 if wc else 0))
+    print('SANCTIONED=%d' % (1 if sanc else 0))
+    print('REASON=%s' % reason[:200])
+    print('RESOLUTION=%s' % resolution)
+    sys.exit(0)
+
+# Recorded reason: a line-anchored LEADV2-DIRECT-REASON marker anywhere in the prompt.
+reason = ''
+for ln in prompt.splitlines():
+    m = re.match(r'^[ \t]*LEADV2-DIRECT-REASON:[ \t]*(.+?)[ \t]*$', ln)
+    if m:
+        reason = m.group(1)
+        break
+
+# Grants (default-deny posture; this file can only OPEN doors, never weaken the
+# capability predicate). Missing/unreadable policy -> platform-truth fallback:
+# explore is read-only, everything else unproven stays write-capable.
+grants_ro, grants_sanc, loaded = ['explore'], [], False
+src_text = ''
+try:
+    src_text = open(policy_src, encoding='utf-8', errors='replace').read()
+    try:
+        import yaml
+        p = yaml.safe_load(src_text) or {}
+        if isinstance(p, dict):
+            grants_ro   = [str(x).lower() for x in (p.get('read_only_builtins') or [])]
+            grants_sanc = [str(x).lower() for x in (p.get('sanctioned_bypass_roles') or [])]
+            loaded = True
+    except ImportError:
+        pass
+except Exception:
+    pass
+if not loaded and src_text:
+    def _lst(key, text):
+        m = re.search(r'^' + key + r':[ \t]*\n((?:[ \t]*-[ \t]*[^\n]+\n?)*)', text, re.M)
+        if not m:
+            return []
+        return [r.strip().lstrip('-').strip().lower()
+                for r in m.group(1).strip().splitlines() if r.strip().startswith('-')]
+    grants_ro = _lst('read_only_builtins', src_text) or ['explore']
+    grants_sanc = _lst('sanctioned_bypass_roles', src_text)
+
+sanc = stype_l in grants_sanc
+
+# Capability 1: explicit per-spawn tool list wins — model- and provider-blind.
+WRITE_TOKENS = {'write', 'edit', 'notebookedit', 'notebookeditwrite', '*', 'all'}
+if isinstance(tools_param, list) and tools_param:
+    tl = set()
+    for t in tools_param:
+        if isinstance(t, dict):
+            t = t.get('name') or ''
+        tl.add(str(t).strip().lower())
+    emit(bool(WRITE_TOKENS & tl), sanc, reason, 'tools-param')
+
+# Capability 2: the target's agent definition (repo -> plugin -> user), first
+# match wins. tools: absent or unparseable == inherits the full set == capable.
+safe = re.sub(r'[^A-Za-z0-9._-]', '', stype_l) or 'unknown'
+cands = []
+if project_root:
+    cands.append(os.path.join(project_root, '.claude', 'agents', safe + '.md'))
+if plugin_root:
+    cands.append(os.path.join(plugin_root, 'agents', safe + '.md'))
+if home:
+    cands.append(os.path.join(home, '.claude', 'agents', safe + '.md'))
+for c in cands:
+    try:
+        text = open(c, encoding='utf-8', errors='replace').read()
+    except Exception:
+        continue
+    fm = re.match(r'^---[ \t]*\n(.*?)\n---[ \t]*\n', text, re.S)
+    if not fm:
+        emit(True, sanc, reason, 'definition-unparseable:' + c)
+    block = fm.group(1)
+    tm = re.search(r'^tools:[ \t]*(.*)$', block, re.M)
+    if not tm:
+        emit(True, sanc, reason, 'definition-no-tools-field:' + c)
+    inline = tm.group(1).strip()
+    if inline:
+        tl = set(t.strip().lower() for t in inline.strip('[]').split(',') if t.strip())
+    else:
+        rows = re.findall(r'^[ \t]+-[ \t]*(.+?)$', block[tm.end():], re.M)
+        tl = set(r.strip().strip(chr(39)).strip(chr(34)).lower() for r in rows)
+        if not tl:
+            emit(True, sanc, reason, 'definition-unparseable-tools:' + c)
+    emit(bool(WRITE_TOKENS & tl), sanc, reason, 'definition:' + c)
+
+# Capability 3: no definition anywhere. A platform builtin granted read-only
+# passes; everything else is unproven and stays write-capable (fail-safe).
+if stype_l in grants_ro:
+    emit(False, sanc, reason, 'builtin-read-only')
+emit(True, sanc, reason, 'default-write-capable')
+" "$INPUT" "$GATE_POLICY_SRC" "$_LV2_ROOT" "$PROJECT_ROOT" "${HOME:-}" 2>/dev/null || true)"
+
+    GATE_WC="$(printf -- '%s' "$GATE_RESULT" | sed -n 's/^WRITE_CAPABLE=//p')"
+    GATE_SANC="$(printf -- '%s' "$GATE_RESULT" | sed -n 's/^SANCTIONED=//p')"
+    GATE_REASON="$(printf -- '%s' "$GATE_RESULT" | sed -n 's/^REASON=//p')"
+    GATE_RES="$(printf -- '%s' "$GATE_RESULT" | sed -n 's/^RESOLUTION=//p')"
+
+    # Resolver silence is a crash, not an all-clear: an empty result denies as
+    # write-capable (cause=resolver_failed) instead of waving the spawn through.
+    if [[ -z "$GATE_WC" ]]; then
+      GATE_WC="1"; GATE_SANC="0"; GATE_REASON=""; GATE_RES="resolver_failed"
+    fi
+
+    if [[ "$GATE_WC" == "1" ]]; then
+      GATE_SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")"
+      [[ -z "$GATE_SESSION_ID" ]] && GATE_SESSION_ID="$PPID"
+      GATE_MODEL="$(echo "$INPUT" | jq -r '.tool_input.model // empty' 2>/dev/null || echo "")"
+      [[ -z "$GATE_MODEL" ]] && GATE_MODEL="inherited"
+      GATE_JOURNAL="${LEADV2_DIRECT_SPAWN_GATE_JOURNAL:-${HOME:-$PWD}/.claude/leadv2-state/leadv2/direct-spawn-gate.jsonl}"
+
+      if [[ "$GATE_SANC" == "1" ]]; then
+        # Sanctioned bypass (config grant): allowed, but journaled so the quota
+        # spend stays auditable (known-gap visibility, not enforcement).
+        _gate_journal "sanctioned_bypass" || true
+      elif [[ -n "$GATE_REASON" ]]; then
+        # Recorded reason: allowed ONLY when the journal write succeeds — a
+        # reason that cannot be read back later is an assertion, not a record.
+        if ! _gate_journal "allow_with_reason"; then
+          if [[ "$GATE_PERMISSION_DECISION" == "deny" ]]; then
+            _gate_deny "journal_unavailable"
+          fi
+        fi
+      else
+        _gate_journal "deny" || true
+        if [[ "$GATE_PERMISSION_DECISION" == "deny" ]]; then
+          _gate_deny "no_recorded_reason"
+        fi
+      fi
+    fi
+  fi
+fi
+
 # Already routed to Codex -> nothing to nudge.
 [[ "$SUBTYPE_LOWER" == *codex* ]] && exit 0
 
@@ -26,10 +260,6 @@ case "$SUBTYPE_LOWER" in
   *) exit 0 ;;
 esac
 
-CWD="$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")"
-[[ -z "$CWD" ]] && CWD="$PWD"
-
-PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$CWD")}}"
 POLICY="$PROJECT_ROOT/.claude/leadv2-overrides/codex-policy.yaml"
 
 # No policy file, or codex_enabled not true -> stay silent (this repo hasn't opted in).
```

## `plugins/leadv2/config/direct-spawn-gate.yaml` (untracked, 2131 bytes)

```
# direct-spawn-gate.yaml — policy for the direct write-capable spawn gate
# (leadv2-codex-first-nudge.sh, ROUTING-HAS-NO-ENFORCING-LAYER-01, 2026-09-04).
#
# The gate's DENY side is capability-only: it fires on a direct Agent() spawn
# whose effective tool set carries Write/Edit (explicit tool_input.tools, the
# agent definition's frontmatter tools:, or an unprovable read-onlyness) and
# that carries no recorded LEADV2-DIRECT-REASON line. No model name, provider
# name, or subtype name decides a denial — a write-capable spawn on sonnet,
# opus, glm, kimi or freepool is denied by the same predicate.
#
# This file only holds GRANTS under that default-deny posture: anything not
# granted here and not provably read-only is denied and pointed at
# leadv2-dispatch-code.sh (or at the LEADV2-DIRECT-REASON escape hatch).
#
#   read_only_builtins      — platform builtins with no definition file that are
#                             read-only by platform truth (recon passes
#                             untouched at any model). Also the in-hook fallback
#                             when this file itself is missing (broken install):
#                             explore passes, everything else write-capable.
#   sanctioned_bypass_roles — write-capable roles that bypass the dispatcher BY
#                             DESIGN (plan synthesis / review panels). Their
#                             passes are journaled as sanctioned_bypass so the
#                             quota spend stays auditable. Known gaps recorded
#                             in the lane report: devops-engineer, critic,
#                             security-auditor (v1 scope decision).
#
# Per-repo override (wins ENTIRELY, same rule as nested-spawn-policy.yaml —
# copy the grant lists you want, not just the enabled flag):
#   <repo>/.claude/leadv2-overrides/direct-spawn-gate.yaml
# Repo-local kill switch: that file with `enabled: false`.
# Session kill switch: LEADV2_DIRECT_SPAWN_GATE=0.
enabled: true
read_only_builtins:
  - explore
sanctioned_bypass_roles:
  - architect
  - critic
  - security-auditor
  - devops-engineer
```

## `plugins/leadv2/scripts/tests/test-direct-spawn-gate.sh` (untracked, 12614 bytes)

```
#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, discovered by scan_suite_triggers):
# run-all-triggers: leadv2-codex-first-nudge direct-spawn-gate
# test-direct-spawn-gate.sh — ROUTING-HAS-NO-ENFORCING-LAYER-01.
#
# The nudge used to print permissionDecision:'allow' unconditionally — it could
# only be ignored. This suite locks the enforcing layer now living in the same
# hook. The deny predicate is CAPABILITY TO WRITE only (explicit tools param,
# agent-definition frontmatter, or unprovable read-onlyness) — never a model,
# provider, or subtype name. Locked cases (mission acceptance 1/2/3/4/4b/5):
#   1.  write-capable direct spawn, no recorded reason        -> DENIED (exit 2)
#   2.  same spawn WITH LEADV2-DIRECT-REASON                  -> allowed, reason journaled + readable back
#   3.  Explore / read-only definitions                       -> passes at any model
#   4.  general-purpose (builtin catch-all)                   -> DENIED, with or without a tools param
#   4b. write-capable spawn on non-Claude models (glm/kimi/freepool ids) -> DENIED
#   5.  NEGATIVE CONTROL: seam flipped to allow -> green-through; restored -> denied again
#   6.  sanctioned bypass roles (architect/critic/security-auditor/devops-engineer) -> pass, journaled
#   7.  nested callers (agent_type present) never reach this gate
#   8.  kill switches: LEADV2_DIRECT_SPAWN_GATE=0, per-repo override enabled:false
#   9.  journal unavailable -> a reason that cannot be recorded is NOT accepted
#   10. broken-install fallback (no config file): explore still passes, developer still denied
#   11. legacy Codex-first reminder still fires for allowed review spawns
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
HOOK="${ROOT}/plugins/leadv2/hooks/leadv2-codex-first-nudge.sh"
PLUG="${ROOT}/plugins/leadv2"
[ -f "$HOOK" ] || { echo "FAIL: nudge hook missing: $HOOK"; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dsg.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
HOME_SBX="${TMP}/home"
mkdir -p "${HOME_SBX}/.claude/agents"

REPO="${TMP}/repo"
mkdir -p "${REPO}/.claude/agents"
JOURNAL="${TMP}/direct-spawn-gate.jsonl"

# Agent definitions: developer carries Write+Edit (the defect payload);
# ro-probe is a read-only definition (recon via custom agent).
cat > "${REPO}/.claude/agents/developer.md" <<'MD'
---
name: developer
description: "fixture"
tools: Read, Write, Edit, Bash, Glob, Grep
---
MD
cat > "${REPO}/.claude/agents/ro-probe.md" <<'MD'
---
name: ro-probe
description: "fixture"
tools:
  - Read
  - Grep
  - Glob
---
probe body
MD
# A definition with NO tools field inherits the full set -> write-capable.
cat > "${REPO}/.claude/agents/no-tools-decl.md" <<'MD'
---
name: no-tools-decl
description: "fixture"
---

MD

call_gate() { # <name> <json> [env k=v] -> sets RC, OUT=stderr verbatim (printed)
  local _extra="${3:-}"
  RC=0
  printf '%s' "$2" \
    | env CLAUDE_PLUGIN_ROOT="${PLUG}" CLAUDE_PROJECT_ROOT="${REPO}" \
          HOME="${HOME_SBX}" LEADV2_DIRECT_SPAWN_GATE_JOURNAL="${JOURNAL}" \
          ${_extra} bash "$HOOK" >/dev/null 2>"${TMP}/err.$$" || RC=$?
  # NOTE: read via the bash builtin `$(< f)`, not `cat f` — under the plugin's
  # Bash-tool wrapper an external `cat` was observed returning empty for this
  # freshly-written stderr file while `wc -c < f` saw the bytes (measured
  # 2026-09-04, ROUTING-HAS-NO-ENFORCING-LAYER-01 debugging); the builtin read
  # does not exec or glob anything and sidesteps it.
  OUT=""
  [ -r "${TMP}/err.$$" ] && { read -r -d '' OUT < "${TMP}/err.$$" || true; }
  rm -f "${TMP}/err.$$"
  printf '%s\n' "$OUT"
}

payload() { # <subtype> <model> <prompt> -> hook input json
  printf '{"tool_name":"Agent","session_id":"%s","cwd":"%s","tool_input":{"subagent_type":"%s","model":"%s","prompt":%s}}' \
    "$4" "${REPO}" "$1" "$2" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$3")"
}

payload_tools() { # <subtype> <model> <tools-csv> -> hook input json with explicit tools
  printf '{"tool_name":"Agent","session_id":"%s","cwd":"%s","tool_input":{"subagent_type":"%s","model":"%s","tools":[%s],"prompt":"x"}}' \
    "$4" "${REPO}" "$1" "$2" "$3"
}

# --- 1: write-capable spawn, no reason -> DENIED, way forward named -----------
echo "== 1: developer, no recorded reason =="
call_gate c1 "$(payload developer sonnet "fix the bug" s1)"
if [ "$RC" -eq 2 ]; then ok "denied with exit 2"; else bad "expected rc=2 got rc=${RC}"; fi
case "$OUT" in
  *"[leadv2-codex-first-nudge] DENIED direct write-capable spawn (subagent_type=developer, model=sonnet"*"cause=no_recorded_reason)"*)
    ok "deny names capability + cause" ;;
  *) bad "deny header malformed: ${OUT}" ;;
esac
case "$OUT" in
  *"leadv2-dispatch-code.sh"*"LEADV2-DIRECT-REASON"*) ok "way forward names dispatcher + reason escape" ;;
  *) bad "deny does not name both exits: ${OUT}" ;;
esac
grep -q '"decision": "deny", "session_id": "s1"' "$JOURNAL" \
  && ok "denial journaled" || bad "denial not journaled"

# --- 2: same spawn WITH recorded reason -> passes, reason readable back -------
echo "== 2: developer + LEADV2-DIRECT-REASON =="
call_gate c2 "$(payload developer sonnet "LEADV2-DIRECT-REASON: hook surgery needs live lead context
fix the bug" s2)"
if [ "$RC" -eq 0 ]; then ok "allowed with recorded reason"; else bad "expected rc=0 got rc=${RC}: ${OUT}"; fi
BACK="$(grep '"session_id": "s2"' "$JOURNAL" | tail -1)"
case "$BACK" in
  *'"decision": "allow_with_reason"'*"hook surgery needs live lead context"*)
    ok "reason readable back from journal" ;;
  *) bad "journal read-back failed: ${BACK:-<none>}" ;;
esac

# --- 3: read-only recon passes at any model -----------------------------------
echo "== 3: Explore / read-only definitions =="
for M in haiku sonnet; do
  call_gate c3 "$(payload Explore "$M" "find callers of X" "s3-$M")"
  [ "$RC" -eq 0 ] && ok "Explore on ${M} passes" || bad "Explore on ${M} denied: ${OUT}"
done
call_gate c3b "$(payload ro-probe haiku "probe" s3b)"
[ "$RC" -eq 0 ] && ok "read-only definition (block-list tools) passes" || bad "ro-probe denied: ${OUT}"
call_gate c3c "$(payload no-tools-decl sonnet "x" s3c)"
[ "$RC" -eq 2 ] && ok "definition with NO tools field (inherits full set) denied" || bad "no-tools-decl passed: rc=${RC}"

# --- 4: builtin catch-alls denied ---------------------------------------------
echo "== 4: general-purpose =="
call_gate c4 "$(payload general-purpose sonnet "do everything" s4)"
[ "$RC" -eq 2 ] && ok "general-purpose (unprovable) denied" || bad "general-purpose passed: rc=${RC}"
call_gate c4t "$(payload_tools general-purpose sonnet '"Read", "Write", "Bash"' s4t)"
[ "$RC" -eq 2 ] && ok "general-purpose with explicit Write tools denied" || bad "tools-param Write passed: rc=${RC}"
call_gate c4r "$(payload_tools general-purpose haiku '"Read", "Grep", "Glob"' s4r)"
[ "$RC" -eq 0 ] && ok "tools-param read-only passes even for a catch-all type" || bad "read-only tools-param denied: ${OUT}"

# --- 4b: provider-blind — non-Claude arms denied too ---------------------------
echo "== 4b: non-Claude model ids =="
for M in glm-5.3 kimi-k2 freepool/anthropic.nvidia_nim; do
  call_gate c4b "$(payload developer "$M" "write code" "s4b-$M")"
  [ "$RC" -eq 2 ] && ok "write-capable on ${M} denied" || bad "write-capable on ${M} passed: rc=${RC}"
done

# --- 5: NEGATIVE CONTROL — inert guard vs working guard ------------------------
echo "== 5: negative control (seam flip) =="
INERT_HOOK="${TMP}/nudge-inert.sh"
sed 's/GATE_PERMISSION_DECISION="deny"/GATE_PERMISSION_DECISION="allow"/' "$HOOK" > "$INERT_HOOK"
NRC=0
NOUT="$(printf '%s' "$(payload developer sonnet "fix the bug" s5n)" \
  | env CLAUDE_PLUGIN_ROOT="${PLUG}" CLAUDE_PROJECT_ROOT="${REPO}" HOME="${HOME_SBX}" \
        LEADV2_DIRECT_SPAWN_GATE_JOURNAL="${TMP}/neg.jsonl" bash "$INERT_HOOK" 2>&1)" || NRC=$?
[ "$NRC" -eq 0 ] && ok "seam='allow' -> spawn goes GREEN-through (guard inert)" \
                  || bad "seam='allow' still blocked rc=${NRC}: ${NOUT}"
call_gate c5 "$(payload developer sonnet "fix the bug" s5r)"
[ "$RC" -eq 2 ] && ok "seam restored -> denied again" || bad "restored guard did not deny: rc=${RC}"

# --- 6: sanctioned bypass roles pass (and are journaled) -----------------------
echo "== 6: sanctioned bypass roles =="
for ROLE in architect critic security-auditor devops-engineer; do
  call_gate c6 "$(payload "$ROLE" opus "review the plan" "s6-$ROLE")"
  if [ "$RC" -eq 0 ]; then
    grep -q "\"decision\": \"sanctioned_bypass\".*\"subagent_type\": \"${ROLE}\"" "$JOURNAL" \
      && ok "${ROLE} passes as sanctioned (journaled)" \
      || bad "${ROLE} passed but not journaled"
  else
    bad "${ROLE} denied — MUST-NOT-TOUCH broken: ${OUT}"
  fi
done

# --- 7: nested callers never reach this gate -----------------------------------
echo "== 7: nested caller =="
call_gate c7 '{"tool_name":"Agent","agent_type":"developer","session_id":"s7","cwd":"'"${REPO}"'","tool_input":{"subagent_type":"developer","model":"sonnet","prompt":"x"}}'
[ "$RC" -eq 0 ] && ok "agent_type present -> gate skipped (routing-guard's path)" \
                 || bad "nested spawn hit the direct gate: rc=${RC}: ${OUT}"

# --- 8: kill switches -----------------------------------------------------------
echo "== 8: kill switches =="
call_gate c8 "$(payload developer sonnet "x" s8e)" "LEADV2_DIRECT_SPAWN_GATE=0"
[ "$RC" -eq 0 ] && ok "env kill switch works" || bad "env kill switch failed: rc=${RC}"
mkdir -p "${REPO}/.claude/leadv2-overrides"
printf 'enabled: false\n' > "${REPO}/.claude/leadv2-overrides/direct-spawn-gate.yaml"
call_gate c8o "$(payload developer sonnet "x" s8o)"
[ "$RC" -eq 0 ] && ok "per-repo override kill switch works" || bad "override kill switch failed: rc=${RC}"
rm -f "${REPO}/.claude/leadv2-overrides/direct-spawn-gate.yaml"

# --- 9: a reason that cannot be recorded is not accepted ------------------------
echo "== 9: journal unavailable =="
mkdir -p "${TMP}/ro-dir" && chmod 500 "${TMP}/ro-dir"
call_gate c9 "$(payload developer sonnet "LEADV2-DIRECT-REASON: must record this
fix" s9)" "LEADV2_DIRECT_SPAWN_GATE_JOURNAL=${TMP}/ro-dir/nested/file.jsonl"
if [ "$RC" -eq 2 ]; then
  case "$OUT" in *"cause=journal_unavailable"*) ok "unwritable journal -> denied (recorded, not asserted)" ;;
                         *) bad "wrong deny cause: ${OUT}" ;; esac
else
  # chmod 500 may not block root; treat a pass on root as environment-skipped.
  if [ "$(id -u)" -eq 0 ]; then ok "journal-unavailable skipped under root (chmod 500 unenforced)"; else bad "reason accepted without a record: rc=${RC}"; fi
fi
chmod 700 "${TMP}/ro-dir"

# --- 10: broken install (no config file) falls back platform-truth ---------------
echo "== 10: missing config fallback =="
BARE_PLUG="${TMP}/bare-plugin"; mkdir -p "${BARE_PLUG}/scripts"
: > "${BARE_PLUG}/scripts/leadv2-dispatch-code.sh"
RC=0
OUT="$(printf '%s' "$(payload developer sonnet "x" s10a)" \
  | env CLAUDE_PLUGIN_ROOT="${BARE_PLUG}" CLAUDE_PROJECT_ROOT="${REPO}" HOME="${HOME_SBX}" \
        LEADV2_DIRECT_SPAWN_GATE_JOURNAL="${TMP}/bare.jsonl" bash "$HOOK" 2>&1)" || RC=$?
[ "$RC" -eq 2 ] && ok "no config file: developer still denied (fail-safe)" || bad "missing config fail-opened: rc=${RC}"
RC=0
OUT="$(printf '%s' "$(payload Explore haiku "x" s10b)" \
  | env CLAUDE_PLUGIN_ROOT="${BARE_PLUG}" CLAUDE_PROJECT_ROOT="${REPO}" HOME="${HOME_SBX}" \
        LEADV2_DIRECT_SPAWN_GATE_JOURNAL="${TMP}/bare.jsonl" bash "$HOOK" 2>&1)" || RC=$?
[ "$RC" -eq 0 ] && ok "no config file: Explore still passes (platform truth)" || bad "missing config denied Explore: rc=${RC}"

# --- 11: legacy Codex-first reminder still fires on an allowed spawn -------------
echo "== 11: legacy nudge preserved =="
printf 'codex_enabled: true\n' > "${REPO}/.claude/leadv2-overrides/codex-policy.yaml"
rm -f "${REPO}/docs/leadv2/codex-first-nudge.log"
RC=0
STDOUT="$(printf '%s' "$(payload critic sonnet "review the diff" s11)" \
  | env CLAUDE_PLUGIN_ROOT="${PLUG}" CLAUDE_PROJECT_ROOT="${REPO}" HOME="${HOME_SBX}" \
        LEADV2_DIRECT_SPAWN_GATE_JOURNAL="${JOURNAL}" bash "$HOOK" 2>/dev/null)" || RC=$?
[ "$RC" -eq 0 ] && ok "critic spawn allowed (rc=0)" || bad "critic denied: rc=${RC}"
case "$STDOUT" in
  *'"permissionDecision": "allow"'*route*Codex*) ok "allow decision + reminder still emitted" ;;
  *) bad "legacy reminder missing from stdout: ${STDOUT}" ;;
esac

echo "passed=${PASS} failed=${FAIL}"
[ "$FAIL" -eq 0 ]
```

