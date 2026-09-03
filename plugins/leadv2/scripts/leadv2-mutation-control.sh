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
#   leadv2-mutation-control.sh <suite> <file> <sed-or-patch> [task_dir]
#     <suite>       path (repo-relative or absolute) to the target suite script
#     <file>        path (repo-relative or absolute) to the file to mutate
#     <sed-or-patch> either a sed(1) expression (applied via `sed -i`) or a
#                    path to a unified-diff patch file (detected by a leading
#                    "--- "/"+++ " pair inside the file)
#     [task_dir]    where to write mutation-control/<run-id>.txt; defaults to
#                   $(pwd) if omitted (still under LANE_WRITES-owned dirs
#                   only — the caller is responsible for passing the right one)
#
# diff_hash is computed HERE, never taken from the caller (fix-round-2
# finding 1): it is sha256 of `git diff <base> HEAD` over ROOT's own
# committed history, the same command+base lib/leadv2-dod-gate.sh's
# _dod_worker_diff_hash() re-runs after the worker exits. A caller-supplied
# hash could only ever be sha256 of some OTHER artifact (e.g. review.diff,
# written after the worker's round ends) and would never match what the gate
# recomputes independently — that was fix-round-1's shipped defect.
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

if [[ $# -lt 3 || $# -gt 4 ]]; then
  printf 'Usage: %s <suite> <file> <sed-or-patch> [task_dir]\n' "$0" >&2
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
DIFF_HASH="$(git -C "${ROOT}" diff "${MC_BASE}" HEAD -- . ':(exclude,glob)**/mutation-control/**' 2>/dev/null | shasum -a 256 2>/dev/null | awk '{print $1}')"
if [[ -z "${DIFF_HASH}" ]]; then
  printf 'leadv2-mutation-control: control_not_applied reason=no_merge_base\n'
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

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-mutctl.XXXXXX")"
trap 'rm -rf "${SCRATCH}"' EXIT

# ── 1. Snapshot the WORKING tree, not HEAD ──────────────────────────────────
# `git archive HEAD` is committed-only and misses uncommitted suite/mutation-
# target files the worker is still iterating on — that produces a lying-green
# result by construction (CHALLENGE-05). Snapshot tracked+untracked-but-not-
# ignored files from the actual working tree instead.
if ! git -C "${ROOT}" ls-files -co --exclude-standard -z 2>/dev/null \
     | tar -cf - --null -T - -C "${ROOT}" 2>/dev/null \
     | tar -xf - -C "${SCRATCH}" 2>/dev/null; then
  printf 'leadv2-mutation-control: control_not_applied reason=snapshot_failed\n'
  exit 2
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

# ── 6. Run the suite again (mutated) ────────────────────────────────────────
MUTATED_OUT="$(_mc_run_suite)"; MUTATED_RC=$?

if [[ "${MUTATED_RC}" == "0" ]]; then
  printf 'MUTATION-CONTROL mutant_survived suite=%s file=%s\n' "${SUITE_REL}" "${FILE_REL}"
  printf '%s\n' "${MUTATED_OUT}" | tail -20
  exit 1
fi

RED_LINE="$(printf '%s\n' "${MUTATED_OUT}" | grep -iE 'fail|assert|error' | head -1)"
[[ -z "${RED_LINE}" ]] && RED_LINE="$(printf '%s\n' "${MUTATED_OUT}" | tail -1)"

# ── 7. Write the artifact, bound to this round's diff_hash ─────────────────
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
  printf 'diff_hash=%s\n' "${DIFF_HASH}"
} > "${ARTIFACT}" 2>/dev/null

printf 'MUTATION-CONTROL ok suite=%s file=%s red_line=%s diff_hash=%s\n' \
  "${SUITE_REL}" "${FILE_REL}" "${RED_LINE}" "${DIFF_HASH}"
exit 0
