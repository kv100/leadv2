#!/usr/bin/env bash
# .claude/leadv2-overrides/status-collector-facts.sh — leadv2 plugin repo's
# own repo_facts hook for leadv2-status-collector.sh.
#
# CODE-INTEL-IS-INSTALLED-AND-UNUSED-01 item 5: the code-intel attach rate
# (leadv2-code-intel-rate.sh) existed only as a CLI someone had to remember to
# run by hand -- nothing put it in front of anyone, so a regression to 0/5
# attached (the state the founder's original question found) could recur
# silently forever. This hook is the fix: leadv2-status-collector.sh sources
# it, calls collect_repo_facts(), and folds its one JSON object into
# docs/leadv2/status-snapshot.json's "repo_facts" section, which
# render_repo_facts() (leadv2-status-surface.sh) prints on every
# `--mode all` / `--mode repo-facts` call -- the same path founder-status.md
# reads. Contract: print exactly one JSON object to stdout; a non-JSON or
# nonzero-exit run is caught by the collector's own per-section isolation
# (_sc_run_section), so a rate-script regression degrades this one section,
# never the whole snapshot.
collect_repo_facts() {
  local rate_script="${PROJECT_ROOT}/plugins/leadv2/scripts/leadv2-code-intel-rate.sh"
  local raw rate_line by_arm
  raw=""
  if [[ -x "${rate_script}" ]]; then
    raw="$(bash "${rate_script}" 2>/dev/null)" || raw=""
  fi

  rate_line="$(printf '%s\n' "${raw}" | grep "^attach rate among MCP-capable arms" | head -1)"
  if [[ -z "${rate_line}" ]]; then
    rate_line="$(printf '%s\n' "${raw}" | grep "^code-intel attach rate" | head -1)"
  fi
  [[ -n "${rate_line}" ]] || rate_line="unavailable"

  # ARM/MODE/COUNT rows look like "glm-flash    attached    5" -- collapse to
  # "glm-flash:attached=5 sonnet:fail_open=8" so it's one flat repo_facts value.
  by_arm="$(printf '%s\n' "${raw}" \
    | awk '/^[A-Za-z0-9_-]+[[:space:]]+(attached|fail_open|arm_unwired|other)[[:space:]]+[0-9]+$/ {print $1":"$2"="$3}' \
    | paste -sd ' ' -)"
  [[ -n "${by_arm}" ]] || by_arm="no data"

  CODE_INTEL_RATE_LINE="${rate_line}" CODE_INTEL_BY_ARM="${by_arm}" python3 -c '
import json, os
print(json.dumps({
    "code_intel_attach_rate": os.environ["CODE_INTEL_RATE_LINE"],
    "code_intel_by_arm": os.environ["CODE_INTEL_BY_ARM"],
}))
'
}
