#!/usr/bin/env bash
# FP-06 (2026-08-28) — model-selection telemetry suite.
#
# Contract: leadv2-dispatch-code.sh emits ONE machine-parseable journal row
# per dispatch attempt at EVERY model-selection terminal (fix-round H2
# census: win, chain-exhaustion, quota-lockout, exclusion,
# not-dispatchable, arbiter hard-refusal):
#   model_select_telemetry task=<sig8> role=worker class=<class>
#     work_kind=<wk> arm=<arm> model=<model> fallback_depth=<N>
#     floor=<applied|none> spawn_to_terminal_s=<S> terminal=<win|fail>
#     cause=<c>
# model names the FINAL executing arm/model (fix-round H1: after a
# route_fallback it is the fallback candidate, never the arbiter's original
# pick). The same row is appended as CSV to docs/leadv2/
# model-select-telemetry.csv (header auto-created exactly once,
# lock-protected — fix-round M3; capped — H4) for FP-04's later 20-diff
# quality analysis.
#
# Test (a): the line is present on a stubbed WIN (freepool bulk build with a
# live stub worker -> confirmed spawn -> terminal=win) AND on a stubbed
# no_work FAIL (stub launcher produces nothing and dies -> chain exhausted ->
# terminal=fail), with every field present and parseable.
# Test (b): CSV row appended, header written once across both dispatches.
# Test (e) [H1]: glm-flash refuses -> route_fallback -> freepool wins; the
# row must carry arm=freepool model=freepool fallback_depth=1.
# Test (g) [H2 census]: each stubbed refusal terminal emits exactly one row
# with the right cause.
# Test (h) [M2]: a work_kind containing a space survives as ONE token in
# both the journal row and the CSV column count.
# Test (i) [H4]: a pre-grown CSV over the cap is rotated (header kept,
# newest rows kept, line count == cap).
#
# NEGATIVE CONTROLS (RUN RED):
#   (d) a throwaway copy of dispatch-code with the win-terminal telemetry
#       call removed re-runs the EXACT win probe and must produce NO
#       model_select_telemetry line and NO CSV row -- proving (a)'s
#       assertion is load-bearing, not tautological.
#   (f) [H1] a throwaway copy with the per-candidate model re-stamp mutated
#       back to "arbiter model wins everywhere" re-runs the EXACT fallback
#       probe and must reproduce the pre-fix lie (arm=freepool
#       model=glm-5.3-flash) -- proving (e) is load-bearing.
# Both copies live in a mktemp-unique $TMP scripts mirror (symlinks to every
# canonical sibling, only dispatch-code itself is a real mutated file) —
# fix-round H3: NEVER a real file in the canonical plugin dir, no fixed
# shared name, no trap-only cleanup dependency.
#
# Hermetic: no network, no live proxy, no real dispatch. Same seams as the
# FP-08 floor suite (LEADV2_ROUTE_ARBITER_*, LEADV2_DISPATCH_*_BIN).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_BIN="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"
ROUTING="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fp06-telem.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

bash -n "$DISPATCH_BIN" || { fail "bash syntax: dispatch"; exit 1; }
pass "bash syntax: dispatch"

# ── fixtures (same shape as test-freepool-capability-floor.sh) ──────────────
cat > "$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat > "$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"

quota_json() { # <glm_pct> <codex_pct> <claude_pct>
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
# every paid provider capped -> freepool is the only capable arm (bulk build)
ALL_CAPPED="$(quota_json 99 99 99)"
# glm healthy -> arbiter chain glm-flash,freepool,glm (fallback probe (e))
GLM_LIVE="$(quota_json 30 99 99)"

mk_repo() { # <dir>
  mkdir -p "$1/.claude/ref" "$1/docs/leadv2" "$1/docs/leadv2/tasks"
  git -C "$1" init -q -b main
  git -C "$1" config user.email t@e.com; git -C "$1" config user.name t
  : > "$1/seed"; git -C "$1" add seed; git -C "$1" commit -qm seed
  cp "$ROUTING" "$1/.claude/ref/leadv2-routing.yaml"
}

WORKER="$TMP/worker.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' > "$WORKER"
chmod +x "$WORKER"

# Hermetic admission: trivial estimate -> Light (never floored), work_kind=<arg>.
mk_judge() { # <path> <work_kind>
  cat > "$1" <<JEOF
#!/usr/bin/env bash
printf '%s\n' '{"complexity":"trivial","work_kind":"$2","estimate_source":"fallback"}'
JEOF
  chmod +x "$1"
}
mk_judge "$TMP/judge-light.sh" build

# (a-win) freepool stub: bg -> live handle, status -> running. The win
# terminal fires at spawn CONFIRM time, so no background completion is needed.
FP_RUNS="$TMP/freepool-runs"; mkdir -p "$FP_RUNS"
cat > "$TMP/freepool-win-stub.sh" <<STUB
#!/usr/bin/env bash
RUNS="\${FP_STUB_RUNS:-$FP_RUNS}"
case "\${1:-}" in
  bg)
    shift
    id="run-\$\$"
    mkdir -p "\$RUNS/\$id"
    printf 'status: running\npid: %s\n' "\$\$" > "\$RUNS/\$id/meta.yaml"
    printf '%s\n' "\$id"
    ;;
  status)
    cat "\$RUNS/\${2:-}/meta.yaml" 2>/dev/null
    ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$TMP/freepool-win-stub.sh"

# (a-fail) freepool stub that produces NOTHING and dies (no_work shape: no
# run dir, no handle ever live, launcher exit 99 with no refusal marker).
cat > "$TMP/freepool-fail-stub.sh" <<'STUB'
#!/usr/bin/env bash
printf 'status: failed\nexit_code: 1\n' >&2
exit 99
STUB
chmod +x "$TMP/freepool-fail-stub.sh"

for _arm in glm kimi codex; do
  printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "$TMP/poison-${_arm}.sh"
  chmod +x "$TMP/poison-${_arm}.sh"
done

# Optional-seam knobs (per-probe overrides, all default to the (a) shape):
#   FP06_ROUTER_V2 / FP06_JUDGE_BIN / FP06_EXCLUDED — census probes (g).
# Everything else (LEADV2_ROUTER_V2_BIN, LEADV2_QUOTA_LOCKOUT_DIR, ...) rides
# through the exported environment unchanged.
run_dispatch() { # <repo_dir> <freepool_stub> <unique-mission> [dispatch_bin]
  (cd "$1" && \
   LEADV2_STATE_ROOT="$TMP/state-root-$3" \
   LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
   LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
   LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-$3" \
   ROUTE_TEST_QUOTA="${FP06_QUOTA:-$ALL_CAPPED}" \
   CLAUDE_PROJECT_ROOT="$1" LEADV2_PROJECT_ROOT="$1" \
   LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-$3" \
   LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
   LEADV2_ROUTER_V2="${FP06_ROUTER_V2:-0}" \
   LEADV2_EXCLUDED_ARMS="${FP06_EXCLUDED:-__none__}" LEADV2_LANE_SHAPE=off \
   LEADV2_BURN_GOVERNOR=0 \
   LEADV2_TASK_JUDGE_BIN="${FP06_JUDGE_BIN:-$TMP/judge-light.sh}" \
   LEADV2_ARM_EARLY_VERDICT_S=1 LEADV2_ARM_EARLY_VERDICT_POLL_S=0.2 \
   LEADV2_DISPATCH_FREEPOOL_BIN="$2" FP_STUB_RUNS="$FP_RUNS" \
   LEADV2_DISPATCH_GLM_BIN="${FP06_GLM_BIN:-$TMP/poison-glm.sh}" \
   LEADV2_DISPATCH_KIMI_BIN="$TMP/poison-kimi.sh" \
   LEADV2_DISPATCH_CODEX_BIN="$TMP/poison-codex.sh" \
   LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
   bash "${4:-$DISPATCH_BIN}" "FP-06 telemetry probe $3" \
     --kind code --task-class bulk --writes src/x.py 2>&1 || true)
}

# every field, present and parseable (shared by win and fail rows)
TELEM_RE='model_select_telemetry task=[0-9a-f]{8} role=worker class=[a-z]+ work_kind=[a-z_-]+ arm=[a-z_-]+ model=[^ ]+ fallback_depth=[0-9]+ floor=(applied|none) spawn_to_terminal_s=[0-9]+ terminal=(win|fail) cause=[a-z_]+'

# one_row <label> <log> <expected terminal=... cause=... substring>: exactly
# ONE telemetry row in the whole dispatch output, parseable, with the given
# terminal/cause — the H2 census shape (a silent missing row is the failure
# mode this catches; a duplicate row is the opposite corruption).
one_row() { # <label> <output-log> <expected-substring>
  local _label="$1" _log="$2" _want="$3" _n _line
  _n="$(printf '%s\n' "$_log" | grep -c 'model_select_telemetry task=')"
  _line="$(printf '%s\n' "$_log" | grep 'model_select_telemetry task=' | tail -1)"
  if [[ "${_n}" -eq 1 ]]; then
    pass "${_label}: exactly one telemetry row"
  else
    fail "${_label}: expected exactly 1 telemetry row, got ${_n}"
  fi
  if printf '%s' "$_line" | grep -qE "$TELEM_RE"; then
    pass "${_label}: row parseable, every field present"
  else
    fail "${_label}: row unparseable (line: '${_line}')"
  fi
  if printf '%s' "$_line" | grep -qF "$_want"; then
    pass "${_label}: ${_want}"
  else
    fail "${_label}: row lacks '${_want}' (line: '${_line}')"
  fi
}

# ── (a) WIN: stubbed freepool worker -> confirmed spawn -> terminal=win ────
REPO1="$TMP/repo1"; mk_repo "$REPO1"
win_out="$(run_dispatch "$REPO1" "$TMP/freepool-win-stub.sh" win)"
printf '%s\n' "$win_out" > "$TMP/win-out.log"
win_line="$(printf '%s\n' "$win_out" | grep -E 'model_select_telemetry' | tail -1)"
if printf '%s' "$win_line" | grep -qE "$TELEM_RE"; then
  pass "(a) win: telemetry line present with every field parseable"
else
  fail "(a) win: telemetry line missing/unparseable (line: '$win_line'; log: $TMP/win-out.log)"
fi
if printf '%s' "$win_line" | grep -q 'terminal=win cause=worker_spawned'; then
  pass "(a) win: terminal=win cause=worker_spawned"
else
  fail "(a) win: wrong terminal/cause ($win_line)"
fi
if printf '%s\n' "$win_out" | grep -q 'route_resolved by=arbiter role=worker arm=freepool'; then
  pass "(a) win: probe really dispatched via freepool"
else
  fail "(a) win: probe did not dispatch via freepool (log: $TMP/win-out.log)"
fi

# ── (a) FAIL: stub that produces no work and dies -> chain exhausted ────────
REPO2="$TMP/repo2"; mk_repo "$REPO2"
fail_out="$(run_dispatch "$REPO2" "$TMP/freepool-fail-stub.sh" fail)"
printf '%s\n' "$fail_out" > "$TMP/fail-out.log"
fail_line="$(printf '%s\n' "$fail_out" | grep -E 'model_select_telemetry' | tail -1)"
if printf '%s' "$fail_line" | grep -qE "$TELEM_RE"; then
  pass "(a) fail: telemetry line present with every field parseable"
else
  fail "(a) fail: telemetry line missing/unparseable (line: '$fail_line'; log: $TMP/fail-out.log)"
fi
if printf '%s' "$fail_line" | grep -q 'terminal=fail cause=all_arms_unavailable'; then
  pass "(a) fail: terminal=fail cause=all_arms_unavailable"
else
  fail "(a) fail: wrong terminal/cause ($fail_line)"
fi
if printf '%s' "$fail_line" | grep -q 'arm=freepool'; then
  pass "(a) fail: failing arm recorded"
else
  fail "(a) fail: arm field wrong ($fail_line)"
fi

# ── (b) CSV: row per dispatch, header exactly once ──────────────────────────
CSV="$REPO2/docs/leadv2/model-select-telemetry.csv"
win_csv="$REPO1/docs/leadv2/model-select-telemetry.csv"
if [[ -f "$win_csv" && -f "$CSV" ]]; then
  pass "(b) CSV file created under docs/leadv2 for each repo"
else
  fail "(b) CSV file missing (win: ${win_csv}, fail: ${CSV})"
fi
h1="$(grep -c '^task,role,class,work_kind,arm,model,fallback_depth,floor,spawn_to_terminal_s,terminal,cause$' "$CSV" 2>/dev/null || true)"
if [[ "${h1:-0}" -eq 1 ]]; then
  pass "(b) CSV header written exactly once"
else
  fail "(b) CSV header count != 1 ($h1; file: $(cat "$CSV" 2>/dev/null | head -3))"
fi
if tail -1 "$CSV" 2>/dev/null | grep -qE "^[0-9a-f]{8},worker,[a-z]+,[a-z_-]+,freepool,.+,[0-9]+,(applied|none),[0-9]+,fail,all_arms_unavailable$"; then
  pass "(b) fail dispatch appended a matching CSV row"
else
  fail "(b) fail CSV row wrong ($(tail -1 "$CSV" 2>/dev/null))"
fi
if tail -1 "$win_csv" 2>/dev/null | grep -qE "^[0-9a-f]{8},worker,[a-z]+,[a-z_-]+,freepool,.+,[0-9]+,(applied|none),[0-9]+,win,worker_spawned$"; then
  pass "(b) win dispatch appended a matching CSV row"
else
  fail "(b) win CSV row wrong ($(tail -1 "$win_csv" 2>/dev/null))"
fi

# ── H3: negative-control scripts mirror ─────────────────────────────────────
# A mktemp-unique directory holding SYMLINKS to every canonical sibling and
# exactly one real file: the mutated dispatch copy. Nothing is ever written
# into the canonical plugin dir (2026-07-29 one-copy rule), no fixed shared
# name exists for two concurrent runs to collide on, and $TMP's own EXIT trap
# removes everything.
mk_negctrl_dir() { # <mutation-sed-program> -> stdout: mutated dispatch path
  local _dir _f _b _mut="$1"
  _dir="$(mktemp -d "${TMP}/negctrl.XXXXXX")"
  for _f in "${SCRIPTS_ROOT}"/*; do
    [[ -e "${_f}" ]] || continue
    _b="$(basename "${_f}")"
    [[ "${_b}" == "leadv2-dispatch-code.sh" ]] && continue
    ln -s "${_f}" "${_dir}/${_b}"
  done
  sed "${_mut}" "$DISPATCH_BIN" > "${_dir}/leadv2-dispatch-code.sh"
  printf '%s' "${_dir}/leadv2-dispatch-code.sh"
}

# ── (d) NEGATIVE CONTROL — RUN RED (mission test d) ─────────────────────────
# Remove the win-terminal telemetry call from a throwaway copy, re-run the
# EXACT win probe against the copy, and require the (a) assertions to go RED:
# no journal line AND no CSV row. If either survives, (a) was tautological.
NEGCTRL="$(mk_negctrl_dir 's/^      _model_select_telemetry win worker_spawned "${candidate}"$/      : # fp06-negctl: win telemetry removed/')"
if grep -q 'fp06-negctl' "$NEGCTRL" && ! grep -q '^      _model_select_telemetry win' "$NEGCTRL"; then
  pass "(negative-control) telemetry call removed from a throwaway dispatch copy"
else
  fail "(negative-control) mutation did not land — control is void"
fi
if [[ -L "$(dirname "$NEGCTRL")/lib" && -f "$NEGCTRL" && ! -L "$NEGCTRL" ]]; then
  pass "(negative-control) copy lives in a \$TMP mirror with symlinked siblings (H3)"
else
  fail "(negative-control) mirror dir shape wrong (H3)"
fi
bash -n "$NEGCTRL" || { fail "(negative-control) mutated copy fails bash -n"; exit 1; }
REPO3="$TMP/repo3"; mk_repo "$REPO3"
neg_out="$(run_dispatch "$REPO3" "$TMP/freepool-win-stub.sh" neg "$NEGCTRL")"
printf '%s\n' "$neg_out" > "$TMP/neg-out.log"
neg_csv="$REPO3/docs/leadv2/model-select-telemetry.csv"
neg_red=0
printf '%s\n' "$neg_out" | grep -q 'model_select_telemetry' || neg_red=$((neg_red + 1))  # (a) journal assertion goes red
[[ ! -f "$neg_csv" ]] && neg_red=$((neg_red + 1))                                      # (b) CSV assertion goes red
if [[ "$neg_red" -eq 2 ]]; then
  pass "(negative-control) with emission removed, (a)+(b) run RED: no journal line, no CSV"
else
  fail "(negative-control) telemetry survived the mutation — (a)/(b) not load-bearing (log: $TMP/neg-out.log; csv: ${neg_csv})"
fi
# the mutated copy still WINS the dispatch itself (telemetry removal must not
# change the outcome) -- proves the control neutralized telemetry, not spawning
if printf '%s\n' "$neg_out" | grep -q 'route_resolved by=router router=arbiter model=freepool'; then
  pass "(negative-control) mutated copy still spawns freepool (only telemetry is gone)"
else
  fail "(negative-control) mutation broke the dispatch itself, control is invalid (log: $TMP/neg-out.log)"
fi

# ── (e) H1: fallback row names the FINAL arm/model ──────────────────────────
# glm healthy (30%) -> arbiter chain glm-flash,freepool,glm, pick glm-flash
# (model=glm-5.3-flash). glm-flash launcher dies with no refusal marker ->
# route_fallback -> freepool (win stub) confirms. The row MUST read
# arm=freepool model=freepool fallback_depth=1 — naming glm-5.3-flash here
# is exactly the round-1 H1 lie (the dataset said the LOSING model produced
# the diff).
REPO4="$TMP/repo4"; mk_repo "$REPO4"
fb_out="$(FP06_QUOTA="$GLM_LIVE" FP06_GLM_BIN="$TMP/freepool-fail-stub.sh" \
  run_dispatch "$REPO4" "$TMP/freepool-win-stub.sh" fb)"
printf '%s\n' "$fb_out" > "$TMP/fb-out.log"
fb_line="$(printf '%s\n' "$fb_out" | grep 'model_select_telemetry task=' | tail -1)"
one_row "(e) H1 fallback" "$fb_out" "terminal=win cause=worker_spawned"
if printf '%s' "$fb_line" | grep -q 'arm=freepool model=freepool fallback_depth=1'; then
  pass "(e) H1: row names the FINAL executing arm/model (freepool, not the arbiter pick)"
else
  fail "(e) H1: row does not name the final arm/model (line: '${fb_line}'; log: $TMP/fb-out.log)"
fi
if printf '%s' "$fb_line" | grep -q 'glm-5.3-flash'; then
  fail "(e) H1: row carries the REFUSED arm's model (round-1 defect alive; line: '${fb_line}')"
else
  pass "(e) H1: refused arm's model absent from the row"
fi
if printf '%s\n' "$fb_out" | grep -q 'route_fallback from=glm-flash to=freepool'; then
  pass "(e) H1: probe really exercised a route_fallback"
else
  fail "(e) H1: no route_fallback in probe — probe is void (log: $TMP/fb-out.log)"
fi
fb_csv="$REPO4/docs/leadv2/model-select-telemetry.csv"
if tail -1 "$fb_csv" 2>/dev/null | grep -qE ',freepool,freepool,1,(applied|none),[0-9]+,win,worker_spawned$'; then
  pass "(e) H1: CSV row carries arm=freepool model=freepool fallback_depth=1"
else
  fail "(e) H1: CSV row wrong ($(tail -1 "$fb_csv" 2>/dev/null))"
fi

# ── (f) H1 NEGATIVE CONTROL — RUN RED ───────────────────────────────────────
# Mutate the per-candidate re-stamp back to the round-1 shape (arbiter's
# model wins on EVERY iteration), re-run the EXACT (e) probe, and require the
# pre-fix lie to reappear: arm=freepool model=glm-5.3-flash. If it does not,
# (e) was not actually testing the re-stamp.
NEGCTRL_H1="$(mk_negctrl_dir 's/^      _MS_MODEL="${candidate}"$/      _MS_MODEL="${_arb_model:-${candidate}}" # fp06-negctl-h1: arbiter model wins everywhere/')"
if grep -q 'fp06-negctl-h1' "$NEGCTRL_H1"; then
  pass "(negative-control H1) per-candidate re-stamp mutated back to round-1 shape"
else
  fail "(negative-control H1) mutation did not land — control is void"
fi
bash -n "$NEGCTRL_H1" || { fail "(negative-control H1) mutated copy fails bash -n"; }
REPO5="$TMP/repo5"; mk_repo "$REPO5"
negh1_out="$(FP06_QUOTA="$GLM_LIVE" FP06_GLM_BIN="$TMP/freepool-fail-stub.sh" \
  run_dispatch "$REPO5" "$TMP/freepool-win-stub.sh" negh1 "$NEGCTRL_H1")"
printf '%s\n' "$negh1_out" > "$TMP/negh1-out.log"
negh1_line="$(printf '%s\n' "$negh1_out" | grep 'model_select_telemetry task=' | tail -1)"
if printf '%s' "$negh1_line" | grep -q 'arm=freepool model=glm-5.3-flash'; then
  pass "(negative-control H1) round-1 lie reproduced under mutation — (e) is load-bearing"
else
  fail "(negative-control H1) mutation did not reproduce the lie — (e) may be tautological (line: '${negh1_line}'; log: $TMP/negh1-out.log)"
fi
if printf '%s\n' "$negh1_out" | grep -q 'route_fallback from=glm-flash to=freepool'; then
  pass "(negative-control H1) mutated copy still exercises the fallback"
else
  fail "(negative-control H1) mutated copy lost the fallback — control invalid (log: $TMP/negh1-out.log)"
fi

# ── (g) H2 census: one row per refusal terminal ─────────────────────────────
# Fake router_v2 dependency chain (shape cribbed from
# test-router-v2-retired-arm.sh): judge needs the v2 estimate vocabulary,
# bandit is fail-open, rv2 answers filter/resolve.
cat > "$TMP/v2-judge.sh" <<'JEOF'
#!/usr/bin/env bash
printf '%s\n' '{"work_kind":"build","duration_class":"short","complexity":"simple"}'
JEOF
chmod +x "$TMP/v2-judge.sh"
cat > "$TMP/v2-bandit.sh" <<'JEOF'
#!/usr/bin/env bash
printf '%s\n' 'samples={}'
JEOF
chmod +x "$TMP/v2-bandit.sh"
# <path> <resolve-output...>: filter echoes a fixed eligible list; resolve is
# per-probe (v2 initial needs arm=/eligible=; census sites need --chain rc3).
mk_fake_rv2() { # <path> <filter-eligible> <resolve-output-file>
  local path="$1" elig="$2" resout="$3"
  cat > "$path" <<SH
#!/usr/bin/env bash
case "\${1:-}" in
  filter)  printf 'eligible=${elig}\nfiltered=[]\n' ;;
  resolve) cat "${resout}" ;;
  *) exit 1 ;;
esac
SH
  chmod +x "$path"
}

# (g1) all_arms_exhausted — v2 resolver hands back an EMPTY chain.
printf 'arm=freepool\nrule=t\nreason=t\neligible=\ncodex_quota_blocked=0\n' > "$TMP/rv2-empty.txt"
mk_fake_rv2 "$TMP/rv2-empty.sh" "" "$TMP/rv2-empty.txt"
REPO6="$TMP/repo6"; mk_repo "$REPO6"
export LEADV2_ROUTER_V2_BIN="$TMP/rv2-empty.sh" LEADV2_ROUTE_BANDIT_BIN="$TMP/v2-bandit.sh"
g1_out="$(FP06_ROUTER_V2=1 FP06_JUDGE_BIN="$TMP/v2-judge.sh" run_dispatch "$REPO6" "$TMP/freepool-win-stub.sh" g1)"
printf '%s\n' "$g1_out" > "$TMP/g1-out.log"
one_row "(g1) v2 empty chain" "$g1_out" "terminal=fail cause=all_arms_exhausted"
if printf '%s\n' "$g1_out" | grep -q 'dispatch_rolled_back reason=all_arms_exhausted task=.* router=v2'; then
  pass "(g1) probe hit the v2 empty-chain terminal itself"
else
  fail "(g1) probe did not hit the expected terminal (log: $TMP/g1-out.log)"
fi

# (g2) all_arms_not_dispatchable_v2 — v2 eligible carries only a retired id.
printf 'arm=kimi\nrule=t\nreason=t\neligible=kimi\ncodex_quota_blocked=0\n' > "$TMP/rv2-kimi.txt"
mk_fake_rv2 "$TMP/rv2-kimi.sh" "kimi" "$TMP/rv2-kimi.txt"
REPO7="$TMP/repo7"; mk_repo "$REPO7"
export LEADV2_ROUTER_V2_BIN="$TMP/rv2-kimi.sh"
g2_out="$(FP06_ROUTER_V2=1 FP06_JUDGE_BIN="$TMP/v2-judge.sh" run_dispatch "$REPO7" "$TMP/freepool-win-stub.sh" g2)"
printf '%s\n' "$g2_out" > "$TMP/g2-out.log"
one_row "(g2) v2 not-dispatchable" "$g2_out" "terminal=fail cause=all_arms_not_dispatchable_v2"
if printf '%s\n' "$g2_out" | grep -q 'arm_dropped_not_dispatchable arm=kimi'; then
  pass "(g2) probe really dropped the retired arm"
else
  fail "(g2) retired-arm drop missing (log: $TMP/g2-out.log)"
fi

# (g3) all_arms_quota_locked — every chain arm's provider carries a live
# lockout record, so the quota precheck benches the whole chain.
LOCKDIR="$TMP/lockouts"; mkdir -p "$LOCKDIR"
python3 - "$LOCKDIR" <<'PY'
import json, os, sys, time
d = sys.argv[1]
for prov in ("freepool", "glm", "codex", "anthropic"):
    json.dump({"locked_until_epoch": int(time.time()) + 3600, "class": "test"},
              open(os.path.join(d, "quota-lockout-%s.json" % prov), "w"))
PY
REPO8="$TMP/repo8"; mk_repo "$REPO8"
export LEADV2_QUOTA_LOCKOUT_DIR="$LOCKDIR"
g3_out="$(run_dispatch "$REPO8" "$TMP/freepool-win-stub.sh" g3)"
printf '%s\n' "$g3_out" > "$TMP/g3-out.log"
one_row "(g3) quota-locked" "$g3_out" "terminal=fail cause=all_arms_quota_locked"
if printf '%s\n' "$g3_out" | grep -q 'quota_precheck_skip model=freepool'; then
  pass "(g3) probe really benched freepool at the precheck"
else
  fail "(g3) precheck skip line missing (log: $TMP/g3-out.log)"
fi

# (g4) all_arms_excluded — operator override removes the whole chain.
# (lockouts unset: g4 must reach the exclusion block, not the precheck)
unset LEADV2_QUOTA_LOCKOUT_DIR
REPO9="$TMP/repo9"; mk_repo "$REPO9"
g4_out="$(FP06_EXCLUDED="freepool,glm,glm-flash,codex,sonnet" run_dispatch "$REPO9" "$TMP/freepool-win-stub.sh" g4)"
printf '%s\n' "$g4_out" > "$TMP/g4-out.log"
one_row "(g4) excluded" "$g4_out" "terminal=fail cause=all_arms_excluded"
if printf '%s\n' "$g4_out" | grep -q 'arm_excluded by=router model=freepool'; then
  pass "(g4) probe really excluded freepool"
else
  fail "(g4) arm_excluded line missing (log: $TMP/g4-out.log)"
fi

# (g5) all_arms_capped — the arbiter itself hard-refuses (freepool gate down
# + every paid provider capped). Covers the one refusal terminal that WAS
# instrumented before the census but had no test.
REPO10="$TMP/repo10"; mk_repo "$REPO10"
g5_out="$(ROUTE_TEST_FREE_RC=1 run_dispatch "$REPO10" "$TMP/freepool-win-stub.sh" g5)"
printf '%s\n' "$g5_out" > "$TMP/g5-out.log"
one_row "(g5) arbiter all-capped" "$g5_out" "terminal=fail cause=all_arms_capped"
if printf '%s\n' "$g5_out" | grep -q 'route_resolved by=arbiter role=worker arm=refuse'; then
  pass "(g5) probe really hit the arbiter refusal"
else
  fail "(g5) arbiter refusal line missing (log: $TMP/g5-out.log)"
fi

# (g6) all_arms_exhausted_quota — ROUTER_V2 quota-filter re-resolve over the
# arbiter-routed chain refuses (rv2 resolve --chain exits 3). Initial resolve
# still must succeed so the chain is non-empty when the filter runs.
cat > "$TMP/rv2-qf.sh" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  filter)  printf 'eligible=freepool\nfiltered=[]\n' ;;
  resolve)
    if [[ "${2:-}" == "--chain" ]]; then exit 3; fi
    printf 'arm=freepool\nrule=t\nreason=t\neligible=freepool\nordered=freepool\ncodex_quota_blocked=0\n'
    ;;
  *) exit 1 ;;
esac
SH
chmod +x "$TMP/rv2-qf.sh"
REPO11="$TMP/repo11"; mk_repo "$REPO11"
export LEADV2_ROUTER_V2_BIN="$TMP/rv2-qf.sh"
unset LEADV2_QUOTA_LOCKOUT_DIR   # g6 must reach the rv2 quota filter, not the precheck
g6_out="$(FP06_ROUTER_V2=1 FP06_JUDGE_BIN="$TMP/v2-judge.sh" run_dispatch "$REPO11" "$TMP/freepool-win-stub.sh" g6)"
printf '%s\n' "$g6_out" > "$TMP/g6-out.log"
one_row "(g6) quota-filter exhaustion" "$g6_out" "terminal=fail cause=all_arms_exhausted_quota"
if printf '%s\n' "$g6_out" | grep -q 'dispatch_rolled_back reason=all_arms_exhausted task=.* by=router_v2'; then
  pass "(g6) probe hit the router_v2 exhaustion terminal itself"
else
  fail "(g6) expected terminal not reached (log: $TMP/g6-out.log)"
fi
unset LEADV2_ROUTER_V2_BIN LEADV2_ROUTE_BANDIT_BIN LEADV2_QUOTA_LOCKOUT_DIR

# ── (h) M2: a space inside an LLM-derived field cannot corrupt the row ──────
mk_judge "$TMP/judge-space.sh" "big build"
REPO12="$TMP/repo12"; mk_repo "$REPO12"
h_out="$(FP06_JUDGE_BIN="$TMP/judge-space.sh" run_dispatch "$REPO12" "$TMP/freepool-fail-stub.sh" h)"
printf '%s\n' "$h_out" > "$TMP/h-out.log"
h_line="$(printf '%s\n' "$h_out" | grep 'model_select_telemetry task=' | tail -1)"
if printf '%s' "$h_line" | grep -q 'work_kind=big_build '; then
  pass "(h) M2: space folded to '_' in the journal row (work_kind=big_build)"
else
  fail "(h) M2: journal row not sanitized (line: '${h_line}')"
fi
h_csv="$REPO12/docs/leadv2/model-select-telemetry.csv"
h_ncols="$(tail -1 "$h_csv" 2>/dev/null | awk -F',' '{print NF}')"
if [[ "${h_ncols:-0}" -eq 11 ]]; then
  pass "(h) M2: CSV row still has exactly 11 columns"
else
  fail "(h) M2: CSV column count wrong (${h_ncols:-missing}; row: $(tail -1 "$h_csv" 2>/dev/null))"
fi
mk_judge "$TMP/judge-comma.sh" 'build,urgent'
REPO12_COMMA="$TMP/repo12-comma"; mk_repo "$REPO12_COMMA"
h_comma_out="$(FP06_JUDGE_BIN="$TMP/judge-comma.sh" run_dispatch "$REPO12_COMMA" "$TMP/freepool-fail-stub.sh" hcomma)"
printf '%s\n' "$h_comma_out" > "$TMP/h-comma-out.log"
h_comma_csv="$REPO12_COMMA/docs/leadv2/model-select-telemetry.csv"
h_comma_ncols="$(tail -1 "$h_comma_csv" 2>/dev/null | awk -F',' '{print NF}')"
if [[ "${h_comma_ncols:-0}" -eq 11 ]]; then
  pass "(h) M2: comma value still yields exactly 11 CSV columns"
else
  fail "(h) M2: comma value split the CSV row (${h_comma_ncols:-missing}; row: $(tail -1 "$h_comma_csv" 2>/dev/null))"
fi
mk_judge "$TMP/judge-formula.sh" '=formula'
REPO12_FORMULA="$TMP/repo12-formula"; mk_repo "$REPO12_FORMULA"
h_formula_out="$(FP06_JUDGE_BIN="$TMP/judge-formula.sh" run_dispatch "$REPO12_FORMULA" "$TMP/freepool-fail-stub.sh" hformula)"
printf '%s\n' "$h_formula_out" > "$TMP/h-formula-out.log"
h_formula_csv="$REPO12_FORMULA/docs/leadv2/model-select-telemetry.csv"
h_formula_cell="$(tail -1 "$h_formula_csv" 2>/dev/null | awk -F',' '{print $4}')"
if [[ "${h_formula_cell}" != =* ]]; then
  pass "(h) M2: formula-leading CSV cell is neutralized"
else
  fail "(h) M2: formula-leading CSV cell remains unsafe (${h_formula_cell})"
fi

# ── (i) H4: over-cap CSV is rotated, header + newest rows kept ──────────────
REPO13="$TMP/repo13"; mk_repo "$REPO13"
i_csv="$REPO13/docs/leadv2/model-select-telemetry.csv"
{ printf 'task,role,class,work_kind,arm,model,fallback_depth,floor,spawn_to_terminal_s,terminal,cause\n'
  seq 1 6000 | sed 's/^/oldrow/' ; } > "$i_csv"
i_out="$(FP06_JUDGE_BIN="$TMP/judge-light.sh" run_dispatch "$REPO13" "$TMP/freepool-fail-stub.sh" i)"
printf '%s\n' "$i_out" > "$TMP/i-out.log"
i_lines="$(wc -l < "$i_csv" 2>/dev/null | tr -d ' ')"
if [[ "${i_lines:-0}" -eq 5000 ]]; then
  pass "(i) H4: over-cap CSV rotated to exactly the cap (5000 lines)"
else
  fail "(i) H4: rotation wrong (${i_lines:-missing} lines)"
fi
if [[ "$(head -1 "$i_csv" 2>/dev/null)" == task,role,class,work_kind,arm,model,fallback_depth,floor,spawn_to_terminal_s,terminal,cause ]]; then
  pass "(i) H4: header survived rotation"
else
  fail "(i) H4: header lost ($(head -1 "$i_csv" 2>/dev/null))"
fi
if tail -1 "$i_csv" 2>/dev/null | grep -qE ',fail,all_arms_unavailable$'; then
  pass "(i) H4: newest row kept after rotation"
else
  fail "(i) H4: newest row lost ($(tail -1 "$i_csv" 2>/dev/null))"
fi

printf '\n=== %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
