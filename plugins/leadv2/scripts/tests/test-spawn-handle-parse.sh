#!/usr/bin/env bash
# changed-scope triggers, self-registered (discovered by scan_suite_triggers):
# run-all-triggers: kimi-coder.sh leadv2-dispatch-code.sh
# tests/test-spawn-handle-parse.sh — DISPATCH-HANDLE-SLICE-UNATTRIBUTED-01.
#
# The kimi arm of leadv2-dispatch-code.sh recovered a worker handle by taking
# the FIRST HALF of the launcher's last line by character count, on the stated
# assumption that kimi-coder.sh prints "$RUNS/$handle$handle". It does not:
# cmd_bg ends with a bare `echo "${run_id}"` -- one copy, no path prefix. The
# identical halving on the glm arm was removed under GLM-ARM-THROUGHPUT-01
# after it truncated every handle into a string `status` could never resolve,
# so that arm never launched a worker at all. This suite pins both halves of
# the contract so the assumption cannot be reintroduced silently:
#
#   LAUNCHER: kimi-coder.sh bg prints ONE non-empty line, no '/', not doubled,
#             and `status <that line>` is true immediately afterwards.
#   PARSER:   the production assignment line in leadv2-dispatch-code.sh's kimi
#             arm is EXTRACTED FROM THE SOURCE at run time and executed here,
#             so this suite tests the shipped text, not a copy of it. It must
#             return the launcher's line unchanged, and must never return a
#             half of any input.
#
# Not covered, and named rather than implied: a full dispatch through the real
# arbiter onto the kimi arm. In a hermetic fixture the arbiter resolves to
# freepool and then sonnet (measured 2026-09-06), so steering it onto kimi
# would take a routing fixture this suite does not have. The round-trip refusal
# that protects a bad handle downstream (`status` -> spawn_failed not_live)
# lives in the same case block and is exercised by test-glm-flash-handle.sh on
# the sibling arm.
#
# DECLARED NEGATIVE CONTROL (applied INSIDE the production case body, in a
# scratch copy of the dispatcher, and run below): reinstate the halving
#   handle="${_kimi_temp:0:_kimi_half}"
# => cases (c) and (d) go RED. Case (a)/(b), the launcher contract, stay green:
# the launcher is not what this mutation touches.
#
# Hermetic: KIMI_RUNS_DIR in a temp dir, a stub `claude` that exits at once,
# stub secrets. No network, no shared state.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="$(cd "${PLUGIN_SCRIPTS}/.." && pwd)"
KIMI_SCRIPT="${KIMI_HANDLE_SUITE_LAUNCHER:-${PLUGIN_SCRIPTS}/kimi-coder.sh}"
DISPATCH_SRC="${KIMI_HANDLE_SUITE_DISPATCH:-${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh}"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/spawn-handle-parse.XXXXXX")" || exit 2
cleanup() {
  local f pid
  for f in "${FIXTURE}"/kimi-runs/.lock-*/pgid "${FIXTURE}"/kimi-runs/.lock-*/pid; do
    [[ -f "${f}" ]] || continue
    pid="$(cat "${f}" 2>/dev/null || true)"
    [[ -n "${pid}" ]] && { kill -TERM -"${pid}" 2>/dev/null; kill -TERM "${pid}" 2>/dev/null; }
  done
  sleep 1
  rm -rf "${FIXTURE}"
}
trap cleanup EXIT INT TERM

# ── floors: a suite whose tools are missing must go red, never skip ─────────
for f in "scripts/kimi-coder.sh" "scripts/leadv2-dispatch-code.sh"; do
  if bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null && /bin/bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null; then
    pass "bash -n ${f} (incl. 3.2)"
  else
    fail "bash -n ${f}"
  fi
done
if python3 -c 'pass' >/dev/null 2>&1; then pass "dep floor: python3"; else fail "dep floor: python3 missing"; fi
if [[ ${FAIL} -ne 0 ]]; then
  printf -- '[TEST] test-spawn-handle-parse: %d passed, %d failed\n' "${PASS}" "${FAIL}"
  exit 1
fi

# ── fixture ─────────────────────────────────────────────────────────────────
REPO="${FIXTURE}/repo"; mkdir -p "${REPO}"
git -C "${REPO}" init -q 2>/dev/null || true
git -C "${REPO}" -c user.email=h@test -c user.name=h commit -q --allow-empty -m init 2>/dev/null || true

mkdir -p "${FIXTURE}/bin"
cat > "${FIXTURE}/bin/claude" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' '{"type":"system","subtype":"init","model":"stub"}'
exit 0
STUBEOF
chmod +x "${FIXTURE}/bin/claude"
printf 'TOKENROUTER_AUTH_TOKEN=stub-token\n' > "${FIXTURE}/secrets"; chmod 600 "${FIXTURE}/secrets"

export KIMI_CLAUDE_BIN="${FIXTURE}/bin/claude"
export KIMI_SECRETS_FILE="${FIXTURE}/secrets"
export KIMI_RUNS_DIR="${FIXTURE}/kimi-runs"
export KIMI_TIMEOUT=15
# kimi_launch_probe() hits api.tokenrouter.com live and fails closed (rc 77)
# on a stub token; this is its documented test seam (kimi-coder.sh:218).
export KIMI_SKIP_LAUNCH_PROBE=1
export TMPDIR="${FIXTURE}"
export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"

# ── (a) LAUNCHER CONTRACT: one line, non-empty, no slash ────────────────────
raw_out="$(bash "${KIMI_SCRIPT}" bg "handle contract probe" --cwd "${REPO}" 2>/dev/null)" || raw_out=""
launcher_line="$(printf '%s' "${raw_out}" | tail -1)"
if [[ -n "${launcher_line}" && "${launcher_line}" != */* ]]; then
  pass "(a) launcher prints a non-empty handle with no path prefix (${launcher_line})"
else
  fail "(a) launcher line is empty or path-shaped: [${launcher_line}]"
fi

# ── (b) the doubled assumption is FALSE ────────────────────────────────────
_is_doubled() { # <s> -> 0 when s == x+x
  local s="$1" n h
  n=${#s}; (( n % 2 == 0 )) || return 1
  h=$(( n / 2 ))
  [[ "${s:0:h}" == "${s:h}" ]]
}
if [[ -z "${launcher_line}" ]]; then
  fail "(b) not run: the launcher printed nothing, so nothing can be checked for doubling"
elif _is_doubled "${launcher_line}"; then
  fail "(b) the launcher line IS doubled — the old parser's assumption would hold and this suite's premise is wrong"
else
  pass "(b) the launcher line is a single copy, not handle+handle (the halving assumption was false)"
fi

# ── extract the PRODUCTION parse line from the shipped source ───────────────
# Not a copy of the logic: the kimi case block is read out of the dispatcher
# and its `handle=` assignment executed here, so a future edit to that line is
# what these cases judge.
PARSE_SNIPPET="${FIXTURE}/parse.sh"
python3 - "${DISPATCH_SRC}" "${PARSE_SNIPPET}" <<'PY'
import io, re, sys
src = io.open(sys.argv[1], encoding='utf-8').read()
i = src.index('\n    kimi)')
j = src.index('\n      if [[ -z "${handle}" ]]; then', i)
block = src[i:j]
lines = [l for l in block.splitlines()
         if re.match(r'\s*(local\s+_kimi|handle=)', l)]
if not lines:
    sys.exit('no handle assignment found in the kimi case block')
io.open(sys.argv[2], 'w', encoding='utf-8').write(
    '_parse_handle() {\n  local out="$1" handle=""\n'
    + '\n'.join(lines) + '\n  printf %s "$handle"\n}\n')
PY
if [[ -s "${PARSE_SNIPPET}" ]]; then
  pass "extracted the production handle assignment from the kimi case block"
else
  fail "could not extract the production handle assignment — later cases cannot judge the shipped code"
  printf -- '[TEST] test-spawn-handle-parse: %d passed, %d failed\n' "${PASS}" "${FAIL}"
  exit 1
fi
# shellcheck disable=SC1090
. "${PARSE_SNIPPET}"

# ── (c) the launcher's real line survives the production parser ─────────────
parsed="$(_parse_handle "${launcher_line}"$'\n')"
if [[ -n "${launcher_line}" && "${parsed}" == "${launcher_line}" ]]; then
  pass "(c) the production parser returns the launcher's handle unchanged"
else
  fail "(c) parser mangled the handle: launcher=[${launcher_line}] parsed=[${parsed}]"
fi
if [[ -z "${parsed}" ]]; then
  fail "(c2) not run: parsed handle empty, so status would fall back to the latest run"
elif bash "${KIMI_SCRIPT}" status "${parsed}" >/dev/null 2>&1; then
  pass "(c2) status resolves the parsed handle — it names a real run"
else
  fail "(c2) status could not resolve [${parsed}] — the handle does not round-trip"
fi

# ── (d) synthetic shapes: never a silent half ──────────────────────────────
for probe in "260906-101112-repo-abcd" "odd-length-handle-123" "dup-dup"; do
  got="$(_parse_handle "${probe}"$'\n')"
  if [[ "${got}" == "${probe}" ]]; then
    pass "(d) [${probe}] passes through whole"
  else
    fail "(d) [${probe}] came back as [${got}] — a truncation, silently"
  fi
done

# ── (e) NEGATIVE CONTROL: reinstate the halving inside the production case ──
MUT="${FIXTURE}/dispatch.mutated.sh"
cp "${DISPATCH_SRC}" "${MUT}"
python3 - "${MUT}" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding='utf-8').read()
i = s.index('\n    kimi)')
j = s.index('\n      if [[ -z "${handle}" ]]; then', i)
block = s[i:j]
needle = '      handle="${out%$\'\\n\'}"\n'
assert needle in block, 'kimi handle assignment not found -- fixture drifted from source'
mutated = block.replace(needle,
    '      local _kimi_out="${out%$\'\\n\'}"\n'
    '      local _kimi_temp="${_kimi_out##*/}"\n'
    '      local _kimi_len=${#_kimi_temp}\n'
    '      local _kimi_half=$((_kimi_len / 2))\n'
    '      handle="${_kimi_temp:0:_kimi_half}"\n', 1)
io.open(p, 'w', encoding='utf-8').write(s[:i] + mutated + s[j:])
print('mutation applied')
PY
mut_rc=$?
MUT_SNIPPET="${FIXTURE}/parse-mutated.sh"
python3 - "${MUT}" "${MUT_SNIPPET}" <<'PY'
import io, re, sys
src = io.open(sys.argv[1], encoding='utf-8').read()
i = src.index('\n    kimi)')
j = src.index('\n      if [[ -z "${handle}" ]]; then', i)
lines = [l for l in src[i:j].splitlines()
         if re.match(r'\s*(local\s+_kimi|handle=)', l)]
io.open(sys.argv[2], 'w', encoding='utf-8').write(
    '_parse_handle_mut() {\n  local out="$1" handle=""\n'
    + '\n'.join(lines) + '\n  printf %s "$handle"\n}\n')
PY
# The control must verify the mutation was applied BY THIS RUN. Checking only
# that _kimi_half is present passes when the source was ALREADY halving --
# i.e. exactly when this suite is pointed at a mutated dispatcher, where the
# needle is absent and the python above dies. That reads as a green control
# over an unapplied mutation, which is the disease this file exists to kill.
if [[ ${mut_rc} -ne 0 ]]; then
  fail "(e) NEG-CTL invalid: mutation not applied (needle absent -- is the source already halving?)"
elif ! grep -Fq '_kimi_half' "${MUT}"; then
  fail "(e) NEG-CTL invalid: the mutation did not land in the scratch dispatcher"
else
  # shellcheck disable=SC1090
  . "${MUT_SNIPPET}"
  mut_got="$(_parse_handle_mut "260906-101112-repo-abcd"$'\n')"
  if [[ "${mut_got}" != "260906-101112-repo-abcd" ]]; then
    pass "(e) NEG-CTL: with the halving back, the parser truncates to [${mut_got}] — cases (c)/(d) would go RED"
  else
    fail "(e) NEG-CTL: the halving mutation changed nothing — these cases do not actually test the parser"
  fi
fi

printf -- '[TEST] test-spawn-handle-parse: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
