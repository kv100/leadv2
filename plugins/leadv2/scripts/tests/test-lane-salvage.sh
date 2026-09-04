#!/usr/bin/env bash
# test-lane-salvage.sh — LANE-SALVAGE-TOOL-01
#
# Hermetic git-sandbox fixtures for leadv2-lane-salvage.sh. Every case is a
# from-scratch `git init` in a mktemp -d scratch dir (never a worktree of the
# real repo) with a stub tests/run-all.sh whose exit code the case controls
# through STUB_RC — so "salvaged_green" is provably "the suites ran green",
# not "the carry succeeded".
#
# Locked behaviours:
#   1. carry: branch cut from CURRENT main, anchors and merge commits
#      excluded, work commits present, suite actually invoked;
#   2. registration union: a tests/run-all.sh row-append conflict on both
#      sides resolves by union with row-count conservation
#      (after == ours + theirs - common), verified against the three git
#      blobs independently of the script's own arithmetic;
#   3. foreign conflict: a pick conflicting anywhere but the registration
#      list stops with verdict=conflict naming file and lines;
#   4. nothing_to_salvage: anchor-only lanes never create a branch;
#   5. green requires suite green (STUB_RC=1 -> salvaged_red);
#   6. a run-all.sh conflict over CODE (not registration rows) is refused;
#   7. lane resolution prefers the live worktree's HEAD over the branch;
#   8. commits whose patch is already on main drop out as empty picks;
#   and in every case: main's sha is identical before and after.
#
# The three required mutation controls (anchor exclusion, union line loss,
# main touched) live in leadv2-mutation-control.sh artifacts referenced from
# the lane report — they mutate function bodies of the salvage script and
# must turn THIS suite red.
#
# Bash 3.2 compatible: no associative arrays, no ${x^^}, no readarray.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SALVAGE="${SCRIPT_DIR}/../leadv2-lane-salvage.sh"

PASS=0
FAIL=0

_ok()   { PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
_fail() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }

# Registration-row regex kept in lockstep with the salvage script's.
REGROW_RE='^(EXTRA_SUITE_MAP=")?[A-Za-z0-9._/@+-]+:[^:#[:space:]]*test-[^:]*\.sh("?)$'

_mk_repo() { # -> stdout: fixture repo path with a 3-row registration map on main
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/lane-salvage-fixture.XXXXXX")"
  git -C "$tmp" init -q
  git -C "$tmp" config user.email t@t.example
  git -C "$tmp" config user.name t
  mkdir -p "$tmp/tests" "$tmp/plugins" "$tmp/docs"
  printf 'shared base\n' > "$tmp/shared.txt"
  # placeholder committed on base so plugins/ survives `git checkout main`
  # when a lane branch was the only thing tracking files in it
  printf 'placeholder\n' > "$tmp/plugins/placeholder.txt"
  cat > "$tmp/tests/run-all.sh" <<'STUB'
#!/usr/bin/env bash
# fixture stub of the repo runner — the salvage verdict must come from HERE
echo "STUB-RUN-ALL scope=$*"
exit "${STUB_RC:-0}"
STUB
  cat > "$tmp/tests/map.txt" <<'MAP'
EXTRA_SUITE_MAP="alpha.sh:plugins/leadv2/scripts/tests/test-alpha.sh
beta.sh:plugins/leadv2/scripts/tests/test-beta.sh
gamma.sh:plugins/leadv2/scripts/tests/test-gamma.sh"
MAP
  # The registration map lives inside tests/run-all.sh, like the real one.
  cat "$tmp/tests/map.txt" >> "$tmp/tests/run-all.sh"
  rm -f "$tmp/tests/map.txt"
  git -C "$tmp" add -A && git -C "$tmp" commit -qm "base"
  git -C "$tmp" branch -m main >/dev/null 2>&1 || true
  printf '%s\n' "$tmp"
}

_regrow_count() { # <repo> <ref> -> stdout: number of registration rows
  git -C "$1" show "$2:tests/run-all.sh" | grep -cE "${REGROW_RE}"
}

_main_sha() { git -C "$1" rev-parse main; }

# Run the salvage tool inside fixture repo $1 for lane $2; captures output;
# -> stdout: "<rc>" (tool exit code); output left in $3 (absolute path).
_run_salvage() { # <repo> <lane> <outfile>
  local repo="$1" lane="$2" out="$3" rc
  (cd "$repo" && bash "$SALVAGE" "$lane") > "$out" 2>&1
  rc=$?
  printf '%s' "$rc"
}

# ---------------------------------------------------------------------------
# Case 1: carry. Anchor + two work commits + a side branch merged in. Main
# advances after the fork. Expect green, cut from CURRENT main, anchor and
# merge commit excluded, suite invoked, main untouched.
# ---------------------------------------------------------------------------
test_carry_happy_path() {
  local repo out rc main_before
  repo="$(_mk_repo)"
  out="$(mktemp)"

  git -C "$repo" checkout -qb worktree-LANE1

  printf 'anchor\n' > "$repo/docs/anchor.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane LANE1 anchor"

  printf 'alpha v1\n' > "$repo/plugins/alpha.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "feat: alpha module"

  git -C "$repo" checkout -qb side1
  printf 'side work\n' > "$repo/plugins/side.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "chore: side work"
  git -C "$repo" checkout -q worktree-LANE1
  git -C "$repo" merge --no-edit --no-ff -q side1 >/dev/null 2>&1

  printf 'beta v1\n' > "$repo/plugins/beta.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "feat: beta module"

  git -C "$repo" checkout -q main
  printf 'main moved\n' >> "$repo/shared.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "main moves on"

  main_before="$(_main_sha "$repo")"
  rc="$(_run_salvage "$repo" LANE1 "$out")"

  if [[ "$rc" -eq 0 ]] && grep -q 'verdict=salvaged_green ' "$out" \
     && grep -q 'carried=3/3 ' "$out"; then
    _ok "case 1: salvaged_green carried=3/3 (anchor + merge excluded)"
  else
    _fail "case 1: expected salvaged_green carried=3/3 rc=0, got rc=$rc: $(tail -3 "$out")"
  fi

  if [[ "$(git -C "$repo" merge-base main salvage/LANE1)" == "$(_main_sha "$repo")" ]]; then
    _ok "case 1: salvage branch cut from CURRENT main"
  else
    _fail "case 1: merge-base(salvage, main) != main tip — not cut from current main"
  fi

  local subjects
  subjects="$(git -C "$repo" log --format=%s main..salvage/LANE1)"
  if ! grep -qi 'anchor' <<< "$subjects" \
     && ! grep -q 'Merge branch' <<< "$subjects" \
     && grep -q 'feat: alpha module' <<< "$subjects" \
     && grep -q 'feat: beta module' <<< "$subjects" \
     && grep -q 'chore: side work' <<< "$subjects"; then
    _ok "case 1: carried subjects are the work only (no anchor, no merge commit)"
  else
    _fail "case 1: wrong subjects carried: $(tr '\n' '|' <<< "$subjects")"
  fi

  if grep -q 'STUB-RUN-ALL scope=--scope changed' "$out"; then
    _ok "case 1: verdict backed by an actual suite run"
  else
    _fail "case 1: no suite invocation in output — green is unproven"
  fi

  if [[ "$(_main_sha "$repo")" == "$main_before" ]]; then
    _ok "case 1: main untouched"
  else
    _fail "case 1: main MOVED during salvage"
  fi

  rm -rf "$repo" "$out"
}

# ---------------------------------------------------------------------------
# Case 2: registration union. After the fork, main appends row M and the
# lane appends row L to EXTRA_SUITE_MAP. The pick must conflict, resolve by
# union, and conserve rows: after == ours + theirs - common, counted from
# the three git blobs independently of the script's arithmetic.
# ---------------------------------------------------------------------------
test_registration_union() {
  local repo out rc main_before ours_n theirs_n base_n after_n expect
  repo="$(_mk_repo)"
  out="$(mktemp)"

  git -C "$repo" checkout -qb worktree-LANE2
  printf 'lane-tool row\n' > "$repo/plugins/lane-tool.txt"
  # lane appends its registration row (last row carries the closing quote)
  git -C "$repo" show main:tests/run-all.sh \
    | sed -e 's|gamma.sh:plugins/leadv2/scripts/tests/test-gamma.sh"|gamma.sh:plugins/leadv2/scripts/tests/test-gamma.sh|' \
      -e '$a\
lane-tool.sh:plugins/leadv2/scripts/tests/test-lane-tool.sh"' > "$repo/tests/run-all.sh"
  git -C "$repo" add -A && git -C "$repo" commit -qm "feat: register lane-tool suite"

  git -C "$repo" checkout -q main
  printf 'main-tool row\n' > "$repo/plugins/main-tool.txt"
  git -C "$repo" show main:tests/run-all.sh \
    | sed -e 's|gamma.sh:plugins/leadv2/scripts/tests/test-gamma.sh"|gamma.sh:plugins/leadv2/scripts/tests/test-gamma.sh|' \
      -e '$a\
main-tool.sh:plugins/leadv2/scripts/tests/test-main-tool.sh"' > "$repo/tests/run-all.sh"
  git -C "$repo" add -A && git -C "$repo" commit -qm "feat: register main-tool suite"

  base_n="$(_regrow_count "$repo" 'main~1')"              # 3 rows before either append
  ours_n="$(_regrow_count "$repo" 'main')"                # main's side of the pick
  theirs_n="$(_regrow_count "$repo" 'worktree-LANE2')"    # lane's side of the pick

  main_before="$(_main_sha "$repo")"
  rc="$(_run_salvage "$repo" LANE2 "$out")"

  if [[ "$rc" -eq 0 ]] && grep -q 'verdict=salvaged_green ' "$out"; then
    _ok "case 2: registration conflict auto-unions to salvaged_green"
  else
    _fail "case 2: expected salvaged_green, got rc=$rc: $(tail -5 "$out")"
  fi

  after_n="$(_regrow_count "$repo" 'salvage/LANE2')"
  expect=$((ours_n + theirs_n - base_n))
  if [[ "$after_n" -eq "$expect" ]]; then
    _ok "case 2: no row lost — after=${after_n} == ours=${ours_n} + theirs=${theirs_n} - common=${base_n}"
  else
    _fail "case 2: row count off — after=${after_n} expected=${expect}"
  fi

  local resolved
  resolved="$(git -C "$repo" show salvage/LANE2:tests/run-all.sh)"
  if [[ "$(grep -c 'lane-tool.sh:plugins' <<< "$resolved")" -eq 1 ]] \
     && [[ "$(grep -c 'main-tool.sh:plugins' <<< "$resolved")" -eq 1 ]] \
     && bash -n <<< "$resolved"; then
    _ok "case 2: both new rows present exactly once, result parses (bash -n)"
  else
    _fail "case 2: resolved run-all.sh malformed or a row missing"
  fi

  if [[ "$(_main_sha "$repo")" == "$main_before" ]]; then
    _ok "case 2: main untouched"
  else
    _fail "case 2: main MOVED during salvage"
  fi

  rm -rf "$repo" "$out"
}

# ---------------------------------------------------------------------------
# Case 2b: registration union when OURS side of the hunk carries lines base
# never saw — a comment stem main added inside the map region after the lane
# forked (measured live: the merge-safety-gate carrier stem, 2026-09-04).
# Ours is kept verbatim so this is not a loss risk; the union must proceed.
# THEIRS side still carries only registration rows.
# ---------------------------------------------------------------------------
test_registration_union_ours_comment() {
  local repo out rc main_before ours_n theirs_n base_n after_n expect
  repo="$(_mk_repo)"
  out="$(mktemp)"

  git -C "$repo" checkout -qb worktree-LANE2B
  # lane appends its registration row (last row carries the closing quote)
  git -C "$repo" show main:tests/run-all.sh \
    | sed -e 's|gamma.sh:plugins/leadv2/scripts/tests/test-gamma.sh"|gamma.sh:plugins/leadv2/scripts/tests/test-gamma.sh|' \
      -e '$a\
lane2b.sh:plugins/leadv2/scripts/tests/test-lane2b.sh"' > "$repo/tests/run-all.sh"
  git -C "$repo" add -A && git -C "$repo" commit -qm "feat: register lane2b suite"

  git -C "$repo" checkout -q main
  # main adds a comment INSIDE the map region (base never saw it) + its own row
  git -C "$repo" show main:tests/run-all.sh \
    | sed -e 's|^EXTRA_SUITE_MAP="|# LANE-MERGE-SILENTLY-REVERTS-MAIN-01: carrier stem\
EXTRA_SUITE_MAP="|' \
      -e 's|gamma.sh:plugins/leadv2/scripts/tests/test-gamma.sh"|gamma.sh:plugins/leadv2/scripts/tests/test-gamma.sh|' \
      -e '$a\
main2b.sh:plugins/leadv2/scripts/tests/test-main2b.sh"' > "$repo/tests/run-all.sh"
  git -C "$repo" add -A && git -C "$repo" commit -qm "feat: comment stem + register main2b suite"

  base_n="$(_regrow_count "$repo" 'main~1')"
  ours_n="$(_regrow_count "$repo" 'main')"
  theirs_n="$(_regrow_count "$repo" 'worktree-LANE2B')"

  main_before="$(_main_sha "$repo")"
  rc="$(_run_salvage "$repo" LANE2B "$out")"

  if [[ "$rc" -eq 0 ]] && grep -q 'verdict=salvaged_green ' "$out"; then
    _ok "case 2b: ours-side comment in hunk does not block union"
  else
    _fail "case 2b: expected salvaged_green, got rc=$rc: $(tail -5 "$out")"
  fi

  after_n="$(_regrow_count "$repo" 'salvage/LANE2B')"
  expect=$((ours_n + theirs_n - base_n))
  if [[ "$after_n" -eq "$expect" ]]; then
    _ok "case 2b: no row lost — after=${after_n} == ours=${ours_n} + theirs=${theirs_n} - common=${base_n}"
  else
    _fail "case 2b: row count off — after=${after_n} expected=${expect}"
  fi

  local resolved
  resolved="$(git -C "$repo" show salvage/LANE2B:tests/run-all.sh)"
  if grep -q 'carrier stem' <<< "$resolved" \
     && [[ "$(grep -c 'lane2b.sh:plugins' <<< "$resolved")" -eq 1 ]] \
     && bash -n <<< "$resolved"; then
    _ok "case 2b: ours comment kept verbatim, lane row inserted, result parses"
  else
    _fail "case 2b: resolved run-all.sh lost the comment stem or malformed"
  fi

  if [[ "$(_main_sha "$repo")" == "$main_before" ]]; then
    _ok "case 2b: main untouched"
  else
    _fail "case 2b: main MOVED during salvage"
  fi

  rm -rf "$repo" "$out"
}

# ---------------------------------------------------------------------------
# Case 3: foreign conflict. The lane and main both edit the same line of a
# production file. The pick must stop with verdict=conflict, name the file,
# report conflicting lines, and never touch main.
# ---------------------------------------------------------------------------
test_foreign_conflict_stops() {
  local repo out rc main_before
  repo="$(_mk_repo)"
  out="$(mktemp)"

  git -C "$repo" checkout -qb worktree-LANE3
  printf 'lane version of the hot line\n' > "$repo/shared.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "feat: lane rewrites hot line"

  git -C "$repo" checkout -q main
  printf 'main version of the hot line\n' > "$repo/shared.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "main rewrites hot line"

  main_before="$(_main_sha "$repo")"
  rc="$(_run_salvage "$repo" LANE3 "$out")"

  if [[ "$rc" -eq 0 ]] && grep -q 'verdict=conflict ' "$out" \
     && grep -q 'conflict_files=shared.txt' "$out"; then
    _ok "case 3: foreign conflict -> verdict=conflict naming the file"
  else
    _fail "case 3: expected verdict=conflict conflict_files=shared.txt, got rc=$rc: $(tail -5 "$out")"
  fi

  if grep -q 'shared.txt: conflicting lines' "$out"; then
    _ok "case 3: conflict report carries the disputed line range"
  else
    _fail "case 3: no conflicting-lines report in output"
  fi

  if ! git -C "$repo" show-ref --verify -q refs/heads/salvage/LANE3; then
    _ok "case 3: empty-prefix conflict leaves no empty salvage branch"
  else
    _fail "case 3: salvage/LANE3 left behind despite empty prefix"
  fi

  if [[ "$(_main_sha "$repo")" == "$main_before" ]]; then
    _ok "case 3: main untouched"
  else
    _fail "case 3: main MOVED during salvage"
  fi

  rm -rf "$repo" "$out"
}

# ---------------------------------------------------------------------------
# Case 4: nothing to salvage. A lane whose only commit is its anchor.
# ---------------------------------------------------------------------------
test_nothing_to_salvage() {
  local repo out rc main_before
  repo="$(_mk_repo)"
  out="$(mktemp)"

  git -C "$repo" checkout -qb worktree-LANE4
  printf 'anchor\n' > "$repo/docs/anchor.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane LANE4 anchor"

  git -C "$repo" checkout -q main

  main_before="$(_main_sha "$repo")"
  rc="$(_run_salvage "$repo" LANE4 "$out")"

  if [[ "$rc" -eq 0 ]] && grep -q 'verdict=nothing_to_salvage ' "$out" \
     && grep -q 'branch=- ' "$out"; then
    _ok "case 4: anchor-only lane -> nothing_to_salvage, no branch"
  else
    _fail "case 4: expected nothing_to_salvage branch=-, got rc=$rc: $(tail -3 "$out")"
  fi

  if ! grep -q 'STUB-RUN-ALL' "$out"; then
    _ok "case 4: no suite run when nothing was carried"
  else
    _fail "case 4: suite ran despite nothing to salvage"
  fi

  if [[ "$(_main_sha "$repo")" == "$main_before" ]]; then
    _ok "case 4: main untouched"
  else
    _fail "case 4: main MOVED during salvage"
  fi

  rm -rf "$repo" "$out"
}

# ---------------------------------------------------------------------------
# Case 5: green means SUITES green. Same happy shape as case 1 but the
# runner stub exits 1 — the carry succeeds and the verdict must be red.
# ---------------------------------------------------------------------------
test_red_until_suites_prove_green() {
  local repo out rc main_before
  repo="$(_mk_repo)"
  out="$(mktemp)"

  git -C "$repo" checkout -qb worktree-LANE5
  printf 'alpha v1\n' > "$repo/plugins/alpha.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "feat: alpha module"
  git -C "$repo" checkout -q main

  main_before="$(_main_sha "$repo")"
  # exported (not VAR=x cmd): an assignment-prefix does not reliably reach
  # the stub two process levels down
  export STUB_RC=1
  rc="$(_run_salvage "$repo" LANE5 "$out")"
  unset STUB_RC

  if [[ "$rc" -eq 0 ]] && grep -q 'verdict=salvaged_red ' "$out" \
     && grep -q 'suite_rc=1' "$out" && grep -q 'carried=1/1 ' "$out"; then
    _ok "case 5: carry ok + red suite -> salvaged_red (green is never 'it merged')"
  else
    _fail "case 5: expected salvaged_red suite_rc=1 carried=1/1, got rc=$rc: $(tail -3 "$out")"
  fi

  if [[ "$(_main_sha "$repo")" == "$main_before" ]]; then
    _ok "case 5: main untouched"
  else
    _fail "case 5: main MOVED during salvage"
  fi

  rm -rf "$repo" "$out"
}

# ---------------------------------------------------------------------------
# Case 6: run-all.sh conflict over CODE is refused. Both sides edit the
# stub's echo line differently AND the lane appends a registration row: the
# conflict hunk contains a code line, so no union — verdict=conflict.
# ---------------------------------------------------------------------------
test_code_conflict_in_run_all_refused() {
  local repo out rc main_before
  repo="$(_mk_repo)"
  out="$(mktemp)"

  git -C "$repo" checkout -qb worktree-LANE6
  git -C "$repo" show main:tests/run-all.sh \
    | sed -e 's|echo "STUB-RUN-ALL scope=\$\*"|echo "STUB-LANE scope=$*"|' \
      -e 's|gamma.sh:plugins/leadv2/scripts/tests/test-gamma.sh"|gamma.sh:plugins/leadv2/scripts/tests/test-gamma.sh|' \
      -e '$a\
lane6.sh:plugins/leadv2/scripts/tests/test-lane6.sh"' > "$repo/tests/run-all.sh"
  git -C "$repo" add -A && git -C "$repo" commit -qm "feat: lane6 restyles runner + row"

  git -C "$repo" checkout -q main
  git -C "$repo" show main:tests/run-all.sh \
    | sed -e 's|echo "STUB-RUN-ALL scope=\$\*"|echo "STUB-MAIN scope=$*"|' > "$repo/tests/run-all.sh"
  git -C "$repo" add -A && git -C "$repo" commit -qm "main restyles runner"

  main_before="$(_main_sha "$repo")"
  rc="$(_run_salvage "$repo" LANE6 "$out")"

  if [[ "$rc" -eq 0 ]] && grep -q 'verdict=conflict ' "$out" \
     && grep -q 'non-registration lines' "$out"; then
    _ok "case 6: code-line conflict inside run-all.sh refused (no guessing)"
  else
    _fail "case 6: expected verdict=conflict with refusal reason, got rc=$rc: $(tail -5 "$out")"
  fi

  if [[ "$(_main_sha "$repo")" == "$main_before" ]]; then
    _ok "case 6: main untouched"
  else
    _fail "case 6: main MOVED during salvage"
  fi

  rm -rf "$repo" "$out"
}

# ---------------------------------------------------------------------------
# Case 7: lane resolution prefers the live worktree's HEAD. The worktree is
# detached one commit AHEAD of branch worktree-LANE7 — the salvage must
# carry the newer commit, not the branch tip.
# ---------------------------------------------------------------------------
test_worktree_head_preferred() {
  local repo out rc main_before
  repo="$(_mk_repo)"
  out="$(mktemp)"

  git -C "$repo" checkout -qb worktree-LANE7
  printf 'branch tip work\n' > "$repo/plugins/w1.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "feat: w1 from branch"
  git -C "$repo" checkout -q main
  mkdir -p "${repo}-wts"
  git -C "$repo" worktree add --detach -q "${repo}-wts/LANE7" worktree-LANE7 >/dev/null 2>&1
  # extra commit ONLY in the worktree (detached), branch stays behind
  (cd "${repo}-wts/LANE7" \
    && printf 'worktree-only work\n' > plugins/w2.txt \
    && git add -A && git commit -qm "feat: w2 worktree only") >/dev/null 2>&1

  main_before="$(_main_sha "$repo")"
  rc="$(_run_salvage "$repo" LANE7 "$out")"

  if [[ "$rc" -eq 0 ]] && grep -q 'carried=2/2 ' "$out" \
     && git -C "$repo" show-ref --verify -q refs/heads/salvage/LANE7 \
     && git -C "$repo" show salvage/LANE7:plugins/w2.txt >/dev/null 2>&1; then
    _ok "case 7: lane resolved from the live worktree HEAD (w2 carried)"
  else
    _fail "case 7: worktree HEAD not used, got rc=$rc: $(tail -5 "$out")"
  fi

  if [[ "$(_main_sha "$repo")" == "$main_before" ]]; then
    _ok "case 7: main untouched"
  else
    _fail "case 7: main MOVED during salvage"
  fi

  git -C "$repo" worktree remove --force "${repo}-wts/LANE7" >/dev/null 2>&1
  rm -rf "$repo" "${repo}-wts" "$out"
}

# ---------------------------------------------------------------------------
# Case 8: commits whose patch is already on main drop out as empty picks —
# same change landed on main through another path. Nothing left to carry.
# ---------------------------------------------------------------------------
test_already_on_main_drops_empty() {
  local repo out rc main_before
  repo="$(_mk_repo)"
  out="$(mktemp)"

  git -C "$repo" checkout -qb worktree-LANE8
  printf 'z content\n' > "$repo/plugins/z.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "feat: add z module"

  git -C "$repo" checkout -q main
  printf 'z content\n' > "$repo/plugins/z.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "main lands z independently"

  main_before="$(_main_sha "$repo")"
  rc="$(_run_salvage "$repo" LANE8 "$out")"

  if [[ "$rc" -eq 0 ]] && grep -q 'verdict=nothing_to_salvage ' "$out" \
     && grep -q 'empty' "$out"; then
    _ok "case 8: already-on-main patch -> empty pick -> nothing_to_salvage"
  else
    _fail "case 8: expected nothing_to_salvage via empty pick, got rc=$rc: $(tail -3 "$out")"
  fi

  if [[ "$(_main_sha "$repo")" == "$main_before" ]]; then
    _ok "case 8: main untouched"
  else
    _fail "case 8: main MOVED during salvage"
  fi

  rm -rf "$repo" "$out"
}

# ---------------------------------------------------------------------------

if ! bash -n "$SALVAGE"; then
  _fail "bash -n leadv2-lane-salvage.sh"
else
  _ok "bash -n leadv2-lane-salvage.sh (incl. 3.2)"
fi

test_carry_happy_path
test_registration_union
test_registration_union_ours_comment
test_foreign_conflict_stops
test_nothing_to_salvage
test_red_until_suites_prove_green
test_code_conflict_in_run_all_refused
test_worktree_head_preferred
test_already_on_main_drops_empty

printf 'lane-salvage: pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
