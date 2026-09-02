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
#   5. R4 (2026-09-02): value-class census — pins matched by VALUE shape
#      regardless of variable name/case (uppercase X_MODEL="opus",
#      ${X:-opus}, generic X="opus", "KEY":"opus", arm arrays); resolver files
#      exempted at file level; every other surviving opus hit carries an
#      explicit allowlist entry with a one-line reason.
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
# Value-class match: bare 'opus', full model ids ('claude-opus-5', future
# 'claude-opus-4.8'), and context-window suffixes ('opus[1m]') all classify
# as the SAME pin — a rename or full-id spelling must not evade the census.
census_re="[Mm][Oo][Dd][Ee][Ll][A-Za-z_0-9]*[^A-Za-z0-9_$]{1,4}['\"]?(claude-)?opus(-[0-9][0-9.]*)?(\\[1m\\])?['\"]?|[A-Za-z_][A-Za-z_0-9]*:?[+-]?=['\"]?(claude-)?opus(-[0-9][0-9.]*)?(\\[1m\\])?['\"]?([[:space:]]|;|\\)|,|$)|[,:[:space:]]['\"](claude-)?opus(-[0-9][0-9.]*)?['\"]|\$\{[A-Za-z_][A-Za-z_0-9]*:[-+]?['\"]?(claude-)?opus(-[0-9][0-9.]*)?|--model[ =]['\"]?(claude-)?opus(-[0-9][0-9.]*)?"

# A survivor is exempt ONLY if it is (a) guard prose ("... reserved for ..."),
# or (b) a fallback branch that is itself gated by a resolver check in the
# 2 preceding lines (e.g. `if (X !== 'opus')` / `think-model` on the guard
# line) — the bare word "fallback" on the pin line is NOT an exemption, since
# a rename to a fallback-sounding label would otherwise defeat the gate.
_lv2_classify_survivor() {
  local file="$1" lineno="$2" content="$3" ctx
  printf '%s' "$content" | grep -qiE "reserved for" && return 0
  if printf '%s' "$content" | grep -qiE "fallback"; then
    ctx="$(sed -n "$(( lineno > 25 ? lineno - 25 : 1 )),${lineno}p" "$file" 2>/dev/null)"
    printf '%s' "$ctx" | grep -qE "THINK_MODEL[[:space:]]*[=!]==?[[:space:]]*['\"]opus['\"]|think-model" && return 0
  fi
  # line itself is resolver-wired (chain/guard naming THINK_MODEL)
  printf '%s' "$content" | grep -qE "THINK_MODEL|think-model" && return 0
  # shell fallback operator immediately after a resolver call (preceding 2
  # lines), e.g. dispatch-code.sh: _LEADV2_ARCHITECT_THINK_DEFAULT="opus"
  if printf '%s' "$content" | grep -qE '\|\|'; then
    ctx="$(sed -n "$(( lineno > 2 ? lineno - 2 : 1 )),${lineno}p" "$file" 2>/dev/null)"
    printf '%s' "$ctx" | grep -qE "think-model|THINK_MODEL" && return 0
  fi
  return 1
}

# Explicit allowlist: opus hits that are NOT think-role spawn pins. Each entry
# is "path-suffix::content-regex::reason". If the matched line drifts, the
# entry stops matching and the census goes red (self-falsifying allowlist).
ALLOWLIST=(
  'leadv2-model-inherit-guard.sh::grep -q "opus"::hook containment check — classifies a model id, spawns nothing'
  'claude-subsession.sh::--model <opus[|]sonnet>::usage prose'
  'claude-subsession.sh::if "opus" in m::python containment check on an already-resolved model id'
  'leadv2-cache-warm.sh::opus\)   MODEL_ID="claude-opus-5"::alias-to-full-id case mapping; MODEL comes from the caller'
  'leadv2-cost-estimate.sh::Usage:.*--main-model::usage prose'
  'leadv2-cost-estimate.sh::"opus":   \{"input"::pricing table row'
  'leadv2-cost-flush.sh::if "opus" in m::python containment check on an already-resolved model id'
  'leadv2-dispatch-code.sh::arm=opus \(lead::exit-code documentation prose (heredoc text)'
  'leadv2-dispatch-code.sh::== "opus" \]\]::comparison branch on a router-resolved arm'
  'leadv2-lane-status-line-tail.sh::if .opus. in val::python containment check (status surfacing)'
  'leadv2-llm-judge-parse.sh::MODEL_USED="opus"::metadata label default in a parser; actual judge arm comes from leadv2-llm-judge.sh/router'
  'leadv2-main-model-check.sh::MAIN_MODEL="opus"::opus-guardrail CHECKER (LEADV2_FORCE_OPUS_LEAD=1 path), not a spawn'
  'leadv2-main-model-check.sh::!= "opus"::comparison in the same opus-guardrail checker'
  'leadv2-priors-compile.sh::"(new-route|cross-service|strategic)": "opus"|"critic": \{"default": "opus"\}::compiled priors prose route table; live spawns resolve via router/bandit'
  'leadv2-router-v2.py::"opus": "anthropic"|"claude-opus": "anthropic"::arm-to-provider map'
  'leadv2-router-v2.py::not in \("sonnet", "opus"\)::allowed-arms membership validation'
  'leadv2-glm-policy-resolve.py::DISPATCHABLE_PLAN_ARMS|DEFAULT_REVIEW_ARM_ORDER|"opus", "opus_mission_kind"::pool-resolver arm constants; fable ordered before opus (pinned by section 3)'
  'leadv2-worker-reason.sh::any\(k in arm for k in \("sonnet", "claude", "opus", "haiku"\)\)::provider-class membership check on an already-resolved arm; spawns nothing'
  'leadv2-causal-critique.js::TASK_CLASS === .Heavy. \? .opus.::PRE-EXISTING think-role pin — workflow file OUTSIDE this lane LANE_WRITES; the old lowercase-only census regex missed it (this match proves review HIGH-1). NOT fixed here — flagged for a follow-up lane in the round-4 report'
  'leadv2-review/SKILL.md::critic=opus::skill doc table prose (auto-upgrade description); live review pool comes from glm-policy-resolve'
  'SCHEMAS.md::model_used: opus::skill schema doc prose'
  'WRITER.md::"model_used": judge.get::skill doc example'
  'workflow-review-reference.md::claude-opus-5::reference doc of legacy workflow JS; live pool pins fable ahead of opus'
  'leadv2-token-discipline/SKILL.md::LEADV2_MAIN_MODEL=opus::stale doc prose about the main-model env (doc debt, logged in round-4 report)'
)

_lv2_allowlisted() { # $1=file $2=content — rc0 if an allowlist entry matches
  local file="$1" content="$2" entry fpat rest cpat
  for entry in "${ALLOWLIST[@]}"; do
    fpat="${entry%%::*}"; rest="${entry#*::}"; cpat="${rest%%::*}"
    if [[ "$file" == *"$fpat" ]]; then
      printf '%s' "$content" | grep -qE -e "$cpat" && return 0
    fi
  done
  return 1
}

_lv2_filter_census() {
  local raw="$1" line file rest lineno content out=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    file="${line%%:*}"
    rest="${line#*:}"
    lineno="${rest%%:*}"
    content="${rest#*:}"
    _lv2_classify_survivor "$file" "$lineno" "$content" && continue
    _lv2_allowlisted "$file" "$content" && continue
    out="${out}${line}"$'\n'
  done <<< "$raw"
  printf '%s' "$out" | sed '/^$/d'
}

# The resolver is exempt AT FILE LEVEL: leadv2-router.sh (think_model) and
# lib/leadv2-think-model.sh are the ONE place an opus fallback may live.
census_raw="$(grep -rnE "$census_re" \
    "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/workflows" "$PLUGIN_ROOT/skills" "$PLUGIN_ROOT/hooks" 2>/dev/null \
  | grep -v "$PLUGIN_ROOT/scripts/tests/" \
  | grep -v "${PLUGIN_ROOT}/scripts/leadv2-router.sh" \
  | grep -v "${PLUGIN_ROOT}/scripts/lib/leadv2-think-model.sh" \
  | grep -vE ":[0-9]+: *(#|//|emit |log |log_warn |printf )" \
  || true)"
census="$(_lv2_filter_census "$census_raw")"
# Second census pass: spawn lines naming a think role that also mention opus
# on the same line — catches pins written as `model=<opus ...>` or role-first
# syntax the first pattern misses.
census2_raw="$(grep -rnE "(subagent_type|agentType)[\"'= :]+[^,)]*(architect|critic|judge)" \
    "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/workflows" "$PLUGIN_ROOT/skills" "$PLUGIN_ROOT/hooks" 2>/dev/null \
  | grep -v "$PLUGIN_ROOT/scripts/tests/" \
  | grep -iE "opus" \
  || true)"
census2="$(_lv2_filter_census "$census2_raw")"
if [[ -z "$census" && -z "$census2" ]]; then
  pass "tree-wide census: zero live think-role 'opus' spawn pins"
else
  [[ -n "$census"  ]] && fail "tree-wide census: unclassified 'opus' literal(s): $census"
  [[ -n "$census2" ]] && fail "tree-wide census: think-role spawn line pinning opus: $census2"
fi

# --- 2c. mutation negative controls (round-3 review bypass shapes) ---------
# Bypass A: full model id instead of bare 'opus' — reviewer proved
# `model: 'claude-opus-5'` at a think-role site slipped past the round-2
# census_re, which only matched the bare word.
mut_line="{ label: 'x', agentType: 'critic', model: 'claude-opus-5' }"
if printf '%s' "$mut_line" | grep -qE "$census_re"; then
  pass "mutation A (full model id pin) matches census_re"
else
  fail "mutation A (full model id pin) NOT matched by census_re — bypass reopened"
fi
# Bypass B: any pin line containing the word "fallback" — reviewer proved
# the round-2 filter exempted by keyword alone, with no resolver guard.
mut_file="$TMP/mut-fallback-no-guard.js"
printf "%s\n" \
  "// no THINK_MODEL guard anywhere near this line" \
  "  { label: 'sneaky-fallback', agentType: 'architect', model: 'opus', schema: X })" \
  > "$mut_file"
if _lv2_classify_survivor "$mut_file" 2 "  { label: 'sneaky-fallback', agentType: 'architect', model: 'opus', schema: X })"; then
  fail "mutation B (unguarded 'fallback'-labeled opus pin) wrongly exempted — bypass reopened"
else
  pass "mutation B (unguarded 'fallback'-labeled opus pin) correctly rejected"
fi
# Positive control: the same pin IS exempt when a real resolver guard precedes it.
mut_guard_file="$TMP/mut-fallback-guard.js"
printf "%s\n" \
  "if (judged === null && THINK_MODEL !== 'opus') {" \
  "  { label: 'judge-opus-fallback', agentType: 'critic', model: 'opus', schema: X }" \
  > "$mut_guard_file"
if _lv2_classify_survivor "$mut_guard_file" 2 "  { label: 'judge-opus-fallback', agentType: 'critic', model: 'opus', schema: X }"; then
  pass "resolver-gated fallback (guard present) correctly exempted"
else
  fail "resolver-gated fallback (guard present) wrongly rejected"
fi

# --- 2d. round-4 HIGH-1..5 fixtures: value-class pin shapes -----------------
# Each shape from the round-3 verdict MUST match census_re (an uppercase shell
# var, a ${X:-opus} default, a generic assignment, a JSON key or an arm array
# cannot evade the census), and the resolver-routed replacement MUST NOT trip it.
fx_pass=0; fx_fail=0
fx_red() { # $1 label, $2 line — a pin: census_re MUST match
  if printf '%s' "$2" | grep -qE "$census_re"; then
    fx_pass=$((fx_pass + 1))
  else
    fx_fail=$((fx_fail + 1)); log "FAIL: fixture (red) '$1' NOT matched by census_re: $2"
  fi
}
fx_green() { # $1 label, $2 line — resolver-routed shape: MUST NOT match
  if printf '%s' "$2" | grep -qE "$census_re"; then
    fx_fail=$((fx_fail + 1)); log "FAIL: fixture (green) '$1' wrongly matched: $2"
  else
    fx_pass=$((fx_pass + 1))
  fi
}
fx_red   "HIGH-2 driver: model token + ':-' default"   '  model="${LEADV2_ASK_ARCHITECT_MODEL:-opus}"'
fx_red   "HIGH-3 driver: uppercase shell-var pin"      'CLAUDE_HEAVY_MODEL="opus"'
fx_red   "HIGH-4 driver: generic var assignment"       '      default_architect="opus"'
fx_red   "HIGH-4 driver: arm array without fable"      "$(printf "  local two_arms='[\"sonnet\",\"opus\"]'")"
fx_red   "HIGH-5 driver: JSON model-key pin"           ' "LEADV2_MAIN_MODEL":"opus",'
fx_red   "full-id uppercase pin"                       'CLAUDE_HEAVY_MODEL="claude-opus-5"'
fx_green "resolver-routed ask default"                 '  model="${LEADV2_ASK_ARCHITECT_MODEL:-$(bash "${SCRIPT_DIR}/lib/leadv2-think-model.sh")}"'
fx_green "resolver-routed heavy tier"                  'CLAUDE_HEAVY_MODEL="$(bash "${SCRIPT_DIR}/lib/leadv2-think-model.sh")"'
fx_green "arm array incl fable"                        "$(printf "  local two_arms='[\"sonnet\",\"fable\"]'")"
fx_green "installer writes resolver answer"            ' "LEADV2_MAIN_MODEL": os.environ.get("LV2_THINK_MODEL", "fable"),'
PASS=$((PASS + fx_pass)); FAIL=$((FAIL + fx_fail))
log "fixtures 2d: red-shapes+controls matched=$fx_pass missed=$fx_fail"

# --- 4b. session-route Heavy tier: config YAML cannot pin a think tier ------
# R4 discovery: config/session-routing.yaml carried 'heavy: model: opus',
# which overrode the script default and kept the Heavy tier on opus even after
# the default was resolver-routed (the census scans scripts/, not config/).
# The Heavy tier is now forced through the resolver AFTER config/env
# application; this probe proves a stub config pin cannot win.
STUB_ROOT="$TMP/stub-repo"
mkdir -p "$STUB_ROOT/.claude/leadv2-overrides"
printf 'claude:\n  models:\n    heavy:\n      model: opus\n      effort: high\n' \
  > "$STUB_ROOT/.claude/leadv2-overrides/session-routing.yaml"
sr_out="$(LEADV2_PROJECT_ROOT="$STUB_ROOT" bash "$SCRIPTS_ROOT/leadv2-session-route.sh" --class Heavy 2>/dev/null || true)"
sr_model="$(printf '%s\n' "$sr_out" | grep '^model=' | head -1 | cut -d= -f2)"
if [[ "$sr_model" == "fable" ]]; then
  pass "session-route Heavy: stub config 'heavy: opus' cannot pin — resolver wins (model=fable)"
else
  fail "session-route Heavy: expected model=fable despite stub config pin, got: ${sr_model:-<none>}"
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

# --- 2c2. architect escape-mission template: extracted command must parse --
# The template's fenced bash block is documentation, not executed code, but a
# broken continuation or a bare (non-PATH) script name means the escape path
# silently fails to run when a lane copies it verbatim (round-2 review C1).
escape_md="$PLUGIN_ROOT/skills/leadv2-review/ref/architect-escape-mission.md"
if [[ -f "$escape_md" ]]; then
  escape_cmd="$(awk '/^```bash$/{f=1;next} /^```$/{f=0} f' "$escape_md")"
  echo "$escape_cmd" > "$TMP/escape-cmd.sh"
  if bash -n "$TMP/escape-cmd.sh" 2>/dev/null; then
    pass "architect-escape-mission.md: extracted bash block parses (bash -n)"
  else
    fail "architect-escape-mission.md: extracted bash block fails bash -n"
  fi
  router_path="$(printf '%s' "$escape_cmd" | grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/scripts/[a-zA-Z0-9_.-]+\.sh' | head -1 | sed 's#\${CLAUDE_PLUGIN_ROOT}#'"$PLUGIN_ROOT"'#')"
  if [[ -n "$router_path" && -f "$router_path" ]]; then
    pass "architect-escape-mission.md: referenced router script exists ($router_path)"
  else
    fail "architect-escape-mission.md: referenced router script missing or unresolved (got '${router_path:-<none>}')"
  fi
else
  fail "architect-escape-mission.md not found at expected path"
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
