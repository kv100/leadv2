#!/usr/bin/env bash
# lib/leadv2-builder-selfcheck.sh — BUILDER-SELFCHECK-GATE-01
#
# lv2_selfcheck_run <diff_file> <diff_root> <project_root> <out_md> runs a mechanical
# falsification set (bash -n, py_compile, changed-scope suites) over the files a lane's
# diff touched, and writes a GREEN/RED/DEGRADED verdict artifact to <out_md>. Purely a
# reader: no `emit`, no `_dl_note`, no `exit` -- every ledger/terminal side effect stays
# in the caller (leadv2-dispatch-product-close.sh) so this file is unit-testable
# standalone.
#
# stdout: comma-joined names of failed checks (empty unless RED).
# rc: 0 GREEN, 1 RED, 2 DEGRADED (no check could run at all -- checks==0).
#
# Round 2 (BUILDER-SELFCHECK-GATE-01 R2): the suite check NEVER invokes a repo-level
# runner (tests/run-all.sh) -- that runner is what reaches THIS gate via
# leadv2-dispatch-product-close.sh, so calling it back created unbounded recursion
# (C1). Suite discovery is diff-scoped stem matching only, resolved from the LANE tree
# (diff_root), never from the plugin tree this lib lives in (M3). Every suite spawn
# carries a flag+depth belt-and-braces re-entry guard (decision B) and a lazy
# merge-base baseline comparison so an inherited-red suite is never blamed on the
# builder (decision D, H1).
#
# Sets on every return path (globals, this file is sourced -- no export needed):
#   LV2_SELFCHECK_CHECKS, LV2_SELFCHECK_FAILED, LV2_SELFCHECK_SKIPPED,
#   LV2_SELFCHECK_DEPTH_SKIP (0/1)
#
# Env: LEADV2_BUILDER_SELFCHECK_TESTS (auto|always|never, default auto),
#      LEADV2_BUILDER_SELFCHECK_TIMEOUT_S (default 900),
#      LEADV2_BUILDER_SELFCHECK_MAX_FILES (default 200),
#      LEADV2_BUILDER_SELFCHECK_BASELINE (default 1; 0 = treat lane red as FAIL
#        directly, no merge-base comparison),
#      LEADV2_BUILDER_SELFCHECK_DEPTH (internal, default 0 -- re-entry depth),
#      LEADV2_E2E_GATE (default 1) -- caller-set mirror of its own E2E_ON, read only in
#      `auto` mode to decide whether the suite check delegates to the e2e stage (D2).
#      LEADV2_SCOPE_DISCIPLINE (default 1, kill-switch for the SCOPE-DISCIPLINE-01
#      write-set/oversize check, C0), LEADV2_SCOPE_DISCIPLINE_MAX_FILES (default 40).
#
# Param 5 (write_set_csv, optional): the caller's already-normalised declared
# write-set (_PC_SCOPE_WRITES_CSV / LEADV2_DISPATCH_LANE_WRITES) -- feeds C0 only.
set -uo pipefail

# Portable timeout wrapper (same fallback pattern as codex-task.sh:1383-1419): stock
# macOS ships neither gtimeout nor timeout(1), so a hung suite still gets a real
# deadline via a background sleep+kill watcher, reporting 124 like timeout(1) would.
#
# R2/C2 fix: the no-gtimeout/no-timeout fallback previously forked its watcher without
# redirecting the watcher subshell's own stdout/stderr/stdin -- it inherited the fd of
# whatever command substitution called in (product-close.sh's `$( lv2_selfcheck_run )`),
# so even after `kill $watcher` the surviving `sleep` child kept the pipe's write end
# open and the caller blocked for the FULL timeout. Fix: the watcher's own I/O is fully
# detached (`>/dev/null 2>&1 </dev/null`), and `set -m` makes the child its own
# process-group leader so a `kill -TERM -"${pid}"` reaches the whole group, not just the
# top process -- a suite that forks children (e.g. bash tests/foo.sh spawning more bash)
# is fully reapable, not just its outer pid.
_lv2_selfcheck_timeout_run() { # <timeout_s> <logfile> -- <cmd...>
  local timeout_s="$1" logfile="$2"; shift 2
  [[ "${1:-}" == "--" ]] && shift
  local rc=0
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${timeout_s}" "$@" > "${logfile}" 2>&1; rc=$?
  elif command -v timeout >/dev/null 2>&1; then
    timeout "${timeout_s}" "$@" > "${logfile}" 2>&1; rc=$?
  else
    local pid watcher
    set -m
    { "$@" >"${logfile}" 2>&1 & } 2>/dev/null
    pid=$!
    set +m
    ( sleep "${timeout_s}"
      kill -0 "${pid}" 2>/dev/null || exit 0
      kill -TERM -"${pid}" 2>/dev/null || kill -TERM "${pid}" 2>/dev/null || true
      sleep 2
      kill -KILL -"${pid}" 2>/dev/null || kill -KILL "${pid}" 2>/dev/null || true
    ) >/dev/null 2>&1 </dev/null &
    watcher=$!
    wait "${pid}" 2>/dev/null; rc=$?
    kill -TERM "${watcher}" 2>/dev/null || true
    wait "${watcher}" 2>/dev/null || true
    (( rc > 128 )) && rc=124
  fi
  return "${rc}"
}

lv2_selfcheck_run() {
  local diff_file="$1" diff_root="$2" project_root="$3" out_md="$4" write_set_csv="${5:-}"
  local tests_mode="${LEADV2_BUILDER_SELFCHECK_TESTS:-auto}"
  local timeout_s="${LEADV2_BUILDER_SELFCHECK_TIMEOUT_S:-900}"
  local max_files="${LEADV2_BUILDER_SELFCHECK_MAX_FILES:-200}"
  local baseline_on="${LEADV2_BUILDER_SELFCHECK_BASELINE:-1}"
  local depth="${LEADV2_BUILDER_SELFCHECK_DEPTH:-0}"
  local _lib_dir _scripts_dir
  _lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _scripts_dir="$(cd "${_lib_dir}/.." && pwd)"

  LV2_SELFCHECK_CHECKS=0
  LV2_SELFCHECK_FAILED=0
  LV2_SELFCHECK_SKIPPED=0
  LV2_SELFCHECK_DEPTH_SKIP=0

  if [[ ! -f "${diff_file}" ]]; then
    printf 'verdict: DEGRADED\nreason: no_diff_file\nchecks: 0   failed: 0   skipped: 0\n' > "${out_md}"
    return 2
  fi

  # ── changed-path extraction: both sides of every diff file header ("+++ b/<path>"
  # and "--- a/<path>"), dropping /dev/null. Collecting only "+++" missed deletions
  # (whose new side is /dev/null) and rename SOURCES (whose old side never appears as
  # a "+++" line) -- both bypassed the C0 write-set/oversize scope check silently
  # (codex r1 HIGH, SCOPE-DISCIPLINE-01 fix-round-2).
  local line path
  local -a changed=()
  while IFS= read -r line; do
    case "${line}" in
      '+++ '*) path="${line#+++ }"; path="${path#b/}" ;;
      '--- '*) path="${line#--- }"; path="${path#a/}" ;;
      *) continue ;;
    esac
    [[ -z "${path}" || "${path}" == "/dev/null" ]] && continue
    changed+=("${path}")
  done < "${diff_file}"

  # dedupe, preserving order
  local -a dedup=()
  local p q seen
  for p in "${changed[@]:-}"; do
    [[ -z "${p}" ]] && continue
    seen=0
    for q in "${dedup[@]:-}"; do [[ "${q}" == "${p}" ]] && { seen=1; break; }; done
    (( seen )) || dedup+=("${p}")
  done

  local rows="" raws="" checks=0 failed=0 skipped=0
  local failed_names=""
  local ws_max="${LEADV2_SCOPE_DISCIPLINE_MAX_FILES:-40}"
  _selfcheck_row() { rows="${rows}| $1 | $2 | $3 |
"; }
  _selfcheck_fail_name() {
    if [[ -z "${failed_names}" ]]; then failed_names="$1"; else failed_names="${failed_names},$1"; fi
  }
  _selfcheck_raw() {
    raws="${raws}
## raw — $1 (rc=$2)
$(tail -n 40 "$3" 2>/dev/null)
"
  }

  # ── C0: SCOPE-DISCIPLINE-01 — bounce an oversized/off-write-set diff BEFORE any
  # review arm is spent (root cause: unscopable_diff x102, a sprawling diff never
  # caught until a human/review arm had already been spent on it). write_set_csv
  # (param 5) is the CALLER's already-normalised declared write-set
  # (_PC_SCOPE_WRITES_CSV / LEADV2_DISPATCH_LANE_WRITES) — empty means the caller
  # declared nothing to enforce against, so this is a pure SKIP, never a bounce.
  # LEADV2_SCOPE_DISCIPLINE=0 restores today's path (no scope check at all), same
  # kill-switch idiom as LEADV2_BUILDER_SELFCHECK.
  if [[ "${LEADV2_SCOPE_DISCIPLINE:-1}" == "0" ]]; then
    : # kill switch: zero C0 bookkeeping/output -- restores the pre-C0 path
      # byte-for-byte (no row, no skipped++, no selfcheck.md/journal footprint
      # change). Codex r1 MEDIUM: the prior "SKIP (scope_discipline_disabled)"
      # row still mutated skipped/selfcheck.md/the product-close journal even
      # with the gate off.
  elif [[ -z "${write_set_csv}" ]]; then
    _selfcheck_row "scope" "-" "SKIP (no_write_set_declared)"
    skipped=$((skipped + 1))
  else
    local -a ws_entries=() ws_off=()
    IFS=',' read -r -a ws_entries <<< "${write_set_csv}"
    local ws_e ws_p ws_in
    for ws_p in "${dedup[@]:-}"; do
      [[ -z "${ws_p}" ]] && continue
      ws_in=0
      for ws_e in "${ws_entries[@]:-}"; do
        ws_e="${ws_e%/}"
        [[ -z "${ws_e}" ]] && continue
        if [[ "${ws_p}" == "${ws_e}" || "${ws_p}" == "${ws_e}/"* ]]; then
          ws_in=1; break
        fi
      done
      (( ws_in )) || ws_off+=("${ws_p}")
    done
    checks=$((checks + 1))
    local ws_n=${#dedup[@]}
    if (( ${#ws_off[@]} > 0 )); then
      local ws_list="" ws_i=0
      for ws_p in "${ws_off[@]}"; do
        if (( ws_i >= 5 )); then
          ws_list="${ws_list},+$(( ${#ws_off[@]} - 5 )) more"
          break
        fi
        [[ -n "${ws_list}" ]] && ws_list="${ws_list},${ws_p}" || ws_list="${ws_p}"
        ws_i=$((ws_i + 1))
      done
      _selfcheck_row "scope" "${ws_list}" "FAIL (off_write_set)"
      failed=$((failed + 1))
      _selfcheck_fail_name "scope:off_write_set:${ws_list}"
    elif (( ws_n > ws_max )); then
      _selfcheck_row "scope" "${ws_n} files > max ${ws_max}" "FAIL (oversized_diff)"
      failed=$((failed + 1))
      _selfcheck_fail_name "scope:oversized_diff:${ws_n}_files"
    else
      _selfcheck_row "scope" "${ws_n} files, write-set honored" "0"
    fi
  fi

  # ── resolve each changed path: diff_root -> project_root -> unresolved (SKIP, never RED) ──
  local n=0 resolved
  local -a resolved_paths=() resolved_rels=()
  for p in "${dedup[@]:-}"; do
    if (( n >= max_files )); then
      _selfcheck_row "resolve" "${p}" "SKIP (max_files_exceeded)"
      skipped=$((skipped + 1))
      continue
    fi
    n=$((n + 1))
    resolved=""
    if [[ -f "${diff_root}/${p}" ]]; then
      resolved="${diff_root}/${p}"
    elif [[ -f "${project_root}/${p}" ]]; then
      resolved="${project_root}/${p}"
    fi
    if [[ -z "${resolved}" ]]; then
      _selfcheck_row "resolve" "${p}" "SKIP (unresolved_path)"
      skipped=$((skipped + 1))
      continue
    fi
    resolved_paths+=("${resolved}")
    resolved_rels+=("${p}")
  done

  # ── C1: bash -n on every resolved *.sh ──
  local f rc log
  for f in "${resolved_paths[@]:-}"; do
    [[ "${f}" == *.sh ]] || continue
    log="$(mktemp)"
    bash -n "${f}" > "${log}" 2>&1
    rc=$?
    checks=$((checks + 1))
    _selfcheck_row "bash -n" "${f#"${diff_root}"/}" "${rc}"
    if (( rc != 0 )); then
      failed=$((failed + 1))
      _selfcheck_fail_name "bash-n:$(basename "${f}")"
      _selfcheck_raw "bash -n ${f}" "${rc}" "${log}"
    fi
    rm -f "${log}"
  done

  # ── C2: py_compile on every resolved *.py, PYTHONPYCACHEPREFIX kept out of the tree (R4) ──
  local pycache_dir=""
  for f in "${resolved_paths[@]:-}"; do
    [[ "${f}" == *.py ]] || continue
    [[ -z "${pycache_dir}" ]] && pycache_dir="$(mktemp -d)"
    log="$(mktemp)"
    PYTHONPYCACHEPREFIX="${pycache_dir}" python3 -m py_compile "${f}" > "${log}" 2>&1
    rc=$?
    checks=$((checks + 1))
    _selfcheck_row "py_compile" "${f#"${diff_root}"/}" "${rc}"
    if (( rc != 0 )); then
      failed=$((failed + 1))
      _selfcheck_fail_name "py_compile:$(basename "${f}")"
      _selfcheck_raw "py_compile ${f}" "${rc}" "${log}"
    fi
    rm -f "${log}"
  done
  [[ -n "${pycache_dir}" ]] && rm -rf "${pycache_dir}"

  # ── baseline attribution (H1, decision D): lazily materialise the merge-base copy of
  # the lane repo the FIRST time a suite comes back red, then re-run that suite's
  # baseline copy under the same env/timeout. A red inherited from main is never the
  # builder's fault; an unattributable red fails OPEN (never blocks a lane it cannot
  # explain) unless LEADV2_BUILDER_SELFCHECK_BASELINE=0.
  local _baseline_dir="" _baseline_tried=0 _baseline_ok=0 _baseline_base=""
  _selfcheck_baseline_verdict() { # <suite_rel_path> -> prints PASS|FAIL|SKIP_RED|SKIP_UNRESOLVED
    local rel="$1"
    if [[ "${baseline_on}" == "0" ]]; then
      printf 'FAIL'
      return
    fi
    if (( ! _baseline_tried )); then
      _baseline_tried=1
      _baseline_base="$(git -C "${diff_root}" merge-base HEAD origin/main 2>/dev/null || true)"
      [[ -z "${_baseline_base}" ]] && _baseline_base="$(git -C "${diff_root}" merge-base HEAD main 2>/dev/null || true)"
      if [[ -n "${_baseline_base}" ]]; then
        _baseline_dir="$(mktemp -d)"
        if git -C "${diff_root}" archive "${_baseline_base}" 2>/dev/null | tar -x -C "${_baseline_dir}" 2>/dev/null; then
          _baseline_ok=1
        fi
      fi
    fi
    if (( ! _baseline_ok )); then
      printf 'SKIP_UNRESOLVED'
      return
    fi
    local base_suite="${_baseline_dir}/${rel}"
    if [[ ! -f "${base_suite}" ]]; then
      printf 'FAIL'
      return
    fi
    local blog brc
    blog="$(mktemp)"
    LEADV2_BUILDER_SELFCHECK=0 LEADV2_BUILDER_SELFCHECK_DEPTH=$((depth + 1)) \
      _lv2_selfcheck_timeout_run "${timeout_s}" "${blog}" -- bash "${base_suite}"
    brc=$?
    rm -f "${blog}"
    if (( brc == 0 )); then printf 'FAIL'; else printf 'SKIP_RED'; fi
  }

  # ── C3: changed-scope suites only, resolved from the LANE tree (M3) ──
  # R2/C1: the repo-level runner (tests/run-all.sh) is NEVER invoked here -- that
  # runner is exactly what reaches this gate (via product-close.sh, via a suite it
  # spawns), so calling it back created unbounded recursion. Driving suites end-to-end
  # is the e2e stage's job (the `auto`+delegate arm below), not this gate's.
  case "${tests_mode}" in
    never)
      _selfcheck_row "suites" "-" "SKIP (suite_disabled)"
      skipped=$((skipped + 1))
      ;;
    auto|always)
      local delegate=0 delegate_cmd=""
      # The depth guard precedes the auto-delegate probe. A re-entered gate must
      # leave visible depth-guard evidence even if its lane also has an e2e
      # entrypoint; this is also the ordering in the caller/data-flow contract.
      if (( depth >= 1 )); then
        _selfcheck_row "suites" "-" "SKIP (depth_guard:${depth})"
        skipped=$((skipped + 1))
        LV2_SELFCHECK_DEPTH_SKIP=1
      else
        if [[ "${tests_mode}" == "auto" && "${LEADV2_E2E_GATE:-1}" == "1" \
              && -f "${_scripts_dir}/leadv2-e2e-entrypoint.sh" ]]; then
          if delegate_cmd="$(bash "${_scripts_dir}/leadv2-e2e-entrypoint.sh" "${diff_root}" 2>/dev/null)" \
             && [[ -n "${delegate_cmd}" ]]; then
            delegate=1
          fi
        fi
        if (( delegate )); then
          _selfcheck_row "suites" "delegated: ${delegate_cmd}" "SKIP (delegated_to_e2e)"
          skipped=$((skipped + 1))
        else
          local stem test_rel test_file ran_any=0 bverdict
        for f in "${resolved_paths[@]:-}"; do
          stem="$(basename "${f}")"; stem="${stem%.*}"
          test_file=""
          for test_rel in "plugins/leadv2/scripts/tests/test-${stem}.sh" "tests/test-${stem}.sh"; do
            if [[ -f "${diff_root}/${test_rel}" ]]; then
              test_file="${diff_root}/${test_rel}"
              break
            fi
          done
          [[ -n "${test_file}" ]] || continue
          ran_any=1
          log="$(mktemp)"
          LEADV2_BUILDER_SELFCHECK=0 LEADV2_BUILDER_SELFCHECK_DEPTH=$((depth + 1)) \
            _lv2_selfcheck_timeout_run "${timeout_s}" "${log}" -- bash "${test_file}"
          rc=$?
          checks=$((checks + 1))
          if (( rc == 0 )); then
            _selfcheck_row "suites" "${test_rel}" "${rc}"
          else
            bverdict="$(_selfcheck_baseline_verdict "${test_rel}")"
            case "${bverdict}" in
              SKIP_RED)
                _selfcheck_row "suites" "${test_rel}" "SKIP (baseline_red)"
                skipped=$((skipped + 1))
                checks=$((checks - 1))
                _selfcheck_raw "${test_rel} (lane red, baseline red -- inherited)" "${rc}" "${log}"
                ;;
              SKIP_UNRESOLVED)
                _selfcheck_row "suites" "${test_rel}" "SKIP (baseline_unresolved)"
                skipped=$((skipped + 1))
                checks=$((checks - 1))
                _selfcheck_raw "${test_rel} (lane red, baseline unresolvable -- fail-open)" "${rc}" "${log}"
                ;;
              *)
                _selfcheck_row "suites" "${test_rel}" "${rc}"
                failed=$((failed + 1))
                _selfcheck_fail_name "suites:test-${stem}$([[ ${rc} -eq 124 ]] && printf ':timeout')"
                _selfcheck_raw "${test_rel}" "${rc}" "${log}"
                ;;
            esac
          fi
          rm -f "${log}"
        done
        if (( ! ran_any )); then
          _selfcheck_row "suites" "-" "SKIP (no_matching_suite)"
          skipped=$((skipped + 1))
        fi
        fi
      fi
      ;;
    *)
      _selfcheck_row "suites" "-" "SKIP (unknown_tests_mode:${tests_mode})"
      skipped=$((skipped + 1))
      ;;
  esac

  [[ -n "${_baseline_dir}" ]] && rm -rf "${_baseline_dir}"

  LV2_SELFCHECK_CHECKS="${checks}"
  LV2_SELFCHECK_FAILED="${failed}"
  LV2_SELFCHECK_SKIPPED="${skipped}"

  local verdict reason_line=""
  if (( failed > 0 )); then
    verdict="RED"
  elif (( checks == 0 )); then
    verdict="DEGRADED"
    reason_line="reason: no_check_ran
"
  else
    verdict="GREEN"
  fi

  {
    printf '# builder selfcheck — %s\n' "$(basename "$(dirname "${out_md}")")"
    printf 'generated_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'diff_root: %s\n' "${diff_root}"
    printf 'checks: %s   failed: %s   skipped: %s\n\n' "${checks}" "${failed}" "${skipped}"
    printf '| check | target | rc |\n|-------|--------|----|\n'
    printf '%s' "${rows}"
    printf '%s' "${raws}"
    printf '\nverdict: %s\n' "${verdict}"
    printf '%s' "${reason_line}"
  } > "${out_md}"

  unset -f _selfcheck_row _selfcheck_fail_name _selfcheck_raw _selfcheck_baseline_verdict

  printf '%s' "${failed_names}"
  if (( failed > 0 )); then
    return 1
  elif (( checks == 0 )); then
    return 2
  fi
  return 0
}
