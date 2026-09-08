#!/usr/bin/env bash
# test-plugin-sync-is-link-only.sh — C1-RETIRE-RSYNC (2026-09-08).
#
# Acceptance criterion of the lane: after this change, a --write run of
# leadv2-plugin-sync.sh creates NO new real copy of a plugin-owned file in
# any destination it converts — (b) ~/.claude/leadv2-shared, (d) project
# contracts, (e) ~/.claude/scripts. An absent plugin-owned file enters as a
# symlink resolving into plugins/leadv2/ — asserted as a FILESYSTEM FACT
# (test -L + readlink), never a log line.
#
# Two negative controls (E2E-KILLRATE-01), both pinned by this suite:
#   SYMPTOM — against the pre-change script (LEADV2_PLUGIN_SYNC_UNDER_TEST
#   pointing at a copy of the anchor-commit version) this suite goes RED:
#   the old rsync legs leave real files where this suite demands links.
#   GUARD — a canonical file that is NOT plugin-owned (present in the tree,
#   NOT in `git ls-files plugins/leadv2/...`) must remain a real file and
#   must never be replaced by a link. Breaking _is_plugin_owned to return 0
#   ("treat everything as plugin-owned") reddens this suite on a value.
#
# Also pins the lane boundaries: drifted real copies are left real (bulk
# conversion is SD-SYMLINK-FARM-CONVERT-01, step 3), the retired (a) cache
# leg writes nothing, and the producer removes its own dead links (UNLINK)
# but never touches foreign ones.
#
# Runs the REAL leadv2-plugin-sync.sh against an isolated canonical tree +
# HOME (test-plugin-sync-claude-scripts.sh pattern; no mocked functions).
# run-all-triggers: leadv2-plugin-sync
#
# SUITE-SELECTION-COVERS-140-OF-390-01: triggers are the production files the
# suite's own body references most, so `run-all.sh --scope changed` selects it
# on any leadv2-plugin-sync.sh change.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../scripts" && pwd)"
PLUGIN_SYNC="${LEADV2_PLUGIN_SYNC_UNDER_TEST:-${PLUGIN_DIR}/leadv2-plugin-sync.sh}"

pass=0
fail=0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

check() {
  local got="$1" want_substr="$2" label="$3"
  if [[ "$got" == *"$want_substr"* ]]; then
    printf '[TEST] PASS: %s\n' "$label"; pass=$((pass+1))
  else
    printf '[TEST] FAIL: %s\n  got: %s\n  want substring: %s\n' "$label" "$got" "$want_substr" >&2
    fail=$((fail+1))
  fi
}

is_link_into_canon() { # $1 = dst file, $2 = canonical root prefix
  [[ -L "$1" ]] || return 1
  local resolved
  resolved="$(readlink "$1")"
  [[ "$resolved" == "$2"/plugins/leadv2/* ]]
}

# ── Fixture: isolated canonical git tree ──────────────────────────────────────
canon="$tmp/canon"
mkdir -p "$canon/plugins/leadv2/scripts" "$canon/plugins/leadv2/contracts" "$canon/plugins/leadv2/hooks"
printf '#!/usr/bin/env bash\necho "canonical good"\n' > "$canon/plugins/leadv2/scripts/leadv2-good.sh"
printf '#!/usr/bin/env bash\necho ok\n' > "$canon/plugins/leadv2/scripts/tool.sh"
printf '#!/usr/bin/env bash\necho hook\n' > "$canon/plugins/leadv2/hooks/leadv2-hook.sh"
printf '{"schema": "scorecard", "v": 1}\n' > "$canon/plugins/leadv2/contracts/leadv2-scorecard.schema.json"
printf '{"schema": "shadow-proposal", "v": 1}\n' > "$canon/plugins/leadv2/contracts/leadv2-shadow-proposal.schema.json"
(cd "$canon" && git init -q && git config user.email test@example.invalid \
  && git config user.name link-only-test && git add -A && git commit -q -m "init")

# NOT plugin-owned: present in the canonical TREE, absent from git ls-files.
printf '#!/usr/bin/env bash\necho "stray uncommitted"\n' > "$canon/plugins/leadv2/scripts/leadv2-stray.sh"

home="$tmp/home"
mkdir -p "$home"

# GUARD pre-state: the same-content REAL copy of the untracked canonical file
# (as a legacy rsync would have delivered it), a foreign destination-only
# script, and a drifted real shadow of a plugin-owned file.
mkdir -p "$home/.claude/leadv2-shared/scripts" "$home/.claude/scripts"
printf '#!/usr/bin/env bash\necho "stray uncommitted"\n' > "$home/.claude/leadv2-shared/scripts/leadv2-stray.sh"
printf '#!/usr/bin/env bash\necho "user tool"\n' > "$home/.claude/scripts/not-leadv2-mine.sh"
printf '#!/usr/bin/env bash\necho "OLD DIVERGENT"\n' > "$home/.claude/leadv2-shared/scripts/leadv2-good.sh"

# Retired (a): canary inside the orphaned cache version dir.
cache_dir="$home/.claude/plugins/cache/leadv2-local/leadv2/0.1.0"
mkdir -p "$cache_dir"
printf 'canary\n' > "$cache_dir/CANARY"

# (d) project: non-git dir, one divergent real schema already present.
proj="$tmp/proj"
mkdir -p "$proj/.claude/contracts"
printf '{"schema": "scorecard", "v": 2, "local-edit": true}\n' > "$proj/.claude/contracts/leadv2-scorecard.schema.json"

run_sync() {
  local rc=0
  env -u LEADV2_PROJECT_ROOT -u LEADV2_STATE_ROOT -u PROJECT_ROOT \
    HOME="$home" LEADV2_CANONICAL_ROOT="$canon" \
    LEADV2_QUARANTINE_ROOT="$tmp/quarantine" \
    bash "$PLUGIN_SYNC" --write --project-root "$proj" >"$tmp/run.out" 2>"$tmp/run.log" || rc=$?
  return "$rc"
}

rc=0
run_sync || rc=$?
run_log="$(cat "$tmp/run.log")"

# ── Case 1 SYMPTOM (b): absent plugin-owned files enter as links ─────────────
for f in ".claude/leadv2-shared/scripts/tool.sh" \
         ".claude/leadv2-shared/hooks/leadv2-hook.sh" \
         ".claude/leadv2-shared/contracts/leadv2-scorecard.schema.json" \
         ".claude/scripts/leadv2-good.sh"; do
  if is_link_into_canon "$home/$f" "$canon"; then
    printf '[TEST] PASS: Case 1: %s is a symlink into canonical\n' "$f"; pass=$((pass+1))
  else
    printf '[TEST] FAIL: Case 1: %s is not a symlink into canonical\n' "$f" >&2
    ls -la "$home/$f" >&2 || true
    fail=$((fail+1))
  fi
done

# ── Case 2 GUARD: not-plugin-owned stays REAL, logged, never linked ──────────
if [[ -L "$home/.claude/leadv2-shared/scripts/leadv2-stray.sh" ]]; then
  printf '[TEST] FAIL: Case 2: untracked canonical file was replaced by a link\n' >&2
  fail=$((fail+1))
else
  printf '[TEST] PASS: Case 2: untracked canonical copy stays a real file\n'; pass=$((pass+1))
fi
check "$run_log" "SKIP-UNTRACKED: $home/.claude/leadv2-shared/scripts/leadv2-stray.sh" \
  "Case 2: SKIP-UNTRACKED logged for the not-plugin-owned file"
if printf '#!/usr/bin/env bash\necho "user tool"\n' | cmp -s - "$home/.claude/scripts/not-leadv2-mine.sh"; then
  printf '[TEST] PASS: Case 2: foreign destination-only script untouched\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 2: foreign destination-only script changed/vanished\n' >&2; fail=$((fail+1))
fi

# ── Case 3 BOUNDARY: drifted shadow NOT converted (stays real) ───────────────
if [[ -L "$home/.claude/leadv2-shared/scripts/leadv2-good.sh" ]]; then
  printf '[TEST] FAIL: Case 3: drifted shadow was converted to a link (SD-SYMLINK-FARM-CONVERT-01 is step 3)\n' >&2
  fail=$((fail+1))
else
  printf '[TEST] PASS: Case 3: drifted shadow left as a real file\n'; pass=$((pass+1))
fi
check "$run_log" "DRIFT: $home/.claude/leadv2-shared/scripts/leadv2-good.sh" \
  "Case 3: DRIFT logged for the drifted shadow"

# ── Case 4 (a) retired: the orphaned cache dir receives nothing ──────────────
if [[ "$(ls -A "$cache_dir" | tr -d ' \n')" == "CANARY" ]] && [[ "$(cat "$cache_dir/CANARY")" == "canary" ]]; then
  printf '[TEST] PASS: Case 4: retired (a) wrote nothing to the 0.1.0 cache dir\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 4: cache 0.1.0 was written: %s\n' "$(ls -A "$cache_dir")" >&2; fail=$((fail+1))
fi

# ── Case 5 (d): project contracts are link-only ──────────────────────────────
if is_link_into_canon "$proj/.claude/contracts/leadv2-shadow-proposal.schema.json" "$canon"; then
  printf '[TEST] PASS: Case 5: absent project contract enters as a link\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 5: absent project contract is not a link\n' >&2; fail=$((fail+1))
fi
if [[ -L "$proj/.claude/contracts/leadv2-scorecard.schema.json" ]]; then
  printf '[TEST] FAIL: Case 5: divergent project contract was converted\n' >&2; fail=$((fail+1))
else
  printf '[TEST] PASS: Case 5: divergent project contract left real\n'; pass=$((pass+1))
fi
check "$run_log" "DRIFT: $proj/.claude/contracts/leadv2-scorecard.schema.json" \
  "Case 5: DRIFT logged for the divergent project contract"

# ── Case 6 idempotence: a second --write keeps the links and stays rc=0 ──────
rc2=0
run_sync || rc2=$?
if [[ "$rc2" -eq 0 ]]; then
  printf '[TEST] PASS: Case 6: second --write exits 0\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 6: second --write exited %s\n' "$rc2" >&2; fail=$((fail+1))
fi
if is_link_into_canon "$home/.claude/scripts/leadv2-good.sh" "$canon"; then
  printf '[TEST] PASS: Case 6: links survive the second run\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 6: links lost after the second run\n' >&2; fail=$((fail+1))
fi

# ── Case 7 UNLINK: a producer-owned dead link is removed, foreign kept ───────
rm "$canon/plugins/leadv2/scripts/tool.sh"
(cd "$canon" && git add -A && git commit -q -m "remove tool.sh")
rc3=0
run_sync || rc3=$?
run3_log="$(cat "$tmp/run.log")"
if [[ ! -e "$home/.claude/leadv2-shared/scripts/tool.sh" && ! -L "$home/.claude/leadv2-shared/scripts/tool.sh" ]]; then
  printf '[TEST] PASS: Case 7: dead producer link removed after canonical deletion\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 7: dead producer link still present\n' >&2; fail=$((fail+1))
fi
check "$run3_log" "UNLINK: $home/.claude/leadv2-shared/scripts/tool.sh" \
  "Case 7: UNLINK logged"
if [[ -f "$home/.claude/scripts/not-leadv2-mine.sh" ]]; then
  printf '[TEST] PASS: Case 7: foreign file untouched by UNLINK pass\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 7: foreign file vanished in UNLINK pass\n' >&2; fail=$((fail+1))
fi

# ── Case 8 no silence: every converted destination logs its tally ────────────
check "$run_log" "link-only[shared/scripts]:" "Case 8: shared/scripts tally line present"
check "$run_log" "link-only[user-scripts]:" "Case 8: user-scripts tally line present"

printf '\n[TEST] plugin-sync is-link-only: %s passed, %s failed\n' "$pass" "$fail"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
