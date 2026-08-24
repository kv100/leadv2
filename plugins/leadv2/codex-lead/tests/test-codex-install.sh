#!/usr/bin/env bash
# tests/test-codex-install.sh — CODEX-LEAD-FULL-01 / CODEX-LEAD-PLUGIN-01.
# HOME redirected to a fixture AND codex stubbed via LEADV2_CODEX_BIN —
# without the stub, install.sh would shell out to the real codex and mutate
# the founder's real ~/.codex/config.toml from inside a test (design §1b,
# CRITICAL). install.sh run TWICE per path. Asserts plugin registration
# idempotency on the plugin path, prompt-pack + config.toml idempotency on
# the fallback path, and the existing rc contract (0/3/4).
#
# Run: bash plugins/leadv2/codex-lead/tests/test-codex-install.sh
# Exit 0 = all pass; non-zero = failures found.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_LEAD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$CODEX_LEAD_DIR/install.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

FIX_HOME="$FIX/home"
FIX_REPO="$FIX_HOME/Projects/persona-engine"
mkdir -p "$FIX_HOME" "$FIX_REPO"
printf '# fixture AGENTS.md\n\n@import ref/01-orchestrator.md\n' > "$FIX_REPO/AGENTS.md"

# --- codex stub: records argv; emulates the config.toml writes the real CLI
# would make, so install.sh's grep-based idempotency checks see real state.
STUB="$FIX/codex-stub.sh"
CALLS="$FIX/codex-calls.log"
cat > "$STUB" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$CALLS"
if [[ "\$1" == "plugin" && "\$2" == "marketplace" && "\$3" == "add" ]]; then
  dir="\$4"
  abs="\$(cd "\$dir" && pwd -P)"
  printf '\n[marketplaces.leadv2-local]\nsource_type = "local"\nsource = "%s"\n' "\$abs" >> "\$HOME/.codex/config.toml"
  exit 0
fi
if [[ "\$1" == "plugin" && "\$2" == "add" ]]; then
  printf '\n[plugins."leadv2@leadv2-local"]\nenabled = true\n' >> "\$HOME/.codex/config.toml"
  exit 0
fi
exit 0
EOF
chmod +x "$STUB"

# --- no-plugin-support stub (fallback path) --------------------------------
STUB_NOPLUG="$FIX/codex-noplug.sh"
cat > "$STUB_NOPLUG" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$STUB_NOPLUG"

N_PROMPTS="$(ls -1 "$CODEX_LEAD_DIR/prompts"/*.md 2>/dev/null | wc -l | tr -d ' ')"

# --- plugin path, run 1 ----------------------------------------------------
rm -f "$CALLS"
OUT1="$(HOME="$FIX_HOME" LEADV2_CODEX_BIN="$STUB" bash "$INSTALL_SH" "$FIX_REPO" 2>&1)"; RC1=$?
[[ $RC1 -eq 0 ]] && pass "plugin run 1: exit 0" || fail "plugin run 1: exit 0 (rc=$RC1, out=$OUT1)"

printf '%s' "$OUT1" | grep -q "plugin: installed leadv2@leadv2-local" && pass "plugin run 1: installed line" || fail "plugin run 1: installed line (out=$OUT1)"
printf '%s' "$OUT1" | grep -q "marketplace leadv2-local: added" && pass "plugin run 1: marketplace added" || fail "plugin run 1: marketplace added (out=$OUT1)"

grep -q "plugin marketplace add" "$CALLS" && pass "plugin run 1: stub saw marketplace add" || fail "plugin run 1: stub never saw marketplace add"
grep -q "plugin add leadv2@leadv2-local" "$CALLS" && pass "plugin run 1: stub saw plugin add" || fail "plugin run 1: stub never saw plugin add"

grep -qF '[plugins."leadv2@leadv2-local"]' "$FIX_HOME/.codex/config.toml" && pass "plugin run 1: plugin registered in config.toml" || fail "plugin run 1: not registered in config.toml"

# plugin path must NOT write the repowise block (plugin .mcp.json owns it)
if grep -q 'BEGIN leadv2-codex-lead repowise' "$FIX_HOME/.codex/config.toml" 2>/dev/null; then
  fail "plugin run 1: repowise block written on plugin path (two servers would race)"
else
  pass "plugin run 1: no repowise block on plugin path"
fi

GOT_PROMPTS="$(ls -1 "$FIX_HOME/.codex/prompts"/*.md 2>/dev/null | wc -l | tr -d ' ')"
[[ "$GOT_PROMPTS" == "$N_PROMPTS" ]] && pass "plugin run 1: all $N_PROMPTS prompts installed" || fail "plugin run 1: prompt count ($GOT_PROMPTS != $N_PROMPTS)"

[[ -f "$FIX_REPO/.claude/ref/90-codex-lead-pilot.md" ]] && pass "plugin run 1: AGENTS-pilot ref file copied" || fail "plugin run 1: AGENTS-pilot ref file missing"

# --- plugin path, run 2 (idempotency) ---------------------------------------
CALLS_AFTER_RUN1="$(wc -l < "$CALLS" | tr -d ' ')"
OUT2="$(HOME="$FIX_HOME" LEADV2_CODEX_BIN="$STUB" bash "$INSTALL_SH" "$FIX_REPO" 2>&1)"; RC2=$?
[[ $RC2 -eq 0 ]] && pass "plugin run 2: exit 0" || fail "plugin run 2: exit 0 (rc=$RC2, out=$OUT2)"

printf '%s' "$OUT2" | grep -q "plugin: unchanged leadv2@leadv2-local" && pass "plugin run 2: plugin reported unchanged" || fail "plugin run 2: plugin not reported unchanged (out=$OUT2)"
printf '%s' "$OUT2" | grep -q "marketplace leadv2-local: unchanged" && pass "plugin run 2: marketplace reported unchanged" || fail "plugin run 2: marketplace not unchanged (out=$OUT2)"

CALLS_AFTER_RUN2="$(wc -l < "$CALLS" | tr -d ' ')"
if grep -q "plugin add leadv2@leadv2-local" <(tail -n +"$((CALLS_AFTER_RUN1 + 1))" "$CALLS"); then
  fail "plugin run 2: re-registered an already-installed plugin"
else
  pass "plugin run 2: no redundant plugin add"
fi

UNCHANGED_COUNT="$(printf '%s' "$OUT2" | grep -c '^unchanged ')"
[[ "$UNCHANGED_COUNT" -ge "$N_PROMPTS" ]] && pass "plugin run 2: every prompt reported unchanged" || fail "plugin run 2: only $UNCHANGED_COUNT/$N_PROMPTS reported unchanged (out=$OUT2)"

BAK_COUNT="$(find "$FIX_HOME/.codex" -name '*.bak' 2>/dev/null | wc -l | tr -d ' ')"
[[ "$BAK_COUNT" == "0" ]] && pass "plugin runs: no .bak files" || fail "plugin runs: unexpected .bak files ($BAK_COUNT)"

# --- plugin path: marketplace registered at a DIFFERENT root -> no re-point --
FIX4="$(mktemp -d)"
FIX4_HOME="$FIX4/home"
FIX4_REPO="$FIX4_HOME/Projects/persona-engine"
mkdir -p "$FIX4_HOME/.codex" "$FIX4_REPO"
printf '@import .claude/ref/90-codex-lead-pilot.md\n' > "$FIX4_REPO/AGENTS.md"
printf '[marketplaces.leadv2-local]\nsource_type = "local"\nsource = "/some/other/root"\n' > "$FIX4_HOME/.codex/config.toml"
OUT5="$(HOME="$FIX4_HOME" LEADV2_CODEX_BIN="$STUB" bash "$INSTALL_SH" "$FIX4_REPO" 2>&1)"; RC5=$?
[[ $RC5 -eq 0 ]] && pass "different-root: exit 0" || fail "different-root: exit 0 (rc=$RC5)"
printf '%s' "$OUT5" | grep -q "ACTION REQUIRED: marketplace leadv2-local already registered" && pass "different-root: ACTION REQUIRED printed" || fail "different-root: no ACTION REQUIRED (out=$OUT5)"
grep -q '/some/other/root' "$FIX4_HOME/.codex/config.toml" && pass "different-root: registered root left untouched" || fail "different-root: root was re-pointed"
rm -rf "$FIX4"

# --- fallback path: CLI without plugin support ------------------------------
FIX2="$(mktemp -d)"
FIX2_HOME="$FIX2/home"
FIX2_REPO="$FIX2_HOME/Projects/persona-engine"
mkdir -p "$FIX2_HOME" "$FIX2_REPO"
printf '@import .claude/ref/90-codex-lead-pilot.md\n' > "$FIX2_REPO/AGENTS.md"

OUT3="$(HOME="$FIX2_HOME" LEADV2_CODEX_BIN="$STUB_NOPLUG" bash "$INSTALL_SH" "$FIX2_REPO" 2>&1)"; RC3=$?
[[ $RC3 -eq 0 ]] && pass "fallback: exit 0" || fail "fallback: exit 0 (rc=$RC3)"
printf '%s' "$OUT3" | grep -q "plugin: CLI has no plugin support — installed prompt pack instead" && pass "fallback: no-plugin-support line" || fail "fallback: missing no-plugin-support line (out=$OUT3)"

SENTINEL_COUNT_1="$(grep -c 'BEGIN leadv2-codex-lead repowise' "$FIX2_HOME/.codex/config.toml" 2>/dev/null || echo 0)"
[[ "$SENTINEL_COUNT_1" == "1" ]] && pass "fallback run 1: exactly one repowise sentinel block" || fail "fallback run 1: sentinel count = $SENTINEL_COUNT_1"

printf '%s' "$OUT3" | grep -q "@import line present" && pass "fallback: @import already present, no ACTION REQUIRED for it" || fail "fallback: unexpected @import handling (out=$OUT3)"
printf '%s' "$OUT3" | grep -q "ACTION REQUIRED" && fail "fallback: unexpected ACTION REQUIRED (out=$OUT3)" || pass "fallback: no ACTION REQUIRED"

OUT3B="$(HOME="$FIX2_HOME" LEADV2_CODEX_BIN="$STUB_NOPLUG" bash "$INSTALL_SH" "$FIX2_REPO" 2>&1)"; RC3B=$?
[[ $RC3B -eq 0 ]] && pass "fallback run 2: exit 0" || fail "fallback run 2: exit 0 (rc=$RC3B)"
printf '%s' "$OUT3B" | grep -q "config.toml: repowise block unchanged" && pass "fallback run 2: config.toml reported unchanged" || fail "fallback run 2: config.toml change reported on re-run (out=$OUT3B)"
SENTINEL_COUNT_2="$(grep -c 'BEGIN leadv2-codex-lead repowise' "$FIX2_HOME/.codex/config.toml" 2>/dev/null || echo 0)"
[[ "$SENTINEL_COUNT_2" == "1" ]] && pass "fallback run 2: still exactly one repowise sentinel block" || fail "fallback run 2: sentinel count = $SENTINEL_COUNT_2"

# --- fallback path: hand-written repowise block never touched ----------------
FIX2B="$(mktemp -d)"
FIX2B_HOME="$FIX2B/home"
FIX2B_REPO="$FIX2B_HOME/Projects/persona-engine"
mkdir -p "$FIX2B_HOME/.codex" "$FIX2B_REPO"
printf '@import .claude/ref/90-codex-lead-pilot.md\n' > "$FIX2B_REPO/AGENTS.md"
cat > "$FIX2B_HOME/.codex/config.toml" <<'EOF'
[mcp_servers.repowise]
command = "/hand/written/path.sh"
args = []
EOF
OUT3C="$(HOME="$FIX2B_HOME" LEADV2_CODEX_BIN="$STUB_NOPLUG" bash "$INSTALL_SH" "$FIX2B_REPO" 2>&1)"; RC3C=$?
[[ $RC3C -eq 0 ]] && pass "hand-written block: exit 0" || fail "hand-written block: exit 0 (rc=$RC3C)"
grep -q '/hand/written/path.sh' "$FIX2B_HOME/.codex/config.toml" && pass "hand-written block: left untouched" || fail "hand-written block: was modified"
printf '%s' "$OUT3C" | grep -q "already configured by hand" && pass "hand-written block: reported left-untouched message" || fail "hand-written block: missing left-untouched message (out=$OUT3C)"
rm -rf "$FIX2B"

# --- H6 (MERGED-BATCH-FIXROUND-01): marketplace add FAILS -> loud fallback ----
# A stub whose `plugin --help` succeeds (plugin path is entered) but whose
# `plugin marketplace add` exits non-zero. This branch had zero coverage:
# every prior stub succeeded at everything.
STUB_MKTFAIL="$FIX/codex-mktfail.sh"
cat > "$STUB_MKTFAIL" <<'EOF'
#!/bin/bash
if [[ "$1" == "plugin" && "$2" == "marketplace" && "$3" == "add" ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "$STUB_MKTFAIL"

FIX5="$(mktemp -d)"
FIX5_HOME="$FIX5/home"
FIX5_REPO="$FIX5_HOME/Projects/persona-engine"
mkdir -p "$FIX5_HOME" "$FIX5_REPO"
printf '@import .claude/ref/90-codex-lead-pilot.md\n' > "$FIX5_REPO/AGENTS.md"
OUT6="$(HOME="$FIX5_HOME" LEADV2_CODEX_BIN="$STUB_MKTFAIL" bash "$INSTALL_SH" "$FIX5_REPO" 2>&1)"; RC6=$?
[[ $RC6 -eq 0 ]] && pass "marketplace-add-failure: exit 0" || fail "marketplace-add-failure: exit 0 (rc=$RC6, out=$OUT6)"
printf '%s' "$OUT6" | grep -q "ACTION REQUIRED: .codex plugin marketplace add.*failed" && pass "marketplace-add-failure: ACTION REQUIRED printed" || fail "marketplace-add-failure: no ACTION REQUIRED (out=$OUT6)"
printf '%s' "$OUT6" | grep -q "plugin: CLI has no plugin support — installed prompt pack instead" && pass "marketplace-add-failure: prompt-pack fallback installed" || fail "marketplace-add-failure: no fallback line (out=$OUT6)"
GOT_PROMPTS5="$(ls -1 "$FIX5_HOME/.codex/prompts"/*.md 2>/dev/null | wc -l | tr -d ' ')"
[[ "$GOT_PROMPTS5" == "$N_PROMPTS" ]] && pass "marketplace-add-failure: all prompts installed by fallback" || fail "marketplace-add-failure: prompt count ($GOT_PROMPTS5 != $N_PROMPTS)"
grep -qF '[plugins."leadv2@leadv2-local"]' "$FIX5_HOME/.codex/config.toml" 2>/dev/null && fail "marketplace-add-failure: plugin registered despite failed marketplace" || pass "marketplace-add-failure: plugin not registered"
rm -rf "$FIX5"

# --- H6 (MERGED-BATCH-FIXROUND-01): fallback -> plugin upgrade path -----------
# lean: characterises M2, not a fix. A host that ran the pre-plugin installer
# carries the managed [mcp_servers.repowise] sentinel block; upgrading to the
# plugin path skips the TOML block (the plugin .mcp.json owns repowise) but
# does NOT strip the old one — leaving two servers named repowise. M2 is a
# deliberate non-goal of MERGED-BATCH-FIXROUND-01 (config-mutating change on
# already-installed hosts needs founder sign-off); this case pins today's
# behaviour so the defect is visible the moment someone looks for it.
FIX6="$(mktemp -d)"
FIX6_HOME="$FIX6/home"
FIX6_REPO="$FIX6_HOME/Projects/persona-engine"
mkdir -p "$FIX6_HOME" "$FIX6_REPO"
printf '@import .claude/ref/90-codex-lead-pilot.md\n' > "$FIX6_REPO/AGENTS.md"
OUT7A="$(HOME="$FIX6_HOME" LEADV2_CODEX_BIN="$STUB_NOPLUG" bash "$INSTALL_SH" "$FIX6_REPO" 2>&1)"; RC7A=$?
[[ $RC7A -eq 0 ]] && pass "upgrade run A (fallback): exit 0" || fail "upgrade run A: exit 0 (rc=$RC7A)"
grep -q 'BEGIN leadv2-codex-lead repowise' "$FIX6_HOME/.codex/config.toml" && pass "upgrade run A: sentinel block written" || fail "upgrade run A: no sentinel block"
OUT7B="$(HOME="$FIX6_HOME" LEADV2_CODEX_BIN="$STUB" bash "$INSTALL_SH" "$FIX6_REPO" 2>&1)"; RC7B=$?
[[ $RC7B -eq 0 ]] && pass "upgrade run B (plugin): exit 0" || fail "upgrade run B: exit 0 (rc=$RC7B, out=$OUT7B)"
printf '%s' "$OUT7B" | grep -q "plugin: installed leadv2@leadv2-local" && pass "upgrade run B: plugin installed" || fail "upgrade run B: plugin not installed (out=$OUT7B)"
SENTINEL_STILL="$(grep -c 'BEGIN leadv2-codex-lead repowise' "$FIX6_HOME/.codex/config.toml" 2>/dev/null || echo 0)"
MCPJSON_DECL="$(grep -c '"repowise"' "$CODEX_LEAD_DIR/marketplace/plugins/leadv2/.mcp.json" 2>/dev/null || echo 0)"
if [[ "$SENTINEL_STILL" == "1" && "$MCPJSON_DECL" -ge 1 ]]; then
  pass "upgrade run B: M2 characterised — old TOML repowise block survives next to plugin .mcp.json (two servers named repowise; strip is founder-gated)"
else
  fail "upgrade run B: M2 shape changed (sentinel=$SENTINEL_STILL mcpjson=$MCPJSON_DECL) — update this characterisation"
fi
rm -rf "$FIX6"

# --- target repo missing -> rc 3 ---------------------------------------------
FIX3_HOME="$(mktemp -d)"
OUT4="$(HOME="$FIX3_HOME" LEADV2_CODEX_BIN="$STUB" bash "$INSTALL_SH" "$FIX3_HOME/no-such-repo" 2>&1)"; RC4=$?
[[ $RC4 -eq 3 ]] && pass "missing target repo -> rc 3" || fail "missing target repo -> rc 3 (got rc=$RC4, out=$OUT4)"
rm -rf "$FIX3_HOME"

# --- bash -n --------------------------------------------------------------
bash -n "$INSTALL_SH" && pass "bash -n install.sh" || fail "bash -n install.sh"

echo
echo "==================================================="
echo "PASS: $PASS  FAIL: $FAIL"
echo "==================================================="
if [[ $FAIL -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
