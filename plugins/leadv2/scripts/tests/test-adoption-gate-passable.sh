#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-repo-install.sh
# test-adoption-gate-passable.sh — ADOPTION-GUARANTEES-A-PASSABLE-GATE-01.
#
# Guarantees that leadv2-repo-install.sh leaves EVERY adopted repo's phase gate
# honestly passable, not just the repos someone hand-patched (leadv2 6f6b55b,
# persona-engine 833e4926e on 2026-08-31 — the hand-fix is the defect).
#
# The gate (leadv2-phase-record.sh) and the dispatcher (leadv2-dispatch-code.sh)
# accept only COMMITTED artifacts: docs/handoff/dispatch-<sig8>/{context.yaml,
# architect-prepass.md,.gate1-passed} plus the lead-authored plan notes
# docs/handoff/<task>/{brief.md,fix-round-N.md}. A lane worktree contains only
# what is committed, so a .gitignore that blankets docs/handoff makes an honest
# gate passage physically impossible and trains the lead to bypass the gate.
#
# The ONLY oracle used here is `git check-ignore` on concrete paths — never a
# grep of .gitignore: only git knows which of layered rules wins, and a
# negation that is present but overridden must read as BROKEN, not fixed.
#
# Fixtures only — never a real repo, never the real ~/.claude: canonical
# scripts/agents point at empty dirs, the state base at $TMP, and a scoped
# GIT_CONFIG_GLOBAL keeps the host's global excludes out of the fixture.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL="${SCRIPT_DIR}/../leadv2-repo-install.sh"
if [ ! -f "$INSTALL" ]; then
  printf 'FAIL: production script missing: %s\n' "$INSTALL" >&2
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/adopt-gate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/gitconfig"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
export LEADV2_CANONICAL_SCRIPTS="$TMP/canon-scripts"
export LEADV2_SHARED_AGENTS="$TMP/canon-agents"
export LEADV2_STATE_BASE="$TMP/state"
mkdir -p "$TMP/canon-scripts" "$TMP/canon-agents" "$TMP/state"

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

# The guarded shapes, in both id spellings the gate sees (dispatch-<sig8> and a
# plain task id). brief.md / fix-round-N.md are the round-N briefs the
# dispatcher reads and phase-record accepts as an attested plan.
SAMPLES='docs/handoff/dispatch-1d76cf8a/context.yaml
docs/handoff/dispatch-1d76cf8a/architect-prepass.md
docs/handoff/dispatch-1d76cf8a/.gate1-passed
docs/handoff/some-task/brief.md
docs/handoff/some-task/fix-round-2.md'

all_committable() { # <repo> — rc 0 iff NO guarded shape is ignored
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if git -C "$1" check-ignore -q "$p" 2>/dev/null; then return 1; fi
  done <<EOF
${SAMPLES}
EOF
  return 0
}

assert_all_committable(){ # <repo> <label>
  if all_committable "$1"; then
    pass "$2"
  else
    fail "$2 (git check-ignore still ignores a guarded path)"
  fi
}

mk_repo() { # <name> <gitignore-source-or-empty> — prints repo path
  local r="$TMP/$1"
  mkdir -p "$r/docs/handoff"
  git -C "$r" init -q >/dev/null 2>&1
  git -C "$r" config user.email fixture@leadv2.local
  git -C "$r" config user.name fixture
  if [ -n "${2:-}" ]; then cp "$2" "$r/.gitignore"; fi
  printf '%s' "$r"
}

run_install() { # <repo> [flags...] — captures out/err in $TMP/last.{out,err}, echoes rc
  local repo="$1"; shift
  bash "$INSTALL" "$@" "$repo" >"$TMP/last.out" 2>"$TMP/last.err"
  printf '%s' "$?"
}

assert_rc(){ # <want: 0|nonzero> <rc> <label>
  if [ "$1" = "0" ]; then
    if [ "$2" -eq 0 ]; then pass "$3"; else fail "$3 (rc=$2)"; fi
  else
    if [ "$2" -ne 0 ]; then pass "$3"; else fail "$3 (expected nonzero rc, got 0)"; fi
  fi
}

# ── fixture ignore shapes ────────────────────────────────────────────────────
printf '%s\n' '# repo rules' '*.log' 'docs/handoff/*/*' 'node_modules/' > "$TMP/gi-star"
printf '%s\n' '*.log' 'docs/handoff/dispatch-*/*' 'node_modules/' > "$TMP/gi-dispatch"
printf '%s\n' 'docs/' > "$TMP/gi-unfixable"

# ═══ 1. blanket docs/handoff/*/* (the shape that burned 2026-08-31) ══════════
r1="$(mk_repo fix-star "$TMP/gi-star")"
if git -C "$r1" check-ignore -q docs/handoff/dispatch-1d76cf8a/context.yaml 2>/dev/null; then
  pass "fixture sanity: blanket */* repo starts with the gate artifact ignored"
else
  fail "fixture sanity: blanket */* repo does not exercise the defect"
fi
rc="$(run_install "$r1")"
assert_rc 0 "$rc" "blanket */*: adoption exits 0"
assert_all_committable "$r1" "blanket */*: all gate artifacts committable after adoption"

# round-N briefs, explicitly (acceptance #7)
brief_ok=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in */brief.md|*/fix-round-2.md) git -C "$r1" check-ignore -q "$p" 2>/dev/null || brief_ok=$((brief_ok+1)) ;; esac
done <<EOF
${SAMPLES}
EOF
if [ "$brief_ok" -eq 2 ]; then
  pass "blanket */*: round-N brief paths (brief.md, fix-round-2.md) committable"
else
  fail "blanket */*: round-N brief paths still ignored (${brief_ok}/2 committable)"
fi

# ═══ 2. blanket docs/handoff/dispatch-*/* (persona-engine's shape) ═══════════
r2="$(mk_repo fix-dispatch "$TMP/gi-dispatch")"
rc="$(run_install "$r2")"
assert_rc 0 "$rc" "blanket dispatch-*: adoption exits 0"
assert_all_committable "$r2" "blanket dispatch-*: all gate artifacts committable after adoption"

# ═══ 3. already-correct repo ⇒ adoption changes nothing, prints nothing ══════
r3="$(mk_repo fix-already "")"
run_install "$r3" >/dev/null 2>&1   # first heal converges it
cp -R "$r3" "$TMP/r3-before"
rc="$(run_install "$r3" --quiet)"
assert_rc 0 "$rc" "already-correct: re-adoption exits 0"
if [ ! -s "$TMP/last.out" ] && [ ! -s "$TMP/last.err" ]; then
  pass "already-correct: re-adoption prints nothing (--quiet)"
else
  fail "already-correct: re-adoption printed output (out=$(wc -c < "$TMP/last.out" | tr -d ' ')B err=$(wc -c < "$TMP/last.err" | tr -d ' ')B)"
fi
if diff -r "$TMP/r3-before" "$r3" >/dev/null 2>&1; then
  pass "already-correct: re-adoption changed no byte"
else
  fail "already-correct: re-adoption mutated the repo"
fi

# ═══ 4. running adoption twice ⇒ no duplicate lines ══════════════════════════
gi1="$r1/.gitignore"
md5_1="$(md5 -q "$gi1" 2>/dev/null || md5sum < "$gi1")"
rc="$(run_install "$r1")"
md5_2="$(md5 -q "$gi1" 2>/dev/null || md5sum < "$gi1")"
assert_rc 0 "$rc" "second adoption exits 0"
if [ "$md5_1" = "$md5_2" ]; then
  pass "idempotency: second adoption left .gitignore byte-identical"
else
  fail "idempotency: second adoption rewrote .gitignore"
fi
marker_count="$(grep -c 'phase-gate artifacts' "$gi1" 2>/dev/null || true)"
if [ "$marker_count" = "1" ]; then
  pass "idempotency: exactly one guarantee block (no duplicates)"
else
  fail "idempotency: guarantee block appears ${marker_count} times"
fi

# ═══ 5. unrelated .gitignore lines survive byte-identically ══════════════════
if head -4 "$gi1" | diff - "$TMP/gi-star" >/dev/null 2>&1; then
  pass "additive: original 4 .gitignore lines survive byte-identically and first"
else
  fail "additive: original .gitignore lines were rewritten/reordered/removed"
fi
grep -Fqx '*.log' "$gi1" && grep -Fqx 'node_modules/' "$gi1" \
  && pass "additive: unrelated rules (*.log, node_modules/) still present" \
  || fail "additive: unrelated rules lost"

# ═══ 6. unfixable repo ⇒ loud explicit failure ═══════════════════════════════
r6="$(mk_repo fix-unfixable "$TMP/gi-unfixable")"   # `docs/` excludes the parent dir — no negation can re-include
rc="$(run_install "$r6")"
assert_rc nonzero "$rc" "unfixable (docs/ parent-dir exclusion): heal exits nonzero"
if grep -q 'UNFIXABLE' "$TMP/last.out" "$TMP/last.err" 2>/dev/null; then
  pass "unfixable: failure is loud and explicit (UNFIXABLE reported)"
else
  fail "unfixable: no UNFIXABLE report in output"
fi
rc="$(run_install "$r6" --check)"
assert_rc nonzero "$rc" "unfixable: --check also exits nonzero"

# ═══ summary — exit code follows the failures ════════════════════════════════
printf 'adoption-gate-passable: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
