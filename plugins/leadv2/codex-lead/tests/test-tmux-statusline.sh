#!/usr/bin/env bash
# tests/test-tmux-statusline.sh — CODEX-TMUX-STATUSLINE-01.
# Covers the functional contract: wrapper cache hit / stale refresh / error
# fallback (via LEADV2_STATUSLINE_CMD stub — never the real quota runtime),
# default install touches no tmux config, --tmux-conf install is idempotent
# and preserves non-managed content, uninstall removes only the managed block,
# and everything survives paths with spaces. All tmux-conf fixtures are files
# inside a mktemp HOME; the real user config is never touched.
#
# Run: bash plugins/leadv2/codex-lead/tests/test-tmux-statusline.sh
# Exit 0 = all pass; non-zero = failures found.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_LEAD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUSLINE_DIR="$CODEX_LEAD_DIR/statusline"
WRAPPER="$STATUSLINE_DIR/leadv2-tmux-status.sh"
INSTALL_SH="$STATUSLINE_DIR/install-tmux-statusline.sh"
UNINSTALL_SH="$STATUSLINE_DIR/uninstall-tmux-statusline.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# fixture root deliberately contains a space (contract: paths with spaces)
FIX="$(mktemp -d)/spa ced"
trap 'rm -rf "$(dirname "$FIX")"' EXIT
FIX_HOME="$FIX/home"
mkdir -p "$FIX_HOME"

# =====================================================================
# A. wrapper: cache hit / stale refresh / error fallback
# =====================================================================
STUB="$FIX/status-stub.sh"
CALLS="$FIX/stub-calls.log"
cat > "$STUB" <<'EOF'
#!/bin/bash
printf 'call\n' >> "$STUB_CALLS_LOG"
printf 'cc 10%%/1d2h · cx 20%%/3h · glm 30%%/5h | lanes 2 | task FIX-1\n'
EOF
chmod +x "$STUB"
export STUB_CALLS_LOG="$CALLS"
CACHE="$FIX/cache dir/status.cache"   # cache path with a space, on purpose
NC=0   # number of stub calls so far
calls() {
  if [[ -f "$CALLS" ]]; then wc -l < "$CALLS" | tr -d ' '; else printf '0'; fi
}

run_wrap() { LEADV2_STATUSLINE_CMD="$STUB" LEADV2_STATUSLINE_CACHE="$CACHE" \
  LEADV2_STATUSLINE_TTL=20 bash "$WRAPPER"; }

rm -f "$CALLS"
OUT="$(run_wrap)"
[[ "$OUT" == *"task FIX-1"* ]] && pass "A1 fresh render calls stub and prints status line" \
  || fail "A1 fresh render calls stub and prints status line (got: $OUT)"
[[ "$(cat "$CACHE")" == *"task FIX-1"* ]] && pass "A2 fresh render writes cache" \
  || fail "A2 fresh render writes cache"

NC="$(calls)"
OUT="$(run_wrap)"
[[ "$OUT" == *"task FIX-1"* ]] && pass "A3 cache hit still renders the line" \
  || fail "A3 cache hit still renders the line (got: $OUT)"
[[ "$(calls)" == "$NC" ]] && pass "A4 cache hit does NOT call the stub" \
  || fail "A4 cache hit does NOT call the stub (calls: $(calls) vs $NC)"

# stale: backdate the cache beyond TTL, stub output changes
cat > "$STUB" <<'EOF'
#!/bin/bash
printf 'call\n' >> "$STUB_CALLS_LOG"
printf 'cc 90%%/1h | lanes 1 | task REFRESHED\n'
EOF
chmod +x "$STUB"
touch -t 202001010000 "$CACHE"
OUT="$(run_wrap)"
[[ "$OUT" == *"REFRESHED"* ]] && pass "A5 stale cache refreshes via stub" \
  || fail "A5 stale cache refreshes via stub (got: $OUT)"
[[ "$(cat "$CACHE")" == *"REFRESHED"* ]] && pass "A6 refresh rewrites the cache" \
  || fail "A6 refresh rewrites the cache"

# stale-while-error: stub fails, cache exists (still backdated) → last good line
cat > "$STUB" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$STUB"
touch -t 202001010000 "$CACHE"
OUT="$(run_wrap)"
RC=$?
[[ "$OUT" == *"REFRESHED"* ]] && pass "A7 stub failure serves stale cache (stale-while-error)" \
  || fail "A7 stub failure serves stale cache (got: $OUT)"
[[ "$RC" == "0" ]] && pass "A8 wrapper always exits 0" || fail "A8 wrapper always exits 0 (rc=$RC)"

# no cache at all + stub failure → compact fallback
rm -rf "$(dirname "$CACHE")"
OUT="$(run_wrap)"
[[ "$OUT" == "leadv2 ?" ]] && pass "A9 no cache + failure renders compact fallback" \
  || fail "A9 no cache + failure renders compact fallback (got: $OUT)"

# missing status command → fallback, exit 0
OUT="$(LEADV2_STATUSLINE_CMD="$FIX/no such cmd" LEADV2_STATUSLINE_CACHE="$CACHE" bash "$WRAPPER")"; RC=$?
[[ "$OUT" == "leadv2 ?" && "$RC" == "0" ]] && pass "A10 missing status command → fallback rc=0" \
  || fail "A10 missing status command → fallback rc=0 (got: $OUT rc=$RC)"

# =====================================================================
# B. install default: assets only, NO tmux config mutation
# =====================================================================
B_HOME="$FIX/home B"
mkdir -p "$B_HOME"
B_CONF="$B_HOME/.tmux.conf"
printf '# my tmux\nset -g prefix C-a\n' > "$B_CONF"
B_SUM_BEFORE="$(cksum "$B_CONF")"

OUT="$(HOME="$B_HOME" XDG_CONFIG_HOME="$B_HOME/.config" bash "$INSTALL_SH")"; RC=$?
[[ "$RC" == "0" ]] && pass "B1 default install rc=0" || fail "B1 default install rc=$RC"
[[ "$B_SUM_BEFORE" == "$(cksum "$B_CONF")" ]] && pass "B2 default install leaves existing tmux.conf untouched" \
  || fail "B2 default install mutated existing tmux.conf"
grep -qF 'BEGIN leadv2 tmux statusline' "$B_CONF" \
  && fail "B3 default install adds no managed block" || pass "B3 default install adds no managed block"
GEN="$B_HOME/.config/leadv2/tmux-statusline.conf"
[[ -f "$GEN" ]] && pass "B4 default install generates activation conf" \
  || fail "B4 default install generates activation conf ($GEN missing)"
grep -qF 'set -g status-right' "$GEN" 2>/dev/null && pass "B5 conf sets status-right" \
  || fail "B5 conf sets status-right"
grep -qF "tmux source-file" <<<"$OUT" && pass "B6 default install prints the activation command" \
  || fail "B6 default install prints the activation command"

# =====================================================================
# C. install --tmux-conf: idempotent managed block, content preserved
# =====================================================================
C_HOME="$FIX/home C"
mkdir -p "$C_HOME"
C_CONF="$C_HOME/tmux conf with space.conf"   # tmux-conf path with a space
printf '# user header\nset -g prefix C-a\nset -g status-right "#S"\n' > "$C_CONF"

OUT="$(HOME="$C_HOME" XDG_CONFIG_HOME="$C_HOME/.config" bash "$INSTALL_SH" --tmux-conf "$C_CONF")"; RC=$?
[[ "$RC" == "0" ]] && pass "C1 explicit install rc=0" || fail "C1 explicit install rc=$RC"
grep -qF '# user header' "$C_CONF" && grep -qF 'set -g prefix C-a' "$C_CONF" \
  && grep -qF 'set -g status-right "#S"' "$C_CONF" \
  && pass "C2 non-managed content preserved" || fail "C2 non-managed content preserved"
COUNT="$(grep -cF 'BEGIN leadv2 tmux statusline' "$C_CONF")"
[[ "$COUNT" == "1" ]] && pass "C3 managed block present exactly once" \
  || fail "C3 managed block present exactly once (count=$COUNT)"
grep -qF "source-file \"$C_HOME/.config/leadv2/tmux-statusline.conf\"" "$C_CONF" \
  && pass "C4 block source-files the generated conf" || fail "C4 block source-files the generated conf"

SUM_AFTER_FIRST="$(cksum "$C_CONF")"
OUT="$(HOME="$C_HOME" XDG_CONFIG_HOME="$C_HOME/.config" bash "$INSTALL_SH" --tmux-conf "$C_CONF")"; RC=$?
[[ "$RC" == "0" && "$SUM_AFTER_FIRST" == "$(cksum "$C_CONF")" ]] \
  && pass "C5 second install is byte-idempotent" || fail "C5 second install is byte-idempotent (rc=$RC)"

# quoting end-to-end: extract the #() payload and run it exactly as popen/sh
# would — proves a wrapper path containing spaces stays one word, no eval
GEN_C="$C_HOME/.config/leadv2/tmux-statusline.conf"
PAYLOAD="$(sed -n 's/^set -g status-right "#(\\"\(.*\)\\")"$/\1/p' "$GEN_C")"
[[ -n "$PAYLOAD" ]] && pass "C6 conf exposes a quoted #() payload" || fail "C6 conf exposes a quoted #() payload"
POUT="$(HOME="$C_HOME" LEADV2_STATUSLINE_CACHE="$CACHE" sh -c "$PAYLOAD" 2>/dev/null)"; RC=$?
[[ "$RC" == "0" && -n "$POUT" ]] && pass "C7 #() payload runs via sh with spaces in path" \
  || fail "C7 #() payload runs via sh with spaces in path (rc=$RC out=$POUT)"

# no eval: payload must be a pure double-quoted path, no $(), ``, ;, &&
if printf '%s' "$PAYLOAD" | grep -qE '\$|\(|`|;|&&|\|'; then
  fail "C8 payload contains shell metacharacters (got: $PAYLOAD)"
else
  pass "C8 payload is a quoted path, no metacharacters/eval"
fi

# =====================================================================
# D. uninstall: selective removal, idempotent
# =====================================================================
OUT="$(HOME="$C_HOME" XDG_CONFIG_HOME="$C_HOME/.config" bash "$UNINSTALL_SH" --tmux-conf "$C_CONF")"; RC=$?
[[ "$RC" == "0" ]] && pass "D1 uninstall rc=0" || fail "D1 uninstall rc=$RC"
grep -qF 'BEGIN leadv2 tmux statusline' "$C_CONF" \
  && fail "D2 managed block removed" || pass "D2 managed block removed"
grep -qF '# user header' "$C_CONF" && grep -qF 'set -g prefix C-a' "$C_CONF" \
  && grep -qF 'set -g status-right "#S"' "$C_CONF" \
  && pass "D3 non-managed content preserved after uninstall" || fail "D3 non-managed content preserved after uninstall"
[[ ! -f "$GEN_C" ]] && pass "D4 generated conf removed" || fail "D4 generated conf removed"
SUM_AFTER_UNINSTALL="$(cksum "$C_CONF")"
OUT="$(HOME="$C_HOME" XDG_CONFIG_HOME="$C_HOME/.config" bash "$UNINSTALL_SH" --tmux-conf "$C_CONF")"; RC=$?
[[ "$RC" == "0" && "$SUM_AFTER_UNINSTALL" == "$(cksum "$C_CONF")" ]] \
  && pass "D5 second uninstall is a no-op" || fail "D5 second uninstall is a no-op (rc=$RC)"

# restore C's block, then verify uninstall byte-restores the original file
printf '# user header\nset -g prefix C-a\nset -g status-right "#S"\n' > "$C_CONF"
SUM_ORIG="$(cksum "$C_CONF")"
HOME="$C_HOME" XDG_CONFIG_HOME="$C_HOME/.config" bash "$INSTALL_SH" --tmux-conf "$C_CONF" >/dev/null
HOME="$C_HOME" XDG_CONFIG_HOME="$C_HOME/.config" bash "$UNINSTALL_SH" --tmux-conf "$C_CONF" >/dev/null
[[ "$SUM_ORIG" == "$(cksum "$C_CONF")" ]] && pass "D6 install→uninstall round-trips byte-identical" \
  || fail "D6 install→uninstall round-trips byte-identical"

# =====================================================================
# E. public-path safety: apostrophes must survive tmux's config parser;
#    pre-existing generated-conf target must be restored, never deleted.
# =====================================================================
Q_DIR="$FIX/O'Brien statusline"
cp -R "$STATUSLINE_DIR" "$Q_DIR"
Q_INSTALL="$Q_DIR/install-tmux-statusline.sh"
Q_UNINSTALL="$Q_DIR/uninstall-tmux-statusline.sh"
Q_HOME="$FIX/home O'Brien"
Q_CONF="$Q_HOME/tmux.conf"
mkdir -p "$Q_HOME/.config/leadv2"
printf 'user-owned generated-conf\nset -g status-right "ORIGINAL"\n' > "$Q_HOME/.config/leadv2/tmux-statusline.conf"
Q_ORIGINAL_SUM="$(cksum "$Q_HOME/.config/leadv2/tmux-statusline.conf")"
printf '# user tmux config\n' > "$Q_CONF"
HOME="$Q_HOME" XDG_CONFIG_HOME="$Q_HOME/.config" bash "$Q_INSTALL" --tmux-conf "$Q_CONF" >/dev/null; RC=$?
[[ "$RC" == "0" && -f "$Q_HOME/.config/leadv2/tmux-statusline.conf.leadv2-original" ]] \
  && pass "E1 install preserves pre-existing generated-conf" || fail "E1 install preserves pre-existing generated-conf"
Q_SOCKET="lv2quote$$"
Q_TMUX_DIR="$(mktemp -d)"
TMUX_TMPDIR="$Q_TMUX_DIR" tmux -L "$Q_SOCKET" -f /dev/null new-session -d -s quote >/dev/null 2>&1
TMUX_TMPDIR="$Q_TMUX_DIR" tmux -L "$Q_SOCKET" source-file "$Q_CONF" >/dev/null 2>&1
Q_RIGHT="$(TMUX_TMPDIR="$Q_TMUX_DIR" tmux -L "$Q_SOCKET" show-option -gv status-right 2>/dev/null)"
TMUX_TMPDIR="$Q_TMUX_DIR" tmux -L "$Q_SOCKET" kill-server >/dev/null 2>&1 || :
rm -rf "$Q_TMUX_DIR"
[[ "$Q_RIGHT" == *"O'Brien statusline"* ]] && pass "E2 tmux parses apostrophe path into status-right" \
  || fail "E2 tmux apostrophe path broken (status-right=$Q_RIGHT)"
HOME="$Q_HOME" XDG_CONFIG_HOME="$Q_HOME/.config" bash "$Q_UNINSTALL" --tmux-conf "$Q_CONF" >/dev/null; RC=$?
[[ "$RC" == "0" && "$Q_ORIGINAL_SUM" == "$(cksum "$Q_HOME/.config/leadv2/tmux-statusline.conf")" ]] \
  && pass "E3 uninstall restores pre-existing generated-conf byte-identically" \
  || fail "E3 uninstall does not restore pre-existing generated-conf"
[[ ! -e "$Q_HOME/.config/leadv2/tmux-statusline.conf.leadv2-original" ]] \
  && pass "E4 ownership marker removed after restore" || fail "E4 ownership marker remains"

# =====================================================================
# F. argument contract
# =====================================================================
bash "$INSTALL_SH" --bogus >/dev/null 2>&1; [[ $? == "2" ]] && pass "E1 unknown arg rc=2" || fail "E1 unknown arg rc=2"
bash "$UNINSTALL_SH" --bogus >/dev/null 2>&1; [[ $? == "2" ]] && pass "E2 uninstall unknown arg rc=2" || fail "E2 uninstall unknown arg rc=2"

# =====================================================================
printf '\n'
printf 'tmux-statusline tests: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
