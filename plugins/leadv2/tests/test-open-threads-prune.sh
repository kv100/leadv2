#!/usr/bin/env bash
# tests/test-open-threads-prune.sh — OPEN-THREADS-HYGIENE-01 smoke tests.
#
# Covers:
#   (1) leadv2-thread-prune.sh list / resolve / prune against a sandbox
#       open-threads.md — resolve removes the matching entry and leaves
#       everything else untouched; prune strips stray "- [x] " lines.
#   (2) leadv2-task-anchor.sh's capture_ask() self-strips "- [x] " lines on
#       every write (belt-and-braces pruning, independent of #1's resolve
#       path).
#   (3) pre-compact-task-freeze.sh, run against a small (already-pruned)
#       open-threads.md, emits a bounded OPEN THREADS section that points at
#       supervisor-role.md instead of embedding a stale role/status block.
#
# Usage: bash tests/test-open-threads-prune.sh
# Exit 0 = all pass; non-zero = failure count.
set -euo pipefail

HOOKS_DIR="${BASH_SOURCE[0]%/*}/../hooks"
SCRIPTS_DIR="${BASH_SOURCE[0]%/*}/../scripts"
PRUNE_SCRIPT="${SCRIPTS_DIR}/leadv2-thread-prune.sh"
TASK_ANCHOR="${HOOKS_DIR}/leadv2-task-anchor.sh"
FREEZE_HOOK="${HOOKS_DIR}/pre-compact-task-freeze.sh"

PASS=0
FAIL=0
pass() { printf -- 'PASS: %s\n' "$1"; PASS=$(( PASS + 1 )); }
fail() { printf -- 'FAIL: %s\n' "$1"; FAIL=$(( FAIL + 1 )); }

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ---------------------------------------------------------------------------
# Sandbox project: leadv2_dir=docs/leadv2, a small open-threads.md with 3
# open entries plus one already-resolved "- [x] " line (simulating a
# hand-checked box).
# ---------------------------------------------------------------------------
PROJ="${TMPDIR_BASE}/proj"
mkdir -p "${PROJ}/docs/leadv2" "${PROJ}/.claude/leadv2-overrides"
git -C "$PROJ" init -q
git -C "$PROJ" config user.email test@test.local
git -C "$PROJ" config user.name test

cat > "${PROJ}/docs/leadv2/open-threads.md" <<'MD'
# Open threads — sandbox

## Captured asks (auto)
- [ ] 2026-07-28T10:00:00Z — question one still awaiting an answer
- [x] 2026-07-28T10:05:00Z — already resolved, should never linger
- [ ] 2026-07-28T10:10:00Z — question two also still open
- [ ] 2026-08-04T09:00:00Z [s:aaaaaaaa] — alpha tagged ask from session A
- [ ] 2026-08-04T09:01:00Z [s:bbbbbbbb] — beta tagged ask from session B
MD

# ---------------------------------------------------------------------------
# (1) list shows only the two unresolved entries
# ---------------------------------------------------------------------------
LIST_OUT="$(cd "$PROJ" && bash "$PRUNE_SCRIPT" list)"
if printf '%s\n' "$LIST_OUT" | grep -q "question one" \
  && printf '%s\n' "$LIST_OUT" | grep -q "question two" \
  && ! printf '%s\n' "$LIST_OUT" | grep -q "already resolved"; then
  pass "(1) list shows only unresolved '- [ ] ' entries"
else
  fail "(1) list output wrong: ${LIST_OUT}"
fi

# ---------------------------------------------------------------------------
# (2) resolve removes the matching entry and leaves the other open entry
# ---------------------------------------------------------------------------
RESOLVE_OUT="$(cd "$PROJ" && bash "$PRUNE_SCRIPT" resolve "question one" 2>&1)"
AFTER_RESOLVE="$(cat "${PROJ}/docs/leadv2/open-threads.md")"
if printf '%s\n' "$RESOLVE_OUT" | grep -q "removed 1 entry" \
  && ! printf '%s\n' "$AFTER_RESOLVE" | grep -q "question one" \
  && printf '%s\n' "$AFTER_RESOLVE" | grep -q "question two"; then
  pass "(2) resolve removes the matched entry, keeps the other open entry"
else
  fail "(2) resolve did not prune correctly (out=${RESOLVE_OUT})"
fi

# ---------------------------------------------------------------------------
# (3) resolving a non-matching substring exits non-zero and changes nothing
# ---------------------------------------------------------------------------
BEFORE_NOMATCH="$(cat "${PROJ}/docs/leadv2/open-threads.md")"
set +e
(cd "$PROJ" && bash "$PRUNE_SCRIPT" resolve "no such text anywhere" >/dev/null 2>&1)
NOMATCH_RC=$?
set -e
AFTER_NOMATCH="$(cat "${PROJ}/docs/leadv2/open-threads.md")"
if [[ "$NOMATCH_RC" -ne 0 && "$BEFORE_NOMATCH" == "$AFTER_NOMATCH" ]]; then
  pass "(3) resolve on a non-matching substring exits non-zero, file unchanged"
else
  fail "(3) expected non-zero exit and no file change (rc=$NOMATCH_RC)"
fi

# ---------------------------------------------------------------------------
# (4) prune strips every residual "- [x] " line defensively — the fixture
#     already carries the original "already resolved" box (never touched by
#     `resolve`, which only ever matches unresolved "- [ ] " lines) plus a
#     freshly reintroduced one, so a correct prune removes BOTH.
# ---------------------------------------------------------------------------
printf -- '- [x] 2026-07-28T11:00:00Z — stray checked box from a hand edit\n' >> "${PROJ}/docs/leadv2/open-threads.md"
PRUNE_OUT="$(cd "$PROJ" && bash "$PRUNE_SCRIPT" prune)"
AFTER_PRUNE="$(cat "${PROJ}/docs/leadv2/open-threads.md")"
if printf '%s\n' "$PRUNE_OUT" | grep -q "pruned 2 resolved" \
  && ! printf '%s\n' "$AFTER_PRUNE" | grep -q "stray checked box" \
  && ! printf '%s\n' "$AFTER_PRUNE" | grep -q "already resolved"; then
  pass "(4) prune strips every stray '- [x] ' line"
else
  fail "(4) prune did not strip stray resolved lines (out=${PRUNE_OUT})"
fi

# ---------------------------------------------------------------------------
# (5) capture_ask (leadv2-task-anchor.sh, invoked via UserPromptSubmit
#     payload) self-strips any "- [x] " line on every write, independent of
#     the prune script above.
# ---------------------------------------------------------------------------
printf -- '- [x] 2026-07-28T12:00:00Z — another stray checked box\n' >> "${PROJ}/docs/leadv2/open-threads.md"
LONG_PROMPT="this is a brand new founder ask that is long enough to be captured by the hook heuristic"
PAYLOAD_JSON=$(python3 -c "import json,sys; print(json.dumps({'cwd': sys.argv[1], 'prompt': sys.argv[2], 'session_id': 'test-session'}))" "$PROJ" "$LONG_PROMPT")
printf '%s' "$PAYLOAD_JSON" | bash "$TASK_ANCHOR" >/dev/null 2>&1 || true
AFTER_CAPTURE="$(cat "${PROJ}/docs/leadv2/open-threads.md")"
if printf '%s\n' "$AFTER_CAPTURE" | grep -q "brand new founder ask" \
  && ! printf '%s\n' "$AFTER_CAPTURE" | grep -q "another stray checked box"; then
  pass "(5) capture_ask appends the new ask AND self-strips the stray '- [x] ' line"
else
  fail "(5) capture_ask did not behave as expected:"$'\n'"${AFTER_CAPTURE}"
fi

# ---------------------------------------------------------------------------
# (6) pre-compact-task-freeze.sh dry-run: against the now-small, clean
#     open-threads.md, stdout carries the OPEN THREADS section pointing at
#     supervisor-role.md, NOT a giant embedded role/status block.
# ---------------------------------------------------------------------------
INPUT_JSON=$(python3 -c "import json,sys; print(json.dumps({'cwd': sys.argv[1]}))" "$PROJ")
FREEZE_OUT="$(CLAUDE_PLUGIN_ROOT="/fake/plugin/root" bash -c "printf '%s' '$INPUT_JSON' | bash '$FREEZE_HOOK'")"
if printf '%s\n' "$FREEZE_OUT" | grep -q "OPEN THREADS" \
  && printf '%s\n' "$FREEZE_OUT" | grep -q "supervisor-role.md" \
  && printf '%s\n' "$FREEZE_OUT" | grep -q "question two"; then
  pass "(6) pre-compact freeze dry-run points at supervisor-role.md and carries the open item"
else
  fail "(6) freeze dry-run missing expected content:"$'\n'"${FREEZE_OUT}"
fi

# ---------------------------------------------------------------------------
# (7) OT-SESSION-SCOPE-01: capture_ask tags the entry [s:<sid8>] when a
#     session_id is present, and falls back to the legacy untagged form when
#     one is absent. (sid8 = first 8 chars of the sanitized session_id.)
# ---------------------------------------------------------------------------
PROJ_TAG="${TMPDIR_BASE}/proj_tag"
mkdir -p "${PROJ_TAG}/docs/leadv2" "${PROJ_TAG}/.claude/leadv2-overrides"
git -C "$PROJ_TAG" init -q
git -C "$PROJ_TAG" config user.email test@test.local
git -C "$PROJ_TAG" config user.name test
printf -- '## Captured asks (auto)\n- [ ] 2026-08-04T08:00:00Z — pre-existing legacy ask\n' \
  > "${PROJ_TAG}/docs/leadv2/open-threads.md"
TAG_PROMPT="this is a tagged founder ask that is long enough to pass the heuristic"
TAG_PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'cwd': sys.argv[1], 'prompt': sys.argv[2], 'session_id': '2385b583-62e9-403e-a9c7-b7aa99638c67'}))" "$PROJ_TAG" "$TAG_PROMPT")
printf '%s' "$TAG_PAYLOAD" | bash "$TASK_ANCHOR" >/dev/null 2>&1 || true
TAG_FILE="$(cat "${PROJ_TAG}/docs/leadv2/open-threads.md")"
if printf '%s\n' "$TAG_FILE" | grep -Eq '^- \[ \] .* \[s:2385b583\] — '; then
  pass "(7) capture_ask tags the entry with [s:2385b583]"
else
  fail "(7) capture_ask did not tag the entry:"$'\n'"${TAG_FILE}"
fi

# untagged fallback: no session_id -> legacy form (no [s:)
PROJ_UNTAG="${TMPDIR_BASE}/proj_untag"
mkdir -p "${PROJ_UNTAG}/docs/leadv2" "${PROJ_UNTAG}/.claude/leadv2-overrides"
git -C "$PROJ_UNTAG" init -q
git -C "$PROJ_UNTAG" config user.email test@test.local
git -C "$PROJ_UNTAG" config user.name test
printf -- '## Captured asks (auto)\n' > "${PROJ_UNTAG}/docs/leadv2/open-threads.md"
UNTAG_PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'cwd': sys.argv[1], 'prompt': sys.argv[2]}))" "$PROJ_UNTAG" "$TAG_PROMPT")
printf '%s' "$UNTAG_PAYLOAD" | bash "$TASK_ANCHOR" >/dev/null 2>&1 || true
UNTAG_FILE="$(cat "${PROJ_UNTAG}/docs/leadv2/open-threads.md")"
if printf '%s\n' "$UNTAG_FILE" | grep -Eq '^- \[ \] .* — ' \
  && ! printf '%s\n' "$UNTAG_FILE" | grep -q '\[s:'; then
  pass "(7b) capture_ask with no session_id emits the legacy untagged form"
else
  fail "(7b) untagged fallback wrong:"$'\n'"${UNTAG_FILE}"
fi

# ---------------------------------------------------------------------------
# (8) OT-SESSION-SCOPE-01: leadv2-thread-prune.sh list/resolve are
#     format-agnostic — they key on the "- [ ] " prefix + a free-text
#     substring, never on the [s:...] tag. list prints all three shapes;
#     resolve removes exactly the matched tagged entry and leaves the
#     untagged one.
# ---------------------------------------------------------------------------
PROJ_PF="${TMPDIR_BASE}/proj_prune_fmt"
mkdir -p "${PROJ_PF}/docs/leadv2" "${PROJ_PF}/.claude/leadv2-overrides"
git -C "$PROJ_PF" init -q
git -C "$PROJ_PF" config user.email test@test.local
git -C "$PROJ_PF" config user.name test
cat > "${PROJ_PF}/docs/leadv2/open-threads.md" <<'MD'
## Captured asks (auto)
- [ ] 2026-08-04T09:00:00Z — legacy untagged open thread
- [ ] 2026-08-04T09:01:00Z [s:aaaaaaaa] — alpha tagged thread
- [ ] 2026-08-04T09:02:00Z [s:bbbbbbbb] — beta tagged thread
MD
LIST_FMT="$(cd "$PROJ_PF" && bash "$PRUNE_SCRIPT" list)"
if printf '%s\n' "$LIST_FMT" | grep -q "legacy untagged" \
  && printf '%s\n' "$LIST_FMT" | grep -q "alpha tagged" \
  && printf '%s\n' "$LIST_FMT" | grep -q "beta tagged"; then
  pass "(8a) list prints all three entry shapes (legacy + tagged)"
else
  fail "(8a) list did not show all shapes:"$'\n'"${LIST_FMT}"
fi
RES_FMT="$(cd "$PROJ_PF" && bash "$PRUNE_SCRIPT" resolve "alpha tagged" 2>&1)"
AFTER_FMT="$(cat "${PROJ_PF}/docs/leadv2/open-threads.md")"
if printf '%s\n' "$RES_FMT" | grep -q "removed 1 entry" \
  && ! printf '%s\n' "$AFTER_FMT" | grep -q "alpha tagged" \
  && printf '%s\n' "$AFTER_FMT" | grep -q "legacy untagged"; then
  pass "(8b) resolve removes the tagged entry, leaves the untagged one"
else
  fail "(8b) resolve was not format-agnostic:"$'\n'"${AFTER_FMT}"
fi

# ---------------------------------------------------------------------------
# (9) OT-SESSION-SCOPE-01 (CRITICAL guard): dedupe survives the _ENTRY_RE
#     group renumber — firing the SAME prompt twice in one session appends
#     exactly ONE entry. If group(2)/group(3) were crossed, the dedupe key
#     would compare session ids and every ask would re-capture forever.
# ---------------------------------------------------------------------------
PROJ_DD="${TMPDIR_BASE}/proj_dedupe"
mkdir -p "${PROJ_DD}/docs/leadv2" "${PROJ_DD}/.claude/leadv2-overrides"
git -C "$PROJ_DD" init -q
git -C "$PROJ_DD" config user.email test@test.local
git -C "$PROJ_DD" config user.name test
printf -- '## Captured asks (auto)\n' > "${PROJ_DD}/docs/leadv2/open-threads.md"
DD_PROMPT="repeat this exact founder ask to verify dedupe keeps only one copy"
DD_PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'cwd': sys.argv[1], 'prompt': sys.argv[2], 'session_id': 'dedupe-sess'}))" "$PROJ_DD" "$DD_PROMPT")
printf '%s' "$DD_PAYLOAD" | bash "$TASK_ANCHOR" >/dev/null 2>&1 || true
printf '%s' "$DD_PAYLOAD" | bash "$TASK_ANCHOR" >/dev/null 2>&1 || true
DD_FILE="$(cat "${PROJ_DD}/docs/leadv2/open-threads.md")"
DD_COUNT="$(printf '%s\n' "$DD_FILE" | grep -c 'verify dedupe keeps only one copy')"
if [[ "$DD_COUNT" -eq 1 ]]; then
  pass "(9) dedupe survives the group renumber — one entry after two identical fires"
else
  fail "(9) expected exactly 1 entry, got ${DD_COUNT}:"$'\n'"${DD_FILE}"
fi

# ---------------------------------------------------------------------------
# (10) OT-SESSION-SCOPE-01 (mandatory): one open-threads.md holds A-tagged +
#      B-tagged + one untagged legacy line. The task-anchor hook run with
#      session A shows the untagged line and A's line, hides B's, and reports
#      the hidden count. (No session_id passed to anchor = unscoped legacy
#      view — covered implicitly by every prior case.)
# ---------------------------------------------------------------------------
PROJ_ISO="${TMPDIR_BASE}/proj_iso"
mkdir -p "${PROJ_ISO}/docs/leadv2" "${PROJ_ISO}/.claude/leadv2-overrides"
git -C "$PROJ_ISO" init -q
git -C "$PROJ_ISO" config user.email test@test.local
git -C "$PROJ_ISO" config user.name test
cat > "${PROJ_ISO}/docs/leadv2/open-threads.md" <<'MD'
## Captured asks (auto)
- [ ] 2026-08-04T10:00:00Z — legacy untagged visible to everyone
- [ ] 2026-08-04T10:01:00Z [s:aaaaaaaa] — alpha only visible to session A
- [ ] 2026-08-04T10:02:00Z [s:bbbbbbbb] — beta only visible to session B
MD
# prompt starts with '[' -> rejected by looks_like_new_ask -> no capture
# side-effect on the file; the thread anchor still builds (no active task).
ISO_PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'cwd': sys.argv[1], 'prompt': sys.argv[2], 'session_id': 'aaaaaaaa-1111-2222-3333-444455556666'}))" "$PROJ_ISO" "[anchor isolation probe message]")
ISO_OUT="$(printf '%s' "$ISO_PAYLOAD" | bash "$TASK_ANCHOR" 2>/dev/null || true)"
if printf '%s\n' "$ISO_OUT" | grep -q "legacy untagged visible to everyone" \
  && printf '%s\n' "$ISO_OUT" | grep -q "alpha only visible to session A" \
  && ! printf '%s\n' "$ISO_OUT" | grep -q "beta only visible to session B" \
  && printf '%s\n' "$ISO_OUT" | grep -q "thread(s) from other sessions hidden"; then
  pass "(10) session A anchor shows untagged + A, hides B, reports hidden count"
else
  fail "(10) anchor isolation failed:"$'\n'"${ISO_OUT}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
