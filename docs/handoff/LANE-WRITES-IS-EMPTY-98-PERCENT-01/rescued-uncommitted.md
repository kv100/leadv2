# LANE-WRITES-IS-EMPTY-98-PERCENT-01 — uncommitted work rescued from the checkout

Carried out of `.claude/worktrees/LANE-WRITES-IS-EMPTY-98-PERCENT-01` on 2026-09-06 by the blocking filter of
LEADV2-WORKTREE-ADJUDICATION-01, **before** any verdict was written about the
branch. A lane's branch can be an empty anchor while the work sits untracked or
merely staged inside its checkout: `git log` never sees the index, and removing
the checkout would take both with it.

Text only — nothing here is installed or made executable. Restoring any of it is
a deliberate act by whoever owns the row.

## `git diff HEAD -- plugins tests` (staged and unstaged)

```diff
diff --git a/plugins/leadv2/scripts/leadv2-dispatch-ledger.sh b/plugins/leadv2/scripts/leadv2-dispatch-ledger.sh
index a642dd40..9fd4e2d9 100755
--- a/plugins/leadv2/scripts/leadv2-dispatch-ledger.sh
+++ b/plugins/leadv2/scripts/leadv2-dispatch-ledger.sh
@@ -941,6 +941,27 @@ _dl_derive_lane_state() {
       local st
       st="$(git -C "${repo}" status --porcelain -uall -- "${pathspec[@]}" 2>/dev/null || true)"
       [[ -n "${st}" ]] && dirty=1
+    else
+      # LANE-WRITES-IS-EMPTY-98-PERCENT-01 (guard #4 of 5 that silently
+      # self-disable on an empty write-set): an empty pathspec used to mean
+      # this probe never ran at all, so `dirty` stayed 0 and a lane with real
+      # uncommitted work fell straight through to liveness/dead with no
+      # rescue. This is NOT the same fallback the commit-log branch above
+      # explicitly forbids ("deliberately NO unscoped `git log --since`
+      # fallback" — that caused the 2026-08-04 137-lane misattribution
+      # because a shared/canonical repo's log has no per-lane boundary).
+      # `git status`, by contrast, only ever reports THIS worktree's own
+      # state (`repo`, which per the standing per-task-worktree-isolation
+      # decision is already this lane's own isolated tree) — unscoped here
+      # cannot attribute another lane's work to this one. Fail-safe direction
+      # matches R1: false "dirty" costs one extra liveness check, false
+      # "clean" costs a real lane declared dead.
+      local st
+      st="$(git -C "${repo}" status --porcelain -uall -- . ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null || true)"
+      if [[ -n "${st}" ]]; then
+        dirty=1
+        printf 'dl_derive_lane_state: dirty=1 reason=unscoped_fallback writes_csv_empty=1 repo=%s\n' "${repo}" >&2
+      fi
     fi
   fi
 
diff --git a/plugins/leadv2/scripts/leadv2-dispatch-product-close.sh b/plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
index 4716fb95..b6a6a6e0 100755
--- a/plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
+++ b/plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
@@ -1800,7 +1800,36 @@ _pc_norm_write() {  # <raw> -> normalised path on stdout
 pc_precheck_writes() {
   _PC_UNDIFFABLE_CSV=""
   _PC_SCOPE_WRITES_CSV=""
-  [[ -n "${WRITES_CSV:-}" ]] || return 0
+  if [[ -z "${WRITES_CSV:-}" ]]; then
+    # LANE-WRITES-IS-EMPTY-98-PERCENT-01 (guard #2 of 5): a bare `return 0`
+    # here used to leave _PC_SCOPE_WRITES_CSV empty with ZERO trace in the
+    # journal — indistinguishable from "the lane declared it writes nothing".
+    # Try to derive a real write-set first (scope-inferred: what actually
+    # changed in the lane's own worktree); only skip loudly if that also
+    # comes back unknown.
+    local _pcw_lib="${SCRIPT_DIR}/lib/leadv2-writeset-derive.sh"
+    [[ -f "${_pcw_lib}" ]] || _pcw_lib="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-writeset-derive.sh"
+    local _pcw_lane_root="${LEADV2_LANE_WORK_ROOT:-}"
+    if [[ -z "${_pcw_lane_root}" ]]; then
+      _pcw_lane_root="$(LEADV2_PROJECT_ROOT="${ROOT}" bash "${SCRIPT_DIR}/leadv2-lane-worktree.sh" path-of "${FOUNDER_TASK_ID:-${TASK}}" 2>/dev/null || true)"
+    fi
+    if [[ -f "${_pcw_lib}" ]]; then
+      # shellcheck source=lib/leadv2-writeset-derive.sh
+      source "${_pcw_lib}"
+      local _pcw_out _pcw_writes _pcw_source
+      _pcw_out="$(lv2_derive_lane_writes "" "" "${_pcw_lane_root}")"
+      _pcw_writes="$(printf '%s\n' "${_pcw_out}" | sed -n 's/^writes=//p')"
+      _pcw_source="$(printf '%s\n' "${_pcw_out}" | sed -n 's/^writes_source=//p')"
+      if [[ -n "${_pcw_writes}" ]]; then
+        WRITES_CSV="${_pcw_writes}"
+        emit decision "writeset_derived task=${TASK} by=pc_precheck_writes writes_source=${_pcw_source}"
+      fi
+    fi
+    if [[ -z "${WRITES_CSV:-}" ]]; then
+      emit decision "writeset_unknown task=${TASK} by=pc_precheck_writes action=skipped reason=no_declared_or_derivable_writes"
+      return 0
+    fi
+  fi
   local raw_writes_pf w bad_paths=() good_paths=() bad_n=0 good_n=0
   IFS=',' read -r -a raw_writes_pf <<< "${WRITES_CSV}"
   for w in "${raw_writes_pf[@]}"; do
@@ -1908,7 +1937,19 @@ _pc_stop_gate_resolve_reason() {
 
 pc_stop_gate_autocommit() {
   [[ "${LEADV2_STOP_GATE:-1}" != 0 ]] || return 0
-  [[ -n "${_PC_SCOPE_WRITES_CSV:-}" ]] || return 0
+  if [[ -z "${_PC_SCOPE_WRITES_CSV:-}" ]]; then
+    # LANE-WRITES-IS-EMPTY-98-PERCENT-01 (guard #3 of 5, cascades from #2): a
+    # bare `return 0` here means autocommit never runs at all and NOTHING is
+    # journaled — the exact silent-disable class this task fixes. Do NOT
+    # widen to an unbounded `git add -A`: pc_scope_diff's unscoped_lane_work
+    # classifier deliberately treats out-of-write-set changes as a scope
+    # violation to catch, and auto-committing them here would launder that
+    # violation instead (see the block comment above this function). So the
+    # safe fix is option (b), not (a): always journal WHY autocommit is
+    # being skipped, so a skip is never confused with "ran, nothing to do".
+    emit decision "writeset_unknown task=${TASK} by=pc_stop_gate_autocommit action=skipped reason=no_scoped_writes_to_commit"
+    return 0
+  fi
 
   # Cross-repository writes are diffed by pc_scope_diff but are not safe to
   # commit from this lane's repository. Do not silently claim protection.
diff --git a/plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh b/plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh
index ee4e2f60..18c0aee5 100644
--- a/plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh
+++ b/plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh
@@ -131,7 +131,15 @@ leadv2_writeset_missing() {
   mission_text="$(cat)"
   local required
   required="$(printf '%s\n' "${mission_text}" | leadv2_writeset_extract_required)"
-  [[ -n "${required}" ]] || return 0
+  if [[ -z "${required}" ]]; then
+    # LANE-WRITES-IS-EMPTY-98-PERCENT-01 (guard #5 of 5): this `return 0` is
+    # legitimate when the mission genuinely names no required output path —
+    # but it used to be indistinguishable from "the extractor was fed a
+    # write-set it couldn't parse". Log which one happened so a lane that
+    # falls through here leaves a trace instead of silent theater.
+    printf 'leadv2_writeset_missing: skip reason=no_required_paths_detected\n' >&2
+    return 0
+  fi
 
   if [[ -z "${writes_csv}" ]]; then
     writes_csv="$(printf '%s\n' "${mission_text}" \
```

## `plugins/leadv2/scripts/lib/leadv2-writeset-derive.sh` (untracked, 8175 bytes)

```
#!/usr/bin/env bash
# leadv2-writeset-derive.sh — LANE-WRITES-IS-EMPTY-98-PERCENT-01.
#
# Sourced (never executed) by leadv2-dispatch-code.sh and by anything that
# needs the lane write-set populated. Fixes the root cause documented in
# docs/handoff/LANE-WRITES-IS-EMPTY-98-PERCENT-01/brief.md: LEADV2_DISPATCH_
# LANE_WRITES is empty in 98.3% of dispatches (237/241 sampled) because it
# relies on mission authors hand-writing `Reads:`/`Writes:`/`Touches:`
# syntax — 0/324 missions do. Five downstream guards silently self-disable
# on that empty field (path-based task protection, pc_precheck_writes,
# pc_stop_gate_autocommit, _dl_derive_lane_state's dirty probe,
# leadv2_writeset_missing).
#
# This file does NOT change any of those guards' semantics — it changes what
# feeds them, so a guard that "worked" only because writes happened to be
# non-empty keeps working, and a guard that silently skipped now sees a
# real (or explicitly `unknown`) value instead of "".
#
# Bash 3.2 safe: no associative arrays, no ${x^^}, no mapfile/readarray.

# ── priority order — the ONE place to change it ─────────────────────────────
# lv2_derive_lane_writes tries sources in this order and stops at the first
# one that yields a non-empty result. Reordering the source priority means
# editing this list and nothing else.
LV2_WRITESET_SOURCE_ORDER="mission brief-inferred scope-inferred"

# lv2_derive_lane_writes <mission_file> <explicit_csv> <lane_root_or_empty>
#   -> stdout: two lines
#        writes=<csv-or-empty>
#        writes_source=<mission|brief-inferred|scope-inferred|unknown>
#
# <explicit_csv> is whatever the caller already parsed from a `LANE_WRITES:`/
# `Writes:`/`Touches:` line (the pre-existing, rarely-used convention) — this
# function does not re-parse mission text for that syntax, it just honors it
# as the highest-priority source when the caller already has it.
#
# NEVER returns a non-empty writes with writes_source=unknown, and NEVER
# returns writes_source=mission/brief-inferred/scope-inferred with an empty
# writes — the two fields are meant to be read together by every guard so
# "unknown" and "declared but empty" are never confused.
lv2_derive_lane_writes() {
  local mission_file="$1" explicit_csv="${2:-}" lane_root="${3:-}"
  local src

  for src in ${LV2_WRITESET_SOURCE_ORDER}; do
    case "${src}" in
      mission)
        if [[ -n "${explicit_csv}" ]]; then
          printf 'writes=%s\nwrites_source=mission\n' "${explicit_csv}"
          return 0
        fi
        ;;
      brief-inferred)
        if [[ -n "${mission_file}" && -s "${mission_file}" ]]; then
          local inferred
          inferred="$(_lv2_wsd_infer_from_text "${mission_file}")"
          if [[ -n "${inferred}" ]]; then
            printf 'writes=%s\nwrites_source=brief-inferred\n' "${inferred}"
            return 0
          fi
        fi
        ;;
      scope-inferred)
        if [[ -n "${lane_root}" && -d "${lane_root}" ]]; then
          local scoped
          scoped="$(_lv2_wsd_infer_from_scope "${lane_root}")"
          if [[ -n "${scoped}" ]]; then
            printf 'writes=%s\nwrites_source=scope-inferred\n' "${scoped}"
            return 0
          fi
        fi
        ;;
    esac
  done

  printf 'writes=\nwrites_source=unknown\n'
  return 0
}

# _lv2_wsd_infer_from_text <mission_or_brief_file> -> stdout: comma-joined
# repo-relative paths found in the text that (a) look like real repo paths
# (>=1 path separator, a file extension OR a known dir prefix) and (b) exist
# on disk under PROJECT_ROOT/ROOT at the time of inference. Existence-gating
# is deliberate: a mission/brief names plenty of paths that are prose
# examples, not writes ("see docs/x.md") — requiring the path to already
# exist keeps the false-positive rate the same class of low as the existing
# leadv2-mission-writeset.sh extractor, without requiring the "## Done
# means" heading structure that extractor depends on (missions and briefs in
# this task's own sample don't reliably have one).
_lv2_wsd_infer_from_text() {
  local f="$1" root="${PROJECT_ROOT:-${ROOT:-.}}"
  python3 - "${f}" "${root}" <<'PY'
import re, sys, os

path, root = sys.argv[1], sys.argv[2]
try:
    text = open(path, "r", errors="replace").read()
except OSError:
    sys.exit(0)

# backticked or bare tokens that look like repo-relative paths, optionally
# with a trailing :LINE or :LINE-LINE the way this repo's own briefs cite
# locations (e.g. "leadv2-dispatch-product-close.sh:1803").
token_re = re.compile(r'`?([A-Za-z0-9_./\-]+/[A-Za-z0-9_./\-]+\.[A-Za-z0-9]+)(?::\d+(?:-\d+)?)?`?')

seen = []
for m in token_re.finditer(text):
    p = m.group(1).rstrip('.,;:)')
    if p.startswith('/') or '..' in p.split('/'):
        continue
    full = os.path.join(root, p)
    if os.path.isfile(full) and p not in seen:
        seen.append(p)

print(','.join(seen))
PY
}

# _lv2_wsd_infer_from_scope <lane_root> -> stdout: comma-joined paths that
# are actually dirty/committed-since-HEAD in the lane's OWN worktree.
# Deliberately scoped to lane_root (never a shared/canonical repo) and
# deliberately NOT a `git log --since=<epoch>` over the whole repo — that
# exact shape caused the 2026-08-04 cross-lane misattribution incident
# documented at leadv2-dispatch-ledger.sh's _dl_derive_lane_state (137
# unrelated persona-engine lanes stamped `landed` off one shared commit).
# `git status --porcelain` only ever reflects THIS worktree's own state, so
# it carries none of that cross-lane risk even when unscoped to a pathspec.
_lv2_wsd_infer_from_scope() {
  local lane_root="$1" out
  git -C "${lane_root}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  out="$(git -C "${lane_root}" status --porcelain=v1 -uall -- . ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null \
    | sed -E 's/^...//' | tr '\n' ',' | sed -E 's/,$//')"
  printf '%s' "${out}"
}

# lv2_classify_writes_flag_source <writes_csv> <writes_source>
#   -> stdout: two lines
#        write_class=<tests_docs|protected|standard|unknown>
#        flag_source=<path|prose|none>
#
# Same path-classification rule leadv2-dispatch-code.sh's `_lane_writes_class`
# already applies (tests/docs-only, *safety*/*publish*/*payment* substring ->
# protected, else standard/unknown) — duplicated here on purpose, not
# refactored out of the off-limits file, so this task's fix does not require
# an edit to leadv2-dispatch-code.sh (see docs/handoff/dispatch-23221626/
# developer.full.md for the exact call-site edit the lead still needs to
# make to WIRE this in). `flag_source=path` is set iff the classification
# was reached by inspecting an actual write-set entry (write_class in
# {tests_docs, protected, standard}) — never for `unknown`, where there is
# no path evidence at all and calling it `flag_source=path` would be a lie
# a reviewer could not catch.
lv2_classify_writes_flag_source() {
  local writes="$1" writes_source="${2:-unknown}" entry trimmed count=0 class="unknown"
  if [[ -n "${writes//[[:space:]]/}" ]]; then
    while IFS= read -r entry; do
      trimmed="$(printf '%s' "${entry}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -n "${trimmed}" ]] || continue
      count=$((count + 1))
      case "${trimmed}" in
        tests/*|plugins/leadv2/scripts/tests/*|docs/handoff/*) ;;
        *safety*|*publish*|*payment*) class="protected" ;;
      esac
      [[ "${class}" == "protected" ]] && break
    done < <(printf '%s\n' "${writes}" | tr ',;' '\n')
    if [[ "${class}" != "protected" && ${count} -gt 0 ]]; then
      local non_safe=0
      while IFS= read -r entry; do
        trimmed="$(printf '%s' "${entry}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        case "${trimmed}" in tests/*|plugins/leadv2/scripts/tests/*|docs/handoff/*) ;; *) non_safe=1 ;; esac
      done < <(printf '%s\n' "${writes}" | tr ',;' '\n')
      class="standard"
      [[ ${non_safe} -eq 0 ]] && class="tests_docs"
    fi
  fi
  local flag_source="none"
  [[ "${class}" != "unknown" ]] && flag_source="path"
  printf 'write_class=%s\nflag_source=%s\n' "${class}" "${flag_source}"
}
```

