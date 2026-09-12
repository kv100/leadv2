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
# run-all-triggers: leadv2-lane-liveness leadv2-resume leadv2-budget-check leadv2-state-path
#
# SUITE-SELECTION-COVERS-140-OF-390-01: this suite carried no trigger
# marker and matched no name convention, so `run-all.sh --scope changed`
# never selected it — it could only ever run under `--scope all`. The
# triggers are the production files the suite's own body references most,
# with shared helpers excluded so a helper edit does not select everything.


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
      # surface, not fix, them. anti-silence-pulse.sh joined the list
      # ONE-STATUS-MECHANISM-01 (2026-09-13) when the pulse moved into the
      # plugin: its ACTIVE_YAML refs are env-overridable resolver-fallback
      # lines, the same shape as lane-liveness.sh's.
      printf 'plugins/leadv2/scripts/leadv2-lane-liveness.sh\nplugins/leadv2/scripts/leadv2-resume.sh\nplugins/leadv2/scripts/leadv2-status-snapshot.sh\nplugins/leadv2/scripts/leadv2-phase-advance.sh\nplugins/leadv2/scripts/leadv2-budget-check.sh\nplugins/leadv2/scripts/leadv2-writes-overlap.sh\nplugins/leadv2/scripts/leadv2-task-init-pattern.sh\nplugins/leadv2/scripts/anti-silence-pulse.sh\nplugins/leadv2/hooks/leadv2-stale-pid-sweep.sh\n'
      ;;
    "glm-deferred.jsonl"|".arm-exceptions-"*|".codex-credits-empty.stamp"|"glm-deferred.d")
      printf 'plugins/leadv2/scripts/leadv2-dispatch-code.sh\n'
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
)

# Parameterised so a falsification mutant corpus (a COPY of the tree, never
# the tree itself) can be scanned with the identical logic real CI runs.
# scan_root() -> 0 if every raw reference under $1 is allow-listed, 1 + a
# "SOME FAILED"-shaped report on stdout otherwise. $2 (optional) suppresses
# pass()/fail() emission (used by the falsification round below so its own
# expected-red run doesn't pollute this suite's PASS/FAIL tally).
scan_root() {
  local root="$1" quiet="${2:-0}" root_fail=0
  local _pass _fail
  if [[ "$quiet" == "1" ]]; then
    _pass() { :; }
    _fail() { root_fail=1; }
  else
    _pass() { pass "$1"; }
    _fail() { fail "$1" "$2"; root_fail=1; FAIL=1; }
  fi

  for name in "${MANAGED_NAMES[@]}"; do
    # Raw construction only: ${PROJECT_ROOT}/docs/leadv2/<name> or
    # $PROJECT_ROOT/docs/leadv2/<name>, skipping comment-only lines and this
    # test file itself.
    esc_name="$(printf '%s' "$name" | sed 's/[.[\*^$]/\\&/g')"
    hits="$(grep -rEn "\\\$\\{?PROJECT_ROOT\\}?/docs/leadv2/${esc_name}([^A-Za-z0-9._-]|$)" \
      "${root}/scripts" "${root}/hooks" \
      --include='*.sh' 2>/dev/null | grep -v ':[0-9]*: *#' | grep -v '/tests/')"

    allowed="$(allowed_files_for "$name")"
    offenders=""
    while IFS= read -r hit; do
      [[ -z "$hit" ]] && continue
      hit_file="${hit%%:*}"
      hit_rel="plugins/leadv2/${hit_file#${root}/}"
      if ! grep -qxF "$hit_rel" <<<"$allowed"; then
        offenders="${offenders}${hit}"$'\n'
      fi
    done <<<"$hits"

    if [[ -z "$offenders" ]]; then
      _pass "${name}: every raw reference is on the allow-list"
    else
      _fail "${name}: un-allow-listed raw reference" "$offenders"
    fi
  done
  return "${root_fail}"
}

scan_root "${PLUGIN_ROOT}" 0

# ── falsification: prove this guard can actually catch a reintroduced raw
# path. Mutant: a COPY of the plugin tree (never the tree itself) with one
# line appended to a file that is NOT on any allow-list. Same scanner, same
# allow-list logic, run against the mutant corpus.
CORPUS_ROOT="$(mktemp -d)"
trap 'rm -rf "${CORPUS_ROOT}"' EXIT
mkdir -p "${CORPUS_ROOT}/scripts" "${CORPUS_ROOT}/hooks"
cp -R "${PLUGIN_ROOT}/scripts/." "${CORPUS_ROOT}/scripts/"
cp -R "${PLUGIN_ROOT}/hooks/." "${CORPUS_ROOT}/hooks/"
MUTANT_FILE="${CORPUS_ROOT}/scripts/leadv2-mutant-raw-path-probe.sh"
cat > "${MUTANT_FILE}" <<'EOF'
#!/usr/bin/env bash
# Falsification fixture only -- not a real caller, not on any allow-list.
X="${PROJECT_ROOT}/docs/leadv2/active.yaml"
EOF

scan_root "${CORPUS_ROOT}" 1; pre_rc=$?
scan_root "${PLUGIN_ROOT}" 1; post_rc=$?
if [[ ${pre_rc} -ne 0 && ${post_rc} -eq 0 ]]; then
  pass "falsification: mutant corpus (un-allow-listed raw path) is caught, real tree is clean"
  echo "RED-then-GREEN: state-path-no-raw-paths (pre_rc=${pre_rc} -> post_rc=${post_rc})"
else
  fail "falsification" "mutant pre_rc=${pre_rc} (want !=0) real post_rc=${post_rc} (want 0)"
fi
rm -rf "${CORPUS_ROOT}"
trap - EXIT

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME FAILED"
  exit 1
fi
