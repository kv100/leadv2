#!/usr/bin/env bash
# run-all-triggers: leadv2-state-path leadv2-active-registry leadv2-status-collector
# SHADOW-CONTROL-PLANE-01: mutation = remove git-toplevel normalization.
set -euo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPTS/leadv2-temp.sh"
TMP="$(lv2_mktemp_dir shadow-control-plane)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
REPO="$TMP/repo"
mkdir -p "$REPO/plugins/leadv2/scripts" "$TMP/state"
git -C "$REPO" init -q
lv2_assert_scratch_repo "$REPO"
export LEADV2_TEST_CONTEXT=1 LEADV2_STATE_BASE="$TMP/state"
unset LEADV2_STATE_ROOT LEADV2_STATE_PATH_BIN LEADV2_PROJECT_ROOT CLAUDE_PROJECT_DIR PROJECT_ROOT
PASS=0; FAIL=0
check() { if "$@"; then PASS=$((PASS+1)); else echo "FAIL: $*"; FAIL=$((FAIL+1)); fi; }
# Same PROJECT_ROOT input as collector -> lanes-snapshot from scripts cwd.
cd "$REPO/plugins/leadv2/scripts"
resolved="$(PROJECT_ROOT="$PWD" bash "$SCRIPTS/leadv2-state-path.sh" active.yaml)"
check test "$resolved" = "$TMP/state/repo/active.yaml"
check test -L "$REPO/docs/leadv2/active.yaml"
check test "$(readlink "$REPO/docs/leadv2/active.yaml" || true)" = "$resolved"
check test ! -e "$PWD/docs/leadv2"
# Independent directory census catches links (including dangling ones).
check python3 - "$REPO" <<'PYTEST'
import os, sys
assert not any(p.endswith('/scripts/docs/leadv2') for p, ds, fs in os.walk(sys.argv[1]))
PYTEST
# Paired deletion control: identical real registry CRUD, with nine legacy
# links present and absent. No mocks of registry storage or resolver.
for variant in present absent; do
  CASE="$TMP/$variant"
  mkdir -p "$CASE/plugins/leadv2/scripts"
  git -C "$CASE" init -q
  lv2_assert_scratch_repo "$CASE"
  if [[ "$variant" == present ]]; then
    mkdir -p "$CASE/plugins/leadv2/scripts/docs/leadv2"
    for name in active.yaml active.yaml.lock bus.jsonl merge-queue.jsonl open-threads.md questions .bus-offsets .bus.lock .merge.lock; do
      ln -s "$TMP/dead-state/$name" "$CASE/plugins/leadv2/scripts/docs/leadv2/$name"
    done
  fi
  (
    cd "$CASE/plugins/leadv2/scripts"
    export LEADV2_PROJECT_ROOT="$CASE"
    source "$SCRIPTS/leadv2-active-registry.sh" || exit 1
    leadv2_active_register SHADOW-CRUD Standard "$CASE" fixture false > "$TMP/$variant.register" || exit 1
    leadv2_active_list > "$TMP/$variant.list" || exit 1
    python3 - "$TMP/state/$variant/active.yaml" <<'PYTEST' || exit 1
import sys, yaml
rows=yaml.safe_load(open(sys.argv[1]))['sessions']
assert len(rows)==1 and rows[0]['task_id']=='SHADOW-CRUD', rows
PYTEST
    leadv2_active_unregister SHADOW-CRUD > "$TMP/$variant.unregister" || exit 1
    python3 - "$TMP/state/$variant/active.yaml" <<'PYTEST' || exit 1
import sys, yaml
assert yaml.safe_load(open(sys.argv[1]))['sessions']==[]
PYTEST
  ) && check true || check false
  check grep -q SHADOW-CRUD "$TMP/$variant.list"
  if [[ "$variant" == absent ]]; then
    check test ! -e "$CASE/plugins/leadv2/scripts/docs/leadv2"
    check python3 - "$CASE/plugins/leadv2/scripts" <<'PYTEST'
import os, sys
assert os.listdir(sys.argv[1])==[], os.listdir(sys.argv[1])
PYTEST
  fi
  echo "deletion-control: $variant register/list/unregister checked"
done
# Run the actual writer from scripts cwd with no project-root override.
# Storage, collector and snapshot are real; the liveness override applies
# only to foreign-repo enrichment (own-repo liveness remains real).
COLLECT="$TMP/collector"
mkdir -p "$COLLECT/plugins/leadv2/scripts" "$TMP/ledger"
git -C "$COLLECT" init -q
git -C "$COLLECT" -c user.name=test -c user.email=test@local commit --allow-empty -qm seed
lv2_assert_scratch_repo "$COLLECT"
# A fresh git repository has no registry yet. Snapshot must fail closed;
# initialize via the same sourced registry API used by dispatch before reading.
(LEADV2_PROJECT_ROOT="$COLLECT" LEADV2_SUPERVISE_OBSERVE_ONLY=1 \
  bash "$SCRIPTS/leadv2-lanes-snapshot.sh" --json --no-all-repos) > "$TMP/uninitialized.json" 2> "$TMP/uninitialized.err" || true
python3 - "$TMP/uninitialized.json" <<'PYTEST'
import json, sys
error=json.load(open(sys.argv[1]))
assert error['error']=='registry_error', error
print('writer precondition: '+error['message'])
PYTEST
(
  export LEADV2_PROJECT_ROOT="$COLLECT"
  source "$SCRIPTS/leadv2-active-registry.sh"
  leadv2_active_register SHADOW-WRITER Standard "$COLLECT" fixture false
  leadv2_active_unregister SHADOW-WRITER
) > "$TMP/writer-init.out" 2>&1
printf '#!/usr/bin/env bash\nprintf '''%%s\\n''' '''{"lanes":[],"jobs":[],"availability":"available"}'''\n' > "$TMP/liveness.sh"
chmod +x "$TMP/liveness.sh"
(cd "$COLLECT/plugins/leadv2/scripts" &&
  env -u PROJECT_ROOT -u LEADV2_PROJECT_ROOT -u CLAUDE_PROJECT_DIR -u CLAUDE_PROJECT_ROOT \
    LEADV2_SUPERVISE_OBSERVE_ONLY=1 LEADV2_LANE_LIVENESS_BIN="$TMP/liveness.sh" \
    LEADV2_STATUS_LEDGER_DIR="$TMP/ledger" LEADV2_EVENT_LOG_DIR="$TMP/events" \
    bash "$SCRIPTS/leadv2-status-collector.sh") > "$TMP/collector.out" 2>&1 || true
check test -L "$COLLECT/docs/leadv2/active.yaml"
check test ! -e "$COLLECT/plugins/leadv2/scripts/docs/leadv2"
check python3 - "$COLLECT" <<'PYTEST'
import json, os, sys
root=sys.argv[1]
p=root+'/docs/leadv2/status-snapshot.json'
assert os.path.isfile(p), p
doc=json.load(open(p))
assert doc['sections']['lanes']['ok'], doc['sections']['lanes']
assert doc['sections']['lanes']['data']['table']==[], doc['sections']['lanes']
assert not os.path.lexists(root+'/plugins/leadv2/scripts/docs')
print('writer: lanes.ok=true table=[]; nested docs absent by lexists + os.walk')
assert not any(p.endswith('/scripts/docs/leadv2') for p, ds, fs in os.walk(root))
PYTEST
echo "writer: real collector -> lanes-snapshot -> state-path checked"
# Explicit non-git sandbox roots retain their supported local layout.
mkdir -p "$TMP/plain"
plain="$(PROJECT_ROOT="$TMP/plain" bash "$SCRIPTS/leadv2-state-path.sh" --no-link active.yaml)"
check test "$plain" = "$TMP/plain/docs/leadv2/active.yaml"
echo "shadow-control-plane: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" == 0 ]]
