#!/usr/bin/env bash
# leadv2-shebang-lint.sh — FROZEN-SHEBANG-IS-A-LATENT-CLASS-01.
#
# `#!/bin/bash` pins macOS's frozen system bash (3.2.57, GPLv2) instead of the
# modern bash on PATH (Homebrew, 5.3.9+) that `#!/usr/bin/env bash` picks up.
# A file executed BY PATH (no explicit `bash` prefix -- exactly how
# codex:codex-rescue invokes codex-task.sh) takes its interpreter from the
# shebang, so a stray `#!/bin/bash` is a LATENT class of failure: `bash -n`
# stays clean (that check uses whatever bash is on PATH), the file runs fine
# every time someone tests it with an explicit `bash file.sh`, and it only
# breaks the one way nobody tests -- direct execution -- and only once the
# file happens to use a bash-4+ construct somewhere upstream of wherever the
# error surfaces. codex-task.sh proved this exact shape on 2026-09-07: the
# reported error was 770 lines away from its cause and cost two sessions an
# hour of chasing the wrong file. This lint exists so the NEXT such file is
# caught at commit time, not discovered by an agent path silently failing.
#
# A guard hook (5 of the 22 files this caught were themselves guard hooks:
# leadv2-model-inherit-guard.sh, leadv2-no-opus-code-edit.sh,
# leadv2-workflow-model-guard.sh, plugin-scripts-drift-guard.sh,
# leadv2-opus-read-budget.sh) that silently degrades to "нарушений нет"
# because its OWN interpreter never started is our own false-green class one
# floor up -- catching this here is catching that too.
#
# Scope: plugins/leadv2/ EXCLUDING plugins/leadv2/codex-lead/ -- that
# subtree is a separate vendored/embedded thing (its own shims deliberately
# target plain /bin/bash), not a leadv2-authored script, and folding it in
# would either false-positive on intentional shims or require a second,
# uninspected exception list. 22 files were in scope at time of writing (all
# under hooks/, scripts/, scripts/tests/, not codex-lead/); this lint does
# not hardcode that count or list -- it re-derives it every run.
#
# Usage: leadv2-shebang-lint.sh [root-dir]   (default: plugins/leadv2 next to this script)
# Exit 0: clean. Exit 1: prints every offending path, one per line, to stderr.
set -uo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(cd "${_HERE}/.." && pwd)}"

if [[ ! -d "$ROOT" ]]; then
  echo "[leadv2-shebang-lint] no such directory: $ROOT" >&2
  exit 1
fi

# LINE 1 ONLY, never a whole-file grep: a `grep -rl '^#!/bin/bash$'` over the
# tree also matches the pattern wherever it appears INSIDE a file -- and it
# does, for real, in this repo: test-status-churn.sh writes throwaway fixture
# scripts via heredoc (`cat > "$COMPUTE_SH" <<'EOF' / #!/bin/bash / ...`) that
# have nothing to do with the test file's OWN interpreter. A whole-file match
# flagged that file as frozen even though its actual line 1 was already
# `#!/usr/bin/env bash` -- caught only by checking the byte-identical thing
# the kernel actually reads (line 1), not a substring anywhere in the file.
# A shebang carrying flags (`#!/bin/bash -e`, rare but real elsewhere in this
# codebase) is a DIFFERENT, not-yet-measured case and must not be silently
# swept into this lint's verdict -- false positives here are exactly how a
# guard stops being trusted.
HITS=()
while IFS= read -r -d '' _f; do
  IFS= read -r _first < "$_f" 2>/dev/null || continue
  [[ "$_first" == '#!/bin/bash' ]] && HITS+=("$_f")
done < <(find "$ROOT" -type f -name '*.sh' -not -path '*/codex-lead/*' -print0 2>/dev/null)
IFS=$'\n' HITS=($(sort <<<"${HITS[*]-}")); unset IFS

if [[ "${#HITS[@]}" -eq 0 ]]; then
  echo "[leadv2-shebang-lint] clean: no frozen #!/bin/bash shebang under $ROOT (codex-lead/ excluded)"
  exit 0
fi

echo "[leadv2-shebang-lint] FROZEN SHEBANG: ${#HITS[@]} file(s) pin macOS's system bash 3.2.57 instead of #!/usr/bin/env bash:" >&2
for _f in "${HITS[@]}"; do
  echo "  $_f" >&2
done
echo "[leadv2-shebang-lint] fix: change line 1 to '#!/usr/bin/env bash'. See FROZEN-SHEBANG-IS-A-LATENT-CLASS-01." >&2
exit 1
