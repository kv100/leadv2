#!/usr/bin/env bash
set -euo pipefail
# proof-of: leadv2-memory-gc exercises the live batched-verdict path via a CLAUDE_BIN stub, proving the --model flag reaches the CLI, the model is called exactly once, the request is batched, and malformed JSON surfaces as llm:error.
#
# Scope: this proves the wiring (flag propagation, single-call batching, report
# consumption, error handling), NOT the vendor contract of the real Claude CLI.
# The stub stands in for the CLI; a real model call is out of scope for a
# deterministic offline proof.

source "$LEADV2_PLUGIN_ROOT/scripts/leadv2-proof-lib.sh"

TMP=$(proof_tmpdir)
MEMGC_SH="$LEADV2_PLUGIN_ROOT/scripts/leadv2-memory-gc.sh"

# ── Build fixture memory directory ──────────────────────────────────────────
MEMDIR="$TMP/memdir"
mkdir -p "$MEMDIR"

cat > "$MEMDIR/entry-one.md" <<'EOF'
---
name: entry-one
description: active reference
---
Content for entry one.
EOF

cat > "$MEMDIR/entry-two.md" <<'EOF'
---
name: entry-two
description: old superseded entry
---
Content for entry two.
EOF

cat > "$MEMDIR/entry-three.md" <<'EOF'
---
name: entry-three
description: ongoing docs
---
Content for entry three.
EOF

cat > "$MEMDIR/MEMORY.md" <<'EOF'
# Memory index

## Section A

- [Entry One](entry-one.md) — active reference
- [Entry Two](entry-two.md) — old superseded entry
- [Entry Three](entry-three.md) — ongoing docs
EOF

# ── Fixture project root (no immune/negative-memory files → no immunity) ────
PROOT="$TMP/projroot"
mkdir -p "$PROOT"

# ── Build stub claude binary ────────────────────────────────────────────────
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUBEOF'
#!/usr/bin/env bash
set -euo pipefail
# Stub claude CLI for memory-gc proof. Records the call and emits a
# well-formed batched verdict JSON. When STUB_MODE=malformed, emits garbage.
printf '%s\n' "$*" >> "${PROOF_DIR}/calls.argv"
printf '%s'  "$2"  >> "${PROOF_DIR}/prompt.txt"
_cnt=0
[[ -f "${PROOF_DIR}/calls.count" ]] && _cnt=$(cat "${PROOF_DIR}/calls.count")
_cnt=$((_cnt + 1))
printf '%s' "$_cnt" > "${PROOF_DIR}/calls.count"

if [[ "${STUB_MODE:-}" == "malformed" ]]; then
  echo "this is not valid json at all"
  exit 0
fi

cat <<'VERDICTJSON'
{"structured_output":{"verdicts":[{"entry_id":"e0001","verdict":"live","reason":"still referenced"},{"entry_id":"e0002","verdict":"spent","reason":"superseded by newer entry"},{"entry_id":"e0003","verdict":"live","reason":"active documentation"}]}}
VERDICTJSON
STUBEOF
chmod +x "$TMP/bin/claude"

# ── Run 1: valid batched verdicts ───────────────────────────────────────────
export PROOF_DIR="$TMP"
export CLAUDE_BIN="$TMP/bin/claude"

bash "$MEMGC_SH" \
  --memory-dir "$MEMDIR" \
  --project-root "$PROOT" \
  --byte-cap 50000 \
  --line-limit 500 \
  --model haiku

# ── Assertions for run 1 ────────────────────────────────────────────────────
assert_eq   1 "$(cat "$TMP/calls.count")"                              "model called exactly once"
assert_contains "$(cat "$TMP/calls.argv")" "--model haiku"             "--model haiku flag reached the CLI"
assert_contains "$(cat "$TMP/prompt.txt")" "entry-one"                 "entry-one slug present in batched prompt"
assert_contains "$(cat "$TMP/prompt.txt")" "entry-two"                 "entry-two slug present in batched prompt"
assert_contains "$(cat "$TMP/prompt.txt")" "entry-three"               "entry-three slug present in batched prompt"
assert_file_contains "$MEMDIR/memory-gc-report.md" "entry-one.*live"   "report has entry-one: live"
assert_file_contains "$MEMDIR/memory-gc-report.md" "entry-two.*spent"  "report has entry-two: spent"
assert_file_contains "$MEMDIR/memory-gc-report.md" "entry-three.*live" "report has entry-three: live"

# ── Run 2: malformed JSON surfaces as llm:error ────────────────────────────
rc=0
STUB_MODE=malformed bash "$MEMGC_SH" \
  --memory-dir "$MEMDIR" \
  --project-root "$PROOT" \
  --byte-cap 50000 \
  --line-limit 500 \
  --model haiku \
  >/dev/null 2>&1 || rc=$?

assert_ne 0 "$rc" "malformed JSON causes non-zero exit"
assert_file_contains "$MEMDIR/memory-gc-report.md" "llm: error" "malformed JSON surfaces as llm:error in report"

echo "[PROOF] leadv2-memory-gc: all assertions passed"
