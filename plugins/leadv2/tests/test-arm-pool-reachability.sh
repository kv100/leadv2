#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01);
# EXTRA_SUITE_MAP rows for the same stems live in tests/run-all.sh at the repo root.
# run-all-triggers: leadv2-dispatch-code leadv2-route-arbiter leadv2-routing.yaml leadv2-glm-policy-resolve.py
#
# POOL-IS-COMPUTED-AFTER-THE-ARM-IS-CHOSEN-01 -- the pool must be computed
# BEFORE the arm is chosen, never reconstructed from the ordered ladder
# suffix of an already-resolved arm.
#
# Bug reproduced live (2026-09-07): a dispatch pinned to fable
# (--kind plan --task-class heavy --requested-arm fable) came back
#   route_resolved by=arbiter role=worker arm=refuse
#   reason=requested_arm_incapable ... arm_excluded=fable:not_allowed
# The pin never had a chance: _build_candidate_chain walked dispatch_ladder
# from the RESOLVED arm's position (suffix only), haiku/opus/fable were
# dropped by `dispatch: false` / the DISPATCHABLE filter, the suffix became
# the arbiter's allowed_arms, and everything outside was marked not_allowed
# BEFORE the requested_arm filter ran. Fable was not incapable -- it was
# never in the room.
#
# Contract under test (mission):
#   - a pin to an arm the legacy ladder branch didn't contain either RUNS on
#     that arm or REFUSES naming the exact typed stage (not_in_pool,
#     not_launchable, untrusted, capped, failure_memory) -- never
#     requested_arm_incapable for a capable arm;
#   - --arm-pool a,b,c is a hard candidate set: unknown names / empty /
#     pin+pool conflict are errors BEFORE anything launches; the winner runs
#     inside the set;
#   - --pin-arm is an alias of --requested-arm;
#   - the launchability seam is one named function: with a registry present
#     (sibling lane ARMS-CANNOT-LAUNCH-THEMSELVES-01) a pin to a
#     registry-launchable arm RUNS; with the stub (today) it refuses
#     honestly as not_launchable.
#
# Controls (mission, each mutation INSIDE a throwaway copy of the production
# script, each must turn this suite red):
#   M1: restore _build_candidate_chain as the allowed_arms/pool source
#       (the exact live bug) -> the pin-fable case must flip.
#   M3: allow silent substitution when the pinned arm is capped (strip the
#       exit) -> the pin-capped case must flip.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
DISPATCH_BIN="${PLUGIN_ROOT}/scripts/leadv2-dispatch-code.sh"
ROUTING="${PLUGIN_ROOT}/config/leadv2-routing.yaml"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/arm-pool-reach.XXXXXX")"
trap '[[ "${POOLREACH_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"' EXIT

bash -n "$DISPATCH_BIN" || { fail "bash syntax: dispatch"; printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"; exit 1; }
pass "bash syntax: dispatch"

# fable MUST still be absent from the stub seam's DISPATCHABLE_BUILD_ARMS --
# the whole "honest refusal today, runs when the registry lands" story rests
# on the stub telling the truth about what _spawn_worker_body can launch.
STUB_ARMS="$(python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("_pr", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(" ".join(sorted(m.DISPATCHABLE_BUILD_ARMS)))' \
  "${PLUGIN_ROOT}/scripts/lib/leadv2-glm-policy-resolve.py" 2>/dev/null || true)"
if [[ -n "${STUB_ARMS}" && " ${STUB_ARMS} " == *" fable "* ]]; then
  fail "(fixture) fable joined DISPATCHABLE_BUILD_ARMS (${STUB_ARMS})" \
    "the stub seam now claims to launch fable; re-anchor this suite on an arm the stub still cannot launch (see the seam note in leadv2-glm-policy-resolve.py)"
else
  pass "(fixture) fable is still outside the stub seam (DISPATCHABLE_BUILD_ARMS)"
fi

HEALTHY='{"glm":{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":20}]},"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","five_hour_pct":20,"seven_day_pct":20}]}}'
CLAUDE_CAPPED='{"glm":{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":20}]},"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","five_hour_pct":99,"seven_day_pct":99}]}}'

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$ROUTE_TEST_QUOTA"\n' > "$TMP/live.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/free.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' > "$TMP/worker.sh"
printf '#!/usr/bin/env bash\nprintf %%s "{\\"complexity\\":\\"complex\\",\\"estimate_source\\":\\"judge\\"}"\n' > "$TMP/task-judge.sh"
chmod +x "$TMP/live.sh" "$TMP/free.sh" "$TMP/worker.sh" "$TMP/task-judge.sh"

setup_repo() { # <dir>
  local repo="$1"
  mkdir -p "$repo/.claude/ref" "$repo/docs/leadv2" "$repo/docs/leadv2/tasks"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@e.com; git -C "$repo" config user.name t
  : > "$repo/seed"; git -C "$repo" add seed; git -C "$repo" commit -qm seed
  cp "$ROUTING" "$repo/.claude/ref/leadv2-routing.yaml"
}

# run <dispatch_bin> <repo> <suffix> <quota_json> [extra args...] -> stdout,
# with rc preserved in REACH_RC (never pipe this: exit codes are the M3 signal).
run_dispatch() {
  local bin="$1" repo="$2" suffix="$3" quota="$4"; shift 4
  (cd "$repo" && LEADV2_STATE_ROOT="$TMP/state-root-$suffix" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-dispatch-$suffix" \
    ROUTE_TEST_QUOTA="$quota" \
    CLAUDE_PROJECT_ROOT="$repo" LEADV2_PROJECT_ROOT="$repo" \
    LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-$suffix" \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_REQUIRE_PHASES=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
    LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_TASK_JUDGE_BIN="$TMP/task-judge.sh" \
    LEADV2_DISPATCH_SUBSESSION_BIN="$TMP/worker.sh" \
    bash "$bin" "pool-reachability probe $suffix" \
      --kind plan --task-class heavy --no-spawn --writes src/x.py "$@" 2>&1)
}

expect_rc() { # <label> <actual> <want>
  [[ "$2" == "$3" ]] && { pass "$1 (rc=$2)"; return 0; }
  fail "$1" "rc=$2 want=$3"
  return 1
}

# ── GREEN 1: the live bug's exact dispatch -- pin fable, plan/heavy ───────
REPO_G1="$TMP/repo-g1"; setup_repo "$REPO_G1"
out="$(run_dispatch "$DISPATCH_BIN" "$REPO_G1" g1 "$HEALTHY" --requested-arm fable)"
REACH_RC=$?
printf '%s\n' "$out" > "$TMP/g1.log"
if printf '%s\n' "$out" | grep -q 'reason=requested_arm_not_launchable requested_arm=fable'; then
  pass "(g1) pin fable plan/heavy refuses naming the stage: requested_arm_not_launchable"
else
  fail "(g1) pin fable plan/heavy did not refuse with requested_arm_not_launchable" "log: $TMP/g1.log"
fi
if printf '%s\n' "$out" | grep -q 'arm_excluded=[^ ]*fable:not_launchable'; then
  pass "(g1) the refusal line carries the typed token fable:not_launchable"
else
  fail "(g1) refusal line lacks fable:not_launchable" "log: $TMP/g1.log"
fi
if printf '%s\n' "$out" | grep -q 'requested_arm_incapable'; then
  fail "(g1) requested_arm_incapable still appears for a capable arm -- the live bug is back" "log: $TMP/g1.log"
else
  pass "(g1) requested_arm_incapable is gone for a capable (matrix-covered) arm"
fi
if printf '%s\n' "$out" | grep -q 'launchable_seam .*source=stub_dispatchable'; then
  pass "(g1) the launchability seam names its source (stub_dispatchable)"
else
  fail "(g1) no launchable_seam source=stub_dispatchable line" "log: $TMP/g1.log"
fi
expect_rc "(g1) stage refusal exits 4 (never silently substitutes)" "$REACH_RC" "4"

# ── GREEN 2: --pin-arm is an alias of --requested-arm ──────────────────────
REPO_G2="$TMP/repo-g2"; setup_repo "$REPO_G2"
out="$(run_dispatch "$DISPATCH_BIN" "$REPO_G2" g2 "$HEALTHY" --pin-arm fable)"
REACH_RC=$?
printf '%s\n' "$out" > "$TMP/g2.log"
if printf '%s\n' "$out" | grep -q 'reason=requested_arm_not_launchable requested_arm=fable' \
  && printf '%s\n' "$out" | grep -q 'pin=fable'; then
  pass "(g2) --pin-arm behaves exactly like --requested-arm (refusal + persisted pin)"
else
  fail "(g2) --pin-arm alias diverged" "log: $TMP/g2.log"
fi

# ── GREEN 3: pinned arm capped -> refuse, never silent substitution ───────
REPO_G3="$TMP/repo-g3"; setup_repo "$REPO_G3"
out="$(run_dispatch "$DISPATCH_BIN" "$REPO_G3" g3 "$CLAUDE_CAPPED" --pin-arm sonnet)"
REACH_RC=$?
printf '%s\n' "$out" > "$TMP/g3.log"
if printf '%s\n' "$out" | grep -q 'reason=requested_arm_capped requested_arm=sonnet'; then
  pass "(g3) pin sonnet with claude at 99% refuses: requested_arm_capped"
else
  fail "(g3) pin sonnet capped did not refuse with requested_arm_capped" "log: $TMP/g3.log"
fi
if printf '%s\n' "$out" | grep -q 'arm_excluded=[^ ]*sonnet:capped'; then
  pass "(g3) the capped stage is typed on the line (sonnet:capped)"
else
  fail "(g3) sonnet:capped token missing" "log: $TMP/g3.log"
fi
expect_rc "(g3) capped pin exits 4" "$REACH_RC" "4"

# ── GREEN 4: explicit --arm-pool is a hard set (winner inside it) ──────────
REPO_G4="$TMP/repo-g4"; setup_repo "$REPO_G4"
out="$(run_dispatch "$DISPATCH_BIN" "$REPO_G4" g4 "$HEALTHY" --arm-pool glm,codex)"
REACH_RC=$?
printf '%s\n' "$out" > "$TMP/g4.log"
_pick="$(printf '%s\n' "$out" | grep -oE 'arbiter_pick=[a-z-]+' | head -1 | cut -d= -f2)"
if [[ "${_pick}" == "glm" || "${_pick}" == "codex" ]]; then
  pass "(g4) explicit pool glm,codex: winner (${_pick}) runs inside the set"
else
  fail "(g4) explicit pool glm,codex picked '${_pick:-nothing}'" "log: $TMP/g4.log"
fi
if printf '%s\n' "$out" | grep -q 'arm_excluded=[^ ]*sonnet:not_in_pool'; then
  pass "(g4) arms outside the hard set are typed not_in_pool (sonnet)"
else
  fail "(g4) sonnet:not_in_pool missing -- pool is not bounding" "log: $TMP/g4.log"
fi
expect_rc "(g4) explicit pool resolves, rc=0" "$REACH_RC" "0"

# ── GREEN 5/6: validation fires BEFORE anything launches ──────────────────
REPO_G5="$TMP/repo-g5"; setup_repo "$REPO_G5"
out="$(run_dispatch "$DISPATCH_BIN" "$REPO_G5" g5 "$HEALTHY" --arm-pool fable,no-such-arm)"
REACH_RC=$?
printf '%s\n' "$out" > "$TMP/g5.log"
if printf '%s\n' "$out" | grep -q 'dispatch_refused reason=arm_pool_unknown_arm.*bad=no-such-arm' \
  && ! printf '%s\n' "$out" | grep -q 'launchable_seam'; then
  pass "(g5) unknown pool member refused at the door, before any resolution"
else
  fail "(g5) unknown pool member not refused pre-launch" "log: $TMP/g5.log"
fi
REPO_G6="$TMP/repo-g6"; setup_repo "$REPO_G6"
out="$(run_dispatch "$DISPATCH_BIN" "$REPO_G6" g6 "$HEALTHY" --pin-arm fable --arm-pool fable,opus)"
REACH_RC=$?
printf '%s\n' "$out" > "$TMP/g6.log"
printf '%s\n' "$out" | grep -q 'dispatch_refused reason=pin_and_pool_conflict' \
  && pass "(g6) pin+pool conflict refused (a pin IS a singleton pool)" \
  || fail "(g6) pin_and_pool_conflict missing" "log: $TMP/g6.log"

# ── GREEN 7: the registry-landed shape -- a pin to a launchable arm RUNS ──
# Contract of the seam (_arm_launchable_arms): when
# scripts/lib/leadv2-launch-registry.sh exists and exports
# leadv2_launchable_arms <kind> <role>, the seam uses IT (source=registry)
# and the same pin that refuses not_launchable today must RUN. This is the
# single named seam the sibling lane (ARMS-CANNOT-LAUNCH-THEMSELVES-01)
# lands into -- do not fork a second registry.
REG_PLUGIN="$TMP/registry-plugin"
mkdir -p "$REG_PLUGIN"
cp -R "${PLUGIN_ROOT}/scripts" "$REG_PLUGIN/scripts"
cp -R "${PLUGIN_ROOT}/config" "$REG_PLUGIN/config"
cat > "$REG_PLUGIN/scripts/lib/leadv2-launch-registry.sh" <<'EOF'
# fixture registry (test double for ARMS-CANNOT-LAUNCH-THEMSELVES-01)
leadv2_launchable_arms() {
  printf '%s' "glm,glm-flash,freepool,codex,sonnet,haiku,opus,fable"
}
EOF
REPO_G7="$TMP/repo-g7"; setup_repo "$REPO_G7"
out="$(run_dispatch "$REG_PLUGIN/scripts/leadv2-dispatch-code.sh" "$REPO_G7" g7 "$HEALTHY" --requested-arm fable)"
REACH_RC=$?
printf '%s\n' "$out" > "$TMP/g7.log"
if printf '%s\n' "$out" | grep -q 'launchable_seam .*source=registry'; then
  pass "(g7) seam flips to source=registry when the registry is present"
else
  fail "(g7) seam did not report source=registry" "log: $TMP/g7.log"
fi
if printf '%s\n' "$out" | grep -q 'route_resolved by=arbiter role=worker arm=fable.*reason=explicit_requested_capable'; then
  pass "(g7) the SAME pin now RUNS on fable (explicit_requested_capable)"
else
  fail "(g7) registry-launchable pin did not run on fable" "log: $TMP/g7.log"
fi
expect_rc "(g7) registry-launchable pin resolves rc=0" "$REACH_RC" "0"

# ── RED M1: restore _build_candidate_chain as the pool source ─────────────
# The exact live bug: the candidate_arms array (the ladder SUFFIX from the
# already-resolved arm) becomes the HARD pool again, so a pin to an arm the
# suffix doesn't contain is not_in_pool instead of reaching the matrix.
copy_plugin_tree() { # <dest>
  local dest="$1"
  mkdir -p "$dest"
  cp -R "${PLUGIN_ROOT}/scripts" "$dest/scripts"
  cp -R "${PLUGIN_ROOT}/config" "$dest/config"
}
MUT1="$TMP/mut1-plugin"; copy_plugin_tree "$MUT1"
python3 - "$MUT1/scripts/leadv2-dispatch-code.sh" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
anchor = '''    if [[ -n "${requested_arm}" ]]; then
      _arb_allowed_csv=""
    elif [[ "${_arb_pool_flag}" == "1" ]]; then
      _arb_allowed_csv="${arm_pool_cli}"
    else
      _arb_allowed_csv="$(_ladder_policy_arms "${sig8}" "${task_class:-standard}")"
    fi'''
mut = '''    _arb_allowed_csv="$(IFS=,; printf '%s' "${candidate_arms[*]}")"
    if [[ "${_arb_pool_flag}" != "1" ]]; then
      arm_pool_cli="${_arb_allowed_csv}"
      _arb_pool_flag=1
    fi'''
n = src.count(anchor)
if n != 1:
    sys.exit('M1 anchor %r found %d times (expected 1) -- re-anchor the control, '
             'do not silence it' % (anchor[:60], n))
open(path, 'w').write(src.replace(anchor, mut))
PY
if [[ $? -ne 0 ]]; then
  fail "(m1) mutation anchor missing -- control not falsifiable" "zero-match"
else
  bash -n "$MUT1/scripts/leadv2-dispatch-code.sh" || fail "(m1) mutated copy fails bash -n"
  REPO_M1="$TMP/repo-m1"; setup_repo "$REPO_M1"
  out="$(run_dispatch "$MUT1/scripts/leadv2-dispatch-code.sh" "$REPO_M1" m1 "$HEALTHY" --requested-arm fable)"
  printf '%s\n' "$out" > "$TMP/m1.log"
  if printf '%s\n' "$out" | grep -q 'reason=requested_arm_not_in_pool requested_arm=fable'; then
    pass "(m1) chain-as-pool regression reproduces: pin dies as not_in_pool, suite is red under it"
  else
    fail "(m1) chain-as-pool mutation did not flip the outcome" "log: $TMP/m1.log"
  fi
fi

# ── RED M3: allow silent substitution when the pinned arm is capped ────────
# Strip the exit from the pin-refusal branch: the refusal line is still
# emitted, but the dispatch CONTINUES on another arm and exits 0 -- the
# false-green "request for X quietly answered by Y" shape.
MUT3="$TMP/mut3-plugin"; copy_plugin_tree "$MUT3"
python3 - "$MUT3/scripts/leadv2-dispatch-code.sh" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
anchor = '''      _dl_note "${sig8}" refused "${_arb_reason}" "${_arb_util}" "${founder_task_id}"
      exit 4'''
mut = '''      _dl_note "${sig8}" refused "${_arb_reason}" "${_arb_util}" "${founder_task_id}"
      : # mutated: continue past a refused pin (silent substitution)'''
n = src.count(anchor)
if n != 1:
    sys.exit('M3 anchor %r found %d times (expected 1) -- re-anchor the control, '
             'do not silence it' % (anchor[:60], n))
open(path, 'w').write(src.replace(anchor, mut))
PY
if [[ $? -ne 0 ]]; then
  fail "(m3) mutation anchor missing -- control not falsifiable" "zero-match"
else
  bash -n "$MUT3/scripts/leadv2-dispatch-code.sh" || fail "(m3) mutated copy fails bash -n"
  REPO_M3="$TMP/repo-m3"; setup_repo "$REPO_M3"
  out="$(run_dispatch "$MUT3/scripts/leadv2-dispatch-code.sh" "$REPO_M3" m3 "$CLAUDE_CAPPED" --pin-arm sonnet)"
  REACH_RC=$?
  printf '%s\n' "$out" > "$TMP/m3.log"
  if [[ "$REACH_RC" != "4" ]]; then
    pass "(m3) stripped exit lets the capped pin continue (rc=${REACH_RC}), suite is red under it"
  else
    fail "(m3) mutation did not flip the exit code" "log: $TMP/m3.log"
  fi
fi

echo "---"
printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
