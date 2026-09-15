#!/usr/bin/env bash
# tests/test-plugin-review-arms.sh — PLUGIN-REVIEW-ARMS-01 regression suite.
#
# The plugin's own repo ran a whole dispatch (4c9ddb05) out of a STALE real-copy
# script tree: status: no_reviewer, empty pool, routing_config_degraded, and a
# phase_precondition rc=127 -- all one root cause. These tests pin the four
# fixes so that incident cannot reform silently:
#
#   T1  tenant routing yaml exists, parses, and its protected-path patterns
#       steer review-signals correctly for a bash+markdown repo (plugin paths
#       protected, docs/ NOT).
#   T2  the resolver, against the TENANT yaml specifically, author-excludes:
#       --author glm tags glm:author: and never seats glm; --author opus tags
#       opus:author: and never seats opus (R7 -- claimed, now proven).
#   T3  dispatcher provenance: a dispatch invoked from a non-plugin tree while
#       a plugin tree is discoverable next to the project REFUSES (exit 4,
#       journal dispatch_refused reason=stale_script_tree, remedy on stderr).
#   T4  LEADV2_ALLOW_STALE_SCRIPT_TREE=1 downgrades the refusal to a warn.
#   T5  legitimate run trees pass the check: the plugin tree itself and a
#       worktree-style copy (.claude/worktrees/<id>/plugins/leadv2/scripts) --
#       suffix match only, never an absolute prefix (R3/R4).
#   T6  when no reviewer can be resolved, the ENGINE's review-gate.md carries
#       the full 8-field diagnostic shape (refusal/resolver_rc/resolver_stderr/
#       merge_blocked), not a bare empty pool: line.
#   T7  the engine writer and the lane writer (_pc_write_unreviewed) emit the
#       identical field set -- two writers of review-gate.md must not drift
#       again (R8).
#   T8  phase-record resolves (no rc=127) when dispatch runs from the plugin
#       tree -- pin the ABSENCE of 'reason=unexpected_rc value=127' (R6: the
#       warn itself may stay -- rc=3 with a real missing= list is load-bearing,
#       do not silence it).
#
# Hermetic: scratch git repo + poison provider bins (same fence as
# test-dispatch-arm-vocabulary.sh); no live quota/network read.
# run-all-triggers: leadv2-dispatch-code leadv2-dispatch-product-close leadv2-lane-child-suffixes leadv2-portable-lock
#
# SUITE-SELECTION-COVERS-140-OF-390-01: this suite carried no trigger
# marker and matched no name convention, so `run-all.sh --scope changed`
# never selected it — it could only ever run under `--scope all`. The
# triggers are the production files the suite's own body references most,
# with shared helpers excluded so a helper edit does not select everything.


set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPTS_ROOT}/../../.." && pwd)"
TENANT_YAML="${REPO_ROOT}/.claude/ref/leadv2-routing.yaml"
RESOLVER="${SCRIPTS_ROOT}/lib/leadv2-glm-policy-resolve.py"
SIGNALS_LIB="${SCRIPTS_ROOT}/lib/leadv2-review-signals.sh"
DISPATCH="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"
REVIEW_RUN="${SCRIPTS_ROOT}/leadv2-review-run.sh"
PRODUCT_CLOSE="${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

# Hermeticity: strip parent-session LEADV2_* state (E2E-GATE-RESIDUE-01 pattern).
unset LEADV2_PROJECT_ROOT LEADV2_LANE_WORK_ROOT LEADV2_TASK_ID \
      LEADV2_PARENT_SESSION_ID LEADV2_DISPATCH_LANE_NAME LEADV2_ROUTING_YAML
export LEADV2_ARM_EARLY_VERDICT_S=0

bash -n "$DISPATCH" 2>/dev/null || { echo "ERROR: dispatch-code.sh syntax"; exit 1; }
bash -n "$REVIEW_RUN" 2>/dev/null || { echo "ERROR: review-run.sh syntax"; exit 1; }

ROOT="$(mktemp -d 2>/dev/null || mktemp -d -t leadv2-pra01)"; trap 'rm -rf "$ROOT"' EXIT
REPO="$ROOT/repo"
mkdir -p "$REPO/.claude/ref" "$REPO/docs/leadv2/.bus-offsets" "$REPO/docs/leadv2/tasks"
(cd "$REPO" && git init -q && git config user.email test@example.com && git config user.name test \
  && printf 'seed\n' > seed && git add seed && git commit -qm seed)

# Poison fence: any forgotten provider-bin override dies loudly, offline.
for _arm in glm kimi codex; do
  printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "$ROOT/poison-${_arm}.sh"
  chmod +x "$ROOT/poison-${_arm}.sh"
done
export LEADV2_DISPATCH_GLM_BIN="$ROOT/poison-glm.sh"
export LEADV2_DISPATCH_KIMI_BIN="$ROOT/poison-kimi.sh"
export LEADV2_DISPATCH_CODEX_BIN="$ROOT/poison-codex.sh"
export LEADV2_DISPATCH_CACHE_DIR="$ROOT/cache"
export LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$ROOT/ledger.tsv"
export LEADV2_QUOTA_LOCKOUT_DIR="$ROOT/lockouts"

# Shared hermetic env for every full-dispatch invocation (env(1) form -- a pipeline
# `while read; export` subshell would not propagate to the command that follows).
dispatch_env() {
  env CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
    "$@"
}

# ── T1: tenant yaml exists, parses, patterns steer signals ─────────────────────
if [[ -s "$TENANT_YAML" ]]; then
  pass "T1a: tenant routing yaml present at .claude/ref/leadv2-routing.yaml"
else
  fail "T1a: tenant routing yaml" "missing/empty at ${TENANT_YAML}"
fi
if python3 -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); pats=d['router']['glm_policy']['protected_path_patterns']; sys.exit(0 if pats else 1)" "$TENANT_YAML" 2>/dev/null; then
  pass "T1b: tenant yaml parses under yaml.safe_load with non-empty protected_path_patterns"
else
  fail "T1b: tenant yaml parse" "yaml.safe_load or glm_policy key failed"
fi
t1_sig() { # <writes_csv> <expect_protected 0|1>
  bash -c 'source "$1"; leadv2_review_signals "$2" "$3" >/dev/null 2>&1; exit $((1 - LEADV2_REVIEW_SIGNALS_PROTECTED))' _ "$SIGNALS_LIB" "$TENANT_YAML" "$1" && got=1 || got=0
  [[ "$got" == "$2" ]]
}
t1_sig "plugins/leadv2/scripts/leadv2-dispatch-code.sh,docs/foo.md" 1 \
  && pass "T1c: plugin script path -> protected" \
  || fail "T1c: plugin script path" "expected protected=1"
t1_sig "plugins/leadv2/hooks/x.sh,plugins/leadv2/config/x.yaml,plugins/leadv2/scripts/lib/x.py" 1 \
  && pass "T1d: hooks/config/lib paths -> protected" \
  || fail "T1d: hooks/config/lib paths" "expected protected=1"
t1_sig "docs/missions/some-report.md" 0 \
  && pass "T1e: docs markdown path -> NOT protected (deliberate)" \
  || fail "T1e: docs markdown path" "expected protected=0"

# ── T2: author exclusion against the TENANT policy surface (R7) ────────────────
# PLUGIN-REPO-CARRIES-A-SHADOW-ROUTING-CONFIG-01 (2026-09-10): the tenant file
# is now a DELTA; what dispatch actually reads in this repo is the MERGED
# config (canonical registry + this repo's delta), so the author-exclusion
# proof runs against the merged materialization, not the delta file alone.
T2_YAML="$(bash -c 'source "$1"; leadv2_routing_config_path "$2"' _ \
  "${SCRIPTS_ROOT}/lib/leadv2-routing-config.sh" "$REPO_ROOT" 2>/dev/null)" || T2_YAML="$TENANT_YAML"
[[ -n "$T2_YAML" ]] || T2_YAML="$TENANT_YAML"
t2_pool() { # <author> -> prints resolver output
  python3 "$RESOLVER" --routing-yaml "$T2_YAML" --job review --base-arm codex \
    --review-pool --author "$1" --signals '{"protected_path":true,"safety_touched":true}' 2>/dev/null
}
out_glm="$(t2_pool glm)"
pool_glm="$(printf '%s\n' "$out_glm" | sed -n 's/^pool=//p')"
rev_glm="$(printf '%s\n' "$out_glm" | sed -n 's/^reviewer=//p')"
if printf '%s' ",${pool_glm}," | grep -q ',glm:author:'; then
  pass "T2a: --author glm keeps glm in pool tagged :author: (present but never selectable)"
else
  fail "T2a: --author glm" "pool lacks glm:author: -- got: ${pool_glm}"
fi
if [[ -n "$rev_glm" && "$rev_glm" != "glm" ]]; then
  pass "T2b: --author glm seats reviewer=${rev_glm} (not the author)"
else
  fail "T2b: --author glm" "reviewer empty or equals author: '${rev_glm}'"
fi
out_opus="$(t2_pool opus)"
pool_opus="$(printf '%s\n' "$out_opus" | sed -n 's/^pool=//p')"
rev_opus="$(printf '%s\n' "$out_opus" | sed -n 's/^reviewer=//p')"
if printf '%s' ",${pool_opus}," | grep -q ',opus:author:'; then
  pass "T2c: --author opus tags opus:author: in pool"
else
  fail "T2c: --author opus" "pool lacks opus:author: -- got: ${pool_opus}"
fi
if [[ -n "$rev_opus" && "$rev_opus" != "opus" ]]; then
  pass "T2d: --author opus seats reviewer=${rev_opus} (not the author)"
else
  fail "T2d: --author opus" "reviewer empty or equals author: '${rev_opus}'"
fi
# kimi stays safety-excluded under a protected-path signal with the tenant patterns live.
if printf '%s' ",${pool_glm}," | grep -q ',kimi:excluded:safety'; then
  pass "T2e: kimi stays excluded:safety under protected-path signal (arm mix unchanged)"
else
  fail "T2e: kimi exclusion" "pool lacks kimi:excluded:safety -- got: ${pool_glm}"
fi

# ── T3: stale-tree dispatch refuses (exit 4) ───────────────────────────────────
STALE="$ROOT/stale-tree/scripts"
mkdir -p "$STALE" "$REPO/plugins/leadv2/scripts"
cp "$DISPATCH" "$STALE/leadv2-dispatch-code.sh"
cp "${SCRIPTS_ROOT}/leadv2-lane-child-suffixes.sh" "${SCRIPTS_ROOT}/leadv2-portable-lock.sh" "$STALE/"
# The discoverable canonical tree (suffix-matched path inside the scratch project).
cp "$DISPATCH" "$REPO/plugins/leadv2/scripts/leadv2-dispatch-code.sh"
FAKE_JOURNAL="$ROOT/fake-journal.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/journal-capture.txt"\n' "$ROOT" > "$FAKE_JOURNAL"
chmod +x "$FAKE_JOURNAL"

out3="$(dispatch_env LEADV2_JOURNAL_BIN="$FAKE_JOURNAL" bash "$STALE/leadv2-dispatch-code.sh" \
    'stale tree refusal probe' --kind product --writes src/main.py --no-spawn 2>&1)" ; rc3=$?
if [[ "$rc3" -eq 4 ]]; then
  pass "T3a: stale-tree dispatch exits 4"
else
  fail "T3a: stale-tree exit" "expected rc=4, got ${rc3}"
fi
if printf '%s\n' "$out3" | grep -q 'dispatch refused: running from a stale script copy'; then
  pass "T3b: refusal names the stale tree on stderr"
else
  fail "T3b: refusal text" "stderr lacks the refuse line -- got: $(printf '%s' "$out3" | tail -2)"
fi
if printf '%s\n' "$out3" | grep -q 'remedy: ln -sf'; then
  pass "T3c: remedy lands on stderr"
else
  fail "T3c: remedy" "no remedy line"
fi
if grep -q 'dispatch_refused reason=stale_script_tree' "$ROOT/journal-capture.txt" 2>/dev/null; then
  pass "T3d: journal carries dispatch_refused reason=stale_script_tree"
else
  fail "T3d: journal line" "capture lacks dispatch_refused: $(cat "$ROOT/journal-capture.txt" 2>/dev/null | tail -2)"
fi

# ── T4: escape hatch downgrades to warn ────────────────────────────────────────
rm -f "$ROOT/journal-capture.txt"
out4="$(dispatch_env LEADV2_ALLOW_STALE_SCRIPT_TREE=1 LEADV2_JOURNAL_BIN="$FAKE_JOURNAL" \
  bash "$STALE/leadv2-dispatch-code.sh" \
    'stale tree escape hatch probe' --kind product --writes src/main.py --no-spawn 2>&1)" ; rc4=$?
if [[ "$rc4" -ne 4 ]]; then
  pass "T4a: escape hatch does not refuse (rc=${rc4})"
else
  fail "T4a: escape hatch" "still refused with LEADV2_ALLOW_STALE_SCRIPT_TREE=1"
fi
if printf '%s\n' "$out4" | grep -q 'dispatch_stale_script_tree_warn'; then
  pass "T4b: escape hatch emits the downgrade warn"
else
  fail "T4b: downgrade warn" "no dispatch_stale_script_tree_warn line"
fi

# ── T5/T8: legitimate run trees pass; phase-record resolves (no rc=127) ───────
run_pass_tree() { # <script_path> <label>
  local out rc
  out="$(dispatch_env LEADV2_JOURNAL_BIN="$FAKE_JOURNAL" bash "$1" \
      "legitimate tree probe $2" --kind product --writes src/main.py --no-spawn 2>&1)" ; rc=$?
  if [[ "$rc" -eq 4 ]]; then
    fail "T5($2)" "refused (rc=4) -- legitimate tree must pass the suffix check"
    return
  fi
  if printf '%s\n' "$out" | grep -q 'dispatch_refused reason=stale_script_tree'; then
    fail "T5($2)" "emitted dispatch_refused from a legitimate tree"
    return
  fi
  pass "T5($2): passes provenance check (rc=${rc})"
  # R6 pin: the phase precondition may still WARN (rc=3 with a real missing= list is
  # load-bearing -- no phase has ever been recorded for plugin work) but it must never
  # again be rc=127 (binary not found under a stale tree).
  if printf '%s\n' "$out" | grep -q 'value=127'; then
    fail "T8($2)" "phase_precondition reports rc=127 -- phase-record binary not resolved"
  else
    pass "T8($2): no 'value=127' (phase-record binary resolves from the plugin tree)"
  fi
}
run_pass_tree "$DISPATCH" "plugin-tree"
WT="$ROOT/wt/plugins/leadv2/scripts"
mkdir -p "$WT"
cp -R "${SCRIPTS_ROOT}/." "$WT/"
run_pass_tree "$WT/leadv2-dispatch-code.sh" "worktree-style"

# ── T6: engine unreviewed artifact carries the full diagnostic shape ───────────
HANDOFF6="$ROOT/handoff6"; mkdir -p "$HANDOFF6"
printf 'diff --git a/x b/x\n' > "$ROOT/d6.diff"
CRASH="$ROOT/crash-resolver.py"
printf '#!/usr/bin/env python3\nimport sys\nsys.stderr.write("boom: simulated resolver crash\\n")\nsys.exit(1)\n' > "$CRASH"
chmod +x "$CRASH"
out6="$(LEADV2_GLM_POLICY_RESOLVER="$CRASH" LEADV2_ROUTING_YAML="$TENANT_YAML" \
  bash "$REVIEW_RUN" --task t6probe --root "$REPO" --handoff "$HANDOFF6" \
  --diff "$ROOT/d6.diff" --author glm 2>&1)" ; rc6=$?
GATE6="$HANDOFF6/review-gate.md"
gate_has() { grep -q "^$1" "$GATE6" 2>/dev/null; }
if [[ "$rc6" -eq 9 && -s "$GATE6" ]]; then
  pass "T6a: engine exits 9 and writes review-gate.md"
else
  fail "T6a: engine unreviewed path" "rc=${rc6}, artifact=$(ls "$GATE6" 2>/dev/null || echo none)"
fi
gate_has "status: unreviewed" && pass "T6b: status: unreviewed" || fail "T6b: status" "absent"
gate_has "refusal: " && pass "T6c: refusal: present" || fail "T6c: refusal" "absent"
grep -q "^resolver_rc: 1$" "$GATE6" 2>/dev/null && pass "T6d: resolver_rc: 1 captured" || fail "T6d: resolver_rc" "not 1: $(grep '^resolver_rc' "$GATE6" 2>/dev/null)"
grep -q "^resolver_stderr: boom" "$GATE6" 2>/dev/null && pass "T6e: resolver_stderr carries the crash line" || fail "T6e: resolver_stderr" "$(grep '^resolver_stderr' "$GATE6" 2>/dev/null)"
gate_has "merge_blocked: true" && pass "T6f: merge_blocked: true" || fail "T6f: merge_blocked" "absent"
if [[ "$(tail -1 "$GATE6" 2>/dev/null)" == "merge_blocked: true" ]]; then
  pass "T6g: artifact ends on merge_blocked: true, not a bare pool: line"
else
  fail "T6g: last line" "got: $(tail -1 "$GATE6" 2>/dev/null)"
fi

# ── T7: engine and lane writers emit the identical field set (R8) ─────────────
# Extract 'key:' tokens from the engine's actual artifact and from the lane writer's
# printf format string (_pc_write_unviewed -> _pc_write_unreviewed body, \\n split).
# python, not sed: BSD sed cannot emit a newline from the replacement side.
t7_out="$(python3 - "$GATE6" "$PRODUCT_CLOSE" <<'PYEOF'
import re, sys
gate = open(sys.argv[1]).read()
eng = sorted(set(re.findall(r'(?m)^([a-z_]+):', gate)))
src = open(sys.argv[2]).read()
m = re.search(r"_pc_write_unreviewed\(\)[^{]*\{(.*?)\n\}", src, re.S)
if not m:
    print("ERR no _pc_write_unreviewed body"); sys.exit(1)
lane = sorted(set(re.findall(r'([a-z_]+):', m.group(1).replace('\\n', '\n'))))
print("engine=" + ",".join(eng))
print("lane=" + ",".join(lane))
print("same=" + ("1" if eng == lane else "0"))
PYEOF
)"
if printf '%s\n' "$t7_out" | grep -q '^same=1$'; then
  pass "T7: engine review-gate.md field set == lane _pc_write_unreviewed field set ($(printf '%s\n' "$t7_out" | sed -n 's/^engine=//p' | tr ',' ' '))"
else
  fail "T7: field-set drift" "$(printf '%s\n' "$t7_out" | tr '\n' ' ')"
fi

printf '\nplugin-review-arms: %d pass, %d fail\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
