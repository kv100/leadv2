#!/usr/bin/env bash
# leadv2-worker-output-gate.sh — FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01.
#
# Applies to EVERY arm, not just freepool: before a worker's changed files
# are accepted as done, every changed *.sh must pass `bash -n` and every
# changed *.py must pass `python3 -m py_compile`. A file that does not parse
# is rejected with its parse error, never silently recorded as a completed
# task -- two of the three unusable free-arm results on 2026-08-30 (a
# syntactically broken hook line, a bash -n-failing test suite committed
# four times) would have been caught here.
#
# Usage:
#   leadv2-worker-output-gate.sh <repo-root> <file> [<file> ...]
#   leadv2-worker-output-gate.sh <repo-root> --from-git-diff [<git-diff-args...>]
#
# Exit 0: every changed *.sh/*.py parses.
# Exit 1: at least one changed *.sh/*.py fails to parse; stdout carries one
#         `worker_output_gate_reject file=<path> tool=<bash-n|py_compile>`
#         line per failure, followed by that tool's own parse-error text.
# Non-*.sh/*.py files are ignored -- this gate checks syntax, not content.
#
# Bash 3.2 safe: no associative arrays, no mapfile, no ${var^^}.
set -uo pipefail

_wog_usage() {
  echo "usage: leadv2-worker-output-gate.sh <repo-root> <file> [<file> ...]" >&2
  echo "       leadv2-worker-output-gate.sh <repo-root> --from-git-diff [<git-diff-args...>]" >&2
}

# worker_output_gate_resolve_base <repo-root> -> stdout "<ref> <sha>", rc 0
# `origin/main` is one way to name the lane's base, not the only one -- a
# checkout with no remote, a differently-named default branch, or a fresh
# clone that hasn't fetched yet all have a usable base under a different
# name (GATE-ORIGIN-MAIN-01). Tries, in order: the remote's advertised
# default branch (git remote set-head), origin/main, origin/master, a local
# main/master branch, and the current branch's configured upstream. Each
# failed attempt is logged to stderr so a total failure is diagnosable, not
# just a bare "no". On total failure, prints the aggregate reason to stderr
# and returns 1 -- callers must treat that as a refusal, not a pass.
worker_output_gate_resolve_base() {
  local repo_root="$1"
  local origin_default
  origin_default="$(git -C "$repo_root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  local -a candidates=()
  [[ -n "$origin_default" ]] && candidates+=("origin/${origin_default}")
  candidates+=("origin/main" "origin/master" "main" "master" "@{upstream}")

  local -a tried=()
  local ref base already t
  for ref in "${candidates[@]}"; do
    already=0
    for t in "${tried[@]:-}"; do
      [[ -n "$t" && "$t" == "$ref" ]] && { already=1; break; }
    done
    [[ "$already" -eq 1 ]] && continue
    tried+=("$ref")
    if base="$(git -C "$repo_root" merge-base "$ref" HEAD 2>/dev/null)"; then
      printf '%s %s\n' "$ref" "$base"
      return 0
    fi
    printf 'worker_output_gate_base_attempt ref=%s result=unresolved\n' "$ref" >&2
  done
  printf 'worker_output_gate_error reason=committed_range_unresolved attempts=%s\n' \
    "$(IFS=,; printf '%s' "${tried[*]:-}")" >&2
  return 1
}

# worker_output_gate_check <repo-root> <file> [<file> ...] -> 0 pass, 1 reject
# Prints one worker_output_gate_reject line + the tool's parse error per
# failing file; prints nothing on full pass.
worker_output_gate_check() {
  local repo_root="$1"; shift
  local rc=0 f abspath err
  for f in "$@"; do
    [[ -n "$f" ]] || continue
    case "$f" in
      /*) abspath="$f" ;;
      *)  abspath="${repo_root%/}/${f}" ;;
    esac
    [[ -f "$abspath" ]] || continue
    case "$f" in
      *.sh)
        if ! err="$(bash -n "$abspath" 2>&1 1>/dev/null)"; then
          printf 'worker_output_gate_reject file=%s tool=bash-n\n' "$f"
          printf '%s\n' "$err"
          rc=1
        fi
        ;;
      *.py)
        if ! err="$(python3 -m py_compile "$abspath" 2>&1 1>/dev/null)"; then
          printf 'worker_output_gate_reject file=%s tool=py_compile\n' "$f"
          printf '%s\n' "$err"
          rc=1
        fi
        ;;
      *) continue ;;
    esac
  done
  return "$rc"
}

main() {
  local repo_root="${1:-}"
  [[ -n "$repo_root" && -d "$repo_root" ]] || { _wog_usage; return 64; }
  shift
  if [[ "${1:-}" == "--from-git-diff" ]]; then
    shift
    # Bash 3.2 + `set -u` treats an empty array expansion as an unbound
    # variable.  Keep the collected file list on disk instead: an empty
    # working tree is a normal, passing input, not a parser failure.
    local files_file line rc=0
    files_file="$(mktemp "${TMPDIR:-/tmp}/leadv2-worker-output-gate.XXXXXX")" || return 1
    # Caller-supplied diff args cover uncommitted/staged work (the production
    # caller supplies HEAD).  Also inspect commits made by the worker: a clean
    # working tree after `git commit` must not hide a broken shell file.
    git -C "$repo_root" diff --name-only --diff-filter=ACMR "$@" 2>/dev/null >> "$files_file" || true
    # A clean worker tree is only safe to pass when we can also resolve the
    # committed range.  Lane repositories commonly have no origin/main; do
    # not turn that missing evidence into a silent success -- but origin/main
    # is not the only valid name for the lane's base (GATE-ORIGIN-MAIN-01).
    local resolved committed_base
    if ! resolved="$(worker_output_gate_resolve_base "$repo_root")"; then
      # worker_output_gate_resolve_base already printed the per-attempt
      # trail and the aggregate reason to stderr.
      rm -f "$files_file"
      return 2
    fi
    committed_base="${resolved#* }"
    if ! git -C "$repo_root" diff --name-only --diff-filter=ACMR "${committed_base}...HEAD" 2>/dev/null >> "$files_file"; then
      printf 'worker_output_gate_error reason=committed_range_diff_failed base=%s head=HEAD\n' "$committed_base" >&2
      rm -f "$files_file"
      return 2
    fi
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      worker_output_gate_check "$repo_root" "$line" || rc=1
    done < <(LC_ALL=C sort -u "$files_file")
    rm -f "$files_file"
    return "$rc"
  fi
  worker_output_gate_check "$repo_root" "$@"
}

# Sourced (for worker_output_gate_check) or executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit $?
fi
