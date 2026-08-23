#!/usr/bin/env bash
# RED-FIRST-SELF-INVALIDATES-01: shared pinned-baseline resolver for red-first
# assertions. A red-first check that reconstructs its "pre-fix" tree from a
# floating ref (HEAD^, merge-base with a branch that keeps moving) goes green
# forever the moment the fix is an ancestor of that ref -- it stops proving
# anything but never says so. This helper pins the pre-fix tree to the parent
# of the commit that introduced <marker> in <pathspec>'s history, so the
# assertion stays meaningful on any branch, forever. Bash 3.2 only.
#
# lv2_rf_baseline_ref <marker> <pathspec> [<pin-fallback-ref>]
#   stdout: resolved baseline ref (rc 0 only)
#   stderr: human-readable reason on rc 3 / rc 4
#   rc 0  resolved and verified marker-absent at that ref
#   rc 3  unresolvable (no git, shallow clone, marker never in history, ref
#         does not exist, marker's intro commit is the repo root)
#   rc 4  operator override (LEADV2_TEST_BASELINE_REF) already contains the
#         marker -- red-first evidence at that ref would be vacuous
lv2_rf_baseline_ref() {
  local marker="$1" pathspec="$2" pin="${3:-}"
  local repo ref

  repo="${LEADV2_REPO:-}"
  [[ -n "${repo}" ]] || repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "${repo}" ]] || ! git -C "${repo}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "no usable git checkout to resolve a red-first baseline" >&2
    return 3
  fi

  if [[ "$(git -C "${repo}" rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
    echo "shallow clone -- history is truncated, cannot pickaxe for marker '${marker}'" >&2
    return 3
  fi

  if [[ -n "${LEADV2_TEST_BASELINE_REF:-}" ]]; then
    ref="${LEADV2_TEST_BASELINE_REF}"
    if ! git -C "${repo}" rev-parse --verify "${ref}^{commit}" >/dev/null 2>&1; then
      echo "LEADV2_TEST_BASELINE_REF='${ref}' does not resolve to a commit" >&2
      return 3
    fi
    if git -C "${repo}" grep -q -F -- "${marker}" "${ref}" -- "${pathspec}" 2>/dev/null; then
      echo "baseline override '${ref}' already contains '${marker}' -- red-first evidence would be vacuous" >&2
      return 4
    fi
    printf '%s\n' "${ref}"
    return 0
  fi

  local intro
  intro="$(git -C "${repo}" log --reverse --format=%H -S"${marker}" --fixed-strings -- "${pathspec}" 2>/dev/null | head -1)"
  if [[ -n "${intro}" ]]; then
    ref="${intro}^"
    if git -C "${repo}" rev-parse --verify "${ref}^{commit}" >/dev/null 2>&1 &&
       ! git -C "${repo}" grep -q -F -- "${marker}" "${ref}" -- "${pathspec}" 2>/dev/null; then
      printf '%s\n' "${ref}"
      return 0
    fi
    # intro commit is the repo root (no parent) -- fall through to the pin.
  fi

  if [[ -n "${pin}" ]] && git -C "${repo}" rev-parse --verify "${pin}^{commit}" >/dev/null 2>&1; then
    if git -C "${repo}" grep -q -F -- "${marker}" "${pin}" -- "${pathspec}" 2>/dev/null; then
      echo "pin fallback '${pin}' already contains '${marker}' -- cannot use as a pre-fix baseline" >&2
      return 3
    fi
    printf '%s\n' "${pin}"
    return 0
  fi

  echo "no pre-fix baseline resolvable for marker '${marker}' in '${pathspec}'" >&2
  return 3
}

# lv2_rf_extract <ref> <dest-dir> <pathspec...>
# Extracts <ref> under <dest-dir> via git archive | tar. rc 3 (not a FAIL) on
# an unreadable ref or an empty resulting tree -- an unextractable archive is
# an environment fault, not a product regression.
lv2_rf_extract() {
  local ref="$1" dest="$2"; shift 2
  local repo="${LEADV2_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
  [[ -n "${repo}" ]] || { echo "no usable git checkout to extract '${ref}'" >&2; return 3; }
  mkdir -p "${dest}"
  if ! git -C "${repo}" archive "${ref}" "$@" 2>/dev/null | tar -x -C "${dest}" 2>/dev/null; then
    echo "git archive '${ref}' -- $* extraction failed" >&2
    return 3
  fi
  if [[ -z "$(find "${dest}" -type f -print -quit 2>/dev/null)" ]]; then
    echo "git archive '${ref}' -- $* produced an empty tree" >&2
    return 3
  fi
  return 0
}
