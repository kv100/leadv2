#!/usr/bin/env bash
# SOFT-FINISH-DEAD-RETURN-01 — falsifying harness.
#
# claude-subsession.sh's WAIT-path completion check runs at the TOP LEVEL of the
# script (not inside any function -- confirmed: no enclosing `foo() {` wraps the
# `if [[ "$WAIT" == "1" ]]` block). Its SOFT_FINISH fallback used a bare
# `return 0` to report success after auto-promoting a marker-less .full.md --
# `return` outside a function/sourced script is a bash usage error
# ("return: can only `return' from a function or sourced script"); execution
# fell through past it into the truncation/refusal/exit-1 checks below, so a
# worker whose .full.md content qualified for SOFT_FINISH (>200 bytes,
# matches fixed|added|changed|implemented|diff|##) and already had its
# .summary.md on disk was still declared failed (exit 1) even though the
# script printed "auto-promoting" and appended the marker.
#
# Related to V3-DISPATCHER-ACCEPTANCE-01 Fault 1 (PREPASS-RC1-RACE-01): the
# grace-recheck (9a512a2) covers the race where files land a beat late: it
# does NOT cover this dead-return path, which fires only after the grace
# window is exhausted and the primary/legacy checks both miss.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUB="${SCRIPT_DIR}/claude-subsession.sh"
PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

d="$(mktemp -d)"
repo="${d}/repo"
mkdir -p "${repo}/.claude/agents" "${repo}/docs/handoff"
( cd "${repo}" && git init -q )
printf 'role: architect\n' > "${repo}/.claude/agents/architect.md"

# Fake `claude` CLI on PATH: writes a SOFT_FINISH-shaped deliverable (substantive
# content, matching the promote regex, NO literal DELIVERABLE_COMPLETE) plus an
# already-present .summary.md, then exits 0 with no stream-json result line
# (so _detect_truncation never fires). Writes to the ABSOLUTE handoff dir the
# real `claude` CLI is told about via the "Deliverable full: <path>" line in
# its prompt (last positional arg after -p) -- matching the real invocation
# contract (no --task-id flag is ever passed to `claude`, see PER_TASK_BOILERPLATE).
bindir="${d}/bin"; mkdir -p "${bindir}"
cat > "${bindir}/claude" <<'EOF'
#!/usr/bin/env bash
prompt=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) prompt="$2"; shift 2 ;;
    *) shift ;;
  esac
done
full="$(printf '%s\n' "${prompt}" | sed -n 's/^- Deliverable full: *\(.*\.full\.md\).*/\1/p' | head -1)"
hdir="$(dirname "${full}")"
mkdir -p "${hdir}"
cat > "${full}" <<'BODY'
## Changes
Fixed the thing, added the file, implemented the design end to end. This body
is long enough to clear the 200-byte SOFT_FINISH threshold on its own without
any help from filler text appended after it for no particular reason at all.
BODY
printf 'ok\n' > "${hdir}/architect.summary.md"
exit 0
EOF
chmod +x "${bindir}/claude"

mfile="${d}/mission.md"; printf 'test mission\n' > "${mfile}"

out="$(PATH="${bindir}:${PATH}" PROJECT_ROOT="${repo}" \
  bash "${SUB}" --role architect --model opus --task-id "dispatch-soft-finish-test" \
  --mission-file "${mfile}" --wait 2>&1)"
rc=$?

if [[ ${rc} -eq 0 ]]; then
  ok "SOFT_FINISH-eligible worker with .summary.md present exits 0 (not 1)"
else
  bad "expected exit 0 after SOFT_FINISH auto-promote, got rc=${rc} (out: ${out})"
fi

if printf '%s' "${out}" | grep -q '^LABEL='; then
  ok "success LABEL/SESSION_ID line printed on the SOFT_FINISH success path"
else
  bad "expected a LABEL=... SESSION_ID=... line on stdout (out: ${out})"
fi

if grep -q 'DELIVERABLE_COMPLETE' "${repo}/docs/handoff/dispatch-soft-finish-test/architect.full.md" 2>/dev/null; then
  ok "marker was actually appended to .full.md"
else
  bad "expected DELIVERABLE_COMPLETE appended to architect.full.md"
fi

rm -rf "${d}"

printf '[test-subsession-soft-finish-dead-return] pass=%s fail=%s\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
