#!/usr/bin/env bash
# leadv2-mutation-control.sh — WORKER-DOD-GATE-01
#
# Applies a mutation to ONE file, in a scratch copy of the lane (never the
# lane itself), and proves the target suite actually goes red because of it.
# Motivation (brief §Why, row 2): 4 of 19 review-round Highs one night were a
# "mutation control" that never applied its mutant — the worker printed
# "red-capable" while the suite stayed green throughout. This tool makes that
# claim mechanically checkable: the artifact it writes is the only thing
# lib/leadv2-dod-gate.sh's check (b) mutation sub-check will accept.
#
# Usage:
#   leadv2-mutation-control.sh [--live] <suite> <file> <sed-or-patch> [task_dir]
#     <suite>       path (repo-relative or absolute) to the target suite script
#     <file>        path (repo-relative or absolute) to the file to mutate
#     <sed-or-patch> either a sed(1) expression (applied via `sed -i`) or a
#                    path to a unified-diff patch file (detected by a leading
#                    "--- "/"+++ " pair inside the file)
#     [task_dir]    where to write mutation-control/<run-id>.txt; defaults to
#                   $(pwd) if omitted (still under LANE_WRITES-owned dirs
#                   only — the caller is responsible for passing the right one)
#
# Two modes (W-LEAD-LAST-MILE-01 §2):
#   default        WORKER mode — mutates a scratch copy of the lane (this
#                  tool's original contract; artifact accepted by
#                  lib/leadv2-dod-gate.sh).
#   --live         LEAD mode — applies the SAME mutation to the REAL file in
#                  the lane checkout, proves the suite reds there, then
#                  restores the file byte-identical and proves the repo's
#                  `git status --porcelain` is byte-identical to the pre-run
#                  snapshot (empty when the checkout was clean). A mutation
#                  of a scratch copy proves nothing for the lead — that is
#                  why this mode exists. Restoration is guaranteed by trap
#                  on EVERY controlled exit, including TERM/INT/HUP mid-run
#                  (kill); kill -9 is the one signal no trap can catch.
#                  Artifact carries mode=live + porcelain_clean=yes.
#
# lane_diff_hash is computed HERE, never taken from the caller (fix-round-2
# finding 1): it is sha256 of `git diff <base> HEAD` over ROOT's own committed
# history, the same command+base lib/leadv2-dod-gate.sh's
# _dod_worker_diff_hash() re-runs after the worker exits. The artifact's
# diff_hash is different: it is the sha256 of the actual applied mutant diff
# in the scratch repository. Keeping both fields prevents the mutation proof
# from confusing the identity of the mutant with the identity of the lane.
#
# Exit codes:
#   0 = mutation applied, suite went red as required (ok, artifact written)
#   1 = mutant_survived — suite stayed green despite the mutation
#   2 = control_not_applied — reason= baseline_not_green | anchor_count | noop_edit | no_merge_base
#   3 = usage error
#
# Never `git worktree add` (2026-08-22 founder lesson) — a plain `mktemp -d`
# scratch dir with its own from-scratch `git init` registers nothing in
# .git/worktrees/ and is prune-safe by construction.
set -uo pipefail

LIVE=0
if [[ "${1:-}" == "--live" ]]; then LIVE=1; shift; fi

if [[ $# -lt 3 || $# -gt 4 ]]; then
  printf 'Usage: %s [--live] <suite> <file> <sed-or-patch> [task_dir]\n' "$0" >&2
  exit 3
fi

SUITE_ARG="$1"
FILE_ARG="$2"
MUTATION_ARG="$3"
TASK_DIR="${4:-$(pwd)}"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Same base-resolution ladder as lib/leadv2-dod-gate.sh's _dod_resolve_base()
# — LEADV2_LANE_START_SHA env, else main, else origin/main. Kept independent
# (not sourced) so this tool has zero dependency on the gate library ever
# being present.
_mc_resolve_base() {
  git -C "${ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  local base sha="${LEADV2_LANE_START_SHA:-}"
  if [[ -n "${sha}" ]] && git -C "${ROOT}" cat-file -e "${sha}^{commit}" 2>/dev/null; then
    base="$(git -C "${ROOT}" merge-base "${sha}" HEAD 2>/dev/null || true)"
    [[ -n "${base}" ]] && { printf '%s' "${base}"; return 0; }
  fi
  if git -C "${ROOT}" cat-file -e "main^{commit}" 2>/dev/null; then
    base="$(git -C "${ROOT}" merge-base main HEAD 2>/dev/null || true)"
    [[ -n "${base}" ]] && { printf '%s' "${base}"; return 0; }
  fi
  if git -C "${ROOT}" cat-file -e "origin/main^{commit}" 2>/dev/null; then
    base="$(git -C "${ROOT}" merge-base origin/main HEAD 2>/dev/null || true)"
    [[ -n "${base}" ]] && { printf '%s' "${base}"; return 0; }
  fi
  return 1
}

MC_BASE="$(_mc_resolve_base)"
if [[ -z "${MC_BASE}" ]]; then
  printf 'leadv2-mutation-control: control_not_applied reason=no_merge_base\n'
  exit 2
fi
# **/mutation-control/** excluded: this tool's own artifact write happens
# AFTER this hash is computed and gets committed in a later commit than the
# one this hash describes — including the directory would make the gate's
# post-commit recomputation structurally unable to ever match. See
# lib/leadv2-dod-gate.sh's _dod_worker_diff_hash() comment for the full
# chicken-and-egg explanation; both sides exclude identically.
# MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01 (founder 2026-09-05).
# The emptiness guard below used to read `[[ -z "${LANE_DIFF_HASH}" ]]` -- it
# tested the guard's own OUTPUT instead of its INPUT, and `shasum` of empty
# input is not an empty string, it is a perfectly well-formed hash
# (e3b0c442...7852b855). A guard that checks its own output can never fire for
# the case it exists for.
#
# The case is not rare: a lane working in the CANONICAL checkout rather than on
# its own branch has main == HEAD, so `git diff <base> HEAD` is empty every
# single time. Measured across all 63 artifacts in the tree on 2026-09-05: 8
# carried the empty-diff hash as their lane identity, from 5 different lanes.
#
# What was lost is IDENTITY, not proof -- all 8 carried a real, distinct
# `diff_hash`, so the mutation genuinely applied in every one and the suites
# genuinely went red. The artifact still proves "this suite reddens"; it stops
# proving "it reddens ON THIS WORK", and with the field constant across lanes
# every such artifact is indistinguishable from every other.
#
# `git diff --quiet` exits 0 when there is NO diff. It is tested SEPARATELY from
# the hash on purpose: the hash pipeline itself is left byte-identical, because
# lib/leadv2-dod-gate.sh's _dod_worker_diff_hash() recomputes it with the same
# command and the two must never drift.
if git -C "${ROOT}" diff --quiet "${MC_BASE}" HEAD -- . ':(exclude,glob)**/mutation-control/**' 2>/dev/null; then
  printf 'leadv2-mutation-control: control_not_applied reason=empty_lane_diff base=%s\n' "${MC_BASE:0:12}"
  printf '  This lane has no committed diff against its resolved base, so the artifact would carry\n'
  printf '  the sha256 of an empty diff as its identity -- a value every such artifact shares, which\n'
  printf '  is why it is refused rather than written.\n'
  printf '  Set LEADV2_LANE_START_SHA=<sha of the commit before this lane started> and re-run.\n'
  exit 2
fi
LANE_DIFF_HASH="$(git -C "${ROOT}" diff "${MC_BASE}" HEAD -- . ':(exclude,glob)**/mutation-control/**' 2>/dev/null | shasum -a 256 2>/dev/null | awk '{print $1}')"
if [[ -z "${LANE_DIFF_HASH}" ]]; then
  printf 'leadv2-mutation-control: control_not_applied reason=no_merge_base\n'
  exit 2
fi
# Belt and braces: whatever path produced it, that one hash is never an identity.
if [[ "${LANE_DIFF_HASH}" == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]; then
  printf 'leadv2-mutation-control: control_not_applied reason=empty_lane_diff base=%s\n' "${MC_BASE:0:12}"
  printf '  Set LEADV2_LANE_START_SHA=<sha of the commit before this lane started> and re-run.\n'
  exit 2
fi

_mc_abs() { # <path relative-to-ROOT-or-absolute> -> stdout absolute path (no existence check)
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s/%s' "${ROOT}" "$1" ;;
  esac
}

SUITE_ABS="$(_mc_abs "${SUITE_ARG}")"
FILE_ABS="$(_mc_abs "${FILE_ARG}")"

if [[ ! -f "${SUITE_ABS}" ]]; then
  printf 'leadv2-mutation-control: not a file: suite=%s\n' "${SUITE_ABS}" >&2
  exit 3
fi
if [[ ! -f "${FILE_ABS}" ]]; then
  printf 'leadv2-mutation-control: not a file: target=%s\n' "${FILE_ABS}" >&2
  exit 3
fi

FILE_REL="${FILE_ABS#${ROOT}/}"
SUITE_REL="${SUITE_ABS#${ROOT}/}"

# ── LEAD mode: same mutation, REAL file, trap-guaranteed restore ────────────
# Globals (NOT locals): the EXIT trap must see them even after this function
# has returned, and set -u must not blow up inside the trap.
LIVE_BACKUP=""; LIVE_OUT=""; LIVE_MUTATED=0; LIVE_CHILD=""

_mc_live_restore() { # called from the EXIT trap — restore beats everything
  if [[ "${LIVE_MUTATED:-0}" -eq 1 && -f "${LIVE_BACKUP}" && -f "${FILE_ABS}" ]]; then
    cp -f "${LIVE_BACKUP}" "${FILE_ABS}"
  fi
  rm -f "${LIVE_BACKUP}" "${LIVE_OUT}" "${LIVE_OUT}.mut" 2>/dev/null
}

_mc_live_flow() {
  local rc out red_line is_patch=0 run_dir porcelain_before porcelain_after
  run_dir="$(dirname "${SUITE_ABS}")"
  LIVE_OUT="$(mktemp "${TMPDIR:-/tmp}/leadv2-mutctl-live.XXXXXX")"
  LIVE_BACKUP="$(mktemp "${TMPDIR:-/tmp}/leadv2-mutctl-live.XXXXXX")"
  trap '_mc_live_restore' EXIT
  # EXIT alone never fires on an untrapped TERM/INT/HUP (macOS bash 3.2);
  # route them through exit() so the restore still runs. The suite child is
  # killed FIRST so a foreground wait cannot defer the trap behind it.
  trap '[[ -n "${LIVE_CHILD:-}" ]] && kill "${LIVE_CHILD}" 2>/dev/null; exit 143' TERM
  trap '[[ -n "${LIVE_CHILD:-}" ]] && kill "${LIVE_CHILD}" 2>/dev/null; exit 130' INT
  trap '[[ -n "${LIVE_CHILD:-}" ]] && kill "${LIVE_CHILD}" 2>/dev/null; exit 129' HUP

  # baseline green in the REAL checkout — same order as scratch mode
  ( cd "${run_dir}" && bash "${SUITE_ABS}" ) > "${LIVE_OUT}" 2>&1
  rc=$?
  if [[ ${rc} -ne 0 ]]; then
    printf 'MUTATION-CONTROL control_not_applied mode=live reason=baseline_not_green baseline_rc=%s\n' "${rc}"
    tail -20 "${LIVE_OUT}"
    return 2
  fi

  porcelain_before="$(git -C "${ROOT}" status --porcelain 2>/dev/null | LC_ALL=C sort)"

  # build/apply the mutant; only touch the real file once it differs
  if head -5 "${MUTATION_ARG}" 2>/dev/null | grep -qE '^(--- |\+\+\+ )'; then is_patch=1; fi
  if [[ ${is_patch} -eq 1 ]]; then
    if ! patch -p1 --dry-run -d "${ROOT}" < "${MUTATION_ARG}" >/dev/null 2>&1; then
      printf 'MUTATION-CONTROL control_not_applied mode=live reason=anchor_count\n'
      return 2
    fi
    cp -f "${FILE_ABS}" "${LIVE_BACKUP}"; LIVE_MUTATED=1
    patch -p1 -d "${ROOT}" < "${MUTATION_ARG}" >/dev/null 2>&1
  else
    sed -e "${MUTATION_ARG}" "${FILE_ABS}" > "${LIVE_OUT}.mut" 2>/dev/null
    if [[ ! -s "${LIVE_OUT}.mut" && -s "${FILE_ABS}" ]]; then
      printf 'MUTATION-CONTROL control_not_applied mode=live reason=anchor_count\n'
      return 2
    fi
    if cmp -s "${FILE_ABS}" "${LIVE_OUT}.mut" 2>/dev/null; then
      printf 'MUTATION-CONTROL control_not_applied mode=live reason=noop_edit\n'
      return 2
    fi
    cp -f "${FILE_ABS}" "${LIVE_BACKUP}"; LIVE_MUTATED=1
    cp -f "${LIVE_OUT}.mut" "${FILE_ABS}"
  fi
  if git -C "${ROOT}" diff --quiet -- "${FILE_REL}" 2>/dev/null; then
    printf 'MUTATION-CONTROL control_not_applied mode=live reason=noop_edit\n'
    return 2
  fi

  local mut_hash
  mut_hash="$(git -C "${ROOT}" diff --no-ext-diff --binary --no-color -- "${FILE_REL}" 2>/dev/null \
    | shasum -a 256 2>/dev/null | awk '{print $1}')"
  if [[ -z "${mut_hash}" || "${mut_hash}" == e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ]]; then
    printf 'MUTATION-CONTROL control_not_applied mode=live reason=empty_mutation_diff\n'
    return 2
  fi

  # mutated run — backgrounded so a TERM reaches the parent's trap NOW,
  # not after the suite exits on its own
  ( cd "${run_dir}" && exec bash "${SUITE_ABS}" ) > "${LIVE_OUT}" 2>&1 &
  LIVE_CHILD=$!
  wait "${LIVE_CHILD}"; rc=$?
  LIVE_CHILD=""
  out="$(cat "${LIVE_OUT}")"
  if [[ ${rc} -eq 0 ]]; then
    printf 'MUTATION-CONTROL mutant_survived mode=live suite=%s file=%s\n' "${SUITE_REL}" "${FILE_REL}"
    printf '%s\n' "${out}" | tail -20
    return 1 # restore happens in the trap
  fi

  red_line="$(printf '%s\n' "${out}" | grep -iE 'fail|assert|error' | head -1)"
  [[ -z "${red_line}" ]] && red_line="$(printf '%s\n' "${out}" | tail -1)"

  # restore NOW on the happy path too; the trap is the crash net, not the plan
  cp -f "${LIVE_BACKUP}" "${FILE_ABS}"
  LIVE_MUTATED=0

  porcelain_after="$(git -C "${ROOT}" status --porcelain 2>/dev/null | LC_ALL=C sort)"
  if [[ "${porcelain_after}" != "${porcelain_before}" ]]; then
    printf 'MUTATION-CONTROL restore_failed mode=live file=%s — porcelain differs from the pre-run snapshot\n' "${FILE_REL}"
    diff <(printf '%s\n' "${porcelain_before}") <(printf '%s\n' "${porcelain_after}") | head -20
    return 1
  fi

  local run_id mc_dir
  run_id="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo run)-live-$$"
  mc_dir="${TASK_DIR}/mutation-control"
  mkdir -p "${mc_dir}" 2>/dev/null || true
  {
    printf 'suite=%s\n' "${SUITE_REL}"
    printf 'file=%s\n' "${FILE_REL}"
    printf 'anchor=%s\n' "${MUTATION_ARG}"
    printf 'mode=live\n'
    printf 'baseline_rc=0\n'
    printf 'mutated_rc=%s\n' "${rc}"
    printf 'red_line=%s\n' "${red_line}"
    printf 'diff_hash=%s\n' "${mut_hash}"
    printf 'lane_diff_hash=%s\n' "${LANE_DIFF_HASH}"
    printf 'porcelain_clean=yes\n'
    printf 'restored=yes\n'
  } > "${mc_dir}/${run_id}.txt" 2>/dev/null

  printf 'MUTATION-CONTROL ok mode=live suite=%s file=%s red_line=%s diff_hash=%s lane_diff_hash=%s porcelain_clean=yes\n' \
    "${SUITE_REL}" "${FILE_REL}" "${red_line}" "${mut_hash}" "${LANE_DIFF_HASH}"
  return 0
}

if [[ ${LIVE} -eq 1 ]]; then
  _mc_live_flow
  exit $?
fi

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-mutctl.XXXXXX")"
trap 'rm -rf "${SCRATCH}"' EXIT

# ── 1. Snapshot HEAD, then overlay ONLY what this measurement is about ──────
# CHALLENGE-05 was right that `git archive HEAD` alone misses the uncommitted
# suite/mutation-target files a worker is still iterating on. Its fix copied
# the WHOLE working tree (`ls-files -co`), and in a shared checkout that drags
# every other lane's half-finished file into the measured tree
# (MUTATION-RUNNER-STAGES-EVERYTHING-01): a mutation can then read killed --
# or survived -- for a reason that came from somebody else's edit.
#
# So: HEAD, plus the mutation's file, plus the suite, plus whatever the caller
# declares in LEADV2_MUTCTL_OVERLAY (csv of repo-relative paths). Nothing else
# from the working tree reaches the verdict. A suite that needs some OTHER
# uncommitted file now fails the baseline-green gate in step 3 loudly, instead
# of being measured against a tree nobody chose. LEADV2_MUTCTL_SNAPSHOT=worktree
# restores the old behaviour in one flip.
_mc_overlay() { # <repo-relative path> -- copies from the real tree when present
  local rel="${1:-}" src dst
  [[ -n "${rel}" ]] || return 0
  src="${ROOT}/${rel}"; dst="${SCRATCH}/${rel}"
  [[ -f "${src}" ]] || return 0
  mkdir -p "$(dirname "${dst}")" 2>/dev/null || return 0
  cp "${src}" "${dst}" 2>/dev/null || true
  return 0
}

if [[ "${LEADV2_MUTCTL_SNAPSHOT:-head}" == "worktree" ]]; then
  if ! git -C "${ROOT}" ls-files -co --exclude-standard -z 2>/dev/null \
       | tar -C "${ROOT}" --null -cf - -T - 2>/dev/null \
       | tar -xf - -C "${SCRATCH}" 2>/dev/null; then
    printf 'leadv2-mutation-control: control_not_applied reason=snapshot_failed\n'
    exit 2
  fi
  printf 'leadv2-mutation-control: snapshot=worktree (every dirty file in the checkout is in the measured tree)\n'
else
  if ! git -C "${ROOT}" archive HEAD 2>/dev/null | tar -xf - -C "${SCRATCH}" 2>/dev/null; then
    printf 'leadv2-mutation-control: control_not_applied reason=snapshot_failed\n'
    exit 2
  fi
  _mc_declared=("${FILE_REL}" "${SUITE_REL}")
  if [[ -n "${LEADV2_MUTCTL_OVERLAY:-}" ]]; then
    IFS=',' read -r -a _mc_extra <<< "${LEADV2_MUTCTL_OVERLAY}"
    for _e in "${_mc_extra[@]}"; do
      _e="$(printf '%s' "${_e}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -n "${_e}" ]] && _mc_declared+=("${_e}")
    done
  fi
  for _d in "${_mc_declared[@]}"; do _mc_overlay "${_d}"; done
  # Loudness: say how many dirty files were deliberately left OUT, so a
  # contaminated checkout is visible in the record rather than silently baked in.
  _mc_dirty=0
  while IFS= read -r _line; do
    [[ -z "${_line}" ]] && continue
    _p="${_line:3}"
    _skip=0
    for _d in "${_mc_declared[@]}"; do [[ "${_p}" == "${_d}" ]] && { _skip=1; break; }; done
    (( _skip )) || _mc_dirty=$(( _mc_dirty + 1 ))
  done < <(git -C "${ROOT}" status --porcelain 2>/dev/null)
  printf 'leadv2-mutation-control: snapshot=head_plus_declared declared=%s excluded_dirty=%s\n' \
    "${#_mc_declared[@]}" "${_mc_dirty}"
fi

# ── 2. Give the scratch tree its own git identity ───────────────────────────
# So git-dependent suites run for the right reason. A fresh, untracked repo
# — never `git worktree add`, so it registers nothing in .git/worktrees/.
( cd "${SCRATCH}" \
  && git init -q \
  && git add -A \
  && git -c user.email=dod@local -c user.name=dod commit -qm base -q ) >/dev/null 2>&1
if [[ ! -d "${SCRATCH}/.git" ]]; then
  printf 'leadv2-mutation-control: control_not_applied reason=scratch_git_init_failed\n'
  exit 2
fi

SCRATCH_SUITE="${SCRATCH}/${SUITE_REL}"
SCRATCH_FILE="${SCRATCH}/${FILE_REL}"
if [[ ! -f "${SCRATCH_SUITE}" || ! -f "${SCRATCH_FILE}" ]]; then
  printf 'leadv2-mutation-control: control_not_applied reason=snapshot_missing_target\n'
  exit 2
fi

_mc_run_suite() { # -> stdout: captured output; function's own exit status IS the suite's rc
  local out rc
  out="$(cd "$(dirname "${SCRATCH_SUITE}")" && bash "${SCRATCH_SUITE}" 2>&1)"
  rc=$?
  printf '%s' "${out}"
  return "${rc}"
}

# ── 3. Baseline-green gate (NEW, CHALLENGE-05) ──────────────────────────────
BASELINE_OUT="$(_mc_run_suite)"; BASELINE_RC=$?
if [[ "${BASELINE_RC}" != "0" ]]; then
  printf 'MUTATION-CONTROL control_not_applied reason=baseline_not_green baseline_rc=%s\n' "${BASELINE_RC}"
  printf '%s\n' "${BASELINE_OUT}" | tail -20
  exit 2
fi

# ── 4. Anchor check ──────────────────────────────────────────────────────────
IS_PATCH=0
if head -5 "${MUTATION_ARG}" 2>/dev/null | grep -qE '^(--- |\+\+\+ )'; then
  IS_PATCH=1
fi

cp -f "${SCRATCH_FILE}" "${SCRATCH_FILE}.orig"

if [[ "${IS_PATCH}" -eq 1 ]]; then
  if ! patch -p1 --dry-run -d "${SCRATCH}" < "${MUTATION_ARG}" >/dev/null 2>&1; then
    printf 'MUTATION-CONTROL control_not_applied reason=anchor_count\n'
    exit 2
  fi
  patch -p1 -d "${SCRATCH}" < "${MUTATION_ARG}" >/dev/null 2>&1
else
  # sed expression: the anchor is whatever pattern the expression's address
  # matches. We can't statically extract it for every possible sed syntax, so
  # we detect "exactly one match" by running the expression once and diffing
  # line-count of changed lines against `sed -n '<addr>p'`-style single-apply
  # semantics is impractical in general; instead require the expression apply
  # exactly once by convention (workers write single-anchor sed expressions,
  # per the worker-facing contract in leadv2-helpers.sh) and detect a no-op
  # as the anchor-absent signal, which is the observable failure mode.
  sed -e "${MUTATION_ARG}" "${SCRATCH_FILE}.orig" > "${SCRATCH_FILE}.mutated" 2>/dev/null
  if [[ ! -s "${SCRATCH_FILE}.mutated" ]] && [[ -s "${SCRATCH_FILE}.orig" ]]; then
    printf 'MUTATION-CONTROL control_not_applied reason=anchor_count\n'
    exit 2
  fi
  if cmp -s "${SCRATCH_FILE}.orig" "${SCRATCH_FILE}.mutated" 2>/dev/null; then
    printf 'MUTATION-CONTROL control_not_applied reason=anchor_count\n'
    exit 2
  fi
  cp -f "${SCRATCH_FILE}.mutated" "${SCRATCH_FILE}"
fi

# ── 5. noop_edit guard ──────────────────────────────────────────────────────
if cmp -s "${SCRATCH_FILE}.orig" "${SCRATCH_FILE}" 2>/dev/null; then
  printf 'MUTATION-CONTROL control_not_applied reason=noop_edit\n'
  exit 2
fi

# Hash the bytes of the applied mutation as Git renders them, including mode
# and binary changes when applicable. This is deliberately computed after the
# mutation is applied and before the suite runs; hashing the lane diff here
# would make different mutants indistinguishable (and hashing an empty stream
# would yield the false-assurance SHA-256 empty-string value).
MUTATION_DIFF_HASH="$(git -C "${SCRATCH}" diff --no-ext-diff --binary --no-color -- "${FILE_REL}" 2>/dev/null \
  | shasum -a 256 2>/dev/null | awk '{print $1}')"
if [[ -z "${MUTATION_DIFF_HASH}" || "${MUTATION_DIFF_HASH}" == e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ]]; then
  printf 'leadv2-mutation-control: control_not_applied reason=empty_mutation_diff\n'
  exit 2
fi

# ── 6. Run the suite again (mutated) ────────────────────────────────────────
MUTATED_OUT="$(_mc_run_suite)"; MUTATED_RC=$?

if [[ "${MUTATED_RC}" == "0" ]]; then
  printf 'MUTATION-CONTROL mutant_survived suite=%s file=%s\n' "${SUITE_REL}" "${FILE_REL}"
  printf '%s\n' "${MUTATED_OUT}" | tail -20
  exit 1
fi

RED_LINE="$(printf '%s\n' "${MUTATED_OUT}" | grep -iE 'fail|assert|error' | head -1)"
[[ -z "${RED_LINE}" ]] && RED_LINE="$(printf '%s\n' "${MUTATED_OUT}" | tail -1)"

# ── 7. Write the artifact, bound to this round's lane and mutation hashes ───
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo "run")-$$"
MC_DIR="${TASK_DIR}/mutation-control"
mkdir -p "${MC_DIR}" 2>/dev/null || true
ARTIFACT="${MC_DIR}/${RUN_ID}.txt"
{
  printf 'suite=%s\n' "${SUITE_REL}"
  printf 'file=%s\n' "${FILE_REL}"
  printf 'anchor=%s\n' "${MUTATION_ARG}"
  printf 'baseline_rc=0\n'
  printf 'mutated_rc=%s\n' "${MUTATED_RC}"
  printf 'red_line=%s\n' "${RED_LINE}"
  printf 'diff_hash=%s\n' "${MUTATION_DIFF_HASH}"
  printf 'lane_diff_hash=%s\n' "${LANE_DIFF_HASH}"
} > "${ARTIFACT}" 2>/dev/null

printf 'MUTATION-CONTROL ok suite=%s file=%s red_line=%s diff_hash=%s lane_diff_hash=%s\n' \
  "${SUITE_REL}" "${FILE_REL}" "${RED_LINE}" "${MUTATION_DIFF_HASH}" "${LANE_DIFF_HASH}"
exit 0
