#!/usr/bin/env bash
# DISPATCH-CLOSE-GATE-01: prevent a new single-file consumer startup crash.
#
# The census has pre-existing out-of-lane entries recorded in the handoff.  They are an
# explicit, reviewed baseline because this lane may not edit them.  Every other lib source
# must be preceded by a local-or-canonical fallback and a file guard.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
BASELINE="${ROOT}/docs/handoff/DISPATCH-CLOSE-GATE-01/unguarded-sources.md"
PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

scan_unguarded() { # <root> -> file:line; a source without a canonical fallback in prior 4 lines
  python3 - "$1" <<'PY'
import os, re, sys
root = sys.argv[1]
source = re.compile(r'(?:^|&&|\|\|)\s*(?:source|\.)\s+(.+)$')
for base in ('plugins/leadv2/scripts', 'plugins/leadv2/hooks'):
    directory = os.path.join(root, base)
    for walk, _, files in os.walk(directory):
        for name in sorted(files):
            if not name.endswith('.sh'):
                continue
            path = os.path.join(walk, name)
            rel = os.path.relpath(path, root)
            text = open(path, encoding='utf-8').read()
            lines = text.splitlines()
            # A test file always runs from a full checkout (never symlinked standalone
            # into a consumer repo), so its own sourcing of the module under test is not
            # a single-file-symlink concern -- only the old lib/-literal heuristic applies
            # there. A PRODUCTION/hook file that already speaks LEADV2_CANONICAL_ROOT
            # somewhere has opted into the symlink-safe idiom, so every sibling-script
            # source in it must follow the same discipline, not just the ones whose
            # argument happens to contain "lib/". DISPATCH-CLOSE-GATE-01 round 6: the
            # prior `/lib/`-literal heuristic missed leadv2-lane-child-suffixes.sh and
            # leadv2-portable-lock.sh, which sit directly under scripts/, not lib/.
            is_test_file = '/tests/' in ('/' + rel)
            file_is_canonical_aware = (not is_test_file) and 'LEADV2_CANONICAL_ROOT' in text
            for index, line in enumerate(lines):
                match = source.search(line)
                if not match:
                    continue
                context = '\n'.join(lines[max(0, index - 4):index + 1])
                argument = match.group(1)
                is_lib = '/lib/' in argument or '.lib/' in argument
                variable = re.search(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)', argument)
                if variable and re.search(r'^\s*%s=.*(?:/|\.)lib/' % re.escape(variable.group(1)), context, re.M):
                    is_lib = True
                is_script = is_lib
                if file_is_canonical_aware and not is_script:
                    is_script = bool(re.search(r'\.sh\b', argument))
                    if variable and re.search(r'^\s*%s=.*\.sh"?\s*$' % re.escape(variable.group(1)), context, re.M):
                        is_script = True
                if not is_script:
                    continue
                if 'LEADV2_CANONICAL_ROOT' not in context:
                    print('%s:%d' % (rel, index + 1))
PY
}

current="$(scan_unguarded "${ROOT}")"
documented="$(sed -n 's/^- \(`\)\{0,1\}\([^` ]*:[0-9][0-9]*\)\(`\)\{0,1\}.*/\2/p' "${BASELINE}")"
unexpected="$(comm -23 <(printf '%s\n' "${current}" | sed '/^$/d' | sort) <(printf '%s\n' "${documented}" | sed '/^$/d' | sort))"
[[ -z "${unexpected}" ]] \
  && pass "census: no new unguarded lib source outside the recorded out-of-lane baseline" \
  || fail "census: unguarded lib source lacks canonical fallback: ${unexpected}"

# A local fixture proves the scanner itself is live: removing the canonical fallback from a
# guarded source produces a finding.  The required production mutation is run separately
# against leadv2-dispatch-code.sh and recorded in the handoff RED artifact.
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/lib-source-guarded.XXXXXX")"
trap 'rm -rf "${FIXTURE}"' EXIT
mkdir -p "${FIXTURE}/plugins/leadv2/scripts/lib"
cat > "${FIXTURE}/plugins/leadv2/scripts/probe.sh" <<'EOF'
_PROBE_SH="${SCRIPT_DIR}/lib/probe.sh"
[[ -f "${_PROBE_SH}" ]] || _PROBE_SH="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/probe.sh"
source "${_PROBE_SH}"
EOF
fixture_green="$(scan_unguarded "${FIXTURE}")"
if [[ -n "${fixture_green}" ]]; then
  fail "scanner: guarded fixture was incorrectly reported: ${fixture_green}"
else
  sed -i.bak '/LEADV2_CANONICAL_ROOT/d' "${FIXTURE}/plugins/leadv2/scripts/probe.sh"
  fixture_red="$(scan_unguarded "${FIXTURE}")"
  [[ "${fixture_red}" == "plugins/leadv2/scripts/probe.sh:2" ]] \
    && pass "control: removed canonical fallback is detected (would be red)" \
    || fail "control: removed fallback was not detected: ${fixture_red}"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
