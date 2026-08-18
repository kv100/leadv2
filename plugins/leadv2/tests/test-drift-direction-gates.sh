#!/usr/bin/env bash
# tests/test-drift-direction-gates.sh — DRIFT-GUARD-ADVISES-BACKWARD-SYNC-01
# regression coverage for the direction classifier (leadv2-drift-guard.sh
# decide_direction()) and the plugin-sync write gates (leadv2-plugin-sync.sh
# gate-1 uncommitted-destination refusal, gate-2 backward-move refusal,
# dry-run-by-default). Six write gates and a three-way direction classifier
# shipped with zero regression tests — this file is that coverage.
#
# All fixtures live under a scratch dir from mktemp -d; the live checkout
# and real $HOME are NEVER touched. Every drift-guard/plugin-sync invocation
# below sets both LEADV2_CANONICAL_ROOT and HOME to fixture paths.
#
# Usage: bash tests/test-drift-direction-gates.sh
# Exit 0 = all pass; non-zero = failure count.
set -euo pipefail

SCRIPTS_DIR="$(cd "${BASH_SOURCE[0]%/*}/../scripts" && pwd)"
DRIFT_GUARD="${SCRIPTS_DIR}/leadv2-drift-guard.sh"
PLUGIN_SYNC="${SCRIPTS_DIR}/leadv2-plugin-sync.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "FAIL: $1"; FAIL=$(( FAIL + 1 )); }

FIXTURE_ROOT="$(mktemp -d)"
cleanup() { rm -rf "${FIXTURE_ROOT}"; }
trap cleanup EXIT

# Hard safety net (risk table row 3): never let a fixture bug point a real
# sync at the live tree. Every case below must operate strictly inside this
# root, so refuse to proceed at all if mktemp handed back anything else.
case "${FIXTURE_ROOT}" in
  /tmp/*|/var/folders/*) : ;;
  *) echo "FATAL: fixture root not under /tmp or /var/folders: ${FIXTURE_ROOT}" >&2; exit 2 ;;
esac

# ── shared fixture helpers ──────────────────────────────────────────────────

# git_commit_at <repo> <iso8601> <message> — commit with author+committer
# date pinned, so `git log -1 --format=%ct` is fully controlled (that's the
# evidence decide_direction() and _sync_direction_of() both read).
git_commit_at() {
  local repo="$1" when="$2" msg="$3"
  ( cd "${repo}" && GIT_AUTHOR_DATE="${when}" GIT_COMMITTER_DATE="${when}" \
      git commit -q -m "${msg}" )
}

# new_canonical_fixture — fresh $FIXTURE_ROOT/case-N/canonical, git-init'd,
# with plugins/leadv2/scripts/ ready for files. Returns the path on stdout.
new_canonical_fixture() {
  local dir="$1"
  local canon="${dir}/canonical"
  mkdir -p "${canon}/plugins/leadv2/scripts"
  ( cd "${canon}" && git init -q && git config user.email t@t.com && git config user.name t )
  printf -- '%s\n' "${canon}"
}

tree_checksum() {
  # Deterministic whole-tree content+path checksum (order-independent per
  # file, sorted, so add/remove/modify anywhere in $1 is detected).
  find "$1" -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}'
}

# ── Case 1: vendored copy committed after canonical -> VENDORED_NEWER ──────
run_case1() {
  local dir="${FIXTURE_ROOT}/case1"
  local canon; canon="$(new_canonical_fixture "${dir}")"
  local f="${canon}/plugins/leadv2/scripts/dummy.sh"
  printf -- '#!/usr/bin/env bash\necho canonical\n' > "${f}"
  ( cd "${canon}" && git add plugins/leadv2/scripts/dummy.sh )
  git_commit_at "${canon}" "2026-01-01T00:00:00" "canonical version"

  mkdir -p "${canon}/.claude/scripts"
  local copy="${canon}/.claude/scripts/dummy.sh"
  printf -- '#!/usr/bin/env bash\necho vendored-newer\n' > "${copy}"
  touch -d "2026-01-10T00:00:00" "${copy}"

  local home="${dir}/home"; mkdir -p "${home}"
  local out
  out="$(LEADV2_CANONICAL_ROOT="${canon}" LEADV2_HOME_ROOT="${home}" bash "${DRIFT_GUARD}" 2>&1)" || true

  if echo "${out}" | grep -q "leadv2-repo-vendored.*dummy\.sh.*VENDORED_NEWER" \
     && echo "${out}" | grep -q "promote vendored -> canonical"; then
    pass "case1: vendored-committed-after-canonical -> VENDORED_NEWER + promote remedy"
  else
    fail "case1: expected VENDORED_NEWER + promote remedy, got: $(echo "${out}" | grep -i dummy || echo '<no dummy.sh line>')"
  fi
  if echo "${out}" | grep -qi "sync.*from canonical.*dummy\.sh"; then
    fail "case1: output still recommends syncing FROM canonical for the newer vendored file"
  fi
}

# ── Case 2: canonical committed after vendored copy -> CANONICAL_NEWER ─────
run_case2() {
  local dir="${FIXTURE_ROOT}/case2"
  local canon; canon="$(new_canonical_fixture "${dir}")"
  mkdir -p "${canon}/.claude/scripts"
  local copy="${canon}/.claude/scripts/dummy.sh"
  printf -- '#!/usr/bin/env bash\necho vendored-old\n' > "${copy}"
  touch -d "2026-01-01T00:00:00" "${copy}"

  local f="${canon}/plugins/leadv2/scripts/dummy.sh"
  printf -- '#!/usr/bin/env bash\necho canonical-newer\n' > "${f}"
  ( cd "${canon}" && git add plugins/leadv2/scripts/dummy.sh )
  git_commit_at "${canon}" "2026-01-10T00:00:00" "canonical newer version"

  local home="${dir}/home"; mkdir -p "${home}"
  local out
  out="$(LEADV2_CANONICAL_ROOT="${canon}" LEADV2_HOME_ROOT="${home}" bash "${DRIFT_GUARD}" 2>&1)" || true

  if echo "${out}" | grep -q "leadv2-repo-vendored.*dummy\.sh.*CANONICAL_NEWER"; then
    pass "case2: canonical-committed-after-vendored -> CANONICAL_NEWER"
  else
    fail "case2: expected CANONICAL_NEWER, got: $(echo "${out}" | grep -i dummy || echo '<no dummy.sh line>')"
  fi
}

# ── Case 3: commit times within the 2s buffer -> UNKNOWN ───────────────────
run_case3() {
  local dir="${FIXTURE_ROOT}/case3"
  local canon; canon="$(new_canonical_fixture "${dir}")"
  local f="${canon}/plugins/leadv2/scripts/dummy.sh"
  printf -- '#!/usr/bin/env bash\necho canonical\n' > "${f}"
  ( cd "${canon}" && git add plugins/leadv2/scripts/dummy.sh )
  git_commit_at "${canon}" "2026-01-01T00:00:00" "canonical version"

  mkdir -p "${canon}/.claude/scripts"
  local copy="${canon}/.claude/scripts/dummy.sh"
  printf -- '#!/usr/bin/env bash\necho vendored\n' > "${copy}"
  # 1s inside the 2s buffer -> must NOT classify either direction.
  touch -d "2026-01-01T00:00:01" "${copy}"

  local home="${dir}/home"; mkdir -p "${home}"
  local out
  out="$(LEADV2_CANONICAL_ROOT="${canon}" LEADV2_HOME_ROOT="${home}" bash "${DRIFT_GUARD}" 2>&1)" || true

  if echo "${out}" | grep -q "leadv2-repo-vendored.*dummy\.sh.*UNKNOWN" \
     && echo "${out}" | grep -qi "diff manually"; then
    pass "case3: within-2s-buffer -> UNKNOWN + diff-manually remedy"
  else
    fail "case3: expected UNKNOWN + diff-manually remedy, got: $(echo "${out}" | grep -i dummy || echo '<no dummy.sh line>')"
  fi
}

# ── Case 4: 3 drifted files in one copy -> one SUMMARY-BY-COPY, total=3 ────
run_case4() {
  local dir="${FIXTURE_ROOT}/case4"
  local canon; canon="$(new_canonical_fixture "${dir}")"
  mkdir -p "${canon}/.claude/scripts"
  for n in a b c; do
    local f="${canon}/plugins/leadv2/scripts/${n}.sh"
    printf -- '#!/usr/bin/env bash\necho %s-canonical\n' "${n}" > "${f}"
    ( cd "${canon}" && git add "plugins/leadv2/scripts/${n}.sh" )
  done
  git_commit_at "${canon}" "2026-01-01T00:00:00" "three canonical files"
  for n in a b c; do
    local copy="${canon}/.claude/scripts/${n}.sh"
    printf -- '#!/usr/bin/env bash\necho %s-vendored\n' "${n}" > "${copy}"
    touch -d "2026-01-10T00:00:00" "${copy}"
  done

  local home="${dir}/home"; mkdir -p "${home}"
  local out
  out="$(LEADV2_CANONICAL_ROOT="${canon}" LEADV2_HOME_ROOT="${home}" bash "${DRIFT_GUARD}" 2>&1)" || true

  local summary_lines
  summary_lines="$(echo "${out}" | grep -c "SUMMARY-BY-COPY: leadv2-repo-vendored:" || true)"
  if [[ "${summary_lines}" -eq 1 ]] && echo "${out}" | grep -q "SUMMARY-BY-COPY: leadv2-repo-vendored: 3 entries"; then
    pass "case4: 3 drifted files -> exactly one SUMMARY-BY-COPY line, total=3"
  else
    fail "case4: expected exactly 1 SUMMARY-BY-COPY line with 3 entries (got ${summary_lines} lines): $(echo "${out}" | grep 'SUMMARY-BY-COPY' || echo '<none>')"
  fi
}

# ── plugin-sync fixture: canonical + a git-tracked "shared" destination ────
# Uses the (b) leadv2-shared target, the simplest destination that is (a)
# reachable without --project-root/cross-repo-paths.yaml plumbing and (b)
# already routed through _direction_safety_excludes (the function carrying
# both write gates), by pointing $HOME at the fixture.
new_sync_fixture() {
  local dir="$1"
  local canon; canon="$(new_canonical_fixture "${dir}")"
  local f="${canon}/plugins/leadv2/scripts/dummy.sh"
  printf -- '#!/usr/bin/env bash\necho canonical\n' > "${f}"
  ( cd "${canon}" && git add plugins/leadv2/scripts/dummy.sh )
  git_commit_at "${canon}" "2026-01-05T00:00:00" "canonical version"

  local home="${dir}/home"
  local shared="${home}/.claude/leadv2-shared"
  mkdir -p "${shared}/scripts"
  ( cd "${shared}" && git init -q && git config user.email t@t.com && git config user.name t )
  cp "${f}" "${shared}/scripts/dummy.sh"
  ( cd "${shared}" && git add scripts/dummy.sh && git commit -q -m "seed shared copy" )

  printf -- '%s\t%s\n' "${canon}" "${home}"
}

run_sync() {
  # $1 canon $2 home; remaining args passed through to plugin-sync.sh
  local canon="$1" home="$2"; shift 2
  LEADV2_CANONICAL_ROOT="${canon}" HOME="${home}" bash "${PLUGIN_SYNC}" "$@" 2>&1
}

# ── Case 5: destination tracked-and-modified -> refused, incl. under
#            --allow-backward (gate 1 has NO override — the assertion most
#            likely to rot per the architect risk table). ────────────────
run_case5() {
  local dir="${FIXTURE_ROOT}/case5"
  local pair; pair="$(new_sync_fixture "${dir}")"
  local canon="${pair%%$'\t'*}" home="${pair##*$'\t'}"
  local dst="${home}/.claude/leadv2-shared/scripts/dummy.sh"
  printf -- '#!/usr/bin/env bash\necho locally-edited-uncommitted\n' > "${dst}"
  local before; before="$(cat "${dst}")"

  local out1
  out1="$(run_sync "${canon}" "${home}")" || true
  if ! echo "${out1}" | grep -qi "DRY_RUN REFUSED (uncommitted destination)"; then
    fail "case5: dry-run did not report the uncommitted-destination refusal"
  elif [[ "$(cat "${dst}")" != "${before}" ]]; then
    fail "case5: dry-run mutated the destination file"
  else
    pass "case5a: dry-run refuses uncommitted destination, writes nothing"
  fi

  local out2
  out2="$(run_sync "${canon}" "${home}" --write)" || true
  if echo "${out2}" | grep -qi "REFUSED: .*tracked-and-modified/uncommitted" && [[ "$(cat "${dst}")" == "${before}" ]]; then
    pass "case5b: --write refuses uncommitted destination, leaves it untouched"
  else
    fail "case5b: expected refusal + untouched file, got: $(echo "${out2}" | grep -i refus || echo '<no refusal line>')"
  fi

  local out3
  out3="$(run_sync "${canon}" "${home}" --write --allow-backward)" || true
  if echo "${out3}" | grep -qi "REFUSED: .*tracked-and-modified/uncommitted" && [[ "$(cat "${dst}")" == "${before}" ]]; then
    pass "case5c: --allow-backward does NOT override gate 1 (uncommitted destination still refused)"
  else
    fail "case5c: REGRESSION — --allow-backward overrode gate 1: $(echo "${out3}" | grep -i refus || echo '<no refusal line, file changed?>')"
  fi
}

# ── Case 6: destination newer (clean git state), no flag -> refused, byte-
#            identical destination after the run. ──────────────────────────
run_case6() {
  local dir="${FIXTURE_ROOT}/case6"
  local pair; pair="$(new_sync_fixture "${dir}")"
  local canon="${pair%%$'\t'*}" home="${pair##*$'\t'}"
  local dst="${home}/.claude/leadv2-shared/scripts/dummy.sh"
  printf -- '#!/usr/bin/env bash\necho committed-and-newer\n' > "${dst}"
  ( cd "${home}/.claude/leadv2-shared" && git add scripts/dummy.sh && git commit -q -m "newer committed edit" )
  touch -d "2026-02-01T00:00:00" "${dst}"
  local before_sum; before_sum="$(sha256sum "${dst}" | awk '{print $1}')"

  local out
  out="$(run_sync "${canon}" "${home}" --write)" || true
  local after_sum; after_sum="$(sha256sum "${dst}" | awk '{print $1}')"

  if echo "${out}" | grep -qi "REFUSED (backward)" && [[ "${before_sum}" == "${after_sum}" ]]; then
    pass "case6: destination newer, no flag -> refused, byte-identical after run"
  else
    fail "case6: expected backward refusal + unchanged file, got: $(echo "${out}" | grep -i refus || echo '<no refusal line>') (checksum before=${before_sum} after=${after_sum})"
  fi
}

# ── Case 7: destination newer, --allow-backward -> written, quarantine
#            path printed. ──────────────────────────────────────────────────
run_case7() {
  local dir="${FIXTURE_ROOT}/case7"
  local pair; pair="$(new_sync_fixture "${dir}")"
  local canon="${pair%%$'\t'*}" home="${pair##*$'\t'}"
  local dst="${home}/.claude/leadv2-shared/scripts/dummy.sh"
  printf -- '#!/usr/bin/env bash\necho committed-and-newer\n' > "${dst}"
  ( cd "${home}/.claude/leadv2-shared" && git add scripts/dummy.sh && git commit -q -m "newer committed edit" )
  touch -d "2026-02-01T00:00:00" "${dst}"

  local out
  out="$(LEADV2_QUARANTINE_ROOT="${home}/.claude/leadv2-quarantine" run_sync "${canon}" "${home}" --write --allow-backward)" || true
  local canon_content; canon_content="$(cat "${canon}/plugins/leadv2/scripts/dummy.sh")"
  local dst_content; dst_content="$(cat "${dst}" 2>/dev/null || echo '<missing>')"

  if echo "${out}" | grep -qi "quarantine" && [[ "${dst_content}" == "${canon_content}" ]]; then
    pass "case7: destination newer + --allow-backward -> written from canonical, quarantine path printed"
  else
    fail "case7: expected write + quarantine mention, got dst=[${dst_content}] out-quarantine-line=[$(echo "${out}" | grep -i quarantine || echo none)]"
  fi
}

# ── Case 8: no flags at all -> zero writes anywhere in the destination
#            tree (dry-run default). Catches an accidental DRY_RUN=false
#            default via a whole-tree checksum, not just the one known file.
run_case8() {
  local dir="${FIXTURE_ROOT}/case8"
  local pair; pair="$(new_sync_fixture "${dir}")"
  local canon="${pair%%$'\t'*}" home="${pair##*$'\t'}"
  local before; before="$(tree_checksum "${home}")"

  run_sync "${canon}" "${home}" >/dev/null 2>&1 || true

  local after; after="$(tree_checksum "${home}")"
  if [[ "${before}" == "${after}" ]]; then
    pass "case8: bare invocation (no flags) writes nothing anywhere under \$HOME"
  else
    fail "case8: REGRESSION — bare invocation wrote to the destination tree (checksum before=${before} after=${after})"
  fi
}

# ── bash -n syntax gate on both scripts under test ─────────────────────────
if bash -n "${DRIFT_GUARD}" 2>/dev/null; then pass "bash -n: leadv2-drift-guard.sh"; else fail "bash -n: leadv2-drift-guard.sh"; fi
if bash -n "${PLUGIN_SYNC}" 2>/dev/null; then pass "bash -n: leadv2-plugin-sync.sh"; else fail "bash -n: leadv2-plugin-sync.sh"; fi

run_case1
run_case2
run_case3
run_case4
run_case5
run_case6
run_case7
run_case8

echo "----"
echo "PASS=${PASS} FAIL=${FAIL}"
[[ "${FAIL}" -eq 0 ]]
