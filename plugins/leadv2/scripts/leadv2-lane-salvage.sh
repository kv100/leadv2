#!/usr/bin/env bash
# leadv2-lane-salvage.sh — LANE-SALVAGE-TOOL-01
#
# Carries a stale lane's real work commits onto a fresh branch cut from
# CURRENT main, without ever merging the stale branch (a merge would revert
# main by hundreds of files — LANE-MERGE-SILENTLY-REVERTS-MAIN-01) and
# without ever touching main itself.
#
# What it does on ONE lane:
#   1. resolves the lane's ref (its worktree's HEAD, else branch
#      worktree-<lane-id>) and the merge-base with main;
#   2. lists the commits ahead of that base, EXCLUDING anchor commits
#      (subject ending in "anchor") and merge commits;
#   3. creates branch salvage/<lane-id> from current main in a throwaway
#      worktree and cherry-picks each work commit there (-x, --empty=drop
#      so a change already on main is skipped, not failed);
#   4. on conflict, resolves NOTHING except one shape: the suite
#      registration list (EXTRA_SUITE_MAP rows) in tests/run-all.sh, and
#      only by UNION — ours kept verbatim, theirs-only registration rows
#      inserted before the map's closing quote, no row of either side
#      dropped, syntax-checked with bash -n before staging. Any other
#      conflict stops the run with a report of file + conflicting lines,
#      leaving the successfully picked prefix on the branch;
#   5. runs tests/run-all.sh --scope changed inside the salvage worktree;
#   6. prints a verdict line (see below). Merging is the lead's job.
#
# The script NEVER writes to main: main's sha is recorded before anything
# and re-asserted on every exit path; moving it is a hard failure.
#
# Usage:
#   leadv2-lane-salvage.sh <lane-id> [--force] [--suite-timeout <sec>]
#                          [--log-dir <dir>]
#     --force          recreate an existing salvage/<lane-id> branch
#     --suite-timeout  bound on tests/run-all.sh (default 1800s; GNU
#                      timeout/gtimeout if present, else unbounded)
#     --log-dir        also write the full pick + suite transcript to
#                      <log-dir>/<lane-id>.log
#
# Run from inside any worktree of the target repository.
#
# Output: progress lines prefixed [slv], and a final machine line
#   SALVAGE_RESULT verdict=<v> lane=<id> branch=<b|-> carried=<n>/<m> \
#                  suite_rc=<rc|-> [conflict_commit=<sha>] [conflict_files=<f>]
# with <v> one of:
#   salvaged_green     all work commits carried AND run-all exited 0
#   salvaged_red       carried, but run-all exited non-zero (or timed out)
#   conflict           a pick conflicted outside the auto-resolvable shape
#   nothing_to_salvage no non-anchor, non-merge commits ahead of merge-base
#
# Exit codes:
#   0 = a verdict was produced (all four verdicts; the verdict is data)
#   2 = usage / environment error (no verdict), incl. main-moved invariant
set -uo pipefail

export GIT_EDITOR=true

LANE_ID=""
FORCE=0
SUITE_TIMEOUT=1800
LOG_DIR=""

# ── helpers ──────────────────────────────────────────────────────────────────
_slv_log() { printf '[slv] %s\n' "$*"; }
_slv_fatal() { printf 'leadv2-lane-salvage: FATAL %s\n' "$*" >&2; exit 2; }

# Registration-row shape inside EXTRA_SUITE_MAP: "key:.../test-*.sh", with
# an optional 'EXTRA_SUITE_MAP="' prefix (the map's first row) and an
# optional trailing '"' (the map's last row — the closing quote rides on it).
REGROW_RE='^(EXTRA_SUITE_MAP=")?[A-Za-z0-9._/@+-]+:[^:#[:space:]]*test-[^:]*\.sh("?)$'

# Normalized identity of a registration row: strip the string-opener prefix
# and the string-closer quote, leaving "key:path".
_regrow_norm() { sed -e 's/^EXTRA_SUITE_MAP="//' -e 's/"$//'; }

# Registration rows of ONE version of run-all.sh, restricted to the
# EXTRA_SUITE_MAP=" ... " string region, normalized, one per line, sorted -u.
_regrow_keys() { # <file>
  awk '
    !in_map && /EXTRA_SUITE_MAP="/ { in_map = 1 }
    in_map {
      if ($0 ~ /"$/) { print; in_map = 0 }   # closer row carries the quote
      else print
    }
  ' "$1" | grep -E "${REGROW_RE}" | _regrow_norm | sort -u
}

# Does the EXTRA_SUITE_MAP region of <file> have exactly one closing quote?
_regrow_region_ok() { # <file>
  local n
  n="$(awk '
    !in_map && /EXTRA_SUITE_MAP="/ { in_map = 1; next }
    in_map { if ($0 ~ /"$/) { c++; in_map = 0 } }
    END { print c + 0 }
  ' "$1")"
  [[ "$n" -eq 1 ]]
}

# ── lane resolution ──────────────────────────────────────────────────────────
resolve_lane_ref() { # <lane-id> -> stdout: <sha> (ref the lane's worktree HEAD or branch)
  local lane="$1" line wt_dir head ref
  # A live worktree whose directory basename IS the lane id owns the truth:
  # its HEAD is exactly "HEAD её рабочего дерева".
  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        wt_dir="${line#worktree }"
        if [[ "$(basename "${wt_dir}")" == "${lane}" ]]; then
          ref="found"
          break
        fi
        ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null)
  if [[ "${ref:-}" == "found" ]]; then
    head="$(git -C "${wt_dir}" rev-parse --verify HEAD 2>/dev/null)" \
      || _slv_fatal "lane worktree ${wt_dir} has no HEAD"
    printf '%s' "${head}"
    return 0
  fi
  if git rev-parse --verify -q "worktree-${lane}" >/dev/null 2>&1; then
    git rev-parse "worktree-${lane}"
    return 0
  fi
  return 1
}

# Work commits ahead of the merge-base: no merge commits, no anchors.
list_work_commits() { # <merge-base> <lane-ref> -> stdout: shas, oldest first
  local mb="$1" ref="$2"
  git log --no-merges --reverse --format='%H%x09%s' "${mb}..${ref}" \
    | grep -Ev '(^|[[:space:]])anchor[[:space:]]*$' \
    | cut -f1
}

# ── main guard ───────────────────────────────────────────────────────────────
MAIN_BEFORE=""
guard_main_untouched() {
  local now
  now="$(git rev-parse --verify main 2>/dev/null)" \
    || _slv_fatal "main disappeared mid-salvage"
  if [[ -n "${MAIN_BEFORE}" && "${now}" != "${MAIN_BEFORE}" ]]; then
    _slv_fatal "main_moved before=${MAIN_BEFORE} now=${now} — salvage never touches main"
  fi
}

# ── salvage worktree ─────────────────────────────────────────────────────────
WT=""
SALVAGE_BRANCH=""
_worktree_cleanup() {
  if [[ -n "${WT}" && -d "${WT}" ]]; then
    git worktree remove --force "${WT}" >/dev/null 2>&1
  fi
  guard_main_untouched
}
trap '_worktree_cleanup' EXIT

# Drop a salvage branch that ended up identical to main, together with its
# worktree (a branch checked out in a worktree cannot be deleted until the
# worktree is gone).
_drop_empty_salvage_branch() {
  if [[ -n "${WT}" && -d "${WT}" ]]; then
    git worktree remove --force "${WT}" >/dev/null 2>&1
    WT=""
  fi
  git branch -q -D "${SALVAGE_BRANCH}" >/dev/null 2>&1
  SALVAGE_BRANCH="-"
}

create_salvage_branch() { # <main-tip>
  local main_tip="$1"
  SALVAGE_BRANCH="salvage/${LANE_ID}"
  if git show-ref --verify -q "refs/heads/${SALVAGE_BRANCH}"; then
    if [[ "${FORCE}" -ne 1 ]]; then
      _slv_fatal "branch ${SALVAGE_BRANCH} exists (rerun with --force to recreate)"
    fi
    if git worktree list --porcelain 2>/dev/null \
         | grep -Eq "branch ${SALVAGE_BRANCH}\$"; then
      _slv_fatal "branch ${SALVAGE_BRANCH} is checked out in a worktree — refusing"
    fi
  fi
  WT="$(mktemp -d "${TMPDIR:-/tmp}/lane-salvage.${LANE_ID}.XXXXXX")"
  if [[ "${FORCE}" -eq 1 ]]; then
    git worktree add --quiet -B "${SALVAGE_BRANCH}" "${WT}" "${main_tip}" >/dev/null \
      || _slv_fatal "git worktree add (-B) failed"
  else
    git worktree add --quiet -b "${SALVAGE_BRANCH}" "${WT}" "${main_tip}" >/dev/null \
      || _slv_fatal "git worktree add (-b) failed"
  fi
}

# ── conflict report ──────────────────────────────────────────────────────────
report_conflict_file() { # <file-with-markers>
  local f="$1"
  awk -v f="$f" '
    /^<{7} / { s = NR; next }
    /^={7}$/  { m = NR; next }
    /^>{7} / {
      printf "[slv]   %s: conflicting lines %d-%d (separator %d)\n", f, s, NR, m
      s = 0; m = 0
    }
  ' "$f"
}

# ── run-all.sh registration union ────────────────────────────────────────────
# The ONLY auto-resolution: tests/run-all.sh conflicted solely over
# registration rows. Construction: ours verbatim + theirs-only registration
# rows inserted before the map's closing quote. Refuses (returns 1) when the
# conflict touches anything else, or when any check fails.
union_resolve_run_all() { # <wt> <relpath> -> 0 resolved (staged), 1 refused
  local wt="$1" rel="$2" t base ours theirs result
  t="$(mktemp -d "${TMPDIR:-/tmp}/lane-salvage-union.XXXXXX")"
  git -C "${wt}" show ":1:${rel}" > "${t}/base" 2>/dev/null || {
    printf '[slv]   %s: no merge base for the pick (added both sides?) — refusing\n' "${rel}"
    rm -rf "${t}"; return 1
  }
  git -C "${wt}" show ":2:${rel}" > "${t}/ours" 2>/dev/null || { rm -rf "${t}"; return 1; }
  git -C "${wt}" show ":3:${rel}" > "${t}/theirs" 2>/dev/null || { rm -rf "${t}"; return 1; }

  # 1) Every non-marker line inside every conflict hunk of the working file
  #    must be a registration row, blank, or a line verbatim in base. One
  #    code line means this is NOT a registration conflict — refuse.
  local bad
  bad="$(awk '
    /^<{7} / { inhunk = 1; next }
    /^={7}$/  { next }
    /^>{7} /  { inhunk = 0; next }
    inhunk && NF > 0 { print }
  ' "${wt}/${rel}" \
    | grep -Ev "${REGROW_RE}" \
    | grep -vFx -f "${t}/base" \
    | head -3 || true)"
  if [[ -n "${bad}" ]]; then
    printf '[slv]   %s: conflict hunk has non-registration lines (e.g. "%s") — refusing\n' \
      "${rel}" "$(printf '%s' "${bad}" | head -1)"
    rm -rf "${t}"; return 1
  fi

  # 2) Theirs-only registration rows (normalized identity).
  _regrow_keys "${t}/ours"   > "${t}/ours.keys"
  _regrow_keys "${t}/theirs" > "${t}/theirs.keys"
  comm -13 "${t}/ours.keys" "${t}/theirs.keys" > "${t}/insert"

  # 3) Result = ours, with theirs-only rows inserted before the map closer.
  awk '
    NR == FNR { ins[++n] = $0; next }
    !in_map && /EXTRA_SUITE_MAP="/ { print; in_map = 1; next }
    in_map && /"$/ { for (i = 1; i <= n; i++) print ins[i]; in_map = 0 }
    { print }
  ' "${t}/insert" "${t}/ours" > "${t}/result"

  # 4) Checks: syntax valid, one closer, no registration row lost.
  if ! bash -n "${t}/result"; then
    printf '[slv]   %s: union result failed bash -n — refusing\n' "${rel}"
    rm -rf "${t}"; return 1
  fi
  if ! _regrow_region_ok "${t}/result"; then
    printf '[slv]   %s: union result lost/gained the map closing quote — refusing\n' "${rel}"
    rm -rf "${t}"; return 1
  fi
  _regrow_keys "${t}/result" > "${t}/after.keys"
  local n_ours n_theirs n_common n_after
  n_ours="$(wc -l < "${t}/ours.keys" | tr -d ' ')"
  n_theirs="$(wc -l < "${t}/theirs.keys" | tr -d ' ')"
  n_common="$(comm -12 "${t}/ours.keys" "${t}/theirs.keys" | wc -l | tr -d ' ')"
  n_after="$(wc -l < "${t}/after.keys" | tr -d ' ')"
  if [[ "$((n_after))" -ne "$((n_ours + n_theirs - n_common))" ]]; then
    printf '[slv]   %s: union lost a line (after=%s expected=%s) — refusing\n' \
      "${rel}" "${n_after}" "$((n_ours + n_theirs - n_common))"
    rm -rf "${t}"; return 1
  fi
  printf '[slv]   %s: registration union ok after=%s (ours=%s + theirs=%s - common=%s)\n' \
    "${rel}" "${n_after}" "${n_ours}" "${n_theirs}" "${n_common}"

  cp "${t}/result" "${wt}/${rel}"
  git -C "${wt}" add "${rel}"
  rm -rf "${t}"
  return 0
}

# ── suites ───────────────────────────────────────────────────────────────────
run_changed_scope() { # <wt> <timeout> -> rc
  local wt="$1" tmo="$2" tbin rc
  tbin="$(command -v timeout || command -v gtimeout || true)"
  if [[ -n "${tbin}" ]]; then
    (cd "${wt}" && "${tbin}" "${tmo}" bash tests/run-all.sh --scope changed)
    rc=$?
    if [[ "${rc}" -eq 124 ]]; then
      _slv_log "suite timed out after ${tmo}s"
    fi
  else
    _slv_log "no timeout binary — running suite unbounded"
    (cd "${wt}" && bash tests/run-all.sh --scope changed)
    rc=$?
  fi
  return "${rc}"
}

# ── main ─────────────────────────────────────────────────────────────────────
main() {
  local arg
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) FORCE=1; shift ;;
      --suite-timeout) [[ $# -ge 2 ]] || _slv_fatal "--suite-timeout needs a value"; SUITE_TIMEOUT="$2"; shift 2 ;;
      --suite-timeout=*) SUITE_TIMEOUT="${1#--suite-timeout=}"; shift ;;
      --log-dir) [[ $# -ge 2 ]] || _slv_fatal "--log-dir needs a value"; LOG_DIR="$2"; shift 2 ;;
      --log-dir=*) LOG_DIR="${1#--log-dir=}"; shift ;;
      -h|--help) sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *)
        if [[ -z "${LANE_ID}" ]]; then LANE_ID="$1"; shift; else
          _slv_fatal "unknown argument: $1"
        fi ;;
    esac
  done
  [[ "${SUITE_TIMEOUT}" =~ ^[0-9]+$ ]] || _slv_fatal "--suite-timeout must be a number"
  [[ -n "${LANE_ID}" ]] || _slv_fatal "usage: leadv2-lane-salvage.sh <lane-id> [--force] [--suite-timeout <s>] [--log-dir <dir>]"
  [[ "${LANE_ID}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || _slv_fatal "lane id must not contain '/' or spaces: ${LANE_ID}"
  if [[ -n "${LOG_DIR}" ]]; then
    mkdir -p "${LOG_DIR}" || _slv_fatal "cannot create --log-dir ${LOG_DIR}"
  fi
  git rev-parse --show-toplevel >/dev/null 2>&1 || _slv_fatal "not inside a git repository"

  MAIN_BEFORE="$(git rev-parse --verify main 2>/dev/null)" \
    || _slv_fatal "no 'main' branch in this repository"

  local lane_ref mb
  lane_ref="$(resolve_lane_ref "${LANE_ID}")" \
    || _slv_fatal "cannot resolve lane '${LANE_ID}' (no worktree dir, no branch worktree-${LANE_ID})"
  mb="$(git merge-base main "${lane_ref}")" \
    || _slv_fatal "no merge-base between main and ${lane_ref}"
  _slv_log "lane=${LANE_ID} ref=${lane_ref:0:12} merge_base=${mb:0:12} main=${MAIN_BEFORE:0:12}"

  local commits total
  commits="$(list_work_commits "${mb}" "${lane_ref}")"
  total="$(printf '%s\n' "${commits}" | grep -c . || true)"
  if [[ "${total}" -eq 0 ]]; then
    printf 'SALVAGE_RESULT verdict=nothing_to_salvage lane=%s branch=- carried=0/0 suite_rc=-\n' "${LANE_ID}"
    return 0
  fi
  _slv_log "planned=${total} work commits (anchors and merges excluded)"

  create_salvage_branch "${MAIN_BEFORE}"
  _slv_log "branch=${SALVAGE_BRANCH} from main@${MAIN_BEFORE:0:12} (worktree ${WT})"

  local c f carried=0 rc conf_files verdict="" conflict_commit="" conflict_files="" pick_err
  local head_before head_after
  pick_err="$(mktemp "${TMPDIR:-/tmp}/lane-salvage-pick.XXXXXX")"
  for c in ${commits}; do
    head_before="$(git -C "${WT}" rev-parse HEAD)"
    if git -C "${WT}" cherry-pick -x --empty=drop "${c}" >/dev/null 2>"${pick_err}"; then
      head_after="$(git -C "${WT}" rev-parse HEAD)"
      if [[ "${head_after}" == "${head_before}" ]]; then
        # --empty=drop dropped it (patch already upstream): rc 0, no commit
        _slv_log "pick dropped (already upstream) ${c:0:12} $(git log -1 --format=%s "${c}")"
        continue
      fi
      carried=$((carried + 1))
      _slv_log "pick ok ${c:0:12} $(git log -1 --format=%s "${c}")"
      continue
    fi
    conf_files="$(git -C "${WT}" diff --name-only --diff-filter=U)"
    if [[ "${conf_files}" == "tests/run-all.sh" ]]; then
      if union_resolve_run_all "${WT}" "tests/run-all.sh"; then
        if git -C "${WT}" cherry-pick --continue >/dev/null 2>&1 \
           && [[ "$(git -C "${WT}" rev-parse HEAD)" != "${head_before}" ]]; then
          carried=$((carried + 1))
          _slv_log "pick ok (registration union) ${c:0:12} $(git log -1 --format=%s "${c}")"
          continue
        fi
      fi
    fi
    verdict="conflict"
    conflict_commit="${c}"
    conflict_files="${conf_files}"
    _slv_log "pick CONFLICT ${c:0:12} $(git log -1 --format=%s "${c}")"
    if [[ -z "${conf_files}" ]]; then
      _slv_log "  pick failed without file conflicts: $(head -2 "${pick_err}" | tr '\n' ' ')"
    else
      for f in ${conf_files}; do
        report_conflict_file "${WT}/${f}"
      done
    fi
    git -C "${WT}" cherry-pick --quit >/dev/null 2>&1
    break
  done
  rm -f "${pick_err}"
  guard_main_untouched

  local suite_rc="-"
  if [[ -z "${verdict}" ]]; then
    if [[ "${carried}" -eq 0 ]]; then
      # Every planned commit was an empty pick: the work is already on main.
      _slv_log "all ${total} picks were empty — work already on main"
      _drop_empty_salvage_branch
      printf 'SALVAGE_RESULT verdict=nothing_to_salvage lane=%s branch=- carried=0/%s suite_rc=-\n' \
        "${LANE_ID}" "${total}"
      return 0
    fi
    if [[ "${carried}" -lt "${total}" ]]; then
      _slv_log "note: $((total - carried)) empty pick(s) dropped — already on main"
    fi
    _slv_log "running tests/run-all.sh --scope changed in ${SALVAGE_BRANCH}"
    local suite_log=""
    if [[ -n "${LOG_DIR}" ]]; then suite_log="${LOG_DIR}/${LANE_ID}.log"; fi
    if [[ -n "${suite_log}" ]]; then
      run_changed_scope "${WT}" "${SUITE_TIMEOUT}" 2>&1 | tee "${suite_log}"
      rc=${PIPESTATUS[0]}
    else
      run_changed_scope "${WT}" "${SUITE_TIMEOUT}" 2>&1 | tail -40
      rc=${PIPESTATUS[0]}
    fi
    suite_rc="${rc}"
    if [[ "${rc}" -eq 0 ]]; then verdict="salvaged_green"; else verdict="salvaged_red"; fi
    guard_main_untouched
  fi

  # An empty conflict prefix leaves the branch identical to main — drop it
  # rather than hand the lead a salvage branch with nothing on it.
  if [[ "${verdict}" == "conflict" && "${SALVAGE_BRANCH}" != "-" ]] \
     && [[ "$(git rev-parse "${SALVAGE_BRANCH}" 2>/dev/null)" == "${MAIN_BEFORE}" ]]; then
    _drop_empty_salvage_branch
  fi

  printf 'SALVAGE_RESULT verdict=%s lane=%s branch=%s carried=%s/%s suite_rc=%s' \
    "${verdict}" "${LANE_ID}" "${SALVAGE_BRANCH}" "${carried}" "${total}" "${suite_rc}"
  if [[ -n "${conflict_commit}" ]]; then
    printf ' conflict_commit=%s conflict_files=%s' "${conflict_commit:0:12}" "${conflict_files}"
  fi
  printf '\n'
  return 0
}

main "$@"
