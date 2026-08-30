#!/usr/bin/env bash
# T13 slice1 fix-round: executable regression checks plus mutation controls.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
GUARD="${ROOT}/scripts/codex-guard.sh"
LANE_GUARD="${ROOT}/scripts/lib/leadv2-lane-guard.sh"
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
# R5/F2: a MALFORMED startedAt (not missing -- a garbage string) must hit the
# except-branch fail-open, same as the missing-timestamp case, never crash
# into a false "old enough" verdict.
guard_case_malformed_age() { # <script>
  local s="$1" p="${TMP}/malformed.json"
  printf '{"id":"garbage-job","status":"running","pid":999999,"startedAt":"not-a-real-timestamp"}\n' > "$p"
  extract_guard "$s" || return 2
  mark_job_failed "$p" dead 0 30 garbage-job
  grep -q '"status":"running"' "$p"
}
# R2/R5: test-only monkeypatch INSIDE this test file (never a prod hook) --
# builds a scratch copy of the guard with a seam injected right after the
# FIRST fd-based read computes data/original_stat, then that seam simulates
# a concurrent writer replacing the record (new inode via os.replace,
# T13_TEST_SWAP_JSON) between our two reads.
cas_inject_swap_seam() { # <source-script> <dest-script>
  perl -0pe 's/(    data = json\.loads\(raw\)\nexcept Exception:\n    sys\.exit\(0\)\n)/$1\nif os.environ.get("T13_TEST_SWAP_JSON"):\n    _swp = path + ".swaptmp"\n    with open(_swp, "w") as _swf:\n        _swf.write(os.environ["T13_TEST_SWAP_JSON"])\n    os.replace(_swp, path)\n/' "$1" > "$2" && chmod +x "$2"
}
# R5/F1: id-branch control -- a record whose `id` no longer matches what the
# caller is watching must never be mutated, regardless of generation.
guard_case_cas_id() { # <script>
  local base="$1" p="${TMP}/cas_id.json" s="${TMP}/cas_id_guard.sh"
  cas_inject_swap_seam "$base" "$s" || return 2
  write_job "$p" old "2020-01-01T00:00:00Z"
  extract_guard "$s" || return 2
  T13_TEST_SWAP_JSON='{"id":"new","status":"running","pid":999999,"startedAt":"2020-01-01T00:00:00Z"}' mark_job_failed "$p" dead 0 30 old
  grep -q '"id":"new"' "$p" && grep -q '"status":"running"' "$p"
}
# R5/F1: generation-branch control -- SAME id survives the swap, but a
# concurrent replacement still changed the file's identity (inode/mtime).
# The id check alone would let this through; only the fd-generation compare
# catches it. Isolates the exact TOCTOU this round exists to close.
guard_case_cas_gen() { # <script>
  local base="$1" p="${TMP}/cas_gen.json" s="${TMP}/cas_gen_guard.sh"
  cas_inject_swap_seam "$base" "$s" || return 2
  write_job "$p" old "2020-01-01T00:00:00Z"
  extract_guard "$s" || return 2
  T13_TEST_SWAP_JSON='{"id":"old","status":"running","pid":999999,"startedAt":"2020-01-01T00:00:00Z"}' mark_job_failed "$p" dead 0 30 old
  grep -q '"status":"running"' "$p"
}

extract_close() { # <script>
  unset -f _pc_norm_write _pc_drop_bootstrap_dirt _pc_lane_dirty 2>/dev/null || true
  unset _PC_PORCELAIN_EXCLUDE_RE _PC_BOOTSTRAP_PREFIX_RE 2>/dev/null || true
  source "$1" || return 2
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
run_pair "guard-malformed-age" guard_case_malformed_age 's/print\("WARN: mark_job_failed age malformed; preserving job", file=sys\.stderr\)\n[ ]*sys\.exit\(0\)/data["startedAt"]="2020-01-01T00:00:00Z"/' "$GUARD"
run_pair "guard-cas-id-swap" guard_case_cas_id 's/if \(current\.get\("id"\) != data\.get\("id"\) or/if False and (current.get("id") != data.get("id") or/' "$GUARD"
# T13-SLICE1 R1/R5: the id check alone (mutation above) cannot prove the
# fd-generation compare does anything -- this pair keeps id matching and
# neuters ONLY the (st_ino, st_mtime_ns) half of the OR, so it is red iff the
# generation compare is the thing actually stopping the swapped write.
run_pair "guard-cas-gen-swap" guard_case_cas_gen 's/\(current_stat\.st_ino, current_stat\.st_mtime_ns\) !=\n        \(original_stat\.st_ino, original_stat\.st_mtime_ns\)/False/' "$GUARD"

# Sole tasks.yaml is real work; with another edit it is injector noise. A .bak
# path must always survive the exact path matcher.
filter_case "$LANE_GUARD" '' ' M docs/tasks.yaml\n' 'docs/tasks.yaml' '' && pass "tasks-only-refusable" || fail "tasks-only-refusable"
filter_case "$LANE_GUARD" '' ' M docs/tasks.yaml\n M src/real.sh\n' 'src/real.sh' 'docs/tasks.yaml' && pass "tasks-noise-with-real-work" || fail "tasks-noise-with-real-work"
# The anchoring only becomes observable when real other work is also present:
# a sole .bak edit passes through the has_other_work==0 fallback either way
# (glob or exact match), so that shape can't distinguish the fix from the bug.
filter_case "$LANE_GUARD" '' ' M docs/tasks.yaml.bak\n M src/real.sh\n' 'docs/tasks.yaml.bak' '' && pass "tasks-bak-anchored" || fail "tasks-bak-anchored"
mutate "$LANE_GUARD" "${TMP}/close.mutant" 's/if \[\[ "\$\{path\}" == "docs\/tasks\.yaml" \]\]; then/if [[ "\$\{path\}" == docs\/tasks.yaml* ]]; then/'
filter_case "${TMP}/close.mutant" '' ' M docs/tasks.yaml.bak\n M src/real.sh\n' 'docs/tasks.yaml.bak' ''; rc=$?
[[ $rc -ne 0 ]] && pass "tasks-bak negative-control red" || fail "tasks-bak negative control stayed green"

# R5/F5: behavioral proof, not a grep -- extract the real function, stub
# every collaborator atomic_dispatch_reserve_spawn_confirm calls, drive it
# through the exit-76 + permanent-sentinel branch, and assert BOTH that no
# respawn was attempted (dispatch_abort, the respawn trigger, never runs)
# AND that the function's own rc is a FAILURE, not 0 -- rc=0 previously told
# the caller this was a confirmed live spawn and let the close flow run
# against a dead worker (R3).
extract_atomic_confirm() { # <script>
  unset -f atomic_dispatch_reserve_spawn_confirm 2>/dev/null || true
  local start end
  start="$(grep -n '^atomic_dispatch_reserve_spawn_confirm() {' "$1" | head -1 | cut -d: -f1)"
  [[ -n "$start" ]] || return 1
  end="$(awk -v s="$start" 'NR<s{next} {n=gsub(/\{/,"{"); m=gsub(/\}/,"}"); depth+=n-m; if(NR>=s && depth==0){print NR; exit}}' "$1")"
  [[ -n "$end" ]] || return 1
  eval "$(sed -n "${start},${end}p" "$1")" || return 1
}
dispatch_case_exit76_sentinel() { # <script> -- rc0 iff no respawn AND rc is failure
  local s="$1" abort_marker="${TMP}/abort_called"
  rm -f "$abort_marker"
  dispatch_reserve() { printf 'tok\n'; return 0; }
  spawn_worker() { printf 'worker_spawned handle=h1\n'; return 0; }
  dispatch_confirm() { return 0; }
  dispatch_abort() { : > "$abort_marker"; return 0; }
  _dispatch_normalize_handle() { printf '%s' "$2"; }
  _wait_arm_early_verdict() { return 76; }
  _arm_final_output() { printf 'GLM_PERMANENT_FAILURE_SENTINEL\n'; }
  emit() { :; }
  log() { :; }
  ACTIVE_DISPATCH_TOKEN=""
  extract_atomic_confirm "$s" || return 2
  local rc
  atomic_dispatch_reserve_spawn_confirm sig glm rule mission sig8 1 >/dev/null
  rc=$?
  [[ ! -e "$abort_marker" && ${rc} -ne 0 ]]
}
run_pair "exit76-permanent-sentinel-no-respawn-and-rc-failure" dispatch_case_exit76_sentinel 's/no respawn\)"\n        return 5/no respawn)"\n        return 0/' "$DISPATCH"

# R4 final-verify finding: a suffixed identifier (SENTINEL-retry) must NOT be
# treated as the sentinel. Green iff the suppress path (rc=5) is NOT taken for
# the suffixed spelling; the negative control reverts the token-exact match to
# the old word-bounded grep -qw, which wrongly matches the suffix and goes rc=5.
dispatch_case_exit76_sentinel_suffix() { # <script> -- rc0 iff suffixed sentinel does NOT suppress
  local s="$1"
  dispatch_reserve() { printf 'tok\n'; return 0; }
  spawn_worker() { printf 'worker_spawned handle=h1\n'; return 0; }
  dispatch_confirm() { return 0; }
  dispatch_abort() { return 0; }
  _dispatch_normalize_handle() { printf '%s' "$2"; }
  _wait_arm_early_verdict() { return 76; }
  _arm_final_output() { printf 'GLM_PERMANENT_FAILURE_SENTINEL-retry\n'; }
  emit() { :; }
  log() { :; }
  ACTIVE_DISPATCH_TOKEN=""
  extract_atomic_confirm "$s" || return 2
  local rc
  atomic_dispatch_reserve_spawn_confirm sig glm rule mission sig8 1 >/dev/null
  rc=$?
  [[ ${rc} -ne 5 ]]
}
run_pair "exit76-sentinel-suffix-not-suppressed" dispatch_case_exit76_sentinel_suffix 's/grep -Eq \x27[^\x27]*GLM_PERMANENT_FAILURE_SENTINEL[^\x27]*\x27/grep -qw \x27GLM_PERMANENT_FAILURE_SENTINEL\x27/' "$DISPATCH"

printf '[TEST] RESULTS PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
