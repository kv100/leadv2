#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GC="$ROOT/plugins/leadv2/scripts/leadv2-memory-gc.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MEM="$TMP/memory"; PROJECT="$TMP/project"
mkdir -p "$MEM/archive" "$PROJECT/docs/leadv2"
cat > "$MEM/MEMORY.md" <<'EOF'
## References
- [Alpha topic](reference_alpha.md) — OPEN follow-up. Also: [detail](reference_alpha_detail.md)
- [Alpha closed copy](reference_alpha_copy.md) — closed task
- [Standing alpha](reference_alpha_standing.md) — STANDING: never archive
- [User profile](user_profile.md) — user preference
- [Pinned fact](reference_keep.md) — explicit opt-out
- [Active pattern](reference_alpha_active.md) — active guard
- [Old incident](reference_old_incident.md) — fixed one-off
- [Orphan](reference_orphan.md) — missing file
EOF
for slug in reference_alpha reference_alpha_copy reference_alpha_standing user_profile reference_keep reference_alpha_active reference_old_incident; do
  printf '%s\n' "---" "name: $slug" "description: $slug durable details" "metadata:" "  type: reference" "---" "body" > "$MEM/$slug.md"
done
sed -i '' 's/type: reference/type: user/' "$MEM/user_profile.md"
sed -i '' '/metadata:/a\
  memory_gc: keep' "$MEM/reference_keep.md"
printf '%s\n' 'OPEN follow-up remains unresolved' >> "$MEM/reference_alpha.md"
cat > "$PROJECT/docs/leadv2-negative-memory.yaml" <<'EOF'
entries:
  - id: reference_alpha_active
    status: active
EOF
cat > "$PROJECT/docs/leadv2/immune-patterns.yaml" <<'EOF'
patterns: []
EOF
cp "$MEM/MEMORY.md" "$TMP/original"

cat > "$TMP/fake-claude" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' >> "$FAKE_CALLS"
printf '%s\n' "$@" > "$FAKE_ARGS"
printf '%s\n' '{"result":"{\"verdicts\":[{\"entry_id\":\"e0001\",\"verdict\":\"spent\",\"reason\":\"malicious unresolved composite verdict\"},{\"entry_id\":\"e0002\",\"verdict\":\"spent\",\"reason\":\"closed task already represented by alpha\"},{\"entry_id\":\"e0003\",\"verdict\":\"spent\",\"reason\":\"malicious standing verdict\"},{\"entry_id\":\"e0004\",\"verdict\":\"spent\",\"reason\":\"malicious user verdict\"},{\"entry_id\":\"e0005\",\"verdict\":\"spent\",\"reason\":\"malicious opt-out verdict\"},{\"entry_id\":\"e0006\",\"verdict\":\"spent\",\"reason\":\"malicious active verdict\"},{\"entry_id\":\"e0007\",\"verdict\":\"spent\",\"reason\":\"fixed one-off incident\"},{\"entry_id\":\"e0008\",\"verdict\":\"spent\",\"reason\":\"malicious orphan verdict\"}]}"}'
EOF
chmod +x "$TMP/fake-claude"

COMMON=(--memory-dir "$MEM" --project-root "$PROJECT" --byte-cap 2000 --line-limit 200)
FAKE_CALLS="$TMP/calls" FAKE_ARGS="$TMP/args" CLAUDE_BIN="$TMP/fake-claude" bash "$GC" "${COMMON[@]}" --model test-model >/dev/null
test "$(wc -l < "$TMP/calls" | tr -d ' ')" = 1
grep -qx -- '--model' "$TMP/args"
grep -qx -- 'test-model' "$TMP/args"
grep -q 'llm: available (model=test-model)' "$MEM/memory-gc-report.md"
grep -q 'spent entries: 2' "$MEM/memory-gc-report.md" || { sed -n '1,80p' "$MEM/memory-gc-report.md"; exit 1; }
grep -q 'configured maximum index read cost: 2000 bytes' "$MEM/memory-gc-report.md"
grep -q 'reference_alpha: live.*multi_pointer_index_line,unresolved_work.*model=spent overridden' "$MEM/memory-gc-report.md"
grep -q 'reference_alpha_standing: live.*model=spent overridden' "$MEM/memory-gc-report.md"
grep -q 'reference_alpha_active: live.*model=spent overridden' "$MEM/memory-gc-report.md"

cat > "$TMP/fail-claude" <<'EOF'
#!/usr/bin/env bash
echo 'synthetic provider failure' >&2
exit 9
EOF
chmod +x "$TMP/fail-claude"
set +e
CLAUDE_BIN="$TMP/fail-claude" bash "$GC" "${COMMON[@]}" --apply >/dev/null 2>"$TMP/failure.stderr"
failure_rc=$?
set -e
test "$failure_rc" = 7
grep -q 'llm: error: model call exited 9: synthetic provider failure' "$MEM/memory-gc-report.md"
test "$(find "$MEM/archive" -maxdepth 1 -type d -name 'gc-*' | wc -l | tr -d ' ')" = 0

cat > "$TMP/bad.json" <<'EOF'
{"verdicts":[{"entry_id":"e0001","verdict":"live","reason":"valid"},{"entry_id":"e0002","verdict":"spent","reason":""},{"entry_id":"e0003","verdict":"spent","reason":"bad"},{"entry_id":"e0004","verdict":"live","reason":"valid"},{"entry_id":"e0005","verdict":"live","reason":"valid"},{"entry_id":"e0006","verdict":"live","reason":"valid"},{"entry_id":"e0007","verdict":"live","reason":"valid"},{"entry_id":"e0008","verdict":"live","reason":"valid"}]}
EOF
bash "$GC" "${COMMON[@]}" --verdicts-file "$TMP/bad.json" >/dev/null
grep -q 'empty_reason' "$MEM/memory-gc-report.md"
grep -q 'immune_violation' "$MEM/memory-gc-report.md"

FAKE_CALLS="$TMP/calls" FAKE_ARGS="$TMP/args" CLAUDE_BIN="$TMP/fake-claude" bash "$GC" "${COMMON[@]}" --model test-model --apply >/dev/null
RUN="$(find "$MEM/archive" -maxdepth 1 -type d -name 'gc-*' | head -1)"
test -f "$RUN/manifest.yaml"
test -f "$RUN/MEMORY.md.archived"
test -f "$RUN/REASONS.md"
test ! -f "$MEM/reference_alpha_copy.md"
test ! -f "$MEM/reference_old_incident.md"
test -f "$MEM/reference_alpha_standing.md"
test "$(wc -l < "$RUN/REASONS.md" | tr -d ' ')" = 2

audit="$(bash "$GC" "${COMMON[@]}" --audit "$RUN")"
grep -q '"empty_reasons": 0' <<< "$audit"
grep -q '"missing_archived_index_lines": 0' <<< "$audit"
grep -q '"total_violations": 0' <<< "$audit"

before_calls="$(wc -l < "$TMP/calls" | tr -d ' ')"
noop="$(FAKE_CALLS="$TMP/calls" FAKE_ARGS="$TMP/args" CLAUDE_BIN="$TMP/fake-claude" bash "$GC" "${COMMON[@]}")"
grep -q 'no-op (index already classified at current sha256' <<< "$noop"
after_calls="$(wc -l < "$TMP/calls" | tr -d ' ')"
test "$before_calls" = "$after_calls"

bash "$GC" "${COMMON[@]}" --restore "$RUN" >/dev/null
diff -u "$TMP/original" "$MEM/MEMORY.md"
test -f "$MEM/reference_alpha_copy.md"
test -f "$MEM/reference_old_incident.md"
test ! -e "$MEM/.memory-gc-state.json"
echo 'PASS test-memory-index-gc'
