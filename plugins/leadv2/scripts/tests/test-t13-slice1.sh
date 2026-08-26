#!/usr/bin/env bash
# T13 slice1 fix-round: executable regression checks plus mutation controls.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
GUARD="${ROOT}/scripts/codex-guard.sh"
CLOSE="${ROOT}/scripts/leadv2-dispatch-product-close.sh"
DISPATCH="${ROOT}/scripts/leadv2-dispatch-code.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/t13-slice1.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

extract_guard() { # <script>
  unset -f log read_job_age_sec acquire_job_lock release_job_lock mark_job_failed stat_mtime 2>/dev/null || true
  log() { printf '[guard-test] %s\n' "$*" >&2; }
  LOG_FILE="${TMP}/guard.log"; JOB_ID="test-job"; CWD="${TMP}"; STATE_ROOT="${TMP}/state"
  JOB_LOCK_MAX_WAIT_SEC=1; JOB_LOCK_STALE_SEC=60
  local end
  end="$(grep -n '^STATUS=""' "$1" | head -1 | cut -d: -f1)"
  [[ -n "$end" ]] || return 1
  eval "$(sed -n "98,$((end - 1))p" "$1")" || return 1
}
write_job() { # <path> <id> <timestamp-or-empty>
  local p="$1" id="$2" ts="$3"
  if [[ -n "$ts" ]]; then
    printf '{"id":"%s","status":"running","pid":999999,"startedAt":"%s"}\n' "$id" "$ts" > "$p"
  else
    printf '{"id":"%s","status":"running","pid":999999}\n' "$id" > "$p"
  fi
}
guard_case_young() { # <script> expected unchanged=1
  local s="$1" p="${TMP}/young.json"
  write_job "$p" young "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  extract_guard "$s" || return 2
  mark_job_failed "$p" dead 0 30 young
  grep -q '"status":"running"' "$p"
}
guard_case_unknown() { # <script>
  local s="$1" p="${TMP}/unknown.json"
  write_job "$p" unknown ""
  extract_guard "$s" || return 2
  mark_job_failed "$p" dead 0 30 unknown
  grep -q '"status":"running"' "$p"
}
guard_case_cas() { # <script>
  local s="$1" p="${TMP}/cas.json" hook="${TMP}/swap.sh"
  write_job "$p" old "2020-01-01T00:00:00Z"
  printf '#!/usr/bin/env bash\nprintf %%s '\''{"id":"new","status":"running","pid":999999}'\'' > %q\n' "$p" > "$hook"
  chmod +x "$hook"
  extract_guard "$s" || return 2
  CODEX_GUARD_TEST_BEFORE_REPLACE_HOOK="$hook" mark_job_failed "$p" dead 0 30 old
  grep -q '"id":"new"' "$p" && grep -q '"status":"running"' "$p"
}

extract_close() { # <script>
  unset -f _pc_norm_write _pc_drop_bootstrap_dirt _pc_lane_dirty 2>/dev/null || true
  unset _PC_PORCELAIN_EXCLUDE_RE _PC_BOOTSTRAP_PREFIX_RE 2>/dev/null || true
  local a b norm
  a="$(grep -n '^_PC_PORCELAIN_EXCLUDE_RE=' "$1" | head -1 | cut -d: -f1)"
  b="$(grep -n '^_pc_phys()' "$1" | head -1 | cut -d: -f1)"
  [[ -n "$a" && -n "$b" ]] || return 2
  norm="$(sed -n '/^_pc_norm_write() {/,/^}/p' "$1")"
  eval "$(sed -n "${a},$((b - 1))p" "$1")
${norm}" || return 2
}
filter_case() { # <script> <writes> <porcelain> <required> <forbidden>
  local s="$1" writes="$2" in="$3" required="$4" forbidden="$5" out
  WRITES_CSV="$writes"; extract_close "$s" || return 2
  out="$(printf '%b' "$in" | grep -vE "${_PC_PORCELAIN_EXCLUDE_RE}" | _pc_drop_bootstrap_dirt "$TMP")"
  [[ -z "$required" || "$out" == *"$required"* ]] || return 1
  [[ -z "$forbidden" || "$out" != *"$forbidden"* ]] || return 1
}

mutate() { # <source> <dest> <perl expression>
  cp "$1" "$2" || return 1
  perl -0pi -e "$3" "$2"
}
run_pair() { # <name> <function> <mutation>
  local name="$1" fn="$2" expr="$3" green red mutant
  mutant="${TMP}/${name}.mutant"
  "$fn" "$4"; green=$?
  mutate "$4" "$mutant" "$expr" || { fail "$name mutation setup"; return; }
  "$fn" "$mutant"; red=$?
  [[ $green -eq 0 ]] && pass "$name green" || fail "$name green rc=$green"
  [[ $red -ne 0 ]] && pass "$name negative-control red" || fail "$name negative control stayed green"
}

bash -n "$GUARD" && bash -n "$CLOSE" && bash -n "$DISPATCH" && pass "syntax" || fail "syntax"
run_pair "guard-young" guard_case_young 's/if age < grace_sec:/if False:/' "$GUARD"
run_pair "guard-unknown-age" guard_case_unknown 's/print\("WARN: mark_job_failed age missing timestamp; preserving job", file=sys\.stderr\)\n        sys\.exit\(0\)/data["startedAt"]="2020-01-01T00:00:00Z"/' "$GUARD"
run_pair "guard-cas-id-swap" guard_case_cas 's/if \(current\.get\("id"\) != data\.get\("id"\) or/if False and (current.get("id") != data.get("id") or/' "$GUARD"

# Sole tasks.yaml is real work; with another edit it is injector noise. A .bak
# path must always survive the exact path matcher.
filter_case "$CLOSE" '' ' M docs/tasks.yaml\n' 'docs/tasks.yaml' '' && pass "tasks-only-refusable" || fail "tasks-only-refusable"
filter_case "$CLOSE" '' ' M docs/tasks.yaml\n M src/real.sh\n' 'src/real.sh' 'docs/tasks.yaml' && pass "tasks-noise-with-real-work" || fail "tasks-noise-with-real-work"
# The anchoring only becomes observable when real other work is also present:
# a sole .bak edit passes through the has_other_work==0 fallback either way
# (glob or exact match), so that shape can't distinguish the fix from the bug.
filter_case "$CLOSE" '' ' M docs/tasks.yaml.bak\n M src/real.sh\n' 'docs/tasks.yaml.bak' '' && pass "tasks-bak-anchored" || fail "tasks-bak-anchored"
mutate "$CLOSE" "${TMP}/close.mutant" 's/if \[\[ "\$\{path\}" == "docs\/tasks\.yaml" \]\]; then/if [[ "\$\{path\}" == docs\/tasks.yaml* ]]; then/'
filter_case "${TMP}/close.mutant" '' ' M docs/tasks.yaml.bak\n M src/real.sh\n' 'docs/tasks.yaml.bak' ''; rc=$?
[[ $rc -ne 0 ]] && pass "tasks-bak negative-control red" || fail "tasks-bak negative control stayed green"

# Consumer proof: the permanent marker is tested before the exit-76 spill and
# journals suppression; deleting the guard makes this structural probe red.
if awk '/if \[\[ \$\{_early_rc\} -eq 76 \]\]; then/{p=1} p{print} /elif \[\[ \$\{_early_rc\} -eq 78 \]\]; then/{exit}' "$DISPATCH" | grep -q 'route_fallback_suppressed.*permanent_sentinel'; then pass "exit76 permanent suppression"; else fail "exit76 permanent suppression"; fi
mutate "$DISPATCH" "${TMP}/dispatch.mutant" 's/emit decision "route_fallback_suppressed[^\n]*"/# removed permanent suppression/'
if ! awk '/if \[\[ \$\{_early_rc\} -eq 76 \]\]; then/{p=1} p{print} /elif \[\[ \$\{_early_rc\} -eq 78 \]\]; then/{exit}' "${TMP}/dispatch.mutant" | grep -q 'route_fallback_suppressed.*permanent_sentinel'; then pass "exit76 negative-control red"; else fail "exit76 negative control stayed green"; fi

printf '[TEST] RESULTS PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
