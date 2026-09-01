#!/usr/bin/env bash
# FABLE-THINK-TIER-01 (2026-09-01, founder order).
#
# THE CONTRACT THIS SUITE PINS: every role whose value is THINKING (not typing)
# runs on Fable 5.1 (`claude-fable-5-1`) first; Opus 5 is the fallback when
# Fable is refused/unavailable — never the default. Typing roles (developer,
# GLM/Kimi/Codex arms, haiku reads) are untouched; Sonnet stays the Standard
# critic. R2 (2026-09-01): the round-1 "same Claude-Max bucket as Opus" claim
# was WITHDRAWN — the quota-read probe showed five_hour unchanged across a
# live fable probe and a separate Fable weekly_scoped window in the reader
# (evidence: model-capability.yaml fable row). The review pool keeps fable on
# the anthropic ACCOUNT reading as the conservative ceiling only.
#
# Pins:
#   1. think_model() resolver — default fable; `unavailable: true` in
#      model-capability.yaml -> opus; LEADV2_THINK_MODEL env wins outright
#      (negative control).
#   2. grep-gates — TREE-WIDE census (reviewer R2 HIGH fix): the census grep
#      itself runs over plugins/leadv2/{scripts,workflows,skills,hooks} and
#      every 'opus' hit must classify as comment/prose, explicit-fallback, or
#      route-telemetry; a live think-role spawn pin is red. Plus zero `opus-4`
#      literals under the same tree ("Opus means Opus 5, never 4.8").
#   3. review pool — fable enters ahead of opus (anthropic ACCOUNT reading as
#      the conservative ceiling) and the diff author's arm is never picked.
#   4. dispatch architect prepass — no `:-opus` literal default; resolves
#      through the router's think-model query mode.
#
# No network, no provider: the pool test uses the REAL resolver with a stubbed
# --quota-live reader (same pattern as test-review-arm-failclosed-nonzero.sh).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPTS_ROOT/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
ROUTER="${LEADV2_TEST_ROUTER:-$SCRIPTS_ROOT/leadv2-router.sh}"
RESOLVER="${LEADV2_TEST_RESOLVER:-$SCRIPTS_ROOT/lib/leadv2-glm-policy-resolve.py}"
CAP_YAML="${LEADV2_MODEL_CAPABILITY_YAML:-$PLUGIN_ROOT/config/model-capability.yaml}"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- 1. resolver: default is fable -----------------------------------------
out="$(bash "$ROUTER" think-model 2>/dev/null)"
if [[ "$out" == "fable" ]]; then
  pass "resolver default = fable"
else
  fail "resolver default expected 'fable', got '${out:-<empty>}'"
fi

# --- 1b. resolver: env override wins (negative control) ---------------------
out="$(LEADV2_THINK_MODEL=opus bash "$ROUTER" think-model 2>/dev/null)"
if [[ "$out" == "opus" ]]; then
  pass "resolver LEADV2_THINK_MODEL=opus override wins (negative control)"
else
  fail "resolver override expected 'opus', got '${out:-<empty>}'"
fi

# --- 1c. resolver: capability yaml 'unavailable: true' -> opus --------------
printf 'fable:\n  model_id: claude-fable-5-1\n  unavailable: true\n' > "$TMP/cap-unavailable.yaml"
out="$(LEADV2_MODEL_CAPABILITY_YAML="$TMP/cap-unavailable.yaml" bash "$ROUTER" think-model 2>/dev/null)"
if [[ "$out" == "opus" ]]; then
  pass "resolver falls back to opus when fable marked unavailable"
else
  fail "resolver fallback expected 'opus', got '${out:-<empty>}'"
fi

# --- 2. TREE-WIDE census grep-gate: zero live think-role 'opus' pins --------
# This is the census command from the lane report, run over the whole plugin
# tree. Survivors allowed (each classified in the dispatch round-2 report):
#   - comment lines (`# ...`) and route telemetry (emit/log/printf lines that
#     DESCRIBE an opus decision the router already made) — they spawn nothing
#   - explicit fallback sites (the line itself names the fallback)
#   - guard prose ("opus is reserved for ..." — the hook ENFORCES the tiering)
#   - test fixtures under scripts/tests/ (excluded entirely)
census_re="model[=: ]+['\"]?opus|--model[ =]['\"]?opus"
census="$(grep -rnE "$census_re" \
    "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/workflows" "$PLUGIN_ROOT/skills" "$PLUGIN_ROOT/hooks" 2>/dev/null \
  | grep -v "$PLUGIN_ROOT/scripts/tests/" \
  | grep -vE ":[0-9]+: *(#|emit |log |log_warn |printf )" \
  | grep -viE "fallback|reserved for" \
  || true)"
# Second census pass: spawn lines naming a think role that also mention opus
# on the same line — catches pins written as `model=<opus ...>` or role-first
# syntax the first pattern misses.
census2="$(grep -rnE "(subagent_type|agentType)[\"'= :]+[^,)]*(architect|critic|judge)" \
    "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/workflows" "$PLUGIN_ROOT/skills" "$PLUGIN_ROOT/hooks" 2>/dev/null \
  | grep -v "$PLUGIN_ROOT/scripts/tests/" \
  | grep -iE "opus" \
  | grep -viE "fallback|reserved for" \
  || true)"
if [[ -z "$census" && -z "$census2" ]]; then
  pass "tree-wide census: zero live think-role 'opus' spawn pins"
else
  [[ -n "$census"  ]] && fail "tree-wide census: unclassified 'opus' literal(s): $census"
  [[ -n "$census2" ]] && fail "tree-wide census: think-role spawn line pinning opus: $census2"
fi
# The four migrated workflows keep their THINK_MODEL const (resolver wiring).
for wf in leadv2-diverge leadv2-learn leadv2-diagnose leadv2-po-feedback-loop; do
  f="$PLUGIN_ROOT/workflows/${wf}.js"
  if [[ ! -f "$f" ]]; then fail "workflow missing: $f"; continue; fi
  grep -n "const THINK_MODEL" "$f" >/dev/null 2>&1 \
    && pass "$wf: THINK_MODEL const present" \
    || fail "$wf: THINK_MODEL const missing"
done

# --- 2b. grep-gate: zero opus-4 literals (Opus means Opus 5) ----------------
opus4_hits="$(grep -rn --exclude="$(basename "$0")" 'opus-4' \
  "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/config" "$PLUGIN_ROOT/ref" \
  "$PLUGIN_ROOT/workflows" "$PLUGIN_ROOT/hooks" 2>/dev/null || true)"
if [[ -z "$opus4_hits" ]]; then
  pass "zero opus-4 literals under plugins/leadv2/{scripts,config,ref,workflows,hooks}"
else
  fail "opus-4 literals found (must be claude-opus-5): $opus4_hits"
fi

# --- 3. review pool: fable ahead of opus, author excluded -------------------
cat > "$TMP/quota-live.sh" <<'SH'
#!/usr/bin/env bash
# Real reader contract (JSON). anthropic 30% (< 95 ceiling) -> every
# claude-family arm ok; codex 98% / glm 95% blocked by their thresholds.
case "$1" in
  codex)     printf '{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":98.0}]}\n' ;;
  glm)       printf '{"status":"ok","five_hour":{"pct":95.0},"weekly":{"pct":95.0}}\n' ;;
  anthropic) printf '{"status":"ok","accounts":[{"active":true,"account_label":"a","five_hour_pct":30.0,"seven_day_pct":30.0}]}\n' ;;
  *)         printf '{"status":"ok"}\n' ;;
esac
SH
chmod +x "$TMP/quota-live.sh"
# Hermetic: no live lockout files may bar an arm (codex lockout is a REAL
# on-disk artefact of the running fleet — never let the suite read it).
export LEADV2_QUOTA_LOCKOUT_DIR="$TMP/lockout-empty"
mkdir -p "$LEADV2_QUOTA_LOCKOUT_DIR"

pool_out="$(python3 "$RESOLVER" --routing-yaml /dev/null --job review --base-arm codex \
  --review-pool --author kimi --signals '{}' \
  --quota-live "$TMP/quota-live.sh" 2>/dev/null || true)"
pool_line="$(printf '%s\n' "$pool_out" | grep '^pool=' | head -1)"
rev_line="$(printf '%s\n' "$pool_out" | grep '^reviewer=' | head -1)"
# fable must be :ok: and must appear BEFORE opus in the pool
fable_idx="$(printf '%s' "${pool_line#pool=}" | tr ',' '\n' | awk -F: '$1=="fable"{print NR; exit}')"
opus_idx="$(printf '%s' "${pool_line#pool=}" | tr ',' '\n' | awk -F: '$1=="opus"{print NR; exit}')"
fable_ok="$(printf '%s' "${pool_line#pool=}" | tr ',' '\n' | grep -c '^fable:ok:')"
if [[ "${fable_idx:-0}" -gt 0 && "${opus_idx:-0}" -gt 0 && "${fable_idx}" -lt "${opus_idx}" ]]; then
  pass "pool orders fable before opus (${pool_line#pool=})"
else
  fail "pool must list fable (ok) before opus; got: ${pool_line:-<none>}"
fi
if [[ "${fable_ok:-0}" -ge 1 ]]; then
  pass "fable shares the anthropic reading (ok under the 95 ceiling)"
else
  fail "fable not ok in pool — anthropic bucket mapping missing: ${pool_line:-<none>}"
fi
if [[ "$rev_line" == "reviewer=fable" ]]; then
  pass "reviewer=fable (first eligible arm after the author/probe exclusions)"
else
  fail "reviewer expected fable, got: ${rev_line:-<none>}"
fi
# author exclusion: author=opus -> opus must carry :author: and fable must win
# safety signals exclude kimi (probe-gated arm never reviews safety), so with
# opus as author the reviewer must be fable — the first eligible think arm.
pool_out2="$(LEADV2_QUOTA_LOCKOUT_DIR="$TMP/lockout-empty" python3 "$RESOLVER" --routing-yaml /dev/null --job review --base-arm codex \
  --review-pool --author opus --signals '{"safety_touched":true}' \
  --quota-live "$TMP/quota-live.sh" 2>/dev/null || true)"
pool_line2="$(printf '%s\n' "$pool_out2" | grep '^pool=' | head -1)"
rev_line2="$(printf '%s\n' "$pool_out2" | grep '^reviewer=' | head -1)"
if printf '%s' "$pool_line2" | grep -q 'opus:author:' && [[ "$rev_line2" == "reviewer=fable" ]]; then
  pass "author-exclusion intact: author=opus excluded, reviewer=fable"
else
  fail "author-exclusion broke: ${pool_line2:-<none>} / ${rev_line2:-<none>}"
fi

# --- 4. dispatch architect prepass default goes through the resolver --------
if grep -n 'LEADV2_DISPATCH_ARCHITECT_MODEL:-opus' "$SCRIPTS_ROOT/leadv2-dispatch-code.sh" >/dev/null 2>&1; then
  fail "dispatch-code.sh still hardcodes \${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}"
else
  pass "dispatch-code.sh: no hardcoded opus prepass default"
fi
if grep -n '_LEADV2_ARCHITECT_THINK_DEFAULT' "$SCRIPTS_ROOT/leadv2-dispatch-code.sh" | grep -q 'leadv2-router.sh"; think-model\|router.sh" think-model'; then
  pass "dispatch-code.sh prepass default resolves via router think-model"
else
  fail "dispatch-code.sh: _LEADV2_ARCHITECT_THINK_DEFAULT not wired to router think-model"
fi

log "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
