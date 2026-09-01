#!/usr/bin/env bash
# test-plugin-cache-sync.sh — LEADV2-HOOK-CACHE-DEPLOY-01.
#
# Hermetic suite for leadv2-plugin-cache-sync.sh: the script must push the
# repo's plugins/leadv2 tree into the ACTIVE plugin-cache copy (the one
# Claude Code actually loads — installed_plugins.json installPath, falling
# back to the highest numeric version dir), delete stale cache-only files,
# record repo HEAD in <cache>/.synced-from, and fail closed when no cache
# dir exists. Runs entirely inside a temp tree via LEADV2_PLUGIN_CACHE_ROOT
# / LEADV2_PLUGIN_SRC / LEADV2_PLUGIN_META — never touches the live cache.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC="${SCRIPT_DIR}/../leadv2-plugin-cache-sync.sh"

pass=0
fail=0

check() { # check <got> <want-substr> <label>
  if [[ "$1" == *"$2"* ]]; then
    printf '[TEST] PASS: %s\n' "$3"; pass=$((pass+1))
  else
    printf '[TEST] FAIL: %s\n  got: %s\n  want substring: %s\n' "$3" "$1" "$2" >&2
    fail=$((fail+1))
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── Fixture: fake repo (git, so repo_head is real) + fake cache ─────────────
REPO="$tmp/repo"
mkdir -p "$REPO/plugins/leadv2/hooks/lib"
git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
printf '#!/usr/bin/env bash\n# repo v2 content\necho a\n' > "$REPO/plugins/leadv2/hooks/leadv2-a.sh"
printf '#!/usr/bin/env bash\necho kind\n' > "$REPO/plugins/leadv2/hooks/lib/leadv2-kind.sh"
printf '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo new-hook"}]}]}}\n' > "$REPO/plugins/leadv2/hooks/hooks.json"
git -C "$REPO" add -A
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m "plugin tree"
SHA="$(git -C "$REPO" rev-parse HEAD)"

CACHE_ROOT="$tmp/plugins-cache"
ACTIVE="$CACHE_ROOT/leadv2-local/leadv2/0.3.0"
mkdir -p "$ACTIVE/hooks/lib" "$ACTIVE/hooks.bak-20260902"
# Stale cache state: old content, a cache-only extra file (deleted upstream),
# and a manual backup that --delete must never touch.
printf '#!/usr/bin/env bash\n# STALE v1 content\necho a-old\n' > "$ACTIVE/hooks/leadv2-a.sh"
printf '#!/usr/bin/env bash\necho dead-supervisor-residue\n' > "$ACTIVE/hooks/leadv2-dead.sh"
printf 'keep\n' > "$ACTIVE/hooks.bak-20260902/keep.sh"
printf 'old\n' > "$ACTIVE/hooks/lib/leadv2-kind.sh"
META="$tmp/installed_plugins.json"
cat > "$META" <<EOF
{"version":2,"plugins":{"leadv2@leadv2-local":[{"scope":"user","installPath":"$ACTIVE","version":"0.3.0","installedAt":"2026-05-12T10:29:28.990Z"}]}}
EOF

run_sync() { # run_sync <cache-root> <meta>
  LEADV2_PLUGIN_CACHE_ROOT="$1" LEADV2_PLUGIN_SRC="$REPO/plugins/leadv2" \
    LEADV2_PLUGIN_META="$2" bash "$SYNC" 2>&1
}

# (d0) precondition for the hooks.json cases: the cache starts WITHOUT the
# repo's hooks.json — the exact round-1 defect state (an added hook is
# invisible to Claude Code until something copies the LIST into the cache).
check "$([[ -e "$ACTIVE/hooks/hooks.json" ]] && echo present || echo MISSING)" "MISSING" \
  "d0: fixture cache lacks hooks.json before sync (defect state)"

# ── (a) sync: diff -rq empties, marker holds the sha, output line ───────────
out="$(run_sync "$CACHE_ROOT" "$META")" && rc=0 || rc=$?
check "$out" "synced=" "a1: exit 0 and prints synced= line (rc=$rc)"
check "$out" "repo_head=$SHA" "a2: output carries the repo HEAD sha"
check "$out" "cache=$ACTIVE" "a3: output names the installed_plugins.json dir (authoritative)"
d="$(diff -rq "$REPO/plugins/leadv2" "$ACTIVE" 2>&1 | grep -v hooks.bak- | grep -v .synced-from || true)"
check "diff-empty:${d:-OK}" "diff-empty:OK" "a4: diff -rq repo vs cache is empty after sync"
check "$(cat "$ACTIVE/.synced-from" 2>/dev/null || echo MISSING)" "$SHA" "a5: .synced-from holds the sha"

# ── (d) hooks.json: cache lacked it before sync (the real-world defect —
#     an added hook / changed matcher is invisible to Claude Code until the
#     cache copy exists), sync must materialize it verbatim ─────────────────
check "$([[ -f "$ACTIVE/hooks/hooks.json" ]] && echo present || echo MISSING)" "present" \
  "d1: hooks.json present in cache after sync"
check "$(cat "$ACTIVE/hooks/hooks.json" 2>/dev/null)" "echo new-hook" \
  "d2: hooks.json content matches repo (new hook entry synced)"

# ── (b) stale cache-only file removed; backup preserved ─────────────────────
if [[ ! -e "$ACTIVE/hooks/leadv2-dead.sh" ]]; then
  printf '[TEST] PASS: b1: stale cache-only hook deleted (--delete)\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: b1: stale cache-only hook survived --delete: %s\n' "$ACTIVE/hooks/leadv2-dead.sh" >&2
  fail=$((fail+1))
fi
if [[ "$(cat "$ACTIVE/hooks.bak-20260902/keep.sh" 2>/dev/null)" == "keep" ]]; then
  printf '[TEST] PASS: b2: hooks.bak-* backup survives --delete\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: b2: hooks.bak-* backup was destroyed\n' >&2
  fail=$((fail+1))
fi

# ── (b3) idempotent: second run is a no-op, marker intact ───────────────────
out2="$(run_sync "$CACHE_ROOT" "$META")" && rc2=0 || rc2=$?
check "$out2" "synced=0 cache=" "b3: second run synced=0 (idempotent), rc=$rc2"
check "$(cat "$ACTIVE/.synced-from" 2>/dev/null || echo MISSING)" "$SHA" "b4: .synced-from survives the second run"

# ── (c) no cache dir anywhere → non-zero exit with the message ──────────────
out3="$(run_sync "$tmp/no-such-cache" "$tmp/no-such-meta.json")" && rc3=0 || rc3=$?
check "rc=$rc3" "rc=1" "c1: missing cache exits non-zero"
check "$out3" "BLOCK: no leadv2 plugin cache dir found" "c2: stderr names the miss"

# ── (d) fallback without installed_plugins.json: highest NUMERIC version ────
mkdir -p "$CACHE_ROOT/leadv2-local/leadv2/0.9.0/hooks" "$CACHE_ROOT/leadv2-local/leadv2/0.10.0/hooks"
out4="$(run_sync "$CACHE_ROOT" "$tmp/no-such-meta.json")"
check "$out4" "cache=$CACHE_ROOT/leadv2-local/leadv2/0.10.0" \
  "d1: no meta json → picks 0.10.0 over 0.9.0 (numeric, not string, sort)"
check "$(cat "$CACHE_ROOT/leadv2-local/leadv2/0.10.0/.synced-from" 2>/dev/null || echo MISSING)" "$SHA" \
  "d2: fallback dir got the .synced-from marker"

printf '\n[TEST] %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
