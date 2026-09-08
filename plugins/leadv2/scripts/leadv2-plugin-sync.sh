#!/usr/bin/env bash
# leadv2-plugin-sync.sh — Idempotent sync of plugin scripts/contracts/workflows/hooks
# from the canonical plugin source tree to all runtime locations.
#
# Syncs to:
#   (a) RETIRED (C1-RETIRE-RSYNC, 2026-09-08): the hardcoded
#       ~/.claude/plugins/cache/leadv2-local/leadv2/0.1.0/ leg is gone — that
#       version dir is ORPHANED by the runtime (installed_plugins.json
#       installPath = .../0.5.7 is authoritative; 0.1.0 carries a runtime
#       .orphaned_at marker; hook/command BODIES are live-from-repo via the
#       plugins/local symlink). The ACTIVE cache dir has its own dedicated
#       producer: leadv2-plugin-cache-sync.sh. Nothing is written to the
#       cache from this script anymore — deliberately stopped, not linked.
#   (b) ~/.claude/leadv2-shared/                            (scripts + contracts + hooks)
#       LINK-ONLY producer (C1-RETIRE-RSYNC): a plugin-owned canonical file
#       with no destination counterpart enters as a symlink into
#       plugins/leadv2/, never a real copy. The gated rsync leg remains ONLY
#       as shadow refresh for pre-existing real copies (never creates files:
#       absent plugin-owned files are already links and excluded).
#   (c) <project>/.claude/scripts/                          (per-repo runtimes from cross-repo-paths.yaml)
#       already link-mode — _link_project_scripts, unchanged.
#   (d) <project>/.claude/contracts/                        (schema files per-repo)
#       LINK-ONLY (C1-RETIRE-RSYNC): same _link_one_file pass as (c). An
#       existing real copy is structurally never written anymore, so the
#       cp-era backward-refusal machinery is deleted (see _sync_project_root).
#   (e) ~/.claude/scripts/                                  (user-global leadv2-* scripts; ADDITIVE, no --delete)
#       LINK-ONLY producer for the leadv2-* + explicit-name set; rsync leg
#       stays as shadow refresh, same as (b).
#   (f) ~/Projects/leadv2/.claude/scripts/                  (this repo's own vendored copy)
#       still rsync --delete, unchanged this lane (header doc previously
#       mis-numbered this leg out of the list).
#   (g) ~/.codex/skills/source-command-leadv2/              (Codex leadv2 skill; enables provider=codex lead sessions)
#       still an additive copy, unchanged: ~/.codex is not ours and Codex-side
#       symlink acceptance is UNVERIFIED — converting it is deferred, not
#       assumed either way.
#
# (c)/(d): reads project roots from ~/.claude/leadv2-shared/cross-repo-paths.yaml.
# Missing root on disk → WARN + skip (never silent).
# --project-root overrides to a single root (bypasses yaml iteration).
#
# Also calls leadv2-workflows-sync.sh to sync JS workflow files to ~/.claude/workflows/.
#
# Usage:
#   bash leadv2-plugin-sync.sh [--write] [--allow-backward] [--dry-run] [--project-root <path>]
#
# --write           Actually write. WITHOUT it the run is a DRY RUN (default,
#                   DRIFT-GUARD-ADVISES-BACKWARD-SYNC-01): prints the plan and
#                   writes nothing. The old writes-by-default behavior is gone —
#                   a bare invocation used to be able to clobber a newer
#                   vendored copy with week-old canonical content.
# --allow-backward  With --write, permit overwriting a destination that is
#                   NEWER than canonical (VENDORED_NEWER). Without it such
#                   files are refused (left untouched) with a promote command.
# --dry-run         Explicit no-op: re-asserts the default dry-run mode
#                   (kept for muscle memory + existing tests). Last flag wins
#                   if both --dry-run and --write are passed; the resolved
#                   mode is logged at start.
# --project-root    Sync (c)/(d) to this single root only (skips yaml iteration).
#
# Exit codes: 0 = clean run (including LINK/CONVERT/BADLINK/DANGLING/ERROR --
# only DRIFT is fatal); 2 = usage error; 3 = pinned canonical root missing or
# invoked from the plugin cache; 4 = one or more (c)/(c2) project-scripts
# files diverged from canonical and were left untouched — promote or discard
# before the next sync (D1, PLUGIN-SYNC-CLAUDE-SCRIPTS-01).
#
# Write gates (DRIFT-GUARD-ADVISES-BACKWARD-SYNC-01), applied by the remaining
# rsync legs — the shadow-refresh transfers on (b)/(e) and the vendored (f)
# leg — per file a real run would overwrite, in order — a dirty destination is
# refused regardless of direction tags:
#   1. Uncommitted destination: if the destination file is TRACKED and MODIFIED
#      (or staged) in the destination repo's git, hard-refuse that file. No
#      flag overrides this; the only path forward is commit-or-promote.
#      Untracked (??) files are NOT "dirty" here — many vendored .claude/scripts
#      trees are carried untracked by design; refusing them would permanently
#      block every sync to those repos (the DRIFT-GUARD-UNSATISFIABLE-01 trap).
#      Untracked files are still protected by gate 2 + direction-safety.
#   2. Backward move: if the destination file is NEWER than canonical's last
#      git-commit time for that relpath (same evidence rule as
#      leadv2-drift-guard.sh decide_direction, 2s buffer), refuse without
#      --allow-backward — exclude + print the promote command. With
#      --allow-backward, the pre-existing quarantine-then-reconcile applies.
# (d) project contracts are link-only since C1-RETIRE-RSYNC: an existing real
# copy is structurally never written (a divergent copy is DRIFT, left
# untouched), so the cp-era _contract_write_gate is deleted; only the
# uncommitted-destination hard-refuse survives, checked inline before
# _link_one_file.
#
# Idempotent: safe to re-run after any plugin edit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# CACHE-REFUSAL (PLUGIN-CACHE-THIRD-COPY-REVERTS-FIXES-01): this script must
# only ever run from the git-tracked canonical tree. If $0 resolves to a path
# under the runtime plugin cache, refuse outright — a cache-invoked sync
# would otherwise treat the STALE cache copy as source-of-truth and push its
# staleness back out to every other copy, exactly the incident this task
# exists to fix. Cache-invocation is never legitimate for this script.
case "${SCRIPT_DIR}" in
  "${HOME}"/.claude/plugins/cache/leadv2-local/*)
    printf -- 'REFUSING: leadv2-plugin-sync.sh invoked from the plugin cache (%s) — this script must only run from the git-tracked canonical tree (~/Projects/leadv2/plugins/leadv2/scripts/). Re-invoke from canonical.\n' "${SCRIPT_DIR}" >&2
    exit 3
    ;;
esac

# SOURCE-PIN: canonical is a FIXED path, not derived from dirname($0). Before
# this fix, PLUGIN_ROOT="$(dirname "${SCRIPT_DIR}")" meant whichever COPY
# happened to invoke this script became "the source" for that run — the
# exact bug that let the stale plugin-cache copy silently push itself out to
# vendored repos and the shared tree, reverting 4 already-landed fixes
# (PLUGIN-CACHE-THIRD-COPY-REVERTS-FIXES-01). Only one tree is ever
# canonical: the git-tracked ~/Projects/leadv2/plugins/leadv2/.
CANONICAL_ROOT="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}"
PLUGIN_ROOT="${CANONICAL_ROOT}/plugins/leadv2"
if [[ ! -d "${PLUGIN_ROOT}" ]]; then
  printf -- 'REFUSING: pinned canonical PLUGIN_ROOT does not exist on disk: %s (set LEADV2_CANONICAL_ROOT to override for tests)\n' "${PLUGIN_ROOT}" >&2
  exit 3
fi
PLUGIN_GIT_ROOT="$(git -C "${CANONICAL_ROOT}" rev-parse --show-toplevel 2>/dev/null || printf -- '%s' "${CANONICAL_ROOT}")"

# DRY-RUN DEFAULT (DRIFT-GUARD-ADVISES-BACKWARD-SYNC-01 scope c): a bare run
# plans, never writes. --write flips to a real run; --dry-run re-asserts the
# default. Sequential assignment = last-wins for --dry-run/--write; the
# resolved mode is logged right after parsing so a double-flag invocation can
# never silently run the wrong mode.
DRY_RUN=true
ALLOW_BACKWARD=false
PROJECT_ROOT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write) DRY_RUN=false ;;
    --allow-backward) ALLOW_BACKWARD=true ;;
    --dry-run) DRY_RUN=true ;;
    --project-root)
      shift
      if [[ $# -eq 0 || -z "$1" ]]; then
        printf -- 'Unknown/invalid arg: --project-root requires a non-empty path\n' >&2
        exit 2
      fi
      PROJECT_ROOT_OVERRIDE="$1"
      ;;
    *) printf -- 'Unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

log()      { printf -- '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
log_ok()   { printf -- '[%s] OK: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
log_warn() { printf -- '[%s] WARN: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

log "Mode: $([[ "${DRY_RUN}" == "true" ]] && printf -- 'DRY_RUN (default; pass --write to write)' || printf -- 'WRITE (--write)')$([[ "${ALLOW_BACKWARD}" == "true" ]] && printf -- ' + --allow-backward (backward overwrites permitted)')"

# Global per-run refusal counter (write gates above). Surfaced in the final
# summary; REFUSED/BLOCKED lines above name each individual file.
_REFUSED_COUNT=0

# ── Target directories ────────────────────────────────────────────────────────
SHARED_TARGET="${HOME}/.claude/leadv2-shared"
CROSS_REPO_CONFIG="${HOME}/.claude/leadv2-shared/cross-repo-paths.yaml"

# D3 (PLUGIN-SYNC-CLAUDE-SCRIPTS-01): declared per-repo overrides for (c)/(c2)
# project-scripts sync. Same file, same env override, same vocabulary as
# leadv2-one-copy-convert.sh's EXCEPTIONS_FILE — one exception list, not two.
# New root-key here: "project/<repo-basename>/<relpath>", where <relpath> is
# under .claude/scripts/ for (c) or "toplevel/<name>" for (c2).
ONE_COPY_EXCEPTIONS_FILE="${LEADV2_ONE_COPY_EXCEPTIONS_FILE:-${PLUGIN_ROOT}/ref/one-copy-exceptions.txt}"
declare -a PLUGIN_SYNC_EXCEPTIONS=()
_load_plugin_sync_exceptions() {
  PLUGIN_SYNC_EXCEPTIONS=()
  if [[ ! -f "${ONE_COPY_EXCEPTIONS_FILE}" ]]; then
    log_warn "exception list not found at ${ONE_COPY_EXCEPTIONS_FILE} — treating as empty"
    return 0
  fi
  local raw line
  while IFS= read -r raw || [[ -n "${raw}" ]]; do
    line="${raw%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "${line}" ]] && continue
    PLUGIN_SYNC_EXCEPTIONS+=("${line}")
  done < "${ONE_COPY_EXCEPTIONS_FILE}"
}
_load_plugin_sync_exceptions

# _is_plugin_sync_exception <root-basename> <relpath-under-.claude/scripts-or-toplevel/>
_is_plugin_sync_exception() {
  local key="project/$1/$2" e
  for e in "${PLUGIN_SYNC_EXCEPTIONS[@]}"; do
    [[ "${e}" == "${key}" ]] && return 0
  done
  return 1
}

# ── Plugin-owned gate (C1-RETIRE-RSYNC, 2026-09-08) ───────────────────────────
# Founder's definition, verbatim: a file is plugin-owned IFF its relative path
# exists in canonical git — `git -C <canonical> ls-files plugins/leadv2/<rel>`.
# Name prefixes decide nothing. The link-only destinations (b)/(d)/(e) create
# symlinks ONLY for plugin-owned files: an untracked canonical file (mid-flight,
# not yet committed) is not plugin-owned, is never linked, and is logged
# SKIP-UNTRACKED — the legacy rsync legs still deliver it as before until it is
# committed, after which the next run converts the delivered copy to a link.
# Fail-closed: if the index cannot be read, NOTHING is plugin-owned (no links
# created that run; rsync behavior unchanged) and one WARN is logged.
_PLUGIN_OWNED_LIST=""
_PLUGIN_OWNED_LOADED=false
_load_plugin_owned_index() {
  if [[ "${_PLUGIN_OWNED_LOADED}" == "true" ]]; then return 0; fi
  _PLUGIN_OWNED_LOADED=true
  if ! command -v git >/dev/null 2>&1; then
    log_warn "plugin-owned index unavailable: git not on PATH — link-only destinations create NO links this run (fail-closed)"
    return 0
  fi
  _PLUGIN_OWNED_LIST="$(git -C "${PLUGIN_GIT_ROOT}" ls-files -- 'plugins/leadv2/' 2>/dev/null || true)"
  if [[ -z "${_PLUGIN_OWNED_LIST}" ]]; then
    log_warn "plugin-owned index empty for ${PLUGIN_GIT_ROOT} — link-only destinations create NO links this run (fail-closed)"
  fi
}
_is_plugin_owned() { # $1 = repo-relative path, e.g. plugins/leadv2/scripts/foo.sh
  _load_plugin_owned_index
  [[ -z "${_PLUGIN_OWNED_LIST}" ]] && return 1
  printf '%s\n' "${_PLUGIN_OWNED_LIST}" | grep -Fxq -- "$1"
}

# --checksum only (no -u): mtime skew must never cause silent content divergence.
#
# _syntax_gate_excludes — HOOK-EDIT-SPAWN-POISON-01 (T16 §9). A live sync used
# to copy hook files MID-EDIT: a session spawning at that moment received a
# syntax-broken plugin-cache snapshot and died at its first prompt (killed lane
# 75a42e3a, 2026-08-26). Every .sh in the source tree is gated through `bash -n`
# BEFORE the transfer; a failing file becomes an --exclude rule, and rsync
# --delete never touches excluded paths — so the PREVIOUS copy survives at the
# destination until canonical holds a syntactically valid file again. Each hold
# is logged. Fail-open: no bash on PATH, or a failed scan, syncs ungated (the
# pre-gate behavior) rather than blocking every sync.
_syntax_gate_excludes() { # $1 = src dir WITH trailing slash; prints --exclude=<relpath> lines
  local src="$1"
  command -v bash >/dev/null 2>&1 || return 0
  local f rel
  while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    rel="${f#"${src}"}"
    if ! bash -n "${f}" 2>/dev/null; then
      log_warn "[syntax-gate] holding ${rel}: bash -n failed — previous copy kept (mid-edit source not synced)"
      printf -- '--exclude=%s\n' "${rel}"
    fi
  done < <(find "${src}" -type f -name '*.sh' 2>/dev/null)
  return 0
}

_rsync_or_dry() {
  local label="$1" src="$2" dst="$3"
  shift 3
  local extra_flags=("$@")
  local gate_excludes=()
  while IFS= read -r _g; do
    [[ -z "${_g}" ]] && continue
    gate_excludes+=("${_g}")
  done < <(_syntax_gate_excludes "${src}")
  # Gate excludes go FIRST: rsync filter rules are first-match-wins, and the
  # user-scripts leg passes wildcard include rules that would otherwise claim a
  # broken file before a trailing exclude could hold it.
  local flags=(${gate_excludes[@]+"${gate_excludes[@]}"} ${extra_flags[@]+"${extra_flags[@]}"})
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY_RUN [${label}]: rsync --checksum ${flags[*]} ${src} ${dst}"
    rsync --checksum --dry-run ${flags[@]+"${flags[@]}"} "${src}" "${dst}" 2>&1 | python3 -c "
import sys
for l in sys.stdin:
    if l.startswith('>') or l.startswith('<') or l.startswith('*'):
        print(l, end='')
" | head -20 || true
  else
    mkdir -p "${dst}"
    rsync --checksum ${flags[@]+"${flags[@]}"} "${src}" "${dst}" && log_ok "[${label}] synced ${src} -> ${dst}"
  fi
}

# PER-FILE-SYMLINK-MANAGED-01: mirrors leadv2-one-copy-convert.sh's vocabulary
# for a repo-local tree, but deliberately enumerates canonical so missing links
# are visible and creatable here. Prints exactly one classification token.
_link_one_file() {
  local canonical_file="$1" dst_file="$2" parent tmp err resolved canonical_resolved
  if [[ ! -f "${canonical_file}" ]]; then
    printf 'SKIP\n'
    return 0
  fi
  if [[ -L "${dst_file}" ]]; then
    if [[ ! -e "${dst_file}" ]]; then
      printf 'DANGLING\n'
      return 0
    fi
    canonical_resolved="$(readlink -f "${canonical_file}" 2>/dev/null || true)"
    resolved="$(readlink -f "${dst_file}" 2>/dev/null || true)"
    if [[ -n "${canonical_resolved}" && "${resolved}" == "${canonical_resolved}" ]]; then
      printf 'OK\n'
    else
      printf 'BADLINK\n'
    fi
    return 0
  fi
  if [[ -d "${dst_file}" ]]; then
    printf 'TYPECLASH\n'
    return 0
  fi
  if [[ ! -e "${dst_file}" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      printf 'LINK\n'
      return 0
    fi
    parent="$(dirname "${dst_file}")"
    if ! mkdir -p "${parent}" 2>/dev/null; then
      printf 'ERROR\n'
      return 0
    fi
    if ln -s "${canonical_file}" "${dst_file}" 2>/dev/null; then
      printf 'LINK\n'
    else
      printf 'ERROR\n'
    fi
    return 0
  fi
  if [[ ! -r "${dst_file}" ]]; then
    printf 'ERROR\n'
    return 0
  fi
  if cmp -s "${canonical_file}" "${dst_file}"; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      printf 'CONVERT\n'
      return 0
    fi
    tmp="${dst_file}.tmp.$$"
    if ln -s "${canonical_file}" "${tmp}" 2>/dev/null && mv -f "${tmp}" "${dst_file}" 2>/dev/null; then
      printf 'CONVERT\n'
    else
      rm -f "${tmp}" 2>/dev/null || true
      printf 'ERROR\n'
    fi
  else
    # cmp 1 means different; any other result is an I/O failure, not drift.
    if [[ $? -eq 1 ]]; then
      printf 'DRIFT\n'
    else
      printf 'ERROR\n'
    fi
  fi
}

# D2 (PLUGIN-SYNC-CLAUDE-SCRIPTS-01): project_drift_repos must count a repo
# ONCE across both (c) .claude/scripts and (c2) top-level curated scripts, not
# once per call site. Bash 3.2 has no associative arrays, so track seen repo
# basenames in a plain array and scan it linearly (small: one entry per repo).
declare -a _DRIFT_COUNTED_REPOS=()
_mark_repo_drift_once() {
  local repo="$1" r
  for r in "${_DRIFT_COUNTED_REPOS[@]}"; do
    [[ "${r}" == "${repo}" ]] && return 1
  done
  _DRIFT_COUNTED_REPOS+=("${repo}")
  return 0
}

_link_diff_detail() {
  local canonical_file="$1" dst_file="$2" detail lines
  if command -v git >/dev/null 2>&1; then
    detail="$(git --no-pager diff --no-index --stat -- "${canonical_file}" "${dst_file}" 2>/dev/null || true)"
    detail="$(printf '%s' "${detail}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/[[:space:]]*$//')"
    [[ -n "${detail}" ]] && { printf '%s\n' "${detail}"; return; }
  fi
  lines="$(diff "${canonical_file}" "${dst_file}" 2>/dev/null | grep -cE '^[<>]' || true)"
  printf '%s lines differ\n' "${lines:-unknown}"
}

# ── Link-only producer pass (C1-RETIRE-RSYNC, 2026-09-08) ─────────────────────
# The (b) shared tree and (e) user-global scripts used to be pure rsync
# targets — an rsync target drifts between --write runs by construction, which
# is how the shadow census arose. This pass makes those destinations behave
# the way (c) already does: a plugin-owned canonical file with no destination
# counterpart enters as a SYMLINK into plugins/leadv2/, never a real copy; an
# identical real copy converts losslessly (CONVERT); a divergent real copy is
# DRIFT — left untouched, never converted here (bulk conversion of drifted
# shadows is step 3, SD-SYMLINK-FARM-CONVERT-01, condition-bound on no live
# worktrees) — and remains the gated rsync leg's job.
#
# Two producer duties unique to this pass:
#   * syntax-gate at creation: never LINK a canonical .sh that fails bash -n
#     (HOOK-EDIT-SPAWN-POISON-01 — a link is live-from-repo, so a mid-edit
#     source would ship the moment the link lands);
#   * UNLINK: producer-owned links (resolving into PLUGIN_ROOT) whose
#     canonical source vanished are removed — the producer cleans up only its
#     own links; foreign links are counted and never touched.
#
# Every decision is logged; the pass ends with a grep-able tally line. A run
# that cannot link says so — never silently nothing.
#
# $1 label    tally label, e.g. shared/scripts or user-scripts
# $2 src_dir  canonical subdir (no trailing slash)
# $3 dst_dir  destination subdir
# $4 kind     relpath kind under plugins/leadv2/ (scripts|contracts|hooks)
# $5 scope    "all" (recursive) or "user-scripts" (top level only, leadv2-* +
#             USER_SCRIPTS_EXPLICIT_NAMES)
# Also records _LO_WOULD_LINK_RELS (newline-separated rels that got LINK):
# in DRY_RUN no links exist on disk yet, so the caller's rsync dry-run must
# exclude those rels too or it reports copies a real run would never make.
_LO_WOULD_LINK_RELS=""
_link_only_pass() {
  local label="$1" src="$2" dst="$3" kind="$4" scope="$5"
  local linked=0 converted=0 ok=0 drift=0 badlink=0 dangling=0 typeclash=0 error=0 skip=0 untracked=0 unlinked=0 foreign_links=0 held=0 total=0
  local canonical_file rel dst_file token target lrel n in_scope explicit
  local -a files=()
  _LO_WOULD_LINK_RELS=""
  [[ -d "${src}" ]] || { log_warn "link-only[${label}]: source missing: ${src}"; return 0; }
  if [[ "${scope}" == "user-scripts" ]]; then
    for canonical_file in "${src}"/*; do
      [[ -f "${canonical_file}" ]] || continue
      n="${canonical_file##*/}"
      in_scope=0
      case "${n}" in leadv2-*) in_scope=1 ;; esac
      if [[ "${in_scope}" -eq 0 ]]; then
        for explicit in "${USER_SCRIPTS_EXPLICIT_NAMES[@]}"; do
          [[ "${n}" == "${explicit}" ]] && in_scope=1 && break
        done
      fi
      [[ "${in_scope}" -eq 1 ]] && files+=("${canonical_file}")
    done
  else
    while IFS= read -r canonical_file; do
      [[ -n "${canonical_file}" ]] && files+=("${canonical_file}")
    done < <(find "${src}" -type f ! -path '*/__pycache__/*' ! -name '*.pyc' ! -name '.DS_Store' 2>/dev/null | LC_ALL=C sort)
  fi
  for canonical_file in "${files[@]}"; do
    rel="${canonical_file#${src}/}"
    dst_file="${dst}/${rel}"
    total=$((total + 1))
    if ! _is_plugin_owned "plugins/leadv2/${kind}/${rel}"; then
      untracked=$((untracked + 1))
      log "SKIP-UNTRACKED: ${dst_file} (canonical plugins/leadv2/${kind}/${rel} not in git ls-files — not plugin-owned; left to the rsync legs until committed)"
      continue
    fi
    if [[ "${dst_file}" == *.sh ]] && ! bash -n "${canonical_file}" 2>/dev/null; then
      held=$((held + 1))
      log_warn "[syntax-gate] holding ${rel}: bash -n failed — not linking a mid-edit source (a link is live-from-repo)"
      continue
    fi
    token="$(_link_one_file "${canonical_file}" "${dst_file}")"
    case "${token}" in
      LINK) linked=$((linked + 1)); log "$([[ "${DRY_RUN}" == true ]] && printf 'WOULD LINK' || printf 'LINK'): ${dst_file}"; _LO_WOULD_LINK_RELS+="${rel}\n" ;;
      CONVERT) converted=$((converted + 1)); log "$([[ "${DRY_RUN}" == true ]] && printf 'WOULD CONVERT' || printf 'CONVERT'): ${dst_file}" ;;
      OK) ok=$((ok + 1)) ;;
      DRIFT) drift=$((drift + 1)); log_warn "DRIFT: ${dst_file} — left untouched (reconciled only by the gated rsync leg; bulk conversion is SD-SYMLINK-FARM-CONVERT-01)" ;;
      BADLINK) badlink=$((badlink + 1)); log_warn "BADLINK: ${dst_file} -> $(readlink "${dst_file}" 2>/dev/null || printf '?') (left untouched)" ;;
      DANGLING) dangling=$((dangling + 1)); log_warn "DANGLING: ${dst_file} -> $(readlink "${dst_file}" 2>/dev/null || printf '?') (left untouched)" ;;
      TYPECLASH) typeclash=$((typeclash + 1)); log_warn "TYPECLASH: ${dst_file} is a directory (left untouched)" ;;
      ERROR) error=$((error + 1)); log_warn "ERROR: ${dst_file} could not be linked (left untouched)" ;;
      SKIP) skip=$((skip + 1)); log_warn "SKIP: canonical file vanished: ${canonical_file}" ;;
      *) error=$((error + 1)); log_warn "ERROR: unknown link classification ${token} for ${dst_file}" ;;
    esac
  done
  # Producer-owned link cleanup: a link we created whose canonical source is
  # gone is ours to remove. Foreign links (targets outside PLUGIN_ROOT) are
  # counted and never touched.
  if [[ -d "${dst}" ]]; then
    while IFS= read -r lrel; do
      [[ -z "${lrel}" ]] && continue
      target="$(readlink "${dst}/${lrel}" 2>/dev/null || true)"
      case "${target}" in
        "${PLUGIN_ROOT}"/*) ;;
        *) foreign_links=$((foreign_links + 1)); continue ;;
      esac
      [[ -e "${src}/${lrel}" ]] && continue
      if [[ "${DRY_RUN}" == "true" ]]; then
        log "WOULD UNLINK: ${dst}/${lrel} (canonical source gone)"
      else
        if rm -f "${dst}/${lrel}" 2>/dev/null; then
          log "UNLINK: ${dst}/${lrel} (canonical source gone)"
        else
          log_warn "ERROR: could not remove dead producer link ${dst}/${lrel}"
        fi
      fi
      unlinked=$((unlinked + 1))
    done < <(cd "${dst}" 2>/dev/null && find . -type l 2>/dev/null | sed 's|^\./||' | LC_ALL=C sort)
  fi
  log "link-only[${label}]: linked=${linked} converted=${converted} ok=${ok} drift=${drift} badlink=${badlink} dangling=${dangling} typeclash=${typeclash} error=${error} skip=${skip} untracked=${untracked} held=${held} unlinked=${unlinked} foreign_links=${foreign_links} total=${total}"
}

# _dst_link_exclude_args <dst> — rsync exclude args (anchored, leading "/")
# for every symlink currently under a destination, plus in DRY_RUN the rels
# the link pass WOULD create. rsync must never clobber a destination link back
# into a real file (a type change IS a transfer) — that would re-produce the
# exact copy production this task retires — and --delete must not reap links
# either (excluded paths are delete-protected, the same property the syntax
# gate relies on). The leading "/" anchors each pattern to the transfer root
# so a top-level name cannot over-exclude same-named files in subdirectories.
_dst_link_exclude_args() { # $1 = dst dir; prints --exclude=/<rel> lines
  local dst="$1" lrel
  [[ -d "${dst}" ]] || return 0
  while IFS= read -r lrel; do
    [[ -n "${lrel}" ]] && printf -- '--exclude=/%s\n' "${lrel}"
  done < <(cd "${dst}" 2>/dev/null && find . -type l 2>/dev/null | sed 's|^\./||' | LC_ALL=C sort)
  if [[ "${DRY_RUN}" == "true" && -n "${_LO_WOULD_LINK_RELS}" ]]; then
    printf '%b' "${_LO_WOULD_LINK_RELS}" | while IFS= read -r lrel; do
      [[ -n "${lrel}" ]] && printf -- '--exclude=/%s\n' "${lrel}"
    done
  fi
}

# Enumerate only canonical top-level files and the deliberate lib/tests trees.
# No rsync writes into a mixed repo .claude/scripts tree: every canonical file
# is classified first, so divergent local content is never overwritten.
_link_project_scripts() {
  local root="$1" dst_dir="$2" src="${PLUGIN_ROOT}/scripts" canonical_file rel dst_file token
  local root_basename="${root##*/}"
  local linked=0 converted=0 ok=0 drift=0 badlink=0 dangling=0 typeclash=0 error=0 skip=0 exception=0 total=0
  local -a canonical_files=()
  [[ -d "${src}" ]] || return 0
  while IFS= read -r canonical_file; do
    [[ -n "${canonical_file}" ]] && canonical_files+=("${canonical_file}")
  done < <(
    for canonical_file in "${src}"/*; do
      [[ -e "${canonical_file}" ]] || continue
      case "$(basename "${canonical_file}")" in
        __pycache__|*.pyc|.DS_Store) continue ;;
      esac
      if [[ -f "${canonical_file}" ]]; then
        printf '%s\n' "${canonical_file}"
      elif [[ -d "${canonical_file}" ]] && [[ "$(basename "${canonical_file}")" == "lib" || "$(basename "${canonical_file}")" == "tests" ]]; then
        find "${canonical_file}" -type f ! -path '*/__pycache__/*' ! -name '*.pyc' ! -name '.DS_Store' -print
      fi
    done | LC_ALL=C sort
  )
  for canonical_file in "${canonical_files[@]}"; do
    rel="${canonical_file#${src}/}"
    dst_file="${dst_dir}/${rel}"
    total=$((total + 1))
    if _is_plugin_sync_exception "${root_basename}" "${rel}"; then
      exception=$((exception + 1))
      log "EXCEPTION: ${dst_file} (declared override, left untouched)"
      continue
    fi
    token="$(_link_one_file "${canonical_file}" "${dst_file}")"
    case "${token}" in
      LINK) linked=$((linked + 1)); log "$([[ "${DRY_RUN}" == true ]] && printf 'WOULD LINK' || printf 'LINK'): ${dst_file}" ;;
      CONVERT) converted=$((converted + 1)); log "$([[ "${DRY_RUN}" == true ]] && printf 'WOULD CONVERT' || printf 'CONVERT'): ${dst_file}" ;;
      OK) ok=$((ok + 1)) ;;
      DRIFT) drift=$((drift + 1)); log_warn "DRIFT: ${dst_file} — $(_link_diff_detail "${canonical_file}" "${dst_file}") (left untouched)" ;;
      BADLINK) badlink=$((badlink + 1)); log_warn "BADLINK: ${dst_file} -> $(readlink "${dst_file}" 2>/dev/null || printf '?') (canonical: ${canonical_file}; left untouched)" ;;
      DANGLING) dangling=$((dangling + 1)); log_warn "DANGLING: ${dst_file} -> $(readlink "${dst_file}" 2>/dev/null || printf '?') (left untouched)" ;;
      TYPECLASH) typeclash=$((typeclash + 1)); log_warn "TYPECLASH: ${dst_file} is a directory (left untouched)" ;;
      ERROR) error=$((error + 1)); log_warn "ERROR: ${dst_file} could not be synced (left untouched)" ;;
      SKIP) skip=$((skip + 1)); log_warn "SKIP: canonical file vanished: ${canonical_file}" ;;
      *) error=$((error + 1)); log_warn "ERROR: unknown link classification ${token} for ${dst_file}" ;;
    esac
  done
  project_link_tallies+=("(c) ${root_basename}: linked=${linked} converted=${converted} ok=${ok} drift=${drift} badlink=${badlink} dangling=${dangling} typeclash=${typeclash} error=${error} skip=${skip} exception=${exception} total=${total}")
  if (( drift > 0 )); then
    project_drift_files=$((project_drift_files + drift))
    _mark_repo_drift_once "${root_basename}" && project_drift_repos=$((project_drift_repos + 1))
  fi
}

# ── Direction-safety (sync_direction_safety decision) ────────────────────────
# Before a --delete rsync push overwrites a target file with different
# content, refuse (don't guess) unless canonical's OWN git history for that
# relative path ever held exactly that content. A downstream copy carrying
# an un-landed fix canonical hasn't seen yet is exactly what silently got
# clobbered in the incident this task fixes.
#
# MODE (1st arg) controls what happens to a file deemed UNSAFE (dst content
# not reachable anywhere in canonical's git history for that relpath):
#   exclude  Emit the relpath so the caller --exclude's it; LEAVE THE COPY
#            UNTOUCHED (hard block). Use ONLY where in-place local development
#            is plausible AND the target is NOT checked by leadv2-drift-guard.sh
#            — i.e. (e) ~/.claude/scripts.
#   warn     QUARANTINE the copy's current content to a timestamped dir, THEN
#            emit nothing so rsync OVERWRITES the copy with canonical
#            (reconcile). Quarantine-then-reconcile (round-2): warn WITHOUT
#            quarantine was the e399c95 regression Codex caught — it logged a
#            loud warning and then clobbered the copy anyway, so a real
#            un-landed fix was lost exactly as the 2026-07-16 incident lost 3
#            committed fixes (a warning in a log nobody reads is not a guard).
#            Quarantine keeps the content one `cp` away from recovery into
#            canonical, while the overwrite keeps the guard satisfiable — the
#            property BOTH prior modes failed: exclude trapped divergent copies
#            forever (unsatisfiable guard); plain warn ate fixes (decorative
#            protection). Use for every guard-checked copy: (a) cache, (b)
#            shared, (f) vendored, across every warn-mode subdir.
# COPY_NAME (2nd arg): logical copy id (e.g. cache/hooks, shared/scripts,
#            leadv2-repo-vendored/scripts) — disambiguates the same relpath
#            across copies inside one quarantine timestamp dir and names the
#            recovery path in the warning.
#
# Why reconcile (not exclude) for guard-checked copies (DRIFT-GUARD-UNSATISFIABLE-01):
# exclude mode left a divergent copy unreconcilable — rsync skipped it, the copy
# stayed divergent, re-running sync never cleared it, leadv2-drift-guard exited 1
# permanently with a remedy that provably could not work; the reflex became
# LEADV2_SKIP_DRIFT_GUARD=1. ~/Projects/leadv2/.claude/scripts/ (the vendored
# copy) is gitignored+untracked in canonical's own repo, so once it diverges its
# content can NEVER be in canonical's git history — exclude mode trapped it
# forever. Verified live: exclude mode also refused to clear a 1-byte hand-edit
# on plugin-cache, so this is a class bug, not vendored-specific. Reconcile
# WITH quarantine is the only mode that both clears drift and loses nothing.
_QUARANTINE_ROOT="${LEADV2_QUARANTINE_ROOT:-${HOME}/.claude/leadv2-quarantine}"
_DIRECTION_SAFETY_CHECK="${SCRIPT_DIR}/leadv2-direction-safety-check.py"
# Runtime/compiler debris is never a plugin artifact. Keep it out of both the
# safety scan and rsync input so a local test run cannot manufacture drift or
# trigger pointless quarantine of .pyc files.
SYNC_HYGIENE_FILTERS=(--exclude='__pycache__/' --exclude='*.pyc' --exclude='.DS_Store')

# _quarantine_copy — preserve a target file's CURRENT content to a timestamped
# quarantine dir BEFORE rsync overwrites it (quarantine-then-reconcile).
#   $1 dst_file   the copy about to be overwritten
#   $2 copy_name  logical copy id (disambiguates same relpath across copies)
#   $3 relpath    path within the subdir (e.g. leadv2-foo.sh or tests/x.sh)
# Prints the absolute quarantine path on stdout; returns 1 (prints nothing) if
# the copy can't be read/preserved, so the caller can warn that reconcile
# proceeded without a safety net. One UTC timestamp per process groups a single
# sync run's quarantines together; each (copy_name, relpath) is visited at most
# once per run, so there is no in-run clobber of preserved content.
#
# LANE-TRUTH-BATCH-01 Row 3: CONVERGENCE — deduplicate by content hash.  A
# permanently-divergent copy synced N times must produce ONE quarantine copy,
# not N.  Before writing, hash the content and check whether an identical copy
# already exists anywhere in the quarantine tree for this (copy_name, relpath).
# If so, return that existing path instead of creating a duplicate.
_quarantine_copy() {
  local dst_file="$1" copy_name="$2" relpath="$3"
  [[ -f "${dst_file}" ]] || return 0
  local content_hash
  # Do not pipe sha256sum through cut: without pipefail, a failed hash command
  # becomes an empty successful substitution and two unreadable files compare
  # equal. Empty hashes are never valid content identities.
  content_hash="$(sha256sum "${dst_file}" 2>/dev/null)" || return 1
  content_hash="${content_hash%% *}"
  [[ -n "${content_hash}" ]] || return 1
  # Check for an existing quarantine copy with identical content (convergence)
  local existing
  existing="$(while IFS= read -r prev; do
    local prev_hash
    prev_hash="$(sha256sum "${prev}" 2>/dev/null)" || return 1
    prev_hash="${prev_hash%% *}"
    [[ -n "${prev_hash}" ]] || return 1
    if [[ "${prev_hash}" == "${content_hash}" ]]; then
      printf -- '%s\n' "${prev}"; break
    fi
  done < <(find "${_QUARANTINE_ROOT}" -path "*/${copy_name}/${relpath}" -type f 2>/dev/null))" || return 1
  if [[ -n "${existing}" ]]; then
    printf -- '%s\n' "${existing}"
    return 0
  fi
  local ts qpath
  ts="$(date -u '+%Y%m%dT%H%M%SZ')" || return 1
  # Include the content identity in the run directory. Two edits can be
  # quarantined within the same UTC second; without this, the later edit
  # overwrites the earlier recovery copy despite having a different hash.
  qpath="${_QUARANTINE_ROOT}/${ts}-${content_hash}/${copy_name}/${relpath}"
  mkdir -p "$(dirname "${qpath}")" || return 1
  cp -p "${dst_file}" "${qpath}" || return 1
  printf -- '%s\n' "${qpath}"
}

# _sync_direction_of <canonical_file> <canonical_git_relpath> <dst_file>
# Prints VENDORED_NEWER / CANONICAL_NEWER / UNKNOWN. DUPLICATED from
# leadv2-drift-guard.sh decide_direction() on purpose — shell heredocs cannot
# import, and the two must stay evidence-identical: canonical evidence = last
# git-commit time of the relpath (fallback: canonical file mtime when
# untracked), copy evidence = copy filesystem mtime, 2s buffer. If you change
# the rule here, change it there in the same commit.
_sync_direction_of() {
  python3 - "${PLUGIN_GIT_ROOT}" "$1" "$2" "$3" <<'PYEOF'
import os, subprocess, sys

git_root, canonical_file, git_relpath, copy_file = sys.argv[1:5]

def canonical_commit_time(git_relpath):
    try:
        out = subprocess.run(
            ["git", "-C", git_root, "log", "-1", "--format=%ct", "--", git_relpath],
            capture_output=True, text=True, timeout=5,
        )
        ts = out.stdout.strip()
        if ts:
            return int(ts)
    except Exception:
        pass
    return None

def _mtime(path):
    try:
        return os.path.getmtime(path)
    except OSError:
        return None

canon_evidence = canonical_commit_time(git_relpath)
if canon_evidence is None:
    canon_evidence = _mtime(canonical_file)
copy_evidence = _mtime(copy_file)
if canon_evidence is None or copy_evidence is None:
    print("UNKNOWN")
elif copy_evidence > canon_evidence + 2:
    print("VENDORED_NEWER")
elif canon_evidence > copy_evidence + 2:
    print("CANONICAL_NEWER")
else:
    print("UNKNOWN")
PYEOF
}

# _dst_file_dirty <dst_dir> <dst_file> — 0 when dst_dir sits inside a git work
# tree AND dst_file is tracked-and-modified or staged there (any porcelain XY
# except untracked `??`; ignored files never appear in porcelain at all).
# Untracked is deliberately NOT dirty: many vendored .claude/scripts trees are
# carried untracked by design, and refusing them would permanently block every
# sync to those repos — the DRIFT-GUARD-UNSATISFIABLE-01 trap. Untracked files
# keep their protection from the backward gate + direction-safety instead.
_dst_file_dirty() {
  local dst_dir="$1" dst_file="$2"
  local status_line
  status_line="$(git -C "${dst_dir}" --no-optional-locks status --porcelain -- "${dst_file}" 2>/dev/null | head -1)" || return 1
  [[ -z "${status_line}" ]] && return 1
  [[ "${status_line}" == "?? "* ]] && return 1
  return 0
}

# _contract_write_gate — DELETED (C1-RETIRE-RSYNC, 2026-09-08): project
# contracts (d) are link-only now, and a link is structurally never written,
# so the cp-era gate-1/gate-2 overwrite machinery had nothing left to guard.
# The uncommitted-destination hard-refuse survives inline in
# _sync_project_root (swapping a tracked-and-modified project file for a link
# mid-edit is still not ours to do); the VENDORED_NEWER refusal is moot — a
# divergent real contract copy is DRIFT and is left untouched, never
# overwritten, so nothing newer can be lost.

_direction_safety_excludes() {
  local mode="$1" copy_name="$2" subdir="$3" src="$4" dst="$5"
  shift 5
  # M-B fix (review-2.md): optional trailing rsync filter args, e.g.
  # --include='leadv2-*' --exclude='*' for target (e), whose real sync only
  # ever transfers a leadv2-* subset. Scopes this dry-run scan to the same
  # subset instead of checksumming the full (possibly large, e.g.
  # node_modules/) source tree just to compute an exclude list nothing in
  # that tree would ever have matched anyway.
  local -a extra_filters=("$@")
  [[ -f "${_DIRECTION_SAFETY_CHECK}" ]] || return 0
  [[ -d "${dst}" ]] || return 0  # nothing on disk yet to clobber — all safe
  local changed
  changed="$(rsync -rc --delete --dry-run --itemize-changes "${extra_filters[@]}" "${src}" "${dst}" 2>/dev/null \
    | awk '$1 ~ /^>f/ {print $2}')" || true
  [[ -z "${changed}" ]] && return 0
  local relpath
  while IFS= read -r relpath; do
    [[ -z "${relpath}" ]] && continue
    local dst_file="${dst}/${relpath}"
    [[ -f "${dst_file}" ]] || continue  # new file, nothing to clobber — safe
    local canonical_relpath="plugins/leadv2/${subdir}/${relpath}"
    # Write gate 1 (DRIFT-GUARD-ADVISES-BACKWARD-SYNC-01): uncommitted
    # destination — hard refuse, no flag overrides. Runs FIRST so a dirty
    # destination is refused regardless of direction tags.
    if _dst_file_dirty "${dst}" "${dst_file}"; then
      _REFUSED_COUNT=$((_REFUSED_COUNT + 1))
      if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "DRY_RUN REFUSED (uncommitted destination): would not write ${dst_file} — tracked-and-modified/uncommitted in the destination repo. Commit it, or promote it into canonical; no flag overrides this."
      else
        log_warn "REFUSED: ${dst_file} is tracked-and-modified/uncommitted in the destination repo — refusing to overwrite (no flag overrides). Commit it, or promote it into canonical (cp ${dst_file} ${CANONICAL_ROOT}/plugins/leadv2/${subdir}/${relpath}) and re-run."
      fi
      printf -- '%s\n' "${relpath}"
      continue
    fi
    # Write gate 2: backward move. Same evidence rule as drift-guard
    # (_sync_direction_of above): destination mtime newer than canonical's
    # last commit for this relpath → refuse without --allow-backward.
    local _direction
    _direction="$(_sync_direction_of "${src}${relpath}" "${canonical_relpath}" "${dst_file}")" || _direction="UNKNOWN"
    if [[ "${_direction}" == "VENDORED_NEWER" && "${ALLOW_BACKWARD}" != "true" ]]; then
      _REFUSED_COUNT=$((_REFUSED_COUNT + 1))
      if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "WOULD MOVE BACKWARDS (refusing without --allow-backward): ${dst_file} is NEWER than canonical for ${canonical_relpath} — a real run will NOT overwrite it. Promote instead: cp ${dst_file} ${CANONICAL_ROOT}/plugins/leadv2/${subdir}/${relpath} + commit in canonical."
      else
        # Refuse = exclude + leave untouched, but STILL preserve a quarantine
        # copy first: e399c95's lesson (protection without preservation loses
        # the fix) applies to refusals too. _quarantine_copy is
        # non-destructive and content-hash deduplicated.
        local qpath
        qpath="$(_quarantine_copy "${dst_file}" "${copy_name}" "${relpath}")" || qpath=""
        log_warn "REFUSED (backward): ${dst_file} is NEWER than canonical for ${canonical_relpath} — NOT overwriting. Promote instead: cp ${dst_file} ${CANONICAL_ROOT}/plugins/leadv2/${subdir}/${relpath} then commit in canonical. (Content also preserved at: ${qpath:-<quarantine-unavailable>}; override with --allow-backward.)"
      fi
      printf -- '%s\n' "${relpath}"
      continue
    fi
    if ! python3 "${_DIRECTION_SAFETY_CHECK}" "${PLUGIN_GIT_ROOT}" "${canonical_relpath}" "${dst_file}"; then
      if [[ "${mode}" == "exclude" ]]; then
        # LANE-TRUTH-BATCH-01 Row 3: quarantine the divergent copy BEFORE
        # excluding, so a later manual cleanup or forced sync cannot silently
        # lose an un-landed fix.  The exclude itself is unchanged — rsync skips
        # the file, the copy stays divergent.  The quarantine is the safety net
        # the old exclude lacked (warn mode already quarantines+reconciles;
        # exclude mode was the only path with no preservation at all).
        # _quarantine_copy deduplicates by content hash (convergence): a
        # permanently-divergent copy is quarantined once, not on every sync.
        if [[ "${DRY_RUN}" == "true" ]]; then
          log_warn "DRY_RUN DIRECTION-SAFETY (block+would-quarantine): ${dst_file} content not reachable in canonical history for ${canonical_relpath}. No quarantine or target write performed."
        else
          local qpath
          qpath="$(_quarantine_copy "${dst_file}" "${copy_name}" "${relpath}")" || qpath=""
          if [[ -n "${qpath}" ]]; then
            log_warn "DIRECTION-SAFETY (block+quarantine): refusing to overwrite ${dst_file} — its content is not reachable anywhere in canonical's git history for ${canonical_relpath} (possible un-landed fix on this copy). Excluding this file from the sync. ORIGINAL CONTENT PRESERVED at: ${qpath} — if this was a real fix: cp it into canonical (${canonical_relpath}) and re-sync."
          else
            log_warn "DIRECTION-SAFETY (block): refusing to overwrite ${dst_file} — its content is not reachable anywhere in canonical's git history for ${canonical_relpath} (possible un-landed fix on this copy). Excluding this file from the sync; quarantine unavailable. Land the fix in canonical first."
          fi
        fi
        printf -- '%s\n' "${relpath}"
      else
        # warn mode: PRESERVE first (quarantine), THEN let rsync reconcile.
        # Quarantine-then-reconcile — see MODE doc above. Emit nothing so the
        # caller's rsync still overwrites (reconcile); the quarantine copy is
        # the safety net plain-warn mode lacked.
        if [[ "${DRY_RUN}" == "true" ]]; then
          log_warn "DRY_RUN DIRECTION-SAFETY (would quarantine+reconcile): ${dst_file} content is not reachable in canonical history for ${canonical_relpath}. No quarantine or target write performed."
        else
          local qpath
          qpath="$(_quarantine_copy "${dst_file}" "${copy_name}" "${relpath}")" || qpath=""
          if [[ -n "${qpath}" ]]; then
            log_warn "DIRECTION-SAFETY (warn+quarantine): ${dst_file} content not reachable in canonical's git history for ${canonical_relpath} (possible un-landed fix). Canonical is the pinned source of truth (SOURCE-PIN + CACHE-REFUSAL) — OVERWRITING this copy to reconcile (guard stays satisfiable). ORIGINAL CONTENT PRESERVED at: ${qpath} — if this was a real fix: cp it into canonical (${canonical_relpath}) and re-sync."
          else
            log_warn "DIRECTION-SAFETY (warn): ${dst_file} content not reachable in canonical history; quarantine unavailable but reconcile proceeds (guard satisfiability takes priority — content may be lost; investigate)."
          fi
        fi
      fi
    fi
  done <<< "${changed}"
}
# ── Resolve list of (c)/(d) project roots ────────────────────────────────────
_resolve_project_roots() {
  if [[ -n "${PROJECT_ROOT_OVERRIDE}" ]]; then
    printf -- '%s\n' "${PROJECT_ROOT_OVERRIDE}"
    return
  fi
  if [[ -n "${LEADV2_PROJECT_ROOT:-}" ]]; then
    printf -- '%s\n' "${LEADV2_PROJECT_ROOT}"
    return
  fi
  if [[ ! -f "${CROSS_REPO_CONFIG}" ]]; then
    log_warn "(c)/(d): cross-repo-paths.yaml not found at ${CROSS_REPO_CONFIG}; skipping project sync"
    return
  fi
  # Parse path + vendors_scripts values from YAML with python3 (no yq
  # dependency). Emits "<path>\t<vendors_scripts>" (default "true" when the
  # field is absent, preserving prior behavior for every repo except any
  # explicitly opted out — C2 fix, PLUGIN-CACHE-THIRD-COPY-REVERTS-FIXES-01).
  python3 - "${CROSS_REPO_CONFIG}" <<'PYEOF'
import sys, yaml, os

def vendors_scripts_enabled(entry):
    # L-B fix (review-2.md): PyYAML only auto-bools UNQUOTED false/no/off/0.
    # A future `vendors_scripts: "false"` (quoted string) would otherwise be
    # a truthy non-empty str -> silently re-vendors the repo with zero
    # warning, the exact incident this field exists to prevent. Accept
    # common string spellings too, not just the bool identity.
    v = entry.get("vendors_scripts", True)
    if isinstance(v, bool):
        return v
    return str(v).strip().lower() not in ("false", "no", "off", "0")

config = yaml.safe_load(open(sys.argv[1])) or {}
repos = config.get("repos") or {}
for name, entry in repos.items():
    entry = entry or {}
    raw = entry.get("path", "")
    expanded = os.path.expanduser(raw)
    if expanded:
        vendors = vendors_scripts_enabled(entry)
        print(f"{expanded}\t{'true' if vendors else 'false'}")
PYEOF
}

# ── Helper: sync (c)/(d) for a single project root ───────────────────────────
# $2 (vendors_scripts, default "true"): when "false", skip (c) .claude/scripts/
# AND (c2) the curated top-level scripts/ subset entirely for this root — a
# repo whose architecture is symlink-only (e.g. campaign-platform,
# cross-repo-paths.yaml `vendors_scripts: false`) must never have a vendored
# scripts tree recreated on it (C2 fix, PLUGIN-CACHE-THIRD-COPY-REVERTS-FIXES-01).
# (d) contracts (schema files, not "scripts") are unaffected by this flag.
_sync_project_root() {
  local root="$1"
  local vendors_scripts="${2:-true}"
  if [[ ! -d "${root}" ]]; then
    log_warn "(c)/(d): project root not found on disk, skipping: ${root}"
    return 0
  fi
  local proj_scripts="${root}/.claude/scripts"
  local proj_contracts="${root}/.claude/contracts"
  # Declared unconditionally (not just inside the non-symlink branch below):
  # the (c2) curated-subset loop further down this function reads ${src}
  # regardless of which branch (c) took, and this script runs under
  # `set -euo pipefail` — an unset `local src` only declared inside a
  # not-taken if-branch would abort the whole sync on any repo whose
  # .claude/scripts IS a symlink (M-A fix, caught before landing).
  local src="${PLUGIN_ROOT}/scripts/"

  # SYMLINK-AWARE-SYNC-01 (plugin-distribution Stage 2, 2026-07-28): if
  # proj_scripts is ALREADY a symlink (Stage 3 target: <repo>/.claude/scripts
  # -> canonical or a shared tree, same pattern already live for
  # .claude/leadv2/ and .claude/agents/), it is symlink-managed and reading
  # through it always reflects canonical directly — nothing to rsync. Writing
  # through it anyway is at best redundant and at worst destructive: rsync
  # --checksum with no -l/-L declared, run repeatedly as this repo's own
  # scripts/ tree grows, is one `--delete` addition away from deleting the
  # symlink and materializing real files in its place, silently restoring the
  # exact five-copy world this whole task exists to close (team-lead brief,
  # explicit premise). `-L` tests "is a symlink" even if the link is dangling.
  if [[ -L "${proj_scripts}" ]]; then
    log "(c): ${proj_scripts} is a symlink (symlink-managed, Stage 3) — skipping project-scripts sync entirely, nothing to write"
  else
    if [[ "${vendors_scripts}" == "false" ]]; then
      log_warn "(c): skipping project scripts vendoring for ${root} — vendors_scripts: false (symlink-only architecture)"
    else
      log "Syncing -> project scripts (c): ${proj_scripts}"
      if [[ ! -d "${proj_scripts}" ]]; then
        log "(c): ${proj_scripts} absent — not creating it"
      elif [[ -d "${src}" ]]; then
        _link_project_scripts "${root}" "${proj_scripts}"
      fi
    fi
  fi

  # (c2) Some repos ALSO vendor a CURATED subset of leadv2-* scripts at
  # <root>/scripts/ (top-level, NOT .claude/scripts/) — e.g. persona-engine's
  # out-of-worktree control plane (2026-07-14, 6321bf2). This second location was
  # never covered by (c) above, so it silently drifted (SUPERVISE-V2-01 found it
  # missing the supervisor loop's two companion scripts entirely + a stale
  # snapshot script). FIXED SET, not a leadv2-* wildcard: a wildcard rsync
  # dumps the FULL ~150-file canonical scripts/ dir into what has always been a
  # deliberately curated ~13-file subset (confirmed by scoping this list to the
  # pre-existing files there + the hard runtime deps leadv2-lanes-snapshot.sh's
  # source chain actually requires: active-registry.sh sourced directly by
  # lanes-snapshot.sh L136-138). SUPERVISOR-DELETE-01 (2026-08-17): the
  # supervisor loop/pick companions are gone — the snapshot script was renamed
  # to leadv2-lanes-snapshot.sh (live founder-status lanes-table dependency,
  # not supervisor-only) and the loop's two companion scripts were deleted
  # outright with the rest of the supervisor machinery. Extend this list only
  # when a repo's control-plane scripts/ genuinely adopts a new companion —
  # never switch this back to a wildcard.
  local proj_scripts_toplevel="${root}/scripts"
  local -a toplevel_curated_files=(
    leadv2-answer.sh leadv2-ask.sh leadv2-bus.sh leadv2-client-surface-gate.sh
    leadv2-fanout-classify.sh leadv2-fanout.sh leadv2-phase8-assert.sh leadv2-phase8-close.sh leadv2-phase8-e2e-gate.sh
    leadv2-merge-queue.sh leadv2-provider-rollup.sh leadv2-session-route.sh
    leadv2-session-runner.sh leadv2-codex-session-runner.sh leadv2-progress-fingerprint.sh
    leadv2-state-path.sh leadv2-lanes-snapshot.sh leadv2-tasks-regen-gate.sh
    leadv2-active-registry.sh
    leadv2-tasks-lib.sh leadv2-helpers.sh
  )
  if [[ "${vendors_scripts}" != "false" ]] && [[ -d "${proj_scripts_toplevel}" ]] && compgen -G "${proj_scripts_toplevel}/leadv2-*" > /dev/null 2>&1; then
    log "Syncing -> project top-level scripts (c2, out-of-worktree control plane): ${proj_scripts_toplevel} [curated set, additive]"
    for cf in "${toplevel_curated_files[@]}"; do
      local cf_src="${src}${cf}"
      if [[ -f "${cf_src}" ]]; then
        if _is_plugin_sync_exception "${root##*/}" "toplevel/${cf}"; then
          log "EXCEPTION: ${proj_scripts_toplevel}/${cf} (declared override, left untouched)"
          continue
        fi
        local cf_token
        cf_token="$(_link_one_file "${cf_src}" "${proj_scripts_toplevel}/${cf}")"
        case "${cf_token}" in
          LINK|CONVERT) log "$([[ "${DRY_RUN}" == true ]] && printf "WOULD ${cf_token}" || printf "${cf_token}"): ${proj_scripts_toplevel}/${cf}" ;;
          OK|SKIP) : ;;
          DRIFT)
            log_warn "DRIFT: ${proj_scripts_toplevel}/${cf} — $(_link_diff_detail "${cf_src}" "${proj_scripts_toplevel}/${cf}") (left untouched)"
            project_drift_files=$((project_drift_files + 1))
            _mark_repo_drift_once "${root##*/}" && project_drift_repos=$((project_drift_repos + 1))
            ;;
          BADLINK|DANGLING|TYPECLASH|ERROR) log_warn "${cf_token}: ${proj_scripts_toplevel}/${cf} (left untouched)" ;;
          *) log_warn "ERROR: unknown link classification ${cf_token} for ${proj_scripts_toplevel}/${cf}" ;;
        esac
      fi
    done
    log_ok "[project/scripts-toplevel[${root##*/}]] synced curated set -> ${proj_scripts_toplevel}"
  fi

  log "Syncing -> project contracts (d): ${proj_contracts} [link-only]"
  for schema_file in leadv2-scorecard.schema.json leadv2-shadow-proposal.schema.json; do
    local schema_src="${PLUGIN_ROOT}/contracts/${schema_file}"
    if [[ -f "${schema_src}" ]]; then
      # C1-RETIRE-RSYNC: contracts enter projects the way scripts enter (c) —
      # as symlinks into canonical. A link is never overwritten, so only one
      # cp-era protection survives, inline: an uncommitted (tracked-and-
      # modified/staged) destination file is hard-refused. A divergent but
      # committed copy is DRIFT and left untouched (promote or discard);
      # identical content converts losslessly.
      local dst_schema="${proj_contracts}/${schema_file}"
      if _dst_file_dirty "${root}" "${dst_schema}"; then
        _REFUSED_COUNT=$((_REFUSED_COUNT + 1))
        log_warn "REFUSED (uncommitted destination): ${dst_schema} is tracked-and-modified/uncommitted in the destination repo — refusing to touch it (no flag overrides). Commit it, or promote it into canonical (cp ${dst_schema} ${CANONICAL_ROOT}/plugins/leadv2/contracts/${schema_file}) and re-run."
        continue
      fi
      if ! _is_plugin_owned "plugins/leadv2/contracts/${schema_file}"; then
        log "SKIP-UNTRACKED: ${dst_schema} (canonical plugins/leadv2/contracts/${schema_file} not in git ls-files — not plugin-owned; not delivered)"
        continue
      fi
      local d_token
      d_token="$(_link_one_file "${schema_src}" "${dst_schema}")"
      case "${d_token}" in
        LINK|CONVERT) log "$([[ "${DRY_RUN}" == true ]] && printf 'WOULD %s' "${d_token}" || printf '%s' "${d_token}"): ${dst_schema}" ;;
        OK) : ;;
        DRIFT) log_warn "DRIFT: ${dst_schema} — left untouched (promote into canonical or discard; bulk conversion is SD-SYMLINK-FARM-CONVERT-01)" ;;
        BADLINK|DANGLING|TYPECLASH|ERROR|SKIP) log_warn "${d_token}: ${dst_schema} (left untouched)" ;;
        *) log_warn "ERROR: unknown link classification ${d_token} for ${dst_schema}" ;;
      esac
    else
      log_warn "source not found, skipping: ${schema_src}"
    fi
  done

}

changed_summary=()
project_link_tallies=()
project_drift_files=0
project_drift_repos=0

# ── (a) Plugin cache — RETIRED (C1-RETIRE-RSYNC, 2026-09-08) ──────────────────
# This leg rsynced into ~/.claude/plugins/cache/leadv2-local/leadv2/0.1.0/ — a
# version dir the runtime has ORPHANED. Measured live 2026-09-08:
#   * installed_plugins.json leadv2@leadv2-local installPath =
#     .../cache/leadv2-local/leadv2/0.5.7 — the path Claude Code actually
#     loads; 0.1.0 is not referenced by the registry;
#   * 0.1.0/.orphaned_at exists (runtime-written 2026-09-08 21:06:43 +0300,
#     epoch-ms content 1788890803187);
#   * hook/command BODIES are live-from-repo regardless: settings.json pins
#     CLAUDE_PLUGIN_ROOT to ~/.claude/plugins/local/leadv2/plugins/leadv2, a
#     directory symlink to this repo (probe evidence in
#     leadv2-plugin-cache-sync.sh's header, LEADV2-HOOK-CACHE-DEPLOY-01);
#   * the ACTIVE cache dir already has a dedicated producer:
#     leadv2-plugin-cache-sync.sh (whole-tree rsync --delete + .synced-from=
#     <repo HEAD>, its own suite test-plugin-cache-sync.sh).
# Writing 0.1.0 was pure copy-production into a tree nothing reads. Stopped
# entirely — deliberately NOT converted to links. Residual readers of the
# frozen 0.1.0 (follow-up, out of this lane's writes): leadv2-drift-guard.sh
# (COPY_PATHS entry) and leadv2-outcome-watch.sh (soak-class-delays.yaml).
log "SKIP plugin cache (a): RETIRED (C1-RETIRE-RSYNC) — 0.1.0 is an orphaned version dir (runtime installPath=0.5.7); the active cache is owned by leadv2-plugin-cache-sync.sh"

# ── (b) leadv2-shared (scripts + contracts + hooks) ──────────────────────────
# hooks added COMPACT-DEDUP-01 FU1 (2026-07-23): leadv2-shared/hooks/ held a
# manually-copied mirror of the plugin's hooks/ that this loop never touched
# -- it drifted (missing fixes landed only in canonical/cache). Global
# ~/.claude/settings.json points PreCompact directly at this shared copy
# (the repo-agnostic bootstrap, works without the plugin loaded), so it must
# be kept byte-identical to canonical the same way scripts/contracts already are.
log "Syncing -> leadv2-shared (b): ${SHARED_TARGET} [link-only producer + gated shadow refresh]"
for subdir in scripts contracts hooks; do
  src="${PLUGIN_ROOT}/${subdir}/"
  dst="${SHARED_TARGET}/${subdir}"
  if [[ -d "${src}" ]]; then
    # Link-only producer first (C1-RETIRE-RSYNC): every plugin-owned canonical
    # file either is a link, becomes one, or is a real copy this pass refuses
    # to touch (DRIFT / dirty). Only then the rsync leg runs, scoped by the
    # link excludes to the REAL copies — shadow refresh only, never creation:
    # absent plugin-owned files are already links and excluded.
    _link_only_pass "shared/${subdir}" "${PLUGIN_ROOT}/${subdir}" "${dst}" "${subdir}" all
    _link_excludes=()
    while IFS= read -r _le; do
      [[ -n "${_le}" ]] && _link_excludes+=("${_le}")
    done < <(_dst_link_exclude_args "${dst}")
    _unsafe_excludes=()
    while IFS= read -r _u; do
      [[ -z "${_u}" ]] && continue
      _unsafe_excludes+=(--exclude="${_u}")
    done < <(_direction_safety_excludes "warn" "shared/${subdir}" "${subdir}" "${src}" "${dst}" ${_link_excludes[@]+"${_link_excludes[@]}"} "${SYNC_HYGIENE_FILTERS[@]}")
    # Link excludes FIRST: rsync filter rules are first-match-wins and a
    # destination symlink must never be reclaimed as a transfer (type change)
    # or deleted — that would re-produce the copy this pass just retired.
    _rsync_or_dry "shared/${subdir}" "${src}" "${dst}" --recursive --delete ${_link_excludes[@]+"${_link_excludes[@]}"} "${SYNC_HYGIENE_FILTERS[@]}" "${_unsafe_excludes[@]}"
    changed_summary+=("shared/${subdir}")
  fi
done

# ── (e) ~/.claude/scripts/ — user-global leadv2-* scripts ───────────────────
# ADDITIVE ONLY: --include='leadv2-*' --exclude='*' scopes rsync to leadv2-*
# files only. NO --delete — preserves codex-task.sh, ask-lead.sh, cx-tail.sh,
# and all other non-leadv2 user-global scripts (24 files; must never change).
USER_SCRIPTS_TARGET="${HOME}/.claude/scripts"
log "Syncing -> user-global scripts (e): ${USER_SCRIPTS_TARGET} [leadv2-* only, additive, no --delete]"
# H1 fix (review-1.md, fix1): (e) was the only sync target NOT wrapped in
# _direction_safety_excludes — no --delete does not mean no overwrite; rsync
# still clobbers a same-named file when content differs. A locally-patched
# leadv2-*.sh sitting here that hasn't yet landed in canonical would be
# silently overwritten on the next sync (the exact incident class this task
# fixes, for a target context.yaml's "five copies" enumeration didn't name).
# PLUGIN-TOOLING-FIX-01 C: measured intersection of canonical scripts/ and the
# user tree's genuinely-consumed non-`leadv2-*` launchers (glm-coder.sh killed
# three lanes stale). Single source of truth for BOTH the direction-safety
# generator (below) and the real rsync -- duplicating this list literally
# between the two call sites is exactly the drift bug this fix exists to avoid.
USER_SCRIPTS_EXPLICIT_NAMES=(
  glm-coder.sh
  ask-lead.sh
  claude-subsession.sh
  codex-task.sh
  lv2
  lv2-ledger-emit.py
  lv2-ledger-last-phase.py
  leadv2_tasks_yaml_common.py
)
USER_SCRIPTS_FILTERS=(--include='leadv2-*')
for _explicit in "${USER_SCRIPTS_EXPLICIT_NAMES[@]}"; do
  USER_SCRIPTS_FILTERS+=(--include="${_explicit}")
done
USER_SCRIPTS_FILTERS+=(--exclude='*')

# Link-only producer (C1-RETIRE-RSYNC): in-scope plugin-owned canonical
# scripts enter ~/.claude/scripts as symlinks; existing real copies are
# classified (CONVERT when identical, DRIFT when divergent) and the rsync leg
# below remains as gated shadow refresh only.
_link_only_pass "user-scripts" "${PLUGIN_ROOT}/scripts" "${USER_SCRIPTS_TARGET}" "scripts" user-scripts
_link_excludes=()
while IFS= read -r _le; do
  [[ -n "${_le}" ]] && _link_excludes+=("${_le}")
done < <(_dst_link_exclude_args "${USER_SCRIPTS_TARGET}")

_unsafe_excludes=()
while IFS= read -r _u; do
  [[ -z "${_u}" ]] && continue
  _unsafe_excludes+=(--exclude="${_u}")
done < <(_direction_safety_excludes "exclude" "user-scripts" "scripts" "${PLUGIN_ROOT}/scripts/" "${USER_SCRIPTS_TARGET}" ${_link_excludes[@]+"${_link_excludes[@]}"} "${USER_SCRIPTS_FILTERS[@]}")
# rsync filter rules are first-match-wins: link excludes and unsafe excludes
# MUST precede the generic USER_SCRIPTS_FILTERS wildcard block, or that
# wildcard would already have claimed (and included) the filename before its
# specific --exclude is ever reached. Link excludes also keep rsync from
# reclaiming a destination symlink as a real-file transfer.
_rsync_or_dry "user-scripts" "${PLUGIN_ROOT}/scripts/" "${USER_SCRIPTS_TARGET}" \
  ${_link_excludes[@]+"${_link_excludes[@]}"} "${_unsafe_excludes[@]}" "${USER_SCRIPTS_FILTERS[@]}" -d
changed_summary+=("user-scripts")

# ── (e.1) Skip report (PLUGIN-TOOLING-FIX-01 C.2) ───────────────────────────
# Report-only: names every canonical top-level entry NOT delivered to the user
# scripts dir and why, so drift is visible instead of silently converging
# "81 of 90" with no record of the other 9. Never changes a delivery decision;
# derived purely from filesystem state + the filter list above, so --dry-run
# produces the identical report.
_us_delivered=0
_us_skipped=0
for _canon_entry in "${PLUGIN_ROOT}/scripts"/*; do
  [[ -e "${_canon_entry}" ]] || continue
  _cname="$(basename "${_canon_entry}")"
  if [[ ! -f "${_canon_entry}" ]]; then
    printf '[plugin-sync] user-scripts SKIPPED %s reason=not-a-file\n' "${_cname}"
    _us_skipped=$((_us_skipped + 1))
    continue
  fi
  _in_scope=0
  case "${_cname}" in
    leadv2-*) _in_scope=1 ;;
  esac
  if [[ "${_in_scope}" -eq 0 ]]; then
    for _explicit in "${USER_SCRIPTS_EXPLICIT_NAMES[@]}"; do
      [[ "${_cname}" == "${_explicit}" ]] && _in_scope=1 && break
    done
  fi
  if [[ "${_in_scope}" -eq 0 ]]; then
    printf '[plugin-sync] user-scripts SKIPPED %s reason=out-of-include-scope\n' "${_cname}"
    _us_skipped=$((_us_skipped + 1))
    continue
  fi
  _is_unsafe=0
  for _u in "${_unsafe_excludes[@]}"; do
    [[ "${_u}" == "--exclude=${_cname}" ]] && _is_unsafe=1 && break
  done
  if [[ "${_is_unsafe}" -eq 1 ]]; then
    printf '[plugin-sync] user-scripts SKIPPED %s reason=drift-guard-excluded\n' "${_cname}"
    _us_skipped=$((_us_skipped + 1))
    continue
  fi
  _target_file="${USER_SCRIPTS_TARGET}/${_cname}"
  if [[ -f "${_target_file}" ]] && ! cmp -s "${_canon_entry}" "${_target_file}"; then
    # LAUNCHER-DIVERGENCE-01: this branch only runs for entries that already
    # passed out-of-include-scope and drift-guard-excluded above, i.e.
    # direction-safety judged the target safe to overwrite -- the rsync at
    # (d) above (real, non---dry-run) DELIVERS this file. It is not a skip;
    # label it as delivered so the report's own contract ("names every
    # canonical entry NOT delivered") holds.
    printf '[plugin-sync] user-scripts DELIVERED %s reason=overwrites-divergent-target\n' "${_cname}"
    _us_delivered=$((_us_delivered + 1))
    continue
  fi
  _us_delivered=$((_us_delivered + 1))
done
printf '[plugin-sync] user-scripts: delivered=%s skipped=%s (of %s canonical entries)\n' \
  "${_us_delivered}" "${_us_skipped}" "$((_us_delivered + _us_skipped))"

# ── (f) leadv2 repo's OWN vendored .claude/scripts (copy #2 of the 5,
# PLUGIN-CACHE-THIRD-COPY-REVERTS-FIXES-01 context.yaml) ─────────────────────
# ~/Projects/leadv2/.claude/scripts/ is not this repo's own canonical (that's
# plugins/leadv2/scripts/), but it IS one of the 5 copies the drift-guard
# checks, and — unlike the (c)/(d) targets which iterate cross-repo-paths.yaml
# — it was never an actual sync TARGET here, so it would drift forever and
# perpetually fail the drift-guard/fanout preflight. Sync it the same way as
# (c), hardcoded (this repo is intentionally NOT added to the shared
# cross-repo-paths.yaml — that file is a shared tree, out of this task's
# edit authorization).
LEADV2_REPO_VENDORED="${CANONICAL_ROOT}/.claude/scripts"
if [[ -d "${CANONICAL_ROOT}/.claude" ]]; then
  log "Syncing -> leadv2 repo's own vendored scripts (f): ${LEADV2_REPO_VENDORED}"
  _unsafe_excludes=()
  while IFS= read -r _u; do
    [[ -z "${_u}" ]] && continue
    _unsafe_excludes+=(--exclude="${_u}")
  done < <(_direction_safety_excludes "warn" "leadv2-repo-vendored/scripts" "scripts" "${PLUGIN_ROOT}/scripts/" "${LEADV2_REPO_VENDORED}" "${SYNC_HYGIENE_FILTERS[@]}")
  _rsync_or_dry "leadv2-repo-vendored/scripts" "${PLUGIN_ROOT}/scripts/" "${LEADV2_REPO_VENDORED}" --recursive --delete "${SYNC_HYGIENE_FILTERS[@]}" "${_unsafe_excludes[@]}"
  changed_summary+=("leadv2-repo-vendored")
fi

# ── (g) Codex leadv2 skill — install so provider=codex lead sessions route ───
# leadv2-session-route.sh requires a leadv2 skill file for Codex lead sessions;
# without it provider=codex SILENTLY falls back to Claude. The plugin now SHIPS
# the canonical skill under codex-skills/ so a fresh rollout enables Codex-lead
# with NO hand-created artifact. Install it to the Codex user skills dir.
# Additive per-skill dir (scoped to source-command-leadv2; never touches other
# Codex skills). Idempotent.
CODEX_SKILL_SRC="${PLUGIN_ROOT}/codex-skills/source-command-leadv2"
CODEX_SKILL_DST="${HOME}/.codex/skills/source-command-leadv2"
if [[ -d "${CODEX_SKILL_SRC}" ]]; then
  log "Syncing -> Codex leadv2 skill (g): ${CODEX_SKILL_DST}"
  # No --delete: the skill dir only ever holds SKILL.md (nothing to prune), and
  # --delete could follow a symlinked dst and remove unrelated Codex skills (Codex
  # review HIGH). Additive copy is sufficient and symlink-safe.
  _rsync_or_dry "codex-leadv2-skill" "${CODEX_SKILL_SRC}/" "${CODEX_SKILL_DST}" --recursive
  changed_summary+=("codex-skill")
else
  log "SKIP (g) Codex leadv2 skill: source ${CODEX_SKILL_SRC} absent"
fi

# ── (c)/(d) Per-project .claude/scripts + .claude/contracts ──────────────────
# Iterate all roots from cross-repo-paths.yaml (or single --project-root
# override). Each line is "<path>\t<vendors_scripts>" (see _resolve_project_roots);
# --project-root bypass emits a bare path with no tab -> defaults to "true".
roots_output=""
roots_rc=0
roots_output="$(_resolve_project_roots)" || roots_rc=$?
if [[ ${roots_rc} -ne 0 || ( -f "${CROSS_REPO_CONFIG}" && -z "${roots_output}" && -z "${PROJECT_ROOT_OVERRIDE}" && -z "${LEADV2_PROJECT_ROOT:-}" ) ]]; then
  log_warn "(c)/(d): resolved 0 project roots from ${CROSS_REPO_CONFIG} — nothing synced"
fi
while IFS=$'\t' read -r proj_root proj_vendors_scripts; do
  [[ -z "${proj_root}" ]] && continue
  _sync_project_root "${proj_root}" "${proj_vendors_scripts:-true}"
  changed_summary+=("project[${proj_root##*/}]")
done <<< "${roots_output}"

# ── Subsume: sync workflow JS files ──────────────────────────────────────────
WORKFLOWS_SYNC="${SCRIPT_DIR}/leadv2-workflows-sync.sh"
if [[ -f "${WORKFLOWS_SYNC}" ]]; then
  log "Calling leadv2-workflows-sync.sh..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    bash "${WORKFLOWS_SYNC}" --dry-run
  else
    bash "${WORKFLOWS_SYNC}"
  fi
  changed_summary+=("workflows")
fi

# ── Summary ───────────────────────────────────────────────────────────────────
if [[ ${#changed_summary[@]} -gt 0 ]]; then
  log "Sync complete. Targets touched: ${changed_summary[*]}"
else
  log "Nothing synced (empty target list or all dry-run)."
fi
for tally in "${project_link_tallies[@]}"; do
  log "${tally}"
done
if (( project_drift_files > 0 )); then
  log_warn "ACTION REQUIRED: ${project_drift_files} diverging file(s) across ${project_drift_repos} repo(s) — promote or discard; nothing was overwritten"
  exit 4
fi
