#!/usr/bin/env bash
# Mutation: return 1 as the first statement of lv2_lane_containment_violation.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; LIB="${DIR}/../lib/leadv2-lane-guard.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
git init -q "$T/main"; git -C "$T/main" config user.email t@e; git -C "$T/main" config user.name t
touch "$T/main/seed"; git -C "$T/main" add seed; git -C "$T/main" commit -qm seed
mkdir -p "$T/main/docs/handoff/dispatch-abc" "$T/lane"; : > "$T/main/docs/handoff/dispatch-abc/main-dirt.base"
printf x > "$T/main/escape"
source "$LIB"
lv2_lane_containment_violation abc "$T/lane" "$T/main"
M="$T/mut.sh"
python3 - "$LIB" "$M" <<'PY'
import sys
s = open(sys.argv[1]).read()
needle = 'lv2_lane_containment_violation() { # <sig8> <work-root> <project-root>\n'
open(sys.argv[2], 'w').write(s.replace(needle, needle + '  return 1\n', 1))
PY
source "$M"
if lv2_lane_containment_violation abc "$T/lane" "$T/main"; then echo 'mutation survived' >&2; exit 1; fi
echo 'PASS: containment detects non-excluded main dirt; mutation red'
