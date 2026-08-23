#!/usr/bin/env bash
# ARCHITECT-PREPASS-ORPHAN-01 (D2): on prepass timeout, dispatch-code.sh must kill
# the WHOLE descendant tree of the architect launcher, not just processes still in
# its own process group. A descendant that calls os.setsid() (macOS has no `setsid`
# binary, so this uses `python3 -c "os.setsid()"` to actually re-session, unlike a
# plain background `&` which stays in the same group) escapes `os.killpg` entirely
# and, unfixed, keeps running/writing indefinitely after the lane has already been
# parked -- the mechanism behind lane 117656b5: architect.stream.jsonl still growing
# 63 minutes after prepass entered, with the lane's own dispatch long since done.
set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
REPO="$ROOT/repo"; mkdir -p "$REPO/.claude/ref" "$REPO/docs/leadv2/.bus-offsets"
(cd "$REPO" && git init -q && git config user.email test@example.com && git config user.name test && : > seed && git add seed && git commit -qm seed)
printf 'router:\n  glm_policy:\n    sonnet_exceptions: [safety_gate_publish_payments]\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' > "$REPO/.claude/ref/leadv2-routing.yaml"
WORKER="$ROOT/worker"; ARCH="$ROOT/architect"
MARKER="$ROOT/grandchild-alive"
printf '#!/usr/bin/env bash\nnohup sleep 60 >/dev/null 2>&1 &\nprintf "PID=%%s LABEL=test SESSION_ID=test\\n" "$!"\n' > "$WORKER"
cat > "$ARCH" <<EOF
#!/usr/bin/env bash
python3 -c "
import os, time
os.setsid()
with open('$MARKER', 'a') as f:
    for i in range(60):
        f.write(str(i) + chr(10)); f.flush()
        time.sleep(1)
" </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true
sleep 600
EOF
chmod +x "$WORKER" "$ARCH"
DISPATCH="$(cd "$(dirname "$0")/.." && pwd)/leadv2-dispatch-code.sh"
start=$(date +%s)
LEADV2_DISPATCH_ARCHITECT_GATE=1 \
CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" LEADV2_DISPATCH_CACHE_DIR="$ROOT/cache" \
LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" LEADV2_DISPATCH_ARCHITECT_BIN="$ARCH" \
LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC=3 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
  bash "$DISPATCH" 'test D2 detached grandchild must die on timeout' --kind product --protected --writes "a.txt,b.txt,c.txt" >"$ROOT/out.log" 2>&1
elapsed=$(( $(date +%s) - start ))

grep -q 'architect_prepass task=.* status=failed reason=timeout' "$ROOT/out.log" || {
  echo "FAIL no architect_prepass timeout was ever journaled: elapsed=${elapsed}s"
  cat "$ROOT/out.log"
  exit 1
}

# Give the escaped grandchild a moment to have written at least once if it survived.
sleep 2
count_a=$(wc -l < "$MARKER" 2>/dev/null | tr -d ' ')
count_a="${count_a:-0}"
sleep 3
count_b=$(wc -l < "$MARKER" 2>/dev/null | tr -d ' ')
count_b="${count_b:-0}"
pkill -f "os.setsid" >/dev/null 2>&1 || true

if [[ "$count_b" -gt "$count_a" ]]; then
  echo "FAIL the detached grandchild survived the timeout kill and kept writing after the lane parked (count ${count_a} -> ${count_b})"
  exit 1
fi
echo "PASS: architect prepass timeout kills the whole descendant tree, including a re-sessioned grandchild (ARCHITECT-PREPASS-ORPHAN-01 D2); marker stable at ${count_b} lines"
