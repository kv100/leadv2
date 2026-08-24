#!/usr/bin/env bash
# tests/test-codex-plugin-manifest.sh — CODEX-LEAD-PLUGIN-01. Validates the
# marketplace tree: all three JSON files parse, plugin.json declares the
# capabilities we ship, every prompt has a matching skill with correct
# frontmatter, and every shell file passes bash -n.
#
# Run: bash plugins/leadv2/codex-lead/tests/test-codex-plugin-manifest.sh
# Exit 0 = all pass; non-zero = failures found.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_LEAD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MKT="$CODEX_LEAD_DIR/marketplace"
PLUGIN="$MKT/plugins/leadv2"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# --- JSON files parse -------------------------------------------------------
for f in "$MKT/.agents/plugins/marketplace.json" "$PLUGIN/.codex-plugin/plugin.json" "$PLUGIN/hooks.json" "$PLUGIN/.mcp.json"; do
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null; then
    pass "json: $(basename "$f") parses"
  else
    fail "json: $f does not parse"
  fi
done

# --- marketplace.json shape --------------------------------------------------
python3 - "$MKT/.agents/plugins/marketplace.json" <<'EOF' && pass "marketplace.json: one leadv2 entry, local source, AVAILABLE" || fail "marketplace.json: entry shape wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["name"] == "leadv2-local"
p = d["plugins"][0]
assert p["name"] == "leadv2"
assert p["source"]["source"] == "local" and p["source"]["path"] == "./plugins/leadv2"
assert p["policy"]["installation"] == "AVAILABLE"
assert p["policy"]["authentication"] == "ON_USE"
EOF

# --- plugin.json shape -------------------------------------------------------
python3 - "$PLUGIN/.codex-plugin/plugin.json" <<'EOF' && pass "plugin.json: capabilities declared" || fail "plugin.json: capability declarations wrong"
import json, sys
d = json.load(open(sys.argv[1]))
for k in ("name", "version", "description", "skills", "hooks", "mcpServers"):
    assert d.get(k), k
assert d["skills"] == "./skills/"
assert d["hooks"] == "./hooks.json"
assert d["mcpServers"] == "./.mcp.json"
EOF

# --- hooks.json: PreToolUse adapter wired ------------------------------------
python3 - "$PLUGIN/hooks.json" <<'EOF' && pass "hooks.json: PreToolUse matcher .* -> lv2guard adapter" || fail "hooks.json: PreToolUse wiring wrong"
import json, sys
d = json.load(open(sys.argv[1]))
groups = d["hooks"]["PreToolUse"]
assert any(g.get("matcher") == ".*" and
           any(h["type"] == "command" and "lv2guard-pretooluse.sh" in h["command"] for h in g["hooks"])
           for g in groups)
EOF

# --- .mcp.json: repowise launcher --------------------------------------------
python3 - "$PLUGIN/.mcp.json" <<'EOF' && pass ".mcp.json: repowise -> launcher script" || fail ".mcp.json: repowise wiring wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert "repowise" in d["mcpServers"]
assert "repowise-launch.sh" in d["mcpServers"]["repowise"]["command"]
EOF

# --- skills: one per prompt, frontmatter name == dir, no $ARGUMENTS ----------
for p in "$CODEX_LEAD_DIR"/prompts/*.md; do
  name="$(basename "$p" .md)"
  s="$PLUGIN/skills/$name/SKILL.md"
  if [[ ! -f "$s" ]]; then
    fail "skill: $name missing"
    continue
  fi
  if head -1 "$s" | grep -q '^---$' && \
     grep -q "^name: $name$" "$s" && \
     grep -q '^description: .\+' "$s"; then
    pass "skill: $name frontmatter (name matches dir)"
  else
    fail "skill: $name frontmatter wrong"
  fi
  if grep -q '## Usage' "$s"; then
    pass "skill: $name has Usage line"
  else
    fail "skill: $name missing Usage line"
  fi
  if grep -q '\$ARGUMENTS' "$s"; then
    fail "skill: $name still contains \$ARGUMENTS"
  else
    pass "skill: $name has no \$ARGUMENTS token"
  fi
done
SKILL_COUNT="$(ls -1d "$PLUGIN"/skills/*/ 2>/dev/null | wc -l | tr -d ' ')"
PROMPT_COUNT="$(ls -1 "$CODEX_LEAD_DIR"/prompts/*.md 2>/dev/null | wc -l | tr -d ' ')"
[[ "$SKILL_COUNT" == "$PROMPT_COUNT" ]] && pass "skills: exactly one per prompt ($SKILL_COUNT)" || fail "skills: $SKILL_COUNT skills vs $PROMPT_COUNT prompts"

# --- shell files pass bash -n -------------------------------------------------
for f in "$PLUGIN"/hooks/*.sh "$PLUGIN"/scripts/*.sh; do
  [[ -f "$f" ]] || continue
  bash -n "$f" 2>/dev/null && pass "bash -n $f" || fail "bash -n $f"
done

# --- no copies of lv2guard.sh or the yamls inside the plugin ------------------
# (one-copy rule: the plugin resolves the guard at runtime; a shipped copy
# would drift silently — design §4)
FOUND="$(find "$PLUGIN" -name 'lv2guard.sh' -o -name '*.yaml' | wc -l | tr -d ' ')"
[[ "$FOUND" == "0" ]] && pass "one-copy: plugin ships no guard/yaml copy" || fail "one-copy: plugin ships $(find "$PLUGIN" -name 'lv2guard.sh' -o -name '*.yaml')"

# --- CLI version pin (design §5.2: a version bump forces a re-probe of the
# hook wire contract — payload shape was recorded against this exact build) ---
CODEX_VERSION="${LEADV2_CODEX_VERSION_PIN:-0.145.0-alpha.1}"
if command -v codex >/dev/null 2>&1; then
  GOT_VERSION="$(codex --version 2>/dev/null | awk '{print $NF}')"
  if [[ "$GOT_VERSION" == "$CODEX_VERSION" ]]; then
    pass "cli pin: codex $GOT_VERSION matches the probed build"
  else
    fail "cli pin: codex is $GOT_VERSION but the hook wire contract was probed on $CODEX_VERSION — re-probe (logging PreToolUse hook, deny/rc7/bypass matrix) and update the pin, or the floor may be silently inert"
  fi
else
  pass "cli pin: codex CLI absent from PATH — pin check skipped"
fi

# --- adapter behavior on the blocking wire contract (round-1 review) ----------
# The manifest checks above prove shape; these prove BEHAVIOR: allow is empty
# stdout rc 0, every deny path is valid deny JSON with a non-empty reason rc 0
# (a deny that fails to emit reads as ALLOW at runtime), resolver precedence,
# and fail-closed when python3 itself is unavailable.
ADAPTER="$PLUGIN/hooks/lv2guard-pretooluse.sh"
ADPT="$(mktemp -d)"
# isolate the adapter's unrecognized-shape log (and any other ~/.codex write)
# to the fixture — a test must not append to the founder's real log
export CODEX_HOME="$ADPT/codex-home"
mkdir -p "$CODEX_HOME"

payload_for() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"
}
deny_json_reason() {
  python3 -c 'import json,sys
d = json.load(sys.stdin); h = d["hookSpecificOutput"]
assert h["hookEventName"] == "PreToolUse"
assert h["permissionDecision"] == "deny"
r = h["permissionDecisionReason"]
assert isinstance(r, str) and r.strip(), "empty reason"
print(r)'
}

RMRF_CMD="rm -rf "" /"   # concatenated: catastrophic literal stays out of this file

out="$(payload_for "git status" | bash "$ADAPTER" 2>/dev/null)"; rc=$?
if [[ $rc -eq 0 && -z "$out" ]]; then pass "adapter: allow -> empty stdout, rc 0"; else fail "adapter: allow (rc=$rc out=$out)"; fi

out="$(payload_for "$RMRF_CMD" | bash "$ADAPTER" 2>/dev/null)"; rc=$?
reason="$(printf '%s' "$out" | deny_json_reason 2>/dev/null)"
if [[ $rc -eq 0 && -n "$reason" ]] && printf '%s' "$reason" | grep -q 'irreversible root wipe'; then
  pass "adapter: deny -> valid deny JSON, non-empty reason naming the rule"
else
  fail "adapter: deny JSON (rc=$rc reason=$reason)"
fi

out="$(printf 'this is not json' | bash "$ADAPTER" 2>/dev/null)"; rc=$?
reason="$(printf '%s' "$out" | deny_json_reason 2>/dev/null)"
if [[ $rc -eq 0 && -n "$reason" ]] && printf '%s' "$reason" | grep -q 'unreadable PreToolUse payload'; then
  pass "adapter: not-JSON stdin -> deny"
else
  fail "adapter: not-JSON deny (rc=$rc reason=$reason)"
fi

# fake guards: env override wins the resolution chain, and each rc class maps right
printf '#!/bin/bash\nexit 2\n' > "$ADPT/g2.sh"
printf '#!/bin/bash\nexit 7\n' > "$ADPT/g7.sh"
printf '#!/bin/bash\nprintf "line0\\nREFUSED: FAKE97_MARKER rule\n" >&2\nexit 97\n' > "$ADPT/g97.sh"

out="$(payload_for "ls" | LEADV2_CODEX_LV2GUARD="$ADPT/g2.sh" bash "$ADAPTER" 2>/dev/null)"; rc=$?
reason="$(printf '%s' "$out" | deny_json_reason 2>/dev/null)"
[[ $rc -eq 0 ]] && printf '%s' "$reason" | grep -q 'guard usage error' && pass "adapter: guard rc 2 -> deny (usage error)" || fail "adapter: guard rc 2 (rc=$rc reason=$reason)"

out="$(payload_for "ls" | LEADV2_CODEX_LV2GUARD="$ADPT/g7.sh" bash "$ADAPTER" 2>/dev/null)"; rc=$?
reason="$(printf '%s' "$out" | deny_json_reason 2>/dev/null)"
[[ $rc -eq 0 ]] && printf '%s' "$reason" | grep -q 'failing closed' && pass "adapter: guard rc 7 -> deny (failing closed)" || fail "adapter: guard rc 7 (rc=$rc reason=$reason)"

out="$(payload_for "ls" | LEADV2_CODEX_LV2GUARD="$ADPT/g97.sh" bash "$ADAPTER" 2>/dev/null)"; rc=$?
reason="$(printf '%s' "$out" | deny_json_reason 2>/dev/null)"
[[ $rc -eq 0 ]] && printf '%s' "$reason" | grep -q 'FAKE97_MARKER' && pass "adapter: env override wins chain; guard stderr feeds the reason" || fail "adapter: override precedence (rc=$rc reason=$reason)"

out="$(payload_for "ls" | LEADV2_CODEX_LV2GUARD=/no/such/guard.sh bash "$ADAPTER" 2>/dev/null)"; rc=$?
reason="$(printf '%s' "$out" | deny_json_reason 2>/dev/null)"
[[ $rc -eq 0 ]] && printf '%s' "$reason" | grep -q 'LEADV2_CODEX_LV2GUARD' && pass "adapter: nonexistent override -> deny naming the var" || fail "adapter: bad override (rc=$rc reason=$reason)"

# round-1 review BLOCKER probe: deny must still emit with no python3 on PATH
out="$(payload_for "ls" | env PATH=/no/such/path HOME="$ADPT/nohome" /bin/bash "$ADAPTER" 2>/dev/null)"; rc=$?
reason="$(printf '%s' "$out" | deny_json_reason 2>/dev/null)"
if [[ $rc -eq 0 && -n "$reason" ]]; then
  pass "adapter: missing python3 -> deny still emits (pure-bash emitter)"
else
  fail "adapter: missing python3 deny (rc=$rc out=$out)"
fi

rm -rf "$ADPT"

echo
echo "==================================================="
echo "PASS: $PASS  FAIL: $FAIL"
echo "==================================================="
if [[ $FAIL -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
