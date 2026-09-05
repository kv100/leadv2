#!/usr/bin/env bash
# 100 concurrent calls must yield unique portable temporary file paths.
# run-all-triggers: leadv2-temp
#
# SUITE-SELECTION-COVERS-140-OF-390-01: this suite carried no trigger
# marker and matched no name convention, so `run-all.sh --scope changed`
# never selected it — it could only ever run under `--scope all`. The
# triggers are the production files the suite's own body references most,
# with shared helpers excluded so a helper edit does not select everything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../leadv2-temp.sh"

ROOT="$(lv2_mktemp_dir temp-stress)"
trap 'rm -rf "$ROOT"' EXIT
export -f lv2_mktemp_file
export -f lv2_rmtemp_file

for _ in $(seq 1 100); do
  bash -c 'path="$(lv2_mktemp_file stress json)"; printf "%s\\n" "$path"; lv2_rmtemp_file "$path"' >> "${ROOT}/paths" &
done
wait

count="$(wc -l < "${ROOT}/paths" | tr -d ' ')"
unique="$(sort -u "${ROOT}/paths" | wc -l | tr -d ' ')"
[[ "$count" == "100" && "$unique" == "100" ]] || {
  printf '[TEMP-STRESS] FAIL: paths=%s unique=%s\n' "$count" "$unique" >&2
  exit 1
}
printf '[TEMP-STRESS] PASS: 100 invocations, 0 collisions\n'
