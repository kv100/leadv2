#!/usr/bin/env bash
# run-all-triggers: leadv2-claude-profile-select.sh leadv2-claude-profile-pick.py leadv2-dispatch-code.sh claude-subsession.sh
# tests/test-balancer-every-arm.sh — W1-BALANCER-COVERS-EVERY-ARM-01
#
# §1.1 (founder 2026-09-09: «балансировщик обязан заработать до того, как мы
# возьмём сотни новых задач»): for EVERY Claude arm (sonnet|haiku|opus|fable)
# prove profile selection RAN and left a line naming the picked profile — in
# the launcher's own journal (claude-profile.log, the selector's
# LEADV2_CLAUDE_PROFILE_JOURNAL target) and, on the dispatched path, in the
# dispatch decision journal (claude_profile arm=<arm> selected=<label>).
# §1.3: the dispatching session's OWN profile is DEMOTED to last in the
# ranking, never excluded — with two live accounts the OTHER must win; a
# demoted live account still beats a confirmed-cooling sibling, and with no
# alternative the demoted one still runs (work never stalls).
#
# Hermetic: probe stubbed via LEADV2_CLAUDE_PROFILE_PROBE, registry under
# mktemp, `claude` itself faked on PATH (sleep — alive long enough for the
# spawn's kill -0 liveness check), dispatch runs in a scratch git repo with a
# fixture tenant routing yaml (dispatch_ladder), a fixture capability matrix
# (LEADV2_ROUTE_ARBITER_ROUTING_YAML admits haiku/opus/fable for kind=code)
# and a fixture policy module (LEADV2_LAUNCH_REGISTRY_GLM_POLICY_MODULE adds
# the same arms to DISPATCHABLE_BUILD_ARMS) — so all four arms travel the REAL
# dispatch CLI into the REAL claude-subsession.sh into the REAL selector.
#
# S7 is the in-suite copy-mutation control (T28 idiom). The REAL-file
# mutation artifacts the acceptance asks for live in
# docs/handoff/w1-balancer-covers-every-arm/mutation-control/ and are produced
# by leadv2-mutation-control.sh running THIS suite against a mutated copy of
# the lane.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SELECT_BIN="${LEADV2_TEST_SELECT_BIN:-${SCRIPTS_ROOT}/leadv2-claude-profile-select.sh}"
PICK_BIN="${SCRIPTS_ROOT}/lib/leadv2-claude-profile-pick.py"
SUBSESSION_SH="${SCRIPTS_ROOT}/claude-subsession.sh"
DISPATCH_SH="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1 -- ${2:-}"; }
check_grep() { # <haystack> <pattern> <label>
  if grep -qE -- "$2" <<<"$1"; then pass "$3"; else fail "$3" "no match for '$2' in: $1"; fi
}
check_nogrep() { # <haystack> <pattern> <label>
  if grep -qE -- "$2" <<<"$1"; then fail "$3" "unexpected match for '$2' in: $1"; else pass "$3"; fi
}

unset LEADV2_CLAUDE_MULTIPROFILE LEADV2_CLAUDE_PROFILES_FILE \
      LEADV2_CLAUDE_PROFILE_PROBE LEADV2_CLAUDE_PROFILE_TIMEOUT \
      LEADV2_QUOTA_CACHE_DIR LEADV2_ANTHROPIC_ACTIVE_SERVICE CLAUDE_CONFIG_DIR \
      LEADV2_CLAUDE_PROFILE_DEMOTE_DIR LEADV2_CLAUDE_PROFILE_DEFAULT_DIR \
      LEADV2_CLAUDE_PROFILE_REQUESTED \
      LEADV2_PROJECT_ROOT LEADV2_LANE_WORK_ROOT LEADV2_TASK_ID \
      LEADV2_PARENT_SESSION_ID LEADV2_DISPATCH_LANE_NAME \
      LEADV2_LAUNCH_REGISTRY_GLM_POLICY_MODULE LEADV2_ROUTE_ARBITER_ROUTING_YAML

tmp="$(mktemp -d "${TMPDIR:-/tmp}/balancer-every-arm.XXXXXX")"
FAKEBIN="$tmp/fakebin"
cleanup() {
  pkill -f 'lv2-bea-fake-claude' 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
FIX="${tmp}/fixtures"; CACHE="${tmp}/cache"; REG="${tmp}/registry.tsv"
mkdir -p "$FIX" "$CACHE" "$tmp/dir-alpha" "$tmp/dir-beta" "$tmp/dir-gamma" "$tmp/dir-default" "$FAKEBIN"

# Fixtures mirror test-claude-profile-select.sh: alpha 20% (the account the
# dispatching session burns — nominally the BEST window), beta 80%.
printf '{"claudeAiOauth":{"subscriptionType":"max","expiresAt":9999999999999}}' > "$tmp/dir-alpha/cred.json"
printf '{"claudeAiOauth":{"subscriptionType":"max","expiresAt":9999999999999}}' > "$tmp/dir-beta/cred.json"
printf '{"claudeAiOauth":{"subscriptionType":"max","expiresAt":9999999999999}}' > "$tmp/dir-gamma/cred.json"
printf '{"claudeAiOauth":{"accessToken":"sk-ant-fixture","subscriptionType":"max","expiresAt":9999999999999}}' > "$tmp/dir-default/.credentials.json"
printf '{"oauthAccount":{"emailAddress":"default@fixture.test"}}' > "$tmp/dir-default/.claude.json"

STUB="${tmp}/stub-probe.py"
cat > "$STUB" <<'PY'
#!/usr/bin/env python3
import json, os, sys
label = os.environ.get("LEADV2_CLAUDE_PROFILE_LABEL", "")
path = os.path.join(os.environ["STUB_FIXDIR"], label + ".json")
if os.path.exists(path):
    print(open(path).read())
else:
    print(json.dumps({"provider": "anthropic", "status": "unknown", "accounts": []}))
PY

acct_json() { # <five_hour_pct> <seven_day_pct> <file>
  printf '{"provider":"anthropic","status":"ok","accounts":[{"entry_suffix":"file","service":"file:stub","status":"ok","five_hour_pct":%s,"seven_day_pct":%s,"active":true,"account_label":"stub"}],"active_account":"stub","fetched_at":"2026-09-09T00:00:00Z"}' "$1" "$2" > "$FIX/$3"
}
acct_json 20 20 alpha.json
acct_json 80 80 beta.json
# gamma: confirmed live failure -> starts a cooldown (T25 fixture shape)
printf '{"provider":"anthropic","status":"ok","accounts":[{"entry_suffix":"file","service":"file:stub","status":"error","error":"http 401","active":true,"account_label":"stub"}],"active_account":"stub","fetched_at":"2026-09-09T00:00:00Z"}' > "$FIX/gamma.json"

# The fake `claude`: stays alive ~6s so every kill -0 liveness check passes.
printf '#!/bin/sh\n# lv2-bea-fake-claude\nexec sleep 6\n' > "$FAKEBIN/claude"
chmod +x "$FAKEBIN/claude"

write_reg() { # alpha + beta (+gamma when $1=3)
  : > "$REG"
  printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
  printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
  [[ "${1:-2}" == "3" ]] && printf 'gamma\t%s\tfile:%s/cred.json\n' "$tmp/dir-gamma" "$tmp/dir-gamma" >> "$REG"
}

base_env() {
  printf '%s\n' "LEADV2_CLAUDE_MULTIPROFILE=1" \
    "LEADV2_CLAUDE_PROFILES_FILE=$REG" \
    "LEADV2_CLAUDE_PROFILE_PROBE=$STUB" \
    "LEADV2_QUOTA_CACHE_DIR=$CACHE" \
    "LEADV2_CLAUDE_PROFILE_DEFAULT_DIR=$tmp/dir-default" \
    "STUB_FIXDIR=$FIX"
}

run_select() { # -> sets OUT / ERR / RC
  OUT="$(env "$@" bash "$SELECT_BIN" 2>"$tmp/select.err")"; RC=$?
  ERR="$(cat "$tmp/select.err")"
}

# ============================================================================
echo "=== S1: session burns the BETTER account -> the OTHER must be picked (§1.3) ==="
write_reg 2
run_select $(base_env) "CLAUDE_CONFIG_DIR=$tmp/dir-alpha"
check_grep "$OUT" '^profile=beta .*score=80 source=live .*demoted=alpha$' 'S1-lead-profile-demoted-not-picked: beta (80%%) wins over the session-owned alpha (20%%) and demoted=alpha names it'
[[ "$RC" -eq 0 ]] && pass "S1: exit 0" || fail "S1 exit" "rc=$RC"

echo "=== S2: demoted live beats a confirmed-cooling sibling (demote is not exclusion) ==="
# No beta here: a tier-0 live 80%% sibling would win on score alone and prove
# nothing about tiers. The race is ONLY alpha (live 20, session-owned=tier 1)
# vs gamma (confirmed live failure in round 1 -> cooling = tier 2 in round 2).
: > "$REG"
printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'gamma\t%s\tfile:%s/cred.json\n' "$tmp/dir-gamma" "$tmp/dir-gamma" >> "$REG"
run_select $(base_env) "CLAUDE_CONFIG_DIR=$tmp/dir-alpha" "LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900"
run_select $(base_env) "CLAUDE_CONFIG_DIR=$tmp/dir-alpha" "LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900" # round 2: gamma now cooling
check_grep "$OUT" '^profile=alpha .*demoted=alpha$' 'S2-demoted-live-beats-cooling: round 2 — the demoted-but-live alpha still wins over cooling gamma (never re-pick a broken slot just to avoid the session window)'
[[ "$RC" -eq 0 ]] && pass "S2: exit 0" || fail "S2 exit" "rc=$RC"

echo "=== S3: demotion inert — session dir matches nothing, and explicit off ==="
write_reg 2
run_select $(base_env) "CLAUDE_CONFIG_DIR=/nonexistent-session-dir"
check_grep "$OUT" '^profile=alpha .*score=20 ' 'S3a-no-match: no registry row is the session dir -> best window wins, line unchanged'
check_nogrep "$OUT" 'demoted=' 'S3a: no demoted= field when no row matched (legacy line shape)'
run_select $(base_env) "CLAUDE_CONFIG_DIR=$tmp/dir-alpha" "LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off"
check_grep "$OUT" '^profile=alpha .*score=20 ' 'S3b-off: LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off disables demotion -> alpha (20%%) wins again'
check_nogrep "$OUT" 'demoted=' 'S3b: no demoted= field when demotion is off'

# ============================================================================
echo "=== S4: pick.py tier ordering (unit) ==="
pick_run() { pick_out="$(printf '%b' "$1" | python3 "$PICK_BIN")"; }
B20="$(printf '{"provider":"anthropic","status":"ok","accounts":[{"status":"ok","five_hour_pct":20,"seven_day_pct":20,"active":true}]}' | base64 | tr -d '\n')"
B80="$(printf '{"provider":"anthropic","status":"ok","accounts":[{"status":"ok","five_hour_pct":80,"seven_day_pct":80,"active":true}]}' | base64 | tr -d '\n')"
pick_run "alpha\t/d/a\tfile:/d/a/c\t$B20\tid/a\t0\t1\nbeta\t/d/b\tfile:/d/b/c\t$B80\tid/b\t0\t0\n"
check_grep "$pick_out" '^profile=beta .*demoted=alpha$' 'S4a-pick-tier: tier-0 live 80%% beats tier-1 demoted live 20%%'
pick_run "alpha\t/d/a\tfile:/d/a/c\t$B20\tid/a\t0\t1\n"
check_grep "$pick_out" '^profile=alpha .*demoted=alpha$' 'S4b-pick-single: a lone demoted candidate is still picked (never excluded)'
pick_run "alpha\t/d/a\tfile:/d/a/c\t$B20\tid/a\t0\t0\nbeta\t/d/b\tfile:/d/b/c\t$B80\tid/b\t0\t0\n"
check_grep "$pick_out" '^profile=alpha .*windows=alpha:worst_of_both=20\|beta:worst_of_both=80$' 'S4c-pick-legacy-byte-identical: 6-column input keeps the pre-§1.3 line byte-identical (no demoted= field)'

# ============================================================================
echo "=== S5: every Claude arm's REAL launcher run selects off the session profile (§1.1) ==="
S5_ROOT="$tmp/s5repo"; mkdir -p "$S5_ROOT"; git -C "$S5_ROOT" init -q 2>/dev/null || true
# Role files the real launcher resolves (claude-subsession.sh: no
# .claude/agents/<role>.md -> exit 1 before selection ever runs). Minimal
# bodies: --model is passed explicitly, frontmatter carries nothing we need.
for r in developer critic architect; do
  mkdir -p "$S5_ROOT/.claude/agents"
  printf 'You are the %s. Execute the mission.\n' "$r" > "$S5_ROOT/.claude/agents/${r}.md"
done
s5_run() { # <arm> <role>
  local arm="$1" role="$2" tid="prof-journal-${arm}"
  printf 'mission for %s\n' "$arm" > "$tmp/m-${arm}.md"
  PROJECT_ROOT="$S5_ROOT" \
    PATH="${FAKEBIN}:$PATH" \
    LEADV2_CLAUDE_RUNS_DIR="$tmp/runs-${arm}" \
    LEADV2_SUBSESSION_SLIM_MCP=0 \
    CLAUDE_CONFIG_DIR="$tmp/dir-alpha" \
    env $(base_env) \
    bash "$SUBSESSION_SH" --role "$role" --model "$arm" --task-id "$tid" --mission-file "$tmp/m-${arm}.md" \
    >"$tmp/s5-${arm}.out" 2>"$tmp/s5-${arm}.err"
  S5_LOG="$(cat "$S5_ROOT/docs/handoff/$tid/claude-profile.log" 2>/dev/null || true)"
}
for pair in sonnet:developer haiku:critic opus:critic fable:architect; do
  arm="${pair%%:*}"; role="${pair#*:}"
  s5_run "$arm" "$role"
  check_grep "$S5_LOG" '\[claude-profile\] selected=beta .* demoted=alpha' "S5-${arm}-selected-off-lead-profile: real claude-subsession --role ${role} --model ${arm} journaled selected=beta (not the session's alpha), demoted=alpha named"
done

# ============================================================================
echo "=== S6: the dispatch decision journal carries the profile per arm (§1.1) ==="
export LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0
# advance-arm defaults an unlabeled ledger row to class Standard, whose
# mandatory plan/gate1 phases would refuse the spawn before any claude_profile
# line — the phase gate's own suites own that behaviour (B2 kill switch).
export LEADV2_REQUIRE_PHASES=0
REPO="$tmp/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q; git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null || true
mkdir -p "$REPO/.claude/ref"
# Role fixtures for the dispatched sonnet spawn (same reason as S5)...
for r in developer critic architect; do
  mkdir -p "$REPO/.claude/agents"
  printf 'You are the %s. Execute the mission.\n' "$r" > "$REPO/.claude/agents/${r}.md"
done
# Tenant routing yaml: a dispatch_ladder the dispatcher respects (v1 path).
printf 'router:\n  dispatch_ladder:\n' > "$REPO/.claude/ref/leadv2-routing.yaml"
for a in glm codex sonnet; do
  printf '    - { id: %s, provider: %s, when: [all] }\n' "$a" "$a" >> "$REPO/.claude/ref/leadv2-routing.yaml"
done
# Fixture capability matrix: admits the whole claude family for kind=code so
# the launch registry resolves haiku/opus/fable argvs (registry-only widening
# for the test; production admission stays the router lines' scope), plus glm
# and codex so S6c's --requested-arm glm is ADMITTED (the pin-drop line fires
# at spawn time — a refusal before spawn exercises nothing).
MATRIX="$tmp/matrix.yaml"
printf 'router_v2:\n  capability_matrix:\n' > "$MATRIX"
printf '    - { arm: sonnet, provider: claude, model: sonnet, tier: standard, cost: 5, kinds: [code], sizes: [standard], review: true }\n' >> "$MATRIX"
for a in haiku opus fable; do
  printf '    - { arm: %s, provider: claude, model: %s, tier: standard, cost: 5, kinds: [code], sizes: [standard], review: true }\n' "$a" "$a" >> "$MATRIX"
done
printf '    - { arm: glm, provider: glm, model: glm-5.3, tier: standard, cost: 1, kinds: [code, docs, review, plan], sizes: [standard, heavy, bulk], review: true }\n' >> "$MATRIX"
printf '    - { arm: codex, provider: codex, model: gpt-5.1-codex, tier: standard, cost: 1, kinds: [code, docs, review, plan], sizes: [standard, heavy] }\n' >> "$MATRIX"
# Fixture policy module: DISPATCHABLE_BUILD_ARMS admits the same arms for the
# launch registry's build-arm gate.
cat > "$tmp/policy-module.py" <<'EOF'
DISPATCHABLE_BUILD_ARMS = {"glm", "glm-flash", "codex", "sonnet", "freepool", "haiku", "opus", "fable"}
DISPATCHABLE_PLAN_ARMS = {"glm", "codex", "sonnet", "fable", "opus", "haiku"}
EOF
# Resolver stub: primary arm = sonnet (proven idiom from
# test-dispatch-arm-vocabulary.sh case1).
cat > "$tmp/resolver-stub.py" <<'EOF'
#!/usr/bin/env python3
print("arm=sonnet")
print("rule=none")
print("reason=stub")
print("tier=")
EOF
chmod +x "$tmp/resolver-stub.py"
# Poison non-claude launchers: any spawn that reaches them must FAIL loudly.
for b in glm kimi codex; do
  printf '#!/bin/sh\necho "poison-%s must not spawn" >&2\nexit 1\n' "$b" > "$tmp/poison-${b}.sh"
  chmod +x "$tmp/poison-${b}.sh"
done

dispatch_env() { # common env for every S6 dispatch invocation
  printf '%s\n' \
    "CLAUDE_PROJECT_ROOT=$REPO" \
    "LEADV2_PROJECT_ROOT=$REPO" \
    "LEADV2_DISPATCH_CACHE_DIR=$tmp/dcache" \
    "LEADV2_DISPATCH_E2E_GATE=0" \
    "LEADV2_DISPATCH_REVIEW_GATE=0" \
    "LEADV2_DISPATCH_ARCHITECT_GATE=0" \
    "LEADV2_ROUTER_V2=0" \
    "LEADV2_EXCLUDED_ARMS=__none__" \
    "LEADV2_LANE_SHAPE=off" \
    "LEADV2_DISPATCH_TERMINAL_LEDGER_FILE=$tmp/ledger.tsv" \
    "LEADV2_STATE_ROOT=$tmp/state" \
    "LEADV2_LAUNCH_REGISTRY_GLM_POLICY_MODULE=$tmp/policy-module.py" \
    "LEADV2_ROUTE_ARBITER_ROUTING_YAML=$MATRIX" \
    "GLM_POLICY_RESOLVER=$tmp/resolver-stub.py" \
    "LEADV2_DISPATCH_GLM_BIN=$tmp/poison-glm.sh" \
    "LEADV2_DISPATCH_KIMI_BIN=$tmp/poison-kimi.sh" \
    "LEADV2_DISPATCH_CODEX_BIN=$tmp/poison-codex.sh" \
    "LEADV2_CLAUDE_RUNS_DIR=$tmp/runs-s6" \
    "LEADV2_SUBSESSION_SLIM_MCP=0" \
    "CLAUDE_CONFIG_DIR=$tmp/dir-alpha" \
    "PATH=${FAKEBIN}:$PATH"
}

# Every S6 invocation runs with cwd=$REPO (canonical tests/ idiom): the
# FOREIGN-PROJECT-ROOT-GUARD otherwise overrides the env root with the cwd git
# toplevel — from this suite's own cwd that is the LANE WORKTREE, which both
# pollutes it with runtime state and slugs the reserve/confirm ledger to a
# different repo than advance-arm's --worktree pin finds (:852 repo_slug reads
# LEDGER_REPO_ROOT <- WORK_ROOT), so the confirmed row is never seen.
dispatch_in_repo() { # <mission> [args...] -> dispatch stdout+stderr
  local mission="$1"; shift
  ( cd "$REPO" && env $(dispatch_env) $(base_env) bash "$DISPATCH_SH" "$mission" "$@" ) 2>&1
}

# S6a: full resolve->spawn on sonnet with the REAL claude-subsession.sh.
S6A_OUT="$(dispatch_in_repo 'balancer-every-arm S6 sonnet end to end' --kind code --writes src/main.py)" || true
S6_SIG8="$(printf '%s\n' "$S6A_OUT" | sed -n 's/.*worker_spawned model=sonnet task=\([a-z0-9]*\).*/\1/p' | head -1)"
if [[ -z "$S6_SIG8" ]]; then
  fail "S6-dispatch-sonnet-profile-journaled" "no worker_spawned line — spawn did not reach sonnet: $S6A_OUT"
else
  check_grep "$S6A_OUT" 'claude_profile arm=sonnet task=[a-z0-9]+ selected=beta .*demoted=alpha' 'S6-dispatch-sonnet-profile-journaled: full dispatch journaled the selected profile (beta) off the session-owned alpha for arm=sonnet'
fi

# S6b: haiku/opus/fable through advance-arm (arm taken verbatim; the v2
# re-arbitration fail-opens to the static pick for non-registry arms).
if [[ -n "$S6_SIG8" ]]; then
  for arm in haiku opus fable; do
    printf 'advance %s on the balancer lane\n' "$arm" > "$tmp/adv-${arm}.md"
    ADV_OUT="$( cd "$REPO" && env $(dispatch_env) $(base_env) \
      bash "$DISPATCH_SH" advance-arm --sig8 "$S6_SIG8" --arm "$arm" \
      --mission-file "$tmp/adv-${arm}.md" --worktree "$REPO" 2>&1 )" || true
    check_grep "$ADV_OUT" "claude_profile arm=${arm} task=${S6_SIG8} selected=beta .*demoted=alpha" "S6-dispatch-${arm}-profile-journaled: advance-arm journaled the selected profile (beta) off the session-owned alpha for arm=${arm}"
  done
else
  for arm in haiku opus fable; do
    fail "S6-dispatch-${arm}-profile-journaled" "skipped: no confirmed reservation (S6a spawn failed)"
  done
fi

# S6c: --requested-profile on a NON-Claude arm is dropped LOUDLY, not silently.
S6C_OUT="$(dispatch_in_repo 'balancer-every-arm S6 pin drop on glm' --kind code --writes src/main2.py \
  --requested-arm glm --requested-profile alpha)" || true
check_grep "$S6C_OUT" 'claude_profile_pin_dropped .* arm=glm .*requested=alpha' 'S6-pin-drop-journaled: a profile pin on a non-Claude arm is journaled as dropped, never silently ignored'

# ============================================================================
echo "=== S7: in-suite mutation control — removing the demote stamp must flip S1 (copy, T28 idiom) ==="
MUT="${SCRIPTS_ROOT}/.mut-balancer-select-$$.sh"
sed -E 's/\[\[ -n "\$DEMOTE_DIR" && "\$dir" == "\$DEMOTE_DIR" \]\] && demote=1/demote=0; [[ 1 -eq 0 ]] \&\& demote=1/' \
  "$SELECT_BIN" > "$MUT"
chmod +x "$MUT"
if diff -q "$SELECT_BIN" "$MUT" >/dev/null 2>&1; then
  fail "S7: mutation applied" "sed did not change the selector — pattern no longer matches the real line"
else
  pass "S7: mutation applied (copy differs from the real selector)"
  write_reg 2
  OUT="$(env $(base_env) "CLAUDE_CONFIG_DIR=$tmp/dir-alpha" bash "$MUT" 2>/dev/null)"
  check_grep "$OUT" '^profile=alpha ' 'S7 (RED under mutation): with the demote stamp neutralized the session-owned alpha (20%%) is picked again — exactly what S1 exists to catch'
fi
rm -f "$MUT"

printf '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
