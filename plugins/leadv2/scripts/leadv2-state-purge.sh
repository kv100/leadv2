#!/usr/bin/env bash
# leadv2-state-purge.sh — STATE-DIR-JUNK-01 classifier + guarded remover for
# ~/.claude/leadv2-state/.
#
# ~100 `leadv2-lwt.<rand>` (and a handful of `revrepo.*`/`tmp.*`/`r1`-`r6`/
# named-fixture) directories accumulate at the top level of the control-plane
# state base -- one per test run that never exported LEADV2_STATE_ROOT or
# LEADV2_STATE_BASE (leadv2-state-path.sh:81-... resolved a real STATE_ROOT
# from whatever scratch repo the test happened to `git init` in). The leak
# itself is fixed at the source in leadv2-state-path.sh (STATE-DIR-JUNK-01
# EPHEMERAL-REDIRECT block): new scratch-repo callers now land under
# <base>/.ephemeral/<slug> instead of the top level, and that subtree is
# itself swept by this tool under the same age rule (Class 4 below). This
# script's job is the ONE-TIME (and repeatable) cleanup of everything that
# already exists.
#
# Pure classifier + guarded remover. Default is --dry-run; deleting requires
# an explicit --apply. Never deletes anything outside LEADV2_STATE_BASE,
# never at more than one path-component depth, never a symlink, never the
# three protected slugs under any flag combination.
#
# Usage:
#   leadv2-state-purge.sh [--dry-run|--apply] [--min-age-days N] [--base DIR]
#
# Exit codes:
#   0 -- clean classification (no UNKNOWN roots)
#   1 -- bad usage / lock held / base dir missing
#   4 -- classification completed but at least one root is UNKNOWN
#
# Env:
#   LEADV2_STATE_BASE   default: $HOME/.claude/leadv2-state (same var
#                       leadv2-state-path.sh reads -- keep them in sync)

set -euo pipefail

# ── Args ─────────────────────────────────────────────────────────────────
MODE="dry-run"
MIN_AGE_DAYS=1
BASE="${LEADV2_STATE_BASE:-${HOME}/.claude/leadv2-state}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --apply) MODE="apply"; shift ;;
    --min-age-days)
      MIN_AGE_DAYS="${2:?--min-age-days requires a value}"
      shift 2
      ;;
    --base)
      BASE="${2:?--base requires a value}"
      shift 2
      ;;
    -h|--help)
      sed -n '1,30p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf -- '[leadv2-state-purge] ABORT: unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ ! "$MIN_AGE_DAYS" =~ ^[0-9]+$ ]]; then
  printf -- '[leadv2-state-purge] ABORT: --min-age-days must be a non-negative integer, got %q\n' "$MIN_AGE_DAYS" >&2
  exit 1
fi

if [[ ! -d "$BASE" ]]; then
  printf -- '[leadv2-state-purge] ABORT: base dir does not exist: %s\n' "$BASE" >&2
  exit 1
fi
BASE="$(cd "$BASE" && pwd -P)"

# Invariant 3: no flag combination -- present or future -- reaches these.
# Asserted here, AFTER flag parsing, independent of the classification loop.
readonly -a PROTECTED_SLUGS=(persona-engine leadv2 respiro-ios)

# Class-4 fixture-name patterns (anchored, extended-regex).
readonly -a FIXTURE_PATTERNS=(
  '^leadv2-lwt\.[A-Za-z0-9]{6}$'
  '^revrepo\.[A-Za-z0-9]{6}$'
  '^tmp\.[A-Za-z0-9]{8,12}$'
  '^r[1-9]$'
  '^repo[0-9]*$'
  '^target-repo$'
  '^root$'
  '^proj$'
  '^glm-proof-[a-z0-9]+$'
  '^codex-nopoll-counter$'
  '^pe-fanout-verify-[A-Za-z0-9]{6}$'
  '^leadv2-r1-prefix-fixture\.[A-Za-z0-9]{6}$'
)

is_protected() { # <slug>
  local slug="$1" p
  for p in "${PROTECTED_SLUGS[@]}"; do
    [[ "$slug" == "$p" ]] && return 0
  done
  return 1
}

matches_fixture_pattern() { # <slug>
  local slug="$1" pat
  for pat in "${FIXTURE_PATTERNS[@]}"; do
    if [[ "$slug" =~ $pat ]]; then
      return 0
    fi
  done
  return 1
}

is_live_repo() { # <slug>
  local slug="$1" dir="$2" marker root
  marker="${dir}/.repo-root"
  if [[ -f "$marker" && -r "$marker" ]]; then
    root="$(cat "$marker" 2>/dev/null || true)"
    if [[ -n "$root" && -d "$root" ]]; then
      return 0
    fi
  fi
  if [[ -d "${HOME}/Projects/${slug}/.git" ]]; then
    return 0
  fi
  return 1
}

now_epoch() { date -u +%s; }

mtime_epoch() { # <path> -> epoch seconds, or empty on failure
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || true
}

age_days() { # <path> -> integer days since newer of (dir mtime, dir/active.yaml mtime)
  local path="$1" active="$1/active.yaml" m1 m2 newest now
  m1="$(mtime_epoch "$path")"
  [[ -z "$m1" ]] && { printf '%s' "999999"; return; }
  newest="$m1"
  if [[ -f "$active" ]]; then
    m2="$(mtime_epoch "$active")"
    if [[ -n "$m2" && "$m2" -gt "$newest" ]]; then
      newest="$m2"
    fi
  fi
  now="$(now_epoch)"
  printf '%s' "$(( (now - newest) / 86400 ))"
}

# ── Lock (invariant 5) ──────────────────────────────────────────────────
LOCK_DIR="${BASE}/.purge.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  printf -- '[leadv2-state-purge] ABORT: lock held (%s exists) -- another purge or sweep may be in flight.\n' "$LOCK_DIR" >&2
  exit 1
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

# ── Classify one root ────────────────────────────────────────────────────
# Emits: CLASS<TAB>slug<TAB>age_days<TAB>reason<TAB>abs_path
classify_root() { # <abs_path> <slug>
  local path="$1" slug="$2" age reason

  # Invariant 1: realpath must sit exactly one path-component under BASE,
  # and never be a symlink -- refuse outright, never follow.
  if [[ -L "$path" ]]; then
    printf 'REFUSED\t%s\t-\tsymlink entry, refusing to follow\t%s\n' "$slug" "$path"
    return
  fi
  local resolved
  resolved="$(cd "$path" 2>/dev/null && pwd -P)" || {
    printf 'REFUSED\t%s\t-\tcannot resolve realpath\t%s\n' "$slug" "$path"
    return
  }
  # Valid parent is BASE itself (top-level roots) or BASE/.ephemeral (the
  # redirect subtree) -- exactly one level under either, at a
  # path-component boundary.
  local resolved_parent
  resolved_parent="$(dirname "$resolved")"
  if [[ "$resolved_parent" != "$BASE" && "$resolved_parent" != "${BASE}/.ephemeral" ]]; then
    printf 'REFUSED\t%s\t-\tresolved path escapes base or is not one level deep (%s)\t%s\n' "$slug" "$resolved" "$path"
    return
  fi

  age="$(age_days "$path")"

  if is_protected "$slug"; then
    printf 'PROTECTED\t%s\t%s\tin PROTECTED_SLUGS const\t%s\n' "$slug" "$age" "$path"
    return
  fi

  if is_live_repo "$slug" "$path"; then
    printf 'LIVE\t%s\t%s\t.repo-root or HOME/Projects/%s/.git resolves\t%s\n' "$slug" "$age" "$slug" "$path"
    return
  fi

  if [[ "$age" -lt "$MIN_AGE_DAYS" ]]; then
    reason="mtime younger than --min-age-days=${MIN_AGE_DAYS} -- held, re-check next run"
    printf 'HELD\t%s\t%s\t%s\t%s\n' "$slug" "$age" "$reason" "$path"
    return
  fi

  if [[ -f "${path}/.ephemeral" || "$slug" == ".ephemeral" ]]; then
    printf 'EPHEMERAL\t%s\t%s\t.ephemeral marker present\t%s\n' "$slug" "$age" "$path"
    return
  fi

  if matches_fixture_pattern "$slug"; then
    printf 'EPHEMERAL\t%s\t%s\tmatches known test-fixture name pattern\t%s\n' "$slug" "$age" "$path"
    return
  fi

  printf 'UNKNOWN\t%s\t%s\tno LIVE marker, no .ephemeral marker, no fixture-name match -- retained, needs a human look\t%s\n' "$slug" "$age" "$path"
}

# ── Enumerate: top-level roots + one level into .ephemeral/ ─────────────
TMP_ROWS="$(mktemp)"
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true; rm -f "$TMP_ROWS"' EXIT

shopt -s nullglob
for entry in "$BASE"/*/; do
  slug="$(basename "$entry")"
  [[ "$slug" == ".ephemeral" ]] && continue
  [[ "$slug" == ".purge.lock" ]] && continue
  classify_root "${entry%/}" "$slug" >> "$TMP_ROWS"
done

if [[ -d "${BASE}/.ephemeral" ]]; then
  for entry in "${BASE}/.ephemeral"/*/; do
    slug=".ephemeral/$(basename "$entry")"
    row="$(classify_root "${entry%/}" "$(basename "$entry")")"
    # An ephemeral-subtree entry is EPHEMERAL by construction (it only ever
    # exists because leadv2-state-path.sh's redirect put it there) unless the
    # age/live/protected checks above already said otherwise -- relabel the
    # slug column to show the .ephemeral/ prefix without re-deriving class.
    printf '%s\n' "$row" | awk -F'\t' -v s="$slug" 'BEGIN{OFS="\t"} {$2=s; print}' >> "$TMP_ROWS"
  done
fi
shopt -u nullglob

# ── Report ────────────────────────────────────────────────────────────────
declare -A COUNTS=(
  [PROTECTED]=0 [LIVE]=0 [HELD]=0 [EPHEMERAL]=0 [UNKNOWN]=0 [REFUSED]=0
)
while IFS=$'\t' read -r class slug age reason path; do
  [[ -z "$class" ]] && continue
  COUNTS["$class"]=$(( ${COUNTS["$class"]:-0} + 1 ))
done < "$TMP_ROWS"

printf -- '[leadv2-state-purge] base=%s mode=%s min_age_days=%s\n' "$BASE" "$MODE" "$MIN_AGE_DAYS"
printf -- '[leadv2-state-purge] counts: PROTECTED=%s LIVE=%s HELD=%s EPHEMERAL=%s UNKNOWN=%s REFUSED=%s\n' \
  "${COUNTS[PROTECTED]:-0}" "${COUNTS[LIVE]:-0}" "${COUNTS[HELD]:-0}" "${COUNTS[EPHEMERAL]:-0}" "${COUNTS[UNKNOWN]:-0}" "${COUNTS[REFUSED]:-0}"

while IFS=$'\t' read -r class slug age reason path; do
  [[ -z "$class" ]] && continue
  [[ "$class" == "LIVE" || "$class" == "PROTECTED" ]] && continue
  printf -- '%s\t%s\tage=%sd\t%s\n' "$class" "$slug" "$age" "$reason"
done < "$TMP_ROWS"

REMOVED=0
if [[ "$MODE" == "apply" ]]; then
  while IFS=$'\t' read -r class slug age reason path; do
    [[ "$class" == "EPHEMERAL" ]] || continue
    # Invariant 6: per-root, resolved absolute path, never a glob, never an
    # empty variable.
    target="${path:?}"
    rm -rf -- "$target"
    REMOVED=$((REMOVED + 1))
  done < "$TMP_ROWS"
  printf -- '[leadv2-state-purge] removed %s EPHEMERAL root(s)\n' "$REMOVED"
else
  printf -- '[leadv2-state-purge] dry-run: %s EPHEMERAL root(s) would be removed. Re-run with --apply to delete.\n' "${COUNTS[EPHEMERAL]:-0}"
fi

if [[ "${COUNTS[UNKNOWN]:-0}" -gt 0 ]]; then
  exit 4
fi
exit 0
