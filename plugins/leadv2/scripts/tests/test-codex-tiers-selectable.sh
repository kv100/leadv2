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
#      selectable (the astra bug wearing a different name). Since
#      ASTRA-SELECTOR-HAS-NO-NEGATIVE-CONTROL-01, this also covers the
#      astra and sol singleton arm rows (9791190a2fea / d15812fd): astra
#      binds to codex-task.sh's own --tier astra chain head; sol has no
#      launcher --tier keyword (dispatched by explicit --model) so it gets
#      the same models_cache availability check without a chain-head match.
#   P2 resolve -- --requested-arm codex, kind=code, both sizes resolve to
#      gpt-5.6-terra tier=standard: MEASURED 2026-09-14 (not the pre-router_v2.cost
#      assumption this suite originally encoded) -- router_v2.cost prices
#      every codex cell at the SAME per-provider median (codex: null ->
#      matrix_median; that thread is closed, founder ruling, not this
#      suite's job to re-litigate), so ecost() ties across all three codex
#      tiers and the sort's next key, tier name as a bare string, decides:
#      'standard' < 'top' < 'volume' alphabetically. Both sizes therefore
#      land on terra today. NOT sol (a task the matrix should not send to
#      the top tier must not get it); NOT gpt-6-astra (the original bug).
#   P3 resolve -- astra and sol as their OWN selectable arms (not codex
#      tiers), pinned directly: --pin-arm astra -> gpt-6-astra tier=astra;
#      --pin-arm sol -> gpt-5.6-sol tier=top (live-verified 2026-09-14).
#      Unconstrained (no requested arm) Standard-size work must never pick
#      astra — its row is sizes:[heavy]-only, so it cannot even enter the
#      candidate pool for a standard-size task; this is the negative half
#      of "astra became selectable" for ordinary work.
#
# Controls (E2E-KILLRATE-01). Mutations are applied to THROWAWAY copies of
# the routing yaml and injected through the seam both consumers already
# honor — LEADV2_ROUTE_ARBITER_ROUTING_YAML (arbiter lib:77, launch-registry
# load_capability_matrix) plus the fixture repo's .claude/ref copy for the
# router side. Production files are never touched; scripts stay real:
#   C1 collapse: all three codex rows onto ONE model (volume row re-tiered
#      to its registered (gpt-5.6-terra, standard) pair so the mutation is
#      judged AT THE AUCTION, not bounced by the registry's
#      codex_model_tier_not_registered guard) -> the terra resolve must
#      flip OFF gpt-5.6-terra onto the mutated model, proving the green
#      assertion is load-bearing (red lands on the resolved model= value).
#   C2 phantom: volume row bound to a slug models_cache does not list ->
#      P1's availability check must go RED naming that slug.
#   C3 negative control (ASTRA-SELECTOR-HAS-NO-NEGATIVE-CONTROL-01): the
#      astra row's model is mutated to a name registered NOWHERE (not
#      models_cache, not launch-registry's CODEX_MODEL_TIERS) and pinned
#      with --pin-arm astra -> the resolve must be arm=refuse
#      reason=requested_arm_not_launchable, MEASURED live 2026-09-14 --
#      never a silent fallback onto terra or sonnet. A selector that cannot
#      be shown refusing an unserved name is not proven to be choosing a
#      served one either.
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

# ASTRA-SELECTOR-HAS-NO-NEGATIVE-CONTROL-01 part 2: 'astra' joined the
# codex-task.sh --tier vocabulary (top|standard|volume|astra) as a direct,
# no-fallback chain -- captured by the same regex so the matrix/launcher
# binding check covers it exactly like the original three tiers.
launch = {}
for m in re.finditer(r'^[ \t]*(top|standard|volume|astra)\)[ \t]+_chain=\(([^)]*)\)',
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
matrix = (data.get('router_v2') or {}).get('capability_matrix') or []
rows = [c for c in matrix if c.get('arm') == 'codex']
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
missing = sorted(set(('top', 'standard', 'volume')) - set(seen))
if missing:
    errors.append('tiers the launcher can serve but the matrix does not '
                  'offer: %s' % ', '.join(missing))

# ASTRA-SELECTOR-HAS-NO-NEGATIVE-CONTROL-01 part 2: astra and sol are now
# their own selectable ARMS (not codex tiers), each a singleton row in the
# matrix. `astra` has a dedicated codex-task.sh --tier of its own, so its
# binding is checked exactly like a codex tier above. `sol` has no launcher
# --tier keyword (it is dispatched by an explicit --model, never --tier
# sol) -- so there is no chain-head to bind against; it still gets the SAME
# availability check as every other row below, keyed by (arm, tier) so it
# never collides with codex's own 'top' tier of the same model.
avail_checks = {}  # (arm, tier) -> model, fed into the models_cache loop below
for c in rows:
    avail_checks[('codex', c.get('tier'))] = c.get('model')

astra_rows = [c for c in matrix if c.get('arm') == 'astra']
if len(astra_rows) != 1:
    errors.append('expected exactly 1 astra capability_matrix row (a '
                  'singleton selectable arm), found %d' % len(astra_rows))
else:
    a = astra_rows[0]
    at, amodel = a.get('tier'), a.get('model')
    if at != 'astra':
        errors.append("astra arm row must carry tier 'astra' (codex-task.sh's "
                      "--tier astra branch), got %r" % at)
    elif 'astra' not in launch:
        errors.append('astra arm row exists but codex-task.sh has no astra '
                      '_chain -- ASTRA-MUST-BE-SELECTABLE-01 regressed')
    elif amodel != launch['astra']:
        errors.append('astra arm: matrix model %r != launcher astra chain '
                      'head %r (codex-task.sh _chain)' % (amodel, launch['astra']))
    avail_checks[('astra', at)] = amodel

sol_rows = [c for c in matrix if c.get('arm') == 'sol']
if len(sol_rows) != 1:
    errors.append('expected exactly 1 sol capability_matrix row (a '
                  'singleton selectable arm), found %d' % len(sol_rows))
else:
    s = sol_rows[0]
    avail_checks[('sol', s.get('tier'))] = s.get('model')

try:
    cache = json.load(open(cache_path))
    slugs = set(m.get('slug') for m in cache.get('models', [])
                if isinstance(m, dict))
    for (arm, t) in sorted(avail_checks):
        model = avail_checks[(arm, t)]
        if model not in slugs:
            errors.append('arm %r tier %r model %r is NOT listed in %s -- a '
                          'tier the account cannot serve must not be '
                          'selectable (the astra bug wearing a different name)'
                          % (arm, t, model, cache_path))
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
print('MATRIX-OK: %d codex rows + astra + sol, tier->model binding matches '
      'the launcher chains' % len(rows))
PY
}

check_matrix "$ROUTING" "$MODELS_CACHE" \
  && pass "static: matrix tiers bound to launcher chain heads" \
  || fail "static: matrix/launcher/cache inconsistency" "see MATRIX-RED above"

# The core offline runner deliberately gives every parallel suite an empty HOME,
# so its dispatch subprocess cannot read the account cache.  Resolve probes need
# the launcher's availability gate open in that hermetic shape; manufacture only
# the launcher's declared chain heads, not a second hand-maintained tier table.
# The static assertion above remains the sole account-cache audit and prints
# AVAILABILITY_UNVERIFIED when the real source is intentionally unavailable.
DISPATCH_MODELS_CACHE="$TMP/dispatch-models-cache.json"
if ! python3 - "$LAUNCHER_BIN" "$DISPATCH_MODELS_CACHE" <<'PY'
import json, re, sys
launcher, dest = sys.argv[1:]
heads = []
for m in re.finditer(r'^[ \t]*(top|standard|volume)\)[ \t]+_chain=\(([^)]*)\)',
                     open(launcher).read(), re.M):
    head = m.group(2).split()[0]
    if head not in heads:
        heads.append(head)
if set(heads) != set(('gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna')):
    raise SystemExit('FIXTURE PRECONDITION GONE: launcher heads=%r' % heads)
json.dump({'models': [{'slug': s} for s in heads]}, open(dest, 'w'))
PY
then
  fail "dispatch cache fixture generation failed" "cannot extract launcher chain heads"
  exit 1
fi

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
#            <arm: unset->codex (P2 default), ''->no --requested-arm at all, or a name to pin>
run_dispatch() {
  local repo="$1" suffix="$2" tc="$3" routing_env="$4" arm="${5-codex}" extra=() arm_flag=()
  [[ -n "$tc" ]] && extra+=("--task-class" "$tc")
  [[ -n "$arm" ]] && arm_flag=("--requested-arm" "$arm")
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
    CODEX_MODELS_CACHE="$DISPATCH_MODELS_CACHE" \
    LEADV2_TASK_JUDGE_BIN="$TMP/no-task-judge" \
    LEADV2_COMPLEXITY_ESTIMATOR_BIN="$TMP/no-complexity-estimator" \
    CLAUDE_PROJECT_ROOT="$repo" LEADV2_PROJECT_ROOT="$repo" \
    LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-$suffix" \
    LEADV2_DISPATCH_ENFORCE=0 \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_REQUIRE_PHASES=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
    LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
    bash "$DISPATCH_BIN" "codex-tiers-selectable probe ${suffix}" \
      --kind code --no-spawn --no-probe-yet --writes src/x.py \
      ${arm_flag[@]+"${arm_flag[@]}"} ${extra[@]+"${extra[@]}"} 2>&1 || true
  )
}

resolved_line() { # <log> -> the worker route_resolved line, else empty
  grep -E 'route_resolved by=arbiter role=worker arm=codex model=' "$1" | head -1
}
resolved_line_any() { # <log> -> the worker route_resolved line, any arm
  grep -E 'route_resolved by=arbiter role=worker ' "$1" | head -1
}

# ── GREEN: Standard codex task -> terra/standard ────────────────────────────
# MEASURED 2026-09-14 (see file header P2): router_v2.cost prices every codex
# cell at the same per-provider median, so the within-arm tie lands on tier
# name as a bare string -- 'standard' sorts before 'volume'. terra, not luna,
# is today's real winner for a Standard-size codex-arm task.
REPO_STD="$TMP/repo-std"; setup_repo "$REPO_STD" "$ROUTING"
out_std="$(run_dispatch "$REPO_STD" std "" "")"
printf '%s\n' "$out_std" > "$TMP/std.log"
line_std="$(resolved_line "$TMP/std.log")"
if [[ -n "$line_std" ]]; then
  case "$line_std" in
    *"model=gpt-5.6-terra tier=standard"*)
      pass "Standard codex task resolves the real standard tier: ${line_std%% task=*}";;
    *)
      fail "Standard codex task resolved a NON-terra cell" "line: $line_std";;
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

# ── GREEN: astra and sol are their own selectable arms, pinned directly ────
# ASTRA-SELECTOR-HAS-NO-NEGATIVE-CONTROL-01: astra/sol joined the matrix as
# singleton arms (not codex tiers) in 9791190a2fea / d15812fd. Both are
# heavy-only rows, so --task-class Heavy is required to enter their pool.
REPO_ASTRA="$TMP/repo-astra"; setup_repo "$REPO_ASTRA" "$ROUTING"
out_astra="$(run_dispatch "$REPO_ASTRA" astra Heavy "" astra)"
printf '%s\n' "$out_astra" > "$TMP/astra.log"
line_astra="$(resolved_line_any "$TMP/astra.log")"
case "$line_astra" in
  *"arm=astra model=gpt-6-astra tier=astra"*)
    pass "pin-arm astra resolves gpt-6-astra directly: ${line_astra%% task=*}";;
  "")
    fail "no arbiter route_resolved line for the astra pin probe" "log: $TMP/astra.log";;
  *)
    fail "pin-arm astra resolved unexpectedly" "line: $line_astra";;
esac

REPO_SOL="$TMP/repo-sol"; setup_repo "$REPO_SOL" "$ROUTING"
out_sol="$(run_dispatch "$REPO_SOL" sol Heavy "" sol)"
printf '%s\n' "$out_sol" > "$TMP/sol.log"
line_sol="$(resolved_line_any "$TMP/sol.log")"
case "$line_sol" in
  *"arm=sol model=gpt-5.6-sol tier=top"*)
    pass "pin-arm sol resolves gpt-5.6-sol directly: ${line_sol%% task=*}";;
  "")
    fail "no arbiter route_resolved line for the sol pin probe" "log: $TMP/sol.log";;
  *)
    fail "pin-arm sol resolved unexpectedly" "line: $line_sol";;
esac

# ── GREEN: astra never wins unconstrained Standard-size work ───────────────
# The negative half of "astra became selectable": its row is sizes:[heavy]
# only, so an ordinary Standard-size task (no requested arm at all) must
# never resolve to astra -- structurally, not just by cost.
REPO_UNC="$TMP/repo-unc"; setup_repo "$REPO_UNC" "$ROUTING"
out_unc="$(run_dispatch "$REPO_UNC" unc "" "" "")"
printf '%s\n' "$out_unc" > "$TMP/unc.log"
line_unc="$(resolved_line_any "$TMP/unc.log")"
if [[ -n "$line_unc" ]]; then
  case "$line_unc" in
    *"arm=astra"*|*"model=gpt-6-astra"*)
      fail "unconstrained Standard-size work resolved to astra — a heavy-only row must not enter this pool" "line: $line_unc";;
    *)
      pass "unconstrained Standard-size work never resolves to astra: ${line_unc%% task=*}";;
  esac
else
  fail "no arbiter route_resolved line for the unconstrained Standard probe" "log: $TMP/unc.log"
fi

# ── RED C3 (ASTRA-SELECTOR-HAS-NO-NEGATIVE-CONTROL-01): pin an arm whose ──
# model is registered NOWHERE (not models_cache, not the launch registry's
# CODEX_MODEL_TIERS) -> the resolve must be a NAMED refusal, never a silent
# fallback onto terra or sonnet. MEASURED 2026-09-14: this lands on
# arm=refuse reason=requested_arm_not_launchable, from the launch registry's
# own pre-filter (leadv2-launch-registry.py:530 codex_model_tier_not_registered
# folded into the arbiter's launchable-arms set) -- never a value this suite
# invents.
MUT3YAML="$TMP/phantom-astra-routing.yaml"
cp "$ROUTING" "$MUT3YAML"
python3 - "$MUT3YAML" <<'PY' || { fail "(negative-control) fixture mutation failed" "see stderr above"; }
import re, sys
p = sys.argv[1]
src, out, n = open(p).read(), [], 0
for ln in src.splitlines(keepends=True):
    if re.match(r'^[ \t]*-[ ]*\{[ ]*arm:[ ]*astra,', ln):
        ln2, k = re.subn(r'model:[ ]*[^,]+', 'model: gpt-9-unserved-phantom', ln, count=1)
        n += k; ln = ln2
    out.append(ln)
if n != 1:
    sys.exit('FIXTURE PRECONDITION GONE: expected exactly 1 astra row to '
             'rewrite, matched %d -- re-anchor, do not silence' % n)
open(p, 'w').writelines(out)
PY
REPO_C3="$TMP/repo-c3"; setup_repo "$REPO_C3" "$MUT3YAML"
out_c3="$(run_dispatch "$REPO_C3" c3 Heavy "$MUT3YAML" astra)"
printf '%s\n' "$out_c3" > "$TMP/c3.log"
line_c3="$(resolved_line_any "$TMP/c3.log")"
if [[ -n "$line_c3" ]]; then
  case "$line_c3" in
    *"arm=refuse"*"reason=requested_arm_not_launchable"*)
      pass "(negative-control) unserved model name pinned via astra -- selector refuses by name: ${line_c3%% task=*}";;
    *"model=gpt-5.6-terra"*|*"arm=sonnet"*)
      fail "(negative-control) selector silently fell back to terra/sonnet instead of refusing" "line: $line_c3";;
    *)
      fail "(negative-control) resolved without the expected named refusal" "line: $line_c3";;
  esac
else
  fail "(negative-control) no route_resolved line for the unserved-model pin probe" "log: $TMP/c3.log"
fi
if check_matrix "$MUT3YAML" "$MODELS_CACHE" >/dev/null 2>&1; then
  fail "(negative-control) static availability check stayed green on an unserved astra model — control not falsifiable"
else
  pass "(negative-control) static availability check reds naming the unserved astra model"
fi

# ── RED C1: collapse the three tier rows onto one model ────────────────────
# All three codex rows -> gpt-5.6-luna, all re-tiered to `volume` so the
# winning pair is the REGISTERED (luna, volume) and the mutation is judged
# at the arbiter's auction — not bounced by the registry's
# codex_model_tier_not_registered guard. gpt-5.6-luna (never gpt-5.6-terra,
# which the unmutated P2 baseline resolves to today, MEASURED 2026-09-14 —
# see the file header) is the target precisely so a broken mutation that
# left today's real winner untouched cannot pass by accident.
MUT1YAML="$TMP/collapse-routing.yaml"
cp "$ROUTING" "$MUT1YAML"
python3 - "$MUT1YAML" <<'PY' || { fail "(red-collapse) fixture mutation failed" "see stderr above"; }
import re, sys
p = sys.argv[1]
lines, out, n_model, n_tier = open(p).read().splitlines(keepends=True), [], 0, 0
for ln in lines:
    if re.match(r'^[ \t]*-[ ]*\{[ ]*arm:[ ]*codex,', ln):
        ln, k = re.subn(r'model:[ ]*[^,]+', 'model: gpt-5.6-luna', ln, count=1)
        n_model += k
        ln, k2 = re.subn(r'tier:[ ]*(top|standard|volume)', 'tier: volume', ln, count=1)
        n_tier += k2
    out.append(ln)
if n_model != 3 or n_tier != 3:
    sys.exit('FIXTURE PRECONDITION GONE: expected 3 codex model cells + 3 '
             'tier cells to rewrite, matched %d/%d -- re-anchor, do not '
             'silence' % (n_model, n_tier))
open(p, 'w').writelines(out)
PY
REPO_C1="$TMP/repo-c1"; setup_repo "$REPO_C1" "$MUT1YAML"
out_c1="$(run_dispatch "$REPO_C1" c1 "" "$MUT1YAML")"
printf '%s\n' "$out_c1" > "$TMP/c1.log"
line_c1="$(resolved_line "$TMP/c1.log")"
if [[ -n "$line_c1" ]]; then
  case "$line_c1" in
    *"model=gpt-5.6-luna tier=volume"*)
      pass "(red-collapse) collapsed matrix resolves luna — the terra assertion is load-bearing (red on the resolved model=)";;
    *"model=gpt-5.6-terra"*)
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
