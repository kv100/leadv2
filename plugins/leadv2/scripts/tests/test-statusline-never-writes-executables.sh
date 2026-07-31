#!/usr/bin/env bash
# STATUSLINE-DESTROYS-PROBER-01: the statusline tail script was writing a
# JSON memo over leadv2-lane-liveness.sh itself, many times a minute, on
# every repaint -- it destroyed the very prober it depends on. This test
# NEVER runs against the real plugin tree (see the containment pattern in
# test-lane-liveness-authoritative.sh, TEST-DESTROYS-PRODUCTION-SCRIPT-01):
# every helper here runs against a throwaway copy of scripts/ under $tmp,
# with its own scratch TMPDIR/CACHE_DIR, and an EXIT tripwire re-checks the
# real repo's leadv2-lane-liveness.sh/tail-script md5 so any escape aborts
# loudly instead of destroying it quietly.
#
# T1/T2/T3's write-site assertions invoke the embedded python block
# DIRECTLY (extracted fresh from the CURRENT tail script on every run, so
# it can never silently drift from production code) rather than going
# through the full bash+git-resolver+outer-timeout chain -- that chain
# depends on `leadv2-state-path.sh`'s git resolution and an outer `timeout
# 10`, both of which are unrelated to the write-guard this test exists to
# prove and were observed to add flaky multi-second latency under load,
# occasionally starving the outer timeout before the guard logic even ran.
# The bash-level fail-closed derivation (LIVENESS_BIN="") IS still tested
# end-to-end against the real script, via the unconditional Step-0 trace
# line that fires before any git/resolver work.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$(cd "${SCRIPT_DIR}/.." && pwd)/leadv2-temp.sh"

tmp="$(lv2_mktemp_dir statusline-safety)"
trap 'rm -rf "$tmp"' EXIT

_lv2_md5() { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}'; }
REAL_HELPER="${REAL_PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
REAL_TAIL="${REAL_PLUGIN_DIR}/scripts/leadv2-lane-status-line-tail.sh"
REAL_HELPER_MD5_BEFORE="$(_lv2_md5 "$REAL_HELPER")"
REAL_TAIL_MD5_BEFORE="$(_lv2_md5 "$REAL_TAIL")"
lv2_tripwire() {
  local after_h after_t
  after_h="$(_lv2_md5 "$REAL_HELPER")"
  after_t="$(_lv2_md5 "$REAL_TAIL")"
  if [[ "$after_h" != "$REAL_HELPER_MD5_BEFORE" || "$after_t" != "$REAL_TAIL_MD5_BEFORE" ]]; then
    printf '[TEST-SAFETY] FATAL: test mutated a production path\n  helper before=%s after=%s\n  tail   before=%s after=%s\n' \
      "$REAL_HELPER_MD5_BEFORE" "$after_h" "$REAL_TAIL_MD5_BEFORE" "$after_t" >&2
    exit 99
  fi
}
trap 'lv2_tripwire' EXIT

PLUGIN_DIR="$tmp/plugin"
mkdir -p "$PLUGIN_DIR"
cp -a "${REAL_PLUGIN_DIR}/scripts" "$PLUGIN_DIR/"
case "$PLUGIN_DIR" in
  "$tmp"/*) ;;
  *) printf '[TEST-SAFETY] ABORT: PLUGIN_DIR %s did not resolve under scratch root %s\n' "$PLUGIN_DIR" "$tmp" >&2; exit 90 ;;
esac

CACHE_DIR="$tmp/cache"
mkdir -p "$CACHE_DIR"
# Canonicalize once: $TMPDIR on this platform can carry a trailing slash,
# which would otherwise make bash's own $CACHE_DIR string diverge (double
# slash) from python's os.path.abspath()-normalized dest strings, breaking
# every later lexical "under CACHE_DIR" comparison for a reason that has
# nothing to do with the guard itself.
CACHE_DIR="$(cd "$CACHE_DIR" && pwd)"
TAIL_SCRIPT="$PLUGIN_DIR/scripts/leadv2-lane-status-line-tail.sh"
LIVENESS_COPY="$PLUGIN_DIR/scripts/leadv2-lane-liveness.sh"

pass=0 fail=0 skip=0
ok()   { pass=$((pass+1)); printf '[PASS] %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '[FAIL] %s\n' "$1"; }
skp()  { skip=$((skip+1)); printf '[SKIP] %s\n' "$1"; }

# ---------------------------------------------------------------------
# Extract the embedded python block fresh from the CURRENT tail script
# (never a hand-copy, so this can never drift from what actually ships).
# Bash's own double-quote parsing turns every escaped \$ inside that
# heredoc-style string into a literal $ before python ever sees it (the
# raw_label() tasks-lib subprocess snippet relies on this) -- replicate
# that one transform after extraction so the standalone .py file behaves
# byte-for-byte like the string bash would actually hand to python3 -c.
# ---------------------------------------------------------------------
START_LINE="$(grep -n 'python3 -c "$' "$TAIL_SCRIPT" | head -1 | cut -d: -f1)"
END_LINE="$(grep -n '^" "\$ACTIVE_YAML" "\$CWD_FROM_INPUT" "\$LANE_CACHE_FILE"' "$TAIL_SCRIPT" | head -1 | cut -d: -f1)"
if [[ -z "$START_LINE" || -z "$END_LINE" ]]; then
  printf '[TEST-SAFETY] ABORT: could not locate the embedded python block markers in %s -- extraction markers have drifted, update this test\n' "$TAIL_SCRIPT" >&2
  exit 91
fi
PY_BLOCK="$tmp/tail-block.py"
sed -n "$((START_LINE+1)),$((END_LINE-1))p" "$TAIL_SCRIPT" > "$PY_BLOCK"
python3 -c "
p = '$PY_BLOCK'
s = open(p).read()
s = s.replace(chr(92)+chr(36), chr(36))
open(p, 'w').write(s)
"

# run_block <active_yaml> <root> <cache_file> <limits_path> <label_memo_file>
#           <tasks_lib> <liveness_bin> <liveness_memo_file> <liveness_ttl>
#           <count_sidecar_file> <width> <base_visible_len> <cache_dir>
run_block() { python3 "$PY_BLOCK" "$@"; }

FIXTURE_ROOT="$tmp/fixture-repo"
mkdir -p "$FIXTURE_ROOT"
CACHE_FILE="$CACHE_DIR/lane-cache"
LABEL_MEMO_FILE="$CACHE_DIR/lane-cache.labels"
LIMITS_PATH="$FIXTURE_ROOT/.claude/leadv2-overrides/active-limits.yaml"
LIVENESS_MEMO_FILE="$CACHE_DIR/lane-cache.liveness"
COUNT_SIDECAR_FILE="$CACHE_DIR/lanecount"
ACTIVE_YAML="$tmp/state-root/active.yaml"

# ---------------------------------------------------------------------
# T1: pre-plant an EXECUTABLE dummy "prober" at the exact path the memo
# write targets. Pre-fix, os.replace() unconditionally clobbers it; the
# safe_replace guard must refuse (target-executable) and leave it intact.
# ---------------------------------------------------------------------
rm -f "$LIVENESS_MEMO_FILE"
printf '#!/bin/sh\necho DUMMY_PROBER\n' > "$LIVENESS_MEMO_FILE"
chmod 755 "$LIVENESS_MEMO_FILE"
DUMMY_MD5_BEFORE="$(_lv2_md5 "$LIVENESS_MEMO_FILE")"

run_block "$ACTIVE_YAML" "$FIXTURE_ROOT" "$CACHE_FILE" "$LIMITS_PATH" \
  "$LABEL_MEMO_FILE" "${PLUGIN_DIR}/scripts/leadv2-tasks-lib.sh" \
  "$LIVENESS_COPY" "$LIVENESS_MEMO_FILE" "10" "$COUNT_SIDECAR_FILE" \
  "80" "0" "$CACHE_DIR" >/dev/null 2>&1

DUMMY_MD5_AFTER="$(_lv2_md5 "$LIVENESS_MEMO_FILE")"
if [[ -x "$LIVENESS_MEMO_FILE" && "$DUMMY_MD5_AFTER" == "$DUMMY_MD5_BEFORE" ]]; then
  ok "T1: executable at the memo-write target is left byte-identical (guard refused)"
else
  bad "T1: memo write clobbered an executable target (before=$DUMMY_MD5_BEFORE after=$DUMMY_MD5_AFTER, exec=$([[ -x "$LIVENESS_MEMO_FILE" ]] && echo yes || echo no))"
fi
rm -f "$LIVENESS_MEMO_FILE"

# ---------------------------------------------------------------------
# T2: enumerate every write destination from the opt-in trace log and
# assert each one resolves under CACHE_DIR.
# ---------------------------------------------------------------------
TRACE_LOG="${CACHE_DIR}/leadv2-statusline-trace.log"
rm -f "$TRACE_LOG"
LEADV2_STATUSLINE_TRACE=1 run_block "$ACTIVE_YAML" "$FIXTURE_ROOT" "$CACHE_FILE" "$LIMITS_PATH" \
  "$LABEL_MEMO_FILE" "${PLUGIN_DIR}/scripts/leadv2-tasks-lib.sh" \
  "$LIVENESS_COPY" "$LIVENESS_MEMO_FILE" "10" "$COUNT_SIDECAR_FILE" \
  "80" "0" "$CACHE_DIR" >/dev/null 2>&1

if [[ -f "$TRACE_LOG" ]]; then
  BAD_DEST=""
  while IFS= read -r dest; do
    case "$dest" in
      "$CACHE_DIR"/*) ;;
      *) BAD_DEST="$BAD_DEST $dest" ;;
    esac
  done < <(grep -o 'dest=.*' "$TRACE_LOG" | sed 's/^dest=//')
  if [[ -z "$BAD_DEST" ]] && grep -q 'safe_replace dest=' "$TRACE_LOG"; then
    ok "T2: every traced write destination resolves under CACHE_DIR"
  else
    bad "T2: write destination(s) outside CACHE_DIR or no safe_replace calls traced:$BAD_DEST"
  fi
else
  bad "T2: trace log was not created at $TRACE_LOG"
fi

# ---------------------------------------------------------------------
# T3a: the BASH-level fail-closed derivation (Step 2) -- a non-executable
# prober must resolve LIVENESS_BIN to the empty string. Read straight off
# the unconditional Step-0 trace line (fires before any git/resolver
# work), so this does not depend on ACTIVE_YAML resolution succeeding.
# ---------------------------------------------------------------------
chmod 644 "$LIVENESS_COPY"
rm -f "$TRACE_LOG"
INPUT_JSON='{"workspace":{"current_dir":"'"$FIXTURE_ROOT"'"},"model":{"display_name":"test"},"context_window":{"remaining_percentage":50}}'
SETTINGS_JSON="$tmp/settings.json"
printf '{}' > "$SETTINGS_JSON"
TMPDIR="$CACHE_DIR" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" LEADV2_STATUSLINE_TRACE=1 \
  timeout 5 bash "$TAIL_SCRIPT" "$INPUT_JSON" "$SETTINGS_JSON" "$PLUGIN_DIR/scripts" "0" >/dev/null 2>&1

if [[ -f "$TRACE_LOG" ]]; then
  # cut (not awk) -- awk's default whitespace splitting collapses a genuine
  # empty field (the fail-closed "" for LIVENESS_BIN prints as two adjacent
  # spaces) into the NEXT field, silently reading LIVENESS_MEMO_FILE instead
  # and reporting a false failure.
  STEP0_LIVENESS_BIN="$(head -1 "$TRACE_LOG" | cut -d' ' -f6)"
  if [[ -z "$STEP0_LIVENESS_BIN" ]]; then
    ok "T3a: non-executable prober resolves LIVENESS_BIN to empty (fail-closed)"
  else
    bad "T3a: LIVENESS_BIN did not fail closed, resolved to: $STEP0_LIVENESS_BIN"
  fi
else
  bad "T3a: Step-0 trace line was not written at all (script may have hung/timed out)"
fi

# ---------------------------------------------------------------------
# T3b: with liveness_bin empty (unusable prober), the count sidecar must
# never be (re)written -- a stale sidecar must not masquerade as fresh.
# ---------------------------------------------------------------------
rm -f "$COUNT_SIDECAR_FILE"
run_block "$ACTIVE_YAML" "$FIXTURE_ROOT" "$CACHE_FILE" "$LIMITS_PATH" \
  "$LABEL_MEMO_FILE" "${PLUGIN_DIR}/scripts/leadv2-tasks-lib.sh" \
  "" "$LIVENESS_MEMO_FILE" "10" "$COUNT_SIDECAR_FILE" \
  "80" "0" "$CACHE_DIR" >/dev/null 2>&1
if [[ ! -f "$COUNT_SIDECAR_FILE" ]]; then
  ok "T3b: count sidecar not written when liveness_bin is empty/unusable"
else
  bad "T3b: count sidecar was written despite an empty liveness_bin: $(cat "$COUNT_SIDECAR_FILE" 2>/dev/null)"
fi
chmod 755 "$LIVENESS_COPY"

# ---------------------------------------------------------------------
# T4 (keep, static): argv positions 7/8 map to LIVENESS_BIN/LIVENESS_MEMO_FILE
# in BOTH the python unpack and the bash call site -- the argv off-by-one
# hypothesis (E5) is REFUTED; this test exists so it can never silently
# become true again via an unrelated argv-list edit.
# ---------------------------------------------------------------------
UNPACK_LINE="$(grep -n 'liveness_bin, liveness_memo_file, liveness_ttl_raw = sys.argv\[7\], sys.argv\[8\], sys.argv\[9\]' "$TAIL_SCRIPT")"
CALL_LINE="$(grep -n '"\$LIVENESS_BIN" "\$LIVENESS_MEMO_FILE" "\$LIVENESS_MEMO_TTL_S"' "$TAIL_SCRIPT")"
if [[ -n "$UNPACK_LINE" && -n "$CALL_LINE" ]]; then
  # positions 1-6 in the call are $ACTIVE_YAML $CWD_FROM_INPUT $LANE_CACHE_FILE
  # $LIMITS_YAML $LABEL_MEMO_FILE $TASKS_LIB -- so LIVENESS_BIN/MEMO_FILE land
  # at argv[7]/argv[8] as sys.argv[0] is the -c script text itself.
  BEFORE="$(printf '%s' "$CALL_LINE" | sed -E 's/"\$LIVENESS_BIN".*//')"
  ARG_COUNT="$(printf '%s' "$BEFORE" | grep -o '"\$[A-Z_]*"' | wc -l | tr -d ' ')"
  if [[ "$ARG_COUNT" == "6" ]]; then
    ok "T4: LIVENESS_BIN/LIVENESS_MEMO_FILE remain positional argv[7]/argv[8]"
  else
    bad "T4: positional argument count before LIVENESS_BIN drifted (expected 6 preceding args, found $ARG_COUNT)"
  fi
else
  bad "T4: could not locate the unpack line or the call-site line to cross-check"
fi

# ---------------------------------------------------------------------
# T5: plugin-sync should refuse to propagate a corpse (.sh under 1KB) --
# D1 (shared-tree edit to ~/.claude/scripts/leadv2-plugin-sync.sh) is
# pending founder sign-off (async question, dispatch-81443b5f). This run
# shipped the plugin-repo fix only (default option b); the guard has NOT
# been added to plugin-sync.sh yet, so this assertion is expected to stay
# RED until D1 resolves "a" and the guard lands. Recorded, not silently
# dropped.
# ---------------------------------------------------------------------
skp "T5: plugin-sync corpse-size guard -- blocked on pending D1 (shared-tree sign-off), not implemented this run"

echo "----"
echo "pass=$pass fail=$fail skip=$skip"
[[ "$fail" == "0" ]]
