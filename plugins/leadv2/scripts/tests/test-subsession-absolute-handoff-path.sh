#!/usr/bin/env bash
# PREPASS-RC1-RACE-01 root cause — falsifying harness.
#
# claude-subsession.sh never `cd`s the exec'd `claude` process to $PROJECT_ROOT
# (grep confirms: every `cd` in the file is a subshelled path lookup, never
# applied to the script's own process). The old PER_TASK_BOILERPLATE told the
# agent to write its deliverable to the RELATIVE path
# "docs/handoff/${TASK_ID}/${ROLE}.full.md" -- which resolves against whatever
# cwd the CALLER happened to be in at exec time, not $PROJECT_ROOT.
#
# Live-relevant shape: leadv2-dispatch-code.sh's architect_prepass spawns
# claude-subsession.sh via a bare `python3 subprocess.Popen` with no cwd= set
# (inherits the grandparent's cwd verbatim) -- reproduced here by invoking
# claude-subsession.sh from a DIFFERENT cwd than $PROJECT_ROOT, exactly the
# shape a caller running from an unrelated directory (or one level removed via
# a subprocess with no explicit cwd) produces.
#
# Before the fix: the fake `claude` stub (which honors the prompt's own
# "Deliverable full: <path>" line, matching how a real agent reads its
# instructions) writes under the CALLER's cwd, not $PROJECT_ROOT -- so
# claude-subsession.sh's own completion check (which always reads the
# ABSOLUTE $HANDOFF_DIR = $PROJECT_ROOT/docs/handoff/$TASK_ID) finds nothing
# and declares the worker failed (rc=1) even though a complete deliverable
# exists on disk, just at the wrong path.

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUB="${SCRIPT_DIR}/claude-subsession.sh"
PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

d="$(mktemp -d)"
repo="${d}/repo"
elsewhere="${d}/elsewhere"
mkdir -p "${repo}/.claude/agents" "${elsewhere}"
( cd "${repo}" && git init -q )
printf 'role: architect\n' > "${repo}/.claude/agents/architect.md"

# Fake `claude` CLI: writes DELIVERABLE_COMPLETE to whatever path the prompt's
# "Deliverable full:" line names -- this is the one honest source of truth a
# real agent has for where to write, since no --task-id/--cwd flag is ever
# passed to the `claude` binary (PER_TASK_BOILERPLATE embeds the path in text).
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
summary="$(printf '%s\n' "${prompt}" | sed -n 's/^- Deliverable summary: *\(.*\.summary\.md\).*/\1/p' | head -1)"
mkdir -p "$(dirname "${full}")"
printf 'design complete\nDELIVERABLE_COMPLETE\n' > "${full}"
printf 'ok\n' > "${summary}"
exit 0
EOF
chmod +x "${bindir}/claude"

mfile="${d}/mission.md"; printf 'test mission\n' > "${mfile}"

# Invoked from a cwd that is NOT $PROJECT_ROOT -- the architect-prepass shape.
out="$(cd "${elsewhere}" && PATH="${bindir}:${PATH}" PROJECT_ROOT="${repo}" \
  bash "${SUB}" --role architect --model opus --task-id "dispatch-abs-path-test" \
  --mission-file "${mfile}" --wait 2>&1)"
rc=$?

if [[ ${rc} -eq 0 ]]; then
  ok "worker invoked from a foreign cwd still exits 0 (deliverable found at PROJECT_ROOT)"
else
  bad "expected exit 0, got rc=${rc} (out: ${out})"
fi

if [[ -f "${repo}/docs/handoff/dispatch-abs-path-test/architect.full.md" ]]; then
  ok "deliverable landed under PROJECT_ROOT/docs/handoff/<task-id>/, not the caller's cwd"
else
  bad "expected ${repo}/docs/handoff/dispatch-abs-path-test/architect.full.md to exist"
fi

if [[ -e "${elsewhere}/docs" ]]; then
  bad "deliverable leaked into the caller's foreign cwd (${elsewhere}/docs exists)"
else
  ok "no stray docs/ directory created under the caller's foreign cwd"
fi

rm -rf "${d}"

printf '[test-subsession-absolute-handoff-path] pass=%s fail=%s\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
