#!/usr/bin/env bash
# test-reflect-is-retired.sh — REFLECT-SELF-LEARNING-DECISION acceptance suite
# (VERDICT delete, founder-confirmed 2026-09-12; decision doc:
# docs/handoff/REFLECT-SELF-LEARNING-DECISION/decision.md, executed by lane
# d4ef053f1742; backup: docs/handoff/d4ef053f1742/retired-reflect-self-learning-20260912.tar.gz).
#
# Pins BOTH halves of the retirement:
#   A. the mechanism is GONE — none of the ten retired files exists anymore;
#   B. no LIVE surface still names it — a scan of tracked files for the
#      mechanism names comes back empty once tombstone lines (lines carrying
#      the decision id) are filtered out;
#   C. the KEPT contract still stands — over-deletion is also a failure:
#      lead-reflect writer, force-reflect recovery hook, phase8-assert A4
#      reflect-history gate, and the close-ritual guard all remain.
#
# Why B matters as much as A: the failure mode of this retirement is the
# leftover NAME (a hook registration, a Workflow(...) call, a trigger-file
# writer, an env knob) — a name left behind points at nothing and reads as a
# live surface to the next reader. A suite that only checked file absence
# would pin nothing.
#
# Scope: this repository (the plugin is the mechanism). Repo-local settings
# registrations (persona-engine, getmany) are swept separately — see
# test-portable-guards-are-plugin-owned.sh for the cross-repo guard checks.
#
# Run: bash plugins/leadv2/scripts/tests/test-reflect-is-retired.sh
# run-all-triggers: hooks.json leadv2-phase8-close.sh leadv2-learn.js leadv2-causal-critique.js learn-trigger-inject.sh leadv2-learn-consume.sh lead-reflect leadv2-close leadv2-force-reflect.sh

set -uo pipefail

SCRIPT_TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_TESTS}/../.." && pwd)"
REPO_ROOT="$(git -C "${PLUGIN_ROOT}" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${PLUGIN_ROOT%/plugins/leadv2}")"

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1" >&2; }

# ── A. mechanism gone: none of the retired files exists ───────────────────────
RETIREMENT_SET=(
  "workflows/leadv2-learn.js"
  "workflows/leadv2-causal-critique.js"
  "hooks/learn-trigger-inject.sh"
  "hooks/leadv2-learn-consume.sh"
  "skills/lead-reflect/CAUSAL-CRITIQUE.md"
  "scripts/tests/test-leadv2-causal-critique.sh"
  "scripts/tests/fixtures/causal-critique-harness.mjs"
  "scripts/tests/test-leadv2-phase8-learn-counter.sh"
  "scripts/tests/test-leadv2-learn-freeform-flag.sh"
  "scripts/tests/fixtures/learn-freeform-flag-harness.mjs"
)
for f in "${RETIREMENT_SET[@]}"; do
  if [[ -e "${PLUGIN_ROOT}/${f}" ]]; then
    fail "A: retired file still exists: plugins/leadv2/${f}"
  else
    pass "A: absent: plugins/leadv2/${f}"
  fi
done

# ── B. no live surface names the mechanism ────────────────────────────────────
# Case-insensitive name scan over TRACKED files (git grep: untracked scratch,
# other lanes' worktrees and .git never match). Historical record surfaces are
# excluded: docs/handoff (frozen task reports + the decision doc + the backup
# tarball), plugins/leadv2/docs/handoff, CHANGELOG.md, docs/audits. A line that
# carries the decision id is a tombstone (it NAMES what was retired on purpose)
# and is allowed; a name on any other line is a live surface and fails.
NAME_PATTERN='leadv2-learn|learn-trigger|learn-consume|causal-critique|learn-close-counter|last-learn[.]txt'
TOMBSTONE='REFLECT-SELF-LEARNING-DECISION|retired-reflect-self-learning'
leftovers="$(
  git -C "${REPO_ROOT}" grep -niE "${NAME_PATTERN}" -- \
    ':(exclude)docs/handoff' \
    ':(exclude)plugins/leadv2/docs/handoff' \
    ':(exclude)CHANGELOG.md' \
    ':(exclude)docs/audits' \
    ':(exclude)plugins/leadv2/scripts/tests/test-reflect-is-retired.sh' \
    2>/dev/null | grep -viE "${TOMBSTONE}" || true
)"
if [[ -n "${leftovers}" ]]; then
  fail "B: live surface(s) still name the retired mechanism:"
  printf '%s\n' "${leftovers}" | head -20 >&2
else
  pass "B: zero live surfaces name the retired mechanism (tracked-file scan, tombstones exempt)"
fi

# hooks.json specifically: the registration must be gone with the hook.
if grep -q 'learn-consume' "${PLUGIN_ROOT}/hooks/hooks.json" 2>/dev/null; then
  fail "B: hooks.json still registers the retired consumer hook"
else
  pass "B: hooks.json carries no retired consumer-hook registration"
fi

# ── C. kept contract: over-deletion is also a failure ─────────────────────────
keep_check() { # $1=description  $2=file  $3=grep-re (optional)
  local desc="$1" f="$2" re="${3:-}"
  if [[ ! -f "${PLUGIN_ROOT}/${f}" ]]; then
    fail "C: kept surface missing: plugins/leadv2/${f} (${desc})"
    return
  fi
  if [[ -n "${re}" ]] && ! grep -qE "${re}" "${PLUGIN_ROOT}/${f}"; then
    fail "C: kept surface lost its contract: plugins/leadv2/${f} no longer matches /${re}/ (${desc})"
    return
  fi
  pass "C: kept: ${desc} (plugins/leadv2/${f})"
}

keep_check "lead-reflect close/audit writer skill" "skills/lead-reflect/SKILL.md" 'reflect-history[.]yaml'
keep_check "force-reflect A4 recovery/completeness hook" "hooks/leadv2-force-reflect.sh" 'reflect-history'
keep_check "phase8-assert A4 reflect-history gate" "scripts/leadv2-phase8-assert.sh" 'reflect-history'
keep_check "close-ritual guard" "hooks/leadv2-close-ritual-guard.sh" 'phase8-passed[.]flag'
keep_check "phase8-close still writes the closed/<id>.yaml record" "scripts/leadv2-phase8-close.sh" 'CLOSED_DIR=.docs/leadv2/closed'

# ── summary ───────────────────────────────────────────────────────────────────
printf 'pass=%d fail=%d\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
