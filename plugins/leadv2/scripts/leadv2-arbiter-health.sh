#!/usr/bin/env bash
# leadv2-arbiter-health.sh — one screen answering "is the decision layer actually working?"
#
# Every line reads a LIVE artifact, never a test. Each check names the surface it
# read, because a count is a claim about a surface (2026-09-14: "zero gate
# disagreements" was true of the journal and false of the launcher's stderr).
#
# Usage: bash leadv2-arbiter-health.sh [--window-hours N]   (default 24)
set -uo pipefail

WINDOW_H="${2:-24}"
# Both repos hold handoff artifacts; LEADV2_PROJECT_ROOT points at whichever
# repo the caller is in, so reading only it under-counts. Read both, always.
ROOT="$HOME/Projects/leadv2"
ROOT2="$HOME/Projects/persona-engine"
STATE="$HOME/.claude/leadv2-state"
TMP="${TMPDIR:-/tmp}"

hdr() { printf '\n== %s\n' "$1"; }
row() { printf '  %-34s %s\n' "$1" "$2"; }

# --- 1. reset urgency: does the arbiter prefer a window about to reset? -------
hdr "reset urgency (surface: decision lines in $STATE/*/tasks/*/journal.md)"
_ru=$(grep -rhoE "reset_urgency=[^ ]+" "$STATE"/*/tasks/*/journal.md 2>/dev/null | tail -5)
if [ -n "$_ru" ]; then
  row "present in last decisions" "yes"
  printf '%s\n' "$_ru" | sed 's/^/    /'
else
  row "present in last decisions" "NO — term is not reaching the live path"
fi

# --- 2. price provenance ------------------------------------------------------
hdr "price provenance (same surface)"
_cs=$(grep -rhoE "cost_src=[^ ]+" "$STATE"/*/tasks/*/journal.md 2>/dev/null | sort | uniq -c | sort -rn | head -4)
[ -n "$_cs" ] && printf '%s\n' "$_cs" | sed 's/^/    /' || row "cost_src" "NO — decisions carry no price provenance"

# --- 3. decision record: can it be replayed? ---------------------------------
hdr "decision record schema (surface: the recorded decision artifact)"
DEC="${LEADV2_ROUTE_ARBITER_DECISIONS_FILE:-$TMP/leadv2-route-arbiter-decisions.jsonl}"
row "decisions file" "$DEC"
if [ -f "$DEC" ]; then
  _all=$(wc -l < "$DEC" | tr -d ' ')
  _v2=$(grep -c '"record_schema_version": *2' "$DEC" 2>/dev/null)
  row "rows total / schema v2" "$_all / ${_v2:-0}"
  [ "${_v2:-0}" -eq 0 ] && row "replayable" "NO — every row is output-only history"
  [ "${_v2:-0}" -gt 0 ] && row "replayable" "yes — $_v2 row(s) carry their inputs"
else
  row "decisions file" "absent — no decision has been recorded at all"
fi

# --- 4. the judge: model verdict or silent fallback? -------------------------
# Surface note: the judge's verdict reaches the decision as `complexity_source`.
# `judge` = a model answered. `fallback`/`unknown` = the code-only estimator did,
# which is what 13 silent GLM parse failures looked like on 2026-09-13.
hdr "judge (surface: complexity_source on decision lines)"
_cs2=$(grep -rhoE "complexity_source=[a-z_]+" "$STATE"/*/tasks/*/journal.md 2>/dev/null | awk -F= '{print $2}' | sort | uniq -c | sort -rn | head -4)
[ -n "$_cs2" ] && printf '%s\n' "$_cs2" | sed 's/^/    /' || row "complexity_source" "absent"
_ja=$(grep -rhoE "judge_arm[\": ]+[a-z]+" "$ROOT"/docs/handoff/*/*.yaml 2>/dev/null | grep -oE "[a-z]+$" | sort | uniq -c)
[ -n "$_ja" ] && printf '%s\n' "$_ja" | sed 's/^/    judge_arm /' || row "judge_arm recorded" "no — no envelope names its arm yet"

# --- 4b. token estimate (D2) --------------------------------------------------
hdr "token estimate (surface: docs/handoff/*/cost-estimate.yaml)"
_est=$(ls "$ROOT"/docs/handoff/*/cost-estimate.yaml "$ROOT2"/docs/handoff/*/cost-estimate.yaml 2>/dev/null | wc -l | tr -d ' ')
_join=$(grep -l "dispatch_sig8" "$ROOT"/docs/handoff/*/cost-estimate.yaml "$ROOT2"/docs/handoff/*/cost-estimate.yaml "$ROOT2"/docs/handoff/*/cost-estimate.yaml 2>/dev/null | wc -l | tr -d ' ')
_nz=$(grep -A2 "expected_tokens" "$ROOT"/docs/handoff/*/cost-estimate.yaml "$ROOT2"/docs/handoff/*/cost-estimate.yaml 2>/dev/null | grep -cE "input: *[1-9]")
row "estimate files" "${_est:-0}"
row "carry the join key" "${_join:-0}  (join key landed 2026-09-14)"
row "with a NON-ZERO token estimate" "${_nz:-0}  (0 = D2 still not derived)"

# --- 5. launcher refusals: the surface that was invisible --------------------
hdr "launcher refusals (surface: $TMP/leadv2-dispatch-spawn-*.stderr.log)"
_tot=$(ls "$TMP"/leadv2-dispatch-spawn-*.stderr.log 2>/dev/null | wc -l | tr -d ' ')
_ref=$(grep -l "refused:" "$TMP"/leadv2-dispatch-spawn-*.stderr.log 2>/dev/null | wc -l | tr -d ' ')
row "spawn attempts on disk" "${_tot:-0}"
row "refused by the launcher" "${_ref:-0}"
[ "${_tot:-0}" -gt 0 ] && grep -h "refused:" "$TMP"/leadv2-dispatch-spawn-*.stderr.log 2>/dev/null | sort | uniq -c | sed 's/^/    /'
_evt=$(grep -rhc "launcher_refused" "$STATE"/*/tasks/*/journal.md 2>/dev/null | paste -sd+ - | bc 2>/dev/null)
row "same fact as a journal event" "${_evt:-0}  (0 = still invisible to every census)"

# --- 6. arm spread: is one provider starving? --------------------------------
hdr "arm spread (surface: decision lines)"
grep -rhoE "arbiter_pick=[a-z-]+" "$STATE"/*/tasks/*/journal.md 2>/dev/null \
  | sort | uniq -c | sort -rn | head -6 | sed 's/^/    /'

printf '\n'
