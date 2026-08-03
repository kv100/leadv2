#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GC="$ROOT/plugins/leadv2/scripts/leadv2-memory-gc.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MEM="$TMP/memory"; mkdir -p "$MEM/archive"
cat > "$MEM/MEMORY.md" <<'EOF'
## References
- [Alpha topic](reference_alpha.md) — alpha hook
- [Alpha duplicate](reference_alpha_copy.md) — duplicate hook
- [Standing alpha](reference_alpha_standing.md) — STANDING: never merge

## Feedback
- [Beta topic](feedback_beta.md) — beta hook
- [Beta copy](feedback_beta_copy.md) — beta copy hook
- [Orphan](reference_orphan.md) — missing file
EOF
for s in reference_alpha reference_alpha_copy reference_alpha_standing feedback_beta feedback_beta_copy; do
  printf '%s\n' "---" "name: $s" "description: alpha beta topic duplicate" "metadata:" "  type: reference" "---" "body" > "$MEM/$s.md"
done
sed -i '' 's/type: reference/type: feedback/' "$MEM/feedback_beta.md" "$MEM/feedback_beta_copy.md"
cp "$MEM/MEMORY.md" "$TMP/original"
cat > "$TMP/bad.json" <<'EOF'
{"verdicts":[{"cluster_id":"c01","verdict":"merge","into":"reference_alpha","members":[{"slug":"reference_alpha_standing","action":"absorb","absorbed_by":"reference_alpha","merged_hook":"x"}],"rationale":"bad"},{"cluster_id":"c02","verdict":"archive","into":"feedback_beta","members":[{"slug":"feedback_beta_copy","action":"absorb","merged_hook":"x"}],"rationale":"bad"}]}
EOF
bash "$GC" --memory-dir "$MEM" --cap 1 --sim 0 --verdicts-file "$TMP/bad.json" >/dev/null
grep -q 'immune_violation' "$MEM/memory-gc-report.md"
grep -q 'invalid_absorbed_by' "$MEM/memory-gc-report.md"
cat > "$TMP/good.json" <<'EOF'
{"verdicts":[{"cluster_id":"c01","verdict":"merge","into":"reference_alpha","members":[{"slug":"reference_alpha_copy","action":"absorb","absorbed_by":"reference_alpha","merged_hook":"copy"}],"rationale":"same topic"},{"cluster_id":"c02","verdict":"archive","into":"feedback_beta","members":[{"slug":"feedback_beta_copy","action":"absorb","absorbed_by":"feedback_beta","merged_hook":"copy"}],"rationale":"same topic"}]}
EOF
bash "$GC" --memory-dir "$MEM" --cap 1 --sim 0 --verdicts-file "$TMP/good.json" --apply >/dev/null
RUN="$(find "$MEM/archive" -maxdepth 1 -type d -name 'gc-*' | head -1)"
test -f "$RUN/manifest.yaml" && test ! -f "$MEM/reference_alpha_copy.md"
before="$(find "$MEM/archive" -maxdepth 1 -type d -name 'gc-*' | wc -l | tr -d ' ')"
noop="$(bash "$GC" --memory-dir "$MEM" --cap 7)"
grep -q 'no-op (index size 7, cap 7)' <<< "$noop"
after="$(find "$MEM/archive" -maxdepth 1 -type d -name 'gc-*' | wc -l | tr -d ' ')"
test "$before" = "$after"
bash "$GC" --memory-dir "$MEM" --restore "$RUN" >/dev/null
diff -u "$TMP/original" "$MEM/MEMORY.md"
test -f "$MEM/reference_alpha_copy.md"
echo 'PASS test-memory-index-gc'
