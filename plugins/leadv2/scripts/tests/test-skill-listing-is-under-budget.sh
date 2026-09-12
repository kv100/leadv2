#!/usr/bin/env bash
# test-skill-listing-is-under-budget.sh — SKILL-LISTING-REACHABILITY-01 (row d83bd49d5898).
#
# Guards the skill-listing retirement of 2026-09-12 on BOTH sides:
#   persona-engine (PE)  — 35 skills retired, 4 kept model-listed + migrate
#                          user-invoked + lifecycle state dir; budget 8.
#   leadv2 plugin        — 16 [internal] skills flagged disable-model-invocation
#                          (user-invocable /name still works, zero model-listing
#                          cost), leadv2-supervise archived, 6 deleted names
#                          registered; budget 24.
#
# The counts come from the LIVE skill directories and the LIVE frontmatter —
# never a hand-kept list. A skill counts as model-listed when its directory has
# a SKILL.md whose frontmatter lacks `disable-model-invocation: true` and PE
# settings.json has no `"name": "off"` override for it.
#
# The registries (.claude/skills/.retired in PE, plugins/leadv2/skills/.retired
# here) make revival a two-file lie: this suite fails if a retired name is
# named by a live surface in fire-form — Skill(<name>), skill="<name>",
# /<name> as a slash-command (preceded by start/space/backtick/quote, not a
# path segment), skills/<name>/SKILL.md, or "<name>": "off". Historical
# surfaces (docs/handoff/, docs/leadv2/closed/, docs/leadv2/tasks/ lane
# journals, docs/leadv2/reflect-history.yaml, docs/tasks.yaml, generated
# truth.generated.json, skills/archive/) are data, not firing surfaces.
# A registry entry suffixed `state-dir` keeps its directory for runtime state;
# only the skills/<name>/SKILL.md form is a revival for it.
#
# PE root override: SKILL_LISTING_PE_ROOT (default $HOME/Projects/persona-engine).
# Point it at a PE worktree to prove a lane there. Until row d83bd49d5898's PE
# lane merges, this suite is RED against PE main (41 listed > 8) — that is the
# strict, correct behavior; run it with SKILL_LISTING_PE_ROOT=<pe-worktree>
# from the PE lane itself.
#
# Declared negative control (mutation anchored, run via
# leadv2-mutation-control.sh worker mode): swap `Skill(skill="leadv2-doubt-driven")`
# for `Skill(skill="leadv2-loop-detection")` (a registry name) in
# plugins/leadv2/docs/phases.md -> no_fire_forms_plugin goes RED.
#
# Run: bash plugins/leadv2/scripts/tests/test-skill-listing-is-under-budget.sh
# Exit 0 = all pass; non-zero = failures.
# run-all-triggers: SKILL.md .retired leadv2.md phases.md

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"          # plugins/leadv2
LEADV2_ROOT="$(cd "${PLUGIN_ROOT}/../.." && pwd)"        # the leadv2 repo
PE_ROOT="${SKILL_LISTING_PE_ROOT:-$HOME/Projects/persona-engine}"
PE_BUDGET=8
PLUGIN_BUDGET=24

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1${2:+ -- $2}"; FAIL=$((FAIL + 1)); }

# listed_count <skills-dir> [settings-json>] — live dirs with SKILL.md, minus
# frontmatter-flagged, minus settings "off" overrides.
listed_count() {
  local dir="$1" settings="${2:-}" d name n=0 hidden
  for d in "${dir}"/*/; do
    [[ -f "${d}/SKILL.md" ]] || continue
    name="$(basename "${d}")"
    hidden=0
    # frontmatter ends at the second --- line
    if awk 'NR>1 && /^---[[:space:]]*$/ {exit} NR>1' "${d}/SKILL.md" \
        | grep -q '^disable-model-invocation:[[:space:]]*true'; then
      hidden=1
    fi
    if [[ -n "${settings}" && -f "${settings}" ]] \
       && grep -q "\"${name}\"[[:space:]]*:[[:space:]]*\"off\"" "${settings}" 2>/dev/null; then
      hidden=1
    fi
    [[ ${hidden} -eq 0 ]] && n=$((n + 1))
  done
  echo "${n}"
}

# registry_dead <registry-file> <skills-dir> — no registry name has a live
# SKILL.md under <skills-dir>/<name>/. For a `state-dir` entry the directory
# itself staying is expected; its SKILL.md coming back is still a revival.
registry_dead() {
  local reg="$1" dir="$2" line name bad=""
  [[ -f "${reg}" ]] || { echo "MISSING_REGISTRY ${reg}"; return 1; }
  while IFS= read -r line; do
    [[ -n "${line}" && "${line}" != \#* ]] || continue
    name="${line%% *}"
    if [[ -f "${dir}/${name}/SKILL.md" ]]; then
      bad="${bad} ${name}"
    fi
  done < "${reg}"
  if [[ -n "${bad}" ]]; then echo "REVIVED:${bad}"; return 1; fi
  echo "dead"
}

# ── 1. PE listing budget ─────────────────────────────────────────────────────
if [[ -d "${PE_ROOT}/.claude/skills" ]]; then
  pe_n="$(listed_count "${PE_ROOT}/.claude/skills" "${PE_ROOT}/.claude/settings.json")"
  if (( pe_n <= PE_BUDGET )); then
    pass "pe_listing_under_budget (${pe_n} <= ${PE_BUDGET}, root ${PE_ROOT})"
  else
    fail "pe_listing_under_budget" "${pe_n} listed > ${PE_BUDGET} at ${PE_ROOT} (retired skills revived? lane not merged?)"
  fi
else
  fail "pe_listing_under_budget" "no ${PE_ROOT}/.claude/skills (SKILL_LISTING_PE_ROOT wrong?)"
fi

# ── 2. Plugin listing budget ─────────────────────────────────────────────────
plugin_n="$(listed_count "${PLUGIN_ROOT}/skills")"
if (( plugin_n <= PLUGIN_BUDGET )); then
  pass "plugin_listing_under_budget (${plugin_n} <= ${PLUGIN_BUDGET})"
else
  fail "plugin_listing_under_budget" "${plugin_n} listed > ${PLUGIN_BUDGET} at ${PLUGIN_ROOT}/skills"
fi

# ── 3. Registries exist and stay dead ────────────────────────────────────────
if [[ ! -f "${PE_ROOT}/.claude/skills/.retired" ]]; then
  fail "pe_retired_registry_exists" "missing ${PE_ROOT}/.claude/skills/.retired"
elif [[ "$(registry_dead "${PE_ROOT}/.claude/skills/.retired" "${PE_ROOT}/.claude/skills")" == "dead" ]]; then
  pass "pe_retired_stay_dead ($(( $(grep -c . "${PE_ROOT}/.claude/skills/.retired") - $(grep -c '^#' "${PE_ROOT}/.claude/skills/.retired") )) names)"
else
  fail "pe_retired_stay_dead" "$(registry_dead "${PE_ROOT}/.claude/skills/.retired" "${PE_ROOT}/.claude/skills")"
fi
if [[ ! -f "${PLUGIN_ROOT}/skills/.retired" ]]; then
  fail "plugin_retired_registry_exists" "missing ${PLUGIN_ROOT}/skills/.retired"
elif [[ "$(registry_dead "${PLUGIN_ROOT}/skills/.retired" "${PLUGIN_ROOT}/skills")" == "dead" ]]; then
  pass "plugin_retired_stay_dead ($(( $(grep -c . "${PLUGIN_ROOT}/skills/.retired") - $(grep -c '^#' "${PLUGIN_ROOT}/skills/.retired") )) names)"
else
  fail "plugin_retired_stay_dead" "$(registry_dead "${PLUGIN_ROOT}/skills/.retired" "${PLUGIN_ROOT}/skills")"
fi

# ── 4. Fire-form scan: no retired name named by a live surface ───────────────
# Same pattern family as the registry headers, ported to python for the
# slash-command lookbehind. Scans git-tracked files only, minus historical
# surfaces. Runs against BOTH repos.
# NB: every argv after the registry is an EXCLUSION prefix — never pass a
# label or any other non-path token here. The first version of this scan
# passed the label "plugin" as argv[3], which startswith-excluded the whole
# plugins/ tree and made the plugin scan a permanent false green — caught by
# this suite's own declared negative control (mutant survived, 2026-09-12).
fire_forms() { # <repo-root> <registry> <extra-exclusion-prefixes...>
  python3 - "$@" <<'PYEOF'
import os, re, subprocess, sys
root, registry = sys.argv[1], sys.argv[2]
os.chdir(root)
extra = sys.argv[3:]
raw = [l for l in open(registry).read().splitlines() if l and not l.startswith("#")]
RETIRED, STATE_DIR = [], set()
for line in raw:
    name = line.split()[0]
    RETIRED.append(name)
    if line.rstrip().endswith("state-dir"):
        STATE_DIR.add(name)
patterns = {n: re.compile(
    r'Skill\(\s*(skill\s*=\s*")?' + re.escape(n) + r'["\s,)]'
    r'|skill\s*=\s*"' + re.escape(n) + r'"'
    + ("" if n in STATE_DIR else r'|(?<![\w/.-])/' + re.escape(n) + r'(?![.\w-])')
    + r'|skills/' + re.escape(n) + r'/SKILL\.md'
    r'|"' + re.escape(n) + r'"\s*:\s*"off"') for n in RETIRED}
r = subprocess.run(["git", "ls-files"], capture_output=True, text=True)
if r.returncode != 0:
    print(f"SCAN_ERROR git ls-files failed in {root}: {r.stderr.strip()}"); sys.exit(2)
EXCLUDE = ("docs/handoff/", "docs/leadv2/closed/", "docs/leadv2/tasks/",
           "docs/tasks.yaml", "docs/leadv2/reflect-history.yaml",
           "docs/systems-map/truth.generated.json",
           "plugins/leadv2/skills/archive/") + tuple(extra)
hits = []
for f in r.stdout.splitlines():
    if f.startswith(EXCLUDE):
        continue
    p = os.path.join(root, f)
    try:
        if not os.path.isfile(p) or os.path.getsize(p) > 3_000_000: continue
        s = open(p, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    for n, rx in patterns.items():
        if rx.search(s):
            hits.append(f"{n}: {f}")
if hits:
    for h in sorted(hits): print(f"RESIDUE {h}")
    sys.exit(1)
print(f"clean ({len(RETIRED)} names)")
PYEOF
}
pe_scan="$(fire_forms "${PE_ROOT}" ".claude/skills/.retired" 2>&1)"; pe_rc=$?
if (( pe_rc == 0 )); then
  pass "no_fire_forms_pe (${pe_scan})"
else
  fail "no_fire_forms_pe" "$(echo "${pe_scan}" | grep RESIDUE | head -5)"
fi
plugin_scan="$(fire_forms "${LEADV2_ROOT}" "plugins/leadv2/skills/.retired" 2>&1)"; plugin_rc=$?
if (( plugin_rc == 0 )); then
  pass "no_fire_forms_plugin (${plugin_scan})"
else
  fail "no_fire_forms_plugin" "$(echo "${plugin_scan}" | grep RESIDUE | head -5)"
fi

echo "---"
echo "skill-listing budget: ${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]] || exit 1
exit 0
