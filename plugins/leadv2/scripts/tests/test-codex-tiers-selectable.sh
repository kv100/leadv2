#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01,
# discovered by scan_suite_triggers; the yaml's own filename is a trigger token
# by run-all's stem-or-filename key rule — same as its EXTRA_SUITE_MAP rows):
# run-all-triggers: leadv2-routing.yaml leadv2-route-arbiter codex-task leadv2-dispatch-code
#
# CODEX-TIERS-COLLAPSED-ONTO-ASTRA part B — E2E-KILLRATE-01 controls.
#
# Bug (measured, lane A1): leadv2-routing.yaml named gpt-6-astra in ALL THREE
# codex capability_matrix rows, so the arbiter's tier cells were one model
# under three names — whichever cell won `cheapest_capable`, the resolve was
# astra and part A's launcher chains (codex-task.sh tier table) were
# unreachable from a live dispatch. Part A taught the LAUNCHER the chains and
# A1-CODEX-TIERS-A2 registered the (model, tier) pairs in the launch
# registry's CODEX_MODEL_TIERS; this suite pins the remaining half: the
# ARBITER's matrix must offer exactly the tiers the launcher can serve, each
# bound to its ~/.codex/models_cache.json slug.
#
# Properties under test (the value under test is the RESOLVED model/tier
# token on the decision line, never a decorative log string):
#   P1 static  -- exactly three codex rows; tier->model binding equals the
#      launcher chain HEAD per tier, extracted live from codex-task.sh's
#      `_chain=(...)` table (never hardcoded here, so launcher and matrix
#      cannot drift apart silently); every codex matrix slug exists in
#      models_cache.json — a tier the account cannot serve must not be
#      selectable (the astra bug wearing a different name).
#   P2 resolve -- --requested-arm codex, kind=code:
#        Standard task -> route_resolved ... model=gpt-5.6-luna tier=volume
#          (cheapest capable codex cell; NOT sol: a task the matrix should
#          not send to the top tier must not get it; NOT gpt-6-astra);
#        Heavy task    -> route_resolved ... model=gpt-5.6-terra
#          tier=standard (4 < 7; sol's row is sizes:[heavy]-only and priced
#          above terra, so heavy code rides the balanced tier).
#
# Controls (E2E-KILLRATE-01). Mutations are applied to THROWAWAY copies of
# the routing yaml and injected through the seam both consumers already
# honor — LEADV2_ROUTE_ARBITER_ROUTING_YAML (arbiter lib:77, launch-registry
# load_capability_matrix) plus the fixture repo's .claude/ref copy for the
# router side. Production files are never touched; scripts stay real:
#   C1 collapse: all three codex rows onto ONE model (volume row re-tiered
#      to its registered (gpt-5.6-terra, standard) pair so the mutation is
#      judged AT THE AUCTION, not bounced by the registry's
#      codex_model_tier_not_registered guard) -> the Standard resolve must
#      flip OFF gpt-5.6-luna, proving the green assertion is load-bearing
#      (red lands on the resolved model= value).
#   C2 phantom: volume row bound to a slug models_cache does not list ->
#      P1's availability check must go RED naming that slug.
#
# Hermetic: quota/freepool-gate/arbiter state are test seams; --no-spawn; the
# worker is a stub; state roots live under mktemp. The dispatch script, the
# arbiter, the launch registry and (for P1) the account's
# ~/.codex/models_cache.json are REAL. CODEX_MODELS_CACHE overrides the cache
# path — the same seam codex-task.sh uses.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_BIN="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"
LAUNCHER_BIN="${SCRIPTS_ROOT}/codex-task.sh"
ROUTING="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"
MODELS_CACHE="${CODEX_MODELS_CACHE:-$HOME/.codex/models_cache.json}"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/codex-tiers-selectable.XXXXXX")"
trap '[[ "${CODEXTIERS_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"' EXIT

bash -n "$DISPATCH_BIN" || { fail "bash syntax: dispatch"; exit 1; }
pass "bash syntax: dispatch"
bash -n "$LAUNCHER_BIN" || { fail "bash syntax: launcher"; exit 1; }
pass "bash syntax: launcher"

# ── P1: static matrix-vs-launcher-vs-cache consistency ────────────────────
# <yaml> <cache> <label>; exit 0 = matrix honest. The expected tier->model
# binding is extracted from the LIVE codex-task.sh chain table, so this
# check reds the day launcher and matrix disagree, whichever side moved.
check_matrix() { # <yaml> <cache>
  python3 - "$1" "$2" "$LAUNCHER_BIN" <<'PY'
import sys, re, json
import yaml

yaml_path, cache_path, launcher_path = sys.argv[1], sys.argv[2], sys.argv[3]
errors = []

launch = {}
for m in re.finditer(r'^[ \t]*(top|standard|volume)\)[ \t]+_chain=\(([^)]*)\)',
                     open(launcher_path).read(), re.M):
    launch[m.group(1)] = m.group(2).split()[0]
if not launch:
    print('FIXTURE PRECONDITION GONE: no `_chain=(...)` tier lines found in '
          'codex-task.sh -- re-anchor this control, do not silence it')
    sys.exit(1)

try:
    data = yaml.safe_load(open(yaml_path))
except Exception as e:
    print('MATRIX-RED: cannot parse %s: %s' % (yaml_path, e))
    sys.exit(1)
rows = [c for c in ((data.get('router_v2') or {}).get('capability_matrix') or [])
        if c.get('arm') == 'codex']
if len(rows) != 3:
    errors.append('expected exactly 3 codex capability_matrix rows (one per '
                  'real tier), found %d' % len(rows))
seen = {}
for c in rows:
    t, model = c.get('tier'), c.get('model')
    if t in seen:
        errors.append('duplicate codex tier %r in the matrix' % t)
    seen[t] = model
    if t not in ('top', 'standard', 'volume'):
        errors.append('codex row tier %r not in top|standard|volume -- '
                      'codex-task.sh rejects others (spark banned, founder '
                      '2026-04-28)' % t)
    elif model != launch[t]:
        errors.append('tier %r: matrix model %r != launcher chain head %r '
                      '(codex-task.sh _chain)' % (t, model, launch[t]))
missing = sorted(set(launch) - set(seen))
if missing:
    errors.append('tiers the launcher can serve but the matrix does not '
                  'offer: %s' % ', '.join(missing))

try:
    cache = json.load(open(cache_path))
    slugs = set(m.get('slug') for m in cache.get('models', [])
                if isinstance(m, dict))
    for t in sorted(seen):
        if seen[t] not in slugs:
            errors.append('tier %r model %r is NOT listed in %s -- a tier '
                          'the account cannot serve must not be selectable '
                          '(the astra bug wearing a different name)'
                          % (t, seen[t], cache_path))
    print('AVAILABILITY_VERIFIED: %d slugs in %s' % (len(slugs), cache_path))
except Exception as e:
    # part-A precedent: an unreadable models_cache never fails the run, but
    # it is said out loud, never silently treated as verified.
    print('AVAILABILITY_UNVERIFIED: %s unreadable (%s) -- binding checks '
          'still enforced' % (cache_path, e))

if errors:
    for e in errors:
        print('MATRIX-RED: ' + e)
    sys.exit(1)
print('MATRIX-OK: %d codex rows, tier->model binding matches the launcher '
      'chains' % len(rows))
PY
}

check_matrix "$ROUTING" "$MODELS_CACHE" \
  && pass "static: matrix tiers bound to launcher chain heads" \
  || fail "static: matrix/launcher/cache inconsistency" "see MATRIX-RED above"

# ── resolve probes: real dispatch, hermetic seams ──────────────────────────
quota_json() { # <glm_pct> <codex_pct> <claude_pct> -- codex healthy
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
g, c, a = (int(x) for x in sys.argv[1:])
print(json.dumps({
    'glm': {'status': 'ok', 'five_hour': {'pct': g}, 'weekly': {'pct': g}},
    'codex': {'status': 'ok', 'binding_window': 'primary',
              'windows': [{'kind': 'primary', 'used_percent': c}]},
    'anthropic': {'status': 'ok', 'accounts': [
        {'active': True, 'five_hour_pct': a, 'seven_day_pct': a}]},
}))
PY
}
LOW_QUOTA="$(quota_json 99 20 20)"

cat > "$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat > "$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"

WORKER="$TMP/worker.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' > "$WORKER"
chmod +x "$WORKER"

setup_repo() { # <dir> <routing_yaml>
  local repo="$1" routing="$2"
  mkdir -p "$repo/.claude/ref" "$repo/docs/leadv2" "$repo/docs/leadv2/tasks"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@e.com; git -C "$repo" config user.name t
  : > "$repo/seed"; git -C "$repo" add seed; git -C "$repo" commit -qm seed
  cp "$routing" "$repo/.claude/ref/leadv2-routing.yaml"
}

# <repo_dir> <suffix> <task_class|''->default Standard> <routing_env|''->plugin config>
run_dispatch() {
  local repo="$1" suffix="$2" tc="$3" routing_env="$4" extra=()
  [[ -n "$tc" ]] && extra+=("--task-class" "$tc")
  (
    cd "$repo" || exit 1
    # exported BEFORE the env-prefixed command: a conditional assignment
    # inside the prefix (${routing_env:+X=...}) stops being an assignment
    # word after expansion and kills the whole prefix (bash 3.2 measured).
    if [[ -n "$routing_env" ]]; then
      export LEADV2_ROUTE_ARBITER_ROUTING_YAML="$routing_env"
    fi
    LEADV2_STATE_ROOT="$TMP/state-root-$suffix" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-dispatch-$suffix" \
    ROUTE_TEST_QUOTA="$LOW_QUOTA" \
    CLAUDE_PROJECT_ROOT="$repo" LEADV2_PROJECT_ROOT="$repo" \
    LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-$suffix" \
    LEADV2_DISPATCH_ENFORCE=0 \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_REQUIRE_PHASES=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
    LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
    bash "$DISPATCH_BIN" "codex-tiers-selectable probe ${suffix}" \
      --kind code --no-spawn --writes src/x.py --requested-arm codex \
      ${extra[@]+"${extra[@]}"} 2>&1 || true
  )
}

resolved_line() { # <log> -> the worker route_resolved line, else empty
  grep -E 'route_resolved by=arbiter role=worker arm=codex model=' "$1" | head -1
}

# ── GREEN: Standard codex task -> luna/volume ──────────────────────────────
REPO_STD="$TMP/repo-std"; setup_repo "$REPO_STD" "$ROUTING"
out_std="$(run_dispatch "$REPO_STD" std "" "")"
printf '%s\n' "$out_std" > "$TMP/std.log"
line_std="$(resolved_line "$TMP/std.log")"
if [[ -n "$line_std" ]]; then
  case "$line_std" in
    *"model=gpt-5.6-luna tier=volume"*)
      pass "Standard codex task resolves the real volume tier: ${line_std%% task=*}";;
    *)
      fail "Standard codex task resolved a NON-luna cell" "line: $line_std";;
  esac
  case "$line_std" in
    *"model=gpt-5.6-sol"*) fail "Standard task got sol (top tier) — matrix sent work to a tier it should not" "line: $line_std";;
    *) pass "Standard task does NOT get sol";;
  esac
  case "$line_std" in
    *"model=gpt-6-astra"*) fail "resolve collapsed onto astra — the original bug" "line: $line_std";;
    *) pass "resolve never names gpt-6-astra";;
  esac
else
  fail "no arbiter route_resolved line for the Standard probe" "log: $TMP/std.log"
fi

# ── GREEN: Heavy codex task -> terra/standard, not sol ─────────────────────
REPO_HVY="$TMP/repo-hvy"; setup_repo "$REPO_HVY" "$ROUTING"
out_hvy="$(run_dispatch "$REPO_HVY" hvy Heavy "")"
printf '%s\n' "$out_hvy" > "$TMP/hvy.log"
line_hvy="$(resolved_line "$TMP/hvy.log")"
if [[ -n "$line_hvy" ]]; then
  case "$line_hvy" in
    *"model=gpt-5.6-terra tier=standard"*)
      pass "Heavy codex task resolves the real standard tier: ${line_hvy%% task=*}";;
    *"model=gpt-5.6-sol"*)
      fail "Heavy task got sol — top row must lose the 4-vs-7 auction" "line: $line_hvy";;
    *)
      fail "Heavy codex task resolved neither terra nor sol" "line: $line_hvy";;
  esac
else
  fail "no arbiter route_resolved line for the Heavy probe" "log: $TMP/hvy.log"
fi

# ── RED C1: collapse the three tier rows onto one model ────────────────────
# All three codex rows -> gpt-5.6-terra; the volume row is re-tiered to
# `standard` so the winning pair is the REGISTERED (terra, standard) and the
# mutation is judged at the arbiter's auction — not bounced by the registry's
# codex_model_tier_not_registered guard (a collapse onto (terra, volume) was
# measured to end as arm=refuse requested_arm_not_launchable before any
# model choice happened, which tests the registry, not this matrix).
MUT1YAML="$TMP/collapse-routing.yaml"
cp "$ROUTING" "$MUT1YAML"
python3 - "$MUT1YAML" <<'PY' || { fail "(red-collapse) fixture mutation failed" "see stderr above"; }
import re, sys
p = sys.argv[1]
lines, out, n_model, n_tier = open(p).read().splitlines(keepends=True), [], 0, 0
for ln in lines:
    if re.match(r'^[ \t]*-[ ]*\{[ ]*arm:[ ]*codex,', ln):
        ln, k = re.subn(r'model:[ ]*[^,]+', 'model: gpt-5.6-terra', ln, count=1)
        n_model += k
        if 'tier: volume' in ln:
            ln, k = re.subn(r'tier:[ ]*volume', 'tier: standard', ln, count=1)
            n_tier += k
    out.append(ln)
if n_model != 3 or n_tier != 1:
    sys.exit('FIXTURE PRECONDITION GONE: expected 3 codex model cells + 1 '
             'volume tier cell to rewrite, matched %d/%d -- re-anchor, do '
             'not silence' % (n_model, n_tier))
open(p, 'w').writelines(out)
PY
REPO_C1="$TMP/repo-c1"; setup_repo "$REPO_C1" "$MUT1YAML"
out_c1="$(run_dispatch "$REPO_C1" c1 "" "$MUT1YAML")"
printf '%s\n' "$out_c1" > "$TMP/c1.log"
line_c1="$(resolved_line "$TMP/c1.log")"
if [[ -n "$line_c1" ]]; then
  case "$line_c1" in
    *"model=gpt-5.6-terra"*)
      pass "(red-collapse) collapsed matrix resolves terra — the luna assertion is load-bearing (red on the resolved model=)";;
    *"model=gpt-5.6-luna"*)
      fail "(red-collapse) mutation did not flip the resolved model — control not falsifiable" "line: $line_c1";;
    *)
      fail "(red-collapse) unexpected resolved line under mutation" "line: $line_c1";;
  esac
else
  fail "(red-collapse) no route_resolved line under mutation" "log: $TMP/c1.log"
fi
if check_matrix "$MUT1YAML" "$MODELS_CACHE" >/dev/null 2>&1; then
  fail "(red-collapse) static check stayed green on a collapsed matrix — binding check not falsifiable"
else
  pass "(red-collapse) static binding check reds on the collapsed matrix"
fi

# ── RED C2: a tier bound to a slug models_cache does not list ──────────────
MUT2YAML="$TMP/phantom-routing.yaml"
cp "$ROUTING" "$MUT2YAML"
python3 - "$MUT2YAML" <<'PY' || { fail "(red-phantom) fixture mutation failed" "see stderr above"; }
import re, sys
p = sys.argv[1]
src, out, n = open(p).read(), [], 0
for ln in src.splitlines(keepends=True):
    if re.match(r'^[ \t]*-[ ]*\{[ ]*arm:[ ]*codex,', ln) and 'tier: volume' in ln:
        ln2, k = re.subn(r'model:[ ]*[^,]+', 'model: gpt-5.6-nova', ln, count=1)
        n += k; ln = ln2
    out.append(ln)
if n != 1:
    sys.exit('FIXTURE PRECONDITION GONE: expected exactly 1 volume row to '
             'rewrite, matched %d -- re-anchor, do not silence' % n)
open(p, 'w').writelines(out)
PY
# Fixture cache: the three REAL slugs, never nova — so the only red cause is
# the phantom binding, not a stale fixture.
python3 - "$TMP/fixture-cache.json" <<'PY'
import json, sys
json.dump({'models': [{'slug': s} for s in
                      ('gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna')]},
          open(sys.argv[1], 'w'))
PY
if out2="$(check_matrix "$MUT2YAML" "$TMP/fixture-cache.json" 2>&1)"; then
  fail "(red-phantom) availability check stayed green on an un-servable slug — control not falsifiable"
else
  if printf '%s\n' "$out2" | grep -q "gpt-5.6-nova"; then
    pass "(red-phantom) availability check reds naming the un-servable slug: $(printf '%s\n' "$out2" | grep -o "MATRIX-RED.*nova" | head -1)"
  else
    fail "(red-phantom) red for the wrong reason" "$out2"
  fi
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
