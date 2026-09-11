#!/usr/bin/env bash
# leadv2-hook-registration-guard.sh — SessionStart.
#
# Runs a repo's own hook-registration check from the PLUGIN side, so that
# reverting the repo's `.claude/settings.json` cannot silence the check that
# would have reported the revert.
#
# WHY THIS LIVES IN THE PLUGIN (measured 2026-09-11, getmany-followup-bot):
# ten plugin hook registrations were added to a repo's settings.json and the
# obvious place to register their guard was that same settings.json. That does
# not work. A single `git checkout -- .claude/settings.json` removes the
# registrations AND the guard in one stroke, and the guard is silent about its
# own deletion — a guard that lives inside the thing it guards cannot survive
# that thing being deleted. The plugin is the only surface that a revert of a
# repo file does not reach.
#
# A COUNTING CHECK CANNOT SEE A REMOVAL. The sibling probe
# (scripts/check-registered-hooks-exist.sh) verifies that every REGISTERED hook
# resolves to a real file. Revert settings.json and the registered set becomes
# empty, so that probe reports "0 registered, all resolve" — green. This guard
# therefore compares against a COMMITTED EXPECTED SET
# (<root>/.claude/hooks-manifest.json) and fails on `expected - actual`.
#
# THE LIMIT, STATED RATHER THAN PAPERED OVER: no guard can detect the removal
# of its own declaration without state held outside both the declaration and
# the thing declared. Delete the manifest too and this exits 0. What it does
# cover is the case that actually happens — a targeted revert of settings.json,
# which is a different file from the manifest — plus the case where the
# manifest survives and the checker does not, which is a hard failure below.
#
# Contract per repo (opt-in; a repo with no manifest is untouched):
#   <root>/.claude/hooks-manifest.json            the committed expected set
#   <root>/.claude/scripts/check-hook-registrations.py   the repo's checker
#
# Exit is always 0: SessionStart advises, it never blocks a session. The signal
# is the printed text.
set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "${root}" || ! -d "${root}" ]]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "${root}" && -d "${root}" ]] || exit 0

manifest="${root}/.claude/hooks-manifest.json"
checker="${root}/.claude/scripts/check-hook-registrations.py"

# No manifest: this repo has not opted in. Silence is correct here — printing
# "no manifest" in every repo that never wanted one is how advisories get
# trained away.
[[ -r "${manifest}" ]] || exit 0

if [[ ! -r "${checker}" ]]; then
  # The manifest declares that this repo expects a guard, and the guard is
  # gone. That is a stronger signal than a missing registration, because the
  # repo is asserting the check should exist.
  echo "HOOK-REGISTRATION-GUARD FAIL: ${manifest} declares an expected hook set," >&2
  echo "  but its checker ${checker} is missing or unreadable." >&2
  echo "  Either restore the checker or delete the manifest; a declared guard that" >&2
  echo "  cannot run is worse than no guard, because the declaration reads as cover." >&2
  exit 0
fi

out="$(cd "${root}" && python3 "${checker}" 2>&1)"
rc=$?
if [[ "${rc}" -ne 0 ]]; then
  echo "HOOK-REGISTRATION-GUARD: ${root##*/} — checker exit ${rc}" >&2
  printf '%s\n' "${out}" >&2
fi
exit 0
