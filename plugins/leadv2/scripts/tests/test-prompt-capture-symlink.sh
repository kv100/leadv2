#!/usr/bin/env bash
# tests/test-prompt-capture-symlink.sh — PROMPT-CAPTURE-HOOK-DESTROYS-THE-SHARED-JOURNAL-01.
#
# The UserPromptSubmit hook leadv2-task-anchor.sh appends the submitted prompt to
# docs/leadv2/open-threads.md. In every real checkout that path is a SYMLINK into
# the shared live control plane (~/.claude/leadv2-state/<repo>/), so the write
# reaches every session. Before this fix the hook did
# `os.replace(tmp, ot_path)`, which does not follow a symlink: it replaced the
# LINK, forking the checkout silently -- other sessions kept writing the shared
# file, this one wrote a private copy, and both saw a self-consistent picture.
#
# Cases:
#   T1 — a founder-shaped prompt is captured AND the path is still a symlink
#        afterwards, AND the shared target (not a local copy) received the row.
#   T2 — a model-facing role preamble ("You are estimating the shape of ...",
#        two of which were found in the founder-ask journal on 2026-09-04) is
#        NOT captured. The journal has capture without closing, so anything
#        admitted stays for good.
#   T3 — declared negative control: replacing os.path.realpath(ot_path) with
#        ot_path inside the shipped hook must make T1's symlink assertion go
#        red, then restore and recover.
#
# Run: bash plugins/leadv2/scripts/tests/test-prompt-capture-symlink.sh
# Exit 0 = all pass.
set -uo pipefail
_src="${BASH_SOURCE[0]:-}"
if [[ -z "$_src" && -f "${0:-}" ]]; then _src="$0"; fi
SCRIPT_DIR="$(cd "$(dirname "$_src")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/leadv2-task-anchor.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

[[ -r "$HOOK" ]] || { printf 'FAIL: hook not readable at %s\n' "$HOOK" >&2; exit 2; }

# /private/tmp, never /tmp: on macOS /tmp is a symlink to /private/tmp and
# run-all.sh's root_escape guard aborts a run whose tree resolves through it --
# the abort then reads as a verdict about the code under test.
TMP="$(mktemp -d /private/tmp/lv2-pcs.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"; SHARED="$TMP/shared"
mkdir -p "$REPO/docs/leadv2" "$SHARED"
printf '# Open threads\n\n## Captured asks (auto)\n' > "$SHARED/open-threads.md"
relink() { rm -f "$REPO/docs/leadv2/open-threads.md"; ln -s "$SHARED/open-threads.md" "$REPO/docs/leadv2/open-threads.md"; }
relink

run_hook() { # <prompt>
  python3 -c 'import json,sys; sys.stdout.write(json.dumps({"prompt": sys.argv[1], "session_id": "pcs00001", "cwd": sys.argv[2]}))' \
    "$1" "$REPO" \
    | ( cd "$REPO" && CLAUDE_PROJECT_DIR="$REPO" LEADV2_PROJECT_ROOT="$REPO" \
        bash "$HOOK" >/dev/null 2>&1 )
}
rows() { grep -c '^- \[ \] ' "$SHARED/open-threads.md" 2>/dev/null || echo 0; }

ASK='а можешь глянуть, почему очередь слияний стоит вторые сутки и никто не жалуется'
PREAMBLE='You are estimating the shape of a single engineering task — not choosing who or what will carry it out. Read the TASK DESCRIPTION below and answer.'

# ── T1 ─────────────────────────────────────────────────────────────────────
run_hook "$ASK"
sym_ok=0; [[ -L "$REPO/docs/leadv2/open-threads.md" ]] && sym_ok=1
in_shared=0; grep -qF "${ASK:0:40}" "$SHARED/open-threads.md" && in_shared=1
if [[ "$sym_ok" -eq 1 && "$in_shared" -eq 1 ]]; then
  pass "T1: founder-shaped prompt reached the SHARED target and the path is still a symlink"
else
  fail "T1: symlink=${sym_ok} row_in_shared=${in_shared} (expected 1/1) -- symlink=0 means the link was replaced by a real file, i.e. this checkout forked"
fi

# ── T2 ─────────────────────────────────────────────────────────────────────
before="$(rows)"
run_hook "$PREAMBLE"
after="$(rows)"
if [[ "$after" -eq "$before" ]]; then
  pass "T2: role-preamble prompt not captured (rows stayed ${before})"
else
  fail "T2: role preamble was captured -- rows ${before} -> ${after}; capture without closing means anything admitted stays for good"
fi

# Each T3 prompt must differ from T1's in its FIRST 60 characters: capture_ask
# dedupes on single_line[:60], so a near-copy is silently dropped and the control
# then "passes" by never writing at all. That is how the first run of this suite
# reported T3 green while nothing had been written.
# ── T3: declared negative control ──────────────────────────────────────────
ORIG="$TMP/hook.orig"; cp "$HOOK" "$ORIG"
if grep -qF 'target = os.path.realpath(ot_path)' "$HOOK"; then
  python3 -c 'import sys; p=sys.argv[1]; s=open(p).read(); open(p,"w").write(s.replace("target = os.path.realpath(ot_path)","target = ot_path",1))' "$HOOK"
  if cmp -s "$HOOK" "$ORIG"; then
    fail "T3: mutant is byte-identical to the original -- the anchor stopped matching, so this control proves nothing"
  else
    relink
    run_hook "контрольный прогон: слетает ли ссылка, если убрать разрешение пути перед переименованием"
    if [[ -L "$REPO/docs/leadv2/open-threads.md" ]]; then
      fail "T3: with realpath removed the symlink SURVIVED -- T1's assertion cannot go red, so it is not evidence"
    else
      pass "T3 (negative control): realpath removed -> the symlink was replaced by a real file, exactly what T1 asserts against"
    fi
    cp "$ORIG" "$HOOK"
    relink
    run_hook "после восстановления: ссылка обязана пережить запись, проверяем третьей несовпадающей репликой"
    if [[ -L "$REPO/docs/leadv2/open-threads.md" ]]; then
      pass "T3: restored -- the symlink survives again, so the control was reversible"
    else
      fail "T3: after restoring the hook the symlink was still replaced -- restoration did not recover behaviour"
    fi
  fi
  cp "$ORIG" "$HOOK"
else
  fail "T3: 'target = os.path.realpath(ot_path)' not found in the hook -- the fix is not present"
fi

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
