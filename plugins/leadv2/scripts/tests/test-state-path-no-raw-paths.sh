#!/usr/bin/env bash
# tests/test-state-path-no-raw-paths.sh — LANE-STATE-LEAK-01 §4(i)
#
# The invariant this task exists to protect ("no session-global leadv2 state
# is stored per-worktree") is enforced by nothing but review today. This
# guard makes it a test: grep every leadv2 script/hook for a raw
# ${PROJECT_ROOT}/docs/leadv2/<managed-name> construction and fail on any
# occurrence NOT accounted for by the explicit allow-list below.
#
# The allow-list has two legitimate kinds of entry, both commented inline:
#   - the resolver-fallback line itself (the degrade-to-old-path branch a
#     resolver failure takes -- required by §2.1, not a violation)
#   - a pre-existing violation the architect prepass named as OUT OF SCOPE
#     for this task (leadv2-resume.sh, leadv2-lane-liveness.sh, etc. --
#     §6 non-goals) -- listed so a NEW pre-existing-style violation doesn't
#     hide behind an already-accepted one, and so fixing one of these
#     shrinks the allow-list rather than needing a second edit here.
#
# Any raw reference to a managed name in a file/line NOT on the allow-list
# is exactly the drift this guard exists to catch (§4i: "the same drift that
# produced this task will produce the next one").

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

# Managed name -> newline-separated list of "relative/path.sh" allowed to
# reference it raw (resolver-fallback lines + named pre-existing violations).
allowed_files_for() {
  case "$1" in
    "active.yaml")
      # active.yaml/tombstones.yaml/questions raw refs pre-date
      # LEAD-CONTROL-PLANE-01 and are named OUT OF SCOPE for LANE-STATE-LEAK-01
      # (design §6 non-goals) -- the guard test §4(i) itself was asked to
      # surface, not fix, them.
      printf 'plugins/leadv2/scripts/leadv2-lane-liveness.sh\nplugins/leadv2/scripts/leadv2-resume.sh\nplugins/leadv2/scripts/leadv2-status-snapshot.sh\nplugins/leadv2/scripts/leadv2-phase-advance.sh\nplugins/leadv2/scripts/leadv2-budget-check.sh\nplugins/leadv2/scripts/leadv2-writes-overlap.sh\nplugins/leadv2/scripts/leadv2-task-init-pattern.sh\nplugins/leadv2/hooks/leadv2-stale-pid-sweep.sh\n'
      ;;
    "glm-deferred.jsonl"|".arm-exceptions-"*|".codex-credits-empty.stamp"|"glm-deferred.d")
      printf 'plugins/leadv2/scripts/leadv2-dispatch-code.sh\nplugins/leadv2/scripts/leadv2-broad-status.sh\n'
      ;;
    "founder-status.md"|"founder-status-full.md")
      printf 'plugins/leadv2/scripts/leadv2-broad-status.sh\nplugins/leadv2/hooks/leadv2-single-lead-beat.sh\n'
      ;;
    ".board-empty-since"|".founder-status-epoch")
      printf 'plugins/leadv2/scripts/leadv2-broad-status.sh\n'
      ;;
    *)
      printf ''
      ;;
  esac
}

MANAGED_NAMES=(
  "active.yaml"
  "glm-deferred.jsonl"
  "glm-deferred.d"
  ".codex-credits-empty.stamp"
  "founder-status.md"
  "founder-status-full.md"
  ".board-empty-since"
  ".founder-status-epoch"
)

for name in "${MANAGED_NAMES[@]}"; do
  # Raw construction only: ${PROJECT_ROOT}/docs/leadv2/<name> or
  # $PROJECT_ROOT/docs/leadv2/<name>, skipping comment-only lines and this
  # test file itself.
  esc_name="$(printf '%s' "$name" | sed 's/[.[\*^$]/\\&/g')"
  hits="$(grep -rEn "\\\$\\{?PROJECT_ROOT\\}?/docs/leadv2/${esc_name}([^A-Za-z0-9._-]|$)" \
    "${PLUGIN_ROOT}/scripts" "${PLUGIN_ROOT}/hooks" \
    --include='*.sh' 2>/dev/null | grep -v ':[0-9]*: *#' | grep -v '/tests/')"

  allowed="$(allowed_files_for "$name")"
  offenders=""
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    hit_file="${hit%%:*}"
    hit_rel="${hit_file#${PLUGIN_ROOT}/../../}"
    hit_rel="plugins/leadv2/${hit_file#${PLUGIN_ROOT}/}"
    if ! grep -qxF "$hit_rel" <<<"$allowed"; then
      offenders="${offenders}${hit}"$'\n'
    fi
  done <<<"$hits"

  if [[ -z "$offenders" ]]; then
    pass "${name}: every raw reference is on the allow-list"
  else
    fail "${name}: un-allow-listed raw reference" "$offenders"
  fi
done

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME FAILED"
  exit 1
fi
