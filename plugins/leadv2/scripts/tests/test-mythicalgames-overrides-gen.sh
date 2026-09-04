#!/usr/bin/env bash
# Offline contract tests for leadv2-mythicalgames-overrides-gen.sh
# (MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01).
#
# Builds synthetic fixture repos under /tmp/leadv2-fixture-repos/<name>/ --
# real `git init`, only marker files (package.json+pnpm-lock.yaml, go.mod,
# foundry.toml, etc.) -- and runs the generator against fixtures ONLY. Never
# touches ~/MythicalGames.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="${SCRIPT_DIR}/leadv2-mythicalgames-overrides-gen.sh"

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

FIXROOT="/tmp/leadv2-fixture-repos"
rm -rf "$FIXROOT"
mkdir -p "$FIXROOT"
trap 'rm -rf "$FIXROOT"' EXIT

if bash -n "$GEN"; then
  pass 'bash syntax: generator'
else
  fail 'bash syntax: generator'
fi

mk_fixture() { # <name>
  local name="$1"
  local dir="$FIXROOT/$name"
  mkdir -p "$dir"
  (cd "$dir" && git init -q)
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# node-pnpm fixture: package.json + pnpm-lock.yaml
# ---------------------------------------------------------------------------
NPNPM_DIR="$(mk_fixture node-pnpm-app)"
echo '{}' > "$NPNPM_DIR/package.json"
echo 'lockfileVersion: 6.0' > "$NPNPM_DIR/pnpm-lock.yaml"

bash "$GEN" --repo "$NPNPM_DIR" >/tmp/leadv2-fixture-repos-gen-out.$$ 2>&1
if grep -q 'WROTE (node-pnpm):.*stack.yaml' /tmp/leadv2-fixture-repos-gen-out.$$; then
  pass 'node-pnpm fixture: detected as node-pnpm'
else
  fail "node-pnpm fixture: NOT detected as node-pnpm ($(cat /tmp/leadv2-fixture-repos-gen-out.$$))"
fi
if [[ -f "$NPNPM_DIR/.claude/leadv2-overrides/stack.yaml" ]] \
   && grep -q '^lang: typescript' "$NPNPM_DIR/.claude/leadv2-overrides/stack.yaml" \
   && grep -q '^pkg_manager: pnpm' "$NPNPM_DIR/.claude/leadv2-overrides/stack.yaml"; then
  pass 'node-pnpm fixture: stack.yaml has pnpm pkg_manager'
else
  fail 'node-pnpm fixture: stack.yaml missing or wrong pkg_manager'
fi
if [[ -x "$NPNPM_DIR/.claude/leadv2-overrides/verify.sh" ]] \
   && grep -q 'pnpm' "$NPNPM_DIR/.claude/leadv2-overrides/verify.sh" \
   && ! grep -qE '(^|[^p])npm ' "$NPNPM_DIR/.claude/leadv2-overrides/verify.sh"; then
  pass 'node-pnpm fixture: verify.sh is pnpm-flavored, not npm-flavored'
else
  fail 'node-pnpm fixture: verify.sh is NOT correctly pnpm-flavored'
fi
for f in state-paths.yaml codex-policy.yaml deploy.sh; do
  if [[ -f "$NPNPM_DIR/.claude/leadv2-overrides/$f" ]]; then
    pass "node-pnpm fixture: $f emitted"
  else
    fail "node-pnpm fixture: $f MISSING"
  fi
done
if grep -q '^codex_enabled: false' "$NPNPM_DIR/.claude/leadv2-overrides/codex-policy.yaml"; then
  pass 'node-pnpm fixture: codex_enabled defaults false'
else
  fail 'node-pnpm fixture: codex_enabled default wrong'
fi
if [[ -x "$NPNPM_DIR/.claude/leadv2-overrides/deploy.sh" ]]; then
  pass 'node-pnpm fixture: deploy.sh is executable'
else
  fail 'node-pnpm fixture: deploy.sh not executable'
fi

# ---------------------------------------------------------------------------
# node-npm fixture: package.json + package-lock.json (no pnpm-lock.yaml)
# ---------------------------------------------------------------------------
NNPM_DIR="$(mk_fixture node-npm-app)"
echo '{}' > "$NNPM_DIR/package.json"
echo '{}' > "$NNPM_DIR/package-lock.json"

bash "$GEN" --repo "$NNPM_DIR" >/tmp/leadv2-fixture-repos-gen-out.$$ 2>&1
if grep -q 'WROTE (node-npm):.*stack.yaml' /tmp/leadv2-fixture-repos-gen-out.$$; then
  pass 'node-npm fixture: detected as node-npm'
else
  fail "node-npm fixture: NOT detected as node-npm ($(cat /tmp/leadv2-fixture-repos-gen-out.$$))"
fi
if grep -q 'npm test' "$NNPM_DIR/.claude/leadv2-overrides/verify.sh" \
   && ! grep -q 'pnpm' "$NNPM_DIR/.claude/leadv2-overrides/verify.sh"; then
  pass 'node-npm fixture: verify.sh is npm-flavored, not pnpm-flavored'
else
  fail 'node-npm fixture: verify.sh is NOT correctly npm-flavored'
fi

# ---------------------------------------------------------------------------
# go fixture
# ---------------------------------------------------------------------------
GO_DIR="$(mk_fixture go-app)"
echo 'module example.com/x' > "$GO_DIR/go.mod"
bash "$GEN" --repo "$GO_DIR" >/tmp/leadv2-fixture-repos-gen-out.$$ 2>&1
if grep -q 'WROTE (go):.*stack.yaml' /tmp/leadv2-fixture-repos-gen-out.$$ \
   && grep -q 'go test' "$GO_DIR/.claude/leadv2-overrides/verify.sh"; then
  pass 'go fixture: detected as go, verify.sh runs go test'
else
  fail "go fixture: wrong detection or verify.sh ($(cat /tmp/leadv2-fixture-repos-gen-out.$$))"
fi

# ---------------------------------------------------------------------------
# foundry fixture (must win over a coincidental go.mod, per detect_stack order)
# ---------------------------------------------------------------------------
FOUNDRY_DIR="$(mk_fixture foundry-app)"
echo '[profile.default]' > "$FOUNDRY_DIR/foundry.toml"
bash "$GEN" --repo "$FOUNDRY_DIR" >/tmp/leadv2-fixture-repos-gen-out.$$ 2>&1
if grep -q 'WROTE (foundry):.*stack.yaml' /tmp/leadv2-fixture-repos-gen-out.$$ \
   && grep -q 'forge test -vvv' "$FOUNDRY_DIR/.claude/leadv2-overrides/verify.sh"; then
  pass 'foundry fixture: detected as foundry, verify.sh runs forge test'
else
  fail "foundry fixture: wrong detection or verify.sh ($(cat /tmp/leadv2-fixture-repos-gen-out.$$))"
fi

# ---------------------------------------------------------------------------
# docker-compose-only fixture
# ---------------------------------------------------------------------------
COMPOSE_DIR="$(mk_fixture compose-app)"
echo 'services: {}' > "$COMPOSE_DIR/docker-compose.yml"
bash "$GEN" --repo "$COMPOSE_DIR" >/tmp/leadv2-fixture-repos-gen-out.$$ 2>&1
if grep -q 'WROTE (docker-compose-only):.*stack.yaml' /tmp/leadv2-fixture-repos-gen-out.$$ \
   && grep -q 'docker compose config' "$COMPOSE_DIR/.claude/leadv2-overrides/verify.sh"; then
  pass 'docker-compose fixture: detected, verify.sh runs docker compose config'
else
  fail "docker-compose fixture: wrong detection or verify.sh ($(cat /tmp/leadv2-fixture-repos-gen-out.$$))"
fi

# ---------------------------------------------------------------------------
# iac-only fixture
# ---------------------------------------------------------------------------
IAC_DIR="$(mk_fixture iac-app)"
echo 'resources: []' > "$IAC_DIR/kustomization.yaml"
bash "$GEN" --repo "$IAC_DIR" >/tmp/leadv2-fixture-repos-gen-out.$$ 2>&1
if grep -q 'WROTE (iac-only):.*stack.yaml' /tmp/leadv2-fixture-repos-gen-out.$$ \
   && grep -q 'SKIP -- no automated verify' "$IAC_DIR/.claude/leadv2-overrides/verify.sh"; then
  pass 'iac-only fixture: detected, verify.sh is a labeled skip (no invented command)'
else
  fail "iac-only fixture: wrong detection or verify.sh ($(cat /tmp/leadv2-fixture-repos-gen-out.$$))"
fi

# ---------------------------------------------------------------------------
# shell-only fixture
# ---------------------------------------------------------------------------
SHELL_DIR="$(mk_fixture shell-app)"
printf '#!/usr/bin/env bash\necho hi\n' > "$SHELL_DIR/run.sh"
bash "$GEN" --repo "$SHELL_DIR" >/tmp/leadv2-fixture-repos-gen-out.$$ 2>&1
if grep -q 'WROTE (shell-only):.*stack.yaml' /tmp/leadv2-fixture-repos-gen-out.$$ \
   && grep -q 'SUBSTITUTE PROXY' "$SHELL_DIR/.claude/leadv2-overrides/verify.sh" \
   && grep -q 'bash -n' "$SHELL_DIR/.claude/leadv2-overrides/verify.sh"; then
  pass 'shell-only fixture: detected, verify.sh uses labeled bash -n proxy'
else
  fail "shell-only fixture: wrong detection or verify.sh ($(cat /tmp/leadv2-fixture-repos-gen-out.$$))"
fi

# ---------------------------------------------------------------------------
# unknown fixture (nothing recognizable)
# ---------------------------------------------------------------------------
UNKNOWN_DIR="$(mk_fixture unknown-app)"
echo 'hello' > "$UNKNOWN_DIR/README.md"
bash "$GEN" --repo "$UNKNOWN_DIR" >/tmp/leadv2-fixture-repos-gen-out.$$ 2>&1
if grep -q 'WROTE (unknown):.*stack.yaml' /tmp/leadv2-fixture-repos-gen-out.$$; then
  pass 'unknown fixture: falls back to unknown stack, does not crash'
else
  fail "unknown fixture: did not fall back cleanly ($(cat /tmp/leadv2-fixture-repos-gen-out.$$))"
fi

# ---------------------------------------------------------------------------
# .git as a FILE (real linked worktree, via `git worktree add`) must resolve
# its override tree from the parent clone via a symlink -- LEAD ADDENDUM:
# a worktree must not get its own hand-authored tree (rots). Never a fake
# `gitdir:` file -- `git rev-parse --git-common-dir` needs a real worktree
# registration to resolve.
WTPARENT_DIR="$(mk_fixture worktree-parent)"
echo 'module x' > "$WTPARENT_DIR/go.mod"
bash "$GEN" --repo "$WTPARENT_DIR" >/tmp/leadv2-fixture-repos-gen-out.$$ 2>&1
WT_DIR="$FIXROOT/worktree-child"
git -C "$WTPARENT_DIR" worktree add -q -b wt-child-branch "$WT_DIR" >/dev/null 2>&1
if [[ -f "$WT_DIR/.git" ]]; then
  bash "$GEN" --repo "$WT_DIR" >/tmp/leadv2-fixture-repos-gen-out.$$ 2>&1
  if grep -q 'WORKTREE-LINK:' /tmp/leadv2-fixture-repos-gen-out.$$ \
     && [[ -L "$WT_DIR/.claude/leadv2-overrides" ]] \
     && [[ "$(cd "$WT_DIR/.claude/leadv2-overrides" && pwd -P)" == "$(cd "$WTPARENT_DIR/.claude/leadv2-overrides" && pwd -P)" ]]; then
    pass 'linked-worktree fixture: override tree symlinked to parent clone, not copied'
  else
    fail "linked-worktree fixture: NOT symlinked to parent ($(cat /tmp/leadv2-fixture-repos-gen-out.$$))"
  fi
  if grep -q '^lang: go' "$WT_DIR/.claude/leadv2-overrides/stack.yaml" 2>/dev/null; then
    pass 'linked-worktree fixture: reads through the symlink to parent stack.yaml'
  else
    fail 'linked-worktree fixture: symlinked stack.yaml unreadable or wrong content'
  fi
else
  fail 'linked-worktree fixture: git worktree add did not produce a .git file (setup broken, not the generator)'
fi

# A companion dir with NO .git at all (e.g. m3-market) is a different case
# from a worktree and must still be skipped outright, never symlinked.
NOGIT_DIR="$FIXROOT/companion-app"
mkdir -p "$NOGIT_DIR"
bash "$GEN" --repo "$NOGIT_DIR" >/tmp/leadv2-fixture-repos-gen-out.$$ 2>&1
if grep -q 'SKIP (not a canonical repo' /tmp/leadv2-fixture-repos-gen-out.$$ \
   && [[ ! -d "$NOGIT_DIR/.claude" ]]; then
  pass 'no-.git companion dir: skipped, no override tree and no symlink written'
else
  fail "no-.git companion dir: NOT skipped ($(cat /tmp/leadv2-fixture-repos-gen-out.$$))"
fi

# ---------------------------------------------------------------------------
# Idempotency: default run never clobbers hand-tuning; --force does, and logs it.
# ---------------------------------------------------------------------------
echo 'HAND_TUNED_MARKER' > "$NPNPM_DIR/.claude/leadv2-overrides/stack.yaml"
bash "$GEN" --repo "$NPNPM_DIR" >/tmp/leadv2-fixture-repos-gen-out.$$ 2>&1
if grep -q 'SKIP (exists):.*stack.yaml' /tmp/leadv2-fixture-repos-gen-out.$$ \
   && grep -q 'HAND_TUNED_MARKER' "$NPNPM_DIR/.claude/leadv2-overrides/stack.yaml"; then
  pass 'idempotency: default run does not clobber hand-tuned file'
else
  fail 'idempotency: default run OVERWROTE a hand-tuned file'
fi
bash "$GEN" --repo "$NPNPM_DIR" --force >/tmp/leadv2-fixture-repos-gen-out.$$ 2>&1
if grep -q 'WROTE (node-pnpm):.*stack.yaml' /tmp/leadv2-fixture-repos-gen-out.$$ \
   && ! grep -q 'HAND_TUNED_MARKER' "$NPNPM_DIR/.claude/leadv2-overrides/stack.yaml"; then
  pass '--force: overwrites and logs WROTE'
else
  fail '--force: did not overwrite as expected'
fi

# ---------------------------------------------------------------------------
# Auto-discovery: LEADV2_MG_ROOT scoped to the fixture tree only, never
# touches ~/MythicalGames. Confirms canonical (.git dir) vs worktree (.git
# file) vs companion-dir disambiguation across a mixed root in one pass.
# ---------------------------------------------------------------------------
DISCOVER_ROOT="/tmp/leadv2-fixture-repos-discover.$$"
rm -rf "$DISCOVER_ROOT"
mkdir -p "$DISCOVER_ROOT/real-repo" "$DISCOVER_ROOT/companion-dir"
(cd "$DISCOVER_ROOT/real-repo" && git init -q)
echo 'module x' > "$DISCOVER_ROOT/real-repo/go.mod"
# companion-dir has no .git at all -- must be skipped, same as a worktree.
LEADV2_MG_ROOT="$DISCOVER_ROOT" bash "$GEN" >/tmp/leadv2-fixture-repos-gen-out.$$ 2>&1
if [[ -f "$DISCOVER_ROOT/real-repo/.claude/leadv2-overrides/stack.yaml" ]] \
   && [[ ! -d "$DISCOVER_ROOT/companion-dir/.claude" ]]; then
  pass 'auto-discovery: processes canonical repo, skips non-git companion dir'
else
  fail 'auto-discovery: mis-selected repos'
fi
rm -rf "$DISCOVER_ROOT"

rm -f /tmp/leadv2-fixture-repos-gen-out.$$

printf '[TEST] === %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
