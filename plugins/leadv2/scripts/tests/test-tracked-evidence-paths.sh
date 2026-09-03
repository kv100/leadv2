#!/usr/bin/env bash
# test-tracked-evidence-paths.sh — HANDOFF-ANALYSIS-DIES-UNTRACKED-01
#
# docs/handoff/*/* is gitignored except a named allowlist (report.md,
# brief*.md, round*-red, fix-round*.md, continue-round*.md, context.yaml,
# architect-prepass.md, .gate1-passed, divergence.md — .gitignore:49-81).
# That allowlist is a closed decision (brief §Задача) and is NOT reopened
# here. What this suite catches instead: a path CITED BY one of those
# allowlisted docs, or by docs/leadv2/scheduled-decisions.md, as evidence
# for a claim, that itself never made it into git — the exact failure
# the brief measured (a scheduled-decisions.md row pointing at a file git
# never saw; a report.md pointing at another lane's dead artifact).
#
# Scope decision (documented, not left implicit): a cited path is checked
# only when it (a) currently exists on disk under repo root — a path whose
# target is already gone from every worktree cannot be un-lost by a test
# assertion, so re-litigating repo archaeology is out of scope — and (b) its
# basename does not match a known per-run scratch pattern (stream/session
# logs, locks, pids, stamps, pulse/receipt state) that .gitignore's own
# comment (line 47-48) already calls out as intentionally-ignored churn, not
# evidence. This keeps the suite green on today's tree while still catching
# a *new* citation of a real, uncommitted file — the failure mode in scope.
#
# Two checks:
#   A) every backtick-quoted path referenced by docs/leadv2/scheduled-decisions.md
#      (a scheduled action naming a file it depends on) must be `git ls-files`-visible.
#   B) every backtick-quoted docs/handoff/<id>/<name> path referenced by a
#      TRACKED evidence-family doc (report.md, brief*.md, round*-red/*,
#      fix-round*.md, continue-round*.md, divergence.md, architect-prepass.md)
#      — i.e. a lane citing another artifact as its own proof — must be
#      `git ls-files`-visible too.
#
# Negative control (RED, fixture-only — never touches this repo's real
# index): seed a throwaway git repo with a scheduled-decisions.md citing a
# tracked file, prove the check passes (baseline_rc=0), then `git rm --cached`
# that exact file — content stays on disk, only the index entry drops,
# reproducing exactly what a silent `git add` swallow leaves behind — and
# prove the SAME check function now fails (mutated_rc!=0) with a printed FAIL
# line naming the path. No diff_hash: baseline_rc/mutated_rc pair + the red
# line themselves are the evidence (brief §Приёмка item 2).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${ROOT}" ]]; then
  echo "FAIL: cannot resolve repo root from ${SCRIPT_DIR} via git" >&2
  exit 1
fi

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

# extract_cited_paths <root> <pattern> <file...> -> repo-relative paths, one
# per line, that are backtick-quoted in <file...>, match <pattern> (an
# ERE anchored to the whole backtick span), currently exist under <root>,
# and are not per-run scratch by basename.
extract_cited_paths() {
  local root="$1" pattern="$2"; shift 2
  local f p base
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    grep -oE "\`${pattern}\`" "$f" 2>/dev/null
  done | tr -d '`' | sort -u | while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    [[ -f "${root}/${p}" ]] || continue
    base="$(basename "$p")"
    case "$base" in
      *.jsonl|*.lock|*.pid|*.log|*stream*|*session*|*.stamp|*pulse*|*receipt*|.gate1-passed) continue ;;
    esac
    printf '%s\n' "$p"
  done
}

# check_tracked_paths <root> <paths-file> -> prints PASS/FAIL per path (via
# the pass/fail globals when called live; the fixture run below shells out
# to a subshell copy instead so fixture noise never touches PASS/FAIL here).
# Returns 1 if any path in <paths-file> is not `git ls-files`-visible.
check_tracked_paths() {
  local root="$1" paths_file="$2" rc=0 p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if git -C "${root}" ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
      pass "tracked: $p"
    else
      fail "NOT tracked: $p (git ls-files --error-unmatch failed)"
      rc=1
    fi
  done < "${paths_file}"
  return "${rc}"
}

# check_tracked_paths_quiet <root> <paths-file> -> same assertion as
# check_tracked_paths but prints raw PASS:/FAIL: lines instead of touching
# the pass()/fail() globals -- used by the fixture RED control below so a
# throwaway fixture path never pollutes this suite's own PASS/FAIL tally.
check_tracked_paths_quiet() {
  local root="$1" paths_file="$2" rc=0 p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if git -C "${root}" ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
      printf 'PASS: tracked: %s\n' "$p"
    else
      printf 'FAIL: NOT tracked: %s\n' "$p"
      rc=1
    fi
  done < "${paths_file}"
  return "${rc}"
}

# ── A: scheduled-decisions.md citations ─────────────────────────────────────
SD_FILE="${ROOT}/docs/leadv2/scheduled-decisions.md"
a_paths="$(mktemp)"
if [[ -f "${SD_FILE}" ]]; then
  extract_cited_paths "${ROOT}" '[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+' "${SD_FILE}" > "${a_paths}"
else
  : > "${a_paths}"
fi
if [[ -s "${a_paths}" ]]; then
  check_tracked_paths "${ROOT}" "${a_paths}" || true
else
  fail "check A found zero citable paths in scheduled-decisions.md (extractor or fixture drifted)"
fi
rm -f "${a_paths}"

# ── B: evidence-family doc citations ────────────────────────────────────────
family_files="$(git -C "${ROOT}" ls-files \
  'docs/handoff/*/report.md' 'docs/handoff/*/brief*.md' \
  'docs/handoff/*/round*-red' 'docs/handoff/*/round*-red/*' \
  'docs/handoff/*/fix-round*.md' 'docs/handoff/*/continue-round*.md' \
  'docs/handoff/*/divergence.md' 'docs/handoff/*/architect-prepass.md' \
  2>/dev/null | sed "s#^#${ROOT}/#")"
b_paths="$(mktemp)"
if [[ -n "${family_files}" ]]; then
  # shellcheck disable=SC2086 -- intentional word-split of a newline list of real repo paths
  extract_cited_paths "${ROOT}" 'docs/handoff/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+' ${family_files} > "${b_paths}"
else
  : > "${b_paths}"
fi
if [[ -s "${b_paths}" ]]; then
  check_tracked_paths "${ROOT}" "${b_paths}" || true
else
  fail "check B found zero citable paths across evidence-family docs (extractor or corpus drifted)"
fi
rm -f "${b_paths}"

# ── RED control: git rm --cached inside a throwaway fixture repo ───────────
FIXTURE="$(mktemp -d)"
cleanup_fixture() { [[ -n "${FIXTURE:-}" && -d "${FIXTURE}" ]] && rm -rf "${FIXTURE}"; }
trap cleanup_fixture EXIT

(
  cd "${FIXTURE}" || exit 1
  git init -q
  git config user.email t@example.com
  git config user.name t
  mkdir -p docs/leadv2 plugins/leadv2/scripts
  printf '# scheduled\n\nSee `plugins/leadv2/scripts/fake-carrier.sh` for the action.\n' \
    > docs/leadv2/scheduled-decisions.md
  printf '#!/usr/bin/env bash\necho fake carrier\n' > plugins/leadv2/scripts/fake-carrier.sh
  git add -A
  git commit -qm seed
) || { fail "RED control: fixture setup failed"; }

fx_paths="$(mktemp)"
extract_cited_paths "${FIXTURE}" '[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+' \
  "${FIXTURE}/docs/leadv2/scheduled-decisions.md" > "${fx_paths}"

baseline_out="$(check_tracked_paths_quiet "${FIXTURE}" "${fx_paths}")"
baseline_rc=$?

git -C "${FIXTURE}" rm --cached -q plugins/leadv2/scripts/fake-carrier.sh

mutated_out="$(check_tracked_paths_quiet "${FIXTURE}" "${fx_paths}")"
mutated_rc=$?
rm -f "${fx_paths}"

printf 'RED control: baseline_rc=%s mutated_rc=%s\n' "${baseline_rc}" "${mutated_rc}"
printf 'RED control: baseline_out=%s\n' "${baseline_out}"
printf 'RED control: mutated_out=%s\n' "${mutated_out}"

if [[ "${baseline_rc}" -eq 0 ]]; then
  pass "RED control: baseline_rc=0 (fixture file tracked, check green before mutation)"
else
  fail "RED control: baseline_rc=${baseline_rc}, expected 0 -- fixture itself is broken"
fi
if [[ "${mutated_rc}" -ne 0 ]] && [[ "${mutated_out}" == *"FAIL: NOT tracked: plugins/leadv2/scripts/fake-carrier.sh"* ]]; then
  pass "RED control: mutated_rc=${mutated_rc} with a red line naming the untracked path (git rm --cached caught)"
else
  fail "RED control: mutation did not turn the check red (mutated_rc=${mutated_rc}) -- check has no teeth"
fi

printf 'test-tracked-evidence-paths: %d passed, %d failed\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
