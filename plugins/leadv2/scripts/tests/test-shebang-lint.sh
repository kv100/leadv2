#!/usr/bin/env bash
# run-all-triggers: leadv2-shebang-lint.sh leadv2-model-inherit-guard.sh leadv2-no-opus-code-edit.sh leadv2-workflow-model-guard.sh plugin-scripts-drift-guard.sh leadv2-opus-read-budget.sh
# test-shebang-lint.sh — FROZEN-SHEBANG-IS-A-LATENT-CLASS-01 acceptance.
#
# A lint checked only against "no violations found" proves nothing about
# whether it can find one -- this suite's negative control (case 2) is the
# whole point, not a formality: it puts a real `#!/bin/bash` back on a
# scratch copy of a real repo file and requires the lint to go red on it.
set -uo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="${_HERE}/../leadv2-shebang-lint.sh"
FAIL=0
ok()  { echo "  PASS: $1"; }
bad() { echo "  FAIL: $1"; FAIL=1; }

echo "== 1: real repo tree, post-normalization -- clean =="
if bash "$LINT" >/tmp/shebang-lint-1.out 2>&1; then
  ok "exits 0 on the real plugins/leadv2 tree"
else
  bad "expected rc=0, got $? ($(cat /tmp/shebang-lint-1.out))"
fi
grep -q "^\[leadv2-shebang-lint\] clean:" /tmp/shebang-lint-1.out \
  && ok "prints the clean line" || bad "missing the clean-line message"

echo "== 2: NEGATIVE CONTROL -- inject a frozen shebang into a scratch tree, must catch it =="
SBX="$(mktemp -d)"
trap 'rm -rf "$SBX"' EXIT
mkdir -p "$SBX/hooks" "$SBX/scripts/tests"
# A representative real file, copied (never the live repo file itself) so
# this control cannot leave the real tree dirty on failure.
cp "${_HERE}/../../hooks/leadv2-model-inherit-guard.sh" "$SBX/hooks/leadv2-model-inherit-guard.sh" 2>/dev/null \
  || cp "${_HERE}/test-status-churn.sh" "$SBX/scripts/tests/copy.sh"
# One clean file (env bash) alongside it, so a lint that just always fails
# would be caught by case 1 above, not hidden by this case alone.
printf '#!/usr/bin/env bash\necho clean\n' > "$SBX/scripts/tests/clean.sh"
# The injected violation.
printf '#!/bin/bash\necho frozen\n' > "$SBX/scripts/bad.sh"

if bash "$LINT" "$SBX" >/tmp/shebang-lint-2.out 2>&1; then
  bad "lint exited 0 with a frozen shebang present -- negative control failed"
else
  ok "exits non-zero with the injected violation present"
fi
grep -q "bad\.sh" /tmp/shebang-lint-2.out \
  && ok "names the offending file (bad.sh)" || bad "did not name bad.sh: $(cat /tmp/shebang-lint-2.out)"
grep -q "clean\.sh" /tmp/shebang-lint-2.out \
  && bad "false-flagged the clean file (clean.sh)" || ok "did not false-flag the clean file"

echo "== 3: codex-lead/ subtree is deliberately excluded (vendored shims) =="
mkdir -p "$SBX/codex-lead/shim"
printf '#!/bin/bash\necho shim\n' > "$SBX/codex-lead/shim/git"
if bash "$LINT" "$SBX" >/tmp/shebang-lint-3.out 2>&1; then
  bad "expected the pre-existing bad.sh violation to still fail this run"
fi
grep -q "codex-lead" /tmp/shebang-lint-3.out \
  && bad "codex-lead/ file leaked into the verdict" || ok "codex-lead/ correctly excluded"

echo "== 4: a line 45/55-style heredoc-embedded '#!/bin/bash' inside an OTHERWISE clean file must not false-positive (the real bug this suite caught during development) =="
rm -f "$SBX/scripts/bad.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf 'cat > "$TMP/fixture.sh" <<'"'"'EOF'"'"'\n'
  printf '#!/bin/bash\n'
  printf 'echo fixture\n'
  printf 'EOF\n'
} > "$SBX/scripts/tests/heredoc-fixture.sh"
if bash "$LINT" "$SBX" >/tmp/shebang-lint-4.out 2>&1; then
  ok "clean file with an embedded heredoc shebang does not trip the lint"
else
  bad "false-flagged heredoc-embedded content: $(cat /tmp/shebang-lint-4.out)"
fi

if [[ "$FAIL" == "1" ]]; then echo "[SHEBANG-LINT] FAILED"; exit 1; fi
echo "[SHEBANG-LINT] All checks passed"
