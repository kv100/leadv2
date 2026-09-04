#!/usr/bin/env bash
# leadv2-mythicalgames-overrides-gen.sh
#
# Generates a minimal .claude/leadv2-overrides/ tree for a repo so leadv2 has
# a build/test/verify contract for it (see leadv2-helpers.sh readers:
# _lv2_stack_scalar, _lv2_load_paths, _lv2_codex_enabled). Written for the
# MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01 task: 8 real employer repos under
# ~/MythicalGames were adopted into leadv2 with no override tree.
#
# The emitted files are meant to be written as LOCAL-ONLY, untracked config
# inside a target repo (covered by that repo's .git/info/exclude). This
# script never touches git state itself -- it only writes files under
# <repo>/.claude/leadv2-overrides/. The caller is responsible for making sure
# .git/info/exclude covers that path in the target repo before pointing this
# generator at a repo that must never see a tracked leadv2 file.
#
# Usage:
#   leadv2-mythicalgames-overrides-gen.sh                 # auto-discover under $LEADV2_MG_ROOT (default ~/MythicalGames)
#   leadv2-mythicalgames-overrides-gen.sh --repo <path>    # single repo
#   leadv2-mythicalgames-overrides-gen.sh [--repo <path>] --force   # overwrite existing files
#
# Bash 3.2 compatible (macOS ships 3.2): no associative arrays, no ${x^^},
# no readarray.
set -euo pipefail

FORCE=0
SINGLE_REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      SINGLE_REPO="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    *)
      echo "leadv2-mythicalgames-overrides-gen: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

MG_ROOT="${LEADV2_MG_ROOT:-$HOME/MythicalGames}"

# ── detect_stack ────────────────────────────────────────────────────────
# repo path in, stack id out on stdout:
#   node-pnpm | node-npm | go | foundry | docker-compose-only | iac-only |
#   shell-only | unknown
# Lockfile decides the package manager for node repos (per-repo stack table,
# MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01 brief).
detect_stack() {
  local repo="$1"

  if [[ -f "$repo/foundry.toml" ]]; then
    printf '%s\n' "foundry"
    return 0
  fi

  if [[ -f "$repo/go.mod" ]]; then
    printf '%s\n' "go"
    return 0
  fi

  if [[ -f "$repo/pnpm-lock.yaml" ]]; then
    printf '%s\n' "node-pnpm"
    return 0
  fi

  if [[ -f "$repo/package-lock.json" ]]; then
    printf '%s\n' "node-npm"
    return 0
  fi

  if [[ -f "$repo/docker-compose.yml" || -f "$repo/docker-compose.yaml" \
        || -f "$repo/compose.yml" || -f "$repo/compose.yaml" ]]; then
    printf '%s\n' "docker-compose-only"
    return 0
  fi

  # IaC repos (e.g. environment-platform) keep their kustomization.yaml files
  # several directories deep, per-overlay (devops/<app>/<env>/kustomization.yaml) --
  # a shallow maxdepth 2 search misses every real one, so this goes deeper
  # than the other markers, which are always at repo root.
  if [[ -f "$repo/kustomization.yaml" || -f "$repo/kustomization.yml" ]] \
     || find "$repo" -maxdepth 5 -iname 'kustomization.yaml' 2>/dev/null | grep -q .; then
    printf '%s\n' "iac-only"
    return 0
  fi

  if find "$repo" -maxdepth 2 -name '*.sh' 2>/dev/null | grep -q .; then
    printf '%s\n' "shell-only"
    return 0
  fi

  printf '%s\n' "unknown"
}

_mg_lang_for_stack() {
  case "$1" in
    node-pnpm|node-npm) printf '%s' "typescript" ;;
    go) printf '%s' "go" ;;
    foundry) printf '%s' "solidity" ;;
    docker-compose-only) printf '%s' "n/a" ;;
    iac-only) printf '%s' "iac" ;;
    shell-only) printf '%s' "shell" ;;
    *) printf '%s' "unknown" ;;
  esac
}

_mg_pkgmgr_for_stack() {
  case "$1" in
    node-pnpm) printf '%s' "pnpm" ;;
    node-npm) printf '%s' "npm" ;;
    go) printf '%s' "go modules" ;;
    foundry) printf '%s' "forge" ;;
    *) printf '%s' "n/a" ;;
  esac
}

# Per-repo hand-tuning layered on top of the generic stack detection: the
# 8 real repos have a CI-authoritative test command that a generic
# lockfile-based guess cannot reproduce (e.g. m3's only real CI gate is
# eslint, not `pnpm test`). Falls back to a generic stack default for any
# repo name not in this table, so the generator stays useful for future
# adoptions too.
_mg_repo_test_cmd() {
  local name="$1" stack="$2"
  case "$name" in
    environment-platform) printf '%s' "" ;;
    m3) printf '%s' "pnpm --filter=main exec eslint ." ;;
    mondia-portal) printf '%s' "" ;;
    mp-frontend) printf '%s' "npm run test" ;;
    mythical-aii) printf '%s' "" ;;
    pf3-backend) printf '%s' "make ci-unit-tests" ;;
    pf3-local-dev) printf '%s' "" ;;
    pf3-smart-contracts) printf '%s' "forge test -vvv" ;;
    *)
      case "$stack" in
        node-pnpm) printf '%s' "pnpm test" ;;
        node-npm) printf '%s' "npm test" ;;
        go) printf '%s' "go test ./..." ;;
        foundry) printf '%s' "forge test -vvv" ;;
        *) printf '%s' "" ;;
      esac
      ;;
  esac
}

# Nearest safe (read-only) proxy for repos with no CI-run test command.
# Explicitly labeled a substitute at emit time -- never presented as "the
# test suite".
_mg_repo_proxy_cmd() {
  local name="$1" stack="$2"
  case "$name" in
    mythical-aii)
      printf '%s' 'find . -name "*.sh" -print0 | while IFS= read -r -d "" f; do bash -n "$f" || exit 1; done'
      ;;
    pf3-local-dev)
      printf '%s' "docker compose config"
      ;;
    mondia-portal)
      printf '%s' "pnpm lint"
      ;;
    environment-platform)
      printf '%s' ""
      ;;
    *)
      case "$stack" in
        shell-only)
          printf '%s' 'find . -maxdepth 3 -name "*.sh" -print0 | while IFS= read -r -d "" f; do bash -n "$f" || exit 1; done'
          ;;
        docker-compose-only)
          printf '%s' "docker compose config"
          ;;
        *)
          printf '%s' ""
          ;;
      esac
      ;;
  esac
}

emit_stack_yaml() {
  local repo="$1" stack="$2" name lang pkgmgr test_cmd out
  name="$(basename "$repo")"
  lang="$(_mg_lang_for_stack "$stack")"
  pkgmgr="$(_mg_pkgmgr_for_stack "$stack")"
  test_cmd="$(_mg_repo_test_cmd "$name" "$stack")"
  out="$repo/.claude/leadv2-overrides/stack.yaml"
  {
    printf '# .claude/leadv2-overrides/stack.yaml -- generated by leadv2-mythicalgames-overrides-gen.sh\n'
    printf '# detected stack: %s (repo: %s)\n' "$stack" "$name"
    printf 'lang: %s\n' "$lang"
    printf 'pkg_manager: %s\n' "$pkgmgr"
    if [[ -n "$test_cmd" ]]; then
      printf 'test_cmd: "%s"\n' "$test_cmd"
    else
      printf '# no CI-run test command exists for this repo -- verify.sh uses a labeled\n'
      printf '# substitute proxy instead (see verify.sh), never presented as the real suite\n'
      printf 'test_cmd: ""\n'
    fi
    printf 'deploy_method: none\n'
    printf 'deploy_verify:\n'
    printf '  required: false\n'
    printf 'hot_paths: []\n'
  } > "$out"
}

emit_state_paths() {
  local repo="$1" out
  out="$repo/.claude/leadv2-overrides/state-paths.yaml"
  {
    printf '# .claude/leadv2-overrides/state-paths.yaml -- generated by leadv2-mythicalgames-overrides-gen.sh\n'
    printf '# Uncomment and edit any line to override default file locations.\n'
    printf '# board_path: docs/BOARD.md\n'
    printf '# dialogue_path: docs/agents/product-owner/DIALOGUE.md\n'
    printf '# queue_path: docs/agents/product-owner/QUEUE.md\n'
    printf '# lead_state_path: docs/LEAD_V2_STATE.md\n'
    printf '# handoff_dir: docs/handoff\n'
    printf '# leadv2_dir: docs/leadv2\n'
    printf '# queue_archive_dir: docs/agents/product-owner/queue/_archive\n'
  } > "$out"
}

emit_codex_policy() {
  local repo="$1" out
  out="$repo/.claude/leadv2-overrides/codex-policy.yaml"
  {
    printf '# .claude/leadv2-overrides/codex-policy.yaml -- generated by leadv2-mythicalgames-overrides-gen.sh\n'
    printf '# Explicit opt-out: Codex dispatch for MythicalGames repos is a separate\n'
    printf '# founder decision (out of scope for MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01).\n'
    printf 'codex_enabled: false\n'
  } > "$out"
}

emit_deploy_stub() {
  local repo="$1" out
  out="$repo/.claude/leadv2-overrides/deploy.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf '# .claude/leadv2-overrides/deploy.sh -- generated NO-OP stub\n'
    printf '# (leadv2-mythicalgames-overrides-gen.sh). Real deploy wiring for MythicalGames\n'
    printf '# repos is out of scope -- this stub exists only so\n'
    printf '# leadv2-deploy-merge.sh'\''s hard-require check (deploy.sh must exist and be\n'
    printf '# executable) passes; it does not deploy anything.\n'
    printf 'set -euo pipefail\n'
    printf 'echo "leadv2-overrides/deploy.sh: NO-OP stub -- deploy not wired for this repo (LEAD_V2_TASK_ID=${LEAD_V2_TASK_ID:-unset} LEAD_V2_COMMIT=${LEAD_V2_COMMIT:-unset})"\n'
    printf 'exit 0\n'
  } > "$out"
  chmod +x "$out"
}

emit_verify() {
  local repo="$1" stack="$2" name test_cmd proxy_cmd out
  name="$(basename "$repo")"
  test_cmd="$(_mg_repo_test_cmd "$name" "$stack")"
  proxy_cmd="$(_mg_repo_proxy_cmd "$name" "$stack")"
  out="$repo/.claude/leadv2-overrides/verify.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf '# .claude/leadv2-overrides/verify.sh -- generated by leadv2-mythicalgames-overrides-gen.sh\n'
    printf '# detected stack: %s\n' "$stack"
    printf 'set -euo pipefail\n'
    printf 'cd "$(cd "$(dirname "$0")/../.." && pwd)"\n'
    if [[ -n "$test_cmd" ]]; then
      printf '%s\n' "$test_cmd"
    elif [[ -n "$proxy_cmd" ]]; then
      printf 'echo "verify.sh: SUBSTITUTE PROXY -- no CI-run test command exists for this repo; running the nearest safe read-only check instead of a real test suite" >&2\n'
      printf '%s\n' "$proxy_cmd"
    else
      printf 'echo "verify.sh: SKIP -- no automated verify command configured for this repo; needs a human-authored check (see stack.yaml)" >&2\n'
      printf 'exit 0\n'
    fi
  } > "$out"
  chmod +x "$out"
}

# A linked worktree (`.git` is a FILE, not a dir) has the same stack, test
# command and deploy posture as its parent clone -- LEAD ADDENDUM
# (docs/handoff/MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01/lead-addendum-census.md)
# rejects emitting a second hand-authored tree per worktree because it rots
# (two copies drift silently, same failure class as the 2026-07-29 canonical/
# persona-engine gate defect). Instead: symlink the worktree's
# .claude/leadv2-overrides at its parent clone's tree -- one inode, N views,
# same convention leadv2-shared already uses for cross-repo symlinks. No
# leadv2-helpers.sh reader change needed: a symlinked directory resolves
# transparently to plain file reads.
_mg_worktree_parent() {
  local repo="$1" common_dir parent
  common_dir="$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$common_dir" in
    /*) : ;;
    *) common_dir="$repo/$common_dir" ;;
  esac
  parent="$(cd "$common_dir/.." 2>/dev/null && pwd)" || return 1
  printf '%s\n' "$parent"
}

process_worktree() {
  local repo="$1" parent link
  parent="$(_mg_worktree_parent "$repo")"
  if [[ -z "$parent" ]]; then
    echo "SKIP (worktree parent unresolved via git rev-parse --git-common-dir): $repo"
    return 0
  fi
  if [[ ! -d "$parent/.git" ]]; then
    echo "SKIP (worktree parent is not itself a canonical repo): $repo -> $parent"
    return 0
  fi
  mkdir -p "$repo/.claude"
  link="$repo/.claude/leadv2-overrides"
  if [[ -e "$link" || -L "$link" ]] && [[ "$FORCE" -ne 1 ]]; then
    echo "SKIP (exists): $link"
    return 0
  fi
  ln -sfn "$parent/.claude/leadv2-overrides" "$link"
  echo "WORKTREE-LINK: $repo -> $parent/.claude/leadv2-overrides"
}

process_repo() {
  local repo="$1" name ov stack f
  name="$(basename "$repo")"

  if [[ -f "$repo/.git" ]]; then
    process_worktree "$repo"
    return 0
  fi

  if [[ ! -d "$repo/.git" ]]; then
    echo "SKIP (not a canonical repo -- .git is not a directory): $repo"
    return 0
  fi

  ov="$repo/.claude/leadv2-overrides"
  mkdir -p "$ov"
  stack="$(detect_stack "$repo")"

  for f in stack.yaml state-paths.yaml codex-policy.yaml deploy.sh verify.sh; do
    if [[ -e "$ov/$f" && "$FORCE" -ne 1 ]]; then
      echo "SKIP (exists): $ov/$f"
      continue
    fi
    case "$f" in
      stack.yaml) emit_stack_yaml "$repo" "$stack" ;;
      state-paths.yaml) emit_state_paths "$repo" ;;
      codex-policy.yaml) emit_codex_policy "$repo" ;;
      deploy.sh) emit_deploy_stub "$repo" ;;
      verify.sh) emit_verify "$repo" "$stack" ;;
    esac
    echo "WROTE ($stack): $ov/$f"
  done
}

if [[ -n "$SINGLE_REPO" ]]; then
  RESOLVED="$(cd "$SINGLE_REPO" && pwd)"
  process_repo "$RESOLVED"
else
  if [[ ! -d "$MG_ROOT" ]]; then
    echo "leadv2-mythicalgames-overrides-gen: no such directory: $MG_ROOT" >&2
    exit 1
  fi
  for d in "$MG_ROOT"/*/; do
    [[ -d "$d" ]] || continue
    d="${d%/}"
    process_repo "$d"
  done
fi
