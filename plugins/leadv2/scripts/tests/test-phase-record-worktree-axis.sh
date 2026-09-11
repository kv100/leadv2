#!/usr/bin/env bash
# run-all-triggers: leadv2-phase-record leadv2-test-context
# Exercise existing foreign records in real linked worktrees, never live state.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
unset PROJECT_ROOT LEADV2_PROJECT_ROOT
JOURNAL_STUB="$T/journal.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$JOURNAL_STUB"
chmod +x "$JOURNAL_STUB"
export LEADV2_JOURNAL_BIN="$JOURNAL_STUB" LEADV2_DISPATCH_CACHE_DIR="$T/cache"
export HOME="$T/home"
mkdir -p "$HOME" "$T/repo/scripts/lib" "$T/repo/docs/handoff/dispatch-axis0001/phases.d"
cp "$SCRIPTS/leadv2-phase-record.sh" "$T/repo/scripts/"
cp "$SCRIPTS/lib/leadv2-test-context.sh" "$T/repo/scripts/lib/"
R="$T/repo"; W="$T/worker"; P=docs/handoff/dispatch-axis0001/phases.d/e2e.yaml
printf 'phase: e2e\nstatus: running\nstarted_at: original\n' > "$R/$P"
git -C "$R" init -q
git -C "$R" add scripts/leadv2-phase-record.sh scripts/lib/leadv2-test-context.sh "$P"
git -C "$R" -c user.name=test -c user.email=test@example.invalid commit -qm fixture
git -C "$R" worktree add -q --detach "$W" HEAD
WRITER="$R/scripts/leadv2-phase-record.sh"
PASS=0; FAIL=0
ok() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }
run_record() { # cwd, root, context (unset uses ancestor detection)
  local context="$3"
  ( cd "$1" || exit 99
    unset LEADV2_TEST_CONTEXT
    [[ "$context" == unset ]] || export LEADV2_TEST_CONTEXT="$context"
    LEADV2_PROJECT_ROOT="$2" bash "$WRITER" record axis0001 e2e --status running --handle fixture
  ) > "$T/out" 2> "$T/err"
}
refused() {
  local label="$1" from="$2" root="$3" context="$4" rc=0
  git -C "$R" show "HEAD:$P" > "$root/$P"
  cp "$root/$P" "$T/before"
  run_record "$from" "$root" "$context" || rc=$?
  if [[ "$rc" != 0 ]] && grep -qi 'refus' "$T/err"; then ok "$label refused"; else bad "$label refused (rc=$rc)"; fi
  if cmp -s "$root/$P" "$T/before"; then ok "$label foreign bytes unchanged"; else bad "$label foreign bytes unchanged"; fi
}
refused 'production linked worktree' "$W" "$R" 0
refused 'test linked worktree' "$W" "$R" 1
refused 'test cwd fallback tree' "$R" "$R" 1
# Installed scripts need not themselves live in a Git checkout. An omitted
# redirect must still be refused when their cwd falls back to a live tree.
mkdir -p "$T/installed/lib"
cp "$WRITER" "$T/installed/"
cp "$SCRIPTS/lib/leadv2-test-context.sh" "$T/installed/lib/"
git -C "$R" show "HEAD:$P" > "$R/$P"
cp "$R/$P" "$T/before"
rc=0
(cd "$R" && LEADV2_TEST_CONTEXT=1 bash "$T/installed/leadv2-phase-record.sh" record axis0001 e2e --status running --handle fixture) > "$T/out" 2> "$T/err" || rc=$?
if [[ "$rc" != 0 ]] && grep -qi 'refus' "$T/err"; then ok 'installed writer without redirect refused'; else bad 'installed writer without redirect refused'; fi
if cmp -s "$R/$P" "$T/before"; then ok 'installed writer foreign bytes unchanged'; else bad 'installed writer foreign bytes unchanged'; fi
# Deterministic ancestor process fixture: process inspection is sandbox-dependent.
mkdir -p "$T/bin"
cat > "$T/bin/ps" <<'PS'
#!/usr/bin/env bash
printf 'bash /fixture/tests/test-ancestor.sh\n'
PS
chmod +x "$T/bin/ps"
OLD_PATH="$PATH"; export PATH="$T/bin:$PATH"
refused 'unmarked suite ancestor fixture' "$R" "$R" unset
export PATH="$OLD_PATH"
# Legitimate production in the owning tree must still be completely silent.
rc=0; run_record "$W" "$W" 0 || rc=$?
if [[ "$rc" == 0 && ! -s "$T/out" && ! -s "$T/err" ]] && grep -q '^handle: fixture$' "$W/$P"; then
  ok 'same-tree production succeeds silently'
else bad 'same-tree production succeeds silently'; cat "$T/err"; fi
mkdir -p "$W/subdir"
ln -s "$W" "$T/alias"
rc=0; run_record "$W/subdir" "$T/alias" 0 || rc=$?
if [[ "$rc" == 0 && ! -s "$T/out" && ! -s "$T/err" ]]; then
  ok 'same-tree subdirectory and symlink alias stay silent'
else bad 'same-tree subdirectory and symlink alias stay silent'; fi
rc=0
(cd "$W" && LEADV2_TEST_CONTEXT=0 LEADV2_PROJECT_ROOT="$W" bash "$WRITER" record fresh001 classify) > "$T/out" 2> "$T/err" || rc=$?
if [[ "$rc" == 0 && ! -s "$T/out" && ! -s "$T/err" ]] && grep -q '^proof: verified$' "$W/docs/handoff/dispatch-fresh001/phases.d/classify.yaml"; then
  ok 'fresh same-tree classify remains verified and silent'
else bad 'fresh same-tree classify remains verified and silent'; cat "$T/err"; fi
# Explicit fixture redirection to a separate repository is still usable.
mkdir -p "$T/fixture/$(dirname "$P")"
printf 'original\n' > "$T/fixture/$P"
git -C "$T/fixture" init -q
rc=0; run_record "$R" "$T/fixture" 1 || rc=$?
if [[ "$rc" == 0 && ! -s "$T/out" && ! -s "$T/err" ]] && grep -q '^handle: fixture$' "$T/fixture/$P"; then
  ok 'isolated test fixture succeeds silently'
else bad 'isolated test fixture succeeds silently'; cat "$T/err"; fi
printf 'SUMMARY: %s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" == 0 ]]
