#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-dispatch-code leadv2-route-arbiter
# FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 -- the arbiter must never pick an arm the
# router already excluded in the SAME dispatch.
#
# Bug reproduced live 2026-08-30 across tasks 37a9e8fa/d7b71ad4/f9ecad31:
#   arm_excluded by=router arm=freepool reason=arm_not_capable_for_size task_class=light when=standard,bulk
#   route_resolved by=arbiter reason=cheapest_capable arbiter_pick=freepool
# The router's ladder-level `when:` filter (_build_candidate_chain in
# leadv2-dispatch-code.sh) excludes freepool for a `light` task (freepool's
# ladder entry only declares `when: [standard, bulk]`), but the arbiter's own
# capability matrix independently folds light -> the "standard" size bucket
# (SIZE_MAP) and its capability floor deliberately keeps trivial/light
# freepool-COST-eligible -- so the arbiter re-admits exactly the arm the
# router just excluded.
#
# Fix: leadv2-dispatch-code.sh now passes the router's post-filter
# candidate_arms as `allowed_arms` in the descriptor handed to route_arbiter;
# the arbiter's matrix (leadv2-route-arbiter.sh:146) already intersects
# against `allowed_arms` when present -- it just never received one before.
#
# Control (mission rule): mutate a THROWAWAY COPY of the production dispatch
# script (strip the allowed_arms wiring), prove the exact repro line comes
# back (RED), then run the same scenario against the real, unmutated file
# and prove it stays fixed (GREEN). Hermetic: quota/freepool-gate/arbiter
# state are all test seams; --no-spawn; real worker process never runs.
#
# ── 2026-09-05: why the fixture now OWNS the routing config ──────────────────
# This suite went 1/3 red, and two of the three failures were the suite
# asserting a precondition the shipped config had deliberately deleted:
#
#   78ae2a5a 2026-08-30 fix(freepool): arbiter honours router arm exclusions
#            -- created the allowed_arms wiring AND this suite. At that commit
#            freepool's ladder entry did not list `light`, so a light task was
#            genuinely excluded by the router.
#   8cbeeed4 2026-08-31 feat(routing): arm admission -- ... router/arbiter
#            agreement -- ADDED `light` to freepool's ladder `when:`, with a
#            ten-line rationale in the yaml itself (ARMS-ADMISSION-01 /
#            ROUTER-ARBITER-DISAGREE-ON-FREEPOOL-01): the arbiter's SIZE_MAP
#            has always folded light -> the `standard` cell, the founder
#            already signed that behaviour off (FP-06/FP-08), so the ladder
#            now agrees with the arbiter instead of the arbiter being
#            overruled.
#
# The same disagreement was settled twice, one day apart, in opposite
# directions -- first by FORCING the arbiter to honour the exclusion, then by
# REMOVING the exclusion. Both are in the tree. The observable consequence:
# the shipped config produces `candidate_chain arms=freepool,codex,sonnet` for
# a light task -- no exclusion at all, so there is nothing for the arbiter to
# violate and the guard could not be exercised.
#
# The property under test is NOT "the shipped config excludes freepool for a
# light task" -- that is policy, and policy moved. It is "the arbiter must
# never re-admit an arm the router excluded IN THE SAME DISPATCH". So the
# fixture manufactures the disagreement itself: it copies the real routing
# yaml and removes `light` from freepool's LADDER entry only, restoring
# exactly the shape the live 2026-08-30 bug had. The arbiter side is
# untouched and real -- its SIZE_MAP still folds light -> standard, and its
# capability cell still lists freepool as cost-eligible there, so it still
# genuinely WANTS the arm the router just dropped.
#
# If the downgrade below stops applying (freepool's ladder entry gone, or
# `light` no longer in it), the fixture FAILS LOUDLY naming what it looked
# for. A precondition that quietly evaporates is what put this suite in the
# red list for six days while reading as a product accusation.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_BIN="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"
ROUTING="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/arm-cap-honoured.XXXXXX")"
trap '[[ "${ARMCAP_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"' EXIT

bash -n "$DISPATCH_BIN" || { fail "bash syntax: dispatch"; exit 1; }
pass "bash syntax: dispatch"

quota_json() { # <glm_pct> <codex_pct> <claude_pct> -- all healthy (low pct)
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
# glm capped so glm/glm-flash leave the picture (matches FP-08's shape) --
# codex+claude healthy, freepool (cost 0 when un-gated) is the only cheap arm
# left standing, so an un-filtered arbiter genuinely WANTS to pick it.
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

setup_repo() { # <dir>
  local repo="$1"
  mkdir -p "$repo/.claude/ref" "$repo/docs/leadv2" "$repo/docs/leadv2/tasks"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@e.com; git -C "$repo" config user.name t
  : > "$repo/seed"; git -C "$repo" add seed; git -C "$repo" commit -qm seed
  cp "$ROUTING" "$repo/.claude/ref/leadv2-routing.yaml"
  # Restore the router/arbiter disagreement this suite exists to pin (see the
  # header): drop `light` from freepool's LADDER `when:` only. Structural, not
  # a copied line -- the entry is found by id, so a reordered or extended
  # `when:` list still matches. The capability_matrix cell for freepool is a
  # one-line flow mapping carrying `sizes:`, never `when:`, so it cannot be
  # hit by accident.
  # A fixture that cannot build its own scenario must stop the run, not hand
  # the green assertions a config they were never written against.
  python3 - "$repo/.claude/ref/leadv2-routing.yaml" <<'PY' || { fail "(fixture) routing downgrade failed" "see stderr above"; echo "---"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
import sys

# Line scan, deliberately NOT one regex. The first attempt was
#   ^ *- id: freepool\n(?:[ \t]+(?!- id:)[^\n]*\n)*? +when: \[([^\]]*)\]
# and it HUNG: `[ \t]+` followed by `[^\n]*` is a nested quantifier over the
# same text, so a non-matching `- id: freepool` block sent it into exponential
# backtracking. Measured 2026-09-05: python pinned for 2.5 minutes with no
# output. A fixture that HANGS is worse than one that fails -- it reads as a
# slow suite, which is exactly the misdiagnosis this lane spent a run undoing.
p = sys.argv[1]
lines = open(p).read().splitlines(keepends=True)

# There is more than one `- id: freepool` in this yaml (one of them carries no
# `when:` at all), so scan EVERY occurrence and take the ones that do. If two
# ever qualify, refuse rather than silently picking the first -- an ambiguous
# anchor is how a fixture ends up downgrading something nobody meant.
found = []                                   # [(entry_line, when_line)]
for i, ln in enumerate(lines):
    if ln.strip() != '- id: freepool':
        continue
    for k in range(i + 1, len(lines)):
        st = lines[k].strip()
        if st.startswith('- id:'):
            break                            # next entry: this one has no when:
        if st.startswith('when:'):
            found.append((i, k))
            break
if not found:
    sys.exit("FIXTURE PRECONDITION GONE: no `- id: freepool` entry in "
             "leadv2-routing.yaml carries a `when:` list -- this suite's "
             "scenario cannot be built; re-anchor it, do not silence it")
if len(found) > 1:
    sys.exit("FIXTURE ANCHOR AMBIGUOUS: %d `- id: freepool` entries carry a "
             "`when:` (lines %s) -- refusing to guess which is the ladder"
             % (len(found), [f[0] + 1 for f in found]))
when_i = found[0][1]
head, _, rest = lines[when_i].partition('[')
body, _, tail = rest.partition(']')
items = [x.strip() for x in body.split(',') if x.strip()]
if 'light' not in items:
    sys.exit("FIXTURE PRECONDITION GONE: freepool's ladder `when:` is %r, which "
             "already lacks `light` -- the downgrade would be a no-op and the "
             "green assertions would pass for the wrong reason" % (items,))
lines[when_i] = head + '[' + ', '.join(x for x in items if x != 'light') + ']' + tail
open(p, 'w').writelines(lines)
PY
}

WORKER="$TMP/worker.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' > "$WORKER"
chmod +x "$WORKER"

# Admission classifier stub: reports complexity=trivial so
# leadv2_admission_map_class -> "Light", which becomes DC_TASK_CLASS=light
# for _build_candidate_chain's `when:` filter -- the exact task_class the
# live bug's repro lines show (task_class=light when=standard,bulk).
TASK_JUDGE="$TMP/task-judge.sh"
cat > "$TASK_JUDGE" <<'EOF'
#!/usr/bin/env bash
printf '%s' '{"complexity":"trivial","estimate_source":"judge"}'
EOF
chmod +x "$TASK_JUDGE"

run_dispatch() { # <dispatch_bin> <repo_dir> <state_suffix>
  local bin="$1" repo="$2" suffix="$3"
  (cd "$repo" && LEADV2_STATE_ROOT="$TMP/state-root-$suffix" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-dispatch-$suffix" \
    ROUTE_TEST_QUOTA="$LOW_QUOTA" \
    CLAUDE_PROJECT_ROOT="$repo" LEADV2_PROJECT_ROOT="$repo" \
    LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-$suffix" \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_REQUIRE_PHASES=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
    LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_TASK_JUDGE_BIN="$TASK_JUDGE" \
    LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
    bash "$bin" "arm-capability-honoured probe ${TMP}" \
      --kind product --no-spawn --writes src/x.py 2>&1 || true)
}

# ── GREEN: real, unmutated dispatch script ────────────────────────────────
REPO_GREEN="$TMP/repo-green"
setup_repo "$REPO_GREEN"
out_green="$(run_dispatch "$DISPATCH_BIN" "$REPO_GREEN" green)"
printf '%s\n' "$out_green" > "$TMP/green.log"

if printf '%s\n' "$out_green" | grep -q 'arm_excluded by=router arm=freepool task=[0-9a-f]\{8\} reason=arm_not_capable_for_size task_class=light'; then
  pass "(green) router still excludes freepool for a light task (when=standard,bulk)"
else
  # A missing exclusion means the SCENARIO is gone, not that the guard broke --
  # say so by name, because reading this as a product accusation is exactly how
  # this suite sat red for six days.
  fail "(green) router did not exclude freepool for a light task -- the fixture's
      precondition no longer holds. The exclusion is emitted at
      leadv2-dispatch-code.sh:2455 (reason=arm_not_capable_for_size), driven by
      the freepool ladder entry's when: list in plugins/leadv2/config/leadv2-routing.yaml;
      the arbiter side that must honour it is lib/leadv2-route-arbiter.sh:336.
      Check setup_repo's downgrade actually applied before blaming either" \
      "log: $TMP/green.log"
fi
if printf '%s\n' "$out_green" | grep -qE 'route_resolved by=arbiter role=worker arm=freepool|arbiter_pick=freepool'; then
  fail "(green) arbiter picked freepool despite router exclusion (log: $TMP/green.log)"
else
  pass "(green) arbiter honours the router's exclusion -- freepool never arbiter_pick"
fi

# ── RED: throwaway mutated copy with the allowed_arms wiring stripped ─────
# Copy the complete scripts tree into TMP so sibling-library resolution stays
# real while production directories remain immutable even on interruption.
MUT_PLUGIN_ROOT="$TMP/mutated-plugin"
mkdir -p "$MUT_PLUGIN_ROOT"
cp -R "$SCRIPTS_ROOT" "$MUT_PLUGIN_ROOT/scripts"
cp -R "${SCRIPTS_ROOT}/../config" "$MUT_PLUGIN_ROOT/config"
MUT_BIN="${MUT_PLUGIN_ROOT}/scripts/leadv2-dispatch-code.sh"
# Drop ONLY the allowed_arms key from the descriptor the dispatcher builds, so
# the arbiter's cell filter stops intersecting against the router's post-filter
# chain (leadv2-route-arbiter.sh:336, `allowed is None or ...`) and falls back
# to its own capability matrix alone -- the pre-78ae2a5a shape.
#
# 2026-09-05: this used to be a verbatim copy of the ENTIRE descriptor line,
# and it rotted -- production gained complexity/duration_class/test_only, the
# replace matched nothing, and the control could not run. The anchor is now
# the smallest fragment that carries the meaning, so any further field added
# beside it leaves the control working. The zero-match failure below stays:
# a control that cannot find its anchor must be LOUD, never a silent pass.
python3 - "$MUT_BIN" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
anchor = ',"allowed_arms":allowed'
n = src.count(anchor)
if n != 1:
    sys.exit('mutation anchor %r found %d times in %s (expected exactly 1) -- '
             'zero-match/ambiguous, hard failure. The wiring under test lives at '
             'the _arb_desc build in leadv2-dispatch-code.sh; the arbiter side '
             'that consumes it is lib/leadv2-route-arbiter.sh:336. If the key was '
             'renamed or moved, re-anchor this control -- do not silence it.'
             % (anchor, n, path))
open(path, 'w').write(src.replace(anchor, ''))
PY
if [[ $? -ne 0 ]]; then
  fail "(red) mutation anchor not found in production file -- cannot prove the control" "zero-match"
else
  bash -n "$MUT_BIN" || fail "(red) mutated copy fails bash -n"
  REPO_RED="$TMP/repo-red"
  setup_repo "$REPO_RED"
  out_red="$(run_dispatch "$MUT_BIN" "$REPO_RED" red)"
  printf '%s\n' "$out_red" > "$TMP/red.log"
  if printf '%s\n' "$out_red" | grep -qE 'route_resolved by=arbiter role=worker arm=freepool|arbiter_pick=freepool'; then
    pass "(red) with allowed_arms wiring stripped, the exact live bug reproduces -- arbiter re-picks the router-excluded arm"
  else
    fail "(red) mutation did not flip the outcome -- control is not falsifiable (log: $TMP/red.log)"
  fi
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
